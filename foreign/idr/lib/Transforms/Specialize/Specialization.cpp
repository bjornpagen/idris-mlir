// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The two alphabets' copies.
//
// A pattern copy is its owner's body with the static parts of the key
// substituted for its parameters, whose new parameters are the key's
// holes, parameter i holding the i-th hole in pre-order. Each op it adds
// takes the location of the parameter it replaces, and a new parameter
// the function's, unless it is the whole parameter.
//
// A signature copy is its owner's body under the key's index arguments,
// substituted, with each parameter at the type the key gives it: a layout
// class fixed makes a known index's shape inline, an axis of a bare tensor
// argument whose index term becomes a constant is static in the copy's
// signature, which its caller casts its operand to and the substitution
// carries into its body, and a parameter's hold is the one its caller
// passes, static data that counting then counts nothing of, or a claim its
// caller's re-grading lowered, which re-grades the copy's body in turn. A
// result the key opens is given open by every tail of the copy: what the
// copy builds where its index is known it still builds in place, and casts
// at the end of each tail, at the grade the cast gives, shared down to the
// grade the key asks where it claims less. A result the key gives at a
// lowered parameter's hold, since that parameter may reach it, is given at
// it by every tail the same way.

#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

namespace {

// A pattern's canonical bytes, in pre-order: its kind, a constructor's tag
// and arity, a constant's content. Positions fix every type, so no type is
// written.
void writePattern(const Pattern *pattern, Bytes &bytes) {
  SmallVector<const Pattern *> work{pattern};
  while (!work.empty()) {
    const Pattern *at = work.pop_back_val();
    idr::match(
        at->get(), [&](Hole) { bytes.word(0); },
        [&](const Con &con) {
          bytes.word(1);
          bytes.word(static_cast<unsigned>(con.tag));
          bytes.word(con.fields.size());
          for (const Pattern *field : llvm::reverse(con.fields))
            work.push_back(field);
        },
        [&](const Const &constant) {
          bytes.word(2);
          bytes.attribute(constant.value);
        });
  }
}

} // namespace

void Patterns::write(Key key, Bytes &bytes) {
  for (const Pattern *param : key->params)
    writePattern(param, bytes);
}

LogicalResult Patterns::edit(Key key, FuncOp clone) {
  unsigned arity = clone.getNumArguments();
  SmallVector<unsigned> positions;
  SmallVector<Type> types;
  SmallVector<Location> locs;
  for (auto [p, pattern] : llvm::enumerate(key->params)) {
    BlockArgument param = clone.getArgument(static_cast<unsigned>(p));
    size_t before = types.size();
    detail::holeTypes(*pattern, param.getType(), types);
    // A hole that is the whole parameter is that binder, and keeps its
    // location; a hole inside a pattern is the pass's binder, at the
    // function's location, which no binder of Idris's has.
    Location at = pattern->hasStructure() ? clone.getLoc() : param.getLoc();
    for (size_t hole = before; hole < types.size(); ++hole) {
      positions.push_back(arity);
      locs.push_back(at);
    }
  }
  SmallVector<DictionaryAttr> attrs(positions.size(), DictionaryAttr());
  (void)clone.insertArguments(positions, types, attrs, locs);

  Block &entry = clone.getBody().front();
  SmallVector<Value> holes(entry.getArguments().drop_front(arity));
  OpBuilder b = OpBuilder::atBlockBegin(&entry);
  unsigned next = 0;
  for (auto [p, pattern] : llvm::enumerate(key->params)) {
    BlockArgument param = entry.getArgument(static_cast<unsigned>(p));
    param.replaceAllUsesWith(
        detail::rebuild(b, param.getLoc(), *pattern, param.getType(), holes, next));
  }
  llvm::BitVector originals(clone.getNumArguments());
  originals.set(0, arity);
  return clone.eraseArguments(originals);
}

void Signatures::write(Key key, Bytes &bytes) {
  bytes.type(key->signature);
  bytes.attribute(key->indices);
}

LogicalResult Signatures::edit(Key key, FuncOp clone) {
  // The index arguments first, through the one substitution every pass
  // that instantiates a function shares: each case a known index makes
  // impossible goes with it, each bare tensor argument's axis whose term
  // becomes a constant is made static, and its one walk in program order
  // infers each result type again wherever an operand's type changed.
  FailureOr<SmallVector<families::Sort>> kept = families::substituteFunction(clone, key->indices);
  if (failed(kept))
    return failure();
  clone.setBindersAttr(IndexBindersAttr::get(clone.getContext(), *kept));
  // Then each parameter at the hold the key gives it where its own
  // differs, the one its caller passes: the key's signature is already
  // substituted, and a hold names no index variable, so it is read off the
  // key position by position. What carries such a parameter on is
  // re-graded with it, the walk a caller of a result opened at a weaker
  // hold takes (regrade): a value a branch forwards, a cast, an inferred
  // result and a value built of it alike.
  Block &entry = clone.getBody().front();
  SmallVector<Type> inputs(clone.getArgumentTypes());
  SmallVector<Value> regraded;
  for (auto [index, keyed] : llvm::enumerate(key->signature.getInputs())) {
    if (inputs[index] == keyed)
      continue;
    std::optional<Hold> hold = holdOf(keyed);
    assert(hold && atHold(inputs[index], *hold) == keyed &&
           "a copy's parameter differs from its owner's, substituted, only by the hold its key "
           "gives it");
    inputs[index] = keyed;
    BlockArgument arg = entry.getArgument(static_cast<unsigned>(index));
    arg.setType(keyed);
    regraded.push_back(arg);
  }
  clone.setFunctionType(FunctionType::get(clone.getContext(), inputs, clone.getResultTypes()));
  // Each call the walk stops at, an operand of which it lowered, takes the
  // results its callee's copy will give when this copy is taken up
  // (openResults), as every caller's calls do.
  (void)regrade(clone, regraded);
  // The key's results are what its callers read before the copy was built:
  // a result a lowered parameter may reach on some path is keyed at no more
  // than that parameter's hold, or, by a part, that hold claiming nothing
  // (keyGivenBack), so a parameter's weaker claim reaches the return no
  // further than the key says. A result the key keeps at its layout is
  // checked here; one it opens is given by a re-pack at the hold the key
  // asks, which giveAs checks.
  assert([&] {
    Operation *end = entry.getTerminator();
    if (!end->hasTrait<OpTrait::ReturnLike>())
      return true;
    return llvm::all_of(
        llvm::zip_equal(end->getOperandTypes(), clone.getResultTypes(),
                        key->signature.getResults()),
        [](auto each) {
          auto [given, own, keyed] = each;
          return unrestricted(own) != unrestricted(keyed) || holdFits(given, keyed);
        });
  }() && "a copy keyed at the hold its caller passes gives no less at its result than its key "
         "says");
  // Each result the key opens, or keys to a lowered parameter it gives
  // back, given so by every tail.
  openTails(clone, key->signature.getResults());
  // The call's view of the copy, read off the same mapping before the copy
  // was built and opened where the key opens a result, is the copy's type.
  assert(clone.getFunctionType() == key->signature &&
         "a signature copy's type differs from the type its callers were given");
  return success();
}

} // namespace idr::specialize
