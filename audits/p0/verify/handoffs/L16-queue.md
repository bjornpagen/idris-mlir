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
