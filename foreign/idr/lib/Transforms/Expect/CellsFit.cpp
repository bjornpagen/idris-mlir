// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// cells-fit: after idr-defunctionalize, no box constructor's cell and no
// array element holds more counted references than a header counts: the
// boxes fit made leave each cell only what no box can shrink, and a test
// states that here, by the one measure fit and the layouts use.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

using namespace mlir;

namespace idr::expect {

// Every cell's header counts its object slots. Layouts that cannot be
// built have said why at each cell, so the property fails with them.
LogicalResult cellsFit(ModuleOp module, AnalysisManager &analyses, StringRef) {
  constexpr StringRef property = "cells-fit";
  Layouts &layouts = analyses.getAnalysis<Layouts>();
  bool held = succeeded(layouts.valid());
  layout::Holders holders(module);
  holders.overflows(layouts, [&](Operation *at, ArrayRef<Type>, unsigned objects) {
    InFlightDiagnostic diag = fail(at->getLoc(), property);
    if (auto ctor = dyn_cast<CtorOp>(at))
      diag << "the cell of @" << ctor->getParentOfType<DataOp>().getSymName() << "::@"
           << ctor.getSymName();
    else
      diag << "an element of an array of @" << cast<DataOp>(at).getSymName();
    diag << " holds " << objects << " counted references, and a header counts at most "
         << layout::mostObjects;
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
