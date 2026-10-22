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
// class fixed makes a known index's shape inline, and a static hold makes
// counting count nothing of what the parameter holds.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "Calls.h"

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
  // impossible goes with it.
  FailureOr<SmallVector<families::Sort>> kept = families::substituteFunction(clone, key->indices);
  if (failed(kept))
    return failure();
  clone.setBindersAttr(IndexBindersAttr::get(clone.getContext(), *kept));
  // Then each parameter the key gives another type: a static hold, which
  // the grades derived from it follow.
  Block &entry = clone.getBody().front();
  for (auto [arg, type] : llvm::zip_equal(entry.getArguments(), key->signature.getInputs()))
    arg.setType(type);
  clone.setFunctionType(key->signature);
  return grades::follow(clone);
}

} // namespace idr::specialize
