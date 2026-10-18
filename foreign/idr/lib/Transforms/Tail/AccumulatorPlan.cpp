// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- AccumulatorPlan.cpp - What an accumulator tail is ------------------===//
//
// `length (x :: xs) = S (length xs)` is an addition of the recursive
// result. The addition associates and commutes and its identity is zero,
// so adding on the way down equals adding on the way back: the function
// the program calls seeds a clone with zero, and the clone adds its
// argument before the call, which is then the last thing that tail does.
// A self call in any other position stays a call, and so does one whose
// other operand is itself a self call (`f l + f r`): both results are
// wanted, and the stack grows with them. The addition has to be the tail.
//
// A countdown is that sum with nothing else in it. `f(0) = 0` and
// `f(n) = f(n - 1) + 1`, the predecessor a match on a natural uses to
// show the argument shrank, is `f(n) = n`: n ones. The clone would add
// one on each step down to zero, which is the same value and does not
// finish when n is the whole range of a word. The function returns its
// argument, or that argument as an Integer when the sum is a big.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/DenseSet.h"

using namespace mlir;

namespace idr::tail {
namespace {

// The constant natural or integer `value` is, when it is one.
std::optional<APInt> constantOf(Value value) {
  auto constant = value.getDefiningOp<ConstantOp>();
  auto big = constant ? dyn_cast<BigAttr>(constant.getValue()) : BigAttr();
  if (!big)
    return std::nullopt;
  return big.getValue();
}

bool isOne(Value value) {
  std::optional<APInt> constant = constantOf(value);
  return constant && constant->isOne();
}

// The one value `block` yields, when it holds nothing but constants before
// the yield.
std::optional<Value> yieldedPastConstants(Block &block) {
  auto yield = dyn_cast<YieldOp>(block.getTerminator());
  if (!yield || yield.getNumOperands() != 1 ||
      !llvm::all_of(block.without_terminator(), llvm::IsaPred<ConstantOp>))
    return std::nullopt;
  return yield.getOperand(0);
}

// The other operand of `add`, when exactly one of its operands is
// `operand`.
std::optional<Value> otherOperand(BigAddOp add, Value operand) {
  if (add.getLhs() == operand && add.getRhs() != operand)
    return add.getRhs();
  if (add.getRhs() == operand && add.getLhs() != operand)
    return add.getLhs();
  return std::nullopt;
}

// Whether the default region of a countdown computes `f(n - 1) + 1` and
// yields it, `n` the function's argument `arg`, which the region also has
// back as its own argument: either is the scrutinee.
bool addsOneToPredecessor(Block &block, FuncOp fn, BlockArgument arg) {
  BigPredOp pred;
  CallOp call;
  BigAddOp add;
  for (Operation &op : block) {
    if (isa<ConstantOp, YieldOp>(op))
      continue;
    if (auto p = dyn_cast<BigPredOp>(op)) {
      if (pred)
        return false;
      pred = p;
    } else if (auto c = dyn_cast<CallOp>(op)) {
      if (call)
        return false;
      call = c;
    } else if (auto a = dyn_cast<BigAddOp>(op)) {
      if (add)
        return false;
      add = a;
    } else {
      return false;
    }
  }
  if (!pred || !call || !add || (pred.getValue() != arg && pred.getValue() != block.getArgument(0)))
    return false;
  if (!isSelfCall(call, fn) || call.getArgs().size() != 1 || call.getArgs()[0] != pred.getResult())
    return false;
  std::optional<Value> addend = otherOperand(add, call.getResult(0));
  if (!addend || !isOne(*addend))
    return false;
  auto yield = dyn_cast<YieldOp>(block.getTerminator());
  return yield && yield.getNumOperands() == 1 && yield.getOperand(0) == add.getResult();
}

// Whether `value` is computed from a self call of `fn`.
bool dependsOnSelfCall(Value value, FuncOp fn, llvm::DenseSet<Value> &seen) {
  if (!seen.insert(value).second)
    return false;
  Operation *def = value.getDefiningOp();
  if (!def)
    return false;
  if (isSelfCall(def, fn))
    return true;
  return llvm::any_of(def->getOperands(), [&](Value operand) { return dependsOnSelfCall(operand, fn, seen); });
}

// The accumulator tail of the self call `call` of `fn`, or none.
std::optional<Site> siteOf(CallOp call, FuncOp fn) {
  if (call.getNumResults() != 1)
    return std::nullopt;
  if (inTailPosition(call))
    return Site{call, std::nullopt};
  if (!call->hasOneUse())
    return std::nullopt;
  auto add = dyn_cast<BigAddOp>(*call->user_begin());
  if (!add || !inTailPosition(add) || add->getBlock() != call->getBlock())
    return std::nullopt;
  std::optional<Value> addend = otherOperand(add, call.getResult(0));
  if (!addend)
    return std::nullopt;
  llvm::DenseSet<Value> seen;
  if (dependsOnSelfCall(*addend, fn, seen))
    return std::nullopt;
  // The ops of the block between the call and the addition.
  auto between = llvm::make_range(std::next(call->getIterator()), add->getIterator());
  if (!llvm::all_of(between, [](Operation &op) { return isMemoryEffectFree(&op) && isSpeculatable(&op); }))
    return std::nullopt;
  return Site{call, Site::Addition{add, *addend}};
}

// Whether every use of `fn` in its own body is a call. A reference that is
// not a call would keep calling the function the program calls, which
// seeds the sum at zero.
bool refersToItselfOnlyByCall(FuncOp fn) {
  std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(fn.getSymNameAttr(), &fn.getBody());
  return !uses || llvm::all_of(*uses, [](const SymbolTable::SymbolUse &use) { return isa<CallOp>(use.getUser()); });
}

} // namespace

bool isZero(Value value) {
  std::optional<APInt> constant = constantOf(value);
  return constant && constant->isZero();
}

void clearBlock(RewriterBase &rewriter, Block &block) {
  for (Operation &op : llvm::make_early_inc_range(llvm::reverse(block)))
    rewriter.eraseOp(&op);
}

// The constants may sit in the function or in the branch: simplification
// lifts them out of the match.
bool isCountdown(FuncOp fn) {
  if (fn.getNumArguments() != 1 || fn.getNumResults() != 1)
    return false;
  BlockArgument arg = fn.getArgument(0);
  if (!isa<NatType>(arg.getType()) || !isa<NatType, BigType>(fn.getResultTypes()[0]))
    return false;

  MatchLitOp match;
  ReturnOp ret;
  for (Operation &op : fn.getBody().front()) {
    if (isa<ConstantOp>(op))
      continue;
    if (auto lit = dyn_cast<MatchLitOp>(op); lit && !match)
      match = lit;
    else if (auto returned = dyn_cast<ReturnOp>(op); returned && !ret)
      ret = returned;
    else
      return false;
  }
  if (!match || !ret || match.getNumResults() != 1 || match.getScrutinee() != arg ||
      ret.getNumOperands() != 1 || ret.getOperand(0) != match.getResult(0))
    return false;
  if (match.getCases().size() != 1)
    return false;
  auto zeroCase = dyn_cast<BigAttr>(match.getCases()[0]);
  if (!zeroCase || !zeroCase.getValue().isZero())
    return false;

  std::optional<Value> zeroValue = yieldedPastConstants(match.getCaseRegion(0).front());
  if (!zeroValue || !isZero(*zeroValue))
    return false;
  return addsOneToPredecessor(match.getDefaultRegion().front(), fn, arg);
}

void returnArgument(FuncOp fn, RewriterBase &rewriter) {
  Block &entry = fn.getBody().front();
  clearBlock(rewriter, entry);
  rewriter.setInsertionPointToStart(&entry);
  Value result = fn.getArgument(0);
  if (isa<BigType>(fn.getResultTypes()[0]))
    result = NatToBigOp::create(rewriter, fn.getLoc(), result).getResult();
  ReturnOp::create(rewriter, fn.getLoc(), ValueRange{result});
}

SmallVector<Site> accumulatorSites(FuncOp fn) {
  if (fn.getNumResults() != 1 || !refersToItselfOnlyByCall(fn))
    return {};
  SmallVector<Site> sites;
  WalkResult walk = fn.walk([&](CallOp call) {
    if (!isSelfCall(call, fn))
      return WalkResult::advance();
    std::optional<Site> site = siteOf(call, fn);
    if (!site)
      return WalkResult::interrupt();
    sites.push_back(*site);
    return WalkResult::advance();
  });
  if (walk.wasInterrupted() || llvm::none_of(sites, [](const Site &site) { return site.addition.has_value(); }))
    return {};
  return sites;
}

} // namespace idr::tail
