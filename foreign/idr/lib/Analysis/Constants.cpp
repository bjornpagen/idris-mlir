// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a final body returns, and which ops are never folded.
#include "idr/Analysis/Constants.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <vector>

// The never-folded list, generated with the rewrite graph's tables.
#include "idr/IR/Generated/Rewrites.h.inc"

using namespace mlir;
using mlir::dataflow::ConstantValue;

namespace {

bool beforeId(TypeID a, TypeID b) { return a.getAsOpaquePointer() < b.getAsOpaquePointer(); }

template <class... Ops>
std::vector<TypeID> sortedIds(idr::egraph::table::OpList<Ops...>) {
  std::vector<TypeID> ids{TypeID::get<Ops>()...};
  std::sort(ids.begin(), ids.end(), beforeId);
  return ids;
}

} // namespace

// The list's TypeIDs, which MLIR's open op set leaves to run time, sorted
// once for the process: an op class's TypeID is the same in every context.
idr::Folding idr::foldingOf(Operation *op) {
  static const std::vector<TypeID> never = sortedIds(egraph::generated::NeverFolded{});
  return std::binary_search(never.begin(), never.end(), op->getName().getTypeID(), beforeId)
             ? Folding::Never
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
