// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rewrites of the control-flow ops, which the specification declares as
// skeleton rules of the e-graph pass (IdrisMLIR.Spec.Control.Rules): one-way,
// since a match or a join point is an op of the skeleton, never a pure
// value. Each `decide` reads the extracted e-graph and the root, and what it
// chose (a region, the cases kept, the arms a dispatch goes into) rides in
// its Rewrite; `rewrite` carries that out between the engine's two rounds,
// on the root as it then is, checking that the shape it rewrites still
// stands and leaving the root as it is where it does not. This unit holds
// what the rule families share (idr/Transforms/Joins/Rules.h).

#include "idr/Transforms/Joins/Rules.h"

#include "idr/IR/Control/Stated.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::control {

bool yields(Region &region) {
  return !region.empty() && isa<YieldOp>(region.front().getTerminator());
}

Operation *withResults(RewriterBase &rewriter, Operation *op, TypeRange types) {
  rewriter.setInsertionPoint(op);
  OperationState state(op->getLoc(), op->getName(), op->getOperands(), types, op->getAttrs(),
                       /*successors=*/{}, /*regions=*/{});
  state.propertiesAttr = op->getPropertiesAsAttribute();
  for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i)
    state.addRegion();
  Operation *fresh = rewriter.create(state);
  for (auto [from, into] : llvm::zip_equal(op->getRegions(), fresh->getRegions()))
    rewriter.inlineRegionBefore(from, into, into.end());
  return fresh;
}

unsigned scopedResultCount(Operation *op) {
  return static_cast<unsigned>(llvm::count_if(op->getResults(), scoped));
}

// The lifetimes the op made states are those of the scoped results kept,
// then those of what its regions bind, which stay: a result's entry goes
// with it, so no entry is left for a value that is not there.
Operation *keepResults(RewriterBase &rewriter, Operation *op, const llvm::BitVector &keep) {
  for (Region &region : op->getRegions())
    if (yields(region)) {
      auto yield = cast<YieldOp>(region.front().getTerminator());
      SmallVector<Value> kept;
      for (auto [index, value] : llvm::enumerate(yield.getResults()))
        if (keep.test(index))
          kept.push_back(value);
      rewriter.setInsertionPoint(yield);
      rewriter.replaceOpWithNewOp<YieldOp>(yield, kept);
    }
  OperandRange stated = cast<StatesOutersOpInterface>(op).getOutersMutable();
  SmallVector<Value> outers;
  unsigned entry = 0;
  for (OpResult result : op->getResults()) {
    if (!scoped(result))
      continue;
    if (keep.test(result.getResultNumber()))
      outers.push_back(stated[entry]);
    ++entry;
  }
  llvm::append_range(outers, stated.drop_front(entry));
  SmallVector<Type> types;
  for (OpResult result : op->getResults())
    if (keep.test(result.getResultNumber()))
      types.push_back(result.getType());
  Operation *fresh = withResults(rewriter, op, types);
  rewriter.modifyOpInPlace(fresh, [&] {
    lifetimes::restateOuters(cast<StatesOutersOpInterface>(fresh), outers);
  });
  unsigned next = 0;
  for (OpResult result : op->getResults())
    if (keep.test(result.getResultNumber()))
      rewriter.replaceAllUsesWith(result, fresh->getResult(next++));
  rewriter.eraseOp(op);
  return fresh;
}

void eraseAfter(RewriterBase &rewriter, Operation *op) {
  for (Operation *after = &op->getBlock()->back(); after != op;) {
    Operation *previous = after->getPrevNode();
    after->dropAllUses();
    rewriter.eraseOp(after);
    after = previous;
  }
}

void exits(RewriterBase &rewriter, Operation *op) {
  eraseAfter(rewriter, op);
  Operation *kept = op;
  if (op->getNumResults())
    kept = keepResults(rewriter, op, llvm::BitVector(op->getNumResults(), false));
  rewriter.setInsertionPointAfter(kept);
  ub::UnreachableOp::create(rewriter, kept->getLoc());
}

void unused(RewriterBase &rewriter, Operation *op) {
  llvm::BitVector keep(op->getNumResults());
  for (OpResult result : op->getResults())
    if (!result.use_empty())
      keep.set(result.getResultNumber());
  if (!keep.all())
    keepResults(rewriter, op, keep);
}

bool someResultUnused(Operation *op) {
  return llvm::any_of(op->getResults(), [](OpResult result) { return result.use_empty(); });
}

std::optional<egraph::Edit> rewriteIf(bool holds) {
  return holds ? std::optional<egraph::Edit>(egraph::Rewrite{}) : std::nullopt;
}

DataConOp constructorOf(Value value, const egraph::OperandFacts &facts) {
  Operation *origin = facts.origin(value);
  if (auto cast = dyn_cast_or_null<DataReindexOp>(origin))
    origin = facts.origin(cast.getValue());
  return dyn_cast_or_null<DataConOp>(origin);
}

bool knownConstructor(Value value, const egraph::OperandFacts &facts) {
  return isa_and_nonnull<ConAttr>(facts.constant(value)) ||
         static_cast<bool>(constructorOf(value, facts));
}

} // namespace idr::control
