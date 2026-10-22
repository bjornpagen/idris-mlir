// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The spine of a lifetime a call puts into: a root used again after every
// allocation that follows it in the lifetime's block, so nothing the call
// put is dead while memory is taken. The verifier checks it and the decide
// step meets it before it writes a lifetime, so both read this one rule.

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Verify.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

// One backward scan from `last` to the root, which fails at an op that may
// allocate before the root is used again and ends where it is: everything
// before that use is followed by it on every path. A region's block is
// scanned from its end, as if from after its op, so a use inside it ends
// only its own scan. The blocks still to scan are kept on a list, never on
// the C++ stack.
bool idr::verify::usedAfterEveryAllocation(Value root, Operation *last) {
  Operation *maker = root.getDefiningOp();
  if (!maker || maker->getBlock() != last->getBlock())
    return false;
  // The values that are the root: it, and each value made from it as
  // itself (a match's refined argument, a cast), met in program order.
  SmallVector<Value, 4> same{root};
  auto join = [&](Value value) {
    match(
        sourceOf(value),
        [&](const Same &of) {
          if (llvm::is_contained(same, of.value))
            same.push_back(value);
        },
        [](Made) {}, [](const Field &) {});
  };
  for (Operation *op = maker->getNextNode(); op; op = op == last ? nullptr : op->getNextNode())
    op->walk<WalkOrder::PreOrder>([&](Operation *nested) {
      for (Region &region : nested->getRegions())
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments())
            join(arg);
      for (Value result : nested->getResults())
        join(result);
    });
  auto uses = [&](Operation *op) {
    return llvm::any_of(op->getOperands(), [&](Value operand) { return llvm::is_contained(same, operand); });
  };

  SmallVector<Operation *, 8> pending{last};
  while (!pending.empty())
    for (Operation *op = pending.pop_back_val(); op && op != maker; op = op->getPrevNode()) {
      for (Region &region : op->getRegions())
        for (Block &block : region)
          if (!block.empty())
            pending.push_back(&block.back());
      if (effects::mayAcquire(effects::own(op)))
        return false;
      if (uses(op))
        break;
    }
  return true;
}
