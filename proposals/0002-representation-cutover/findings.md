# Findings

One entry per finding, in groups. Each entry gives:

- the claim;
- the evidence, at ee4ce8e, as `path:line` or a symbol;
- the selected correction, as a contract section.

The owner is in README's finding map. `ownership.json` is the authority
for it.

Paths are relative to `foreign/idr/lib` unless they start with `runtime/`,
`compiler/`, `tests/`, `include/` or a top-level file. Counts are
**measured** with `grep` at ee4ce8e. Everything else is **read** there.

## The evaluation mode

## F-mode-1 The lowering takes a mode, and branches on it in five files

- **Claim:** `lowerModule(module, jit)` threads one flag through the
  lowering, and it is read in five files.
- **Evidence:**
  - `Lower/Lowering.cppm:151`, `:155`, `:175`, `:242`, `:270`;
  - `Lower/Runtime.cppm:25-32`;
  - `Lower/Counting.cppm:45`;
  - `Lower/StackCell.cppm:31`;
  - `Lower/Pass.cc:23`;
  - `Eval/Round.cppm:80`.
- **Correction:** C6.1.

## F-mode-2 The lowering builds the evaluator's cells itself

- **Claim:** In JIT mode the lowering allocates from the arena with
  `idris_rt_arena_alloc` and writes count 0 itself. In arena mode
  `idris_rt_cell` already gives a persistent cell.
- **Evidence:** `Lower/Runtime.cppm:106-124`; `runtime/idris_rt.h:193-198`.
- **Correction:** C6.1.

## F-mode-3 There are two crash entries, and the lowering picks one

- **Claim:** The lowering chooses between two crash entries.
- **Evidence:** `Lower/Runtime.cppm:66-73` (`idris_rt_crash` or
  `idris_rt_eval_crash`); `Lower/Runtime.cppm:56-60`, the noreturn list.
- **Correction:** C1.5, C6.5.

## F-mode-4 The evaluator's tick is a branch of the lowering

- **Claim:** The tick is decided inside the lowering.
- **Evidence:**
  - `Lower/Runtime.cppm:91-104`: `mayLoop` calls `idris_rt_eval_tick` or
    emits `llvm.sideeffect`;
  - `Lower/Lowering.cppm:171-180`: an `idr.may_loop` at every function
    entry in JIT mode.
- **Correction:** C6.2 (`idr-meter`).

## F-mode-5 The program's entry is built inside the lowering

- **Claim:** The lowering builds the program's entry.
- **Evidence:** `Lower/Lowering.cppm:32-104` (`findRoot`,
  `requiredCpuFeatures`, `emitMain`) and `:155-169`, `:268-273`. `@main`
  takes no `argc`/`argv`, so base's `getArgs` has nothing to read.
- **Correction:** C6.3 (`idr-entry`).

## F-mode-6 The facts at function boundaries are skipped in JIT mode

- **Claim:** The facts are skipped only because evaluated closures call
  through pointers.
- **Evidence:** `Lower/Lowering.cppm:268-273`.
- **Correction:** C6.1, since evaluated code holds no closure.

## Closures

## F-clo-1 Closures are lowered for the evaluator alone

- **Claim:** The closure lowering exists only for `idr-eval`.
- **Evidence:**
  - `Lower/Closures.cppm:1-4`, `:110-118`: "Only idr-eval's lowering meets
    a closure";
  - `Lower/Runtime.cppm`: `code`, `codeType`, `emitCode`, `emitClosure`;
  - `Lower/Lowering.cppm:242-243`.
- **Correction:** C6.1, C6.4.

## F-clo-2 Reify recognizes a closure by its code address

- **Claim:** Reify identifies a closure through a code table.
- **Evidence:**
  - `Eval/Reify.cppm:38-42`, `:226-253`: a map from code addresses to
    labels;
  - `Eval/Round.cppm:146-160`: `codesName`, a global table of every
    label's code.
- **Correction:** C5.7, C6.4.

## F-clo-3 The evaluator's scratch module is not defunctionalized

- **Claim:** This is the one reason a runtime closure exists.
- **Evidence:** `Eval/Round.cppm:78-82` (lowers the scratch with
  `jit=true`); `Eval/Scratch.cppm`.
- **Correction:** C1.3 (the evaluation pipeline), C6.4.

## F-clo-4 Layout keeps labels and code names for closures and suspensions

- **Claim:** Layout carries closure-only state.
- **Evidence:**
  - `Layout/Labels.cppm`, `Layout/CodeName.cppm`,
    `Layout/PlaceClosures.cc`;
  - `Layout/Layouts.cppm:54-57` (`closure`, `forced`) and `:92`
    (`forcedCells`).
- **Correction:** C5.2.

## F-clo-5 The runtime has a closure kind

- **Claim:** A closure kind exists, and nothing a program builds uses it.
- **Evidence:** `runtime/idris_rt.h:44`, `:95`, `:159-161`;
  `runtime/Rc/Freeing.cppm`.
- **Correction:** C1.5, C5.6.

## F-clo-6 Closure conversion is done in Idris

- **Claim:** `Lam` and `Suspend` are closure-converted on the Idris side.
- **Evidence:**
  - `compiler/src/IdrisMLIR/Term.idr:16-20`, `:111-114`: each carries a
    `Label` and a capture vector;
  - `Term.idr:300-330`: `lam`, `delay`;
  - `Emit/Bodies.idr:160-185`: `lifted`, and `:314-342`;
  - `Frontend/Translate/Terms.idr` and `Closed.idr` build them.
- **Correction:** C4.1, C4.2.

## F-clo-7 Upstream's region isolation is unused

- **Claim:** The pinned MLIR provides isolation, and we do not use it.
- **Evidence:** `.toolchain/llvm-project/mlir/include/mlir/Transforms/RegionUtils.h:66-71`
  (`makeRegionIsolatedFromAbove`). No `idr` op has a body region that
  becomes a function.
- **Correction:** C4.3 (`idr-isolate`).

## Thunks

## F-lazy-1 A thunk holds a code pointer

- **Claim:** A thunk's state is a code pointer, so the heap holds code.
- **Evidence:**
  - `Lower/Runtime.cppm:230-304` (`emitSuspension`: `enter` and `done`
    per label);
  - `:306-313` (`distinguish`, a volatile store that defeats identical
    code folding).
- **Correction:** C5.3.

## F-lazy-2 A running thunk keeps its captures alive

- **Claim:** `enter` holds a reference to every capture while the body
  runs. A thunk that consumes a list therefore holds it at count 2
  through the whole consumption, and blocks reuse in place. This is
  STG §9.3.3's space leak.
- **Evidence:** `Lower/Runtime.cppm:270-290`.
- **Correction:** C5.3 (captures move out at entry).

## F-lazy-3 A thunk that forces itself overflows the stack

- **Claim:** A self-forcing thunk calls itself until the stack runs out.
  It does not name the loop.
- **Evidence:** `Lower/Runtime.cppm:236-304`: no state between `enter`
  and `done`.
- **Correction:** C5.3 (`running`, crashing with a named cause).

## F-lazy-4 A constant suspension is mutable static data

- **Claim:** A constant suspension is the only static data that is ever
  written.
- **Evidence:** `Lower/StaticData.cppm:109-110` (`frozen = !isa<LazyType>`).
- **Correction:** C5.5. The memo cell is the only written static data, marked by its kind. Thread-local copies cannot be referenced from constant static data, so they wait for the shards work.

## F-lazy-5 The runtime keeps a list of forced constant suspensions

- **Claim:** The runtime keeps a list of every persistent suspension
  that a force wrote.
- **Evidence:** `runtime/Rc/Counting.cppm:38-70` (`Kept`,
  `idris_rt_lazy_kept`, `idris_rt_release_persistent`);
  `runtime/idris_rt.h:218-223`.
- **Correction:** C5.5, C5.6 (`__idr_release_cafs`, `idris_rt_caf_release`).

## F-lazy-6 Thunks bypass defunctionalization

- **Claim:** The analysis knows a thunk's labels, and the conversion
  does not use them.
- **Evidence:**
  - `Lower/Closures.cppm:120-123`: "Suspensions stay suspensions through
    defunctionalization";
  - `Defunctionalize/AdaptLazy.cc`;
  - `Defunctionalize/Slots.cppm` already follows `SuspendOp` and
    `ForceOp`.
- **Correction:** C5.1.

## F-lazy-7 A force never consumes its cell

- **Claim:** Even the last use of an exclusive thunk writes the memo.
  STG's update flag `n` has no counterpart.
- **Evidence:**
  - `Ownership/UseOf.cppm:20-48`: `ForceOp` is a borrow;
  - `Lower/Closures.cppm:95-110`: the force always calls through the
    code pointer.
- **Correction:** C5.3, C5.4.

## F-lazy-8 A world-forging thunk is memoized, and Chez runs it at every force

- **Claim:** A trusted library's forged world inside a `Delay` runs once
  here and at every force on Chez, which runs every non-CAF `Delay` by
  name.
- **Evidence:** `third_party/Idris2/src/Compiler/Scheme/Common.idr`
  (`defaultLaziness`).
- **Correction:** C5.1 (`by_name`), C5.3.

## F-lazy-9 A suspension's cell is sized per label for the code-pointer protocol

- **Claim:** The suspension cell's size comes from the code-pointer
  protocol.
- **Evidence:** `Layout/PlaceClosures.cc`; `Layout/Layouts.cppm:381-388`.
- **Correction:** C5.2 (one size per memo sum).

## Ownership

## F-own-1 Consumption is an `isa` table

- **Claim:** Every new op must remember to join the table. The table
  says nothing to upstream passes.
- **Evidence:** `Ownership/UseOf.cppm:20-48` (about 20 op kinds).
- **Correction:** C1.1 item 1, C2.1.

## F-own-2 A module attribute changes what a plain type means

- **Claim:** `idr.stage = "owned"` makes a plain `T` mean "view".
- **Evidence:**
  - `Ownership/Stage.cppm`;
  - it is read in `Ownership/{Verify,Rc,Borrowed,OpChecks}.cppm`,
    `Narrow/Words.cppm:42-43` and `Dialect/Verify/Attributes.cc:45-47`.
- **Correction:** C2.2.

## F-own-3 "Holds references" is decided per site

- **Claim:** Each site decides it on its own.
- **Evidence:** `Ownership/Counting.cppm:19-52` (`counted`, `tracked`)
  and its siblings. `substrate.md` S2.4 proposed a type interface, but an
  unboxed sum answers only through its declaration, which a type cannot
  look up (`include/idr/IdrOps.td:78-83`: `DataType` has only a name).
- **Correction:** C2.3 (one function with a scope, not a type
  interface).

## F-own-4 The nested-visibility fix for the clone's self-reference does not hold

- **Claim:** `substrate.md` S2.5 says a clone's "callers to come" can be
  said with `nested` visibility. Refuted: `remove-dead-values` keeps the
  parameters of a public function only (`isPublic()`). The verifier
  allows exactly one public function, the root.
- **Evidence:**
  - `.toolchain/llvm-project/mlir/lib/Transforms/RemoveDeadValues.cpp:278`;
  - `Verify/Program.cppm:22-31`.
- **Correction:** refuted. `Idr_CloneAttr` stays, and the coordinator
  corrects `substrate.md`.

## F-own-5 `idr-canonicalize` copies canonicalize's options

- **Claim:** It copies the options instead of wrapping upstream's
  constructor.
- **Evidence:** `Canonicalize/Pass.cc:36-80`.
- **Correction:** U02 builds the pass from
  `createCanonicalizerPass(GreedyRewriteConfig, ...)`. A listener keeps
  today's per-pattern counts.

## Sentinels

Every entry in this group has the same correction: C2.4.

## F-poison-1 `ub.poison` means "no value" in Narrow, Tail and Specialize

- **Evidence:** `Narrow/{Facts,Versions,Naturals}.cppm`,
  `Tail/{Returned,Loop}.cppm`, `Specialize/ShapeOf.cppm` (8 sites).

## F-poison-2 `ub.poison` means "no value" in the lowering's structure

- **Evidence:** `Lower/{Lowering,TailPosition,Matches,Loops,Facts}.cppm`
  (6 sites).

## F-poison-3 `ub.poison` means "no value" in the cell lowering

- **Evidence:** `Lower/Cells.cppm` (5 sites).

## F-poison-4 `ub.poison` means "no value" in static data

- **Evidence:** `Lower/StaticData.cppm` (2 sites).

## F-poison-5 `ub.poison` means "no value" in ownership and the facts

- **Evidence:** `Ownership/{Placement,IsStatic,ExclusiveAnalysis,Commit}.cppm`,
  `Facts/Evaluation.cppm` (5 sites).

## F-poison-6 `ub.poison` means "no value" in the in-bounds proofs

- **Evidence:** `InBounds/{Returned,Components,Lengths}.cppm` (5 sites).

## F-poison-7 `ub.poison` means "no value" in the linearity verifier

- **Evidence:** `Verify/Linearity.cppm` (1 site).

## F-poison-8 Defunctionalization makes `ub.poison` for unreached values

- **Claim:** These are values of the program, not C++ sentinels. Each
  site is classified, and a sentinel goes.
- **Evidence:** `Defunctionalize/{Sums,Converter}.cppm` (2 sites).

## Partial ops

## F-guard-1 A partial op states its precondition three times

- **Claim:** The precondition is stated by the crash cause, by the
  lowering's check and by the folder's guard.
- **Evidence:**
  - 17 ops with `Idr_MayCrash` (`include/idr/IdrOps.td:319-337`);
  - `getCrashCause` in `Dialect/Ops/{Scalars,Strings,Bigs,Arrays,Buffer,Bytes,Crash}.cc`
    (45 mentions);
  - the folders in `Fold/`.
- **Correction:** C1.1 items 2 and 3, C3.1, C3.4.

## F-guard-2 The lowering checks each partial op itself

- **Claim:** The lowering emits the precondition check per op.
- **Evidence:**
  - `Lower/RuntimeCalls.cppm:70-87` (`crashCondition`) and `:133-136`;
  - `Lower/Scalars.cppm:67-69`, `:183-191`;
  - `Lower/Arrays.cppm:79`, `:155`;
  - `Lower/Buffers.cppm:33`.
- **Correction:** C3.6.

## F-guard-3 `in_bounds` is a claim that only pipeline order makes sound

- **Claim:** `in_bounds` is an inherent property that one pass sets and
  the lowering reads. It rests on facts no verifier sees, so
  `idr-in-bounds` must run right before `idr-lower`.
- **Evidence:**
  - `include/idr/IdrOps.td:1435-1447`, the comment above
    `Idr_ArrayGetOp`;
  - `Dialect/Ops/Arrays.cc:55-60`;
  - `Dialect/Registration/PipelineSteps.cc` (the comment on
    `idr-in-bounds`).

  `substrate.md` called it discardable. It is not, but the defect it
  names stands.
- **Correction:** C3.5.

## F-guard-4 Emit writes partial ops without guards

- **Claim:** The Idris side emits each partial primitive as one op.
- **Evidence:** `compiler/src/IdrisMLIR/Emit/Operations.idr` (every
  partial `Prim` and `IOOp`).
- **Correction:** C3.2, C8.3 (`guardOf`).

## F-guard-5 `substrate.md` names a `char` guard, which no op needs

- **Claim:** `idr.to_char` is total: an invalid code point is 0
  (`include/idr/IdrOps.td`, the summary of `Idr_ToCharOp`). The kind
  that is missing is `finite`, for `ToIntOp` and `BigFromDoubleOp`.
- **Evidence:** `Dialect/Ops/Scalars.cc:57-61`. The audit at 4cfce76
  listed `finite`.
- **Correction:** C1.1 item 2. The coordinator corrects `substrate.md`.

## F-guard-6 A total op made speculatable would escape the proof that removed its guard

- **Claim:** Once a path condition proves a guard away, a speculatable
  total op could be hoisted above that condition. `str.index` is pure,
  so `licm` would move it, which is an out-of-bounds read.
  `substrate.md` S2.3 says the total op is "speculatable", which is
  unsound as written.
- **Evidence:** `include/idr/IdrOps.td:923` (`str.index` is not IO). An
  array access is safe only because it is world-ordered
  (`IdrOps.td:1435-1447`).
- **Correction:** C3.3.

## Constants

## F-const-1 A list constant nests as deep as the list is long

- **Claim:** Two upstream bugs show only at that depth.
- **Evidence:** `PINS.md` `mlir-recursion` and
  `bytecode-deferred-quadratic`: "a computed list of 10,000 elements is
  a constant nested 10,000 deep".
- **Correction:** C7.1, C7.2.

## F-const-2 Reify builds a list one nested `#idr.con` at a time

- **Evidence:** `Eval/Reify.cppm` (`constructor`, called per cell).
- **Correction:** C6.4, C7.2 (`getRun`).

## F-const-3 Static data lowers a constant by recursion over its nesting

- **Evidence:** `Lower/StaticData.cppm` (`constant` and its callees).
- **Correction:** C7.2.

## The primitive set

## F-prim-1 The Idris side mirrors the dialect's primitives by hand

- **Claim:** `Prim` and `IOOp` restate the dialect's ops, and `ioArgs`
  restates their operand types.
- **Evidence:** `compiler/src/IdrisMLIR/Types.idr:252-293`, `:454-509`.
  The Idris mirror of the ops is already generated
  (`compiler/src/IdrisMLIR/Dialect/Idr.idr:1-3`).
- **Correction:** C8.

## F-prim-2 The array loops are special constructors on the Idris side

- **Evidence:** `compiler/src/IdrisMLIR/Term.idr:126-137`;
  `Emit/Bodies.idr:345-376`; `Types.idr` `ArrayLoop`.
- **Correction:** C4.2 (`Region`), C8.2 (`IdrRegionPrim`).

## Base's surface

## F-base-1 Base's file, directory, clock, environment, argument, errno and terminal primitives are rejected

- **Claim:** 66 base `%foreign` definitions have no registry entry, so a
  program that reaches one is rejected as `%foreign`.
- **Evidence:**
  - `third_party/Idris2/libs/base/System.idr`, `System/File/*.idr`,
    `System/Clock.idr`, `System/Directory.idr`, `System/Errno.idr`,
    `System/Term.idr` (73 `prim__` definitions, 7 of them known to
    `compiler/src/IdrisMLIR/Registry/Primitives.idr`);
  - the failing upstream tests in `findings/upstream-idris/results`.
- **Correction:** C9.2, C8.4.

## F-base-2 The runtime has no meaning for base's surface

- **Claim:** `runtime/Io` and `runtime/Platform` serve the standard
  streams, processors and buffers only.
- **Correction:** C9.2, C9.4, C9.6.

## F-base-3 Pointer operations are ruled out, though no raw pointer can exist

- **Claim:** `%foreign` is excluded in user code, so every pointer an
  accepted program holds comes from a recognized primitive. Base's
  wrappers (`getEnv`, `currentDir`, `fGetLine`) take one apart with
  `prim__nullPtr`, `prim__getString` and `prim__free`.
- **Evidence:** `compiler/src/IdrisMLIR/Registry/Recognized.idr:129-135`.
- **Correction:** C9.1.

## F-base-4 Signal handlers are rejected as `%foreign`, not by a named rule

- **Evidence:** `third_party/Idris2/libs/base/System/Signal.idr` (16
  foreign definitions); no `signal` rule in `Rule.idr`.
- **Correction:** C1.6, C9.5.

## F-base-5 `System.Concurrency` is not named `threads`

- **Claim:** `threads` exists but names only `Prelude.IO`'s `fork` and
  `threadWait`.
- **Evidence:** `compiler/src/IdrisMLIR/Registry/Recognized.idr:121-126`;
  `System/Concurrency.idr` (21 foreign definitions).
- **Correction:** C9.5.

## F-base-6 Process creation has no decision

- **Claim:** `system`, `popen` and `popen2` reach the generic `%foreign`
  rejection.
- **Evidence:** `findings/README.md`, open question 3.
- **Correction:** O4, C1.6, C9.5.

## F-base-7 A file handle other than the standard streams reads and writes nothing

- **Evidence:** `include/idr/IdrOps.td:1265-1290` (`write_bytes`,
  `read_bytes`, `eof`: "any other handle reads nothing and gives 0").
- **Correction:** C9.2.

## Promises

## F-prom-1 The acyclic heap is decided and not enforced

- **Evidence:** `findings/decision-acyclic-heap.md`; no `cycle` rule in
  `compiler/src/IdrisMLIR/Rule.idr`. The knot program leaks one cell per
  knot (measured in the decision note).
- **Correction:** C10.1.

## F-prom-2 The in-place promise is stated and not enforced

- **Evidence:** `README.md`, "Why not Lean 4": "the static promise is
  not".
- **Correction:** C10.2.

## Upstream workarounds

## F-up-1 A clang crash is worked around in our code

- **Claim:** `clang-module-layout-forward-declaration` is avoided by
  typing the escape analysis's sets as `func::FuncOp`.
- **Evidence:** `Stack/Escape.cppm`; `PINS.md`
  `clang-module-layout-forward-declaration`.
- **Correction:** C11.1.

## F-up-2 A second clang crash is worked around in our code

- **Claim:** `clang-module-predeclared-new` is avoided with an
  `llvm::SmallString` feature string.
- **Evidence:** `Driver/Retarget.cppm`; `PINS.md`
  `clang-module-predeclared-new`.
- **Correction:** C11.1.

## F-up-3 `idr-dead-values` works around upstream behaviour without a report

- **Claim:** It runs `remove-dead-values` on a copy and keeps the module
  when the copy hashes the same.
- **Evidence:** `include/idr/Passes.td:479-490`;
  `Simplify/DeadValues.cppm`; `findings/substrate.md` §6.
- **Correction:** C11.2.

## Rules

## F-rule-1 The rejections this cutover adds have no names

- **Claim:** `cycle`, `uniqueness`, `signal` and `process` are missing
  from `Rule`, so `parseRule` cannot read them back from
  `idris-mlir-cc`.
- **Evidence:** `compiler/src/IdrisMLIR/Rule.idr:13-81`.
- **Correction:** C1.6.
