// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Passes of the idr dialect. Each is built by its generated constructor;
// none declares a constructor of its own, and only idr-expect, a test API,
// has an option: nothing on a command line selects how a program is
// compiled. The program is an op, `idr.program`, inside the builtin.module:
// a pass that reads it is anchored on ::idr::ProgramOp and sees only it,
// and a pass anchored on ::idr::FuncOp runs under a nested pass manager
// inside the program and touches nothing outside its function. A pass that
// writes the builtin.module itself (the target, the lowering that takes
// the program apart, everything after) is anchored on it. The nested steps
// a pass runs itself are not declared here: their pass builds them and
// keeps their statistics.

#ifndef IDR_PASSES
#define IDR_PASSES

include "mlir/Pass/PassBase.td"

//===----------------------------------------------------------------------===//
// The module's target (lib/Target)
//===----------------------------------------------------------------------===//

def IdrTarget : Pass<"idr-target", "::mlir::ModuleOp"> {
  let summary = "Give the module its target: triple, CPU, features, data layout";
  let description = [{
    Writes the build's target triple and CPU on the module as its
    `#llvm.target`, then lets LLVM fill in the CPU's features and the data
    layout (`dlti.dl_spec`), and writes the module's
    `dlti.target_system_spec`: for the device `"CPU"`,
    `max_vector_op_width`, the width in bits of the CPU's fixed vector
    registers, LLVM's answer for it, replacing any spec there. Every later
    step reads the target there, the program's passes through the module
    around it: idr-entry tells the runtime's entry which features to test,
    the vectorization schedule sizes its vectors, and idris-mlir compiles
    the objects for it. The triple and the CPU are the build's target entry
    (CMakeLists.txt).
  }];
  let dependentDialects = ["::mlir::LLVM::LLVMDialect", "::mlir::DLTIDialect"];
}

//===----------------------------------------------------------------------===//
// Whole-program facts and the optimizer (lib/Transforms)
//===----------------------------------------------------------------------===//

def IdrDeduplicate : Pass<"idr-deduplicate", "::idr::ProgramOp"> {
  let summary = "Keep one of each class of functions with identical bodies";
  let description = [{
    Monomorphisation makes one function per instantiation, and erasure
    leaves some of them the same function twice over: the same type, the
    same facts, and bodies that match op for op, locations aside. Of each
    class of such functions the one whose name sorts first stays, with the
    locations of the class fused into its own, so that a function is still
    found by the definition it came from; every use of the others, the
    program's root and a label's function among them, names it instead,
    and the others are erased. The classes are found bottom-up over the
    call graph, a function compared once its callees' classes are known, so
    merging is transitive in one run. It runs before idr-defunctionalize,
    whose label sets are then made over the functions that stay.
  }];
  let statistics = [
    Statistic<"numGroups", "groups", "Classes of identical functions merged">,
    Statistic<"numMerged", "merged", "Duplicate functions erased">,
  ];
  let dependentDialects = ["::idr::IdrDialect"];
}

def IdrDefunctionalize : Pass<"idr-defunctionalize", "::idr::ProgramOp"> {
  let summary = "Replace every closure and suspension by a constructor of a sum, every force by a call";
  let description = [{
    A sparse dataflow analysis finds the labels each value of a closure or
    lazy type may hold. A label enters a set only where an op names it
    (`idr.closure`, `idr.suspend`, a closure constant), and moves only along
    the edges an op's flow interface declares, each between two values of
    one carrier. The program is closed, every function defined in it and
    its root its one entry, so every set is finite and known: there is no
    unknown label set.

    Sums are keyed by (type, label set). Each key becomes a sum with one
    constructor per label, of role `Label`, which names the label's
    function and whose fields are its captures. `idr.closure` becomes
    `idr.con`, and `idr.apply` a match whose every case calls its label's
    function; the applies of an empty set are unreachable. A `!idr.lazy`
    key becomes a memo sum, always a box, since forcing updates the one
    cell every holder of it shares: a constructor per label, then one of
    role `Running` and one of role `Forced` that holds the value.
    `idr.suspend` becomes `idr.con` of its label, an evaluated suspension
    `Forced`. Each memo sum gets one dispatch function, named from the
    sum's content as `<sum>.force`, and every `idr.force` becomes an
    `idr.call` of it, so the call graph sees every function a force runs.
    The dispatch matches the cell's state: on a label, `idr.memo.enter`
    makes it Running, the label's function is called, and
    `idr.memo.settle` makes it Forced with the value; on Running,
    `idr.crash`, the loop; on Forced, the value. A memo label whose
    function reaches an observable output is `by_name` in its sum, by the
    effects solved over the call graph the dispatches make. Where a value
    moves from a key to a larger one, the converter rebuilds it in the
    larger sum. Then each function is converted on its own, and which of
    the new sums are boxes is decided as for every data type, by the
    cycles of the type graph.

    The program is then in the `first` stage, which the pass sets on it: no
    closure, suspension, apply or force is left, and the verifier holds
    every later pass to that.
  }];
  let dependentDialects = ["::mlir::ub::UBDialect"];
  let statistics = [
    Statistic<"numSums", "sums", "Closure and memo sums made">,
    Statistic<"numConstructors", "constructors", "Label constructors over every sum made">,
    Statistic<"largestBoxedSum", "largest-boxed", "Labels of the largest closure sum made a box">,
    Statistic<"numBoxed", "boxed", "Types made boxes, each on a cycle of the type graph">,
  ];
}

def IdrEffects : Pass<"idr-effects", "::idr::ProgramOp"> {
  let summary = "Compute the effects of every idr.func";
  let description = [{
    Writes `effects` on every `idr.func` of a program past the `higher`
    stage, as the ready set of idr-optimize writes them: solved once,
    bottom-up over the strongly connected components of the call graph,
    which is complete there, every force being a call and every label
    naming its function. A function's entry is what a run of it may do:
    `io` where it takes a world, as a parameter or in data one holds, or
    forges one; `crash` where it reaches an op that may crash; `diverge`
    where it reaches a function without `total`, itself included. A call
    holds no effects of its own: they are its callee's. In the `higher`
    stage only defunctionalization's label solve knows what an apply runs,
    so the effects are solved after it.
  }];
  let statistics = [
    Statistic<"numIO", "io", "Functions that get io">,
    Statistic<"numCrash", "crash", "Functions that get crash">,
    Statistic<"numDiverge", "diverge", "Functions that get diverge">,
  ];
}

def IdrContify : Pass<"idr-contify", "::idr::ProgramOp"> {
  let summary = "Inline each function called once from another function of its cycle";
  let description = [{
    A function whose one use is a call from another function of its
    strongly connected component of the call graph returns to one place,
    and that call's block dominates it: it is a continuation of the
    function that calls it, as Idris makes one of every `case` and `if` on
    a clause's right-hand side. It is moved into that call with MLIR's
    `inlineCall`, which copies nothing, and erased; the function it moves
    into keeps `total` only if it has it. The components are taken once,
    when the pass starts: a move joins two functions of one component,
    which never joins two components, and leaves every other function's
    one call a call from its component, so one sweep in program order
    decides each function once. This is MLton's contification where a body
    of regions can hold it: a second call site would need a branch out of
    a match region. A function on no cycle with its caller is left to
    idr-optimize, which inlines a function of one call under the caller's
    size. It runs after idr-defunctionalize, where every call is direct,
    and before idr-optimize, so that the cell a function takes apart and
    the constructor its continuation builds meet in one function, where
    idr-rc reuses the one for the other.
  }];
  let statistics = [
    Statistic<"numContified", "contified", "Functions inlined into their one caller">,
  ];
  let dependentDialects = ["::idr::IdrDialect"];
}

def IdrOptimize : Pass<"idr-optimize", "::idr::ProgramOp"> {
  let summary = "Optimize each function once, bottom-up over the call graph";
  let description = [{
    One bottom-up ready set over the strongly connected components of the
    program's call graph, which sees every call, since idr-defunctionalize
    made every apply and every force a direct call. A function is ready
    when every callee outside its component is final, and it is processed
    once:
      - its calls are inlined as MLton decides: a callee that calls nothing
        and has at most 40 ops, or any callee on no cycle of calls with
        (calls - 1) * (size - 60) <= 320, the size counted in ops on the
        callee's final body and the calls in call sites when the pass
        starts. A function on a cycle of calls is never inlined. Calls are
        inlined in call-site order while the caller stays at or under
        10,000 ops; a call past that stays a call;
      - then one pipeline runs on the function, once: idr-identity,
        canonicalize, cse, idr-redirect and idr-constants, which solves the
        function's constants with its callees' summaries. A call into a
        final callee that this exposed is inlined under the same decisions,
        and the pipeline runs on the function again, up to its size;
      - a call whose argument is a known constructor of a sum asks for its
        callee specialized on it: a function keyed by the callee and the
        static pattern, made once, named from its key's canonical hash, and
        processed before the function that asked. A key that embeds a key
        on its own request chain is not made, and its argument stays a
        runtime value: embedding is a well-quasi-order on keys, so every
        chain of requests ends.
    One summary per function holds its effects, identities, binding times,
    constants and inline facts, computed when its component is ready and
    published when it is final; a call reads its callee's. A function no
    symbol use reaches from the program's root is erased after the run, in
    program order. A budget only stops optimizing: no count rejects a
    program. Each body is a function of its own body and its callees' final
    bodies, so the program is the same at every thread count.
  }];
  let statistics = [
    Statistic<"numInlined", "inlined", "Calls inlined">,
    Statistic<"numCapped", "capped", "Calls left calls because the caller reached its size">,
    Statistic<"numErased", "erased", "Functions no symbol use reaches from the root, erased">,
    Statistic<"numNodes", "nodes", "Functions made for a specialization key">,
  ];
  let dependentDialects = ["::idr::IdrDialect", "::mlir::arith::ArithDialect"];
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
    fixpoint over each strongly connected component of the call graph, so
    the functions of a mutual recursion are found together, its callees'
    read as final: the function's summary, which idr-optimize computes for
    each component when it is ready. In each function, every call of such
    a function becomes its argument, at the quantity of the call's result,
    and symbol-dce erases the function once nothing names it. A function of
    a program in the `owned` stage, or one that takes a world, gives back
    nothing.
  }];
  let statistics = [
    Statistic<"numCalls", "calls", "Calls made the argument they give back">,
  ];
  let dependentDialects = ["::idr::IdrDialect"];
}

def IdrConstants : Pass<"idr-constants", "::idr::FuncOp"> {
  let summary = "Propagate constants through one function, calls through their callees' summaries";
  let description = [{
    Sparse conditional constant propagation through one function, a call's
    results taken from its callee's summary: what the callee returns, read
    from its final body once its component is final. A step of
    idr-optimize's inner pipeline, the last, after idr-redirect, so that a
    function's final body states its summary; it reads the summaries
    idr-optimize holds and runs nowhere else.
  }];
  let statistics = [
    Statistic<"numConstants", "constants", "Values replaced by a constant">,
  ];
  let dependentDialects = ["::mlir::arith::ArithDialect"];
}

def IdrRedirect : Pass<"idr-redirect", "::idr::FuncOp"> {
  let summary = "Call the specialization a call's key already has";
  let description = [{
    A call whose key, its callee and the static pattern of its arguments,
    names a specialization the program already holds calls that
    specialization. The per-function half of specialization, a step of
    the pipeline idr-optimize runs on each function. It makes no function.
  }];
  let statistics = [
    Statistic<"numRedirected", "redirected", "Calls redirected to a specialization made before">,
  ];
  let dependentDialects = ["::mlir::arith::ArithDialect", "::idr::IdrDialect"];
}

def IdrBindingTimes : Pass<"idr-binding-times", "::idr::ProgramOp"> {
  let summary = "Report the binding time of every parameter";
  let description = [{
    A remark on every function: `free for every parameter` for one on no
    cycle of calls, or else the binding time of each parameter as
    specialization finds it, fixed, decreasing, bounded or other, computed
    for each strongly connected component of the call graph from its own
    bodies. It changes nothing.
  }];
}

//===----------------------------------------------------------------------===//
// The arrays stage (lib/Transforms/Columns, StructureLoops, Bufferize)
//===----------------------------------------------------------------------===//

def IdrColumns : Pass<"idr-columns", "::idr::ProgramOp"> {
  let summary = "Hold a tensor of records as one tensor per leaf of the record";
  let description = [{
    A tensor whose element is a record (`tensor<...x!idr.data<r>>`, r a
    data type of one plain constructor) becomes one tensor per leaf of the
    record, by upstream's one-to-N type conversion. A leaf is a field; a
    field that is a record is its own leaves in turn, and a field that is a
    tensor of a static shape adds its dimensions after the tensor's. Every
    signature, call, return, match result, scf loop and branch, array op
    (`idr.tabulate`, `idr.tabulate_io`, `idr.fold_last`, `idr.scan_last`,
    `idr.transpose`) and its region, shape tie and linear position that
    carries such a tensor carries its columns instead, at the tensor's
    grade. An element read builds the record from each column at its
    index; a write takes it apart into them; an empty tensor, a cast, a
    slice and a reshape are one per column; a region yields the leaves of
    each record it gives, and a fold's or a scan's accumulator that is a
    record is its leaves. A record keeps its tensor whole when a field is
    graded (a linear field is used once, and its column would be used as
    the tensor is), is an array a world orders, is a tensor whose shape its
    type leaves dynamic, or is a tensor of records. Where an op the
    conversion does not take holds a tensor of records (a constructor's
    field, say), the tensor is gathered from its columns there by an
    `idr.tabulate` and taken apart into them where it comes out: the
    program is the same, held two ways at that boundary. It never refuses
    a program. It runs right after the optimizer, so that what only reads
    one field reads one column, and a column nothing reads is removed with
    the rest of what no caller reads; idr-structure-loops then meets array
    ops over words wherever the records hold words.
  }];
  let dependentDialects = ["::mlir::tensor::TensorDialect", "::idr::IdrDialect"];
}

def IdrStructureLoops : Pass<"idr-structure-loops", "::idr::FuncOp"> {
  let summary = "Lower each array op to a linalg op or to its ordered loop nest";
  let description = [{
    The one-to-one lowering of the array language's generating set,
    `idr.tabulate`, `idr.tabulate_io`, `idr.fold_last`, `idr.scan_last` and
    `idr.transpose`, once every call's callee has its final effects. Each op
    says how it visits its domain, in row-major order: a tabulation's
    dimensions are parallel; a fold's or a scan's frame is parallel and its
    last dimension ordered; a tabulation in the world's order is ordered in
    every dimension. An op whose region returns and does nothing beyond
    compute and crash (no world, no call whose callee's `effects` say it
    may do more), over arrays of words (it makes, folds and reads in its
    region no array of other elements), keeps its parallel dimensions
    parallel in one `linalg.generic`, whose inputs are its region's reads
    of arrays at the op's own indices. A tabulation is that op. A fold
    whose every next accumulator is one associative and commutative integer
    op of its accumulator (`addi`, `muli`, `andi`, `ori`, `xori`, `minsi`,
    `minui`, `maxsi`, `maxui`) without overflow flags, and which reads an
    input along its last dimension, makes that dimension a `reduction`: an
    op marked `nsw` or `nuw`, reassociated, could overflow where the
    program did not. Any other such fold, and such a scan, over a frame is
    an `scf.for` over its last dimension around one parallel
    `linalg.generic` over the frame, each element combined in index order,
    so that a float fold gives the same result on every target and its
    frame computes on lanes. A transpose of words is `linalg.transpose`.
    Every other op becomes an `scf.for` nest in its row-major order, its
    region the body: a tabulation in the world's order, a region with any
    other effect, an array of non-word elements, a fold or a scan with no
    frame that is no reduction. A region that never returns ends its step
    in its crash. A cell whose dimensions its type leaves to the cells is
    made at the domain's first index before the array, which then has its
    size, and that first cell is the first written. No array of non-word
    elements reaches linalg. Each op is lowered once; the pass never
    refuses and touches nothing outside its function.
  }];
  let statistics = [
    Statistic<"numParallel", "parallel",
              "Array ops made linalg ops with parallel dimensions, alone or inside an ordered loop">,
    Statistic<"numReductions", "reductions", "Folds made linalg ops with a reduction dimension">,
    Statistic<"numOrdered", "ordered", "Array ops made ordered scf.for nests">,
  ];
  let dependentDialects = ["::mlir::linalg::LinalgDialect", "::mlir::tensor::TensorDialect",
                           "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
                           "::mlir::ub::UBDialect"];
}

def IdrBufferize : Pass<"idr-bufferize", "::idr::ProgramOp"> {
  let summary = "Put every array in a buffer, in place wherever the program allows";
  let description = [{
    One-Shot Bufferize on the whole program, before counting: every tensor
    becomes a buffer, and every write is decided in place or on a copy,
    once, by upstream's analysis, across calls through upstream's own
    function-boundary models, which read `idr.func`, `idr.call` and
    `idr.return` through FunctionOpInterface and CallOpInterface. A buffer
    is a cell made by the runtime's allocator, and a copy is the runtime's,
    which counts the elements it copies when they hold references;
    counting, not the bufferization, frees them. A linear array enters its
    thread at `idr.lin.enter`, a release, after which its buffer is the
    thread's; each link of a thread is bufferized in place, always, so a
    copy there is an internal error that names the write and the read,
    never a rejection. A copy made at a call is a `missed` remark with its
    conflict. `!idr.lin<T>` is a tensor-like type whose buffer type is
    `!idr.lin<B>`, B the buffer type of T, so the grade is carried through
    the analysis and the rewrite, and no conversion follows them.
  }];
  let statistics = [
    Statistic<"numAllocs", "allocs", "Buffers allocated">,
    Statistic<"numInPlace", "in-place", "Tensor operands bufferized in place">,
    Statistic<"numCopies", "copies", "Tensor operands bufferized out of place">,
  ];
  let dependentDialects = ["::mlir::bufferization::BufferizationDialect",
                           "::mlir::memref::MemRefDialect", "::mlir::linalg::LinalgDialect"];
}

//===----------------------------------------------------------------------===//
// Memory and loops (lib/Transforms/Stack, Ownership, Demand, Tail, Narrow)
//===----------------------------------------------------------------------===//

def IdrStack : Pass<"idr-stack", "::idr::ProgramOp"> {
  let summary = "Put the cells of boxes that never leave their frame on the stack";
  let description = [{
    Gives an `idr.con` of a box its `stack` property when no reference to
    its cell can outlive the frame of the function that builds it, nor the
    loop iteration that builds it. A reference escapes when it is
    returned, forwarded by a terminator of a loop around the con, passed to
    a call in tail position of a function on the same cycle of calls (a
    tail call, idr-tail-calls, or the next iteration of a loop,
    idr-tail-loops), passed to a parameter that escapes (the parameters
    are summarized over the program's calls), used by an op the analysis
    does not know, or stored in a constructor whose value escapes or whose
    fields are read into something that escapes. idr-lower builds such a
    cell in a slot of its function's entry block, with the stack mark in
    its header. A cell of more than 256 bytes stays on the heap, and so do
    a function's cells past 1024 bytes, or 64 bytes for a function on a
    cycle of calls. The property is recomputed wherever the pass runs.
  }];
  // A cell's size is idr-lower's layout, whose components are LLVM types.
  let dependentDialects = ["::mlir::LLVM::LLVMDialect"];
  let statistics = [
    Statistic<"numBoxes", "boxes", "Constructors of boxes seen">,
    Statistic<"numCells", "cells", "Constructors of boxes put on the stack">,
  ];
}

def IdrAccumulate : Pass<"idr-accumulate", "::idr::ProgramOp"> {
  let summary = "Make a recursion that adds its own result a tail call with an accumulator";
  let description = [{
    A self call whose result a tail position adds (an `idr.big.add` of the
    call and a value the call does not compute) becomes a tail call. The
    function keeps its signature and calls a clone with zero, addition's
    identity, named from its content (`<f>.acc.<hash>`); the clone carries
    the sum so far, adds before it calls
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

def IdrRc : Pass<"idr-rc", "::idr::ProgramOp"> {
  let summary = "Make every reference explicit: reset/reuse, borrowed parameters, dup and drop";
  let description = [{
    Runs on a program in the `first` stage, on functional code, after the
    arrays stage and before idr-tail-loops, and leaves it in the `owned`
    stage, which it sets on the program. In order, it writes the owned
    grades borrow inference finds into signatures; runs idr-rc-place on
    each function, nested (reset/reuse and explicit counting); decides the
    exclusive grades: first, for each function, the set of grade contexts
    its callers need, then one copy of it for each context but the one it
    has, each copy made once and named from its key, and the grades written
    into signatures and call results; runs idr-rc-commit on each function,
    nested (the exclusive grades into bodies, shared into each owned
    position); and erases every original that a copy replaced and nothing
    uses. What each does:
      - reset/reuse: in a case region of a match on a box that dies there,
        the box is taken apart where it dies (`idr.take`), and the first
        constructor on each path after that with a cell of the same size
        is built in its cell (`idr.reuse`);
      - borrow inference: a parameter that never needs a reference of its
        own is a view of the caller's value, and its callers keep theirs;
        every other parameter and every result is `!idr.own<T>`;
      - explicit counting: every value that holds references is owned
        (`!idr.own<T>`, one reference of its own, consumed exactly once on
        every path) or a view (read while its owner holds its reference,
        the grade `idr.borrow` gives an owned value): `idr.dup` takes a
        reference of its own from a view before a use that consumes one,
        and `idr.drop` gives one up after the last use;
      - exclusivity: an owned value that holds the only reference to every
        cell it reaches (a constructor of exclusive fields, a field an
        exclusive value was taken apart into, a parameter every caller
        passes exclusive, a result every return makes exclusive; never a
        dup, a constant other than a nullary one, or a stack cell) gets the
        grade `!idr.excl<T>`, on which a take needs no count test and a
        reuse no null test; where it meets an owned position it is shared
        into it (`idr.share`).
    The verifier holds every later pass to the owned stage's rules: owned
    and exclusive grades appear only there, and a counted reference there
    is owned, exclusive or a view.
  }];
  // Buffer loops whose elements hold references become scf.for loops
  // first (linalg's own lowering: affine.apply, memref loads and stores,
  // index constants), and the commit fills a moved-out place with
  // ub.poison; the nested steps load no dialect of their own.
  let dependentDialects = [
    "::idr::IdrDialect", "::mlir::scf::SCFDialect", "::mlir::affine::AffineDialect",
    "::mlir::arith::ArithDialect", "::mlir::memref::MemRefDialect", "::mlir::ub::UBDialect"
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

def IdrDemand : Pass<"idr-demand", "::idr::ProgramOp"> {
  let summary = "Reject a program that breaks the in-place promise its types make";
  let description = [{
    Runs after idr-rc, on a program in the `owned` stage and the grades it
    holds, on every program. A type whose declaration promises that its
    values are rebuilt in place and exclusive makes the promise for every
    parameter of it of quantity 1 that its function rebuilds in place (an
    `idr.reuse` takes its token from an `idr.take` of the parameter, or of
    what a match of it binds): every call must pass it exclusive
    (`!idr.excl<T>`). A call that passes it shared is the error
    `unsupported (uniqueness)` at the call, with a note at the `idr.dup`
    that shared it.
  }];
  let dependentDialects = ["::idr::IdrDialect"];
}

def IdrTrmc : Pass<"idr-trmc", "::idr::ProgramOp"> {
  let summary = "Make a recursion that returns a constructor around its own result a tail call with a destination";
  let description = [{
    A self call whose result is a field of the boxed constructor a tail
    position returns (`Cons x (copy xs)`) becomes a tail call: the
    constructor is built first, with that field pending, and the call
    takes the field as a destination (`!idr.dest`) to write its result
    to. The function keeps its signature and does that for its first
    level; the calls go to a clone, named from its content
    (`<f>.trmc.<hash>`), that takes a destination and returns nothing, whose own such tails write the cell they build to the
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

def IdrNarrow : Pass<"idr-narrow", "::idr::ProgramOp"> {
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
    are the program's, solved once; the word rewrite then runs on each
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

//===----------------------------------------------------------------------===//
// Lowering (lib/Conversion)
//===----------------------------------------------------------------------===//

def IdrLower : Pass<"idr-lower", "::mlir::ModuleOp"> {
  let summary = "Lower idr to func, arith, math, scf, ub and llvm";
  let description = [{
    Lowers the program, in the `owned` stage, inside it. First every
    `idr.func` becomes a `func.func` named by its mangled symbol, every
    `idr.call` a `func.call` and every `idr.return` a `func.return`; the
    facts of `idr.func` are not copied, and nothing after reads one. Then
    matches become scf. Then each function is converted on its own: every
    idr op and type and every memref value takes its runtime layout, the
    ops becoming arith, scf, llvm and calls of the runtime's C functions. A
    memref used inside a function is upstream's descriptor, built at the
    use from its cell, and lowers by upstream's memref patterns; at a
    function boundary and in a cell's field it is its one-pointer
    components. A buffer is a cell of the runtime and a copy the runtime's
    counted copy. `idr.memo.enter` and `idr.memo.settle` become writes of
    the cell's header. Each guard becomes its comparison and a crash with
    its cause. Constants become static data, named by their content, and
    `@__idr_release_cafs` releases what the static thunks among them hold
    once forced. A view (`memref.subview`, `expand_shape`, `collapse_shape`)
    is first expanded into its strided metadata by upstream's patterns, in
    one walk, since upstream's subview lowering takes no unexpanded view.
    The program's functions are lowered in place, each under its mangled
    name, the root renamed to its own, and the program's stage becomes
    `lowered`; its root becomes its entry in idr-entry, after this, which
    takes the program apart.
  }];
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect",
    "::mlir::math::MathDialect", "::mlir::memref::MemRefDialect",
    "::mlir::affine::AffineDialect"
  ];
}

def IdrEntry : Pass<"idr-entry", "::mlir::ModuleOp"> {
  let summary = "Make the lowered root the program's entry: @__idr_main and @main";
  let description = [{
    Runs after idr-lower. Every function and datum of the lowered program
    moves into the builtin.module, and the `idr.program` is erased. Its
    root, which the program names, becomes private like every other
    function, and its kind comes from its lowered signature: `() -> i64`
    returns the exit status, and `() -> ()` returns 0. `@__idr_main` calls
    the root, then `@__idr_release_cafs`, then `idris_rt_main_return`.
    `@main(i32, ptr)` passes `argc` and `argv`, with the CPU features the
    target requires, to `idris_rt_start`, which runs `@__idr_main`. Runtime
    functions are declared where absent.
  }];
  let dependentDialects = ["::mlir::LLVM::LLVMDialect", "::mlir::func::FuncDialect"];
}

//===----------------------------------------------------------------------===//
// After lowering, on func.func (lib/Transforms/Narrow)
//===----------------------------------------------------------------------===//

def IdrNarrowLanes : Pass<"idr-narrow-lanes", "::mlir::func::FuncOp"> {
  let summary = "Run the integer lanes of each vectorized loop in 32 bits under a bound on the sizes";
  let description = [{
    After the vectorization schedule, each vectorized loop (as its ops say:
    vector ops, the loops of its tiles, ops with neither effects nor
    regions) that computes on lanes of integers wider than 32 bits gets two
    versions: where every integer it reads from outside (the sizes, the
    tile bound) is at most B, a copy in which integer range analysis sees
    that bound (each such input stands behind `arith.minui` of itself and
    B) and upstream's arith-int-range-narrowing makes every integer op it
    proves fits 32 bits an op on i32; otherwise the loop as it was. B is
    the largest power of two from 2^31 down to 2^8 at which every
    elementwise integer op of the copy wider than 32 bits fits, and is an
    arith op whose 32-bit form computes the same (a shift by less than 32,
    a signed remainder that never sees INT32_MIN % -1, an op reading its
    operands unsigned on no negative word), found by running the analysis
    on the copy in a scratch module. A loop that runs at most once (its
    bounds, as upstream's value bounds see them, less than a step apart:
    the loop of a peeled tile loop's last tile), or whose integers fit
    under no bound, stays as it is. A vector accumulator (an iteration
    argument of vector type and the elementwise ops that only combine into
    it) keeps its width: a sum is as wide as the program made it, so its
    lanes are no wide lanes to narrow. Remarks in the category
    idr-narrow-lanes: `Narrowed` with the bound, `Wide` with why not.
  }];
  let statistics = [
    Statistic<"numNarrowed", "narrowed", "Vectorized loops given a 32-bit version">,
    Statistic<"numWide", "wide", "Vectorized loops on wide integer lanes left on 64 bits">,
  ];
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::func::FuncDialect", "::mlir::scf::SCFDialect"
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
// Test assertions (lib/Transforms/Expect)
//===----------------------------------------------------------------------===//

// On the builtin.module, not the program: a test checks a module at every
// stage, the lowered one too, where the program has been taken apart.
def IdrExpect : Pass<"idr-expect", "::mlir::ModuleOp"> {
  let summary = "Check named properties of the module, and change nothing";
  let description = [{
    Tests state what a pass guarantees by name, not by the ops that happen
    to show it. Each property in `holds`, `name` or `name=argument`, reports
    every place it fails as an error `expected <name>: <what>`, and the pass
    fails if any does. Each property is a function of the expect library,
    whose declaration says what it checks; `@f` in an argument names the
    functions made from the code the programmer wrote as f.
  }];
  let options = [
    ListOption<"holds", "holds", "std::string", "The properties that must hold">,
  ];
  // `quantities-kept` parses the emitted module, which holds ops of every
  // dialect the frontend writes, whether or not the module under test
  // still does. `folds-balanced` reads the context's count, which the idr
  // dialect holds.
  let dependentDialects = [
    "::idr::IdrDialect",
    "::mlir::func::FuncDialect", "::mlir::arith::ArithDialect",
    "::mlir::math::MathDialect", "::mlir::ub::UBDialect",
    "::mlir::memref::MemRefDialect", "::mlir::tensor::TensorDialect",
    "::mlir::scf::SCFDialect"
  ];
}

#endif // IDR_PASSES
