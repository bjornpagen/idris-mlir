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
namespace {

// The box `op` builds, when it is an idr.con or idr.reuse of a boxed type.
std::optional<Built> builtBox(Operation *op) {
  if (!op || op->getNumResults() == 0 || !isa<BoxType>(unrestricted(op->getResult(0).getType())))
    return std::nullopt;
  if (auto con = dyn_cast<ConOp>(op))
    return Built(con);
  if (auto reuse = dyn_cast<ReuseOp>(op))
    return Built(reuse);
  return std::nullopt;
}

// The value `built` builds its field `index` of, or null for a hole, and
// how many fields its constructor has.
Value fieldOf(const Built &built, unsigned index) {
  return std::visit([&](auto op) { return op.getField(index); }, built);
}

size_t fieldCount(const Built &built) {
  return std::visit([](auto op) { return op.getDataType().getCtor(op.getTag()).fields.size(); },
                    built);
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

Operation *opOf(const Built &built) {
  return std::visit([](auto op) -> Operation * { return op.getOperation(); }, built);
}

std::optional<Modulo> moduloAt(Block &block, FuncOp fn) {
  Operation *terminator = block.getTerminator();
  if (!passesOnPrevious(terminator))
    return std::nullopt;
  std::optional<Built> built = builtBox(terminator->getPrevNode());
  if (!built)
    return std::nullopt;
  for (unsigned index : llvm::seq(static_cast<unsigned>(fieldCount(*built)))) {
    Value source = fieldOf(*built, index);
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
    // The ops of the block between the call and the constructor.
    auto between = llvm::make_range(std::next(call->getIterator()), opOf(*built)->getIterator());
    if (llvm::all_of(between, [&](Operation &op) {
          return llvm::is_contained(grades, &op) || (isMemoryEffectFree(&op) && isSpeculatable(&op));
        }))
      return Modulo{call, *built, index, std::move(grades)};
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
