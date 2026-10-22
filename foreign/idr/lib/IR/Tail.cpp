// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position: the one definition, the call's own check of its fact,
// and its function's. Tail position modulo a context is Tail/Context.cpp's.

#include "idr/IR/Tail.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Traits.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

// What each stage of a program implies: whether every call's tail fact is
// the decider's.
#include "idr/IR/Generated/StageFacts.h.inc"

using namespace mlir;

namespace idr::tail {

// A reindex is one op whose run-time work its two types decide: none where
// they share a layout, a re-pack where they do not, which is work after
// the value it takes. A change of grade has no run-time form.
bool carriesOn(Operation *op) {
  if (auto reindex = dyn_cast<DataReindexOp>(op))
    return reindex.isFree();
  return op->hasTrait<ResultCarriesOperand>();
}

namespace {

// The block's terminator, when the ops after `op` only give its results on
// with no run-time work and the terminator forwards exactly those values,
// which `values` then holds; null when another op runs after `op`, so that
// what `op` gives is not yet what the block gives, or when the terminator
// forwards anything else.
Operation *passesOn(Operation *op, SmallVectorImpl<Value> &values) {
  values.assign(op->result_begin(), op->result_end());
  Operation *next = op->getNextNode();
  for (; next && !next->hasTrait<OpTrait::IsTerminator>(); next = next->getNextNode()) {
    if (!carriesOn(next))
      return nullptr;
    auto *carried = llvm::find(values, next->getOperand(0));
    if (carried == values.end())
      return nullptr;
    *carried = next->getResult(0);
  }
  return next && llvm::equal(next->getOperands(), values) ? next : nullptr;
}

} // namespace

Operation *rejoinOf(Operation *terminator) {
  Operation *parent = terminator->getParentOp();
  auto branch = dyn_cast<RegionBranchTerminatorOpInterface>(terminator);
  if (!branch || !parent || !parent->hasTrait<OpTrait::PropagateControlFlowBreak>())
    return nullptr;
  SmallVector<RegionSuccessor, 2> successors;
  branch.getSuccessorRegions(SmallVector<Attribute>(terminator->getNumOperands()), successors);
  if (successors.size() != 1 || successors.front().getSuccessorOp() != parent ||
      branch.getMutableSuccessorOperands(successors.front()).size() !=
          terminator->getNumOperands() ||
      parent->getNumResults() != terminator->getNumOperands())
    return nullptr;
  return parent;
}

Operation *tailSource(Block &block) {
  Operation *terminator = block.getTerminator();
  Operation *source = terminator->getPrevNode();
  while (source && carriesOn(source))
    source = source->getPrevNode();
  llvm::SmallVector<Value, 4> values;
  return source && passesOn(source, values) == terminator ? source : nullptr;
}

llvm::SmallVector<Block *> tailEnds(FuncOp fn) {
  llvm::SmallVector<Block *> ends;
  llvm::SmallVector<Block *, 8> spine{&fn.getBody().front()};
  while (!spine.empty()) {
    Block *block = spine.pop_back_val();
    Operation *source = tailSource(*block);
    if (!source || !source->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      ends.push_back(block);
      continue;
    }
    for (Region &region : source->getRegions())
      if (!region.empty() && rejoinOf(region.front().getTerminator()) == source)
        spine.push_back(&region.front());
  }
  return ends;
}

bool inTailPosition(Operation *op) {
  llvm::SmallVector<Value, 4> values;
  for (Operation *at = op;;) {
    Operation *terminator = passesOn(at, values);
    if (!terminator)
      return false;
    if (isa<ReturnOp>(terminator))
      return true;
    at = rejoinOf(terminator);
    if (!at)
      return false;
  }
}

TailKind decide(CallOp call) {
  if (inTailPosition(call))
    return TailKind::tail;
  if (contextOf(call))
    return TailKind::modulo_context;
  return TailKind::nontail;
}

bool decided(FuncOp fn) { return tailsAt[fn.getProgram().getStage()] == StageTails::Decided; }

namespace {

// Whether an operand of a call that becomes a jump is, or lives in, a
// lifetime that ends with the call: that lifetime, through the views and
// rooms it is the extent of, is any but a parameter of the function, so its
// region encloses the call or it is this call's activation, and its memory
// would be gone when the callee reads it. So no lifetime is handed over at
// a tail call: every lifetime ends in the function that opened it.
bool endsWithCall(Value operand, FuncOp fn) {
  Value lifetime =
      isa<LifetimeType>(operand.getType()) ? operand : lifetimes::statedLifetime(operand);
  if (!lifetime)
    return false;
  auto root = dyn_cast<BlockArgument>(lifetimes::extentOf(lifetime));
  return !root || root.getOwner() != &fn.getBody().front();
}

// The lifetime rule for a call that becomes a jump.
LogicalResult verifyOperands(CallOp call, FuncOp fn) {
  for (OpOperand &operand : call->getOpOperands())
    if (endsWithCall(operand.get(), fn))
      return call.emitOpError("internal error: operand #")
             << operand.getOperandNumber()
             << " is or lives in a lifetime that ends with this call, which goes in its place";
  return success();
}

} // namespace

LogicalResult verify(CallOp call) {
  auto fn = call->getParentOfType<FuncOp>();
  switch (call.getTailKind()) {
  case TailKind::nontail:
    // A self call the rule admits, left an ordinary call, is a loop with a
    // destination the compiler fails to make. One in tail position is its
    // function's to show.
    if (decided(fn) && contextOf(call))
      return call.emitOpError("internal error: a call modulo a context left nontail, a loop with "
                              "a destination the compiler fails to make");
    return success();
  case TailKind::tail: {
    llvm::SmallVector<Value, 4> values;
    Operation *terminator = passesOn(call, values);
    if (!terminator || (!isa<ReturnOp>(terminator) && !rejoinOf(terminator)))
      return call.emitOpError(
          "internal error: a tail call whose results its block does not give on unchanged");
    return verifyOperands(call, fn);
  }
  case TailKind::modulo_context:
    if (!contextOf(call))
      return call.emitOpError("internal error: a call modulo a context whose result goes "
                              "elsewhere than into cells built for it that its function returns");
    return verifyOperands(call, fn);
  }
  return success();
}

LogicalResult verify(FuncOp fn) {
  // The tail calls of the function, and the calls its spine reaches: each
  // block that ends a tail, from the body down through every region op a
  // break crosses whose results the block gives on, read once. Each call
  // there is in tail position, so, once every fact is decided, one that is
  // no tail call is a jump the compiler fails to make.
  unsigned tails = 0;
  fn.walk([&](CallOp call) {
    if (call.getTailKind() == TailKind::tail)
      ++tails;
  });
  bool exact = decided(fn);
  unsigned reached = 0;
  for (Block *end : tailEnds(fn)) {
    auto call = dyn_cast_or_null<CallOp>(tailSource(*end));
    if (!call)
      continue;
    if (call.getTailKind() == TailKind::tail)
      ++reached;
    else if (exact)
      return call.emitOpError("internal error: a call in tail position that is no tail call, a "
                              "jump the compiler fails to make");
  }
  if (reached == tails)
    return success();
  // Some tail call is off the spine: name it, reading up from each.
  LogicalResult result = success();
  fn.walk([&](CallOp call) {
    if (call.getTailKind() == TailKind::tail && !inTailPosition(call)) {
      result = call.emitOpError("internal error: a tail call that is not in tail position: an "
                                "op runs after a region op around it");
      return WalkResult::interrupt();
    }
    return WalkResult::advance();
  });
  return result;
}

} // namespace idr::tail
