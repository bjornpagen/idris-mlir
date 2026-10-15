// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// resets-unshared: every take that may reuse a cell tests one its function
// never gives a second reference.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

using namespace mlir;

namespace idr::expect {

namespace {

// Whether the function gives `value` a second reference: an idr.dup of a
// view of it, of the value it moved in from (idr.lin.enter, idr.lin.use),
// or of a value it was read from, whose cell then holds it shared.
bool givenSecondReference(Value value) {
  auto dupped = [](Value view) { return llvm::any_of(view.getUsers(), llvm::IsaPred<DupOp>); };
  for (; value; value = ownership::readFrom(value)) {
    for (Value alias = value; alias;) {
      if (dupped(alias))
        return true;
      for (Operation *user : alias.getUsers())
        if (auto borrow = dyn_cast<BorrowOp>(user); borrow && dupped(borrow.getResult()))
          return true;
      Operation *def = alias.getDefiningOp();
      alias = isa_and_nonnull<LinEnterOp, LinUseOp, BorrowOp>(def) ? def->getOperand(0) : Value();
    }
  }
  return false;
}

} // namespace

// Every take of a box, in the function the argument names or in every
// function with a body, tests a cell that its function never gives a
// second reference: no idr.dup of a view of the box or of a value it was
// read from.
LogicalResult resetsUnshared(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "resets-unshared";
  SmallVector<Operation *> roots =
      rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool held = true;
  for (Operation *root : roots)
    root->walk([&](TakeOp take) {
      if (!take.getToken() || !givenSecondReference(take.getValue()))
        return;
      fail(take.getLoc(), property) << take->getName() << " in " << where(take)
                                    << " tests a cell that its function gives a second reference";
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
