// cells-fit: after idr-defunctionalize, no box constructor's cell and no
// array element holds more counted references than a header counts: the
// boxes fit made leave each cell only what no box can shrink, and a test
// states that here, by the one measure fit and the layouts use.
export module idr.expect:cellsFit;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :report;

using namespace mlir;

namespace idr::expect {

// Every cell's header counts its object slots.
export LogicalResult cellsFit(ModuleOp module, StringRef) {
  constexpr StringRef property = "cells-fit";
  layout::Components parts(module);
  layout::Holders holders(module);
  bool held = true;
  holders.overflows(parts, [&](Operation *at, ArrayRef<Type>, unsigned objects) {
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
