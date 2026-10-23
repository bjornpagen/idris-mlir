// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rewrites of the control-flow ops, which the specification declares as
// skeleton rules of the e-graph pass (IdrisMLIR.Spec.Control.Rules): one-way,
// since a match or a join point is an op of the skeleton, never a pure
// value. Each `decide` reads the extracted e-graph and the root, and what it
// chose (a region, the cases kept, the arms a dispatch goes into) rides in
// its Rewrite; `rewrite` carries that out between the engine's two turns,
// on the root as it then is, checking that the shape it rewrites still
// stands and leaving the root as it is where it does not. This unit holds
// what the rule families share (idr/Transforms/Joins/Rules.h).

#include "idr/Transforms/Joins/Rules.h"

#include "idr/IR/Control/Stated.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ops/Rules.h"

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
      // A yield's operands are its op's results, each at its number.
      auto yield = cast<YieldOp>(region.front().getTerminator());
      SmallVector<Value> kept;
      for (OpOperand &given : yield->getOpOperands())
        if (keep.test(given.getOperandNumber()))
          kept.push_back(given.get());
      rewriter.setInsertionPoint(yield);
      rewriter.replaceOpWithNewOp<YieldOp>(yield, kept);
    }
  // Only an op that states the lifetimes its scoped results live in
  // restates them for the results it keeps; one that states none (an index
  // assumption, an unsafe run) keeps its results with nothing to restate.
  auto states = dyn_cast<StatesOutersOpInterface>(op);
  SmallVector<Value> outers;
  if (states) {
    OperandRange stated = states.getOutersMutable();
    unsigned entry = 0;
    for (OpResult result : op->getResults()) {
      if (!scoped(result))
        continue;
      if (keep.test(result.getResultNumber()))
        outers.push_back(stated[entry]);
      ++entry;
    }
    llvm::append_range(outers, stated.drop_front(entry));
  }
  SmallVector<Type> types;
  for (OpResult result : op->getResults())
    if (keep.test(result.getResultNumber()))
      types.push_back(result.getType());
  Operation *fresh = withResults(rewriter, op, types);
  if (states)
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

void exits(RewriterBase &rewriter, Operation *op) {
  eraseAfter(rewriter, op);
  Operation *kept = op;
  if (op->getNumResults())
    kept = keepResults(rewriter, op, llvm::BitVector(op->getNumResults(), false));
  rewriter.setInsertionPointAfter(kept);
  ub::UnreachableOp::create(rewriter, kept->getLoc());
}

llvm::SmallVector<unsigned, 4> unusedResults(Operation *op) {
  llvm::SmallVector<unsigned, 4> found;
  for (OpResult result : op->getResults())
    if (result.use_empty())
      found.push_back(result.getResultNumber());
  return found;
}

// A position the root no longer has, or a result an earlier rewrite gave a
// use, stays.
void dropUnused(RewriterBase &rewriter, Operation *op, ArrayRef<unsigned> chosen) {
  llvm::BitVector keep(op->getNumResults(), true);
  for (unsigned at : chosen)
    if (at < op->getNumResults() && op->getResult(at).use_empty())
      keep.reset(at);
  if (!keep.all())
    keepResults(rewriter, op, keep);
}

std::optional<egraph::Edit> choose(llvm::SmallVector<unsigned, 4> found) {
  if (found.empty())
    return std::nullopt;
  return egraph::Edit(egraph::Rewrite{std::move(found)});
}

DataConOp constructorOf(Value value, const egraph::OperandFacts &facts) {
  if (auto made = facts.builtBy<DataConOp>(value))
    return made;
  if (auto reindex = facts.builtBy<DataReindexOp>(value))
    return facts.builtBy<DataConOp>(reindex.getValue());
  return {};
}

bool knownConstructor(Value value, const egraph::OperandFacts &facts) {
  return isa_and_nonnull<ConAttr>(facts.held(value)) ||
         static_cast<bool>(constructorOf(value, facts));
}

} // namespace idr::control
