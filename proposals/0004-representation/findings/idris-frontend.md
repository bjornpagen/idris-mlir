<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Representation survey: idris-frontend

Area: `compiler/src/IdrisMLIR/Frontend/{Translate/Dictionaries,Translate/Errors,Translate/Given,Translate/Primitives,Translate/Shapes,Translate,Resolve,Walk}.idr`, `libs/mlir-array`, `libs/mlir-linear`, `tests/{Main,Runner,Gen,Fuzz,Prims,Sem,TwoLevels,Lock}.idr`. Read-only. Line numbers in this area's files are stable (no lane is editing them). Line numbers in other files are as of the survey and approximate, because the cleanup lanes are editing those files now. Symbols are given everywhere.

## The area as it stands

Most of the area is in good shape. `Walk` and `Given` are type-driven: a measure the types can see, and a telescope read without substitution one binder at a time. The two libraries keep shapes, extents, bounds and linearity in their types (`Index s`, `Extents s`, `Cell c`, erased `LTE` and `count s = count t` proofs, quantity-1 continuations), and check at run time only at their boundaries (`checkIndex`, `!?`, a vector's capacity test). The defects cluster where a fact is flattened at a boundary:
- A refusal turns into prose at the moment `reject` makes it. Every consumer then re-reads it as text: `noting`'s dedup, the C++ driver's verdict, and `profile.sh`.
- Idris's `PrimType` and `RigCount` are re-classified in several places, by partial or Boolean functions, instead of one total view.
- `Shapes` names positions with bare `Nat`s in three coordinate systems, and converts between them with lookups that return `Maybe`.
- A definition's identity is resolved from its `Name` two or three times per site.
- In the test machinery, `Prims`' flat `Ty` forces partial width and bounds functions and a parallel proof family. `TwoLevels` spells primitives again as strings. Tests identify cases by position and pass facts through comments that shell scripts re-parse.

Two bugs came out of this reading:
1. The frontend refuses `prim__negate_<fixed>`, but `Prims`/`Fuzz` generate it (finding 3).
2. `TwoLevels` claims "every primitive" but covers about 297 of `Prims.prims`' 353 (finding 7).

## Ranking

| Rank | ID | Root cause | Branches removed (approx.) | Risk |
|---|---|---|---|---|
| 1 | idris-frontend-1 | A refusal is prose from the moment it is made | ~15 checks in Idris and shell, plus a stated invariant made true | medium (reverses one line of 0002 §4.4) |
| 2 | idris-frontend-2 | Shapes: positions are bare Nats in three coordinates; the witness analysis is written twice | ~22 | medium |
| 3 | idris-frontend-3 | `PrimType` classified by three partial functions; `primOp` is a priority cascade (and the Neg bug) | ~35 arms, 1 dead refusal | low |
| 4 | idris-frontend-4 | `Prims.Ty` is flat: integerness and width recovered by `Maybe` and a proof family | ~40 arms | low |
| 5 | idris-frontend-5 | `RigCount`: five classifiers, ~40 Boolean tests, `quantityOf 0 = Many` | 5 classifiers to 1; ~40 tests become matches | low |
| 6 | idris-frontend-6 | A definition's place is resolved two or three times per site; `enter`'s `Nothing` means two things | ~12 | low |
| 7 | idris-frontend-7 | `TwoLevels` re-spells `Prims` as strings, so "every primitive" is a comment | coverage gap of ~56 primitives; ~10 string arms | low |
| 8 | idris-frontend-8 | A test case's identity is its position (`t<n>`, Sem chunk numbers) | all 699 expected lines go stale on one insertion | low |
| 9 | idris-frontend-9 | Semantics tests held twice: `Sem.tests` and 72 identical directories | 144 files, 1 spec | medium (runner) |
| 10 | idris-frontend-10 | Generator facts pass to shell through labels and comments that shell re-parses | ~55 lines of awk/sed | medium |
| 11 | idris-frontend-11 | Probe sentinels spelled as string literals in six files, one spelling shared by two families | 18 literals | low |
| 12 | idris-frontend-12 | A dictionary field has two keys, converted by a lookup by printed symbol | 1 internal, 2 `Maybe`s | low |
| 13 | idris-frontend-13 | `Loc` uses `""` for "no file" and "no module" | 3 `== ""` tests | low |
| 14 | idris-frontend-14 | Shape terms recognised by hand three times; `arrayShape`'s pair is never read | ~8 | low |
| 15 | idris-frontend-15 | Gen/Prims: dead arms a measure or evidence would rule out | 4 | low |
| 16 | idris-frontend-16 | Lock validates and silently skips non-object entries | 2 | low |
| 17 | idris-frontend-17 | Fuzz literal pools hold source text and parse it back | 2 helpers | low |
| 18 | idris-frontend-18 | `IndexInto Nat` points at another argument by position | 3 | low |

---

## idris-frontend-1: a refusal is prose from the moment it is made

**Evidence.**
- `Translate/Errors.idr:33-37`: `reject` builds `GenericMsg fc' (owner ++ ": unsupported (" ++ show rule ++ "): " ++ what)`. From that point the `Rule` (an ODS-generated enum, `Syntax/Idr.idr:184`) and the site exist only as text.
- `Errors.idr:51-59`: `noting` dedups by `any (\e => show e == shown) st.rejected`, a linear string compare per recorded error.
- `Translate/State.idr` (`TS.rejected : SnocList Error`).
- `Resolve.idr:221-225` (`data Validation = Valid | Wrong FC String String`) is consumed once, at `Program.idr` `validated`, which turns it into `reject at owner HookShape msg`.
- `Resolve.idr:159-160`: `foreignHookOf : … -> Maybe (Either String Hooks)`. Two callers re-make the same three refusals:
  - `Profile.idr` around line 376: `Just (Right hs)`, `Just (Left wrong) => reject … HookShape`, `Nothing => reject … EscapeHatch`;
  - `Terms.idr` around line 916: the same three arms.
- `foreign/idr/lib/Driver/Compile.cpp:41-67` reads only exit status 3, as `Verdict::Refused` with no diagnostic, so the report holds `verdict: refused` alone.
- `harness/lib/profile.sh` re-parses the prose:
  - `:91` counts `grep -o 'unsupported ('`;
  - `:94-96` guards `grep -qF 'internal error'` ("which may quote a diagnostic … that reads the same");
  - `:104-108` greps the phrase;
  - `:23-26` `reported_line` parses two text formats, Idris's and MLIR's.
- `tests/spec/refusals-as-data/run:4-11` states the opposite of what happens: "A refusal is a diagnostic that carries its rule, which the driver reads; the phrase … never matched by its text". On the frontend side, which makes most refusals, the code contradicts it.

**Counterexample.**
- A reject fixture whose refused source line also holds `unsupported (` in a comment. The driver prints the error's source lines (`Driver.showingItsSource`), so `profile_reject` counts 2 and reports "expected once".
- An internal error that quotes a refusal phrase is classified by a text guard.
- Two distinct refusals that print alike are merged into one.
- A `--report` for a frontend refusal cannot say which rule refused or where. A C++ refusal's report can.

**Root cause.** The frontend has no refusal value. Idris's `Error` is the only carrier, and the frontend fills it with prose.

**Correction.**
- Add `record Refusal where constructor MkRefusal; site : FC; owner : String; rule : Rule; what : String` (with `Eq`/`Ord`), held in `TS` as `rejected : SortedSet Refusal`, with Idris's own errors beside it as `IdrisRejection Error`.
- `reject` records the `Refusal`, puts it in `TS.inFlight : Maybe Refusal`, and throws the rendered `GenericMsg` only to unwind. `noting` takes `inFlight`: `Just r` is already recorded; `Nothing` records the error as Idris's.
- `render : Refusal -> String` is the one phrase, byte-identical to today's.
- `validate` returns `Maybe Refusal`. `foreignHookOf` returns `Either Refusal Hooks`, with each refusal built once in `Resolve`.
- The driver gives the frontend `--report FILE`. The frontend writes 0002 §4.4's `diagnostic: error <rule with dashes> <file:line>` line per refusal (`-` as rule for Idris's own errors), and `Compile.cpp` folds those lines into its report.
- `profile_reject` reads rule, count and line from the report.

**Deletion.**
- `noting`'s string scan;
- `Validation` and `Program.validated`'s case;
- the three-way re-match at the two `foreignHookOf` callers;
- in `profile.sh`: the `unsupported (` count, the `internal error` guard, the phrase grep and `reported_line`. The `message:` header stays: it checks the human text, which is its contract.
- 0002 §4.4's carve-out "a frontend refusal writes `verdict: refused` alone".

**Consumers.**
- `Frontend/Translate/{Errors,State}.idr`, `Frontend/{Resolve,Program,Profile,Driver}.idr`, `Frontend/Translate/Terms.idr`;
- `foreign/idr/lib/Driver/{Compile,Options}.cpp`;
- `harness/lib/profile.sh`, `tests/spec/refusals-as-data/run` (its claim then holds).

**Discriminator.** The comment fixture above fails today and passes after. A `--report` of `tests/polymorphism-nested` names `polymorphism` and line 12.

**Verification here.**
- The frontend builds and runs on Chez. Run `idris-mlir-front --core … -o …` on the reject fixtures: the report lines it writes, and stdout byte-identical to today.
- `Compile.cpp` under `make typecheck`.
- `profile_reject` end to end needs `idris-mlir` (owner's build).

**Size and risk.** About 60 lines of Idris and shell removed. The risk is in the printed text, which must stay byte-identical. Reversing 0002 §4.4's line is the owner's call. Essential and kept: Idris's own errors, which carry no rule, and the refusal/internal split in `Driver.statusOfAll`.

**Insight.** 6 (validation discards the proof: here, the rule), 4.

## idris-frontend-2: Shapes names positions with bare Nats in three coordinate systems, and writes the witness analysis twice

**Evidence.** All in `Translate/Shapes.idr`:
- `SizeVar = Axis Nat Nat | Size Nat` (`:101`) uses the definition's parameter position.
- `Witness = NatAt Nat | AxisAt Nat Nat` (`:206`) uses the runtime parameter position.
- The axis `k` is a third coordinate.
- Conversions go through lookups that can miss: `runtimeIndex` (`:188-192`, `getAt` plus an if), `unrestricted` (`:197-200`), and `witnessTerm` (`:301-303`, `getAt r vs` twice).
- The analysis exists twice: `entryWitnesses.sourced`/`firsts`/`witness`/`tieOf` (`:215-257`) and `resultWitnesses.sourced`/`witness` (`:264-296`).
  - Each copy repeats `Just r <- pure (runtimeIndex kinds i) | Nothing => pure Nothing` and `dimensionSources a`.
  - Each copy pads with `srcs ++ replicate (length ds) Nothing` (`:256`, `:272`), because `ds` (the Core `Ty`'s dims) and `srcs` (the Idris type's sources) are two readings of one type, matched by position.
  - The copies have already diverged: `firsts` (`:236-238`) takes only `Dynamic` dims as sources, while the result's `sourced` (`:280-282`) takes every dim.
- `sizedTelescope` (`:153-177`) matches `arity` against `kinds` by position and returns a shorter telescope on a mismatch (`_ => pure ([], t')`).
- Consumers re-derive the same coordinates:
  - `Programs.idr` `tied` (around 385-389): `natToFin r n` with a skip on `Nothing`, `fromMaybe p (natToFin i n)` per parameter, `w >>= witnessTerm`, and the internal error `when (length env /= length kinds)` (around 353);
  - `Terms.idr` `tiedCall` (around 1040-1047): `w >>= witnessTerm`, `mapMaybe runtimeBinder kinds`;
  - the runtime list is re-filtered at four more sites in `Terms.idr`.

**Counterexample.** A size variable fixing a static axis of one parameter and a dynamic axis of another is tied at a call's result but not at the function's entry, because the two copies disagree. A runtime index past `vs` silently drops the tie (`Nothing`) instead of failing to typecheck.

**Root cause.** The telescope holds no runtime position per parameter, so each consumer recounts it from `List PKind`. Dimensions and their sources are two parallel lists.

**Correction.**
- `sizedTelescope` returns `Telescope r`: one entry per parameter, `{ kind : PKind, type : ClosedTerm, runtime : Maybe (Fin r, Binder), dims : List (Dim, Maybe SizeVar) }`, built in one walk.
- `Witness r = NatAt (Fin r) | AxisAt (Fin r) Nat`.
- One table, `witnesses : Telescope r -> SortedMap SizeVar (List (Witness r))`, filled from the quantity-ω entries in parameter-then-axis order (natural first, then every axis).
- Entry ties: per dynamic dim, the first witness of its source other than itself. Result ties: the first witness.
- `witnessTerm : Vect r (Fin n) -> Witness r -> Term n`, total.
- The static/dynamic asymmetry is settled one way: static axes witness too.

**Deletion.**
- `runtimeIndex`, `unrestricted`, both `sourced`, `firsts`, both `witness`, `tieOf`, both paddings, `witnessTerm`'s `Maybe`;
- in `Programs.tied`: both `natToFin` fallbacks and the out-of-order internal error;
- in `Terms.tiedCall`: `>>=`.

**Consumers.** `Translate/Shapes.idr`, `Translate/Programs.idr`, `Translate/Terms.idr`, and `Translate/State.idr` if `PKind` lists become a `Vect arity`.

**Discriminator.** An array program with `f : (n : Nat) -> Array [<3] a -> Array [<n] a -> …` where a static and a dynamic axis share a source: the entry tie appears after the change. Removing an argument from the `vs` given to `witnessTerm` becomes a type error.

**Verification here.** The frontend on Chez: the Core text of `tests/programs/arrays/*` before and after. Byte-identical except the decided asymmetry.

**Size and risk.** About 22 branches and 60 lines. Medium risk: the tie semantics must be preserved. Essential and kept: static against dynamic dims, and quantity one against ω (a value used once witnesses nothing).

**Insight.** 11 (coordinates), 6.

## idris-frontend-3: `PrimType` is classified by three partial functions, and `primOp` is a priority cascade

**Evidence.**
- `Resolve.idr:180-194` `primTy : PrimType -> Maybe PrimTy` returns `Just` on all 14 constructors, so `shapeOf`'s `maybe Hole` (`:204`) is dead.
- `Types.idr:52-62` `intTy : PrimType -> Maybe IntTy`. Its consumer `coreTypeIn` (around 687-695) re-cases the five non-integers after `Nothing` and ends in `_ => reject fc owner rule (show t ++ " in a runtime position")`, which is unreachable.
- In `Translate/Primitives.idr`:
  - `scalar` (`:17-20`), `runtimeCast` (`:45-48`) and `fromString` (`:91-93`) are each another partial classification;
  - `primOp` (`:96-116`) matches a 5-tuple `(integer p, double p, arith p, comparison p, p)` whose correctness depends on arm order (`arith (Add DoubleType)` also matches, and only the order sends it to `double`);
  - `opOrder` (`:122-124`) falls through unchanged on any other arity.
- `Terms.idr` around 1246-1248 splits `Neg` again before calling `primOp`: `Neg DoubleType`/`Neg IntegerType => supported`; `Neg _ => reject fc ctx.owner Primitive "negate"`. `primOp (Neg IntType)` would also return `Nothing`, a second refusal of the same case.
- **Bug.** Idris has `prim__negate_<t>` for every numeric type (`Core/Primitives.idr:685`). `harness/Prims.idr:466` lists them, and `Fuzz.has Runtime` admits them. A runtime fuzz case of a fixed type with the Negate family kept therefore compiles to exit 3, and `tests/fuzz/seed-*` "every build compiles" fails on the owner's build.

**Counterexample.** A new `PrimType` constructor upstream: `coreTypeIn`'s `_` swallows it as a refusal instead of a coverage error. Reordering `primOp`'s arms silently turns Integer addition into `IntOp`, and `intTy` then gives `Nothing`.

**Root cause.** No total view of `PrimType`. The registry's `PrimTy = IntP IntTy | IntegerP | CharP | DoubleP | StringP | WorldP` (`Registry/Entry.idr:85`) is that view, but it is reached through `Maybe`.

**Correction.**
- Make `Resolve.primTy : PrimType -> PrimTy` total.
- `primOp` matches `(p, primTy t)` directly, one arm per meaning. Its `Maybe` remains only for combinations Idris never builds (`Add StringType`), which `PrimFn`'s type admits.
- `opOrder : PrimFn k -> Vect k a -> Vect k a`.
- Fixed-width `Neg` translates as Prelude's own `negate` for every fixed width, the width's `IntOp Sub` from 0. `Terms`' `Neg` pre-split goes, so `Prims` and the compiler agree.

**Deletion.** `Types.intTy`; `coreTypeIn`'s nested case and dead refusal (one 6-arm match instead); `scalar`'s, `runtimeCast`'s and `fromString`'s `PrimType` arms; the tuple cascade; `opOrder`'s catch-all; `shapeOf`'s dead `Hole`; the three `Neg` arms in `Terms`.

**Consumers.** `Frontend/Resolve.idr`, `Translate/Primitives.idr`, `Translate/Types.idr`, `Translate/Terms.idr`, and possibly `IdrisMLIR/Types.idr` (`Prim.Negate` is Double-only by name: `show Negate = "neg_Double"`).

**Discriminator.** `tests/fuzz/seed-1` compiles every runtime case (it fails today when a case draws `prim__negate_Int8`). A program applying `prim__negate_Bits16` prints `wrap(-x)`. Adding a `PrimType` constructor fails coverage in one place.

**Verification here.** Frontend on Chez: the Core of the fuzz programs (`runtests --fuzz-program program 1 30 runtime main`) translates with no refusal. Running them needs the owner's build.

**Size and risk.** About 35 arms. Low risk. Essential and kept: the escape hatches (`BelieveMe`, `Crash`) and `opOrder`'s one real permutation.

**Insight.** 4, 7.

## idris-frontend-4: `Prims.Ty` is flat, so integerness and width are recovered by `Maybe`s and a parallel proof family

**Evidence.**
- `harness/Prims.idr`:
  - `Ty` (`:25-26`) has 13 constructors;
  - `widthOf : Ty -> Maybe Width` (`:80-93`) has 4 `Nothing` arms, and `bounds : Ty -> Maybe` (`:134-141`) follows from it;
  - `IsInteger` (`:97-107`) has 10 constructors that restate the integer subset;
  - `divisor`/`operand` (`:438-454`) test `elem integralTypes`, and `amount` (`:445-446`) uses `maybe SmallShift … (widthOf t)`.
- `harness/Fuzz.idr`:
  - `Kind` and `kind` (`:91-110`) add 4 constructors and 13 arms;
  - `IntLit`'s `{auto 0 isInt : IsInteger t}` (`:78`);
  - `Range = Fixed Width | Unbounded` with `rangeOf` (`:539-544`) re-derives the integer split a third time;
  - `integerLiteral` (`:257-259`) and `codePoint.holds` (`:301-303`) each `case bounds t`;
  - `sameIndex` (`:114-127`) has 13 clauses.
- `harness/Sem.idr`: `Fixed` (`:33-38`) stores `lo`/`hi`, which `width` already determines. `fixed` (`:41-42`) discards with `toList (widthOf t)` and `toList (bounds t)`, and `int = fromJust (widthOf TInt)` (`:49-50`).
- `harness/TwoLevels.idr:59-60` repeats the same comprehension.

**Counterexample.** `widthOf TString` is expressible and returns `Nothing`, which every caller must handle. `MkFixed TInt8 (MkWidth 8 True) 0 0` is a `Fixed` whose bounds contradict its width.

**Root cause.** The fixed-width/Integer/other split is a property of the type, held outside it.

**Correction.** `data Ty = TInt IntTy | TDouble | TChar | TString`, `data IntTy = Fixed FixedTy | Big`, and `data FixedTy = Int | Int8 | … | Bits64` (9). `width : FixedTy -> Width` and `bounds : FixedTy -> (Integer, Integer)` are total. `IntLit : (i : IntTy) -> Integer -> Expr (TInt i)`. The order lists (`integralTypes`, `numTypes`, `primTypes`) stay, in Idris's order. The flat `Ty` was lane N's fixed contract (0002 `parts/lanes/N.md:114-138`), not an owner decision against this lens.

**Deletion.** `IsInteger`, `Kind`, `kind`, `Range`, `rangeOf`; `widthOf`'s and `bounds`' `Nothing`s; both `case bounds`; Sem's `lo`/`hi`, both `toList` comprehensions and the `fromJust`; the `elem integralTypes` tests. `sameIndex` drops from 13 clauses to 9.

**Consumers.** `tests/{Prims,Fuzz,Sem,TwoLevels}.idr`.

**Discriminator.** `runtests --fuzz-program two-hosts` text byte-identical before and after (names print through `tyName`). `widthOf TString` no longer typechecks.

**Verification here.** The runner builds and runs on Chez. Diff `--fuzz-program two-hosts`, `--sem-program <each>` and `--two-levels-program * *` before and after.

**Size and risk.** About 40 arms. Low risk.

**Insight.** 4.

## idris-frontend-5: `RigCount` has five classifiers and ~40 Boolean tests, and `quantityOf 0 = Many`

**Evidence.**
- `Resolve.idr:170-171`: `quantityOf rig = if isLinear rig then One else Many`. Its domain admits 0, which silently becomes `Many`; the doc comment asks every caller to test `isErased` first.
- The other classifiers of the same three-way fact:
  - `Resolve.idr:202-203` `shapeOf.multiplicity`: `if isErased … M0 else if isLinear … M1 else Mw`;
  - `Keys.idr` around 343 `quantityPrefix`, which repeats the fork's own `Algebra.showCount`;
  - `Keys.idr` around 474 `quantity : RigCount -> Fin 3`;
  - `Growth/Sites.idr` around 817 `byQuantity`.
- About 40 `isErased`/`isLinear` tests across `Translate/*` and `Growth/*`, typically `if isErased rig then A else … quantityOf rig …` (for example `Terms.letIn`, `Types.coreBinderIn`).
- Eight call sites pass a constant: `quantityOf linear` and `quantityOf top`.
- `ZeroOneOmega`'s constructors are not exported. The fork provides the total eliminator `elimSemi` (`compiler/idris/src/Algebra/Semiring.idr:30`), which nothing in `IdrisMLIR` uses.

**Counterexample.** `quantityOf erased` returns `Many`: a binder of quantity 0 typed as an unrestricted runtime value if a caller forgets the guard.

**Root cause.** No view of a rig. Boolean blindness: the `else` branch does not carry the quantity it established.

**Correction.** In `Resolve`: `data Use = Erased | Used Quantity` and `use : RigCount -> Use = elimSemi Erased (Used One) (const (Used Many))`. `multiplicity : Use -> Multiplicity` is the registry's. Sites match on `use rig`. Constants are written `One` and `Many`.

**Deletion.** `quantityOf` and its trap; `shapeOf.multiplicity`, `Keys.quantityPrefix` (use `showCount`), `Keys.quantity` and `Sites.byQuantity` become functions of `Use`; the Boolean tests become matches.

**Consumers.** `Frontend/Resolve.idr`, `Translate/{Types,Terms,Instances,Programs,Keys,Cases,Closed}.idr`, `Growth/{Sites,Fields}.idr`.

**Discriminator.** `quantityOf` no longer exists, so a quantity cannot be produced for a 0 binder. The Core of every fixture is byte-identical.

**Verification here.** Frontend on Chez: Core diffs on `tests/programs/linear/*`.

**Size and risk.** Five classifiers become one. About 40 tests carry their evidence. Low risk, wide write set.

**Insight.** 6 (decide, don't test), 5.

## idris-frontend-6: a definition's place is resolved two or three times per site, and `enter`'s `Nothing` means two things

**Evidence.**
- `Walk.idr:94-99`: `enter gam n w` does `getNameID n gam`, then `pathOf d i` (`:87-89`, `Maybe` for negative or too-deep places), then `enterAt`. `Nothing` means either "entered already" or "no place".
- `Walked` stores a `depth` (`:39-42`), but only 63 is ever built (`start`, `:51-52`).
- Sites that resolve the same name again just before (`definitionAddress` = `addressOf <$> getNameID`), each with its own `Nothing` arm:
  - `Profile.idr` around 417/418/434, three lookups: `lookupCtxtExact`, `definitionAddress`, `enter`;
  - `Growth/Graph.idr` around 187/191/194, three lookups;
  - `Keys.idr` around 200/204 and 225/229;
  - `Recursion.idr` around 97/101 and 141/144. The `enter … start` at 144 cannot fail once the address was found, so its `Nothing => pure ()` is dead;
  - `Closed.idr` around 836/843, 836/870 and 1471/1553 (`getNameID`, then `enter … (Resolved i)`, which resolves again).
- The fork's `lookupCtxtExactI : Name -> Context -> Core (Maybe (Int, GlobalDef))` (`Core/Context.idr:188`) returns the index and the definition in one lookup.

**Counterexample.** A "no place" branch after an address was found. A depth other than 63 is constructible.

**Root cause.** No resolved-definition handle. The place is an `Int` re-looked-up from a `Name` for each use.

**Correction.**
- `record Place` (the non-negative context index and its `Vect 63 Bool` path, computed once).
- `resolve : Name -> Core (Maybe (Place, GlobalDef))` over `lookupCtxtExactI`, the one boundary.
- `addressOf : Place -> Address` and `enter : Place -> (w : Walked) -> Maybe (Subset …)` are total except for "entered already".
- `Walked` is `Seen 63`, with no depth field.

**Deletion.** `pathOf` and its two `Nothing`s; `depth`; the second (and third) lookup and its `Nothing` arm at each site above; `Recursion`'s dead arm.

**Consumers.** `Frontend/Walk.idr`, `Translate/State.idr` (`addressOf`, `definitionAddress`), `Frontend/Profile.idr`, `Growth/Graph.idr`, `Translate/{Keys,Recursion,Closed}.idr`.

**Discriminator.** The paired-lookup sites no longer typecheck with a second lookup (`enter` takes a `Place`). Behaviour is identical (Core diffs empty).

**Verification here.** Frontend on Chez: typecheck, plus Core of the whole of `tests/programs` byte-identical.

**Size and risk.** About 12 branches. Low risk. Essential and kept: a reference with no definition (every probe sentinel, finding 11) has no place.

**Insight.** 6, 8.

## idris-frontend-7: `TwoLevels` spells `Prims` again as strings, so "every primitive" is a comment

**Evidence.** `harness/TwoLevels.idr`:
- `Term.ty : String` (`:43-47`);
- `intTys = map tyName fixedTys` (`:55-56`);
- `prim op t = "prim__" ++ op ++ "_" ++ t` (`:72-73`) restates `Prims.named`;
- the op lists are literals: `["add","sub","mul","and","or","xor"]` (`:86`), `["div","mod"]` (`:88`) and `["lt",…]` (`:91`, `:125`, `:142`, `:160`, `:175`);
- `printer` (`:250-253`) matches the strings `"String"`/`"Char"`, a second copy of `Fuzz.printer` (`:524-528`, on `Ty`);
- `preludeTerms`' `hostTerm "exp: libm"` restates `Prims.hostOf`.
- The header (`:3`) says "over every primitive". Counted against `Prims.prims` (353): no `shl`/`shr` (20), no fixed or Integer `negate` (10), no `Char`→fixed-except-Int (9), no fixed-except-Int→`Char` (9), no `String`→fixed-except-Int (8). About 56 are absent.

**Counterexample.** A primitive added to `Prims.prims` is never compared by two-levels. Renaming an op spelling in `Prims` leaves `TwoLevels` silently out of sync.

**Root cause.** The corpus is hand-picked text beside the typed table, not derived from it.

**Correction.**
- The primitive corpus is `[ term p (edgeArgs a) | p <- prims, a <- argumentSets p ]`, where `argumentSets : Prim -> List (Args p.args)` draws each argument from a total `edges : (t : Ty) -> Domain -> List (Expr t)`.
- Names come from `p.name`, host dependence from `hostOf p.op`, types from `Ty`, and printing from one `Prims.printer : Ty -> String -> String`.
- `preludeTerms` keep their text but hold a `Ty`.

**Deletion.** `prim`, `intTys`, the op-string lists, `TwoLevels.printer`'s string arms, `Fuzz.printer` (moved to `Prims`), `Term.ty : String`.

**Consumers.** `tests/{TwoLevels,Prims,Fuzz}.idr`, `tests/two-levels/terms/expected-primitives`.

**Discriminator.** A check, run by both hosts as Gen's are: every `p <- prims` appears in the corpus. It fails today on `prim__shl_Int`.

**Verification here.** The runner on Chez: `--two-levels-program primitives terms` lists all 353. The values need the owner's build.

**Size and risk.** About 10 string arms removed, 56 primitives added. Low risk. Expected-file regeneration is reviewed.

**Insight.** 14 (the table drives the code).

## idris-frontend-8: a test case's identity is its position

**Evidence.**
- `TwoLevels.mainModule` prints `t<n> <value>` (`:295-296`), and the expected files are keyed by `n`: `tests/two-levels/terms/expected-primitives` (653 lines) and `expected-prelude` (46). The header (`:29-31`): "A change to the terms, or to their order, changes the expected files, which are then written again from the program's output". `harness/lib/two-levels.sh:40-52` compares line by line.
- `Sem.tests` names chunks `prim-<type>-<table>-<part>` with `part` the chunk's position (`:140-145`), sized by `maxCases = 120` (`:45-46`). The 72 directory names under `tests/programs/semantics/` are those positions.

**Counterexample.**
- One term inserted early in `intTerms` renumbers about 650 expected lines. The diff then hides which value changed, and the whole file is re-snapshotted from output: the unreviewed-snapshot pattern 0002 F16 deleted elsewhere.
- One more edge value in `Sem.values` shifts chunk boundaries: names change and directories go stale.

**Root cause.** Identity by position, not by content.

**Correction.**
- A two-levels line is keyed by the term's text, which is unique: `<term text> = <value>`. The comparison is a map, reporting a missing, extra or changed term by its text.
- A semantics case is keyed by `(type, table, op)` (each ≤ 36 cases, so no chunking): `prim-int8-compare-lt`.

**Deletion.** `t<n>` numbering; `maxCases`/`chunks`; part numbers.

**Consumers.** `tests/{TwoLevels,Sem}.idr`, `harness/lib/two-levels.sh`, both expected files, `tests/programs/semantics/*` (see finding 9).

**Discriminator.** Inserting one term changes exactly one expected line. Adding a value to `Sem.values` changes no test name.

**Verification here.** Runner on Chez: generated programs and names diffed. Values need the owner's build.

**Size and risk.** Low risk. A one-time re-key of 699 lines, by mechanical transformation of the current files (no value changes).

**Insight.** 11, 12.

## idris-frontend-9: the semantics tests are held twice, as `Sem.tests` and as 72 identical directories

**Evidence.**
- `tests/programs/semantics/prim-*`: 72 directories whose `run` scripts are identical except for the name, and whose `expected` files are identical (measured: one md5 each).
- `tests/programs/semantics/sem-index/run` exists only to check that the two copies agree.
- `Main.idr` pools tests by directory (`:107-114`). `harness/one.sh` runs `cd "$test" && sh ./run`, so a test can only be a directory.

**Counterexample.** A chunk the table makes but no directory holds goes unrun until sem-index fails. 72 universal-line edits for one harness change.

**Root cause.** The runner has no parameterized test. A brittle test means a missing test API.

**Correction.**
- A pool entry may be `<dir>@<parameter>`. `one.sh` runs `<dir>/run` with the parameter, and `<dir>/expected` is the one expectation.
- `Main.pool` for `programs/semantics/prim` expands to one entry per `Sem.names` (computed in the runner itself).
- `sem_case` takes the parameter.

**Deletion.** 71 directories (142 files), `sem-index`.

**Consumers.** `tests/{Main,Runner}.idr`, `harness/one.sh`, `harness/lib/e2e.sh` (`sem_case`), `tests/programs/semantics/`, `tests/ACCEPTANCE.md`.

**Discriminator.** `make test` lists exactly `Sem.names` as semantics tests. A new table entry runs with no new file.

**Verification here.** Runner on Chez with `--only` listing; the tests themselves need the owner's build.

**Size and risk.** -144 files. Medium risk: a runner change that every suite passes through.

**Insight.** 14.

## idris-frontend-10: generator facts pass to shell through labels and comments that shell re-parses

**Evidence.**
- Fuzz writes its facts into program text:
  - the case's mode and host dependence go into a label grammar (`d|j|r|s`, an optional `L`, the number; `Fuzz.write` `:616`, `:629-637`);
  - the tape's overrun goes into a comment, `-- overran: case n` (`programText` `:691`);
  - models go into `m<n> <v>` lines.
- `harness/lib/fuzz.sh:59-62` finds the overrun with `head -n 1 | case '-- overran'*`. `fuzz_compare` (`:99-139`) re-parses the label grammar in awk (`$1 ~ /^[djrs]L?[0-9]+$/`, `sub(/^[djrs]L?/…)`) to rebuild facts Idris already held.
- `TwoLevels.termsModule` writes host dependence as `-- host-dependent: t<n> <reason>` (`:264`). `two-levels.sh:32-44` reads it back with `sed` and filters with `awk`.

**Counterexample.** A label printed as `dL3` against awk's `[djrs]L?` would drop a case's comparison silently. A generated program whose first line is not the overrun comment (any header change) hides an overrun.

**Root cause.** The checker lives apart from the generator, so the generator's in-memory facts are serialized as ad hoc text. This goes against the owner's Idris-first rule for oracles.

**Correction.**
- Runner subcommands: `--fuzz-check <seed> <cases> <part> <stdout-file>` and `--two-levels-check <corpus> <stdout-file> <expected-file>`. Each regenerates its cases deterministically, reads the program's output keyed by its own printer's inverse, and prints the property lines and the first failing case.
- Shell compiles, runs and calls the checker. `fuzz_shrink` stays in shell, since it runs the compiler.

**Deletion.** The overrun comment and its `head -n 1` test; the `L` prefix; `fuzz_compare`'s awk; `two_levels`' `sed`/`awk` and the host comment.

**Consumers.** `tests/{Fuzz,TwoLevels,Main}.idr`, `harness/lib/{fuzz,two-levels}.sh`, `tests/fuzz/*/expected` (lines unchanged), `tests/two-levels/terms/expected`.

**Discriminator.** A checker unit (both hosts, as Gen's checks): an output with one disagreeing line names that case. Changing the generated header leaves overrun detection intact.

**Verification here.** The runner on Chez can check a hand-written stdout file against generated cases. Real program outputs need the owner's build.

**Size and risk.** About 55 lines of awk/sed removed, about 60 lines of Idris added. Medium risk.

**Insight.** 6, 14.

## idris-frontend-11: probe sentinels are spelled as string literals in six files, and one spelling is shared by two families

**Evidence.** 18 `MN "idris-mlir-…"` literals:
- `Shapes.idr:72,75,116,117,120,121`: form, axis, axis-at, size;
- `Closed.idr`: hole (around 227/230), unknown (1083 and its recognizer), runtime (1342/1345);
- `Types.idr` around 66/71: binder;
- `Terms.idr` around 233: hole-found;
- `Growth/Fields.idr:33,36`: field;
- `Growth/Sites.idr` around 240 `runtimeAt p = MN "idris-mlir-runtime" p` (Bound, indexed) — the spelling of `Closed.runtimeVariable` (Func, 0), whose `isRuntimeVariable` matches any index.

**Counterexample.** A typo in a recognizer's string literal never matches, and no coverage check catches it. Two families (Sites' indexed runtime stand-ins and Closed's one runtime variable) cannot be told apart.

**Root cause.** The probe kind is a string tag inside Idris's `Name`, written at every builder and recognizer.

**Correction.** One module: `data Probe = Binder Nat | Field Nat | Hole Nat | HoleFound Nat | Unknown | Runtime | RuntimeAt Nat | Form | Axis Nat Nat | Size Nat`. `probeName : Probe -> Name` is the only place spelling the strings; `probeOf : Name -> Maybe Probe` is its inverse; `probeTerm`/`probeOfTerm` cover the two-reference `Axis`. The sentinel mechanism itself stays (Insight 8, a good one).

**Deletion.** 18 literals become constructor matches. Sites' and Closed's collision becomes two constructors.

**Consumers.** `Translate/{Shapes,Closed,Types,Terms}.idr`, `Growth/{Fields,Sites}.idr`.

**Discriminator.** `probeOf (probeName p) = Just p` for every constructor, stated as a check. A recognizer that matches the wrong family fails coverage.

**Verification here.** Frontend on Chez: Core byte-identical (names unchanged).

**Size and risk.** Low risk.

**Insight.** 8, 7.

## idris-frontend-12: a dictionary field has two keys, converted by a lookup by printed symbol

**Evidence.**
- `Dictionaries.idr:141-171` keys fields by `(ConId, Nat)`, the `Nat` being the position among the constructor's arguments. `TS.dicts`/`assumed` use the same key (`State.idr`).
- `Finite.idr` `DictField = (Link Form, Nat, Nat)` (around 82). `fieldIn` (around 312-322) converts through `lookup cid.dataId.name st.symbols`, with `internal … "belongs to an instance with no link"` on a miss.
- The position is re-derived at `Cases.dictPositions` (around 60) and in `Terms.idr` (around 1207-1221, `zip [0 ..] (zip info.args kinds)`).
- Also in `Dictionaries`:
  - `chooser` (`:61-73`) returns `Maybe (Name, FC)`, and `recordDictionary` reads it twice (`:146-147`);
  - `con = maybe (show cid) … (lookup cid st.cons)` (`:152`) re-looks-up the layout the caller held.

**Counterexample.** A `DataId` whose printed symbol is missing from `symbols` is an internal error in Finite. The field's identity is held in two forms that must agree.

**Root cause.** The data instance's link is not part of the dictionary field's key.

**Correction.**
- `TS.dicts`/`assumed` keyed by Finite's `DictField` (link, constructor index, argument index), built where the constructor's layout is known.
- `recordDictionary` takes the `ConLayout` (for the name) and a resolved `chooser : … -> Core (Shown, FC)` that falls back to the owner itself.

**Deletion.** `fieldIn`'s symbol lookup and internal error; the `Maybe` on `con`; `chooser`'s double `maybe`.

**Consumers.** `Translate/{Dictionaries,State,Cases,Terms}.idr`, `Frontend/Finite.idr`.

**Discriminator.** `fieldIn` is total (no internal error). Dictionary refusals (`tests/reject/dictionary-field-*`) print the same text.

**Verification here.** Frontend on Chez on the two reject fixtures and `tests/programs/interfaces/*`.

**Size and risk.** About 4 branches. Low risk.

**Insight.** 6.

## idris-frontend-13: `Loc` uses `""` for "no file" and "no module"

**Evidence.**
- `Errors.idr:80` writes `fromMaybe "" <$> moduleSource …`; `:91` writes `shown ""` for a package file; `:92` returns `noLoc`.
- `Loc.idr:28-29` defines `noLoc = MkLoc Generated (shown "") "" 0 0 0 0`.
- Readers test the sentinel: `Loc.idr:34` `if l.file == "" then show l.place`, and `MLIR.idr` around 254 and 274 `l.file == ""`.

**Counterexample.** A module whose resolved source path is empty is printed as unknown. `noLoc` and a real location at 0:0 of a file named `""` are indistinguishable.

**Root cause.** Absence encoded as an empty string.

**Correction.** `data Source = Unknown | InModule Shown (Maybe String) | InPackage String`, held in `Loc` with the span. Printers and `MLIR.location` match on it.

**Deletion.** Three `== ""` tests, the `fromMaybe ""`, and `shown ""`.

**Consumers.** `Translate/Errors.idr`, `IdrisMLIR/{Loc,MLIR,SyntaxSamples}.idr`, `Translate/{Terms,Programs}.idr` (`noLoc`).

**Discriminator.** The emitted MLIR locations are byte-identical (`tests/compiler` location units).

**Verification here.** Frontend on Chez: Core and module text diffs.

**Size and risk.** Low risk. The files cross into the emit area.

**Insight.** 5, 8.

## idris-frontend-14: shape terms are recognised by hand three times, and `arrayShape`'s pair is never read

**Evidence.**
- `Shapes.idr` `shapeSpine` (`:42-45`), `shapeForm` (`:50-54`) and `axes` (`:126-132`) each match `Ref _ (DataCon 0 _)` / `Ref _ (DataCon 1 _)`. `axes` calls `shapeSpine rest` at every level (quadratic) with `maybe 0 length`.
- `arrayShape` (`:63-66`), `dimensionSources` (`:138-143`) and `formNeeded.inShape` (`:88-91`) each re-recognise "a value array applied to a shape and an element".
- All three callers of `arrayShape` discard its pair (`Just _ <-`: `Cases.idr` around 518, `Terms.idr` around 1040 and 1197).

**Counterexample.** A fix to the tag test in one recogniser is missed in the other two.

**Root cause.** No view over a shape term or over an array type.

**Correction.**
- `data ShapeView = SLin ClosedTerm | SSnoc ClosedTerm ClosedTerm ClosedTerm` with `shapeView : ClosedTerm -> Maybe ShapeView`.
- `arrayView : ClosedTerm -> Core (Maybe (ClosedTerm, ClosedTerm))`.
- `shapeSpine`, `shapeForm` and `axes` are folds over `shapeView`, with axes numbered by an accumulator. `dimensionSources`, `formNeeded` and the three callers use `arrayView`.

**Deletion.** Two recognisers of each; `axes`' per-level spine and `maybe 0`.

**Consumers.** `Translate/Shapes.idr`, `Translate/{Cases,Terms}.idr`.

**Discriminator.** Core of `tests/programs/arrays/*` byte-identical.

**Verification here.** Frontend on Chez.

**Size and risk.** About 8 arms. Low risk.

**Insight.** 7.

## idris-frontend-15: Gen and Prims have dead arms that a measure or evidence would rule out

**Evidence.**
- `harness/Gen.idr:196-198`: `swarm`'s `No _ => w`, with the comment "`No` cannot happen", because `weighted` (`:182-183`) forgets that the option it picked has positive weight.
- Structural bounds whose zero arm is argued dead in comments:
  - `shrink.go Z u = u` (`:356-362`);
  - `spans.go Z _ acc` (`:330-332`);
  - `Prims.bitLength.halvings Z _ = 0` (`:198-203`).

**Counterexample.** None at run time. Each arm is a guard whose impossibility is a comment.

**Root cause.** The evidence (`IsSucc (index i ws)`; a strictly decreasing measure) is computed and dropped.

**Correction.**
- `weighted : (w : Weights n) -> Gen (i : Fin n ** IsSucc (index i (ws w)))`, with a lemma that `zeroed` keeps `weightSum` positive.
- `shrink` recurses on `SizeAccessible` of `length + sum`, with `candidates` returning each candidate with its erased `LT` proof.
- `spans` and `bitLength` recurse on `Accessible` of their argument.

**Deletion.** Four dead arms.

**Consumers.** `tests/{Gen,Prims}.idr`.

**Discriminator.** Gen's checks unchanged on both hosts (two-hosts text identical).

**Verification here.** Runner on Chez.

**Size and risk.** Low risk. The proofs are erased, so there is no run-time cost in the subset.

**Insight.** 6.

## idris-frontend-16: Lock validates, and silently skips entries that are not objects

**Evidence.** `harness/Lock.idr`:
- `problems` (`:30-35`) and `accepted` (`:38-42`) re-read fields with `text key entry`, each returning `Maybe`.
- `objects` (`:45-48`) drops any entry that is not an object.

**Counterexample.** `"cmake": "3.31"` written as a string is not reported. The spec still prints "every tool is pinned".

**Root cause.** The check validates instead of parsing.

**Correction.** `record Pin { revision : String; repository, version : String; ref : Either Tag Describe; accept : Maybe String }` and `pin : (String, JSON) -> Either (List String) Pin`, applied to every key but `schema_version`. `accepted : Pin -> Bool`.

**Deletion.** `objects`' silent skip; the per-check re-reads.

**Consumers.** `harness/Lock.idr`, `tests/lock`.

**Discriminator.** A non-object tool entry is reported by name.

**Verification here.** Runner on Chez: `runtests --lock`.

**Size and risk.** Low risk.

**Insight.** 6.

## idris-frontend-17: Fuzz literal pools hold source text and parse it back

**Evidence.** `harness/Fuzz.idr`:
- Char and String literals are held as source (`CharLit`/`StringLit`, `:80-84`). `unescaped` (`:338-345`) parses the escapes back, and depends on the comment "no pool puts a digit after an escape" (`:336-337`).
- `unparenthesized` (`:452-455`) strips parentheses that `doubleLiteral` added.
- `Leaf` holds both `source` and `input` (`:445-449`).
- `roomOf` (`:348-350`) parses to count characters.

**Counterexample.** A pool entry like `"\\233"` followed by a digit is misread.

**Root cause.** The pool's representation is the printed form.

**Correction.**
- Char and String pools hold values, and their source is `show v`, which prints `\233`-style escapes on both hosts. `two-hosts` already holds the hosts to byte-identical text.
- Double pools hold the unparenthesized source, parenthesized when rendered, as `integerText` does for integers.

**Deletion.** `unescaped`, `unparenthesized`, `Leaf.input` (it becomes the value).

**Consumers.** `harness/Fuzz.idr`, and `harness/TwoLevels.idr`'s literal lists if finding 7 shares the pools.

**Discriminator.** `two-hosts` text identical.

**Verification here.** Runner on Chez.

**Size and risk.** Low risk.

**Insight.** 6.

## idris-frontend-18: `IndexInto Nat` points at another argument by position

**Evidence.**
- `Prims.Domain`'s `IndexInto Nat` (`:219`), used once: `StrIndex`, `IndexInto 0` (`:478`).
- `Fuzz.roomAt` (`:246-249`) has a default 0 for a miss.
- `integerLiteral` (`:254-255`) relies on "the argument indexed is a string of the NonEmpty pool" and uses `S (pred …)`.
- `arguments` threads `rooms ++ [roomOf e]` (`:391-398`).

**Counterexample.** `IndexInto 1` on a primitive whose second argument is not a NonEmpty string draws from 0 rooms. The `pred` trick then yields index 0 into an empty string, a crash case outside the domain.

**Root cause.** A reference to an earlier argument by bare position, matched against a parallel list.

**Correction.** `IndexInto : Elem (TString, NonEmpty) before -> Domain` inside the indexed `Args`, so the generator reads the indexed argument's expression directly.

**Deletion.** `roomAt` and its default; the `rooms` threading; the `pred` trick.

**Consumers.** `tests/{Prims,Fuzz}.idr`.

**Discriminator.** `IndexInto` at a non-string position no longer typechecks.

**Verification here.** Runner on Chez (`two-hosts`).

**Size and risk.** Low risk.

**Insight.** 11, 6.

---

## Judged essential and kept

- `Errors.noting`'s fail-soft recording: every independent refusal is reported, a requirement of the problem. So is the refusal/internal split (`Driver.statusOfAll`).
- `Dictionaries`' demand-driven passes with `assumed` and restart: a match can come before any construction site, which is a property of demand-driven translation. `dictionaryOf`'s `Nothing` (never built) is an essential case.
- `Dictionaries.opaqueFor` and its prose: an explanation for a human.
- `Given`'s `size` beside `values`: both are indexed by `vars`, so they cannot disagree; `substs` needs the size.
- `Walk.Seen`'s non-canonical empty (`None` against `Split None None`): no branch depends on it.
- `Resolve.homeOf`'s parsing of package directories: Idris gives only a file path, and this is the one boundary that parses it.
- `Resolve.validate`'s per-entry checks: the registry's representation, checked once before use (only its result type is in finding 1).
- `Primitives.opOrder`'s permutation: Idris's argument order against the op's.
- The probe sentinel itself (a reference to a definition that does not exist, at which reduction stops): a good sentinel. Only its spelling is finding 11.
- `mlir-array`: shapes, extents, bounds and counts are in types, with run-time checks only at boundaries (`checkIndex`, `!?`, `push`/`reserve`'s capacity tests). The internal errors in `Terms` for a generating function's unexpected type follow from the representation wave's decision R14 (the declaration's type is the one source).
- `Linear.Vec`: capacity held only in the linear array's extent; the fill value in unused slots.
- `Linear.String.Iterator`: the offset is abstract (only `withString`/`uncons` make one), and `uncons`'s end test is essential. One remark: `uncons` steps by offset from the start, while `foldl`/`unpack` step by bytes left. One step function over bytes left would share the walk. That is a small duplication, not a defect of state.
- `Gen.Slots` uses one constructor for written and blank cells (`bound = 0` while unwritten). A draw rebuilds the cell it took apart, which is what lets idris-mlir reuse it in place; two types would forbid that.
- `Gen.exhaustive`'s `limit`: a real budget, reported in `whole`.
- Gen's erased `Refl` proofs beside its run-time `checks`: they check two different evaluators (the elaborator, and compiled code on each host).
- `Prims.Op` kept apart from `PrimFn` (0002 §9, deliberate). `opIndex`/`tyIndex`, an index as identity with `Eq` derived once (no deriving in the subset).
- `Fuzz.familyIndex : Family -> Fin 9`: the type catches a new family.
- `Fuzz.node`'s `weightsOf … Nothing => leaf t`: a type with no production of weight in a case is a real case.
- `Main.suites`' list of pools: every test directory is pooled (checked; `templates` and `upstream-idris` are run elsewhere).
