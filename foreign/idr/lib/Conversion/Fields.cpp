// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the owned stage settled about the fields of the ops that count
// references.

#include "idr/IR/IdrDialect.h"
#include "idr/Conversion/Fields.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The value a field was given on as: through the changes of grade, which
// have no runtime form, to the value that holds the reference.
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
  program->walk([&](ReuseOp reuse) {
    auto take = reuse.getToken().getDefiningOp<TakeOp>();
    if (!take || take.getDataType() != reuse.getDataType() || take.getTag() != reuse.getTag())
      return;
    SmallVector<bool> &mask = keptFields[reuse];
    for (auto [index, taken] : llvm::enumerate(take.getFields())) {
      Value field = reuse.getField(static_cast<unsigned>(index));
      mask.push_back(field && moved(field) == taken);
    }
  });
}

ArrayRef<bool> Fields::kept(ReuseOp reuse) const {
  auto it = keptFields.find(reuse);
  return it == keptFields.end() ? ArrayRef<bool>() : ArrayRef<bool>(it->second);
}

} // namespace idr::conversion
