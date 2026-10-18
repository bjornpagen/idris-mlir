<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Representation survey: idris-emit

Area: the Idris side outside the frontend, `compiler/src/IdrisMLIR/`:
`Emit.idr`, `Emit/`, `Dialect/`, `Encoding/`, `MLIR.idr`, `MLIR/`, `Syntax/`,
`Registry.idr`, `Registry/`, `Term.idr`, `Types.idr`, `Ids.idr`, `Loc.idr`,
`Facts.idr`, `SyntaxSamples.idr`. Read whole, with the frontend sites that
build what Emit consumes (`Frontend/Translate/{Terms,Cases,Primitives,Types,Errors}.idr`),
the generator (`foreign/idr/tools/idris-mlir-tblgen.cpp`) and the C++ readers
of what Emit writes (`lib/IR/Bytecode.cpp`, `lib/IR/DataBody.cpp`,
`IdrMatchOps.td`). Nothing was built or run.

## The area as it stands

`Dialect/`, `Syntax/` and `Encoding/` are generated from ODS and hold no
hand-written fact, which is the earlier waves' work (D9, D10, D16, D20).
What is left is at the seam between Core (`Term`, `Types`) and the generated
builders. Core refers to what Emit must know by key: a constructor or an
`IORes` by `ConId`/`DataId`, a primitive by a bare tag, the dialect's
primitives by one untyped builder (`primOp : IdrPrim -> List Value -> List
MlirType -> Op`), and the operands of an array operation, a primitive or a
reduction as a flat `List`. So Emit looks each one up again, counts its
arguments again, reads the result types again from hand tables (`resultOf`,
the unit heuristic in `effect`), and finds guards by matching the built op's
name string. Emit has 47 `internal`/`Left` exits. About 35 of them, and a
handful of silent fallbacks (`fromMaybe`, `_ => False`, `zip` that
truncates), guard states that a refined Core would make impossible. The
frontend often had the fact in hand and threw it away: `PrimFn k`'s arity,
`onlyCon`'s constructor, a dead arm it had proved impossible, the source
file's `Maybe`. The rest of the area is sound. `MLIR.idr`'s model, the
bytecode writer and the registry tables are good representations; they hold
a few sentinels (`file == ""`, `"-"`) and one dead field.

## Findings, ranked (branches removed against risk)

Verification note for every finding: on this machine, the frontend can be
built by the stock host (Chez) and run over `tests/programs/**` and
`tests/accept/**` to write `.mlirbc` and `.core`. For a refactor that keeps
behaviour, the check is byte-identical `.mlirbc` before and after; `.core`
too, unless the finding says the dump changes. No MLIR tool runs here, so
the generated C++ side of a finding compiles under `make typecheck` and
nothing reads the bytecode.

### idris-emit-1: a constructor is referenced by id, so Emit resolves it and counts its fields again

| Field | Content |
|---|---|
| Evidence | `Term.idr:98` `ConApp : Loc -> ConId -> List (Term n)`; `:158` `MkAlt : ConId -> Vect k (Shown, Binder) -> …`; `:93` `Effect … -> DataId`; `:141` `TabulateIO … (step, done : DataId)`; `Emit/Monad.idr:92` `Taken ConId (List Val)`. Emit re-resolves each one: `Emit/Bodies.idr:326-327` (ConApp lookup, internal), `:328` `saturated` (internal), `:350-351` (a lookup of the match's data whose result `decl` is never used, a pure validator), `:375-376` (Alt lookup, internal), `:377` `saturated` (internal), `:244-246` and `:262-264` (`plainHeld`/`evaluated`: a miss silently answers `False`); `Emit/Operations.idr:390-391` (`force`, internal), `:401-404` `only` (lookup plus exactly-one, internal), `:436-437` (`[x, _] <- fields`, internal); `Emit/Tensors.idr:454-456` (`only` plus `[elemField, _]`, internal); `Emit/Index.idr:25,81,90` (`cons` table and its `maybe (show c)` fallback); `Term.idr:466-468` (the dump's `cons` map). That is 9 internal errors and 3 silent fallbacks. |
| Counterexample | A `ConApp` whose `ConId` names no declared constructor, or a `ConApp`/`MkAlt` with a different number of arguments than the constructor has fields. Both are representable and reported at Emit as "not declared" or "passes N values; it takes M". An `Effect` whose `DataId` has two constructors, or one whose constructor holds three fields, is also representable. The frontend held the `Con` at every one of these sites: `onlyCon` (`Frontend/Translate/Terms.idr:1411-1419`) resolves the `IORes` constructor and passes on only `res.id`, `doneCon` is resolved at `:1514` and dropped, and `absurd` alternatives are built from `dt.cons` (`Cases.idr:554`). |
| Root cause | A constructor reference does not carry its declaration, and its field count is in no type. The `MkAlt` binders copy `Con.fields`. Both come from `ConInfo`'s `Field _ b _` (`Cases.idr:796`, `Types.idr:858`), so the fact is held twice and compared by `saturated`. |
| Correction | `Con : Nat -> Type`, indexed by its field count (`fields : Vect k Binder`). `Data.cons : List (k ** Con k)`. Every constructor reference holds the declaration: `ConApp : {k : Nat} -> Loc -> Con k -> Vect k (Term n) -> Term n`; `MkAlt : {k : Nat} -> Con k -> Vect k Shown -> Term (Under k n) -> Alt n`, which holds names only because the binders are the constructor's; `Effect … (res : Con 2)`; `TabulateIO … (step, done : Con 2)`; `Taken : Con k -> Vect k Val -> Parts`. `Tabulate` already stores `{k : Nat}` with a `Vect k`, so this stays inside the subset. |
| Deletion | `saturated` for `ConApp` and `MkAlt`; the lookups at Bodies 326, 350, 375 and Operations 390; `only` and its three callers' destructuring (Operations 404, 437; Tensors 456); the `False` fallbacks in `plainHeld` and `evaluated`; `Index.cons` and the `cons` arm of `Index.names`; `Term.sourceNames`' `cons` map; the binder copy in `MkAlt`. `saturated` stays for calls only (see the cross-area note). |
| Consumers | `Term.idr`, `Emit/Bodies.idr`, `Emit/Operations.idr`, `Emit/Tensors.idr`, `Emit/Index.idr`, `Emit/Monad.idr`; `Frontend/Translate/Terms.idr` (`snocValue` :100, `:111`, `pack` :313, `:1223`, `:1488`, `:1503`, `ioCall`/`arrayCall` Effect :1298/:1369, TabulateIO :1525), `Frontend/Translate/Cases.idr` (:554, :793), `Frontend/Translate/Types.idr` (where `Con` is built). |
| Discriminator | A `ConApp` of the wrong arity, or an `Effect` on a type with other than one two-field constructor, no longer typechecks. The `.mlirbc` and `.core` of every program are byte-identical. |
| Verification here | The frontend builds on Chez with `%default total`; byte-identical `.mlirbc` and `.core` over the program corpus. |
| Size and risk | About 60 lines and 12 branches deleted; a mechanical change at roughly 12 frontend sites. Before the change, confirm that `Cases.idr`'s alternative binders equal `Con.fields` for every instance (both are `Field` binders of one `ConInfo`). Where they differ, the difference is itself the bug. Essential and kept: the data table (`Index.table`), which Bytecode writes. |
| Insight | 6 (the frontend parsed the constructor and handed on only its name), 4 |

### idris-emit-2: a primitive application forgets the signature Idris gave it (arity and result type)

| Field | Content |
|---|---|
| Evidence | Idris's `PrimFn : Nat -> Type` carries its arity. `Frontend/Translate/Primitives.idr:93` `primOp : PrimFn k -> Maybe Prim` drops it. `Types.idr:334-350` `Prim` has no arity, and `:425-442` `primArgs` lists operand types with `primArgs (Op _) = []` ("lists none"). `Term.idr:89` `PrimApp : … -> List (Term n)`. Emit then matches by position: `Emit/Operations.idr:298-367`, every clause on `[a, b]`/`[a]`, with the catch-all `:368` (internal) and `mathOp`'s `Maybe` with `:313` (internal); `Bodies.idr:125-131` `operands` consumes the slot list by `head'`/`drop 1`, with an empty list meaning "no expectation". The result type of a dialect primitive is re-derived by a hand table, `Operations.idr:258-291` `resultOf`, 30 clauses, catch-all internal at `:291`, and `BigAdd`/`BigMul` "give what they take". Two dialect primitives are separate `Term` constructors because `resultOf` cannot type them: `SystemOs` (idr.os) and `NewWorld` (idr.world.new), each repeated in `rename`, `TermF`, `hmap`, `para`, the printer, `mostUses` and `alg`. `CrashStr` has a special clause ahead of the generic one (`Bodies.idr:300-305`) because the generic clause assumes a result. The frontend's `opOrder` (`Primitives.idr:116-119`) permutes `[start, len, s]` with a fall-through. |
| Counterexample | `PrimApp (IntOp Add Int) [x]` or `PrimApp (Math Pow) [x]` is representable and reaches the internal "the primitive … with 1 operands". `PrimApp (Op Os) []` is representable and reaches "gives no value of a type of its own". |
| Root cause | `Prim` is not indexed by its arity, and `Op` does not carry the Core result type the frontend knew from Idris's type. |
| Correction | `Prim : Nat -> Type`: `IntOp : ArithOp -> IntTy -> Prim 2`, `Negate : Prim 1`, `Math1 : UnaryMath -> Prim 1`, `Pow : Prim 2`, `Compare … : Prim 2`, `Cast … : Prim 1`, …, and `Op : (p : PurePrim) -> (result : Ty) -> Prim (primArity p)`, with `primArity` generated from the op's ODS operand count (the generator refuses a variadic primitive, as it already refuses a variadic of variadics). `PrimApp : {k : Nat} -> Loc -> Prim k -> Maybe Shown -> Vect k (Term n) -> Term n`; `primOp : PrimFn k -> Maybe (Prim k)`. A registry hook's arity is converted once where the frontend builds the call, against the shape `Resolve` already validated. `prim : Prim k -> Vect k Val -> E Val` is total. `SystemOs` becomes `PrimApp (Op Os StrT) []` and `NewWorld` becomes `PrimApp (Op WorldNew WorldT) []`. A runtime crash message leaves `PrimApp`: `Crash : Loc -> Term n -> Term n`, where Emit writes `idr.crash` for a string literal and `idr.crash_str` otherwise. |
| Deletion | `prim`'s catch-all; `mathOp`'s `Maybe` and its internal; `resultOf` and its catch-all; the `Op _ = []` case of `primArgs`; the empty-slot regime of `operands`; the `CrashStr` clause; the `Term` constructors `SystemOs`/`NewWorld` and their seven appearances each; `opOrder`'s fall-through (a `Vect 3` permutation). |
| Consumers | `Types.idr`, `Term.idr`, `Emit/Bodies.idr`, `Emit/Operations.idr`, `Registry/Entry.idr` (`NatMeaning`'s `Prim`, `PrimCall`), `Registry/Recognized.idr` (`naturals`), `Frontend/Translate/Primitives.idr`, `Frontend/Translate/Terms.idr` (:1157-1181, :1243, :1259, :1269, :364, :1609), `foreign/idr/tools/idris-mlir-tblgen.cpp` (`primArity`), `Dialect/Idr.idr` (regenerated). |
| Discriminator | A primitive applied to the wrong number of arguments, or a dialect primitive without a result type, no longer typechecks. Output is byte-identical apart from the `.core` text of `os`/`new-world`, which print as primitives. |
| Verification here | Chez build, plus the corpus `.mlirbc` compare. The generator change compiles under `make typecheck`, and `Dialect/Idr.idr` regenerates through it. |
| Size and risk | About 70 lines and 8 branches deleted, plus 2 `Term` constructors; medium risk, because every primitive site in the frontend changes. Essential and kept: `Prim` as Core's vocabulary apart from the ops (see "Kept"). |
| Insight | 6 (Idris's index dropped and re-checked), 4 |

### idris-emit-3: whether a primitive performs IO, and which results it gives, are re-derived by hand from Idris's types

| Field | Content |
|---|---|
| Evidence | `Dialect/Idr.idr:1203` generates `primPerformsIO : IdrPrim -> Bool`. `Term.Effect` holds any `IdrPrim`. `Emit/Operations.idr:433-434` guards with "which performs no IO, as an effect" (internal), and the frontend branches on the same Bool (`Terms.idr:1291`). `Operations.idr:439-451` decides the op's results from Idris's `IORes` value type: if it is a unit, the op "gives no result"; `ArrayGet` is the exception "even when the element is a unit". The three-way `gives` and four-way `(p, unit, head' names)` cases follow, with internals at `:449` "without its value" and `:451` "without the next world". `Registry/Entry.idr:231` `IOCall IdrPrim` covers both pure and IO primitives. |
| Counterexample | `Effect` holding `BigAdd` is representable and is refused only at Emit. An IO op whose ODS gives a status word that Idris's type names `()` would be emitted with no value result and would fail the verifier. The ODS states each op's results, and the Idris side guesses them from the unit. |
| Root cause | The dialect's split between pure and IO primitives, and each IO op's result shape, are ODS facts that reach Idris as a Bool and not at all. |
| Correction | The generator emits two sums, `PurePrim` and `IOPrim` (each with `Idr_PerformsIO` deciding membership), in place of `IdrPrim` plus `primPerformsIO`, and `ioResult : IOPrim -> IOResult` with `data IOResult = WorldOnly \| ValueThenWorld`, read from each op's ODS results. `Effect` holds an `IOPrim`, its `IORes` constructor (`Con 2`, idris-emit-1), and for a `WorldOnly` primitive the unit constructor its value is, which the frontend resolves where it resolves the `IORes`. Hooks split as `PureCall PurePrim (List Lit)` and `IOCall IOPrim (List Lit)`; `ArrayCall` and `Exits` hold `IOPrim`; `Builds` holds `PurePrim`. |
| Deletion | The `primPerformsIO` guard; `gives`' unit heuristic and its `ArrayGet` exception; `unitOf`; the four-way result case and its two internals; the frontend's `if primPerformsIO` (it becomes the choice between two hooks). |
| Consumers | `idris-mlir-tblgen.cpp`, `Dialect/Idr.idr` (regenerated), `Types.idr`, `Term.idr`, `Emit/Operations.idr`, `Registry/Entry.idr`, `Registry/Primitives.idr`, `Registry/Recognized.idr`, `Frontend/Translate/Terms.idr` (`ioCall`, `arrayCall`, the hook dispatch at :1598-1605). |
| Discriminator | `Effect` on a pure primitive no longer typechecks. An IO op's result count comes from its ODS, and a sample per `IOResult` case in `SyntaxSamples` round-trips (on the owner's machine). Output is byte-identical. |
| Verification here | `make typecheck` for the generator; Chez build; corpus `.mlirbc` compare. |
| Size and risk | About 40 lines and 8 branches deleted; medium risk (generator, registry and frontend in one change). |
| Insight | 7 (a Bool and a heuristic in place of the ODS's own per-op facts) |

### idris-emit-4: the array language's operands are positional lists

| Field | Content |
|---|---|
| Evidence | `Term.idr:126` `Tensor : TensorOp -> Ty -> List (Term n)`, whose arity per op is written only in comments (`Types.idr:210-233`: "(x :: coords)", "[k, x]", "[lo, hi, v, x]"). `Emit/Tensors.idr:246-385` matches `[x]`, `x :: coords`, `x :: v :: coords`, `[k, x]`, `[x, y]`, `x :: extents`, `[lo, hi, v, x]`, with the catch-all internal at `:384-385`. `Emit/Bodies.idr:506-508` builds `[z, x]` only to match it back, with the internal "a reduction of other than its accumulators and its array". `:500-503` and `:534-537`: `operands` forgets the `Vect k` of extents and `toVect k` re-checks it (internal, twice). `Term.idr:151` `Tie : List (Maybe (Term n))` is "one entry per dimension of its type", yet `Tensors.idr:502` pads it with `replicate` and `zip3` truncates it. `Bodies.idr:519-525` decides exact-extent against natural by inspecting the stated subterm's syntax (`Tensor _ (Extent _) _ _`). |
| Counterexample | `Tensor (Take 0) t [x]` and `Tensor Pad t [v, x]` are representable and are reported at Emit. A `Tie` with more entries than the rank is silently truncated, and one with fewer is padded. A stated dimension that was an extent but is written through a `Let` becomes "a natural" and gets a guarded conversion. |
| Root cause | An operation's operands are not part of the operation's constructor, and `operands` returns a `List` where it was given a `Vect`. |
| Correction | `TensorOp` becomes a `Traversable` container of its operands: `Extent Nat t \| Extract t (List t) \| Insert t t (List t) \| Take Nat t t \| Drop Nat t t \| Concat Nat t t \| Transpose Nat t \| Reshape t (List t) \| Pad Nat t t t t`. `Term`: `Tensor : Loc -> Ty -> TensorOp (Term n) -> Term n`, and `TermF` the same over `f n`. Emit evaluates operands with `traverse`, which keeps the shape. `Tie : Loc -> Term n -> List (Nat, Stated (Term n))` lists the stated axes only, with `data Stated t = SameAs t \| Natural t` given by the frontend (`witnessTerm` knows which it built). A reduction evaluates `z` and `x` as two binds. |
| Deletion | `tensorOp`'s catch-all; the two `toVect` internals; the `[z, x]` round trip and its internal; `tie`'s padding; the syntax test in `stated`; the frontend's generic `operation op` (`Terms.idr:1552`), which becomes a constructor per op. |
| Consumers | `Types.idr`, `Term.idr` (`Tensor`, `TensorF`, `rename`, `para`, `hmap`, printer), `Emit/Bodies.idr`, `Emit/Tensors.idr`, `Frontend/Translate/Terms.idr` (`arrayTerm` :1421-1556), `Frontend/Translate/Shapes.idr` (`witnessTerm` :303), `Frontend/Translate/Programs.idr` (:391). |
| Discriminator | A tensor operation with the wrong operands no longer typechecks. The corpus output is byte-identical except for a program whose stated extent passed through a `let`; the guard it now omits is correct, but confirm each such diff by reading it. |
| Verification here | Chez build; corpus `.mlirbc` compare (array programs under `tests/programs`). |
| Size and risk | About 30 lines and 6 branches deleted; low to medium risk. |
| Insight | 4, 6 |

### idris-emit-5: `Entry.rules` is a field nothing reads, a second copy of the hook's rule

| Field | Content |
|---|---|
| Evidence | `Registry/Entry.idr:459` `rules : List Rule` is set on all of about 150 entries (`Primitives.idr`, `Recognized.idr`) and read nowhere: no `.rules`, and no pattern on `MkEntry` outside construction, in `compiler/src` or `tests`. For the refusing hooks it repeats the hook's payload: `ruledOut … (Forbidden rule) [rule]` (`Recognized.idr:222`), `spelling … (Forbidden EscapeHatch) [EscapeHatch]`, `rootOnly … (Forbidden WorldUse) [WorldUse]`, `(Deprecated r) [Deprecated]`. It is the only place the rules `IOPrimitive` and `IdentityHook` appear (`tests/reject/without-fixture:9-10` says so). |
| Counterexample | `MkEntry k e (Forbidden Threads) [Signal]` is representable and means nothing different. |
| Root cause | A transcription of "the rules the hook's handler implements" with no reader. |
| Correction | Delete the field. Delete the `Rule` cases `IOPrimitive` and `IdentityHook` from ODS (`IdrBase.td`), with their lines in `tests/reject/without-fixture`. This is 0002 §9's deferred item ("a rule with no raise site is a second copy of nothing"). |
| Deletion | About 150 list literals, the field, 2 rule cases (C++ enum, generated Idris, `IdrRules.txt`) and 2 fixture-exemption lines. |
| Consumers | `Registry/Entry.idr`, `Registry/Primitives.idr`, `Registry/Recognized.idr`, `foreign/idr/include/idr/IR/IdrBase.td`, `Syntax/Idr.idr` (regenerated), `tests/reject/without-fixture`. |
| Discriminator | `tests/spec/rules-covered` (every rule has a fixture or an exemption) still holds with two fewer rules. Output is byte-identical. |
| Verification here | Chez build; `make typecheck`; `make check` runs the rules spec. |
| Size and risk | About 160 lines, no branches; no behaviour risk. |
| Insight | 4 (two fields that can disagree, one unread) |

### idris-emit-6: guards are found by the built op's name string and its operand positions, so the word type rides alongside

| Field | Content |
|---|---|
| Evidence | The generated `guardsOf : Op -> List Guard` (`Dialect/Idr.idr:1469-1495`) matches `MkOp "idr.big.div" …` by string, on every op Emit places (`Operations.idr:104,121`), with positions as `Nat`. `Emit/Operations.idr:70-71` `operandAt` (internal "without its operand"), `:58-61` `setAt` (silently does nothing when out of range), `:80-82` `WordSize` read from `types` (internal "at the types"). `types` is `Term.Effect`'s `List Ty` (`Term.idr:93`), threaded through `effect`, `placed`, `guarded` and `resultNames`, and computed by the frontend's `wordOf` (`Terms.idr:1328-1340`, two internals). Emit reads it only for `WordSize`: the `[el]` of the array effects is printed in the dump and nowhere else. D10 named the table `guardsOf : IdrOp -> List Guard`, over a typed op, which was not built. |
| Counterexample | An `Effect BufferLoad [] …` (no word type) is representable and fails at Emit. A guard position past the operands is representable and is silently not substituted by `setAt`. |
| Root cause | A guard is a fact of the builder that made the op, re-derived after the op is erased into `MkOp name operands …`. The word whose size a buffer guard checks is the op's own `value` (its result type for a load, its operand for a store), which the builder has as an `MlirType`. |
| Correction | The generator makes each guarded op's builder, the `primOp` clause of each guarded primitive included, return `Guarded = MkGuarded Op (List Guard)`, its guards stated over the builder's own arguments: the guarded operand's position, which the builder knows, and a `Count` that names the word by its `MlirType` (`WordOf MlirType`) and an operand by its `Value`. `placed` takes an `Op` and `guard : Guarded -> E Op` writes the checks, so a partial op cannot be placed without its guards, as a type fact. Total ops keep returning `Op` and are not inspected. |
| Deletion | The generated string dispatch `guardsOf` and `positions`; `operandAt`'s internal; `WordSize`'s internal and `wordSize`; the `types` parameter of `effect`, `placed`, `guarded` and `resultNames`; `Term.Effect`'s `List Ty` and its printing; the frontend's `wordOf` and its two internals. |
| Consumers | `idris-mlir-tblgen.cpp` (`guardsOf`, `positionOf`, builders), `Dialect/Idr.idr` (regenerated), `Emit/Operations.idr`, `Emit/Bodies.idr`, `Emit/Tensors.idr`, `Term.idr`, `Frontend/Translate/Terms.idr`. |
| Discriminator | Placing a partial op without its guards no longer typechecks. Output is byte-identical; the `.core` loses `io.op<T>` type arguments. |
| Verification here | `make typecheck` (generator); Chez build; corpus compare. |
| Size and risk | About 60 lines and 4 branches deleted, plus a parameter through five functions; medium risk (generator). Essential and kept: guards written by the Idris side (D10), and the check ops themselves. |
| Insight | 7 |

### idris-emit-7: arms Idris proved impossible travel as `Unreachable` subterms, which Emit rediscovers

| Field | Content |
|---|---|
| Evidence | The frontend holds a natural match's arms as `Maybe`s (`Cases.idr:622` `natAlternatives : … (Maybe (Term nv), Maybe (Shown, Term …), Maybe (Term nv))`), writes each dead arm as `Unreachable` (`:636`, `:650`, `:662`), and folds the triple into `CaseNat` with `fromMaybe` (`:609-614`), as it does for constructor alternatives (`:785`) and defaults (`:800`). Emit tests each subterm's syntax (`Bodies.idr:165-168` `excluded`). CaseF filters the alternatives and re-tests the default (`:353-355`). CaseLitF branches on `if excluded def` then `reverse live` (`:396-400`, 3 branches) and then `(cases, final)` (`:401-406`, 3 branches). CaseNatF splits four ways on `(excluded z, excluded s)` (`:418-429`). The module header gives this as the reason the algebra is a paramorphism. |
| Counterexample | `CaseNat x Unreachable p Unreachable`, a match with no possible arm, is representable as a match. A `Case` whose every alternative is `Unreachable` is too. |
| Root cause | The frontend learned that an arm is impossible, in some places already as a `Maybe`, and encoded it as a term, so the absence of an arm is a value that has to be tested. |
| Correction | The frontend omits impossible arms. `Case` keeps only possible alternatives (its default is already a `Maybe`). `CaseLit`'s default becomes `Maybe (Term n)`. `CaseNat` holds `data NatArms n = OnlyZero (Term n) \| OnlySucc Shown (Term (Under 1 n)) \| Both (Term n) Shown (Term (Under 1 n))`, which cannot say "no arm". A match with no possible arm is `Unreachable` itself. |
| Deletion | `excluded`; the filters and default test in CaseF; the `excluded def` branch in CaseLitF (the step where the last alternative stands for a missing default stays, because `idr.match_lit` requires a default, `OpsMatch.cpp:146`); CaseNatF's `(True, True)` case and its Boolean split, which become three constructor cases. |
| Consumers | `Term.idr`, `Emit/Bodies.idr`, `Frontend/Translate/Cases.idr`. |
| Discriminator | Output is byte-identical. A `NatArms` with no arm cannot be built. |
| Verification here | Chez build; corpus compare. |
| Size and risk | About 25 lines and 6 branches deleted; medium risk (`Cases.idr`'s dead-arm logic). |
| Insight | 6, 8 |

### idris-emit-8: an empty file name stands for "no source"

| Field | Content |
|---|---|
| Evidence | `Loc.idr:14-29`: `file : String`, `noLoc = MkLoc Generated (shown "") "" 0 0 0 0`. `Frontend/Translate/Errors.idr:79` `fromMaybe "" <$> moduleSource …` folds the `Maybe` into `""`, which is tested again at `MLIR.idr:254` (`span`), `MLIR.idr:274` (`location`) and `Loc.idr:35` (`Show`). `Frontend/Growth.idr:133` orders `("", line)` pairs. The empty string means two things: generated code with no place, and a library module whose source is not installed (place known, file unknown). |
| Counterexample | A `Loc` with `file = ""` and a real span, and `noLoc`'s span `0:0`, which prints as `:1:1`. |
| Root cause | Absence is a sentinel inside a string, after the `Maybe` that said it was discarded. |
| Correction | `record Loc { origin : Origin; at : Place }` with `data Place = InFile String Span \| InModule Shown Span \| Nowhere` and `record Span` holding the four positions. `toLoc` builds the case it learned. |
| Deletion | Three `file == ""` tests; `noLoc`'s fake zeros; the `fromMaybe ""`. |
| Consumers | `Loc.idr`, `MLIR.idr`, `Frontend/Translate/Errors.idr`, `Frontend/Growth.idr`, `Frontend/Profile.idr` (:152 rebuilds an `FC` from the span), every `MkLoc` site. |
| Discriminator | Output is byte-identical, since locations print as before. A `Loc` with an empty file and a span cannot be made. |
| Verification here | Chez build; corpus compare, `.mlirbc` locations included. |
| Size and risk | About 15 lines and 4 branches; low risk. |
| Insight | 5, 8 |

### idris-emit-9: a data body's kind and its constructors' roles are independent fields (crosses into the C++ dialect)

| Field | Content |
|---|---|
| Evidence | Idris side: `Term.Data.kind : SumKind` and `Term.Con.role : CtorRole`, each set from a separate registry hook (`Types.idr:838` `sumOf`, `:867` `plays`). Base's list therefore takes three entries: `SumOf BaseList` on `List` and `Plays ListNil`/`Plays ListCons` on its constructors (`Recognized.idr:171-177`). The generated `IdrCtor` (`Syntax/Idr.idr:439-457`) holds `role`, `fn : Maybe String` ("only a label names") and `byName : Bool`, which `Emit/Index.idr:74` hard-codes as `False … Nothing`. C++: `DataBody.cpp:32-108` validates the combinations with a `KindRule` table (roles per kind, exactly-once roles with field counts), `fn` exactly when `Label`, `byName` only for a memo label, and the list's cons tail. |
| Counterexample | `SumOf BaseList` on a type whose constructors have no `Plays`, a `Plain` sum with a `ListCons` constructor, or a `Label` without `fn`. Each is representable on both sides and refused by `verifyBody`. |
| Root cause | One fact, the shape of a sum, is spread over a kind field and one role field per constructor, plus two optional fields that only some roles have. |
| Correction | Idris: `Data.shape : DataShape` with `data DataShape = PlainSum (List (k ** Con k)) \| InPlaceSum (List (k ** Con k)) \| BaseListSum (Con 0) (Con 2)`, given by one registry hook `ListType` that names the nil and the cons. The frontend never makes `Closures` or `Memo`. C++ (owner of the other half): `DataType::Body` becomes a variant by kind (plain constructors; a list's nil and cons; labels each with its `fn`; a memo's labels, its running and its forced), and the generated `IdrSum` follows it. |
| Deletion | Idris: `Con.role`, `Hooks.plays`, the `Plays` hook and its two entries, the frontend's role fold, `Index.body`'s hard-coded fields. C++: `KindRule`/`ruleOf`, the role, `fn`, `byName` and once checks in `verifyBody`. |
| Consumers | `Term.idr`, `Emit/Index.idr`, `Registry/Entry.idr`, `Registry/Recognized.idr`, `Frontend/Translate/Types.idr`; `foreign/idr/include/idr/IR/IdrTypes.td`, `lib/IR/DataBody.cpp`, `lib/IR/Bytecode.cpp`, every C++ reader of `Ctor.role` (defunctionalization, memo, list folds), `idris-mlir-tblgen.cpp`. |
| Discriminator | A body whose roles do not fit its kind cannot be built (C++ type); the `verifyBody` fixtures that test those refusals go. Idris output is byte-identical. |
| Verification here | Idris half: Chez build and corpus compare. C++ half: `make typecheck` only. |
| Size and risk | Idris about 20 lines; C++ about 60 lines and 8 checks; medium-high risk on the C++ side. |
| Insight | 4 |

### idris-emit-10: multi-result naming is written three times, and callers take results by list position

| Field | Content |
|---|---|
| Evidence | The `name#i` convention appears in `MLIR.idr:327-331` (`boundNames`), `Operations.idr:105-114` (`placed`, written again), `Closures.idr:70-76` (`numbered`, written again) and `MLIR.idr:391-394` (`named`). `Statement.result : Maybe String` is independent of `op.results` (`MLIR.idr:318-322`). Callers match the returned list by position: `Tensors.idr:467-468` `[arr, w] … \| _ => internal`, `:481-482` `[e, w2] … \| _ => internal`, `Operations.idr:445-451` `head' names`/`last' names` with two internals. |
| Counterexample | `MkStatement (Just r) op` with no results prints as `r = "op"()` in the generic text that a content key hashes, and `MkStatement Nothing op` with results binds nothing. |
| Root cause | The coordinate is "result i of statement r", but each caller rebuilds it as a list and indexes back. |
| Correction | One function, `resultAt : String -> Nat -> String` (`r` for a single result, `r#i` otherwise), used by `boundNames`, `numbered` and the text. `placed` returns the statement's name, and a caller asks for result `i`. `Statement` is made only through `bind : String -> (o : Op) -> {auto 0 _ : NonEmpty o.results} -> Location -> Statement` and `run : Op -> Location -> Statement`. |
| Deletion | `placed`'s three-way case; `numbered`'s copy; the two internals in `Tensors` and the two in `effect`. |
| Consumers | `MLIR.idr`, `MLIR/Bytecode.idr`, `Emit/Operations.idr`, `Emit/Closures.idr`, `Emit/Tensors.idr`, `SyntaxSamples.idr`. |
| Discriminator | Output is byte-identical. A named statement with no results does not typecheck. |
| Verification here | Chez build; corpus compare; `SyntaxSamples` builds and writes the file. |
| Size and risk | About 20 lines and 4 internals; low risk. |
| Insight | 11 |

### idris-emit-11: a value in scope and a value an op uses are one type

| Field | Content |
|---|---|
| Evidence | `Emit/Monad.idr:92-102`: `Val { name; type; use; parts : Parts }` with `Parts = Whole \| Taken ConId (List Val)`. For `Taken`, `name` is "a key no operation defines". `Emit/Types.idr:29-31` `operand` has the internal "taken apart", and it is called monadically at about 60 sites (`!(operand ix v)`). The fold's results are always whole, because `VarF` forces (`Bodies.idr:296`); only the environment holds `Taken`. |
| Counterexample | A `Taken` value passed to `operand`, or its pseudo-name compared in `renamed` as if it were an SSA name. |
| Root cause | One record holds two things: what a variable stands for (a value, or a constructor taken apart), and an SSA value. |
| Correction | `data Held = Whole Val \| Taken (Con k) (Vect k Held) Key` in the environment (`Fin nv -> Held`). Emitters return `Val`, always an SSA value. `force : Held -> E Val`. `operand : Val -> Value` is pure and total. |
| Deletion | `operand`'s internal and its `E` wrapper and `Index` argument at about 60 sites; the double use of `name`. |
| Consumers | `Emit/Monad.idr`, `Emit/Types.idr`, `Emit/Bodies.idr`, `Emit/Operations.idr`, `Emit/Tensors.idr`, `Emit/Declarations.idr`. |
| Discriminator | Output is byte-identical. An op operand of a taken-apart value does not typecheck. |
| Verification here | Chez build; corpus compare. |
| Size and risk | About 60 call sites simplified, 1 internal; low risk. Do it with idris-emit-1 (`Taken` holds `Con k`). |
| Insight | 4 |

### idris-emit-12: `Scalar` admits conversions and comparisons that the frontend never makes

| Field | Content |
|---|---|
| Evidence | `Types.idr:325` `Scalar = SInt IntTy \| SChar \| SDouble`; `Cast Scalar Scalar` admits 9 pairs. The frontend refuses two of them (`Primitives.idr:43-46` `runtimeCast SChar SDouble = Nothing`, and the converse). Emit: `Operations.idr:240-243` `intLike : Scalar -> Maybe (Nat, Bool)`, the `Compare` internal at `:316-319` (unreachable, because `SDouble` is matched first), the identity cases `:326-327`, and `:328-335`'s fall-through internal "a cast from". |
| Counterexample | `Cast SChar SDouble` and `Compare Eq SDouble` taking the integer path. |
| Root cause | "Integral" against "double" is a `Maybe` computed again at each use, and `Cast` is a product where only some pairs exist. |
| Correction | `data Scalar = Integral IntLike \| SDouble` with `data IntLike = SInt IntTy \| SChar` (total `width`/`signed`), and `Cast` as the conversions that exist: `IntToInt IntLike IntLike \| IntToDouble IntTy \| DoubleToInt IntTy`. |
| Deletion | `intLike`; two internals; the identity cases; the frontend's `runtimeCast` refusals (a refusal becomes "no constructor"). |
| Consumers | `Types.idr`, `Emit/Operations.idr`, `Frontend/Translate/Primitives.idr`. |
| Discriminator | Output is byte-identical; `Cast SChar SDouble` cannot be written. |
| Verification here | Chez build; corpus compare. |
| Size and risk | About 15 lines and 4 branches; low risk. |
| Insight | 4 |

### idris-emit-13: Emit re-reads what it built, and searches for the root

| Field | Content |
|---|---|
| Evidence | `Emit.idr:66-67` `find (\f => f.id == src.root)`, with "the root function is missing". `Emit.idr:74-75,85-88` `symbolOf` reads `"sym_name"` back out of each statement it just built and matches `StringAttr` ("a function without its symbol"). `Emit/Declarations.idr:40` `function` returns `List Statement` although `fnSymbol` and `lift` both had the symbol. `Emit/Types.idr:21-24` `fnSymbol` looks a function up only to return `f.name` ("not in the program"). |
| Counterexample | A `Source` whose `root` is not among `fns`, and a statement whose `sym_name` is not a string. |
| Root cause | The root is a key, not the function, and the symbol is dropped between the place that knows it and the place that needs it. |
| Correction | `record Source { datas; root : TFn; others : List TFn }`. `function : Index -> TFn -> E (List (String, Statement))`, whose lifted functions are kept as `(symbol, statement)`. |
| Deletion | The root search and its error; `symbolOf` and its error. `fnSymbol`'s lookup stays only as the call-arity source (see the cross-area note). |
| Consumers | `Emit.idr`, `Emit/Declarations.idr`, `Emit/Monad.idr` (`lifted`), `Emit/Closures.idr`, `Term.idr`, `Frontend/Translate/Programs.idr` (builds `Source`). |
| Discriminator | Output is byte-identical. |
| Verification here | Chez build; corpus compare. |
| Size and risk | About 15 lines and 2 errors; low risk. Kept: the duplicate-symbol check (`written`), as 0002 F11 decided. |
| Insight | 6 |

### idris-emit-14: tensor dimensions are addressed by a `Nat` into a `List`

| Field | Content |
|---|---|
| Evidence | `Tensors.idr:92-96` `dimEntry … getAt j ds` (internal "dimension j of an array of rank"), called at 14 sites, 10 of them with `j` taken from `axes ds` of the same list (`:182,207,258,268,282,286,287,316,508`). `:239-242` `resultSize`'s `_ => otherwise` treats out-of-range as dynamic. `:301` Transpose's `fromMaybe Dynamic (getAt i ds)`. `:276-282` Concat indexes `xds` with the result's axes `axes rds`. |
| Counterexample | An axis past the rank silently becomes `Dynamic` in Transpose and resultSize, and is an internal error in `dimEntry`. |
| Root cause | The code iterates positions and indexes back into the list, where it could iterate the dimensions with their positions. |
| Correction | `withAxes : List Dim -> List (Nat, Dim)`, built once per operand, passes each per-axis computation its `Dim`. The op's own axis (`Extent j`, `Take`/`Drop`/`Concat`/`Pad a`, the `reduce` frame) is split once by `atAxis : Nat -> List Dim -> Maybe (List Dim, Dim, List Dim)`: one internal per op where there were one per lookup. |
| Deletion | `dimEntry`'s `Nothing` arm at the ten iterating sites; the silent fallbacks in `resultSize` and Transpose. |
| Consumers | `Emit/Tensors.idr`. |
| Discriminator | Output is byte-identical. |
| Verification here | Chez build; corpus compare (array programs). |
| Size and risk | About 20 lines and 3 branches; low risk. |
| Insight | 11 |

### idris-emit-15: the data table's layout is written by hand on both sides of the bytecode

| Field | Content |
|---|---|
| Evidence | Idris: `MLIR/Bytecode.idr:264-273` `Dialect` with `fieldCode` 2 (idr) and 3 (builtin), the literals `VarInt 1` (member) and `VarInt 0` (entry) at `:381,383,414`, and the order of `ctorParts`/`bodyParts` (`:458-471`). C++: `lib/IR/Bytecode.cpp:55` `enum class FieldCode { Entry = 0, Member = 1, Idr = 2, Builtin = 3 }` and the order of `readCtor`/`readBody` (`:188-205`). The layout itself is written in a comment, `IdrBytecode.td:53-66`. The type records next to them are generated (`Encoding/Idr.idr`). |
| Counterexample | Reordering a `Ctor` member on one side only compiles on both, and the reader rejects every module. |
| Root cause | The table is declared "not generated" because its fields are no entries, but its codes and record order need no custom reader. |
| Correction | `IdrBytecode.td` declares `Idr_FieldCode` as an enum and `Body`/`Ctor` as bytecode records. The generator writes `encodeBody`/`encodeCtor` and the field codes into `Encoding/Idr.idr`, and the enum into C++. `FieldReader` keeps only its dispatch. |
| Deletion | `Dialect.fieldCode`, the code literals and the hand `ctorParts`/`bodyParts`; the C++ `FieldCode` enum and the hand order of the reads. |
| Consumers | `MLIR/Bytecode.idr`, `Encoding/Idr.idr` (regenerated), `foreign/idr/include/idr/IR/IdrBytecode.td`, `lib/IR/Bytecode.cpp`, `idris-mlir-tblgen.cpp`. |
| Discriminator | `.mlirbc` is byte-identical; `tests/compiler/dialect-syntax` round-trips (owner's machine). |
| Verification here | `make typecheck`; Chez build; byte compare. |
| Size and risk | About 30 lines; no branches; medium-low risk. This prevents drift and removes no branches. |
| Insight | 14 |

### idris-emit-16: `MemRefT`'s dimension list admits shapes that are never made

| Field | Content |
|---|---|
| Evidence | `Types.idr:104` `MemRefT (List Dim) Ty`. Only `[]` (an IORef's cell) and `[Dynamic]` (`ArrayData`, `Buffer`) are made (`Types.idr:95-97`, `Primitives.idr:420,432,445`). `Types.idr:168-169` prints `[]` as `Mut` and anything else as `Array`. `Registry/Entry.idr:244` `OrderedArrayType (List Dim) …`. |
| Counterexample | `MemRefT [Static 3, Dynamic] e` prints as `Array` and reaches the array ops with two indices. |
| Root cause | The general builtin shape is used where the problem has two cases. |
| Correction | `MemRefT Ordered Ty` with `data Ordered = Cell \| Row`. `mlirType` writes `[]` or `[Dynamic]`. The hook holds `Ordered`. |
| Deletion | The `_` arm of `tyText`; the per-dimension loop where the frontend builds array indices (two cases instead). |
| Consumers | `Types.idr`, `Emit/Index.idr`, `Registry/Entry.idr`, `Registry/Primitives.idr`, `Frontend/Translate/Types.idr` (:744-760), `Frontend/Translate/Terms.idr` (`arrayElement`). |
| Discriminator | Output is byte-identical. |
| Verification here | Chez build; corpus compare. |
| Size and risk | About 10 lines and 1-2 branches; low risk. |
| Insight | 4 |

### idris-emit-17: a let-bound value's location is patched after the fact by searching for its name

| Field | Content |
|---|---|
| Evidence | `Emit/Monad.idr:110-132`: `newest` reads the last statement's name before the value is emitted, and `atBinder` compares names afterwards and rewrites that statement's location (`Bodies.idr:335-339`, `:433-435`). |
| Counterexample | A value that ends in a statement emitted earlier under the same name (a `let` of a variable) is the case `before /= Just v.name` exists to tell apart. |
| Root cause | The binder's name is known before the value is emitted, but it is applied by a search afterwards. |
| Correction | The emitter's context carries the binder (`Em nv = (Fin nv -> Held) -> Expect -> E (Maybe Val)` with `record Expect { type : Maybe Ty; binder : Maybe Shown }`), and the value-making helpers (`value`, `mlirValue`) locate their op at `Named binder l` when given one. |
| Deletion | `newest`, `atBinder` and its name comparison. |
| Consumers | `Emit/Monad.idr`, `Emit/Bodies.idr`, `Emit/Operations.idr`, `Emit/Tensors.idr`. |
| Discriminator | `.mlirbc` is byte-identical, NameLoc placement included. |
| Verification here | Chez build; byte compare. |
| Size and risk | About 25 lines and 2 branches; medium-low risk (the binder must reach only the op that makes the value). Small gain. |
| Insight | 14 |

### idris-emit-18: a key's non-keying position is the sentinel string `-`

| Field | Content |
|---|---|
| Evidence | `Ids.idr:68` `arguments : List String -- … text or "-"`; `Frontend/Translate/Keys.idr:936,949` writes `"-"`; `Term.idr:429-431` argues that no compile-time value prints as `-`. |
| Counterexample | A key position whose printed value is `-` would collide; the guarantee rests on a property of the printer. |
| Root cause | Absence is a sentinel string. |
| Correction | `arguments : List (Maybe String)`. `keyText` and `#idr.instance` write `-` for `Nothing` (the printed text does not change). |
| Deletion | The printer argument in `keyText`'s comment; nothing else. |
| Consumers | `Ids.idr`, `Term.idr`, `Emit/Declarations.idr`, `Emit/Index.idr`, `Frontend/Translate/Keys.idr`. |
| Discriminator | Output is byte-identical. |
| Verification here | Chez build; corpus compare. |
| Size and risk | About 5 lines; no branches; low risk. |
| Insight | 8 |

### idris-emit-19: XXH3's eight accumulators are a `List`

| Field | Content |
|---|---|
| Evidence | `Ids.idr:315-347`: `Accs = List Bits64`; `pairs … pairs as _ _ = as` and `merge`'s `go r _ _ = r` fall through when the lists differ in length; `stripeWords` builds a list of 8. |
| Counterexample | `accumulate` given 7 accumulators silently returns the 7th unchanged. |
| Root cause | A fixed width is held as a list. |
| Correction | `Accs = Vect 8 Bits64`; stripe and key words as `Vect 8`; `pairs` over `Vect 4 (Bits64, Bits64)`. |
| Deletion | The two fall-through clauses. |
| Consumers | `Ids.idr`. |
| Discriminator | Content names (every `contentName`) are byte-identical; the hash vectors still match. |
| Verification here | Chez build; corpus compare (lifted-function symbols hash through it). |
| Size and risk | About 10 lines and 2 clauses; low risk. |
| Insight | 4 |

## Crossing into other areas

- **Frontend** (idris-emit-1, 2, 3, 4, 6, 7): each correction is a change to
  what `Frontend/Translate/{Terms,Cases,Primitives,Shapes,Programs,Errors}.idr`
  builds. Separately, `arrayTerm` (`Terms.idr:1421-1556`) matches its bound
  arguments by position with `_ => Unreachable loc`. An arity mismatch
  becomes an arm Emit drops as impossible, a silent miscompile where an
  internal error belongs. The call-site arity (`classify` at the call) and
  the definition's arity (`TFn.arity`) are computed twice; Emit's
  `saturated` for calls is the one check that they agree.
- **C++ dialect**: idris-emit-9's `Body` variant; idris-emit-15's
  `FieldCode`. `idr.match`/`idr.match_lit` hold the default as "the region
  past the cases" (`IdrMatchOps.td:15`, `getDefaultRegion`), a positional
  convention, where upstream's `scf.index_switch` declares a
  `defaultRegion`. Emit builds `arms ++ [default]` to fit it.
  `InstanceAttr::verify` checks that every argument is a string, which an
  `ArrayRefParameter<"StringAttr">` would make unrepresentable.
- **Generator** (`idris-mlir-tblgen.cpp`): `primArity` (2), the
  `PurePrim`/`IOPrim` split and `ioResult` (3), guarded builders (6), table
  records (15).

## Judged essential, or kept

- **Core is not intrinsically typed.** Emit synthesizes types
  bidirectionally (the `Emit.idr` header), so its eliminators guard their
  scrutinee's type: `DataT` (`Bodies.idr:348`), `FunT` (`:461`), `LazyT`
  (`:489`), `TensorT` (`Tensors.idr:74-77`). An intrinsically typed Core
  would be a redesign of the frontend's output out of proportion to these
  guards. One case to test, not run: a let-bound lambda or `Delay` whose
  body never returns meets no expected type (`LetF` passes `Nothing`) and
  reaches "the result type of a lambda whose body never returns"
  (`Bodies.idr:453`, `:481`). A fixture is owed to show whether a source
  program reaches it.
- `fit`'s casts between static and dynamic extents (`Tensors.idr:125-135`)
  follow MLIR's own model of shaped types. The same holds for
  `dynamicDims` and `dynamicExtent` (`kDynamic`).
- `coerce`'s two-by-two (linear against plain, in each direction) and
  `heldType`'s world case: the quantity lives in the type, as AGENTS.md
  requires.
- `Maybe Val` for "never returns" and `match`'s handling of arms that
  never return: `ub.unreachable` is a real case.
- CaseLit's last possible alternative standing in for a missing default:
  `idr.match_lit` requires a default (`OpsMatch.cpp:146`).
- `reduce`'s rank-0 tensor for a scalar accumulator: the op's inits are
  tensors (`IdrArrayOps.td:144`); this is the boundary's coordinate.
- SSA values identified by name strings (Bytecode's `Scope`, Closures'
  `Seen`, `renameRegion`): 0002 §4.6 deferred typed SSA names to 0011.
- The duplicate-symbol and collision checks (`Emit.idr`'s `written`,
  `ES.keys`, `membersOf`) and the data type named by its string in the
  table: decided in 0002 F11; MLIR identifies the data type by name.
- `Hooks` as a record of one field per kind (D20), `Expect` indexed by
  `Key`, and `Libraries.Row` as a table: good representations.
- `Prim` as Core's vocabulary distinct from ops, `Multiplicity` (Idris's,
  with 0) distinct from the dialect's `Quantity`, and `IntTy`'s nine
  constructors that mirror Idris's `PrimType` at the boundary.
- The hand-written builtin `MlirType`/`MlirAttr` and their text: upstream's
  builtin types have C++ printers and no ODS syntax to generate from. Their
  bytecode records are generated.
- `Spelling` inside `MlirType`: a lazy text made only by `idr`/`arith`/`ub`
  (constructor not exported), which keeps totality.
- Captures computed on the emitted region (`Closures.captures`) and the
  closure's linearity read from the captures' `!idr.lin` types: this is
  more precise than the term's free variables after a match rebuilds a
  value, and quantity 1 is a type.
- `SyntaxSamples`' run-time check that every mnemonic is sampled: it is a
  test program, and its exit status is the check.
- `Spec.convention : String`: Idris's own spec text; arbitrary conventions
  must be representable to be refused.
- `Facts.terminating : Bool`: it is MLIR's unit attribute `total`.
