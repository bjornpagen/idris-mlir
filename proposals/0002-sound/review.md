<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Adversarial review of packet 0002-sound

Reviewer: independent read-only pass at HEAD `47f97059`. Nothing was built or
executed except two read-only runs: `llvm-tblgen` (pinned, already built) on a
four-line TableGen file, and `validate.py` / a throwaway ownership script in
`/tmp/rev`. Every criticism below cites a path and line or gives a schedule.
"Not recomputed" marks a number I did not verify.

## 1. Are the eighteen lanes concurrent? No: three groups wait on a sibling's shape.

The write sets are disjoint (claim 2), but disjoint files are not independent
files. Where a lane's inputs are names or types another lane has not yet
written, the packet fixes them in prose only.

**1a. I -> T, Q (§4.6) is not concurrent.** §4.6 says `Request.base` "becomes that
index", `ConId` becomes `MkConId (dataId : DataId) (index : Fin arity)`, and
`TS.symbols`, the loops table, Emit's tables are "keyed by those identities".
No Idris signature is given: not what `n` of `Fin n` is (the context size is a
runtime value, so `Request`, `TS`, `Ctx` become indexed or hold an existential,
changing every signature in `State.idr`), not what `arity` is in a record with
no parameter, not the name of the function that prints a `ConId` from the
context (today `Show ConId` is `c.name`, `Ids.idr:~80`, with no context).
Concrete breakages the moment I lands, all in files I does not own:

- `Translate/Cases.idr:496` (T) builds `MkConId d (shortName cn)` and looks it
  up in `st.cons`; `ConId` has a different constructor after I.
- `Translate/Keys.idr:806,810` (Q) reads and writes `TS.symbols` with a
  `String` key (`lookup symbol (!(get TState)).symbols`,
  `symbols $= insert symbol link`). `TS` is `State.idr:225`, I's.
- `Frontend/Finite.idr:126-128,157` (Q) uses `r.base` as a `String`
  (`"... " ++ r.base`, `Request.base : String`, `State.idr:100`) and `r.owner`;
  `Finite.idr:250,284` (Q) is typed over `ConId`.
- `Terms.idr`/`Cases.idr` (T) pass `ctx.owner` (a `String`) to `reject` ~25
  times.

Schedule: T and Q each typecheck against a private copy; their copy has the old
`Ids.idr`/`State.idr` (I's change has not landed) or a guessed new one. Either
their typecheck proves nothing about the integrated tree or they guess I's
signatures. F13's first alternative ("proved over F11's typed field identity")
cannot even be started: a finiteness proof over `(ConId, Nat)` needs the final
`ConId`. Its fallback ("trust kept as now") is sound and does not wait.
Prerequisite: put the actual Idris declarations (`Ids.idr` records, `Request`,
`TS` fields, the printing function's name and type) in §4.6, or serialize
I -> {T, Q}.

*Status after the lane files arrived:* `parts/lanes/I.md` fixes exactly these
declarations (`ConId` with `{arity : Nat}` and `index : Fin arity`;
`Address`-keyed tables rather than `Fin n`; `Request.owner : Shown`, which is
better than §4.6's `FnId` because an `FnId` prints the instance symbol and would
change the refusal text; `conIdOf`; `TS.symbols` and `ES.keys` kept as collision
checks, which is my D2), and `T.md` and `Q.md` quote the same text; each lane's
private copy applies the others' minimal adaptations, which is duplication, not
waiting. README §4.6 still said `Fin n` and `FnId`; I replaced it (edit 6). The
residual risk is that three lanes hold three copies of one declaration; the
coordinator's integration check must diff them.

**1b. R1 -> R2, R3 (§4.8) `prop.h` is not fixed.** §4.8 names a mechanism
(compiler-rt `FuzzedDataProvider`, splitmix64, `--seed S --case I`, swarm masks,
halving) but no function, type or file contract, so R2 and R3 cannot write a
call. Worse, `FuzzedDataProvider.h` is a C++ class (`class FuzzedDataProvider`,
includes `<vector>`, `<string>`, `<algorithm>`), and every program under
`tests/toolchain/` is C (`api.c`, `rc.c`, `fuzz.c`, `start.c`), built by
`link_program` with `$pinned_cc` and linked with a C driver
(`tests/lib/compile.sh:40-48`). A `prop.h` that "draws through"
`FuzzedDataProvider` cannot be included from `api.c`. So either the programs
become C++ (a build change in `testutils.sh`/`compile.sh`, X3's) or `prop.h` is
a C wrapper over a C++ object file (a link step). Not decided; each of R1, R2,
R3 will decide differently.

*Status:* `R1.md` fixes `prop.h` as C++ (`.cpp` programs built by `prop_build`
with `-std=c++2c -fno-exceptions -fno-rtti`, no C++ library at link time, only
the `FuzzedDataProvider` calls that need none, which its header permits since the
unused `std::vector`/`std::string` members are never instantiated), quotes the
declarations, and `R2.md:85` quotes them again. Resolved, provided the owner
accepts C++ test programs (X3's `zones` spec change, `X3.md` C12, admits them).

**1c. K1 -> E (§4.1) is not "call the definitions idr-expect already has".**
`include/idr/Transforms/Expect.h` exports only `lookup(name)` returning
`Check = LogicalResult(*)(ModuleOp, AnalysisManager&, StringRef argument)`,
`names`, `named`, `callees`, `cycles`. A property takes an *expected value* as
text (`crash-sites=@f:3`, `effects=@f:io+crash`, `quantities-kept=...`), not a
before/after pair. The helpers a snapshot needs (`crashes(op, symbols)` in
`CrashSites.cpp:23`, `keyOf`, `bindsProved`, `quantityOfBinder` in
`Quantities.cpp`) are in anonymous namespaces and E (who owns the files) is not
told to export them; E's own obligation (F21: "a failing fixture or is
deleted") may delete or rename a property while K1 depends on it. Only
`folds-balanced` (a global leak counter) is reusable as stated. *Correction to this paragraph after reading `Expect.h` past line 120:* every
property is exported by name (`quantitiesKept`, `crashSites`, `foldsBalanced`,
`functionsOf`, `names`), and `quantities-kept=<file>` is a before/after
relation (the file is the baseline), so K1's design (print the module before the
pass to a temporary file, call `quantitiesKept` with it, call `crashSites` with
`@f:0` for functions whose effects lacked `crash`) is sound. What stays true: the
helpers are private, and E may delete a property; `K1.md` and `E.md` bind E to
keep the five. Resolved by the lanes.

**1d. §4.4 verdict, frontend half: nothing to wait for, and nothing to write.**
`Frontend/Driver.idr:216-223` already is `Accepted < Refused < Internal`
(`statusOfAll`: any internal -> `ExitFailure 1`). The only change is the
driver's, G's. "I writes the frontend's half" is an empty obligation, and the
F08 row now correctly names G alone. Fine, but see disagreement D1.

**1e. K2 and K3 overlap by obligation despite disjoint files.** F04 (K2) says
idr-optimize's "inner steps" become actions; F03 (K3) says "every other
optimization pass". The inner steps' code is in K3's directories:
`lib/Transforms/Identity/Identity.cpp` (idr-identity) and
`lib/Transforms/Effects/Constants.cpp` (idr-constants) are K3's, while
`PureCalls.cpp` and `Contify.cpp` (which contains idr-contify, a separate pass
with its own `InlinerInterface`) are in K2's `Optimize/`. `include/idr/Transforms/Inline.h`,
`Identity.h`, `Narrow.h` ... are in no lane (see claim 2). So "tag each inner
step" has no single owner. Prerequisite: K2 owns the tag names; K3 wraps
inner-step code it owns with them, or move the four inner passes' files to K2.

## 2. Are the write sets disjoint? Exactly yes; completely, no.

Method: expand `ownership.json` (globs, excludes) against `git ls-files`
(`/tmp/rev/own.py`). Result: **no file has two owners** (the overlap check is
sound, and agrees with `validate.py`). But the packet's own claim is that the
tree is covered, and it is not:

**Unowned, but needed.** No lane (not even the coordinator) owns
`foreign/idr/{include,lib}/idr/{Analysis,Conversion,Support,Target}/**`
(11+18+4+3 headers, 13+6+31+4+6 sources), `foreign/idr/include/idr/Transforms/*.h`
except `Optimize.h`/`Expect.h`/`Contracts.h` (17 headers: `Inline.h`, `Narrow.h`,
`Specialize.h` ...), `foreign/idr/tools/idris-mlir.cpp`, `tools/**` (dialects.sh,
bootstrap.sh), `tests/{upstream,runner,templates,upstream-idris}/**`,
`upstream/**`.

Consequences:

- **F02 (F's verifier) has no legal implementation.** Body effects are computed
  by `bodyOf`/`componentEffects` in `lib/Analysis/Effects.cpp` (unowned;
  `Effects.h` says "diverge unless Idris proved its function total; crash where
  an op may crash; IO where it forges a world or a parameter may hold one"). The
  verifier lives in `IdrIR` (F's `lib/IR/Verify/Program.cpp`), and `IdrAnalysis`
  links `IdrIR` (`lib/Analysis/CMakeLists.txt`: `LINK_LIBS PUBLIC IdrIR`), so IR
  cannot call Analysis (cycle). F must either write a second copy of the
  effect-of-a-body rule (AGENTS.md "one thing, one representation": the copy
  drifts, and then I3 is checked against the wrong rule) or move `bodyOf` into
  `lib/IR` and have `lib/Analysis/Effects.cpp` call it, which is outside every
  write set. Prerequisite: give `foreign/idr/{include,lib}/idr/Analysis/Effects.*`
  to F, with the instruction to move the rule down.
- **F14 (P) has cross-lane consequences the packet does not list.** `scalar_end`
  appears in `runtime/idris_rt.h:460` (R3), `tests/toolchain/runtime-api/api.c:406-407`
  (R3; deleting the definition in `runtime/Strings/Scalars.cpp:131` breaks this link
  if R3 still calls it), `tests/idr/fold/string-offsets.mlir:35-42` and
  `tests/idr/lower/llvm-facts.mlir:36,67` (X1), the generated
  `compiler/src/IdrisMLIR/Dialect/Idr.idr` (I's prefix), `HANDOFF.md`
  (coordinator). A P that deletes the op in ODS leaves X1's fixtures failing to
  parse. Edit applied: README F14 row now lists them.
- **Generated modules.** `compiler/src/IdrisMLIR/{Dialect,Syntax}/*.idr` are
  generated by `tools/dialects.sh` and fingerprinted over "the records
  mlir-tblgen reads from the dialect's ODS **and the generator's source**"
  (`tools/dialects.sh:101`: `cat records $generator_source | cksum`;
  `generator_source=foreign/idr/tools/idris-mlir-tblgen.cpp`). So F (ODS), P
  (`IdrStringOps.td`) and K2 (`idris-mlir-tblgen.cpp`, any edit) each stale all
  fourteen generated modules, and `tests/spec/dialects-current` fails until one
  regeneration after the last of them. By prefix the modules are I's
  (`compiler/src/IdrisMLIR/**`, not excluded), but I cannot regenerate until F,
  P, K2 are final, and `common.md` told F and P to run `make typecheck-dialects`
  in the shared tree, which writes those files while I edits nearby. The
  orchestrator already regenerates them. Edit applied: they go to the coordinator,
  I excludes them, `common.md` says lanes regenerate only on a private copy.
  Independently, K2's `-gen-pass-roles` is avoidable (claim 7).
- **`tools/policies.txt` (X3) vs T, Q, I.** `tests/spec/no-fuel` requires every
  `policies.txt` line to still be "in its file" (`policies.txt:4-5`). It lists
  `covering term/suspend/delayed/letIn/applyOver/bindHeld/application/headStep`
  (Terms.idr), `translateInstance/translateIOProgram` (Programs.idr), seven in
  Cases.idr (T), `Finite.idr: assert_total (passes (union known ...))` (Q), and
  `Program.idr`/`Driver.idr` coverings (I). Each lane removes some of these; X3,
  running at the same time, cannot know which. Either X3's `no-fuel` fails on a
  stale line, or X3 deletes a line whose `covering` is still in place. Edit
  applied: `tools/policies.txt` is the coordinator's, applied from lanes'
  handoffs, like `PINS.md`.
- **`runtime-prepared`.** F20 lists `runtime-prepared` among "specs [that]
  transcribe their findings" for X3. The directory is `tests/toolchain/runtime-prepared/`
  (R3's, not in `tests/spec/`); X3 cannot write it. Moreover its `run` consumes
  the runtime-api programs by path (`api=$root/tests/toolchain/runtime-api`) and
  its `expected` repeats their line structure ("api: the same output ... rc: ...
  rc leak: ... rc crash: ..."). So any change by R1/R2/R3 to `runtime-api`
  programs changes a file R3 owns. See D4.
- **F16's two deleted snapshots live in different owners' trees.**
  `tests/toolchain/runtime-api/**` (including `expected-operations`, `api.c`,
  `rc.c`, `run`, `expected`) is in R3's complement set; F16's owner is R1 and its
  deleter-of-record is nobody (R1's writes are `tests/toolchain/{lib,runtime-bigs,runtime-text}`).
  `api.c` prints bigs, strings and doubles in one file (R1's and R2's families),
  while `rc.c` (the counting checks) is R3's F17 work, and `run` runs both. A file
  that three lanes must change and one lane owns is not concurrent; D4.
- **Specs that pin option lists.** `tests/spec/no-behaviour-options/run` scans
  every `cl::opt` of `idris-mlir`, `idris-mlir-opt`, `idris-mlir-reduce` against
  a `kept` list. K1's `--idr-contracts` (`idris-mlir-opt`) and G's
  `--report` (`idris-mlir`) fail it until X3 adds them, and `no-behaviour-options`'s
  comment ("idris-mlir-opt keeps upstream's counter, where experiments live")
  needs the contracts named. X3's inputs are "§2" only; the names are fixed in §4
  so X3 can act, if its dispatch says so (check at lane arrival below).

## 3. Findings F01-F21 at HEAD

Verified by reading (not running).

| ID | Verdict | Evidence |
|---|---|---|
| F01 | real but overstated | `tests/lib/properties.sh:13-56` checks `quantities-kept` after **each dumped pipeline step** (`quantities_kept` loops `step_dumps`), i.e. already per pass, on every compiled program. What is new in K1 is: on the `idris-mlir-opt` fixtures, with no baseline file, and with failure naming the pass. "only on whole e2e compilations, never at the pass that drops one" should read "only on e2e compilations, per dumped step". |
| F02 | real | `FuncOp::verify` (`lib/IR/Func/Func.cpp:105-114`) checks only the empty body and the default form of `effects`; `verifyRegions` -> `verify::function` checks no effect. `tests/idr/canon/facts.mlir:36` states `@applies` with `idr.apply` of an unknown closure and declared `crash, diverge` (so see claim 6). |
| F03 | real | `perform<` at `Specialize.cpp:386` (two tags) and `Optimize/Component.cpp:229` (one). Missing from §4.2/§5: upstream already makes every pattern application an action (`mlir/lib/Rewrite/PatternApplicator.cpp:197`, tag `apply-pattern`) and every pass execution one (`PassExecutionAction`, `mlir/include/mlir/Pass/Pass.h:505`, tag `pass-execution`); see claim 7. |
| F04 | real | `Optimize.h:233-239` `InnerCounts` has `identityCalls, pureErased, pureMerged, redirected, constants`; no canonicalizer or CSE count. |
| F05 | real | `Passes.td` has 25 `def ...: Pass<...>`; no role. **The snippet in §4.2 does not compile**: `class IdrPass<string arg, string anchor, string role> : Pass<arg, anchor> { string role = role; }` gives `error: Recursion / self-assignment forbidden` under the pinned `llvm-tblgen` (run on `/tmp/rev/t.td`). Renaming the parameter works. Edit applied. |
| F06 | real at the source level, test claim unverified | `OpsCon.cpp:146-150` accepts `isOwned(value.getType()) && view(value.getType()) == expected`. `view` (`Grades.cpp:86-90`, changed in bfdcac70 after the check was written in 1e1a3827) returns `q<many, borrow, !idr.str>` for an owned `!idr.str`, and field types are stored exactly as parsed (`DataBody.cpp:176-210`, `Types.cpp:199`), so `expected` is plain `!idr.str`; `q<many,borrow,..> != !idr.str`. `tests/idr/ownership/consumed-effects.mlir:20-30` (`idr.con !idr.own<!P> @P(%s : !idr.own<!idr.str>)`) is therefore refused, unless a normalization I did not find exists. The same commit edited that fixture, so the author believed it passed. Needs one run to settle; the fix (compare at the value's own grade) is right. |
| F07 | real | `tools/idris-mlir-reduce.cpp:20-35` registers no reduction patterns and does not use `idr/Support/Stack.h`; `tests/idr/verify/reduce-regions.mlir` header describes the stuck reduction. `DialectReductionPatternInterface` exists at the pin (`mlir/include/mlir/Reducer/`). |
| F08 | real, but a reversal of documented intent | `Run.cpp:63-68`: "A refusal decides the verdict whatever else was reported: the program is what the compiler does not take." `enum class Verdict { Clean, Internal, Rejected }` with `std::max` at `:238` is deliberate. The frontend `statusOfAll` is the reverse. Which is right is a product decision, D1. |
| F09 | real | `Run.cpp:203-215` builds `handoff` with exactly the frontend's dialects. |
| F10 | not recomputed | no box exists for the rules named; plausible. |
| F11 | partly wrong | See D2: `TS.symbols : SortedMap String (Link Form)` (`State.idr:225`) is a *collision guard*: `Keys.idr:806-808` raises `internal ("two instances on the symbol ...")` when two links print to one symbol. The counterexample "two definitions whose printed names collide would share a table row" is the case the table detects. Rekeying it by identities removes the guard while the printed symbol still goes to MLIR as a symbol (and `InstanceKey`'s `Lossy` print exists because prints do collide). The check must stay; only the string-keyed *lookups of things by name* are worth typing. |
| F12 | real | `covering` counts: Terms 8, Programs 2, Cases 10 (grep), 20 lines in `tools/policies.txt:38-47` etc. |
| F13 | real | `Finite.idr:295`, `policies.txt` line for it. |
| F14 | real | consequences listed in claim 2. |
| F15 | real | `Fuzz.idr:83`, `Sem.idr:66`, `TwoLevels.idr:59`, `Fuzz.idr:95` all as cited; `TInt` appears first in `intTys` and again as the weight-list head (`Fuzz.idr:58,80,302`); `tests/programs/semantics` has 72 `prim-*` directories (91 total, 19 hand-written), consistent. |
| F16 | real, owner mismatch | sizes verified (`3136`, `176000`). See claim 2. |
| F17 | partly wrong | `runtime/Start/Entry.cpp:67-80` **already names missing features**: `IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_NAME)` prints `" name"` per missing bit. The frozen message has no name because the test requires bit 63 (`start.c:42-44`), a bit no feature owns. "The message names the bit" would add output for an unassigned bit, a product choice, not a bug (D3). `idris_rt_caf_release` is called by no `tests/toolchain` program (only `tests/idr/lower/static-thunk.mlir`). |
| F18 | not recomputed | 297 `.mlir` fixtures under `tests/idr` outside `expect/`, 159 use FileCheck; the packet's 123 is a subset I could not reproduce. |
| F19 | not recomputed except | 24 `mlir.check` files (verified: 24). |
| F20 | real | `tools/compile.sh:42` `--num-threads="$ncpu"`; 358 `expected` files start with `compile: exit 0` (the packet says 318; not the same count, I did not find its criterion). |
| F21 | not recomputed | 51 files in `lib/Transforms/Expect`. |

## 4. Brittle tests deleted from lists: does it delete a real contract's only check?

X1 and X2 can implement deletion from lists. The danger is the converse: the
list contains tests whose op text *is* the contract. Concrete cases found:

1. **`tests/idr/lower/llvm-facts.mlir`** (`FileCheck` of LLVM attributes and
   `call range(i32 0, 1114112) i32 @idris_rt_str_scalar_at`). This is the only
   test that lowered signatures carry `nonnull`, `align 8`, `dereferenceable(8)`
   and `llvm.range` facts, and that runtime-call results carry the op's range
   (`grep "range(i" tests` finds only this file). A wrong `range` is a
   miscompile, not a style issue; the attributes are exactly the artifact. The
   file is FileCheck on text but the text is the contract. A list-based cull
   of "FileCheck on a transformed module" deletes it. Keep, or state the
   facts check once (e.g. an `idr-expect` property) *before* deleting.
2. **`tests/programs/partial/lambda-terminates/mlir.check`** (and four more
   `mlir.check` files that mention `total`: `data/shapes`, `eval/dead-static`,
   `eval/static-evaluation`, `interfaces/interface-superclass`). Under §2's
   "a brittle check in an otherwise good test is deleted from it" and "nothing is
   transliterated into a property", the frontend's *providing `total` on a
   lambda's function* loses its only test (`idr-expect`'s `proved=` property,
   `Expect/Proved.cpp:25`, is the existing mechanism but no program test uses
   it). F's new §4.3 rule says `total` comes only from the frontend, so this is
   the contract the new rule rests on.
3. **`tests/programs/partial/partial-divergent-call/mlir.check`**: `call @Main.spin(`
   remaining after idr-optimize is the check that "a closed call runs at run
   time" (AGENTS.md) rather than being folded. Without it a compile-time fold
   of a diverging call would be caught only by the harness timeout, as a hang
   rather than a failed assertion; that is weaker but arguably adequate.
4. **`tests/idr/fold/string-offsets.mlir`**: dies with F14's op (not a loss).
5. **The dialect round trip.** F18 says `--verify-roundtrip` replaces the
   fixtures that "checked nothing else" but the `tests/idr/syntax` and `asm`
   fixtures check *printing* contracts (the one place text is the contract).
   If X1 deletes by pattern, the printer of `#idr.con`, `!idr.data` and
   `idr.func` loses its specification. `--verify-roundtrip` checks print-parse
   agreement, not that the printed form is the documented one.

Prerequisite: X1 and X2 are given a "text is the contract" keep-list (these
cases first) or a rule: a test whose only assertion states a fact that no other
check states is kept until that fact is stated by a contract. As written (§2:
"deleted, never restated") it is not implementable without deleting items 1-2.

## 5. §4.1 contracts: sound relations?

Four problems with the statement as written; the first makes the instrumentation
inert for most of the pipeline.

**5a. The anchor is never the module for the idr passes.** `buildPipeline`
(`lib/Transforms/Pipeline.cpp`) nests everything under `pm.nest<idr::ProgramOp>()`
and `program.nest<idr::FuncOp>()`. `runBeforePass(pass, op)` is called with the
pass's anchor op (`Pass.cpp:600`), so `op` is an `idr.program` or an `idr.func`
for every pass but `idr-target`, `idr-lower`, `idr-entry`, `idr-returned-arguments`
and `idr-tail-calls`. "When `op` is the module, record a Snapshot" skips all of
them. Function-anchored passes (`idr-canonicalize`, CSE, `idr-structure-loops`,
`idr-tail-loops`) run in parallel on the pool, so `runBeforePass`/`runAfterPass`
fire concurrently on worker threads, each with its own function; a snapshot of
"per function, by symbol, the module's fold balance" read from a worker races
with siblings mutating. Fix (applied): snapshot the anchor op's own subtree;
store per anchor with a mutex; cross-function relations only for program-anchored
passes.

**5b. `PassInstrumentation` cannot fail a pass.** `runAfterPass` returns void;
an `emitError` there does not change the pass manager's result, so
`idris-mlir-opt` exits 0 unless the instrumentation records the failure and the
tool turns it into the status after `MlirOptMain` returns (K1 owns the tool, so
it can, but the packet does not say). A fixture that uses `-verify-diagnostics`
sees the error; one that uses exit status does not.

**5c. The relations reject correct passes.** Counter-passes at HEAD:

- *quantities-kept as "no `!idr.lin` lost, multiset of (grade, type)"*:
  `idr-defunctionalize` turns `!idr.lin<!idr.fn<..>>` into `!idr.lin<sum>`
  (types change); `idr-inline`/`idr-optimize`'s case-of-known-constructor
  removes a `con` and its `match` and with them a linear field binder;
  `idr-pure-calls` erases a call whose linear result is dropped by its only
  user; `idr-lower` ends the dialect. A multiset of `(grade, type)` per function
  rejects all of them. The existing definition (`Quantities.cpp:1-24`) is
  different and correct: a *binder* (function parameter or match-bound field),
  identified by location, keeps its quantity; a binder a pass makes has no
  baseline; stage ends at `idr-lower`. The packet says both "multiset" and
  "idr-expect's definitions, called". They are not the same relation. State
  the binder-keyed one, per quantity (grade is allowed to change, e.g. idr-rc),
  up to `idr-lower`.
- *effects-not-widened*: functions a pass creates (idr-defunctionalize's force
  and dispatch functions, specialization clones, contify) carry no `effects`,
  i.e. everything (`IdrOps.td:93-112`), until `idr-effects` solves them; a clone
  compared "by origin" to a solved original looks widened. `idr-effects` itself
  moves entries from everything to narrow, and a pass after it that
  legitimately *adds* an effect to a function (it must, e.g. lowering `idr.str`
  ops to runtime calls, or an inliner's callee with `crash` into a caller that
  by construction already included it) is correct to widen. Compare only
  functions that have an origin *and* a solved entry on both sides, within the
  first-order stages (`first`, `owned`), and treat "no entry" as top.
- *crash-sites-not-added* as a **count per function**: `idr-inline` of a callee
  with a guard into a caller adds a crash site to the caller (0 -> 1) while the
  program's behaviour is the same; loop versioning (`idr-narrow`,
  `idr-narrow-lanes`) and specialization duplicate a guard. The existing
  property is "exactly n places for each copy of @f, before = after lowering"
  (`CrashSites.cpp:1-12`), a different relation. State it as: the set of crash
  causes (`MayCrashOpInterface::getCrashCause`, used by `bodyOf` in
  `Analysis/Effects.cpp`) reachable from each surviving function through
  `idr.call` does not grow; deleting a function or guard shrinks it; compare by
  origin and by cause, not by site count.
- *folds-balanced*: correct as a global post-condition (`Folds.cpp`), fine.
- *functions a pass deletes*: `symbol-dce`, `remove-dead-values` (deletes
  parameters and results!) are in the pipeline. A binder removed because nothing
  reads it loses a *quantity-one* parameter? `RemoveDeadValues` may remove a
  linear parameter only if unused, which linearity forbids; so the contract
  should flag it, and does (that is the point), but only if the relation is
  per binder, not per multiset.

§4.1 was rewritten concurrently by the packet's author to the same substance
(program/module anchors only, per-binder quantities, `crashSites @f:0`, no
comparison of created functions, `signalPassFailure`); my own edit of that
section was superseded and is not in the list below. `K1.md` is consistent with
it. One residue: a *lying* fixture (declared effects narrower than the body)
makes `effects-not-widened` fire against a correct `idr-effects` (it widens the
lie); F's verifier now rejects such input first, so the order verifier ->
contract matters, and K1's no-false-positive acceptance ("every dialect fixture
passes exactly as without") holds only after X1's A10 repairs.

## 6. §4.3's effects check, and circularity with idr-effects

The rule as written: for each function with a declared `effects`, body ops
plus callees' declared effects are contained in it; a call to a function with
no `effects` counts as everything.

- **Stage.** At `stage(higher)` (before idr-defunctionalize) a function's
  `idr.apply`/`idr.force` runs labels no verifier knows, and the pass that
  solves effects (`Effects.h`: "Once the program is first-order ...") has not
  run. `tests/idr/canon/facts.mlir:36` (stage higher) declares `@applies`
  with `crash, diverge` and body `idr.apply %f(%x)`; whatever the verifier
  counts for an apply (everything: rejects, since `io` is missing; nothing:
  accepts a lie), it cannot say. The rule must apply only at `first` and later
  stages, where a force is a call and an apply is a dispatch. Edit applied.
- **`diverge` is a function of `total`.** `bodyOf` adds `diverge` unless
  `fn.getTotal()` and `io` if a parameter holds the world. So "declared covers
  body" already includes: declared `none` requires `total`; a fixture with
  `effects = <none>` without `total` is invalid. Count: 38 files under
  `tests/idr` mention `effects`; `tests/idr/dedup/keep-apart.mlir:18`
  (`@A.eff ... effects = #idr.effects<none>`, no `total`) and
  `tests/idr/canon/case-of-case.mlir` shapes are candidates the new verifier
  rejects. No lane's inputs include repairing these (X1 owns them; its Consumes
  are "§2, §4.1"; E's `tests/idr/expect/**` too). Prerequisite: name the
  fixtures that become invalid (or have F state the exact verifier domain and
  X1/E repair them).
- **`total` provenance.** §4.3 says no pass sets `total` and that the verifier
  "refuses `total` on a function whose body calls one that is not". But
  `Defunctionalize/Forces.cpp:45` (`properties.setTotal(...)`) sets `total` on
  every lazy dispatch function, commenting "its own body bounds what it
  runs ... whose own termination the label's function answers for": a total
  function that calls non-total labels, by design (the call's effect
  propagates the callee's `diverge`). The proposed check rejects every program
  with a lazy sum whose label is partial. So `total` means "this body does not
  diverge by itself", and the callee check must be dropped, or the dispatch
  rule restated. Edit applied.
- **`no_inline` "from idr-optimize's capped callees"**: no pass sets `no_inline`
  at HEAD (grep `no_inline|noInline|setNoInline`: only readers; `Inliner`
  and `Analysis/Inline.cpp`), and 0008 deleted the caps. Edit applied
  (struck).
- **Circularity.** Not circular in the data: `idr-effects` computes entries
  from bodies, the verifier checks entries cover bodies; the least solution
  satisfies it, a mutual recursion `f <-> g` gets the same union on both
  (`componentEffects`). But two copies of the rule is the danger: if the
  verifier re-derives `own` it will be checked against itself. And running the
  check inside a pass's own pipeline position matters: `idr-canonicalize`'s
  pre-solve calls "may do anything" (Pipeline.cpp comment), so declared
  entries are present only after `idr-effects`; the verifier must treat absence
  as top. Single source: see claim 2 (IR/Analysis layering).

## 7. Library first (§5)

Nothing is told to hand-roll what the pinned tree provides in the lanes I could
read; but the table misses two mechanisms that remove work, and one mechanism
is mis-assigned.

- **`PassExecutionAction` and `ApplyPatternAction` already exist** (claim 3
  F03 row). `-mlir-debug-counter=pass-execution-skip=N` skips any whole pass,
  upstream passes included, and `apply-pattern-skip=N` skips any rewrite of
  every greedy driver (idr-canonicalize, CSE's canonicalization). K3's
  hand-wrapping of pattern-driven transforms in `perform<Tag>` duplicates
  `apply-pattern`; the tags are needed only for the non-pattern transforms
  (clone, inline call, node turn). §5 should say so. I2's "every transform
  of a pass of role `optimization`" also cannot reach the upstream
  optimization passes of the pipeline (`remove-dead-values`, `symbol-dce`,
  `cse`): they are not `IdrPass`; they have no per-transform action at the pin
  (grep `executeAction` shows only Pass, ApplyPattern, GreedyIteration,
  Conversion, WalkAndApply); only whole-pass skipping is available. Edit
  applied to §4.2.
- **`-gen-pass-roles` is a hand-rolled generator** in the one source file
  (`idris-mlir-tblgen.cpp`) whose text fingerprints every generated Idris
  module (claim 2). `llvm-tblgen -dump-json` over `Passes.td` already emits every
  record with its fields, role included. `IdrPassRoles.txt` is one `jq` away,
  with no edit to `idris-mlir-tblgen.cpp`, no stale modules, no K2 write to a
  shared tool. Not applied (a design choice), listed in D5.
- **`--report` statistics**: `Pass::Statistic` with
  `PassManager::enableStatistics` already produces the data; a loop over
  `OpPassManager::getPasses()` and `Pass::getStatistics()` is the way (not text
  parsing of `-mlir-pass-statistics`); the packet does not say which.
- **Googletest (O2)**: `third-party/unittest/CMakeLists.txt` builds with
  `add_llvm_library(llvm_gtest ...)` (needs `AddLLVM` and LLVM's own variables)
  and installs only with `LLVM_INSTALL_GTEST` (which `llvm/CMakeLists.txt:927`
  gates). Our CMake is out of tree against `find_package(MLIR)`
  (`foreign/idr/CMakeLists.txt:15`). "No LLVM rebuild" is plausible via
  `add_subdirectory(<llvm>/third-party/unittest)` but B cannot test it here and
  nothing in `tools/bootstrap.sh` mentions gtest. Unverified; flag to the
  owner.
- Hand-rolled but small and not provided upstream: swarm masks, halving
  shrinker, per-class counts, splitmix64 (a C++26 `std::mt19937_64` is the
  deterministic standard engine, usable from C++ tests).

## I2 (optional transforms are skippable): the role assignment

`README §1` I2 says skipping any one transform of an `optimization` pass
"leaves a valid module whose behaviour is unchanged". Skipping `idr-accumulate`,
`idr-trmc` or `idr-tail-loops` leaves a self- or cyclic-recursive function as
deep recursion; `README.md:45` guarantees tail calls ("a call in tail position
around a cycle of calls is a guaranteed tail call") and `tests/programs/partial/{deep-recursion,
tail-loop-deep,stack-exhausted}` pin stack depth as behaviour. Those passes must
be `lowering`, not `optimization`, or I2 must say "result for runs within the
stack". Likewise `idr-columns`, `idr-structure-loops`, `idr-bufferize` are
required for array lowering to succeed (the later passes refuse records in
tensors). Edit applied to §4.2 (a sentence); the classification itself is K2's
and the owner's, D6.

## Lane review (all eighteen lane files present at 15:34)

Read in full: K1, F, I, R1 (declarations), and the decision sections of K2, K3, E, G, B, P, R3, X1,
X3, N; skimmed T, Q, R2, X2. The lane drafters evidently read this review's
earlier findings: most of claims 1-6 are already answered in the lane texts.
What I found in them:

- **Good, verified against source:** F.md's "`total` contradiction" and the
  four sites of F06 (`ConOp::verify`, `verifyElement`, `verifyEnd`,
  `DupOp::verify`; `consumed-effects.mlir` `@plain` stores a *borrow* into a
  field, which every version of the rule refuses, so that fixture fails at
  HEAD too: F06 is confirmed beyond my source reading). G.md finds an
  unsynchronized write of `verdict` from the diagnostic handler
  (`Run.cpp:238`), which is real (handlers run from worker threads).
  K2.md settles the K2/K3 split of inner steps by file (my 1e). X1.md keeps
  `asm/`, `syntax/`, `verify/` (my claim 4 item 5) and tags the other
  doubtful rows `[D8]` for the owner. R3 deletes `expected-operations` because
  the file is in its set (my D4 is a routing fix, not an ownership fix, and
  works: R1 and R2 name the `api.c` sections in their handoffs for R3).
- **Defects found in lane files (fixed in place):** F.md header gave F
  `lib/Analysis/Effects.cpp` while its NOT TO DO forbade editing it and its hub
  request asked the coordinator to; two lines edited (edit 7).
- **Open, not mine to decide:**
  - `X1.md:27` and `X2.md:31` delete the `[D8]` rows by default ("deleted like
    the others"), which contradicts my claim-4 recommendation (keep
    `llvm-facts`, `lambda-terminates`, `data/shapes`, `eval/dead-static`,
    `interfaces/interface-superclass`, `partial-divergent-call`). The
    orchestrator must strike them or rule before dispatch, as the lane text says.
  - `R3.md` makes the runtime name an unowned CPU bit ("lacks bit 63"): a
    runtime message change (D3).
  - `R3.md:62` says `runtime-prepared/expected` "cannot pass on macOS"; the
    directory has an `expected.macos`, so the per-target lists exist; the
    restatement as an allowlist is still right by AGENTS.md ("per-target cases
    elsewhere are bugs") but the stated reason is wrong.
  - `E.md` adds a new property `folded=@f` that N consumes by text
    (`N.md:192,210`); both define it identically; fine, but the coordinator
    must diff the two definitions.
  - `X1.md:27` counts 133 module FileChecks, README F18 says 123; one is stale.
  - `B.md` compiles googletest's sources from the pinned tree into the unit
    programs (`IDR_GTEST`), which sidesteps my §7 worry about
    `LLVM_INSTALL_GTEST`; not run here.
  - Lane texts of T and Q were skimmed only for §4.6 consistency (consistent).

## Disagreements between packet and reviewer (owner decides)

| # | Packet says | Reviewer says | Packet evidence | Reviewer evidence |
|---|---|---|---|---|
| D1 | I4: Internal wins over refused (driver and frontend) | The driver's order is deliberate: a refusal means "the program is what the compiler does not take"; an internal error that follows a refusal can be a cascade of it. Reversing changes the exit code of refused programs from 3 to 1 whenever a later pass trips, and is a product decision absent from §8 | F08 | `Run.cpp:63-68` comment; `Frontend/Driver.idr:216-223` |
| D2 | F11: typed identities remove "two definitions whose printed names collide share a row" | `TS.symbols` is the collision *guard*; the printed symbol still reaches MLIR; keep the string check, type the rest | §3 F11 | `State.idr:225`, `Keys.idr:806-810`, `Ids.idr` `KeyPrint` `Lossy` |
| D3 | F17: runtime-start's message "names no feature"; make it name the bit | It already names features; the test uses an unowned bit. Unknown bits printing text is a product choice | `start.c:44`, `Entry.cpp:67-80` | same lines; `IDRIS_RT_CPU_NAME` macro |
| D4 (routing settled by R1/R2/R3 handoffs; kept for the record) | F16: R1 owns the deletion of `runtime-api/expected-operations`; R2 writes strings/doubles programs; `runtime-prepared` is X3's | `runtime-api/**` and `runtime-prepared/**` are R3's by ownership; one file (`api.c`) is three lanes' work; `runtime-prepared`'s `run` and `expected` consume it | §3 F16, F20, §6 | `ownership.json` R1/R2/R3/X3; `runtime-prepared/run` (`api=$root/tests/toolchain/runtime-api`) |
| D5 | K2 writes `-gen-pass-roles` into `idris-mlir-tblgen.cpp` | `llvm-tblgen -dump-json` provides the data; the edit stales 14 generated modules | §4.2 | `tools/dialects.sh:101`; upstream tool |
| D6 (K2.md accepts "same behaviour but for the stack and the heap"; owner confirms) | I2: every optimization is skippable, behaviour unchanged | tail-position passes and array-lowering passes are not optional | §1 I2 | `README.md:45`; `tests/programs/partial/*`; Pipeline.cpp comments |
| D7 (settled: README §4.3 and F.md now state the source's meaning) | §4.3: `total` only from the frontend; verifier refuses `total` over a non-total callee | `Forces.cpp:45` sets `total`; `total` is the body's own termination, callee divergence propagates through the effects | §4.3 | `Forces.cpp:25-50`; `Effects.cpp` `bodyOf` |
| D8 | §2: tests deleted, never restated | Items 1-2 of claim 4 are the only checks of a real contract | §2 | claim 4 |

## Packet edits made

Each re-read just before editing; the packet's author edited the same files
concurrently, so several of my first edits were superseded and are omitted.

1. `README.md` §4.2: the `IdrPass` snippet's template parameter renamed (the
   pinned `llvm-tblgen` rejects `string role = role;` with `Recursion /
   self-assignment forbidden`, run on `/tmp/rev/t.td`). The author's rewrite of
   §4.2 now carries the renamed form (`passRole`).
2. `README.md` §3 rows F01, F11, F14, F17: the evidence corrected (F01: per
   dumped step; F11: `TS.symbols` is a guard and stays; F14: the other lanes'
   files that name `scalar_end`; F17: bit 63 is unowned, the runtime already
   prints names).
3. `README.md` §6: `tools/policies.txt` named a coordinator hub (T, Q, I edit it
   by handoff), the F row names `include/idr/Analysis/Effects.h` and
   `lib/Analysis/Effects.cpp`, the X3 row names the two flags it adds to the
   `no-behaviour-options` spec.
4. `ownership.json`: `tools/policies.txt` moved from X3 to the coordinator
   (`tests/spec/no-fuel` wants each line still in its file; T, Q and I cannot
   tell X3 which they removed); `Analysis/Effects.{h,cpp}` to F (my duplicate
   entries were removed; the author's remain).
5. `parts/common.md`: lanes run `make typecheck-tblgen` but not
   `make typecheck-dialects`, which rewrites the coordinator's generated Idris
   modules from every lane's ODS at once.
6. `README.md` §4.6: replaced the vague prose (`Fin n`, `FnId` owner) by the
   settled declarations of `I.md` (Address, `Shown`, `conIdOf`, guards kept).
7. `parts/lanes/F.md`: two lines made consistent with F owning
   `lib/Analysis/Effects.cpp`.

Not edited, listed as decisions: D1, D3, D4 (partly settled), D5, D6, D7 (settled
by F.md and README §4.3), D8.

## Verdict

executable after named concrete prerequisites: (1) the owner rules D1 (G.md and I.md implement `Accepted < Refused < Internal`, reversing the driver's documented "a refusal decides the verdict"), and rules or strikes the `[D8]` rows of X1 and X2 before dispatch (they currently delete the only check of the LLVM-facts, `total`-provenance and no-compile-time-fold contracts); (2) the coordinator treats integration as a sequenced step, not a merge: one `tools/dialects.sh generate` after F, P and K2 are final (K2's tblgen edit stales every generated Idris module), `tools/policies.txt` from T, Q and I handoffs, and a diff of the three copies of the §4.6 declarations (I, T, Q) and the two definitions of `folded=@f` (E, N); (3) X1's A10 fixture repairs land with F's verifier, since K1's no-false-positive acceptance depends on them; (4) the owner accepts C++ property programs (R1's `prop.h`) and an unrun googletest-from-source build (B), neither of which can be checked on this machine.
