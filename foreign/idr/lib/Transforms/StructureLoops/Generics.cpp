// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The linalg op a plan names, built where its root loop was. The body is the
// loop's own ops, cloned: each induction variable of the nest becomes the
// op's index along its dimension, a read that is an input becomes the input's
// element, the destination's element or the fold's accumulator becomes the
// output element, and a nest's tensor, asked only its shape, becomes the
// destination, whose shape it has. The yield is what the loop inserted or
// the fold yielded.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/IR/IRMapping.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::structure {

namespace {

// The inputs of an op: one per distinct read of a tensor at a map, so a
// read made twice is one input.
struct Inputs {
  SmallVector<Value> tensors;
  SmallVector<AffineMap> maps;
  // For each read of the plan, the input it is.
  SmallVector<unsigned> of;
};

Inputs inputsOf(Plan &plan) {
  Inputs inputs;
  for (Read read : plan.reads) {
    unsigned at = 0;
    while (at < inputs.tensors.size() &&
           (inputs.tensors[at] != read.op.getTensor() || inputs.maps[at] != read.map))
      ++at;
    inputs.of.push_back(at);
    if (at == inputs.tensors.size()) {
      inputs.tensors.push_back(read.op.getTensor());
      inputs.maps.push_back(read.map);
    }
  }
  return inputs;
}

// What a body is built from: the plan, the op's block arguments (its inputs'
// elements, then its output element), and what the fold's induction
// variable becomes: the op's index along `foldDim`, or `foldValue`, a
// loop's induction variable.
struct Body {
  Plan &plan;
  const Inputs &inputs;
  ValueRange args;
  std::optional<unsigned> foldDim;
  Value foldValue;
};

// Whether the body built from `ops` (and from the fold's body when
// `withFold`), yielding `yielded`, reads `value`. A read that becomes an
// input reads nothing in the body.
bool readsValue(Value value, Plan &plan, ArrayRef<Operation *> ops, bool withFold,
                Value yielded) {
  if (value == yielded)
    return true;
  Block *fold = withFold ? plan.fold.getBody() : nullptr;
  return llvm::any_of(value.getUsers(), [&](Operation *user) {
    if (llvm::any_of(plan.reads, [&](Read read) { return read.op.getOperation() == user; }))
      return false;
    return llvm::any_of(ops, [&](Operation *op) { return op->isAncestor(user); }) ||
           (fold && fold->findAncestorOpInBlock(*user));
  });
}

// Clones `ops`, then, when `withFold`, the fold's body, and yields `yielded`
// as mapped. An index is made only where the body reads its induction
// variable.
void fill(OpBuilder &b, Location loc, const Body &body, ArrayRef<Operation *> ops, bool withFold,
          Value yielded) {
  Plan &plan = body.plan;
  Value out = body.args.back();
  IRMapping mapping;
  for (auto [dim, loop] : llvm::enumerate(plan.nest)) {
    if (readsValue(loop.getInductionVar(), plan, ops, withFold, yielded))
      mapping.map(loop.getInductionVar(),
                  linalg::IndexOp::create(b, loc, static_cast<uint64_t>(dim)).getResult());
    mapping.map(loop.getRegionIterArg(0), plan.destination);
  }
  if (plan.form == Form::Parallel && plan.element)
    mapping.map(plan.element.getResult(), out);
  for (auto [read, input] : llvm::zip_equal(plan.reads, body.inputs.of))
    mapping.map(read.op.getResult(), body.args[input]);
  if (withFold) {
    mapping.map(plan.fold.getRegionIterArg(0), out);
    Value step = plan.fold.getInductionVar();
    if (body.foldValue)
      mapping.map(step, body.foldValue);
    else if (body.foldDim && readsValue(step, plan, ops, withFold, yielded))
      mapping.map(step, linalg::IndexOp::create(b, loc, *body.foldDim).getResult());
  }
  for (Operation *op : ops)
    b.clone(*op, mapping);
  if (withFold)
    for (Operation &op : plan.fold.getBody()->without_terminator())
      if (llvm::none_of(plan.reads, [&](Read read) { return read.op.getOperation() == &op; }))
        b.clone(op, mapping);
  linalg::YieldOp::create(b, loc, mapping.lookupOrDefault(yielded));
}

// The tensor of the fold's inits, one per element: the destination where it
// holds them, else a parallel op over it computing each.
Value initsOf(RewriterBase &rewriter, Location loc, Plan &plan) {
  if (plan.element)
    return plan.destination;
  MLIRContext *ctx = rewriter.getContext();
  auto depth = static_cast<unsigned>(plan.nest.size());
  Inputs none;
  auto generic = linalg::GenericOp::create(
      rewriter, loc, TypeRange{plan.destination.getType()}, ValueRange{},
      ValueRange{plan.destination}, ArrayRef<AffineMap>{AffineMap::getMultiDimIdentityMap(depth, ctx)},
      SmallVector<utils::IteratorType>(depth, utils::IteratorType::parallel),
      [&](OpBuilder &b, Location l, ValueRange args) {
        Plan inits = plan;
        inits.reads.clear();
        fill(b, l, Body{inits, none, args, std::nullopt, Value()}, plan.initClones,
             /*withFold=*/false,
             plan.fold.getInitArgs()[0]);
      });
  return generic.getResult(0);
}

// The nest made one parallel op.
Value parallel(RewriterBase &rewriter, Location loc, Plan &plan) {
  MLIRContext *ctx = rewriter.getContext();
  auto depth = static_cast<unsigned>(plan.nest.size());
  Inputs inputs = inputsOf(plan);
  SmallVector<AffineMap> maps(inputs.maps);
  maps.push_back(AffineMap::getMultiDimIdentityMap(depth, ctx));
  auto generic = linalg::GenericOp::create(
      rewriter, loc, TypeRange{plan.destination.getType()}, inputs.tensors,
      ValueRange{plan.destination}, maps,
      SmallVector<utils::IteratorType>(depth, utils::IteratorType::parallel),
      [&](OpBuilder &b, Location l, ValueRange args) {
        auto insert = cast<tensor::InsertOp>(*plan.nest.back().getBody()->getTerminator()
                                                  ->getOperand(0)
                                                  .getDefiningOp());
        fill(b, l, Body{plan, inputs, args, std::nullopt, Value()}, plan.clones,
             /*withFold=*/false, insert.getScalar());
      });
  return generic.getResult(0);
}

// The nest and its fold made one op, the fold's dimension the last, a
// reduction into the inits.
Value reduceUnder(RewriterBase &rewriter, Location loc, Plan &plan) {
  MLIRContext *ctx = rewriter.getContext();
  auto depth = static_cast<unsigned>(plan.nest.size());
  Value inits = initsOf(rewriter, loc, plan);
  Inputs inputs = inputsOf(plan);
  SmallVector<AffineMap> maps(inputs.maps);
  SmallVector<AffineExpr> frame = llvm::map_to_vector(
      llvm::seq<unsigned>(0, depth), [&](unsigned dim) { return getAffineDimExpr(dim, ctx); });
  maps.push_back(AffineMap::get(depth + 1, 0, frame, ctx));
  SmallVector<utils::IteratorType> iterators(depth, utils::IteratorType::parallel);
  iterators.push_back(utils::IteratorType::reduction);
  auto generic = linalg::GenericOp::create(
      rewriter, loc, TypeRange{inits.getType()}, inputs.tensors, ValueRange{inits}, maps,
      iterators, [&](OpBuilder &b, Location l, ValueRange args) {
        fill(b, l, Body{plan, inputs, args, depth, Value()}, plan.clones, /*withFold=*/true,
             plan.fold.getBody()->getTerminator()->getOperand(0));
      });
  return generic.getResult(0);
}

// The fold's loop around one parallel op over the nest: each step combines
// every element's accumulator with its element at that step, so each
// element is combined in index order, and the nest's elements on lanes.
Value interchange(RewriterBase &rewriter, Location loc, Plan &plan) {
  MLIRContext *ctx = rewriter.getContext();
  auto depth = static_cast<unsigned>(plan.nest.size());
  Value inits = initsOf(rewriter, loc, plan);
  Inputs inputs = inputsOf(plan);
  SmallVector<AffineMap> maps(inputs.maps);
  maps.push_back(AffineMap::getMultiDimIdentityMap(depth, ctx));
  Value zero = arith::ConstantIndexOp::create(rewriter, loc, 0);
  Value one = arith::ConstantIndexOp::create(rewriter, loc, 1);
  auto loop = scf::ForOp::create(
      rewriter, loc, zero, plan.fold.getUpperBound(), one, ValueRange{inits},
      [&](OpBuilder &b, Location l, Value step, ValueRange accumulators) {
        auto generic = linalg::GenericOp::create(
            b, l, TypeRange{inits.getType()}, inputs.tensors, accumulators, maps,
            SmallVector<utils::IteratorType>(depth, utils::IteratorType::parallel),
            [&](OpBuilder &inner, Location at, ValueRange args) {
              fill(inner, at, Body{plan, inputs, args, std::nullopt, step}, plan.clones,
                   /*withFold=*/true, plan.fold.getBody()->getTerminator()->getOperand(0));
            });
        scf::YieldOp::create(b, l, generic.getResult(0));
      });
  return loop.getResult(0);
}

// A lone fold made one reduction into a tensor of no dimension.
Value reduce(RewriterBase &rewriter, Location loc, Plan &plan) {
  MLIRContext *ctx = rewriter.getContext();
  Value init = plan.fold.getInitArgs()[0];
  auto scalar = RankedTensorType::get({}, init.getType());
  Value seed = tensor::FromElementsOp::create(rewriter, loc, scalar, ValueRange{init});
  Inputs inputs = inputsOf(plan);
  SmallVector<AffineMap> maps(inputs.maps);
  maps.push_back(AffineMap::get(1, 0, ctx));
  auto generic = linalg::GenericOp::create(
      rewriter, loc, TypeRange{scalar}, inputs.tensors, ValueRange{seed}, maps,
      ArrayRef<utils::IteratorType>{utils::IteratorType::reduction},
      [&](OpBuilder &b, Location l, ValueRange args) {
        fill(b, l, Body{plan, inputs, args, 0u, Value()}, {}, /*withFold=*/true,
             plan.fold.getBody()->getTerminator()->getOperand(0));
      });
  return tensor::ExtractOp::create(rewriter, loc, generic.getResult(0), ValueRange{});
}

} // namespace

Value build(RewriterBase &rewriter, Plan &plan) {
  Operation *root = plan.nest.empty() ? plan.fold.getOperation() : plan.nest.front().getOperation();
  Location loc = root->getLoc();
  OpBuilder::InsertionGuard guard(rewriter);
  rewriter.setInsertionPoint(root);
  switch (plan.form) {
  case Form::Parallel:
    return parallel(rewriter, loc, plan);
  case Form::ReduceUnder:
    return reduceUnder(rewriter, loc, plan);
  case Form::Interchange:
    return interchange(rewriter, loc, plan);
  case Form::Reduce:
    return reduce(rewriter, loc, plan);
  }
  llvm_unreachable("every form is built");
}

} // namespace idr::structure
