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

//===----------------------------------------------------------------------===//
// The optimization passes (docs/cutover.md 6.3; lib/Passes/)
//===----------------------------------------------------------------------===//

def IdrLoopBreakers : Pass<"idr-loop-breakers", "::mlir::ModuleOp"> {
  let summary = "Keep a loop breaker in every cycle of references (OPT-PIPE-3)";
  let description = [{
    A function refers to what it calls and to the functions its closures and
    closure constants name. In every cycle of such references among the
    functions that may be inlined, one becomes `no_inline`: the newest
    clone, or else the first function in module order that is not from a
    library. The first step of every round of `idr-simplify`, so that the
    inliner never unrolls a cycle the previous round closed.
  }];
}

def IdrSpecialize : Pass<"idr-specialize", "::mlir::ModuleOp"> {
  let summary = "Clone callees for calls with constant-like arguments (ELIM-SPEC-1)";
  let description = [{
    A `func.call` with an argument built from constants, `idr.con` or
    `idr.closure` gets a clone of its callee with that static part
    substituted; the runtime leaves become the clone's parameters. Clones are
    shared by (callee, pattern) and named `@<origin>$spec$<n>` in the order
    they are first requested. A closed call is left to `idr-eval`. The only
    bound is `clone-limit` clones per original callee; a call it stops gets a
    `Missed` remark, and its callee the attribute `idr.spec_stopped`.
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
    hold. Sums are keyed by (closure type, label set): each slot (value,
    argument, result, field) of a key whose labels are known and fit, and
    which is on no cycle of "a capture of its labels holds a value of that
    key", becomes a sum with one constructor per label, whose fields are the
    label's captures: `idr.closure` becomes `idr.con` and `idr.apply` an
    `idr.match` that calls the label. Where a value moves between slots of
    different keys, a match rebuilds it in the other sum, or as a closure.
  }];
  let dependentDialects = ["::mlir::ub::UBDialect"];
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

def IdrPrune : Pass<"idr-prune", "::mlir::ModuleOp"> {
  let summary = "Empty the code dead-code analysis proves unreachable (OPT-PIPE-5)";
  let description = [{
    Runs right before `remove-dead-values`, with the analyses it runs: a
    match region they never reach ends in `ub.unreachable`, and a function
    they never reach returns `ub.poison`. At the pin, `remove-dead-values`
    crashes on such code (`PINS.md`: `prune-before-remove-dead-values`).
  }];
  let dependentDialects = ["::mlir::ub::UBDialect"];
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
    Runs idr-loop-breakers, idr-effects, inline, idr-specialize, sccp,
    canonicalize, cse, idr-eval, idr-prune, symbol-dce, remove-dead-values
    and symbol-dce, again and again, until a round leaves the module unchanged,
    up to where constants are.
  }];
  let options = [
    Option<"inlineIterations", "inline-iterations", "unsigned", "4",
           "max-iterations of the inliner in each round (K)">,
    Option<"cloneLimit", "clone-limit", "unsigned", "4096",
           "clone-limit of idr-specialize">,
  ];
}

#endif // IDR_PASSES
