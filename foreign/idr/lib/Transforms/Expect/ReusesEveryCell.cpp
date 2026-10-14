// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reuses-every-cell: every cell a take yields for a constructor with fields
// is reused, not freed.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names, every cell a take yields for a
// constructor with fields is reused: no idr.drop frees one.
LogicalResult reusesEveryCell(ModuleOp module, AnalysisManager &analyses, StringRef function) {
  constexpr StringRef property = "reuses-every-cell";
  SymbolTable &symbols = analyses.getAnalysis<SymbolTable>();
  SmallVector<FunctionOpInterface> functions = named(module, symbols, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](DropOp drop) {
      auto take = drop.getValue().getDefiningOp<TakeOp>();
      if (!take || drop.getValue() != take.getToken())
        return;
      SymbolRefAttr ctor = take.getCtor();
      // A constructor without fields is a static cell, never the program's
      // to reuse.
      if (CtorOp decl = lookupCtor(symbols, ctor); decl && decl.getFieldTypes().empty())
        return;
      fail(drop.getLoc(), property) << "the cell of " << ctor << " is freed, not reused, in "
                                    << where(drop);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
