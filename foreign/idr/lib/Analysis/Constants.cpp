// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a final body returns, and the solve that reads it at each call.
#include "idr/Analysis/Constants.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>

using namespace mlir;
using mlir::dataflow::ConstantValue;

// Per result, the join over the returns of the constant an operand is, or
// unknown where it is none. With no return, nothing reaches a caller, and
// every result stays uninitialized.
idr::ConstantResults idr::returnedConstants(FuncOp fn) {
  ConstantResults out(fn.getResultTypes().size());
  for (Block &block : fn.getBody()) {
    auto ret = dyn_cast<ReturnOp>(block.getTerminator());
    if (!ret)
      continue;
    for (auto [value, operand] : llvm::zip_equal(out, ret.getOperands())) {
      Attribute constant;
      ConstantValue held = matchPattern(operand, m_Constant(&constant))
                               ? ConstantValue(constant, operand.getDefiningOp()->getDialect())
                               : ConstantValue::getUnknownConstant();
      value = ConstantValue::join(value, held);
    }
  }
  return out;
}

idr::SummarizedConstantPropagation::SummarizedConstantPropagation(DataFlowSolver &solver,
                                                                   ConstantsOf constantsOf)
    : SparseConstantPropagation(solver), constantsOf(constantsOf) {}

void idr::SummarizedConstantPropagation::visitExternalCall(
    CallOpInterface call, ArrayRef<const dataflow::Lattice<ConstantValue> *>,
    ArrayRef<dataflow::Lattice<ConstantValue> *> results) {
  auto direct = dyn_cast<CallOp>(call.getOperation());
  const ConstantResults *summary = direct ? constantsOf(direct.getCalleeAttr().getAttr()) : nullptr;
  if (!summary)
    return setAllToEntryStates(results);
  assert(summary->size() == results.size() && "a call's results are its callee's");
  for (auto [lattice, value] : llvm::zip_equal(results, *summary))
    propagateIfChanged(lattice, lattice->join(value));
}
