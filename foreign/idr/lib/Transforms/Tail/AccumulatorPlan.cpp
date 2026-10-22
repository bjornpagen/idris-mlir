// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- AccumulatorPlan.cpp - What an accumulator tail is ------------------===//
//
// `length (x :: xs) = 1 + length xs` combines the recursive result in its
// tail. When the operation is exactly associative and has an identity, as
// the runtime defines it (Integer's and Int's addition and multiplication,
// a fixed width wrapping; the bitwise and, or and xor; string
// concatenation), combining on the way down gives what combining on the
// way back gives: the function seeds a clone with the identity, and the
// clone combines before it calls itself, which is then its tail. The
// clone keeps the combination on the side the call was on, so the
// operation need not commute. A floating-point operation is never one,
// and neither is a user's Semigroup or Monoid, whose laws Idris does not
// prove: only an operation the specification gives its law is.
//
// Eager evaluation's order stays: the other operand is computed before
// the call, or computes only (no effect, no crash), so it may run first;
// the call may run where the combination is; and a self call anywhere but
// such a site or a tail call (`f l ⊕ f r`) leaves the function as it is,
// for the frames to keep its depth.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/Effects/Query.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Match.h"

#include "mlir/IR/SymbolTable.h"

using namespace mlir;

namespace idr::tail {
namespace {

bool isSelfCall(CallOp call, FuncOp fn) {
  return call.getCalleeAttr().getAttr() == fn.getSymNameAttr();
}

// Whether `call` may run where `combine`, later in its block, is: each op
// between them may cross it, so neither may tell.
bool mayMoveTo(CallOp call, Operation *combine) {
  for (Operation *op = call->getNextNode(); op != combine; op = op->getNextNode())
    if (!effects::mayMoveAcross(call, op))
      return false;
  return true;
}

// Whether `value` is computed before `call`: in a block around the call's,
// or in its block before it.
bool before(Value value, CallOp call) {
  Operation *def = value.getDefiningOp();
  if (!def || def->getBlock() != call->getBlock())
    return true;
  return def->isBeforeInBlock(call);
}

// The combination `call` is a site of, if any: its one result's one use is
// a binary operation the specification calls exactly associative with an
// identity, whose result is what the function gives, whose other operand
// either is computed before the call or computes only on values that are,
// and to whose place the call may move.
std::optional<Combined> combinedAt(CallOp call) {
  if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse())
    return std::nullopt;
  OpOperand &use = *call->getResult(0).getUses().begin();
  Operation *combine = use.getOwner();
  // An operation on one type, which the combination so far has too.
  if (combine->getNumOperands() != 2 || combine->getNumResults() != 1 ||
      combine->getOperand(0).getType() != combine->getResult(0).getType() ||
      combine->getOperand(1).getType() != combine->getResult(0).getType() ||
      combine->getBlock() != call->getBlock() || !laws::identityOf(combine) ||
      !inTailPosition(combine) || !mayMoveTo(call, combine))
    return std::nullopt;
  Side side = use.getOperandNumber() == 0 ? Side::Left : Side::Right;
  Value other = combine->getOperand(use.getOperandNumber() == 0 ? 1 : 0);
  if (other == call->getResult(0))
    return std::nullopt;
  if (!before(other, call)) {
    Operation *def = other.getDefiningOp();
    if (!effects::whole(def).onlyComputes() ||
        !llvm::all_of(def->getOperands(), [&](Value v) { return before(v, call); }))
      return std::nullopt;
  }
  return Combined{call, combine, side};
}

// Whether every use of `fn` in its own body is a call: a reference that is
// no call would keep running the function the program calls, which seeds
// the combination with the identity.
bool refersToItselfOnlyByCall(FuncOp fn) {
  std::optional<SymbolTable::UseRange> uses =
      SymbolTable::getSymbolUses(fn.getSymNameAttr(), &fn.getBody());
  return !uses || llvm::all_of(*uses, [](const SymbolTable::SymbolUse &use) {
           return isa<CallOp>(use.getUser());
         });
}

} // namespace

std::optional<Accumulator> accumulatorOf(FuncOp fn) {
  if (fn.getNumResults() != 1 || !refersToItselfOnlyByCall(fn))
    return std::nullopt;
  llvm::SmallVector<Site> sites;
  std::optional<Accumulator> plan;
  WalkResult walk = fn.walk([&](CallOp call) {
    if (!isSelfCall(call, fn))
      return WalkResult::advance();
    if (call.getTailKind() == TailKind::tail) {
      sites.push_back(call);
      return WalkResult::advance();
    }
    std::optional<Combined> combined = combinedAt(call);
    if (!combined)
      return WalkResult::interrupt();
    if (!plan) {
      plan = Accumulator{{}, combined->combine, *laws::identityOf(combined->combine),
                         combined->side};
    } else {
      // One operation for every site, and one side unless it commutes.
      bool commutes = plan->combine->hasTrait<OpTrait::IsCommutative>();
      if (combined->combine->getName() != plan->combine->getName() ||
          combined->combine->getAttrDictionary() != plan->combine->getAttrDictionary() ||
          (!commutes && combined->side != plan->side))
        return WalkResult::interrupt();
    }
    sites.push_back(*combined);
    return WalkResult::advance();
  });
  if (walk.wasInterrupted() || !plan)
    return std::nullopt;
  plan->sites = std::move(sites);
  return plan;
}

} // namespace idr::tail
