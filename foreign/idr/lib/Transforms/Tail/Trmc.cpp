// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Trmc.cpp - idr-trmc ------------------------------------------------===//
//
// A self call whose result the value a tail position returns holds, in a
// context that nothing else reaches, becomes a tail call that writes it.
//
// `copy (Cons x xs) = Cons x (copy xs)` returns through every level of
// the list. The constructor can be built before the call, with the field a
// hole, and the call given the hole's destination (`!idr.dest`), which the
// constructor gives, to write once it has its value; then the call is the
// last thing the tail does. So can every cell the returned value holds the
// first one in (`dup (x :: xs) = x :: x :: dup xs`, `traverse_`'s action
// of the rest inside the actions that run it), and across a join, where
// each region builds its own holed cell and gives its destination as one
// more result of the match (contextAt). The function keeps its signature
// and does that for its first level only: each such tail builds its value,
// calls a clone with the destination and returns the value. The clone
// takes a destination and returns nothing: a tail of its own that builds a
// context around a self call writes the value to the destination it was
// given and calls itself with the new one, a plain self tail call passes
// the destination on, and any other tail writes its value. idr-tail-loops
// then makes the clone a loop, and the structure is written top down in
// constant stack. A self call in any other position (one whose result is
// inspected, as a rebalancing insert inspects its subtree) stays a call of
// the function, and the stack grows with it, as it must.
//
// The pass stays at the program: each clone is a new symbol in the
// program's block, which no pass on one function may add. It goes right
// after its function, under a name made from the function's and the kind
// `trmc`, so no order reaches the name.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/Tail.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Actions.h"
#include "idr/Support/Remake.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Sequence.h"

namespace idr {
#define GEN_PASS_DEF_IDRTRMC
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// idr-trmc gives one function its destination-passing clone; the unit is
// the function.
struct TrmcCloneAction : support::TaggedAction<TrmcCloneAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-trmc-clone";
};

// A call of `clone` with `operands`, in place of `old`: the clone is the
// same recursion with the same facts, so the call does what the old one
// did.
void callClone(RewriterBase &rewriter, CallOp old, FuncOp clone, ValueRange operands) {
  auto call = CallOp::create(rewriter, old.getLoc(), clone, operands);
  call->setDiscardableAttrs(old->getDiscardableAttrDictionary());
}

// The terminator of `block`, an idr.return or a match's idr.yield, with no
// operands.
void endWithNothing(RewriterBase &rewriter, Block &block) {
  Operation *terminator = block.getTerminator();
  rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperands(ValueRange()); });
}

// The box `built` writes into its cell, again, with its field `index` a
// hole: the same cell, the fields it was given but that one, and the
// hole's destination. The box keeps the grade counting gave it.
CellInitOp withHole(RewriterBase &rewriter, CellInitOp built, unsigned index) {
  rewriter.setInsertionPoint(built);
  SmallVector<Value> fields;
  for (auto [at, given] : llvm::enumerate(built.getFields()))
    if (at != index)
      fields.push_back(given);
  return CellInitOp::create(rewriter, built.getLoc(), built.getResult().getType(), built.getCell(),
                            fields, {static_cast<int32_t>(index)});
}

// The destination-passing form of one tail: each holed cell built with the
// field a hole, each join giving its region's destination as one more
// result, and at the end of the tail, once the value it returns is built,
// that value written to `hole`, the clone's own, when there is one (the
// function's first level has none: it returns the value), and the one
// destination that arrives passed to the clone in the call's place. Each
// cell gives its destination as it is built, and its reference then moves
// on: into the hole it fills, or out of the function.
void passDestination(RewriterBase &rewriter, const Context &tail, FuncOp clone,
                     std::optional<Value> hole) {
  CallOp call = tail.call;
  Location loc = call.getLoc();
  llvm::DenseMap<Block *, Value> dests;
  Type destType;
  for (Hole each : tail.holes) {
    CellInitOp holed = withHole(rewriter, each.init, each.index);
    rewriter.replaceAllUsesWith(each.init.getResult(), holed.getResult());
    rewriter.eraseOp(each.init);
    Value dest = holed.getDest(each.index);
    destType = dest.getType();
    dests[holed->getBlock()] = dest;
  }
  for (Operation *grade : llvm::reverse(tail.grades))
    rewriter.eraseOp(grade);
  for (Operation *join : tail.joins) {
    for (Region &region : join->getRegions()) {
      if (region.empty())
        continue;
      Operation *yield = region.front().getTerminator();
      Value dest = dests.at(&region.front());
      rewriter.modifyOpInPlace(yield,
                               [&] { yield->insertOperands(yield->getNumOperands(), dest); });
    }
    SmallVector<Type> results(join->getResultTypes());
    results.push_back(destType);
    Operation *made = remakeOp(rewriter, join, join->getOperands(), results);
    rewriter.replaceOp(join, made->getResults().drop_back());
    dests[made->getBlock()] = made->getResults().back();
  }
  Block &block = *call->getBlock();
  Operation *terminator = block.getTerminator();
  rewriter.setInsertionPoint(terminator);
  if (hole)
    DestWriteOp::create(rewriter, loc, *hole, terminator->getOperand(0));
  SmallVector<Value> operands(call.getArgs());
  operands.push_back(dests.at(&block));
  callClone(rewriter, call, clone, operands);
  rewriter.eraseOp(call);
}

// Rewrites the tails of `block` in the clone, which returns nothing:
// each writes what it would have returned to `hole`, or passes it on. A
// match in tail position then yields nothing, and so has no results.
void rewriteClone(RewriterBase &rewriter, Block &block, FuncOp fn, FuncOp clone, Value hole) {
  // A context the block's own (one whose holes are in the regions of the
  // match in tail position, which is then its join) comes before the
  // contexts of those regions.
  if (std::optional<Context> tail = contextAt(block, fn)) {
    passDestination(rewriter, *tail, clone, hole);
    endWithNothing(rewriter, block);
    return;
  }
  Operation *terminator = block.getTerminator();
  if (Operation *tailOp = tailMatch(terminator)) {
    // The match keeps every region and yields nothing.
    auto match = cast<MatchOpInterface>(tailOp);
    rewriter.setInsertionPoint(tailOp);
    Operation *rebuilt = match.rebuild(rewriter, TypeRange(),
                                       llvm::to_vector(llvm::seq(match.getNumCases())),
                                       &match.getDefaultRegion());
    // An exhaustive match's default region is empty: it holds no tail.
    for (Region &region : rebuilt->getRegions())
      if (!region.empty())
        rewriteClone(rewriter, region.front(), fn, clone, hole);
    endWithNothing(rewriter, block);
    rewriter.eraseOp(tailOp);
    return;
  }
  if (!isa<ReturnOp, YieldOp>(terminator))
    return;
  if (Operation *prev = terminator->getPrevNode(); passesOnPrevious(terminator) && isSelfCall(prev, fn)) {
    auto call = cast<CallOp>(prev);
    SmallVector<Value> operands(call.getArgs());
    operands.push_back(hole);
    rewriter.setInsertionPoint(call);
    callClone(rewriter, call, clone, operands);
    endWithNothing(rewriter, block);
    rewriter.eraseOp(call);
    return;
  }
  rewriter.setInsertionPoint(terminator);
  DestWriteOp::create(rewriter, terminator->getLoc(), hole, terminator->getOperand(0));
  endWithNothing(rewriter, block);
}

// The tails modulo a context of `block`, which ends in a tail position: its
// own, when it has one, else those of the regions of the match in tail
// position it ends with, as rewriteClone finds them.
void contextsOf(Block &block, FuncOp fn, SmallVectorImpl<Context> &tails) {
  if (std::optional<Context> tail = contextAt(block, fn)) {
    tails.push_back(*tail);
    return;
  }
  if (Operation *match = tailMatch(block.getTerminator()))
    for (Region &region : match->getRegions())
      if (!region.empty())
        contextsOf(region.front(), fn, tails);
}

// A function whose result a tail builds around a self call: those tails,
// and the name of the clone that writes them top down.
struct Plan {
  FuncOp fn;
  SmallVector<Context> tails;
  StringAttr name;
};

// The plan of `fn`; none when no tail of it builds a box around a self
// call, failure when its clone's name is taken.
FailureOr<std::optional<Plan>> planOf(FuncOp fn, SymbolTable &symbols) {
  if (fn.getNumResults() != 1 || !isa<BoxType>(unrestricted(fn.getResultTypes()[0])))
    return std::optional<Plan>();
  SmallVector<Context> tails;
  contextsOf(fn.getBody().front(), fn, tails);
  if (tails.empty())
    return std::optional<Plan>();
  FailureOr<StringAttr> name = copyName(fn, "trmc", symbols);
  if (failed(name))
    return failure();
  return std::optional<Plan>(Plan{fn, std::move(tails), *name});
}

struct Trmc : impl::IdrTrmcBase<Trmc> {
  void runOnProgram(ProgramOp program) override {
    MLIRContext *ctx = program.getContext();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    // Every function is planned on the program as it stands, before any
    // changes: a plan reads its own function alone.
    SmallVector<Plan> plans;
    for (FuncOp fn : program.getOps<FuncOp>()) {
      FailureOr<std::optional<Plan>> plan = planOf(fn, symbols);
      if (failed(plan))
        return signalPassFailure();
      if (*plan)
        plans.push_back(std::move(**plan));
    }
    IRRewriter rewriter(ctx);
    unsigned performed = 0;
    for (const Plan &plan : plans) {
      FuncOp fn = plan.fn;
      performed += support::perform<TrmcCloneAction>(fn, [&] {
        ++numFunctions;
        numTails += plan.tails.size();
        FuncOp clone = fn.clone();
        clone.setSymNameAttr(plan.name);
        symbols.insert(clone, std::next(fn->getIterator()));
        auto dest = DestType::get(ctx, cast<BoxType>(unrestricted(fn.getResultTypes()[0])));
        unsigned arity = clone.getNumArguments();
        (void)clone.insertArgument(arity, dest, DictionaryAttr(), fn.getLoc());
        (void)clone.eraseResult(0);
        rewriteClone(rewriter, clone.getBody().front(), fn, clone, clone.getArgument(arity));
        for (const Context &tail : plan.tails)
          passDestination(rewriter, tail, clone, std::nullopt);
      });
    }
    if (performed == 0)
      return markAllAnalysesPreserved();
    markAnalysesPreserved<SymbolTable, TypeGraph, Layouts>();
  }
};

} // namespace
} // namespace idr::tail
