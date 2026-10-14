// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Specialization: a call is redirected to a clone of its callee in which
// the static parts of its arguments are substituted, and whose parameters
// are their runtime leaves, parameter p holding hole p of the key.
//
// The key goes into the table before the clone is simplified, so the
// clone's own calls with its key, a fixed parameter passed on unchanged,
// become self calls: that, and the finite supply of keys the binding times
// allow, is why a run ends.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize {

namespace {

void count(Statistics &stats, BindingTime time) {
  switch (time) {
  case BindingTime::Free:
    ++stats.free;
    return;
  case BindingTime::Fixed:
    ++stats.fixed;
    return;
  case BindingTime::Decreasing:
    ++stats.decreasing;
    return;
  case BindingTime::Bounded:
    ++stats.bounded;
    return;
  case BindingTime::Other:
    return;
  }
}

} // namespace

// Replaces each parameter of `clone` whose argument is static by that
// argument's pattern, rebuilt over new parameters for its leaves. The new
// parameters follow the holes in order, so parameter p holds hole p.
void Specializer::substitute(idr::FuncOp clone, const Composed &composed) {
  ArrayRef<Argument> args = composed.args;
  unsigned arity = clone.getNumArguments();
  SmallVector<unsigned> positions;
  SmallVector<Type> types;
  SmallVector<Location> locs;
  for (unsigned p = 0; p < arity; ++p) {
    const Argument &arg = args[p];
    if (arg.pattern.isHole()) {
      positions.push_back(arity);
      types.push_back(clone.getArgument(p).getType());
      locs.push_back(clone.getArgument(p).getLoc());
      continue;
    }
    // A leaf keeps its type, and with it how often it may be used.
    for (Value leaf : arg.leaves) {
      positions.push_back(arity);
      types.push_back(leaf.getType());
      locs.push_back(leaf.getLoc());
    }
  }
  SmallVector<DictionaryAttr> attrs(positions.size(), DictionaryAttr());
  (void)clone.insertArguments(positions, types, attrs, locs);

  Block &entry = clone.getBody().front();
  SmallVector<Value> holes(composed.values.size());
  unsigned next = arity;
  for (unsigned p = 0; p < arity; ++p)
    for (unsigned hole : composed.held[p])
      holes[hole] = entry.getArgument(next++);
  rewriter.setInsertionPointToStart(&entry);
  for (unsigned p = 0; p < arity; ++p)
    rewriter.replaceAllUsesWith(entry.getArgument(p), rebuild(rewriter, args[p].pattern, holes));
  llvm::BitVector originals(clone.getNumArguments());
  originals.set(0, arity);
  (void)clone.eraseArguments(originals);
}

LogicalResult Specializer::specialize(idr::CallOp call, idr::FuncOp callee) {
  if (!callee || callee.isExternal())
    return success();
  std::optional<Composed> composed = composeKey(call, clones, times);
  if (!composed)
    return success();

  // Making the clone and calling it is one action, which a debug counter
  // may skip: then there is no clone and the call stays.
  LogicalResult result = success();
  support::perform<SpecializeCloneAction>(call, [&] {
    const Clone *clone = clones.lookup(composed->key);
    if (clone) {
      ++stats.shared;
    } else {
      FailureOr<idr::FuncOp> copy =
          makeClone(rewriter, callee, composed->key.getOrigin(), CloneTable::Kind::Spec, call,
                    symbols, clones);
      if (failed(copy)) {
        result = failure();
        return;
      }
      changed = true;
      substitute(*copy, *composed);
      SmallVector<FlatSymbolRefAttr> named;
      for (const Argument &arg : composed->args)
        labels(arg.pattern, named);
      SmallVector<idr::FuncOp> functions = llvm::map_to_vector(
          named, [&](FlatSymbolRefAttr name) { return symbols.lookup<idr::FuncOp>(name.getAttr()); });
      giveFirstFacts(*copy, callee, functions, holds);
      bool unrolls = false;
      for (const Argument &arg : composed->args) {
        if (arg.pattern.isHole())
          continue;
        count(stats, arg.time);
        unrolls |= arg.time == BindingTime::Decreasing;
      }
      ++stats.clones;
      copy->setCloneAttr(CloneAttr::get(copy->getContext(),
                                        FlatSymbolRefAttr::get(copy->getSymNameAttr()),
                                        composed->key));
      clone = &clones.add(*copy);
      made.push_back({*copy, unrolls});
    }
    if (redirect(rewriter, call, *clone, composed->values, std::nullopt))
      changed = true;
  });
  return result;
}

} // namespace idr::specialize
