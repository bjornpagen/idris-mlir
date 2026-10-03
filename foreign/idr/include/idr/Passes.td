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

def IdrTarget : Pass<"idr-target", "::mlir::ModuleOp"> {
  let summary = "Give the module its target: triple, CPU, features, data layout";
  let description = [{
    Writes the build's target triple and the CPU on the module as its
    `#llvm.target`, then lets LLVM fill in the CPU's features and the data
    layout (`dlti.dl_spec`). Every later step reads the target there:
    idr-eval's JIT compiles for it, idr-lower tells the runtime's entry which
    features to test, and idris-mlir-cc compiles the object for it. The
    triple and the default CPU are the build's target entry (CMakeLists.txt).
  }];
  let options = [
    Option<"cpu", "cpu", "std::string", "IDRIS_MLIR_TARGET_CPU",
           "The CPU, an LLVM name for one of the triple's">,
    Option<"features", "features", "std::string", "\"\"",
           "Features beyond the CPU's, as LLVM writes them (+avx2,-fma)">,
  ];
  let dependentDialects = ["::mlir::LLVM::LLVMDialect", "::mlir::DLTIDialect"];
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
    "::mlir::math::MathDialect", "::mlir::memref::MemRefDialect",
    "::mlir::linalg::LinalgDialect"
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
    refused memory by the machine stays, and so does one whose results
    would take more than 1 MiB of static data. The results come back as
    MLIR bytecode, read once per cell, so parts they share stay shared.
    Results are cached per callee and arguments. Remarks: `Passed` with the
    wall time, `Missed` for a crash, for a call that did not finish and
    for results too large, in the category idr-eval.
    Replacing one call by its results is the action `idr-eval-call`.
  }];
  let statistics = [
    Statistic<"numEvaluated", "evaluated", "Calls replaced by their results">,
    Statistic<"numStayedCrash", "stayed-crash", "Calls that crash, left to run at runtime">,
    Statistic<"numStayedBudget", "stayed-budget",
              "Metered calls that did not finish, left to run at runtime">,
    Statistic<"numStayedLarge", "stayed-large",
              "Calls whose results are too large to be worth it, left to run at runtime">,
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

def IdrContify : Pass<"idr-contify", "::mlir::ModuleOp"> {
  let summary = "Inline each function called once from another function";
  let description = [{
    A private function whose one use is a `func.call` from another function
    is a continuation of that function: Idris makes one of every `case` and
    `if` on a clause's right-hand side (a case block). It is inlined there
    with MLIR's `inlineCall` and erased, which copies nothing, and which the
    inliner refuses when the case block calls its parent back. It runs
    before the simplify loop, so that the cell a function takes apart and
    the constructor its case block builds meet in one function, where
    idr-rc reuses the one for the other. A function called twice, one that
    calls itself, and one a closure names are left alone.
  }];
  let statistics = [
    Statistic<"numContified", "contified", "Functions inlined into their one caller">,
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

def IdrTrmc : Pass<"idr-trmc", "::mlir::ModuleOp"> {
  let summary = "Make a recursion that returns a constructor around its own result a tail call with a destination";
  let description = [{
    A self call whose result is a field of the boxed constructor a tail
    position returns (`Cons x (copy xs)`) becomes a tail call: the
    constructor is built first, with that field pending, and the call
    takes the field as a destination (`!idr.dest`) to write its result
    to. The function keeps its signature and does that for its first
    level; the calls go to a clone that takes a destination and returns
    nothing, whose own such tails write the cell they build to the
    destination they got and recurse on the new one, and whose other
    tails write their value. idr-tail-loops then makes the clone a loop:
    the structure is written top down in constant stack. A self call in
    any other position (one whose result is inspected) stays a call of the
    function.
  }];
  let statistics = [
    Statistic<"numFunctions", "functions", "Functions given a destination-passing clone">,
    Statistic<"numTails", "tails", "Constructors around a self call that became tail calls">,
  ];
}

def IdrTailLoops : Pass<"idr-tail-loops", "::mlir::ModuleOp"> {
  let summary = "Turn self tail calls into scf.while loops";
  let description = [{
    A function that calls itself in tail position, directly or through the
    regions of matches whose results it returns, becomes one `scf.while`.
    When its body ends in a match with one region that calls and one that
    returns, the loop is in while-do form: the before region computes the
    decision, the after region is the calling region, the returning region
    follows the loop, arguments the call passes unchanged are not carried,
    and code that holds no reference and depends on nothing the loop
    changes runs once, before it. Upstream's uplift then makes a loop that
    counts to a bound an `scf.for`. A function without `idr.total` gets
    `idr.may_loop` in its loop.
  }];
  let dependentDialects = ["::mlir::scf::SCFDialect", "::mlir::ub::UBDialect",
                           "::mlir::arith::ArithDialect"];
  let statistics = [
    Statistic<"numLoops", "loops", "Functions whose self tail calls became a loop">,
    Statistic<"numCounted", "counted", "Loops that became scf.for">,
  ];
}

def IdrNarrow : Pass<"idr-narrow", "::mlir::ModuleOp"> {
  let summary = "Make the bigs and naturals proved to fit a small plain i64 words";
  let description = [{
    Integer range analysis sees the ops on bigs and naturals through their
    ranges, a natural it cannot see computed starting at 0. Every web of
    them it proves fits a small (the values, the loop-carried arguments and
    the merged results that carry them) becomes `arith` on `i64`, with
    `nsw`, and `nuw` where nothing is negative; `idr.big.to_int` and
    `idr.big.from_int` convert where a web meets a big it does not prove.
    The count of such a value is gone: a small big owns nothing.

    A loop whose natural argument only descends (every value it passes
    back is the argument or a predecessor of it) is versioned: one test on
    entry that the argument is small, then a copy of the loop in which it
    is proved to stay small, and the loop as it was otherwise.
  }];
  let dependentDialects = ["::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect"];
  let statistics = [
    Statistic<"numNarrowed", "narrowed", "Ops on bigs and naturals made i64 arithmetic">,
    Statistic<"numCarried", "carried", "Loop-carried and merged bigs made i64">,
    Statistic<"numVersioned", "versioned", "Loops versioned on a small descending natural">,
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

def IdrReturnedArguments : Pass<"idr-returned-arguments", "::mlir::ModuleOp"> {
  let summary = "Drop a result a function always returns as one of its arguments";
  let description = [{
    A result that is, on every path, one and the same argument of its
    function (directly, through the join of an `scf.if` or
    `scf.index_switch`, or through a recursive call that gives back the
    argument it was passed) is dropped, and every caller uses the argument
    it passed instead. A value threaded through a function and given back
    (a linear array through its reads and writes) is such a result once
    lowered, and costs the caller nothing when dropped: it holds the value
    already. Only a private function every use of which is a direct call
    changes its signature.
  }];
  let statistics = [
    Statistic<"numDropped", "dropped", "Results dropped, whose callers use the argument">,
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
    int-range-optimizations, idr-canonicalize, cse, idr-eval, idr-prune, symbol-dce,
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
  let summary = "Make every reference explicit: reset/reuse, borrowed parameters, dup and drop";
  let description = [{
    Runs on functional code, after the simplify group and
    idr-defunctionalize and before idr-tail-loops, in Lean's order:
      - reset/reuse: in a case region of a match on a box that dies there,
        the box is taken apart where it dies (`idr.take`), and the first
        constructor on each path after that with a cell of the same size
        is built in its cell (`idr.reuse`);
      - borrow inference: a parameter that never needs a reference of its
        own stays a plain type (a view of the caller's value), and its
        callers keep theirs; every other parameter and every result is
        `!idr.own<T>`;
      - explicit counting: every value that holds references is owned
        (`!idr.own<T>`, one reference of its own, consumed exactly once on
        every path) or a view (plain `T`, read while its owner holds its
        reference): `idr.dup` takes a reference of its own from a view
        before a use that consumes one, `idr.drop` gives one up after the
        last use, and `idr.borrow` makes the view an owned value is read
        through;
      - exclusivity: an owned value that holds the only reference to every
        cell it reaches (a constructor of exclusive fields, a field an
        exclusive value was taken apart into, a parameter every caller
        passes exclusive, a result every return makes exclusive; never a
        dup, a constant other than a nullary one, or a stack cell) gets the
        grade `!idr.excl<T>`, on which a take needs no count test and a
        reuse no null test; where it meets an owned position it is shared
        into it (`idr.share`).
    The module then gets `idr.stage = "owned"`, whose rule the verifier
    checks after every later pass.
  }];
  let options = [
    Option<"reuse", "reuse", "bool", "true", "Reuse the cells of dead boxes">,
    Option<"borrow", "borrow", "bool", "true", "Infer borrowed parameters">,
    Option<"sink", "sink", "bool", "true",
           "Move an op that consumes an owned value down to its result's first use">,
  ];
  // The sizes of cells, for reuse, are those of their LLVM layouts.
  let dependentDialects = ["::mlir::LLVM::LLVMDialect"];
  let statistics = [
    Statistic<"numDups", "dups", "idr.dup added">,
    Statistic<"numDrops", "drops", "idr.drop added">,
    Statistic<"numTakes", "takes", "Dead boxes taken apart for their cells">,
    Statistic<"numReuses", "reuses", "Constructors built in a taken cell">,
    Statistic<"numBorrowed", "borrowed", "Parameters borrowed">,
    Statistic<"numExclusive", "exclusive", "Values that hold the only reference to their cells">,
  ];
}

//===----------------------------------------------------------------------===//
// Test assertions (lib/Expect/)
//===----------------------------------------------------------------------===//

def IdrVectorize : Pass<"idr-vectorize", "::mlir::ModuleOp"> {
  let summary = "Tile each loop over an array by the target's lanes and vectorize it";
  let description = [{
    Every `linalg.generic` with a parallel dimension (the loops over arrays
    idr-lower leaves) is tiled by the target's lanes along its parallel
    dimensions and by one along its reductions, its tile loop peeled so
    that the full tiles are known to be full, and each tile vectorized at
    those sizes: the full tiles without masks, the last one masked. The lane
    count is the target's vector register (idr-target's `#llvm.target`)
    over the widest word the loop computes. A reduction dimension never
    gets more than one lane, so a floating accumulator adds in program
    order; the unit dimension that lane leaves on the tile's vectors is
    dropped again, so that LLVM sees vectors of the lanes. A loop the
    vectorizer refuses (a call or a crash check in its body) stays, for
    convert-linalg-to-loops. Remarks in the category idr-vectorize:
    `Vectorized` with the lanes, `Scalar` with why not.
  }];
  let statistics = [
    Statistic<"numVectorized", "vectorized", "Loops that compute on lanes">,
    Statistic<"numScalar", "scalar", "Loops left for convert-linalg-to-loops">,
  ];
  let dependentDialects = [
    "::mlir::affine::AffineDialect", "::mlir::arith::ArithDialect",
    "::mlir::linalg::LinalgDialect", "::mlir::memref::MemRefDialect",
    "::mlir::scf::SCFDialect", "::mlir::vector::VectorDialect"
  ];
}

def IdrNarrowLanes : Pass<"idr-narrow-lanes", "::mlir::ModuleOp"> {
  let summary = "Run the integer lanes of each vectorized loop in 32 bits under a bound on the sizes";
  let description = [{
    After idr-vectorize, each vectorized loop (as its ops say: vector ops,
    the loops of its tiles, ops with neither effects nor regions) that
    computes on lanes of integers wider than 32 bits gets two versions:
    where every integer it reads from outside (the sizes, the tile bound)
    is at most B, a copy in which integer range analysis sees that bound
    (each such input stands behind `arith.minui` of itself and B) and
    upstream's arith-int-range-narrowing makes every integer op it proves
    fits 32 bits an op on i32; otherwise the loop as it was. B is the
    largest power of two from 2^31 down to 2^8 at which every elementwise
    integer op of the copy wider than 32 bits fits, and is an arith op
    whose 32-bit form computes the same (a shift by less than 32, a signed
    remainder that never sees INT32_MIN % -1, an op reading its operands
    unsigned on no negative word), found by running the analysis on the
    copy in a scratch module. A loop that runs at most once (its bounds,
    as upstream's value bounds see them, less than a step apart: the loop
    of a peeled tile loop's last tile), or whose integers fit under no
    bound, stays as it is. Remarks in the category idr-narrow-lanes:
    `Narrowed` with the bound, `Wide` with why not.
  }];
  let statistics = [
    Statistic<"numNarrowed", "narrowed", "Vectorized loops given a 32-bit version">,
    Statistic<"numWide", "wide", "Vectorized loops on wide integer lanes left on 64 bits">,
  ];
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::func::FuncDialect", "::mlir::scf::SCFDialect"
  ];
}

def IdrExpect : Pass<"idr-expect", "::mlir::ModuleOp"> {
  let summary = "Check named properties of the module, and change nothing";
  let description = [{
    Tests state what a pass guarantees by name, not by the ops that happen
    to show it. Each property in `holds`, `name` or `name=argument`, reports
    every place it fails as an error `expected <name>: <what>`, and the pass
    fails if any does. A property of `@f` is of @f and of every clone of it
    (a specialization, a raised copy), which keeps the location naming the
    definition it was copied from, so a test names the function the
    programmer wrote:
      - `no-closures`: no closure is built, applied or a constant;
      - `no-heap-allocation`, `no-heap-allocation=@f`: nothing allocates a
        heap cell, anywhere, or in @f and everything it may call;
      - `every-cycle-has-breaker`: every cycle of references among the
        functions that may be inlined has a `no_inline` function;
      - `one-clone=@f`: every call of @f or of a clone of it calls one
        function;
      - `reuses-in-place=@f`: in @f every box is built in a reused cell
        (idr.reuse), and at least one is;
      - `counts-nothing=@f`: no idr.dup or idr.drop in @f, other than a dup of
        static data, which holds no count;
      - `tests-nothing=@f`: every take in @f is of an exclusive value and
        every reuse builds in an exclusive cell, so no count or null is
        tested; and there is at least one take;
      - `resets-unshared`, `resets-unshared=@f`: every take of a box,
        anywhere or in @f, tests a cell that its function never gives a
        second reference (an idr.dup of a view of the box or of a value it
        was read from);
      - `reuses-every-cell=@f`: every cell a take in @f yields
        for a constructor with fields is reused, and none is freed;
      - `contified`: no private function is called once, from another
        function, and used nowhere else;
      - `quantities-kept=<file>`: every parameter has a quantity, and every
        parameter and constructor field of the module in <file> (the
        emitted module) has the quantity it has there;
      - `facts-as-marked`: every op marked `expect.facts = "..."` gets from
        lib/Facts the answers the mark lists, of `drop move delay evaluate`
        in that order: whether it may be dropped (an unused call), moved
        across anything, delayed, and evaluated at compile time;
      - `output-fused`: no string is built only to be written: no
        `idr.io.put_str` writes what `idr.str.append`, `cons`, `from_char`
        or `show` made, or what `pack` or `concat` made for it alone;
      - `constant-stack=@f`: no function @f may call, @f included, is on a
        cycle of references: every recursion from @f became a loop;
      - `counted-loop=@f`: @f loops, and each of its loops is an `scf.for`;
      - `pure-array-loops`, `pure-array-loops=@f`: every loop over an array
        (`idr.array.generate`, `idr.array.fold`), anywhere or in @f, has a
        body that only computes (no count changes, nothing allocated,
        nothing called), and there is at least one;
      - `vectorized`, `vectorized=@f`: after idr-vectorize, anywhere or in
        @f, some loop computes on vectors, and no `linalg.generic` with a
        parallel dimension and a body of words alone (arith, math,
        `linalg.index`) is left scalar;
      - `narrowed-lanes`, `narrowed-lanes=@f`: after idr-narrow-lanes,
        anywhere or in @f, some loop computes integer lanes in 32 bits or
        fewer, and every loop that computes integer lanes wider than 32
        bits (an elementwise op on a vector of such integers that is no
        cast and no select, which only move lanes) and may run more than
        once is the 64-bit version beside a loop that computes its lanes
        in 32: the else region of an `scf.if` whose then region holds one;
      - `folds-balanced`: the folders released every reference they took
        from the runtime, which holds no live cell (on the calling thread,
        so run single-threaded).
  }];
  let options = [
    ListOption<"holds", "holds", "std::string", "The properties that must hold">,
  ];
  // `quantities-kept` parses the emitted module, which holds ops of every
  // dialect of the contract, whether or not the module under test still
  // does: a dimension read that folded away still loads memref there.
  let dependentDialects = [
    "::mlir::func::FuncDialect", "::mlir::arith::ArithDialect",
    "::mlir::math::MathDialect", "::mlir::ub::UBDialect",
    "::mlir::memref::MemRefDialect"
  ];
}

#endif // IDR_PASSES
