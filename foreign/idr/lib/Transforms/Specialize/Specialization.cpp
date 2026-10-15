// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A specialization node's function: its owner's final body with the static
// parts of the key substituted for its parameters, whose new parameters
// are the key's holes, parameter i holding hole i.
//
// It is built from the key and the owner alone, never from a call that
// asked for it, so every schedule builds the same function: each op it
// adds takes the location of the parameter it replaces. A call of the
// owner in it with the node's own key, a fixed parameter passed on
// unchanged, becomes the node's own call when its first turn redirects it.
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Builders.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize::detail {

FailureOr<idr::FuncOp> buildSpec(idr::FuncOp from, SpecKeyAttr key, StringAttr name) {
  ArrayAttr patterns = key.getPatterns();
  unsigned arity = from.getNumArguments();
  if (patterns.size() != arity)
    return from.emitError() << "internal error: a specialization key of @" << from.getSymName()
                            << " has " << patterns.size() << " patterns for " << arity
                            << " parameters";

  // The copy keeps the owner's location, instance and the facts Idris gave
  // it; what it may do is written once its component is final.
  auto clone = cast<idr::FuncOp>(from->clone());
  clone.setSymName(name.getValue());
  clone.removeEffectsAttr();

  SmallVector<unsigned> positions;
  SmallVector<Type> types;
  SmallVector<Location> locs;
  for (auto [p, pattern] : llvm::enumerate(patterns)) {
    BlockArgument param = clone.getArgument(static_cast<unsigned>(p));
    unsigned before = static_cast<unsigned>(types.size());
    holeTypes(pattern, param.getType(), types);
    for (unsigned hole = before; hole < types.size(); ++hole) {
      positions.push_back(arity);
      locs.push_back(param.getLoc());
    }
  }
  SmallVector<DictionaryAttr> attrs(positions.size(), DictionaryAttr());
  (void)clone.insertArguments(positions, types, attrs, locs);

  Block &entry = clone.getBody().front();
  SmallVector<Value> holes(entry.getArguments().drop_front(arity));
  OpBuilder b = OpBuilder::atBlockBegin(&entry);
  for (auto [p, pattern] : llvm::enumerate(patterns)) {
    BlockArgument param = entry.getArgument(static_cast<unsigned>(p));
    param.replaceAllUsesWith(rebuild(b, param.getLoc(), pattern, param.getType(), holes));
  }
  llvm::BitVector originals(clone.getNumArguments());
  originals.set(0, arity);
  (void)clone.eraseArguments(originals);
  return clone;
}

} // namespace idr::specialize::detail
