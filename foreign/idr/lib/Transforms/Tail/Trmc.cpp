// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Trmc.cpp - idr-trmc ------------------------------------------------===//
//
// Every self call modulo a context becomes a tail call that writes its
// result. The call's op says it is one (`idr.context_call`, which the
// decider made where the program became first order and every pass kept,
// the verifier holding each to the rule), so nothing here searches: each
// call's context is read once, off the call, and executed.
//
// `copy (Cons x xs) = Cons x (copy xs)` returns through every level of the
// list. The cell can be built before the call, with the field a hole, and
// the call given the hole's destination (`!idr.dest`) to write once it has
// its value; then the call is the last thing the tail does. So can every
// cell the returned value holds the first one in (`x :: x :: dup xs`, the
// action of the rest inside the actions that run it), and across a
// rejoin: where the context's cell is built after a match whose regions
// give its field, the cell is built before the match and each region
// writes its value into the hole, its own self call by passing the hole on.
// The function keeps its signature and does that for its first level; its
// self calls modulo a context go to a clone that takes a destination and
// returns nothing, whose own such tails write the value they build to the
// destination they got and recurse on the new one, whose self tail calls
// pass the destination on, and whose other tails write their value.
// idr-tail-loops makes the clone a loop: the structure is written top down
// in constant stack.
//
// It runs after counting, which honours each context: the cells on it are
// fresh heap cells, the scrutinee's token recycled into them, and nothing
// is placed between the call and its context's constructors. A promise, so
// no step of it is an action a debug counter may skip; a context it cannot
// execute is an internal error.
//
// The pass stays at the program: each clone is a new symbol of the program.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail/Trmc.h"

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Counting/Counting.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Counting/Bound.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Optimize/Tails.h"
#include "idr/Transforms/Tail.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/BitVector.h"

#define GEN_PASS_DEF_IDRTRMC
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

using namespace trmc;

// A function with self calls modulo a context: their contexts, each read
// once off its call, and the destination every hole of the recursion
// takes, which its clone takes in turn.
struct Plan {
  FuncOp fn;
  llvm::SmallVector<Context> contexts;
  DestType hole;
};

// The destination each context's hole takes, as the cell's own rule gives
// it: the field's type at its grade. The clone is handed every hole, so
// one recursion's holes take one type; holes of two types are two
// destinations no one parameter takes.
LogicalResult holeOf(Plan &plan) {
  for (const Context &context : plan.contexts) {
    auto init = cast<CellInitOp>(context.hole.op);
    FailureOr<DestType> dest = destOf(init.getLoc(), cast<CellType>(init.getCell().getType()),
                                      static_cast<int32_t>(context.hole.field));
    if (failed(dest))
      return failure();
    if (plan.hole && *dest != plan.hole)
      return context.call->emitOpError("internal error: idr-trmc: a recursion whose holes take ")
             << plan.hole << " and " << *dest << ", which no one clone takes";
    plan.hole = *dest;
  }
  return success();
}

struct Trmc : impl::IdrTrmcBase<Trmc> {
  void runOnProgram(ProgramOp program) {
    MLIRContext *ctx = program.getContext();
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    solver::ProgramGraph &graph = getAnalysis<solver::ProgramGraph>();
    footprint::Vector<Plan> plans;
    for (FuncOp fn : program.getOps<FuncOp>()) {
      Plan plan{fn, {}, {}};
      // idr.context_call's verifier, run after every pass, refuses a self
      // call modulo a context whose context the rule does not admit, so
      // each one's is there to read.
      fn.walk([&](ContextCallOp call) { plan.contexts.push_back(*contextOf(call)); });
      if (plan.contexts.empty())
        continue;
      if (failed(holeOf(plan)))
        return signalPassFailure();
      plans.push_back(std::move(plan));
    }
    if (plans.empty())
      return markAllAnalysesPreserved();

    IRRewriter rewriter(ctx);
    footprint::Vector<std::pair<FuncOp, FuncOp>> made;
    for (Plan &plan : plans) {
      FuncOp fn = plan.fn;
      ++numFunctions;
      numTails += plan.contexts.size();
      // The clone: the function, returning nothing and taking the
      // destination of its holes, so every call made of it reads that off
      // its signature.
      IRMapping mapping;
      auto clone = cast<FuncOp>(fn->clone(mapping));
      clone.setSymNameAttr(StringAttr::get(ctx, fn.getSymName() + ".trmc"));
      symbols.insert(clone, std::next(fn->getIterator()));
      (void)clone.eraseResults(llvm::BitVector(clone.getNumResults(), true));
      unsigned arity = clone.getNumArguments();
      (void)clone.insertArgument(arity, plan.hole, DictionaryAttr(), fn.getLoc());
      llvm::SmallVector<Context> inClone;
      for (const Context &context : plan.contexts)
        inClone.push_back(mapped(context, mapping));

      Rewrite first(rewriter, fn, clone, plan.contexts);
      Rewrite again(rewriter, fn, clone, inClone);
      Operation *returned = fn.getBody().front().getTerminator();
      Operation *cloneReturned = clone.getBody().front().getTerminator();
      if (failed(again.give(cloneReturned, 0, Written{clone.getArgument(arity)})) ||
          failed(first.give(returned, 0, Given{})))
        return signalPassFailure();
      // Each call becomes the member its final place makes, read off each
      // function's tails, since the rewrite moved calls and the ops after
      // them throughout both: the clone's calls in its tails are tail
      // calls, the function's first level calls the clone and then returns
      // the value it built, and a call whose value a tail of the clone now
      // writes returns to it. No self call modulo a context is left.
      (void)optimize::decideTails(fn);
      (void)optimize::decideTails(clone);
      LogicalResult kinds = success();
      auto settled = [&](ContextCallOp call) {
        kinds = call.emitOpError("internal error: idr-trmc left a call modulo a context");
      };
      fn.walk(settled);
      clone.walk(settled);
      if (failed(kinds))
        return signalPassFailure();
      made.push_back({fn, clone});
    }

    // The program graph learns the clones and the calls that now go to
    // them; then every row, the clones' with the writes of their holes,
    // is made equal to its derivation.
    {
      solver::Editor editor = graph.thaw();
      for (const std::pair<FuncOp, FuncOp> &pair : made)
        (void)editor.insert(pair.second);
      for (auto [fn, clone] : made) {
        editor.setCallees(editor.id(FlatSymbolRefAttr::get(fn.getSymNameAttr())),
                          solver::rowOf(fn, editor));
        editor.setCallees(editor.id(FlatSymbolRefAttr::get(clone.getSymNameAttr())),
                          solver::rowOf(clone, editor));
      }
      std::move(editor).freeze();
    }
    solver::Work work;
    rows::write(program, graph, work);
    numWork += work.steps();

    // What each function rewritten and each clone holds that it no longer
    // needs, on the rows just made exact: what the call held across it is
    // held while the cells are built before it, and a clone copied its
    // function's bound; each is measured as it now stands.
    const Layouts &layouts = getAnalysis<Layouts>();
    for (auto [fn, clone] : made) {
      fn.setFrameBound(counting::frameBound(fn, layouts));
      clone.setFrameBound(counting::frameBound(clone, layouts));
    }
    markAnalysesPreserved<SymbolTable, solver::ProgramGraph>();
  }
};

} // namespace
} // namespace idr::tail
