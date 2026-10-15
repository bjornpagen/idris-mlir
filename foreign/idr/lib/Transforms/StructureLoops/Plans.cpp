// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a loop is: a nest that writes every element of a tensor, a fold, or
// neither. The shapes are the frontend's, after the optimizer: each loop
// counts from 0 by 1 over an index and carries one value; a tabulation is a
// nest of one loop per dimension, carrying the tensor and inserting the
// element at the induction variables in nest order; a fold carries a word.
// A loop of any other shape, or whose body does more than compute, is the
// program's own order and is left to it.
//
// The facts each plan rests on are the IR's: effects through
// MemoryEffectOpInterface (idr::onlyAllocates), and the equality of sizes
// through value bounds, which idr.tie_shape carries across calls. Nothing
// here reads an element type to decide.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;

namespace idr::structure {

namespace {

// A loop from 0 by 1 over an index, carrying one value: the loops the
// frontend writes.
bool unitLoop(scf::ForOp loop) {
  return !loop.getUnsignedCmp() && loop.getNumRegionIterArgs() == 1 &&
         loop.getInductionVar().getType().isIndex() &&
         matchPattern(loop.getLowerBound(), m_Zero()) && matchPattern(loop.getStep(), m_One());
}

// Whether `value` is defined outside `root`, so a body built in `root`'s
// place may use it as it is.
bool outside(Value value, Operation *root) {
  return !root->isAncestor(value.getParentBlock()->getParentOp());
}

// Whether two sizes are one, as value bounds proves it; what it cannot
// prove is not.
bool same(const ValueBoundsConstraintSet::Variable &a,
          const ValueBoundsConstraintSet::Variable &b) {
  FailureOr<bool> equal = ValueBoundsConstraintSet::areEqual(a, b);
  return succeeded(equal) && *equal;
}

// An op of the nest that runs once per element of the op made in its place,
// where it ran once per row or once per element: it may only compute, and
// one between the loops or that a fold's body reads runs more often than it
// did, so it holds no loop and makes no array.
bool scalarCode(Operation *op) {
  return op->getNumRegions() == 0 &&
         llvm::none_of(op->getResultTypes(), [](Type type) { return isa<ShapedType>(type); });
}

// A tabulation: the loops, the insert of its innermost body, and the read of
// the destination at the insert's indices where the body reads it.
struct Nest {
  SmallVector<scf::ForOp> loops;
  tensor::InsertOp insert;
  tensor::ExtractOp element;
  // The ops between the loops, outer first.
  SmallVector<Operation *> between;

  Block &innermost() { return *loops.back().getBody(); }
  Value destination() { return loops.front().getInitArgs()[0]; }
};

// The nest rooted at `root`, or none. Each loop's body ends in the next loop
// and the yield of its result; the innermost inserts at the induction
// variables in nest order and yields the insert. A loop's tensor is used
// only along that chain, by tensor.dim, and in the innermost body by one read
// at the insert's indices. Every op of the bodies only computes, those
// between the loops are scalar code, and the nest writes every element.
std::optional<Nest> nestAt(scf::ForOp root) {
  if (!unitLoop(root))
    return std::nullopt;
  auto type = dyn_cast<RankedTensorType>(root.getRegionIterArg(0).getType());
  if (!type || type.getRank() == 0)
    return std::nullopt;
  Nest nest;
  for (scf::ForOp loop = root;;) {
    nest.loops.push_back(loop);
    Block *body = loop.getBody();
    Value yielded = cast<scf::YieldOp>(body->getTerminator()).getOperand(0);
    if (static_cast<int64_t>(nest.loops.size()) < type.getRank()) {
      auto inner = yielded.getDefiningOp<scf::ForOp>();
      if (!inner || inner->getBlock() != body || !unitLoop(inner) ||
          inner.getInitArgs()[0] != loop.getRegionIterArg(0) ||
          inner.getRegionIterArg(0).getType() != type)
        return std::nullopt;
      for (Operation &op : body->without_terminator())
        if (&op != inner.getOperation()) {
          if (!scalarCode(&op) || !onlyAllocates(&op))
            return std::nullopt;
          nest.between.push_back(&op);
        }
      loop = inner;
      continue;
    }
    auto insert = yielded.getDefiningOp<tensor::InsertOp>();
    if (!insert || insert->getBlock() != body || insert.getDest() != loop.getRegionIterArg(0) ||
        !insert->hasOneUse() ||
        !llvm::equal(insert.getIndices(), nest.loops,
                     [](Value index, scf::ForOp at) { return index == at.getInductionVar(); }))
      return std::nullopt;
    nest.insert = insert;
    for (Operation &op : body->without_terminator())
      if (&op != insert.getOperation() && !onlyAllocates(&op))
        return std::nullopt;
    break;
  }
  // Each loop's tensor flows only down the chain, or is asked its shape.
  size_t depth = nest.loops.size();
  for (auto [d, loop] : llvm::enumerate(nest.loops))
    for (Operation *user : loop.getRegionIterArg(0).getUsers()) {
      if (d + 1 < depth ? user == nest.loops[d + 1].getOperation()
                        : user == nest.insert.getOperation())
        continue;
      if (isa<tensor::DimOp>(user))
        continue;
      auto read = dyn_cast<tensor::ExtractOp>(user);
      if (d + 1 == depth && read && read->getBlock() == &nest.innermost() && !nest.element &&
          llvm::equal(read.getIndices(), nest.insert.getIndices())) {
        nest.element = read;
        continue;
      }
      return std::nullopt;
    }
  for (auto [d, loop] : llvm::enumerate(nest.loops))
    if (!same(loop.getUpperBound(), {nest.destination(), static_cast<int64_t>(d)}))
      return std::nullopt;
  return nest;
}

// A fold: a loop carrying an integer or a float, whose body only computes,
// with its combiner where that is one associative and commutative integer
// op of the accumulator and another value, the accumulator's only use. An
// op that may overflow (nsw, nuw) is no such combiner: reassociated, it
// could overflow where the program did not.
struct Fold {
  scf::ForOp loop;
  Operation *combiner = nullptr;
};

std::optional<Fold> foldAt(scf::ForOp loop) {
  if (!unitLoop(loop) || !isa<IntegerType, FloatType>(loop.getRegionIterArg(0).getType()))
    return std::nullopt;
  Block *body = loop.getBody();
  for (Operation &op : body->without_terminator())
    if (!onlyAllocates(&op))
      return std::nullopt;
  Fold fold{loop};
  Value acc = loop.getRegionIterArg(0);
  Operation *combine = cast<scf::YieldOp>(body->getTerminator()).getOperand(0).getDefiningOp();
  if (!isa<IntegerType>(acc.getType()) || !combine || combine->getBlock() != body ||
      !isa<arith::AddIOp, arith::MulIOp, arith::AndIOp, arith::OrIOp, arith::XOrIOp,
           arith::MinSIOp, arith::MinUIOp, arith::MaxSIOp, arith::MaxUIOp>(combine) ||
      !acc.hasOneUse() || (combine->getOperand(0) == acc) == (combine->getOperand(1) == acc))
    return fold;
  if (auto flags = dyn_cast<arith::ArithIntegerOverflowFlagsInterface>(combine);
      flags && flags.getOverflowAttr().getValue() != arith::IntegerOverflowFlags::none)
    return fold;
  fold.combiner = combine;
  return fold;
}

// The reads directly in `blocks` of a tensor defined outside `root`, each
// index one of the op's dimensions `dims`, no dimension twice, and each read
// dimension the size of the op's dimension it is read at (`extent`): the
// inputs of the op, at their maps. Any other read stays in the body.
SmallVector<Read> readsIn(ArrayRef<Block *> blocks, ArrayRef<Value> dims, Operation *root,
                          function_ref<bool(Value tensor, int64_t at, unsigned dim)> extent) {
  MLIRContext *ctx = root->getContext();
  SmallVector<Read> reads;
  for (Block *block : blocks)
    for (Operation &op : block->without_terminator()) {
      auto read = dyn_cast<tensor::ExtractOp>(&op);
      if (!read || !outside(read.getTensor(), root))
        continue;
      SmallVector<AffineExpr> exprs;
      llvm::SmallDenseSet<unsigned> seen;
      bool lifted = true;
      for (auto [at, index] : llvm::enumerate(read.getIndices())) {
        const auto *found = llvm::find(dims, index);
        auto dim = static_cast<unsigned>(found - dims.begin());
        if (found == dims.end() || !seen.insert(dim).second ||
            !extent(read.getTensor(), static_cast<int64_t>(at), dim)) {
          lifted = false;
          break;
        }
        exprs.push_back(getAffineDimExpr(dim, ctx));
      }
      if (lifted)
        reads.push_back({read, AffineMap::get(static_cast<unsigned>(dims.size()), 0, exprs, ctx)});
    }
  return reads;
}

// The ops among `candidates` that `users` read, through each other, in the
// order of `candidates`.
SmallVector<Operation *> needed(ArrayRef<Operation *> users, ArrayRef<Operation *> candidates) {
  llvm::SmallPtrSet<Operation *, 16> pool(candidates.begin(), candidates.end());
  llvm::SmallPtrSet<Operation *, 16> taken;
  SmallVector<Operation *> work(users.begin(), users.end());
  while (!work.empty()) {
    Operation *op = work.pop_back_val();
    op->walk([&](Operation *inner) {
      for (Value operand : inner->getOperands())
        if (Operation *def = operand.getDefiningOp(); def && pool.contains(def) &&
                                                      taken.insert(def).second)
          work.push_back(def);
    });
  }
  SmallVector<Operation *> out;
  for (Operation *op : candidates)
    if (taken.contains(op))
      out.push_back(op);
  return out;
}

// The ops of `block`, its terminator included: what reads the values a body
// is built from.
SmallVector<Operation *> opsOf(Block &block) {
  return llvm::map_to_vector(block, [](Operation &op) { return &op; });
}

bool isRead(ArrayRef<Read> reads, Operation *op) {
  return llvm::any_of(reads, [&](Read read) { return read.op.getOperation() == op; });
}

SmallVector<Value> inductionVariables(Nest &nest) {
  return llvm::map_to_vector(nest.loops, [](scf::ForOp loop) { return loop.getInductionVar(); });
}

// The extent of each dimension of the nest is the destination's.
auto nestExtent(Nest &nest) {
  return [&nest](Value tensor, int64_t at, unsigned dim) {
    return same({tensor, at}, {nest.destination(), static_cast<int64_t>(dim)});
  };
}

// A nest whose element is a fold: ReduceUnder when `combined` and the fold's
// combiner is one integer op, Interchange otherwise. The fold's bound is
// fixed outside the nest, so its dimension is the same for every element;
// what the fold reads of the nest is scalar code, which runs once per
// element and step.
std::optional<Plan> underNest(Nest &nest, bool combined) {
  auto inner = nest.insert.getScalar().getDefiningOp<scf::ForOp>();
  if (!inner || inner->getBlock() != &nest.innermost())
    return std::nullopt;
  std::optional<Fold> fold = foldAt(inner);
  Operation *root = nest.loops.front();
  if (!fold || (combined && !fold->combiner) || !outside(inner.getUpperBound(), root))
    return std::nullopt;

  Plan plan;
  plan.form = combined ? Form::ReduceUnder : Form::Interchange;
  plan.nest = nest.loops;
  plan.destination = nest.destination();
  plan.fold = inner;
  plan.element = nest.element;

  SmallVector<Value> dims = inductionVariables(nest);
  if (combined)
    dims.push_back(inner.getInductionVar());
  auto depth = static_cast<unsigned>(nest.loops.size());
  auto extent = [&](Value tensor, int64_t at, unsigned dim) {
    return dim < depth ? nestExtent(nest)(tensor, at, dim)
                       : same({tensor, at}, inner.getUpperBound());
  };
  plan.reads = readsIn({&nest.innermost(), inner.getBody()}, dims, root, extent);
  if (combined && llvm::none_of(plan.reads, [&](Read read) {
        return llvm::any_of(read.map.getResults(), [&](AffineExpr expr) {
          return expr == getAffineDimExpr(depth, root->getContext());
        });
      }))
    return std::nullopt;

  // The ops that may be cloned: those between the loops, and the innermost
  // body's but the fold, the insert and the element. The op made from the
  // nest takes the reads as inputs; the op of the inits, which has none,
  // reads them in its body.
  SmallVector<Operation *> candidates(nest.between.begin(), nest.between.end());
  SmallVector<Operation *> initCandidates(nest.between.begin(), nest.between.end());
  for (Operation &op : nest.innermost().without_terminator())
    if (&op != inner.getOperation() && &op != nest.insert.getOperation() &&
        &op != nest.element.getOperation()) {
      initCandidates.push_back(&op);
      if (!isRead(plan.reads, &op))
        candidates.push_back(&op);
    }
  plan.clones = needed(opsOf(*inner.getBody()), candidates);
  // The output element stands for the accumulator, so the destination's
  // element can be read only as the fold's init: then the destination holds
  // the inits. Any other init is computed per element, from what is outside
  // the nest, the induction variables and the nest's scalar code.
  Value init = inner.getInitArgs()[0];
  if (nest.element && (!nest.element->hasOneUse() || init != nest.element.getResult()))
    return std::nullopt;
  if (Operation *def = init.getDefiningOp(); def && llvm::is_contained(initCandidates, def)) {
    plan.initClones = needed({def}, initCandidates);
    plan.initClones.push_back(def);
  } else if (!nest.element && !outside(init, root) &&
             !llvm::is_contained(inductionVariables(nest), init)) {
    return std::nullopt;
  }
  if (!llvm::all_of(plan.clones, scalarCode) || !llvm::all_of(plan.initClones, scalarCode))
    return std::nullopt;
  return plan;
}

// Any other nest: one parallel op whose body is the innermost body's.
Plan parallel(Nest &nest) {
  Plan plan;
  plan.form = Form::Parallel;
  plan.nest = nest.loops;
  plan.destination = nest.destination();
  plan.element = nest.element;
  plan.reads =
      readsIn({&nest.innermost()}, inductionVariables(nest), nest.loops.front(), nestExtent(nest));
  SmallVector<Operation *> body;
  for (Operation &op : nest.innermost().without_terminator())
    if (&op != nest.insert.getOperation() && &op != nest.element.getOperation() &&
        !isRead(plan.reads, &op))
      body.push_back(&op);
  SmallVector<Operation *> users(body);
  users.push_back(nest.insert);
  plan.clones = needed(users, nest.between);
  plan.clones.append(body.begin(), body.end());
  return plan;
}

// Whether an enclosing nest makes `loop` the fold of a ReduceUnder or an
// Interchange.
bool takenByNest(scf::ForOp loop) {
  for (auto outer = loop->getParentOfType<scf::ForOp>(); outer;
       outer = outer->getParentOfType<scf::ForOp>())
    if (std::optional<Nest> nest = nestAt(outer);
        nest && nest->insert.getScalar() == loop.getResult(0) &&
        (underNest(*nest, true) || underNest(*nest, false)))
      return true;
  return false;
}

// A lone fold whose combiner is one integer op, reading an input whose
// dimension is its bound, which gives the reduction its extent.
std::optional<Plan> reduction(scf::ForOp loop) {
  std::optional<Fold> fold = foldAt(loop);
  if (!fold || !fold->combiner)
    return std::nullopt;
  Plan plan;
  plan.form = Form::Reduce;
  plan.fold = loop;
  plan.reads = readsIn({loop.getBody()}, {loop.getInductionVar()}, loop,
                       [&](Value tensor, int64_t at, unsigned) {
                         return same({tensor, at}, loop.getUpperBound());
                       });
  if (plan.reads.empty() || takenByNest(loop))
    return std::nullopt;
  return plan;
}

} // namespace

std::optional<Plan> planAt(scf::ForOp loop) {
  if (std::optional<Nest> nest = nestAt(loop)) {
    if (std::optional<Plan> plan = underNest(*nest, true))
      return plan;
    if (std::optional<Plan> plan = underNest(*nest, false))
      return plan;
    return parallel(*nest);
  }
  return reduction(loop);
}

} // namespace idr::structure
