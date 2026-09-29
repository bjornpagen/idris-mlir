// Passes of the idr dialect.

#ifndef IDR_PASSES
#define IDR_PASSES

include "mlir/Pass/PassBase.td"
include "mlir/Rewrite/PassUtil.td"

def IdrEffects : Pass<"idr-effects", "::mlir::ModuleOp"> {
  let summary = "Compute idr.effects on every function";
  let description = [{
    `idr.effects = #idr.effects<io, crash>` says what a call of a function
    may do besides computing its results. `io`: it takes a world, as a
    parameter or in data a parameter holds; worlds reach a function only
    that way, so a function that only builds IO actions is not `io`.
    `crash`: it reaches an op that may crash, through calls and through the
    labels of the closures it makes (`idr.closure`, closure constants, and
    the constructors of idr-defunctionalize's sums of closures). A function
    without a body, and every function that reaches one or calls anything
    but a func.func, gets both. `#idr.effects<none>` is neither.
  }];
  let statistics = [
    Statistic<"numIO", "io", "Functions that get io">,
    Statistic<"numCrash", "crash", "Functions that get crash">,
  ];
}

def IdrLower : Pass<"idr-lower", "::mlir::ModuleOp"> {
  let summary = "Lower idr to func, arith, math, scf, ub and llvm";
  let description = [{
    Matches become scf, then a dialect conversion takes every idr type apart
    into its runtime layout and every idr op to arith, scf, llvm and calls of
    the runtime's C functions. Constants become static data. The root, the
    only public function, becomes private, and @main runs it. In JIT mode,
    used by idr-eval, cells come from the evaluation arena, a crash reports
    to the evaluator, code ticks the evaluator's meter (on entry to every
    function, and at `idr.may_loop`), and no @main is made.
  }];
  let options = [
    Option<"jit", "jit", "bool", "false",
           "Lower for compile-time evaluation: arena cells, crashes reported">,
  ];
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect",
    "::mlir::math::MathDialect"
  ];
}

def IdrEval : Pass<"idr-eval", "::mlir::ModuleOp"> {
  let summary = "Evaluate closed calls of functions that perform no IO at compile time";
  let description = [{
    Every call whose operands are all constants, of a function that has a
    body and performs no IO (and whose constant operands name only such
    functions as closures), is run: the round's calls are lowered with
    idr-lower in JIT mode, compiled once by ORC's LLJIT and run in a child
    process, and each result replaces its call as constants. Every call runs
    metered, within a budget of ticks (counted where code enters a function
    or goes round a loop), arena bytes and stack; a call that reaches only
    total code gets a larger budget than one that reaches a function
    without `idr.total`. A call that crashes, spends its budget, or is
    refused memory by the machine stays. Results are cached per callee and
    arguments. Remarks: `Passed` with the wall time, `Missed` for a crash
    and for a call that did not finish, in the category idr-eval.
    Replacing one call by its results is the action `idr-eval-call`.
  }];
  let statistics = [
    Statistic<"numEvaluated", "evaluated", "Calls replaced by their results">,
    Statistic<"numStayedCrash", "stayed-crash", "Calls that crash, left to run at runtime">,
    Statistic<"numStayedBudget", "stayed-budget",
              "Metered calls that did not finish, left to run at runtime">,
    Statistic<"numCacheHits", "cache-hits",
              "Closed calls whose outcome an earlier run of the pass knew">,
  ];
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect",
    "::mlir::math::MathDialect"
  ];
}

//===----------------------------------------------------------------------===//
// The optimization passes (lib/Passes/)
//===----------------------------------------------------------------------===//

def IdrLoopBreakers : Pass<"idr-loop-breakers", "::mlir::ModuleOp"> {
  let summary = "Keep a loop breaker in every cycle of references ";
  let description = [{
    A function refers to what it calls and to the functions its closures and
    closure constants name. In every cycle of such references among the
    functions that may be inlined, one becomes `no_inline`: the newest
    clone, or else the first function in module order that is not from a
    library. The first step of every round of `idr-simplify`, so that the
    inliner never unrolls a cycle the previous round closed.
  }];
  let statistics = [
    Statistic<"numBreakers", "breakers", "Functions made loop breakers">,
  ];
}

def IdrSpecialize : Pass<"idr-specialize", "::mlir::ModuleOp"> {
  let summary = "Clone callees for consumed results and static arguments";
  let description = [{
    Raising comes first: a `func.call` whose result is only applied
    (`idr.apply`, possibly of an `idr.field` of it) or written
    (`idr.io.put_str`), with nothing that has an effect in between, calls
    instead a clone that takes the apply's arguments or the world too,
    keyed by (callee, consumer); the consumer moves to the clone's tails.

    A `func.call` with a static argument (built from constants, `idr.con`
    and `idr.closure`) calls a clone of its callee with that argument
    substituted, whose parameters are the runtime leaves, when the
    parameter's binding time allows it: any argument when the callee is on
    no cycle of references, else that of a fixed parameter, or of a
    decreasing or bounded one when the static value is small
    (`idr-binding-times` reports the binding times). A closed call is left
    to `idr-eval`. Clones are shared by key (the function first cloned, and
    the patterns of its parameters); a key goes into the table before its
    clone is simplified, so a clone's calls with its own key are self calls.
    More clones of one function than a fixed budget is the error
    `unsupported (compile-time budget)`, which names the function.
  }];
  let statistics = [
    Statistic<"numClones", "clones", "Clones made to specialize a call">,
    Statistic<"numRaised", "raised", "Clones made to raise a call">,
    Statistic<"numShared", "shared", "Calls redirected to a clone made before">,
    Statistic<"numFree", "free", "Static arguments of callees on no cycle">,
    Statistic<"numFixed", "fixed", "Static arguments of fixed parameters">,
    Statistic<"numDecreasing", "decreasing", "Static arguments of decreasing parameters">,
    Statistic<"numBounded", "bounded", "Static arguments of bounded parameters">,
  ];
  let dependentDialects = ["::mlir::arith::ArithDialect"];
}

def IdrBindingTimes : Pass<"idr-binding-times", "::mlir::ModuleOp"> {
  let summary = "Report the binding time of every parameter";
  let description = [{
    A remark on every function with a body: `not recursive` for one on no
    cycle of references, or else the binding time of each parameter as
    idr-specialize finds it: fixed, decreasing, bounded or other. It changes
    nothing.
  }];
}

def IdrInline : Pass<"idr-inline", "::mlir::ModuleOp"> {
  let summary = "Inline calls by MLton's size rule";
  let description = [{
    MLIR's inliner, which runs `default-pipeline` on each function before
    it inlines into it, deciding what to inline as MLton does: a function
    that calls nothing and has at most 40 ops, and any function on no cycle
    of calls for which (calls - 1) * (size - 60) <= 320, sizes counted in
    ops, calls in call sites and in closures that name the function. The
    decisions are taken once, before anything is inlined, from the callees
    up.
  }];
  let options = [
    Option<"defaultPipeline", "default-pipeline", "std::string", "\"canonicalize\"",
           "The pipeline run on each function before inlining into it">,
    Option<"maxIterations", "max-iterations", "unsigned", "0",
           "Rounds of simplifying and inlining per group of functions; 0, the "
           "default, until one inlines nothing">,
  ];
  let statistics = [
    Statistic<"numInlinable", "inlinable", "Functions the size rule lets inline">,
    Statistic<"numLeaves", "leaves", "Of those, functions that call nothing">,
  ];
}

def IdrDefunctionalize : Pass<"idr-defunctionalize", "::mlir::ModuleOp"> {
  let summary = "Replace closures of known labels by sums";
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
  let statistics = [
    Statistic<"numSums", "sums", "Keys whose closures became sums">,
    Statistic<"numClosures", "closures", "Keys whose closures stay closures">,
  ];
}

def IdrTailLoops : Pass<"idr-tail-loops", "::mlir::ModuleOp"> {
  let summary = "Turn self tail calls into scf.while loops";
  let description = [{
    A function that calls itself in tail position, directly or through the
    regions of matches whose results it returns, becomes one `scf.while`.
    A function without `idr.total` gets `idr.may_loop` in its loop.
  }];
  let dependentDialects = ["::mlir::scf::SCFDialect", "::mlir::ub::UBDialect",
                           "::mlir::arith::ArithDialect"];
  let statistics = [
    Statistic<"numLoops", "loops", "Functions whose self tail calls became a loop">,
  ];
}

def IdrStack : Pass<"idr-stack", "::mlir::ModuleOp"> {
  let summary = "Put the cells of boxes that never leave their frame on the stack";
  let description = [{
    Marks an `idr.con` of a box with the unit attribute `idr.stack` when no
    reference to its cell can outlive the frame of the function that builds
    it, nor the loop iteration that builds it. A reference escapes when it
    is returned, captured by a closure, applied to an unknown function,
    forwarded by a terminator of a loop around the con, passed to a call of
    the con's own function (which idr-tail-loops may make the next
    iteration of a loop), passed to a parameter that escapes (the
    parameters are summarized over the module's calls), used by an op the
    analysis does not know, or stored in a constructor whose value escapes
    or whose fields are read into something that escapes. idr-lower builds
    a marked cell in a slot of its function's entry block, with the stack
    mark in its header. A cell of more than 256 bytes stays on the heap,
    and so do a function's cells past 1024 bytes, or 64 bytes for a
    function on a cycle of calls. Any `idr.stack` already present is
    recomputed.
  }];
  // A cell's size is idr-lower's layout, whose components are LLVM types.
  let dependentDialects = ["::mlir::LLVM::LLVMDialect"];
  let statistics = [
    Statistic<"numBoxes", "boxes", "Constructors of boxes seen">,
    Statistic<"numCells", "cells", "Constructors of boxes put on the stack">,
  ];
}

def IdrPrune : Pass<"idr-prune", "::mlir::ModuleOp"> {
  let summary = "Empty the code dead-code analysis proves unreachable";
  let description = [{
    Runs right before `remove-dead-values`, with the analyses it runs: a
    match region they never reach ends in `ub.unreachable`, and a function
    they never reach returns `ub.poison`. At the pin, `remove-dead-values`
    crashes on such code (`PINS.md`: `prune-before-remove-dead-values`).
    A call of a function that a closure names passes `ub.poison` for each
    parameter the function never reads, which `remove-dead-values` would
    otherwise leave null (`PINS.md`: `remove-dead-values-address-taken`).
  }];
  let dependentDialects = ["::mlir::ub::UBDialect"];
  let statistics = [
    Statistic<"numEmptied", "emptied", "Unreachable function bodies and match regions emptied">,
    Statistic<"numPoisoned", "poisoned", "Unread parameters passed poison">,
  ];
}

def IdrCanonicalize : Pass<"idr-canonicalize"> {
  let summary = "canonicalize, with the rewrites of each pattern counted";
  let description = [{
    Collects the patterns `canonicalize` collects (those of every loaded
    dialect and every registered op, filtered by the same options) and runs
    the same greedy driver with the same configuration, so it leaves what
    `canonicalize` leaves; a listener counts the patterns that apply. The
    counts by pattern are an `Analysis` remark, and a run that stops before
    its fixpoint is a `Missed` remark, in the category idr-canonicalize.
  }];
  let options = [
    Option<"topDownProcessingEnabled", "top-down", "bool", "true",
           "Seed the worklist in general top-down order">,
    Option<"regionSimplifyLevel", "region-simplify", "std::string", "\"normal\"",
           "Control-flow simplification of the region tree: disabled, normal "
           "or aggressive">,
    Option<"maxIterations", "max-iterations", "int64_t", "10",
           "Max. iterations between applying patterns / simplifying regions">,
    Option<"maxNumRewrites", "max-num-rewrites", "int64_t", "-1",
           "Max. number of pattern rewrites within an iteration">,
    Option<"testConvergence", "test-convergence", "bool", "false",
           "Fail the pass when it stops before a fixpoint">,
    Option<"cseBetweenIterations", "cse-between-iterations", "bool", "false",
           "Run full CSE between each pattern-application iteration">,
    ListOption<"filterDialects", "filter-dialects", "std::string",
               "If non-empty, only collect canonicalization patterns from the "
               "dialects with the given namespaces, which are loaded">,
  ] # RewritePassUtils.options;
  let statistics = [
    Statistic<"numRewrites", "rewrites", "Rewrites by patterns">,
    Statistic<"numUnconverged", "unconverged", "Runs that stopped before a fixpoint">,
  ];
}

def IdrSimplify : Pass<"idr-simplify", "::mlir::ModuleOp"> {
  let summary = "Repeat the simplify round until it changes nothing";
  let description = [{
    Runs idr-loop-breakers, idr-effects, inline, idr-specialize, sccp,
    idr-canonicalize, cse, idr-eval, idr-prune, symbol-dce,
    remove-dead-values and symbol-dce, again and again, until a round
    leaves the module unchanged, up to where constants are. Every member
    of the round is finite, so the rounds end; `max-rounds` asserts it: a
    module that still changes after that many rounds is the error
    `unsupported (compile-time budget)`. The statistics of the round's
    passes are the pass's own, `<pass>.<statistic>`. Remarks in the category
    idr-simplify: an `Analysis` remark after each round (its number, the
    functions, the clones, the ops, the milliseconds), `Passed` at the
    fixpoint, and an `Analysis` remark with the round's statistics.
  }];
  let options = [
    Option<"inlineIterations", "inline-iterations", "unsigned", "0",
           "max-iterations of the inliner in each round; 0, the default, "
           "until an iteration inlines nothing">,
    Option<"cloneLimit", "clone-limit", "unsigned", "4096",
           "clone-limit of idr-specialize">,
    Option<"maxRounds", "max-rounds", "unsigned", "64",
           "The round budget: the most rounds a fixpoint may take">,
  ];
  let statistics = [
    Statistic<"numRounds", "rounds", "Rounds run">,
  ];
}

//===----------------------------------------------------------------------===//
// Ownership (lib/Ownership/)
//===----------------------------------------------------------------------===//

def IdrRc : Pass<"idr-rc", "::mlir::ModuleOp"> {
  let summary = "Make every reference explicit: reset/reuse, borrowed parameters, inc and dec";
  let description = [{
    Runs on functional code, after the simplify group and
    idr-defunctionalize and before idr-tail-loops, in Lean's order:
      - reset/reuse: in a case region of a match on a box that dies there,
        the first constructor on each path after its death with a cell of
        the same size is built in its cell (`idr.reset`, `idr.reuse`);
      - borrow inference: a parameter that never needs a reference of its
        own gets `idr.borrowed`, and its callers keep theirs;
      - explicit counting: every other reference is consumed exactly once
        on every path, with `idr.inc` before a use that consumes a
        reference the value still needs, and `idr.dec` after its last use
        that does not.
    The module then gets `idr.stage = "owned"`, whose rule the verifier
    checks after every later pass.
  }];
  let options = [
    Option<"reuse", "reuse", "bool", "true", "Reuse the cells of dead boxes">,
    Option<"borrow", "borrow", "bool", "true", "Infer borrowed parameters">,
  ];
  // The sizes of cells, for reuse, are those of their LLVM layouts.
  let dependentDialects = ["::mlir::LLVM::LLVMDialect"];
  let statistics = [
    Statistic<"numIncs", "incs", "idr.inc added">,
    Statistic<"numDecs", "decs", "idr.dec added">,
    Statistic<"numResets", "resets", "idr.reset added">,
    Statistic<"numReuses", "reuses", "Constructors built in a reset cell">,
    Statistic<"numBorrowed", "borrowed", "Parameters borrowed">,
  ];
}

//===----------------------------------------------------------------------===//
// Test assertions (lib/Expect/)
//===----------------------------------------------------------------------===//

def IdrExpect : Pass<"idr-expect", "::mlir::ModuleOp"> {
  let summary = "Check named properties of the module, and change nothing";
  let description = [{
    Tests state what a pass guarantees by name, not by the ops that happen
    to show it. Each property in `holds`, `name` or `name=argument`, reports
    every place it fails as an error `expected <name>: <what>`, and the pass
    fails if any does:
      - `no-closures`: no closure is built, applied or a constant;
      - `no-heap-allocation`, `no-heap-allocation=@f`: nothing allocates a
        heap cell, anywhere, or in @f and everything it may call;
      - `every-cycle-has-breaker`: every cycle of references among the
        functions that may be inlined has a `no_inline` function;
      - `one-clone=@f`: every call of @f or of a clone of it calls one
        function;
      - `reuses-in-place=@f`: in @f every box is built in a reused cell
        (idr.reuse), and at least one is;
      - `counts-nothing=@f`: no idr.inc or idr.dec in @f;
      - `quantities-kept=<file>`: every parameter has a quantity, and every
        parameter and constructor field of the module in <file> (the
        emitted module) has the quantity it has there;
      - `facts-as-marked`: every op marked `expect.facts = "..."` gets from
        lib/Facts the answers the mark lists, of `drop move delay evaluate`
        in that order: whether it may be dropped (an unused call), moved
        across anything, delayed, and evaluated at compile time.
  }];
  let options = [
    ListOption<"holds", "holds", "std::string", "The properties that must hold">,
  ];
}

#endif // IDR_PASSES
