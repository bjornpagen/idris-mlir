<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The fold: C281's annotated tree, and the translation as its fold (L16eo's design)

L16eo wrote this at e518e35c (C281's commit), for the coordinator's review
before any lane implements it. It replaces items 1 to 4 of L16ej's plan
(`L16-threading-design.md`: Terms and Cases threading `here` beside their
term, `request` choosing its entry among a place's by what it reaches) and
restates its items 5 to 9 over the tree. Nothing below is in the tree. Each
claim is marked read, measured or conjecture; a choice of core shape is
marked *for review*, since AGENTS.md gives it to the owner.

## 1. What is decided where at e518e35c (read)

The model. `Sites.readingOf` and `Sites.sitesOf` walk each definition once
per node (its address and the type constructor heading each of its
families, `Graph.readings`), every parameter a marker, and make a `Site`
at each place they meet (`Made`), grown into a `Grown Site` in the text's
shape (`Place.grownFrom`). `Graph.numberedReadings` numbers every site
once (`Entry`); `Graph.build` visits nodes from main (`nodesFromMain`,
following `Heads.reaches`), draws the model's sites (`Built.kept`, each
with the `Wrote` that made it) and drops those landing at a capped position
(`uncappedDrawn`). `Growth.checkGrowth` writes `TS.bounds`, `TS.sizes` and
`TS.growth : SiteTable`. The model over-approximates: where only an
instance decides (`Holding.ByInstance`, a binder the type shows only past a
marker), it walks both ways (`Sites.walkedAt`'s `decided ByInstance`,
`useAt`'s `past`).

The translation reads no site: `SiteTable`, `Grown` and `membersOf` have
no reader in `Translate/` outside `State` and `Place`. It requests from its
own term walk at seven points, and registers what arms read at an eighth:
- `Programs.mainInstance` (the root);
- `Terms.applyDefined.call`: `classifyKeys` over `argValueIn`, then
  `resolveMethod` (a method of a fixed dictionary settled in place, so the
  field's body is walked inside the caller) or `Choices.calleeAt`;
- `Terms.applyAtUse` (a form applied at a use: `AtUse`);
- `Terms.applyDefined.libraryCall` (a hook's library function);
- `Cases.staticCase.heldHere` (the same instance, its dictionary rebuilt);
- `Choices.dispatchOn` and `armsFor`/`givenArm`, and `Choices.added`'s
  `armAt` (an arm requested in whichever step meets the later of the
  member and the dispatch, and `heldDispatch`'s arms through `heldMember`);
- `Types.familyIn`, from every `coreType` that meets a data type;
- and, not a request but a registration the arms read,
  `Choices.memberBare`/`memberHolding`, from `Terms.member`.
Each key comes from `argValueIn` (`closeNormalise`, `solved .
closeWritten`, `holed`), classified by `offeredAt` (`keyingOf`, `fixedAt`,
`argumentShape`/`neededShape`), read by `supplying` and keyed by
`instanceFor`. The bounds are checked at run time: `Finite.requestedUnder`
calls `heightWithin` on `Request.positions` (`Instances.boundedAt`: the
node built from the readings' heads, looked up in `TS.bounds`) and
`sizedWithin`; `Types.familyIn` calls `boundsHold` and `sizedWithin`.

What that run-time check catches, by reading, and so what C281's deletion
must make unrepresentable or prove:
1. a key above its position's bound: the reading lemma's open steps
   (`Proof/Covers.idr`'s list);
2. a key at a node the model never visited: an instance whose values head
   a family or root a dictionary the flow did not give (`boundedAt`'s node
   has no entry in `TS.bounds`, "has no bound");
3. a position the instance keys that no site keys at that node (the model
   read the binder past what its markers show, `staticsOver`'s
   `PastBinders`, and the instance's type shows a universe there);
4. a link outside the universe's sizes.
L16ej's step 8 covers 1 and 4; 2 and 3 are new obligations of this design
(§5).

Found while reading (measured on HEAD's frontend, L16em's `new5`
executable): the check fires on a valid program. A runtime argument keyed
by its shape is walked by the model as a static value only
(`Sites.walked`: `AsStatic _` forces `asStatic`), and a static walk
requests no function that gives no implementation (`Sites.staticRef`), but
the translation passes the argument at run time and translates it as code
(`Terms.applyDefined.valueAt`), so a call inside it has no site. Twenty
lines, `/tmp/l16eo/repro/shape-call/Main.idr` (`describe (S (count xs))
"three"`, `describe`'s type reducing on its `Nat`): `INTERNAL ERROR: ...
the growth check is unsound: Main.count[Int], requested in Main.main, has
no bound at its argument 1`. The model must walk a shape-keyed argument as
code too; under this design it is the first node step 2 finds missing.

## 2. The annotated tree (for review: its shape)

### 2.1 The principle

The model's walk already reaches every place the translation requests at,
in the text's shape. Three things change. A node holds the constructor of
the term or case tree it stands at, with its children, so the translation
walks the tree and never a term beside it. Each request is a field of the
node whose role it is (the call's request, the types a binder builds, the
member a lambda makes), never an entry of a place's list chosen by what it
reaches. And what only an instance decides is a sum node holding every
alternative the model walked, which the instance chooses among with
evidence that its choice is one of them (§2.4).

### 2.2 The types

They live in a new `Translate/Annotated.idr`, below `State` (which holds
them in `SiteTable` and `Request`) and above `Place`, `Readings` and the
`Proof` modules. `SiteTable` splits in two: what the graph drew, and the
readings.

```idris
||| What the graph drew, all erased but the count: the graph, its model, how
||| many sites every reading holds, and each model site with what wrote it.
record Drawing where
  0 graph : Graph
  0 model : Model graph
  entries : Nat
  0 kept : List (Bound.Site graph.size, Wrote entries)
  0 keptSites : model.sites = map fst kept

||| A request the model decided at one site, by the role it has there
||| (`reach`, the `SiteReach` constructor as an index): the site, numbered,
||| and per argument its evidence (`Keyed`), at quantity 0. Only the graph's
||| builder makes one: its evidence names the model's kept sites, which no
||| reader can forge.
record Decided (d : Drawing) (reach : Reach) where
  entry : Entry d.entries
  0 reaches : ReachOf entry.site.reach = reach
  callees : Callees d reach entry        -- what it reaches, per §2.4

||| Per argument of a decided site, against one callee alternative: the
||| model site it wrote there (`DrawnFrom`, from `membersOf`), or, at a
||| capped position, the cap, which bounds it in place of a site.
data Keyed : (d : Drawing) -> Fin d.entries -> Argument -> (target : Spot) -> Type where
  Drawn : (from : DrawnFrom d e) -> (0 _ : from.argument = x) -> (0 _ : landsAt from = target) -> Keyed d e x target
  Capped : (p : Fin d.graph.size) -> (0 _ : index p d.graph.caps = Just c) -> (0 _ : spotOf p = target) -> Keyed d e x target
```

(`DrawnFrom` and `membersOf` move from `SiteTable` to `Drawing`, which is
all they read.)

The term and case tree families mirror the model's walk (`Sites.term`,
`static`, `useOf`, `computedField`, `settledWalk`, `tree`), one constructor
per step it takes, in scope `vs` as the translation's environment is
(`StandsFor kc sp vs`):

```idris
mutual
  data Code : Drawing -> Scope -> Type        -- a term walked as code
  data Static : Drawing -> Scope -> Type      -- walked as a static value or a type
  data UseWalk : Drawing -> Scope -> Type     -- a member applied at a use (`useOf`)
  data Tree : Drawing -> Scope -> Type        -- a case tree (`Sites.tree`)
  data Arg : Drawing -> Scope -> Taking -> Type
```

with, in outline (each constructor keeps the `TT` it stands at, which code
generation still reads through `closeNormalise`, as C257 keeps):
- `Code`: `Inert (TT vs)` (a type, a constant, an erased part: no step);
  `Variable` (a variable applied: `Applied` below); `AtDefinition`
  (a reference applied, `AtRef` below); `LambdaCode` (binder type as
  `Static`, scope as `Code` one deeper); `LetCode` (a runtime `let`: value
  `Code`, type `Static`, scope); `LetForm` (a `let` of a dictionary or a
  polymorphic function: value `Static`, its `UseWalk` where its choice is
  applied at a use, its `Keeps` decision where it closes over values,
  scope); `Solution` (a metavariable's solution, walked once on its path);
  `DelayCode`, `ForceCode`, `AsCode`; `AppliedLambda` (a lambda applied:
  the argument as its binder takes it, then the body).
- `AtRef vs` by the definition's kind, the one switch the problem has:
  a function's `Call` (`Decided d Calls`; the member it gives,
  `Maybe (Decided d Makes)`, present where `givesAfter` is `AMember` or
  `ByInstance`; its hooks' `Decided d Calls`; its arguments as
  `Arg d vs taking`; a method call's `MethodCall`; the arguments past its
  arity as `OverType`); a constructor's `Construct` (`Decided d Calls`
  where it holds or builds a dictionary, `Decided d Builds` for its result
  type, the dictionaries' computed fields); a primitive's, an extern's,
  a hole's, each with what the model wrote there.
- `Arg d vs taking`, indexed by the model's decision for that argument
  (`Sites.Taking`, with the member table's `Holding` folded in): a static
  argument's `Static` walk; a runtime argument's `Code`; a member's
  `Decided d Makes` with its `UseWalk` and its `Code`; `ByInstance`'s both,
  as a sum the instance chooses (§2.4); nothing at an erased one. So the
  translation never takes a mode the model did not walk.
- `Tree`: a leaf (`Code`, and the result member's `UseWalk`); `Unmatched`;
  `Impossible`; a match: per alternative its tree, a default's expansion
  per constructor it stands for, and the `Decided d Repacks` where the
  match takes a field of the writer's dictionary apart (`Sites.repacked`).

A reading is one node's: its signature (the `Decided d Builds` of each
runtime binder's type and the result's), its tree, and its type
constructor's fields where it is one (`Fields.fieldSites`). Readings are
numbered once, as entries are, and referenced by number: `SiteTable`
holds `readings : Vect r (Reading d)` and the root's number, so a
reference is a `Fin r` and `index` never misses. `trees : SortedMap Node
...` goes; nothing looks a node up.

### 2.3 Why neither a visit with no node nor a node out of reach exists

- Every request function takes a `Decided d reach` of its role (§4), and
  only a node yields one: its evidence is erased membership in
  `d.kept`, which no code without `believe_me` can make up. The old
  request paths (`classifyKeys` at a call, `instanceFor` over kinds a
  call classified itself) are deleted, so a request with no node does not
  type-check.
- A `Decided d Builds` cannot be given where a `Decided d Calls` is
  asked: the role is an index.
- The fold is a total function over `Code`, `Static`, `UseWalk`, `Tree`
  and `Arg`, so every node kind has its case, and an argument's index
  (its `Taking`) says which walk of it exists. What an instance never
  visits is either an alternative of a sum it chose against (essential: the
  model walks every alternative of a match and both ways where only an
  instance decides) or a site no instance of the program reaches, which
  bounds nothing extra wrongly: it only widens the model.

### 2.4 The choices only an instance makes

A node is a definition's text read at a node's heads; an instance is that
text at its values. Where the values decide, the node holds every
alternative the model drew, and the instance chooses with erased evidence
that its choice is among them, by a function that walks the alternatives
and refutes the empty list with that evidence (no `Maybe`):

| Choice | The node's alternatives | The instance's key | Evidence it is among them |
| --- | --- | --- | --- |
| a callee's node | `Heads.reaches`' visits for the site (`combinations`) | the roots of the values it puts in | `HeadsHold` (§5.2) |
| an argument's evaluated reading | `Graph.evaluated`'s readings, one per choice of closed family values | the values its families take | `LandsHold` (§5.2) |
| a dictionary fixed or chosen | both: the request with the argument's `Static` walk, or the argument's `Code` walk and a dispatch whose arms instantiate the same node at each member (§3.3) | `fixedAt` on the value put in | none: both are present |
| a shape or none | both, the argument's `Code` walk in each (it is a runtime value either way) | `argumentShape` on the value put in | none |
| a member or code (`ByInstance`) | both walks | `typeHolding` on the instance's type | none |
| a method's implementation (`Dispatches`) | `Heads.runs`' implementations, and the hand-written fields of a dictionary built in code | the root of the dictionary | `HeadsHold` |
| a dispatch's arm | the choice's members, each registered at its `Makes` node | each member as it is registered | by construction (§3.3) |
| a form's making walk | the form's handle (§3.2) | carried with the value | by construction |

The first, second and sixth rows are what the run-time check catches as
case 2 of §1 today.

## 3. Where the model decides each request kind

The request at a node is fixed by the model: its callee alternatives, its
static positions with their kinds, the term written at each (over the
writer's markers and the site's stand-ins) and each one's `Keyed`
evidence. What the instance computes is the request's instantiation
(§4.1): each keyed argument as C257 says, from the node's term with the
instance's values put in, by one function the lemma is stated over.

### 3.1 Calls, builds, the root and library calls

- `Sites.callSite` (a call, its `Calls` site) and `Sites.builds` (a type's
  `Builds` sites) decide these now; the node field holds the decision.
- The root is `main`'s reading, at the table's root number; its request
  keys nothing.
- A hook's library function is `Sites.hookCalls`' `Calls` site, keyed by
  nothing.

### 3.2 Member-at-use bodies and settled forms: the form handle

`translateApplication` translates an `AtUse` instance from no
definition, and `Terms.implementationAt` settles a fixed form in place:
both walk a form the instance holds as a value, made elsewhere. The model
walks what such a form's body requests at a use once, where the form is
made, its use's arguments the application's positions (`Sites.useOf`,
`Parameters.UseFrom`, `Arg.asUse`); a dictionary built in code has its
hand-written fields walked there too (`dictionaryArguments`).

So a form carries a handle to that walk: the `UseWalk` subtree at its
making node (or its settled walk, `SettledForm`), with what the fold
needs to read it (the maker's values for its markers, and which of the
held values each runtime value it closes over is). The handle is made
where the form is made (a `LetForm`, an applied lambda's argument, a
`Makes` node, a static argument written as a term) and travels with the
value: an environment entry that holds a form (`Static`, `BoundHere`)
holds its handle, and a request that keys a parameter with the writer's
own parameter as it is passes that parameter's handle on, so each
instance's dictionary parameters hold theirs (`Request` per keyed
dictionary position, §4.2).

Then:
- `Terms.implementationAt` in the written phase folds the handle's walk in
  place, the use's arguments bound once (D128); the requests in it are the
  maker's use-walk sites, at the maker's values and the use's positions,
  which the use's `Applies` site writes (`Sites.implementationAt` writes it
  beside the settled walk).
- An `AtUse` request carries its form's handle (position 1's), and
  `translateApplication` folds it.
- Instances shared by content across places: an instance's identity stays
  its link (content). Two requests of one link from two making places are
  one instance, translated once, folding the handle of the first request
  the worklist takes, as today's translation walks the first request's
  form; the other request's handle is unused. A handle is decided once per
  making place and referenced from every value that came from there.

Open (O-2, §8): whether the use walk is over the maker's scope (as
`useOf` walks today) or over the form closed with hole markers.

### 3.3 Dispatch arms

The model already draws them, under the call's own site: a dictionary the
running program chooses is written at the callee's position as its choice
(`asGiven (Just head)`: `Member k`, or the writer's parameter `Var i 0`
where that parameter is itself a choice, which a caller's `Member k`
reaches through the landings), and every `Makes` site of head `k`
writes its member at the choice's position, program-wide
(`Graph.choicePositionsOf`, C219). So an arm is the call's node
instantiated once more: at the requester's values, with the member's form
put in for the chosen argument (for the writer's own parameter, for its
marker). Its keyed arguments are drawn from the call site as the plain
request's are; at the chosen one, the member's value at the choice's
position is the member's own derivation at its `Makes` node.

- A member is registered at its `Makes` node: `memberBare` and
  `memberHolding` take the `Decided d Makes`, and `ChoiceMember` keeps it
  with the member's instantiation (its form with the maker's values put
  in, its `HeldAs`, at quantity 0 the maker's `MarkersHold`), beside the
  dictionary reading C259 registers.
- A dispatch keeps its call site's `Decided d Calls` and the requester's
  instantiation (`Dispatch` gains them, O-5).
- `armAt d i m` instantiates the dispatch's node at the requester's values
  and member `m`: an arm requested in a later step, or in `dispatchers`,
  reads both nodes and decides nothing.
- A held dispatch's arm (`heldDispatch`, `heldMember`) is the `Repacks`
  node (§3.6) instantiated at the writer's values and the member put in at
  the held field's place, as `Heads.reaches`' `rebuiltAt` draws it (its
  lists `EachOf` and `MembersOf`).

C281 says "a dispatch's arms are nodes under its site". Read here: an arm
has no node of its own, since members are the translation's, found as it
goes; it is its site's node instantiated at one more value, which the
model bounds through the choice's position. If C281 meant a tree node per
arm, the model would have to enumerate members before the translation,
which it cannot (they are made at instances).

### 3.4 Capped positions

`Graph.uncappedDrawn` keeps no site into a capped position, so
`membersOf` gives a capped argument none. Its `Keyed` evidence is
`Capped p cap`. The instantiation's shape cut (`neededShape`, `cutShape`)
returns `CutWithin ctx c held` against that cap (`Template.cappedPlaced`
needs nothing more), which holds because `Caps.capOf` and `neededShape`
read the one type the same way; that is a lemma to write
(`cutWithinCap`), not a trust.

### 3.5 Data family registrations

`Types.familyIn` registers a family wherever `coreType` meets a data type,
and re-checks it with `boundsHold` and `sizedWithin`. Each registration
becomes a `Decided d Builds`: the model's `Builds` sites (`Sites.builds`
in an argument, a binder's or a `let`'s type, a constructor's result; a
definition's signature; a type constructor's fields, `Fields.fieldSites`)
target the type constructor's node with no heads, whose reading holds its
constructors' field types, so a registration's nested registrations fold
that reading's fields. `coreType`, `coreBinder`, `dataOf` and
`dataFamilyOf` take the `Builds` decision of the type they read, so every
call site with no node is found by the compiler, and each is given its
node or shown to read a type no data family heads (the packed types of
held values, `pack`'s, are `OfType` held items of the argument that holds
them, C258). `Types.Registering`'s chain stays; its step's universe
membership comes from the decision (§5) instead of `sizedWithin`.

### 3.6 Repacks, dispatches through a dictionary parameter, keeps

- `Cases.heldHere`'s request is the reading's `Decided d Repacks` at that
  match (`Sites.repacked`); its callee alternatives are `Heads.reaches`'
  `rebuiltAt` visits.
- A method call on a dictionary parameter is a `MethodCall` node holding
  the `Dispatches` decision (`Sites.dispatch`, `projectionSite`); at an
  instance whose dictionary is fixed, `resolveMethod` follows the
  alternative its root selects (the implementation's method function, with
  its leading parameters, as `Heads.reaches`' `method` draws it, or a
  hand-written field's handle); at one where it is chosen, the dispatch.
- A binding that closes over values holds its `Keeps` decision, and the
  pair's projections that take the held values apart (`Sites.pairReached`)
  are the decisions the handle's held list carries.

## 4. The translation as a fold

### 4.1 One instantiation

`Annotated.instantiate : (n : Decided d reach) -> (at : Values d) -> Front
(Instantiated n at)`, where `Values d` is the requesting instance's values
for its reading's markers with its `Placed` (§5.1) at quantity 0, is the
one function that makes a request from a node:
it chooses the callee alternative (§2.4) and computes each keyed argument
from its site's term (L16ej's item 5: a run-time copy of `Host.putIn`
equal to it by `Refl`, then solving, skeleton and cut, each returning its
piece of `HeldAs`), then the readings and the link as `supplying` and
`instanceFor` do. `Instantiated n at` holds the `Supply` list, the link, and
at quantity 0 per keyed position its `Keyed` evidence and `HeldAs`, and
the instance's `MarkersHold` (§5).

A position the node does not key is supplied `Keyless`; the instance
never keys a position the node does not (case 3 of §1): where the
instance's type shows a universe the model read past its markers,
`offeredAt`'s `leftOut` refuses the program at the signature, as a type
no compile-time reduction fixes at the model.

### 4.2 Which functions become readers

- `State.Request` gains its callee's reading (`Fin r`), per keyed position
  its evidence and `HeldAs` at quantity 0 (L16ej's item 7), and per keyed
  dictionary position its handle. `Request.positions` goes.
- `Terms`: `term`, `forced`, `delayed`, `letIn`, `atType`, `suspend`,
  `argOf`, `spine`, `applyHead`, `applyVariable`, `implementationAt`,
  `entered`, `settle`, `bindStands`, `settledPiece`, `holed`, `member`,
  `parameterGiven`, `applyOver`, `applyRef`, `applyDefined` take the
  annotated node in place of the `TT` they took (each still reads the
  node's `TT` for code generation); `holed`, `settledPiece` and `piece`,
  where they compute a value a form closes over inside a settled term,
  fold the form's handle there. In `applyDefined`, `call` reads its
  `Call` node; `classifyKeys` there goes, and the call's kinds are the
  instantiation's (`Instantiated`), read in the caller's scope by
  `atCall` as now. `applyAtUse` reads its `Applies` node, `libraryCall`
  its hook's node, `resolveMethod` its `MethodCall` node, `memberHere`
  the node's `Makes`. `Arg.held` stays the values a form closes over.
- `Cases`: `tree`, `staticCase`, `natCase`, `natAlternatives`,
  `conAlternatives`, `litAlternatives` take `Tree`; `heldHere` reads the
  match's `Repacks` node.
- `Choices`: `calleeAt`, `dispatchOn`, `armsFor`, `givenArm`, `armAt`,
  `heldDispatch` take decided calls and members; `memberBare` and
  `memberHolding` take the `Makes` node; `Dispatch` and `ChoiceMember`
  keep their nodes.
- `Types`: `coreType`, `coreBinder`, `coreTypeIn`, `dataTypeIn`,
  `familyIn`, `dataOf`, `dataFamilyOf` take the `Builds` node.
- `Instances`: `request` and `recordRequest` take `Instantiated`;
  `supplying`, `instanceFor`, `instanceSig`, `classifyAt`, `offeredAt`,
  `argumentShape`, `neededShape` stay as the instantiation's parts;
  `classifyOffered` and `classifyCall` stay for what is no request (a
  primitive's, a constructor's, a lowered call's signature at a call).
- `Keys`: unchanged but for being called from the instantiation alone.
- `Programs`: `translateDefinition` folds its request's reading,
  `translateApplication` its form's handle, `mainInstance` the root;
  `step` and the worklist are unchanged.
- `Finite`: `requestedUnder` builds `Under` from each request's evidence
  (§5) and decides nothing but freshness on its chain.

### 4.3 What is deleted

At the end (L16ej's item 9, extended): `Finite.unsound`, `heightWithin`,
`sizedWithin` and their internal error; `Types.boundsHold`; `TS.bounds`
and `Growth.boundsOf`; `TS.sizes` kept at quantity 0; `Request.positions`
and `Instances.boundedAt`, `heightsOf`; `Instances.classifyKeys` and
`Terms.argValueIn`'s key fields (`normalised`, `written`, `holed` as keys;
`scoped` stays for index terms); `SiteTable.trees` and every lookup by
`Node`; `Requests`' `lteThrough`, `climb`, `fitsWithin`, `within` and the
tower deciders if nothing else reads them; the internal errors the walk
held for a disagreement it can no longer have (`Terms.useGiven`'s and
`heldValue`'s "the values an implementation closes over are gone",
`resolveMethod`'s, which the handle and `Instantiated` replace).

## 5. The lemma, over the model's walk alone

### 5.1 Its statement

Every instance carries, at quantity 0, `Placed d inst`: its reading's
node, its values `vs`, `MarkersHold d.model s ctx stands bs vs` for every
site `s` of that reading, and `HeadsHold` (its values' roots are its
node's heads). The root has it trivially (no static parameter). For a
request made by instantiating node `n` at an instance with `Placed`:
- each keyed argument is written by its site: `Keyed`'s `Drawn` gives the
  site's membership, `HeldAs` the argument's relation to the site's term
  with the values put in, and `ReadingCovers` (`Template.ReadingCovers`)
  then `Covers.siteWritesRead` give `SiteWrites` at the target position;
  `Capped` gives `cappedPlaced`;
- so the argument is within its position's bound (Theorem 1 over the
  model), within the head's height (`Growth.positionWithin`), and the
  link is in the universe (`InUniverse`): `requestedUnder` gets `Under`
  with no decision;
- and the requested instance gets `Placed` from the same facts: its
  values are what the sites wrote at its node's positions (`MarkersHold`
  for its own sites), and `HeadsHold` from the callee alternative's
  selection.

The induction runs over the worklist's chains (already well founded,
`Proof.Generations`), each step from the requester's `Placed`; it never
compares the translation's walk with the model's, because there is one
walk.

### 5.2 Its parts

From L16ej's item 8, unchanged: from the site's normal form to its form;
under a binder (`NodeCovers` over a scope); a call read beside its
unfolding; shapes (the skeleton against the site's, and the cut, §6.2);
dictionaries and shapes read as written (contraction through putting
values in). New here:
- `HeadsHold`, the flow's soundness for the values an instance holds: a
  value written by a site whose root is `Rooted a` is headed by `a`;
  `Parameter i`, by the writer's head at `i`; `ParameterField`, by a head
  the flow's solution gives that field of the writer's head; `Gives f`,
  by one of `f`'s leaves, by inverting the host's unfolding of `f`
  (`Idris.Host`'s `Unfold`/`Chooses`) as `Proof.Inversion` inverts other
  steps. This is case 2 of §1, which `heightWithin` catches today.
- `LandsHold`: the values an evaluated reading's families take are among
  the closed values `Graph.landedTable` says land there.
- `cutWithinCap` (§3.4).
- the dictionary over runtime values (`FromImplementation`): the frontend's
  own reduction (`Closed.implementationOf`) returns its result with the
  host's `Reduces` steps it took (heads, beta, a stuck definition's leaf,
  projection, D68's declared fragment), so no relation of ours stands
  where the host's should.

### 5.3 Trusts

None beyond D68 is needed by this design, by reading: every new part is
an inversion or a simulation over the relation `Idris.Host` declares. Two
places could need one, and if either does, that is the owner's:
- the call read beside its unfolding needs, per `Covers.idr`, the trace's
  `ArityDiffers` (a stuck walk only where an entry's constructor has the
  tag the alternative names) and each taken alternative a `Matches`,
  which `Idris.Host` does not state. If they cannot be proved from what
  `Host` declares, adding them to `Host` is a new trusted claim about the
  checker's evaluator (our code since D118, so a proof against it is the
  better answer, if the subset reaches it);
- keeping today's keys needs §6.2's simulation lemma, holes stuck, over
  `Host`'s relation; it needs no property of the normaliser beyond D68's
  if it is stated over the relation's steps, and would need one
  (monotonicity of `normaliseTypes` under cutting) if stated over the
  normaliser.

## 6. The cutover

### 6.1 Steps

Each step builds the frontend on a `git archive` export and compares
every fixture of the 429 with HEAD's (`/tmp/l16em/scripts/compare.sh`'s
measure: module bytes, and stdout and stderr where no module is written),
byte-identical unless the step names what changes.

1. **The tree, built and unread.** `Annotated.idr`; `Sites` builds the
   annotated readings in place of `Grown Site` (the walk is the same; it
   returns nodes where it returned `List Made`); `Graph` numbers entries
   and readings over them and draws as now; `SiteTable` holds the
   readings. The translation is untouched. Byte-identical; the growth
   verdicts and the drawn sites are unchanged (check: `entries`, the kept
   count and every verdict printed by a debug run, then removed).
2. **The fold, computing as before.** Terms, Cases, Choices and Types take
   nodes and walk them; every request still computes its key the old way
   (`classifyKeys`), beside the node it now has in hand. Byte-identical.
   This step finds every place the translation walks where the model did
   not (a mode the model did not force, a call site of `coreType` with no
   `Builds` node): each is a missing node to add in step 1's walk or a
   model gap to fix, never a fallback. A node added widens the model; a
   growth verdict that changes with it is reported with the fixture that
   shows it, and is the model's correction, not a regression to hide.
   Two are known: a shape-keyed argument's code walk (§1's reproducer,
   which becomes `tests/bounded-shape-argument-calls` or the like, its
   expected output the program's), and a static dictionary argument an
   instance finds chosen, which the translation computes as code
   (`applyDefined.arguments`' `ChoiceParam` case) where the model walked
   it statically (its static walk's `Calls` cover an implementation-giving
   call, so no fixture fails today, but the fold needs the `Code` node).
3. **Instantiation from the node.** `instantiate` replaces `classifyKeys`
   and `argValueIn`'s keys at every request; members, dispatches and arms
   carry their nodes; handles travel. Byte-identical if §6.2's option A is
   taken; option B changes the fixtures §6.2 lists.
4. **Evidence.** `Keyed`, `HeldAs`, `MarkersHold`, `HeadsHold`, `Placed`
   carried at quantity 0; `requestedUnder` builds `Under` from them; the
   run-time checks still run beside, and a debug build asserts they never
   fire on the 429 (then the assertion goes). Byte-identical.
5. **The lemma**, §5.2's parts, in `Proof/Covers.idr` and beside it.
6. **Deletion** (§4.3). Byte-identical but for the internal errors no
   fixture reaches.

Steps 1 and 2 can land apart; 3 to 6 are C281's change and land whole
(AGENTS.md: P0's cutover is one change).

### 6.2 The key risk, measured

Measured. Build: HEAD's frontend (L16em's `new5` tree, whose
`compiler/src` is e518e35c's but for `SyntaxSamples.idr`, against
L16em's host) with a probe in `Instances.offeredAt` that logs, at every
type, form and shape key, where the host's normal form of the written
argument (`normaliseClosed (solved (closeWritten ...))`, standing for the
site's term with the values put in) differs from today's key
(`closeNormalise`, which cuts every computation on a runtime value first).
Input: L16ej's 429 fixtures, from L16em's snapshot. The probe changed no
module (428 byte-identical with `new5`; the one other differs only by the
run directory's name in a refusal, as in L16em's
`/tmp/l16em/logs/compare-new5.txt`). Scripts and logs:
`/tmp/l16eo/scripts/`, `/tmp/l16eo/logs/analyse-prb5.txt`.

- 41 fixtures key at least one argument differently: 33 at a type (354
  keys), 22 at a form (84), none at a shape. 38 compile; the other 3
  (`implementation-index-function`, `implementation-runtime-length`,
  `show-dependent-pair`) are expected to compile and stop today at Emit's
  index check (`(w data family 12[_]) -> String` where `[v0]` is
  expected): F-F2, the index the key erases, which C272 makes an index
  parameter.
- Every difference is the same: where today's key has an erased hole the
  host's normal form keeps the runtime probe (`{idris-mlir-runtime:0}`) or
  a call stuck on it (`Array.foldl`'s form, the linear arrays' sizes, the
  sorted map's and set's indices, `checker-case-tree-fallthrough-copies`'
  135).

So keying by the host's normal form (O-3's B) changes the keys, links and
symbols of 41 fixtures, may split one instance into several where two
stuck computations differ, and puts a computation no compile-time
reduction can run into an instance's identity, which C272 makes an index
parameter instead. Keeping the cut (A) keeps every key and is the better
representation: the key holds what is static, and the call passes the
rest as an index term. Proposed: A, with `cutRuntime` returning its cut as
evidence (`CutFrom`: the term with subterms cut to erased holes) and the
simulation lemma over `Host`'s relation (§5.3), so `HeldAs` gains the cut
at every kind (`HeldCut`), and `Proof.Bound.AtCut` writes the hole at
every kind, not only at a shape.

## 7. What waits on L16ep

L16ep is fixing C272, F-R2, F-R3 and F-R4 in `Translate/` and `Growth/`.
This design builds on all four, landed first:
- C272 makes an index the key erases an index parameter of the instance,
  each call passing its term (`Types.eraseIndices`, `Instances`, `Keys`,
  `Terms`): it changes what a request supplies and what a call passes, so
  `Instantiated` is written against its `Supply` and its call terms
  (`callIndices` over `ArgValue.scoped`, which stays).
- F-R2 (`Instances.idr:474`, `runtimeTypeOf`'s refusal through `rewrite`
  and `replace`) changes `offeredAt`, which the instantiation calls.
- F-R3 (`Types.idr:853`, a polymorphic field re-wrapped in a lambda,
  C217/C213) changes `dataTypeIn`/`familyIn`, which §3.5 turns into a
  `Builds` reader, and the closed sums of rank-2 arguments, which §3.3's
  members and arms carry.
- F-R4 (`Ord (Either a b)`, L16dz's gap) changes `Growth/`'s reading of a
  dictionary (`Heads`, `Sites`), which step 1 rebuilds as nodes.
- D131.2, which the queue gives L16ep too (the frontend's index terms read
  as the specification's term, `Types.indexTerm`): the call terms an
  instantiation passes (`callIndices`) are written in it.
None of them should add a request point outside §1's list; one that does
is a node §3 must name before step 2. At dacc7ebd (HEAD when this was
finished) nothing in `compiler/src/IdrisMLIR/Frontend` had changed since
e518e35c.

## 8. Points not settled

O-1 (*for review*, core shape). **The tree as term nodes, or places with
roles.** Proposed: §2.2's `Code`/`Static`/`UseWalk`/`Tree`/`Arg`, which the
translation walks in place of `TT`. Alternative: keep `Grown` by `Place`,
give each place's entries typed roles (a record per place: the call, the
builds, the member) and let the translation thread the place beside its
`TT`. The alternative is smaller (Terms and Cases keep their `TT`
parameters) but is the beside-walk C281 rules out: a step the translation
takes that the model did not is again a miss found at run time. The
proposal costs every walking function's signature in Terms and Cases
(about thirty) and a shape of the walk in `Annotated` that `TT`'s
constructors do not have (an argument per mode, a sum where only an
instance decides): the model's walk is then the one place that shape is
decided, and `Place` keeps only `BoundPlace`'s identity and messages.

O-2. **The form handle's walk: maker's scope, or closed.** (a) Keep
`Sites.useOf` over the maker's scope; the handle carries a frozen
environment for it (each variable of the maker's scope a value, a held
value's index, or absent). The model's sites are unchanged; the fold of a
handle builds a `StandsFor` for a scope that is not the instance's, a new
kind of entry. (b) Walk the form closed, its runtime values hole markers
(`holedAt`'s key), as the translation walks it today; the handle is
closed, the fold binds hole markers to the held value's projections
(`standingFor`) as now, byte-identity is likelier, but the model's use-walk
sites change (a captured runtime value becomes a hole marker in their
templates), which may move verdicts: measure on the 429 before choosing.

O-3. **Keys from the site's term: today's cut, or the host's normal form**
(§6.2, measured). (A) Keep `closeNormalise`'s cut in the instantiation:
every key as today, a runtime-dependent index left to C272's index
parameter; costs `cutRuntime` returning its cut as evidence, `HeldAs`
and `AtCut` at every kind, and the simulation lemma (§5.3). (B) The host's
normal form, as C257's text states: no cut lemma, but 41 fixtures' keys
change (runtime probes and stuck computations in instance identities,
possibly more instances). Proposed A, which amends C257's wording ("then
solved, skeleton and cut" becomes "cut, then solved, skeleton and cut"):
the coordinator's if A's lemma holds over `Host`'s relation, the owner's
if it needs a property of the normaliser. Byte-identity under A also
assumes the site's term with the values put in is the term the
translation keys today (`closeWritten`'s, a `Shaped` variable as its
written shape); step 3's comparison is what shows it.

O-4. **`HeadsHold` as a lemma, or nodes split by nothing.** §5.2 proves
the flow's soundness for every value an instance holds. The alternative,
nodes split only by definition, deletes the selection but loses the
growth graph's precision (a method requested at two implementations'
heads is one node), which can refuse programs the graph admits today:
the owner's if anyone proposes it; this design does not.

O-5. **Where `ChoiceMember` and `Dispatch` keep the instance's
instantiation.** At quantity 0 only (the lemma's), with the run-time
parts (the member's form, the call's static values) already there; or the
whole `Instantiated` at run time, which the arm's request needs to
re-instantiate its non-chosen positions without the requester. Proposed:
the dispatch keeps the requester's `Supply` list and its evidence, so an
arm computes nothing; this costs one list per dispatch.
