// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-binding-times: a remark on every function, the binding time of each
// of its parameters as the ready set computes it for the function's cycle
// of calls (CallCycles), the one idr-optimize goes through: fixed for each
// parameter of a function on no cycle. It changes nothing.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/BindingTimes.h"
#include "idr/Analysis/CallCycles.h"
#include "idr/Transforms/Pipeline.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/Diagnostics.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRBINDINGTIMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct ReportBindingTimes : idr::impl::IdrBindingTimesBase<ReportBindingTimes> {
  void runOnProgram(idr::ProgramOp) override {
    // A first-order program's callables are its functions.
    for (const idr::CallCycles::Component &component :
         getAnalysis<idr::CallCycles>().components()) {
      SmallVector<idr::FuncOp> members =
          llvm::map_to_vector(component, [](Operation *op) { return cast<idr::FuncOp>(op); });
      for (idr::FuncOp fn : members) {
        InFlightDiagnostic remark = fn.emitRemark() << "@" << fn.getSymName() << ":";
        for (auto [i, time] : llvm::enumerate(idr::bindingTimesOf(fn, members)))
          remark << (i ? ", " : " ") << idr::nameOf(time);
      }
    }
    markAllAnalysesPreserved();
  }
};

} // namespace
