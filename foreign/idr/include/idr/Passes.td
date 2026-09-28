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
  let description = [{
    Matches become scf (LOW-MATCH-1), then a dialect conversion takes every
    idr type apart into its runtime layout and every idr op to arith, scf,
    llvm and calls of the runtime's C functions (LOW-RT-1). Constants become
    static data (LOW-CONST-1). The root, the only public function, becomes
    private, and @main runs it (LOW-ENTRY-1). In JIT mode (LOW-JIT-1), used
    by idr-eval, cells come from the evaluation arena, a crash reports to
    the evaluator, and no @main is made.
  }];
  let options = [
    Option<"jit", "jit", "bool", "false",
           "Lower for compile-time evaluation: arena cells, crashes reported (LOW-JIT-1)">,
  ];
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect",
    "::mlir::math::MathDialect"
  ];
}

// EVAL-1, docs/cutover.md 6.4
def IdrEval : Pass<"idr-eval", "::mlir::ModuleOp"> {
  let summary = "Evaluate closed calls of pure, total functions at compile time";
  let description = [{
    Every call whose operands are all constants, of a function that is pure
    and total (and whose constant operands name only such functions), is run:
    the round's calls are lowered with idr-lower in JIT mode, compiled once
    by ORC's LLJIT and run in a child process, and each result replaces its
    call as constants. A call that crashes stays. Memory or stack the
    machine refuses is the error EVAL-1, which names the call. Results are
    cached per callee and arguments. Remarks: `Passed` with the wall time,
    `Missed` for a crash, in the category idr-eval.
  }];
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect",
    "::mlir::math::MathDialect"
  ];
}

#endif // IDR_PASSES
