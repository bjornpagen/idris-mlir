<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# D133: no `believe_me` of ours (L17bh's design)

L17bh wrote this between e866a09e (D133, C288) and b2aab6e9 (C288
sharpened by the owner, baaba5c9; AGENTS.md's carry-forward rule,
eedaf5d4), for the coordinator's review before any lane implements it.
Nothing below is in the tree. Each claim is marked *read*, *measured* or
*conjecture*; a choice of core shape is marked *for review*. The order of
questions per fact is C288's, as sharpened: first whether a refactor of our
code makes the fact unneeded, then evidence a function returns, then a
proof. Scratch: `/tmp/l17bh/` (`repro111/`, `bench-nat/`, `divprobe/`).

## 1. Inventory (read, at e866a09e; unchanged at b2aab6e9)

### 1.1 The two `believe_me`s and every fact stated through them

Two definitions, each a private `0 trusted : a; trusted = believe_me ()`:
`compiler/checker/src/Core/Primitives/Host.idr:27-28` and
`compiler/checker/src/Idris/Host.idr:108-109`. Fifteen applications, one per
fact (a reduct's two fields counted apart): five in `Core.Primitives.Host`,
ten in `Idris.Host`. "Live" means a reader whose result run-time code or
an assembled proof uses.

| # | Fact (where) | States | Readers, and what for | Live? |
|---|---|---|---|---|
| 1 | `intEqualityReflexive` (Prim/Host:42-44) | `x == x = True` on `Int` | Idris/Host's `intEqualitySymmetric`, `identReflexive`, `nameEqualityReflexive` → `firstAt` (1213) → `localPutBack`/`substitutesMarkers` (1459), `putInMarker` (1500) → only `Proof/Dictionaries.rootedReduces` (52-66) | dead: `rootedReduces` has no reader and no module imports `Proof.Dictionaries` |
| 2 | `intEqualitySound` (Prim/Host:46-48) | `x == y = True -> x = y` | `intEqualitySymmetric` (Idris/Host:1045) → the symmetric name lemmas → `firstAt` (`AtLater`) | dead, same chain |
| 3 | `charEqualitySound` (Prim/Host:57-59) | `Char ==` sound | none | dead |
| 4 | `stringEqualitySound` (Prim/Host:65-67) | `String ==` sound | none | dead |
| 5 | `shiftRightDescends` (Prim/Host:80-83) | `shr 32` of a positive magnitude is smaller | `Core/Binary/Prims.idr:427` `toLimbs`, writing an `Integer` to a TTC | live |
| 6 | `reachesNormalForm` (Idris/Host:911-914) | confluence: a reduct reaches the normaliser's normal form | `Proof/Covers.idr:1348` `normalisedPutIn` → `formCovers`, `coversAtRoot`, `readingFromNormal` | not live: the lemma is unassembled (`Proof.Covers` is imported by nothing; the run-time re-check `Finite.requestedUnder` is the only guarantee) |
| 7, 8 | `reduct`'s `MkReduct v trusted trusted` (Idris/Host:3146-3150) | `steps : Reduces t v`, `normal : Irreducible v` | built at quantity 0 by every `host.normalise*` call; read by `normalisedPutIn` (`site.steps`), `formCovers` (`normal`), `Reading.readNoShapeStep` (585), `Template.shapeForm` (2975), `Readings.solvedSteps` (207) | carried at run time at quantity 0; read only by unassembled lemmas |
| 9 | `probesFresh` (Idris/Host:3128-3130) | no definition names a probe (`FreshIn`) | none: nothing builds `Proof.Markers.MkMarkers`; `FreshIn` is a premise of `normalisedPutIn`, `formCovers`, `coversAtRoot`, `readingFromNormal`, `rootedReduces` | dead |
| 10 | `probesUnresolved` (Idris/Host:3137-3139) | no probe name resolves | `Covers.holeReadAs` (2282), a cut hole reads as `Leaf 1` | unassembled |
| 11 | `computedWithin` (Idris/Host:3354-3357) | a primitive's result is within `boundOf` at its arguments' sizes | `Proof/Primitives.computedGrown` (197-200) → `Covers.computedMeasured` (670-672), the premise of `Bound.AtComputed` | dead: no reader of `computedMeasured`; nothing constructs `AtComputed` |
| 12 | `oneEntryPerName` (Idris/Host:3432-3435) | one entry per full name | `sameByFullName` → `fullNameSameEntry` | dead (no reader anywhere) |
| 13 | `fullNameUnresolved` (Idris/Host:3437-3439) | no entry's full name is a `Resolved` | same | dead |
| 14 | `entryPlaced` (Idris/Host:3446-3448) | entries at non-negative `Int`s | `definedPlaced` (Covers:1903 `definedAddressed`; Template:166 `entryNonNegative`, which removes `placeOf`'s unplaced branch); `resolvedPlaced` (Definitions:50, Boundary:987, State:1318, 1328: the erased argument of `placementAt`) | live (only to turn an `Int` into a `Placement`) |
| 15 | `frozenContext`'s `\_ => trusted` for `Frozen.keeps` (Idris/Host:3552) | the frozen map keeps what `readLive` read before the freeze | `keptAt` → `Boundary.solutionAt` (999, 1004) → `Solution`'s `Defines` | built, never read: every match on `SolvedAs`/`Unsolved` drops it (Closed:900, Sites:2016, 2028, Terms:1077) |

No reader of any of them is in `compiler/spec`, `harness/`, `libs/`,
`tools/` or `bench/`; the frontend's readers are all in `Proof/`,
`Growth/Template`, `Translate/{Boundary,State,Definitions,Readings,Closed}`.

Found while reading (*read*, not measured): `oneEntryPerName` may be false.
Restoring a saved `Defs` rolls `nextEntry` back but keeps the table's slots
(`Core/Context/Context.idr:420-423`), `newEntry` reuses a slot without
clearing it (`Core/Context.idr:102-112`), and `entriesFrom`
(Idris/Host:3527-3533) lacks the `undefinedNames` guard `full` has
(Context.idr:367-373), so a freeze could hold a stale definition whose full
name another entry holds. Deleting the fact (§2.1) removes the false
statement; whether the freeze reads stale slots is the checker's to fix.

### 1.2 The Host modules' other trust points

- 23 `assert_total` in `Core/Primitives/Host.idr:139-258`: `stringHead`,
  `stringTail`, `stringIndex` (the primitive returns on a non-empty string,
  an index in range) and `div*`/`mod*` at ten widths each (it returns at a
  non-zero divisor). Readers: `Core/Primitives.idr:268, 272, 276, 345-371`,
  the evaluator's table. They are needed because both primitive tables mark
  these `notCovering` (ours `Core/Primitives.idr:789, 803, 962-964`;
  upstream's `src/Core/Primitives.idr:686-687, 702-704`) and coverage
  spreads through calls (`Core/Coverage.idr:362-392`).
- 1 `assert_total` in `Idris/Host.idr:3618`, `host`: that the checker's
  evaluator and elaborator return (AGENTS.md's one stated trust of the
  frontend in the checker), and the fields "here until the function it
  names is total" (`checkTerminating`, `buildMain`, `processPackageOpts`,
  `emitError`). It is not a `believe_me` and this design keeps it.
- `covering`: `entriesFrom`, `frozenContext`, and `0 tableOf` (a covering
  function a statement names, `getOp` being covering).
- No `assert_smaller` in either module.

### 1.3 Upstream's `believe_me` that our code reaches (read)

Not ours under D133, but a proof that rests on one is a trust by proxy:
- base's `DecEq Int` is `decEq @{FromEq}`, a `believe_me`
  (`third_party/Idris2/libs/base/Decidable/Equality.idr:136-153`). Two live
  uses, both producing evidence proofs read: `Idris/Host.idr:327`
  `compareEntries` (`SameEntry`, read by `Template.chosen` at 1372 and from
  there by `Covers` 2008, 2018, 2044) and `Growth/Template.idr:306`
  `anotherEntry` (constructor tags: `Blocked (t = tag)` or `TagDiffers`,
  read by `Covers:2009`). The other 75 `decEq` uses in our Idris are at
  structural types (`Nat`, `Fin`, enumerations).
- base's `Data.Fin.fromInteger` (an erased `lemma oh = believe_me oh`,
  `Fin.idr:244-250`), reached by `Fin` literals in `Proof/Forms.idr:41-45`,
  `Translate/Keys.idr:319-322`, `Translate/Literals.idr:28-32`,
  `Spec/Runtime/Endings.idr:223-226`. The literal's range is decided by the
  elaborator; no proof of ours reads past it.
- base's `Data.String.strM` (141-146), through `parsePositive`/
  `parseInteger`, in the harness only (`Lazy.idr:285, 288`,
  `Linear.idr:527-536`, `FuzzRun.idr:134`, `Reject.idr:61, 114`): values,
  no proof.
- prelude's `prim__integerToNat` (`Types.idr:27-31`), a representation
  coercion; no proof rests on it.

### 1.4 The rest of our Idris, and the test inputs (read; one measured)

A sweep of `compiler/`, `harness/`, `libs/`, `tools/`, `bench/`, `tests/`
and `upstream/` for `believe_me` in code finds, beyond §1.1's two:
- the checker implementing the language's own `believe_me`
  (`Core/Primitives.idr:969`, `Core/Name.idr:243`, `Name/Known.idr`), the
  frontend refusing it (`Frontend/Profile.idr:407`, `Translate/Terms.idr:2224`)
  and recognising it (`Registry/Recognized.idr:289-291`): no use;
- four refusal-test inputs, which keep theirs (D133's exception):
  `tests/escape-hatch-believe-me/Main.idr:7`,
  `tests/escape-hatch-believe-me-in-proof/Main.idr:11`, and the planted
  witness in `tests/rules-covered/{witness,near-miss}/tests/escape-hatch-planted/Main.idr:3`;
- one reproducer: `upstream/111-coverage-nested-empty-type/CaseBlock.idr:42-43`
  (`0 joined`, two clauses). It shows its bug without one (*measured*):
  with `joined` made a parameter of `closedBelow`, as
  `tests/checker-coverage-nested-empty-type/Main.idr:59-63` already writes
  it, `/tmp/l17bh/repro111/Param.idr` is still refused ("closedBelow is not
  covering", "Calls non covering function Param.case block in
  closedBelow") by the Idris with 96 and 104 to 110
  (`/tmp/int18/idris2-prev-96-110/bin/idris2`), as `CaseBlock.idr` is, and
  checks on the toolchain's Idris (with 111). So 111's `CaseBlock.idr`
  drops its `believe_me` in the same step as the rest;
- `upstream/59-literal-partial-fold`, `upstream/18-elaboration-primitive-folding`
  and `tests/upstream-literal-partial-fold` name base's `Data.Fin`
  `believe_me`, which is their bug's subject; no input holds one of ours.

## 2. Per fact: removed by refactor, proved, or carried as evidence

| # | Fact | Takes | What goes, or what is made unrepresentable |
|---|---|---|---|
| 1-4 | `Int`/`Char`/`String` equality | removed by refactor (culled; §2.4 removes the name layer they served) | the name-equality lemmas and `firstAt` chain |
| 5 | `shiftRightDescends` | removed by representation (§2.5) | the recursion on `shr` |
| 6 | `reachesNormalForm` | removed by refactor (§2.7.1) | relating two normal forms: there is one run, from the site's normal form |
| 7 | `Reduct.steps` | carried as evidence (§2.7.2) | the run the evaluator returns |
| 8 | `Reduct.normal` | removed by representation, then proved (§2.7.2) | `Irreducible` replaced by the read-back grammar, proved of every run |
| 9 | `probesFresh` | removed by representation (§2.4) | a marker a definition could name: markers are variables |
| 10 | `probesUnresolved` | removed by representation (§2.4) | a hole that could resolve: holes are variables |
| 11 | `computedWithin` | culled now; its role is the owner's (§4.1) | — |
| 12, 13 | `oneEntryPerName`, `fullNameUnresolved` | removed by refactor (culled, §2.1) | — |
| 14 | `entryPlaced` | removed by representation (§2.2) | a negative entry: entries are `Nat` |
| 15 | `Frozen.keeps` | removed by refactor (§2.3) | a definition read twice: the walk reads the frozen context once |
| proxy | base's `DecEq Int` ×2 | removed by representation (§2.2) | an `Int` identity: entries and tags are `Nat`, decided by `equalNat` with proved laws |
| — | 23 `assert_total` | removed by representation (§2.6) | a partial primitive called directly: reached through the prelude's total function or method |

### 2.1 Dead: culled (removed by refactor)

Facts 1-4, 9, 11, 12, 13 have no live reader (§1.1). They go with
everything only they serve: in `Idris/Host.idr`, `intEqualitySymmetric`,
the `ident`/`pair`/`userName`/`name` equality lemmas (1037-1186),
`firstAt`, `replacesAt`, `localPutBack`, `markersPutBack`,
`substitutesMarkers`, `putInMarker` and any helper only these reach
(`noneAt` stays: `mappedEmbed` reads it), `sameByFullName`, `fullNameSameEntry`,
`sameEntryFullName`, `entryFullName`, `definedFullName`,
`resolvedDefinedFullName`; in the checker, `Core/Name/Ident.idr:43-51` and
the `Namespace` lemmas that take the `Int` laws as premises; in the
frontend, `Proof/Dictionaries.idr` whole (its two lemmas are unread and the
module unimported; §3's dictionary part is restated over the evaluator's
run), `Proof/Primitives.computedGrown`, `Covers.computedMeasured`,
`constantMeasured`, `sizesBelow`, `resultBoundMonotone`, `primitiveWithin`,
`boundWithin`; and `probesFresh` with `AllProbeNamed`. The run-time code is
untouched, so every output is unchanged. `computedWithin`'s role in the
assembled lemma is the owner's (§4.1); nothing is asserted meanwhile.

### 2.2 Identities as structural indices: entries and constructor tags (representation)

Facts 14 and the two `decEq Int` proxies (§1.3) exist because an entry
(`Resolved Int`) and a constructor's tag (`DataCon (tag : Int) arity`) are
`Int`s. Make both `Nat`:
- `Core.Name.Resolved : Nat -> Name`, `getNameID : Name -> Context ->
  Maybe Nat`, `Nested`'s parent entry a `Nat`; `DataCon : (tag : Nat) ->
  (arity : Nat) -> NameType`. The context's table stays an `IOArray`
  indexed by `cast` of the `Nat` at its one boundary (no proof reads the
  array); `Frozen.entries` is keyed by `Nat`.
- Equality decides by construction, at constant cost: the frontend's
  idiom (`Proof/Growth.idr:51-107`: `Decided` with erased evidence,
  `equalSo`, `samePosition`) over `equalNat`, which the stock host
  compiles to an integer `=` (`Compiler/Opts/Constructor.idr:90`) and
  idris-mlir to one comparison (`Registry/Faster.idr:52`), its soundness
  proved by structural induction at quantity 0. `compareEntries` and
  `anotherEntry` decide by it; base's `DecEq` is not used. *Measured*
  (`/tmp/l17bh/bench-nat`, stock pinned Idris on Chez, this arm64 macOS
  machine, three runs): 10^6 decisions at an entry of 50,000 take 2-3 ms
  through `equalNat` with erased proofs, 12-15 ms through base's `decEq`
  on `Int` (its loop also casts), and base's structural `decEq` on `Nat`
  takes 2.1-2.4 s for 2×10^4 (about 110 µs each), so base's `DecEq Nat`
  must never decide an entry.
- State made unrepresentable: a negative entry. `entryPlaced`,
  `definedPlaced`, `resolvedPlaced` go; `Walk.placementOf`'s `i < 0` test,
  the run-time check at `Boundary.idr:694-696` and `Template.placeOf`'s
  unplaced branch go (branches deleted).
- Cost (*read*): `Resolved` on 198 lines in 39 checker files and 17 in 8
  frontend files; `DataCon` on 79 lines in 22 checker files and 64 in 13
  frontend files. The TTC is unchanged for entries: `Resolved` is never
  written (`Core/TTC.idr:132-133` throws; `writeTTCFile` makes names full
  first, `Binary.idr:208-210`); tags are written, as an `Int` today, as a
  `Nat` after (format version bump, `Core/Binary.idr:39-40`). Run time is
  the same on both hosts (a `Nat` is an integer at run time, and every
  operation the checker applies to entries and tags, `==`, `compare`,
  `+`, is one of the compiled fast paths); to be measured in the step.
- Name's other `Int`s (`Ident.index`, `MN`, `PV`) stay: once markers are
  variables (§2.4) no proof compares names, so no fact about them is
  stated or needed. *For review* whether to convert them anyway.

### 2.3 The frozen context: freeze before the walk (refactor)

Fact 15 exists because the frontend reads definitions before the freeze
(`Boundary.readFrom`, 686-704) and the freeze follows the walk because
`verdictOf` (280-288) runs `host.checkTerminating`, which writes verdicts
into the live context. Nothing the normalisers run reads a verdict (*read*:
`Termination.idr:70-79`, `setTerminating` at `Context.idr:1983-1989`;
nothing in `Core/Normalise*` reads totality).

Refactor: freeze first, once the program and its imports are loaded; the
walk reads every definition from the frozen context (`definitionIn`, pure,
with `Defines`), and keeps the verdict `checkTerminating` returns as it
does now (`Ends`), the live context's copy of it unread by anything frozen.
`readLive`, `LiveEntry`, `LiveDefinition`, `Frozen.keeps`, `keptAt`,
`Unfrozen`'s pre-freeze reads and `readIn`'s pairing of a pre-freeze read
with a frozen `Defines` go: each definition is read once and its
`Defines` carried from there (AGENTS.md, eedaf5d4). `Host`'s comment that
"nothing changes the context after" becomes "nothing the frozen context
holds changes": a verdict is not part of it. Byte-identical expected.

### 2.4 Markers and holes as variables (representation)

Facts 9 and 10, `FreshIn`, `ProbeNamed`, and the name layer of §2.1 exist
because the walk closes a site's term with probe-named bound references
for the writer's parameters, so that it can call normalisers that take
closed terms. A definition of the context could then, as far as a proof
knows, name a marker, and putting values in by name commutes with
reduction only under freshness.

Refactor: a site's term is a `Term ws` over its markers as de Bruijn
variables, normalised under an environment of abstract binders (the
evaluator keeps a free non-`let` variable as `NApp (NLocal ...)` and
quote returns it as a `Local`, *read*, `Eval.idr:238-246`,
`Quote.idr:139-149`). A definition is a term over its own arguments, so it
cannot name the site's variables: freshness is unrepresentable to violate,
not stated. Which probes become variables (*read*, L17bh's survey):
- the ones instances substitute: `ProbePart` (per match, with its path),
  `ProbePattern`, `ProbeFieldPath`, `ProbeFormal` (per beta): variables of
  the walk's scope, which grows at each match and beta as the walk goes
  under them (the walk's `Values ClosedTerm vs`, `Template.idr:1273`,
  becomes values over that scope, weakened as it grows); the readers that
  recover a marker from a name (`Readings.referenceOf` 603-612,
  `Template.markersIn` 433-445, `Boundary` 370-378, `Sites` 677-690)
  read an index → (parameter, path) table the walk keeps instead;
  `refsToLocals` in `Sites.replacing` (202-203) and `Terms.restore`
  (1218-1224) become `substs`;
- the holes in keys (`ProbeRuntime`, `ProbeHole`, `ProbeRuntimeAt`,
  `ProbeHoleFound`, `ProbeUnknown`): variables of the key's scope, so a key
  is a `Term hs`. A variable is never looked up, so `probesUnresolved`
  goes (`holeReadAs` reads a hole as `Leaf 1` because it is a variable no
  marker is). The evaluator leaves the variable neutral as it leaves the
  unresolved `Ref Func` stuck today, so keys keep their shape; links print
  the variable with today's spelling;
- local stand-ins no proof substitutes (`ProbeBinder`, `ProbeStandIn`,
  `ProbeForm`, `ProbeAxis*`, `ProbeSize`) may stay names.

Gone with it: `FreshIn`, `AllProbeNamed`, `ProbeNamed`, `Walk.probeNamed`,
`Proof.Markers` (its `fresh`, `leafFresh`, `closedNoUnknown`), the premise
"the site's term names no unknown by a marker's name" (Covers' open
premise (a), 1412), and every name-substitution lemma of `Idris.Host`
(`markersOf`, `replacedAt`, `substitutes`, `putIn*`, `normalisesThrough`).
Cost (*conjecture*, from the survey): 300-600 lines in Template, Sites,
Readings, Closed, Keys, Walk; `Reduct` and the host's normalisers take an
environment of abstract binders where they take `ClosedTerm` today
(Idris/Host:896, 3577-3584). It is the representation C281's step 1
builds its nodes over, so it lands with that step (§5).

### 2.5 The TTC's integer (representation)

Fact 5 exists because `toLimbs` recurses on `prim__shr_Integer`'s descent,
which no proof reaches. Write an `Integer` as its decimal text
(`show`, a total primitive cast), read it back by `cast` (total): no
recursion, so no descent to state. The round trip is the runtime's
documented meaning of the two casts, which nothing asserts. Rejected:
recursion on the magnitude as fuel (the survey's proposal): the skill's
"never fuel"; if the bound were short it would truncate silently, the same
reliance on `shr` unstated. Cost: TTC format version bump; bytes and time
of every TTC's integer constants, measured in the step.

### 2.6 Partial primitives (representation, one route each)

*Measured* (`/tmp/l17bh/divprobe/Probe.idr`, the toolchain's Idris,
`%default total`): `stringHead s = map fst (strUncons s)`,
`stringTail s = map snd (strUncons s)`, `stringIndex` through
`prim__strSubstr i 1 s` (total in both tables) then `strUncons`, and
`divInt _ 0 = Nothing; divInt x y = Just (div x y)` (likewise `mod` and
every width) check with no `assert_total`; the direct `prim__div_Int` is
refused ("Calls non covering function prim__div_Int").

So each partial primitive is reached through a total function of ours
returning its refusal (`Nothing`), over the prelude's own: `strUncons`
(upstream's `assert_total`, `Types.idr:845`) and the `Integral` methods
(upstream's `case y == 0 of False => prim__div_…`, `Num.idr:91-96,
128-133`), exactly as `Core/Primitives.idr`'s `Double` division already
reaches its primitive through `/`. Plainly: the primitive's partiality is
then stated by upstream's prelude, as base's `DecEq Int` states `Int`
equality; nothing of ours asserts it, and the behaviour is the same
primitive call at the same values (byte-identical). All 23 `assert_total`
go.

### 2.7 The normaliser (refactor, then evidence)

The coordinator's question, answered first: with C281's model deciding
every request once, does the frontend still need the evaluator to agree
with a site's template? Yes, and that much is essential (Brooks's line).
A key is the evaluator's value of the site's term at an instance's values:
instance identity is content, and two calls that compute one type must
share an instance, so the key is a normal form only the evaluator can
compute (one evaluator, D68). The model never sees those values; it reads
the site once, over markers, and its bound is a statement about every value
the evaluator can produce from that reading. "One function both sides
call" already holds for what is computed (§2.7.1 makes it literal), but no
function the model can run covers the values it never sees; the link
between the symbolic reading and the concrete runs is the lemma, and its
premise is what the evaluator did. What a refactor removes is everything
around that premise.

#### 2.7.1 Confluence (fact 6): removed by refactor

The model computes the site's normal form; C281's node carries it.
`instantiate` (L16-fold §4.1) evaluates *that normal form* in the
environment of the instance's values, not the site's term with the values
put in. The evaluator's own run from the site's normal form is then the
whole relation the lemma needs: `normalisedPutIn`'s goal is that run, and
`substitutes`, `site.steps`, `FreshIn`, the no-unknown premise and
`reachesNormalForm` go from it (*read*, the lemma survey). The fact the
model computed is carried to every instance instead of being derived again
from the term at each (AGENTS.md, eedaf5d4); each instance's evaluation
starts from a normal term, so it should do less work than today's
(*conjecture*, measured with the keys).

The two places the survey found still reaching for confluence (Covers'
open items 3 and 4: a call read beside its unfolding, and solving through
putting values in) are inversions of the instance's run once that run is
the evaluator's own deterministic derivation (§2.7.2): the run says
whether the call unfolded and which alternatives its walk took, so no
second reduction path exists to meet. The solved form is taken from the
site's solved form the same way.

Byte-identity rests on the evaluator giving one normal form for a term and
for its normal form with values in (what `reachesNormalForm` asserted). It
is measured, not assumed: C281's step 3 compares every request's key on the
429 fixtures; a difference is either an evaluator bug (our checker, fixed
there) or a change of instance identity reported with its fixture.

#### 2.7.2 Steps and normality (facts 7, 8): carried as evidence

The certifying evaluator, *for review* (core shape: the relation D68
declared, and the evaluator's interface).

**What the checker declares.** Not the small-step `Reduces` and
`Irreducible` (Idris/Host:606-914), but the evaluator's own semantics, one
rule per case of `eval`, `applyToStack`, the case-tree walk (`evalTree`,
`findAlt`, `tryAlt`, `evalConAlt`) and `quote`, in a new
`Core.Evaluation` beside `Core.Normalise`:

```idris
-- Where the evaluator reads a definition, and the evidence the read gives:
-- the frozen context's `Defines` (`definitionIn`, pure), or for the live
-- context the read itself (an opaque value only its lookup makes), which
-- nothing reads. One evaluator, two sources.
record Source where
  constructor MkSource
  0 Holds : Name -> GlobalDef -> Type
  lookup : (n : Name) -> Core (Maybe (d : GlobalDef ** Holds n d))

mutual
  data Evaluates : Evaluation -> Source -> LocalEnv free vars -> Stack vars ->
                   Term (vars ++ free) -> NF vars -> Type
  -- the case-tree walk over the arguments' closures: a leaf, stuck, or no match
  data Walks     : Evaluation -> Source -> LocalEnv args vars -> CaseTree args -> Walked vars -> Type
  data ReadsBack : Evaluation -> Source -> (level : Nat) -> NF vars -> Term vars -> Type

||| A normaliser's result with the run that produced it: evaluation in the
||| given environment, then read-back. Replaces `Reduct`.
record Normalised (form : NormalForm) (src : Source) (env : Values vars) (t : Term vars) where
  constructor MkNormalised
  value : Term vars
  0 run : Normalises form src env t value
```

Each rule mirrors one case of the code, so each function returns the rule
it took, at quantity 0: no proof work inside the evaluator beyond naming
the case. A stuck application's rule holds why it is stuck (the definition
not admitted, too few arguments, or the walk's scrutinee a neutral), as
the walk's own `NoMatch`/`GotStuck` results already say. `ArityDiffers`
and `Matches`, the case-tree facts C283 feared would need a trust, are
rules of `Walks`: the model's trace (`Template.chosen`, `anotherEntry`) is
built against them, comparing tags and entries as the walk does (§2.2).

**Proved, once, in the checker** (*conjecture* until written; each by
induction on the syntax-directed rules):
- `normalisedOnce : Normalises f s e t u -> Normalises f s e t u' -> u = u'`
  (determinism; `definedOnce` gives one definition per name);
- `readBackSyntax : Normalises f s e t u -> NormalSyntax u`, a grammar of
  read-back terms (neutral heads with the evidence of their stuckness,
  constructors and families applied, binders, constants), which replaces
  `Irreducible` for every reader: `argumentsIrreducible` and
  `readNoShapeStep` (no shape redex at a site's node) hold of the grammar
  by its constructors.
Where a value put in is a key, the environment holds it with its own run
(the instance's values carry their `Normalised`), so reading a marker back
needs no idempotence lemma: the variable's rule returns its entry, whose
run determinism fixes.

**The representation it needs** (refactor, before the evidence): binder
scopes as data, not functions. `NBind`'s scope is `Defs -> Closure vars ->
Core (NF vars)` (*read*, `Value.idr:131-132`), which no relation can
describe; it becomes the closure it already is in all but type (its
environment and body, applied by `eval`). Read-back goes by de Bruijn
levels, not fresh `MN qv i` names from a mutable `Ref QVar Int` counter
turned back by `refsToLocals` (`Quote.idr:76-80, 160-161, 215-217`): no
fresh names, so no freshness to state, and no counter. Both are
improvements of the checker's representation on their own.

**Cost.**
- At run time and in memory: nothing. Every derivation is at quantity 0,
  which both hosts erase. The four normalisers' signatures change; every
  caller that takes `.value` is unchanged.
- In code (*conjecture*, from the survey's counts): the scopes as data
  touch `Value.idr` (266 lines), `Eval.idr` (687), `Quote.idr` (316),
  `Convert.idr` (458) and 143 uses of `NBind` in 29 checker files; the
  relation is about 500 lines; returning the rule touches every case of
  `Eval` and `Quote`; the two lemmas are about 400. The small-step relation
  and its lemmas in `Idris/Host.idr` (606-3098, about 2,500 lines) go once
  §3's lemma no longer reads them, and with them `Proof.Inversion`'s
  inversions of `Then`-chains.
- In time: the source is a record of functions, so each definition read is
  one indirect call; scopes as data apply by `eval` where a closure did the
  same; levels avoid the counter's `IORef`. Expected neutral; measured on
  the test programs' checker times in the step.

**Alternatives costed** (for the same review):
- Keep the small-step relation and prove NbE sound against it (the
  evaluator's run implies `Reduces` and `Irreducible`): the survey's
  estimate is 3,000-5,000 lines of proof on top of the same evaluator
  work, for a relation the frontend's lemma no longer needs (§3): rejected
  as cost without a fact gained.
- A first-order, substitution-based certifying normaliser for the
  frontend's keys only, beside the checker's NbE (the survey's cheapest,
  1,600-2,200 lines, Idris/Host's `reduct` changing in about 20): a second
  evaluator, against D68's "no second evaluator (0010 D3)", and its keys
  would still have to agree with NbE's `classify` (97 calls through
  `normaliseClosed`), which needs either confluence (a trust) or every
  frontend normalisation moved to it (two evaluators of one language,
  drifting). The owner's if anyone proposes it; this design does not.

### 2.8 `computedWithin` (fact 11): for the owner (§4.1)

### 2.9 What stays

`host`'s `assert_total` (§1.2): the frontend's one trust in the checker's
evaluator and elaborator, which AGENTS.md states once in the checker. Its
`normalise*` fields return `Normalised`.

## 3. The frontend's lemma, restated (L16-fold-design §5)

§5.1, over what the evaluator returns:
- `Instantiated n at` holds, at quantity 0, the instance's run from the
  node's site normal form: `run : Normalises OfNormaliseTypes frozen
  (valuesOf at) n.siteNormal key` for a kind read off the normal form, and
  the holes run from the site's solved form for a kind read as written. The
  instantiation computes each keyed argument as that run's value, cut as
  C283 keeps it (`cutRuntime` applied to the site's normal form, returning
  `CutFrom`; a cut hole is a variable of the key's scope, §2.4).
- `Placed d inst` is unchanged but for `MarkersHold` over variables: the
  instance's value at each variable of its reading's scope.
- For a request made by instantiating node `n` at an instance with
  `Placed`, each keyed argument is written by its site: by induction on
  `NormalSyntax n.siteNormal` (the site's own `readBackSyntax`), inverting
  `run` at each node by its rule. At a variable, the value its environment
  holds (its own run fixes it). At a constructor or family applied, the
  head over its arguments' runs. At a neutral call the site read beside its
  unfolding, the run's rule is either stuck (its stuckness evidence) or
  `Unfold` with the `Walks` derivation, whose alternatives the site's trace
  read; no confluence, no `ArityDiffers` or `Matches` trust. At a
  primitive with a variable among its arguments, see §4.1. Under a binder,
  the scope's run at the next level (`NodeCovers` over a scope, open item
  2, is now the induction's binder case, not a substitution lemma).
  `Keyed`'s `Drawn` gives the site's membership and `HeldAs`;
  `ReadingCovers` then `Covers.siteWritesRead` give `SiteWrites`;
  `Capped` gives `cappedPlaced`.
- So the argument is within its bound (Theorem 1 over the model), within
  the head's height, and the link in the universe: `requestedUnder` gets
  `Under` with no decision, and the requested instance gets `Placed`.

§5.2's parts, changed: `HeadsHold`'s `Gives f` case inverts the run's
`Unfold` rule (not `Idris.Host`'s `Unfold`/`Chooses`); `LandsHold` and
`cutWithinCap` are unchanged. The dictionary over runtime values
(`FromImplementation`) is what the frontend's own head reduction finds
(`Closed.idr:699-960`: heads, beta, a stuck definition's leaf, projection,
each by a phase, total by `SizeAccessible`, a definition met again handed
to `normaliseAll` by `again` at 811). L16-fold §5.2 meant it to return
small-step steps, and a big-step relation states one strategy, the
evaluator's, not that one. So the reduction becomes the evaluator's head
evaluation (`eval` to a weak head normal form, which NbE's `eval` already
gives), returning its `Evaluates` run: one evaluator, its run the
evidence, and the frontend's own steps deleted. Its own totality measure
goes with it, which costs nothing it has today (a recurring definition
already goes to the covering evaluator). Open: O-5.

§5.3, trusts: none. The two places it said could need one dissolve: the
case-tree facts are rules of `Walks`, and the cut is applied before the
run, so the simulation lemma (holes stuck) is the rule for a neutral
variable, needing no monotonicity of the normaliser.

## 4. For the owner (C288's last sentence) and for review

### 4.1 `computedWithin`: the size of a primitive's result

The fact: what the evaluator's table computes from constants stays within
`boundOf` at their sizes (`Idris/Host.idr:3153-3357`): integer arithmetic,
shifts, string operations and casts of Chez Scheme and of idris-mlir's
runtime. Evidence: the model reads a saturated builtin with a marker among
its arguments as `Choice c [Head (Just a) ts, Leaf 2]`
(`Template.idr:1216-1225`, `Bound.idr:439-440`); heights need nothing
(`constantHeight` at most 2), but the universe weighs a literal by its
magnitude (`Requests.weight`, `Number _ m` weighs `S m`), and
`AtComputed`'s premise bounds the computed constant's magnitude by
`grown` of its arguments', which only the primitive's own behaviour gives.
No structural index applies (the measure must be the magnitude for finitely
many literals to share a weight) and no total function helps (the
primitive is total; its output's size is the fact). Today it is dead
(§2.1), so nothing is asserted until the lemma is assembled. Options:
- **A.** A key keeps a builtin applied to a variable as the call written,
  cut before the run as the runtime cut is (its head a variable of the
  key's scope during the run). Growth through a primitive is then height,
  which the model bounds; `Leaf 2`, `AtComputed`, `boundOf`,
  `constantSize`, `SizeBound`, `grown`'s `2^1024` term and the exponents
  of `Core.Primitives.Host` go. Costs: an instance whose static argument a
  primitive computes from a static parameter is keyed by the call, not the
  constant, so two requests that compute one constant two ways are two
  instances (each correct); how many of the 429 fixtures have such a
  request is to be measured before choosing.
- **B.** The universe counts a constant computed at a variable by its
  provenance (the requester's key and the site), not its magnitude: the
  image of a finite set under the evaluator's run, which determinism makes
  a function. Keeps keys; reworks `Proof/Requests`' universe and the
  weight check, and holds only where no weight cycle runs through a
  computation (*conjecture*; whether the model ensures that is unread).
- **C.** State the bound per primitive as a fact: refused by D133.

### 4.2 For review (core shapes the coordinator routes)

- §2.7.2: the relation the checker declares is the evaluator's big-step
  semantics (`Evaluates`, `Walks`, `ReadsBack`, `Normalises`), replacing
  D68's small-step `Reduces`; `Source` as the evaluator's one parameter
  for where it reads; `Normalised` replacing `Reduct`.
- §3 and O-5: the frontend's own head reduction replaced by the
  evaluator's head evaluation, so one evaluator's run is the only evidence.
- §2.2: whether `Ident.index`, `MN` and `PV` become `Nat` too.
- §2.6: reaching a partial primitive through the prelude's total function
  or method, the partiality stated by upstream's prelude.

## 5. The cutover

Each step builds the checker (and the frontend where it changes) on a
`git archive` export and compares every test program's check status and
output against HEAD's checker, as L17bd did (`/tmp/l17bd/driver` and its
sweep), and, where the frontend changes, every fixture of the 429 against
HEAD's frontend by L16em's measure (module bytes; stdout and stderr where
no module is written). Byte-identical unless the step names what changes.
Where a step deletes what an unassembled lemma of `Proof/` reads (§1.1:
read by nothing), that lemma goes in the same step, and step 8 states it
again over the new form; no lemma is kept compiling against a deleted
mechanism.

Holders at b2aab6e9 (`git status`): L17be holds `Core/Binary.idr`,
`LinearCheck`, `Termination/CallGraph`, `TTC`, `Idris/Desugar`, `ModTree`,
`Package`, `ProcessIdr`, `Syntax/TTC`, `Libraries/Utils/Shunting`,
`TTImp/Elab/Term`, `ProcessBuiltin`, `ProcessData`, `ProcessDef`,
`ProcessRecord`, `Reflect`, `TTImp/TTC`, `WithClause`
(`/tmp/l17be/owned.txt`); L17bf and L17bg between them hold
`Core/AutoSearch`, `Context`, `Core`, `Normalise/Quote` (a 319-line rewrite
in flight: quote by continuation with a depth), `Unify`, `Idris/Error`;
L16ep holds `Translate/` and `Growth/`. Free: both Host modules,
`Core/Primitives.idr`, `Core/Binary/Prims.idr`, `Core/Name*`, `Core/Value`,
`Core/Normalise.idr`, `Normalise/Eval`, `Proof/`, `Walk`, `Resolve`,
`Finite`, `upstream/111-…`.

1. **Cull** (§2.1, §1.4's reproducer). Write set: `Core/Primitives/Host`,
   `Idris/Host`, `Core/Name/Ident`, `Core/Name/Namespace`,
   `Proof/{Primitives,Covers}`, delete `Proof/Dictionaries`,
   `compiler/idris-mlir.ipkg` (its listing),
   `upstream/111-coverage-nested-empty-type/CaseBlock.idr` (and its README's
   description of `closedBelow`). Waits on nothing. Byte-identical (no
   run-time code changes); `tests/upstream-coverage-nested-empty-type`
   still passes (measured on the variant, §1.4).
2. **Partial primitives and the TTC's integer** (§2.5, §2.6). Write set:
   `Core/Primitives/Host`, `Core/Primitives`, `Core/Binary/Prims`, and the
   TTC version in `Core/Binary.idr` (L17be's): waits on L17be for that one
   line. Byte-identical outputs; TTC bytes and checker time measured. After
   it, `Core.Primitives.Host` holds no trust: its `trusted` goes.
3. **Entries and tags as `Nat`** (§2.2). Write set: `Core/Name`,
   `Core/TT` (`DataCon`), `Core/Context`, `Context/Context`, `Core/TTC`,
   `Core/Binary`, `Normalise/Eval`, the 39 + 22 checker files of `Resolved`
   and `DataCon`, `Idris/Host`; frontend `Walk`, `Definitions`, `Resolve`,
   `Keys`, `Boundary`, `State`, `Closed`, `Sites`, `Template`. Waits on
   L17be, L17bf, L17bg (checker) and L16ep (frontend). Byte-identical
   outputs; checker time measured on the test programs (expected equal).
4. **Freeze before the walk** (§2.3). Write set: `Idris/Host`,
   `Translate/Boundary`, `State`. Waits on L16ep. Byte-identical.
5. **Scopes as data, read-back by levels** (§2.7.2's representation).
   Write set: `Core/Value`, `Normalise/Eval`, `Quote`, `Convert`,
   `Normalise.idr` and the 29 files that match `NBind`. Waits on the
   holder of `Quote` (its in-flight rewrite lands first) and of `Unify`.
   Byte-identical checker outputs; checker time measured.
6. **The certifying evaluator** (§2.7.2). Write set: new
   `Core/Evaluation`, `Normalise/Eval`, `Quote`, `Normalise.idr`,
   `Idris/Host` (`Normalised` replaces `Reduct`; `host`'s fields),
   frontend `Translate/Closed` (`Normaliser`, `readNormal`, `solving`),
   `Readings` (`Solved`), and the `Proof/` lemmas that read `Reduct`
   (`Covers.normalisedPutIn` and its callers, `Reading.readNoShapeStep`,
   `Template.shapeForm`), which go. `reduct` and its two `trusted`,
   `Reduct`, `Irreducible`, and `reachesNormalForm` (no reader left) go.
   Waits on step 5. Byte-identical; the checker's build time measured
   (types grow), run time expected unchanged (everything added is erased).
7. **Markers and holes as variables** (§2.4) **with C281's step 1** (the
   annotated tree built over the variable scope). Write set: `Walk`,
   `Growth/{Template,Sites,Graph}`, `Translate/{Readings,Closed,Keys,
   Instances,State,Shapes,Terms}`, `Proof/Markers` (deleted), `Idris/Host`
   (the name-substitution lemmas, `FreshIn`, `ProbeNamed` and
   `probesUnresolved` go, and with the last of them `Idris.Host`'s
   `trusted`). Waits on L16ep and on C281's review. Byte-identical
   expected (keys print the hole variable with the probe's spelling).
8. **C281's steps 2 to 6 as amended here**: the instantiation evaluates
   the site's normal form in the instance's values (§2.7.1), with its
   `Normalised` run in `Instantiated`; the frontend's own head reduction
   replaced by the evaluator's head evaluation (§3, O-5; `Closed`'s
   phases); the lemma over `Normalises` (§3);
   `computedWithin`'s replacement as the owner rules (§4.1); then the
   deletions of L16-fold §4.3 and of `Idris/Host`'s small-step relation
   and its lemmas, which nothing reads once the lemma is restated. Waits
   on steps 3, 6 and 7. The key comparison of step 3 of
   C281 is where §2.7.1's byte-identity is measured.

After step 7 no `believe_me` of ours remains (step 8 deletes what no
longer has a reader): `grep` finds the four refusal-test inputs alone.

## 6. Not settled

- O-1 (*for review*): §2.7.2's relation and `Source`.
- O-2 (owner): §4.1.
- O-3: whether the stale-slot freeze (§1.1, found while reading) is real;
  the checker's lane would measure it by freezing after a restored `Defs`.
- O-4: `Nested (outer, _)` and `PV _ k` are written to TTCs with
  session-local entry numbers (`Core/TTC.idr:126, 129`; `Closed.idr:565-569`
  says so); §2.2 changes their type, not that. Not this design's to fix.
- O-5 (*for review*, with O-1): §3's replacement of the frontend's own
  head reduction (`Closed`'s phases) by the evaluator's head evaluation.
  If it must stay (a reason not read here), its steps need a relation of
  their own and a lemma that a step keeps the evaluator's normal form,
  which is confluence again: then the small-step relation stays beside the
  big-step one for that reduction alone, and the owner hears it.
