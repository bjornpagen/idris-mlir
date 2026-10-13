# Work units

There are 23 lanes, plus the coordinator's own work. Each lane's full
dispatch is `dispatch/U??-*.md`. This file is the index and the
coordinator's checklist. The roots are as in `ownership.json`:

- `FI` is `foreign/idr`, `INC` is `foreign/idr/include/idr`, `IDR` is
  `foreign/idr/lib`;
- `CS` is `compiler/src/IdrisMLIR`; `RT` is `runtime`; `T` is `tests`.

All 23 lanes start at dispatch where the environment allows (owner
decision 6). Under a lower cap, `orchestrator.md` step 2 says how they
are started; no lane waits for another.

| Unit | Outcome | Writes | Mandatory findings |
|---|---|---|---|
| U01 | The dialect core as `IdrIR`; the symbol helpers of R09 over `SymbolTable&`; table-less code bounded (R05); `getAsmResultNames`, `getAsmName`, aliases; the evaluated delay (R27); the tag limit in `idr.data`'s verifier (R37); `SymbolScope` and `HoldMemo` deleted | the root `IDR/IR/*.cpp` files `ownership.json` lists, `OpsCon.cpp` and `OpsMatchSyntax.cpp` if a split needs them (R45), `INC/IR/{IdrDialect,Grades,Ranges,Symbols}.h`; the old `IDR/Dialect/*`, `IDR/Ops`, `IDR/Ranges`, `IDR/Sharing`, `IDR/Mlir.cppm`, `INC/Idr.h` | F-state-1, F-state-2, F-state-6, F-asm-1, F-asm-2 |
| U02 | `idr.func`, `idr.call`, `idr.return`, their verifiers and the inliner interface mirroring func's (R22); a call's effects checked against its callee (R07); the owned stage's vocabulary (R13); linearity linear; module verifier reduced | `IDR/IR/Func`, `IDR/IR/Verify`, `INC/IR/{Func,Verify,Ownership}.h`; the old verifiers | F-pass-2, F-pass-3, F-pass-13, F-fact-1, F-fact-2 |
| U03 | `References`, `Effects`, `Holds`; `TypeGraph` in `IdrIR` and one SCC utility (R11); `idr-effects` writes facts on functions and calls (R07) | `IDR/Analysis/{References,Effects,Holds}.cpp` and headers, `IDR/IR/TypeGraph.cpp`, `INC/IR/TypeGraph.h`, `IDR/Support/Scc.cpp`, `INC/Support/Scc.h`, `IDR/Transforms/Effects`, `INC/Transforms/Effects.h`; `IDR/Graph`, `IDR/Facts` | F-state-3, F-state-4, F-state-5, F-pass-7 |
| U04 | `idr-simplify` on `CompositeFixedPointPass`; the round of C3.2 with `idr-round-facts` (R15); the loop's instrumentation (R23); breakers; contify | `IDR/Transforms/Simplify`, `INC/Transforms/Simplify.h`; `IDR/Simplify`, `IDR/Canonicalize`, `IDR/Support/{Statistics,Counts}.cppm` | F-pass-4, F-pass-8, F-round-1, F-round-3 |
| U05 | The force preparation (R06); `idr-inline` with the component pipeline only where an iteration inlined (R22); `InlineDecisions` | `IDR/Transforms/Inline`, `INC/Transforms/Inline.h`, `IDR/Analysis/Inline.cpp`, `INC/Analysis/Inline.h`; `IDR/Inline` | F-pass-6, F-pass-9 |
| U06 | `BindingTimes`, `CloneTable`; `idr-specialize`; `idr-redirect` reading no sibling (R15); the two actions (R36); `clone` inherent | `IDR/Transforms/Specialize`, `IDR/Analysis/Specialize.cpp`, `BindingTimes.cpp` if a split needs it (R45), headers; `IDR/Specialize`, two `Support` units | F-fact-3 |
| U07 | `Labels`; defunctionalization as dialect conversion as R26 states it; the evaluated delay's conversion (R27) | `IDR/Transforms/Defunctionalize`, `INC/Transforms/Defunctionalize.h`, `IDR/Analysis/Labels.cpp`, `LabelSites.cpp` if a split needs it (R45), `INC/Analysis/Labels.h`; `IDR/Defunctionalize` | none |
| U08 | `Borrows`, `Reuses`, `Exclusivity`; `idr-rc` in five steps; `idr-rc-place` and `idr-rc-commit` per function (R18) | `IDR/Transforms/Ownership`, `IDR/Analysis/Ownership`, headers; `IDR/Ownership`'s units but `Verify.cppm` | none |
| U09 | `idr-tail-loops` per function; `idr-accumulate`, `idr-trmc` and `idr-returned-arguments` at the module (R19); the tail helpers (R12) | `IDR/Transforms/Tail`, `INC/Transforms/Tail.h`, `IDR/Analysis/Tail.cpp`, `INC/Analysis/Tail.h`; `IDR/Tail` | F-pass-11 |
| U10 | `idr-lower` phase 0 to 2 with mangling in phase 0 (R31); `idr-entry`; `idr-tail-calls` on the module, nested over `llvm.func` (R20); `Layouts` (R37); the target | `IDR/Conversion`, `INC/Conversion`, `IDR/IR/Layout`, `INC/IR/Layout.h`, `IDR/Target/*.cpp`, `INC/Target/Target.h`; `IDR/Lower`, `IDR/Layout`, old `IDR/Target` | F-hand-2, F-pass-12 |
| U11 | Narrowing as `IdrNarrow`: the seeded `Ranges` analysis, module versioning, per-function word rewrite, per-function lanes (R24) | `IDR/Transforms/Narrow`, `INC/Transforms/Narrow.h`, `IDR/Analysis/Ranges.cpp`, `INC/Analysis/Ranges.h`; `IDR/Narrow` | none |
| U12 | `Lengths` private to `IdrInBounds` over `Ranges` (R24); `idr-in-bounds` per function | `IDR/Transforms/InBounds`, `INC/Transforms/InBounds.h`; `IDR/InBounds` | none |
| U13 | `Escapes`, `Identities`; `idr-stack`, `idr-identity`, `idr-isolate`, `idr-demand` | `IDR/Transforms/{Stack,Identity,Isolate,Demand}`, `IDR/Analysis/{Escapes,Identities}.cpp`, `EscapesCycles.cpp`, `IdentitiesRecord.cpp` and `IdentitiesRebuilds.cpp` if a split needs them (R45), headers; the four old dirs | F-round-2 |
| U14 | One typed `PassManager`, `idr-target` then the pipeline of R21; `--without` by top-level step; `--dump-dir` as instrumentation; the driver and tools; `MlirOptMain`; ccache; the presets' consumers | `IDR/Driver`, `INC/Driver`, `IDR/Transforms/Pipeline.cpp`, `INC/Transforms/Pipeline.h`, `IDR/Support/Actions.cpp`, `INC/Support/Actions.h`, `FI/tools/*.cc` but the generator; the registration units, three `Support` units | F-pass-1, F-pass-5, F-pass-10, F-build-1, F-build-2, F-build-3 |
| U15 | `idr-expect` | `IDR/Transforms/Expect`, `INC/Transforms/Expect.h`; `IDR/Expect` | none |
| U16 | Folders; `idr-vectorize` | `IDR/IR/Fold`, `INC/IR/Fold.h`, `IDR/Transforms/Vectorize`, `INC/Transforms/Vectorize.h`; `IDR/Fold`, `IDR/Vectorize` | none |
| U17 | Canonicalization patterns; `DropCoveredDefault` deleted (R42) | `IDR/IR/Canon`, `INC/IR/Canon.h`; `IDR/Canon` | none |
| U18 | Emit, streamed to a file (R34), through the generated head printers (R33) | `CS/Emit*`, `CS/MLIR*`, `CS/Types.idr`, `CS/Term.idr`, `CS/Loc.idr`, `CS/Facts.idr`, `CS/Graph.idr` | F-hand-1, F-hand-4, F-hand-5, F-hand-8 |
| U19 | Translate; text keys (R02); arity (R41); covered defaults dropped (R42); the erased-position refusal (R28) | `CS/Frontend/*`, `CS/Registry*` | F-hand-3, F-hand-6, F-hand-7 |
| U20 | The generator: a head printer per dialect; the samples in both forms (R46) | `FI/tools/idris-mlir-tblgen.cc`, `tools/dialects.sh`, `CS/SyntaxSamples.idr` | none |
| U21 | The dialect suite | `T/idr` | F-test-1 |
| U22 | The program suites; the timing record as JSON (R47); remarks in the determinism proof (R38) | `T/*` but `T/idr`, `T/spec`, `T/README.md` | F-test-2, F-test-3, F-test-4, F-test-5 |
| U23 | Profiling: one instrumentation in every build; allocation tracking behind `IDRIS_MLIR_PROFILE_MEMORY` (R39) | `INC/Support/Profile*.h`, `IDR/Support/Profile*.cpp`, `tools/profile.sh`, `bench/profiles`, `IDR/TracySampling.h` | F-build-4 |

## The coordinator's own work

This runs concurrently with the lanes.

**At dispatch, apply the hubs** from `contracts.md` C1, as revised by
the rulings:

- `INC/IR/IdrOps.td` and `INC/IR/IdrPlatformOps.td`: move from `INC/`,
  then C1.2 as revised by the rulings R01 to R05, R27 and R37, verbatim
  where the text is given.
- `INC/Transforms/Passes.td`: move from `INC/Passes.td`; the anchors of
  C1.3; `IdrRedirect` and `IdrRoundFacts` added; `IdrCanonicalize`
  deleted; no `IdrRcPlace` or `IdrRcCommit` def (R17); no `let
  constructor` anywhere (R21); apply R40.
- The lists of C1.1, and no other `CMakeLists.txt` under `IDR` (R10).
  Each starts with its library target and an empty source list, to be
  filled:
  - `INC/CMakeLists.txt`, `INC/IR/CMakeLists.txt` (`IdrOpsIncGen`:
    `IdrEnums`, `IdrAttrs`, `IdrDialect`, `IdrInterfaces`, `IdrTypes`,
    `IdrOps` as `.h.inc` and `.cpp.inc` under `include/idr/IR`),
    `INC/Transforms/CMakeLists.txt` (`IdrPassesIncGen`);
  - `IDR/IR/CMakeLists.txt`: `IdrIR` from every `.cpp` under `IDR/IR`,
    with the PUBLIC link of `idris_rt` and `runtime/` on its interface
    include path, `IDRIS_MLIR_TARGET_TRIPLE` as
    `FI/CMakeLists.txt:61`, a dependency on `IdrOpsIncGen` and on
    `IdrCanonicalizeIncGen` (the `mlir_tablegen(IdrCanonicalize.inc
    -gen-rewriters)` rule over `IDR/IR/Canon/Canonicalize.td`), and a
    link of `IdrSupport` for `Scc`;
  - `IDR/Analysis/CMakeLists.txt`: `IdrAnalysis` from every `.cpp`
    under `IDR/Analysis`, subdirectories included;
  - `IDR/Transforms/CMakeLists.txt`: the libraries of C1.1's table for
    the areas under `IDR/Transforms`, and `IdrPipeline` from
    `Pipeline.cpp`; `IdrVectorize` depends on `IdrPassesIncGen` and
    links `IdrIR`;
  - `IDR/Support/CMakeLists.txt`: `IdrSupport`;
  - `IDR/Target/CMakeLists.txt`: `IdrTarget`, keeping
    `IDRIS_MLIR_TARGET_TRIPLE` and `IDRIS_MLIR_TARGET_CPU`;
  - `IDR/CMakeLists.txt`: `IdrConversion`; `IdrDriver` with the four
    definitions of `FI/CMakeLists.txt:316-321` plus the triple and the
    CPU, and `idr/TargetEntry.h`, `idris_rt.h` and `cpu_features.h` on
    its include path;
  - `FI/CMakeLists.txt`: the subdirectories and the four tools.
- `CMakePresets.json` and the top-level `CMakeLists.txt`: C1.5; the
  `profile` preset lists `IDRIS_MLIR_PROFILE_MEMORY`, default OFF
  (R39).
- `.gitmodules`, `third_party/tracy` at O2's tag, `toolchain.lock.json`.
- `CS/Ids.idr`: C1.6 as revised by R02.
- `compiler/idris-mlir.ipkg`: remove `IdrisMLIR.Emit.Attributes`; add
  `IdrisMLIR.Frontend.Translate.Keys` after
  `IdrisMLIR.Frontend.Translate.Closed` (R30).
- `.gitignore`: `bench/profiles/*.tracy`.

**While lanes run:**

- **Unit lists.** Each lane reports the `.cpp` files of its library;
  the coordinator writes them into the list of C1.1 that declares the
  library. U23 reports the CMake hub text of its profile build
  (`idr_tracy` only with `IDRIS_MLIR_PROFILE=ON`, the option,
  `ProfileAlloc`'s link into the three tools only).
- **Contract disputes.** A lane reports a conflict, or a difference at
  the pin (R44). The coordinator edits `contracts.md` (taking the named
  fallback where there is one), re-dispatches that lane, and records the
  change in README "Rulings". No lane negotiates with another.
- **`T/spec`**: C9.3's rule changes as R10 revises them
  (`spec/mlir-layout` allows exactly the three state exceptions;
  `spec/file-size`, `spec/verifier-every-pass` and
  `spec/no-local-headers` search `.cpp`, `.h` and `.cc`, the generator
  staying listed in `T/spec/file-size/allowed`; `spec/no-local-headers`
  accepts no header beside a `.cpp`), the new `mlir-layout` rule, and
  `T/spec/verifier-every-pass/run:8` without `idr-eval's lowering`.
- **Docs**: PINS.md, AGENTS.md, README.md, HANDOFF.md as README
  "Qualification" step 4 says.

**Integration:**

1. When all 23 have handed off, audit every diff against its dispatch:
   the permitted outcome, the exclusive writes, the NOT TO DO and Delete
   lists. Reject extras through the same lane.
2. Fill every `CMakeLists.txt` from the unit lists; delete
   `IDR/Dialect/CMakeLists.txt` and `IDR/Ownership/CMakeLists.txt`,
   which the lanes that own their units have emptied. `tools/dialects.sh generate`
   with U20's generator.
3. `make check`, then `make build`. Repair through the owning lane, and
   rerun. This first build is the one serialization.
4. `make test-idr`, `make test`, `make test-mlir-tools`. Repair through
   the owning lane, and rerun.
5. Configure and build `release`, `hardened` and `profile`; run
   `tools/profile.sh` once on `every-interfaces-export`, and once with
   `--memory`.
6. **Sensitivity.** Run each C9 discriminator once against 25890d32's
   build, `T/compiler/dialect-syntax` included, and record that it fails
   there.
7. Commit once the suites are green on arm64 macOS, with x86_64 Linux
   recorded NotRun and run next (owner decision 5); then qualify and
   report as README says.
