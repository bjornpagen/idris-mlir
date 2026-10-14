// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position, and tail position modulo a constructor.

#include "idr/Analysis/Tail.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::tail {
namespace {

// Whether `op` builds a box: an idr.con or idr.reuse of a boxed type.
bool buildsBox(Operation *op) {
  return isa_and_nonnull<ConOp, ReuseOp>(op) && isa<BoxType>(unrestricted(op->getResult(0).getType()));
}

// The operands of the box an idr.con or idr.reuse builds that are its
// fields: an idr.reuse takes the cell it reuses first.
MutableArrayRef<OpOperand> fieldsOf(Operation *op) {
  if (auto con = dyn_cast<ConOp>(op))
    return con.getFieldsMutable();
  return cast<ReuseOp>(op).getFieldsMutable();
}

} // namespace

bool inTailPosition(Operation *op) {
  Operation *next = op->getNextNode();
  if (!next || !next->hasTrait<OpTrait::IsTerminator>() ||
      !llvm::equal(op->getResults(), next->getOperands()))
    return false;
  if (isa<ReturnOp>(next))
    return true;
  Operation *match = next->getParentOp();
  return isa<YieldOp>(next) && isTailMatch(match) && inTailPosition(match);
}

bool passesOnPrevious(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return isa<ReturnOp, YieldOp>(terminator) && prev &&
         llvm::equal(prev->getResults(), terminator->getOperands());
}

bool isTailMatch(Operation *op) { return isa_and_nonnull<MatchOp, MatchLitOp>(op); }

Operation *tailMatch(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return passesOnPrevious(terminator) && isTailMatch(prev) ? prev : nullptr;
}

bool isSelfCall(Operation *op, FuncOp fn) {
  auto call = dyn_cast_or_null<CallOp>(op);
  return call && call.getCallee() == fn.getSymName();
}

std::optional<Modulo> moduloAt(Block &block, FuncOp fn) {
  Operation *terminator = block.getTerminator();
  Operation *built = terminator->getPrevNode();
  if (!passesOnPrevious(terminator) || !buildsBox(built))
    return std::nullopt;
  for (auto [index, field] : llvm::enumerate(fieldsOf(built))) {
    SmallVector<Operation *, 2> grades;
    Value source = field.get();
    while (Operation *def = source.getDefiningOp()) {
      if (!isa<LinEnterOp, LinUseOp>(def) || !def->hasOneUse())
        break;
      grades.push_back(def);
      source = def->getOperand(0);
    }
    auto call = source.getDefiningOp<CallOp>();
    if (!call || !isSelfCall(call, fn) || call->getBlock() != &block || !call->hasOneUse() ||
        call->getNumResults() != 1)
      continue;
    bool movable = true;
    for (Operation *op = call->getNextNode(); op != built; op = op->getNextNode())
      movable = movable &&
                (llvm::is_contained(grades, op) || (isMemoryEffectFree(op) && isSpeculatable(op)));
    if (movable)
      return Modulo{call, built, static_cast<unsigned>(index), &field, std::move(grades)};
  }
  return std::nullopt;
}

bool inTailPositionModuloConstructor(CallOp call) {
  auto fn = call->getParentOfType<FuncOp>();
  if (!fn || !isSelfCall(call, fn))
    return false;
  Block &block = *call->getBlock();
  std::optional<Modulo> tail = moduloAt(block, fn);
  if (!tail || tail->call != call)
    return false;
  Operation *terminator = block.getTerminator();
  Operation *match = terminator->getParentOp();
  return isa<ReturnOp>(terminator) || (isTailMatch(match) && inTailPosition(match));
}

} // namespace idr::tail
