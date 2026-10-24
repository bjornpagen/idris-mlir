# Rederivation audit: the boundary between the checker and the frontend

Family: every fact the checker knows about a definition (its type and that
type's normal form, erasure and quantities, totality and the loops it
proved, case trees and their scrutinee types, the metavariables it solved
and the pattern variables it bound, implicit arguments, what a definition
refers to, escape hatches and holes, the registry's primitives, imports and
packages), how the TTC carries it, and every place past the TTC that
derives it again: the frontend's boundary (`Translate/Boundary.idr`), its
profile (`Profile.idr`), the growth model, the translation, Emit and the
dialect.

- HEAD at start: `b2aab6e9ba40e43debc690277bf1eeda58adcfac`
- HEAD at finish: `d73863f5e4377ce21574b94896868b12f9403fe9` (d73863f5,
  D133's design and C289, landed during the audit; it touches no code,
  and its step 4, "freeze before the walk", bears on CB-4 below, which
  says how)
- Ground. Everything is **read** from source unless marked **measured**.
  Measurements were made on the INT-24 export's frontend
  (`/tmp/int24/src/compiler/build/exec/idris-mlir-front`, built from
  a0d5c9c3, prefix `/tmp/int24/src/build/idris2`), on three 16-line
  programs under `/tmp/checker-boundary/`, with `--timing` and
  `/usr/bin/time -p`, load average 33 to 41 on 8 CPUs: walls are inflated
  and only CPU and the shape of a difference are reported. Nothing was
  built; no make ran in the checkout.
- In flight. 24 of the files below are modified in the checkout now
  (git status at finish): `compiler/checker/src/Core/{TTC,Binary,Context}.idr`,
  `Core/Termination/CallGraph.idr`, `Idris/Host.idr`,
  `TTImp/ProcessDef.idr`, `TTImp/Elab/Term.idr` (L17), and in
  `compiler/src` `Profile.idr`, `Growth/{Sites,Template}.idr`,
  `Translate/{Boundary,Cases,Choices,Closed,Errors,Instances,Programs,Shapes,State,Terms,TypeConstructors,Types}.idr`,
  `Registry/Libraries.idr` (L16), and `tools/self.sh` (L06). Each finding
  says which of its files are among them.

What the earlier boundary audit (`audits/p0/17-fork-boundary.md`) found and
the tree has since closed, checked at d73863f5 and not counted here: a
`let`'s type, `PLet`'s, `PVTy`'s and `Erased`'s reason are written
(`Core/TTC.idr:672-686`, `:760-763`); a case's scrutinee type and a leaf's
clause index are written (`:946-949`) and read (`Cases.idr:534`, `:526`);
the run-time tree is gone; a case or with block's parent is a full `Name`
(`Core/Name.idr:49-50`); `eraseArgs` is read (`Closed.idr:416-424`); a
module's package comes from the session's `Found` (`Resolve.idr:75-79`) and
its origin from the package (`Libraries.idr:83-101`, in flight, R-SPEC's
fix); imports come from the session (`importsRead`) and pragmas from the TTC
(`Profile.idr:197-215`, in flight); the checker's `paramPos` reads normal
forms (a386fe4d, `Core/Context/Data.idr:86-96`), though the frontend's
second reading stayed (CB-9).

---

## CB-1. Solved metavariables: the checker keeps a reference and a definition with no type; the frontend tells, substitutes and refuses them at every read (R-META)

**The fact.** The value of each implicit argument, auto argument and
postponed term the checker solved, and, for a pattern variable, the local
it was bound as.

**First known.**
- A metavariable's solution: `tryInstantiate` writes it as a definition of
  no arguments and one leaf, `PMDef (SolvedHole num) [] (STerm 0 rhs)`
  (`compiler/checker/src/Core/Unify.idr:513-517`).
- A pattern variable's binding: a `PV` metavariable is never instantiated
  (`Unify.idr:492-494` throws `PatternVariableUnifies`); `bindImplVars`
  maps each to a `PVar` binder, rewriting the left-hand side's references
  to locals (`TTImp/Elab/ImplicitBind.idr:240-275`), on a term
  `normaliseHoles` filled first (`:610-613`); `implicitBind` then turns the
  hole into `ImpBind` (`:300-308`).

**Dropped.**
1. The stored terms keep `Meta n i args` and not the value: a type, a case
   tree, a clause holds a reference to a definition elsewhere, and its
   index is written as 0, "needs resolving" (`Core/TTC.idr:617`).
2. That definition is a non-user name, so the TTC keeps its `definition`
   and drops its type, `eraseArgs`, `totality` and the rest: it is read
   back with type `Erased Placeholder` (`Core/TTC.idr:1436-1481`).
3. A bound pattern variable's `ImpBind` (`TTC.idr`, `Def` tag 9) records
   nothing of the local it became; `refsToLocals` rewrote only the term it
   was given, so a solution of another metavariable made while the same
   clause was elaborated still says `Meta {P:w:k}`.
4. A `PV` name's `Int` (the function it belongs to) is a session-local
   entry index written raw (`TTC.idr:126`, decoded `:99-101`;
   `Context.idr:374`, `full` leaves it): in a later session it names
   whatever is at that entry.

**Re-derived.**
- The boundary notes every metavariable any term it reads names, in types
  and erased positions alike, "read or not" (`Boundary.idr:687-706`,
  `noted`), then tells each one's definition by shape once the context is
  frozen and refuses anything but a one-leaf solution or a hole
  (`solutionAt`, `Boundary.idr:961-1018`; table `State.idr:1299-1346`).
  This is R-META (INT-24, **measured**: specgen `{P:w:3415}`, the runner
  past R-117 `{P:k5186:10215}`, the frontend past S-2 and R-UNIFY
  `{P:t:14716}`; three of five of our programs refused, at main, before
  any other check, `build/int24/summary.txt`). By reading, each is a bound
  pattern variable: a `PV` is a hole or `ImpBind` and never a solution
  (`Unify.idr:492-494`), and the probe found no hole (*read*; that it is
  `ImpBind` and not `None` or `Delayed` is the strongest reading, not
  printed by the probe).
- Correction to the probe: its "its function" for each PV
  (`boundary-probe.diff`, `probeOwner (PV _ fi) = lookupPrecise fi ...`)
  looks the PV's `Int` up in the frontend's session, where it is a
  different session's index (drop 4). "Data.SnocList.{x:7230}" is what the
  frontend's session holds at entry 3415, not the PV's function; the
  function is unknown.
- Every reader of a written form fills metavariables in again, per read:
  `solving` walks the term (`hasMeta`) and runs `host.normaliseHoles` on
  it (`Closed.idr:355-374`); every normalisation goes through it
  (`normalisedBy`, `Closed.idr:667-669`), and so do eight readers in the
  translation (`Terms.idr:565`, `:808`, `:948`, `:1173`, `:1476`, `:1817`;
  `Closed.idr:906`) and the growth model's `solving` sites.
- `solvedApplied` substitutes a solution at a meta's arguments by hand
  (`Closed.idr:376-397`, used `Terms.idr:1084`), and an unsolved one is
  refused as a hole at use (`Terms.idr:1078`, `Closed.idr:901`).
- The profile follows a solution as its own category (`Follows.Solution`,
  `Profile.idr:342-400`), reads `getMetas` again (`:336-337`), and the
  boundary's references carry `AMeta` (`Boundary.idr:89-102`).
- Cost: per run, a table of every metavariable named anywhere in what the
  program reaches; per normalisation, a full walk of the term and, where it
  has one, a normaliser run to fill it; 194 lines across 21 files of
  `compiler/src` name `Meta`, a solution or `solving` (*measured* by grep).

**The carrier.** A stored definition holds no solved metavariable: the
checker fills each solution in, and maps each pattern variable to its local,
in every term of a definition (type, case tree, clauses, patterns) once the
definition is complete and before the TTC writes it, as `bindImplicits`
already does for one left-hand side. The decoder then has a verified
property to state: a `Meta` read from a TTC names a hole. It fits the
boundary as the checker's output contract, the same form as the let types
and scrutinee types the TTC now keeps.

**Owner's question it raises.** Filling solutions in copies each one at
every use (upstream keeps metavariables as globals so its back ends compile
a solution once). The frontend already pays that copy, again, at every
normalisation; the checker paying it once is strictly less. Which form
holds a solved value is an architectural choice: the owner's.

**What the fix deletes.** `Solution`, `Solutions`, `solutionPlacement`,
`noSolutions`, `withSolution`, `solutionIn` (`State.idr:1299-1346`, 1470-1480);
`Met.metavariables`, `noted`, `solutionAt`, `solutionsOf` and its call
(`Boundary.idr:666-670`, `:701-706`, `:961-1018`, `:1168-1173`); `AMeta`;
`solving`, `solved`, `solvedApplied`, `hasMeta` (`Closed.idr:355-397`) and
their 8 calls; `Readings.Solved`; `Follows.Solution` and its arms in
`follows`/`followed` (`Profile.idr:342-400`); R-META's refusal; the
`SolvedAs`/`Unsolved` matches D133's fact 15 lists. About 230 lines, and
the per-normalisation walk.

**Owner, waits on.** L17 (`TTImp/ProcessDef.idr` M, `Core/TTC.idr` M,
`Core/Context.idr` M; `ImplicitBind.idr` not modified) and L16
(`Boundary.idr` M, `Closed.idr` M, `State.idr` M, `Terms.idr` M,
`Profile.idr` M). Waits on the owner's ruling above, and on D133's eight
steps (L17bh), which rewrite the same reader (`Host.idr` M).

**Confidence.** The refusal is measured (INT-24); every drop and rederive
site is read; that the PV is `ImpBind` is read (strong); the session-local
index is read.

---

## CB-2. The loops of each component: the checker searches them and keeps one bit; the frontend searches every component again

**The fact.** For each definition, whether the loops through it in its
component of Idris's size-change call graph decrease, and which component
that is (the dialect's `#idr.terminates<component n>`,
`compiler/spec/IdrisMLIR/Spec/Functions/Termination.idr`).

**First known.** `calcTerminating` builds the work graph from a function,
finds its components (`components`, `Core/Termination/SizeChange.idr:225-236`,
a Tarjan search keyed by `NameMap`) and runs `componentLoops` on every one
(`:463-464`, `:591`), a per-component `Loops` verdict for each member.

**Dropped.** The verdicts are reduced to `Terminating = Unchecked |
IsTerminating | NotTerminating` per function (`Core/TT.idr:316-319`): the
component and the per-member loop verdict go; the TTC writes only
`totality` (`Core/TTC.idr:1452`).

**Re-derived.**
1. The boundary runs `host.checkTerminating` for every definition its
   module left `Unchecked` (`Boundary.idr:279-289`): a whole
   `calcTerminating`, components and size-change search, per such
   definition (once each, since `settle` marks what it visited).
2. `Recursion.loopsOf` then runs its own Tarjan search over every
   definition read (`Translate/Recursion.idr:36-162`, keyed by
   `SortedMap Address`), and calls `loopsTerminate` on every component
   again (`checkComponent`, `:127-147`), to get the component the dialect
   is told (`Boundary.idr:1190`; `Emit/Closures.idr:78`,
   `Emit/Bodies.idr:520-521`).
   Every component of the program is searched twice per run, once by the
   checker (at its module's check or at the boundary) and once by
   `loopsOf`; the size-change search is the closure of call graphs, the
   costliest part of termination checking.
3. Two Tarjan implementations over one graph (FB-44, still both present).

**The carrier.** The checker's per-member verdict kept with the
definition: `Terminating` gains the component it was proved in
(`IsTerminating (component : Name)`, the component named by its least
member's full name, which is a graph property and the same in every
session), or a `loops` field beside `sizeChange`, written by
`calcTerminating` from `componentLoops` and by the TTC. The frontend reads
the component off the definition, as it reads `Ends` today; the
dialect's attribute takes it from there.

**What the fix deletes.** `Translate/Recursion.idr` but the read of the
field (about 150 of 162 lines: `Member`, `Search`, `visit`, `successors`,
`Checked`, `checkComponent`, `loopsOf`), its call (`Boundary.idr:1190`) and
the second search per component per run. `verdictOf`'s run of the checker
stays only for `Unchecked` definitions and returns both facts at once.

**Owner, waits on.** L17 (`SizeChange.idr` not modified; `Core/TTC.idr` M,
`CallGraph.idr` M), L16 (`Recursion.idr` not modified, `Boundary.idr` M),
L02 for the specification's wording (`Spec/Functions/Termination.idr`, not
modified). Waits on L17's TTC version bump in flight; D133's step 4 keeps
`Ends` as it is, which this extends.

**Confidence.** Read. The cost is not measured.

---

## CB-3. A definition's type in normal form: computed once at the boundary, dropped, normalised again at eleven sites

**The fact.** The normal form of each definition's closed type (where a
binder hidden behind a definition, as `a -@ b`, shows with its quantity).

**First known.** `frozenAs` normalises every definition read, once
(`Boundary.idr:1204`, `host.normaliseTypes fz u.type`). (The checker
normalised it first, for `eraseArgs` and `paramPos`, at its module's
visibility, and keeps neither.)

**Dropped.** `DefinitionRead` keeps the type as written (`type`) and two
things read off the normal form (`places`, `binders`), not the normal form
itself (`State.idr:1128-1140`, `Boundary.idr:1216`).

**Re-derived** (each `normaliseClosed d.type`, one evaluator run in the
frozen context, per call):
- `Closed.computesType` (`Closed.idr:1346`), from `:1425` and `:1608`;
- `Types.indexSorts` (`Types.idr:660`), per type argument's erased index
  (`:699`) and per family (`:975`);
- a constructor's layout (`Types.idr:1026`), per family instance;
- `TypeConstructors.readOne` (`TypeConstructors.idr:151-152`), per
  constructor;
- `Growth/Sites.conStands` (`Sites.idr:2101-2102`), per case alternative of
  every match site the growth model reads (`:2268`), and `Sites.idr:2180`;
- `Implementations.idr:309`, `:325`; `Fields.idr:140`, per field site;
- `checkedLibrary` (`Boundary.idr:768`), per hook row naming a library
  function, whose own `frozenAs` normalised it already, found by name
  (`foundAs`, `lookupCtxtExactI`, `:743-748`);
- `Resolve.validate` (`Resolve.idr:370-372`), per registry entry (CB-7).

**The carrier.** `DefinitionRead.normal : ClosedTerm`, the normal form the
boundary computed, which `binders` and `places` are already read off. C289
("each definition is read once from the frozen context") is the same rule.

**What the fix deletes.** Eleven normalisations of a type the reading holds
(eleven call lines become field reads), the by-name lookup in
`checkedLibrary`, and the work, which is per match alternative and per
instance at the hottest sites.

**Owner, waits on.** L16 (`Boundary.idr` M, `State.idr` M, `Types.idr` M,
`TypeConstructors.idr` M, `Closed.idr` M, `Sites.idr` M; `Fields.idr`,
`Implementations.idr` not modified). Waits on D133's step 4 (the walk reads
the frozen context once) and C281's fold (L16eo), which move the same
readers.

**Confidence.** Read. Not measured.

---

## CB-4. The definitions the program can meet: found by the reading, dropped at the freeze, which decodes every loaded definition

**The fact.** Which definitions of the loaded context the program can meet:
the reading's walk computes it (`Met.found`, `Boundary.idr:661-706`) and
says a definition outside it is the reading's miss (`State.idr:1452-1480`).

**Dropped.** `frozenContext` takes every entry of the context, 0 to
`nextEntry`, through `lookupCtxtExact`, which decodes each one still coded
(`compiler/checker/src/Idris/Host.idr`, `entriesFrom` and `frozenContext`,
about `:2885-2917` at HEAD, "An entry still coded is decoded here, once").

**Re-derived.** Every definition of every module the program loads is
decoded per compile, reached or not. **Measured** (same `main`,
`putStrLn "hello"`): with the prelude alone, `checks` 1.18 to 1.55 s wall
and the whole run 1.04 to 1.11 s user CPU; with 11 base modules that
declare no registry entry imported (`Data.List`, `Data.Vect`,
`Data.SortedMap` and eight more), `checks` 5.5 to 8.6 s wall and 1.86 to
2.08 s user CPU, while `reachable`, `growth`, `translate` and `emit` stay
where they were. Loading those modules' TTCs is part of the CPU difference
and happens before `checks`; by reading, the only part of `checks` that
grows with the modules loaded rather than with what `main` reaches is the
freeze (`entryPoint`'s one lookup of `main` and the registry validation do
not account for it: 11 modules holding about 100 registry entries cost no
more, 3.3 to 4.4 s).

**The carrier.** The frozen context holds each entry as its TTC stored it
and decodes it, purely, when read (`Stored.decode` is already pure;
`Core/Context.idr:583-641`), so only what the walk reads is decoded. This
fits D133's step 4 (freeze first, the walk reads the frozen context once);
an eager whole-context decode there would keep this cost.

**What the fix deletes.** The decode of every unreached definition per
compile; `entriesFrom`'s walk of the whole context.

**Owner, waits on.** L17 (`Idris/Host.idr` M, in the D133 rewrite), L16
(`Boundary.idr` M). Waits on D133 step 4.

**Confidence.** Measured (the scaling, on a0d5c9c3's build); attribution
read.

---

## CB-5. What a definition refers to: the checker computes it and the TTC keeps it unread; the boundary walks it and drops it; the profile walks and decodes it again

**The fact.** The names a definition's case tree and type refer to,
metavariables among them.

**First known.** `calcRefs` (`TTImp/ProcessDef.idr:670-686`: "what its
compile-time tree, the program the frontend translates, refers to"), the
tree's references and metavariables, kept by the TTC (`Core/TTC.idr:1442`);
the type's references are `getRefs` of the type (`Core/TT.idr:786-787`).

**Dropped.** The frontend reads `refersTo` nowhere (*measured*: no match
for `refersTo` in `compiler/src`). The boundary computes each definition's
references again (`referred`, `references`, `termRefs`, `treeRefs`,
`patRefs`, `Boundary.idr:89-188`, `:242-250`), follows them, and keeps
nothing of them in `DefinitionRead`.

**Re-derived.**
- `Profile.refsOf` walks the type and the tree a third time with `getRefs`
  and `getMetas`, decoding both again from the stored definition
  (`typeOfDefinition`, `caseTreeOf`: `Stored.decode` per call), and
  resolves each to a full name (`Profile.idr:330-341`, `:567`), per
  definition the profile walk enters; it decodes the tree once more for
  `%MkWorld` (`:580-583`), and looks each library reference up by name in
  the live context (`proofOnly`, `:320-325`).
- The same re-decode of what the boundary read, elsewhere:
  `Template.callRead` (`Growth/Template.idr:1199-1203`, tree and type),
  `definitionRoot` (`:2168-2170`, type), `leafRoots` (`:2228-2233`, tree),
  each through `inFrozen` by name; `Sites.parameterNames`
  (`Growth/Sites.idr:2343-2351`, two types, and a constructor by name in the
  live context); `Keys.rolesIn` (`Translate/Keys.idr:524-526`, by name in
  the live context).

**The carrier.** `DefinitionRead.refers : List Referent`, what `referred`
computed, kept with the definition; the profile and every reader take
`d.type` and `d.matched` from the reading, never `d.def`. If the checker's
`refersTo` is extended to the type's references, the boundary reads it in
place of `references` (the checker is ours).

**What the fix deletes.** `refsOf` (about 12 lines) and `proofOnly`'s
lookup; the profile's second tree decode; seven decodes of a type or tree
the reading holds; three by-name lookups in the live context. With the
checker's `refersTo` read: `termRefs`, `treeRefs`, `altRefs`, `patRefs`,
`references` (about 75 lines).

**Owner, waits on.** L16 (`Profile.idr` M, `Boundary.idr` M,
`Template.idr` M, `Sites.idr` M; `Keys.idr` not modified), L17 for
`refersTo` (`ProcessDef.idr` M). Waits on D133 step 4 (the walk reads the
frozen context once) and C281's fold.

**Confidence.** Read.

---

## CB-6. Escape hatches and holes: elaboration resolves each and throws the fact away; the profile reads and lexes every user source again

**The fact.** Where a user module refers to an escape hatch
(`believe_me`, `prim__believe_me`, `idris_crash`, `prim__crash`, any
`%unsafe` definition) or writes a hole.

**First known.** The elaborator resolves every name reference and asks
`isEscapeHatch def` there (`TTImp/Elab/App.idr:86-92`), computing a
`Postulate` decoration at the reference's span; every hole is a `Hole`
definition, and the TTC keeps the module's holes (`userHoles`,
`Core/Binary.idr:222`).

**Dropped.** The decoration is passed to `addSemanticDecorations`, which
does nothing (`Core/Metadata.idr:10-16`, `:139-142`): the checker keeps no
use site, and a reduction may erase the reference from TT
(`Profile.idr:238-243`).

**Re-derived.** Per compile, for every user module: the source file is read
whole (`readText`, `Profile.idr:231-237`), lexed with Idris's lexer, and
every identifier's text looked up in a text-keyed table of spellings
(`checkSpelled`, `Profile.idr:244-273`; `spellings` and `spellingHooks`,
`Registry.idr:42-58`; four `spelling` entries, `Registry/Recognized.idr:289-292`),
each found spelling interned and threaded into the reachability walk to be
told apart again (`spelled`, `Profile.idr:264-266`, `:634`). A text
match cannot tell the escape hatch from a local of the same name, which the
elaborator's resolution does. Beside it, `checkModule` re-reads each user
module's TTC from disk with `readall = True` (`readDefinitions`,
`Core/Binary.idr:312-320`, `Profile.idr:200`) to get its pragma uses, which
the session read when it loaded that TTC and dropped.

**The carrier.** The checker records each resolved escape-hatch reference
(definition and span) and each hole in a user module, kept by the TTC
beside `pragmaUses` (in flight, `Core/Binary.idr:58`, `Idris/Syntax/Pragmas.idr:12-15`),
and the session keeps each loaded module's uses with its `importsRead`.
The profile reads them as it now reads pragmas.

**What the fix deletes.** `checkSpelled`, `readText`, the lexer import, the
`spelled` state and its test in the walk; `spellings`, `spellingHooks`, the
four `spelling` entries; the per-module TTC re-read. About 70 lines, and a
read and a lex of every user source per compile.

**Owner, waits on.** L17 (`TTImp/Elab/App.idr` not modified,
`Core/Binary.idr` M, `Core/TTC.idr` M), L16 (`Profile.idr` M, `Registry.idr`
and `Registry/Recognized.idr` not modified). Waits on the in-flight
pragma-uses change landing (same files).

**Confidence.** Read.

---

## CB-7. The registry checked against the pinned libraries' types on every compile, by printed names

**The fact.** That each registry entry's definition in prelude or base has
the shape the entry states.

**First known.** When the prefix is built: the registry is static, and the
libraries are pinned and installed once (`front-prefix` in INT-24's
terms).

**Dropped.** Nothing records it: a compile holds the registry as text
(`QName`, `Registry/Name.idr:13-17`) and the libraries as TTCs.

**Re-derived.** Per compile: `readRegistry` interns each entry's text and
resolves it (`Resolve.idr:291-301`); `validate` decodes each entry's
definition in a loaded module, normalises its type and compares
`shapeOf` it, a `Shape` whose every head is a printed name
(`qname`, `show n`, `Resolve.idr:43-46`, `:239-250`, `:343-400`), with
`inModules`' text compare over every loaded module for each absent entry;
`foreignHooksAt` scans every site and parses spec strings per `%foreign`
definition read (`Resolve.idr:319-330`, `Registry.idr:61-63`).

**The carrier.** The validation runs when the prefix is installed (the
step that builds prelude and base for the frontend), so its result is a
property of the installed prefix, and the registry's keys name a package
module as `moduleOrigin` already classifies modules (`Home`), so a user's
own definition is never an entry. The per-compile check, and the test
that gives it a user module defining a keyed name, go.

**What the fix deletes.** `validate`, `shapeOf`, `inModules`' use, the
`SiteCheck` reading (about 90 lines of `Resolve.idr`) and the per-compile
normalisations. Not the hooks' reading against a reached definition
(`rowOf`), which reads the definition the program reaches.

**Owner, waits on.** L16 (`Resolve.idr`, `Registry/*` not modified;
`Libraries.idr` M), L19 for the validation's test, INT for the prefix
install step (`Makefile`). Waits on nothing; the coordinator settles where
the check runs (AGENTS.md: no static fact paid at compile time).

**Confidence.** Read. Measured that it is not the dominant per-module cost
(CB-4's comparison).

---

## CB-8. A nested definition's parent, and a pattern variable's function, written as another session's entry number (correctness)

**The fact.** The definition a `where` or `let` function belongs to, and
the function a pattern variable belongs to.

**First known.** `Nested (outer, nextName ust) inner`, `outer` the parent's
resolved entry in the session that elaborates it
(`TTImp/Elab/Local.idr:85-90`); `PV n (defining est)` likewise
(`ImplicitBind.idr:437`, `App.idr:187`).

**Dropped.** Both `Int`s are written raw (`Core/TTC.idr:126`, `:129`) and
kept raw by the full-name conversion (`Core/Context.idr:362-374`), though
the TTC refuses to write a `Resolved` name (`TTC.idr:132-133`) and a case or
with block's parent is now a full `Name`. In any later session the number
names an unrelated entry.

**Re-derived.** `Boundary.parentOf (Nested (outer, _) _) = Just (Resolved
outer)` (`Boundary.idr:183-188`) adds that entry to the reading of every
nested definition (`referred`, `:242-247`), so the reading reads a
definition the program does not reach, and its metavariables are noted and
told (CB-1). `Closed.rootOf` climbs it under a walk that exists because,
its comment says, the parents "can lead anywhere, even back to a definition
passed already" (`Closed.idr:562-593`); `endsOf` reads the root per name
per normalisation (`:595-606`, `:648-656`), so a block's verdict can be an
unrelated definition's; the profile tells a trusted module's admission by
that root (`Profile.idr:564-566`); the checker prints it in messages
(`Context.idr:1879-1882`). Whether R-META's three refusals are reached
this way (an unrelated solved metavariable read through a stale parent) is
a **conjecture**, untested.

**The carrier.** `Nested : (parent : Name) -> (ordinal : Nat) -> Name ->
Name`, the parent written full as `CaseBlock`'s is; `PV` likewise carries
its function's name. A parent is then a subterm of its child's name, so the
climb is structural.

**What the fix deletes.** `rootOf`'s walk and its comment (about 20
lines, the climb becoming structural recursion on the name), the
`Resolved outer` arm, the per-query climb's lookups, the reading of
unreached definitions through a stale parent, and the probe's misreading.

**Owner, waits on.** L17 (`Core/Name.idr`, `TTImp/Elab/Local.idr` not
modified; `Core/TTC.idr` M), L16 (`Boundary.idr` M, `Closed.idr` M,
`Profile.idr` M). Waits on L17's TTC version bump in flight. It should go
before CB-1's ruling, since it may be what reaches R-META.

**Confidence.** Read (the raw writes, the frontend's reading, its own
comment). The consequences are conjecture.

---

## CB-9. A type's parameters: the checker's reading fixed, the frontend's second reading kept

**The fact.** Which positions of a type constructor are parameters.

**First known.** `paramPos`, on the constructors' types in normal form since
a386fe4d (`Core/Context/Data.idr:86-96`), kept as `TCon`'s `parampos`.

**Re-derived.** `dataParams` (`TypeConstructors.idr:156-208`) takes Idris's
set and, when it lacks a position, finds more on the normal forms, "those
its own reading of the constructors' types misses because a type hides its
binders behind a definition": the case the checker's fix removed.

**The carrier.** `parampos` alone.

**What the fix deletes.** `dataParams`' fallback and its helpers (about 45
lines) and the stale comment.

**Owner, waits on.** L16 (`TypeConstructors.idr` M). Nothing else.

**Confidence.** Read; that the fallback never fires now is conjecture (the
two normalisers run at different visibility: the checker's at the module's,
the frontend's in the frozen context), and the first build that runs it
should say so.

---

## CB-10. A package's dependencies restated in `tools/self.sh`

**The fact.** What `idris-mlir-checker` depends on (`mlir-linear`,
`mlir-array`), in its ipkg (`compiler/checker/idris-mlir-checker.ipkg:10`).

**Re-derived.** The in-flight `self.sh` lists them by hand beside the
frontend's own (`-p idris-mlir-checker -p mlir-linear -p mlir-array -p
idris-mlir-spec -p mlir-hash`, S-2's fix), since `-p` loads one package, as
upstream's does. A new dependency of the checker breaks stage 1 again, as
S-2 did.

**The carrier.** The ipkgs: `self.sh` derives the list from
`compiler/idris-mlir.ipkg`'s and each depended package's `depends`, or
runs the frontend through the package as `make frontend` does.

**What the fix deletes.** The hand list (one line) and the class of S-2.

**Owner, waits on.** L06 (`tools/self.sh` M). Nothing else.

**Confidence.** Read.

---

## Covered by sibling reports, not counted

- Erasure decided from `eraseArgs` and again from the binder's quantity
  (`multiplicities.md` R7). Two more sites of the same fact: a hook row's
  operands and a library function's are counted off the Pi quantities of
  the normal form (`Resolve.operandsOf`, `operandsUpTo`,
  `Resolve.idr:498-518`, called `Boundary.idr:741`, `:769`), not from
  `eraseArgs`.
- Nat-likeness (`types-layouts.md` 5); Emit's re-count of uses
  (`multiplicities.md` R1, C286).

## Checked, not a finding

- `Cases.instanceOf` reads the scrutinee's family off its binder's types,
  which the environment carries; `scTy` is read where the binder has no
  family (`assumed`, `Cases.idr:691`).
- `natPlusName` and `ioName` are resolved once, at the boundary
  (`Boundary.idr:1086-1094`, `:1159-1167`, in flight).
- `Translate/State.nameKey` prints names for messages only.
- The registry's spec strings are the libraries' own text (Idris's backend
  contract); comparing them is essential once per `%foreign` definition.
- `interfaces` (`Program.idr:186`) is the session's set of interface
  names, kept by the checker with its syntax; read once.

---

## Table

| # | Fact | Drop site | Rederive sites | Carrier | Lines deleted | Owner | Waits on |
|---|------|-----------|----------------|---------|---------------|-------|----------|
| CB-1 | A solved metavariable's value; a pattern variable's local | `Meta` refs kept (`Core/TTC.idr:617`); non-user defs lose type etc. (`TTC.idr:1436-1481`); `ImpBind` keeps no local (`ImplicitBind.idr:300-308`); PV's `Int` raw (`TTC.idr:126`) | `Boundary.idr:687-706,961-1018` (table, R-META refusal, measured on 3 of 5 programs); `Closed.idr:355-397` (`hasMeta` + `normaliseHoles` per read) and 8 `solved` calls; `Terms.idr:1078-1084`; `Profile.idr:336,342-400` | Stored definitions hold no solved metavariable: the checker fills solutions and binds PVs in every term before the TTC writes (a decoder-verified property) | about 230, plus a walk per normalisation | L17, L16 | owner's ruling; D133 steps (L17bh) |
| CB-2 | Each component's loop verdict | `Terminating` keeps one bit (`Core/TT.idr:316-319`, `TTC.idr:1452`) | `Boundary.idr:279-289` (`checkTerminating` per unchecked); `Recursion.idr:36-162` (second Tarjan, `loopsTerminate` on every component again) | `IsTerminating component`, or a `loops` field, from `componentLoops` (`SizeChange.idr:463,591`) | about 150, and a second size-change search per component per run | L17, L16, L02 | L17's TTC bump |
| CB-3 | A definition's type in normal form | `DefinitionRead` keeps the written type (`State.idr:1128-1140`; computed `Boundary.idr:1204`) | `Closed.idr:1346`; `Types.idr:660,1026`; `TypeConstructors.idr:152`; `Sites.idr:2102,2180`; `Implementations.idr:309,325`; `Fields.idr:140`; `Boundary.idr:768`; `Resolve.idr:370` | `DefinitionRead.normal` | 11 normalisation calls (per alternative, per instance) and a by-name lookup | L16 | D133 step 4; C281 fold |
| CB-4 | What the program can meet | `frozenContext` takes every entry (`Idris/Host.idr`, `entriesFrom`) | every loaded definition decoded per compile (measured: +0.8 to 1.0 s CPU, `checks` 1.2-1.5 s to 5.5-8.6 s wall, 11 base modules, same `main`) | Frozen map decodes an entry when read (`Stored.decode`, pure) | the eager decode per compile | L17, L16 | D133 step 4 |
| CB-5 | What a definition refers to | `refersTo` unread (`TTC.idr:1442`); `referred` not kept (`Boundary.idr:242-250`) | `Profile.idr:320-341,567,580-583`; `Template.idr:1199-1203,2168-2170,2228-2233`; `Sites.idr:2343-2351`; `Keys.idr:524-526` | `DefinitionRead.refers`; readers take `d.type`/`d.matched` | about 12 to 90, and 7 re-decodes, 3 name lookups | L16, L17 | D133 step 4; C281 |
| CB-6 | Escape hatches and holes a user module uses | `addSemanticDecorations` a no-op (`Metadata.idr:139-142`; computed `App.idr:86-92`) | `Profile.idr:231-273` (read and lex every user source, text table `Registry.idr:42-58`); TTC re-read for pragmas (`Profile.idr:200`) | Per-module uses in the TTC beside `pragmaUses` | about 70, and a read and lex per user source per compile | L17, L16 | in-flight pragma-uses change |
| CB-7 | Registry entries fit the pinned libraries | not recorded | `Resolve.idr:291-400` per compile (decode, normalise, printed-name shapes) | Validated at prefix install; entries keyed by package module | about 90 | L16, L19, INT | coordinator's placement |
| CB-8 | A nested function's parent; a PV's function | raw session-local `Int` (`TTC.idr:126,129`; `Context.idr:374`) | `Boundary.idr:183-188,242-247`; `Closed.idr:562-606` (climb under a walk, per normalisation); `Profile.idr:564` | `Nested (parent : Name)`, `PV` with its function's name | about 20, and reads of unrelated definitions (correctness) | L17, L16 | L17's TTC bump |
| CB-9 | A type's parameters | (none: checker fixed, a386fe4d) | `TypeConstructors.idr:156-208` | `parampos` | about 45 | L16 | none |
| CB-10 | A package's dependencies | ipkg not read by `-p` | `tools/self.sh` hand list (in flight) | the ipkgs | 1 line, and S-2's class | L06 | none |

The three findings whose fix deletes the most:

1. **CB-1**, solved metavariables. The checker keeps a reference to a
   definition whose type the TTC drops, and leaves bound pattern variables
   as `ImpBind` references inside other solutions; the frontend keeps a
   table of every metavariable named anywhere, refuses what it cannot tell
   (R-META, three of five of our programs), and fills solutions in again at
   every normalisation. Filling them in at the checker deletes about 230
   lines and a walk per read; which form holds a solved value is the
   owner's ruling.
2. **CB-2**, loop verdicts per component. The checker searches each
   component and keeps one bit; the frontend runs the checker again for
   unchecked definitions and then a second Tarjan search and a second
   size-change search over every component. Keeping the component on the
   verdict deletes `Recursion.idr` (about 150 lines) and half the search.
3. **CB-3**, a definition's normal type. The boundary normalises each type
   once and drops it; eleven sites normalise it again, the busiest per case
   alternative and per instance. One field deletes the evaluator runs.

CB-8 is ranked by its deletions, but it is a correctness defect: a nested
definition's parent and a pattern variable's function are another session's
entry numbers, so the reading follows them into unrelated definitions. It
may be what reaches R-META, and should be fixed before CB-1 is ruled on.
