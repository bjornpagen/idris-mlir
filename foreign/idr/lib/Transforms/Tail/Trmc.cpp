// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Trmc.cpp - idr-trmc ------------------------------------------------===//
//
// A self call whose result is a field of the boxed constructor a tail
// position returns becomes a tail call that writes the field.
//
// `copy (Cons x xs) = Cons x (copy xs)` returns through every level of
// the list. The constructor can be built before the call, with the field
// pending, and the call given the field as a destination (`!idr.dest`) to
// write once it has its value; then the call is the last thing the tail
// does. The function keeps its signature and does that for its first
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
// The pass stays at the module: each clone is a new symbol in the module's
// block, which no pass on one function may add.
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

SymbolRefAttr ctorOf(Operation *op) {
  if (auto con = dyn_cast<ConOp>(op))
    return con.getCtor();
  return cast<ReuseOp>(op).getCtor();
}

// A call of `clone` with `operands`, in place of `old`: the clone is the
// same recursion with the same facts, so the call keeps what the old one
// may do.
void callClone(RewriterBase &rewriter, CallOp old, FuncOp clone, ValueRange operands) {
  auto call = CallOp::create(rewriter, old.getLoc(), TypeRange(), FlatSymbolRefAttr::get(clone.getSymNameAttr()),
                             operands, /*arg_attrs=*/ArrayAttr(), /*res_attrs=*/ArrayAttr(), old.getEffectsAttr());
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

// The destination-passing form of one tail: the constructor built with
// the field pending, the cell written to `hole` when there is one (in the
// clone), and the field's destination passed to the clone in the call's
// place after it. The cell is written after its own destination is taken:
// writing consumes the cell's reference.
void passDestination(RewriterBase &rewriter, const Modulo &tail, FuncOp clone, Value hole) {
  CallOp call = tail.call;
  Location loc = call.getLoc();
  Value cell = tail.built->getResult(0);
  rewriter.setInsertionPoint(tail.built);
  Value pending = PendingOp::create(rewriter, loc, tail.field->get().getType());
  rewriter.modifyOpInPlace(tail.built, [&] { tail.field->set(pending); });
  for (Operation *grade : tail.grades)
    rewriter.eraseOp(grade);
  rewriter.setInsertionPointAfter(tail.built);
  // The destination is taken from a view of the cell, whose reference
  // then moves on: into the hole it fills, or out of the function.
  Value seen = BorrowOp::create(rewriter, loc, cell);
  Value dest = DestOfOp::create(rewriter, loc, DestType::get(rewriter.getContext(), unrestricted(pending.getType())),
                                seen, FlatSymbolRefAttr::get(ctorOf(tail.built).getLeafReference()),
                                rewriter.getI64IntegerAttr(tail.index));
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
    ModuleOp module = getOperation();
    MLIRContext *ctx = module.getContext();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    IRRewriter rewriter(ctx);
    bool changed = false;
    for (FuncOp fn : llvm::make_early_inc_range(module.getOps<FuncOp>())) {
      if (fn.isExternal() || fn.getNumResults() != 1 || !isa<BoxType>(unrestricted(fn.getResultTypes()[0])))
        continue;
      SmallVector<Modulo> tails;
      forTails(fn.getBody().front(), [&](Block &block) {
        if (std::optional<Modulo> tail = moduloAt(block, fn))
          tails.push_back(*tail);
      });
      if (tails.empty())
        continue;
      changed = true;
      ++numFunctions;
      numTails += tails.size();

      FuncOp clone = fn.clone();
      clone.setSymName((fn.getSymName() + ".trmc").str());
      clone.setPrivate();
      clone.removeCloneAttr();
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
