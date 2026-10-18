// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the owned stage settled about the cells it recycles.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/Conversion/Fields.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The value a field was given on as: through the changes of grade, which
// have no runtime form, to the value that holds the reference. Each step
// goes to an operand, which dominates the op it feeds, so the walk climbs
// the function's finite dominance order and ends.
Value moved(Value value) {
  while (Operation *def = value.getDefiningOp()) {
    if (!def->hasTrait<ResultCarriesOperand>())
      break;
    value = def->getOperand(0);
  }
  return value;
}

} // namespace

Fields::Fields(Operation *program) {
  program->walk([&](CellInitOp init) {
    auto recycle = init.getCell().getDefiningOp<CellRecycleOp>();
    if (!recycle)
      return;
    auto take = recycle.getToken().getDefiningOp<TakeOp>();
    if (!take || take.getDataType() != init.getDataType() || take.getTag() != init.getTag())
      return;
    recycledSame.insert(recycle);
    if (!isExclusive(recycle.getToken().getType()))
      return;
    SmallVector<bool> &mask = keptFields[init];
    for (auto [index, taken] : llvm::enumerate(take.getFields())) {
      Value field = init.getField(static_cast<unsigned>(index));
      mask.push_back(field && moved(field) == taken);
    }
  });
}

bool Fields::sameConstructor(CellRecycleOp recycle) const { return recycledSame.contains(recycle); }

std::optional<ArrayRef<bool>> Fields::kept(CellInitOp init) const {
  auto it = keptFields.find(init);
  if (it == keptFields.end())
    return std::nullopt;
  return ArrayRef<bool>(it->second);
}

} // namespace idr::conversion
