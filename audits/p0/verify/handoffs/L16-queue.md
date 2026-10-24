<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L16: the queue after L16cb, L16cc and L16ca

What the frontend's running passes handed back, for the passes that follow
them (2026-10-22). Each item names the type that would carry the fact.

## From L16ca (D112's internal errors, Cases and the small modules)

- `Translate/Cases.idr:812`: `Defined.taken` keeps each binder's type.
- `Cases.idr:906`: `DictParam` holds its constructor and arguments.
- `Cases.idr:880, :926`: `request` returns its signature tied by type to
  the kinds requested (C234 sharpened); the parameters' runtime variables
  carried by position.
- `Cases.idr:900`: a `Static` entry carries its parameter's position.
- `Cases.idr:974`: the family's identity indexes its constructor layouts.
- `Translate/Types.idr:225`, `Keys.idr:93`: `Defined` holds its
  type-constructor facts and its nested-block name (the "split `Defined`"
  item L16bo left).
- `Translate/Shapes.idr:280`: `InstanceSig` keeps the binder types it
  admitted.
- `Keys.idr:1091`: a written reference holds an `Address`.
- `Errors.idr:335, :344`, `Profile.idr:127`: the driver or the checker
  hands over modules already located.
- `Program.idr:208`: `buildMain` returns the reloaded main module;
  `Program.idr:82` goes once Emit cannot fail (after L16cc).
- Kept as a run-time fact: `Keys.idr:1123`, two links sharing a key by a
  64-bit hash collision.

## From recheck 4

- C231 sharpened: `staticsOver` takes the instance's admitted telescope and
  loses its missing-binder branch (`Instances.idr:303, 327-328`).
- C234 sharpened: `request`'s signature indexed by the kinds it was
  requested with (`Instances.idr:803-804`).
- C222: translation requests carry their membership in the growth model's
  sites, so the run-time `unsound` goes (`Frontend/Finite.idr:172-194`).
- D112: the internal errors left in `Growth/`, `Translate/Closed.idr` and
  `Frontend/Finite.idr`.

## From L16cc (C228 and D112 in the term and Emit modules)

- `Translate/Shapes.idr:375`: `witnessTerm` still builds the old extent
  form; `AxisAt` carries its array's `ArrayType r` and the axis as a
  `Fin r` (a compile break until done).
- C228's remaining four Emit checks (`Bodies` about :692, :701, :729,
  `Tensors` :214): a lambda's result type, an application's function
  type and a force's operand type, which Idris's checker knows from
  context but the translation does not keep where it builds the term. The
  translation works against an expected type (checking mode), and
  `etaExpand`/`applyMaker` carry a result type, so the core term's values
  are typed by their scope.
- Internal errors kept in `Terms.idr` (446, 1379, 1494: held implementation
  values read twice; 1773, 1875 and `Choices.idr:88`: the family table;
  1784: two readings of a constructor's fields) and `Choices.idr` (453,
  468: a dispatch's choice and held positions), each needing a type the
  growth and instance modules hold.

## From L16ce (the growth builder's evidence), after L16cd lands

- C254: the graph draws the arc for a field read of an applied rank-2
  dictionary landing open with computing arguments; positions are
  numbered before landings are read, so `closedLands` is proved from a
  numbered table (`Growth/Graph.idr`, `Heads.idr`).
- `Template.rooted` returns its `SiteReading` beside the root, so Sites
  keeps the written-template equation (`asGiven k (r.template, root)`).
- The imports of L16cd's moved names in `Proof/Covers.idr`,
  `Growth/Heads.idr`, `Graph.idr` and `Sites.idr` (`Static`, `Chosen`,
  `markerOf`, `RunZero` and kin).
- The reading lemma's open steps, named in `Proof/Covers.idr`'s header.

## From L03z (generated builders against the frontend's calls)

The generator emits the right signatures; the frontend's calls are wrong:
- `natToExtentOp` takes no result type: `Emit/Tensors.idr:77` calls it under `const`.
- `arrayTabulateOp`'s `outs` is a list: `Tensors.idr:399,427,507,537`, `SyntaxSamples.idr:255`.
- `arrayFoldLastOp` takes `length` first: `Tensors.idr:545,547`, `SyntaxSamples.idr:259`.
- `arrayScanLastOp`: wrong order and no `outs` group, `Tensors.idr:549`.
- `Linalg.transposeOp` takes a region (`Tensors.idr:415`, `SyntaxSamples.idr:267`),
  once L12 admits `Linalg_YieldOp` from `Higher`.

## From L16ch (C254 as built)

- The `LandingTable` is a `Vect` updated once per writing, writings ×
  positions to build. Build it in one pass instead (the writings grouped by
  position, then the table made once), keeping `closedLandsOf`'s proof.

## From L16cg's follow-up (C228, C231)

- Tails in local-action regions (`Term.running`) still apply at the
  definition's declared result type, not the value's by construction.
- `libraryCall` compares the row's arity evidence with `Instances`' own
  count, which carries no evidence: the request's arity should come as the
  `Vect` length C249 gave it, so the two are one by type.

## From L16ck (the type facts for Cases' internal errors)

Done: `Defined.binders`, `program`'s main module, `moduleRefusal`. Seams:
1. `Closed.idr`: delete `argumentsOfNormal`, now unused.
2. `Driver.idr`: `built` returns the main checked file and passes it to
   `program`; the checker's `ModTree.buildMain` and `Host.buildMain`
   return the `mainttc` they reload (L17).
3. `Driver.refusing`: `moduleRefusals (\m => fromMaybe Project (lookup m homes)) loaded`
   replaces `refusalOf` and the `sites` pass; then `Errors.siteModule` goes.
4. `Cases.idr:940`: `Closed.VarInfo.Static` carries the parameter's `Fin k`
   position and holes, built by `Programs.runtimeParams`; Terms' local
   implementations get their own constructor.
5. `Cases.idr:946`: `PKind.DictParam` holds the constructor and arguments
   (`Instances` 145/590/631, `Choices`, `Terms`, `Programs`, `State.AtKey`).
6. `Cases.idr:1014`: `Term.Family` keeps `Vect n ConLayout`, `ConId`
   indexed by `n`, `familyIn` returning the `Family`; `Facts.cons` and the
   lookup at `Terms.idr:1929` go.
7. `Shapes.idr:294`: `InstanceSig` gains `binders : Binders () []` built at
   `Instances.idr:784`; `sizedTelescope` takes the signature (callers
   `Terms.idr:1630`, `Programs.idr:141,155`).
8. The checker: resolved references give `Keys.idr:1022` an `Address`;
   each FC names its module (`Errors.idr:356`); imports arrive located
   (`Profile.idr:127`) (L17).
9. `Program.idr:82`: `Emit.emit` returns its own failures apart from the
   writer's I/O failure.
- Not done: the split of `Defined` (`Types.idr:230`, `Keys.idr:96`):
  `Defined` and `Read` parametrised by the whole-program facts
  (`Read = Reading Nature`); it needs a ruling on a nested block no walk
  names.

## From L17ah (the checker's located facts), frontend readers

- `Driver.built` matches `Reloaded m`, passes `m.file` and `m.ident` to
  `program`, and drops its own `ctxtPathToNS`.
- `Keys.idr:1022` and `Template.inFrozen` take addresses from
  `definitionIn` (`Host.definedPlaced`, `resolvesAs`), so `unresolved` and
  the negative-index `Nothing` go.
- `loadedModules` reads all of `allImported`; `unnamed`,
  `elaboratedChecked`, `elaboratedFile` and the Driver's patch-in go.
- `Profile.checkModule` iterates `importsRead`, so `Profile.idr:127` goes.
- `toLoc` still looks a module up by name: a location's `OriginDesc`
  (`PhysicalIdrSrc ModuleIdent`) already names its module, so read it
  there, with no change to what reflection sees (L17, if the checker's
  side needs it).

## From L16cl

- `Term.Family` cannot hold `ConLayout`: its `ArgKind` and `Name` are TT,
  which Emit's term stays free of, and choice families have no layouts. A
  frontend family record split into data and choice families, with a
  family identity indexing the table (`Cases.idr:1014`).
- The split of `Defined` (C255) needs callers in Growth (`tyConFacts` in
  Caps, Sites, Graph), and `readOf` keeps a "defines nothing" case at
  `keyOrigin` the split alone does not remove.
- `instanceSig`/`request` returns evidence that `sig.kinds` equals the
  requested kinds, so `dispatchOn` takes the dispatch position by type
  (`Choices.idr:458`'s internal error, moved into `dispatchOn`).
- Cases' internal errors left: 920, 946, 1014.

## From L16co

- `Errors.idr:357`: a site in a module the session never read (reflection
  can make up such a location) reaches the lookup of its home and source,
  an internal error a program can reach. A site's module is a sum,
  read or not read, and a refusal at an unread module prints its location
  as given, with no source excerpt.
- `NotBuilt` carries no main module, so a failed build's site still
  converts a path to a namespace (L17, if the checker should hand it over).
- `Walk` exports the placement of a non-negative index, so
  `definedAddress` takes its address from the entry `definitionIn` found
  rather than resolving the name again.

## From L16cm

- `DictParam` (`Cases.idr:947`): `Closed.fixing` returns the reduced
  constructor or function value, and `Template.staticReading` carries it.
- The family table (`Cases.idr:1004`, `Terms.idr:1938,2051`, `Choices.idr:91`):
  family registration in `Translate/Types.idr` (`familyIn`, `constructor`,
  `registeredChoice`, `dataOf`), `ConId` and `DataT` in `Ids.idr` and
  `IdrisMLIR/Types.idr`.
- `Shapes.idr:294`: the classification and `sizedTelescope` substitute
  different stand-ins for the same parameters. One walk is the end state
  (one fact, one derivation); show first that merging them leaves every
  verdict as it is, since the two normalise differently.
- `Terms.idr:490,1494` and `Cases.idr:921`: the caller's data per position
  (held values, runtime variables) is not tied to the callee's signature by
  type, and the cache key holds no holes.

## From L16cp (the lemma over skeletons)

- C222: `Instances` carries `HeldAs` together with the site's membership
  (`Template.ReadingCovers`'s premise), from the translation's site table.
- `Closed.skeleton` returns `SkeletonOf` evidence.
- `Walk` states `probeTerm ProbeRuntime`, so a proof sees a cut's hole.
- The induction at shapes: the request cuts before solving and contraction,
  the site after (Covers' header).
- L17 exports `putInMapped`, `mappedShows`, `mappedSpine` (L17aj).

## From L16cr (C222's threading, as found)

- C222 needs the term walk to know its site: Graph exports the site table,
  `Growth.checkGrowth` stores it in `TS`, and Terms, Choices, Cases and
  Programs pass the site to `request`, which then carries `HeldAs` with
  the membership.
- The induction at shapes still lacks: the translation's argument is the
  site's term with the values put in (C222); `Closed.solved` agrees with
  `Template.solvedIn`; contraction carries through putting values in; the
  runtime probe's name has no place in the context; `closeNormalise`
  matches the host's normal form for `HeldNormal`.
- `State.PKind.DictParam` carries `FixedValue`, so `Cases.idr:947` reads it
  and `staticReading` carries it.

## Audit at db4bcb11 (2026-10-22)

Every item above checked against the tree: 34 done, 4 obsolete, the C222
cluster, and these open.
- `Shapes.idr:300`: `InstanceSig`'s binders, one walk (Shapes, State,
  Instances, Terms:1642, Programs:151,165).
- `Terms.idr:549, 657, 667`: C228's last three checks, which a Core term
  indexed by its type removes.
- `Program.idr:84`: Emit's typed `Unfit` (`Emit/Tensors.idr:192`), the same
  missing index.
- `Driver.idr:274`: a failed build's site named from the path again
  (L17am: the main module named once, in the driver).
- D112 in Growth: `Growth.idr:318, 652`, `Caps.idr:176`, `Fields.idr:135`,
  `Graph.idr:2507, 2530, 2533`, `Sites.idr:2551, 2553`, `Finite.idr:224`;
  and `Closed.idr:402, 405, 1288, 1302`, `State.idr:1103`,
  `Programs.idr:396`, `Choices.idr:533` (the last likely C222's).
- The C222 cluster: `Cases.idr:921, 947`, `Terms.idr:496, 1498, 1617`,
  `Finite.idr:172`, with Covers' induction.
- Kept as run-time facts: `Keys.idr:1080`'s hash collision; the checker's
  one `assert_total`, `Idris/Host.idr`'s `host`, the trust the frontend
  takes in Idris's covering functions, stated once.

## From L16cw (D112 in Growth)

Done: `Caps.idr:176`, the walk carrying a callee's `Defined` (`Callee e`,
`Reached e`), so `capOf` takes it and the lookup by address goes. Open,
each with the type that would carry it:
- `Growth.idr:318`: addresses made with their definition dropped
  (`Sites.definitionOf`, `MkFields`, `Proof.Template.InterfaceHead`,
  `Template.Opaque`) keep the address with its read definition.
- `Growth.idr:652`: each drawn arc tagged with where it came from and its
  computation, at `Proof.Template.occurrences` and
  `Describes.underComputation`, so `computationThrough`/`sourceOf` go.
  Suspected reachable (read, unbuilt): a held arc out of the writer's own
  positions has `sourceFor = Binds i`, so `computationThrough` may find
  nothing there.
- `Fields.idr:135`: `TyConFacts` keeps the constructors, a missing one
  refused at the boundary (`Boundary.readFrom` skips one silently today),
  and `constructorArity`'s silent `[]` goes.
- `Graph.idr:2507`: `Reading.entry`, the entry's `Defined`, so main is
  passed by its definition, not its name (`Program.idr:228`).
- `Graph.idr:2530` (`Outside`), `:2533` (`Unheaded`): proofs (visits within
  `headBound`/`countedIn`; `solve`'s fixpoint and `sitesOf` with heads).
- `Finite.idr:224` is a fact of the instance table, not of the growth
  verdict: `State.Request` holds that its link was absent, chain items that
  theirs are present; C257 does not delete it.

## From L16dc (C228's last checks)

Done: a call's, a hook's and a constant's head carries the type it was
built at (`valueTy`), not one re-read off the value. Open:
- `Terms.idr:549` (an application's head) and `:667` (a force's operand):
  one reading of a value's type, built where the type is first read, each
  step holding the Core binder and result with Idris's erased, polymorphic
  or runtime binder (`Closed.KnownTypes`, `State.Callee`/`InstanceSig`,
  `Types.coreTypeIn`); an argument past every binder is the checked
  module's, refused as `CompiledModule`.
- `Terms.idr:657` (a lambda's result type): the markers of a settled term
  (`settle`, `bindStands`, `holed`) take their position's type from
  Instances; waits on the owner's C257 ruling, which decides how a
  settled member is walked.
- `Emit/Tensors.idr:192` (`Unfit`) and `Program.idr:84`: the term indexed
  by its type (`TermAt js (sc : Vect n Ty) t`, each slot holding its fit),
  which needs `DecEq Ty`, blocked by `ILit (LDouble _)` (base has no
  `DecEq Double`) and ripples into State, Closed, Cases, Choices,
  Programs, Shapes, Primitives, Recursion, Types and `Emit.idr`.
- `Terms.boundTypes` defaults silently with `fromMaybe b.type`.

## From L16db (the boundary's facts carried)

Done: `TyConFacts.constructors` (`ConstructorAt`, read at the freeze, a
constructor the context lacks refused as `CompiledModule`), so
`Fields.idr`'s internal error and `constructorArity` go; `Reading.entry`,
so main is passed by its `Defined` and `Calls`/`Builds` carry callees'
definitions. Open, decided here (the coordinator, 2026-10-23): the
growth graph's positions (`Node`, `Visit`, `Spot`, `HeldBy`) stay keys,
and their definitions are carried beside them, numbered once: a `Vect`
of definitions per position built through `Written` and the numbering,
the definitions along the visit path for the reachers, the interface's
name beside `ChoiceHead` from `choiceHeadOf`, and a stuck recursion's
definition in `Describes`' drawn arc; then `graphDefinition` and
`Growth.idr`'s last address lookup go. Also: `Types.constructor` reads
`TyConFacts.constructors`; Sites' `nodeValues` keeps two internal
errors; R-o2's typed local definitions rest on an Idris behaviour L06d
is confirming.
- (L16df, by reading) `Types.familyIn`/`constructor` re-read a type's
  constructors from `TCon` and test `DCon` again with two refusals, the
  fact `TyConFacts.constructors` now holds: read it there.

## From L16de (INT-16's errors in Instances to Programs)

- `Cases.tailsAgree` and `Programs.predecessors` prove one lemma twice:
  keep one, where both can import it.
- `Errors.getState`, `updateState` and `toLoc` are polymorphic over the
  monad (`RunsCore m`), so a bind after one is ambiguous wherever
  `Core.Core`'s own bind is imported; Choices hides Core's bind, as
  upstream's parser does. If INT-17 meets the same ambiguity in other
  Front-only modules, the same hide there.

## From L16di (Closed and Programs)

- The `%pair` (decided here, the coordinator, 2026-10-23): Sites'
  `Pairing` moves to State as `Reading.pair : Maybe Pairing`, filled by
  `readProgram` after the freeze (`readIn`, `definedAddress`), a declared
  `%pair` naming nothing refused there as `CompiledModule`; packing more
  than one captured value in a program with no `%pair` is refused as
  `unsupported`, naming the pair it needs, where today it is an internal
  error (no accepted program changes). Then `pairNames`/`pairPart` go, and
  `packedType`, `unpacked` and Sites' `pairingOf` read the record.
- A metavariable's solution (`Closed.solution`): either the checker states
  that every metavariable a frozen definition names is at an entry it
  defines, with one leaf and no arguments (`Unify.idr:503, 1527, 1546,
  1572`; `Delayed.idr:278` write nothing else), and the walked terms carry
  their origin; or a solved metavariable is read as a reference to the
  definition it is (Terms, Sites). To be decided on the reading.
- Programs' local-join call: lemmas over `jumpsTo` (a term that never
  calls a callee rewrites for it; rewriting for one keeps another's
  success), `jumpedBy`/`fitsRuns` returning evidence; or tail calls typed
  apart from inner calls from Terms on. `callHead`'s `decEq arity k` tests
  what the callee's identity fixes.

## From L16dj (the stuck recursion's definition)

Done: `graphDefinition` and its internal error (3acf6323), and
`Definitions.definitionAt` with them. Open, decided here (the
coordinator, 2026-10-23):
- An instance's reading shares the writer's reader, so it builds an empty
  `All RecursionDef` list at every node, paying at run time for what is
  known statically (an instance never meets a recursion): the reading is
  indexed by whose term it reads, a writer's carrying the definitions and
  an instance's none, so nothing is built for an instance.
- The other readings of a name from an address: `Sites.render`/`nameText`
  (`Sites.idr:534`, a silent `"_"` for an address with no entry),
  `Graph.idr:2624`, and `Template.atAddress`/`definitionRead`
  (`Template.idr:190, 199`): each carries the name or definition from
  where the address was made, as the positions now do, and `nameAt`'s
  `Maybe` goes with its last reader.

## From L16dl and L16dn (C260, the pair)

- The missing-`%pair` refusal names the module's site, not the packing:
  `Closed.pairFor`/`packedType`/`unpacked` take the packing's site and its
  twenty callers pass it (Terms 11, Sites 4, Choices 3, Cases 1,
  Instances 1).
- `State.natured` works out the entry's and the pair's `Nature` apart
  from the map, three lookups each.
- `Keys.write` is pure and still looks a metavariable's address up; a miss
  writes nothing, for a term the writer was not built for.
- For L17: the freeze states, at quantity 0, that an entry
  `lookupCtxtExactI` read as `def` before it is defined after it as a `d`
  with `definition d = definition def`, so `readDefinition` keeps the tree
  evidence it decodes and `solutionAt` reads each tree once.

## For L17 (from L17at)

- Done (7cd45299, 9dfe3bee): the block's types are checked at a position
  of their own, `KparamBlock`. The item as it was:
- A `parameters` block's type is checked under index `-1`
  (`ProcessParams.idr:48`), which the context never gives out, so a case
  block in such a type would be named `Resolved (-1)` and fail at the TTC
  writer. Base has none; give the block's type a real entry, or name its
  blocks from the block's own name.

## Tests owed (L16ea)

- A fixture beside `closed-double-text` that prints `1.0e309` and divides
  by a subnormal constant, checking the sign and magnitude a Double's bits
  carry into the module.
- `SyntaxSamples` samples of ±inf, NaN and the smallest subnormal beside
  its `-0.0`, with a check that MLIR reads back those exact bits
  (`tests/dialect-syntax` only checks that the file parses and reprints).

## From L16dz (growth refusals of valid programs)

Two refusals the model makes wrongly, each a model gap (dispatch after
L17ay settles whether Readings' marker names change):
- `Compose` (`every-interfaces-export`; reduction `/tmp/l16dz/repro/FA1`,
  `UC1` against `UC2`): the site reading of `Constraint (Functor f) l`
  keeps the projection's as-written alternative, read as no head, so a
  dispatch through it reaches every Functor and closes a cycle no
  instance has. A `Root` for "a field of the writer's own dictionary
  parameter", or the projection read as its field alone
  (`Readings.SProjected`), with its case in `Proof.Covers`.
- A constraint pair (`every-types-export`, `Ord (Either a b)`; reduction
  `TupleSuper` against `CurriedSuper`): a constraint tuple is one
  dictionary built with `MkPair`, whose field positions every pair of
  dictionaries shares, so the superclass read over a field appears to
  feed itself. A field of a constructor-built dictionary read as a part
  of the record, one level below its position: a rule of the growth
  model (`Proof.Bound`, `Proof.Describes`). Base has the shape too
  (`Monoid (SortedMap k v)`, `MonadWriter w (WriterT w m)`).

## From L16eb

- `Growth/Sites.holdingOf` repeats `Translate/Types.typeHolding` line for
  line: Sites calls `typeHolding`, and its copy goes.
- `Boundary.polymorphicHolding` still reads `Type -> Type` as a
  polymorphic function's type; with C263 no parameter or lambda reaches
  it, so the rule is dead there: delete it or make it read a universe as a
  type parameter, as `keyingOf` does.

## D126's second round (left by the first units)

- Unit E: `Conversion/Lower/Functions.cpp:76` (DestType, later DataType,
  on one type) and `:117-118` (LifetimeType on two values);
  `Analysis/Solver/TypeGraph.cpp:125` (a SelfType test
  `IndexedTypeInterface::getPositionalMember` answers);
  `IR/Layout/Components.cpp`'s `wordsOf`, a template fold over the
  dialect's types, which D126 says is not the form.
- Unit B: `Defunctionalize/Convert.cpp:100-104, 135-144` and
  `Analysis/LabelSites.cpp:260-277` choose closure or constructor by a
  two-way `dyn_cast`; one method giving a closed sum (`Closure | Con`)
  folded by `match` is AGENTS.md's form. `Conversion/Lower/Statics.cpp:46,
  103` reads a crash site by the attribute name `"site"`: a site interface
  the op families that carry one implement, then a typed walk.
- Unit F: `Conversion/Strings.cpp:172, 188` picks four runtime functions
  per element by `is_same_v<OpT, StrPackOp>`, facts the specification
  should declare in a generated per-op table (as `ShownOutput` is).
- Unit A: `IR/Lifetimes/Ops.cpp`'s `extentOf` (forget, reserve) and
  `packedOf` (unpack, opener) each test two op classes; `Proof.cpp`'s
  `keptHere` tests for `CellArenaOp`: interface methods.
- Unit H: the tail kind is still tested by hand outside Tail.h:
  `Analysis/LabelSites.cpp:302`, `PlacementUses.cpp:50, 71`,
  `Narrow/Carried.cpp:65`, `Contify.cpp:162, 260`, `EGraph/Build.cpp:64`,
  `TrmcRewrite.cpp:221`, `TailLoops.cpp:129`, `AccumulatorPlan.cpp:281`,
  `Tail/Frames.h:139`, `Analysis/Ownership/Borrows.cpp:161, 316`: each
  calls `tailCallOf` or `lastActOf`.
- Unit D: `MatchFamily.h`'s `verifyKeys` compares keys pairwise, quadratic
  in a match's cases, since a carrier's equality need not be identity (a
  Double's two zeros); hash the carriers whose `sameLiteral` is identity
  and compare pairwise only the others.
- Unit G: `Chains::Demand` (`Rule.h`, `Versions.cpp`) holds a `CallOp`
  only for its result count; holding the count removes Chains' last
  `cast<CallOp>`. INT should check the tests that read gives-back facts,
  which the analysis now produces for the first time.

## D126 round 2c (left by round 2b-T)

- A type method on `ValueFactsTypeInterface` in the specification:
  `getRunTimeWords(std::optional<Hold>) -> RunTimeWords`, today's `Words`
  sum moved to `Interfaces/Vocabulary.h`; `GradedType` asks its carrier
  with its own hold, the builtin types answer through `ValueFacts.cpp`'s
  attachments, `SelfType` has none (its fatal arm goes). Then
  `IR/Layout/Components.cpp`'s `wordsOf` template fold goes, and
  `Lower/Functions.cpp:76`'s `componentFacts` folds over the answer (its
  `DestType` test and `dataTypeOf` go). Dispatch after round 2b-S lands
  its regeneration.
- `Frames.cpp:154-164` and `Lifetimes/Pass.cpp`'s `framingOf` ask one
  question of a component twice ("does a member call a member and get
  control back?"): one answer in `ProgramGraph`, beside `onCycle`.
- `Support/Match.h`'s header says a type interface is not used to say
  what each of our types is, which D126 contradicts.
- Hand readings of the tail kind outside Tail.h: `Accounts.cpp:66`,
  `Func/Call.cpp:273`, and `EGraph/Build.cpp:64` (L14x's).

## Recheck 5's items not yet dispatched (2026-10-23)

Dispatched from recheck 5: L10z (§4's tail-layout check, D32's frame
decision once), L17bb (the checker's internal errors, `%start`, C55's
`%transform`), L06h (stock Idris's nested linear patterns, D121),
L16ef (Emit's tie before the call, C262), L19z (loan escapes, C17),
D126 round 3-B and 3-A (with C65's `idr.may_loop`, C87's constraint and
C264's float list declared), L16eg (the registry's string set), L11y,
L19w, L05x (D124's frame case), the sources lane (C13). Waiting:
- After L16ee (Translate/, Growth/): C257 obligations 4 to 6, C258, the
  reading lemma and `Finite.unsound`'s deletion (D46, D68, D128.3); the
  frontend's 20 internal errors (D112.1); C122 (erasure held in
  `ArgumentAt` and `Use`, and Sites' binder-quantity read); C55's case
  blocks as regions of their parent (`Keys.idr:71-76`); C213 and C217
  (the two `RuntimeClosure` refusals at `Terms.idr:614, 1004` name a
  translation situation, not an unbounded set); C256's site membership;
  `Caps.idr:135, 165` name the deleted `closedHeight`; D44 (Finite's
  semi-naive worklist onto R2's fixpoint, C175; 0011's O8); L16dz's two
  growth-model refusals; `MLIR.idr:149` (`typeText TokenType = "none"`,
  a wrong text for a state the type allows); `Finite.idr:224`.
- After round 3-A: C65's insertion of `idr.may_loop` where a loop is
  made from code Idris did not prove total, and its readers (L09);
  C87's callers; L14y (C264(b)'s float ops computed by `APFloat`, guards
  and conditions over computed values, `OperandFacts::constant` over
  them, `Constants.cpp`'s `isBuildableWith` asking `constantStandsAt`,
  `heldFacts` through `ConstantAttrInterface`, C264(c)'s reading of hold
  strengthening, `Analysis/Constants.cpp:36`'s `sortedIds(NeverFolded)`
  built at run time from a static list); the specification's
  `Termination` declared and read by nothing while `Func.h:68-82` writes
  the same variant by hand (L02, L03); `Generator/Main.idr:33-52` finds
  modules by scanning `spec.ipkg`'s text (L03).
- INT, on the owner's machine: the measurements (D30's `tailcc`, D32's
  and D33's stacks, D58's `shapeBudget`, D78, D95, D100, D108's
  `nodesPerOp`, D115, C5, C43, C98, C201 and the other stage-1 rows);
  D49 and D51's dialect modules (`tools/dialects.sh generate` on a built
  toolchain: the 13 stamped modules and the missing Linalg,
  Bufferization and SCF); `audits/bugs.md`'s entries rechecked.
- The coordinator: strike `audits/p0/design/idris-linear-check.md` §5
  when L06h returns.
- From recheck 5's §6 report, waiting: N1, the tail decider's climb
  (`inTailPosition`, D30 and C20 delete it; 17 files re-decide through
  `tail::decide`, four ask it of ops that are not calls) and N2, the
  cycle rule written in four places (`ProgramGraph.h:139-141`,
  `Components.h:76-82`, `Effects/Component.cpp:116`,
  `Optimize/Settle.cpp:186-191`), after L10z; N10, the array externs'
  hand enum (`Registry/Entry.idr:210-213`) and hand case
  (`Terms.idr:2306-2320`), each row naming the specification's op
  (C6 as replaced), after L16eg, L16ee and round 3-A; N4, N5, N6's
  frontend half and N7, in L16ee's files; N6's checker half (a nested
  block's parent a typed name, `Core/Name.idr:43`) with its frontend
  reader.
- From round 3-B, after round 3-A's typed lifetime predicates:
  `lifetimes::kindOf` takes `TypedValue<LifetimeType>` (`Lifetimes/Kind.cpp`,
  `Lifetimes.h`, `Lifetimes/Proof.cpp:39-40`, an opener's body argument
  typed through `RunsOnceAfter`), and `Lower/Lifetimes.cpp`'s callers pass
  typed values; `Expect`'s `idsOf` cast goes once `ExpectArguments.h`'s
  `Functions` resolves per numbering (L19); `FamilyVerify`'s `groupOf`
  cast goes once `Sort` holds a typed group per kind (`Terms.h`, the
  generated `Wire.cpp.inc`). From L11y: `Target.cpp` overwrites a
  module's `#llvm.target` silently (L21: a hand-written module carrying
  another target is refused `unsupported`, or the overwrite says why).
- From L16eh (unrun, by reading): MLIR's generated parser of a type
  list needs one element, so `!idr.fn<() -> ()>` and a
  `lifetime.package` holding nothing would not read back as text (the
  dialect's assembly format, after round 3-A); `SyntaxSamples`' op sample
  refining `List[0]` to `@Nil` writes a refinement the length decides,
  which the reader drops: write the canonical form.
- D130 and D131 (2026-10-23), after round 3-A lands its regeneration:
  one families lane (L04) for the specification and the C++ of both: the
  data type's layout mark (`!idr.data<#Vect[4] open>`: the DataType
  parameter, its storage, syntax and bytecode, `classify` and
  `layoutMatch` reading it, refinement and index identity ignoring it,
  substitution keeping it, the specializer's `openResult` marking instead
  of making indices opaque), and the Nat sum term (`Spec/Families/Terms.idr`
  and its C++ storage, printing, bytecode, unification, substitution
  normalizing sums, the scope rule reading a sum as refining nothing of
  its parts); then C265's one-line gate in `Tail.cpp`; then C267's rule in
  the specializer (no closed copy whose tail callee cannot agree). After
  L16ee: the frontend's `indexTerm` reads base's `plus` on `Nat` by
  identity as a sum (`Translate/Types.idr`), and L18y's test with the two
  properties L19 adds (`tail-calls`, `results-as-given`).
- From L21x, after round 3-A: a refusal rule for a module made for
  another target (the specification's `Rule`, its phrase, scope and
  category: a check against the build, which `Runtime`'s scope also is),
  taken by `idr-target`, `Driver/Run.cpp:118-130` (lowered module) and
  `Verify/Program.cpp:56-72` (word size), which are internal errors
  today; `OpsPlatform.cpp:23-28`'s comment says idr-target writes over a
  module's triple, which it no longer does; `Pipeline.idr:205-211`'s
  description of idr-target.
- C268, after L04x releases the specification: `tie_shape`'s axes named
  (spec `Arrays/Memory.idr`, `OpsArrayShapes.cpp`'s inference, reify and
  value bounds, the specializer's re-inference), then Emit's `tie`
  (`Emit/Tensors.idr` about 600-622) states only the axes something
  states and reads nothing from the array; reproducers
  `/tmp/l16ef/repro/successor-axis`, `literal-index`.
- From L19u: `Tail.h` gains `repackOf(op)` (the op that re-packs a value,
  read off `CarriesOnOpInterface`), asked by `Expect/Tails.cpp` and by
  `Tail.cpp`'s private `carryOf`, after L04x's gate; the lowering's
  re-pack of a value `idr.index.assume` takes in at another layout is
  seen by no property; `tests/expect-coverage` counts `tail-calls` and
  `results-as-given` unstated until a program test states them (L18y's,
  after L04x). From L14y: the guard hooks `decide` and `foldable` as
  template members over `fold::Where` (`holds` and the interface's method
  go; the engine holds each guard's decision over its values), and
  `ConstantAttrInterface::getFoldValue` (a closed sum attached to the
  builtin string, integer and float attributes) for `heldFacts`, both in
  the specification after L04x; a literal match on a computed string,
  Double or big (its lookup reading values, L09); tests for the Double
  ops and the large-big divisor (L19); and, by reading, a contradiction
  among Emit's `coerce` (`Emit/Operations.idr:230`, static data where
  counted is asked with no op between), `Consumer.cpp:305` and the call
  verifier's equal grades, to confirm.
- C269, after L04x releases the specification: the uniqueness test's
  shared region takes its value at `many` (its region argument and type
  compatibility in the specification; `Counting/Expand.cpp:112`'s dup
  then admitted). From L07x: many values read in an `idr.loop` body are
  still held across it (a dup at the entry, a drop after, a count of 2
  inside), which the same region rule would move (counting, measured at
  qualification); a fixture of a once parameter passed into a loop body,
  graded to owned, verifier clean.
- From L09x (C65): after L16ei marks Emit's loops (`Bodies.idr` about
  907-908, `mayLoopOp` first in each join region unless the definition is
  `Terminates c`), L02 deletes the function-entry divergence seed
  (`Fold.cpp:33-41`) and its doc lines (`Analysis/Effects.h:15-17`,
  `Func.h:80-81`); then the specification's `Functions/Termination.idr:3-4`
  and `TerminatesAttr`'s description (after L04x). L19s adds `may-diverge`
  for `tests/partial-loop-diverges`.
- From L14z: a static argument at a call needs a specializer round after
  the e-graph (idr-optimize ends a component's rounds on a round that only
  simplified; the standalone e-graph steps 10 and 14 have none), and
  Signatures::edit re-grades parameters only; the specification could
  state each operand constraint's hold admission as data (TakesStr and
  strRead one fact). From L06h: tools/bootstrap.sh idris rerun so the
  installed stock Idris carries 115 (INT, with 116 when L19v lands);
  LinearCheck's updateHoleUsage visits an as name twice and its pattern
  never (no cost; upstream, unacted).
- From L19r: the root rule (`Program.cpp`'s `verifyRegions`) has no test
  of its own: a program whose root takes an argument, and one whose root
  gives an `i64`, each refused by its message (L19).
- From L19v: the checker (`compiler/checker`, our code) has the same
  `checkUpdate` as patch 116 fixes in the stock Idris
  (`TTImp/Elab/Record.idr` 277-281, `checkUpdateDelayed` 256-261): its
  fix is its own code, with a `tests/checker-*` check (L17, after
  C271); INT reruns `tools/bootstrap.sh idris` for 115, 116 and L06i's
  patches.
- C272 (F-F2), after L16ej and L16ek: an index the instance key erases
  becomes an index parameter of the instance (`Types.idr:361`'s
  `eraseIndices`, Instances, Keys), each call passing its term (Terms);
  reproducer `/private/tmp/l16ei/repro/compose-index`. From L16ei:
  Emit's `fitting` (`Tensors.idr:163-166`) passes two tensors of equal
  dimensions with no comparison of their element types.
- L16eg's second pass (the fileTime validator reading types as the
  reading does, and the registry's hooks keyed by context entry) is in
  the working tree (`Registry.idr`, `Resolve.idr`, `Profile.idr`),
  committed with L16ek's `Boundary.idr` and L16ej's `Closed.idr`, which
  carry its seams. From it: `exit-with` and `harness-cases` refused in
  translation ("PrimIO.MkIORes: a field type that depends on another
  argument of its constructor", L16); validation compares a row's type
  names as printed text, `inModules` module paths as text.
- From L18z: a class copy forced by a parameter whose tail gives an
  index the language cannot express (`Vect (length xs)`) is refused by
  the scope rule's cast `#Vect[_]` to `#Vect[3]`; openResults covers only
  the copy its result alone forces, so the rule must open a copy's result
  wherever its tail cannot match, whatever forced its class (L18);
  `openTails`: an opened function with a tail that builds words needs the
  cast to claim `unique self`, which one hold cannot serve beside a
  passed-through tail before Graded (a decision for the coordinator, with
  L05's reading of claims); `callersOf` misses an asker's call of a copy,
  so `dropUnread` would miss narrowing it (L18); by reading, L04x's
  `open-copy-keeps-refined-index` reindexes a bare type to a graded one
  the refinement check refuses, and in `sum-index-closed-tail`
  contification may make `@reverseOnto` a join point of `@later` (L19,
  the tests). From L02x: `unittests/Rows.cpp`'s model still seeds
  divergence (`ThePipelineStopsExactly`, `EachMutantOracleIsCaught`: draw
  per function whether its body holds a marked loop; L15); Termination's
  `Acyclic` is read like an absent attribute by every reader, a fact held
  for no reader (delete it from the specification and its writers, Emit,
  `Forces.cpp`, `Settle.cpp`, or give it a reader), and
  `Termination.idr:3-4` and `TerminatesAttr`'s description take L02x's
  text (in its handoff, 8123ffde's lane).
- P-1 (INT-21, L17bb's reading), after L07w releases the specification:
  `compiler/spec/spec.ipkg` becomes a library (its modules, no `main`,
  no `executable`), which `make self-spec` installs, and a separate
  `specgen.ipkg` depends on `idris-mlir-spec` with `main =
  IdrisMLIR.Spec.Generator.Main` and `executable = specgen`, built by the
  stock Idris; under self-host the driver compiles specgen as any program
  (L03 with INT's Makefile).
- From L02y: a cycle of several functions whose divergence every member
  dropped together passes the per-function verifier; a contracts relation
  (`Contracts.cpp`, L19's) checked after every pass from the module alone
  runs `addCycles` over the current rows and reports a member whose row
  would grow, its breaking test pass dropping divergence from every member
  of one unproved cycle and their calls. From L19p: `expect-coverage`
  reads only `mlir.expect` lines and harness scripts, so `reached` (asked
  from `Universal.idr`) and `folded` (asked by fixtures) count as stated by
  no test (L19).
- From L07w: `memo.run` and `memo.take` declare their captures as parts of
  a taken-over cell while the cell keeps its reference (closures' owner,
  L18: their flow edges); the arrays' generating ops (fold, scan,
  tabulate) pair their inits with results buffers leave empty, so asking
  their flow asserts (L12); a lend's give-back stays a trait (a flow edge
  would let exclusivity follow the owner into the given-back value without
  the loan's view, L08's `rootOf`). L07v holds the once-only consumption's
  other readers, the literal match's leak and `big.small`'s type.
- For the owner, after the sources question (L14u's finding): idr-constants
  (SummarizedConstantPropagation over upstream's dataflow) and the e-graph
  both fold the same ops by two routes, each round, and drift (NaN, fixed;
  math.sqrt folded by one and left by the other; the byte budget binding
  one). Only idr-constants carries constants a finished callee returns
  (the summaries), joins on live paths (region results, block arguments,
  loop-invariant values), our hand folds and multi-result ops; only the
  e-graph rewrites, shares, reasons by intervals, chooses by cost and
  places static data. (A) one folder: the e-graph takes idr-constants'
  duties (callee constants beside gives-back, live-path joins as region
  rules, hand folds as meanings) and idr-constants goes; (B) idr-constants
  folds only the specification's lists, two propagators kept. An engine
  choice: the owner's.
- From L14u: counting (`FlowOps.cpp`) marks a building reindex's result
  fresh, as a building field read is; `Open.cpp`'s `openedAgainst` gives
  the open type the tail's hold, so a function with one tail giving an
  unclaimed cell and another building from words cannot share one open
  type (L18); `tests/open-copy-keeps-refined-index` can hold words again
  (L19).
- From L16ek: the checker's TTC keeps a case tree's `scTy` unscoped
  (pattern variables as names, `{pat1::6}`; free indices captured under
  binders, `(arg : Int) -> arg[0]`), so a reader of it refused 20 valid
  fixtures (L17: keep it scoped as the term it is); C228's (b) and (c)
  need `Types.coreTypeIn` to return the Core and Idris types together
  (L16ej); D112.1's Terms (held values gone: `classifyKeys` returns what
  it read), Cases 954 and Choices 567 (`request`'s signature tied to the
  kinds requested, C234) and Shapes 300 (`InstanceSig` keeping the
  binders the classification admitted) are L16ej's threading pass's;
  C217's "form type" refusal is reached by a program whose choices are
  fixed (`/tmp/l16ek/repro/form-delay`: the implementation entries carry
  their Idris type); `runtime-closure-poly-rewrapped` still refused (C217);
  `Terms.idr` checks in 918 s against 674 s, almost all Idris's
  termination check of its mutual block (measured, one session).
- From L12x: `idr.array.update` (`OpsArrays.cpp:164`) declares its element
  a plain read, so an update whose region takes the element apart or
  yields it back fails at owned (the emptied-place edge, L12); placement
  dups a value without first forgetting its claim (`PlacementRewrite.cpp:158`),
  so a building reindex's result used twice fails count.dup's verifier
  (L07); a reindex's builds is asked by its verifier and its flow apart,
  the flow's call possibly making types on a worker (one `builds()` on the
  op, beside `fieldReadBuilds`, L04).
- From L06i: our checker needs 117's and 118's fixes as its own code
  (`checkCaseDelayed`, `TTImp/Elab/Case.idr:653-656, 662-665`; `unifyHole`,
  `Core/Unify.idr:936-944`, pruning restricted to a clause's pattern
  variables because of its `bindUnsolved`), so the runner builds under
  idris-mlir too (L17, after L17bc); INT reinstalls the stock Idris with
  96 and 104 to 118.
- From L12w: an update's region verifier (`touchesInPlace`) refuses any
  op that writes or frees heap memory, so after counting a region that
  rebuilds a cell element (`cell.init`) or drops anything fails it; the
  rule must read the resource tree (what the update may not touch: other
  heap contents) rather than refuse counting's own work (L12 with L01's
  effect vocabulary, after the specification frees).
- From L18w: where an opened result's hold is weaker than the claim a
  caller's type makes, the cast back asserts (no cast raises a claim): a
  claim is an optimization and a weaker one always sound, so the caller's
  uses of the result are re-graded down to the open hold where the call
  stands (the specializer's opening edits the callee and every call, L18);
  `Open.cpp`'s grade helper restates the reindex verifier's rule (fold
  into C275's function, L04w); `referenceAt`'s memo exception can go (L07);
  `Local.h` and `ExclusivityGraph` read a memo field's emptied-place edge
  where they look for a taken-over cell (L08); memo's `getYieldTargets`
  in the specification.
- From L04w: `DataType::layoutMatch` has no reader left (its definition in
  `Types.cpp`, its declaration in `Spec/Families/Types.idr:207`: delete
  both after L07v releases the specification); `Layouts::fieldsAt` should
  set each field at the binders it determines, so field types match the
  stored layout, and then `fieldsAt` and `tagsLaidOut` go private in
  `Layout.h` (L04); `tests/reindex-builds-told-apart` is the first dialect
  test through the lowered stage in opt: if those steps need the module's
  target, its RUN line passes the driver's own target, never a pass (L19).
- From L04v: a tail call whose array result goes through a re-packing
  reindex (an element at other index terms, L16el's fit) is now an internal
  error before bufferization, as it was after: an array result whose
  element's layout differs from the caller's at a tail call takes D129's
  rule (the callee's copy returning the caller's element layout, marked
  open where an index stays unwritten), the specializer's, not Emit's
  (L18, after L18t).
- From spec round 4: `tests/spec-current/run` builds `spec.ipkg` expecting
  an executable; it installs the library into a work prefix, then builds
  `specgen.ipkg` (L19); `OtherTarget` has no test (L19);
  `harness/Scale.idr:155` writes `!idr.fn<(i64) -> i64>`, which the format
  never parsed (L19); the frontend's `Term.Termination` keeps `Acyclic`,
  now read as `MayDiverge` by every reader, its writers `Choices.idr:628`,
  `Programs.idr:229, 588` (L16, with the threading pass); `Settle.cpp`
  could keep the origin's proof instead of removing it, as the copy rule
  says, a behaviour change (L18). From L07u: `Narrow/Facts.cpp`'s `given`
  does what `heldAs` does (L07); the static small's type is computed in
  three places (Narrow's `small`, `Generating.cpp`, Emit): a builder on
  `idr.big.small` taking the carrier holds it once (spec); `Bufferize.cpp:313`
  asks `heldAs` to raise a claim from a fresh tensor, which no op admits
  (L12); at the Higher stage Emit's static values (literals, coordinates)
  reach call arguments and yields whose verifiers compare grades exactly,
  and no op gives static data as counted there (count.share is legal from
  First, lin.cast refuses equal uses): read whether the call's verifier
  admits it today, and if not, the decision (D89's specialization by hold
  runs at First) is the coordinator's.

## Dispatched after INT-23 (2026-10-23)

L11z (C279: idr-target first in every slice, the driver's lowered-module
check gone, no test names it; takes over L19w's held pipeline-timing
edit and its invalid root), INT-24 (the frontend over our own programs:
the frontend, syntax-samples, specgen, knowngen, the runner), L17bd
(C126's dependent-pair default and linear tuple patterns; the checker's
own fixes for 116 to 118), L12v (count.share's bufferization model,
array.update's emptied place, the generating ops' flow, the update
region's rule over the resource tree), L06j (patch 27 rewires the hook's
own cast), L19x (the root rule's test, the cycle contract, `reached` and
`folded` coverage, Rows' model, may-diverge), L04y (layoutMatch deleted,
fieldsAt at its binders, one `builds()` on reindex), L03aa (empty type
lists read back, SyntaxSamples' canonical form, the generator's typed
module list, `big.small`'s builder), L18x (D129 for array results, C267
for class copies, one open hold by C277, callers' claims re-graded,
askers in callersOf, Settle's removed proof). Waiting:
- After L03aa: Emit's own static small type (`compiler/src`, L16) asks
  the builder's rule.
- From L19w: `Show` on a deep pair at a known type is exponential (0.9 s,
  4.2 s, 35 s at 20, 24, 28 components) and an untyped `let` of a deep
  pair then `printLn` too: the instance search, not the tuple syntax
  (L17, measured with the checker alone at 3f7cd509).
- From L04y (its obligations 1 and 2 already met by 21f19207 and
  653608e8, 3 by c497d41d): after L16en releases `Spec/Families/Ops.idr`
  and the manifest, `builds` becomes the reindex op's member
  (`MkMember OnObject "bool" "builds" []` beside `isFree`, about :253),
  defined in `Families/Refinement.cpp` as `families::builds` of its
  value's and result's types, asked by the verifier there and the flow
  (`FlowOps.cpp:152`); the lowering's `repack` keeps asking the function
  on types (L04).
- From L11z: `Spec/Pipeline/Pipeline.idr:205-207`'s doc says the driver
  runs idr-target first (every slice does, L03); `Driver/Compile.h:94-97`
  says a lowered module goes "through LLVM" (now idr-target, then LLVM;
  L11); `Verify/Program.cpp:61-72`'s word-size check runs after every
  pass on a layout idr-target fixed, a fact of the build checked at run
  time (a build-time check of the target entry's word size, the read's
  check kept only as idr-target's; L04); `toObjects` sets the data
  layout twice (from DLTI, then the machine's; confirm the round trip on
  a build, INT).
- From L16em: `Term.Termination` restates the specification's
  `Termination` (`Unproved | InComponent Nat`): generated from it or
  replaced by it (L16 with L03).
- From L03aa: `array.tabulate`'s `outs` and `array.fold_last` /
  `array.scan_last`'s `inits` and `outs` print `( $g : type($g) )` with
  no optional group, so an empty group prints `( : )`, which MLIR's
  type-list parser refuses, and `OpsTabulate.cpp:41` calls
  `getOuts().front()` unchecked: the specification has no way to say "at
  least one" (L03 with L12: a non-empty variadic in the specification,
  its verifier generated); Emit's copy of the static small's type
  (`Emit/Tensors.idr:72`, `natural`, through `heldValue` at
  `Emit/Operations.idr:205`) asks the builder's rule: the generated Idris
  `bigSmallOp` takes the full result type because the specification's
  builders print for C++ only (L16 with L03, after L16en); nothing checks
  that every source under `compiler/spec` is in `Package.idr` (L03).
- From recheck 6 (D1 to D64): D7's five op-naming branches
  (`if constexpr (std::is_same_v<OpT, ...Op>)`) become the ODS fact each
  stands for: `Columns/ArrayOps.cpp:45`, `StructureLoops/Linalg.cpp:151`,
  `Narrow/Ops.cpp:125-133` (L12), `IdrDialect.h:173-187` (L03); after the
  running specification lanes (L16en, L01s) land. D49 and D51 are this
  machine's (INT-25), not the owner's.
- From recheck 6 (C1 to C130), waiting: C127 in the checker (`Repeated`
  in `Searched`, `Core/Unify.idr:186-188`, returned from
  `abandonIfCycle`, `Core/AutoSearch.idr:696-708`; the depth-limited
  quote returns `TooDeep` without throwing, `QuoteTooDeep` and its arms
  deleted), after L17bd releases `Core/Unify.idr` (L17); C82 (`Term.idr:365`'s
  `Unreachable` justified; an arm Idris proved impossible kept, not
  dropped as `Dead`, `Translate/Cases.idr:258-284`) and C228 (the slot's
  type carried so Emit's `Mismatch`, `Unfit` and `EmitFailed` go;
  `Terms.idr:802, 1636`), after L16ep releases `Frontend/` (L16); C23,
  C50, C80 dispatched (L16eq); C12's five prose `expected-error`s and
  C66's test dispatched (L19aa). Recheck 6 struck as done: queue lines
  468, 471, 479, 481, 483, 492, 583, 599, 635-638 and 749.
- From recheck 6 (D65 to D131): the frontend's `ITerm`
  (`compiler/src/IdrisMLIR/Types.idr:122-130`) copies the specification's
  `Term` by hand, its sum's normal form held by convention where the
  specification's type holds it: the frontend reads the specification's
  term (L16, after L16ep lands D131.2); five checker internal errors
  reachable from a user's `%builtin` pragma (`ProcessBuiltin.idr:188, 190,
  254, 275, 278`) become refusals as `%start` did, `Unify.idr:646`'s "Can't
  happen" states its reason, and the 38 "impossible" cases written as text
  become types (D112.2; L17, after L17bd); `Constants.cpp:245-262` and
  `EGraph/Values.cpp:509-520` read upstream attributes through
  `ConstantAttrInterface` once L03 declares it (L13, L14).
- From L04z: one `dyn_cast<DataType>` remains in `families::namedBy`
  (`Layout/Classes.cpp`) until `IndexedTypeInterface` declares the method
  that answers it, in the specification (L04 with L03, after the running
  specification lanes land).
- From L19y: `harness/Fuzz.idr:937` finds a builtin by
  `spellingText b.spelling == "prim__div_Int"`, a string as identity (L19).
- From L16eo (C281's design): steps 1 and 2 (build the annotated tree;
  the translation folds it, keyed the old way) land separately, steps 3 to
  6 together; after L16ep releases `Frontend/` (L16).
