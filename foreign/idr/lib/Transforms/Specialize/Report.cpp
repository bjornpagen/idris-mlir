// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-binding-times: a remark on every function, the binding time of each
// of its parameters as the ready set computes it for the function's
// component of upstream's call graph, the one idr-optimize goes through,
// free for each parameter of a function on no cycle. It changes nothing.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/IR/Diagnostics.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRBINDINGTIMES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct ReportBindingTimes : idr::impl::IdrBindingTimesBase<ReportBindingTimes> {
  void runOnOperation() override {
    idr::ProgramOp program = getOperation();
    CallGraph graph(program);
    llvm::DenseMap<Operation *, SmallVector<idr::BindingTime>> times;
    for (const SmallVector<idr::FuncOp> &component : idr::callGraphComponents(graph))
      for (auto [fn, each] : llvm::zip_equal(component, idr::bindingTimesOf(component)))
        times[idr::FuncOp(fn).getOperation()] = std::move(each);
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>()) {
      InFlightDiagnostic remark = fn.emitRemark() << "@" << fn.getSymName() << ":";
      for (auto [i, time] : llvm::enumerate(times[fn.getOperation()]))
        remark << (i ? ", " : " ") << idr::nameOf(time);
    }
    markAllAnalysesPreserved();
  }
};

} // namespace
