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
// The pass stays at the program: each clone is a new symbol in the
// program's block, which no pass on one function may add. It plans and
// rewrites one function at a time, in program order, and enters each clone
// in the table it holds, right after its function, under a name made from
// the function's and the kind `acc`, so no order reaches the name.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/Tail.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Pass/Pass.h"

#include <optional>
#include <variant>

namespace idr {
#define GEN_PASS_DEF_IDRACCUMULATE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// idr-accumulate makes one countdown return its argument; the unit is the
// function.
struct AccumulateCountdownAction : support::TaggedAction<AccumulateCountdownAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-accumulate-countdown";
};

// idr-accumulate gives one function its accumulator clone; the unit is the
// function.
struct AccumulateCloneAction : support::TaggedAction<AccumulateCloneAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-accumulate-clone";
};

// A call of `clone` in place of `call`, with `carried` after its arguments.
// The clone is the same recursion with the same facts, so the call does
// what the old one did.
CallOp retarget(RewriterBase &rewriter, CallOp call, FuncOp clone, Value carried) {
  SmallVector<Value> args(call.getArgs());
  args.push_back(carried);
  auto neu = CallOp::create(rewriter, call.getLoc(), clone, args);
  neu.setResAttrsAttr(call.getResAttrsAttr());
  neu->setDiscardableAttrs(call->getDiscardableAttrDictionary());
  return neu;
}

// The clone's tails, whose ops `mapping` gives for `sites` of the
// function: an addition becomes the sum carried into the call, which takes
// the addition's place at the tail, and a tail that returns a value adds
// the sum to it. An addition of zero, the identity, folds to the sum
// itself.
void rewriteClone(RewriterBase &rewriter, FuncOp clone, ArrayRef<Site> sites, const IRMapping &mapping, Value acc) {
  for (Site site : sites) {
    auto call = cast<CallOp>(mapping.lookup(site.call.getOperation()));
    if (!site.addition) {
      rewriter.setInsertionPoint(call);
      rewriter.replaceOp(call, retarget(rewriter, call, clone, acc).getOperation());
      continue;
    }
    auto add = cast<BigAddOp>(mapping.lookup(site.addition->add.getOperation()));
    rewriter.setInsertionPoint(add);
    Value sum = rewriter.createOrFold<BigAddOp>(add.getLoc(), add.getResult().getType(), acc,
                                                mapping.lookup(site.addition->addend));
    CallOp neu = retarget(rewriter, call, clone, sum);
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
    rewriter.setInsertionPoint(terminator);
    Value sum = rewriter.createOrFold<BigAddOp>(terminator->getLoc(), acc.getType(), acc, value);
    rewriter.modifyOpInPlace(terminator, [&] { terminator->setOperand(0, sum); });
    // What only the tail read, a zero the addition folded away, goes.
    if (Operation *def = value.getDefiningOp(); def && isOpTriviallyDead(def))
      rewriter.eraseOp(def);
  }
}

// What becomes of one function: a countdown returns its argument; the
// function of accumulator tails seeds its clone, named `name`, which adds
// on the way down.
struct Countdown {};
struct Accumulator {
  SmallVector<Site> sites;
  StringAttr name;
};
using Plan = std::variant<Countdown, Accumulator>;

// A visit of a plan with one case for each alternative, so that a missing
// one does not compile.
template <typename... Cases> struct Visit : Cases... {
  using Cases::operator()...;
};
template <typename... Cases> Visit(Cases...) -> Visit<Cases...>;

// The plan of `fn`; none when nothing becomes of it, failure when its
// clone's name is taken.
FailureOr<std::optional<Plan>> planOf(FuncOp fn, SymbolTable &symbols) {
  if (isCountdown(fn))
    return std::optional<Plan>(Countdown{});
  SmallVector<Site> sites = accumulatorSites(fn);
  if (sites.empty())
    return std::optional<Plan>();
  FailureOr<StringAttr> name = copyName(fn, "acc", symbols);
  if (failed(name))
    return failure();
  return std::optional<Plan>(Accumulator{std::move(sites), *name});
}

// The clone of `fn` that carries the sum, named `name`, entered right after
// it; `fn` calls it with zero.
void seed(RewriterBase &rewriter, SymbolTable &symbols, FuncOp fn, const Accumulator &plan) {
  MLIRContext *ctx = fn.getContext();
  Type result = fn.getResultTypes()[0];
  IRMapping mapping;
  auto clone = cast<FuncOp>(fn->clone(mapping));
  clone.setSymNameAttr(plan.name);
  (void)clone.insertArgument(clone.getNumArguments(), result, DictionaryAttr(),
                            passBinder(fn, "sum"));
  symbols.insert(clone, std::next(fn->getIterator()));
  rewriteClone(rewriter, clone, plan.sites, mapping, clone.getArguments().back());

  // The old body computed the sum on the way back; it goes now that the
  // clone holds its copy.
  Block &entry = fn.getBody().front();
  clearBlock(rewriter, entry);
  rewriter.setInsertionPointToStart(&entry);
  Value zero = ConstantOp::create(rewriter, fn.getLoc(), result, BigAttr::get(ctx, APInt(1, 0)));
  SmallVector<Value> args(entry.getArguments());
  args.push_back(zero);
  auto call = CallOp::create(rewriter, fn.getLoc(), clone, args);
  ReturnOp::create(rewriter, fn.getLoc(), call.getResults());
}

struct Accumulate : impl::IdrAccumulateBase<Accumulate> {
  void runOnProgram(ProgramOp program) override {
    SymbolTable &symbols = getAnalysis<SymbolTable>();
    // Every function is planned on the program as it stands, before any
    // changes: a plan reads its own function alone.
    SmallVector<std::pair<FuncOp, Plan>> plans;
    for (FuncOp fn : program.getOps<FuncOp>()) {
      FailureOr<std::optional<Plan>> plan = planOf(fn, symbols);
      if (failed(plan))
        return signalPassFailure();
      if (*plan)
        plans.emplace_back(fn, std::move(**plan));
    }
    IRRewriter rewriter(program.getContext());
    unsigned performed = 0;
    for (auto &[planned, plan] : plans) {
      FuncOp fn = planned;
      performed += std::visit(
          Visit{[&](const Countdown &) {
                  return support::perform<AccumulateCountdownAction>(
                      fn, [&] { returnArgument(fn, rewriter); });
                },
                [&](const Accumulator &accumulator) {
                  return support::perform<AccumulateCloneAction>(fn, [&] {
                    seed(rewriter, symbols, fn, accumulator);
                    ++numFunctions;
                    numTails += static_cast<uint64_t>(
                        llvm::count_if(accumulator.sites, [](const Site &site) {
                          return site.addition.has_value();
                        }));
                  });
                }},
          plan);
    }
    if (performed == 0)
      return markAllAnalysesPreserved();
    markAnalysesPreserved<SymbolTable, TypeGraph, Layouts>();
  }
};

} // namespace
} // namespace idr::tail
