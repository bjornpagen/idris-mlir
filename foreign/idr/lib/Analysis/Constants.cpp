// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The constants summaries of the ready set and the solve that reads them.
// A summary is read from a final body rather than kept from the solve that
// made it: the body is the fact, and nothing has to hold a copy of it
// between the function's last step and its component's end.
#include "idr/Analysis/Constants.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <mutex>

using namespace mlir;
using mlir::dataflow::ConstantValue;

namespace {

// What `fn` returns: per result, the join over its returns of the constant
// an operand is, or unknown where it is none. With no return, nothing
// reaches a caller, and every result stays uninitialized.
idr::ConstantResults returned(idr::FuncOp fn) {
  idr::ConstantResults out(fn.getResultTypes().size());
  for (Block &block : fn.getBody()) {
    auto ret = dyn_cast<idr::ReturnOp>(block.getTerminator());
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

} // namespace

idr::ConstantSummaries::ConstantSummaries(Operation *) {}

std::optional<idr::ConstantResults> idr::ConstantSummaries::lookup(StringAttr callee) const {
  std::shared_lock lock(mutex);
  auto found = published.find(callee);
  if (found == published.end())
    return std::nullopt;
  return found->second;
}

void idr::ConstantSummaries::publish(ArrayRef<FuncOp> component) {
  SmallVector<ConstantResults> results;
  for (FuncOp member : component)
    results.push_back(returned(member));
  std::unique_lock lock(mutex);
  for (auto [member, summary] : llvm::zip_equal(component, results)) {
    FuncOp fn = member;
    published[fn.getSymNameAttr()] = std::move(summary);
  }
}

idr::SummarizedConstantPropagation::SummarizedConstantPropagation(
    DataFlowSolver &solver, const ConstantSummaries &summaries)
    : SparseConstantPropagation(solver), summaries(summaries) {}

void idr::SummarizedConstantPropagation::visitExternalCall(
    CallOpInterface call, ArrayRef<const dataflow::Lattice<ConstantValue> *>,
    ArrayRef<dataflow::Lattice<ConstantValue> *> results) {
  auto direct = dyn_cast<CallOp>(call.getOperation());
  std::optional<ConstantResults> summary =
      direct ? summaries.lookup(direct.getCalleeAttr().getAttr()) : std::nullopt;
  if (!summary)
    return setAllToEntryStates(results);
  assert(summary->size() == results.size() && "a call's results are its callee's");
  for (auto [lattice, value] : llvm::zip_equal(results, *summary))
    propagateIfChanged(lattice, lattice->join(value));
}
