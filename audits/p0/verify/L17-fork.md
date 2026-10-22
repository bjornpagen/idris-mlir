<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L17: the fork of Idris's compiler, and its elaborator

Lane L17 of the P0 verification swarm. HEAD `e96bb991` at the start
(2026-10-21T21:31Z) and at the finish; the tree dirty with the
coordinator's uncommitted P0 work, read as it is. Nothing was built, run
or changed but this file.

**Scope.** D12 (a strict subset, never a contradiction), D44 as it
reaches the fork (proposal 0003's fork items), D45 and the three rulings
that replaced its mechanisms while this lane worked (D53, the path rule;
D54, a growth through unknowns postponed; D55, the ambiguity count
deleted and the tuple settled by representation), and AGENTS.md's rules
for the fork. The frontend's own code is L16's; the elaborator-counts
design (`audits/p0/design/elaborator-counts.md`, read in full, not
edited) is the research agent's, and this file verifies it rather than
redoing it.

**Grounds.** *read* (path:line at HEAD; fork paths are under
`compiler/idris/src/` unless written whole; frontend paths under
`compiler/src/IdrisMLIR/`), *measured* (a command run here: `grep`,
`wc`, `diff`), *recalled*, *conjecture*, *decision* (a ruling Dn, a
coordinator decision Cn, or a G draft DP-nn).

## 1. Verification

Each row: the ruling or claim, the verdict, the class of the observation
(defect confirmed in the source; structural incompleteness; integration
mismatch; unverified behaviour; optional simplification), and the
evidence.

### 1.1 D45 and its replacements (D53, D54, D55)

| claim | verdict | class | evidence |
| --- | --- | --- | --- |
| D45: "each count is replaced by a search that ends by construction, and its pragma is refused by the parser", as `upstream/fork-totality-depth` did | **holds with a correction** | structural incompleteness | Two counts are named; the fork holds five entries into the automatic search, each with its own depth: `%auto_implicit_depth` 50 (`TTImp/Elab/App.idr:272-273`, `Core/Options.idr:222`), `%search` 50 fixed by the parser (`Idris/Parser.idr:146-147`), a `with` clause's auto argument 500 (`TTImp/WithClause.idr:156`), an implementation's parent constraints 500 (`Idris/Elab/Implementation.idr:260`), and the raw TTImp parser's `%search` 1000 (`TTImp/Parser.idr:61`), reached only through `processTTImpFile` (`TTImp/ProcessDecls.idr:199-221`), which nothing calls (measured: `grep -rn processTTImpFile` finds only its definition). D53 names all five; §2.1 lists every other count. |
| D45: `%ambiguity_depth`, 3, `Ambiguity.idr:326-334` | **holds** | read | `checkAmbigDepth` throws `AmbiguityTooDeep` when `length (ambigTries info) > getAmbigLimit` (`TTImp/Elab/Ambiguity.idr:326-334`); `ambigTries` grows only in `addAmbig` (`:343-348`); default 3 (`Core/Options.idr:222`). |
| D45: the size rule ends the search, refusing "a few programs" | **refuted** (so ruled by D53) | defect in the design | The prelude has `Either (Uninhabited a) (Uninhabited b) => Uninhabited (a, b)` (`third_party/Idris2/libs/prelude/Prelude/Types.idr:299-302`, read): its premise is larger than its head. Every data constructor is a hint for its type (`TTImp/ProcessData.idr:561-562`, read), so `S : Nat -> Nat` is a hint whose premise is not smaller, and a rule on implementations alone leaves constructors, `%hint` functions and parent projections unbounded (`Core/Context.idr:1725-1752`, read). |
| D45: ambiguity "bounded by what it has already tried, as the totality fix is" | **refuted** (so ruled by D55) | defect in the design | The totality memo is sound because a comparison is a pure function of its two subterms (`Core/Termination/CallGraph.idr:181-206`, read). A candidate's elaboration reads and writes the unification state, the delayed elaborators, the elaboration state, the metadata and the context, which `successful` saves and restores around each candidate (`TTImp/Elab/Check.idr:550-600`, read), so a memo keyed by what was tried is unsound; and none is needed, since each candidate elaborates strict subterms of the source (`Ambiguity.idr:109-160`, read). |
| D53: the path rule ends every search with no count | **holds with two corrections** | structural incompleteness | (a) Kruskal's theorem needs the labels of `⌊·⌋` to be well-quasi-ordered; a goal can hold `TType fc u`, whose universe name is a fresh definition per `uniVar` (`TTImp/Elab/Check.idr:410-416`, `Core/TT/Term.idr:124`, read), so `⌊·⌋` must collapse every universe to one symbol, as it collapses unknowns. (b) The rule as recorded refuses finite searches the stock Idris answers (the design's own `Rose Nat` case, `elaborator-counts.md:534-537`); a finer order that still ends by construction removes that class (§4 I1, *owner*). |
| D53: "convertible, that step fails, as upstream's cycle check does" | **holds with a correction** | defect confirmed in the source | Upstream's cycle check signals the repeat as `throw (InternalError "Cycle in search")` (`Core/AutoSearch.idr:508-517`, read), an error that means "the compiler's bug" to the frontend's driver (`Frontend/Driver.idr:232-236`, read), caught as an ordinary failure by every combinator (`AutoSearch.idr:130-194`, `Core/UnifyState.idr:551-567`). D53's typed outcome (the design's `Grown` case, `elaborator-counts.md:513-523`) must carry the repeat too, so no internal error stands for a search failure (§4 I8). |
| D53: a growth is a refusal, "never dropped as a failed branch so a sibling wins" | **holds** | read | Every combinator catches every `Error` (`tryUnify`, `handleUnify`: `Core/UnifyState.idr:551-567`; `successful` in the search: `AutoSearch.idr:130-153`; in the elaborator: `Check.idr:550-612`, which re-throws only `abandon`'s errors). The growth must therefore be a value of the search's result type, not an `Error`, as the design says. |
| D54: a growth holding an unknown is postponed "as a determining-argument failure is (`Unify.idr:1450-1455`)" and refused at the last chance | **holds with a correction** | defect confirmed in the source | The handler cited postpones a determining-argument failure in *every* mode, the last chance included: `DeterminingArg ... => ... pure False` before the `case smode of LastChance => throw err` branch (`Core/Unify.idr:1449-1462`, read). Copied as cited, a growth would never be refused by its own rule but left as an unsolved hole, refused later with a message that names no growth. The growth's handler must throw its own refusal at `LastChance` (§4 I5). |
| D55: the ambiguity count only refused; deleting it ends every resolution | **holds** | read | §1.2 of the design, re-read: candidates elaborate strict subterms; a delayed resolution is retried with its captured `ElabInfo` on the same term (`TTImp/Elab/Delayed.idr:80-117`); `retryDelayed` loops only while a round resolves a hole for good (`Delayed.idr:262-328`). |
| D55: the count also disambiguates | **holds** (it is why the deletion is a change of answers, not only of refusals) | read | A candidate failing with `AmbiguityTooDeep` is an ordinary failed candidate (`Check.idr:600-612`), so a sibling can win alone; `depthError` reports the depth only when all fail (`Check.idr:649-668`). |
| D55: "`(a, b)` is settled by the sort of its expected type when known", giving upstream's elaboration | **holds** for a known sort | read | Upstream already prunes by the expected type's head: `couldBe` keeps `Pair` only under `NType` and `MkPair` only under an `NTCon` that can match `Pair` (`Ambiguity.idr:260-296`, `mightMatch` `:216-240`); under any other known head both are pruned, both are tried, both fail (`:322-324`). Settling one reading by the sort reproduces each case. The unknown sort is the open part; §4 I3 drafts it. |
| D55: "its design in the fork is owed" | **open; drafted here** | structural incompleteness | §4 I3 (coordinator item). |

### 1.2 D44 as it reaches the fork (proposal 0003's fork items)

| claim | verdict | class | evidence |
| --- | --- | --- | --- |
| C1: a `let`'s type is dropped by the TTC and guessed back, and a guess refuses valid programs | **holds at HEAD** | defect confirmed in the source | Written as a comment, `-- ; toBuf ty` (`Core/TTC.idr:611-612`; `PLet` `:617-618`; `PVTy` `:619-620`); read back as `Erased emptyFC Placeholder` (`:480-482, 491-495`). The frontend's guess `valueType` (`Frontend/Translate/Terms.idr:261-280`) and the refusal on a miss (`:402`, rule `ValueType`). |
| C2: a match's scrutinee type `scTy` is dropped | **holds at HEAD**; the fact is total in memory | defect confirmed in the source | Not written (`TTC.idr:830-831`), read back as `Erased` (`:775`). In memory it always exists: the case builder takes it from a `Known` column type or fails with `CaseCompile ... UnknownType` (`Core/Case/CaseBuilder.idr:1099-1102`), so keeping it introduces no `Maybe`. |
| A leaf's clause index is dropped | **holds at HEAD** | defect confirmed in the source | Written without the index (`TTC.idr:832-833`), read back as `STerm 0` (`:777`); in memory `STerm (index pid) rhs` (`CaseBuilder.idr:1057`). |
| B1: a block's parent is printed text | **holds with a correction** | defect confirmed in the source | `CaseBlock String Int` and `WithBlock String Int` (`Core/Name.idr:45-46`). The `Int` is not an ordinal within the parent: it is the session's machine-name counter, shared with every `MN` (`genCaseName`, `genWithName`: `Core/UnifyState.idr:193-209`), so an ordinal needs a counter per parent. And base's reflection API holds the same constructor as upstream's (`Core/Reflect.idr:441-482`), so the typed parent meets a seam at reflection (§4 I9). |
| `WhyErased` is dropped | **holds at HEAD** | defect confirmed in the source | Tag 10 for every `Erased` (`TTC.idr:694`), read back `Placeholder` (`:583`). |
| The run-time tree is built and dropped | **holds at HEAD** | defect confirmed in the source | Read back `Unmatched ""` (`TTC.idr:1207`); built by `mkRunTime` for every definition (`TTImp/ProcessDef.idr:722-843, 1025`). |
| 17 C2 / synthesis D §2.2: one runtime signature "from `eraseArgs`, plus the quantities of the remaining `Pi` binders" | **holds with a correction** | integration mismatch | Two sources for one fact (erased positions from `eraseArgs`, the rest from binders) can disagree: a function's `eraseArgs` is computed once, at its declaration (`TTImp/ProcessType.idr:178-186`), by `nf` of its type (`TTImp/Elab/Utils.idr:56-61`); a type that reaches its Π spine through a type-level definition declared before and defined after is stuck then, so `eraseArgs` is short (*conjecture* from the order of the code; the reproducer is in §4 I4). The one source is the quantity on each binder (QTT's own fact); §4 I4. |
| 17 FB-16: read `refersToRuntime` instead of re-walking | **refuted under DP-76** | integration mismatch | `refersToRuntimeM` is produced only by `calcRefs True` over the run-time tree inside `compileRunTime` (`ProcessDef.idr:687-707, 838-843`); G's DP-76 stops building that tree, so the field loses its producer. What survives is `refersTo`, from the compile-time tree (`calcRefs False`, `:1011`), kept in the TTC (`TTC.idr:1322`). |
| 17 FB-18: `paramPos` misses parameters behind a definition | **holds at HEAD** | defect confirmed in the source | `getConPs` sees only syntactic `Pi` and `Let` (`Core/Context/Data.idr:73-81`). It now gates D48 too (§2.7). |
| 17 FB-22: `ZeroOneOmega` hides its constructors | **holds at HEAD** | read | `export data ZeroOneOmega = Rig0 \| Rig1 \| RigW` (`Algebra/ZeroOneOmega.idr:10-11`). |

### 1.3 D12: a strict subset, never a contradiction (the fork's half)

| claim | verdict | class | evidence |
| --- | --- | --- | --- |
| Every pragma the fork accepts means what it means upstream | **holds with three exceptions** | defect confirmed in the source | The fork parses the pin's pragmas minus `totality_depth` (measured: the `decoratedPragma fname "..."` sets of `Idris/Parser.idr` in both trees differ by that one). Exceptions: the count pragmas (§2.3, refused under D53, D55); `%search_timeout`, stored and read by nothing (`Core/Context.idr:2261-2263`; the timer has no starter, `startTimer` uncalled: measured by grep); `%foreign_impl`, stored in the TTC and read by nothing (`Core/Options.idr:183, 242-243`, `Core/Binary.idr:63-165`), against AGENTS.md's "never ignore the pragma" for the foreign world. |
| Every flag the fork accepts means what it means upstream | **holds; two flags select a second behaviour** | defect confirmed in the source | `-Xcase-tree-opt` switches the split choice (`Core/Case/CaseBuilder.idr:828-838`) and reaches only the run-time phase, which is dropped; `--debug-elab-check` turns on a second conversion check (`Core/LinearCheck.idr:301-306`). Both are "two implementations behind an option" (AGENTS.md). The frontend's driver accepts none of the fork's flags itself (`Frontend/Driver.idr:142-180`, read); a package's `opts` reaches them through `processPackageOpts`. |
| Every default is upstream's | **holds** | read | `defaultElab = MkElabDirectives True True CoveringOnly 3 50 25 True` and `defaultSession` equal the pin's but for the removed totality limit and the deleted back-end fields (measured: `diff third_party/Idris2/src/Core/Options.idr compiler/idris/src/Core/Options.idr`). |
| `--total` means what it means upstream | **holds** | read | The fork keeps it (`Idris/CommandLine.idr:194`); the frontend's driver refuses it as an unknown option (`Frontend/Driver.idr:173-174`), a narrowing, never a second meaning. |

### 1.4 AGENTS.md's rules for the fork, and C8

| claim | verdict | class | evidence |
| --- | --- | --- | --- |
| Only `IdrisMLIR.Frontend.*` imports the fork; the fork imports no `IdrisMLIR.*` | **holds** | measured | `grep -rln -E '^import (public )?(Core\|Libraries\|Idris\|TTImp\|Parser\|Algebra\|Protocol\|IdrisPaths)(\.\| \|$)' compiler/src harness libs \| grep -v /Frontend/` prints nothing; `grep -rn 'import.*IdrisMLIR' compiler/idris/src` prints nothing. |
| `third_party/Idris2` unmodified | **holds** | read | `git status` lists no change under it. |
| A fork bug is fixed in the fork, recorded in PINS.md with `upstream/<bug>/pull-request.diff` | **holds as practice; the record is unchecked** | structural incompleteness | Seven `upstream/fork-*` directories and nine numbered Idris directories carry diffs; `tests/upstream-patches/run` checks only README sections and `*.patch` files (read), so no check applies an Idris `pull-request.diff` to the pin. A diff that no longer applies is a stale record the re-sync reads (§2.5, §4 I10). |
| No count bounds a recursion of the fork's own (fork README "Ours") | **holds for its own code; the elaborator's counts are §2.1** | read | `fuel` and `reduceLimit` gone (diff of `Core/Value.idr`), `loopsTerminate` total, `normaliseTypes` follows each name once (`PINS.md` idris-fork "totality"). |
| C8: the fork's Windows branches are a suspected bug outside P0, fixed on main | **holds with a correction** | defect confirmed in the source | Larger than the branches. `Libraries/Utils/Path.idr` reads every path with Windows's grammar on all four targets: `'\\'` separates (`:156-161`), a leading `x:` is a disk volume (`:169-174`), and the names end at the first `':'` or `'?'` (`:182-194`). So `"/tmp/a:b" </> "Main.idr"` is `"/tmp/a/Main.idr"` (derived by reading `lexPath`, `parseBodies` and `(</>)` at `:378`); the frontend resolves module paths through it (`Frontend/Resolve.idr:130`). §4 I2. |

### 1.5 The elaborator-counts design's open conjectures this lane can settle

- *"The case-function size limit may decide which arguments are found
  erased"* (`elaborator-counts.md:630-634`): **settled, it does not.**
  `findErased` normalises its input itself (`nf defs Env.empty tm`,
  `TTImp/Elab/Utils.idr:56-61`) and walks the head-normal Π spine through
  closures (`:38-53`), so the same erased positions come out whether
  `normaliseSizeLimit` returned the normal form or the input
  (`TTImp/Elab/Case.idr:208-209`). What the limit decides is the *form of
  the case function's stored type* (read): representation, not erasure.
- *"Whether the frontend admits elaborator reflection"*
  (`elaborator-counts.md:617-624`): **settled, it does not.** The profile
  refuses every pragma in a user module but `default`, `hide`, `unhide`
  and `logging` (`Frontend/Profile.idr:140-141, 176-178`), so `%runElab`,
  `%macro` and `%language ElabReflection` are refused; base runs no
  script at top level (its `%runElab` occurrences are inside `|||`
  comments: `Deriving/*.idr:6, 284-418`, read). The reflected `ISearch`
  depth is unreachable in an admitted program (§4 I7).
- *`%nf_metavar_threshold` "only changes the work"* (17 FB-42): **holds
  for the verdict.** The occurs check normalises on failure
  (`Core/Unify.idr:368-384`) and the shrink re-quotes in full on failure
  (`:888-896`), so the threshold changes the stored solution's form, never
  whether the hole is solved.

## 2. Boundaries

### 2.1 Every count, depth and budget in the fork

The acceptance: no count left unnamed. Columns: what it bounds, what
running out does, and how it ends without one (the end state under the
rulings).

| count | site | running out | end state |
| --- | --- | --- | --- |
| `%ambiguity_depth`, 3 | `TTImp/Elab/Ambiguity.idr:326-334`; `Core/Options.idr:105, 222`; `Core/Context.idr:2246-2248, 2292-2296` | refuses (`AmbiguityTooDeep`), or lets a sibling win | **D55**: deleted with everything that serves it; nothing replaces it (each candidate elaborates strict subterms); the tuple's cost goes by representation (§4 I3). |
| `%auto_implicit_depth`, 50 | `App.idr:272-273`; `Options.idr:106`; `Context.idr:2251-2253, 2299-2303` | `CantSolveGoal` at `searchIfHole`'s `Z` clause (`Core/AutoSearch.idr:103-104`), an ordinary failure | **D53**: no depth; the path rule. |
| `%search`, 50 | `Idris/Parser.idr:146-147` | as above | **D53**: `%search` keeps its meaning and loses its 50. |
| a `with` clause's auto argument, 500 | `TTImp/WithClause.idr:156` | as above | **D53**. |
| an implementation's parent constraints, 500 | `Idris/Elab/Implementation.idr:260` | as above | **D53**. |
| the raw TTImp parser's `%search`, 1000 | `TTImp/Parser.idr:61` | as above (unreachable: `processTTImpFile` has no caller) | **D53**, and the dead entry goes (§4 I7). |
| a search hole's stored depth | `BySearch rig maxdepth def` (`Core/Context/Context.idr:118`), written in the TTC (`Core/TTC.idr:1192-1193, 1224-1226`), shown back as `ISearch fc d` (`TTImp/Unelab.idr:230`) | carries the depth into retries (`Core/Unify.idr:1439-1441`) | **D53**: `BySearch` without a depth; a TTC format change (`ttcVersion`). |
| the reflected `ISearch` depth | base's `ISearch : FC -> (depth : Nat) -> TTImp` (`third_party/Idris2/libs/base/Language/Reflection/TTImp.idr:66`); `TTImp/Reflect.idr:161-164, 556-559` | a script's own depth | Base's type stays upstream's. Reify drops the number; reflecting a depth-less search into a script refuses the script, since any depth would be invented and no admitted program runs a script (§1.5; §4 I7). |
| `%nf_metavar_threshold`, 25 | `Core/Unify.idr:870-873` | quotes in full instead (`catch`) | Allowed by AGENTS.md as written ("may stop at a budget ... never rejects"): the verdict is unchanged (§1.5). Kept, named; its signal becomes typed (§4 I8). |
| the auto implicit's quote depth, 10 | `App.idr:268-269` | quotes without unfolding instead | Kept, the same class; the search normalises its goal itself (`AutoSearch.idr:532`). |
| a pattern variable's type quote depth, 5 | `TTImp/Elab/ImplicitBind.idr:112-115` | normalises fully instead | Kept, the same class (not in 17 or the design). |
| a hole type's normalisation depth, 10 | `TTImp/Elab.idr:76-79` | `normaliseHoles` instead | Kept, the same class. |
| a case function's type, 10 | `TTImp/Elab/Case.idr:208` | the type as built (`Core/Normalise.idr:88-95`) | Kept, the same class; erasure is unaffected (§1.5). |
| a solved hole's "simple" test, depths 6 and 3 | `Core/Unify.idr:473-493` | the solution is not marked `alwaysReduce`, so `argHolesOnly` evaluation leaves it as a hole application (`Core/Normalise/Eval.idr:551-560`) | Kept, the same class: it decides the form of the checked term the TTC stores, never acceptance (not in 17 or the design). |
| `%transform`'s rounds, 5 | `Core/Transform.idr:146-162` | stops rewriting | Dead work: only `mkRunTime` applies transforms (`ProcessDef.idr:822`); goes with DP-76. |
| `%spec`'s reduction limits | `(n, 1)` per name and `65536` per reachable name (`TTImp/PartialEval.idr:238, 292-297`) | none: the evaluator's `reduceLimit` is gone, so `applySpecialise` ignores the list (`:723-731`), as the pin's does (`third_party/Idris2/src/TTImp/PartialEval.idr:710-718`) | Dead data in a dead pass; `TTImp/PartialEval.idr` is reached only from `mkRunTime` (`ProcessDef.idr:29, 823`, measured by grep), so the module goes whole with DP-76. |
| `delayDepth` | `TTImp/Elab/Check.idr:148, 176`; `Delayed.idr:42-50, 280` | nothing: counted, only logged ("if it gets too deep ... fail quicker", read by nothing: measured) | Dead state; deleted with `deeper` (§4 I7). |
| the search timer and `%search_timeout`, 1000 ms | `Core/Options.idr:140`; `Core/Context.idr:2553-2584`; the check at every unfolding, `Core/Normalise/Eval.idr:302`; `Timeout` (`Core/Core.idr:198, 406, 525`) | never: `startTimer` has no caller | Dead, and paid at every unfolding (D10 at the compiler's run time): deleted, the pragma refused by the parser (§4 I7). |
| `--alt-error-count`, 1 | `Core/Options.idr:152`; `Idris/Error.idr:737` | shows fewer alternative errors | Text for a human; not a budget on acceptance. Kept. |
| the "did you mean" distance, `length / 3` | `Core/Context.idr:1155-1160` | suggests fewer names | Text for a human. Kept. |
| `exactlyOne'`'s new-guess count | `Check.idr:550-600, 638-643` | prefers the candidate that added no postponed constraint | Not a budget: a preference that is part of upstream's overload resolution. Kept (D55's draft reproduces it, §4 I3). |
| `branchDepth` | `Core/Context.idr:61, 144-160, 262-279`; `Core/Context/Context.idr:407-410` | none: the nesting of speculative branches, writes staged until the outer commit | Structural, essential. Kept. |
| loops until no progress | `retryDelayed` (`Delayed.idr:324-328`), `solveConstraints` (`Core/Unify.idr:1516-1534`) | none: they stop when a round solves nothing | Not counts. Each round solves a hole for good and the delays a retry makes are for its own subterms (read), so they end. |

### 2.2 The fork-side facts 0003 needs in the TTC, each with its single reader

Each keeps exactly Idris's fact, in Idris's type, round-tripping, with
`ttcVersion` bumped (`Core/Binary.idr`), and deletes its reconstruction
in the same change (fork README "What a TTC keeps", `compiler/idris/README.md:531-568`).

| fact | representation kept | writer (fork) | single reader (frontend, L16) | deletes |
| --- | --- | --- | --- | --- |
| C1 a `let`'s, `PLet`'s, `PVTy`'s type | the binder's `Term` | `encodeBinder` tags 1, 4, 5 (`TTC.idr:611-620`) and their decoders (`:480-495`) | the translation of a `Let` (`Frontend/Translate/Terms.idr`), which gives `Term.Let` its binder's type (`Term.idr:175-177`) | `valueType` (`Terms.idr:261-280`), the `ValueType` refusal of an unknown value type (`:402`), Emit's synthesis of the let's type |
| C2 a match's scrutinee type | `scTy : Term vars` of `Case` | `encodeTree` tag 0 (`TTC.idr:830-831`), `decodeTree` (`:768-775`) | the match translation (`Frontend/Translate/Cases.idr`), normalising it once per match to its data instance | `instanceOf`'s inference and its internal error (`Cases.idr:247-289`), `siblings` (`:155-176`), `coversAll`'s re-derivation (`:180-185`) |
| a leaf's clause index | `STerm Int` | `encodeTree` tag 1 (`TTC.idr:832-833`), decoder (`:776-777`) | with DP-76 the frontend's tree reader (`Frontend/Translate/Cases.idr`) | `Translate/Forced.idr`'s `covers`, alias merge and per-instance `argToPat` re-run |
| B1 a block's parent | a resolved parent `Name`, the block's kind, its ordinal within the parent (§4 I9) | `Core/Name.idr:45-46`, `genCaseName`, `genWithName` (`Core/UnifyState.idr:193-209`), the name encoder | one structural `rootOf` over the typed parent (`Frontend/Translate/Closed.idr:437`), used by keys | `outermost` (`Closed.idr:419-427`), `rootOf`'s climb by text, `keyOrigin`'s search of the context (`Keys.idr:258-289`) |
| `WhyErased` | the reason (`Placeholder`, `Impossible`, `Dotted t`) | `encodeTerm` (`TTC.idr:694`), decoder (`:583`) | the frontend's dotted-pattern reading, once its own marker has moved to a probe (17 FB-04) | the overload of `Erased _ Impossible` as the frontend's marker |
| B3 imports' locations; pragma uses | each import's `FC` and `ModuleIdent`; each pragma use (kind, `FC`) | the TTC's import list and the parser's pragma records | the profile (L16) | `Profile.imports`' scan with `words`, the pragma half of `checkPragmas`' re-lex |
| B6 a module's package; the main source | per loaded module, its package's name and version, recorded where the session adds the package directory | the session (`addPkgDir`), not the TTC | `Resolve` (L16) | `homeOf`'s parse of TTC paths, `elaboratedFile` |

Not kept, by design: the run-time tree (DP-76, *decision* draft), and
`refersToRuntimeM` with it (§1.2).

### 2.3 D12's audit: pragmas, flags, defaults

Every pragma the fork's parser accepts (`Idris/Parser.idr`, measured),
its meaning against the pin's, and its end state:

| pragma | meaning against upstream | end state |
| --- | --- | --- |
| `%default`, `%hide`, `%unhide`, `%logging` | upstream's code; the only pragmas a user module may write (`Profile.idr:141`) | kept |
| `%ambiguity_depth` | a count deciding acceptance | refused by the parser (D55) |
| `%auto_implicit_depth` | a count deciding acceptance | refused by the parser (D53) |
| `%search` | "find this by search", with a hidden 50 | kept, depth-less (D53) |
| `%nf_metavar_threshold` | a budget that changes a solution's form, never the verdict (§1.5) | kept (AGENTS.md's "may stop at a budget") |
| `%search_timeout` | in batch elaboration, nothing at the pin too (its one reader is the REPL's expression search, deleted) | refused by the parser with the timer (coordinator, §4 I7) |
| `%foreign_impl` | adds a back end's spec; read by nothing here | refused by the parser (AGENTS.md: never ignore a foreign pragma; no package uses it, measured) |
| `%totality_depth` | a count | refused (`upstream/fork-totality-depth`) |
| `%transform` | a rewrite the programmer asserts is an equality, applied by the optimizer | accepted; applied nowhere after DP-76; the registry's `Faster` hooks answer what prelude's transforms target (17 FB-07) |
| `%spec` | a request to specialise | accepted; its only effect, `specArgs`, is read by nothing after DP-76; this compiler specialises every instance anyway |
| `%inline`, `%noinline`, `%tcinline` | hints; `%tcinline` reaches the type checker's evaluator, upstream's code | kept |
| `%hint`, `%globalhint`, `%defaulthint` | search hints | kept; every one under D53's path rule |
| `%foreign`, `%extern`, `%export`, `%nomangle`, `%builtin`, `%unsafe`, `%deprecate`, `%allow_overloads`, `%name`, `%pair`, `%rewrite`, the literal pragmas, `%start`, `%auto_lazy`, `%unbound_implicits`, `%prefix_record_projections`, `%language`, `%runElab`, `%macro` | upstream's code; refused in user modules by the profile; used by prelude, base or the fork itself as measured (`%foreign` 12/144/2, `%extern` 3/10, `%runElab` in base's comments only) | kept |

Flags (`Idris/CommandLine.idr:172-275`): the fork keeps upstream's
meaning for each it keeps; `-Xcase-tree-opt` and `--debug-elab-check`
select a second behaviour and go (§4 I7). Defaults: upstream's (§1.3).
**No contradiction remains** once the count pragmas, `%search_timeout`,
`%foreign_impl` and the two flags go; every other difference is a
refusal (the profile's in user modules, the parser's for removed
pragmas).

### 2.4 Per-target code in the fork

- **`Libraries/Utils/Path.idr`**, the only module of the fork that reads
  the host (`import System.Info`, `:16`; measured: no other `System.Info`
  in `compiler/idris/src`): `dirSeparator` and `pathSeparator` by
  `isWindows` (`:28-34`), `isAbsolute'` by `isWindows` (`:237-245`),
  `pathLookup`'s executable extensions by `isWindows` (`:585`), and the
  Windows grammar applied on every target (`Volume` with `UNC` and
  `Disk`, `:36-48`; `'\\'` a separator, `':'` and `'?'` ending a path,
  `:150-194`; `Show Volume`, `:113-115`). `pathLookup`, `dirSeparator` and
  `pathSeparator` have no caller outside the module (measured). Under
  idris-mlir, `isWindows` is base's `os \`elem\` [...]`
  (`third_party/Idris2/libs/base/System/Info.idr:22-23`), a string test at
  run time of the target, which the target's entry already knows (D10).
- **The TTC's integers** go through `Data.Buffer`'s `setInt`
  (`Core/Binary/Prims.idr:127-154`); all four targets are little-endian, so
  a TTC is the same bytes on each, provided the runtime's buffer
  primitive states its byte order (unverified; the seam is L11's).
- `defaultDirs`' `"/usr/local"` (`Core/Options.idr:195`) and `pathLookup`'s
  `"/usr/bin:/usr/local/bin"` (`Path.idr:586`) are POSIX conventions, not
  branches; the driver requires `--prefix` (`Frontend/Driver.idr:213-214`),
  and `pathLookup` is dead.

### 2.5 The re-sync plan's shape

What each fork change carries so that a re-sync (fork README
`:585-604`; `tools/extract-idris.sh diff OLD NEW | git apply --3way`) can
decide it:

1. **Its code** in `compiler/idris/src`, ours.
2. **A README line** under the section that names its kind ("What was
   deleted", "Honest code", "Total where the frontend calls it",
   "Rewritten so that this compiler can compile it", "Ours", "What a TTC
   keeps", "Bugs in upstream code found here").
3. **When it changes what a program means or whether it is accepted** (a
   bug fixed, a count removed, a pragma refused, a TTC fact kept, the path
   model): `upstream/fork-<name>/` with its README (reproduce, expected,
   cause, the fix, why there is no patch, testing at the pin, upstreaming
   plan: nothing sent), its reproducers, and `pull-request.diff` against
   the pin with the upstream test it would change; a `PINS.md` entry
   (symptom, sites, workaround, retire, upstream); a test under `tests/`
   with a `near/` program.
4. **Its retirement**, one of two kinds: a bug fix retires when the
   re-sync brings upstream's own fix (take upstream's code, delete the
   directory, the entry and the test); a deliberate deviation (D53, D55,
   the TTC facts, the path model) never retires by upstream's fix and is
   carried forward, its diff rebased onto the new pin.
5. **A TTC format change** bumps `ttcVersion` in the same change.

Gaps: no check applies the carried Idris diffs to the pin (§1.4; §4 I10);
`PINS.md` and `upstream/` name one change two ways in places
(`interface-body-dropped` beside `fork-interface-body`), which the
README's "or the name it gives" tolerates. The cost the rulings add,
stated plainly: D25 moves Idris 2's pin about weekly, so the fork
re-syncs about weekly; each deviation is a conflict surface, and D44's
0010 A0 (interned names and the term arena *in the fork*,
`proposals/0010-array-interpreter.md:339`) turns the evaluator's re-sync
from a merge into a re-implementation. That is A0's cost, accepted by
D44, not a reason here to change it.

### 2.6 Constructor provenance

| fact | constructed by | who alone may |
| --- | --- | --- |
| a binder's quantity (`RigCount` on `Lam`, `Let`, `Pi`, `PVar`, `PLet`, `PVTy`) | the elaborator, checked by `Core.LinearCheck` | Idris's elaborator |
| a definition's quantity (`multiplicity`) | elaboration | the elaborator |
| erased positions (`eraseArgs`) | `findErased` over the type's normal form (`TTImp/Elab/Utils.idr:56-75`), at declaration for functions, after data processing for constructors, at creation for case blocks | the fork; the frontend reads binders, not this projection (§4 I4) |
| a type constructor's parameters (`TCon parampos`) | `paramPos` (`Core/Context/Data.idr:83-87`), on normal forms once FB-18 is fixed | the fork |
| a match's scrutinee type, a leaf's clause index | the case builder (`CaseBuilder.idr:1057, 1099-1102`) | the fork |
| a block's parent and ordinal | `genCaseName`, `genWithName`, made typed (§4 I9) | the fork |
| a growing search, a repeated goal | the search's result (D53's typed outcome, §4 I8) | `Core/AutoSearch.idr` alone |
| a refusal of a growth | `retryGuess` at the last chance (D54, §4 I5) | `Core/Unify.idr` |
| a tuple's reading | the expected type's sort, then the components (D55, §4 I3) | `TTImp/Elab/Ambiguity.idr` |
| the TTC's bytes | `Core/TTC.idr`, `Core/Binary.idr` | the fork; read only by the frontend |

### 2.7 Seams with other lanes

- **L16 (the frontend).** Each TTC fact lands with its reader's deletion
  in the same change (§2.2). The runtime signature reads binders from one
  normal form aligned to the case tree's `args` (§4 I4). Under DP-76 the
  profile and keys read `refersTo` or compute runtime references from the
  compile-time tree and the signature; they never rebuild a run-time tree
  (§1.2). The refusal of a removed pragma reaches the frontend as Idris's
  parse error, category `elaboration` (shape of
  `tests/elaboration-totality-depth-pragma/Main.idr`).
- **L04 (families, D48).** A family attribute needs the parameter and
  index split; `paramPos` today makes a parameter hidden behind a
  definition an index (FB-18), which would give every constructor a
  spurious index variable. The fork's fix is a prerequisite of D48's
  translation. The seam: `TCon parampos` on the constructors' normal
  forms; each field's quantity from the constructor type's binders.
- **L03 (the one source).** The fork may never import `IdrisMLIR.Spec.*`
  (AGENTS.md), so `RigCount` to the specification's quantity stays one
  function in the frontend (`Resolve.use`), and the registry's
  `Multiplicity` mirror stays (17 FB-24).
- **L19 (tests).** The tests named in §5 and the check of the carried
  diffs (§4 I10) write in `tests/`.
- **L11 (runtime).** The byte order of `Data.Buffer`'s integer stores
  (§2.4).

### 2.8 What the end state deletes (paths and symbols)

In the fork: `ambigLimit`, `checkAmbigDepth`, `ambigTries`, `addAmbig`,
`AmbiguityTooDeep`, `depthError`, `AmbigDepth`, `AmbigDepthPragma`,
`KwAmbiguityDepth` (D55, design §1.7's list); `autoImplicitLimit`, every
`depth` parameter of `Core/AutoSearch.idr`, `searchIfHole`'s `Z` clause,
the depth of `ISearch`, `PSearch` and `BySearch`, `AutoImplicitDepth`,
`KwAutoImplicitDepth` (D53); `abandonIfCycle`'s `InternalError` (§4 I8);
the timer (`startTimer`, `clearTimer`, `checkTimer`, `timer`,
`setSearchTimeout`, `searchTimeout`, `Timeout`, `SearchTimeout`,
`SearchTimeoutPragma`, `KwSearchTimeOut`), `delayDepth` and `deeper`,
`foreignImpl`, `addForeignImpl`, `ForeignImpl`, `ForeignImplPragma`,
`caseTreeHeuristics` and the heuristic branch of `nextIdxByScore`,
`debugElabCheck`, `processTTImpFile` (§4 I7); `mkRunTime`,
`compileRunTime`, `toCompileCase`, `canInlineCaseBlock`, `canInlineDef`,
`Core/Transform.idr`'s use in elaboration, `TTImp/PartialEval.idr` whole,
`PMDef`'s run-time tree field, `refersToRuntimeM`, `calcRefs`'s `Bool`
(DP-76, §4 I6); the commented TTC writes and their placeholder decoders
(§2.2); `Libraries/Utils/Path.idr`'s `isWindows` branches, `Volume`,
`pathLookup`, `dirSeparator`, `pathSeparator` and the `System.Info`
import (§4 I2).

### 2.9 Essential distinctions that remain

- An elaborator budget that changes the form of a stored term (§2.1's
  "kept" rows) is not a count that decides acceptance; the two classes
  stay apart, and only the second is banned.
- A repeated goal (convertible) fails that step, as upstream's cycle
  check; a growth refuses; a growth through unknowns postpones (D53,
  D54). Three outcomes, three cases of one result type.
- Quantity 1 promises the future only (Brady,
  `sources/papers/brady-2021-idris2-qtt/erasure.tex:34-39`); the fork
  never claims uniqueness, and nothing in this file adds a claim.
- Reflection's types are base's, upstream's: the fork's typed forms meet
  them at `TTImp/Reflect.idr` and `Core/Reflect.idr`, never by changing
  base.

## 3. QTT

**Where quantities enter.** The elaborator puts a `RigCount` on every
binder and on every definition, and `Core.LinearCheck` checks them
(17 §2.4). A constructor's field quantities are its type's Π binders;
a type constructor's parameters are `TCon parampos`.

**Where they are kept.** The TTC writes every binder's quantity
(`TTC.idr:609-620`), every definition's `multiplicity` (`:1320`), and,
for user names only, `eraseArgs`, `safeErase`, `inferrable`
(`:1323-1337`). A case block is a user name (`Core/Name.idr:118-123`), so
it keeps them.

**Where they are lost.** A `let`'s type (its quantity is kept) and the
reason a term is erased (`WhyErased`: a `Dotted t` holds the term an
erased position equals, which is *not* constant per instance, and the TTC
throws it away, `TTC.idr:694`); every fact of a non-user definition,
decoded as `Erased`, empty sets, `unchecked` and `linearChecked = True`
(`:1362-1364`), the "absent" placeholders the README forbids; the
run-time tree, where erasure was applied.

**Where they are read.** By the frontend, today through `Resolve.use` at
43 sites and five erasure readers (17 FB-15, FB-23); `eraseArgs` by no
one in `compiler/src` (measured: `grep -rn eraseArgs compiler/src` is
empty).

**Using them harder, at the boundary, once.**
1. *One source per position.* The quantity of a position is the binder's
   `RigCount` in the definition's type; `eraseArgs` is Idris's projection
   of the Rig0 ones over its `nf`. The frontend's one reader normalises
   the type once (it needs the normal form for types anyway) and reads
   each binder's quantity from it, aligned to the definition's case-tree
   arguments (`PMDef args`, kept, `TTC.idr:1177-1178`): a position is
   absent at Rig0, linear at Rig1, the bare type at RigW. No
   "a binder past the type's is erased" default can be written, since the
   walk is over the arguments the case tree takes (§4 I4).
2. *Matchable quantities.* `ZeroOneOmega` becomes `public export`, so a
   reader matches `Rig0 | Rig1 | RigW` instead of an `if` chain over `==`
   (FB-22); the frontend's `coreBinder` then takes the quantity of a
   runtime position, and its Rig0 internal error cannot be written
   (FB-27, L16).
3. *Erased does not mean constant.* Keeping `Dotted t` gives the frontend
   the value an erased position equals in that clause, which today it
   reconstructs per instance (17 FB-04, FB-06); it stays an erased index
   (quantity 0, no runtime value), refining the match, never a constant
   of the module.
4. *Families.* D48 reads each field's quantity from the constructor's
   type and the parameter/index split from `paramPos`; the FB-18 fix makes
   that split exact (§2.7).
5. *The search respects linearity already.* Only unrestricted locals, or
   any local at quantity 0, are usable by the search (`getUsableEnv`,
   `Core/AutoSearch.idr:201-213`); D53 adds no use of a quantity-1 binder.
6. *Facts paid at the compiler's run time.* The timer's check at every
   unfolding (§2.1), the five erasure readers and the re-normalisations
   (86 call lines, 17 FB-32) pay at compile time for facts the fork held
   once; §4 I4 and I7 delete them.

## 4. Improvements

### I1. D53's order on goals: embedding coupled at the root, constants by their own order (*owner*)

- **Evidence.** D53 compares goals by homeomorphic embedding with
  constants collapsed to their type (`proposals/0000-mlir-native.md`,
  D53; `elaborator-counts.md:477-559`). The design itself lists a finite
  search the rule refuses: `{auto t : Rose Nat}` with `MkRose : a ->
  List (Rose a) -> Rose a` reaches `List (Rose Nat)`, in which `Rose Nat`
  embeds by diving, though `Nil` answers it at once (`:534-537`).
- **Counterexamples.** (a) `Rose Nat`, above: refused; the stock Idris
  answers `MkRose Z []`. (b) `data Foo : Integer -> Type where Base : Foo
  0; Step : Foo (n - 1) -> Foo n` and `{auto p : Foo 5}`: the second goal
  is `Foo 4`; with constants collapsed, `⌊Foo 5⌋ ⊴ ⌊Foo 4⌋`, not
  convertible, no unknown: refused; the stock Idris counts down to `Base`
  (*conjecture*: not run).
- **Root cause.** The order compares more than termination needs: diving
  lets a goal embed in a goal of another type constructor, and collapsing
  integers loses an order that is itself a well-quasi-order.
- **Correction.** Compare a goal only with the earlier goals of the same
  type constructor, argument by argument, each argument by homeomorphic
  embedding; label primitive constants of a finite type by their value,
  integers by magnitude, strings by subsequence; universes as one symbol.
  Termination is kept by construction: on an endless path some type
  constructor recurs endlessly (finitely many in the context), its
  arguments are tuples of fixed arity, a finite product of well-quasi-orders
  is one (Dickson, recalled) and trees with well-quasi-ordered labels are
  one under embedding (Kruskal, recalled); so two goals of that
  constructor have every argument embedded, and the path stops. Every pair
  this order relates, D53's relates too, so it refuses a subset of what
  D53 refuses, and it tests only ancestors with the same head.
- **Deletes.** Nothing beyond D53; it narrows D53's refusals.
- **Discriminated by.** A test accepting the `Rose Nat` search and the
  `Foo 5` countdown, with `near/` programs whose hint grows (`Foo (n + 1)
  -> Foo n`; `Foo (List a) -> Foo a`), refused naming the two goals.

### I2. One POSIX path model in the fork (*coordinator*)

- **Evidence.** §1.4, §2.4: `Libraries/Utils/Path.idr` applies Windows's
  grammar on all four targets.
- **Counterexample.** `idris-mlir-front --prefix '/opt/a:b' ...`: every
  path under the prefix goes through `</>`, which reads `"/opt/a:b"` as
  `/opt/a` (`lexPath` splits at `':'`, `parseBodies` stops at a
  punctuation that is not a separator, `Path.idr:150-194`), so the TTCs
  are looked up under `/opt/a`; a directory named `a\b` is read as two
  (derived by reading; not run).
- **Root cause.** A path type made for every platform (`Volume`, two
  separators, terminators) on targets that have one grammar: a name is
  any bytes but `'/'` and NUL.
- **Correction.** `Path` is an optional root and a list of names split at
  `'/'`; `':'`, `'?'` and `'\\'` are ordinary characters; no `Volume`, no
  `isWindows`, no `System.Info`. It is a fork deviation with a reproducer
  (`upstream/fork-posix-paths/`), a `PINS.md` entry and a test, as C8
  asks, landed on main or within P0, whichever comes first.
- **Deletes.** §2.8's path symbols; the run-time `os` test under
  idris-mlir (D10).
- **Discriminated by.** A test whose package directory holds a `':'`
  and a `'\\'` in its name, checked by `--check`, refused before and
  accepted after.

### I3. D55's design in the fork: the tuple settled by sort (*coordinator*; drafted at the coordinator's request)

- **Where the alternatives are made.** The desugarer writes `(l, r)` as
  `IAlternative fc (UniqueDefault (MkPair l r)) [Pair l r, MkPair l r]`
  (`Idris/Desugar.idr:529-534`), `()` likewise over `Unit`/`MkUnit`
  (`:557-560`), and `(x ** p)` with an implicit type over `DPair`/`MkDPair`
  (`:535-545`); `checkAlternative` elaborates them
  (`TTImp/Elab/Ambiguity.idr:441-484`) through `pruneByType` and `couldBe`
  (`:260-324`), `checkDefaultDelayed` (`:350-396`) and `delayOnFailure`
  (`Delayed.idr:80-117`). A tuple of n nests n-1 such sites.
- **Root cause of the cost.** One syntax for a type former and its
  constructor becomes a generic list of candidates, each elaborated in
  full. With an unknown expected type both candidates "succeed" with
  postponed searches (a literal checked against `Type` postpones `Num
  Type`, `recoverable` being `True` for it, `Core/Unify.idr:1418-1426`), so
  `exactlyOne'` finds two successes that both added guesses, the site is
  ambiguous and delayed, and every retry re-elaborates both readings of
  every nested site (the design's measured cubic attempts and 433 s,
  `elaborator-counts.md:170-195`).
- **Representation.** A `RawImp` node for the syntax that writes a type
  and its value alike, holding the components once:
  `ITypeOrValue : FC -> Overlaid' nm -> RawImp' nm`, with
  `data Overlaid' nm = PairOf (RawImp' nm) (RawImp' nm) | UnitOf |
  DPairOf Name (RawImp' nm)`. The desugarer builds it instead of the
  three `IAlternative`s; the generic `IAlternative` stays for overloaded
  names, macros and `===`.
- **Elaboration** (`checkTypeOrValue`, in `Ambiguity.idr`): classify the
  expected type's head normal form, after `stripDelay`, into
  `data Sort = Universe | Other | Unknown`:
  - `NType`: elaborate the type reading only (`Pair l r`, components
    against `Type`; a nested `ITypeOrValue` then sees `Type`, so no level
    branches). Upstream prunes `MkPair` there (read).
  - any other known head (`NTCon`, `NPrimVal`, a Π, `NDCon`): elaborate the
    value reading only. Under `NTCon Pair` upstream prunes `Pair`; under any
    other head it prunes both, tries both, and both fail, so the verdict is
    the same (a message lists one reading instead of two).
  - `NApp` of an unknown, or `NErased`: elaborate the components *once*,
    against fresh unknowns `?A` and `?B` (exactly the value reading's
    expected types), and leave the site as a pending reading: a delayed
    elaborator with reason `Ambiguity` that on each retry re-classifies the
    expected type and does no elaboration. `Universe` then unifies `?A`
    and `?B` with `Type` and yields `Pair l' r'`; `Other` yields
    `MkPair l' r'` and unifies the expected type with `Pair ?A ?B`;
    `Unknown` stays pending, with no progress. At the last chance, the
    choice upstream makes: of the two readings' unifications, tried
    speculatively, the one that leaves no new postponed constraint wins
    alone (`exactlyOne'`'s rule, `Check.idr:638-643`); otherwise the
    default, the value reading (`UniqueDefault`).
  - Nested sites are their own pending readings, each settled by its own
    expected type, which the outer decision fixes (`?B := Type` under a
    type reading): the cost is one elaboration per component and one
    classification per site per round, linear in the tuple.
- **Exactness, the obligation.** That elaborating a component against
  `?A` and then unifying `?A` with `Type` gives the term elaborating it
  against `Type` gives is *conjecture* (a literal's `Num ?A` becomes
  `Num Type` and fails at the last chance either way; an overloaded name
  is its own delayed site, pruned when its expected type is known; the
  components' quantities are the value reading's, and the linearity check
  runs on the final term). It is discriminated by elaborating every
  definition of prelude, base, `libs/`, the fork, the frontend and
  `tests/` with the stock Idris at `%ambiguity_depth 1000` and with the
  fork, and comparing each definition's checked term (full names); any
  difference is a site the draft must reproduce. The 22-tuple under
  `printLn` is the timing bar (linear expected, *conjecture*).
- **Seams.** `TTImp/TTImp/TTC.idr` gives the node a tag (`ttcVersion`);
  `TTImp/Reflect.idr` reflects it as upstream's `IAlternative` form (base's
  `TTImp` has no such constructor) and reifies base's form as the generic
  alternative, correct and slow, unreachable in an admitted program
  (§1.5); `Idris/Resugar.idr` is unaffected (the checked term is `Pair` or
  `MkPair`).
- **Record.** One change with the count's deletion (one ruling, so no
  state between with the 433 s cost): `upstream/fork-ambiguity-depth/`
  with the design's reproducers (`elaborator-counts.md:688-700`) and an
  8-tuple and a 22-tuple under `printLn`; a `PINS.md` entry
  `ambiguity-depth`; tests: the pragma refused where written, the 8-tuple
  printed, a tuple of types under an unknown type elaborated as upstream's
  default.
- **Deletes.** §2.8's ambiguity symbols; the three tuple `IAlternative`s
  in the desugarer.

### I4. One source of a position's quantity (*coordinator*)

- **Evidence.** §1.2: `eraseArgs` is computed at the function's
  declaration (`TTImp/ProcessType.idr:178-186`); the frontend's five
  readers re-derive it with different defaults (17 FB-15).
- **Counterexample** (*conjecture*, to be run): `Spine : Type` declared;
  `g : Spine` declared; `Spine = (0 n : Nat) -> Nat -> Int` defined after;
  `g n x = x`. At `g`'s declaration `nf` of `Spine` is stuck, so
  `eraseArgs g` is empty; the frontend's `normaliseTypes` sees `(0 n)`, so
  a reader trusting `eraseArgs` gives position 0 a runtime value (a
  quantity-0 value in the module, against AGENTS.md), and one trusting
  `Forced.quantities`' default erases whatever lies past the spine.
- **Root cause.** Two derivations of one fact, one of them a projection
  frozen before the type's definitions are complete.
- **Correction.** The frontend's one signature reader takes each
  position's quantity from the binders of the one normal form it computes,
  aligned to `PMDef args` (§3 item 1), and reads `eraseArgs` nowhere. In
  the fork, `updateErasable` runs again for every definition of a module
  once the module's definitions are processed, so Idris's own readers of
  `eraseArgs` (coverage, `Core/Coverage.idr:427`; builtins,
  `TTImp/ProcessBuiltin.idr:186-202`) agree with the binders; it is a fork
  bug fix if the reproducer confirms it (`PINS.md` entry, diff, test).
- **Deletes.** The five readers and their defaults (L16); nothing in the
  fork but the stale value.
- **Discriminated by.** The reproducer above: `g`'s emitted signature has
  one runtime parameter, and `eraseArgs g = {0}` after the module.

### I5. D54 at the last chance throws its own refusal (*coordinator*)

- **Evidence.** §1.1: `retryGuess` postpones a determining-argument
  failure in every mode, `LastChance` included (`Core/Unify.idr:1449-1455`).
- **Counterexample.** A program whose `{auto p : Elem 3 xs}` has `xs`
  never fixed: under a handler copied from the determining case, the
  growth is postponed at the last chance too, and the program is refused
  later as an unsolved hole whose message names no growth.
- **Correction.** The growth's case in `retryGuess`: postpone in every
  mode but `LastChance`; at `LastChance`, throw the growth's refusal (the
  two goals and the hints between them), classified final by `recoverable`
  and `abandon`.
- **Discriminated by.** That program's refusal names the two goals.

### I6. What DP-76 deletes in the fork (*coordinator*)

- **Evidence.** The run-time tree's builder is `mkRunTime`
  (`ProcessDef.idr:722-829`), run for every definition (`:1025`); its
  products are read by nothing in the frontend (measured:
  `grep -rn 'specArgs\|PartialEval\|refersToRuntime\|safeErase' compiler/src`
  finds none) and by the fork only inside the same pass
  (`canInlineCaseBlock`, `:773`) or by dead code (`canInlineDef`, no
  caller, measured).
- **Root cause.** A second program built for back ends this fork deleted.
- **Correction.** With DP-76 (G's draft, *decision* pending fold-in):
  delete `mkRunTime`, `compileRunTime`, `toCompileCase`,
  `canInlineCaseBlock`, `canInlineDef` and `inlineSafe`; the elaboration-time
  use of `Core/Transform.idr`; `TTImp/PartialEval.idr` whole; `PMDef`'s
  run-time tree field (62 matches of `PMDef `, measured: the re-sync cost
  of the honest form, since a field with no producer would stand for
  absent); `refersToRuntimeM` with its TTC slot and `calcRefs`'s `Bool`;
  the `RunTime` phase of the case builder and with it the
  `-Xcase-tree-opt` branch. FB-45's `saved` stays: the frontend translates
  the compile-time tree as the program.
- **Discriminated by.** The fork builds; the frontend's suites are
  unchanged; the TTCs of prelude and base shrink (measure before and
  after, 17 §8).

### I7. Dead counts, state and options go (*coordinator*)

- **Evidence.** §2.1 and §2.3: `delayDepth` (counted, never read), the
  timer (never started, checked at every unfolding), `%search_timeout`,
  `%foreign_impl`, `--debug-elab-check`, `processTTImpFile` and its
  parser's `%search` 1000, the reflected `ISearch` depth.
- **Correction.** Delete each; the parser refuses `%search_timeout` and
  `%foreign_impl` as it refuses `%totality_depth`; reify drops a script's
  search depth and reflecting a depth-less search refuses the script.
- **Deletes.** §2.8's lists.
- **Discriminated by.** A test refusing each removed pragma where it is
  written, with `near/`.

### I8. Typed outcomes where errors stand for control flow (*coordinator*; the quote half *optional simplification*)

- **Evidence.** The cycle check throws `InternalError "Cycle in search"`
  (`AutoSearch.idr:516`); the size-limited quote throws
  `InternalError "Size limit exceeded"` (`Core/Normalise/Quote.idr:183-186`),
  caught by catch-alls that also swallow every genuine error of the
  normalisation (`Core/Normalise.idr:88-95`, `Core/Unify.idr:871-872`,
  `App.idr:268-269`, `ImplicitBind.idr:112-115`, `Elab.idr:78-79`).
- **Root cause.** An outcome the problem has (a repeat, a quote too deep)
  spelled as "the compiler's bug", text the frontend's driver classifies
  as exit status 1.
- **Correction.** D53's search result is one sum, `Found term | Repeated |
  Grown path` (the design's `Grown`, with the repeat beside it), passed up
  by every combinator by type; the size-limited quote returns `Quoted term
  | TooDeep`, and its callers match instead of catching.
- **Discriminated by.** No `InternalError` is constructed by the search or
  the quote (grep); a repeat inside a search still fails that step.

### I9. B1's typed parent, and reflection's seam (*coordinator*)

- **Representation.** `CaseBlock : Name -> Nat -> Name` and
  `WithBlock : Name -> Nat -> Name`: the parent's resolved full name and
  the block's ordinal within that parent, from a counter per parent in
  `UState` (saved and restored with it on backtracking, as `nextName` is).
  `prettyName` prints `"case block in " ++ prettyName parent` from it, so
  every message is upstream's.
- **Reflection.** Base's `CaseBlock : String -> Int -> Name` stays
  upstream's: reflect writes the printed parent and the ordinal; reify of a
  block name built by a script refuses the script, since a script cannot
  name a block before it exists, and no admitted program runs one (§1.5).
- **Deletes.** `outermost`, `rootOf`'s textual climb, `keyOrigin`'s
  search (L16).
- **Discriminated by.** A case block nested in a `DN`-named definition in
  a namespace gets the root and key it gets today by search, with no
  context search.

### I10. The carried diffs are checked against the pin (*coordinator*)

- **Evidence.** §1.4.
- **Correction.** `tests/upstream-patches` applies every Idris
  `pull-request.diff` to a copy of `third_party/Idris2` with `git apply
  --check`, in each series' order (50, 52, 53), as it applies the
  `*.patch` files.
- **Discriminated by.** A planted diff that does not apply makes the test
  fail (its `witness/`).

## 5. Work units

Drafts; none dispatched by this swarm. Every unit builds under both hosts
(stock Idris on Chez for stage 0, idris-mlir for stage 1), bumps
`ttcVersion` when the TTC changes, and carries §2.5's record.

| unit | exclusive write set | outcome | deletes | must not | acceptance |
| --- | --- | --- | --- | --- | --- |
| U1 POSIX paths (I2) | `compiler/idris/src/Libraries/Utils/Path.idr`, `compiler/idris/README.md`, `upstream/fork-posix-paths/`, `PINS.md` (its entry), `tests/fork-posix-paths/` | one path grammar on all four targets | §2.8's path symbols | read the host; keep any Windows form | a package directory with `':'` and `'\\'` in its name checks |
| U2 the search's bound (D53, D54, I1, I5, I8's search half) | `Core/AutoSearch.idr`, `Core/Unify.idr`, `Core/UnifyState.idr`, `Core/Context/Context.idr`, `Core/TTC.idr`, `Core/Binary.idr`, `TTImp/Elab/{App,Check,Term}.idr`, `TTImp/{TTImp,Unelab,WithClause,Parser,Reflect,Utils}.idr`, `TTImp/TTImp/{Functor,Traversals,TTC}.idr`, `Idris/{Syntax,Parser,Desugar,Resugar,Pretty,Error}.idr`, `Idris/Elab/Implementation.idr`, `Idris/Syntax/Pragmas.idr`, `Core/{Options,Context,Core}.idr` (the design's §5 sites), `upstream/fork-search-depth/`, its `PINS.md` entry, `tests/` (the design's four tests and I1's) | every search ends with no count; growth refused or postponed by D54 | every depth, `searchIfHole`'s `Z`, `%auto_implicit_depth`, `abandonIfCycle`'s internal error | let a growth be caught as a failure; invent a depth at reflection | `Elem 60` found; `Cons2`, `Loop` refused naming goals; `Rose Nat` and the `Foo 5` countdown accepted (if I1 is ruled); prelude, base, the fork and the frontend elaborate with zero firings (the design's §8 measurement first) |
| U3 overloaded names (D55, I3) | `TTImp/Elab/{Ambiguity,Check,Delayed}.idr`, `TTImp/TTImp.idr`, `TTImp/TTImp/TTC.idr`, `TTImp/Reflect.idr`, `Idris/Desugar.idr`, `Idris/{Syntax,Parser,Error}.idr`, `Idris/Syntax/Pragmas.idr`, `Core/{Core,Context,Options}.idr`, `upstream/fork-ambiguity-depth/`, its `PINS.md` entry, `tests/` | no count; tuples, units and dependent pairs settled by sort | the design's §1.7 list; the three tuple `IAlternative`s | keep a memo of tries; change a checked term against upstream's at depth 1000 | the corpus comparison of I3 shows no difference; an 8-tuple under `printLn` prints; the 22-tuple's time is recorded |
| U4 dead state and options (I7) | `Core/{Options,Context,Core}.idr`, `Core/Normalise/Eval.idr`, `TTImp/Elab/{Check,Delayed}.idr`, `TTImp/ProcessDecls.idr`, `Core/LinearCheck.idr`, `Core/Binary.idr`, `Idris/{CommandLine,SetOptions,Parser,Desugar,Syntax,Error}.idr`, `TTImp/TTImp.idr`, `compiler/idris/README.md`, `tests/` | no dead count, timer or option | §2.8's I7 list | refuse a pragma prelude or base writes (none do, measured) | each removed pragma refused where written |
| U5 no run-time tree (DP-76, I6) | `TTImp/ProcessDef.idr`, `TTImp/PartialEval.idr` (deleted), `Core/Transform.idr`, `TTImp/Elab/Utils.idr`, `Core/Context.idr`, `Core/Context/Context.idr`, `Core/Case/CaseBuilder.idr`, `Core/TTC.idr`, `Core/Binary.idr`, `Core/Normalise/Convert.idr`, every `PMDef` match (62) | elaboration builds one tree | I6's list | change the compile-time tree's split order (`saved` stays) | suites unchanged; TTC sizes and elaboration time of base recorded before and after |
| U6 term facts (C1, C2, the leaf index, `WhyErased`) | `Core/TTC.idr`, `Core/Binary.idr`; with L16's readers in the same change | the TTC holds no placeholder where Idris had a term or an index | the commented writes and placeholder decoders | land the TTC half without its reader's deletion; keep `WhyErased` before the frontend's marker moves | `decode . encode` is the identity on prelude's, base's and the tests' TTCs (the README's check); a `let` whose value's type the guess missed today translates |
| U7 the block parent (B1, I9) | `Core/Name.idr`, `Core/UnifyState.idr`, `Core/Context.idr` (`prettyName`), `Core/Reflect.idr`, `Core/TTC.idr`, `Core/Hash.idr` if names hash structurally, `TTImp/Unelab.idr`, `TTImp/ProcessDef.idr`, `TTImp/Elab/Case.idr`; with L16's readers | a block's parent is a name and an ordinal | the textual parent | change a printed message | I9's test; messages byte-identical on the suites |
| U8 quantities exposed (I4, FB-22, FB-18) | `Algebra/ZeroOneOmega.idr`, `TTImp/Elab/Utils.idr`, `TTImp/ProcessDecls.idr` (the end-of-module `updateErasable`), `Core/Context/Data.idr`, `upstream/fork-<bug>/` for each confirmed fork bug, `PINS.md` | binders matchable; `eraseArgs` complete; parameters found on normal forms | the frontend's five readers and `dataParams`' second reading (L16) | let the frontend read `eraseArgs` | I4's reproducer; a type behind `-@` gets its parameters |
| U9 locations and session facts (B3, pragma uses, B6, main path) | `Core/TTC.idr`, `Core/Binary.idr`, the parser's pragma records; the session half in `Frontend/Driver.idr` is L16's | the profile and `Resolve` read facts, not text | `Profile.imports`, the pragma re-lex, `homeOf`, `elaboratedFile` (L16) | add a `Maybe` for a fact Idris always has | an `import` in a block comment is not imported |
| U10 the carried diffs checked (I10) | `tests/upstream-patches/run`, its `witness/` and `near-miss/` | every Idris diff applies to the pin | nothing | apply a diff to the checkout | a planted stale diff fails the test |

Order: U1, U4 and U10 need nothing; U5 before U6 (one tree to keep facts
of); U8 before L16's signature; U2 after the design's §8 measurement;
U3 after U2 (both touch `Check.idr`); U7 last (it changes `Core.Name`
across the elaborator, 17 C1 "Order").

## 6. Owner questions

1. **D53's order on goals (I1).** Keep D53's homeomorphic embedding with
   constants collapsed to their type, or compare only goals of the same
   type constructor, argument by argument, with constants ordered by
   value, magnitude or subsequence?
   - *As recorded*: simplest to state; refuses some finite searches the
     stock Idris answers (`Rose Nat`, an integer countdown). Who pays: a
     program searching for a value of a recursive type through a
     container, or along integer indices.
   - *Coupled at the root* (recommended): still ends by construction
     (Kruskal and Dickson, recalled), refuses a subset of what D53 refuses,
     and compares fewer ancestors. Who pays: one more paragraph in the
     rule, and the label orders for primitive constants in the fork's
     search.
