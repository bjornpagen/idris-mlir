// The owned stage's rule for one function: each reference is consumed
// exactly once on every path, and a view is used only while its owner
// holds its reference. The grades say which is which (`!idr.own<T>` holds
// one reference, plain T holds none) and useOf says what each use does;
// the rule extends linearity, which counts uses on the worst path, to exact
// counts: a walk follows the references every owned value holds along the
// ops, taking the regions of a match as alternatives that must agree where
// they meet again. This unit holds the walk's state and its visit of one
// op; the regions and the loops are OwnedRegions.cpp and OwnedLoops.cpp.
//
// The walk runs in idr.func's region verifier, on one of the verifier's
// threads, so what it asks of the module it asks by a scan of the module's
// top level, once per distinct type, and keeps the answer for this verify
// only.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Verify.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseSet.h"

using namespace mlir;
using namespace idr;

LogicalResult idr::verify::owned(FuncOp fn) {
  if (fn.isExternal())
    return success();
  OwnedWalk walk(fn);
  return walk.check();
}

idr::verify::OwnedWalk::OwnedWalk(FuncOp fn) : fn(fn), stack(fn.getContext()) {}

LogicalResult idr::verify::OwnedWalk::check() {
  Block &entry = fn.getBody().front();
  for (BlockArgument arg : entry.getArguments()) {
    if (tracked(arg))
      define(arg, 1);
    else if (isView(arg))
      owners[arg] = Value();
  }
  return failure(failed(walk(entry)));
}

DataOp idr::verify::OwnedWalk::declaration(Type type) {
  auto [it, fresh] = declarations.try_emplace(type);
  if (fresh)
    it->second = declarationOf(fn, type);
  return it->second;
}

// `@T::@C` within the declaration of T, which depends on the name alone.
CtorOp idr::verify::OwnedWalk::constructor(SymbolRefAttr ctor) {
  if (ctor.getNestedReferences().size() != 1)
    return nullptr;
  Type data = DataType::get(fn.getContext(), FlatSymbolRefAttr::get(ctor.getRootReference()));
  return lookupCtor(declaration(data), ctor.getLeafReference().getValue());
}

bool idr::verify::OwnedWalk::counts(Type type) {
  auto [it, fresh] = counted.try_emplace(type, false);
  if (fresh)
    it->second = holdsReferences(type, [&](Type sum) { return declaration(sum); });
  return it->second;
}

// Whether `value` holds a reference the walk follows: it is owned, and
// not a value that stands for one without holding it (poison, a pending
// field, a small big).
bool idr::verify::OwnedWalk::tracked(Value value) {
  return isOwned(value.getType()) && !ownership::isStatic(value);
}

// Whether `value` is a view: it holds references but not one of its own.
bool idr::verify::OwnedWalk::isView(Value value) {
  return counts(value.getType()) && !isOwned(value.getType()) && !ownership::isStatic(value);
}

// Whether `value` may be used here: it holds a reference, or what it was
// read from is alive, or it is a borrowed parameter.
bool idr::verify::OwnedWalk::alive(Value value) {
  for (unsigned depth = 0; depth < 1024; ++depth) {
    if (!tracked(value) && !isView(value))
      return true;
    auto it = held.find(value);
    if (it != held.end() && it->second > 0)
      return true;
    auto owner = owners.find(value);
    if (owner == owners.end())
      return false;
    if (!owner->second)
      return true;
    value = owner->second;
  }
  return false;
}

void idr::verify::OwnedWalk::set(Value value, int references) {
  auto it = held.find(value);
  log.push_back({value, it == held.end() ? std::nullopt : std::optional<int>(it->second)});
  held[value] = references;
}

void idr::verify::OwnedWalk::define(Value value, int references, Value owner, bool borrowed) {
  set(value, references);
  if (borrowed)
    owners[value] = owner;
}

void idr::verify::OwnedWalk::undo(size_t mark) {
  while (log.size() > mark) {
    Change change = log.pop_back_val();
    if (change.old)
      held[change.value] = *change.old;
    else
      held.erase(change.value);
  }
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
  if (!tracked(value))
    return success();
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
    if (tracked(value) && held.lookup(value) != 0)
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

bool idr::verify::OwnedWalk::reachesOnlyAtoms(Value value) {
  return ownership::reachesOnlyAtoms(value, [&](Type type) { return declaration(type); });
}

LogicalResult idr::verify::OwnedWalk::visit(Operation &op) {
  if (auto select = dyn_cast<arith::SelectOp>(op); select && tracked(select))
    return op.emitOpError("selects between values that hold references; in the owned "
                          "stage a match does");
  // An exclusive value alone reaches its cells: no view of it (or of
  // what was read from it) takes a reference of its own, and an
  // exclusive constructor is built of exclusive fields, on the heap. A
  // reference of its own is exclusive only to static data that reaches
  // no cell but atoms, which no take hands out: of anything else, the
  // copy shares the original's cells.
  if (auto dup = dyn_cast<DupOp>(op)) {
    if (isExclusive(dup.getType()) && !reachesOnlyAtoms(dup.getValue()))
      return fail(op, dup.getValue(), "takes an exclusive reference to a value that reaches "
                                      "cells other than atoms, which it shares");
    Value root = ownership::viewRoot(dup.getValue());
    if (isExclusive(root.getType()))
      for (OpOperand &use : root.getUses())
        if (!isa<ShareOp>(use.getOwner()) && ownership::useOf(use) == ownership::Use::Consume)
          return fail(op, root, "takes a reference to a view of an exclusive value, which "
                                "is then consumed as exclusive (idr.share gives it on as "
                                "owned)");
  }
  if (isa<ConOp, ReuseOp>(op) && isExclusive(op.getResult(0).getType())) {
    if (stack.isAttrPresent(&op))
      return op.emitOpError("builds an exclusive value in the stack frame, whose cell is lent");
    for (Value field : op.getOperands()) {
      auto dup = field.getDefiningOp<DupOp>();
      if (isOwned(field.getType()) && !isExclusive(field.getType()) &&
          isa<BoxType, DataType>(unrestricted(field.getType())) &&
          !(dup && reachesOnlyAtoms(dup.getValue())))
        return fail(op, field, "builds an exclusive value of a field that may be shared");
    }
  }
  // A view of an owned value: the one read of it that is not a use. A
  // view at another quantity (entered into a linear type, or used out of
  // one) is a view of the same value.
  if (isa<BorrowOp>(op) || (isa<LinEnterOp, LinUseOp>(op) && isView(op.getOperand(0)))) {
    if (failed(use(op, op.getOperand(0))))
      return failure();
    define(op.getResult(0), 0, op.getOperand(0), /*borrowed=*/true);
    return success();
  }
  // What the op borrows must be alive for all of it, after what it
  // consumes; a loop's terminator passes both on, the views alive as
  // their owners' references move (walkLoop), so its views are checked
  // before its moves. An owned value is consumed, never read directly: a
  // view of it (idr.borrow) is; a view is read, never consumed: a
  // reference of its own (idr.dup) is.
  SmallVector<Value> consumed, borrowed;
  for (OpOperand &operand : op.getOpOperands()) {
    Value value = operand.get();
    bool consumes = useKind(operand) == ownership::Use::Consume;
    if (tracked(value)) {
      if (!consumes)
        return fail(op, value, "reads an owned value; only a view of it (idr.borrow) is read");
      consumed.push_back(value);
    } else if (isView(value)) {
      if (consumes)
        return fail(op, value, "consumes a view, which holds no reference; a reference of "
                               "its own (idr.dup) is consumed");
      borrowed.push_back(value);
    }
  }
  bool passesOn = isa<scf::ConditionOp, scf::YieldOp>(op) &&
                  isa_and_nonnull<scf::WhileOp, scf::ForOp>(op.getParentOp());
  if (passesOn)
    for (Value value : borrowed)
      if (failed(use(op, value)))
        return failure();
  for (Value value : consumed)
    if (failed(consume(op, value)))
      return failure();
  if (!passesOn)
    for (Value value : borrowed)
      if (failed(use(op, value)))
        return failure();
  for (Value result : op.getResults()) {
    if (tracked(result)) {
      define(result, 1);
    } else if (isView(result)) {
      if (!isa<FieldOp>(op))
        return fail(op, result, "makes a value that holds references and is not owned; only "
                                "a read (idr.field, idr.borrow) makes a view");
      define(result, 0, op.getOperand(0), /*borrowed=*/true);
    }
  }
  if (auto reuse = dyn_cast<ReuseOp>(op))
    return fits(reuse);
  return success();
}

// What a use does, where a loop's terminator passes on a borrowed slot
// or a view (walkLoop).
ownership::Use idr::verify::OwnedWalk::useKind(OpOperand &operand) {
  Operation *op = operand.getOwner();
  Operation *loop = op->getParentOp();
  if (isa_and_nonnull<scf::WhileOp, scf::ForOp>(loop) && isa<scf::ConditionOp, scf::YieldOp>(op)) {
    unsigned slot = operand.getOperandNumber() - (isa<scf::ConditionOp>(op) ? 1 : 0);
    if (slotOwner(loop, slot) || isView(operand.get()))
      return ownership::Use::Borrow;
  }
  if (isa<YieldOp>(op) && op->getParentOp() &&
      passedOn.count(op->getParentOp()->getResult(operand.getOperandNumber())))
    return ownership::Use::Borrow;
  return ownership::useOf(operand);
}

// The token of an idr.reuse comes from an idr.take of a cell of the same
// size. A constructor the module lacks leaves nothing to compare, and the
// module's rules report the type that names it.
LogicalResult idr::verify::OwnedWalk::fits(ReuseOp reuse) {
  auto take = dyn_cast_or_null<TakeOp>(reuse.getToken().getDefiningOp());
  if (!take)
    return reuse.emitOpError("builds in a token that no idr.take made");
  SymbolRefAttr cell = take.getCtorAttr();
  CtorOp from = constructor(cell);
  CtorOp to = constructor(reuse.getCtorAttr());
  if (!from || !to)
    return success();
  // Only a reuse needs the sizes of cells. Layouts that cannot be built
  // have said why, cell by cell, as they were built.
  if (!layouts)
    layouts.emplace(fn->getParentOfType<ModuleOp>().getOperation());
  if (failed(layouts->valid()))
    return failure();
  unsigned have = layouts->box(from).size, need = layouts->box(to).size;
  if (have != need)
    return reuse.emitOpError("builds a cell of ")
           << need << " bytes in the " << have << "-byte cell of " << cell;
  return success();
}
