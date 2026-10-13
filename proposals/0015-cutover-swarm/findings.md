# Findings

One entry per finding, in groups. Each gives the claim, the evidence at
25890d32 as `path:line` or a symbol, and the selected correction as a
contract section. The owner is in README's finding map; `ownership.json`
is the authority for it. Counts marked **measured** were taken with
`grep` and `wc` at 25890d32 on a checkout with no toolchain; nothing
here was run. Evidence marked **recalled** is upstream code at the pin
that the authoring machine does not hold; the lane that leans on it
reads it at the pin and reports a difference (R44). Everything else is
**read** there.

The rulings of 2026-10-12 (README "Rulings") added F-pass-8 to
F-pass-13, F-state-5, F-state-6, F-hand-7, F-hand-8, F-test-4 and
F-test-5, and named the ruling beside a correction where one changed
it.

Paths are relative to `foreign/idr/lib` unless they start with
`foreign/`, `compiler/`, `tests/`, `runtime/`, `sources/` or are a
top-level file.

## The pass layer

## F-pass-1 Every pass is a module pass

- **Claim:** 26 of the 27 passes anchor on `::mlir::ModuleOp`; the one
  op-agnostic pass, `idr-canonicalize`, is run on the module. MLIR
  parallelizes only over the nested operations of a nested pass manager.
- **Evidence:** `foreign/idr/include/idr/Passes.td` (every `Pass<"…",
  "::mlir::ModuleOp">`; `IdrCanonicalize` at :493 has no anchor);
  `Dialect/Registration/PipelineSteps.cc:9-70`;
  `sources/docs/mlir/docs/PassManagement.md`, "OpPassManager".
- **Correction:** C1.3, C1.4, C2.0. A pass that inserts clones or plans
  over the module stays a module pass, and rewrites one function at a
  time or nests that rewrite (R17 to R20).

## F-pass-2 Every verify walks the whole program

- **Claim:** the module's `idr.program` attribute verifier calls the
  whole-program check, which walks every operation, checks every type
  and runs linearity on every function, after every pass that did not
  preserve all analyses.
- **Evidence:** `Dialect/Verify/Attributes.cc:41`; `Verify/Program.cppm`
  (the walks at its `module.walk` sites and the `linearity(fn)` loop
  near its end); `bugs/simplify-does-not-finish.md` (the sample inside
  the first verify).
- **Correction:** C4.

## F-pass-3 The linearity check is quadratic in a function

- **Claim:** `LinearUses` numbers every operation of the home region
  once per linear value; IO code has a world per bind.
- **Evidence:** `Verify/Linearity.cppm:43-47` (the `place` map built in
  the constructor), `:105-130` (one `LinearUses` per quantity-one value).
- **Correction:** C4 (one numbering per body).

## F-pass-4 Passes hash the module to learn whether they changed it

- **Claim:** several passes compute `OperationFingerPrint` of the module
  before and after their run to decide `markAllAnalysesPreserved`.
- **Evidence:** `Simplify/Pass.cc` (`SymbolsHeld::runOnOperation`);
  `Specialize/Pass.cc:20-36`; `Inline/Pass.cc:72-80`.
- **Correction:** C2.0 (a change flag the pass already knows), C3.1 (one
  fingerprint per round, upstream's).

## F-pass-5 Twenty-five pass managers, built from text

- **Claim:** the driver parses each of 25 textual steps into its own
  `PassManager`, so no analysis survives a step and every step boundary
  verifies.
- **Evidence:** `Driver/Run.cppm:182-222`;
  `Dialect/Registration/PipelineSteps.cc`; `Simplify/Pass.cc`
  (`holdsSymbols`, a `StringSwitch` on pass names).
- **Correction:** C1.4, C5.

## F-pass-6 The inliner is given a pipeline runner that does nothing

- **Claim:** `idr-inline` constructs `mlir::Inliner` with a runner that
  returns success and runs no pipeline, so the inliner's parallel
  optimization of each component's callables never runs.
- **Evidence:** `Inline/Pass.cc:66-71`.
- **Correction:** C3.3 (R22: the runner optimizes only a callable an
  iteration inlined into; F-pass-9).

## F-pass-7 Loop breakers rebuild the reference graph every round

- **Claim:** `markLoopBreakers` constructs a `SymbolTable` and walks
  every body each round; `References` is rebuilt again by the inline
  decisions and by the binding times in the same round.
- **Evidence:** `Simplify/Breakers.cppm:62-80`;
  `Inline/Decisions.cppm:37-50` (`References references(module, symbols)`);
  `Specialize/Pass.cc:45-47` (`CloneTable clones(module); BindingTimes
  times(module, clones)`).
- **Correction:** C2.1 (`References`, `InlineDecisions`, `BindingTimes`,
  `CloneTable` as analyses).

## F-pass-8 A nested manager leaves the round's function step without its analyses

- **Claim:** a nested manager and every `runPipeline` destroy every
  module analysis. The round as C3.2 first wrote it has no step that
  computes the analyses its function step reads, so `idr-identity` and
  `idr-redirect` would fail on their first function.
- **Evidence:** `sources/docs/mlir/docs/PassManagement.md:301-306`
  (every analysis is invalidated unless marked), `:459-495` (a dynamic
  pipeline runs with the analyses of the op it runs on); `contracts.md`
  C3.2 as first written (`idr-effects` and `idr-loop-breakers` compute
  neither `Identities`, `CloneTable` nor `BindingTimes`; `sccp` to
  `symbol-dce` preserve nothing); `OpToOpPassAdaptor` marks nothing
  preserved (**recalled**); the escalations of U06 and U13.
- **Correction:** C2.0 (the nest rule: no analysis reference held across
  `runPipeline`), C3.2 (`idr-round-facts` before the round's function
  step); R15.

## F-pass-9 With a pipeline installed, the inliner optimizes every component again

- **Claim:** with a pipeline installed, upstream's inliner optimizes
  every strongly connected component before it inlines into it,
  serially across components. `idr-inline` would canonicalize and CSE
  the whole module once more each round, after the round's parallel
  step did.
- **Evidence:** `Inliner::Impl::inlineSCC` calls `optimizeSCC` before
  `inlineCallsInSCC` in each iteration, and `optimizeSCCAsync`
  parallelizes only within one component (**recalled**,
  `mlir/lib/Transforms/Utils/Inliner.cpp` at the pin); loop breakers
  leave most components a single function
  (`Simplify/Breakers.cppm:1-25`); U05's escalation.
- **Correction:** C3.3 (R22: the pipeline runner runs `canonicalize,cse`
  only on a callable an iteration inlined into).

## F-pass-10 The upstream lowering passes run on the whole module

- **Claim:** after lowering, five op-agnostic upstream passes run on the
  whole module, serially, each followed by a whole-module verify.
- **Evidence:** `Dialect/Registration/PipelineSteps.cc:52-66`
  (`convert-linalg-to-loops` and the lowering conversions as top-level
  steps); `sources/code/mlir/include/mlir/Dialect/Linalg/Passes.td:129`
  (no anchor).
- **Correction:** C1.4 (R21: they run under `func.func` nests).

## F-pass-11 Three tail passes write outside the function they rewrite

- **Claim:** `idr-accumulate` and `idr-trmc` insert a clone into the
  module's block, and `idr-returned-arguments` decides over every
  function and rewrites callers, so none of them can be a function pass.
- **Evidence:** `Tail/Accumulator.cppm:360-367`;
  `Tail/Trmc.cppm:184-194`; `Tail/Returned.cppm:67-136`;
  `sources/docs/mlir/docs/PassManagement.md:33-39` (a function pass
  changes nothing outside its op).
- **Correction:** C1.3, C1.4 (R19: two module passes that plan and
  rewrite one function at a time; `idr::tail::Returned` with a rewrite
  nested over `func.func`).

## F-pass-12 The tail-call pass needs the module's call cycles

- **Claim:** `idr-tail-calls` reads and rewrites `llvm.func` and
  `llvm.call` and needs the module's call cycles, so it cannot run as
  `func.func(idr-tail-calls)` after conversion.
- **Evidence:** `Lower/TailCalls.cppm:77`, `:121`, `:143`;
  `foreign/idr/include/idr/Passes.td:80-82`;
  `Dialect/Registration/PipelineSteps.cc:65-69`.
- **Correction:** C1.3, C1.4 (R20: a module pass with the `TailCallPlan`
  analysis and a rewrite nested over `llvm.func`).

## F-pass-13 An inliner interface for one-block callees changes what is inlined

- **Claim:** today inlining is decided by func's own inliner interface,
  for `func.return` in both terminator forms, and by a dialect interface
  that allows every op and region; the carried patch decides callees
  that end in `ub.unreachable`. An `idr.func` interface that allows only
  one-block callees ending in `idr.return` changes what is inlined.
- **Evidence:** `Ops/Inliner.cppm:14-20`; `PINS.md:285-310`
  (`inline-unreachable`); U02's part as first written.
- **Correction:** C1.2, C3.3 (R22: U02's interface mirrors func's, both
  `handleTerminator` forms).

## State held outside the IR

## F-state-1 Symbol tables are published through thread-local chains and atomics on the dialect

- **Claim:** `SymbolScope` keeps a thread-local chain of scopes, an
  owner token that is the address of a thread-local char, and publishes
  the head through two `std::atomic` members of the dialect object,
  deciding whether it may publish by casting the context's thread pool
  and asking `isWorkerThread`.
- **Evidence:** `Dialect/Symbols/LookupSymbol.cc:17-25` (the chain and
  the token), `:30-40` (`callerPublishes`), `:52-78` (publishing),
  `:101-126` (`lookupSymbol`); `foreign/idr/include/idr/IdrOps.td:30-45`
  (the atomics on the dialect).
- **Correction:** C2.0 (deleted; `getAnalysis<SymbolTable>()` and
  `getCachedParentAnalysis<SymbolTable>()`); the symbol helpers by name
  (R09).

## F-state-2 The may-hold memo is the same mechanism

- **Claim:** `HoldMemo` repeats F-state-1 for the per-type answers of
  `mayHoldWorld` and `mayHoldClosure`, with a thread-local answer map
  keyed by an epoch from a process-wide atomic counter.
- **Evidence:** `Dialect/Symbols/HoldMemo.cc:15-70`, `:72-120`.
- **Correction:** C2.1 (`Holds`, preserved by every pass that changes no
  declaration).

## F-state-3 The effects pass keeps inferred results on the pass instance

- **Claim:** `Effects` holds `Inferred inferred` across rounds, and its
  copy constructor resets it because the pass manager copies passes.
- **Evidence:** `Facts/Pass.cc:17-21`, `:36`; `Facts/Infer.cppm:1-5`.
- **Correction:** C2.1 (`Effects` analysis), C1.3 (`idr-effects` writes
  the facts from it).

## F-state-4 Analyses are rebuilt per pass

- **Claim:** the analysis manager is used in eleven lines of the tree,
  nearly all in `idr-inline`; every other pass rebuilds what it needs.
- **Evidence (measured):** `grep -rn 'getAnalysis<\|getCachedAnalysis\|AnalysisManager\|markAnalysesPreserved<' foreign/idr/lib | wc -l` is 11 at
  25890d32; `Inline/Pass.cc:34` is the one `getAnalysis<SymbolTable>()`.
- **Correction:** C2.1.

## F-state-5 A call's effects are recomputed at every query

- **Claim:** a call's effects are recomputed at every query from its
  callee's fact and from what the closures it is passed may do, through
  lookups an op hook can only make by scanning the module, and through a
  type filter that needs the may-hold answers an op cannot reach.
- **Evidence:** `Facts/CallEffects.cc:40-45`; `Facts/Passed.cppm:51-87`
  (the filter at :57); `Facts/Of.cppm:16-24`;
  `Dialect/Symbols/LookupSymbol.cc:119-126` (a scan without a scope);
  commit 45c2c5d0.
- **Correction:** C1.2, C2.2 (R07: `idr.call`'s effects, written by
  `idr-effects` and read by `getEffects` with no lookup).

## F-state-6 Without a scope, the dialect's table-less code scans the module

- **Claim:** once `SymbolScope` goes, the dialect's code that runs with
  no table in hand resolves declarations and callees by scanning the
  module's top level: the verifiers of the string and force ops on every
  verify, the consumption of a call, and a canonicalization pattern at
  every attempt on every match with a default.
- **Evidence:** `Dialect/Ops/Strings.cc:11-34`;
  `Dialect/Ops/Lazy.cc:300-337`; `Dialect/Effects/Consumed.cc:24-28`;
  `Canon/MatchPatterns.cppm:46-49`;
  `Dialect/Symbols/LookupSymbol.cc:119-126`.
- **Correction:** C1.2, C2.0 (R05: declaration rules as symbol-use
  rules, bounded scans), C2.2 (R08: consumption by grade), C6.4 (R42: a
  covered default dropped by the frontend).

## Facts

## F-fact-1 A function's facts are discardable attributes read by string

- **Claim:** totality, breaker status, effects, clone key and hole are
  `idr.*` discardable attributes on `func.func`, read by string literal
  in 28 places and through generated helpers elsewhere.
- **Evidence (measured):** 28 matches of
  `hasAttr("|getAttr("|getAttrOfType<…>("|setAttr("|removeAttr("` under
  `foreign/idr/lib`; among them `Tail/WhileDo.cppm:271`,
  `Tail/Loop.cppm:108`, `Ownership/Exclusive.cppm:48`,
  `Dialect/Ops/Lazy.cc:226-229`, `Tail/Accumulator.cppm:364`,
  `Tail/Trmc.cppm:188`; the declarations at
  `foreign/idr/include/idr/IdrOps.td:51-67`.
- **Correction:** C1.2 (`idr.func`), C2.2.

## F-fact-2 A trait polices every op's attribute dictionary because facts are discardable

- **Claim:** `Idr_KnownAttributes` on every idr op runs
  `verifyDiscardableAttrs`, and the dialect's `verifyOperationAttribute`
  rejects any other `idr.*` name, because a fact in a discardable
  attribute could otherwise be dropped silently.
- **Evidence:** `foreign/idr/include/idr/Idr.h` (`KnownAttributes`,
  `verifyDiscardableAttrs`); `Dialect/Verify/Attributes.cc:14-80`;
  `Dialect/Verify/DiscardableAttrs.cc`; AGENTS.md ("A fact kept in a
  discardable attribute can be dropped silently").
- **Correction:** C1.2, C4. The dialect keeps `program` and `stack` as
  its only discardable attributes (R04).

## F-fact-3 The specialization key lives in two discardable attributes

- **Claim:** `idr.clone` on the function and `idr.hole` on each
  parameter carry the clone's key between runs.
- **Evidence:** `foreign/idr/include/idr/IdrOps.td:60-66`,
  `:1360-1420` (the key attributes); `Specialize/Clones.cppm:1-12`.
- **Correction:** C1.2 (`clone` inherent), C2.1 (`CloneTable` an
  analysis).

## The build

## F-build-1 The pass layer is written against a profile that forbids MLIR

- **Claim:** PINS.md records that MLIR's API is forbidden by the C++
  profile, so all of `foreign/idr` is quarantine code: C++20 module units
  importing one wrapper of every MLIR header, with `.cc` glue for
  anything that includes ODS output.
- **Evidence (measured):** 314 `.cppm` units (284 partitions), 111 `.cc`
  units, 285 importers of `idr.mlir`; `Mlir.cppm:1-9`; `PINS.md`
  `mlir-cxx-api` (:61-73), `clang-module-layout-forward-declaration`
  (:511-521); `foreign/idr/cmake/IdrLibrary.cmake`.
- **Correction:** C1.1.

## F-build-2 `make build` has no compiler cache

- **Claim:** the README says `make build` goes through no cache because
  its units import C++ modules.
- **Evidence:** `README.md`, "Setup" ("goes through no compiler cache").
- **Correction:** C1.5.

## F-build-3 The compiler is built hardened in every configuration

- **Claim:** UBSan with traps, zero-initialized locals, zeroed call-used
  registers, no strict aliasing and the stack protector are on the
  language profile for every preset, Release included.
- **Evidence:** `CMakeLists.txt:285-301`; `CMakePresets.json` (three
  presets: `dev`, `release`, `lint`).
- **Correction:** C1.5 (`hardened` preset).

## F-build-4 Tracy is compiled in from an unpinned sibling checkout and never instrumented

- **Claim:** every tool force-loads a Tracy client built from
  `${CMAKE_SOURCE_DIR}/../tracy`, a directory outside the repository
  that no pin, lock file, Makefile, bootstrap or document names, with
  `TRACY_ENABLE` always on and an Apple sampler workaround; no zone,
  frame mark or plot exists in the tree.
- **Evidence (measured):** `foreign/idr/CMakeLists.txt:239-266`
  (`IDRIS_MLIR_TRACY_DIR`, `FATAL_ERROR` when missing), `:277`, `:291`,
  `:342`, `:349-351` (force-load); `TracySampling.h`; zero matches of
  `ZoneScoped|FrameMark|TracyPlot|TracyAlloc` under `foreign/idr` and
  `runtime`; zero matches of `tracy` in `Makefile`, `tools/*.sh`,
  `toolchain.lock.json`, `PINS.md`, `README.md`.
- **Correction:** C1.5, C8 (R39: one instrumentation in every build,
  allocation tracking behind its own option).

## The handoff

## F-hand-1 Erased values are emitted as values

- **Claim:** a parameter of quantity zero is a parameter of type
  `!idr.erased`, and every call site materializes `#idr.erased` for it.
- **Evidence:** `compiler/src/IdrisMLIR/Emit/Types.idr:16-18`, `:32`,
  `:47`; `compiler/src/IdrisMLIR/Emit/Bodies.idr:323-334`;
  `compiler/src/IdrisMLIR/Emit/Operations.idr:76-79`;
  `compiler/src/IdrisMLIR/Types.idr:116`, `:128-131`.
- **Correction:** C6.1, C10 (the erased grade deleted). An erased value
  in a runtime position that Translate cannot drop is refused, and the
  corpus records every program newly refused (R28).

## F-hand-2 Symbol names are mangled with `$<n>$`

- **Claim:** every character outside `[A-Za-z0-9_.]` in a name is
  written `$<code point>$`, though MLIR accepts any quoted symbol name.
- **Evidence:** `compiler/src/IdrisMLIR/MLIR/Text.idr:15-26` (`mangle`),
  `:54-59` (`symbol` already quotes); `sources/docs/mlir/docs/LangRef.md:207`
  (`symbol-ref-id ::= @ (suffix-id | string-literal)`).
- **Correction:** C2.3, C6.3 (R31: mangling once, in `idr-lower`'s
  phase 0).

## F-hand-3 The instance key is the symbol name

- **Claim:** `instanceName` prints the definition's name and the normal
  forms of its arguments into the symbol, with a counter suffix for
  collisions; the C++ side cannot read the structure.
- **Evidence:** `compiler/src/IdrisMLIR/Frontend/Translate/Types.idr:61-90`;
  `bugs/idris-mlir-handoff-investigation.md` §3.6, §3.11, §3.12 (from a
  dump).
- **Correction:** C1.2 (`Idr_InstanceAttr`), C1.6, C6.3. Every part of
  the key is text and no part is a symbol use (R02).

## F-hand-4 The handoff is written in generic form by design

- **Claim:** Emit writes every op in MLIR's generic form.
- **Evidence:** `compiler/src/IdrisMLIR/Emit.idr:1-4`;
  `compiler/src/IdrisMLIR/MLIR.idr` (the generic printer).
- **Correction:** C7.3 (R33: a generated head printer per dialect where
  the generator can print the op's format; generic form otherwise).

## F-hand-5 Locations are a start point, and names reach only declarations

- **Claim:** `span` prints the start line and column only, and `Named`
  locations are given to data declarations, constructors and functions,
  never to the values Idris binders bind.
- **Evidence:** `compiler/src/IdrisMLIR/MLIR.idr:126-141`;
  `compiler/src/IdrisMLIR/Emit/Declarations.idr:33`, `:38`, `:60`;
  `compiler/src/IdrisMLIR/Emit/Bodies.idr:104`, `:116`, `:150` (`At l`
  everywhere); `compiler/src/IdrisMLIR/Loc.idr:11-22` (the record holds
  the end).
- **Correction:** C6.5.

## F-hand-6 Shims, newtypes and unneeded delays survive into MLIR

- **Claim:** a method call through a fixed implementation is emitted as
  an apply of a shim function's lambda; single-field single-constructor
  types are declared and matched; `idr.delay` wraps values already
  evaluated.
- **Evidence:** observed in the stage-0 dump,
  `bugs/idris-mlir-handoff-investigation.md` §3.2, §3.3, §3.4, §3.7; the
  mechanism read in
  `compiler/src/IdrisMLIR/Frontend/Translate/Instances.idr:1-5`
  (instances keyed by implementations) and `Translate/Closed.idr:1-6`.
  Unverified in the code for each case: U19 confirms each against the
  translator before changing it.
- **Correction:** C6.2, C6.4 (R41: a missing parameter is a closure).
  Every Delay stays `idr.delay`; the dialect folds an evaluated
  suspension and defunctionalization makes it the memo's forced state
  (C2.4, R27).

## F-hand-7 A complete split is emitted with a default region

- **Claim:** the frontend emits a default region after a complete split
  of a data type, which a C++ pattern then removes by looking up the
  declaration of every match.
- **Evidence:** `Canon/MatchPatterns.cppm:41-59` (the comment: Idris's
  case trees carry one for the clauses that follow a complete split).
- **Correction:** C6.4 (R42: Translate drops a covered default;
  `DropCoveredDefault` goes).

## F-hand-8 Emission holds the whole module as one string

- **Claim:** emission holds the whole module as one Idris `String`,
  built from a piece list and written afterwards. At stage 0 that is a
  405 MB module at 9.1 GB peak.
- **Evidence:** `compiler/src/IdrisMLIR/Emit.idr:39-52`;
  `compiler/src/IdrisMLIR/MLIR.idr:210-214`, `:262-264`;
  `compiler/src/IdrisMLIR/Frontend/Program.idr:41-50`, `:177-183`;
  `HANDOFF.md:22-27`, `:47-49`.
- **Correction:** C6.7 (R34: Emit streams to a handle, top-level op by
  top-level op).

## Readability

## F-asm-1 No op suggests a result name, and no type an alias

- **Claim:** no idr op declares `OpAsmOpInterface`; no idr type declares
  `OpAsmTypeInterface`; the only alias is for large constants.
- **Evidence (measured):** zero matches of `OpAsmOpInterface|OpAsmTypeInterface`
  in `foreign/idr/include/idr/IdrOps.td`; `Sharing/Aliases.cppm:1-62`
  (`aliasFrom = 256`, `idr_value`);
  `sources/docs/mlir/docs/DefiningDialects/Assembly.md` (the hooks).
- **Correction:** C1.2, C7.1, C7.2.

## F-asm-2 A data type is a mangled symbol and nothing else

- **Claim:** `!idr.data<@…>` and `!idr.box<@…>` carry only a
  `FlatSymbolRefAttr`; the instance's structure is in the name.
- **Evidence:** `foreign/idr/include/idr/IdrOps.td:95-105`.
- **Correction:** C1.2 (`instance` on `idr.data`), C7.2 (aliases, a
  character-level shortening that decides nothing, R35); C10
  (declarations stay monomorphic).

## The round

## F-round-1 The round is a fixpoint of eleven module passes

- **Claim:** `idr-simplify` runs eleven module passes up to 64 times;
  MLton runs a fixed sequence of 23 passes with a bounded loop knob.
- **Evidence:** `Simplify/Round.cppm:25-50`; `Simplify/Pass.cc`;
  `foreign/idr/include/idr/Passes.td:515-537` (`max-rounds` 64);
  `sources/docs/mlton/doc/guide/src/SSASimplify.adoc` (the list,
  `-loop-passes <n>`).
- **Correction:** C3 (R15: the round's facts, then `idr-round-facts`,
  then the function step, then the symbol changes).

## F-round-2 Deadness is computed five ways

- **Claim:** `remove-dead-values`, `symbol-dce`, `idr-identity`,
  canonicalize's dead-op erasure and `idr-returned-arguments` each
  answer part of what MLton's `RemoveUnused` answers in one fixpoint.
- **Evidence:** `Simplify/Round.cppm:38-50`; `Identity/Rebuilds.cppm`
  (740 lines); `sources/code/mlton/mlton/ssa/remove-unused.fun:14-70`;
  `sources/docs/mlton/doc/guide/src/RemoveUnused.adoc`.
- **Correction:** C3.2 keeps the upstream passes and makes `Identities`
  an analysis (C2.1); a merge is a later packet, measured. `Returned`
  and `Identities` stay two analyses, noted for that packet (R43).

## F-round-3 Canonicalize is wrapped to count rewrites and hold scopes

- **Claim:** `idr-canonicalize` copies canonicalize's configuration to
  attach a counting listener and open a symbol scope.
- **Evidence:** `Canonicalize/Pass.cc:50-104`; `Support/Counts.cppm`.
- **Correction:** C3.2 (upstream's pass).

## Tests

## F-test-1 Every fixture spells `func.func`

- **Claim:** 254 of 256 dialect fixtures contain `func.func`, with 672
  `func.call` sites.
- **Evidence (measured):** `grep -l 'func\.func' tests/idr/*/*.mlir | wc -l`
  is 254; `func.call` sites sum to 672.
- **Correction:** C9.1.

## F-test-2 Two programs of the suite already hit the wall

- **Claim:** `every-interfaces-export` (282 lines) and
  `every-types-export` (224 lines) compile and then hit their time
  limits.
- **Evidence:** `HANDOFF.md`; `proposals/0001-llvm-trunk.md`;
  `proposals/0002-representation-cutover/README.md` ("Not run");
  `tests/programs/prelude/every-interfaces-export/Main.idr` (282 lines).
- **Correction:** C4, C3, C6; the acceptance of U04, U02 and U22.

## F-test-3 Every program is compiled twice for a mode that no longer exists

- **Claim:** `e2e` compiles each fixture a second time with `--no-eval`,
  and `idr-eval` was deleted in 96e1d308.
- **Evidence:** `tests/lib/e2e.sh:75-80` and `tests/lib/properties.sh:1-7`;
  `git show 96e1d308 --stat` (the `Eval/` deletions); every `expected`
  file's `no-eval` lines.
- **Correction:** C9.2.

## F-test-4 The compile-time record reads the rows of a pass that is gone

- **Claim:** the suite's compile-time record breaks each compilation
  into `idr-eval`'s JIT and evaluation rows, deleted in 96e1d308, and
  records no round count.
- **Evidence:** `tests/compile-times.sh:17-24`, `:94-118`;
  `git show 96e1d308 --stat`.
- **Correction:** C9.2 and README "Qualification" (R47: the timing
  report read as JSON, with the round count per program).

## F-test-5 The determinism proof does not compare remarks

- **Claim:** the determinism proof compares the module and the
  statistics, not the remark stream, though two passes that emit
  remarks become parallel function passes.
- **Evidence:** `tests/lib/determinism.sh:60-105`;
  `tests/idr/vectorize/refused-rows-in-order.mlir:1-2`;
  `Vectorize/Tiles.cppm:110`, `:123`, `:157`;
  `Narrow/Lanes.cppm:64`, `:125`.
- **Correction:** C2.0, C9.2 (R38: `threads-*` also compare the function
  passes' remarks, one thread against the pool).
