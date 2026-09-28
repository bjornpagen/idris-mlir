// Passes of the idr dialect (docs/cutover.md, section 6.3).

#ifndef IDR_PASSES
#define IDR_PASSES

include "mlir/Pass/PassBase.td"

// IDR-FACT-1
def IdrEffects : Pass<"idr-effects", "::mlir::ModuleOp"> {
  let summary = "Compute idr.effect and idr.may_crash on every function";
  let description = [{
    A function is "effectful" if it reaches an idr.io op, directly, through
    calls, or through the functions of the closures it creates; otherwise it
    is "pure". It may crash (`idr.may_crash`) if it reaches an op that may
    crash the same way. A call of a function without a body, or of anything
    but a func.func, reaches both.
  }];
}

def IdrLower : Pass<"idr-lower", "::mlir::ModuleOp"> {
  let summary = "Lower idr to func, arith, math, scf, ub and llvm (LOW-*)";
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect",
    "::mlir::math::MathDialect"
  ];
}

#endif // IDR_PASSES
