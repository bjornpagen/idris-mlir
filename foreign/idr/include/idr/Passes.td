// Passes of the idr dialect (docs/architecture/09-optimization.md, 10-lowering.md).

#ifndef IDR_PASSES
#define IDR_PASSES

include "mlir/Pass/PassBase.td"

def IdrCheckInput : Pass<"idr-check-input", "::mlir::ModuleOp"> {
  let summary = "Check that the module respects the idr contract (IDR-IN-*)";
}

def IdrEntry : Pass<"idr-entry", "::mlir::ModuleOp"> {
  let summary = "Keep the root alive through generic passes: make it public until idr-lower";
}

def IdrTailLoops : Pass<"idr-tail-loops", "::mlir::ModuleOp"> {
  let summary = "Turn self tail calls into loops (LOW-TAIL-*)";
  let dependentDialects = ["::mlir::scf::SCFDialect", "::mlir::ub::UBDialect"];
}

def IdrLower : Pass<"idr-lower", "::mlir::ModuleOp"> {
  let summary = "Lower idr to func, arith, scf, ub and llvm (LOW-*)";
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect"
  ];
}

#endif // IDR_PASSES
