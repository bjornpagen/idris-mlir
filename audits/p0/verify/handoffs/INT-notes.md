<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Notes for INT, kept by the coordinator

Things no lane owns that INT must do before it builds. Each lane's
handoff lists its own wiring.

- **Submodule checkouts lag their gitlinks.** The coordinator moved the
  gitlinks without fetching, so the commits are not yet local:

  | submodule | checkout | gitlink |
  | --- | --- | --- |
  | `third_party/Idris2` | 1c630e67c | 89ba32eb |
  | `third_party/modular` | 9211931 | a1ccd095 |
  | `third_party/simdutf` | bb77e7bb (9.3.0) | 8d82299 (9.3.2) |

  Run `git submodule update --init --recursive` (it fetches) before
  anything builds. The bootstrap's simdutf step refuses a mismatch.
- **Generated outputs.** Run specgen and commit every output listed in
  `generated.manifest`, the manifest included. L16 deleted the stale
  `compiler/src/IdrisMLIR/{Dialect,Encoding}/Idr.idr`, which specgen
  writes again. L19 wrote `Expect/Properties.inc` by hand to match its
  records; the printer must reproduce it.
- **The fork's TTC version** needs bumping if L17's changes alter the
  TTC (L17b).
- **Per D111:** build the Idris half here on stock Idris, route its
  errors, and stop at the LLVM build. The owner runs the bootstrap and
  the C++ build on the four targets.
- **Qualification, added by L11:** re-measure code generation
  time on the large-function program that set `inlineCallerInstructions`
  (recorded 2.8 s against 95 s), since always-inline runtime entries now
  inline into large functions too (C186). L11's guess is a small cost,
  unmeasured.
- **Admitted classes (L06, 2026-10-22):** nothing in CMake runs
  `-gen-admitted-classes` yet; wire it. After specgen `write`, run
  `tools/dialects.sh generate`, which now reads each dialect's
  `Generated/IdrAdmitted<Name>.td`; the Idris dialect modules then hold
  only admitted ops' builders.
- **Stale generation in CMake (L11, 2026-10-22):**
  `foreign/idr/include/idr/IR/CMakeLists.txt` lines 9-12 and 23-28
  still run tblgen backends that no longer exist (`IdrRules.txt`,
  `IdrRuleCategories.inc`, `IdrPassRoles.txt`, `IdrPassStages.txt`).
  `idris-mlir-tblgen` registers only `gen-idris-syntax`,
  `gen-idris-dialect`, `gen-idris-bytecode` and `gen-admitted-classes`.
  Delete those lines. The `lib/` CMakeLists also name about 91 deleted
  sources (the C2 audit's count); rewire every list from the handoffs.
- **Admitted classes (L03, 2026-10-22):** run `-gen-admitted-classes`
  once per `Generated/IdrAdmitted<Name>.td` (Base excluded), writing
  `IdrAdmitted<Name>Classes.h.inc`, taking the file list by glob. Link
  `MLIRInferIntRangeCommon` into the e-graph's library (C191).

## From the 2026-10-22 commits

- **The fork's package (31013e5a).** `idris-compiler.ipkg` depends on
  `mlir-linear` and `mlir-array`, so the fork target builds and installs
  those host libraries first. New modules: `Core/Name/{Ident,Known}.idr`
  and `Core/TT/Stored.idr`. `ttcVersion` is `1_2026_10_21_01`. Under
  C199, `Known.idr` becomes a generated output: L17d names its
  generator, and the manifest and `make check` take it.
- **The lowering's library (7844ae42).** `IdrConversion` links the
  library that compiles `Transforms/Counting/Bound.cpp`. No CMake entry
  lists `Bound.cpp` yet, and `lib/CMakeLists.txt` lists the old
  `Conversion/` units, not `Conversion/Lower/*`.
- **The spec's outputs (432cb165).** Regenerate the spec outputs, the
  Math and UB admitted `.td` files and the dialect modules.
- **The runner (0d1b59ac).** The Makefile's `runner` target builds on
  `IDRIS_PREFIX`, where nothing installs `idris-mlir-spec`, and its
  comment about contrib and test is stale.
- **dialects.sh (9771a679).** It needs `Generated/WrittenDialects.txt`
  committed. If 25's or 28's rewritten reproducer fails to parse, its
  test reports "not this bug": send it back to L06.

## From the later 2026-10-22 commits

- **Tool stacks (fa28fa87, C201).** No target entry defines
  `IDRIS_MLIR_TOOL_STACK_BYTES` or `IDRIS_MLIR_TOOL_SIGNAL_BYTES`. Set
  both in each entry of the root `CMakeLists.txt`, and emit them from
  `foreign/idr/CMakeLists.txt` into the generated `idr/TargetEntry.h`,
  which `Tool.h` includes. Set the stack size to the painted high mark
  over every thread of `idris-mlir`, `idris-mlir-opt` and
  `idris-mlir-reduce` (Release), on the stage-1 module and the nesting
  fixtures, plus the target's outside-code margin (C201), at most
  UINT_MAX/2. Set the signal size to the deepest painted signal stack
  with LLVM's crash report running. Record each with its build and
  input.
- **Unit tests (23160ccb and after).** `unittests/Quantities.cpp` and
  `unittests/TokenCases.cpp` go in one box linking IdrIR and
  MLIRParser.
- **The frontend's package (2c829605).** `compiler/src/IdrisMLIR/Laws.idr`
  is deleted, and `idris-mlir.ipkg` no longer depends on
  `mlir-relational`; check whether the Makefile still installs it for
  the frontend. Regenerate `IdrisMLIR.Dialect.SCF` once
  `scf.index_switch` is admitted (L09).
- **Regenerate the `.td` files** after the TailKind documentation
  change (db35bc4b).

## From the 2026-10-22 evening commits

- **The toolchain checkout.** The local `.toolchain` LLVM checkout is at
  7208ba24, behind the pinned 416f328b (L06h); the bootstrap moves it.
- **New upstream patches 100 and 101** (d3935eeb), with their checks
  under `tests/`. `tools/patches.sh` orders patches by number.
- **Stale CMake.** `StructureLoops/Nests.cpp` is listed but gone, and
  `Bufferize/Generating.cpp` is missing; add `StructureLoops/JoinLoops.cpp`
  (569d1d61) and `Transforms/InPlace/Sites.cpp` (6ab0f70c). IdrStructureLoops
  links the joins library and IdrIR, and IdrTail links IdrStructureLoops
  (d5c5cc0f). The e-graph's library links `MLIRInferIntRangeCommon` and
  reads `StageFacts.h.inc`.
- **New headers.** `include/idr/IR/Ops/BigOfInteger.h` (df7d56b8), which
  `IdrInterfaces.h.inc` needs first, and
  `include/idr/Transforms/Optimize/Tails.h` (fc3c2904).
- **New spec modules.** `Spec/Closures/Memo.idr` (fc3c2904),
  `Spec/Families/{Types,Ops}.idr` (0d858dba), `Spec/Core/Verdict.idr`
  (L03f, in progress); `spec.ipkg` and `Spec.idr` list them (L03).
- **Regenerate** after L04's `ClosureReach`, `numeralBound`,
  `layoutMatch` and `isFree`, L13's `folding`, laws and `ShownOutput`,
  and L09's widened `lit.match`.

- **The arena's decode cost (L17, 2026-10-22).** Measure calls to the
  fork's `typeOf` per definition and the time spent decoding stored
  definitions, from the frontend's `--timing` on the self-compile at
  stage 0 and stage 3. About twelve frontend sites read a definition's
  type. Add no cache unless the stage-3 number shows it pays: a `Lazy`
  in `Root` memoizes under idris-mlir but not on Chez's default laziness.

- **The growth check's stuck calls (L16az, be1146e1).** A site's call
  over the writer's markers is now read as the call as written beside
  its unfolding, so the graph bounds an instance that leaves the call
  stuck. The graph may now refuse a program whose instances never leave
  such a call stuck; until be1146e1 those programs passed and leaned on
  the run-time re-check. When the suite runs, route every new
  `static argument` or growth refusal of a test that passed before to
  L16 with its program, as a precision regression, not an expected
  change. Expected change: instances whose static arguments differ only
  by eta are now one instance (C221).
- **Caps (L16az/L16bb).** `Growth/Caps.idr` must call `capTemplate`
  (L16bb, in flight); build the frontend only at a commit where it does,
  or capped shape parameters lose their caps.
