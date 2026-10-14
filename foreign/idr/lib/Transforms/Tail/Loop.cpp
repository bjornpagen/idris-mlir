// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Loop.cpp - The general loop: a payload at every tail position ------===//
//
// A function with a self tail call whose body is not a decision becomes
// one scf.while over its arguments A whose before region is the old body.
// Every tail position of the body then yields a payload (continue : i1,
// A, R):
//   - a self tail call yields (true, its arguments, poison R);
//   - any other result yields (false, poison A, the results R);
// the matches on the way yield the payload of their regions, and the
// region ends in scf.condition(continue) A, R. The after region passes A
// back to the before region, and the function returns the R of the loop's
// results.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/Canon.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace idr::tail {
namespace {

struct Loop {
  FuncOp fn;
  TypeRange args;
  TypeRange results;
  RewriterBase &rewriter;

  // What a payload carries in the places the path that yields it does not
  // read: a ub.poison, a value of the program, which may be any value of
  // its type, as upstream passes one where an operand goes unread.
  SmallVector<Value> poison(Location loc, TypeRange types) {
    return llvm::map_to_vector(
        types, [&](Type type) -> Value { return ub::PoisonOp::create(rewriter, loc, type); });
  }

  Value flag(Location loc, bool value) {
    return arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(value));
  }

  // The types of a payload: (continue, A, R).
  SmallVector<Type> payloadTypes() {
    SmallVector<Type> types{rewriter.getI1Type()};
    llvm::append_range(types, args);
    llvm::append_range(types, results);
    return types;
  }

  // Ends `block` with `payload` in place of its terminator: the loop's
  // condition where the function returned, a yield in a match's region.
  void end(Block &block, ValueRange payload) {
    Operation *terminator = block.getTerminator();
    rewriter.setInsertionPoint(terminator);
    if (isa<ReturnOp>(terminator))
      scf::ConditionOp::create(rewriter, terminator->getLoc(), payload.front(), payload.drop_front());
    else
      YieldOp::create(rewriter, terminator->getLoc(), payload);
    rewriter.eraseOp(terminator);
  }

  // Makes `block`, which ends in a tail position, end in that position's
  // payload. A match in tail position on the way to a self call yields the
  // payload of its regions; one that ends in ub.unreachable yields nothing.
  void rewriteTail(Block &block) {
    Operation *terminator = block.getTerminator();
    Location loc = terminator->getLoc();
    Operation *prev = passesOnPrevious(terminator) ? terminator->getPrevNode() : nullptr;
    if (prev && isSelfCall(prev, fn)) {
      rewriter.setInsertionPoint(prev);
      SmallVector<Value> payload{flag(loc, true)};
      llvm::append_range(payload, prev->getOperands());
      llvm::append_range(payload, poison(loc, results));
      end(block, payload);
      rewriter.eraseOp(prev);
      return;
    }
    if (prev && isTailMatch(prev) && reachesTailCall(block, fn)) {
      Operation *match = canon::rebuildMatch(rewriter, prev, payloadTypes());
      for (Region &region : match->getRegions())
        if (!region.empty() && isa<YieldOp>(region.front().getTerminator()))
          rewriteTail(region.front());
      end(block, match->getResults());
      rewriter.eraseOp(prev);
      return;
    }
    rewriter.setInsertionPoint(terminator);
    SmallVector<Value> payload{flag(loc, false)};
    llvm::append_range(payload, poison(loc, args));
    llvm::append_range(payload, terminator->getOperands());
    end(block, payload);
  }

  scf::WhileOp build() {
    Block &entry = fn.getBody().front();
    Location loc = fn.getLoc();
    SmallVector<Type> carried(args);
    llvm::append_range(carried, results);
    rewriter.setInsertionPointToStart(&entry);
    auto loop = scf::WhileOp::create(rewriter, loc, carried, entry.getArguments());
    Block *before = rewriter.createBlock(&loop.getBefore(), {}, args,
                                         llvm::map_to_vector(entry.getArguments(), [](BlockArgument arg) {
                                           return arg.getLoc();
                                         }));
    // The body moves into the before region and reads its arguments; only
    // the loop reads the function's, as its initial values.
    Block *body = rewriter.splitBlock(&entry, std::next(loop->getIterator()));
    rewriter.mergeBlocks(body, before);
    for (auto [old, now] : llvm::zip_equal(entry.getArguments(), before->getArguments()))
      rewriter.replaceUsesWithIf(old, now, [&](OpOperand &use) { return use.getOwner() != loop; });
    rewriteTail(*before);
    if (!fn.getTotal()) {
      rewriter.setInsertionPointToStart(before);
      MayLoopOp::create(rewriter, loc);
    }

    Block *after = rewriter.createBlock(&loop.getAfter(), {}, carried, SmallVector<Location>(carried.size(), loc));
    scf::YieldOp::create(rewriter, loc, after->getArguments().take_front(args.size()));
    rewriter.setInsertionPointToEnd(&entry);
    ReturnOp::create(rewriter, loc, loop.getResults().drop_front(args.size()));
    return loop;
  }
};

} // namespace

scf::WhileOp generalLoop(FuncOp fn, RewriterBase &rewriter) {
  return Loop{fn, fn.getArgumentTypes(), fn.getResultTypes(), rewriter}.build();
}

} // namespace idr::tail
