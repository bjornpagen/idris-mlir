// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Dead results, dropped once every function is final: a result no caller
// reads is not returned. What made it still runs, since evaluation is
// eager; the e-graph that runs after deletes what of it is total and
// unused.
//
// A result is read where a call gives it to anything but its caller's return,
// through what forwards it unchanged (a region's rejoin, a jump into a join
// region) and what keeps its value at other uses (a cast into or out of a
// linear position, which gives it on as the cast's result: a cast nothing
// reads reads nothing, and where its result is read the result stands, at its
// uses and with its claim); a value its caller returns at a result that is
// read is read in turn. A least fixpoint over the program's results whose
// bits only rise, so it ends by construction. The program's root keeps its
// results, which its caller outside reads, and so does a result its type uses
// exactly once (a cell, a destination, a package), whose one use is what
// fills it or gives it back. A result used once by its grade is the one
// reference its callee hands its caller, which a value used once may leave
// unused, so it is read only where its callers read it, as any result is;
// dropped, the value its return gave is unused, which counting gives up. A
// tail call's results are its caller's, so the functions tail calls join
// return one type: their results at a position are one class, read when any
// member is, dropped from every member or from none.
//
// A function that loses a result returns it no more, and each op a tail
// passes through (a match, a join group: an op a break crosses, which does
// nothing at its rejoin) whose result only that return took loses it too,
// down through what its regions yield, as the e-graph's rule for an unused
// result drops one: so a tail call that gave the result on still gives on
// exactly what it gives. Then each call of the function is made again
// without the result; where the value still stands, it reaches no return
// and nothing reads it, and it is poison.

#include "idr/Analysis/Solver/Extraction.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Joins/Rules.h"
#include "idr/Transforms/OptimizeScheduler.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/IntEqClasses.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>
#include <utility>
#include <vector>

using namespace mlir;

namespace idr::optimize {

namespace {

// A function's values by its one numbering, in walk order.
struct BodyValue {
  using Minter = solver::Numbering<BodyValue>;
};
using ValueId = BodyValue::Minter::Node;

// Which values one question about a function has followed: each value
// holds the number of the last question that followed it, so every
// question starts with none followed and nothing is cleared between them.
class Followed {
public:
  explicit Followed(FuncOp fn) : numbering(fn), last(numbering.size(), 0) {}
  void ask() { ++question; }
  // Whether this question follows `value` for the first time.
  bool first(Value value) { return std::exchange(last[numbering.at(value)], question) != question; }

private:
  solver::Numbering<BodyValue> numbering;
  IndexVector<ValueId, unsigned> last;
  unsigned question = 0;
};

// The positions of its function's return `value` reaches through what
// forwards it unchanged and what keeps its value at other uses; none when
// anything else takes it, which reads it. A loop's join regions forward a
// value around again: each is followed once in the question.
std::optional<SmallVector<unsigned, 1>> returnsOf(Value value, Followed &followed) {
  SmallVector<unsigned, 1> positions;
  SmallVector<Value> work{value};
  followed.ask();
  while (!work.empty()) {
    Value at = work.pop_back_val();
    if (!followed.first(at))
      continue;
    for (OpOperand &use : at.getUses()) {
      Operation *user = use.getOwner();
      if (isa<ReturnOp>(user)) {
        positions.push_back(use.getOperandNumber());
        continue;
      }
      // An op that keeps its operand's value (Idr_SameValue) gives it on as
      // its result, which is read where that is.
      if (user->hasTrait<SameValue>() && use.getOperandNumber() == 0) {
        work.push_back(user->getResult(0));
        continue;
      }
      bool forwarded = false;
      forwardedValues(user, [&](OpOperand &operand, Value input) {
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

// The operands `op`'s regions yield for its results that `kept` leaves
// out, by result number; what a region yields to another region is no
// result.
SmallVector<Value> yieldedFor(Operation *op, const llvm::BitVector &kept) {
  SmallVector<Value> out;
  for (Region &region : op->getRegions())
    for (Block &block : region)
      if (Operation *end = block.empty() ? nullptr : &block.back())
        forwardedValues(end, [&](OpOperand &operand, Value input) {
          auto result = dyn_cast<OpResult>(input);
          if (result && result.getOwner() == op && !kept.test(result.getResultNumber()))
            out.push_back(operand.get());
        });
  return out;
}

// Each op a break crosses whose results `released` lost their last use
// loses them, down through what its regions yield. Such an op does nothing
// at its rejoin, so its results are what its regions yield, and a result
// goes with every yield's operand for it, as the e-graph's rule for an
// unused result drops one: the ops a tail passes through, so none is left
// giving a tail call's dropped result on. An op is noted by its first
// result's number in `fn`'s numbering, made before any is rewritten: an op
// is noted only by the return or by its parent's rewrite, which comes
// first, so every op noted is one the numbering holds, and each is
// rewritten once.
void releaseRejoins(RewriterBase &rewriter, FuncOp fn, ArrayRef<Value> released) {
  solver::Numbering<BodyValue> numbering(fn);
  BitSet<ValueId> noted(numbering.size());
  SmallVector<Operation *> rejoins;
  auto note = [&](Value value) {
    Operation *def = value.getDefiningOp();
    if (def && value.use_empty() && def->hasTrait<OpTrait::PropagateControlFlowBreak>() &&
        noted.raise(numbering.at(def->getResult(0))) == Changed::Yes)
      rejoins.push_back(def);
  };
  for (Value value : released)
    note(value);
  while (!rejoins.empty()) {
    Operation *op = rejoins.pop_back_val();
    llvm::BitVector kept(op->getNumResults(), true);
    for (OpResult result : op->getResults())
      if (result.use_empty())
        kept.reset(result.getResultNumber());
    SmallVector<Value> yielded = yieldedFor(op, kept);
    control::keepResults(rewriter, op, kept);
    for (Value value : yielded)
      note(value);
  }
}

// `state` takes `call`'s properties, as the member it is: the one of
// `Members` that `call` is, read off the family's list, so the call made
// again stands where it stood.
template <CallFamily... Members>
void takeProperties(OperationState &state, FunctionCallOpInterface call) {
  ((isa<Members>(call.getOperation())
        ? (void)(state.getOrAddProperties<typename Members::Properties>() =
                     cast<Members>(call.getOperation()).getProperties())
        : (void)0),
   ...);
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
  auto calleeOf = [&](FunctionCallOpInterface call) { return graph.id(call.getCalleeAttr()); };

  // The classes: a tail call joins each of its callee's results to its
  // caller's at the same position.
  llvm::IntEqClasses joined(first.back());
  for (FunctionId self : graph.size().ids())
    if (FuncOp fn = fns[self.index()])
      fn.getBody().walk([&](TailCallOp call) {
        for (unsigned r = 0, e = call->getNumResults(); r < e; ++r)
          joined.join(slot(self, r), slot(calleeOf(call), r));
      });
  joined.compress();
  auto classOf = [&](FunctionId fn, unsigned result) { return joined[slot(fn, result)]; };

  // Read: the root's results and those a type uses exactly once, and every
  // result a call gives to anything but its caller's return; a result a
  // caller returns at a position read makes its own read.
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
      if (fn.isRoot() || isLinearByType(type))
        mark(classOf(self, static_cast<unsigned>(r)));
    Followed followed(fn);
    fn.getBody().walk([&](FunctionCallOpInterface call) {
      FunctionId callee = calleeOf(call);
      for (OpResult result : call->getResults()) {
        unsigned given = classOf(callee, result.getResultNumber());
        std::optional<SmallVector<unsigned, 1>> returns = returnsOf(result, followed);
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
    releaseRejoins(rewriter, fn, released);
  }
  // Then every call of a function that lost a result, made again without
  // it, the member it was.
  SmallVector<FunctionCallOpInterface> remade;
  for (FunctionId self : graph.size().ids()) {
    FuncOp fn = fns[self.index()];
    if (!fn)
      continue;
    SmallVector<FunctionCallOpInterface> calls;
    fn.getBody().walk([&](FunctionCallOpInterface call) {
      if (dead[calleeOf(call).index()].any())
        calls.push_back(call);
    });
    for (FunctionCallOpInterface call : calls) {
      const llvm::BitVector &bits = dead[calleeOf(call).index()];
      SmallVector<Type> kept;
      SmallVector<Attribute> keptAttrs;
      ArrayAttr resAttrs = cast<CallOpInterface>(call.getOperation()).getResAttrsAttr();
      for (OpResult result : call->getResults())
        if (!bits.test(result.getResultNumber())) {
          kept.push_back(result.getType());
          if (resAttrs)
            keptAttrs.push_back(resAttrs[result.getResultNumber()]);
        }
      rewriter.setInsertionPoint(call);
      OperationState state(call.getLoc(), call->getName(), call->getOperands(), kept,
                           call->getDiscardableAttrDictionary().getValue());
      takeProperties<
#define GET_CALLS_FAMILY_LIST
#include "idr/IR/Generated/CallsFamily.h.inc"
          >(state, call);
      auto fresh = cast<FunctionCallOpInterface>(rewriter.create(state));
      remade.push_back(fresh);
      if (resAttrs)
        cast<CallOpInterface>(fresh.getOperation())
            .setResAttrsAttr(rewriter.getArrayAttr(keptAttrs));
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
  for (FunctionCallOpInterface call : remade)
    call.copyCallee(fns[calleeOf(call).index()]);
}

} // namespace idr::optimize
