// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The owned stage's rule for one function: each reference is consumed
// exactly once on every path, and a view is used only while what it was
// read from holds its reference. The grades say which is which
// (`!idr.own<T>` and `!idr.excl<T>` hold one reference, a borrow and a
// buffer's plain view hold none) and useOf says what each use does; the
// rule extends linearity, which counts uses on the worst path, to exact
// counts: a walk follows the references every owned value holds along the
// ops. This unit holds the walk's entry and its state: what a value is to
// it (its role), and the references in scope. What one op without regions
// does to that state is OwnedOps.cpp; blocks and the ops with regions are
// OwnedRegions.cpp.
//
// The walk runs in idr.func's region verifier, on one of the verifier's
// threads; what it asks of a value it reads from the value's type and
// definition, once per value, and keeps the answer for this verify only.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Verify.h"
#include "idr/Support/Worklist.h"

#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <optional>
#include <variant>

using namespace mlir;
using namespace idr;

LogicalResult idr::verify::owned(FuncOp fn) {
  OwnedWalk walk(fn);
  return walk.check();
}

idr::verify::OwnedWalk::OwnedWalk(FuncOp fn) : fn(fn) {}

// A borrowed parameter is a view its caller keeps alive throughout. A
// return gives back every reference: the log starts each value in scope at
// its definition, in walk order, so the value named is the same on every
// run.
LogicalResult idr::verify::OwnedWalk::check() {
  Block &entry = fn.getBody().front();
  for (BlockArgument arg : entry.getArguments()) {
    switch (roleOf(arg)) {
    case Role::Owned:
      set(arg, 1);
      break;
    case Role::View:
      viewOf(arg, {});
      break;
    // A parameter is never Carried: only a result an op allocates is.
    case Role::Carried:
    case Role::Untracked:
      break;
    }
  }
  FailureOr<Reach> reached = walk(entry);
  if (failed(reached))
    return failure();
  if (*reached == Reach::Ends)
    return success();
  for (const Change &change : log)
    if (!change.old && references(change.value) != 0)
      return fail(entry.back(), change.value, "returns while a value still holds a reference");
  return success();
}

// A value's role, from its type and its definition alone, so that it is
// the same wherever the walk meets the value. In this order:
// - a value that carries no reference, as its flow edges move it
//   (Carriers, the fact useOf reads: a cell carries its box's), is
//   Untracked, and so is static data its op makes (madeStatic) at an owned
//   grade, which stands for a value (poison, a small big) and holds no
//   reference to give up; static data at a view's grade is a view that
//   lives as long as the program (make), so a use that consumes it takes a
//   reference of its own (idr.dup), as of any view, and what is read from
//   it is a view of it;
// - an owned grade holds a reference of its own, and so does a cell, which
//   its type lets be used once and its init consumes: a cell is decided
//   here, before the allocation its source declares;
// - a result its op allocates carries the fresh reference, and so does
//   idr.own.give's, which it hands to a store. An op that only changes a
//   grade (ResultCarriesOperand) is the one kind whose allocation is no
//   memory: lin.enter's and lin.use's keep two linear values from merging,
//   and the result is the operand's value, its role as its type says;
// - anything else is a view.
idr::verify::Role idr::verify::OwnedWalk::roleOf(Value value) {
  if (auto known = roles.find(value); known != roles.end())
    return known->second;
  Role role = [&] {
    Type type = value.getType();
    if (!Carriers::of(type).contains(Carrier::Reference) ||
        (ownership::madeStatic(value) && (isOwned(type) || isLinearByType(type))))
      return Role::Untracked;
    if (isOwned(type) || isLinearByType(type))
      return Role::Owned;
    if (auto result = dyn_cast<OpResult>(value)) {
      Operation *op = result.getOwner();
      if (isa<OwnGiveOp>(op) || (!op->hasTrait<ResultCarriesOperand>() &&
                                 hasEffect<MemoryEffects::Allocate>(op, value)))
        return Role::Carried;
    }
    return Role::View;
  }();
  roles.try_emplace(value, role);
  return role;
}

// The references an Owned or Carried value holds here: none once consumed,
// or before it is made.
int idr::verify::OwnedWalk::references(Value value) const {
  auto it = slots.find(value);
  if (it == slots.end())
    return 0;
  const auto *state = std::get_if<References>(&it->second);
  return state ? state->count : 0;
}

// What a view was read from, once the walk has seen it made.
const idr::verify::OwnedWalk::Viewing *idr::verify::OwnedWalk::viewing(Value value) const {
  auto it = slots.find(value);
  return it == slots.end() ? nullptr : std::get_if<Viewing>(&it->second);
}

// Whether `value` may be used here: every reference it holds or was read
// from is still held. The walk up its owners meets each value once, so it
// ends with the values in scope.
bool idr::verify::OwnedWalk::alive(Value value) {
  OnceWorklist<Value> work;
  work.push(value);
  while (std::optional<Value> at = work.pop()) {
    switch (roleOf(*at)) {
    case Role::Owned:
    case Role::Carried:
      if (references(*at) < 1)
        return false;
      break;
    case Role::View: {
      const Viewing *view = viewing(*at);
      if (!view)
        return false;
      for (Value owner : view->owners)
        work.push(owner);
      break;
    }
    case Role::Untracked:
      break;
    }
  }
  return true;
}

// Only an Owned or Carried value is set, and its slot is References from
// its first set on: the log records whether it had one, for undo.
void idr::verify::OwnedWalk::set(Value value, int count) {
  auto [it, fresh] = slots.try_emplace(value, Slot(References{count}));
  if (fresh) {
    log.push_back({value, std::nullopt});
    return;
  }
  log.push_back({value, std::get<References>(it->second)});
  it->second = References{count};
}

void idr::verify::OwnedWalk::viewOf(Value value, ArrayRef<Value> from) {
  slots.insert_or_assign(value, Slot(Viewing{llvm::to_vector<1>(from)}));
}

// The changes since `mark`, undone last first.
void idr::verify::OwnedWalk::undo(size_t mark) {
  for (const Change &change : llvm::reverse(ArrayRef<Change>(log).drop_front(mark))) {
    if (change.old)
      slots.insert_or_assign(change.value, Slot(*change.old));
    else
      slots.erase(change.value);
  }
  log.truncate(mark);
}

// The references of the values that were in scope at `mark` and changed
// since.
llvm::MapVector<Value, int> idr::verify::OwnedWalk::changesSince(size_t mark) {
  llvm::MapVector<Value, int> changes;
  llvm::DenseSet<Value> seen;
  for (size_t i = mark; i < log.size(); ++i) {
    if (!seen.insert(log[i].value).second || !log[i].old)
      continue;
    changes[log[i].value] = references(log[i].value);
  }
  return changes;
}

InFlightDiagnostic idr::verify::OwnedWalk::fail(Operation &op, Value value, const Twine &what) {
  InFlightDiagnostic diag = op.emitOpError(what);
  diag.attachNote(value.getLoc()) << "the value is defined here";
  return diag;
}

LogicalResult idr::verify::OwnedWalk::consume(Operation &op, Value value) {
  int count = references(value);
  if (count < 1)
    return fail(op, value, "consumes a reference that the value does not hold here: it was "
                           "consumed before on this path");
  set(value, count - 1);
  return success();
}

LogicalResult idr::verify::OwnedWalk::use(Operation &op, Value value) {
  if (!alive(value))
    return fail(op, value, "uses a value whose last reference is gone on this path");
  return success();
}

// Every value `block` defines holds no reference at its end: an Owned or
// Carried value is the one kind whose state counts references, and a cell
// is Owned, so one never filled is refused here.
LogicalResult idr::verify::OwnedWalk::settled(Block &block, Operation &at) {
  auto check = [&](Value value) -> LogicalResult {
    if (references(value) != 0)
      return fail(at, value, "ends a path on which a value still holds a reference");
    return success();
  };
  for (BlockArgument arg : block.getArguments())
    if (failed(check(arg)))
      return failure();
  for (Operation &op : block)
    for (Value result : op.getResults())
      if (failed(check(result)))
        return failure();
  return success();
}
