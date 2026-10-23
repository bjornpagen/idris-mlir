// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a final body returns, which ops are never folded, and which of what
// a fold computed is kept.
#include "idr/Analysis/Constants.h"

#include "idr/IR/Fold.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

// The never-folded list, generated with the e-graph's tables.
#include "idr/IR/Generated/Rewrites.h.inc"

using namespace mlir;
using mlir::dataflow::ConstantValue;
using mlir::dataflow::Lattice;

namespace {

// Whether `id` is one of the listed classes'. The list is a type, fixed
// when the compiler is built, and each class's TypeID is the address of
// its own static, fixed when the compiler is linked: so the test is the
// list's compares, unrolled here, against constants, and nothing is built,
// sorted or guarded when the compiler runs. Which class an op is is the one
// fact MLIR's open op set leaves to run time.
template <class... Ops>
bool listed(idr::egraph::table::OpList<Ops...>, TypeID id) {
  return ((id == TypeID::get<Ops>()) || ...);
}

} // namespace

idr::Folding idr::foldingOf(Operation *op) {
  return listed(egraph::generated::NeverFolded{}, op->getName().getTypeID()) ? Folding::Never
                                                                              : Folding::Folds;
}

// Upstream's folds give a floating-point constant as a FloatAttr, the one
// form a scalar float takes at the stage the solve runs: Emit writes the
// float ops on Doubles alone.
void idr::keepFixed(dataflow::SparseConstantPropagation &analysis, Operation *op,
                    ArrayRef<Lattice<ConstantValue> *> results) {
  if (op->hasTrait<OpTrait::ConstantLike>())
    return;
  for (Lattice<ConstantValue> *result : results) {
    const ConstantValue &value = result->getValue();
    if (value.isUninitialized())
      continue;
    auto real = dyn_cast_or_null<FloatAttr>(value.getConstantValue());
    if (real && fold::ieeeOn(real.getValue()) == fold::Ieee::LeavesOpen)
      analysis.setToEntryState(result);
  }
}

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
