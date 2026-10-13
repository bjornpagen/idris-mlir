// The class of each value of a function, as counting places it:
// untracked, static, borrowed or owned; and what counting asks of a region:
// whether a value is used in it, and whether its block ends in a crash,
// which counting leaves alone.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::ownership {

Class Classes::classOf(Value value) {
  if (!counted(value.getType()))
    return Class::Untracked;
  if (isStatic(value))
    return Class::Static;
  auto known = classes.find(value);
  if (known != classes.end())
    return known->second;
  Class result = Class::Owned;
  if (Value from = readFrom(value)) {
    if (llvm::all_of(value.getUsers(), [&](Operation *user) { return aliveAt(from, user); }))
      result = Class::Borrowed;
  } else if (auto arg = dyn_cast<BlockArgument>(value);
             arg && arg.getOwner()->getParentOp() == fn.getOperation()) {
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
// there, or is a parameter.
bool Classes::aliveAt(Value value, Operation *op) {
  switch (classOf(value)) {
  case Class::Untracked:
  case Class::Static:
    return true;
  case Class::Owned:
    // Used again after `op`, or inside a region of it: a match uses its
    // scrutinee as it starts, so a use in one of its regions keeps it
    // alive there too. usedIn is what counting asks of a region.
    return usedAfter(value, op) ||
           llvm::any_of(op->getRegions(), [&](Region &region) { return usedIn(value, region); });
  case Class::Borrowed:
    break;
  }
  Value from = readFrom(value);
  return !from || aliveAt(from, op);
}

bool usedIn(Value value, Region &region) {
  return llvm::any_of(value.getUses(), [&](OpOperand &use) {
    return region.isAncestor(use.getOwner()->getParentRegion());
  });
}

bool endsInCrash(Block &block) { return !block.empty() && isa<ub::UnreachableOp>(block.back()); }

} // namespace idr::ownership
