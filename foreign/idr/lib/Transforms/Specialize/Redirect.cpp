// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Calling a node: the one way a call becomes a call of a copy, one for each
// kind. It needs only the node's name and the copy's type, both known from
// the key before the copy is built.
//
// A signature copy's type is its owner's with each axis of a bare tensor
// argument static whose index term the call fixes as a constant. The
// caller's value keeps the type its own code reads, `?` there, so the call
// passes it through upstream's tensor.cast to the copy's type. Idris's type
// proves the extent is that constant, so the cast states an agreement and
// tests nothing at run time; inside a function, ties between extents stay
// idr.array.tie_shape. A copy's results keep the owner's types: a cast
// after the call would take a tail call out of tail position, and the
// caller learns no more from a result than its own types say. A graded
// array keeps its axis `?`, since no cast changes a type under a grade.
// The call's view of a copy is the copy's signature at the terms the call
// passes it, as a call of a built function takes its callee's, so each
// result is the type the call gave: a result the owner's type marks open
// the call took open already, converting it after itself where its own
// type closed it (openResults). The one result type a copy changes is a
// result keyed open for a tail lost to a layout: the call gives it at its
// caller's layout, so the cast after it, which re-packed, now builds
// nothing.
//
// A copy called where the call was stands at the call's place, so it keeps
// the call's tail fact; where it gives a result open, the re-pack it waited
// for is gone, so a tail lost to a layout is a tail call. A call that names
// its own function now (a copy's recursion keyed to the copy itself) takes
// the context the rule reads off it, and one that no longer does loses its
// context. A raise's call stands where the dispatch it replaces stood: a
// tail call where the dispatch was a tail of its function and nothing
// stands between the call and its block's end. Its row is what the call
// and the consumer did, which its function contained already; the writer
// derives the copy's own when its component is final.
// It gives what the dispatch gave as a function returns it, `?` at every
// axis of an array, so where the dispatch's type fixed a size the value
// reaches the dispatch's uses cast back to that type, after the call. A
// use that cast it to the call's type, as a tail does before its return,
// takes the call's result itself, so no cast stands between the call and
// a return and a raise of a recursion keeps its tail call.

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::specialize::detail {

namespace {

// A call of a copy whose function is not built yet, so no builder can read
// it: its properties set whole, its row the one the call it replaces held,
// which its caller's row covers already, and no claim of which operands
// it leaves untouched until the writer derives the copy's own.
CallOp callOf(RewriterBase &rewriter, Location loc, FlatSymbolRefAttr target, TypeRange results,
              IndexArgsAttr indices, ValueRange operands, TailKind tail, effects::Row row) {
  CallOp::Properties properties;
  properties.callee = target;
  properties.index_args = indices;
  properties.row = row;
  CallOp call = CallOp::create(rewriter, loc, results, operands, properties);
  call.setTailKind(tail);
  return call;
}

// `operand` passed where a copy asks `input`. At every position but a bare
// tensor's the copy's type is its owner's at the hold the operand is passed
// at, which the operand has, or one the call's rule lets stand for it (a
// lifetime of any kind where a view is asked), so it goes as it is. A bare
// tensor the copy asks at another type has an axis made static, and
// upstream's cast states it. Which axes became static is not carried out
// of the substitution that made them, so it is read here off the two
// uniqued types.
Value passedAs(OpBuilder &b, Location loc, Value operand, Type input) {
  auto tensor = dyn_cast<RankedTensorType>(input);
  if (!tensor || operand.getType() == input)
    return operand;
  return tensor::CastOp::create(b, loc, tensor, operand).getResult();
}

} // namespace

SmallVector<Value> operandsOf(RewriterBase &rewriter, CallOp call, const PatternWant &want,
                              const PatternKey &key, ArrayRef<Source> sources, FuncOp owner) {
  SmallVector<Type> types;
  for (auto [pattern, type] : llvm::zip_equal(key.params, owner.getArgumentTypes()))
    holeTypes(*pattern, type, types);
  rewriter.setInsertionPoint(call);
  Dialect *idr = call.getContext()->getLoadedDialect<IdrDialect>();
  SmallVector<Value> operands;
  for (auto [hole, source] : llvm::enumerate(sources))
    operands.push_back(idr::match(
        source, [&](Kept kept) -> Value { return want.leaves[kept.hole]; },
        [&](const Lifted &lifted) -> Value {
          return idr->materializeConstant(rewriter, lifted.constant, types[hole], call.getLoc())
              ->getResult(0);
        }));
  return operands;
}

// A copy replaces the call, and returns what the call does: each operand
// passed at the copy's type for it, and the copy's results as the call
// sees them, `type`'s at `indices`, which are the call's own types but
// where the key opens one for a tail lost to a layout. Such a tail gives
// each result to the call's uses as it is, each such use a cast towards its
// caller's return, which builds nothing now.
CallOp redirect(RewriterBase &rewriter, CallOp call, FlatSymbolRefAttr target, FunctionType type,
                IndexArgsAttr indices, ArrayRef<Value> operands) {
  Location loc = call.getLoc();
  rewriter.setInsertionPoint(call);
  SmallVector<Value> passed;
  for (auto [operand, input] : llvm::zip_equal(operands, type.getInputs()))
    passed.push_back(passedAs(rewriter, loc, operand, input));
  // The copy's signature names its own binders, the call's terms the
  // caller's levels: the view substitutes the one by the other, a result
  // keeping its type but for them.
  FunctionType seen = indices ? families::substitute(type, ExtentsAttr(), indices) : type;
  bool opened = !llvm::equal(seen.getResults(), call.getResultTypes());
  assert((!opened || !lastActOf(call)) &&
         "a copy gives each result as its call did, but one keyed open for a tail lost to a "
         "layout, which returns to its caller");
  TailKind kind = opened || tailCallOf(call) ? TailKind::tail : TailKind::nontail;
  CallOp fresh =
      callOf(rewriter, loc, target, seen.getResults(), indices, passed, kind, call.getRow());
  SmallVector<Value> old(call.getArgs());
  rewriter.replaceOp(call, fresh.getResults());
  eraseUnused(rewriter, old);
  if (!tailCallOf(fresh))
    fresh.setTailKind(tail::withContext(fresh));
  return fresh;
}

namespace {

// `given`, what a raise's call gives at the type a function returns it,
// where the dispatch gave `had`, placed after the call: each use of `had`
// takes `given` itself where the two types are one, or where the use is a
// tensor.cast to the type `given` has already, which the cast then states
// nothing of; any other use takes `given` cast back to the type of `had`,
// which fixed a size the function's type leaves `?`. A return gives its
// function's type, `?` at every axis, so it reads `had` only through such a
// cast, and nothing stands between the call and a return.
void giveAs(RewriterBase &rewriter, Location loc, Value given, Value had) {
  if (given.getType() == had.getType()) {
    rewriter.replaceAllUsesWith(had, given);
    return;
  }
  for (OpOperand &use : llvm::make_early_inc_range(had.getUses()))
    if (auto widened = dyn_cast<tensor::CastOp>(use.getOwner());
        widened && widened.getType() == given.getType()) {
      rewriter.replaceAllUsesWith(widened.getResult(), given);
      rewriter.eraseOp(widened);
    }
  if (had.use_empty())
    return;
  rewriter.replaceAllUsesWith(had,
                              tensor::CastOp::create(rewriter, loc, had.getType(), given).getResult());
}

} // namespace

// A raise replaces what the dispatch returns; the steps from the call's
// result to the dispatch, each the one use of the one before, go from the
// dispatch back, and the call last.
CallOp redirect(RewriterBase &rewriter, CallOp call, FlatSymbolRefAttr target, FunctionType type,
                const RaiseWant &want) {
  Operation *dispatch = want.consumer.dispatch;
  // Whether the dispatch is a tail of its function, read off the function's
  // tails before it goes: it holds no fact of its own.
  bool atTail =
      llvm::is_contained(tail::sourcesOf(dispatch->getParentOfType<FuncOp>()), dispatch);
  effects::Row row = call.getRow() | effects::rowOf(dispatch);
  for (Operation *step : want.consumer.steps())
    row = row | effects::rowOf(step);
  rewriter.setInsertionPoint(dispatch);
  CallOp fresh = callOf(rewriter, call.getLoc(), target, type.getResults(), call.getIndexArgsAttr(),
                        want.operands, TailKind::nontail, row);
  SmallVector<Value> old(call.getArgs());
  for (auto [given, had] : llvm::zip_equal(fresh.getResults(), dispatch->getResults()))
    giveAs(rewriter, dispatch->getLoc(), given, had);
  rewriter.eraseOp(dispatch);
  for (Operation *step : llvm::reverse(want.consumer.steps()))
    rewriter.eraseOp(step);
  rewriter.eraseOp(call);
  eraseUnused(rewriter, old);
  // The call gives on what the dispatch gave, from its block, which ends a
  // tail where the dispatch was one: a tail call where nothing, no cast
  // back, stands between the two.
  if (atTail && tail::tailSource(*fresh->getBlock()) == fresh.getOperation())
    fresh.setTailKind(TailKind::tail);
  else
    fresh.setTailKind(tail::withContext(fresh));
  return fresh;
}

} // namespace idr::specialize::detail
