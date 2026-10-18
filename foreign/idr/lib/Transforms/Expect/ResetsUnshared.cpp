// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// resets-unshared: every take that may reuse a cell tests one its function
// never gives a second reference.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

#include <variant>

using namespace mlir;

namespace idr::expect {

namespace {

// Whether the function gives `value` a second reference: an idr.dup of a
// view of it, of the value it is the same as (sourceOf: the value it moved
// in from by idr.lin.enter or idr.lin.use, the value a borrow views, the
// scrutinee a match's default binds again), or of a value it was read
// from, whose cell then holds it shared.
bool givenSecondReference(Value value) {
  auto dupped = [](Value view) { return llvm::any_of(view.getUsers(), llvm::IsaPred<DupOp>); };
  for (; value; value = ownership::readFrom(value)) {
    for (Value alias = value; alias;) {
      if (dupped(alias))
        return true;
      for (Operation *user : alias.getUsers())
        if (auto borrow = dyn_cast<BorrowOp>(user); borrow && dupped(borrow.getResult()))
          return true;
      Source source = sourceOf(alias);
      const auto *same = std::get_if<Same>(&source);
      alias = same ? same->value : Value();
    }
  }
  return false;
}

} // namespace

// Every take, of a box with a cell, in the function the argument names or
// in every function with a body, tests a cell that its function never
// gives a second reference: no idr.dup of a view of the box or of a value
// it was read from. A value with no cell of its own is unpacked, which
// tests nothing.
LogicalResult resetsUnshared(const Request<Roots> &request) {
  bool held = true;
  for (Operation *root : request.argument.roots(request.module))
    root->walk([&](TakeOp take) {
      if (!givenSecondReference(take.getValue()))
        return;
      fail(take.getLoc(), request.property)
          << take->getName() << " in " << where(take)
          << " tests a cell that its function gives a second reference";
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
