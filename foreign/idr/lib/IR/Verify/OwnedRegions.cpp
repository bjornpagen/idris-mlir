// The owned walk through a block and the ops with regions: a match, a
// branch on a condition and a loop over an array. Each returns whether the
// end of what it walked is reached, or failure after reporting a
// violation.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Verify.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "llvm/ADT/MapVector.h"

using namespace mlir;
using namespace idr;

// A crash ends a path with nothing to account for, and a return ends one
// with every reference given back.
FailureOr<bool> idr::verify::OwnedWalk::walk(Block &block) {
  for (Operation &op : block) {
    if (isa<ub::UnreachableOp>(op))
      return false;
    if (op.getNumRegions() != 0) {
      FailureOr<bool> reached = walkRegions(op);
      if (failed(reached) || !*reached)
        return reached;
      continue;
    }
    if (failed(visit(op)))
      return failure();
    if (isa<ReturnOp>(op)) {
      // The log starts each value in scope at its definition, in walk
      // order, so the value named is the same on every run.
      for (const Change &change : log)
        if (!change.old && held.lookup(change.value) != 0)
          return fail(op, change.value, "returns while a value still holds a reference");
      return true;
    }
  }
  return true;
}

FailureOr<bool> idr::verify::OwnedWalk::walkRegions(Operation &op) {
  if (auto match = dyn_cast<MatchOp>(op))
    return walkMatch(op, match.getScrutinee());
  if (auto match = dyn_cast<MatchLitOp>(op))
    return walkMatch(op, match.getScrutinee());
  // A branch on a condition is a match on an i1: idr-narrow versions a
  // loop with one.
  if (auto branch = dyn_cast<scf::IfOp>(op))
    return walkMatch(op, branch.getCondition());
  if (auto loop = dyn_cast<scf::WhileOp>(op))
    return walkLoop(loop);
  if (auto loop = dyn_cast<scf::ForOp>(op))
    return walkFor(loop);
  if (auto loop = dyn_cast<ArrayGenerateOp>(op))
    return walkArrayLoop(op, {{loop.getFill(), true}}, loop.getBody(), loop.getResults());
  if (auto loop = dyn_cast<ArrayFoldOp>(op))
    return walkArrayLoop(op, {{loop.getArray(), false}, {loop.getInit(), true}}, loop.getBody(),
                         loop.getResults());
  return op.emitOpError("has regions, which the owned stage does not know how to count");
}

// A loop over an array (idr.array.generate, idr.array.fold): its body
// runs once per index it covers, takes its arguments owned (the element as
// array.get gives it, the accumulator as the init moved in), consumes
// what its yield passes on, and leaves every value from outside as it
// found it. The results are owned. `operands` are the loop's operands
// that hold references, each with whether the loop consumes it.
FailureOr<bool> idr::verify::OwnedWalk::walkArrayLoop(Operation &op,
                                                      ArrayRef<std::pair<Value, bool>> operands,
                                                      Region &body, ValueRange results) {
  for (auto [value, consumed] : operands)
    if (failed(consumed ? consume(op, value) : use(op, value)))
      return failure();
  size_t mark = log.size();
  Block &block = body.front();
  for (BlockArgument arg : block.getArguments())
    if (tracked(arg))
      define(arg, 1);
  FailureOr<bool> reached = walk(block);
  if (failed(reached))
    return failure();
  if (*reached) {
    if (failed(settled(block, block.back())))
      return failure();
    auto changes = changesSince(mark);
    if (!changes.empty())
      return fail(op, changes.front().first,
                  "changes the references of a value from outside the loop in its body");
  }
  undo(mark);
  for (Value result : results)
    if (tracked(result))
      define(result, 1);
  return true;
}

// Each region starts from the state before the match; the regions that
// reach their yield must leave every value from outside with the same
// references, which it then holds after the match.
FailureOr<bool> idr::verify::OwnedWalk::walkMatch(Operation &op, Value scrutinee) {
  if (failed(use(op, scrutinee)))
    return failure();
  size_t mark = log.size();
  SmallVector<llvm::MapVector<Value, int>> ends;
  for (Region &region : op.getRegions()) {
    if (region.empty())
      continue;
    Block &block = region.front();
    for (BlockArgument field : block.getArguments())
      if (isView(field))
        define(field, 0, scrutinee, /*borrowed=*/true);
    FailureOr<bool> reached = walk(block);
    if (failed(reached))
      return failure();
    if (*reached) {
      if (failed(settled(block, block.back())))
        return failure();
      ends.push_back(changesSince(mark));
    }
    undo(mark);
  }
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
  for (Value result : op.getResults()) {
    auto it = passedOn.find(result);
    if (it != passedOn.end())
      define(result, 0, it->second, /*borrowed=*/true);
    else if (tracked(result))
      define(result, 1);
  }
  return true;
}
