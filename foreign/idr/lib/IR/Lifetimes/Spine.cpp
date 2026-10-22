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

#include "llvm/ADT/STLExtras.h"

#include <variant>

using namespace mlir;
using namespace idr;

// One backward scan from `last` to the root, carrying whether the root is
// used again on every path from where the scan stands; a region's block is
// scanned with what holds after its op, so a use inside it covers only the
// ops before it there. The blocks still to scan are kept on a list, never
// on the C++ stack.
bool idr::verify::usedAfterEveryAllocation(Value root, Operation *last) {
  Operation *maker = root.getDefiningOp();
  if (!maker || maker->getBlock() != last->getBlock())
    return false;
  // The values that are the root: it, and each value made from it as
  // itself (a match's refined argument, a cast), met in program order.
  SmallVector<Value, 4> same{root};
  auto join = [&](Value value) {
    Source source = sourceOf(value);
    if (const auto *of = std::get_if<Same>(&source); of && llvm::is_contained(same, of->value))
      same.push_back(value);
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
  auto acquires = [](Operation *op) { return effects::own(op).row().contains(effects::Atom::alloc); };

  struct Pending {
    Operation *from;
    bool covered;
  };
  SmallVector<Pending, 8> pending{{last, false}};
  while (!pending.empty()) {
    auto [from, covered] = pending.pop_back_val();
    for (Operation *op = from; op && op != maker; op = op->getPrevNode()) {
      for (Region &region : op->getRegions())
        for (Block &block : region)
          if (!block.empty())
            pending.push_back({&block.back(), covered});
      if (!covered && acquires(op))
        return false;
      covered = covered || uses(op);
    }
  }
  return true;
}
