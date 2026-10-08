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
| U01 | Patches for the two clang crashes and the dead-values rebuild; the workarounds deleted | `upstream/{clang-module-layout-forward-declaration,clang-module-predeclared-new,remove-dead-values-unreachable}`, the same three under `T/upstream/`, `IDR/Stack/Escape.cppm`, `IDR/Driver/Retarget.cppm`, `IDR/Simplify` | F-up-1..3 |
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
| U23 | Program, reject, accept and registry discriminators of C12; `gc-clock`; removed rejections rewritten; the runtime's C clients | `T/{programs,accept,reject,properties,lib,registry,compiler,toolchain}`, `T/Main.idr` | none (discriminators) |

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
- `INC/Passes.td`: C1.2.
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
   Delete lists. Reject extras through the same lane.
2. `tools/dialects.sh generate`.
3. `make check`, then `make build` on today's toolchain. U01's two clang
   hunks (C11.1) and its `IDR/Simplify` change (C11.2) stay out of the
   tree until step 5 (C13): both need the patched toolchain.
4. `make test`, `make test-idr` and `make test-mlir-tools`. Repair
   through the owning lane, and rerun from the first step that failed.
5. `make bootstrap`, the patched LLVM: hours, the one serialization.
   Then apply U01's held-out changes, `make build`, and rerun the four
   suites.
6. **Sensitivity.** Run each C12 discriminator once against ee4ce8e's
   build, and record that it fails or shows the old mechanism.

**After integration:**

- **Docs:**
  - `PINS.md` (C1.8; U01's text);
  - `findings/decision-threads-pointers.md`, the paragraph of O1;
  - the root `README.md`'s pipeline and "What compiles today", for the
    base surface;
  - `findings/README.md`: W1 to W10 marked done, by commit.
- **Commits:** to `main`, a few commits, each staging only this packet's
  paths. Then push `main` and force the session branch to it.
- **Qualification:** README "Qualification".
- **Proposal hygiene:** update this packet's status line once it is
  implemented. It stays as the record of the reasoning
  (`proposals/README.md`).
