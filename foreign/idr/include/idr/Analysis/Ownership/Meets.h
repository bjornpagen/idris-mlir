// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a value graded with a stronger sharing claim meets a position that
// takes a weaker one (a call's parameter, a function's result, a region's
// input), it is shared into it by idr.count.share, the one way a claim goes
// down. An op of upstream's reads a loan (idr.carrier), never the value at
// its grade, so it is no such position.
// The passes that write a claim into the types (idr-in-place, the commit of
// idr-rc-exclusive) write it where it is proved, then meet every position
// once; a position that asks more than its value has is the writer's bug,
// which the verifier after the pass reports.
#ifndef IDR_ANALYSIS_OWNERSHIP_MEETS_H
#define IDR_ANALYSIS_OWNERSHIP_MEETS_H

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/SmallVector.h"

#include <cassert>
#include <concepts>
#include <type_traits>
#include <utility>

namespace idr::ownership {

// `use` shared into `slot`, when its value claims more of its sharing than
// the slot takes.
inline void shareInto(mlir::RewriterBase &rewriter, mlir::OpOperand &use, mlir::Type slot) {
  mlir::Type type = use.get().getType();
  std::optional<Hold> held = holdOf(type);
  std::optional<Hold> taken = holdOf(slot);
  if (type == slot || !held || !taken || taken->claims(held->claim()))
    return;
  mlir::Operation *owner = use.getOwner();
  rewriter.setInsertionPoint(owner);
  mlir::Value shared = CountShareOp::create(rewriter, owner->getLoc(), slot, use.get());
  rewriter.modifyOpInPlace(owner, [&] { use.set(shared); });
}

// Each use `edges` move whole, with its reference, into a slot of a
// function's signature, a parameter or a result of a function by name, with
// that slot: a call's argument, which the call moves into its callee's
// parameter, and a return's operand, which it moves into its own function's
// result. A capture moves only its labels into its label's parameter and
// its reference into its closure's cell, so it is neither.
template <typename OnParameter, typename OnResult>
  requires std::invocable<OnParameter &, mlir::OpOperand &, const FlowSource::Parameter &> &&
           std::invocable<OnResult &, mlir::OpOperand &, const FlowSource::Result &>
void forEachSignatureMove(const FlowEdges &edges, OnParameter &&onParameter,
                          OnResult &&onResult) {
  for (const FlowEdges::Edge &edge : edges.edges()) {
    if (!edge.carries(Carrier::Reference))
      continue;
    idr::match(
        edge.move,
        [&](const FlowEdges::Flow &flow) {
          idr::match(
              flow.from.at,
              [&](const FlowSource::Taken &taken) {
                idr::match(
                    flow.to.at,
                    [&](const FlowSource::Parameter &parameter) {
                      onParameter(*taken.use, parameter);
                    },
                    [&](const FlowSource::Result &result) { onResult(*taken.use, result); },
                    [](const OneOf<FlowSource::Whole, FlowPlace::Part> auto &) {});
              },
              [](const NotTaken auto &) {});
        },
        [](const NoFlow auto &) {});
  }
}

// Every position of `fn` met: each use an op's flow edges move into a slot
// of a function's signature (forEachSignatureMove), with the slot's type, a
// parameter's of the function `calleeOf` names and a result's of `fn`; and
// each value a region branch or a jump forwards with the input it becomes.
// Found first and met after, as a meeting adds a use.
template <typename CalleeOf>
  requires std::is_invocable_r_v<FuncOp, CalleeOf &, mlir::FlatSymbolRefAttr>
void shareIntoPositions(FuncOp fn, CalleeOf &&calleeOf) {
  llvm::SmallVector<std::pair<mlir::OpOperand *, mlir::Type>> positions;
  FlowEdges edges;
  fn.walk([&](mlir::Operation *op) {
    if (auto declared = llvm::dyn_cast<FlowOpInterface>(op)) {
      edges.clear();
      declared.getFlowEdges(edges);
      forEachSignatureMove(
          edges,
          [&](mlir::OpOperand &use, const FlowSource::Parameter &parameter) {
            positions.emplace_back(
                &use, calleeOf(parameter.function).getArgumentTypes()[parameter.index]);
          },
          [&](mlir::OpOperand &use, const FlowSource::Result &result) {
            assert(result.function.getAttr() == fn.getSymNameAttr() &&
                   "a return moves into its own function's results");
            positions.emplace_back(&use, fn.getResultTypes()[result.index]);
          });
    }
    forwardedValues(op, [&](mlir::OpOperand &operand, mlir::Value input) {
      positions.emplace_back(&operand, input.getType());
    });
  });
  mlir::IRRewriter rewriter(fn.getContext());
  for (auto [use, slot] : positions)
    shareInto(rewriter, *use, slot);
}

} // namespace idr::ownership

#endif // IDR_ANALYSIS_OWNERSHIP_MEETS_H
