// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Accumulate.cpp - idr-accumulate ------------------------------------===//
//
// A self call whose result a tail position adds becomes a tail call that
// carries the sum: the function seeds a clone with zero, and the clone adds
// before it calls itself. idr-tail-loops makes the clone a loop, and the
// sum is a value of the iteration, not a frame. A tail that returns a value
// adds the sum to it; a tail that is already a self call passes the sum on.
// Counting borrows a call's result and drops it after the addition, so this
// runs first, while the result is still what the tail adds.
//
// The pass stays at the module: each clone is a new symbol in the module's
// block, which no pass on one function may add. It plans and rewrites one
// function at a time, in module order, and enters each clone in the table
// it holds.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Tail.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"

namespace idr {
#define GEN_PASS_DEF_IDRACCUMULATE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// A call of `clone` in place of `call`, with `carried` after its arguments.
// The clone is the same recursion with the same facts, so the call keeps
// what the old one may do.
CallOp retarget(RewriterBase &rewriter, CallOp call, FuncOp clone, Value carried) {
  SmallVector<Value> args(call.getArgs());
  args.push_back(carried);
  auto neu = CallOp::create(rewriter, call.getLoc(), clone.getResultTypes(),
                            FlatSymbolRefAttr::get(clone.getSymNameAttr()), args,
                            /*arg_attrs=*/ArrayAttr(), call.getResAttrsAttr(), call.getEffectsAttr());
  neu->setDiscardableAttrs(call->getDiscardableAttrDictionary());
  return neu;
}

// The clone's tails, whose ops `mapping` gives for `sites` of the
// function: an addition becomes the sum carried into the call, which takes
// the addition's place at the tail, and a tail that returns a value adds
// the sum to it. Zero, the identity, is the sum itself.
void rewriteClone(RewriterBase &rewriter, FuncOp clone, ArrayRef<Site> sites, const IRMapping &mapping, Value acc) {
  for (Site site : sites) {
    auto call = cast<CallOp>(mapping.lookup(site.call.getOperation()));
    if (!site.add) {
      rewriter.setInsertionPoint(call);
      rewriter.replaceOp(call, retarget(rewriter, call, clone, acc).getOperation());
      continue;
    }
    auto add = cast<BigAddOp>(mapping.lookup(site.add.getOperation()));
    rewriter.setInsertionPoint(add);
    auto sum = BigAddOp::create(rewriter, add.getLoc(), add.getResult().getType(), acc, mapping.lookup(site.addend));
    rewriter.setInsertionPointAfter(sum);
    CallOp neu = retarget(rewriter, call, clone, sum.getResult());
    // The call's place was before the addition; its result had no other use.
    rewriter.replaceOp(add, neu.getOperation());
    rewriter.eraseOp(call);
  }

  SmallVector<Block *> tails;
  forTails(clone.getBody().front(), [&](Block &block) { tails.push_back(&block); });
  for (Block *block : tails) {
    Operation *terminator = block->getTerminator();
    if (!isa<ReturnOp, YieldOp>(terminator) || terminator->getNumOperands() != 1)
      continue;
    Value value = terminator->getOperand(0);
    if (isSelfCall(value.getDefiningOp(), clone))
      continue;
    if (isZero(value)) {
      rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperand(0, acc); });
      if (Operation *def = value.getDefiningOp(); def && def->use_empty())
        rewriter.eraseOp(def);
      continue;
    }
    rewriter.setInsertionPoint(terminator);
    auto sum = BigAddOp::create(rewriter, terminator->getLoc(), acc.getType(), acc, value);
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperand(0, sum.getResult()); });
  }
}

struct Accumulate : impl::IdrAccumulateBase<Accumulate> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = module.getContext();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    IRRewriter rewriter(ctx);
    bool changed = false;
    for (FuncOp fn : llvm::make_early_inc_range(module.getOps<FuncOp>())) {
      if (isCountdown(fn)) {
        returnArgument(fn, rewriter);
        changed = true;
        continue;
      }
      SmallVector<Site> sites = accumulatorSites(fn);
      if (sites.empty())
        continue;
      changed = true;
      Type result = fn.getResultTypes()[0];
      IRMapping mapping;
      auto clone = cast<FuncOp>(fn->clone(mapping));
      clone.setSymName((fn.getSymName() + ".acc").str());
      clone.setPrivate();
      clone.removeCloneAttr();
      (void)clone.insertArgument(clone.getNumArguments(), result, DictionaryAttr(), fn.getLoc());
      symbols.insert(clone, std::next(fn->getIterator()));
      rewriteClone(rewriter, clone, sites, mapping, clone.getArguments().back());

      ++numFunctions;
      numTails +=
          static_cast<uint64_t>(llvm::count_if(sites, [](const Site &site) { return static_cast<bool>(site.add); }));

      // The old body computed the sum on the way back; it goes now that the
      // clone holds its copy.
      Block &entry = fn.getBody().front();
      clearBlock(rewriter, entry);
      rewriter.setInsertionPointToStart(&entry);
      Value zero = ConstantOp::create(rewriter, fn.getLoc(), result, BigAttr::get(ctx, "0"));
      SmallVector<Value> args(entry.getArguments());
      args.push_back(zero);
      auto call = CallOp::create(rewriter, fn.getLoc(), fn.getResultTypes(),
                                 FlatSymbolRefAttr::get(clone.getSymNameAttr()), args,
                                 /*arg_attrs=*/ArrayAttr(), /*res_attrs=*/ArrayAttr(), fn.getEffectsAttr());
      ReturnOp::create(rewriter, fn.getLoc(), call.getResults());
    }
    if (!changed)
      return markAllAnalysesPreserved();
    markAnalysesPreserved<SymbolTable, Holds, TypeGraph, Layouts>();
  }
};

} // namespace
} // namespace idr::tail
