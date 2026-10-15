// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The owned walk through a block and the ops with regions. An op's regions
// are read through what it forwards (forwardedValues): the op's entry and
// its regions' terminators move owned values on into region arguments and
// results, with their references, and pass views on. A value an op makes
// in a region without being forwarded it (a field a match binds, an element
// a loop over a buffer reads) is the op's own, made from what it reads. No
// op is known by its kind: the regions of one that return straight to it
// are alternatives (alternatives), and those of any other may run again or
// after one another. Each returns whether the end of what it walked is
// reached, or failure after reporting a violation.

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Verify.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <optional>

using namespace mlir;
using namespace idr;

namespace {

// A terminator that is no region branch's and goes to no block ends its
// path with nothing to account for: the ub.unreachable after a crash.
bool endsPath(Operation &op) {
  return op.hasTrait<OpTrait::IsTerminator>() && op.getNumSuccessors() == 0 &&
         !isa<RegionBranchTerminatorOpInterface>(op);
}

// Whether `value` is defined in a region of `op`.
bool inside(Operation &op, Value value) {
  return op.isAncestor(value.getParentRegion()->getParentOp());
}

// Whether two values an op's branch points forward into are of one
// successor: arguments of one block, or results of one op.
bool samePlace(Value a, Value b) {
  if (auto arg = dyn_cast<BlockArgument>(a)) {
    auto other = dyn_cast<BlockArgument>(b);
    return other && other.getOwner() == arg.getOwner();
  }
  auto other = dyn_cast<OpResult>(b);
  return other && other.getOwner() == cast<OpResult>(a).getOwner();
}

// The terminator of `region`'s entry block, the branch point it forwards
// from, or null.
Operation *exitOf(Region &region) {
  if (region.empty() || region.front().empty())
    return nullptr;
  Operation &last = region.front().back();
  return last.hasTrait<OpTrait::IsTerminator>() ? &last : nullptr;
}

// Adds the regions among `next`, the successors of a branch point, to
// `regions`; whether one of them leaves the op.
bool enters(ArrayRef<RegionSuccessor> next, llvm::SmallPtrSetImpl<Region *> &regions) {
  bool leaves = false;
  for (const RegionSuccessor &successor : next) {
    if (successor.isOperation())
      leaves = true;
    else
      regions.insert(successor.getSuccessor());
  }
  return leaves;
}

} // namespace

void idr::verify::OwnedWalk::Forwarding::add(Operation *from) {
  forwardedValues(from, [&](OpOperand &operand, Value input) {
    into[input].push_back(&operand);
    to[&operand].push_back(input);
  });
}

FailureOr<bool> idr::verify::OwnedWalk::walk(Block &block) {
  for (Operation &op : block) {
    if (endsPath(op))
      return false;
    if (op.getNumRegions() != 0) {
      FailureOr<bool> reached = walkRegions(op);
      if (failed(reached) || !*reached)
        return reached;
      continue;
    }
    if (failed(visit(op)))
      return failure();
  }
  return true;
}

// The op's own operands first: what it forwards moves into its regions or
// results, and what it does not, it takes or reads as any op does. Each
// region the op or a region reached before it may branch to then starts
// from the state after the entry. Where the regions are alternatives, the
// ones that reach their end must leave every value from outside with the
// same references, which it then holds after the op; where they are not,
// each must leave those values as it found them, since it may run again
// from where it ends, or after another.
FailureOr<bool> idr::verify::OwnedWalk::walkRegions(Operation &op) {
  Forwarding forwarding;
  forwarding.add(&op);
  for (Region &region : op.getRegions())
    if (Operation *exit = exitOf(region))
      forwarding.add(exit);
  llvm::DenseSet<OpOperand *> entry;
  for (OpOperand &operand : op.getOpOperands())
    if (forwarding.forwards(operand))
      entry.insert(&operand);
  if (failed(operands(op, entry)))
    return failure();
  SmallVector<Value> reads = readBy(op, entry);

  // An op that does not branch between its regions runs each as it will
  // and returns once they are done.
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  bool choice = branch && alternatives(branch);
  llvm::SmallPtrSet<Region *, 4> entered;
  bool exits = !branch;
  if (branch) {
    SmallVector<RegionSuccessor> next;
    branch.getSuccessorRegions(RegionBranchPoint::parent(), next);
    exits = enters(next, entered);
  } else {
    for (Region &region : op.getRegions())
      entered.insert(&region);
  }
  // The terminators whose region reached its end: the branch points a path
  // takes, whose forwarded values the walk has seen made.
  llvm::SmallPtrSet<Operation *, 4> reached;
  size_t mark = log.size();
  SmallVector<llvm::MapVector<Value, int>> ends;
  if (choice && exits)
    ends.emplace_back();
  for (Region &region : op.getRegions()) {
    if (region.empty() || !entered.contains(&region))
      continue;
    unsigned index = region.getRegionNumber();
    auto given = [&](Operation *from) {
      return from == &op ||
             (reached.contains(from) && from->getParentRegion()->getRegionNumber() < index);
    };
    Block &block = region.front();
    for (BlockArgument arg : block.getArguments())
      if (failed(enter(op, forwarding, arg, reads, given)))
        return failure();
    FailureOr<bool> end = walk(block);
    if (failed(end))
      return failure();
    if (*end) {
      if (failed(settled(block, block.back())))
        return failure();
      llvm::MapVector<Value, int> changes = changesSince(mark);
      if (choice)
        ends.push_back(std::move(changes));
      else if (!changes.empty())
        return fail(op, changes.front().first,
                    "changes the references of a value from outside it in a region that may run "
                    "again, or after another");
      if (Operation *exit = exitOf(region))
        reached.insert(exit);
      if (branch) {
        SmallVector<RegionSuccessor> next;
        branch.getSuccessorRegions(region, next);
        exits = enters(next, entered) || exits;
      }
    }
    undo(mark);
  }

  if (choice) {
    if (ends.empty())
      return false;
    llvm::MapVector<Value, int> after;
    for (auto &end : ends)
      for (auto &[value, references] : end)
        after.try_emplace(value, references);
    for (auto &[value, references] : after)
      for (auto &end : ends) {
        auto it = end.find(value);
        int here = it == end.end() ? held.lookup(value) : it->second;
        if (here != references)
          return fail(op, value, "leaves a value with ")
                 << references << " references on one path and " << here << " on another";
      }
    for (auto &[value, references] : after)
      set(value, references);
  } else if (failed(backEdges(op, forwarding, reached))) {
    return failure();
  }
  if (!exits)
    return false;
  auto given = [&](Operation *from) { return from == &op || reached.contains(from); };
  for (Value result : op.getResults())
    if (failed(enter(op, forwarding, result, reads, given)))
      return failure();
  return true;
}

// A value of `op`, a region argument or a result. One no branch point
// forwards into, the op makes from what it reads. One a branch point
// forwards into: an owned one holds the reference that moved in, unless it
// is a payload (payload); a view is a view of what the values forwarded
// into it were read from, on each edge `given` says the walk has taken.
LogicalResult idr::verify::OwnedWalk::enter(Operation &op, const Forwarding &forwarding,
                                            Value input, ArrayRef<Value> reads,
                                            function_ref<bool(Operation *)> given) {
  auto feeds = forwarding.into.find(input);
  if (feeds == forwarding.into.end())
    return make(op, input, reads);
  if (tracked(input)) {
    set(input, payload(forwarding, input) ? 0 : 1);
    return success();
  }
  if (!isView(input))
    return success();
  SmallVector<Value> from;
  bool any = false;
  for (OpOperand *operand : feeds->second) {
    if (!given(operand->getOwner()))
      continue;
    any = true;
    FailureOr<SmallVector<Value>> across = ownersAcross(op, forwarding, *operand, input);
    if (failed(across))
      return failure();
    for (Value owner : *across)
      if (!llvm::is_contained(from, owner))
        from.push_back(owner);
  }
  if (!any)
    return fail(op, input, "binds a view that no branch the walk has taken gives it");
  viewOf(input, from);
  return success();
}

// What `input` is a view of where `operand`'s view is forwarded into it:
// what the view was read from, followed up to the owned values that hold
// the references. One the same branch point moves on into a value of the
// same successor is, beyond the edge, that value: a view passed on beside
// its owner is a view of where the owner went. One outside the op stays
// where it is. One inside that does not move on with the view holds its
// reference only in the region the view leaves. A chain that reaches no
// owned value is of static data or a borrowed parameter, alive throughout.
// Each step is to a value defined before it, so the walk ends.
FailureOr<SmallVector<Value>> idr::verify::OwnedWalk::ownersAcross(Operation &op,
                                                                   const Forwarding &forwarding,
                                                                   OpOperand &operand,
                                                                   Value input) {
  Operation *from = operand.getOwner();
  auto movedTo = [&](Value value) -> Value {
    for (OpOperand &other : from->getOpOperands()) {
      if (other.get() != value)
        continue;
      auto it = forwarding.to.find(&other);
      if (it == forwarding.to.end())
        continue;
      for (Value to : it->second)
        if (samePlace(to, input))
          return to;
    }
    return Value();
  };
  Value start = operand.get();
  SmallVector<Value> out;
  auto add = [&](Value owner) {
    if (!llvm::is_contained(out, owner))
      out.push_back(owner);
  };
  SmallVector<Value> work{start};
  llvm::DenseSet<Value> seen;
  while (!work.empty()) {
    Value value = work.pop_back_val();
    if (!seen.insert(value).second)
      continue;
    if (value != start)
      if (Value to = movedTo(value)) {
        add(to);
        continue;
      }
    if (tracked(value) || carried(value)) {
      if (inside(op, value)) {
        (void)fail(*from, start, "passes on a view of a value whose reference does not leave "
                                 "the region with it");
        return failure();
      }
      add(value);
      continue;
    }
    if (!isView(value))
      continue;
    auto it = owners.find(value);
    if (it == owners.end()) {
      (void)fail(*from, value, "passes on a view the walk never saw made");
      return failure();
    }
    work.append(it->second.begin(), it->second.end());
  }
  return out;
}

// An owned value forwarded into a successor that never reads it is the
// payload of a path not taken there: a branch point that forwards one value
// into several successors (a loop's condition, into its body and into its
// results) gives it to the one that reads it, and to the others what is
// poison on that path. So an input that nothing uses holds no reference
// when every value forwarded into it is read beyond another successor.
bool idr::verify::OwnedWalk::payload(const Forwarding &forwarding, Value input) {
  if (!input.use_empty())
    return false;
  return llvm::all_of(forwarding.into.find(input)->second, [&](OpOperand *operand) {
    return llvm::any_of(forwarding.to.find(operand)->second, [&](Value other) {
      return !samePlace(other, input) && !other.use_empty();
    });
  });
}

// A region that has run is entered again from a terminator of its own or
// of a region after it. Its views were walked as views of what the edges
// before it gave; what a later edge gives must be read from values outside
// the op that still hold their references once the op is entered, which
// every region leaves as it found them, and not from what moves on into
// the region beside it, whose reference the walk of the region did not
// follow. The state here is the one after the entry.
LogicalResult idr::verify::OwnedWalk::backEdges(Operation &op, const Forwarding &forwarding,
                                                const llvm::SmallPtrSetImpl<Operation *> &reached) {
  for (Region &region : op.getRegions()) {
    if (region.empty())
      continue;
    unsigned index = region.getRegionNumber();
    for (BlockArgument arg : region.front().getArguments()) {
      auto feeds = forwarding.into.find(arg);
      if (feeds == forwarding.into.end() || !isView(arg))
        continue;
      for (OpOperand *operand : feeds->second) {
        Operation *from = operand->getOwner();
        if (from == &op || !reached.contains(from) ||
            from->getParentRegion()->getRegionNumber() < index)
          continue;
        FailureOr<SmallVector<Value>> across = ownersAcross(op, forwarding, *operand, arg);
        if (failed(across))
          return failure();
        for (Value owner : *across)
          if (inside(op, owner) || !alive(owner))
            return fail(*from, operand->get(),
                        "passes a view back into a region that has run, read from what moves "
                        "on into it beside the view: a view a region gets again is read from "
                        "a value outside the op that still holds its reference");
      }
    }
  }
  return success();
}
