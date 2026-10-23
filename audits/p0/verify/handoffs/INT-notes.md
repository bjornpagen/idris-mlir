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

- **INT-5 (2026-10-22, 0ff91c65 → 384796f3).** The specification builds
  end to end on stock Idris 0.8.0 (85 modules, 93-196 s, 361 MiB peak;
  `Spec.idr` alone 113 s, the op-name distinctness proof); specgen
  writes its 60 outputs and the manifest in 0.56 s, deterministically,
  and they are committed (384796f3). knowngen builds and its check
  passes; all four libraries install. The checker, frontend and harness
  are paused while the checker's parser is rewritten (D119). Two
  runaways were found and fixed: Atom's `kept` (986 s, 18.7 GiB) and
  specgen's unary `decimal` (621 s, 20.8 GiB). Open for the owner's
  machines: the bootstrap (it clears the Idris submodule's lag behind
  its pin, 1c630e67c against 89ba32eb, which `make spec` refuses), and
  `tools/dialects.sh generate` for the Linalg, Bufferization and SCF
  modules, which needs the C++ idris-mlir-tblgen.

- **The signature's second classification (L16bm, 2026-10-22).** When
  the frontend first runs, compare in `Instances.request` and in
  `Cases.heldHere` the caller's kinds with the new `sig.kinds`, position
  by position (whether each binds at run time, and its static content),
  across `make test`, `make test-idr` and `make self`. If nothing
  differs, L16 builds the signature from the call's classification and
  threads the instance's runtime parameters through the tree (Cases
  :794, :834 become unrepresentable); if something differs, the kind
  that differs names the reading to fix. Route the result to L16.

- **INT-16 (2026-10-23, at d096237a; `build/int16/`).** The patched stock
  Idris (96, 104 to 110) installs whole, `install-api` included (553 s,
  3.0 GiB); the checker builds clean with no scratch (208 modules,
  629 s), 110 clearing every coverage report and `mappedContracts`'
  runaway. The frontend stops at module 23 of 101; with 23 files of
  throwaway scratch every module builds and `idris-mlir-front` links
  (524 s; Sites 188 s, Terms 124 s; the link 82 s at 6.0 GiB peak).
  Routed: the driver's `Compile` patterns and syntax-samples' dependency
  (5edb5795); five shapes stock rejects to L06d; the rest by file to
  L16db (Growth, Graph, Sites, Template, Heads, Program), L16dd (Proof,
  Indexed), L16de (Instances, Cases, Choices, Programs) and L16df
  (Terms, Types, Readings with `SkeletonOf`'s positivity, Closed,
  Contraction, Keys). INT-17 rebuilds once they hand off.

- **INT-17 (2026-10-23, at 7632b5ad; `build/int17/`).** The checker
  builds clean (208 modules, 684 s, 5.5 GiB peak; spec 86 of 86). The
  frontend builds 55 modules from HEAD before its first error (INT-16:
  22), and with 226 marked scratch lines in 9 files all 102, the
  executable and syntax-samples (498 s; Sites 176 s, Terms 129 s; the
  executable's compile 5.9 GiB). Every INT-16 root is cleared but R-u
  (patch 111, not yet installed) and one R-o2 site, now R-v. Routed:
  Closed's `Part` collision and the driver's scrutinee (a65c6591); State's
  import, R-e in Proof/Template and Describes, Graph's `Calls`/`Builds`
  arity and two ambiguities to L16dh; R-v and a lazy `if` (R-n) to L06e.

- **INT-18's preconditions (2026-10-23).** Reinstall the toolchain's
  stock Idris with 96 and 104 to 112 (`tools/bootstrap.sh idris`), then
  build the checker (now carrying 104, 105, 107 to 112 as its own code)
  and the frontend. `KcaseTy` is unused after L17aq's 107: remove it from
  `compiler/checker/known/Vocabulary.idr` and rerun knowngen, its
  generated `Known.idr` committed. The new `tests/checker-*` run in
  `test-mlir-tools` on the owner's machines; their refusal tests' line
  numbers are assumptions L17aq could not check.

- **INT-18 (2026-10-23, at 366a9a22; `build/int18/`).** The stock Idris
  with 96 and 104 to 112 installs whole (474 s, 3.0 GiB; `install-api`
  about 142 s) and the four upstream checks pass on it. The checker,
  first built with L17aq's ports, needed one fix (R-w, `emptyArg`'s
  as-name in a nested case; 76804a4b), then all 208 modules (649 s,
  4.7 GiB). The frontend builds 85 of 102 modules from HEAD before its
  first error (INT-17: 55) and, with scratch in 5 files, all 102, the
  executable running and syntax-samples (519 s; Sites 194 s, Terms
  126 s, the executable about 100 s at 6.2 GiB). Routed: R-x (Sites'
  `asRole`), R-f (Heads' order), `knownAt`'s state, and R-y and R-z's
  sites to L16do; R-y, R-z and the remaining R-u (`atNamedType`,
  `CovG.idr`) to L06f; State's `resolvedItself` qualified; Boundary's
  dependent-map import came with L17ar.

- **INT-19 (2026-10-23, at 0639a573; `build/int19/`).** The checker
  builds clean, no scratch (208 modules, 634 s). The frontend builds 86 of
  102 modules from HEAD (one missing import, R-h, fixed after), and with
  two scratch files all 102, the executable and syntax-samples (526 s,
  6.1 GiB). The first run of `idris-mlir-front`: prelude installs
  through it; base is refused by our checker at three roots stock Idris
  accepts (C-1 a pair's unbound part types, C-2 a quoted `%search`, C-3 an
  `if` in a type reaching the TTC writer as a resolved name), routed to
  L17at; with those scratched base installs (136 of 136). On `tests/hello`
  and nine other fixtures it writes a module holding one refusal: F-1
  (`main`'s `IO` read as a data family where Programs and Terms still
  match the erased one-field form bfcc5041 removed) and F-2
  (`checkedLibrary` reading a point-free function's arity off its case
  tree), routed to L16dr. Neither `missedEntry` nor the dependent-map
  ambiguity was met.

- **INT-20 (2026-10-23, at 9998e953; `build/int20/`).** The stock Idris
  with 96 and 104 to 114 (111 amended) installs whole (466 s, 3.0 GiB),
  every one of its twelve upstream checks passing; the checker builds
  clean (208 modules, 638 s); `knowngen check` passes. The frontend builds
  87 of 102 modules from HEAD, all with 3 scratch lines (Heads' H-1 and
  H-2). Prelude (14 of 14) and base (136 of 136) install through
  `idris-mlir-front` with no scratch, and it writes a program for hello,
  bubble-sort, chars, bounded-family-head, bounded-method, call-pattern,
  arity-raising, absurd-body, char-list-pipeline and most new checker
  programs; the two refusal tests refuse. Every INT-19 root is cleared.
  Routed: H-1, H-2 and F-4 (every use of Foldable List refused, its
  default foldlM unfixed) to L16dw; F-3 (a polymorphic field read as a
  dependent one), F-5 (`%search` refused by the profile, ruled in the
  subset) and F-6 (a probe's name in a key taken for a definition) to
  L16dx; T-1 (an ill-typed checker test) to L17av.
