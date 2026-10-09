# Work units

There are 23 lanes, plus the coordinator's own work. Each lane's full
dispatch is `dispatch/U??-*.md`. This file is the index and the
coordinator's checklist. The roots are as in `ownership.json`:

- `IDR` is `foreign/idr/lib`;
- `INC` is `foreign/idr/include/idr`;
- `RT` is `runtime`;
- `CS` is `compiler/src/IdrisMLIR`;
- `T` is `tests`.

| Unit | Outcome | Writes | Mandatory findings |
|---|---|---|---|
| U01 | A patch of its own for the calls `remove-dead-values` rebuilds; `idr-dead-values` deleted; written in the shared checkout, set aside at integration until the rebuild (C13) | `upstream/16-remove-dead-values-unchanged-call`, `T/upstream/remove-dead-values-unchanged-call`, `IDR/Simplify` | F-up-3 |
| U02 | The cycle check (C10.1); the linearity verifier's sentinel; `idr-canonicalize` on upstream's constructor | `IDR/Verify`, `IDR/Canonicalize` | F-prom-1, F-own-5, F-poison-7 |
| U03 | Consumption in ODS; `consumes` and `consumedEffects`; the stage derived (`inOwnedStage`); `idr.stage` gone; `holdsReferences`; the force's and the guards' grades; the walk rule | `IDR/{Ownership,Facts}`, `IDR/Dialect/{Grades,Types,Effects,Verify}`, `IDR/Dialect/Dialect/Initialize.cc`, `IDR/Dialect/Ops/{Lin,Dest,Con}.cc` | F-own-1..3, F-poison-5 |
| U04 | The guards' folders (on the `known*` predicates), speculation and `checkHolds`; total ops without causes; creators build guards; rewrites see through `nonempty`; constants by the walk rule | `IDR/Dialect/Ops/{Check,Scalars,Strings,Bigs,Arrays,Buffer,Bytes,Crash,Generated}.cc`, `IDR/Dialect/Crashes`, `IDR/Fold`, `IDR/Ops`, `IDR/Canon` | F-guard-1, F-guard-6 |
| U05 | `idr.lower:checks`; no check in the total ops' lowering | `IDR/Lower/{Checks,Scalars,Strings,Bigs,Arrays,Buffers,Words,RuntimeCalls}.cppm` | F-guard-2 |
| U06 | `idr-in-bounds` erases proved guards; `in-bounds=` restated; `no-guards=` | `IDR/InBounds`, `IDR/Expect` | F-guard-3, F-poison-6 |
| U07 | `Lam`, `Suspend` and `Region` as regions; Emit writes `idr.lambda`, `idr.delay` and region primitives; `Term.Effect` over `IdrPrim` | `CS/{Term,Ids}.idr`, `CS/Emit/{Bodies,Declarations,Monad,Attributes}.idr`, `CS/Frontend/Translate/{Terms,Closed}.idr` | F-clo-6, F-prim-2 |
| U08 | `idr-isolate`; the region ops' verifiers | `IDR/Isolate`, `IDR/Dialect/Ops/Regions.cc` | F-clo-7 |
| U09 | Lazy keys become memo sums with `labels`; arrays in Slots; `by_name`; unknown keys `unsupported`; `isMemo`; the force's verifier and effects | `IDR/Defunctionalize`, `IDR/Dialect/Ops/{Lazy,Data}.cc` | F-lazy-6, F-lazy-8, F-poison-8 |
| U10 | Memo cells sized once, with the thunk kind; labels and code gone from Layout | `IDR/Layout` | F-clo-4, F-lazy-9 |
| U11 | `Runtime` with no mode or closures; the force as a switch on the tag; `Runtime::finish` | `IDR/Lower/{Runtime,Closures,Cells,BuildBox,Fields}.cppm` | F-mode-2, F-clo-1, F-lazy-1..3, F-lazy-7, F-poison-3 |
| U12 | Static memo cells marked by kind; `@__idr_release_cafs`; runs lowered by a loop | `IDR/Lower/StaticData.cppm` | F-lazy-4, F-poison-4, F-const-3 |
| U13 | `lowerModule(ModuleOp)`; `idr-entry`; `idr-meter`; the Lower partitions and lists | `IDR/Lower/{Lowering,Counting,StackCell,Facts,Matches,Loops,TailPosition,Lower,Patterns}.cppm`, `IDR/Lower/Pass.cc`, `IDR/Lower/CMakeLists.txt`, `IDR/Lower/{Entry,Meter}.cppm`, `IDR/Lower/{Entry,Meter}/` | F-mode-1, F-mode-4..6, F-poison-2 |
| U14 | The evaluator on the program's pipeline; reify of sums and runs; no code table | `IDR/Eval` | F-clo-2, F-clo-3, F-const-2 |
| U15 | One crash entry; `argc`/`argv`; thunk kind freed as a box; `idris_rt_caf_release`; no kept list | `RT/{Rc,Start,Eval,Alloc}` | F-mode-3, F-clo-5, F-lazy-5 |
| U16 | Base's surface in the runtime on both targets; the handle table; immediate clocks | `RT/{Platform,Io}`, `RT/CMakeLists.txt` | F-base-2, F-base-7 |
| U17 | The generator's `IdrPrim`, `IdrRegionPrim` and helpers; `Prim` reduced; IO primitive type gone; `effect`; `guardOf` | `CS/Types.idr`, `CS/Emit/Operations.idr`, `CS/Frontend/Translate/Primitives.idr`, `foreign/idr/tools/idris-mlir-tblgen.cc` | F-prim-1, F-guard-4 |
| U18 | Base's surface registered; pointers as handles; hooks over `IdrPrim`; `exitWith` and `OSClock`; `signal`, `threads` and `process` by name | `CS/Registry`, `CS/Registry.idr`, `CS/Frontend/Translate/{Types,Hooks}.idr` | F-base-1, F-base-3..6 |
| U19 | `#idr.con` runs in canonical form, with the C7.2 API; `Aliases` by the walk rule | `IDR/Dialect/Attrs`, `IDR/Sharing` | F-const-1 |
| U20 | `idr-demand{promises=in-place}`; `--demand`; `--directive demand-in-place` | `IDR/Demand`, `IDR/Driver/{Options,Run}.cppm`, `CS/Frontend/Main.idr` | F-prom-2 |
| U21 | Narrow, Tail and Specialize without sentinels and on the derived stage; guards on narrowed divisions; the walk rule | `IDR/{Narrow,Tail,Specialize}` | F-poison-1 |
| U22 | `T/idr` discriminators of C12; retired mechanisms out of the suite | `T/idr` | none (discriminators) |
| U23 | Program, reject, accept and registry discriminators of C12, against committed expected files; removed rejections rewritten; the runtime's C clients | `T/{programs,accept,reject,lib,registry,compiler,toolchain}`, `T/Main.idr` | none (discriminators) |

## The coordinator's own work

This runs concurrently with the lanes.

**At dispatch, apply the hubs** from `contracts.md` C1, verbatim where
the text is given:

- `INC/IdrOps.td`:
  - the resource, interface and traits;
  - the six guards;
  - the total ops without `Idr_MayCrash`, and `in_bounds` removed;
  - `idr.lambda` and `idr.delay`, and the yield's parents;
  - `memo`, `labels`, `by_name` and the force's operand;
  - `idr.stage` removed;
  - `ConAttr`'s parameters;
  - `Idr_Primitive` on the C8.1 ops;
  - the include of `INC/IdrPlatformOps.td`.
- `INC/IdrPlatformOps.td`: the C9.2 and C9.3 ops.
- `INC/Passes.td`: C1.2, except its `idr-dead-values` lines, which go in
  with U01's held-out group (C13).
- `INC/Idr.h`: C1.4.
- `RT/idris_rt.h`: C1.5.
- `CS/Rule.idr`: C1.6.
- `IDR/Dialect/Registration/PipelineSteps.cc`: C1.3.
- The CMake lists and `Dialect.cppm`: C1.7.
- `idr.stage` goes from the hubs: its `IdrOps.td` entry and the
  `Passes.td` text that names it. `CS/Dialect/Idr.idr` loses it when
  regenerated. `IDR/Dialect/Verify/Attributes.cc` is U03's (C2.2).

**While lanes run:**

- **Exports.** Add every `IDR/Mlir.cppm` export a lane reports.
- **Unit lines.** Add every new or deleted unit line a lane reports to
  `IDR/Dialect/CMakeLists.txt`. That includes any split unit from U19.
- **`Canonicalize.td`.** Apply U04's DRR text: the `HeadOfCons` and
  `HeadOfShow*` patterns look through a `nonempty` guard (C3.4).
- **Contract disputes.** A lane reports a conflict. The coordinator
  edits `contracts.md`, re-dispatches that lane, and records the change
  in README "Rulings on the adversarial review" (or a new "Rulings on
  the swarm" section). No lane negotiates with another.

**Integration:**

1. When all 23 have handed off, audit every diff against its dispatch:
   the permitted outcome, the exclusive writes, the NOT TO DO and
   Delete lists. Reject extras through the same lane. Check that no
   existing `expected-stdout`, `expected-exit` or `expected-crash`
   changed outside a test C12 restates (C0), and read every new one
   against its C12 row.
2. `tools/dialects.sh generate`.
3. If U01 added a patch, set its group aside first (C13): U01 wrote it
   in the shared checkout, and a new `llvm.patch` in the tree makes
   `tools/verify-pins.sh llvm`, and so `make build`, refuse today's
   toolchain. Two stashes, from the repository root, so that the patch
   comes back first:

   ```sh
   git stash push --include-untracked -m u01-rest -- \
     tests/upstream/remove-dead-values-unchanged-call foreign/idr/lib/Simplify
   git stash push --include-untracked -m u01-patch -- \
     upstream/16-remove-dead-values-unchanged-call
   ```

   C1.2's `idr-dead-values` lines are not written yet: `Passes.td`
   carries the rest of C1, and a stash takes whole files. Then
   `make check`, then `make build` on today's toolchain
   (`.toolchain/llvm-macos`: llvm main 7208ba24 with the `llvm.patch` of
   02 to 07, 09 and 15).
4. `make test`, `make test-idr` and `make test-mlir-tools`. Repair
   through the owning lane, and rerun from the first step that failed.
   A program whose output disagrees with its expected file is settled
   from C9's meaning and the C12 row, never by accepting the output.

   **Between steps 4 and 5, on today's toolchain.** The launch base's
   build, kept at orchestrator step 1, runs only here: after step 5,
   `tools/verify-pins.sh` refuses the rebuilt toolchain for a tree
   without U01's patch. It was kept before the hubs were applied, after
   a green `make test` at ccc3e1dc: `build/dev-darwin`,
   `compiler/build/exec` and `tests/build/timing`, in
   `/private/tmp/claude-501/-Users-bjorn-Documents-idris-mlir/5885df12-b5c5-432d-ad84-4829b14959f5/scratchpad/launch-base`
   (orchestrator step 1, "Done at launch").
   - **Compile times.** Copy `tests/build/timing`, which step 4's
     `make test` wrote, and run `tests/compile-times.sh --against` the
     launch base's copy (orchestrator step 1) on it. Record the totals
     and the largest ratios (README Qualification 3).
   - **The launch base's bench record.** With the kept
     `build/dev-darwin` swapped in, as for the sensitivity runs below
     (steps 1 and 4 there), run `bench/run.sh --record <dir>` on this Mac
     with `IDRIS_MLIR` naming the kept compiler (the copy of
     `compiler/build/exec/idris-mlir`; `tools/compile.sh` runs the one
     `IDRIS_MLIR` names), and keep the record: it is what README
     Qualification 3 compares this tree's `bench/run.sh` with. It is
     made here, not at orchestrator step 1, because the hubs were
     applied right after the build was kept.
   - **Sensitivity.** Run each C12 discriminator once against the launch
     base's build (README, Engagement contract), with this tree's test
     files and runner, which compare with no other backend:
     1. move this tree's `build/dev-darwin` aside and put the kept one in
        its place. The harness runs the tools in `$dev_prefix/foreign/idr`
        (`tests/lib/lit.sh`), and the launch base's compiler names that
        directory's `idris-mlir-cc` and runtime (`Frontend/Paths.idr`, as
        its `make build` generated it);
     2. from `tests/`, run the runner directly, as `make`'s test recipes
        do (`Makefile` `RUN_TESTS`: its timeout and the variables the
        `Makefile` exports), with the kept compiler, the copy of
        `compiler/build/exec/idris-mlir`, in place of this tree's:
        `build/exec/runtests <kept idris-mlir> --suite test --only '<the C12 program, reject and accept rows>'`,
        and `--suite test-idr` with the C12 `idr/` rows;
     3. record each row: it fails, or shows the old mechanism;
     4. put this tree's `build/dev-darwin` back.
5. If U01 added a patch: pop `u01-patch`, then `make bootstrap`
   (`tools/bootstrap.sh` applies every `upstream/*/llvm.patch` present),
   which rebuilds stage 2 with it and the steps built with stage 2, on
   arm64 macOS (the cutover's run took 0h30m for stage 2 and 0h05m for
   GMP, `.toolchain/bootstrap.trunk.log`): the one serialization.
   `make test-mlir-tools` does not run `check-mlir`, so run the patch's
   `mlir/test` RUN line by hand, with the rebuilt
   `.toolchain/llvm-macos/bin/mlir-opt` and `FileCheck`, on a scratch
   copy of its test file with the patches applied in order (bootstrap
   deletes its patched tree after stage 2). Then pop `u01-rest`, write
   C1.2's `idr-dead-values` lines, `make build`, run
   `tests/upstream/remove-dead-values-unchanged-call`, and rerun the four
   suites. If U01's fix was ours, there is no step 5: nothing was set
   aside, and its change went in at step 3.

**After integration:**

- **Docs:**
  - `PINS.md` (C1.8; U01's text);
  - the sentences of `upstream/06-…/README.md` and
    `upstream/02-…/README.md` that name `idr-dead-values` (C1.8; U01's
    text), then tell the owner: 06 and 02 are pending LLVM submissions,
    and `upstream/16-…` is new for `upstream/README.md`'s table;
  - `findings/decision-threads-pointers.md`, the paragraph of O1;
  - the root `README.md`'s pipeline and "What compiles today", for the
    base surface;
  - `findings/README.md`: W1 to W10 marked done, by commit;
  - `findings/substrate.md` §4 and §6, stale since 20fcfadb, from C11;
    its S2.5, which still reads `RemoveDeadValues.cpp:278` and "a public
    function only" where 7208ba24 has `:280-281` (public, external, or
    with users outside the pass root, F-own-4); and its §1 row 18, which
    still counts two clang workarounds where one remains (C11.1) (README
    "Rulings at launch", L26 and L32).
- **Commits:** to `main`, a few commits, each staging only this packet's
  paths. U01's group, its `PINS.md` text, C1.2's `idr-dead-values` lines
  and the sentences of 02's and 06's READMEs go in one commit (C1.8).
  Before pushing, `git fetch` and rebase onto `origin/main`: another
  agent pushes `upstream/README.md`, the `upstream/NN` READMEs and
  `PINS.md`. Then push `main` and force the session branch to it.
- **Qualification:** README "Qualification".
- **Proposal hygiene:** update this packet's status line once it is
  implemented. It stays as the record of the reasoning
  (`proposals/README.md`).
