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
