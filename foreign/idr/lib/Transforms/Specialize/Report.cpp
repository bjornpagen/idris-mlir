// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-binding-times: a remark on every function with a body, the binding
// time of each of its parameters as idr-specialize decides on it, free for
// each parameter of a function on no cycle. It changes nothing.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRBINDINGTIMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct ReportBindingTimes : idr::impl::IdrBindingTimesBase<ReportBindingTimes> {
  void runOnOperation() override {
    const idr::BindingTimes &times = getAnalysis<idr::BindingTimes>();
    for (auto fn : getOperation().getOps<idr::FuncOp>()) {
      if (fn.isExternal())
        continue;
      InFlightDiagnostic remark = fn.emitRemark() << "@" << fn.getSymName() << ":";
      for (auto [i, time] : llvm::enumerate(times.of(fn.getSymNameAttr())))
        remark << (i ? ", " : " ") << idr::nameOf(time);
    }
    markAllAnalysesPreserved();
  }
};

} // namespace
