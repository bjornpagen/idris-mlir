// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// typed-reads: an access at an index Idris typed below its extent needs no
// guard, so none is written and no pass has to remove one. Stated as the
// absence of a guard among the indices a tensor access takes.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"

using namespace mlir;

namespace idr::expect {

namespace {

// The guard an index comes from, through the casts that only change its
// width; null when it comes from none.
Operation *guardOf(Value index) {
  Operation *def = index.getDefiningOp();
  while (isa_and_nonnull<arith::IndexCastOp, arith::IndexCastUIOp>(def))
    def = def->getOperand(0).getDefiningOp();
  return isa_and_nonnull<GuardOpInterface>(def) ? def : nullptr;
}

// The indices `op` reads or writes a tensor at, if it is a tensor access:
// an element's coordinates, or a slice's dynamic offsets.
std::optional<ValueRange> indicesOf(Operation *op) {
  if (auto extract = dyn_cast<tensor::ExtractOp>(op))
    return ValueRange(extract.getIndices());
  if (auto insert = dyn_cast<tensor::InsertOp>(op))
    return ValueRange(insert.getIndices());
  if (auto slice = dyn_cast<tensor::ExtractSliceOp>(op))
    return ValueRange(slice.getOffsets());
  if (auto slice = dyn_cast<tensor::InsertSliceOp>(op))
    return ValueRange(slice.getOffsets());
  return std::nullopt;
}

} // namespace

// In the function the argument names, no index of a tensor access is a
// guard's result, and it accesses a tensor at least once.
LogicalResult typedReads(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "typed-reads";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true, accessed = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      std::optional<ValueRange> indices = indicesOf(op);
      if (!indices)
        return;
      accessed = true;
      for (Value index : *indices)
        if (Operation *guard = guardOf(index)) {
          fail(op->getLoc(), property) << op->getName() << " in " << where(op)
                                       << " takes an index " << guard->getName() << " checked";
          held = false;
        }
    });
  if (!accessed) {
    fail(functions.front()->getLoc(), property) << "no tensor is accessed in " << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
