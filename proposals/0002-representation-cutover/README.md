# 0002: the representation cutover

**Status:** accepted in part: launched and integrated in 93f5d9c9, 327c2e30
and 0451b1b8; "Rulings on the swarm" records what changed while it ran.
Qualification is open: the suites on both targets, with the toolchain the
one recipe builds (proposal 0003), the bench against the launch base and
`tests/upstream-idris` are NotRun. Its adversarial review (`review.md`) is folded in: see "Rulings on the
adversarial review". What changed between authoring and launch is
folded in too: see "Rulings at launch".

The packet makes the compiler hold each thing it knows once, in the
representation MLIR already has a name for, and deletes the special case
that held it before.

- **Reference counting.** Ownership is declared on the ops, and the
  owned stage is read from the grades. The `isa` table and the
  `idr.stage` attribute go.
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
- **Upstream.** `idr-dead-values`, our workaround for the calls
  `remove-dead-values` rebuilds, becomes a patch (C11.2). Of the two clang
  workarounds, one went with the LLVM pin (20fcfadb), and the other waits
  for an x86_64 Linux host (C11.1).

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
  `findings.md` was read at ee4ce8e.
- **Tree at launch (the launch base):** `main` at ccc3e1dc, which is
  1677b8cb, then phase 1b's 08a065e4 (no oracle: the Chez oracle taken
  out of `tests/` and the docs, each test's expected files its
  specification) and ccc3e1dc (`idr-simplify` ends again: a clone of a
  loop breaker is a breaker). The coordinator re-diffed every owned path
  and re-read every cited anchor from ee4ce8e to 1677b8cb, then from
  1677b8cb to ccc3e1dc, at launch (`orchestrator.md` step 1), moved the
  anchors that moved, and fixed the packet through `contracts.md`;
  "Rulings at launch" records each change. If HEAD moves past ccc3e1dc
  before dispatch, step 1 re-diffs from it and records the new launch
  base here.
  ee4ce8e does not build on the pinned toolchain: 20fcfadb ported
  `foreign/idr` to llvm main 7208ba24, and the 23.1.2 toolchain is not
  rebuilt. So every comparison with "today" (sensitivity, crash
  messages, dumps, benchmarks, compile times) is against the launch base,
  built on the pinned toolchain.
- **Shared declarations:** the hubs in `contracts.md` C1, which belong
  to the coordinator alone:
  - `IdrOps.td`, `IdrPlatformOps.td`, `Passes.td` and `Idr.h`;
  - the CMake area and unit lists;
  - `Dialect.cppm` and `Mlir.cppm`;
  - the pipeline;
  - `idris_rt.h` and `Rule.idr`.

  The coordinator applies C1 at dispatch. Lanes write against its text.
- **Verification timing:** no lane builds or runs a suite, `make check`
  included (C13). `make check` builds the test runner, and it is red
  mid-swarm by design: `spec/dialects-current` until the dialect mirror
  is regenerated, `spec/file-size` while a unit is mid-split. A lane runs
  only the one spec test its acceptance names, from that test's
  directory (U01 also runs its own check and reproducers, C13). The
  coordinator runs AGENTS.md's checks at integration, in the order of
  `work-units.md` "Integration", with repairs and reruns as a phase.
  Tests are authored concurrently by U22 and U23.
- **Commit policy:** lanes do not commit. The coordinator commits to
  `main` at integration, in a few commits that each stage only this
  packet's paths, after the suites are green. U01's group, its
  `PINS.md` text, C1.2's `idr-dead-values` lines and the sentences of
  02's and 06's READMEs go in one commit: AGENTS.md puts a patch's
  directory, its check, its `PINS.md` entry and the deletion of the
  workaround it replaces in the same change (C1.8). Before pushing, the
  coordinator fetches and rebases onto `origin/main`, since another
  agent pushes `upstream/README.md`, the `upstream/NN` READMEs and
  `PINS.md`. Then it pushes `main` and forces the session branch to it,
  as the owner's standing practice says.
- **Toolchain:** the pin is llvm main 7208ba24 (20fcfadb). This host's
  toolchain is `.toolchain/llvm-macos`, built with the `llvm.patch` of
  02 to 07, 09 and 15. U01's patch for `remove-dead-values` (C11.2)
  changes it, and `make bootstrap` then rebuilds stage 2 and what is
  built with it (0h30m and 0h05m for stage 2 and GMP in the cutover's
  run, `.toolchain/bootstrap.trunk.log`). It is the packet's one long
  serialization, and it is confined to the integration tail: every other
  lane's code builds on today's toolchain, and only U01's work needs the
  patched one. U01 writes it in the shared checkout as usual, and the
  coordinator sets all of it aside at integration until the rebuild
  (C13). No x86_64 Linux toolchain is built at the pin yet
  (Qualification).
- **Deletions allowed:** everything under "The Elon pass" and "Retired
  mechanisms". No user data exists. A test is deleted only when it
  tested a retired mechanism and nothing else.
- **Compatibility:** none owed inside the compiler. Its MLIR, its
  runtime ABI (`idris_rt.h`) and its dumps change; the runtime and the
  compiler ship together. The language the compiler accepts grows (C9)
  and loses nothing.
- **Targets:** x86_64 Linux and arm64 macOS. Nothing here assumes x86,
  Linux, ELF or musl (C0, C9.6). The swarm builds and tests on arm64
  macOS, the launch host; x86_64 Linux is NotRun until its toolchain is
  built at the pin (Qualification).

## The move

1. **Declare once, derive the rest.** The facts the compiler keeps in
   tables and module attributes move onto ops and types, where MLIR's
   generic passes and the verifier see them:
   - consumption is declared on each op in ODS (C2.1);
   - the owned stage is a fact of the grades, not an attribute (C2.2);
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
| Every force memoizes | "The memo is what Lazy means" | **Deleted.** A trusted library's effect happens where its value is demanded, so a thunk whose label reaches an observable effect runs at every force. Every other thunk memoizes, and so does one a static constant names: a top-level constant names one value of the program, evaluated once, as Idris defines a top-level definition, so a `trace` in it observes that one evaluation (C5.1, C5.5, O3). |
| `useOf` lists every consuming op | No place on the op to say it | **Deleted.** Consumption is declared in ODS beside the op (C2.1). |
| A module attribute marks the owned stage | A plain type meant two things | **Deleted.** The stage is read from the grades: a module is owned when any value has `own` or `excl` (C2.2, O6). Views stay plain. |
| A proved access is marked `in_bounds` | No place to put a proof | **Deleted.** A proof is the absence of the guard (C3.5). |
| `idr-in-bounds` must run right before the lowering | The claim rested on facts nothing re-checks | **Deleted.** The pass runs where its index systems see the most (C1.3). |
| Closure conversion happens in Idris | The frontend built closures for Emit | **Deleted.** `makeRegionIsolatedFromAbove` (C4.3). |
| `Prim` and `IOOp` list the dialect's ops | They predate the generated mirror | **Deleted.** `IdrPrim` is generated (C8). |
| `ArrayGen` and `ArrayFold` are Idris constructors | Each library loop got its own | **Deleted.** One `Region` node (C4.2). |
| A pointer operation is a raw pointer | `decision-threads-pointers.md` | **Deleted** for base's handles, since user `%foreign` is excluded and every pointer is a handle (C9.1). |
| A list constant nests as deep as the list | `#idr.con` held one cell | **Deleted.** Runs (C7). |
| The calls `remove-dead-values` rebuilds are worked around in our code (`idr-dead-values`) | No patch existed | **Deleted.** A patch of its own (C11.2). Of the clang workarounds, `clang-module-predeclared-new`'s went with the pin, and `clang-module-layout-forward-declaration`'s stays until an x86_64 Linux host reduces it (C11.1). |
| A type interface for "holds references" (`substrate.md` S2.4) | One representation | **Refuted.** An unboxed sum answers only through its declaration, which a type cannot look up. One function with a scope instead (C2.3). |
| `nested` visibility for a clone's callers to come (`substrate.md` S2.5) | MLIR's vocabulary | **Refuted.** `remove-dead-values` keeps a signature only for a public or external function, or one with users outside the pass root (`RemoveDeadValues.cpp:280-281` at 7208ba24), and a `nested` function of the program's module is neither (F-own-4). The clone attribute stays. |
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
  exists in Idris, so a heap memo cannot reach itself. A static memo cell
  can, through persistent cells, which are never counted, so nothing
  leaks (C10.1).
- **A guard's cause is data.** The crash text is the guard's `cause`
  attribute, copied from today's message, so messages do not move.
- **Handles, not addresses.** Null is `-1`, because `0` is already
  stdin (`Registry/Primitives.idr:256`).
- **`OSClock` is immediate** (C9.4). No allocation and no leak.
- **The two GC clocks are invalid** (C9.4, O2). No collector runs, and
  base makes both optional, so `clockTime GCCPU` and `clockTime GCReal`
  give `Nothing`. That is the runtime's documented meaning, not a
  difference from another backend.

## Rulings on the adversarial review

`review.md` found that four contracts would have made lanes write code
that does not compile or does not verify, and that several others left a
literal worker to guess. Each finding was checked against the source and
folded in. The review's own packet edits (its list of eight) stand.

| # | Finding | Ruling | Where |
|---|---|---|---|
| R1 | A `borrow` grade on views fails 31 ODS operand constraints, `memref.dim` and three verifiers | **Accepted.** Views stay plain; the stage is derived (O6). | C2.2, U03, U21 |
| R2 | The trait table does not compile for `idr.con`, the ODS-effect ops and `idr.force` | **Accepted.** `idr.con` keeps its own effects and calls `consumedEffects`; ops whose effects ODS declares get the interface only; `idr.force` is not in the table. | C2.1, C1.1 item 5, U03, U09 |
| R3 | Runs make every spine walk quadratic, and two attributes could denote one value | **Accepted.** A canonical form, an iteration API, the walk rule, and every walker listed with its lane. | C7, U03, U04, U09, U10, U12, U13, U14, U19, U21 |
| R4 | Guards that fold only on constants kill `HeadOfCons` and the string folds | **Accepted.** Guards fold on today's `known*` predicates; `Crashes` stays; the rewrites see through `nonempty`; no folder reads an analysis. | C3.4, U04, coordinator (`Canonicalize.td`) |
| R5 | A guard on a string or a big passes a reference through, uncounted | **Accepted.** `nonzero` and `nonempty` take their operand over, and the result has its grade. | C2.1, U03 |
| R6 | The speculation rule does not tie the guard to the op's own string or array | **Accepted.** The guard's length is the op's own operand's length. | C3.3, U04 |
| R7 | An unknown lazy key is a regression in programs and a contradiction in the evaluator | **Accepted.** Slots follow arrays; an unknown key is `unsupported` from the pass, and leaves the round for runtime in the evaluator. | C5.1, C6.4, U09, U14 |
| R8 | `by_name` by the `io` bit catches linear arrays and `runST`, and diverges from Chez on CAFs | **Accepted.** `by_name` is "reaches an observable effect", and never for a static constant's label (O3). | C5.1, U09 |
| R9 | `memo-shared-stream` asserts the opposite of `by_name`; `environment-arguments` prints `argv[0]` | **Accepted.** The first observes the memo by time; the second prints `length !getArgs`. | C12, U23 |
| R10 | Deleting `IOOp` needs edits in `Term.Effect`, `Hook.IOCall` and an unowned `Hooks.idr`; array types are not in the registry's shape | **Accepted.** `Effect` carries `IdrPrim` and `List Ty` from the call; the hooks carry generated primitives; `Hooks.idr` joins U18. | C8.3, U07, U17, U18 |
| R11 | Environment and directory strings leak; `exitWith` is rejected; `OSClock` has no type entry; clock specs name no C function | **Accepted.** Runtime-owned string slots and `releaseHandles()`; `exitWith` by name; `OSClock` a `WordType`; clocks by `scheme:` spec. | C1.5, C9.1, C9.4, U16, U18 |
| R12 | Files the contracts change that no lane owns; memo label bodies dead to every solver; two units at their limit | **Accepted.** `Con.cc`, `Generated.cc`, `Canon`, `Hooks.idr`, `Attributes.idr`, `Sharing` and `T/toolchain` are assigned; `labels` on the memo sum keeps the bodies live; U09 splits as it edits (U10's `Layouts.cppm` is 348 lines since 1677b8cb). | `ownership.json`, C1.1 item 5, U09, U10 |
| R13 | `make check` is not build-free and is red mid-swarm; the `IDR/Simplify` change needs the patched MLIR | **Accepted.** Lanes run only their named spec test; U01's three C++ changes are held out until the rebuild. | C13, work-units, U01 |

**The smaller points**, all accepted:

- `idr.lambda` and `idr.delay` are `Pure`, as `idr.closure` and
  `idr.suspend` are (C1.1 item 4).
- The in-place promise is read from two ops: an `idr.reuse` whose token
  comes from an `idr.take` of the parameter. The message names the
  call, with a note at a dup, and no provenance is added (C10.2).
- Static memo cells can form a cycle, through persistent cells only
  (C10.1).
- C6.3 holds as written.

**The disagreements table.** The first two rows are the owner's: O6 and
O3 record the defaults and the alternatives. The last two were settled
by the review itself.

## Rulings at launch

HEAD had moved past ee4ce8e when the swarm launched: 62764e33 (there is
no oracle), 20fcfadb (the LLVM pin moves to llvm main 7208ba24, built
and tested on arm64 macOS only), 1677b8cb (four regressions of the
lazy-streams merge fixed), 08a065e4 (phase 1b: the Chez oracle out of
`tests/` and the docs) and ccc3e1dc (a clone of a loop breaker is a
breaker), the launch base. The coordinator re-diffed and re-read the
packet's paths and anchors at launch (Engagement contract): L1 to L48
from ee4ce8e to 1677b8cb, L49 to L54 from 1677b8cb to ccc3e1dc. L55 to
L63 settle the contradictions a review of the hubs, as the coordinator
applied them at dispatch, found between them and the contracts. Each
change made to the packet before dispatch is one row here, with its
reason.

| # | Change | Reason | Where |
|---|---|---|---|
| L1 | A test's committed expected files are its specification; no contract, dispatch or test compares with Idris's Chez backend or reasons from it | AGENTS.md and `findings/decision-no-oracle.md` (62764e33, phase 1b): there is no oracle | C0, C9.2, C12, U16, U22, U23, common obligations |
| L2 | The divergence class `gc-clock` is gone; the GC clocks give `Nothing` as the runtime's documented meaning | `tests/lib/chez-divergences` goes in phase 1b, and base makes both clocks optional (`isClockMandatory`) | C9.4, C12, O2, U16, U23 |
| L3 | C12's `program, Chez` rows are `program` rows, whose expected files U23 writes by hand and which hold on both targets | No backend is compared with; the files are the specification | C12, U23 |
| L4 | A static constant's label is still never `by_name`, on a reason that does not depend on Chez (restated in L30); O3's `trace` and veto are restated; F-lazy-8 gains a "Since" | Chez's `schDef` was the rule's only reason | C5.1, O3, the Elon pass, U09, F-lazy-8 |
| L5 | The oracle's fixture names join "Retired mechanisms" | So `validate.sh` refuses them in every dispatch | Retired mechanisms |
| L6 | The clock constructors are spelled `GCCPU` and `GCReal` | They are base's names (`System/Clock.idr`) | C9.4, C12, O2, U23 |
| L7 | The launch base replaces ee4ce8e in every comparison: sensitivity, crash messages, dumps, benchmarks, compile times | ee4ce8e's `foreign/idr` does not build on trunk MLIR, and the 23.1.2 toolchain is gone (20fcfadb) | Engagement contract, C12, Qualification, `work-units.md`, U05, U17, U22, U23 |
| L8 | The coordinator builds the launch base at orchestrator step 1 and keeps that build, with a bench record and compile times | After the rebuild, `tools/verify-pins.sh` refuses the new toolchain for a tree without U01's patch | `orchestrator.md` step 1, `work-units.md` Integration (between steps 4 and 5, L33), Qualification 3 |
| L9 | The suites qualify on arm64 macOS; x86_64 Linux is NotRun, with what waits for it named; a check whose `targets` excludes the host is NotRun | 20fcfadb built the pin on arm64 macOS only, and `.toolchain/llvm-musl` is not built at 7208ba24 | Qualification 1, `orchestrator.md` step 7, Targets, U16 |
| L10 | F-up-2 is done and the coordinator's; U01 loses `upstream/12-clang-module-predeclared-new`, its check and `Retarget.cppm` | 20fcfadb retired the bug: both paths are gone, and `Retarget.cppm` is plain | C11.1, F-up-2, `ownership.json` |
| L11 | F-up-1 is the coordinator's, NotRun until an x86_64 Linux toolchain exists at the pin; U01 loses `upstream/11-…`, its check and `Escape.cppm`, which keeps its workaround | The crash is the x86_64 Linux build's alone: it does not reproduce on the arm64 macOS host, so nothing of it can be reduced, patched or retired here | C11.1, F-up-1, U01, `ownership.json` |
| L12 | The dead-values fix is a bug directory of its own, `upstream/16-remove-dead-values-unchanged-call`, with its check, not a hunk in 06; the coordinator applies U01's sentences to 02's and 06's READMEs and tells their owner | 06's `llvm.patch` is a pending LLVM pull request that another agent sends, and its README calls the empty-set rebuild a separate matter | C1.8, C11.2, U01, `ownership.json`, `validate.sh` |
| L13 | The round runs `remove-dead-values{canonicalize=false}` | `idr-dead-values` runs it with its canonicalization off today, for the reason `DeadValues.cppm` gives | C11.2, U01 |
| L14 | R13 restated: all of U01's work and C1.2's `idr-dead-values` lines stay out of the tree until integration step 5; if the bug is ours, nothing does | A new `llvm.patch` makes `tools/verify-pins.sh`, and so `make build`, refuse today's toolchain; without the patch the loop's fingerprint never repeats; `Passes.td` keeps the pass while `DeadValues/Pass.cc` defines it | C1, C1.2, C13, `work-units.md` Integration 3 and 5 |
| L15 | U01 leaves the simplify loop as it is | 20fcfadb made it upstream's `composite-fixed-point-pass`, and `T/idr/obs/budget` and `obs/round-failure` pin it | C11.2, U01, U22 |
| L16 | Every format binds its inherent attributes (`cause`, `memo`, `labels`, `by_name`), and `idr.data` and `idr.ctor` stay always public | Trunk's ODS formats are strict, and 20fcfadb made both ops `Idr_PublicSymbol` | C1, C1.1 items 2 and 5, U09, U22 |
| L17 | Lane code calls `llvm::reportFatalInternalError` for an internal error | `Mlir.cppm` no longer exports `report_fatal_error` (20fcfadb) | C1.7 |
| L18 | `Layout/FindLabels.cc` goes with the label table, and U10's split of `Layouts.cppm` is no longer forced | 1677b8cb moved the constructor and its label walk there, and `Layouts.cppm` is 348 lines | C5.2, C7.2, U10, R12 |
| L19 | A walker reads a shared part of a constant once; `functionClosure` keeps its `seen` set and drops its `!idr.lazy` exception | 1677b8cb: `programs/eval/shared-result`'s 41 nodes have 2^41 paths; after C5.1 no suspension is a `#idr.closure` | C7.2, U10, U13 |
| L20 | `Canon/Feeds.cppm`'s two new rules stay, its force rule kept to `!idr.lazy` operands | 1677b8cb added them for an `if`'s branches and for static data a consumer reuses; a memo box's force reads its cell | C0, C3.4, C4.4, U04 |
| L21 | The JIT's table keeps `idris_rt_array_new` | 1677b8cb: a forced constant suspension reaches an array allocation at compile time | U14 |
| L22 | The tests new at 20fcfadb and 1677b8cb stay as they are | They test what the cutover keeps: the symbol form, the simplify budget, reuse in place | U22, U23 |
| L23 | `tests/properties` leaves U23's write set | No commit has it, so `validate.sh` failed on it | `ownership.json`, U23, the frontier, `work-units.md` |
| L24 | `findings.md`'s anchors in changed files are given at 1677b8cb, and F-own-4's at 7208ba24 | `Lowering.cppm`, `Layouts.cppm`, `IdrOps.td` and `RemoveDeadValues.cpp` moved; every claim still holds | `findings.md` |
| L25 | `review.md` keeps its anchors at ee4ce8e and its Chez readings, as F-lazy-8 keeps its own | They are the record of what was decided then | `review.md`, `findings.md` |
| L26 | `substrate.md` §4, §6, S2.5 and §1 row 18 are corrected at qualification | 20fcfadb adopted the composite pass and retired one clang crash; S2.5 reads `RemoveDeadValues.cpp:278` and "a public function only", where 7208ba24 has `:280-281` (F-own-4) | Qualification 5, `work-units.md` |
| L27 | U01 writes its work in the shared checkout. At integration step 3 the coordinator sets it aside in two stashes (`u01-rest`, then `u01-patch`); at step 5 it pops the patch, runs `make bootstrap`, pops the rest, writes C1.2's `idr-dead-values` lines and runs `make build` | "Held out" did not say how a group written in a shared checkout leaves it, and step 5 rebuilt before the patch was back. C1.2's lines stay unwritten until step 5: a stash takes whole files, and `Passes.td` carries the rest of C1 | C13, `work-units.md` Integration 3 and 5, U01, Toolchain, the frontier |
| L28 | Orchestrator step 1 aborts on a dirty owned path except `proposals/0002-representation-cutover/` | The packet's launch edits are committed at integration | `orchestrator.md` step 1 |
| L29 | U01's `mlir/test` case goes before `remove-dead-values.mlir`'s last split (`:899`) or in a file of its own, and tests the fingerprint as 02's `sccp.mlir` RUN line does | 06's test hunk appends at the file's end (`@@ -918,3 +918,100 @@`); a second hunk appending there has no trailing context and fails after 06 (checked with `git apply` on a copy of the file at 7208ba24) | C11.2, U01 |
| L30 | Ruling: a static constant's label stays never `by_name`, because a top-level constant names one value of the program, evaluated once, as Idris defines a top-level definition, so a `trace` in it observes that one evaluation. O3 gives two vetoes: (a) no static exception, so a static `by_name` cell holds its label and is never written (C5.1, C5.5, C12, U09, U12 change); (b) every force memoizes, where "the one-shot row" becomes C5.3's `by_name` row and the force's `Idr_IOResource` write | L4's reason restated the mechanism (written once), and the rule's first basis was Chez's `schDef` | C5.1, O3, the Elon pass, U09, F-lazy-8, L4 |
| L31 | F-own-4 and F-guard-5 cite 1b4549ba for the `substrate.md` corrections | 9ae7bf2a changed only `findings/README.md`; 1b4549ba corrected `substrate.md` S2.3 and S2.5 | `findings.md` |
| L32 | `substrate.md` S2.5 and §1 row 18 join L26's corrections | S2.5 cites `RemoveDeadValues.cpp:278` and "a public function only", 23.1.2's reading; 7208ba24 has `:280-281`: public, external, or with users outside the pass root. Row 18 counts two clang workarounds, and one remains (C11.1) | L26, Qualification 5, `work-units.md`, F-own-4 |
| L33 | The sensitivity runs and the compile-time comparison happen between integration steps 4 and 5, on today's toolchain: the kept `build/dev-darwin` swapped in, and the runner run directly with the kept compiler. Orchestrator step 1 runs `make test` at the launch base and copies `tests/build/timing`. The old Integration step 6 goes | After step 5 the kept build cannot run (`verify-pins.sh` refuses the rebuilt toolchain for it); the harness reads `$dev_prefix/foreign/idr` (`tests/lib/lit.sh`), and the compiler names `build/dev-darwin` (`Frontend/Paths.idr`); `tests/compile-times.sh --against` needs a record, which only a suite run writes | `orchestrator.md` steps 1 and 5, `work-units.md` Integration, C12, Qualification 2 and 3, L8 |
| L34 | U23 writes `guards-messages`' three uncovered causes from the launch base's source (`Strings.cc:59`, `IdrOps.td:960`, `Scalars.cc:39`) and the location in `semantics/crash-location`'s format, with no run | The lowering prints the op's `getCrashCause` text through `crashMessage`, and `tests/lib/e2e.sh` matches `expected-crash` as a fixed substring (`grep -qF`) | C12, U23 |
| L35 | U01 may build a scratch `mlir-opt` from its patched files against the static `libMLIR*.a` in `.toolchain/llvm-macos/lib`; the coordinator runs the patch's RUN line by hand at step 5 with the rebuilt `mlir-opt` and `FileCheck` | No suite runs `check-mlir`, and 06's README checked its patch that way; the libraries are installed (398 `libMLIR*.a`) | C13, U01, `work-units.md` Integration 5 |
| L36 | A change under 06 is recorded in 06's README as well as told to the owner | 06's README is the record of its pull request | C11.2, U01 |
| L37 | The coordinator fetches and rebases onto `origin/main` before pushing | Another agent pushes `upstream/README.md`, the `upstream/NN` READMEs and `PINS.md` | Commit policy, `orchestrator.md` step 6, `work-units.md` |
| L38 | U01's group, its `PINS.md` text, C1.2's `idr-dead-values` lines and 02's and 06's README sentences go in one commit | AGENTS.md: a patch's directory, its check, its `PINS.md` entry and the deletion of its workaround land in the same change | C1.8, Commit policy, `orchestrator.md` step 6, `work-units.md` |
| L39 | F-clo-7 cites `RegionUtils.h:69-72` at 7208ba24 | The declaration is at `:69-72` (at llvmorg-23.1.2 too); `:66-71` began inside its comment | `findings.md` |
| L40 | Orchestrator step 1 names the anchors phase 1b moves: `Lower/Buffers.cppm:33` to `:32`, and every `IdrOps.td` line after 1312 by one (`:1566`, `:1451-1463`) | Phase 1b's comment edits shift them, and the packet cites them at 1677b8cb | `orchestrator.md` step 1 (F-guard-2, F-own-2, F-guard-3, F-guard-6, U05) |
| L41 | The clock primitives have `scheme:`, `RefC:` and `javascript:` specs and no `C:` spec; U18 recognizes them by `scheme:` | Base's `System/Clock.idr:119-204` gives all three, and RefC's support is C | C9.4, U18 |
| L42 | C0 keeps `Feeds.cppm`'s force rule restricted to `!idr.lazy` operands, as C3.4 and U04 do; its box-constructor rule reads "never folded with constants into static data" | C0 said the rule stays as it is, and "folds with no constant" misread `:149-150`, which refuses the fold | C0, C3.4, C4.4, U04 |
| L43 | L24 no longer lists `Passes.td` as moved | It is unchanged from ee4ce8e to 1677b8cb; F-up-3's `:479-490` to `:479-489` is a range correction | L24 |
| L44 | The orchestrator's reading list marks `review.md`'s disagreements table as the record (L25), with README O3 the live text | Its Chez readings predate L1 and L30 | `orchestrator.md` |
| L45 | The common obligations' "only the one spec test" names U01's own check and reproducers | C13 allows them, and the shared text said otherwise | common obligations, Verification timing |
| L46 | `guards-messages` is six fixtures, one per cause | A program crashes once, so one fixture cannot state six crashes | C12, U23 |
| L47 | The bench record is on the same pin, not the same toolchain build | The integration rebuild adds U01's MLIR hunk after the record; it changes compilation, not the runtime the record times | Qualification 3 |
| L48 | C0's symbol form keeps `idr.force`, whose operand may also be a memo box | C5.1 makes the force take the box; C0 said every symbol-form op stays as it is | C0 |
| L49 | The anchors phase 1b moved are given at ccc3e1dc: F-own-2's `IdrOps.td:1566` is `:1567`; F-guard-3's and F-guard-6's `:1451-1463` are `:1451-1464`; F-guard-2's and U05's `Lower/Buffers.cppm:33` is `:32`. Orchestrator step 1 no longer lists them | 08a065e4's comment edits: `Idr_OsOp`'s comment gains a line (`IdrOps.td:1312`), and `Buffers.cppm`'s header loses one, as L40 said. The comment above `Idr_ArrayGetOp` starts at `:1451` at ccc3e1dc (at `:1450` at 1677b8cb, so the old range began a line late) | `findings.md`, U05, `orchestrator.md` step 1, L40 |
| L50 | The launch base is ccc3e1dc, recorded in the Engagement contract and orchestrator step 1; a HEAD past it is re-diffed from it and recorded instead | Phase 1b is committed (08a065e4) and ccc3e1dc followed it on `main`; this re-diff of every owned path from 1677b8cb to ccc3e1dc is L49 to L54 | Engagement contract, `orchestrator.md` step 1, `findings.md`, `contracts.md`, Validation |
| L51 | U21 keeps `CloneTable::settleBreaker` and the binding-time join for raised clones; `T/idr/specialize/breaker-clones`, the raised-clone case of `binding-times.mlir` and `programs/eval/latent-loop`, `latent-loop-delay` and `latent-loop-accumulator` join its acceptance | ccc3e1dc: a specialized or raised clone of a breaker keeps `no_inline` (`Specialization.cppm`, `Raise.cppm`, `Clones.cppm`), and a raised clone's binding times join its callee's (`BindingTimes.cppm`); without either, `idr-simplify` never ends on those fixtures. What U21 is given did not move: the walkers `KeyOf.cppm:29`, `Specialization.cppm:107`, `ShapeOf.cppm:43`, `UnrollSize.cppm:34` (review R3), and C2.4's one sentinel in `ShapeOf.cppm` | C2.4, C7.2, U21 |
| L52 | U22 and U23 keep ccc3e1dc's tests and the expected files phase 1b wrote where the oracle was, as they are; a transcript a lane writes keeps phase 1b's form | They test what the cutover keeps (the loop breakers, the symbol form in the simplify loop), and phase 1b's files are their tests' specification (C0) | C12, U22, U23 |
| L53 | C11.2 and U01 leave `IDR/Simplify/Breakers.cppm` as it is | ccc3e1dc rewrote its header: a clone carries its callee's `no_inline` from `idr-specialize`. The breakers end the loop U01 leaves as it is (L15). `Simplify/Pass.cc`, whose `:114-128`, `:134` and `:163-166` C13 cites, did not change | C11.2, U01 |
| L54 | Nothing else in the packet changes from 1677b8cb to ccc3e1dc | `IdrOps.td`'s other hunk (`Idr_ShiftOp`'s comment, `:723-728`) keeps its line count, so `:45`, `:78-83`, `:208-235`, `:317-335`, `:939`, `:960` and `:1281-1306` hold; `idris_rt.h` loses a line after `:261`, below every cited anchor; `Registry.idr` and `Registry/Primitives.idr` change comments line for line (`:256`, `:90-298` hold); the `findings/` documents drop Chez as the oracle, and the sections cited (`concurrency.md` §2.3 to §2.5, `findings/README.md` decisions 3 and 6, open question 3, W1 to W10) keep their numbers and claims; `tests/lib/e2e.sh` still checks `expected-crash` with `grep -qF`; tracked `tests/` names no retired mechanism but `rc.c`'s `IDRIS_RT_KIND_CLOSURE`, which U23 renames | — |
| L55 | `#idr.con`'s storage is generated by ODS from `(ctor, ArrayRefParameter<"::mlir::ArrayAttr">:$cells, OptionalParameter<"::mlir::Attribute">:$tail, unsigned:$spine)` and the self type. A plain con is one cell of all its fields, with a null tail and spine 0; a run is its `n >= 2` cells without the spine field, its tail and its spine. `get(ctx, ctor, fields)` (an `AttrBuilder`) and `getRun` are U19's, through `Base::get` on canonical parameters; `isRun`, `getRunLength` and `getRunCells`, a thin alias of the generated `getCells` that keeps its meaning (empty for a plain con), are inline in the hub. Walk and replace are the generated ones: a replace can make a non-canonical run, which the verifier rejects; U19 checks the 10^4-cell round trip. `Idr.h` declares no storage | With the storage written by hand (`genStorageClass = 0`), registering `#idr.con` in `IDR/Dialect/Dialect/Initialize.cc`, U03's, needs U19's storage complete there; a generated storage is complete wherever `IdrAttrs.cc.inc` is, as every other attribute's. A plain con with a free spine would give one value two storages. Checked: trunk tblgen generates it, and a scratch unit that includes `IdrAttrs.cc.inc` as `Initialize.cc` does registers it | C1.1 item 6, C1.4, C7.1, C7.2, U03, U19, `IdrOps.td`, `Idr.h` |
| L56 | `consumedEffects` is called by `Con.cc`'s `getEffects` alone. `lin.enter`, `lin.use`, `dest.write`, `take`, `reuse` and `drop`, whose effects ODS generates, and the array ops, whose `getEffects` stay their own, get `Idr_Consumes` (the trait and the interface) and nothing else; U03 and U04 no longer call it from `Lin.cc`, `Dest.cc`, `IDR/Ownership/Ops.cc` or `Arrays.cc` | C2.1 says "today's ODS effects, unchanged" for them and review R2 says why: those files have no `getEffects` to extend, and an op that reports effects is impure anyway | C2.1, U03, U04 |
| L57 | `getSpeculatability` is on exactly the six pure total ops the hub makes `NoMemoryEffect` and `ConditionallySpeculatable`: `idr.div`, `idr.mod`, `idr.to_byte`, `idr.to_int`, `idr.str.index` and `idr.str.head`. The allocating ones (`idr.str.tail`, `idr.big.div`, `idr.big.mod`, `idr.big.from_double`) and the IO, buffer and array ones keep their effects and declare none, and C3.3's length rule is the string's alone | ODS declares the method on no other total op, and one that allocates or does IO was never speculatable | C1.1 item 3, C3.3, U04 |
| L58 | `idr.array.new`, `idr.array.generate` and `idr.array.fold` lose the crash interface with their class, `Idr_ArrayOp`, and nothing changes; U04 deletes their `getCrashCause` with `get`'s and `set`'s | At ccc3e1dc none of the three had `Idr_MayCrash` or a cause: each `getCrashCause` returned nothing (`Arrays.cc:54`, `:157-158`), a negative size is an empty array, the lowering checks only `get` and `set` (`Lower/Arrays.cppm:155`), and the interface's one generic reader (`Facts/Infer.cppm:51`) reads only the cause | C1.1 item 3, U04 |
| L59 | One primitive set: an op that is an `IdrPrim` constructor is never also a `Prim` constructor. `NatToBig`, `NatFromBig` and `StrBuild` leave `Prim` for `Op NatToBig`, `Op NatFromBig`, `Op StrPack` and `Op StrConcat` (by C8.1's rule: attribute-free, emitted one-to-one for `natToInteger`, `integerToNat`, `fastPack`, `fastConcat`), and `Builder` goes, `Hook.Builds` carrying the `IdrPrim`. `Prim` keeps the `arith` and `math` constructors, `ArrayLength` and the ops with an inherent attribute. U17's world convention: an op with `Idr_PerformsIO` takes the world as its last operand, except `world.new`, which makes one and takes none. `big.small` and `big.pred` lose `Idr_Primitive`, as the hub applied it (accepted): no guard checks their preconditions, so no primitive may build them | C8.1 made the four ops primitives while C8.3 kept them in `Prim`, two names for one op; `Builder` named two ops a second time. `world.new` is the only `Idr_PerformsIO` op without a world operand (checked over every op of the hub) | C8.1, C8.2, C8.3, U07, U17, U18 |
| L60 | C1's text follows the hubs as applied: `Idr_CheckOp`'s `using ::idr::MayCrash<false>::Impl<ConcreteOpType>::getEffects;`; `idr::Primitive` in `Idr.h`; `const idris_rt_str *` for every string of `idris_rt.h`'s new declarations, to which U16 defines its functions; `idris_rt_io_exit` `IDRIS_RT_NORETURN`; `dir_current`'s string the program's, in C9.1's ownership list and the hub's comments | Where the applied hubs differed from C1's text: a guard that consumes inherits two `getEffects`; `Idr_Primitive` names a C++ trait; the header's existing string functions take `const idris_rt_str *`; `exit` does not return; base's `currentDir` frees the path (`System/Directory.idr:82-89`) | C1.1 items 2 and 7, C1.4, C1.5, C9.1, C9.2, U16, `idris_rt.h`, `IdrPlatformOps.td` |
| L61 | U19 reads `INC/IdrOps.td:204-264` (`Idr_Attr` and `Idr_ConAttr` as applied). U23 reads its three uncovered causes at the launch base, with `git show ccc3e1dc:<path>`, `IdrOps.td:960`'s line quoted inline | The hub moved `ConAttr` and deleted `Idr_StrHeadOp`'s cause, and U04 deletes the other two during the swarm | U19, U23 |
| L62 | Orchestrator step 1's ordering is satisfied: after a green `make test` at ccc3e1dc, and before the hubs were applied, the launch base's `build/dev-darwin`, `compiler/build/exec` and `tests/build/timing` were kept in the session scratchpad's `launch-base`. The launch base's bench record is made at integration with that build swapped in, as the sensitivity runs are | The hubs were applied right after the build was kept, so no bench record was made at step 1 | `orchestrator.md` step 1, `work-units.md` Integration, Qualification 3 |
| L63 | `idr.yield` declares `getSuccessorRegions`, and U08 defines it in `IDR/Dialect/Ops/Regions.cc`: no successor when the parent is an `idr.lambda` or an `idr.delay`, the parent's otherwise. The region ops' verifiers and `idr-isolate` read the body's terminator directly, never through the region-branch interfaces | The interface's default casts the yield's parent to `RegionBranchOpInterface`, which a lambda and a delay are not: their bodies run when the closure is applied or the suspension forced | C1.1 item 4, C4.3, U08, `IdrOps.td` |
| L64 | `ArrayOp` goes, as `Builder` does; the registry's `ArrayCall` and `Hook.ArrayCall` carry the `IdrPrim` | It named `array.new`, `array.get` and `array.set`, which are primitives, a second time | C8.3, U17, U18 |

## Rulings on the swarm

Contract conflicts a lane reported while the 23 ran. The coordinator
fixed each in `contracts.md` and re-dispatched the affected lane; each
is one row here.

| # | Change | Reason | Where |
|---|---|---|---|
| S1 | U16 writes U15's crash entry and the end of `idris_rt_main_return` in `RT/Io/Ending.cppm`: `idris_rt_crash` calls `idris_rt_eval_crash` first when `rt::alloc::arenaActive`, and `idris_rt_release_persistent` is neither declared nor called | Both functions live in `RT/Io`, which is U16's and excluded for U15; U15 deleted the kept list the call walked | C6.5, U15, U16 |
| S2 | `idris_rt_buffer_at` computes only the address; `check.range` is the one range test, and its crash ends `at <file>:<line>:<column>` after the unchanged cause, as every guard's does | U05 found the runtime tested buffer ranges itself, against C3.1's "as they do today": a second test is a second home for one condition, and it survives a guard `idr-in-bounds` proves away | C3.1, U05, U16, U22 |
| S3 | Layout keeps `!idr.fn` as one counted pointer | An `!idr.fn` that defunctionalization never reaches stays a value of the program (C2.4) and reaches `idr-stack`, `idr-rc` and the lowering; U10's Delete list names only the cases that served closures alone | C2.4, U10 |
| S4 | `in-bounds=@f` keeps "and `@f` has an array access"; the `ub.poison` reads in `IDR/InBounds/{Returned,Components,Lengths}.cppm` stay | U06 dropped the first half with the access ops, so a test whose access was simplified away would pass with nothing checked. U06 found the five reads read the program's poison, which C2.4 leaves alone, and deleting them weakens proofs `T/idr/in-bounds/records.mlir` needs | C2.4, C3.5, U06, `Passes.td` |
| S5 | C2.4's table counts sites to examine, not sentinels to delete; an IR operand a terminator needs where control never arrives is the program's | U13 found its six (`Lowering`, `Facts`, `TailPosition`, `Matches`, `Loops`) all read or build the program's poison, as U06 found its five: the legality of `ub.poison`, the poison `remove-dead-values` passes, an `insertvalue` base, and a yield after a crash that does not return | C2.4, U06, U13, and every lane with a row |
| S6 | U07 also writes `CS/Emit.idr`, `CS/Frontend/Translate/State.idr` and `CS/Frontend/Translate/Cases.idr` (`ownership.json`) | No lane owned them, and closure conversion's remains are there: `Emit.idr` collects and comments on lifted functions, `State.idr` hands out the labels `Ids.idr` declares, and `Cases.idr` keeps the `Ord a` constraints and the "every label stays unique" comment only closure conversion needed | U07, `ownership.json` |
| S7 | The guards' `CheckKind`, `checkHolds` and `checkSpeculatability` are declared in `Idr.h` beside `knownNonZero` and exported by `Dialect.cppm`; U04's `Ops/Checks.cppm` goes. U04 also writes `IDR/Dialect/Ops/Field.cc`; the coordinator registers the `HeadOfChecked*` patterns in `IDR/Dialect/Canonicalize/Strings.cc` | `Idr.h` is where the dialect's plain units declare what they define in the global module; an `export extern "C++"` partition would be a second way to do it. `Field.cc`'s folder read `getFields()[index]`, O(n) on a run (C7.2), and no lane owned it; nor did the unit that registers `Canonicalize.td`'s patterns | C1.4, C3.3, C3.4, C7.2, U04, `ownership.json` |
| S8 | `Idr_ConAttr` declares the private `getStored` and `getStoredChecked`, defined by `extraClassDefinition` | `Base::get` needs the complete storage, which ODS emits only in `Initialize.cc` through `IdrAttrs.cc.inc`, so `ConAttr.cc`'s builders reach it through functions emitted beside it (U19) | C1.1 item 6, C7.2, U19, `IdrOps.td` |
| S9 | `idr::memoRunning` and `idr::memoForced` in `Idr.h`, exported by `Dialect.cppm`, name a memo sum's two states; every pass that builds or reads them uses them | Five units in four lanes (U09, U11, U13, U14) spelled `"running"` and `"forced"` themselves | C1.4, C5.1, U09, U11, U13, U14 |
| S10 | C9.2 states the meanings U16 had to choose: a failed `file_read_line`, `file_read_chars` as bytes, an exit status outside 0 to 255 as a crash (U15 exports the check that main's return already uses), every byte of `file_write_line`, closing a standard handle, a failing close, and `dir_entry`'s errno | The C support function, base's documentation and POSIX left each open, or Linux's and macOS's C libraries disagree; the runtime gives one answer on both targets, and an exit status's low 8 bits would make `ExitFailure 256` a success | C9.2, U15, U16, U23 |
| S11 | `Hook.IOCall` carries the literal operands a call does not supply (`prim__newBuffer`'s zero byte); an `IOCall` of a pure primitive is a `PrimApp`; an array primitive's element comes from its `ArrayT`; U07 translates `exitWith`'s body with its `believe_me` as a non-returning action, and takes an identity hook's argument by its type; U18 also writes `Frontend/Profile.idr`; `prim__fPoll` is `file_poll` by its name | U18 found these between its hooks and U07's translation: `array.new` takes a fill `newBuffer` does not pass, `HandleIsNull` and `HandleString` take no world, `getBits8`'s byte type is its buffer's, `castPtr` and `forgetPtr` are point-free, and `Profile.idr`, which no lane owned, would reject every program that reads its environment as reaching `believe_me`. Base binds `fPoll` to `idris2_fileSize`, so its spec cannot tell it from `fileSize` | C8.3, C9.1, C9.2, U07, U18, `ownership.json` |
| S12 | `Idr_BodyRegion<n>` in `IdrOps.td` states a region primitive's body arity (1 for `array.generate`, 3 for `array.fold`), which the generated verifier checks and `idris-mlir-tblgen` reads for `regionArity`; `Arrays.cc` drops its own count checks | ODS said nothing of a body's arguments, so `regionArity` could not be generated from it (U17), and a count kept in C++ would be a second copy | C8.2, U04, U17, `IdrOps.td` |
| S13 | `guards-messages-byte` is a lit test of U22's (`idr/guards/byte-message`), not a program; the coordinator documents U23's `demand-in-place` mark in `tests/testutils.sh`; `prelude.sh` counts a hook whose translation leaves no call (an identity, a literal handle) as used by the call the program makes | No Idris primitive emits `idr.to_byte` (its one source, `setByte`, is refused as deprecated), so no program can reach the byte guard; `testutils.sh`, which lists the marks, had no owner; Core cannot name `prim__castPtr`, `prim__forgetPtr` or `prim__getNullAnyPtr`, whose translation is their argument or a literal | C12, U22, U23, `ownership.json` |
| S14 | The contract follows what the lanes found the code needs: `guardOf` returns a list; an empty lazy key becomes a memo sum with no label; `by_name` also ignores `idr.world.new` and `idr.io.strerror`; `useOf` reads a force's grade (C5.4), and before `idr-rc` grades signatures `WhereDies` states that every call consumes | `buffer_copy` takes two guards; a key the analysis never reaches would otherwise leave an `!idr.lazy`; forging a world is no effect, and `strerror` reads only the runtime's text; the force is the one owned use `consumes` does not name, and a call's consumption before grading is read from the callee's parameter once it is graded | C2.1, C3.1, C5.1, C5.4, C8.3, U03, U09, U17 |
| S15 | A runtime argument whose head is a call and which mentions no runtime value gives the shape of what it reduces to, when the rest of the type cannot reduce without it; U18 writes `Frontend/Translate/Instances.idr` | Base's `clockTime` passes its with block `isClockMandatory clockType`, a closed pure call Idris itself reduced when it checked the type; read only as written it gives no shape, the result type stays stuck and `MkIO` is refused as a dependent field. No lane owned the file | C9.4, C12, U18, `ownership.json` |
| S16 | `ForceOfOneConstant` does not fire when the function holding the force may run while the label does (the label refers to it, through the functions it names); the relation is the one the loop breakers walk, shared from `idr.graph` (U09 writes `IDR/Graph`). A top-level constant forced in a loop is still recomputed by the call: an open owner decision, reported | A constant suspension is one static memo cell (C5.5). In a knot sccp gives the label its own constant, the rewrite makes the force a call of itself, and the program spins where the cell's `running` state would crash (`self-forcing-caf`). Retiring the pattern would send every constant-capture `if` branch through a memo cell; narrowing it keeps C4.4 for every force that cannot meet itself | C0, C4.4, C5.1 (O3), C5.5, U09, U22 |
| S17 | A constructor's or closure's folder builds a constant only of fields `idr.constant` or `arith.constant` can hold (`canon::buildable`), never of `#ub.poison`; U04 writes `IDR/Dialect/Canonicalize/Con.cc` and `IDR/Dialect/Ops/Closure.cc`, U09 `SuspendOp::fold` | `idr-defunctionalize` replaces an apply no label reaches with the program's poison (C2.4); folding it into `#idr.con<..., [#ub.poison]>` made a constant the dialect's own verifier rejects, which `StaticData` then cast as a con. No lane owned the two folders | C2.4, C7, U04, U09, `ownership.json` |
| S18 | Freeing keeps an array's tag, its element size, while the array is on the dying list: the next cell's high address bits go in the top of its length, which is below 2^45 for an array whose elements hold objects. `idris_rt.h` says freeing reads an array's tag and length too | The dying list overwrote the tag, so freeing an array of counted elements stepped by 0 and leaked all but one, or by an address's bits and read garbage. Latent at the launch base, where no test freed such an array; U23's `array-of-arrays` and `lazy-elements` are the first | C1.5, C5.6, U15, U23 |

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
- **O2. The GC clocks are invalid** (C9.4).
  - Default: yes. `clock_gc_cpu` and `clock_gc_real` always give the
    invalid clock, so `clockTime GCCPU` and `clockTime GCReal` give
    `Nothing`, which is the runtime's documented meaning. No test class
    goes with it.
  - On a veto: the GC clocks are `unsupported (process)`-style
    exclusions under a new rule, which the owner names.
- **O3. Memo per thunk** (`findings/README.md` proposed decision 3, as
  C5 implements it).
  - Default: yes. A label is `by_name` when its function reaches an
    `Idr_PerformsIO` op other than an array or buffer op (output, input,
    a file, a clock), and never when a static constant names it (C5.1).
    `trace` in a thunk runs at every force, where its value is demanded;
    `Linear.Array`, `runST` and `strerror` keep their memo. A static
    constant's label memoizes because a top-level constant names one
    value of the program, evaluated once, as Idris defines a top-level
    definition: a `trace` in it observes that one evaluation.
  - On a veto, the owner names one of two alternatives:
    - (a) No static exception. A static constant's label is `by_name`
      by the same rule as any other label, so a `trace` in a top-level
      constant runs at every force. A static `by_name` cell holds its
      label and is never written: C5.1 and U09 drop the exception, and
      C5.5 and U12 lower such a cell to a `constant` global, outside
      `@__idr_release_cafs`; C12's `idr/defunc/memo-*` row loses its
      static case.
    - (b) Every force memoizes, as today, so an effect inside a thunk
      happens at its first force only, short of AGENTS.md's rule that a
      trusted library's effect happens where its value is demanded. The
      `by_name` attribute, C5.3's `by_name` row and the force's
      `Idr_IOResource` write go.
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
- **O6. Views stay plain; the owned stage is derived** (C2.2, review
  R1).
  - Default: yes. `ownership::inOwnedStage(ModuleOp)` is true when any
    value has `own` or `excl`. `idr.stage` goes, and no ODS constraint
    changes.
  - On a veto ("views are `borrow`"): C1.1 changes every operand
    constraint that takes a view (31 declarations), a graded-array
    length op replaces `memref.dim`, `fieldType` and `view` split into
    declared and view, and `Con.cc`, `Field.cc`, `Matches.cc` and
    `Tag.cc` join U03. That is a sweep of its own, and it would be a
    packet of its own.

## The frontier: 23 lanes, disjoint writes, all start at dispatch

| Lane | Outcome | Exclusive writes | Consumes |
|---|---|---|---|
| U01 | The calls `remove-dead-values` rebuilds fixed by a patch of their own; `idr-dead-values` deleted; written in the shared checkout, set aside at integration until the rebuild | `upstream/16-remove-dead-values-unchanged-call`, `T/upstream/remove-dead-values-unchanged-call`, `IDR/Simplify` | C11.2, C13 |
| U02 | The cycle check; the linearity verifier's sentinel; `idr-canonicalize` on upstream's pass | `IDR/Verify`, `IDR/Canonicalize` | C10.1, C2.4, C1.6 |
| U03 | Consumption declared and derived; the owned stage derived (O6); one holds-references; `idr.stage` gone; the force's and the guards' grades | `IDR/Ownership`, `IDR/Facts`, `IDR/Dialect/{Grades,Types,Effects,Verify}`, `IDR/Dialect/Dialect/Initialize.cc`, `IDR/Dialect/Ops/{Lin,Dest,Con}.cc` | C1.1 item 1, C1.4, C2, C5.4, C7.2 |
| U04 | Guards' folders and speculation; the total ops lose their causes; rewrites see through guards | `IDR/Dialect/Ops/{Check,Scalars,Strings,Bigs,Arrays,Buffer,Bytes,Crash,Generated}.cc`, `IDR/Dialect/Crashes`, `IDR/Fold`, `IDR/Ops`, `IDR/Canon` | C1.1 items 2 and 3, C3.1 to C3.4, C7.2 |
| U05 | The guards' lowering; no check in the total ops' lowering | `IDR/Lower/{Checks,Scalars,Strings,Bigs,Arrays,Buffers,Words,RuntimeCalls}.cppm` | C3.6 |
| U06 | `idr-in-bounds` erases the guards it proves; `in-bounds=`, `no-guards=` | `IDR/InBounds`, `IDR/Expect` | C3.5, C2.4 |
| U07 | The Idris side writes `idr.lambda`, `idr.delay` and `Region`; closure conversion leaves Idris; `Term.Effect` over `IdrPrim` | `CS/Term.idr`, `CS/Ids.idr`, `CS/Emit/{Bodies,Declarations,Monad,Attributes}.idr`, `CS/Frontend/Translate/{Terms,Closed}.idr` | C4.1, C4.2, C8.2, C8.3 |
| U08 | `idr-isolate`; the region ops' verifiers | `IDR/Isolate`, `IDR/Dialect/Ops/Regions.cc` | C1.1 item 4, C4.3 |
| U09 | Lazy keys become memo sums; arrays in Slots; `by_name`; unknown keys `unsupported` | `IDR/Defunctionalize`, `IDR/Dialect/Ops/{Lazy,Data}.cc` | C1.1 item 5, C5.1, C7.2 |
| U10 | Layout without labels or code; memo cells sized once | `IDR/Layout` | C5.2, C2.3 |
| U11 | `Runtime` without a mode or closures; the force's lowering | `IDR/Lower/{Runtime,Closures,Cells,BuildBox,Fields}.cppm` | C5.3, C6.1 |
| U12 | Static memo cells marked by kind, `@__idr_release_cafs`, runs lowered by a loop | `IDR/Lower/StaticData.cppm` | C5.5, C7.2 |
| U13 | `lowerModule` with no flag; `idr-entry`; `idr-meter`; the Lower partition list | `IDR/Lower/{Lowering,Counting,StackCell,Facts,Matches,Loops,TailPosition,Lower,Patterns}.cppm`, `IDR/Lower/Pass.cc`, `IDR/Lower/CMakeLists.txt`, `IDR/Lower/{Entry,Meter}{.cppm,/}` | C6.1 to C6.3, C1.5 |
| U14 | The evaluator runs the program's pipeline; reify of sums and runs; no code table | `IDR/Eval` | C1.3, C5.7, C6.4, C7.2 |
| U15 | One crash entry; `argc`/`argv`; no closure kind; `idris_rt_caf_release` | `RT/{Rc,Start,Eval,Alloc}` | C1.5, C5.6, C6.5 |
| U16 | Base's surface in the runtime; handles; both targets | `RT/Platform`, `RT/Io`, `RT/CMakeLists.txt` | C9 |
| U17 | Generated `IdrPrim`/`IdrRegionPrim`; `Prim` reduced; `IOOp` gone; guards emitted | `CS/Types.idr`, `CS/Emit/Operations.idr`, `CS/Frontend/Translate/Primitives.idr`, `foreign/idr/tools/idris-mlir-tblgen.cc` | C8, C3.2 |
| U18 | Base's surface registered; pointers as handles; hooks over `IdrPrim`; `exitWith` and `OSClock`; `signal`, `threads`, `process` by name | `CS/Registry`, `CS/Registry.idr`, `CS/Frontend/Translate/{Types,Hooks}.idr` | C9.1, C9.2, C9.4, C9.5, C8.3, C8.4 |
| U19 | `#idr.con` runs in canonical form, and their API | `IDR/Dialect/Attrs`, `IDR/Sharing` | C7 |
| U20 | `idr-demand` and `--demand in-place` | `IDR/Demand`, `IDR/Driver/{Options,Run}.cppm`, `CS/Frontend/Main.idr` | C10.2, C1.3 |
| U21 | Narrow, Tail and Specialize without sentinels, on the derived stage, by the walk rule | `IDR/Narrow`, `IDR/Tail`, `IDR/Specialize` | C2.2, C2.4, C7.2 |
| U22 | The dialect suite's discriminators; retired mechanisms out of `tests/idr` | `T/idr` | C12 |
| U23 | The program suites' discriminators and rejections, against committed expected files; the runtime's C clients | `T/{programs,accept,reject,lib,registry,compiler,toolchain}`, `T/Main.idr` | C12, C1.5 |
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
| F-lazy-8 | `by_name` for observable effects, never for a static constant's label (O3) | U09 |
| F-lazy-9 | one size per memo sum | U10 |
| F-own-1 | consumption in ODS; `useOf` derived | U03 |
| F-own-2 | the stage derived from the grades (O6); `idr.stage` deleted | U03 |
| F-own-3 | `idr::holdsReferences` | U03 |
| F-own-4 | refuted (`RemoveDeadValues.cpp:280-281` at 7208ba24) | coordinator |
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
| F-up-1 | deferred: it crashes only the x86_64 Linux build, which has no toolchain at the pin yet; `Escape.cppm` keeps its workaround (C11.1); NotRun at qualification | coordinator |
| F-up-2 | done by the pin move (20fcfadb): `Retarget.cppm` is plain; rechecked on x86_64 Linux when its toolchain is rebuilt at the pin (C11.1) | coordinator |
| F-up-3 | a patch of its own, `upstream/16-remove-dead-values-unchanged-call`; `idr-dead-values` deleted (C11.2) | U01 |
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
- retired: chez-divergences
- retired: chez_agrees
- retired: oracle-chez
- retired: no-chez
- retired: chez-differs
- retired: Oracle.idr

## Qualification

The coordinator does this after integration.

1. **The suites.** All are green on both targets: `make check`,
   `make build`, `make test`, `make test-idr` and `make test-mlir-tools`,
   with the toolchain the one recipe builds at the pin (proposal 0003). A
   target that has not run them is NotRun, never green. A check whose
   `targets` excludes the host is NotRun there, not passed; after the
   toolchain sweep the only such checks are a target's own codegen and
   operating-system tests. This covers U16's Linux branches (C9.6), F-up-1
   (C11.1: its check now runs on every target) and the retirements of
   `clang-module-predeclared-new` and `llvm-cxx17-headers`.
2. **Sensitivity.** Each C12 discriminator fails at the launch base
   (Engagement contract), with the same test files and this tree's
   harness, which compares with no other backend, run once: between
   integration steps 4 and 5, on today's toolchain, against the build
   kept at orchestrator step 1 (`work-units.md` "Integration"). Each
   row's result is recorded.
3. **Measurements the packet owes:**
   - `bench/run.sh` against a record the coordinator makes at the launch
     base, with the build kept at orchestrator step 1 swapped in between
     integration steps 4 and 5 (L62), on the same Mac and LLVM pin (the
     integration rebuild adds only
     U01's `remove-dead-values` hunk, which the record's programs reach
     only at compile time; the last darwin-arm64 record,
     `bench/runs/2026-10-07-f5a4dff9-darwin-arm64`, predates the pin): no
     program slower beyond the run-to-run spread, compared by each run's
     ratio to its own C (`bench/README.md`);
   - compile times within 10% (`T/compile-times.sh --against` the launch
     base's `tests/build/timing`, copied at orchestrator step 1, on the
     one integration step 4's `make test` wrote, both on today's
     toolchain, `work-units.md` "Integration");
   - peak live cells of `thunk-consumes-list` before and after;
   - the size of `compiler/src` and `foreign/idr/lib` in lines before
     and after.
4. **`tests/upstream-idris/run`.** Run it, and record in
   `findings/upstream-idris/results` the tests that now pass (the file,
   directory, clock and environment tests).
5. **Docs.**
   - `findings/substrate.md` S1.2, S2.3, S2.4 and S2.5, and
     `concurrency.md` §2.3, were corrected when this packet was written
     (1b4549ba).
   - These went stale with 20fcfadb, and the coordinator corrects them
     from C11 and F-own-4:
     - `findings/substrate.md` §4 ("`composite-fixed-point-pass` stays
       rejected for the simplify loop");
     - §6 (the two clang crashes, and where `idr-dead-values`'s fix
       belongs);
     - S2.5, which says `remove-dead-values` keeps the parameters of "a
       public function only" (`RemoveDeadValues.cpp:278`, 23.1.2's): at
       7208ba24 it keeps them for a public or external function, or one
       with users outside the pass root (`:280-281`);
     - §1 row 18, which counts two clang-module workarounds: one went
       with the pin, and `clang-module-layout-forward-declaration`'s
       remains (C11.1).
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

`sh proposals/0002-representation-cutover/validate.sh`, rerun at launch
on 1677b8cb with "Rulings at launch" applied (at 1677b8cb the packet as
authored failed three times: two paths of bug 12, which 20fcfadb
retired, and `tests/properties`, which no commit has), again on
ccc3e1dc, the launch base, with L49 to L54 applied and the dispatches
reassembled, and again with the hubs applied and L55 to L63 in, the
dispatches reassembled:

```json
{
  "documents": 54,
  "links": 8,
  "findings": 59,
  "mapped": 59,
  "lanes": 23,
  "dispatches": 23,
  "writers": 24,
  "retiredMechanisms": 26,
  "failures": 0
}
```

The validator was checked for sensitivity on a scratch copy. Each
perturbation below fails it with the named check:

- a write set given to two lanes (a write intersection, and an owned
  path the dispatch does not name);
- a finding moved to another owner in the map (an owner mismatch);
- a retired name and a "wait for U09" put into a lane's prose;
- a lost binding rule;
- a broken link.
