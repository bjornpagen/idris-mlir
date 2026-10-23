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
// carries into its body, and a static hold makes counting count nothing of
// what the parameter holds. A result the key opens is given open by every
// tail of the copy: what the copy builds where its index is known it still
// builds in place, and casts at the end of each tail.

#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

Type openResult(Type type, Type held) {
  DataType data = dataTypeOf(type);
  if (!data)
    return type;
  return graded(gradeOf(held), data.marked(LayoutMark::Open));
}

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

namespace {

// `fn` returning `results`, which differ from its own results only where the
// key opens one: every tail of it gives that result at the open layout.
// Down its tails from the body, a region op a break crosses whose results a
// block gives on takes the open type at that result, as does each op after
// it that only gives one on; a block that ends a tail otherwise casts what
// it gives there to the open type before its terminator, the copy's one
// re-pack of it. So what the copy gives at a tail it gives in its own block
// at the open type, and a call there is a tail lost to a layout, which the
// copy's own turn asks its callee open for. A block whose end never returns
// gives nothing to cast.
void openTails(FuncOp fn, ArrayRef<Type> results) {
  SmallVector<unsigned> opened;
  for (auto [position, types] : llvm::enumerate(llvm::zip_equal(fn.getResultTypes(), results)))
    if (std::get<0>(types) != std::get<1>(types))
      opened.push_back(static_cast<unsigned>(position));
  if (opened.empty())
    return;
  fn.setFunctionType(FunctionType::get(fn.getContext(), fn.getArgumentTypes(), results));
  Block &body = fn.getBody().front();
  if (!body.getTerminator()->hasTrait<OpTrait::ReturnLike>())
    return;
  SmallVector<Block *> spine{&body};
  while (!spine.empty()) {
    Block *block = spine.pop_back_val();
    Operation *terminator = block->getTerminator();
    Operation *source = tail::tailSource(*block);
    if (source && source->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      // The ops after it give its results on, each in its place, to the
      // terminator, which forwards them in order: the one definition found
      // the way so.
      SmallVector<Value> values(source->getResults());
      for (unsigned position : opened)
        source->getResult(position).setType(results[position]);
      for (Operation *op = source->getNextNode(); op != terminator; op = op->getNextNode()) {
        auto *at = llvm::find(values, op->getOperand(0));
        auto position = static_cast<unsigned>(std::distance(values.begin(), at));
        *at = op->getResult(0);
        if (llvm::is_contained(opened, position))
          op->getResult(0).setType(results[position]);
      }
      for (Region &region : source->getRegions())
        if (!region.empty() && tail::rejoinOf(region.front().getTerminator()) == source)
          spine.push_back(&region.front());
      continue;
    }
    OpBuilder b(terminator);
    for (unsigned position : opened) {
      Value given = terminator->getOperand(position);
      terminator->setOperand(
          position,
          DataReindexOp::create(b, terminator->getLoc(), results[position], given).getResult());
    }
    // A tail call the block ended with now reaches the return through the
    // cast, a tail lost to a layout, which the decider leaves no tail call
    // until the copy's own turn asks its callee open: its fact is the one
    // definition's answer at every step.
    if (CallOp call = source ? tailCallOf(source) : CallOp())
      call.setTailKind(tail::decide(call));
  }
}

} // namespace

LogicalResult Signatures::edit(Key key, FuncOp clone) {
  // Each parameter at the hold the key gives it first (a static hold where
  // the caller passes static data), on the owner's own type: the key's
  // signature is already substituted, and a hold names no index variable,
  // so it is read off the key position by position.
  Block &entry = clone.getBody().front();
  SmallVector<Type> inputs;
  for (auto [arg, keyed] : llvm::zip_equal(entry.getArguments(), key->signature.getInputs())) {
    if (std::optional<Hold> hold = holdOf(keyed))
      arg.setType(atHold(arg.getType(), *hold));
    inputs.push_back(arg.getType());
  }
  clone.setFunctionType(FunctionType::get(clone.getContext(), inputs, clone.getResultTypes()));
  // Then the index arguments, through the one substitution every pass that
  // instantiates a function shares: each case a known index makes
  // impossible goes with it, each bare tensor argument's axis whose term
  // becomes a constant is made static, and its one walk in program order
  // infers each result type again wherever an operand's type changed, so
  // the holds just set reach every value derived from the parameters.
  FailureOr<SmallVector<families::Sort>> kept = families::substituteFunction(clone, key->indices);
  if (failed(kept))
    return failure();
  clone.setBindersAttr(IndexBindersAttr::get(clone.getContext(), *kept));
  // Each result the key opens, given open by every tail.
  openTails(clone, key->signature.getResults());
  // The call's view of the copy, read off the same mapping before the copy
  // was built and opened where the key opens a result, is the copy's type.
  assert(clone.getFunctionType() == key->signature &&
         "a signature copy's type differs from the type its callers were given");
  return success();
}

} // namespace idr::specialize
