# U17 — The dialect suite states the new IR's guarantees as properties

## Permitted outcome
1. Mandatory. `idr-expect` holds exactly the properties C24 lists: the
   five new ones (`structured-loops`, `typed-reads`, `in-place`, `fused`,
   `largest-function`), `no-guards` in a unit of its own, `narrowed-lanes`
   with accumulators exempt, and the rest as today. A request for a
   deleted property is `idr-expect: no property named <name>`.
2. Mandatory. `@f` finds its functions by C24's rule (a symbol, or a
   `NameLoc` in the function's own location), never by `instance`,
   `clone` or a symbol-table chain; idr-expect reads no analysis of the
   optimizer (`callees` reads symbol uses).
3. Mandatory. Every fixture under `tests/idr` is written in the IR after
   the cutover: one public root of a root type or none, every function
   private but the root and every function with a body (D7, D28); no
   module mark; data types as C01's identified types; closures and
   suspensions in symbol form and an evaluated suspension as
   `idr.delay %value` (C22, C02); every inherent fact as C02 declares it;
   arrays as tensors with `idr.tie_shape` where Idris ties a dimension
   (C11); world-ordered arrays as C11's memref ops.
4. Mandatory. Every fixture that ran a deleted pass runs what replaces it
   (C12's registry): the optimizer's tests run `idr-optimize`; the dumps
   are upstream's `-mlir-print-ir-tree-dir`; the debug-counter fixture
   runs in `idris-mlir-opt`.
5. Mandatory. New fixtures, each stating its property: every former
   source of an unknown label set converts (0004 §2.2's table); the grade
   fixtures (D27); the empty key; the tag limit (D48); the ready set
   processes each function once (C07); a pure call whose result is unused
   is gone after `idr-optimize` (D38); the caller cap stops inlining and
   never rejects (D25); specialization past its budget compiles (D39);
   names from content (one module and the same module reordered give the
   same symbols; one function edited leaves every other symbol); a module
   with two public functions is refused (D28); `idr.tie_shape` folds,
   bounds and verifies; `idr-structure-loops` structures pure loops and
   keeps ordered ones; bufferization puts a linear thread in place, keeps
   the grade across a branch and a match, makes a two-field record's array
   two buffers, and reports a link read after its release as an internal
   error with One-Shot's conflict (0003 §17 stage 1).
6. Mandatory. Every fixture whose expected text cannot be known without
   running starts with `// NEEDS-ACCEPTANCE: <what to check>` and is
   listed in the handoff.
7. Consumer adaptations: the Expect units that read IR ops C01, C02 and
   C11 change (`CellsFit.cpp`, `Quantities.cpp`, `ReusesEveryCell.cpp`,
   `ReusesInPlace.cpp`, `MovesOut.cpp`, `Continuations.cpp`,
   `Closures.cpp`).

## Owner / exclusive writes
- `tests/idr` (the whole dialect suite: every `.mlir`, every `<name>/run`
  and `<name>/expected`, the `.awk` helpers beside them). New
  directories: `tests/idr/tie-shape`, `tests/idr/structure`,
  `tests/idr/bufferize`, `tests/idr/optimize`, `tests/idr/names`. Deleted
  directories: `tests/idr/in-bounds`, `tests/idr/isolate`.
- `IDR/Transforms/Expect` (`foreign/idr/lib/Transforms/Expect`). New
  units: `Guards.cpp`, `StructuredLoops.cpp`, `TypedReads.cpp`,
  `InPlace.cpp`, `Fused.cpp`, `Sizes.cpp`. Deleted units: the four that
  Delete names.
- `INC/Transforms/Expect.h` (`foreign/idr/include/idr/Transforms/Expect.h`).

**Excluded:** `include/idr/Transforms/Passes.td` (U06: `IdrExpect` is
C12's row, its description names no property); `foreign/idr/lib/Transforms/CMakeLists.txt`
(coordinator: add the six new units, drop the four deleted);
`tests/lib/*.sh`, `tests/testutils.sh`, every `mlir.expect` and every
other directory of `tests/` (U18); `include/idr/Transforms/StructureLoops.h`
(U11), `include/idr/Transforms/Bufferize.h` (U12),
`include/idr/Analysis/Inline.h` (U03), `include/idr/Transforms/Narrow.h`
(U09), every IR header (U01, U02, U11); `tests/upstream` (U16).

## Read first
- `contracts.md` (or `contracts/` until it exists): C24 whole; C01, C02,
  C03 for the IR the fixtures are written in; C05, C06 for defunctionalization;
  C07, C08, C09, C10 for the optimizer's observable behaviour; C11 for
  tensors, `idr.tie_shape`, the world-ordered ops and
  `idr::structure::structurable`; C12 for pass names; C14 for `idr.stack`
  and the in-place type fact; C15 for the bufferization pass and
  `idr::bufferize::copies`; C16 for lowering; C21 for name shapes; C22 for
  the emitted forms; C23 for deduplication's fused location.
- `proposals/0004-compile-time/README.md`: §2.2 (the table of former
  unknowns), §2.4, §2.5, §2.9 (the fixtures each risk names), §4 stages 1
  to 9, §6 (every row naming `tests/idr`; the registry table), §10 lane
  L8, D25, D27, D28, D37, D38, D39, D45, D46, D48.
- `proposals/0003-typed-apl/README.md`: §4.1, §4.3, §5, §6, §7.2 (`fused`),
  §8, §15, §17 stage 1.
- `foreign/idr/lib/Transforms/Expect/*.cpp` and
  `include/idr/Transforms/Expect.h` (1,795 lines; read every unit);
  `include/idr/Transforms/Passes.td:769-869` (the entry C24 replaces).
- `tests/lib/lit.sh:1-99` (how a RUN line runs: `%s`, `%t`, `%status N`,
  pipefail, no Python), `tests/lib/expect.sh:1-12` (how `mlir.expect`
  calls the pass), `tests/README.md:1-70`.
- The fixture classes, by today's form: `module attributes {idr.program}`
  in 218 files; `idr.data` in 145; `idr.lambda` or `idr.delay` regions in
  20; 61 split-input chunks with more than one public `idr.func`; 31
  bodiless `idr.func` in 21 files (`effects/idr-effects.mlir`,
  `stack/calls.mlir`, `func/call-effects.mlir`, `func/clone-shape.mlir`,
  `verify/closure.mlir` and 16 more); passes run by name: `idr-simplify`
  14 files, `idr-inline` 5, `idr-specialize` 26, the isolation pass 7,
  `idr-round-facts` 2, the in-bounds pass 13 (counted 2026-10-14 by a
  search of `tests/idr/**/*.mlir`).
- `foreign/idr/lib/Transforms/Isolate/Isolate.cpp:124-140` (how a
  lambda's function gets its definition's `NameLoc`), `Emit/Declarations.idr:79`
  (how Emit names a function's location).
- `.toolchain/build/llvm-project/mlir/lib/Debug/Observers/ActionLogging.cpp`
  (what `--log-actions-to` prints), `include/mlir/IR/Location.h`
  (`NameLoc`, `FusedLoc`), `lib/Tools/mlir-opt/MlirOptMain.cpp`.

## Fixed decisions
- **One test API.** A fixture states a property through `idr-expect`, an
  exit status (`%status N`), a verifier diagnostic (`-verify-diagnostics`),
  or a FileCheck of the one fact the property is (a fold to a value, a
  lane count from the target). Never an op sequence, an SSA name, a clone
  number or a function order. A generated symbol is never spelled in a
  CHECK line: C21 makes it a hash; a fixture finds the function by
  `loc("f")` and `@f`.
- **The layout stays:** `tests/idr/<concern>/<name>.mlir` with its `RUN:`
  lines, `<name>/run` (`lit ../<name>.mlir`), `<name>/expected` holding
  `RUN 1: ok` to `RUN k: ok`, one line per RUN line. The expected file is
  therefore always known; where a CHECK pattern or a diagnostic text is
  inferred, the `.mlir`'s first line is `// NEEDS-ACCEPTANCE: <what to
  check>`.
- **Closed world in every fixture** (D7, D28). A module holds at most one
  public `idr.func`, the root, typed `() -> i64` or `(!idr.world) -> (...)`;
  every other function is private and has a body. A fixture that runs a
  pass that may erase an unreferenced private function (`idr-optimize`,
  `idr-deduplicate`, `idr-defunctionalize`, `symbol-dce`,
  `remove-dead-values`, `idris-mlir`) has a root that reaches every
  function it checks. A fixture that only parses, verifies or runs a
  per-function pass is a fragment: no public function. A bodiless
  stand-in for "a callee that may do anything" becomes a private function
  whose body has exactly the effects the test needs: IO through
  `idr.io.*` on a world, a crash through `idr.crash`, divergence through a
  call to itself in a function that is not `total`.
- **Pass names are C12's.** `idr-optimize` for every test of inlining,
  specialization, raising, the rounds or their facts (D45); `idr-redirect`,
  `idr-identity`, `idr-contify`, `idr-effects`, `idr-binding-times`,
  `idr-deduplicate`, `idr-defunctionalize` as steps of their own;
  `idr-structure-loops` (C11); the bufferization pass C15 registers;
  upstream `-mlir-print-ir-tree-dir` for every dump.
- **Order is the pipeline's.** A fixture of a pass that runs after
  defunctionalization (the optimizer, the memory passes, lowering) is
  written first-order (sums, no `idr.closure`, `idr.apply`,
  `idr.suspend` or `idr.force` of a closure) or runs
  `--idr-defunctionalize` first in its RUN line.
- **Names from content are tested as invariance.** `names/reorder`: the
  same module with its functions in reverse order (an awk line writes
  it) gives the same set of symbols after `idr-optimize`, compared by
  `sort` and `diff`. `names/edit`: one function's body changed (a sed
  line writes it) leaves every other generated symbol in place.
- **The ready set's "once" is observed through C07's action.** The
  fixture runs `idris-mlir-opt --idr-optimize --mlir-disable-threading
  --log-actions-to=-` and checks, with `grep`, `sort`, `uniq -d` and
  `count`, that C07's per-node action begins once per function of the
  module.
- **The debug-counter fixture moves to `idris-mlir-opt`** (D46): upstream's
  `-mlir-debug-counter=<C09's action tag>-skip=...` on a module with two
  specialization requests; the skipped one stays a call of the original.
- **The bound of `largest-function`** in the caller-cap fixture is 10,000,
  D25's cap; the clone-budget fixture generates 1,025 requests of one
  owner from one node, D39's budget of 1,024 plus one.
- **The tag-limit fixture** generates a capture cycle of 65,537 labels
  (`IDRIS_RT_TAG_LIMIT` = 2^16 tags, plus one) and expects one
  `unsupported (layout)` diagnostic; its `.mlir` carries
  `NEEDS-ACCEPTANCE` for its run time under the suite's bound.
- **Expect units.** One property per unit, as today. `Named.cpp` holds
  `names`, `named` and `rootsOf`; `Cycles.cpp` holds `callees` and
  `cycles`; `Report.cpp` and `Lookup.cpp` as today.

## Inputs
- C24: the whole contract (this lane's own declarations).
- C01: the identified data type's syntax, its constructors by name and
  their field types, its kind; the op that names a constructor.
- C02: inherent facts on ops (`idr.stack` on `idr.con`, `idr.delay
  %value`, call-site effects verified equal, no loop-breaker fact).
- C03: the root and the module verifier, their diagnostics.
- C04: the rule enum and how a refusal prints.
- C05: the flow interface, the ops that declare it, its verifier's
  diagnostics; C06: what a converted key becomes, the empty key.
- C07: the ready set's per-node action tag; C08: `idr::inlineSize` and the
  10,000-op cap; C09: specialization nodes, their action tag, the budget;
  C10: what `idr-effects` writes.
- C11: tensor forms, `idr.tie_shape`'s assembly and verifier,
  `idr-structure-loops`, `idr::structure::structurable`, the world-ordered
  array ops and the read that moves an element out.
- C12: every registered pass name and the pipeline order.
- C13: the vectorization schedule's step in the lowering tail.
- C14: the in-place promise as a type fact; C15: the bufferization pass,
  its diagnostics, `idr::bufferize::copies`; C16: what lowering makes of
  memrefs.
- C21: the shape of a generated name; C22: the emitted module's forms;
  C23: deduplication's fused location of a kept function.

## Outputs
- C24, produced here: `include/idr/Transforms/Expect.h`, whose comment on
  each property's declaration is the one list of the properties, and
  every unit of `lib/Transforms/Expect`, as C24 fixes them. Consumers:
  U06 (`IdrExpect`'s row in the pass registry), U18 (`mlir.expect` files and the test
  helpers that call the pass), the coordinator (the build list).
- The dialect suite itself: the proof the suites' owner runs for every
  contract a fixture exercises (Inputs).

## Implement
1. **Expect.h and Named.cpp.** Write C24's header, one comment per
   property declaration saying what it checks (C12 keeps the list out of
   `Passes.td`). `names(fn, f)`:
   compare `SymbolTable::getSymbolName(fn)` with `f`, then walk
   `fn->getLoc()` with a worklist over `NameLoc::getChildLoc()` and
   `FusedLoc::getLocations()`, true at a `NameLoc` whose name is `f`.
   `named`/`rootsOf` drop the symbol-table parameter. Delete `copiedFrom`.
2. **Cycles.cpp.** `callees(symbols, fn)`: the targets of
   `SymbolTable::getSymbolUses(&body)` that are `FunctionOpInterface`, in
   walk order, repeats dropped. `cycles` unchanged.
3. **Callers of the old signatures.** Every unit that calls `named`,
   `rootsOf` or `names` drops the `SymbolTable` argument; `Clones.cpp`
   and `NotCalled.cpp` look the callee up with the pass's
   `analyses.getAnalysis<SymbolTable>()` and call `names(callee, f)`.
   `Allocation.cpp` follows `callees` instead of `References`.
4. **Guards.cpp.** Move `noGuards` from `InBounds.cpp:80-89` with its
   helper `noneLeft`.
5. **The new properties**, each as C24's table says:
   `StructuredLoops.cpp` (walk the roots for loops implementing
   `LoopLikeOpInterface`; fail on each `structurable(loop)`; fail when no
   op of the linalg dialect is in the roots), `TypedReads.cpp`,
   `InPlace.cpp`, `Fused.cpp`, `Sizes.cpp` (parse the argument with
   `StringRef::getAsInteger(10, n)`).
6. **NarrowedLanes.cpp.** The ops `idr::narrow::accumulations(loop)`
   returns (U09's rule, `include/idr/Transforms/Narrow.h:115-121`) are no
   lane `widestLane` counts.
7. **Consumer adaptations to the IR.** `CellsFit.cpp`, `Quantities.cpp`,
   `ReusesEveryCell.cpp`, `ReusesInPlace.cpp` read constructors and field
   types from C01's identified type; `Quantities.cpp`'s `bindsProved`
   loses `LambdaOp` (a lambda is a function now), keeps
   `MatchOp`/`MatchLitOp`, and compares binders only (a body is set
   once); `MovesOut.cpp` reads C11's world-ordered read;
   `Continuations.cpp` and `Closures.cpp` drop the comments and tests of
   the clone self-reference and external functions.
8. **Lookup.cpp** lists exactly C24's names.
9. **The fixtures**, by directory (each keeps its property, in the IR of
   Fixed decisions):
   - Rewritten in place for the new IR and closed world: `asm`, `canon`,
     `constants`, `contify`, `effects`, `fold`, `guards`, `lower`,
     `narrow`, `ownership`, `returned`, `rc`, `stack`, `syntax`, `world`,
     `e2e`, `tail-calls`.
   - `defunc`: each fixture that expected a refusal of a label set now
     converts, or, where its op lacks the flow interface by C05, is a
     `-verify-diagnostics` fixture of that verifier error in `verify`. New:
     one fixture per row of 0004 §2.2 (a closure through a non-entry block
     argument of a multi-block function; the yield of an evaluated
     suspension; a closure crossing a match's region argument; a lazy key
     whose labels return through the forced anchor; an empty key whose
     apply becomes `ub.unreachable`), each with `no-closures` after
     `idr-defunctionalize`; the three grade fixtures of 0004 §2.9; the tag
     limit.
   - `dedup`: `refuse` becomes `dedup/merge-named`: two functions with
     different `instance` facts and locations `loc("a")`, `loc("b")` merge,
     and `one-clone=@a one-clone=@b` both hold after `idr-deduplicate`
     (the kept function's location names both, C23).
   - `expect`: every property of C24 has a fixture with a module where it
     holds and one where it fails (`%status 1` and a FileCheck of
     `expected <name>:`). `one-clone` and `not-called` find copies by
     `loc("f")`.
   - `func`, `verify`: the module rules of D28 (`verify/module.mlir`: two
     public functions refused, a root of another type refused, a fragment
     passes); a bodiless `idr.func` refused; the call-site effects
     verifier's equality (D38); the flow interface's verifier (C05);
     C01's identified type verifier in `verify/data.mlir`;
     `verify/roundtrip.mlir` gains `idr.tie_shape` on a tensor and on a
     memref.
   - `identity`: `idr-effects` then `idr-identity`, no round facts.
   - `loops`, `raise`, `specialize`, `pipeline`, `obs/stats`,
     `effects/inlined-proof`, `func/inline`: on `idr-optimize`, properties
     instead of symbol names; `specialize/budget` states D39 (compiles,
     the 1,025th request stays a call of `@apply`); `pipeline/steps`,
     `pipeline/timing`, `e2e/eval`, `tail-calls/mutual` read
     `-mlir-print-ir-tree-dir`; `obs/debug-counter` in `idris-mlir-opt`.
   - `vectorize`: `rows-x86-64`, `rows-aarch64` and `lanes-x86-64` on
     tensor inputs in the frontend's shapes (`tensor.empty` and an
     `scf.for` of `tensor.insert`), through `idris-mlir -c` with the
     module dumps, `vectorized` on the dump after C13's vectorization step,
     the lane count from the target by FileCheck on `idr-pipeline`'s LLVM;
     `lanes-loops` as today.
   - New: `optimize/once` (C07's action once per function),
     `optimize/pure-call` (D38), `optimize/caller-cap` (D25:
     `largest-function=10000` and `%status 1` on `not-called` of the call
     the cap kept), `optimize/totality` (no input to `idr-optimize` is
     refused: a module at every budget compiles); `names/reorder`,
     `names/edit`; `tie-shape/dims-fold`, `value-bounds`, `verify`,
     `bufferized`; `structure/tabulate`, `ordered`, `nest`;
     `bufferize/linear-thread`, `recursive-thread`, `release-copies`,
     `release-constant`, `link-read-after-release` (the internal error),
     `branch-and-match` (grade kept), `record-fields` (two tensors, then two
     memrefs), `runtime-cells`.
10. **Failure paths.** A fixture whose operand a contract does not yet
    give (an op's assembly, a pass name, an action tag) is written against
    the contract's text; where the contract is silent, the fixture is
    written with the closest fixed form and listed as a seam.

## Delete
- `lib/Transforms/Expect/BreaksLast.cpp`, `EveryCycleHasBreaker.cpp`
  (the properties `breaks-last` and `every-cycle-has-breaker`, which exist
  only for `LoopBreakers` and `break_last`); `InBounds.cpp` (the
  properties `in-bounds` and `bounds-checked`, which read
  `inbounds::accessedArray` of `idr-in-bounds`); `PureArrayLoops.cpp`
  (`pure-array-loops`, over `idr.array.generate` and `idr.array.fold`).
- From `Expect.h`: `referencedBy`, the `SymbolTable &` parameters of
  `names`, `named`, `rootsOf`, and the declarations of the deleted
  properties. From `Named.cpp`: `copiedFrom` and the clone-key chain.
- `tests/idr/in-bounds/` whole (13 fixtures, 39 files), with
  `idr-in-bounds`.
- `tests/idr/isolate/` whole (7 fixtures), with `idr-isolate` and the
  `idr.lambda`/`idr.delay` region forms.
- `tests/idr/expect/breaks-last.mlir`, `breaks-last/`, `breakers.mlir`,
  `breakers/`; `tests/idr/loops/breakers.mlir`, `breakers/`
  (`LoopBreakers`, `break_last`).
- `tests/idr/obs/budget.mlir`, `round-failure.mlir`,
  `round-failure.mlir.awk`, `round-trace.mlir` and their directories (the
  rounds, `max-rounds`, `compile-time budget`).
- `tests/idr/pipeline/steps.mlir`'s usage errors of `--without` and
  `--demand-in-place`; `tests/idr/pipeline/do-block.mlir:5-6`, the
  `scc-pipeline` A/B lines; every `--dump-dir` in `tests/idr`.
- `tests/idr/specialize/breaker-clones` (loop breakers and clones),
  `tests/idr/specialize/clone-callers` (the self-referencing `CloneAttr`),
  `tests/idr/func/clone-shape` (the `clone` fact and its keys, gone with
  `CloneAttr`), `tests/idr/specialize/redirect` (the redirect step reads
  the node table inside `idr-optimize` and has nothing to read alone).
- `tests/idr/effects/stale` (a call's effects are its callee's, verified
  equal, so a stale fact is no longer expressible).
- `tests/idr/defunc/evaluated-refused`, `unknown-lazy`, `numbering`,
  `dead-move-empty-key`, `tests/idr/dedup/refuse` (refusals of label sets,
  counter-made sum names and the `instance` refusal), replaced by the
  fixtures Implement names.
- In `Quantities.cpp`, the comparison of constructor field quantities: a
  data type's body is set once, so it cannot drift under one name.
- `tests/idr/canon/match-in-generate`, `tests/idr/lower/array-combinators`,
  `tests/idr/rc/array-loops`, `tests/idr/vectorize/generate-fill-first`,
  `tests/idr/vectorize/refused-rows-in-order` (`idr.array.generate`,
  `idr.array.fold`, `ArrayLoops`, `idr-vectorize`).
- The splits of `tests/idr/verify/attributes.mlir` that check `idr.program`
  and `idr.stack` as discardable attributes.
- Every `module attributes {idr.program}`, every `break_last`, every
  `idr.inlined`, every `idr.stack` attribute, every `clone = #idr.clone<...>`
  that names its own function, in `tests/idr`.

## NOT TO DO
- Do not edit `Passes.td` (U06, C12), any CMakeLists.txt
  (coordinator), `tests/lib`, `tests/testutils.sh` or any `mlir.expect`
  (U18).
- Do not add a property option, a mode or a flag to `idr-expect` beyond
  `holds`; a variant of a property is a second property with its own
  name.
- Do not compute a pass's decision a second time inside a property:
  `structured-loops` asks C11's `structurable`, `in-place` C15's
  `copies`, `largest-function` C08's `inlineSize`, `narrowed-lanes`
  U09's `runsAtMostOnce` and `accumulations`.
- Do not read `instance`, a `clone` key or a specialization key to find
  a function; do not match a generated symbol (`.spec<n>`, a hash) in any
  fixture.
- Do not keep a fixture alive by giving `idr-optimize` an option, or by
  running a deleted pass through `--pass-pipeline`.
- Do not add a comparison with Idris's Chez backend or any other
  implementation; the expected files are the specification.
- Do not write `--dump-dir`, `--demand-in-place`, `--without` or
  `-mlir-debug-counter` in an `idris-mlir` RUN line.

## Tempting partial solutions
- **Keep `instance` as the lookup and leave deduplication's refusal
  alone.** Rejected by `dedup/refuse` restated: two functions with
  different `instance` facts merge, and `one-clone=@a` and
  `one-clone=@b` both hold on the module after `idr-deduplicate`.
- **Make every fragment's functions public to keep them alive.** Rejected
  by `verify/module.mlir`: a module with two public functions is refused
  (D28), so every such fixture fails to parse.
- **Spell the specialization's hashed symbol in a CHECK line.** Rejected by
  `names/edit`: the hash moves with any change of the key, and the fixture
  would go stale on an unrelated change (AGENTS.md).
- **Re-derive "pure body" in `structured-loops`.** Rejected by
  `structure/ordered`: a pure float fold stays an `scf.for` (0003 §6), so
  a property that calls every pure loop structurable fails there while
  the pass is right.
- **Turn `breaks-last` into a no-op property** to keep old `mlir.expect`
  lines passing. Rejected by C24's invariant: an unknown or deleted name
  is an error, so a stale line fails where it stands.
- **Keep `tests/idr/isolate` by running Emit's symbol form through a
  no-op.** Rejected by Delete: the region forms are no longer parseable
  (C22, C02), so the fixtures cannot be written.

## Acceptance
- `python3 proposals/0004-compile-time/check-units.py
  foreign/idr/lib/Transforms/Expect/*.cpp` reports no failure in a unit
  of this lane that is not caused by a missing declaration of C01, C02,
  C08, C11 or C15 (each named in the handoff); the six new units report
  "not in the typecheck build".
- `grep -rn 'getCloneAttr\|getInstanceAttr\|References\|copiedFrom'
  foreign/idr/lib/Transforms/Expect` finds nothing.
- `grep -rlE 'idr\.program|break[_]last|idr-simplify|idr-inline[^d]|idr-specialize|idr-round-facts|dump-dir'
  tests/idr` finds nothing; neither directory `tests/idr/in-bounds` nor
  `tests/idr/isolate` exists.
- For every `tests/idr/<d>/<n>.mlir`, `<d>/<n>/run` exists and
  `<d>/<n>/expected` has exactly one `RUN k: ok` line per `RUN:` line
  (a trailing `\` joins two).
- A search of `tests/idr/**/*.mlir` finds no split-input chunk with two
  public `idr.func` and no bodiless `idr.func` outside a fixture whose
  expected diagnostic is that refusal.
- On the owner's machine: `make test-idr` green; every `NEEDS-ACCEPTANCE`
  fixture checked and its line removed.

## Stop and return
Return when the Expect units match C24, every fixture is rewritten, moved
or deleted as Implement says, and the new fixtures exist. Report without
stopping: each contract operand a fixture or unit needed and did not find
(C01's syntax, C07's and C09's action tags, C11's `structurable`, C15's
`copies` and pass name, C08's `inlineSize`, C23's fused location), each
by file and line; every `NEEDS-ACCEPTANCE` file; the build-list lines for
the coordinator.
