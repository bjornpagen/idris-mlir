// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a final body returns, and the solve that reads it at each call.
#include "idr/Analysis/Constants.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using mlir::dataflow::ConstantValue;

// Per result, the constant the return's operand is, or unknown where it is
// none.
idr::ConstantResults idr::returnedConstants(FuncOp fn) {
  ConstantResults out(fn.getResultTypes().size());
  // A body that ends in ub.unreachable never returns: nothing reaches a
  // caller, and every result stays uninitialized.
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

idr::SummarizedConstantPropagation::SummarizedConstantPropagation(DataFlowSolver &solver,
                                                                   ConstantsOf constantsOf)
    : SparseConstantPropagation(solver), constantsOf(constantsOf) {}

// idr-optimize runs on the first-order stage, whose only call is an idr.call.
void idr::SummarizedConstantPropagation::visitExternalCall(
    CallOpInterface call, ArrayRef<const dataflow::Lattice<ConstantValue> *>,
    ArrayRef<dataflow::Lattice<ConstantValue> *> results) {
  ConstantResults returned = constantsOf(cast<CallOp>(call.getOperation()));
  for (auto [lattice, value] : llvm::zip_equal(results, returned))
    propagateIfChanged(lattice, lattice->join(value));
}
