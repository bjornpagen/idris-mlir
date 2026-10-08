# 0002: the representation cutover

**Status:** proposed. This is a swarm packet, not yet launched.

The packet makes the compiler hold each thing it knows once, in the
representation MLIR already has a name for, and deletes the special case
that held it before.

- **Reference counting.** Ownership is declared on the ops and carried
  in the grades. The `isa` table and the `idr.stage` attribute go.
- **Partial ops.** A partial op becomes a guard plus a total op. The
  three statements of every precondition, and the `in_bounds` claim,
  go.
- **Closures.** Closure conversion moves from Idris to upstream's region
  isolation.
- **Thunks.** A thunk becomes a memo sum that defunctionalization
  builds. The code pointer, the kept list and the mutable static data
  go.
- **Compile-time evaluation.** It runs the program's own lowering, with
  no mode. The closure lowering and the code table go.
- **Constants.** List constants become flat, which retires the list
  cases of two pins.
- **The primitive set.** It has one home. `Prim` and `IOOp` stop
  mirroring ODS.
- **Base's surface.** Base's file, directory, clock, environment and
  terminal functions become runtime primitives on both targets, and a
  pointer becomes a runtime handle.
- **Promises.** The two promises the compiler states but does not check
  become checks: the acyclic heap, and in place.
- **Upstream.** The workarounds for upstream bugs become patches.

It is the work W1 to W10 of `findings/README.md`, compiled into 23 lanes
that start at once.

- **Evidence:** `findings/substrate.md` and `findings/concurrency.md`
  §2, read at ee4ce8e and re-read for this packet. The findings, with
  `path:line`, are in `findings.md`.
- **Contracts:** `contracts.md`.
- **Work:** `work-units.md`, `ownership.json` and `dispatch/`.
- **Launch:** `orchestrator.md`.
- **Adversarial review:** `review.md`.

## Engagement contract

- **Mode: proposal.** Nothing here authorizes implementation. The owner
  says "launch".
- **Tree at authoring:** `main` at ee4ce8e, clean. The packet is the
  only change, and it is committed on its own. Every anchor in
  `findings.md` was read at ee4ce8e. If HEAD has moved at launch, the
  coordinator diffs every cited file first (`orchestrator.md` step 1).
- **Shared declarations:** the hubs in `contracts.md` C1, which belong
  to the coordinator alone:
  - `IdrOps.td`, `IdrPlatformOps.td`, `Passes.td` and `Idr.h`;
  - the CMake area and unit lists;
  - `Dialect.cppm` and `Mlir.cppm`;
  - the pipeline;
  - `idris_rt.h` and `Rule.idr`.

  The coordinator applies C1 at dispatch. Lanes write against its text.
- **Verification timing:** no lane builds or runs a test (C13). The tree
  is red mid-swarm by design: lanes write against declarations other
  lanes are writing. The coordinator runs AGENTS.md's checks at
  integration, with repairs and reruns as a phase:
  1. `make check`
  2. `make build`
  3. `make test`
  4. `make test-idr`
  5. `make test-mlir-tools`

  Tests are authored concurrently by U22 and U23.
- **Commit policy:** lanes do not commit. The coordinator commits to
  `main` at integration, in a few commits that each stage only this
  packet's paths, after the suites are green. Then it pushes `main` and
  forces the session branch to it, as the owner's standing practice
  says.
- **Toolchain:** U01's clang and MLIR patches change the pinned LLVM.
  `make bootstrap` rebuilds it, which takes hours. It is the packet's
  one long serialization, and it is confined to the integration tail:
  every other lane's code builds on today's toolchain, and only the two
  clang workarounds' deletion and the dead-values deletion need the
  patched one.
- **Deletions allowed:** everything under "The Elon pass" and "Retired
  mechanisms". No user data exists. A test is deleted only when it
  tested a retired mechanism and nothing else.
- **Compatibility:** none owed inside the compiler. Its MLIR, its
  runtime ABI (`idris_rt.h`) and its dumps change; the runtime and the
  compiler ship together. The language the compiler accepts grows (C9)
  and loses nothing.
- **Targets:** x86_64 Linux and arm64 macOS. Nothing here assumes x86,
  Linux, ELF or musl (C0, C9.6).

## The move

1. **Declare once, derive the rest.** The facts the compiler keeps in
   tables and module attributes move onto ops and types, where MLIR's
   generic passes and the verifier see them:
   - consumption is declared on each op in ODS (C2.1);
   - a view is a grade (C2.2);
   - a precondition is a guard op (C3).

   Each old copy is deleted in the same lane that writes the new one.
2. **Make control flow data.** A thunk's state is no longer a code
   pointer the heap holds. It is a constructor of a memo sum, and a
   force is a small evaluator over it (C5). A closure is no longer
   converted by hand in Idris. It is a region, isolated by upstream's
   utility (C4).
3. **One mode, one set, one meaning.** Compile-time evaluation lowers
   with the program's lowering (C6). The Idris side's primitive set is
   generated from ODS (C8). Every primitive of base has one meaning in
   the runtime, behind the platform layer (C9).
4. **Promises become checks.** The acyclic heap is checked by the
   program verifier (C10.1). The in-place promise is checked when asked
   (C10.2).

**What becomes unrepresentable:**

- a thunk that keeps its captures alive while it runs (F-lazy-2);
- a thunk that recurses on itself to a stack overflow (F-lazy-3);
- a heap cell that holds a code address (F-lazy-1, F-clo-2);
- written static data that nothing marks (F-lazy-4);
- a proved access whose proof a later pass silently invalidates
  (F-guard-3, F-guard-6);
- a module whose stage a missing attribute misreports (F-own-2);
- an evaluation that differs from the program because it took another
  lowering (F-mode-1).

## The Elon pass

These requirements are deleted, not implemented:

| Requirement as practiced | Why it existed | Verdict |
|---|---|---|
| The lowering has an evaluation mode | The evaluator could not run the program's lowering: it holds closures | **Deleted.** It now defunctionalizes its scratch module (C6.4), and the two genuine differences are passes (`idr-meter`, `idr-entry`). |
| A closure has a runtime form | `idr-eval` | **Deleted** with the mode (C6.1). |
| A thunk is a code pointer the force calls | The self-updating model | **Deleted.** The state is a constructor; the force switches on it (C5.3). |
| A forced constant thunk is written in static memory, and the runtime lists it | A constant thunk is static data | **Deleted in part.** The list goes: a compiler-made function releases the forced values (C5.5). The cell is still written once, and its kind marks it. Making it per shard belongs to the shards work, because static data may point at it (C5.5, "Why not thread-local"). |
| Every force memoizes | "The memo is what Lazy means" | **Deleted.** Chez runs `Delay` by name. The memo is our complexity guarantee, decided per thunk (C5.3). |
| `useOf` lists every consuming op | No place on the op to say it | **Deleted.** Consumption is declared in ODS beside the op (C2.1). |
| A module attribute marks the owned stage | A plain type meant two things | **Deleted.** The view is `borrow` (C2.2). |
| A proved access is marked `in_bounds` | No place to put a proof | **Deleted.** A proof is the absence of the guard (C3.5). |
| `idr-in-bounds` must run right before the lowering | The claim rested on facts nothing re-checks | **Deleted.** The pass runs where its index systems see the most (C1.3). |
| Closure conversion happens in Idris | The frontend built closures for Emit | **Deleted.** `makeRegionIsolatedFromAbove` (C4.3). |
| `Prim` and `IOOp` list the dialect's ops | They predate the generated mirror | **Deleted.** `IdrPrim` is generated (C8). |
| `ArrayGen` and `ArrayFold` are Idris constructors | Each library loop got its own | **Deleted.** One `Region` node (C4.2). |
| A pointer operation is a raw pointer | `decision-threads-pointers.md` | **Deleted** for base's handles, since user `%foreign` is excluded and every pointer is a handle (C9.1). |
| A list constant nests as deep as the list | `#idr.con` held one cell | **Deleted.** Runs (C7). |
| Clang and MLIR misbehaviour is worked around in our code | No patch existed | **Deleted.** Patches (C11). |
| A type interface for "holds references" (`substrate.md` S2.4) | One representation | **Refuted.** An unboxed sum answers only through its declaration, which a type cannot look up. One function with a scope instead (C2.3). |
| `nested` visibility for a clone's callers to come (`substrate.md` S2.5) | MLIR's vocabulary | **Refuted.** `remove-dead-values` reads `isPublic()` only (F-own-4). The clone attribute stays. |
| A total op is speculatable (`substrate.md` S2.3) | Upstream passes move it freely | **Refuted as written.** It is speculatable only while its guard, or a constant, feeds it (C3.3, F-guard-6). |
| A `char` guard (`substrate.md` S2.3) | Listed with the others | **Refuted.** `to_char` is total. `finite` is the missing kind (F-guard-5). |
| `idr.lazy.settle` as an MLIR op (`concurrency.md` §2.3) | The memo write visible to passes | **Deferred.** The write happens below the last pass that reasons about references, in the force's lowering. Ownership stays one op's contract through `idr-rc` (C5.3). It returns with phase 2. |
| A property "no heap cell stores a code address" (W7's proof) | Proving F-lazy-1 fixed | **Deleted.** The mechanism is gone: no code address exists to store. |
| `missed` remarks wherever a pass declines (W3) | Observability | **Out of scope.** It is not a representation change. |

**What stays, and why:**

- **The symbol form inside the simplify loop** (C4.4). Moving regions
  through specialization, inlining and evaluation is phase 2, and needs
  its own packet.
- **The three result types `!idr.fn`, `!idr.lazy` and the future
  `!idr.join`.** They are three protocols.
- **The grade as a wrapper type** (`substrate.md` §7).
- **The reserved compile stack.** Deep data other than lists can still
  need it.
- **`Layouts::counted`.** Lowered components are a different question
  from types (C2.3).

## Rulings

These are decisions, not questions.

- **Phase 1 of S1.** `idr-isolate` runs first, and the simplify loop
  keeps the symbol form. This is narrower than `substrate.md` S1.2 ("at
  the first need of a name"). It moves closure conversion out of Idris
  now, without making every pass of the simplify loop region-aware in
  the same change. S1.2 now says so.
- **The force expands in the lowering, not in MLIR before `idr-rc`.**
  Writing the memo before `idr-rc` would make `idr-rc` reason about a
  field that moves out of a shared cell. After it, the grades say
  everything the protocol needs: view, owned or `excl`.
- **The memo is per cell, not per op.** `by_name` is a constructor
  attribute: a cell holds one label, and the label decides.
- **Memo sums are always boxed.** A memo needs an identity.
- **Static thunks stay one per process.** `concurrency.md` §2.4 made
  them thread-local, but static data can point at a static thunk (a
  constant stream's tail), and a thread-local address is not a link-time
  constant. The cell keeps the thunk kind, so the shards work can find
  every one. §2.4 records the correction.
- **The cycle check excludes memo cells.** No recursive `let` of values
  exists in Idris, so a memo cannot reach itself (C10.1).
- **A guard's cause is data.** The crash text is the guard's `cause`
  attribute, copied from today's message, so messages do not move.
- **Handles, not addresses.** Null is `-1`, because `0` is already
  stdin (`Registry/Primitives.idr:256`).
- **`OSClock` is immediate** (C9.4). No allocation and no leak.
- **The two GC clocks are invalid.** This is the divergence class
  `gc-clock`.

## Owner decisions

Each has a default chosen so that lanes can start. One word vetoes it.

- **O1. A pointer is a runtime handle** (C9.1).
  - Default: yes.
  - Consequence: base's `getEnv`, `currentDir`, `nextDirEntry`,
    `fGetLine` and `fGetChars` compile unchanged.
    `decision-threads-pointers.md` gains one paragraph; the coordinator
    writes it.
  - On a veto: U18 recognizes those wrappers by name, each as one
    primitive returning `Maybe String` or `Either FileError String`. The
    `RawPointer` exclusions stay, and U16's string slots go.
- **O2. The divergence class `gc-clock`** (C9.4).
  - Default: yes.
  - On a veto: the GC clocks are `unsupported (process)`-style
    exclusions under a new rule, which the owner names.
- **O3. Memo per thunk** (`findings/README.md` proposed decision 3, as
  C5 implements it).
  - Default: yes.
  - On a veto: every force memoizes, as today. The `by_name` attribute
    and the one-shot row go, and the divergence on world-forging thunks
    stays.
- **O4. Process creation is outside the language for now**,
  `unsupported (process)` (open question 3 of `findings/README.md`).
  - Default: yes.
  - On a veto with "inside, blocking": `system` and `popen` join C9.2 as
    blocking primitives (`posix_spawn`), and `popen` returns a file
    handle.
- **O5. `--demand in-place` stays opt-in in this packet.**
  - Default: yes. It becomes the default when the benchmarks pass it,
    which is `findings/README.md` proposed decision 6, after
    qualification.

## The frontier: 23 lanes, disjoint writes, all start at dispatch

| Lane | Outcome | Exclusive writes | Consumes |
|---|---|---|---|
| U01 | Clang crashes and dead-values fixed by patches; workarounds deleted | `upstream/clang-module-*` (2), `upstream/remove-dead-values-unreachable`, their `tests/upstream/` dirs, `IDR/Stack/Escape.cppm`, `IDR/Driver/Retarget.cppm`, `IDR/Simplify` | C11 |
| U02 | The cycle check; the linearity verifier's sentinel; `idr-canonicalize` on upstream's pass | `IDR/Verify`, `IDR/Canonicalize` | C10.1, C2.4, C1.6 |
| U03 | Consumption declared and derived; the `borrow` grade; one holds-references; `idr.stage` gone; the force's grade | `IDR/Ownership`, `IDR/Facts`, `IDR/Dialect/{Grades,Types,Effects,Verify}`, `IDR/Dialect/Dialect/Initialize.cc`, `IDR/Dialect/Ops/{Lin,Dest}.cc` | C1.1 item 1, C1.4, C2, C5.4 |
| U04 | Guards' folders and speculation; the total ops lose their causes | `IDR/Dialect/Ops/{Check,Scalars,Strings,Bigs,Arrays,Buffer,Bytes,Crash}.cc`, `IDR/Dialect/Crashes`, `IDR/Fold`, `IDR/Ops` | C1.1 items 2 and 3, C3.1 to C3.4, C7.2 |
| U05 | The guards' lowering; no check in the total ops' lowering | `IDR/Lower/{Checks,Scalars,Strings,Bigs,Arrays,Buffers,Words,RuntimeCalls}.cppm` | C3.6 |
| U06 | `idr-in-bounds` erases the guards it proves; `in-bounds=`, `no-guards=` | `IDR/InBounds`, `IDR/Expect` | C3.5, C2.4 |
| U07 | The Idris side writes `idr.lambda`, `idr.delay` and `Region`; closure conversion leaves Idris | `CS/Term.idr`, `CS/Ids.idr`, `CS/Emit/{Bodies,Declarations,Monad}.idr`, `CS/Frontend/Translate/{Terms,Closed}.idr` | C4.1, C4.2, C8.2 |
| U08 | `idr-isolate`; the region ops' verifiers | `IDR/Isolate`, `IDR/Dialect/Ops/Regions.cc` | C1.1 item 4, C4.3 |
| U09 | Lazy keys become memo sums; `by_name`; no `!idr.lazy` after defunctionalization | `IDR/Defunctionalize`, `IDR/Dialect/Ops/{Lazy,Data}.cc` | C1.1 item 5, C5.1 |
| U10 | Layout without labels or code; memo cells sized once | `IDR/Layout` | C5.2, C2.3 |
| U11 | `Runtime` without a mode or closures; the force's lowering | `IDR/Lower/{Runtime,Closures,Cells,BuildBox,Fields}.cppm` | C5.3, C6.1 |
| U12 | Static memo cells marked by kind, `@__idr_release_cafs`, runs lowered by a loop | `IDR/Lower/StaticData.cppm` | C5.5, C7.2 |
| U13 | `lowerModule` with no flag; `idr-entry`; `idr-meter`; the Lower partition list | `IDR/Lower/{Lowering,Counting,StackCell,Facts,Matches,Loops,TailPosition,Lower,Patterns}.cppm`, `IDR/Lower/Pass.cc`, `IDR/Lower/CMakeLists.txt`, `IDR/Lower/{Entry,Meter}{.cppm,/}` | C6.1 to C6.3, C1.5 |
| U14 | The evaluator runs the program's pipeline; reify of sums and runs; no code table | `IDR/Eval` | C1.3, C5.7, C6.4, C7.2 |
| U15 | One crash entry; `argc`/`argv`; no closure kind; `idris_rt_caf_release` | `RT/{Rc,Start,Eval,Alloc}` | C1.5, C5.6, C6.5 |
| U16 | Base's surface in the runtime; handles; both targets | `RT/Platform`, `RT/Io`, `RT/CMakeLists.txt` | C9 |
| U17 | Generated `IdrPrim`/`IdrRegionPrim`; `Prim` reduced; `IOOp` gone; guards emitted | `CS/Types.idr`, `CS/Emit/Operations.idr`, `CS/Frontend/Translate/Primitives.idr`, `foreign/idr/tools/idris-mlir-tblgen.cc` | C8, C3.2 |
| U18 | Base's surface registered; pointers as handles; `signal`, `threads`, `process` by name | `CS/Registry`, `CS/Registry.idr`, `CS/Frontend/Translate/Types.idr` | C9.1, C9.2, C9.5, C8.4 |
| U19 | `#idr.con` runs | `IDR/Dialect/Attrs` | C7 |
| U20 | `idr-demand` and `--demand in-place` | `IDR/Demand`, `IDR/Driver/{Options,Run}.cppm`, `CS/Frontend/Main.idr` | C10.2, C1.3 |
| U21 | Narrow, Tail and Specialize without sentinels and on the `borrow` grade | `IDR/Narrow`, `IDR/Tail`, `IDR/Specialize` | C2.2, C2.4 |
| U22 | The dialect suite's discriminators; retired mechanisms out of `tests/idr` | `T/idr` | C12 |
| U23 | The program suites' discriminators, rejections and divergence class | `T/{programs,accept,reject,properties,lib,registry,compiler}`, `T/Main.idr` | C12 |
| coordinator | Hubs (C1), PINS, findings, README, AGENTS, integration, qualification | see `ownership.json` | all |

`IDR` is `foreign/idr/lib`, `RT` is `runtime`, `CS` is
`compiler/src/IdrisMLIR` and `T` is `tests`. No two rows intersect by
prefix, and `validate.sh` proves it. Every lane writes against
`contracts.md` from the first minute. The one serialization is the
toolchain rebuild, which is part of the integration tail.

## Finding map

Every finding has exactly one accountable lane. Supporting producers and
consumers are named in the lane's dispatch. `refuted` means the claim
did not survive the source.

| Finding | Disposition | Owner |
|---|---|---|
| F-mode-1 | `lowerModule(ModuleOp)`; no flag anywhere | U13 |
| F-mode-2 | every cell from `idris_rt_cell` | U11 |
| F-mode-3 | one crash entry; the child redirects | U15 |
| F-mode-4 | `idr-meter` | U13 |
| F-mode-5 | `idr-entry`, with `argc`/`argv` | U13 |
| F-mode-6 | facts always applied | U13 |
| F-clo-1 | closure lowering deleted | U11 |
| F-clo-2 | reify reads sums; code table deleted | U14 |
| F-clo-3 | scratch defunctionalized | U14 |
| F-clo-4 | labels and code names deleted from Layout | U10 |
| F-clo-5 | closure kind becomes the thunk kind; closure release deleted | U15 |
| F-clo-6 | `Lam`/`Suspend` carry bodies; Emit writes regions | U07 |
| F-clo-7 | `idr-isolate` | U08 |
| F-lazy-1 | memo sum; switch on the tag | U11 |
| F-lazy-2 | captures move out at entry | U11 |
| F-lazy-3 | `running` crashes with a cause | U11 |
| F-lazy-4 | memo cells are the only written static data, marked by kind; the `frozen` rule goes | U12 |
| F-lazy-5 | kept list deleted; `idris_rt_caf_release` | U15 |
| F-lazy-6 | lazy keys become memo sums | U09 |
| F-lazy-7 | the one-shot force on `excl` | U11 |
| F-lazy-8 | `by_name` | U09 |
| F-lazy-9 | one size per memo sum | U10 |
| F-own-1 | consumption in ODS; `useOf` derived | U03 |
| F-own-2 | the `borrow` grade; `idr.stage` deleted | U03 |
| F-own-3 | `idr::holdsReferences` | U03 |
| F-own-4 | refuted (`RemoveDeadValues.cpp:278`) | coordinator |
| F-own-5 | `createCanonicalizerPass(GreedyRewriteConfig)` | U02 |
| F-poison-1 | `std::optional` | U21 |
| F-poison-2 | `std::optional` | U13 |
| F-poison-3 | `std::optional` | U11 |
| F-poison-4 | `std::optional` | U12 |
| F-poison-5 | `std::optional` | U03 |
| F-poison-6 | `std::optional` | U06 |
| F-poison-7 | `std::optional` | U02 |
| F-poison-8 | classified: IR poison stays, any sentinel goes | U09 |
| F-guard-1 | guards; total ops without causes | U04 |
| F-guard-2 | `idr.lower:checks`; no per-op checks | U05 |
| F-guard-3 | proof is the absence of the guard | U06 |
| F-guard-4 | Emit emits `guardOf` before each partial primitive | U17 |
| F-guard-5 | refuted (`char`); `finite` added | coordinator |
| F-guard-6 | `checkSpeculatability` | U04 |
| F-const-1 | `#idr.con` runs | U19 |
| F-const-2 | reify builds runs with `getRun` | U14 |
| F-const-3 | static data lowers a run by a loop | U12 |
| F-prim-1 | generated `IdrPrim`; `IOOp` deleted | U17 |
| F-prim-2 | one `Region` node | U07 |
| F-base-1 | registry entries for C9.2 | U18 |
| F-base-2 | runtime meanings for C9.2 on both targets | U16 |
| F-base-3 | pointers as handles (O1) | U18 |
| F-base-4 | `signal` | U18 |
| F-base-5 | `threads` for `System.Concurrency` | U18 |
| F-base-6 | `process` (O4) | U18 |
| F-base-7 | file handles served | U16 |
| F-prom-1 | the cycle check in the program verifier | U02 |
| F-prom-2 | `idr-demand{promises=in-place}` | U20 |
| F-up-1 | clang patch; `Escape.cppm` written plainly | U01 |
| F-up-2 | clang patch; `Retarget.cppm` written plainly | U01 |
| F-up-3 | MLIR patch hunk; `idr-dead-values` deleted | U01 |
| F-rule-1 | four rules in `Rule.idr` | coordinator |

## Retired mechanisms

The validator refuses these names outside a Delete section.

- retired: idris_rt_lazy_kept
- retired: emitSuspension
- retired: emitClosure
- retired: distinguish(
- retired: lazyDoneName
- retired: storeForcedInfo
- retired: populateClosurePatterns
- retired: isJit
- retired: IdrLowerOptions{/*jit=*/
- retired: stageAttr
- retired: ownedStage
- retired: in_bounds $in_bounds
- retired: crashCondition
- retired: IDRIS_RT_KIND_CLOSURE
- retired: codesName
- retired: AdaptLazy
- retired: IdrDeadValues
- retired: ArrayGenF
- retired: ArrayFoldF
- retired: ioArgs

## Qualification

The coordinator does this after integration.

1. **The suites.** All are green: `make check`, `make build`,
   `make test`, `make test-idr` and `make test-mlir-tools`, on the
   patched toolchain. Run it on x86_64 Linux, and on arm64 macOS when a
   Mac is available. If the Mac is not, say "macOS: NotRun", never
   "green".
2. **Sensitivity.** Each C12 discriminator fails at ee4ce8e, with the
   same test files, run once. Each row's result is recorded.
3. **Measurements the packet owes:**
   - `bench/run.sh` against the last record: no program slower beyond
     the record's run-to-run spread (15% on the shared host);
   - compile times within 10% (`T/compile-times.sh`);
   - peak live cells of `thunk-consumes-list` before and after;
   - the size of `compiler/src` and `foreign/idr/lib` in lines before
     and after.
4. **`tests/upstream-idris/run`.** Run it, and record in
   `findings/upstream-idris/results` the tests that now pass (the file,
   directory, clock and environment tests).
5. **Docs.**
   - `findings/substrate.md` S1.2, S2.3, S2.4 and S2.5, and
     `concurrency.md` §2.3, were corrected when this packet was written.
   - At qualification, `decision-threads-pointers.md` gains O1's
     paragraph, and `findings/README.md` marks W1 to W10 done.
   - Then this packet's status line becomes "accepted" (or "accepted in
     part"), and it stays as the record of the reasoning
     (`proposals/README.md`).

## Documents

- [contracts.md](contracts.md): every shared declaration.
- [findings.md](findings.md): every finding, with its evidence.
- [work-units.md](work-units.md): U01 to U23, and the coordinator's own
  work.
- [ownership.json](ownership.json): exclusive write sets and mandatory
  findings.
- `dispatch/U??-*.md`: assembled from [dispatch/parts](dispatch/parts) by
  [dispatch/assemble.sh](dispatch/assemble.sh).
- [orchestrator.md](orchestrator.md): the launch instruction.
- `review.md`: the adversarial review, and the table of disagreements.
- [validate.sh](validate.sh): the document checks. Its numbers are below.

## Validation

`sh proposals/0002-representation-cutover/validate.sh`:

```json
(filled in by the coordinator after the last edit)
```
