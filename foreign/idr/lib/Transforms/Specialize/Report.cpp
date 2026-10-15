// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-binding-times: a remark on every function, the binding time of each
// of its parameters as the ready set computes it for the function's
// component of the direct calls, free for each parameter of a function on
// no cycle. It changes nothing.
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Specialize.h"
#include "idr/Support/Scc.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/BuiltinOps.h"
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
    SmallVector<idr::FuncOp> functions(getOperation().getOps<idr::FuncOp>());
    llvm::DenseMap<StringAttr, idr::FuncOp> byName;
    for (idr::FuncOp fn : functions)
      byName[fn.getSymNameAttr()] = fn;
    auto callees = [&](idr::FuncOp fn) {
      SmallVector<idr::FuncOp> out;
      fn.walk([&](idr::CallOp call) {
        if (idr::FuncOp callee = byName.lookup(call.getCalleeAttr().getAttr()))
          out.push_back(callee);
      });
      return out;
    };
    llvm::DenseMap<Operation *, SmallVector<idr::BindingTime>> times;
    for (const SmallVector<idr::FuncOp> &component :
         idr::stronglyConnected<idr::FuncOp>(functions, callees))
      for (auto [fn, each] : llvm::zip_equal(component, idr::bindingTimesOf(component)))
        times[idr::FuncOp(fn).getOperation()] = std::move(each);
    for (idr::FuncOp fn : functions) {
      InFlightDiagnostic remark = fn.emitRemark() << "@" << fn.getSymName() << ":";
      for (auto [i, time] : llvm::enumerate(times[fn.getOperation()]))
        remark << (i ? ", " : " ") << idr::nameOf(time);
    }
    markAllAnalysesPreserved();
  }
};

} // namespace
