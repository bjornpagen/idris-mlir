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

## INT-21 (2026-10-23, export of 7878bda0; build/int21/)
- C++ typecheck: HEAD stopped at its shared header (StaticForm.h deleted
  by 0642ef67 with its include standing; cleared by aaa578c6); beneath it
  22 roots that need the typecheck LLVM at the pin with the carried
  patches, and 7 of ours: R2 (the interface defaults' hooks declared after
  the interfaces; L07z), R3 (StaticForm incomplete; cleared by aaa578c6),
  Convert's unqualified match, ScopeWalk's missing include and Extents'
  signedness (fixed in d502a6a6), Lend.cpp:113 (cleared by 80f6e719),
  Reuse.cpp's shadowed freed (L07z).
- specgen check, knowngen check pass; the 19 dialect modules generated
  by the typecheck tblgen are current, HEAD's committed 13 stale (D49/D51,
  INT on the owner's machine).
- Checker clean (208 modules); frontend 102/102 from HEAD; prelude, base,
  linear, network, contrib, test and the four libs/ install through it.
- Fixtures: 424 runs, 325 programs, 80 refused, 19 failed. F-F1 (16,
  tabulate's Nat[_]) and F-F2 (3, a Vect method at a run-time length) at
  Emit's fit: L16ei. F-R1 (System.File.Meta refused, fileTime's alias):
  L16eg. F-R2 (Instances.idr:474 refuses definitions through rewrite or
  replace whose motive the program fixes), F-R3 (Types.idr:853 refuses a
  polymorphic field re-wrapped in a lambda), F-R4 (every-types-export's
  Ord (Either a b), L16dz's gap): L16, after L16ej. F-R5 (five tests not
  valid Idris): L19q. F-R6 (checker-double-nan-itself): L17bb. P-1 (make
  self-spec refused: spec.ipkg's executable against the checker's
  Package.idr): L17bb.
- The runner: fixed in d76f1b33 but for two stock-Idris bugs (L06i).
- (L19q) INT-21's stock-check.sh and front-one.sh omit --no-prelude,
  which the harness passes to every compile (tools/compile.sh, the
  driver forwarding it, Compile.cpp:58): nbody's refusal was that, and
  INT-22 reruns the fixture sweep with the flag before F-R2 to F-R4 are
  worked as frontend refusals.

## INT-22 (2026-10-23, export of 545578b3; build/int22/)
- The fixture sweep as the harness runs it (--no-prelude, each fixture's
  own packages, from a copy as copyFixture makes): 427 runs, 328 programs,
  80 refused, 19 failed. Only nbody was INT-21's missing flag; F-R5's
  other four were real (fixed by L19q). F-F1 fixed by L16ek's Terms
  (uncommitted, lands with L16ej and L16eg), F-F2 is C272, F-R1 L16eg's
  (lands with them), F-R2 to F-R4 queued for L16, F-R6 the test's (fixed).
  N-1 (four near neighbours with no packages file) fixed. HEAD's frontend
  failed at MLIR/Bytecode.idr, fixed in 9690d2aa.
- Seven fixtures expected to compile test where our checker departs from
  stock, each by its comment (where upstream's compiler departs from its
  own language, we keep the language).

## INT-23 (2026-10-23, export of 512a33fe; build/int23/)
- C++ typecheck: past the shared header; INT-21's nine roots of ours
  cleared; 22 old-toolchain roots stand (the typecheck LLVM at the pin
  with the carried patches), one new sibling (Specialize/Open.cpp:119,
  PropagateControlFlowBreak, patch 65). Four new roots of ours: Decide and
  Declare's unqualified match, Tails.h's non-const getter, Nodes.cpp's
  hidden factsOf (fixed by the coordinator), Loans.cpp:116's const
  Dispatch (L07v). specgen check and knowngen check pass.

## INT-25 (2026-10-23, exports of b2a2c4ae and 78ba1613; build/int25/)
- D49, D51: idris-mlir-tblgen rebuilt on each export (make typecheck-tblgen
  over INT-23's user preset, the 2026-10-15 typecheck toolchain) and
  `tools/dialects.sh generate typecheck` run; the 19 modules written into
  the checkout from 78ba1613's generation, no stamp: 13 rewritten (Syntax
  and Dialect of Builtin, Arith, Math, MemRef, Tensor, UB; Encoding/Builtin),
  6 new (Syntax and Dialect of Linalg, Bufferization, SCF). At b2a2c4ae they
  are build/int14/dialects/ byte for byte; at 78ba1613 Dialect/Tensor gains
  688f6b90's concatOp, padOp and yieldOp. check typecheck: 19 current. No
  manifest line (C229). Uncommitted: L16's files, the coordinator commits.
- HEAD's committed modules never build the frontend: the six missing
  ("Module IdrisMLIR.Syntax.Linalg not found"), and the 13 name ops as
  strings (Dialect/Builtin.idr:24 "Can't find an implementation for
  FromString OpName"), stale since f449ae5a. So there is no sweep with
  them; INT-22's (the same module bytes at 545578b3) is the comparison.
- Builds: checker 208/208, spec, frontend 102/102 and syntax-samples at
  b2a2c4ae and at 78ba1613 (each with the 19), the prefix's ten packages:
  status 0, no error. Sweep, 433 fixtures, at both: 367 programs, 62
  refused, 3 failed (F-F2, C272), 1 timeout (checker-tuple-wide-pattern,
  routed to L17 by 3b316a5f). Against INT-22, every difference is another
  lane's commit (F-F1, F-R1 and N-1 fixed), none a module.
- D-1 (L06): the stage-2 form of dialects-current will name
  Dialect/Builtin.idr: upstream 3f38810694 gave builtin.module an optional
  `dlti` attribute, which the typecheck tree (7208ba24, 2430 commits
  behind the pin) lacks; measured with the pin's BuiltinOps.td over it
  (build/int25/pin-ods/). tools/dialects.sh:29-33's "the records are the
  same" holds only while that tree's ODS is the pin's. The other 18 by
  reading are the pin's too.
- D-2: the checkout's build/typecheck idris-mlir-tblgen predates 04d7cfcc
  and writes Dialect/Arith and Syntax/Linalg with the old import order;
  make typecheck-tblgen in the checkout rebuilds it (not run).
- D-3 (L06): make check cannot run here: the runner fails under this
  machine's stock Idris at harness/Covers.idr:471 (upstream/116's bug;
  .toolchain/idris2 carries 96 and 104 to 114, not 116) until
  tools/bootstrap.sh idris rebuilds it. emit-dialects' Linalg, Bufferization
  and SCF lines hold with the written modules by reading.

## INT-24 (2026-10-23, export of a0d5c9c3; build/int24/)
- The frontend over our own Idris, each program as its stage-1 compile
  runs it (tools/self.sh:119-122; tests/spec-self/run:23-27; the others,
  which nothing compiles, as the driver would run their ipkg). Builds from
  HEAD with no scratch but the dialect copy: checker 208/208, spec 86/86,
  frontend 102/102 and syntax-samples (2586 s, 1981 s user, 6.0 GiB); the
  prefix's ten packages, self-checker (208, 421 s, 200 s user, 927 MiB)
  and self-spec (86, 768 s, 426 s user, 449 MiB): status 0, no error.
- 5 programs, 1 written (knowngen: 498,476 bytes, 9 s CPU, byte-identical
  twice), 4 refused; no internal error, no limit reached. Roots in the
  order met (results.tsv, summary.txt):
- S-1 (L06): self.sh:121 passes --core, refused since bfcc5041 ("unknown
  option --core", exit 2): stage 1 compiles nothing.
- S-2 (L06): self.sh:120 omits mlir-linear and mlir-array, which the
  checker depends on (its ipkg:10, 31013e5a) and -p does not bring:
  "Array not found" at Driver.idr:1:1. N-1's shape.
- R-UNIFY (L17, at L16's Growth.idr:498): our checker refuses
  `let (source, a) = head round` ("When unifying", a 520-successor unary
  natural in the type); stock builds it. Past it by a scratch fst/snd.
- R-117 (L17): the runner at harness/Determinism.idr:28; fixed since by
  723cac53 (by reading).
- R-META (L16 Boundary.idr:1005, with L17's output): "a metavariable whose
  definition is neither a solution nor a hole" at main, for specgen, the
  runner (past 117/118) and the frontend (past S-2, R-UNIFY): a pattern
  variable of an implicit's metavariable {x:N}, no clause, no hole, made
  at EmptyFC, at base/Data/SnocList.idr:296 (specgen), Spec/Core/
  Rules.idr:225 (runner), Spec/Ops/Platform.idr:83 (frontend), named by an
  instrumented frontend (scratch 5). Boundary.idr:966-970's "no program
  reaches it" is refuted. specgen reaches it only through main's shape
  (repro/specgen-probe/V25.idr, 11 lines). It hides every later check.
- R-SPEC (L16 Registry/Libraries.idr:92-102): idris-mlir-spec is in no row,
  so it is untrusted: syntax-samples 100 refusals (50 imports, 50
  definitions); with the spec as source it writes its program (4,294,456
  bytes, no refusal). Beneath R-META for the frontend (151 imports) and the
  runner (48), by reading.
- R-PRAGMA (a; L16's code): 54 %prefix_record_projections in 10 modules
  of compiler/src, each refused by the profile (repro/pragma); beneath
  R-META. Drop them or discharge the pragma: the coordinator's call.
- R-ESC-FIN (L16 Profile.idr:446-453; L01's Declaration.idr:83): the walk
  enters a user's auto-0 proof holding a Fin literal and reaches base's
  Fin lemma's believe_me (Data/Fin.idr:249-250): specgen's 38 beneath
  R-META; repro/auto-fin refused with Op 0, written with Op FZ.
- Host modules: reached in no run; by reading neither is refused (the
  checker is the trusted Compiler package: not lexed, its 0-quantity
  believe_me and its assert_total dropped from the walk). No growth
  refusal anywhere; growth is 254 to 664 s of each spec-reaching probe.
