// Passes of the idr dialect. Each is built by its generated constructor,
// with its options struct; none declares a constructor of its own. A pass
// anchored on ::idr::FuncOp runs under a nested pass manager and touches
// nothing outside its function. The nested steps a module pass runs itself
// (idr-rc-place, idr-rc-commit, idr-narrow-words, idr-in-bounds-prove,
// idr-returned-arguments-drop, idr-tail-calls-place) are not declared
// here: their module pass builds them and keeps their statistics.

#ifndef IDR_PASSES
#define IDR_PASSES

include "mlir/Pass/PassBase.td"

def IdrEffects : Pass<"idr-effects", "::mlir::ModuleOp"> {
  let summary = "Compute the effects of every idr.func and every idr.call";
  let description = [{
    `effects = #idr.effects<io, crash, diverge>` on an `idr.func` says what
    a call of it may do besides computing its results. `io`: it takes a world,
    as a parameter or in data a parameter holds; worlds reach a function
    only that way, so a function that only builds IO actions is not `io`.
    `crash`: it reaches an op that may crash, through calls and through the
    labels of the closures it makes (`idr.closure`, closure constants, and
    the constructors of idr-defunctionalize's sums of closures). `diverge`:
    it reaches, the same way, a function without `total`, itself included;
    a function Idris proved does not stop it, since its proof does not see
    the implementations its interface methods reach. A function without a
    body, and every function that reaches one or calls anything but an
    idr.func, may do all three, and has no `effects`. `#idr.effects<none>`
    is none of them.

    Every `idr.call` gets its own: its callee's, joined with what the
    closures it is passed may do when applied, so that a closure's effects
    count where it is passed. A call whose effects would be all three has
    none. Both are rewritten on every function and call each round.
  }];
  let statistics = [
    Statistic<"numIO", "io", "Functions that get io">,
    Statistic<"numCrash", "crash", "Functions that get crash">,
    Statistic<"numDiverge", "diverge", "Functions that get diverge">,
  ];
}

def IdrTarget : Pass<"idr-target", "::mlir::ModuleOp"> {
  let summary = "Give the module its target: triple, CPU, features, data layout";
  let description = [{
    Writes the build's target triple and CPU on the module as its
    `#llvm.target`, then lets LLVM fill in the CPU's features and the data
    layout (`dlti.dl_spec`). Every later step reads the target there:
    idr-entry tells the runtime's entry which features to test, and
    idris-mlir compiles the object for it. The triple and the CPU are the
    build's target entry (CMakeLists.txt).
  }];
  let dependentDialects = ["::mlir::LLVM::LLVMDialect", "::mlir::DLTIDialect"];
}

def IdrLower : Pass<"idr-lower", "::mlir::ModuleOp"> {
  let summary = "Lower idr to func, arith, math, scf, ub and llvm";
  let description = [{
    First every `idr.func` becomes a `func.func` named by its mangled
    symbol, every `idr.call` a `func.call` and every `idr.return` a
    `func.return`; the facts of `idr.func` are not copied, and nothing
    after reads one. Then matches become scf, then a dialect conversion
    takes every idr type apart into its runtime layout and every idr op to
    arith, scf, llvm and calls of the runtime's C functions. Each guard
    becomes its comparison and a crash with its cause. Constants become
    static data, and `@__idr_release_cafs` releases what the static thunks
    among them hold once forced. A program's root becomes its entry in
    idr-entry, after this.
  }];
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect",
    "::mlir::math::MathDialect", "::mlir::memref::MemRefDialect",
    "::mlir::linalg::LinalgDialect"
  ];
}

def IdrEntry : Pass<"idr-entry", "::mlir::ModuleOp"> {
  let summary = "Make the lowered root the program's entry: @__idr_main and @main";
  let description = [{
    Runs after idr-lower. The root, the only public function, becomes
    private, and its kind comes from its lowered signature: `() -> i64`
    returns the exit status, and `() -> ()` returns 0. `@__idr_main` calls
    the root, then `@__idr_release_cafs`, then `idris_rt_main_return`.
    `@main(i32, ptr)` passes `argc` and `argv`, with the CPU features the
    target requires, to `idris_rt_start`, which runs `@__idr_main`. Runtime
    functions are declared where absent.
  }];
  let dependentDialects = ["::mlir::LLVM::LLVMDialect", "::mlir::func::FuncDialect"];
}

def IdrTailCalls : Pass<"idr-tail-calls", "::mlir::ModuleOp"> {
  let summary = "Make every call in tail position on a cycle of calls a guaranteed tail call";
  let description = [{
    Runs on the LLVM dialect, last. The plan is the module's (which calls
    become guaranteed tail calls, which functions change convention or
    return through memory); the rewrite then runs on each `llvm.func`
    nested. A call is in tail position when the path from it returns its
    result unchanged: through extractvalue and insertvalue, through
    branches that carry it, past conditions the path itself decides and ops
    that only compute. When such a call's caller and
    callee are on one cycle of direct calls, and only the module's calls
    reach both (private, their address never taken), the two take the
    `tailcc` calling convention, as do all their calls, and every call in
    tail position between two functions of `tailcc` becomes `musttail`,
    with the return right after it. The other functions keep their
    convention: a call from one cycle to another adds a frame once at most,
    and the callee of a `tailcc` call pops its stack arguments, at a cost
    to every call of it. A function on a tail call whose result the target
    returns in memory (what LLVM's lowering of `tailcc` decides for the
    module's `#llvm.target`) takes a pointer to write it to instead: a tail
    call passes on its own, any other call a slot of its frame. A call that
    takes a pointer into its caller's frame stays a call.
  }];
  let statistics = [
    Statistic<"numTailCalls", "tail-calls", "Calls in tail position made guaranteed tail calls">,
    Statistic<"numInMemory", "in-memory", "Functions on tail calls whose result goes through memory">,
    Statistic<"numFrameBound", "frame-bound", "Calls in tail position that take their caller's frame, left calls">,
  ];
}

//===----------------------------------------------------------------------===//
// The optimization passes (lib/Transforms)
//===----------------------------------------------------------------------===//

def IdrLoopBreakers : Pass<"idr-loop-breakers", "::mlir::ModuleOp"> {
  let summary = "Keep a loop breaker in every cycle of references";
  let description = [{
    A function refers to what it calls and to the functions its closures and
    closure constants name. In every cycle of such references among the
    functions that may be inlined, one becomes `no_inline`: the newest
    clone, or else the first function in module order without
    `break_last`, or else the first. A step of every round of
    `idr-simplify`, before inlining, so that the inliner never unrolls a
    cycle, whether Emit wrote it or the previous round closed it.
  }];
  let statistics = [
    Statistic<"numBreakers", "breakers", "Functions made loop breakers">,
  ];
}

def IdrRoundFacts : Pass<"idr-round-facts", "::mlir::ModuleOp"> {
  let summary = "Compute the analyses the round's function step reads";
  let description = [{
    A step of every round of `idr-simplify`, right before its nested
    function step: computes the module's `SymbolTable`, `Holds`,
    `Identities`, `CloneTable` and `BindingTimes`, which `idr-identity` and
    `idr-redirect` read through their parent, since a nested manager
    preserves no module analysis. It rewrites nothing and preserves
    everything.
  }];
}

def IdrSpecialize : Pass<"idr-specialize", "::mlir::ModuleOp"> {
  let summary = "Clone callees for consumed results and static arguments";
  let description = [{
    Raising comes first: an `idr.call` whose result is only applied
    (`idr.apply`, possibly of an `idr.field` of it, possibly through a
    linear position), with nothing that has an effect in between and no
    world among its operands, calls instead a clone that takes the apply's
    arguments too, keyed by (callee, consumer); the consumer moves to the
    clone's tails.

    An `idr.call` with a static argument (built from constants, `idr.con`
    and `idr.closure`) calls a clone of its callee with that argument
    substituted, whose parameters are the runtime leaves, when the
    parameter's binding time allows it: any argument when the callee is on
    no cycle of references, else that of a fixed parameter, or of a
    decreasing or bounded one when the static value is small
    (`idr-binding-times` reports the binding times). Clones are shared by
    key (the function first cloned, and the patterns of its parameters); a
    key goes into the table before its clone is simplified, so a clone's
    calls with its own key are self calls.
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
  let dependentDialects = ["::mlir::arith::ArithDialect", "::idr::IdrDialect"];
}

def IdrRedirect : Pass<"idr-redirect", "::idr::FuncOp"> {
  let summary = "Call the clone a call's key already has";
  let description = [{
    A call whose key names a clone the module already holds calls that
    clone: a raised clone, when the call's result is only applied (through
    a field, through a linear position) with nothing effectful between;
    a specialization, when the static parts of its arguments compose the
    key of one. The redirect half of idr-specialize, run per function.
    It makes no clone; a key the table lacks is left to idr-specialize.
  }];
  let statistics = [
    Statistic<"numRedirected", "redirected", "Calls redirected to a clone made before">,
  ];
  let dependentDialects = ["::mlir::arith::ArithDialect", "::idr::IdrDialect"];
}

def IdrBindingTimes : Pass<"idr-binding-times", "::mlir::ModuleOp"> {
  let summary = "Report the binding time of every parameter";
  let description = [{
    A remark on every function with a body: `free for every parameter` for
    one on no cycle of references, or else the binding time of each parameter as
    idr-specialize finds it: fixed, decreasing, bounded or other. It changes
    nothing.
  }];
}

def IdrInline : Pass<"idr-inline", "::mlir::ModuleOp"> {
  let summary = "Inline calls by MLton's size rule";
  let description = [{
    MLIR's inliner, deciding what to inline as MLton does: a function that
    calls nothing and has at most 40 ops, and any function on no cycle of
    calls for which (calls - 1) * (size - 60) <= 320, sizes counted in ops,
    calls in call sites and in closures that name the function. The
    decisions are taken once, before anything is inlined, from the callees
    up. Inlining repeats for each group of functions until an iteration
    inlines nothing.

    It first prepares forces, before any decision or call graph is taken:
    a closure that only forces a captured suspension calls the
    suspension's function in its place, and a force of a constant
    suspension used once, where its label cannot be running, becomes the
    call. After an iteration, `canonicalize` and `cse` run only on a
    function it inlined into; the round's function step canonicalizes
    every other.
  }];
  let statistics = [
    Statistic<"numInlinable", "inlinable", "Functions the size rule lets inline">,
    Statistic<"numLeaves", "leaves", "Of those, functions that call nothing">,
  ];
}

def IdrIsolate : Pass<"idr-isolate", "::mlir::ModuleOp"> {
  let summary = "Make every idr.lambda and idr.delay an idr.closure or idr.suspend of an outlined function";
  let description = [{
    Innermost first, the region of each `idr.lambda` and
    of each `idr.delay` but an evaluated one (whose body is one `idr.yield`
    of a value from above, which defunctionalization makes the memo's
    forced constructor) is isolated from above
    (`makeRegionIsolatedFromAbove`): a constant it uses is cloned into it,
    and every other value it uses from above becomes a capture. The region
    becomes the body of a private `idr.func` named after the enclosing
    one, `<f>.lam<n>` or `<f>.delay<n>`, whose parameters are the
    captures, in the order isolation found them, then the lambda's own;
    its `idr.yield` becomes `idr.return`. The function gets `total`,
    `break_last` when the enclosing function has it, and the location
    named as the enclosing function's, and the op becomes `idr.closure` or
    `idr.suspend` of it over the captures. Every function is planned
    first, then rewritten. The simplify loop then sees closures and
    suspensions in their symbol form.
  }];
  let dependentDialects = ["::idr::IdrDialect"];
}

def IdrContify : Pass<"idr-contify", "::mlir::ModuleOp"> {
  let summary = "Inline each function called once from another function";
  let description = [{
    A private function whose one use is an `idr.call` from another function
    is a continuation of that function: Idris makes one of every `case` and
    `if` on a clause's right-hand side (a case block). It is inlined there
    with MLIR's `inlineCall` and erased, which copies nothing, and which the
    inliner refuses when the case block calls its parent back. It runs
    before the simplify loop, so that the cell a function takes apart and
    the constructor its case block builds meet in one function, where
    idr-rc reuses the one for the other. The function it is inlined into
    keeps `total` only if the continuation has it. A function called twice,
    one that calls itself, and one a closure names are left alone.
  }];
  let statistics = [
    Statistic<"numContified", "contified", "Functions inlined into their one caller">,
  ];
}

def IdrIdentity : Pass<"idr-identity", "::idr::FuncOp"> {
  let summary = "Make every call of a function that gives back one of its arguments that argument";
  let description = [{
    Once Idris's indices are erased, a function may only rebuild its
    argument: Data.Fin's weaken, finToNat and last, a term's weakening to a
    larger scope. Such a function gives back an argument x when every
    return is x rebuilt: x itself; a constructor where x is known to be
    that constructor (by the case of a match around the return, or as the
    one constructor of its type), each field the same field of x rebuilt;
    a constant where x is known to be that literal; the successor of x's
    predecessor; a match whose every region that returns yields x rebuilt;
    or a call assumed to give back what it is passed, passed x itself (a
    rebuilt x is a new value, not a part of x). The function must also
    only compute: every other op only allocates its results (a call as its
    callee's `effects` say), a region that does not return ends in
    ub.unreachable, which Idris proved is never taken, and every call
    assumed to give back what it is passed either passes a part strictly
    below the function's argument (a field of a constructor of it, or the
    predecessor of a natural) or calls a function whose `effects` say it
    returns, so that every chain of such calls ends: values are finite.
    Its other arguments may be anything. The assumptions are the greatest
    fixpoint over the module, so the functions of a mutual recursion are
    found together; it is the `Identities` analysis, which idr-round-facts
    computes for the round. In each function, every call of such a
    function becomes its argument, at the quantity of the call's result,
    and symbol-dce erases the function once nothing names it. A function
    in the owned stage, or one that takes a world, gives back nothing.
  }];
  let statistics = [
    Statistic<"numCalls", "calls", "Calls made the argument they give back">,
  ];
  let dependentDialects = ["::idr::IdrDialect"];
}

def IdrDefunctionalize : Pass<"idr-defunctionalize", "::mlir::ModuleOp"> {
  let summary = "Replace closures and suspensions of known labels by sums";
  let description = [{
    A sparse dataflow analysis finds the labels each `!idr.fn` value may
    hold. Sums are keyed by (closure type, label set): each slot (value,
    argument, result, field) of a key whose labels are known and fit, and
    which is on no cycle of "a capture of its labels holds a value of that
    key", becomes a sum with one constructor per label, whose fields are the
    label's captures: `idr.closure` becomes `idr.con` and `idr.apply` an
    `idr.match` that calls the label. Where a value moves between slots of
    different keys, a match rebuilds it in the other sum, or as a closure.

    A `!idr.lazy` value is followed the same way, through array elements
    too, and its key becomes a memo sum (`memo`, always a box, its label
    functions listed in `labels`): a constructor per label, then `running`
    and `forced` with the value. `idr.suspend` becomes `idr.con` of its
    label, and `idr.force` takes the box. A label whose function reaches an
    observable effect is `by_name`, unless a static constant names it. A key
    left unconverted in a program is the error `unsupported (laziness)` or
    `unsupported (runtime closure)`, at the op the value flows through where
    the analysis lost it.

    Then every type is final, and an unboxed sum spreads its slots over
    every cell that holds it: a record (a declaration of one constructor)
    or a closure sum that makes a box's cell, or an array's element, count
    more references than a header can becomes a box, the one of the most
    references first, ties by name, until none does. A sum of several user
    constructors is looked through to the records it holds, never boxed:
    a field read of it may already run where its constructor is not known.
  }];
  let dependentDialects = ["::mlir::ub::UBDialect"];
  let statistics = [
    Statistic<"numSums", "sums", "Keys whose closures became sums">,
    Statistic<"numClosures", "closures", "Keys whose closures stay closures">,
    Statistic<"numBoxed", "boxed", "Records and closure sums made boxes so that the cells holding them fit">,
  ];
}

def IdrAccumulate : Pass<"idr-accumulate", "::mlir::ModuleOp"> {
  let summary = "Make a recursion that adds its own result a tail call with an accumulator";
  let description = [{
    A self call whose result a tail position adds (an `idr.big.add` of the
    call and a value the call does not compute) becomes a tail call. The
    function keeps its signature and calls a clone with zero, addition's
    identity; the clone carries the sum so far, adds before it calls
    itself, and adds that sum to whatever another tail would have returned.
    Addition associates and commutes, so the sum on the way down is the sum
    on the way back. idr-tail-loops then makes the clone a loop. A self call
    in any other position, or added to another self call, stays a call of
    the function.

    Runs before idr-rc. Counting borrows the call's result and drops it
    after the addition, and the call is then no longer what the tail adds.
  }];
  let statistics = [
    Statistic<"numFunctions", "functions", "Functions given an accumulator clone">,
    Statistic<"numTails", "tails", "Additions of a self call that became the carried sum">,
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

def IdrTailLoops : Pass<"idr-tail-loops", "::idr::FuncOp"> {
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
    counts to a bound an `scf.for`. A function without `total` gets
    `idr.may_loop` in its loop. It reads the declarations it needs from the
    function's own ops and changes nothing outside the function.
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
    is proved to stay small, and the loop as it was otherwise. The ranges
    are the module's, solved once; the word rewrite then runs on each
    function nested.
  }];
  // The word rewrite runs nested per function, where no dialect is
  // loaded for it: it makes ub.poison.
  let dependentDialects = ["::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
                           "::mlir::ub::UBDialect"];
  let statistics = [
    Statistic<"numVersioned", "versioned", "Loops versioned on a small descending natural">,
  ];
}

def IdrInBounds : Pass<"idr-in-bounds", "::mlir::ModuleOp"> {
  let summary = "Remove every guard whose condition holds where it runs";
  let description = [{
    An `idr.check.in_bounds` is proven when no integers satisfy what is
    known at it and an index below 0 or at least its length, as MLIR's
    Presburger library decides: the conditions of the matches, ifs and
    loops on its path, the guards that held before it, the linear
    definitions of the integers involved (wrapping exactly), the Euclidean
    quotient of a value already proved non-negative divided by a positive
    constant, a masked index below a capacity already proved a positive
    power of two when the mask is that capacity minus one and the array's
    length is that capacity (doubling one, by a multiply by two or a shift
    left by one, stays a power of two when the value doubled is below half
    the sign bit, so the double stays below the sign), integer range
    analysis, and the length relation: an integer that is the length of an
    array, clamped at 0, wherever both are in scope. The relation starts at
    `idr.array.new` and `idr.array.generate`, and at a size measured off
    the array (its dimension made i64), and follows the pair through the
    values bound from several places (region branch arguments and results,
    the parameters of a private function every use of which is a direct
    call, a call's results, a select), as the greatest fixpoint: a pair
    holds when every place binding it gives a pair that holds. A call that
    gives an array back keeps the relation when every return is that
    argument: the same value, or a borrow, a share, a linear enter, a
    linear use or a constructor rebuilt from it, including that value read
    out of the record the call returns. A return that can be some other
    array keeps nothing. A component of a record (a field, a take's field,
    a match case's argument) has the length of the component its
    constructor stored. A size the array was made from also relates when a
    branch or a max clamps it at 0 to the same integer, from the conditions
    that choose the side. A guard's
    result is its operand, so an index checked against a size before the
    access's own guard checks it is the same integer at both, and the
    first guard's array is the access's.

    A proven guard is erased, its result replaced by its index: a proof is
    the guard's absence, so no later pass can invalidate it unseen, and the
    access it guarded is no longer speculatable. So is any guard that a
    dominating guard of the same kind and operands already checks, and any
    that integer range analysis proves where it runs. The pass needs no
    fixed place in the pipeline: it runs where its index systems see the
    most. The lengths are the module's, over its ranges; the proofs then
    run on each function nested.
  }];
  let statistics = [
    Statistic<"numProved", "proved", "Guards proven and removed">,
    Statistic<"numChecked", "checked", "Guards left to check at runtime">,
  ];
}

def IdrStack : Pass<"idr-stack", "::mlir::ModuleOp"> {
  let summary = "Put the cells of boxes that never leave their frame on the stack";
  let description = [{
    Marks an `idr.con` of a box with the unit attribute `idr.stack` when no
    reference to its cell can outlive the frame of the function that builds
    it, nor the loop iteration that builds it. A reference escapes when it
    is returned, captured by a closure, applied to an unknown function,
    forwarded by a terminator of a loop around the con, passed to a call in
    tail position of a function on the same cycle of calls (a tail call,
    idr-tail-calls, or the next iteration of a loop, idr-tail-loops),
    passed to a parameter that escapes (the parameters are summarized over
    the module's calls), used by an op the analysis does not know, or
    stored in a constructor whose value escapes or whose fields are read
    into something that escapes. idr-lower builds a marked cell in a slot
    of its function's entry block, with the stack mark in its header. A cell of more than 256 bytes stays on the heap,
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
    changes its signature. The results to drop are the module's; the
    rewrite then runs on each func.func nested.
  }];
  let statistics = [
    Statistic<"numDropped", "dropped", "Results dropped, whose callers use the argument">,
  ];
}

def IdrSimplify : Pass<"idr-simplify", "::mlir::ModuleOp"> {
  let summary = "Repeat the simplify round until it changes nothing";
  let description = [{
    Runs the round again and again, until a round leaves the module as it
    found it, as upstream's composite fixed-point pass decides:

      idr-effects
      idr-loop-breakers
      idr-round-facts
      idr.func(idr-identity, canonicalize, cse, idr-redirect)
      idr-inline
      idr-specialize
      sccp
      int-range-optimizations
      remove-dead-values{canonicalize=false}
      symbol-dce

    Every member of the round is finite, so the rounds end; `max-rounds`
    asserts it: a module that still changes after that many rounds is the
    error `unsupported (compile-time budget)`. The round's statistics are
    reported as `<pass>.<statistic>` in the loop's statistics remark.
    Remarks in the category idr-simplify, from the loop's instrumentation,
    without which the pass fails: an `Analysis` remark after each round
    (its number, the functions, the clones, the ops, the milliseconds),
    `Passed` at the fixpoint, and an `Analysis` remark with the round's
    statistics.
  }];
  let options = [
    Option<"maxRounds", "max-rounds", "unsigned", "64",
           "The round budget: the most rounds a fixpoint may take">,
  ];
  let statistics = [
    Statistic<"numRounds", "rounds", "Rounds run">,
  ];
}

//===----------------------------------------------------------------------===//
// Ownership (lib/Transforms/Ownership)
//===----------------------------------------------------------------------===//

def IdrRc : Pass<"idr-rc", "::mlir::ModuleOp"> {
  let summary = "Make every reference explicit: reset/reuse, borrowed parameters, dup and drop";
  let description = [{
    Runs on functional code, after the simplify group and
    idr-defunctionalize and before idr-tail-loops, in five steps: it
    refuses a module already in the owned stage; writes the owned grades
    borrow inference finds into signatures; runs idr-rc-place on each
    function, nested (reset/reuse and explicit counting, with the options
    `reuse` and `sink`); writes the exclusive grades into signatures and
    call results, copying a function as `<f>.excl` where its callers
    disagree; runs idr-rc-commit on each function, nested (the exclusive
    grades into bodies, shared into each owned position); and erases every
    original that a copy replaced and nothing uses. What each does:
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
    The module is then in the owned stage, which its grades say: it holds
    owned or exclusive values. The verifier checks the stage's rule after
    every later pass.
  }];
  // Both are forwarded to idr-rc-place.
  let options = [
    Option<"reuse", "reuse", "bool", "true", "Reuse the cells of dead boxes">,
    Option<"sink", "sink", "bool", "true",
           "Move an op that consumes an owned value down to its result's first use">,
  ];
  // The nested steps report nothing of their own: the counts are taken in
  // one walk after them.
  let statistics = [
    Statistic<"numBorrowed", "borrowed", "Parameters borrowed">,
    Statistic<"numExclusive", "exclusive", "Values that hold the only reference to their cells">,
    Statistic<"numTakes", "takes", "Dead boxes taken apart for their cells">,
    Statistic<"numReuses", "reuses", "Constructors built in a taken cell">,
    Statistic<"numDups", "dups", "idr.dup added">,
    Statistic<"numDrops", "drops", "idr.drop added">,
  ];
}

def IdrDemand : Pass<"idr-demand", "::mlir::ModuleOp"> {
  let summary = "Reject a program that breaks a promise it was asked to keep";
  let description = [{
    Runs after idr-rc, on the grades it wrote, and checks the promise only
    when it is asked to; otherwise it does nothing. `in-place`: a parameter
    of quantity 1 that its function rebuilds in place (an `idr.reuse` takes
    its token from an `idr.take` of the parameter, or of what a match of it
    binds) must be passed exclusive (`!idr.excl<T>`) by every call. A call
    that passes it shared is the error `unsupported (uniqueness)` at the
    call, with a note at the `idr.dup` that shared it.
  }];
  let options = [
    Option<"inPlace", "in-place", "bool", "false",
           "Check the in-place promise">,
  ];
  let dependentDialects = ["::idr::IdrDialect"];
}

//===----------------------------------------------------------------------===//
// After lowering, on func.func (lib/Transforms/Vectorize, Narrow)
//===----------------------------------------------------------------------===//

def IdrVectorize : Pass<"idr-vectorize", "::mlir::func::FuncOp"> {
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

def IdrNarrowLanes : Pass<"idr-narrow-lanes", "::mlir::func::FuncOp"> {
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

//===----------------------------------------------------------------------===//
// Test assertions (lib/Transforms/Expect)
//===----------------------------------------------------------------------===//

def IdrExpect : Pass<"idr-expect", "::mlir::ModuleOp"> {
  let summary = "Check named properties of the module, and change nothing";
  let description = [{
    Tests state what a pass guarantees by name, not by the ops that happen
    to show it. Each property in `holds`, `name` or `name=argument`, reports
    every place it fails as an error `expected <name>: <what>`, and the pass
    fails if any does. `@f` names a function whose symbol is f, an
    `idr.func` whose `instance` has the origin f, and every clone of one (a
    specialization, a raised copy) by its `clone` key, so a test names the
    function the programmer wrote, by its symbol or by its Idris
    definition:
      - `no-closures`: no closure is built, applied or a constant;
      - `no-heap-allocation`, `no-heap-allocation=@f`: nothing allocates a
        heap cell, anywhere, or in @f and everything it may call;
      - `every-cycle-has-breaker`: every cycle of references among the
        functions that may be inlined has a `no_inline` function;
      - `breaks-last`: a cycle that holds a function not marked to break
        last never breaks at one so marked: every marked breaker, other than
        a clone (the newest of which breaks its cycle, whatever it is), is
        on a cycle of marked functions alone;
      - `one-clone=@f`: every call of @f or of a clone of it calls one
        function, and there is one;
      - `not-called=@f`: no call of @f or of a clone of it is left (a
        function the module never had is not called either);
      - `reuses-in-place=@f`: in @f every box is built in a reused cell
        (idr.reuse), and at least one is;
      - `moves-out`, `moves-out=@f`: anywhere or in @f, some
        `idr.array.get` moves its element out for the write that follows;
      - `counts-nothing=@f`: no idr.dup or idr.drop in @f, other than a dup of
        static data, which holds no count;
      - `in-bounds=@f`: no `idr.check.in_bounds` is left in @f: every
        array access in it was proven within its array, and it has one;
      - `bounds-checked=@f`: some array access in @f keeps a check of its
        index: its own, or one against a size whose result its own takes;
      - `no-guards=@f`: no `idr.check.*` op is left in @f;
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
      - `quantities-kept=<file>`: every parameter, every field a match
        binds and every constructor field that the module in <file> (the
        emitted module) declares has the quantity it has there, one or
        many;
      - `facts-as-marked`: every op marked `expect.facts = "..."` answers,
        through the dialect's effects, the questions the mark lists, of
        `drop move delay` in that order: whether it may be dropped (an
        unused call), moved across anything, and delayed; a call answers
        with its own effects;
      - `output-fused`: no string is built only to be written: no
        `idr.io.put_str` writes what `idr.str.append`, `cons`, `from_char`
        or `show` made, or what `pack` or `concat` made for it alone;
      - `constant-stack=@f`: no recursion from @f grows the stack: every
        function @f may call, @f included, that is on a cycle of references
        refers to the others of its cycle only by guaranteed tail calls
        (`musttail`, after idr-tail-calls), so before idr-tail-calls none may
        be on a cycle at all: every recursion became a loop;
      - `counted-loop=@f`: @f loops, and each of its loops is an `scf.for`;
      - `word-loop=@f`: some loop of @f computes on words alone: no value
        defined or bound in it is a big or a natural (idr-narrow);
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
        from the runtime: no fold, on any thread, left a cell live;
      - `cells-fit`: no box constructor's cell and no array element holds
        more counted references than a header counts.
  }];
  let options = [
    ListOption<"holds", "holds", "std::string", "The properties that must hold">,
  ];
  // `quantities-kept` parses the emitted module, which holds ops of every
  // dialect of the contract, whether or not the module under test still
  // does: a dimension read that folded away still loads memref there.
  // `folds-balanced` reads the context's count, which the idr dialect
  // holds.
  let dependentDialects = [
    "::idr::IdrDialect",
    "::mlir::func::FuncDialect", "::mlir::arith::ArithDialect",
    "::mlir::math::MathDialect", "::mlir::ub::UBDialect",
    "::mlir::memref::MemRefDialect"
  ];
}

#endif // IDR_PASSES
