// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Trmc.cpp - idr-trmc ------------------------------------------------===//
//
// A self call whose result is a field of the boxed constructor a tail
// position returns becomes a tail call that writes the field.
//
// `copy (Cons x xs) = Cons x (copy xs)` returns through every level of
// the list. The constructor can be built before the call, with the field a
// hole, and the call given the hole's destination (`!idr.dest`), which the
// constructor gives, to write once it has its value; then the call is the
// last thing the tail does. The function keeps its signature and does that for its first
// level only: each such tail builds its constructor, calls a clone with
// the destination and returns the constructor. The clone takes a
// destination and returns nothing: a tail of its own that builds a
// constructor around a self call writes the constructor to the
// destination it was given and calls itself with the new one, a plain self
// tail call passes the destination on, and any other tail writes its
// value. idr-tail-loops then makes the clone a loop, and the structure is
// written top down in constant stack. A self call in any other position
// (one whose result is inspected, as a rebalancing insert inspects its
// subtree) stays a call of the function, and the stack grows with it, as
// it must.
//
// The pass stays at the program: each clone is a new symbol in the
// program's block, which no pass on one function may add. It goes right
// after its function, under a name made from the function's and the kind
// `trmc`, so no order reaches the name.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Tail.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"

namespace idr {
#define GEN_PASS_DEF_IDRTRMC
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// A call of `clone` with `operands`, in place of `old`: the clone is the
// same recursion with the same facts, so the call does what the old one
// did.
void callClone(RewriterBase &rewriter, CallOp old, FuncOp clone, ValueRange operands) {
  auto call = CallOp::create(rewriter, old.getLoc(), clone, operands);
  call->setDiscardableAttrs(old->getDiscardableAttrDictionary());
}

// The terminator of `block` with no operands, in place of the one it has.
void endWithNothing(RewriterBase &rewriter, Block &block) {
  Operation *terminator = block.getTerminator();
  rewriter.setInsertionPoint(terminator);
  if (isa<ReturnOp>(terminator))
    ReturnOp::create(rewriter, terminator->getLoc(), ValueRange());
  else
    YieldOp::create(rewriter, terminator->getLoc(), ValueRange());
  rewriter.eraseOp(terminator);
}

// The constructor `built` builds, again, with its field `index` a hole:
// the same tag, the fields it was given but that one, and the hole's
// destination.
Operation *withHole(RewriterBase &rewriter, Operation *built, unsigned index) {
  SmallVector<Value> fields;
  SmallVector<int32_t> holes{static_cast<int32_t>(index)};
  auto rebuild = [&](auto op) {
    for (auto [at, given] : llvm::enumerate(op.getFields()))
      if (at != index)
        fields.push_back(given);
    return static_cast<unsigned>(op.getTag());
  };
  rewriter.setInsertionPoint(built);
  if (auto con = dyn_cast<ConOp>(built)) {
    unsigned tag = rebuild(con);
    return ConOp::create(rewriter, con.getLoc(), con.getResult().getType(), tag, fields, holes,
                         con.getStack());
  }
  auto reuse = cast<ReuseOp>(built);
  unsigned tag = rebuild(reuse);
  return ReuseOp::create(rewriter, reuse.getLoc(), reuse.getResult().getType(), reuse.getToken(),
                         tag, fields, holes);
}

// The destination-passing form of one tail: the constructor built with
// the field a hole, the cell written to `hole` when there is one (in the
// clone), and the hole's destination passed to the clone in the call's
// place after it. The constructor gives the destination as it builds the
// cell, whose reference then moves on: into the hole it fills, or out of
// the function.
void passDestination(RewriterBase &rewriter, const Modulo &tail, FuncOp clone, Value hole) {
  CallOp call = tail.call;
  Location loc = call.getLoc();
  Operation *rebuilt = withHole(rewriter, tail.built, tail.index);
  Value cell = rebuilt->getResult(0);
  Value dest;
  if (auto con = dyn_cast<ConOp>(rebuilt))
    dest = con.getDest(tail.index);
  else
    dest = cast<ReuseOp>(rebuilt).getDest(tail.index);
  // The tail returns the cell alone, so the constructor had no hole.
  rewriter.replaceAllUsesWith(tail.built->getResult(0), cell);
  rewriter.eraseOp(tail.built);
  for (Operation *grade : tail.grades)
    rewriter.eraseOp(grade);
  rewriter.setInsertionPointAfter(rebuilt);
  if (hole)
    DestWriteOp::create(rewriter, loc, hole, cell);
  SmallVector<Value> operands(call.getArgs());
  operands.push_back(dest);
  callClone(rewriter, call, clone, operands);
  rewriter.eraseOp(call);
}

// Rewrites the tails of `block` in the clone, which returns nothing:
// each writes what it would have returned to `hole`, or passes it on. A
// match in tail position then yields nothing, and so has no results.
void rewriteClone(RewriterBase &rewriter, Block &block, FuncOp fn, FuncOp clone, Value hole) {
  Operation *terminator = block.getTerminator();
  if (Operation *match = tailMatch(terminator)) {
    Operation *rebuilt = canon::rebuildMatch(rewriter, match, TypeRange());
    for (Region &region : rebuilt->getRegions())
      if (!region.empty())
        rewriteClone(rewriter, region.front(), fn, clone, hole);
    endWithNothing(rewriter, block);
    rewriter.eraseOp(match);
    return;
  }
  if (std::optional<Modulo> tail = moduloAt(block, fn)) {
    passDestination(rewriter, *tail, clone, hole);
    endWithNothing(rewriter, block);
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

struct Trmc : impl::IdrTrmcBase<Trmc> {
  void runOnOperation() override {
    ProgramOp program = getOperation();
    MLIRContext *ctx = program.getContext();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    IRRewriter rewriter(ctx);
    bool changed = false;
    for (FuncOp fn : llvm::make_early_inc_range(program.getOps<FuncOp>())) {
      if (fn.getNumResults() != 1 || !isa<BoxType>(unrestricted(fn.getResultTypes()[0])))
        continue;
      SmallVector<Modulo> tails;
      forTails(fn.getBody().front(), [&](Block &block) {
        if (std::optional<Modulo> tail = moduloAt(block, fn))
          tails.push_back(*tail);
      });
      if (tails.empty())
        continue;
      FailureOr<StringAttr> name = copyName(fn, "trmc", symbols);
      if (failed(name))
        return signalPassFailure();
      changed = true;
      ++numFunctions;
      numTails += tails.size();

      FuncOp clone = fn.clone();
      clone.setSymNameAttr(*name);
      symbols.insert(clone, std::next(fn->getIterator()));
      auto dest = DestType::get(ctx, unrestricted(fn.getResultTypes()[0]));
      unsigned arity = clone.getNumArguments();
      (void)clone.insertArgument(arity, dest, DictionaryAttr(), fn.getLoc());
      (void)clone.eraseResult(0);
      rewriteClone(rewriter, clone.getBody().front(), fn, clone, clone.getArgument(arity));

      for (const Modulo &tail : tails)
        passDestination(rewriter, tail, clone, Value());
    }
    if (!changed)
      return markAllAnalysesPreserved();
    markAnalysesPreserved<SymbolTable, Holds, TypeGraph, Layouts>();
  }
};

} // namespace
} // namespace idr::tail
