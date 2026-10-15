// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The class of each value of a function, as counting places it:
// untracked, static, borrowed or owned; and what counting asks of a region:
// whether a value is used in it, and whether its block ends in a crash,
// which counting leaves alone.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::ownership {

Class Classes::classOf(Value value) {
  // A reference crossing a boundary between counting and upstream's buffer
  // ops: a fresh allocation's, which its idr.own.adopt takes over, and the
  // one an idr.own.give hands to the store that consumes it. Counting
  // places nothing for either; the boundary op is its one use.
  Operation *def = value.getDefiningOp();
  if (!holdsReferences(value.getType()) || isa_and_nonnull<mlir::memref::AllocOp, OwnGiveOp>(def))
    return Class::Untracked;
  // An op that only changes a grade but takes its operand over (a linear
  // position) holds what that operand holds once counted: a static operand
  // gets a reference of its own there, which no count reaches but which
  // the grade says, so what the op gives is owned.
  bool takesOver = def && def->hasTrait<ResultCarriesOperand>() && consumes(def->getOpOperand(0));
  if (isStatic(value) && !takesOver)
    return Class::Static;
  auto known = classes.find(value);
  if (known != classes.end())
    return known->second;
  // Owned, the class that takes a reference of its own, until the reads
  // decide: classOf recurses through aliveAt into other values' classes,
  // no chain definitionChain walks, and a recursion that comes back to this
  // value, which only an unreachable block makes, finds it owned.
  classes[value] = Class::Owned;
  Class result = Class::Owned;
  if (Value from = readFrom(value); from && !isCountedElement(value)) {
    if (llvm::all_of(value.getUsers(), [&](Operation *user) { return aliveAt(from, user); }))
      result = Class::Borrowed;
  } else if (auto arg = dyn_cast<BlockArgument>(value);
             arg && arg.getOwner()->isEntryBlock() &&
             arg.getOwner()->getParentOp() == fn.getOperation()) {
    // Borrow inference graded the signature before any function is placed:
    // a parameter it left a view is borrowed.
    if (!isOwned(arg.getType()))
      result = Class::Borrowed;
  }
  classes[value] = result;
  return result;
}

// Whether `value` still holds a reference, or lives as long as the call,
// where `op` uses what was read from it: an owned value is used again
// after `op`, and a borrowed one is read from a value that is alive
// there, or is a parameter. The reference of an owned value is where
// placement keeps it: up to its last use in each block that holds `op`,
// through every op that does not decide and uses it inside, and into the
// region of a deciding op only when that region uses it.
// The walk goes up the chain of what each was read from: one that closes
// on itself, which only an unreachable block makes, is not alive, so a
// field read from it takes a reference of its own.
bool Classes::aliveAt(Value value, Operation *op) {
  auto readThrough = [](Value at) -> std::optional<Value> {
    if (Value from = readFrom(at))
      return from;
    return std::nullopt;
  };
  for (Value at : definitionChain(value, readThrough)) {
    switch (classOf(at)) {
    case Class::Untracked:
    case Class::Static:
      return true;
    case Class::Owned:
      // Used again after `op`, or inside a region of it: an op with regions
      // reads what it reads as it starts, so a use in one of its regions
      // keeps the value alive there too. usedIn is what counting asks of a
      // region.
      return usedAfter(at, op) ||
             llvm::any_of(op->getRegions(), [&](Region &region) { return usedIn(at, region); });
    case Class::Borrowed:
      break;
    }
    if (!readFrom(at))
      return true;
  }
  return false;
}

bool usedIn(Value value, Region &region) {
  return llvm::any_of(value.getUses(), [&](OpOperand &use) {
    return region.isAncestor(use.getOwner()->getParentRegion());
  });
}

bool endsInCrash(Block &block) { return !block.empty() && isa<ub::UnreachableOp>(block.back()); }

} // namespace idr::ownership
