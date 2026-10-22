// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Accumulate.cpp - idr-accumulate ------------------------------------===//
//
// A self call whose result its tail combines becomes a tail call that
// carries the combination so far: the function calls a clone with the
// operation's identity, and the clone combines before it calls itself. A
// tail of the clone that gives a value combines it with what it carries;
// a tail that is already a self call passes it on. idr-tail-loops makes
// the clone a loop, and the combination a value of the iteration.
//
// It runs before counting, while the call's result is still what the tail
// combines: counting borrows that result and drops it after the
// combination, after which the call would no longer be the tail.
//
// An optimization, so each clone is an action a debug counter may skip:
// the function is left as it was, and its frames keep its depth.
//
// The pass stays at the program: each clone is a new symbol of the
// program, which no pass on one function may add. Every function is
// planned on the program as it stands, each plan reading its own function.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Actions.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"

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

// idr-accumulate gives one function its accumulator clone; the unit is the
// function.
struct AccumulateAction : support::TaggedAction<AccumulateAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::accumulate;
};

// `a ⊕ b`, the plan's operation on two values: a copy of its op, which
// carries whatever attributes say how it computes.
Value combine(RewriterBase &rewriter, const Accumulator &plan, Value a, Value b) {
  Operation *made = rewriter.clone(*plan.combine);
  made->setOperands({a, b});
  return made->getResult(0);
}

// The combination of `value`, given at a tail of the clone, with what the
// clone carries, on the side the calls were on.
Value withCarried(RewriterBase &rewriter, const Accumulator &plan, Value value, Value carried) {
  return plan.side == Side::Left ? combine(rewriter, plan, value, carried)
                                 : combine(rewriter, plan, carried, value);
}

// A tail call of `clone` in place of `old`, passing `carried` after the
// call's arguments, at the same index terms: the clone is the same
// recursion with the same facts, and the call takes its row.
CallOp callClone(RewriterBase &rewriter, CallOp old, FuncOp clone, Value carried) {
  llvm::SmallVector<Value> args(old.getArgs());
  args.push_back(carried);
  return CallOp::create(rewriter, old.getLoc(), clone, old.getIndexArgsAttr(), args,
                        TailKind::tail);
}

// The clone of `fn` that carries the combination, entered right after it;
// `fn` calls it with the identity.
void seed(RewriterBase &rewriter, SymbolTable &symbols, FuncOp fn, const Accumulator &plan) {
  MLIRContext *ctx = fn.getContext();
  Type carriedType = plan.combine->getResult(0).getType();
  IRMapping mapping;
  auto clone = cast<FuncOp>(fn->clone(mapping));
  clone.setSymNameAttr(StringAttr::get(ctx, fn.getSymName() + ".acc"));
  (void)clone.insertArgument(clone.getNumArguments(), carriedType, DictionaryAttr(),
                             fn.getLoc());
  symbols.insert(clone, std::next(fn->getIterator()));
  Value carried = clone.getArguments().back();
  Accumulator mapped = plan;
  mapped.combine = mapping.lookup(plan.combine);

  for (const Site &site : plan.sites)
    idr::match(
        site,
        [&](CallOp call) {
          auto inClone = cast<CallOp>(mapping.lookup(call.getOperation()));
          rewriter.setInsertionPoint(inClone);
          rewriter.replaceOp(inClone, callClone(rewriter, inClone, clone, carried));
        },
        [&](const Combined &combined) {
          auto call = cast<CallOp>(mapping.lookup(combined.call.getOperation()));
          Operation *at = mapping.lookup(combined.combine);
          Value other = at->getOperand(combined.side == Side::Left ? 1 : 0);
          rewriter.setInsertionPoint(at);
          // The other operand joins what is carried on the call's side: for
          // f(...) ⊕ g the clone goes on with g ⊕ carried, for g ⊕ f(...)
          // with carried ⊕ g.
          Value next = combined.side == Side::Left ? combine(rewriter, mapped, other, carried)
                                                    : combine(rewriter, mapped, carried, other);
          rewriter.replaceOp(at, callClone(rewriter, call, clone, next));
          rewriter.eraseOp(call);
        });

  // Every other tail of the clone combines the value it gives.
  for (Block *end : tailEnds(clone)) {
    Operation *terminator = end->getTerminator();
    if (terminator->getNumOperands() != 1)
      continue;
    if (auto call = dyn_cast_or_null<CallOp>(tailSource(*end));
        call && call.getCalleeAttr().getAttr() == clone.getSymNameAttr())
      continue;
    rewriter.setInsertionPoint(terminator);
    Value given = withCarried(rewriter, mapped, terminator->getOperand(0), carried);
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperand(0, given); });
  }

  // The function the program calls starts the clone at the identity.
  Block &entry = fn.getBody().front();
  for (Operation &op : llvm::make_early_inc_range(llvm::reverse(entry)))
    rewriter.eraseOp(&op);
  rewriter.setInsertionPointToStart(&entry);
  Value identity = plan.combine->getDialect()
                       ->materializeConstant(rewriter, plan.identity, carriedType, fn.getLoc())
                       ->getResult(0);
  llvm::SmallVector<Value> args(entry.getArguments());
  args.push_back(identity);
  unsigned own = static_cast<unsigned>(
      cast<ErasedBinderOpInterface>(fn.getOperation()).getBoundSorts(fn.getBody()).size());
  auto call = CallOp::create(rewriter, fn.getLoc(), clone, families::levelArgs(ctx, 0, own), args,
                             TailKind::tail);
  ReturnOp::create(rewriter, fn.getLoc(), call.getResults());
}

struct Accumulate : impl::IdrAccumulateBase<Accumulate> {
  void runOnProgram(ProgramOp program) {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    footprint::Vector<std::pair<FuncOp, Accumulator>> plans;
    for (FuncOp fn : program.getOps<FuncOp>())
      if (std::optional<Accumulator> plan = accumulatorOf(fn))
        plans.emplace_back(fn, std::move(*plan));
    IRRewriter rewriter(program.getContext());
    unsigned performed = 0;
    for (auto &[fn, plan] : plans)
      performed += support::perform<AccumulateAction>(fn, [&] {
        seed(rewriter, symbols, fn, plan);
        ++numFunctions;
        numTails += static_cast<uint64_t>(llvm::count_if(plan.sites, [](const Site &site) {
          return idr::match(
              site, [](CallOp) { return false; }, [](const Combined &) { return true; });
        }));
      });
    if (performed == 0)
      return markAllAnalysesPreserved();
    markAnalysesPreserved<SymbolTable>();
  }
};

} // namespace
} // namespace idr::tail
