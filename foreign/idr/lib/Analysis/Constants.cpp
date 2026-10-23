// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a final body returns, and which ops are never folded.
#include "idr/Analysis/Constants.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

// The never-folded list, generated with the e-graph's tables.
#include "idr/IR/Generated/Rewrites.h.inc"

using namespace mlir;
using mlir::dataflow::ConstantValue;

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
