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

using namespace mlir;

namespace idr::tail {
namespace {

// The block's terminator, when the ops after `op` only change the grade of
// its results and the terminator forwards exactly those values, which
// `values` then holds; null when another op runs after `op`, so that what
// `op` gives is not yet what the block gives, or when the terminator
// forwards anything else.
Operation *passesOn(Operation *op, SmallVectorImpl<Value> &values) {
  values.assign(op->result_begin(), op->result_end());
  Operation *next = op->getNextNode();
  for (; next && !next->hasTrait<OpTrait::IsTerminator>(); next = next->getNextNode()) {
    if (!next->hasTrait<ResultCarriesOperand>())
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
  while (source && source->hasTrait<ResultCarriesOperand>())
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

namespace {

// Whether an operand of a call that becomes a jump lives in a lifetime
// that ends with the call: its lifetime, through the views and rooms it is
// the extent of, is any but a parameter of the function, so its region
// encloses the call or it is this call's activation, and its memory would
// be gone when the callee reads it.
bool endsWithCall(Value operand, FuncOp fn) {
  Value lifetime = lifetimes::statedLifetime(operand);
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
             << " lives in a lifetime that ends with this call, which goes in its place";
  return success();
}

} // namespace

LogicalResult verify(CallOp call) {
  auto fn = call->getParentOfType<FuncOp>();
  switch (call.getTailKind()) {
  case TailKind::nontail:
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
  // The tail calls of the function, and those its spine reaches: each
  // block that ends a tail, from the body down through every region op a
  // break crosses whose results the block gives on, read once.
  unsigned tails = 0;
  fn.walk([&](CallOp call) {
    if (call.getTailKind() == TailKind::tail)
      ++tails;
  });
  if (tails == 0)
    return success();
  unsigned reached = 0;
  for (Block *end : tailEnds(fn))
    if (auto call = dyn_cast_or_null<CallOp>(tailSource(*end));
        call && call.getTailKind() == TailKind::tail)
      ++reached;
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
