// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-reuse's demand (Reuse.h): one backward walk per function over its
// regions, measuring the most sinks of each size on any path ahead until
// the function's tokens die (a return, a call in tail position, a jump, the
// end of the process). A region that may run many times takes no token
// from outside it. What it measures goes on the trail in the order it met
// each point, which the forward walk reads back in reverse. Its stack is on
// the heap, so a nesting of any depth costs no native stack.
#include "idr/Transforms/Counting/Reuse.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <variant>

using namespace mlir;

namespace idr::counting::reuse {

//===----------------------------------------------------------------------===//
// The demand
//===----------------------------------------------------------------------===//

void Reuse::demands() {
  Demand cap;
  fn.walk([&](Operation *op) {
    std::optional<unsigned> bytes = sourceBytes(op);
    if (!bytes)
      return;
    if (!indexOf(*bytes)) {
      sizes.push_back(*bytes);
      cap.push_back(0);
    }
    ++cap[*indexOf(*bytes)];
  });
  if (sizes.empty())
    return;
  struct BlockAt {
    Block *block;
    Operation *next;
    Demand demand;
    unsigned region;
  };
  struct OpAt {
    Operation *op;
    Runs runs;
    Demand after;
    unsigned remaining;
    llvm::SmallVector<Demand, 2> entries;
  };
  llvm::SmallVector<std::variant<BlockAt, OpAt>, 16> stack;
  // A region op's regions, walked last first; then what is asked before it:
  // before an op that enters one region once, the most any region it enters
  // asks; before one that repeats, what is asked after it, since no token
  // from outside enters it.
  auto stepOp = [&](OpAt &at) {
    if (at.remaining > 0) {
      Region &region = at.op->getRegion(--at.remaining);
      if (!region.empty())
        stack.push_back(BlockAt{&region.front(), &region.front().back(), none(), region.getRegionNumber()});
      return;
    }
    Demand before = at.after;
    if (at.runs == Runs::Once) {
      before = none();
      llvm::SmallVector<RegionSuccessor> entries;
      cast<RegionBranchOpInterface>(at.op).getSuccessorRegions(RegionBranchPoint::parent(), entries);
      for (const RegionSuccessor &entry : entries)
        raise(before, at.entries[entry.getSuccessor()->getRegionNumber()]);
    }
    stack.pop_back();
    std::get<BlockAt>(stack.back()).demand = std::move(before);
  };
  // The frame of the region op `op`, a terminator's parent, on the stack.
  auto frameOf = [&](Operation *op) {
    for (auto &frame : llvm::reverse(stack))
      if (OpAt *around = match(
              frame, [&](OpAt &at) { return at.op == op ? &at : nullptr; },
              [](BlockAt &) -> OpAt * { return nullptr; }))
        return around;
    return static_cast<OpAt *>(nullptr);
  };
  auto stepBlock = [&](BlockAt &walk) {
    if (!walk.next) {
      BlockAt done = std::move(walk);
      stack.pop_back();
      trail.push_back(done.demand);
      if (!stack.empty())
        std::get<OpAt>(stack.back()).entries[done.region] = std::move(done.demand);
      return;
    }
    Operation *op = walk.next;
    walk.next = op->getPrevNode();
    if (op->hasTrait<OpTrait::IsTerminator>()) {
      // A yield to an op around that enters one region once asks what is
      // asked after that op; every other way out lets the tokens die.
      walk.demand = none();
      if (auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(op)) {
        llvm::SmallVector<Attribute> constants(op->getNumOperands());
        llvm::SmallVector<RegionSuccessor> successors;
        terminator.getSuccessorRegions(constants, successors);
        for (const RegionSuccessor &successor : successors) {
          if (!successor.isOperation() || successor.getSuccessorOp() != op->getParentOp())
            continue;
          if (OpAt *around = frameOf(op->getParentOp()); around && around->runs == Runs::Once)
            raise(walk.demand, around->after);
        }
      }
      return;
    }
    if (auto sink = dyn_cast<CellNewOp>(op))
      if (std::optional<unsigned> index = indexOf(cellBytes(sink.getCell().getType().getValue())))
        walk.demand[*index] = std::min(walk.demand[*index] + 1, cap[*index]);
    if (sourceBytes(op))
      trail.push_back(walk.demand);
    if (auto call = dyn_cast<CallOp>(op); call && call.getTailKind() == TailKind::tail)
      walk.demand = none();
    if (op->getNumRegions() != 0) {
      trail.push_back(walk.demand);
      OpAt at{op, runsOf(op), walk.demand, op->getNumRegions(), {}};
      at.entries.assign(op->getNumRegions(), none());
      stack.push_back(std::move(at));
    }
  };
  Block &body = fn.getBody().front();
  stack.push_back(BlockAt{&body, &body.back(), none(), 0});
  while (!stack.empty())
    match(stack.back(), stepOp, stepBlock);
}

} // namespace idr::counting::reuse
