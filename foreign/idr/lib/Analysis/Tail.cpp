// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position, and tail position modulo a constructor.

#include "idr/Analysis/Tail.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"

using namespace mlir;

namespace idr::tail {

bool endsTail(Block &block) {
  Operation *terminator = block.getTerminator();
  if (isa<ReturnOp>(terminator))
    return true;
  Operation *match = block.getParentOp();
  return isa<YieldOp>(terminator) && isTailMatch(match) && inTailPosition(match);
}

bool inTailPosition(Operation *op) {
  Operation *next = op->getNextNode();
  return next && next->hasTrait<OpTrait::IsTerminator>() &&
         llvm::equal(op->getResults(), next->getOperands()) && endsTail(*op->getBlock());
}

bool passesOnPrevious(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return isa<ReturnOp, YieldOp>(terminator) && prev &&
         llvm::equal(prev->getResults(), terminator->getOperands());
}

bool isTailMatch(Operation *op) { return isa_and_nonnull<MatchOpInterface>(op); }

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
  if (!passesOnPrevious(terminator))
    return std::nullopt;
  auto built = dyn_cast<CellInitOp>(terminator->getPrevNode());
  if (!built)
    return std::nullopt;
  // Allocation is split from construction: the box is its cell's producer
  // and the init that writes it, and the producer may stand between the
  // call and the init. idr-trmc builds the init before the call, so the
  // call moves past the producer as it moves past the init.
  Operation *producer = built.getCell().getDefiningOp();
  auto fields = static_cast<unsigned>(built.getDataType().getCtor(built.getTag()).fields.size());
  for (unsigned index : llvm::seq(fields)) {
    Value source = built.getField(index);
    if (!source)
      continue;
    // The grades on the way: the chain of definitions through ops that
    // only change a grade and have no other use, the call at its end.
    SmallVector<Value, 4> chain = definitionChain(source, [](Value value) -> std::optional<Value> {
      Operation *def = value.getDefiningOp();
      if (!def || !def->hasTrait<ResultCarriesOperand>() || !def->hasOneUse())
        return std::nullopt;
      return def->getOperand(0);
    });
    SmallVector<Operation *, 2> grades;
    for (Value grade : llvm::drop_end(chain))
      grades.push_back(grade.getDefiningOp());
    source = chain.back();
    auto call = source.getDefiningOp<CallOp>();
    if (!call || !isSelfCall(call, fn) || call->getBlock() != &block || !call->hasOneUse() ||
        call->getNumResults() != 1)
      continue;
    // The ops of the block between the call and the init.
    auto between = llvm::make_range(std::next(call->getIterator()), built->getIterator());
    if (llvm::all_of(between, [&](Operation &op) {
          return &op == producer || llvm::is_contained(grades, &op) ||
                 (isMemoryEffectFree(&op) && isSpeculatable(&op));
        }))
      return Modulo{call, built, index, std::move(grades)};
  }
  return std::nullopt;
}

bool inTailPositionModuloConstructor(CallOp call) {
  auto fn = call->getParentOfType<FuncOp>();
  if (!fn || !isSelfCall(call, fn))
    return false;
  Block &block = *call->getBlock();
  std::optional<Modulo> tail = moduloAt(block, fn);
  return tail && tail->call == call && endsTail(block);
}

} // namespace idr::tail
