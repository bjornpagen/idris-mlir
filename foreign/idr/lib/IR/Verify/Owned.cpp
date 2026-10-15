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
// it, and the references in scope. What one op without regions does to
// that state is OwnedOps.cpp; blocks and the ops with regions are
// OwnedRegions.cpp.
//
// The walk runs in idr.func's region verifier, on one of the verifier's
// threads; what it asks of a type it reads from the type, once per
// distinct type, and keeps the answer for this verify only.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Verify.h"
#include "idr/Support/Worklist.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <optional>

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
    if (tracked(arg))
      set(arg, 1);
    else if (isView(arg))
      viewOf(arg, {});
  }
  FailureOr<Reach> reached = walk(entry);
  if (failed(reached))
    return failure();
  if (*reached == Reach::Ends)
    return success();
  for (const Change &change : log)
    if (!change.old && held.lookup(change.value) != 0)
      return fail(entry.back(), change.value, "returns while a value still holds a reference");
  return success();
}

bool idr::verify::OwnedWalk::counts(Type type) {
  auto [it, fresh] = counted.try_emplace(type, false);
  if (fresh)
    it->second = holdsReferences(type);
  return it->second;
}

// Whether `value` holds a reference the walk follows: it is owned, and
// not a value that stands for one without holding it (poison, a pending
// field, a small big).
bool idr::verify::OwnedWalk::tracked(Value value) {
  return isOwned(value.getType()) && !ownership::isStatic(value);
}

bool idr::verify::OwnedWalk::carried(Value value) { return transit.contains(value); }

// Whether `value` is a view: it holds references but not one of its own.
bool idr::verify::OwnedWalk::isView(Value value) {
  return counts(value.getType()) && !isOwned(value.getType()) && !ownership::isStatic(value) &&
         !carried(value);
}

// Whether `value` may be used here: every reference it holds or was read
// from is still held. The walk up its owners meets each value once, so it
// ends with the values in scope.
bool idr::verify::OwnedWalk::alive(Value value) {
  OnceWorklist<Value> work;
  work.push(value);
  while (std::optional<Value> at = work.pop()) {
    if (tracked(*at) || carried(*at)) {
      if (held.lookup(*at) < 1)
        return false;
      continue;
    }
    if (!isView(*at))
      continue;
    auto from = owners.find(*at);
    if (from == owners.end())
      return false;
    for (Value owner : from->second)
      work.push(owner);
  }
  return true;
}

void idr::verify::OwnedWalk::set(Value value, int references) {
  auto it = held.find(value);
  log.push_back({value, it == held.end() ? std::nullopt : std::optional<int>(it->second)});
  held[value] = references;
}

void idr::verify::OwnedWalk::carry(Value value) {
  transit.insert(value);
  set(value, 1);
}

void idr::verify::OwnedWalk::viewOf(Value value, ArrayRef<Value> from) {
  owners[value].assign(from.begin(), from.end());
}

// The changes since `mark`, undone last first.
void idr::verify::OwnedWalk::undo(size_t mark) {
  for (const Change &change : llvm::reverse(ArrayRef<Change>(log).drop_front(mark))) {
    if (change.old)
      held[change.value] = *change.old;
    else
      held.erase(change.value);
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
    changes[log[i].value] = held.lookup(log[i].value);
  }
  return changes;
}

InFlightDiagnostic idr::verify::OwnedWalk::fail(Operation &op, Value value, const Twine &what) {
  InFlightDiagnostic diag = op.emitOpError(what);
  diag.attachNote(value.getLoc()) << "the value is defined here";
  return diag;
}

LogicalResult idr::verify::OwnedWalk::consume(Operation &op, Value value) {
  int references = held.lookup(value);
  if (references < 1)
    return fail(op, value, "consumes a reference that the value does not hold here: it was "
                           "consumed before on this path");
  set(value, references - 1);
  return success();
}

LogicalResult idr::verify::OwnedWalk::use(Operation &op, Value value) {
  if (!alive(value))
    return fail(op, value, "uses a value whose last reference is gone on this path");
  return success();
}

// Every value `block` defines holds no reference at its end.
LogicalResult idr::verify::OwnedWalk::settled(Block &block, Operation &at) {
  auto check = [&](Value value) -> LogicalResult {
    if ((tracked(value) || carried(value)) && held.lookup(value) != 0)
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
