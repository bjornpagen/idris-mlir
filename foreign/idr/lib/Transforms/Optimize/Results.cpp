// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Dead results, dropped once every function is final: a result no caller
// reads is not returned. What made it still runs, since evaluation is
// eager; the e-graph that runs after deletes what of it is total and
// unused.
//
// A result is read where a call gives it to anything but its caller's
// return, through what forwards it unchanged (a region's rejoin, a jump
// into a join region); a value its caller returns at a result that is read
// is read in turn. A least fixpoint over the program's results whose bits
// only rise, so it ends by construction. The program's root keeps its
// results, which its caller outside reads, and a result of quantity one is
// read, as Idris checked. A tail call's results are its caller's, so the
// functions tail calls join return one type: their results at a position
// are one class, read when any member is, dropped from every member or
// from none.
//
// A function that loses a result returns it no more, and each match or
// join group whose result only that return took loses it too, down
// through what its regions yield, by the e-graph's own rules for an unused
// result: so a tail call that gave the result on still gives on exactly
// what it gives. Then each call of the function is made again without the
// result; where the value still stands, it reaches no return and nothing
// reads it, and it is poison.

#include "idr/IR/Control/Control.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/OptimizeScheduler.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <optional>
#include <vector>

using namespace mlir;

namespace idr::optimize {

namespace {

// The positions of its function's return `value` reaches through what
// forwards it unchanged; none when anything else takes it, which reads it.
std::optional<SmallVector<unsigned, 1>> returnsOf(Value value) {
  SmallVector<unsigned, 1> positions;
  SmallVector<Value> work{value};
  // A loop's join regions forward a value around again: each is followed
  // once.
  llvm::SmallPtrSet<void *, 8> followed;
  while (!work.empty()) {
    Value at = work.pop_back_val();
    if (!followed.insert(at.getAsOpaquePointer()).second)
      continue;
    for (OpOperand &use : at.getUses()) {
      if (isa<ReturnOp>(use.getOwner())) {
        positions.push_back(use.getOperandNumber());
        continue;
      }
      bool forwarded = false;
      forwardedValues(use.getOwner(), [&](OpOperand &operand, Value input) {
        if (&operand != &use)
          return;
        forwarded = true;
        work.push_back(input);
      });
      if (!forwarded)
        return std::nullopt;
    }
  }
  return positions;
}

// The operands `op`'s regions yield for its results that `dropped` holds.
SmallVector<Value> yieldedFor(Operation *op, const llvm::SmallPtrSetImpl<void *> &dropped) {
  SmallVector<Value> out;
  for (Region &region : op->getRegions())
    for (Block &block : region)
      if (Operation *end = block.empty() ? nullptr : &block.back())
        forwardedValues(end, [&](OpOperand &operand, Value input) {
          if (dropped.contains(input.getAsOpaquePointer()))
            out.push_back(operand.get());
        });
  return out;
}

// Each match and join group whose results `released` lost their last use
// loses them, down through what its regions yield, by the e-graph's rules
// for an unused result.
void releaseRejoins(RewriterBase &rewriter, ArrayRef<Value> released) {
  llvm::SetVector<Operation *> rejoins;
  auto note = [&](Value value) {
    Operation *def = value.getDefiningOp();
    if (def && value.use_empty() && (isa<MatchOpInterface>(def) || isa<JoinPointsOpInterface>(def)))
      rejoins.insert(def);
  };
  for (Value value : released)
    note(value);
  while (!rejoins.empty()) {
    Operation *op = rejoins.pop_back_val();
    llvm::SmallPtrSet<void *, 4> unused;
    for (OpResult result : op->getResults())
      if (result.use_empty())
        unused.insert(Value(result).getAsOpaquePointer());
    SmallVector<Value> yielded = yieldedFor(op, unused);
    if (auto match = dyn_cast<MatchOpInterface>(op))
      egraph::DeadResults::rewrite(match, egraph::Rewrite{}, rewriter);
    else
      egraph::DeadJoinResults::rewrite(cast<JoinPointsOpInterface>(op), egraph::Rewrite{}, rewriter);
    for (Value value : yielded)
      note(value);
  }
}

} // namespace

void dropDeadResults(Schedule &schedule) {
  const solver::Editor &graph = schedule.graph;
  // Every result of every function, numbered function by function in id
  // order; a gap in the ids has none.
  footprint::Vector<FuncOp> fns;
  footprint::Vector<unsigned> first{0};
  for (FunctionId id : graph.size().ids()) {
    FuncOp fn = schedule.function(id);
    fns.push_back(fn);
    first.push_back(first.back() + (fn ? fn.getNumResults() : 0));
  }
  auto slot = [&](FunctionId fn, unsigned result) { return first[fn.index()] + result; };
  auto calleeOf = [&](CallOp call) { return graph.id(call.getCalleeAttr()); };

  // The classes: a tail call joins each of its callee's results to its
  // caller's at the same position.
  llvm::IntEqClasses joined(first.back());
  for (FunctionId self : graph.size().ids())
    if (FuncOp fn = fns[self.index()])
      fn.getBody().walk([&](CallOp call) {
        if (call.getTailKind() != TailKind::tail)
          return;
        for (unsigned r = 0, e = call->getNumResults(); r < e; ++r)
          joined.join(slot(self, r), slot(calleeOf(call), r));
      });
  joined.compress();
  auto classOf = [&](FunctionId fn, unsigned result) { return joined[slot(fn, result)]; };

  // Read: the root's results and those of quantity one, and every result a
  // call gives to anything but its caller's return; a result a caller
  // returns at a position read makes its own read.
  llvm::BitVector read(joined.getNumClasses());
  footprint::Vector<SmallVector<unsigned, 1>> feeds(joined.getNumClasses());
  footprint::Vector<unsigned> work;
  auto mark = [&](unsigned c) {
    if (read.test(c))
      return;
    read.set(c);
    work.push_back(c);
  };
  for (FunctionId self : graph.size().ids()) {
    FuncOp fn = fns[self.index()];
    if (!fn)
      continue;
    for (auto [r, type] : llvm::enumerate(fn.getResultTypes()))
      if (fn.isRoot() || isLinear(type))
        mark(classOf(self, static_cast<unsigned>(r)));
    fn.getBody().walk([&](CallOp call) {
      FunctionId callee = calleeOf(call);
      for (OpResult result : call->getResults()) {
        unsigned given = classOf(callee, result.getResultNumber());
        std::optional<SmallVector<unsigned, 1>> returns = returnsOf(result);
        if (!returns) {
          mark(given);
          continue;
        }
        for (unsigned position : *returns)
          feeds[classOf(self, position)].push_back(given);
      }
    });
  }
  while (!work.empty()) {
    unsigned at = work.back();
    work.pop_back();
    for (unsigned fed : feeds[at])
      mark(fed);
  }

  // Each function's dead results.
  footprint::Vector<llvm::BitVector> dead(fns.size());
  bool any = false;
  for (FunctionId self : graph.size().ids()) {
    FuncOp fn = fns[self.index()];
    if (!fn)
      continue;
    llvm::BitVector &bits = dead[self.index()];
    bits.resize(fn.getNumResults());
    for (unsigned r = 0, e = fn.getNumResults(); r < e; ++r)
      if (!read.test(classOf(self, r)))
        bits.set(r);
    any = any || bits.any();
  }
  if (!any)
    return;

  IRRewriter rewriter(schedule.program.getContext());
  // The returns first, with what only they took.
  for (FunctionId self : graph.size().ids()) {
    FuncOp fn = fns[self.index()];
    if (!fn || dead[self.index()].none())
      continue;
    auto ret = dyn_cast<ReturnOp>(fn.getBody().front().getTerminator());
    if (!ret)
      continue;
    SmallVector<Value> released;
    for (unsigned r : dead[self.index()].set_bits())
      released.push_back(ret->getOperand(r));
    ret->eraseOperands(dead[self.index()]);
    releaseRejoins(rewriter, released);
  }
  // Then every call of a function that lost a result, made again without
  // it.
  SmallVector<CallOp> remade;
  for (FunctionId self : graph.size().ids()) {
    FuncOp fn = fns[self.index()];
    if (!fn)
      continue;
    SmallVector<CallOp> calls;
    fn.getBody().walk([&](CallOp call) {
      if (dead[calleeOf(call).index()].any())
        calls.push_back(call);
    });
    for (CallOp call : calls) {
      const llvm::BitVector &bits = dead[calleeOf(call).index()];
      SmallVector<Type> kept;
      SmallVector<Attribute> keptAttrs;
      ArrayAttr resAttrs = call.getResAttrsAttr();
      for (OpResult result : call->getResults())
        if (!bits.test(result.getResultNumber())) {
          kept.push_back(result.getType());
          if (resAttrs)
            keptAttrs.push_back(resAttrs[result.getResultNumber()]);
        }
      rewriter.setInsertionPoint(call);
      OperationState state(call.getLoc(), call->getName(), call->getOperands(), kept,
                           call->getDiscardableAttrDictionary().getValue());
      state.getOrAddProperties<CallOp::Properties>() = call.getProperties();
      auto fresh = cast<CallOp>(rewriter.create(state));
      remade.push_back(fresh);
      if (resAttrs)
        fresh.setResAttrsAttr(rewriter.getArrayAttr(keptAttrs));
      unsigned next = 0;
      for (OpResult result : call->getResults()) {
        if (!bits.test(result.getResultNumber())) {
          rewriter.replaceAllUsesWith(result, fresh->getResult(next++));
          continue;
        }
        if (!result.use_empty())
          rewriter.replaceAllUsesWith(
              result, ub::PoisonOp::create(rewriter, call.getLoc(), result.getType()).getResult());
      }
      rewriter.eraseOp(call);
    }
  }
  // The signatures, each erased result taking what the signature states of
  // it; then each call made again takes its callee's statements again.
  for (FunctionId self : graph.size().ids()) {
    FuncOp fn = fns[self.index()];
    if (!fn || dead[self.index()].none())
      continue;
    (void)fn.eraseResults(dead[self.index()]);
  }
  for (CallOp call : remade)
    call.copyCallee(fns[calleeOf(call).index()]);
}

} // namespace idr::optimize
