// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a final body returns.
#include "idr/Analysis/Constants.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using mlir::dataflow::ConstantValue;

// Per result, the constant the return's operand is, or unknown where it is
// none. A body that ends without returning (its one block ends in a crash)
// reaches no caller, and every result stays uninitialized.
idr::ConstantResults idr::returnedConstants(FuncOp fn) {
  ConstantResults out(fn.getResultTypes().size());
  auto ret = dyn_cast<ReturnOp>(fn.getBody().front().getTerminator());
  if (!ret)
    return out;
  for (auto [value, operand] : llvm::zip_equal(out, ret.getOperands())) {
    Attribute constant;
    value = matchPattern(operand, m_Constant(&constant))
                ? ConstantValue(constant, operand.getDefiningOp()->getDialect())
                : ConstantValue::getUnknownConstant();
  }
  return out;
}
