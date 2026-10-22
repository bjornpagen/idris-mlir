// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Calling a node: the one way a call becomes a call of a copy, one for each
// kind. It needs only the node's name and the copy's type, both known from
// the key before the copy is built.
//
// A copy called where the call was keeps the call's tail fact: the call is
// at the same place. A raise's call stands where the dispatch it replaces
// stood, so its tail fact is the one definition's answer there. Its row
// is what the call and the consumer did, which its function contained
// already; the writer derives the copy's own when its component is final.

#include "idr/IR/Effects/Query.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "Calls.h"

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
        source, [&](Kept kept) { return want.leaves[kept.hole]; },
        [&](const Lifted &lifted) {
          return idr->materializeConstant(rewriter, lifted.constant, types[hole], call.getLoc())
              ->getResult(0);
        }));
  return operands;
}

// A copy replaces the call, and returns what the call does.
CallOp redirect(RewriterBase &rewriter, CallOp call, FlatSymbolRefAttr target, FunctionType type,
                IndexArgsAttr indices, ArrayRef<Value> operands) {
  rewriter.setInsertionPoint(call);
  CallOp fresh = callOf(rewriter, call.getLoc(), target, type.getResults(), indices, operands,
                        call.getTailKind(), call.getRow());
  SmallVector<Value> old(call.getArgs());
  rewriter.replaceOp(call, fresh.getResults());
  eraseUnused(rewriter, old);
  return fresh;
}

// A raise replaces what the dispatch returns; the steps from the call's
// result to the dispatch, each the one use of the one before, go from the
// dispatch back, and the call last.
CallOp redirect(RewriterBase &rewriter, CallOp call, FlatSymbolRefAttr target, FunctionType type,
                const RaiseWant &want) {
  Operation *dispatch = want.consumer.dispatch;
  effects::Row row = call.getRow() | effects::rowOf(dispatch);
  for (Operation *step : want.consumer.steps())
    row = row | effects::rowOf(step);
  rewriter.setInsertionPoint(dispatch);
  CallOp fresh = callOf(rewriter, call.getLoc(), target, type.getResults(), call.getIndexArgsAttr(),
                        want.operands, TailKind::nontail, row);
  SmallVector<Value> old(call.getArgs());
  rewriter.replaceOp(dispatch, fresh.getResults());
  for (Operation *step : llvm::reverse(want.consumer.steps()))
    rewriter.eraseOp(step);
  rewriter.eraseOp(call);
  eraseUnused(rewriter, old);
  fresh.setTailKind(tail::decide(fresh));
  return fresh;
}

} // namespace idr::specialize::detail
