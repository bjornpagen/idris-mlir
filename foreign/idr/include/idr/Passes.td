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

def IdrLower : Pass<"idr-lower", "::mlir::ModuleOp"> {
  let summary = "Lower idr to func, arith, math, scf, ub and llvm (LOW-*)";
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect",
    "::mlir::math::MathDialect"
  ];
}

//===----------------------------------------------------------------------===//
// The optimization passes (docs/cutover.md 6.3; lib/Passes/)
//===----------------------------------------------------------------------===//

def IdrSpecialize : Pass<"idr-specialize", "::mlir::ModuleOp"> {
  let summary = "Clone callees for calls with constant-like arguments (ELIM-SPEC-1)";
  let description = [{
    A `func.call` with an argument built from constants, `idr.con` or
    `idr.closure` gets a clone of its callee with that static part
    substituted; the runtime leaves become the clone's parameters. Clones are
    shared by (callee, pattern) and named `@<origin>$spec$<n>` in the order
    they are first requested. A closed call is left to `idr-eval`. The only
    bound is `clone-limit` clones per original callee; a call it stops gets a
    `Missed` remark, and its callee the attribute `idr.clone_limit_hit`.
  }];
  let options = [
    Option<"cloneLimit", "clone-limit", "unsigned", "4096",
           "The number of clones made of one original callee, in total">,
  ];
  let dependentDialects = ["::mlir::arith::ArithDialect"];
}

def IdrDefunctionalize : Pass<"idr-defunctionalize", "::mlir::ModuleOp"> {
  let summary = "Replace closures of known labels by sums (ELIM-CLOS-1)";
  let description = [{
    A sparse dataflow analysis finds the labels each `!idr.fn` value may
    hold. A closure type whose values all have known labels, and whose
    captures do not contain the type again, becomes a sum with one
    constructor per label: `idr.closure` becomes `idr.con` and `idr.apply`
    an `idr.match` that calls the label.
  }];
}

def IdrTailLoops : Pass<"idr-tail-loops", "::mlir::ModuleOp"> {
  let summary = "Turn self tail calls into scf.while loops (LOW-TAIL-5)";
  let description = [{
    A function that calls itself in tail position, directly or through the
    regions of matches whose results it returns, becomes one `scf.while`.
    A function without `idr.total` gets `idr.may_loop` in its loop
    (LOW-TAIL-4, SEM-EVAL-5).
  }];
  let dependentDialects = ["::mlir::scf::SCFDialect", "::mlir::ub::UBDialect",
                           "::mlir::arith::ArithDialect"];
}

def IdrCheckProfile : Pass<"idr-check-profile", "::mlir::ModuleOp"> {
  let summary = "Reject what would allocate at runtime (PROF-HEAP-*, PROF-DATA-3, PROF-PRIM-4, PROF-TYPE-4)";
  let description = [{
    Reports the first violation in op order as `unsupported (<RULE>): ...`
    at the innermost user location (DIAG-LOC-1), and fails.
  }];
}

def IdrSimplify : Pass<"idr-simplify", "::mlir::ModuleOp"> {
  let summary = "Repeat the simplify round until it changes nothing (OPT-PIPE-5)";
  let description = [{
    Runs idr-effects, inline, idr-specialize, sccp, canonicalize, cse,
    idr-eval, remove-dead-values and symbol-dce, again and again, until a
    round leaves the module's fingerprint unchanged.
  }];
  let options = [
    Option<"inlineIterations", "inline-iterations", "unsigned", "4",
           "max-iterations of the inliner in each round (K)">,
    Option<"cloneLimit", "clone-limit", "unsigned", "4096",
           "clone-limit of idr-specialize">,
  ];
}

#endif // IDR_PASSES
