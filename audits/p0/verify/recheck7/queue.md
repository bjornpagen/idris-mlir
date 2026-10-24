<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 7: `handoffs/L16-queue.md` against HEAD

The queue was rechecked against HEAD d9ff115a0, and again at 0a5e44c5c, which
changes only the queue (its last section, Q1020-1056). Everything here is by
reading and grep. Nothing was built.

`Qn` is the queue's line. Lines 463 to the end (Q463-1056) are classified item
by item. Lines 1-462 list only what is still open there.

Ownership comes from `ownership.json`. "waits" names a running lane that holds
the files: L16et (Growth/{Graph,Sites}, Translate/{Annotated,State,Place}),
L16ev (Profile, Resolve, Registry/{Entry,Recognized}), K16 (`compiler/checker`),
L10aa (Tail), L12ab (Spec/Arrays), L18ad (Contracts/, harness), or L19ad.

**Counts (Q463-1056):**

| | Count | Notes |
|---|---|---|
| OPEN | 47 | 40 lane items and 7 INT items. |
| OWNER | 3 | |
| IN FLIGHT | 36 | |
| DONE | 85 | Bullets often hold several items, each counted once. |
| STALE | 6 | |

**Lines 1-462:**

| | Count | Notes |
|---|---|---|
| OPEN | 21 | 15 restate main-section facts and are merged into them; 6 are new. All are marked `(early Qn)`. |
| DONE | 103 | |
| STALE | 3 | |

## L16 (`compiler/src`)

### OPEN

**C281 steps 3-6** (Q472, Q478, Q511 N7; early Q36, Q70, Q186, Q190, Q196, Q200, Q224)
- Where:
  - `Frontend/Finite.idr:171-194`: `unsound`, `heightWithin` and `sizedWithin`.
  - `Translate/Types.idr:604-606, 959`: `boundsHold`.
  - `State.idr:616`: `record Request` has no `DrawnFrom` or `HeldAs` (C256, C222).
  - `Proof/Covers.idr:95-165`: the lemma's header still lists its open steps.
- C258 is also undone: the cache key holds no holes.
- Waits: L16et (steps 1-2).
- Recipe: fold the annotated tree as `handoffs/L16-fold-design.md` orders it, with the induction over the model's walk. Then delete the four run-time re-checks and write the held holes into the link.

**D112.1, the frontend's internal errors** (Q473; early Q12, Q20, Q53, Q113, Q153, Q176, Q180, Q212, Q220)
- 14 sites remain:
  - `Finite.idr:172` and `:224`;
  - `Growth/Graph.idr:2782` (`Outside`) and `:2784` (`Unheaded`);
  - `Program.idr:85` (Emit's `Unfit`);
  - `Cases.idr:951`;
  - `Choices.idr:567`;
  - `Shapes.idr:296` (`sizedTelescope` walks the type apart from the classification);
  - `State.idr:1444` (`missedEntry`);
  - `Terms.idr:639`, `:1688` and `:1792` ("the values an implementation closes over are gone");
  - `Terms.idr:745` and `:1588` (C228).
- `Keys.idr:1146` (the hash collision) is kept as a run-time fact.
- Waits: L16et for Graph, State and Finite; the rest ride on C281's fold.
- Recipe: classification returns the values it read per position, indexed by `Fin (Runtimes kinds)`, beside `SignedAt`. `InstanceSig` gains its `Binders`, so `sizedTelescope` reads them (first show that no verdict changes). A dispatch arm takes its member through `SignedAt` at the dispatch's kinds. `Reading` carries the walked set with membership evidence. `nodesFromMain` takes `headBound`/`countedIn` evidence.

**C228** (Q686, Q826; early Q214, Q216, Q259, Q269)
- Where:
  - `Terms.idr:739-745` (`forcedType`) and `:1577-1588` (`applied`);
  - Emit's `Mismatch` (`Emit/Tensors.idr:160-176`), `unfit` (`:207`), `EmitFailed` (`Emit.idr:69-76`), thrown at `Program.idr:83-85`.
- Waits: none (`Terms.idr`, `Emit/` and `Program.idr` are free).
- Recipe: `Types.coreTypeIn` returns the Core and Idris binder together, so the head and the operand carry it. Index the term by its scope's types (`TermAt js (sc : Vect n Ty) t`). Give `Ty` a Double literal by its bits, so `DecEq Ty` is total. Then delete `Mismatch`, `Unfit` and `EmitFailed`.

**C122** (Q474)
- Where:
  - `Translate/Closed.idr:403-420` (`byQuantity` and `argumentAt` give `ArgumentAt`);
  - `Growth/Sites.idr:1695-1697`, a second `byQuantity : Use -> Stand`, used at `:1797-1804` and `:2393` (`standFor` reads the binder's quantity).
- Waits: L16et.
- Recipe: `argumentAt` returns C122's one position type, `Absent | Index Sort | Runtime Quantity ClosedTerm`. Delete `ArgumentAt` and Sites' `byQuantity`, and `standFor` reads the position.

**C55's first half, case blocks** (Q475)
- Where: `Translate/Keys.idr:68-79` (`typedBlock`'s `.case<k>`) and `Boundary.idr:526`.
- Waits: L16et (C281).
- Recipe: emit a case block's tree as a region of its parent, and delete the `.case<k>` naming.

**C213/C217** (Q476)
- Four `RuntimeClosure` refusals name a translation situation rather than an unbounded set: `Terms.idr:627`, `:720` and `:1142`, and `Cases.idr:977`. L16ep removed the `formType` one.
- Waits: C281's fold.
- Recipe: compile each situation under D128's walk. Any refusal left names the unbounded member set or use-type set and its site.

**D44** (Q479)
- Where: `compiler/idris-mlir.ipkg:7` does not depend on `mlir-relational`, and `Finite.idr:21-32` is a hand-written semi-naive worklist.
- Waits: L16et, and a coordinator reading of whether C281's fold keeps C175's fixpoint shape.
- Recipe: depend on `mlir-relational` and run the instance generations as `Relational/Fixpoint.idr`'s fixpoint. Delete the worklist; O8's laws become queries on R2.

**F-R4, TupleSuper** (Q480, Q968; early Q391)
- A valid program is refused: `tests/every-types-export` expects exit 0.
- Where: `Proof/Describes.idr:158` (`carriedAt`'s `Field`) and `Growth/Template.idr:1093` (`ofDefinition`).
- Waits: L16et. D133 step 1 already released `Proof/`; check with L17bh during steps 3-8.
- Recipe: read a field of a record that a data constructor built as `Var i (S d)`, with its cases in Covers, Describes and Bound. Reproducers: `/tmp/l16dz/repro/TupleSuper` against `CurriedSuper`.
- Seams, still open:
  - an implementation's form erases a caller's level to `_` (C272 covers type parameters only);
  - `Shapes.sizedTelescope` (`:265`) reads a type parameter as the form;
  - `Instances.idr:860`'s `inScope` reads arguments beside `argValueIn` (`Terms.idr:558`).

**N10 and C284's frontend half** (Q508, Q882)
- Where: `Frontend/Resolve.idr:468` (`ArrayOperation : ArrayPrim`), `:568`, and `Translate/Terms.idr:2355-2405` (`arrayTerm`'s hand case: `AReshape`, `AMerge`, ...).
- No program test of `++`, `pad` or `grow` on word arrays exists.
- Waits: L16ev (`Resolve`, `Registry/Entry`, `Recognized`).
- Recipe: `Generating : ArrayMeaning -> Hook kd`, one walk over `Composed`. Delete `ArrayPrim`, `generatedOperands` and `arrayTerm` with their readers in `Faster`, `Recognized` and `Resolve`, and add the word-array program test.

**C82** (Q826)
- Where: `Translate/Cases.idr:257-272` (`Arm = Absent | Dead | Present`, `missingArm`) and `Term.idr:365` (`Unreachable : Loc`).
- Waits: none.
- Recipe: `Unreachable` carries its justification (the impossible constructor, or the clause marked `impossible`). Keep such an arm as a case ending in it, and delete `Dead`.

**`Term.Termination` and `ITerm` restate the specification** (Q805, Q838, Q490's frontend half)
- Where: `Term.idr:1597` (`Terminates ComponentId | MayDiverge`) and `Types.idr:119-130` (`ITerm`).
- Waits: L16et.
- Recipe: import the specification's `Termination` and `Term`. Delete both hand types.

**Emit's static small type** (Q782, Q808)
- Where: `Emit/Tensors.idr:70-72` states `Hold.Static (NatT IOpaque)` by hand, because the generated `Idr.bigSmallOp` (`Dialect/Idr.idr:452`) takes the full result type.
- The specification's builders print for C++ only.
- Waits: L03, for builders printed to Idris.
- Recipe: specgen prints `big.small`'s one builder (carrier, value) for Idris, and `natural` calls it.

**N5's last third** (Q511)
- Where: `Cases.idr:588`. `instanceOf` reads the family through `lookupFact` on the matched value's Core type, falling back to `dataOf` on its Idris type.
- Waits: none.
- Recipe: read the match's family from the case tree's `scTy` (kept scoped since d093dbfbd) and from `TyConFacts.constructors` at the boundary.

**N6's frontend half** (Q511)
- Where: `Translate/Closed.idr:567` (`rootOf` climbs `Nested` by placement).
- Waits: K16, for the checker half (L17 below).
- Recipe: `rootOf` reads the typed parent once the checker keeps it, and the climb goes.

**The registry compares text** (Q614)
- Where:
  - `Registry.idr:78-79`: `inModules` compares module paths as `List String`.
  - `Registry/Entry.idr:129-145`: `conforms` compares `Head Key` by name and returns a `Bool`.
- Waits: L16ev.
- Recipe: key heads by the resolved address read at the freeze, and modules by `ModuleIdent`. `conforms` returns the mismatch it found, not a `Bool`.

**Smaller items from lines 1-462**
- (early Q92) `libraryCall`: `Terms.idr:2062-2097` looks the definition up again by name and refuses twice. `CheckedLibrary` (`Resolve.idr:438-442`, `Boundary.idr:755-772`) keeps only the name.
  - Waits: L16ev.
  - Recipe: keep the `DefinitionRead` and the classified kinds as a `Vect`.
- (early Q274) `Terms.idr:1938-1942`: `boundTypes`' silent `fromMaybe b.type`.
  - Recipe: `operandsGiven` returns each operand's type beside its term.
- (early Q348) `Closed.idr:1266-1275`: `pairFor` refuses at `EmptyFC programEntry`.
  - Waits: L16et.
  - Recipe: `pairFor`, `packedType` and `unpacked` take the packing's FC.
- (early Q352) `State.idr:1419-1423`: the entry's and the pair's `Nature` are computed apart from the map.
  - Waits: L16et.
  - Recipe: read them back from the natured map.
- (early Q354) `Keys.idr:409`: `write` looks a metavariable up in `w.metavariables`, and a miss writes an address-less hole.
  - Waits: L16et.
  - Recipe: carry each metavariable's placement on the walked term (C281's tree).

## L17 (`compiler/checker`; all wait on K16)

### OPEN

**The ten internal errors left** (Q985, Q838)
- Where:
  - `Core/Case/Util.idr:27`
  - `Core/TTC.idr:133`
  - `Idris/Elab/Implementation.idr:221`
  - `Parser/Source.idr:53` and `:55`
  - `TTImp/Elab/Local.idr:198`
  - `TTImp/Reflect.idr:638`
  - `Core/Unify.idr:660`, "Can't happen", formerly `:646`, which also owes the statement of its reason
  - `Core/Unify.idr:1907`, formerly `:1787`
  - `TTImp/Elab/Check.idr:231`
- Recipe: the representation change L17be's handoff names for each.

**A record parameter** (Q985)
- A record parameter whose type is an unsolved `%search` writes back as `_`.
- Recipe: keep the solved term in the parameter's binder.

**`Show` on a deep pair is exponential** (Q784)
- It takes 0.9 s, 4.2 s and 35 s at 20, 24 and 28 components.
- Recipe: find the instance search's repeated work (measure with the checker alone).

**N6's checker half** (Q511)
- `Core/Name.idr:43`: `Nested : (Int, Int) -> Name -> Name`.
- Recipe: give the nested parent a typed name, as `CaseBlock (parent : Name)` already has.

**`updateHoleUsage`** (Q590, low value)
- `Core/LinearCheck.idr` visits an as-name twice and its pattern never. It costs nothing; upstream's copy is unacted.

## L18

### OPEN

**A copy whose results changed** (Q927)
- `Specialize/Requests.cpp:151` (`ResultsChanged`, `llvm_unreachable` in `passing`) and `SpecializeState.h:205`.
- A copy whose results its component's decisions changed is refused for later requests. For an open key this leaves a lost tail, an internal error at Graded. The nested-key floor closes one path; the others are unsearched.
- Recipe: where the requester's key is open, re-key the request at the copy's restated results instead of leaving the call a call, and search the other paths with a fixture.

**Copies' records** (Q890, with L19, L10 and L07)
- A function a pass makes has no record. Its new parameters and results are compared by nothing beyond quantities-kept.
- Waits: L18ad (linear-kept's result half).
- Recipe: each copying pass states the copy's origin and how its signature derives from it, and linear-kept compares through that derivation.

## L19 (`tests/`, `harness/`, Expect, Contracts)

### OPEN

**`repackOf` on `Tail.h`** (Q558, with L10)
- `Expect/Tails.cpp:50` (`repackOfUse`) restates `IR/Tail.cpp:43-80` (`carryOf`, `passageOf`).
- Waits: L10aa (`Tail.h`).
- Recipe: `Tail.h` exports `repackOf(op)`, read off `CarriesOnOpInterface`, and both ask it.

**The re-pack at `idr.index.assume`** (Q558)
- The lowering's re-pack of a value `idr.index.assume` takes in at another layout is seen by no property: no Expect reader names `assume`.
- Recipe: a property, or `results-as-given`'s walk, reads through `index.assume`.

**A once parameter in a loop body** (Q575)
- No fixture passes a once parameter into an `idr.loop` body and grades it through owned with the verifier clean. No `.mlir` test holds both `idr.loop` and `graded<once`.
- Recipe: add one such dialect fixture.

**K17** (Q1045)
- Moves the harness's specification modules into `compiler/spec`.
- Waits: L18ad and L19ad.

## L09

### OPEN

**Literal matches on computed constants** (Q558, L14y's seam)
- `Transforms/Joins/MatchRules.cpp:95-103`: `literalTaken` returns `nullptr` for a computed `Text`, `Real` or `Big` scrutinee, so a literal match on a computed string, Double or big is not decided.
- Recipe: compare each case key with the graph's value, using the `sameLiteral` the carrier states.

## L12

### OPEN

**C268, `tie_shape` names its axes** (Q552)
- Where:
  - `Spec/Arrays/Memory.idr:399-440`: `dims` still ties every dynamic axis, in order;
  - `IR/OpsArrayShapes.cpp`;
  - then L16's `Emit/Tensors.idr:630-660`, where `tie` reads an unstated axis's size off the array (`sizeAt`, `:657`).
- Waits: L12ab (`Spec/Arrays`).
- Recipe: the op takes the axes it ties as an attribute, and inference, reify and value bounds read it. Emit states only the axes something states. Reproducers: `/tmp/l16ef/repro/{successor-axis,literal-index}`.

**What bufferization writes** (Q901)
- `tensor.concat` and `tensor.pad` bufferize to `memref.subview`, `affine.apply` and `linalg.map`, which no admitted list names (`Spec/Arrays/Declarations.idr:46`), and no reader checks the stage bounds.
- `Transforms/Columns/` has no pattern for `tensor.concat`, `tensor.pad` or `linalg.transpose`.
- Recipe (with L03): admit them with stage bounds and a reader, or say why bufferization's output is outside the lists; add the column patterns if records of words reach them.

**Not verified** (Q1016, with L05)
- `array.new`'s marking at the counted stage: L05y names no file.
- Recipe: L05 reads it against C286.

## L03 (specification core, generator)

### OPEN

**`Termination` is held three times** (Q490, with L02 and L16)
- Where:
  - `Spec/Functions/Termination.idr:29`: `data Termination` is read by nothing;
  - `IR/Func.h:58-77`: `InComponent`, `Unproved` and the `Termination` variant are written by hand (L02);
  - L16's `Term.idr:1597`.
- Recipe: specgen emits the variant from the specification's type, `Func.h`'s copy goes, and the frontend imports it.

**No check that `Package.idr` lists every module** (Q818)
- Nothing checks that every `.idr` under `compiler/spec` is in `Generator/Package.idr`.
- Recipe: `specgen check` lists the tree and fails on a module the package does not name.

**The string-output check as a proof** (Q911)
- `Generator/Outputs.idr:355-378` checks it at generation time.
- Recipe: make these `public export`, then prove the check beside `namesDistinct` (`Spec.idr:306`):
  - `matchable` (`Control/Matches.idr:55`, L09);
  - `refinedValue` (`Families/Ops.idr:37`, L04);
  - `endsOwner` (`Counting/Declarations.idr:131`, L07);
  - `runsOnce`, `runsOnceGivingBack` and `givesLifetime` (`Lifetimes/Declarations.idr:435-459`, L05).

**One fact stated twice** (Q590, low value)
- A runtime row's `TakesStr` and an operand's `strRead` are the same fact, stated twice.
- Recipe: derive one from the other.

## L04

### OPEN

**`groupOf`'s cast** (Q514)
- `IR/Families/FamilyVerify.cpp:57`: `cast_if_present<FamilyAttr>(sort.payload)`, because `Sort` (`Families/Terms.h:66-73`) holds an untyped `mlir::Attribute`.
- Recipe: `Sort` holds a typed payload per kind (a scalar's type, or a family group), and the cast goes.

**`KeptDigest`** (Q1051, with L06)
- `IR/Families/FamilyStorage.h:71`: the digest is filled on first ask. PINS.md does not record this deviation.
- Recipe: add the PINS.md entry, which says why: MLIR gives a storage its kind only after constructing it.

**Not verified** (Q1016)
- A `many` `DataConOp` builder that would write a claim. `OpsCon.cpp:52` asks `freshClaim`; no other builder has been checked.

## L07

### OPEN

**`own.adopt`'s type** (Q1016)
- `IR/Counting/Ops.cpp:181`: it infers `many, counted unique deep` against its bare results.
- Recipe: confirm against C286's stage rule (claims allowed from owned), or narrow it.

**Many values held across a loop** (Q575)
- Many values read in an `idr.loop` body are still held across it: a dup at the entry, a drop after, a count of 2 inside.
- Recipe: apply the repetitive-region rule to many values too, measured at qualification (with INT).

## L06

### OPEN

**A stale claim in `tools/dialects.sh`** (Q943)
- `tools/dialects.sh:30-34` says "the records are the same, so are the modules". That holds only while the typecheck tree's ODS is the pin's (INT-notes.md:322-324).
- Recipe: rebuild the typecheck toolchain at the pin, or strike the claim.

## L11

**IN FLIGHT, to confirm** (Q796)
- `Driver/Compile.h:85-88` says a lowered module goes "through LLVM"; it goes through idr-target, then LLVM.
- This is counted as one of L21z's (K15) "descriptions", but `Compile.h` is an L11 path: confirm that L21z's scope covers it.

## INT

### OPEN

**The stock Idris is out of date** (Q590, Q602, Q708)
- The installed `.toolchain/idris2` dates from 2026-10-23 06:55 and lacks patches 115-118. Because of it, `make check` cannot run on this machine (INT-notes.md:328-332).
- Recipe: run `tools/bootstrap.sh idris` with 96 and 104-118. It needs no LLVM, so it can run here.

**The stage-1 measurements** (Q494; owner's machine)
- D30's `tailcc`, D32, D33, D58's `shapeBudget`, D78, D95, D100, D108's `nodesPerOp`, D115, C5, C43, C98, C201.
- Also recheck the entries in `audits/bugs.md`.

**The cull's measurements** (Q1047)
- M1-M6, which K18-K20 wait on.

**The narrow bound** (Q1055)
- U01 holds one 32-byte bound per value while idr-narrow runs, unmeasured.

**The five self-host programs** (Q951)
- Rerun the frontend over the five (the frontend, syntax-samples, specgen, knowngen, the runner) after L16er and L17bg, possibly as INT-26. Route each new refusal by owner.

**The data layout is set twice** (Q796)
- `Driver/Artifacts.cpp:246` and `Run.cpp:215` both set it, and `Target.cpp:56` sets the scratch module's.
- Recipe: confirm the round trip on a build.

**The typecheck toolchain** (Q943)
- Rebuild it at the pin (it is about 2430 commits behind).
- `build/typecheck`'s idris-mlir-tblgen predates 04d7cfcc: run `make typecheck-tblgen`.

**The gives-back tests** (early Q439)
- Run the tests that read gives-back facts (C277 and C278's readers) and route failures to L18.

## OWNER

**The pending §4 questions**
- **K21, K22** (Q1047): §4's third question, D50's builders (print builders only for ops with an attribute, a region or a variadic group, the generic `specOp` building the rest; or keep D50 with a hand `writer` flag), and QB.
- **U11's properties written natively** (Q1049): stopped on the row's wire format and on the same D50 question. Ask the owner for the row's wire format alongside §4's third question.
- **C298's verifier half** (Q1004): §4's second question, where "a callee keeps nothing of parameter i" lives: (A) a per-parameter fact in the signature, or (B) a `view`-scoped parameter decided earlier. Until it is ruled, L08z checks the local half only.

**Recorded for the owner's review, not questions**
- C268, C281, C283.

## IN FLIGHT (not rechecked)

**Constants, folding and the e-graph**
- Q485, Q558, Q838: `heldFacts` and `Constants.cpp`/`EGraph/Values.cpp` through `ConstantAttrInterface::getFoldValue` (L03ae).
- Q485, Q590, Q927: C264(c)'s e-graph half and the specializer round after the e-graph (L14ad).
- Q927: `static-argument-keyed-by-hold` (L19ad).
- Q995: `data.reindex` after C293 (L18ac).

**Tail calls**
- Q502: N1 (L10aa). The climb is gone (f46fe91d6), but `optimize::decideTails` remains at `Optimize/Tails.h:34` with nine callers.

**idr-target**
- Q544, Q796: the word size (L05z, K11) and `Pipeline.idr:205-211`'s description (L21z, K15).

**Tests**
- Q599: the root rule's tests (L19ad). `tests/root-takes-and-gives-nothing` exists since 1af4154cd: check the dispatch is not a duplicate.
- Q853: `Fuzz.idr:937` (L19ad).

**Reindex builders and `builds`**
- Q700, Q788, Q964: `builds` as the reindex's member, and the three reindex builders (L18ac).

**Arrays and the specification**
- Q808: the non-empty variadic (L12ab).
- Q877: C280's three comments (L12ab).
- Q896: the typed inline meaning (L12ab).
- Q937: `Words.cpp` and `Remake.h` (L12ab), and `Generating.cpp`'s destinations (L03ae).
- Q849: `namedBy` (L03ae).

**The frontend and the checker**
- Q855: C281 steps 1-2 (L16et).
- Q951: R-META (L16ev).
- Q1040, Q1043: D133 steps 3-8 (L17bh).
- early Q226: `Idris/Host.idr`'s `assert_total` and `trusted` (D133).

**Lowering and contracts**
- Q858: `Strings.cpp:254`'s row (L13z).
- Q1004: the c291 Results patch with linear-kept, dead results and the cast, the specializer's casts (L18ad); C298 over a match's bound value and `idr-unique-results` (L08z).

## DONE (Q463-1056)

**Frontend and checker**
- closedHeight (Q478): 088c8197d.
- Compose (Q480): 3a943472b.
- `MLIR.idr:149` `typeText` (Q480): 3f8ff9726.
- C272 (Q608): bc08f0952.
- Emit's `fitting` element (Q612): a0138e0a9, `Tensors.idr:163-168`.
- L16eg's second pass (Q614): 088c8197d.
- exit-with and harness-cases (Q617): 1bc9c3250.
- The checker's `scTy` scoped (Q686): d093dbfbd.
- form-delay and runtime-closure-poly-rewrapped (Q694): bc08f0952.
- The checker's 117 and 118 (Q708): 723cac53d.
- The checker's checkUpdate (Q602): fc306c2c3.
- C127 (Q826): 050d2d7f6.
- The `%builtin` internal errors (Q838): fa57f8c60 (0 hits in `ProcessBuiltin.idr`).
- 28 of the 38 "impossible" cases (Q838): fa57f8c60.
- S-1, S-2, R-SPEC, R-ESC-FIN, R-PRAGMA (Q957): 1f225b6b9. R-UNIFY: 8180a8c4e. R-117: 723cac53d.
- N4 (Q511): 088c8197d.
- N5's `siblings` and `coversAll` (Q511): 088c8197d.

**Specification and generator**
- Generator/Main's ipkg scan (Q491): f7271225f.
- P-1 (Q643): 653608e8b, f7271225f (`specgen.ipkg`, `Makefile:245-257`).
- Empty type lists and SyntaxSamples' canonical form (Q524): f7271225f.
- C50 (Q917): 3f8ff9726.
- `EliminatesOperand`'s comments (Q858): dde1b109b.
- The generator's one-string-output check (Q867): dde1b109b.
- `big.small`'s C++ builder (Q745): f7271225f.

**Effects and termination**
- C65's insertion and readers (Q483): 3dc79aa3b, 5a3c07f12, 8123ffde1.
- L09x's order (Q583): 5a3c07f12, 8123ffde1, 653608e8b, 13a29cf14.
- L02x's Rows seed (Q632): 67cbb8735.
- `Acyclic` (Q632, Q745): 29153f207.
- `Termination`'s text (Q632): 653608e8b.
- The cycle contract (Q650): 8c59308b7.
- expect-coverage's `reached` and `folded` (Q650): 8c59308b7.
- N2 (Q506): fc6fb0f81 (`Components.h:50`).

**Folding and constants**
- C87's callers (Q485): c889c8d55, 19307ee9b.
- Float ops computed by `APFloat` (Q485): 07e4e8443.
- Guards over computed values (Q485, Q558): d378e120e, 6f58d7d70.
- `OperandFacts::constant` (Q485): 07e4e8443.
- Tests of the Double ops and the large divisor (Q558): 1af4154cd.
- The two folders (Q667): D132, 88cafbf3f and 177aefcca.
- C290's rest (Q995): 0f71306ac.

**Targets and the driver**
- `Target.cpp`'s overwrite (Q521): 8a5c1249f.
- `OtherTarget`'s rule, its test, the driver's lowered-module check, OpsPlatform's comment (Q544, Q745): 653608e8b, 3abb69131, 2d7ee52de, 0b80c601a.
- `reindex-builds-told-apart`'s RUN line (Q730): 2d7ee52de (C279).

**Families and layout**
- D130 and D131, C265's gate, C267, `indexTerm`'s plus, L18y's tests (Q530): 8b218c36c, 410c5dcd8, bc08f0952, 92029979f.
- `kindOf` typed (Q514): c889c8d55.
- Expect's `idsOf` cast (Q514): b17aceabd (`Expect.h:237`).
- `layoutMatch` (Q730): 21f192071.
- `fieldsAt` and `tagsLaidOut` private (Q730): `Layout.h` private section.
- L04v's array tail re-pack (Q738): 1e2857f82.

**The specializer**
- L18z's class copy, `openTails`, `callersOf` askers (Q622): 410c5dcd8, 1592a891b, 1e2857f82.
- `Signatures::edit` re-grades results (Q590): 2a9370b75, a0d5c9c36.
- Re-graded down (Q720): 1580ee215.
- `Open.cpp`'s grade helper (Q720): 21f192071.
- `openedAgainst` (Q680): 1d3729844.
- Settle keeps the origin's proof (Q745): 1e2857f82.
- Emit's `coerce` against the call verifier (Q558, Q760): ace30d539, a0d5c9c36.

**Counting, exclusivity, memo and arrays**
- C269 (Q575): 19307ee9b.
- Memo captures and the generating ops' flow (Q659): 4e839e4a8, 989d2e0c6, d41d1c974.
- L07v's readers (Q665): 3bd926f92.
- A building reindex is fresh (Q680): d41d1c974.
- `array.update`'s emptied place (Q700): b9a759ecc.
- Placement forgets a claim (Q702): 3bd926f92.
- The update region over the resource tree (Q714): 1ecf15893.
- `referenceAt`'s memo exception (Q720): 0 hits for "memo" in `IR/Counting/Flow.cpp`.
- Local.h's memo edge (Q720): 989d2e0c6.
- memo's `getYieldTargets` (Q720): `Closures/Memo.idr:61`.
- Narrow's `given` and `Bufferize.cpp:313` (Q745): 327b1f790.
- `tensor.concat` and `tensor.pad` admitted (Q882): 688f6b905.
- D7's branches (Q820): 0aa95a759.

**Tests and harness**
- expect-coverage's `tail-calls` and `results-as-given` (Q558): 1af4154cd (`Properties.idr:191, 194`).
- The `open-copy` and `sum-index` fixtures (Q622): 1af4154cd.
- open-copy holds words (Q680): 3abb69131, 1d3729844.
- spec-current, `OtherTarget`'s test, `Scale.idr` (Q745): 3abb69131.

**Other**
- The strike of §5 (Q500): 230852fe9 (`idris-linear-check.md:113`).
- D49 and D51 (Q494, Q820): 49a26442c.
- Static values at Higher (Q760): ace30d539.

## STALE (Q463-1056)

- `isBuildableWith` and `constantStandsAt` (Q485): gone, 9ac7bb651 and 0f71306ac.
- `sortedIds(NeverFolded)` (Q485): idr-constants deleted, 177aefcca.
- "A lend's give-back stays a trait" (Q659): a design note; no work.
- `Terms.idr`'s 918 s check (Q686): a measurement; no work named.
- Q1040's "C127" and "the `%builtin` internal errors": both are done (050d2d7f6, fa57f8c60). Strike them from K16's waiting line.

## Correctness risks (by reading)

1. **F-R4: a valid program is refused.** `Ord (Either a b)`, constraint tuples, and base's `Monoid (SortedMap k v)`; `tests/every-types-export` expects exit 0. (L16)
2. **C268: a tail call can be lost.** `Emit/Tensors.idr:657` reads an unstated axis off a call's result after the call, wherever some axes are stated and others not. The read follows the call, so it is no longer a tail. (L12, L16)
3. **`Requests.cpp:151`: an internal error at Graded.** A `ResultsChanged` copy leaves an open key's call a call, which loses the tail. Paths beyond the nested-key floor are unsearched. (L18)
4. **`Keys.idr:409`: suspected wrong signature.** A metavariable missing from the writer writes an address-less hole, so two requests could key alike and a cache hit would hand one the other's signature. (L16)
5. **`Shapes.idr:290-296` and `Choices.idr:567`: reachable internal errors.** Each reads one type twice, and nothing ties the two readings. (L16)
