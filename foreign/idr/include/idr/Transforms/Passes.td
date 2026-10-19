// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Passes of the idr dialect. Each is built by its generated constructor.
// Only a test's checks are options (idr-expect's properties): nothing on a
// command line selects how a program is compiled. The program is an op,
// `idr.program`, inside the builtin.module: a pass that reads it is
// anchored on ::idr::ProgramOp and sees only it, and a pass anchored on
// ::idr::FuncOp runs under a nested pass manager inside the program and
// touches nothing outside its function. A pass that writes the
// builtin.module itself (the target, the lowering that takes the program
// apart, everything after) is anchored on it. A step one pass runs inside
// another is declared here like any other, and reads what its parent holds
// from the parent's analyses.

#ifndef IDR_PASSES
#define IDR_PASSES

include "mlir/Pass/PassBase.td"

// Every pass of the dialect is an IdrPass, which states its role, the one
// fact the tests read of it (IdrPassRoles.txt, written by idris-mlir-tblgen
// -gen-pass-roles). A role is a record, one of the four below, so that a
// role none of them is is no TableGen value, and TableGen refuses it:
//   - optimization: every transform it makes is optional, an MLIR action
//     (idr/Support/Actions.h); skipping any one, or the pass, leaves a
//     valid module whose behaviour is the same but for the stack and the
//     heap it needs;
//   - lowering: a step the pipeline needs, which changes the program's
//     representation or its stage, or writes what later steps read;
//   - analysis: changes no op; writes only facts the verifier relates to
//     the body, or remarks;
//   - check: changes nothing, and refuses a program or fails a test.
class IdrPassRole<string roleName> {
  string name = roleName;
}
def IdrRoleOptimization : IdrPassRole<"optimization">;
def IdrRoleLowering : IdrPassRole<"lowering">;
def IdrRoleAnalysis : IdrPassRole<"analysis">;
def IdrRoleCheck : IdrPassRole<"check">;

// The stage of the program a pass runs on, and the one it leaves it at,
// each a record: one of the program's stages (`name` is its case of
// ::idr::Stage, which the C++ compiler checks), or `any`, for a pass that
// runs at every stage and leaves the stage it found. A pass whose `requires`
// is a stage derives from ::idr::StagedPass (idr/Transforms/Pipeline.h),
// which refuses a program at another stage and leaves it at `sets`; the
// tests read both of every pass (IdrPassStages.txt, written by
// idris-mlir-tblgen -gen-pass-stages), in the pipeline's order.
class IdrStage<string stageName> {
  string name = stageName;
}
def IdrStageHigher : IdrStage<"Higher">;
def IdrStageFirst : IdrStage<"First">;
def IdrStageGraded : IdrStage<"Graded">;
def IdrStageOwned : IdrStage<"Owned">;
def IdrStageLowered : IdrStage<"Lowered">;
def IdrStageAny : IdrStage<"any">;

// No stage has a default: a pass that names none is no IdrPass, and
// TableGen refuses it.
class IdrPass<string arg, string anchor, IdrPassRole passRole, IdrStage required,
              IdrStage left> : Pass<arg, anchor> {
  IdrPassRole role = passRole;
  IdrStage requires = required;
  IdrStage sets = left;
  assert !or(!ne(required.name, "any"), !eq(left.name, "any")),
         arg # ": a pass that runs at any stage leaves the stage it found";
  let baseClass = !if(!eq(required.name, "any"), "::mlir::OperationPass<" # anchor # ">",
                      "::idr::StagedPass<" # anchor # ", ::idr::Stage::" # required.name #
                      ", ::idr::Stage::" # left.name # ">");
}

//===----------------------------------------------------------------------===//
// The module's target (lib/Target)
//===----------------------------------------------------------------------===//

def IdrTarget : IdrPass<"idr-target", "::mlir::ModuleOp", IdrRoleLowering,
      IdrStageAny, IdrStageAny> {
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

def IdrDeduplicate : IdrPass<"idr-deduplicate", "::idr::ProgramOp", IdrRoleOptimization,
      IdrStageAny, IdrStageAny> {
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

def IdrDefunctionalize : IdrPass<"idr-defunctionalize", "::idr::ProgramOp", IdrRoleLowering,
      IdrStageHigher, IdrStageFirst> {
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
    The dispatch matches the cell's state: on a label, `idr.memo.run`
    exchanges it, its captures moving out into its region, where the cell
    is Running and the label's function is called on them, and the value
    moving in, the cell Forced with it; on Running,
    `idr.crash`, the loop; on Forced, the value. A memo label whose
    function reaches an observable output is `by_name` in its sum, by the
    effects solved over the call graph the dispatches make. Where a value
    moves from a key to a larger one, the converter rebuilds it in the
    larger sum. Then each function is converted on its own, and which of
    the new sums are boxes is decided as for every data type, by the
    cycles of the type graph. No closure, suspension, apply or force is
    left.
  }];
  let dependentDialects = ["::mlir::ub::UBDialect"];
  let statistics = [
    Statistic<"numSums", "sums", "Closure and memo sums made">,
    Statistic<"numConstructors", "constructors", "Label constructors over every sum made">,
    Statistic<"largestBoxedSum", "largest-boxed", "Labels of the largest closure sum made a box">,
    Statistic<"numBoxed", "boxed", "Types made boxes, each on a cycle of the type graph">,
  ];
}

def IdrEffects : IdrPass<"idr-effects", "::idr::ProgramOp", IdrRoleAnalysis,
      IdrStageFirst, IdrStageFirst> {
  let summary = "Compute the effects of every idr.func and idr.call";
  let description = [{
    Writes `effects` on every `idr.func` of the program, as the ready set of
    idr-optimize writes them: solved once, bottom-up over the strongly
    connected components of the call graph, which is complete once every
    force is a call and every label names its function. A function's entry
    is what a run of it may do: `io` where it takes a world, as a parameter
    or in data one holds, or forges one; `crash` where it reaches an op
    that may crash; `diverge` where it reaches a function without `total`,
    itself included. Every call of a function gets the same effects, written
    with its callee's before any caller's are solved.
  }];
  let statistics = [
    Statistic<"numIO", "io", "Functions that get io">,
    Statistic<"numCrash", "crash", "Functions that get crash">,
    Statistic<"numDiverge", "diverge", "Functions that get diverge">,
  ];
}

def IdrKnots : IdrPass<"idr-knots", "::idr::ProgramOp", IdrRoleCheck,
      IdrStageFirst, IdrStageFirst> {
  let summary = "Refuse a program whose types let an array hold a reference to itself";
  let description = [{
    An array, of any rank (an IORef is one of rank 0), and a memo cell are
    the cells written after they exist. A memo cell closes no knot of
    counted cells: a counted one's value is made of its captures, which
    exist before it, and of globals, and a static one's force makes what it
    holds persistent. So a knot of references needs an array whose element
    type can reach the array again, and no count frees one. Whether
    one can is read off the program's type graph, once every closure is a
    constructor of a sum: each such cycle is refused, `cycle`, once, where
    the program's own code makes one of its arrays, or else builds a value
    of a type on it, or else at the program.
  }];
}

def IdrContify : IdrPass<"idr-contify", "::idr::ProgramOp", IdrRoleOptimization,
      IdrStageAny, IdrStageAny> {
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

def IdrOptimize : IdrPass<"idr-optimize", "::idr::ProgramOp", IdrRoleOptimization,
      IdrStageFirst, IdrStageFirst> {
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
        starts. A function on a cycle of calls is inlined only into a
        member of its cycle that hands it a closure or suspension of a
        function outside the cycle, built for the call, where the inline
        leaves no call of the cycle (beta reduction). Calls are
        inlined in call-site order while the caller stays at or under
        10,000 ops; a call past that stays a call;
      - then one pipeline runs on the function, once: idr-identity,
        canonicalize, cse, idr-redirect and idr-constants, which solves the
        function's constants with its callees' summaries.
        A call into a final callee that this exposed is inlined under the
        same decisions, and the pipeline runs on the function again, up to
        its size;
      - a call whose argument is a known constructor of a sum asks for its
        callee specialized on it: a function keyed by the callee and the
        static pattern, made once, named from its key's canonical hash, and
        processed before the function that asked. A key that embeds a key
        on its own request chain is not made, and its argument stays a
        runtime value: embedding is a well-quasi-order on keys, so every
        chain of requests ends.
    One summary per function holds its effects, identities, binding times,
    constants and inline facts, computed when its component is ready and
    published when it is final; a call reads its callee's. A budget only
    stops optimizing: no count rejects a program. Each body is a function
    of its own body and its callees' final bodies, so the program is the
    same at every thread count. The inner pipeline's own steps are made for
    each run, holding the summaries and the node table they read, so no
    other pipeline can hold one, and none is registered; each counts into a
    statistic of this pass named for the step, and so does its cse, whose
    counts are read off each copy of the pipeline once the waves end.
  }];
  let statistics = [
    Statistic<"numInlined", "inlined", "Calls inlined">,
    Statistic<"numCapped", "capped", "Calls left calls because the caller reached its size">,
    Statistic<"numNodes", "nodes", "Functions made for a specialization key">,
    Statistic<"numIdentityCalls", "idr-identity.calls",
              "Calls made the argument they give back">,
    Statistic<"numRedirected", "idr-redirect.redirected",
              "Calls redirected to the specialization or raise node their key names">,
    Statistic<"numConstants", "idr-constants.constants", "Values replaced by a constant">,
    Statistic<"numCSE", "cse.num-cse'd", "Operations the inner cse merged into an equal one">,
    Statistic<"numDCE", "cse.num-dce'd", "Operations the inner cse erased as dead">,
  ];
  let dependentDialects = ["::idr::IdrDialect", "::mlir::arith::ArithDialect"];
}

def IdrBindingTimes : IdrPass<"idr-binding-times", "::idr::ProgramOp", IdrRoleAnalysis,
      IdrStageFirst, IdrStageFirst> {
  let summary = "Report the binding time of every parameter";
  let description = [{
    A remark on every function: the binding time of each parameter as
    specialization finds it, `fixed` (every call of the function from its
    own strongly connected component of the call graph passes it the same
    parameter back) or `varies`, computed for each component from its own
    bodies. It changes nothing.
  }];
}

//===----------------------------------------------------------------------===//
// The arrays stage (lib/Transforms/Columns, StructureLoops, Bufferize)
//===----------------------------------------------------------------------===//

def IdrColumns : IdrPass<"idr-columns", "::idr::ProgramOp", IdrRoleOptimization,
      IdrStageFirst, IdrStageFirst> {
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
    type leaves dynamic, or is a tensor of records, and when a data type of
    the program holds a tensor of it: a constructor's field holds the tensor
    whole, so its columns would be copied into a fresh tensor at every
    constructor and out of it at every match, and a linear tensor's columns
    used twice. Where another op the conversion does not take holds a
    tensor of records, the tensor is gathered from its columns there by an
    `idr.tabulate` and taken apart into them where it comes out: the
    program is the same, held two ways at that boundary. It never refuses
    a program. It runs right after the optimizer, so that what only reads
    one field reads one column, and a column nothing reads is removed with
    the rest of what no caller reads; idr-structure-loops then meets array
    ops over words wherever the records hold words.
  }];
  let dependentDialects = ["::mlir::tensor::TensorDialect", "::idr::IdrDialect"];
}

def IdrStructureLoops : IdrPass<"idr-structure-loops", "::idr::FuncOp", IdrRoleLowering,
      IdrStageFirst, IdrStageFirst> {
  let summary = "Lower each array op to a linalg op or to its ordered loop nest";
  let description = [{
    The one-to-one lowering of the array language's generating set,
    `idr.tabulate`, `idr.tabulate_io`, `idr.fold_last`, `idr.scan_last` and
    `idr.transpose`, once every call has its final effects. Each op
    says how it visits its domain, in row-major order: a tabulation's
    dimensions are parallel; a fold's or a scan's frame is parallel and its
    last dimension ordered; a tabulation in the world's order is ordered in
    every dimension. An op whose region returns and does nothing beyond
    compute and crash (no world, no call whose `effects` say it may do
    more), over arrays of words (it makes, folds and reads in its
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
    size, and that first cell is the first written; the rest of the domain
    is one loop over its linear index from 1, delinearized in row-major
    order, and an empty domain makes no cell. No array of non-word
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
                           "::mlir::affine::AffineDialect", "::mlir::ub::UBDialect"];
}

def IdrBufferize : IdrPass<"idr-bufferize", "::idr::ProgramOp", IdrRoleLowering,
      IdrStageFirst, IdrStageFirst> {
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
    never a rejection. A function on a cycle of calls is analyzed with the
    others of its cycle until their boundaries are a fixpoint. After
    bufferization, a read of an element that holds references followed by
    the write of the same place becomes `idr.element.update`.
    `!idr.lin<T>` is no tensor to One-Shot; one retyping after it turns
    every tensor left inside another type into its cell's buffer.
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
// Memory and loops (lib/Transforms/Ownership, Stack, Demand, Tail, Narrow)
//===----------------------------------------------------------------------===//

def IdrFrames : IdrPass<"idr-frames", "::idr::ProgramOp", IdrRoleOptimization,
      IdrStageFirst, IdrStageFirst> {
  let summary = "Carry the rest of a run of a closure on a stack of frames";
  let description = [{
    A call of a function of the caller's own call cycle that runs a closure
    (one a closure sum names as a label, or a dispatch whose cases give such
    calls, in a tail block),
    whose result the rest of its block consumes, becomes a tail call: the
    values the rest reads are a frame pushed on a stack the cycle's
    functions take (`<f>.frames`, a data type of an empty stack and a frame
    per call), and a tail that would return a value gives it to the
    function's `<f>.resume` with the stack, which pops a frame and runs its
    rest, or returns the value on the empty stack. `<f>.run` is each
    member's body on the stack; the member calls it with the empty one. The
    run of an IO action is the case: a bind whose left action is a bind
    runs it as a tail call, so binds nested to the left run in constant
    stack, their nesting on the heap. A recursion over data keeps its
    calls.
  }];
  let dependentDialects = ["::mlir::ub::UBDialect"];
  let statistics = [
    Statistic<"numFunctions", "functions", "Functions given a run and a resume">,
    Statistic<"numFrames", "frames", "Calls whose rest became a frame">,
  ];
}

def IdrAccumulate : IdrPass<"idr-accumulate", "::idr::ProgramOp", IdrRoleOptimization,
      IdrStageFirst, IdrStageFirst> {
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

// The steps of idr-rc, the pipeline that makes every reference explicit
// (Ownership.h), in its order, on functional code, after the arrays stage
// and before idr-tail-loops: cells, stack, grades, place and exclusive, then
// upstream's symbol-dce. Memory is explicit from the first: a constructor
// of a cell is the cell's allocation and its initialization, so placing a
// cell, recycling it and counting it each change one op. Each step reads
// what an earlier one decided from the program's analyses.
def IdrRcCells : IdrPass<"idr-rc-cells", "::idr::FuncOp", IdrRoleLowering,
      IdrStageFirst, IdrStageFirst> {
  let summary = "Make each constructor of a cell the cell's allocation and its initialization";
  let description = [{
    Every `idr.con` whose constructor has a cell of its own (a box's
    constructor that is no atom) becomes `idr.cell.new`, a fresh cell of
    the heap, and `idr.cell.init`, which writes the constructor's fields
    into it and gives the box, at the constructor's grade. The constructor
    of an unboxed sum, and an atom, stay `idr.con`: neither has a cell of
    its own.
  }];
  let statistics = [
    Statistic<"numBoxes", "boxes", "Constructors of a cell made its allocation and initialization">,
  ];
  let dependentDialects = ["::idr::IdrDialect"];
}

def IdrRcStack : IdrPass<"idr-rc-stack", "::idr::ProgramOp", IdrRoleOptimization,
      IdrStageFirst, IdrStageFirst> {
  let summary = "Put the cells that never leave their frame on the stack";
  let description = [{
    The lifetimes of the program (the grade's third part, heap or frame),
    inferred from the rules of the frame (IR/Lifetimes.h), which the
    function verifier holds the result to. An `idr.cell.new` becomes
    `idr.cell.stack`, a cell of its function's frame, when every value
    its box may reach, once it is the frame's, keeps the rules: none is
    returned, moved into memory that exists before the op that moves it,
    forwarded out of a region that runs again, passed to a self call that
    becomes the next iteration of a loop, used by an op that declares no
    flow, or filled into a cell of the heap. Each value a cell of the frame
    reaches, through fields, constructors, joins and parameters over the
    whole program, is then written of the frame, and a value of the heap
    that meets one at a join or a parameter is shared into it
    (`idr.share`). A cell that reaches a call in tail position of a
    function on its function's cycle of calls stays on the heap, so that
    the cycle keeps running in constant stack. idr-lower makes a cell of
    the frame in a slot of its function's entry block, with the stack mark
    in its header. It runs before reuse and exclusivity are decided, which
    see the stack cells: a stack cell is never recycled, nor exclusive. A
    cell of more than 256 bytes stays on the heap, and so do a function's
    cells past 1024 bytes, or 64 bytes for a function on a cycle of calls.
  }];
  // A cell's size is idr-lower's layout, whose components are LLVM types.
  let dependentDialects = ["::mlir::LLVM::LLVMDialect"];
  let statistics = [
    Statistic<"numBoxes", "boxes", "Cells of the heap seen">,
    Statistic<"numStackCells", "stack-cells", "Cells put on the stack">,
  ];
}

def IdrRcGrades : IdrPass<"idr-rc-grades", "::idr::ProgramOp", IdrRoleLowering,
      IdrStageFirst, IdrStageGraded> {
  let summary = "Decide reset/reuse and borrowed parameters, grade every signature, place the counts";
  let description = [{
    First the boundaries where counting meets upstream's buffer ops, in
    each function: an `idr.own.adopt` takes over the reference of each
    `memref.alloc`, and an `idr.own.give` hands each store of an element
    that holds references its value. Then two decisions on the program:
      - reset/reuse (the program's Reuses): in a case region of a match on
        a box that dies there, the box is taken apart where it dies, and
        the first `idr.cell.new` on each path after that, of a cell of the
        same size, gets its cell;
      - borrow inference (the program's Borrows): a parameter that never
        needs a reference of its own is a view of the caller's value, and
        its callers keep theirs; every other parameter, every parameter a
        reuse takes apart among them, and every result is `!idr.own<T>`.
    Those grades go into every signature and entry argument, and every
    body is placed under them, in parallel: at each site of the Reuses the
    box is taken apart (`idr.take`), and each `idr.cell.new` that gets its
    cell becomes `idr.cell.recycle` of the take's token. Then explicit
    counting: every value that holds references is owned (`!idr.own<T>`,
    one reference of its own, consumed exactly once on every path) or a
    view (read while its owner holds its reference, the grade `idr.borrow`
    gives an owned value): `idr.dup` takes a reference of its own from a
    view before a use that consumes one, and `idr.drop` gives one up after
    the last use. Before the counts are placed, a select of values that
    hold references becomes a match, an owned value that dies in a case
    region is taken apart there, and a field or an element that needs a
    reference of its own takes it where it is read. Grading and placement
    are one pass: a signature graded ahead of its callers' bodies breaks
    each call of it, so no verifier runs between them.
  }];
  // A cell's size, which reuse compares, is idr-lower's layout.
  let dependentDialects = ["::idr::IdrDialect", "::mlir::LLVM::LLVMDialect"];
  let statistics = [
    Statistic<"numBorrowed", "borrowed", "Parameters borrowed">,
    Statistic<"numTakes", "takes", "Dead boxes taken apart for their cells">,
    Statistic<"numReuses", "reuses", "Cells recycled from a dead box">,
    Statistic<"numDups", "dups", "idr.dup added">,
    Statistic<"numDrops", "drops", "idr.drop added">,
  ];
}

def IdrRcExclusive : IdrPass<"idr-rc-exclusive", "::idr::ProgramOp", IdrRoleLowering,
      IdrStageGraded, IdrStageOwned> {
  let summary = "Grade exclusive every owned value that holds the only reference to its cells";
  let description = [{
    An owned value that holds the only reference to every cell it reaches
    (a fresh cell of the heap, a constructor of exclusive fields, a field an
    exclusive value was taken apart into, a parameter every caller passes
    exclusive, a result every return makes exclusive; never a dup, a
    constant other than a nullary one, or a stack cell) gets the grade
    `!idr.excl<T>`, on which a take needs no count test and a recycle no
    null test. A value some view of which takes a reference of its own is
    shared (`idr.share`) where it is consumed. Exclusivity is solved on the
    program as placement left it, which decides the keys of grade
    specialization: every function some live call gives exclusive values
    while another shares one, and every function such a key calls that
    takes a followed parameter shared. Each key gets one copy, made once
    and named from its key; one solve of the program with its copies sends
    each call of a key or of its copy to the copy when it gives an
    exclusive value at every followed parameter and to the original
    otherwise; each call goes where that solve sent it, and the grades it
    proved go into signatures and call results. Then each function is
    committed, nested: the exclusive grades into its body, and an exclusive
    value shared into each owned position it meets, a moved-out place
    filled with `ub.poison`. A copy or an original no call reaches any more
    is symbol-dce's, next in idr-rc.
  }];
  let dependentDialects = ["::idr::IdrDialect", "::mlir::ub::UBDialect"];
  let statistics = [
    Statistic<"numExclusive", "exclusive", "Values that hold the only reference to their cells">,
  ];
}

def IdrDemand : IdrPass<"idr-demand", "::idr::ProgramOp", IdrRoleCheck,
      IdrStageOwned, IdrStageOwned> {
  let summary = "Reject a program that breaks the in-place promise its types make";
  let description = [{
    On the grades idr-rc wrote, on every program. A type whose declaration
    promises that its values are rebuilt in place and exclusive makes the
    promise for every parameter of it of quantity 1 that its function
    rebuilds in place (an `idr.cell.recycle` takes its token from an
    `idr.take` of the parameter, or of what a match of it binds): every
    call must pass it exclusive
    (`!idr.excl<T>`). A call that passes it shared is the error
    `unsupported (uniqueness)` at the call, with a note at the `idr.dup`
    that shared it.
  }];
  let dependentDialects = ["::idr::IdrDialect"];
}

def IdrTrmc : IdrPass<"idr-trmc", "::idr::ProgramOp", IdrRoleOptimization,
      IdrStageOwned, IdrStageOwned> {
  let summary = "Make a recursion that returns its own result inside a context a tail call with a destination";
  let description = [{
    A self call whose result the value a tail position returns holds, in
    cells and parts of values nothing else reaches (`Cons x (copy xs)`,
    `x :: x :: dup xs`, the action of the rest inside the actions that run
    it, across a join), becomes a tail call: each cell that takes the
    result is built first, with that field pending, and the call takes the
    field as a destination (`!idr.dest`) to write its result to, once the
    value the tail returns is built. The function keeps its signature and
    does that for its first level; the calls go to a clone, named from its
    content (`<f>.trmc.<hash>`), that takes a destination and returns
    nothing, whose own such tails write the value they build to the
    destination they got and recurse on the new one, and whose other tails
    write their value. idr-tail-loops then makes the clone a loop: the
    structure is written top down in constant stack. A self call in any
    other position (one whose result is inspected) stays a call of the
    function.
  }];
  let statistics = [
    Statistic<"numFunctions", "functions", "Functions given a destination-passing clone">,
    Statistic<"numTails", "tails", "Contexts around a self call that became tail calls">,
  ];
}

def IdrTailLoops : IdrPass<"idr-tail-loops", "::idr::FuncOp", IdrRoleOptimization,
      IdrStageAny, IdrStageAny> {
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

def IdrNarrow : IdrPass<"idr-narrow", "::idr::ProgramOp", IdrRoleOptimization,
      IdrStageOwned, IdrStageOwned> {
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
    are the program's, solved once; idr-narrow-words then runs on each
    function nested.
  }];
  // idr-narrow-words runs nested, under this pass, whose dialects are the
  // ones loaded for it: it makes ub.poison.
  let dependentDialects = ["::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
                           "::mlir::ub::UBDialect"];
  let statistics = [
    Statistic<"numVersioned", "versioned", "Loops versioned on a small descending natural">,
  ];
}

def IdrNarrowWords : IdrPass<"idr-narrow-words", "::idr::FuncOp", IdrRoleOptimization,
      IdrStageOwned, IdrStageOwned> {
  let summary = "Make the bigs and naturals of one function proved to fit a small i64 words";
  let description = [{
    The word rewrite of one function, under the ranges its program's
    idr-narrow solved, which it reads from the program's analyses: the
    values carried round loops and out of merges first, while every value
    is still the one analysed, then the ops. A conversion it made folds
    once, and what then reads nothing goes.
  }];
  let dependentDialects = ["::mlir::arith::ArithDialect", "::mlir::ub::UBDialect"];
}

//===----------------------------------------------------------------------===//
// Lowering (lib/Conversion)
//===----------------------------------------------------------------------===//

def IdrLower : IdrPass<"idr-lower", "::mlir::ModuleOp", IdrRoleLowering,
      IdrStageOwned, IdrStageLowered> {
  let summary = "Lower idr to func, arith, math, scf, ub and llvm";
  let description = [{
    Lowers the program inside it. First every
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
    counted copy. `idr.memo.run` becomes the read of the label's captures
    and the writes of the cell's header and forced value around its
    region, after which a static cell makes what it holds persistent
    (`idris_rt_persist_held`). Each guard becomes its comparison and a crash
    with its cause. Constants become static data, named by their content.
    A view (`memref.subview`, `expand_shape`, `collapse_shape`)
    is first expanded into its strided metadata by upstream's patterns, in
    one walk, since upstream's subview lowering takes no unexpanded view.
    The program's functions are lowered in place, each under its mangled
    name, the root renamed to its own; its root becomes its entry in
    idr-entry, after this, which takes the program apart.
  }];
  let dependentDialects = [
    "::mlir::arith::ArithDialect", "::mlir::scf::SCFDialect",
    "::mlir::ub::UBDialect", "::mlir::LLVM::LLVMDialect",
    "::mlir::func::FuncDialect", "::mlir::cf::ControlFlowDialect",
    "::mlir::math::MathDialect", "::mlir::memref::MemRefDialect",
    "::mlir::affine::AffineDialect"
  ];
}

def IdrEntry : IdrPass<"idr-entry", "::mlir::ModuleOp", IdrRoleLowering,
      IdrStageLowered, IdrStageLowered> {
  let summary = "Make the lowered root the program's entry: @__idr$entry$body and @main";
  let description = [{
    Every function and datum of the lowered program moves into the
    builtin.module, and the `idr.program` is erased. Its root, which the
    program names, becomes private like every other function. Its kind is
    the root rule's (`idr::rootKind`), which the lowered stage's verifier
    holds: a `() -> i64` root returns the exit status, and an IO root,
    `() -> ()` once lowered, returns 0. The entry body, `@__idr$entry$body`,
    calls the root, then `idris_rt_main_return`. `@main(i32, ptr)` passes `argc` and `argv`, with
    the CPU features the target requires, to `idris_rt_start`, which runs
    the entry body. Those two runtime functions are declared where the
    module declares none.
  }];
  let dependentDialects = ["::mlir::LLVM::LLVMDialect", "::mlir::func::FuncDialect"];
}

//===----------------------------------------------------------------------===//
// After lowering, on func.func (lib/Transforms/Narrow)
//===----------------------------------------------------------------------===//

def IdrNarrowLanes : IdrPass<"idr-narrow-lanes", "::mlir::func::FuncOp", IdrRoleOptimization,
      IdrStageAny, IdrStageAny> {
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

def IdrReturnedArguments
    : IdrPass<"idr-returned-arguments", "::mlir::ModuleOp", IdrRoleOptimization,
      IdrStageAny, IdrStageAny> {
  let summary = "Drop a result a function always returns as one of its arguments";
  let description = [{
    A result that is, on every path, one and the same argument of its
    function (directly, through what a region branch joins, an `scf.if`,
    an `scf.while` or an `scf.execute_region` among them, through either
    value a select chooses, or through a call, recursive or not, that gives
    back the argument it was passed) is dropped, and every caller uses the
    argument it passed instead. Which argument each value is is one sparse
    forward dataflow over the module, solved by upstream's solver from
    every function's arguments, a call reading its callee's results; a
    result only calls that never return give is any argument. A value threaded through a function and given back
    (a linear array through its reads and writes) is such a result once
    lowered, and costs the caller nothing when dropped: it holds the value
    already. Only a private function every use of which is a direct call
    changes its signature. The results to drop are the module's;
    idr-returned-arguments-drop then runs on each func.func nested.
  }];
  let statistics = [
    Statistic<"numDropped", "dropped", "Results dropped, whose callers use the argument">,
  ];
}

def IdrReturnedArgumentsDrop
    : IdrPass<"idr-returned-arguments-drop", "::mlir::func::FuncOp", IdrRoleOptimization,
      IdrStageAny, IdrStageAny> {
  let summary = "Drop from one function, its returns and its calls the results its module returns as arguments";
  let description = [{
    The rewrite of one function under what its module's
    idr-returned-arguments found, which it reads from the module's
    analyses: a function whose results drop takes the kept ones and returns
    them, and each call of such a function has the kept results, each
    dropped one being the operand the call passed in its place. It writes
    nothing outside its function.
  }];
}

def IdrTailCalls : IdrPass<"idr-tail-calls", "::mlir::ModuleOp", IdrRoleLowering,
      IdrStageAny, IdrStageAny> {
  let summary = "Make every call in tail position on a cycle of calls a guaranteed tail call";
  let description = [{
    Runs on the LLVM dialect, last. The plan is the module's (which calls
    become guaranteed tail calls, which functions change convention or
    return through memory); the rewrite then runs on every `llvm.func` at
    once, and drops the blocks its entry does not reach. A call is in tail
    position when the path from it returns its
    result unchanged: through extractvalue and insertvalue, through
    branches that carry it, past conditions the path itself decides and ops
    that only compute. The path enters a block with the same decided
    argument values once at most, however long it is: one that comes back
    to a block with the values it came with before loops, and its call is
    not in tail position; with other values it may decide another branch. When such a call's caller and
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
def IdrExpect : IdrPass<"idr-expect", "::mlir::ModuleOp", IdrRoleCheck,
      IdrStageAny, IdrStageAny> {
  let summary = "Check named properties of the module, and change nothing";
  let description = [{
    Tests state what a pass guarantees by name, not by the ops that happen
    to show it. Each property in `holds`, `name` or `name=argument`, reports
    every place it fails as an error `expected <name>: <what>`, and the pass
    fails if any does. Each property is a row of the expect library's table
    (Expect/Lookup.cpp), whose comment says what it checks; its argument is
    read into its shape before it runs. `@f` in an argument names the
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
