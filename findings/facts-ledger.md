# The facts ledger: what Idris proves, and where idris-mlir keeps or loses it

Stream: facts-ledger. Read end to end: `compiler/src` (Frontend, Translate,
Emit, Types, Term, Facts), `foreign/idr` (IdrOps.td, Passes.td, Dialect,
Facts, Specialize, Inline, Passes, Eval, Ownership, Stack, Lower,
Registration), `runtime/idris_rt.h`, and the pinned Idris 2 sources. Builds on
review-external.md (dead `quantities`, header packing) and
review-external-2.md (linearity is not uniqueness); neither is repeated
here beyond a pointer.

## The questions

1. For every fact Idris 2 proves about a program, where does idris-mlir read
   it, keep it, use it, drop it or ignore it?
2. Is every type, op, attribute, trait and verifier rule of `idr`
   load-bearing?
3. Which unexploited facts pay most, and what representation would let the
   compiler use them?
4. Which guards in the compiler's own code are a representation not yet
   chosen?

## Evidence: two programs through the pipeline

Built with the tree's compiler in
`scratchpad/research/facts-ledger/{vect,list}` (`tools/compile.sh -p base
--directive dump-mlir --directive dump-core`, plus `idris-mlir-cc --emit=llvm`
for the post-O3 IR). `vect` is `tests/e2e/v3/vect/Main.idr`. `list` is a
new program: a list read from stdin (`readDigits 20`), a linear map
`lmap : (Int -> Int) -> (1 _ : List Int) -> List Int`, a Nat loop
`count : Nat -> Int -> Int`, `safeGet : Fin n -> Vect n Int -> Int` on
`fromList xs`, `natToFin`, an enum `Colour`, and a record `Pt`. Both run
and print the right results.

What the dumps show (quotes are from the files named):

- **Vect keeps no length.** `idr.data @Data.Vect.Vect$91$$91$__$93$$44$$32$Double$93$ box`
  with `@"::" (!idr.erased, f64, !idr.box<...>)` (vect.mlir:11-13): the
  implicit length is a zero-sized `!idr.erased` field, and every length is
  one recursive box type. `[x, 1.0, x / 2.0]` is three `idr.con`s of
  cells (01-idr-simplify.mlir:197-199; idr-stack puts them in the frame,
  05-idr-rc.mlir:243-245). In the O3 IR, `zipWith ... $spec$1` walks the
  linked cells with a header tag load, `and 65535`, an exclusivity test
  and inc/dec per element (vect.ll:986-1060), for a vector whose length 3
  is static.
- **Impossible cases are used.** `Data.Vect.last`: the core has
  `Nil/0 => unreachable` (vect.core:121-126); the simplified function reads
  `idr.field %arg0[@"::", 1]` with no tag test (01-idr-simplify.mlir:106-121).
  `Main.safeGet` specialised to `FZ` is one field read (list 01:163-166).
- **Nat is an arbitrary-precision integer, and O(n) where Idris is O(1).**
  `Main.count(%arg0: !idr.big, ...)` loops with `idr.match_lit %arg0 ... case
  #idr.big<"0">` and `idr.big.pred` (list 01:106-120), lowered to
  `idris_rt_big_cmp` and `idris_rt_dec` calls (list 09:336-353).
  `Prelude.Types.natToInteger` survives as a non-tail O(n) recursion that
  computes the identity (list 01:181-196; list.ll:186); upstream Idris
  rewrites it away (below). `Maybe (Fin n)` is `@Just tag 1 (!idr.big)`
  (list.mlir:19-21): the bound is gone and the index is a GMP-capable word.
- **Proofs computed at runtime.** `Dec (LTE m n)` is
  `@Yes tag 0 (!idr.big)` / `@No tag 1 (!idr.fn<(!idr.big) -> (!idr.data<@Builtin.Void>)>)`
  (list.mlir:46-48); `Data.Nat.isLTE` builds `Yes(add_Integer(#0, 1))` and
  closures `\lam59 ... => succNotLTEzero` (list.core:339-344, 427-430).
  LTE is Nat-like to Idris, so the proof is a counted integer.
- **Pure calls are recomputed.** The root calls
  `@Prelude.Types.List.length$91$Int$93$(%14)` four times on every path, on
  the same list (list 01:609, 615, then 620, 623 in one region of the match
  on the second and 692, 695 in the other), a total function with
  `idr.effects<none>`.
- **Linearity costs nothing and buys nothing.** `lmap` takes
  `!idr.lin<!idr.box<List>>`, uses it at once (`idr.lin.use`, list.mlir:314)
  and matches; after idr-rc the cons case is `idr.take` + `idr.reuse`
  (list 05:862-866), and O3 still tests `count == 1` and the stack bit
  (list.ll:310-330). Consistent with review-external-2.md.
- **LLVM receives no facts from us.** The LLVM-dialect module before
  translation (09-convert-scf-to-cf.mlir, both programs) has no
  `overflow<>`, `nonnull`, `noalias`, `range`, `invariant`, `arg_attrs` or
  function attributes on program functions (grep: zero). Box fields and tags
  are plain `llvm.load`s (Runtime.cc:142-145). Every attribute in the O3 IR
  (`nofree readonly captures(none)` on `length`'s parameter, `noundef`)
  is LLVM's own inference over the runtime bitcode linked in before O3
  (idris-mlir-cc.cc:280-296). `idr.total` is gone at idr-lower (07 dump:
  `attributes {no_inline}` only).

Also checked with the pinned `idris2 --check` (scratchpad `lintest/`):
pattern variables of a quantity-1 scrutinee get the field's quantity, not
1. `dropFirst : (1 xs : List Int) -> List Int; dropFirst (x :: xs) = xs`
and `dup (x :: xs) = (xs, xs)` check; `useLP (MkLP a b) = b` with
`1 fstL : Int` fails ("0 uses of linear name a"). So `1 xs : List Int`
promises nothing about the tail: uniqueness is only ever of the outer cell,
and must be inferred.

## The ledger

Upstream paths are under `third_party/Idris2/src` unless they start with
`libs/`. "LB" = load-bearing.

### 1. Quantities 0/1/ω on binders, fields and arrows

- **Idris computes:** `RigCount` on every `Lam`/`Let`/`Pi`/`PLet` binder
  (Core/TT/Binder.idr:93-107), checked by `linearCheck`
  (Core/LinearCheck.idr:694). Pattern variables get the field's quantity
  (verified above).
- **Frontend reads:** yes, from the binder of the checked type:
  `useOf`/`binderOf` (Frontend/Resolve.idr:78-85) for parameters
  (Translate/Instances.idr:101-128), fields (Translate/Types.idr:308-315),
  arrows (Types.idr:252-258), lambdas and lets (Translate/Terms.idr:111-125).
  Stored as `Binder = Gone | Held Use Ty` (IdrisMLIR/Types.idr:117-118).
- **Emit keeps:** in types. `Gone` → `!idr.erased`, `Held Once` →
  `!idr.lin<T>` (the world stays `!idr.world`, linear by rule),
  `Held Many` → `T` (Emit/Types.idr:36-40, Emit/Monad.idr:74-77).
  Moves between positions are `idr.lin.use`/`idr.lin.enter`
  (Emit/Operations.idr:47-55). Match scrutinees and results of regions and
  functions are always plain (Emit/Bodies.idr:51-54, 189), which matches
  Idris.
- **Passes use it:** only as constraints. Verifier: at most one use per
  path (Dialect.cc:397-420), a closure with a linear capture used once
  (Ops.cc:791-810). Folds must not duplicate a linear field
  (`readOnce`, Ops.cc:392-398; Canonicalize/Field.cc; Apply.cc:17-26).
  Specialization keeps a linear leaf only if its shape dies at the call
  (Specialize.cc:186-190). Defunctionalization keeps linear slots
  (Defunctionalize.cc:882, 959). Borrow inference keeps q1 parameters owned
  (Borrow.cc:53). Counting ignores it (Counting.cc:9-13). idr-expect
  `quantities-kept` checks nothing widened.
- **Lost at:** idr-lower, by design (Layout.cc:102, `LowerLinear`
  Patterns.cc:134-146). Never earlier.
- **LLVM receives:** nothing. q1 removes no work anywhere (lmap above).

### 2. Erasure: `eraseArgs`/`safeErase` and `!idr.erased`

- **Idris computes:** `findErased` → `(eraseArgs, safeErase)`
  (TTImp/Elab/Utils.idr:19-58), stored at ProcessType.idr:171-180 and
  `updateErasable` (Utils.idr:61-73); fields at Core/Context/Context.idr:307-310.
  `safeErase` = positions whose value is determined by a detaggable
  unerased argument (`detagSafe`, Utils.idr:19-35).
- **Frontend reads:** the binder quantities directly (equivalent to
  `eraseArgs`: Translate/Closed.idr:240-251, Instances.idr:110-113).
  `safeErase` is not read. Type arguments become compile-time `TypeParam`s;
  indices are erased from instance names (Types.idr:182-197, 280-283).
- **Emit keeps:** `!idr.erased` parameters, fields and arguments, all the
  one constant `#idr.erased` (Operations.idr:67-70).
- **Passes use it:** specialization never treats an erased value as static
  (Pattern.cc:22, Specialize.cc:163); idr-prune skips it (Prune.cc:94);
  layouts give it no component (Layout.cc:103-104).
- **Lost at:** idr-lower (zero components). What is lost earlier is *which*
  value was erased: every erased value is the same attribute at Emit, so no
  pass can know an erased operand is "the length of this vector".
- **LLVM receives:** nothing (parameters removed by signature conversion).

### 3. Linearity, and uniqueness

- **Idris computes:** linearity (above). Uniqueness it does not compute.
- **Frontend/Emit:** as quantities.
- **Passes:** as quantities. Uniqueness is nowhere; `idr.reset`/`idr.take`
  test exclusivity at runtime (`Runtime::exclusive`, Runtime.cc:147-154;
  ResetReuse.cc:19-25 describes the missing piece).
- **How it could be derived:** review-external-2.md's plan (a call-graph
  fixpoint like Borrow.cc) is right. Two facts make it sharper:
  - a q1 parameter's pattern variables get their fields' quantities
    (checked above), so Idris's q1 on a list says nothing about its tail.
    A tail is unique only if whatever built the list gave the cons a unique
    tail, so inference must follow values into and out of constructor
    fields (Clean's uniqueness propagation through data), not stop at
    parameters;
  - the owned-stage verifier already counts references exactly on every
    path (Ownership/Verify.cc): a value produced by `idr.con`/`idr.reuse`
    and consumed before any `idr.inc` of it is unique by that same walk.
- **LLVM receives:** the runtime test.

### 4. Totality and coverage, impossible and absurd cases

- **Idris computes:** termination `checkTotal` (Core/Termination.idr:101)
  from size-change graphs; coverage in ProcessDef.idr (`MissingCases`,
  :1079) and Core/Coverage.idr; `impossible` clauses become `Impossible`
  leaves; uncovered leaves are `Unmatched`.
- **Frontend reads:** termination by calling `checkTotal` again
  (Translate/Programs.idr:36-41) into `Facts.terminating`
  (Programs.idr:62; its `provenance` is written, never read);
  `isCovering` into `Ctx.complete` (Programs.idr:52-55). `Impossible`,
  and `Unmatched` in a covering definition, become `Unreachable`; otherwise
  `Crash` (Translate/Cases.idr:33-49). Constructors the tree omits become
  alternatives of the same kind (Cases.idr:64-70).
- **Emit keeps:** `idr.total` (Emit/Attributes.idr:32; inherited by lifted
  lambdas). Unreachable alternatives are left out of the match
  (Bodies.idr:57-60, 195-200); a literal match whose default is
  unreachable uses its last case as default (Bodies.idr:217-221). A crash
  is `idr.crash` + `ub.unreachable`.
- **Passes use it:** `facts::of` reads `idr.total` as "may not return"
  (Facts/Functions/Of.cc:15), feeding `canMoveAcross`/`canDelay`/`canDrop`
  (sinking, case-of-case, unused-call removal, raising), the evaluation
  budget (Facts/Evaluation/CanEvaluate.cc:57, Eval/Eval.cc:60-91),
  `idr.may_loop` in non-total loops (TailLoops.cc:153) and clones' facts
  (Facts/Functions/Inherit.cc:15-18). Coverage: a match with neither all
  cases nor a default lowers its last case as the default, with no test
  (Lower/Matches.cc:57-59).
- **Lost at:** `idr.total` at idr-lower. Coverage survives as "no default
  test". An Idris-proved unreachable region that remains becomes a poison
  yield (Matches.cc:24-27) or a poison return (Bodies.idr:118-123,
  Prune.cc:52-66; PINS inline-unreachable), not LLVM `unreachable`.
- **LLVM receives:** fewer switch cases; `noreturn` crash calls (inferred
  from the runtime); no `willreturn`/`mustprogress`.

### 5. Size-change graphs (`GlobalDef.sizeChange`)

- **Idris computes:** `getSC` (Core/Termination/CallGraph.idr:407-422);
  `SCCall` with a `Matrix SizeChange` of Smaller/Same/Unknown
  (Core/Context/Context.idr:272-280; Algebra/SizeChange.idr).
- **Frontend reads:** yes, once: Translate/Recursion.idr:57 reads it to
  reject polymorphic recursion (:113-134). Then drops it.
- **Emit keeps:** nothing.
- **Passes:** idr-specialize re-derives the same classes (fixed, decreasing,
  bounded) by abstract interpretation over `idr.field`, match arguments,
  `idr.big.pred`, and an unproved heuristic: an integer `arith.subi` by a
  positive constant counts as decreasing (Specialize/BindingTimes.cc:102-162,
  121-127).
- **LLVM receives:** nothing.

### 6. Dependent indices and proofs: Nat, Fin n, Vect n a, LTE, Elem, So

- **Idris computes:** `ConType ZERO/SUCC` for any two-constructor type with
  a nullary and a unary self-successor (TTImp/ProcessData.idr:345-363
  `calcNaty`): Nat, Fin, LTE, Elem are all "Nat-like". Detagging positions
  `detagabbleBy` (ProcessData.idr:147-155, stored :548-549;
  Context.idr:104-113). `So` is UNIT-shaped (`calcUnity`, :366-373).
  Upstream's backends then rewrite Nat operations to Integer ones
  (`natHack`, Compiler/Opts/Constructor.idr:81-93: natToInteger,
  integerToNat, plus, mult, minus, equalNat, compareNat), since the
  `%builtin` pragmas are commented out in the pinned prelude
  (libs/prelude/Prelude/Types.idr:41, 103; libs/base/Data/Fin.idr:86, 252).
- **Frontend reads:** ZERO/SUCC only (`natRole`/`natLike`,
  Translate/Types.idr:207-234), and makes every Nat-like `BigT`
  (Types.idr:264-265): Fin's bound, Nat's non-negativity and the
  proof-ness of LTE/Elem are dropped here. Constructors become big literals
  and `add 1` (Terms.idr:226-236); matches become `CaseNat`
  (Cases.idr:97-133). Indices are erased from instances (Types.idr:182-197,
  276-283). `detagabbleBy` is not read (the `TCon` pattern at
  Types.idr:289 ignores it). natHack is not applied: the frontend reads TT,
  not CExp.
- **Emit keeps:** `!idr.big`; `CaseNat` is `idr.match_lit %n : !idr.big
  { case #idr.big<"0"> ... default { idr.big.pred } }` (Bodies.idr:237-254).
  `big.pred` records structural descent for BindingTimes.
- **Passes:** BindingTimes (descent), specialization unrolls static Nats
  (`readDigits 20` unrolled 20 times, list 01:241-593). Lowering makes
  `big.pred` a `big.sub` of 1 (Lower/Predecessors.cc).
- **Lost at:** the frontend.
- **LLVM receives:** calls to `idris_rt_big_*` on a tagged word.

### 7. Interface resolution

- **Idris computes:** instance search (Core/AutoSearch.idr:42) and
  `TypeFlags.uniqueAuto` (Context.idr:55-58).
- **Frontend reads:** `uniqueAuto` to recognise dictionaries
  (Translate/Types.idr:341-350); `classify` makes them compile-time `DictParam`s
  keying the instance (Instances.idr:114-122); a runtime-chosen
  implementation is rejected (:119-120); matches on dictionaries select now
  (Cases.idr:77, 137-159).
- **Emit/passes/LLVM:** nothing left to keep: every method call is a direct
  call. Fully exploited.

### 8. Data type facts: newtype, enum, recursive, ConInfo, detagging

- **Idris computes:** ConInfo NIL/CONS/NOTHING/JUST/ENUM/RECORD/UNIT/ZERO/SUCC
  (Core/CompileExpr.idr:19-29; ProcessData.idr:291-390); newtype argument
  (`findNewtype`, :235-247, into `DCon newtypeArg`, Context.idr:94-103);
  detag positions (above); `mutwith`.
- **Frontend reads:** ZERO/SUCC only. Recursion it computes itself, per
  instance (Programs.idr:85-98), which is more precise than `mutwith`.
- **Emit keeps:** `idr.data ... box` or unboxed.
- **Passes:** the unboxed-sum layout makes enums a tag, unit a zero-slot
  value, records and non-recursive newtypes untagged (Layout.cc:56-97), so
  ENUM/RECORD/UNIT/non-recursive newtype cost nothing to ignore. Lost: a
  recursive newtype is a one-field cell (a `Rose = MkRose (List Rose)`
  instance is boxed by the cycle check); `Nil`/`Nothing` of boxed types are
  static cells whose tag is loaded and masked at every match
  (Runtime.cc:142-145), where a null pointer would do.
- **LLVM receives:** `load i32; and 65535; switch`, no `!range`.

### 9. `%inline`, `%noinline`, `%spec`, `%transform`, `%builtin`

- **Idris computes:** flags `Inline`/`NoInline` (TTImp/ProcessFnOpt.idr:39-43),
  `specArgs` (:85), auto-inline of case blocks (TTImp/ProcessDef.idr:736-742),
  transforms (TTImp/ProcessTransform.idr:18; Core/Context.idr:1019).
  prelude+base carry 469 `%inline`, 21 `%transform`, 0 `%spec`.
- **Frontend reads:** none. User pragmas other than `%default` are rejected
  (Frontend/Profile.idr:118-121).
- **Passes:** idr-inline decides by MLton's size rule alone (Inline.cc:36-38,
  107-108); `no_inline` comes only from loop breakers.
  `%transform "tailRecLength" List.length = List.lengthTR`
  (libs/prelude/Prelude/Types.idr:588) is ignored, so `length` is a
  non-tail recursion (list.ll:135-160).
- **LLVM receives:** nothing.

### 10. Primitive ranges: Int, Integer, Nat, Double, Char

- **Idris:** `PrimType` (Core/TT/Primitive.idr); meaning is the runtime's.
- **Frontend/Emit:** fixed widths with signedness on the op
  (IdrisMLIR/Types.idr:54-97; Emit/Operations.idr:120-203); wrapping arith without
  overflow flags, which is right for Idris `Int`/`BitsN`; Char `i32`;
  Integer and every Nat-like `!idr.big`.
- **Passes:** `InferIntRangeInterface` on `idr.tag`, `idr.to_char`,
  `idr.int_head`, `idr.double_head`, `idr.str.length`
  (IdrOps.td:332-333, 484-485, 506-518, 597-598) is declared, and no pass
  in the pipeline runs integer range analysis (Registration.cc:15-30;
  Simplify.cc:206-222). Crash facts are recomputed from constants only
  (`knownNonZero`, `knownFinite`, `knownNonEmpty`, Ops.cc:20-46).
- **LLVM receives:** no `range`, no `nuw` on sizes, no `noundef` from us.

### 11. World and IO

- **Idris:** `%World` (Core/TT/Primitive.idr:31, 51); `IO a = MkIO (1 _ :
  World -> IORes a)`.
- **Frontend:** `WorldT`; the root written as world-passing code
  (Programs.idr:115-144); forged worlds rejected (Profile.idr:220-223,
  Terms.idr:105).
- **Emit:** `!idr.world` threaded through `idr.io.*`; IO actions are
  `!idr.lin<!idr.fn<(!idr.world) -> ...>>` fields of `MkIO`.
- **Passes:** single use (Dialect.cc:397-420); `io` effects from types
  (Infer.cc:89-101); no evaluation of IO (CanEvaluate.cc:15); no raising
  of world takers; no world in closures (Ops.cc:792-793); `IOResource`
  orders effects.
- **Lost at:** idr-lower (zero components). **LLVM:** runtime calls in order.
  Fully exploited.

## Audit of the dialect: is every part load-bearing?

"Consumed" means a pass or the verifier reads it and behaves differently.
mlir-idioms.md §4 (written in parallel) reaches the same verdicts on the
unprefixed-attribute hole, `RuntimeCallOpInterface`, the Crash and
Divergence resources, the five range interfaces, `arg_attrs`, `tag` and
`box`. Found here and not there: the ops with no producer (`io.get_char`,
`io.exit`), `idr.origin` duplicating `spec_key`, `bindsField` admitting a
binding Idris does not make, `Idr_CountedType` admitting `!idr.lin<i64>`,
the second definition of "holds references" in the `idr.borrowed` rule,
the stringly `closures` link, coverage encoded by absence, speculatability
declared and never read, `FnType::getFunctionType` and `Facts.provenance`
unused.

### Types

| Piece | Verdict | Who consumes it / what is wrong |
|---|---|---|
| `!idr.data<@T>` | LB | layouts, counting, matches, defunctionalize |
| `!idr.box<@T>` | LB, duplicated | reset/reuse, stack, lower. Box-ness is stored twice, here and in `idr.data @T box`, and verifyProgram checks they agree (Dialect.cc:245-250) |
| `!idr.fn<...>` | LB | closures, defunctionalize; the helper `FnType::getFunctionType` (Dialect.cc:76) has no caller |
| `!idr.erased` | LB | layouts, specialization, prune, eval. Weaker than it should be: one value for every erased thing (see §2) |
| `!idr.str` | LB | |
| `!idr.big` | LB, weak | conflates Integer with every Nat-like type; its own summary says "an Integer, or a Nat-like value (non-negative)" (IdrOps.td:80) |
| `!idr.world` | LB | verifier, effects, layout |
| `!idr.lin<T>` | LB as a constraint only | verifier, borrow (owned), specialization and fold guards, quantities-kept. No pass gains speed from it |
| `!idr.token` | LB | owned stage |
| `Idr_CountedType` | weak | admits any `!idr.lin<T>`, so `idr.inc %x : !idr.lin<i64>` verifies (IdrOps.td:875-877) |

### Attributes

| Piece | Verdict | Notes |
|---|---|---|
| `#idr.con`, `#idr.closure`, `#idr.erased` | LB | untyped with a NoneType self type (review-external.md) |
| `#idr.big` | LB | canonical-decimal verifier is load-bearing (uniquing) |
| `CmpPredicate` | LB | str/big comparisons |
| `#idr.effects` | LB | `facts::of` |
| key attrs (`key_hole`, `key_con`, `key_closure`, `spec_key`, `key_apply`, `key_apply_field`) | LB | identity of clones (DenseMap), `fill` (Specialize.cc:73-93) |
| `#idr.clone` | LB via a side channel | its `function` parameter must equal the function's own name (Dialect.cc:470-476): it carries no information, and exists to be a symbol use so that MLIR's interprocedural analyses assume unseen callers (IdrOps.td:1008-1013) |
| `idr.program` | LB | triggers verifyProgram |
| `idr.stage = "owned"` | LB | owned-stage verifier; one dialect, two semantics (review-external.md) |
| `idr.total` | LB | `facts::of`, eval budget, tail loops, inherit |
| `idr.library` | LB, barely | only LoopBreakers.cc:46 (breaker choice) |
| `idr.effects` (on func) | LB | |
| `idr.stack` | LB | ConOp effects (Ops.cc:339), ResetReuse, lowering |
| `idr.origin` | half dead | its presence marks a clone (LoopBreakers.cc:42, Simplify.cc:115); its value is read only by idr-expect (Expect/Clones.cc:24) and duplicates `spec_key`'s origin; nothing checks the two agree |
| `idr.clone`, `idr.hole` | LB | CloneTable (Clones.cc:35-41); a clone whose marks do not parse silently becomes "only a function" (Clones.h:5-7) |
| `idr.borrowed` | LB | its verifier's type list (Dialect.cc:493) is a second definition of "holds references", differing from `Counting::counted` (Counting.cc:9-38) |
| `no_inline` | LB | inliner, breakers |
| any attribute without the `idr.` prefix on an idr op | **dead, accepted** | `quantities` on `idr.ctor` (tests/idr/rc/loops.mlir:16-17, tests/idr/stack/expect.mlir:16-17) is the instance review-external.md found; the hole is general: the dialect verifies only `idr.`-prefixed discardable attributes (Dialect.cc:428-479) |
| `idr.apply`'s `arg_attrs`/`res_attrs` | dead | required by CallOpInterface; never set or read |
| `idr.ctor`'s `tag` | redundant | DataOp::verify forces it to be the position (Ops.cc:164-176); a field whose only legal value is derived is a guard |
| `idr.data`'s `closures` | LB, stringly | the constructors are named after their label functions (Facts/Closures/ClosureLabel.cc:9-13); no verifier checks the function exists or that its captures are the fields |

### Ops

Producers: Emit writes `data`, `ctor`, `constant`, `con`, `match`,
`match_lit`, `yield`, `closure`, `apply`, `crash`, `div`, `mod`,
`to_char`, `to_int`, the `str.*` and `big.*` ops, `io.put_str`,
`io.put_char`, `io.get_byte`, `lin.enter`, `lin.use`.

| Op | Verdict | Notes |
|---|---|---|
| `idr.io.get_char`, `idr.io.exit` | **dead** | no producer: `IOOp = PutStr \| PutChar \| GetByte` (IdrisMLIR/Types.idr:355-356); only tests and the lowering's list mention them (Lower/Patterns.cc:450). `io.exit` never returns yet yields a world |
| `idr.tag` | internal | created only by idr-lower phase 1 (Lower/Matches.cc:64) and converted in phase 2; its range inference is unconsumed, its folder is reachable only through the conversion's fold-first attempt |
| `idr.io.put_int`, `put_double`, `int_head`, `double_head` | LB | produced by canonicalization (Canonicalize.td:20-45) |
| `idr.may_loop` | LB | tail loops; Facts (`partial`); lowering tick |
| `idr.big.pred` | LB, weak | descent for BindingTimes; its precondition (not zero) and Nat-ness are nowhere in the type |
| `idr.match` | LB, weak | coverage is encoded by absence: a match with neither every case nor a default means "Idris proved the rest impossible", and the verifier cannot tell that from a pass that lost a region (Ops.cc:571-585; lowering trusts it, Matches.cc:57-59) |
| `idr.match` region arguments | admitted, unproduced | `bindsField` lets a case bind an ω field linearly (Ops.cc:587-592) "because matching a linear value binds each field linearly"; that is not Idris's rule (checked above) and Emit never writes it |
| `idr.field` | LB | `Pure` claims a read of another constructor's field never traps; for a static `Nil` cell of 8 bytes that is a read past the object. Harmless today because nothing speculates (below) |
| every other op | LB | |

### Traits, interfaces, resources

| Piece | Verdict | Notes |
|---|---|---|
| `CallsRuntime` trait | LB | `getHelper` (Lower/Patterns.cc:358, 402) |
| `RuntimeCallOpInterface` | **dead** | never cast to; only the trait's static method is used |
| `MayCrashOpInterface` | LB | Facts (Only.cc:25, Infer.cc:42), lowering crash checks |
| `MayCrash` effects | LB | MLIR's DCE and CSE |
| speculatability (`MayCrash`, `ConOp`, `RecursivelySpeculatable`) | unconsumed | only LICM, control-flow sink and slice utilities read it, and none runs (Simplify.cc:206-222, Registration.cc:15-30) |
| `PerformsIO` | LB | Facts (Only.cc:18) |
| `IOResource`, `LinResource` | LB | ordering; no merging of linear entries (Expect/Allocation.cc:29) |
| `CrashResource`, `DivergenceResource` | **dead** | every op that writes them also writes `IOResource` (Idr.h:104-107; IdrOps.td:444-446), and nothing queries them |
| `InferIntRangeInterface` (5 ops) | **dead** | no range analysis in the pipeline |
| `RegionBranchOpInterface` on matches | LB | sccp, dead code, prune, remove-dead-values |

### Verifier rules

LB: the root's shape; every sum/box type names a declaration; unboxed
containment is acyclic (Dialect.cc:276-303, needed by layouts); linearity
(Dialect.cc:397-420); `LinType::verify`; `isFieldType`; `BigAttr`/`ConAttr`
forms; constant/con/field/closure symbol checks; `match_lit` keys and
default; no world in a closure (the Facts rely on it); the owned-stage walk.

Redundant or weak: tags 0..n-1 (derivable), box-ness agreement
(duplicated state), `idr.hole` any integer, `idr.origin` any string.

Missing: match exhaustiveness (cases ∪ default versus the constructors);
`closures` constructors versus their functions; header packing limits
(review-external.md); unknown non-`idr.` attributes on idr ops.

## The global maximum: every Idris fact is a type that MLIR's own machinery reads

The ledger's pattern is uniform: Idris proves a fact, the frontend reads
part of it, and what reaches MLIR is either a constraint nothing optimizes
with (`!idr.lin`), a discardable attribute read by a hand-written analysis
of ours (`idr.total` via `Facts`), or nothing (sizes, bounds, indices,
size-change, propositions). The global maximum is the opposite: each fact
is a type (or a typed property of an op or function), every question a pass
asks is answered by an interface derived from those types, and the passes
that answer them are MLIR's: IntegerRangeAnalysis and
ValueBoundsOpInterface, the DataFlow framework, CSE/LICM/DCE through
MemoryEffectOpInterface, One-Shot Bufferize and ownership-based
deallocation, linalg/scf/vector. Where ours duplicates one of them, ours
goes. This extends representation.md (the representation layer: facts as
types, one decision table, lowering only reads) and mlir-idioms.md (MLIR
mechanisms), and puts the ledger's facts into both.

| Idris fact | Its type in the IR | The MLIR machinery that consumes it | What of ours it deletes |
|---|---|---|---|
| quantity 0, indices (`Vect n`, `Fin n`) | a ghost: `!idr.erased<index>` that keeps the erased value's identity and type (conjecture: zero runtime components, verified to reach only ghost positions) | ValueBoundsOpInterface on idr ops (`idr.field @"::"[2]` of a vector with ghost `n` has ghost `n - 1`); `ValueBoundsConstraintSet` proves `Fin` accesses in bounds and folds matches the index decides | the `forced` guard (Cases.idr:91-95); per-length clones for static shapes |
| Nat-likes, Fin, sizes | `!idr.nat` (a non-negative big), `!idr.fin` relative to a ghost bound, narrowed to `index`/`i64` where a range proves it (representation.md R1, R5, R13) | IntegerRangeAnalysis seeded from types (`setToEntryState` override, mlir-idioms 6.1); `int-range-optimizations`; `arith` with `overflow<nuw>` where proved | `CaseNat` special cases (Cases.idr:71-74, Bodies.idr:237-254), `big.pred`'s implicit precondition, BindingTimes' `subi` heuristic, `knownNonZero` |
| totality, effects | properties of the function and of `!idr.fn` (`!idr.fn<(A) -> (R), #idr.effects<...>>`), not discardable attributes | MemoryEffectOpInterface answered from the callee's type: an external model on `func.call`, the op's own implementation on `idr.apply`; MLIR's CSE, LICM, DCE and remove-dead-values then treat pure total calls as pure; `will_return`/`memory_effects` on `llvm.func` | `Facts/Moves` (`canMoveAcross`, `canDelay`, `canDrop`), `RemoveUnusedCall`, the `PerformsIO` trait (with mlir-idioms 3.4's resource hierarchy) |
| quantity 1, uniqueness | `!idr.lin<T>` (Idris's), `!idr.own<T>` and an `i1` exclusivity indicator after rc (mlir-ownership-types.md), inferred interprocedurally | the DataFlow framework (`AbstractSparseBackwardDataFlowAnalysis`, `setInterprocedural(true)`) for borrow and uniqueness inference; canonicalization folds constant indicators | Borrow.cc's fixpoint, Verify.cc's path interpreter, `idr.stage`, the runtime test where the indicator is `true` |
| index-shaped data used by index (Vect, linear arrays) | `tensor<?xT>` whose dimension is the ghost length, chosen by one representation pass when the three proofs of representation.md R12 hold | linalg (`linalg.map`, `linalg.reduce`, `linalg.generic`) for structural recursion raised to it; One-Shot Bufferize for in-place (uniqueness feeds its writability); ownership-based deallocation; vectorization of static shapes (`Vect 3 Double` → `vector<3xf64>`) | idr-rc, reset/reuse and idr-stack for those types (buffer placement and `promote-buffers-to-stack` cover them) |
| size-change graphs | a per-parameter descent property in the function's type (clones map it through their keys' holes) | a DataFlow analysis for binding times; raising of a self-recursion that descends one step per call to `scf.for` with a trip count ValueBounds can use | BindingTimes' abstract interpreter (BindingTimes.cc:102-162) |
| data declarations, ConInfo, detag, newtype | identified recursive types that carry constructors and the layout decision (mlir-idioms 1.5; representation.md's `Rep` grammar), including nullable-pointer nullary constructors and the index pattern that selects each constructor | `DataLayoutTypeInterface` for sizes; folders read constructors off the type in O(1) | the symbol lookups mlir-idioms 1.5 counts (46), verifyProgram's type walk, the `box` flag, `tag` |
| coverage | an exhaustive `idr.match` (every constructor a case or a region ending in `ub.unreachable`), verified | lowering to `cf.switch` with an unreachable default; LLVM `unreachable` | coverage by absence (Matches.cc:57-59) |
| immutability of cells | a consequence of the types, stated at lowering | `invariant.group` loads with a launder at `idr.reuse`, `nonnull`, `dereferenceable`, `range` on tags (mlir-idioms 6.3) | nothing; LLVM gains load CSE across runtime calls |
| propositions (LTE; not Elem) | computed by the frontend from `detagabbleBy`: a field whose value its indices determine is `!idr.erased` | ordinary DCE | the runtime big and closure in `Dec (LTE m n)` |
| library knowledge (`%inline`, `%transform`, natHack) | function properties and registry hooks of kind Faster | the inliner's profitability callback reads the property before MLton's rule | nothing; adds |

## The 10 biggest unexploited facts, by payoff

Each: the fact, what shows it is lost, the representation, and what
consumes it.

1. **Uniqueness, and ownership as types.** Lost: every reset tests the count
   at runtime (list.ll:310-330), and Idris's linearity cannot supply it
   alone, since a q1 value's ω fields are unrestricted (checked above).
   Representation: `!idr.own<T>` with an `i1` exclusivity indicator
   (mlir-ownership-types.md), uniqueness inferred by a sparse backward
   interprocedural analysis on MLIR's DataFlow framework. Consumers:
   canonicalization (constant indicators fold the test away), specialization
   (callers passing `true` get test-free clones), and for arrays One-Shot
   Bufferize (fact 2). The README's promise lives here.
2. **Index-shaped data as tensors.** Lost: `Vect 3 Double` is three linked
   cells, walked with tag loads, exclusivity tests and inc/dec
   (vect.ll:986-1060). Representation: a representation pass chooses
   `tensor<?xT>` (dimension = the ghost length) for an instance when
   representation.md R12's proofs hold, and a static length gives
   `tensor<3xT>`; structural recursions over it (map, zipWith, foldr, as
   Data.Vect writes them) are raised to linalg. Consumers: One-Shot
   Bufferize and its in-place analysis, ownership-based deallocation,
   linalg vectorization. This is MLIR used as MLIR; nothing else in the
   ledger pays as much on numeric code.
3. **Nat-likes are naturals, and mostly small.** Lost: `plus`, `mult`,
   `minus`, `natToInteger`, `compareNat` are O(n) recursions over bigs
   (list 01:181-196; representation.md: `tri 500` overflows the stack),
   because upstream's natHack (Constructor.idr:81-93) runs on CExp, which
   the frontend does not read. Representation: `!idr.nat`; the natHack
   functions as registry hooks to `idr.big` ops (a Faster hook, diffable
   against Chez); `index`-width narrowing where IntegerRangeAnalysis proves
   it. Consumers: IntegerRangeAnalysis, `int-range-optimizations`.
4. **Effects and totality in the types.** Lost: `length xs` runs four times
   on every path (list 01:609-623); nothing in MLIR knows a call is pure.
   Representation: effects and totality as properties of `!idr.fn` and of
   functions, answered by an external MemoryEffectOpInterface model on
   `func.call` and `idr.apply`. Consumers: MLIR's CSE, LICM, DCE,
   remove-dead-values; at the LLVM level `memory_effects` and
   `will_return`. Our `Facts/Moves` and `RemoveUnusedCall` go.
5. **Ghost indices.** Lost at Emit: every erased value is the one
   `#idr.erased`, so "this is the length of that vector" is gone before any
   pass runs (§2). Representation: `!idr.erased<index>` ghosts carrying
   identity, related by ValueBoundsOpInterface implementations on the ops
   that build and take apart indexed data. Consumers: ValueBounds (bounds
   checks, `Fin` in range), match folding when an index decides the
   constructor (`detagabbleBy`), fact 2's tensor dimensions. Conjecture: the
   ghost must survive remove-dead-values, which drops unused parameters.
6. **Data declarations that carry their layout.** Lost: ConInfo beyond
   ZERO/SUCC, newtype-by, detag (§8). Representation: identified recursive
   types with a verified layout (representation.md's layer; mlir-idioms
   1.5), including nullable-pointer `Nil`/`Nothing` and newtypes erased
   even when recursive. Consumer: `DataLayoutTypeInterface`, lowering as a
   reader.
7. **Immutable cells, told to LLVM.** Lost: the LLVM dialect module carries
   no attribute (09 dumps: zero). Representation: at lowering,
   `invariant.group` field loads with a launder at `idr.reuse`, `nonnull`
   and `dereferenceable` on box pointers, `range` on tag loads.
   Consumer: LLVM's GVN and LICM.
8. **Size-change graphs.** Lost after the frontend's rejection check
   (Recursion.idr:57). Representation: per-parameter descent in the
   function's type. Consumers: a DataFlow binding-time analysis replacing
   BindingTimes' interpreter; `scf.for` raising with trip counts; the
   stack pass's depth bound.
9. **Coverage, explicitly.** Lost: impossibility is absence
   (Matches.cc:57-59), and unreachable regions become poison (§4).
   Representation: exhaustive matches, verified, with impossible
   constructors as `ub.unreachable` regions. Consumer: `cf.switch` with an
   unreachable default, LLVM `unreachable`. Needs the upstream inliner bug
   behind PINS inline-unreachable fixed or worked around at the top level
   only.
10. **Propositions and library knowledge.** Lost: `Dec (LTE m n)` carries a
    runtime big and a closure (list.mlir:46-48); 469 `%inline` and 21
    `%transform` in prelude and base are ignored. Representation: the
    frontend erases fields its indices determine; `Inline`/`NoInline` as
    function properties; `%transform` rules as registry hooks. Consumers:
    DCE; the inliner's profitability callback.

## The path to it

Each step leaves the suites green and deletes what it replaces.

1. **Cut the dead and the duplicated** (audit above; mlir-idioms §4): the
   program-wide attribute rule, `io.get_char`/`io.exit` unless Emit gains
   producers, `RuntimeCallOpInterface` made load-bearing or removed, the
   resource hierarchy, `idr.origin`'s value, `tag`, `bindsField`'s extra
   case, `Idr_CountedType` narrowed to counted types.
2. **The natHack hooks** in the registry. Small, and removes the O(n)
   arithmetic and the stack overflow now.
3. **Effects and totality as types**, with the external effect model on
   calls; delete `Facts/Moves` and `RemoveUnusedCall`; add LICM and
   `int-range-optimizations` to the round.
4. **Identified data types with typed constants** (mlir-idioms 1.4, 1.5):
   the prerequisite for layouts, ghosts and exhaustive matches.
5. **`!idr.nat`, ghost indices, ValueBounds on idr ops**; BindingTimes'
   heuristic and `knownNonZero` go. Frontend: read `detagabbleBy`, compute
   propositions.
6. **Ownership as types and uniqueness inference** on the DataFlow
   framework; the owned-stage interpreter, `idr.stage` and Borrow's
   fixpoint go.
7. **The representation pass** (representation.md), deciding layouts from
   the facts, including `tensor` for index-shaped data; raising structural
   recursion to linalg; One-Shot Bufferize, ownership-based deallocation
   and vectorization for tensors, idr-rc for the boxes that remain.
8. **LLVM facts at lowering** (can go any time after 4).

## Guards and special cases a better representation would remove

Each with the representation, and the MLIR mechanism where one exists.

- Translate/Cases.idr:71-74: a `BigT` match is a Nat match if any
  alternative is a constructor, else a literal match. Same for
  Terms.idr:78-87 (`succArg`), :226-236 (`natConstructor`),
  Emit/Bodies.idr:237-254 (`CaseNat`), Lower/Predecessors.cc (pred as
  `big.sub` 1). Representation: `!idr.nat`, whose type decides.
- Specialize/BindingTimes.cc:121-127: an Int counted down by a positive
  constant counts as decreasing, "unlike a Nat it may pass zero"; the whole
  interpreter (:102-162) re-derives size-change. Representation: Idris's
  descent facts in the function type; mechanism: the DataFlow framework.
- Translate/Cases.idr:91-95: "a match on an erased value with more than one
  alternative" is rejected. Representation: ghost indices plus the detag
  relation; mechanism: ValueBounds.
- Translate/Recursion.idr:57, 113-134: reads `sizeChange` only to reject,
  then drops it. Representation: keep it (fact 8).
- Dialect.cc:245-250 and Ops.cc:164-176: box-ness and tags must agree with
  their copies. Representation: identified types that carry both once.
- Ownership/ResetReuse.cc:19-25, Lower/Runtime.cc:147-154: the runtime
  exclusivity test. Representation: the `i1` indicator of fact 1;
  mechanism: canonicalization, and One-Shot Bufferize for tensors.
- Ownership/Borrow.cc:53: a q1 parameter is forced owned, the only use of
  q1 in any optimization. Representation: `!idr.own` in the signature;
  mechanism: a sparse backward DataFlow analysis instead of the fixpoint
  loop (Borrow.cc:57-61).
- Ops.cc:791-810: a closure with a linear capture must be applied or entered
  at once. Representation: `idr.closure` returns `!idr.lin<!idr.fn>` when a
  capture is linear, and the generic rule covers it.
- Ops.cc:392-398, Canonicalize/Field.cc, Apply.cc:17-26,
  Dialect.cc:149-171 (`throughLinear`, `readOnce`): every fold sees through
  `lin.enter`/`lin.use` pairs. Conjecture: a verifier rule on positions (a
  `!idr.lin` position filled by a plain value counts as that value's use)
  would let the pair ops and the helpers go; it needs a proof that no pass
  can then duplicate the value unnoticed.
- Ops.cc:20-46 (`knownNonZero`, `knownFinite`, `knownNonEmpty`): facts
  recomputed by chasing definitions, constants only. Mechanism:
  IntegerRangeAnalysis (non-zero is a range) and a DataFlow lattice for
  non-empty strings. Erased proofs that would license the same (`NonZero y`
  in `divNatNZ`, libs/base/Data/Nat.idr:53-61) are `!idr.erased` and carry
  nothing; a ghost fact type is a conjecture worth a prototype.
- Lower/Matches.cc:57-59: no default means the last case is the default.
  Representation: exhaustive matches (fact 9).
- Facts/Functions/Of.cc:15-19, Inherit.cc:9-19: a function without
  `idr.effects` "may do anything", and `partial` lives in a second
  attribute combined by hand. Representation: effects and totality as one
  typed property (fact 4); mechanism: MemoryEffectOpInterface.
- Dialect.cc:493 against Counting.cc:9-38: two definitions of "holds
  references". Representation: one type interface (mlir-idioms 3.5's
  `RuntimeLayoutTypeInterface`).
- Facts.idr:24-36, Programs.idr:62, 143: `Provenance` is written, never read.
  Keep it as a field of the typed function property, or delete it.
- Inline.cc:36-38, 107-108: the size rule ignores Idris's `%inline`.
  Representation: `Inline`/`NoInline` as function properties read by the
  profitability callback.

## Open questions

- Fact 2 against AGENTS.md: "Idris does types; MLIR does programs" puts the
  raising of Data.Vect's recursions to linalg on the MLIR side, fed by
  facts from the frontend (ghost lengths, size-change, uniqueness). Is a
  registry hook per Data.Vect function acceptable as a first step, or must
  the raising be generic from the start? Generic is the maximum; hooks are
  the path.
- Tensors of dialect types are legal (`TensorType::isValidElementType`
  admits non-builtin types, BuiltinTypes.cpp:433-439); memrefs of them need
  `MemRefElementTypeInterface` on `!idr.box` and friends, so a `Vect n (List
  a)` bufferizes only once the idr types implement it.
- Would `!idr.nat` stay compatible with idr-eval's reification and the
  runtime's single representation of each integer (idris_rt.h:88-92)? The
  small word of a Nat is the same word; only the type changes, so probably.
- Ghost values: does remove-dead-values drop ghost-only parameters that a
  later specialization needs? It drops unused `!idr.erased` ones today.
- Fact 10's propositions: a value is determined by its indices only when
  every constructor is detaggable by indices at every level. `Elem x xs` is
  not (two paths when `xs` has duplicates), so its position is information;
  LTE is. The frontend must compute it, never assume it of every Nat-like.
- How much of fact 4 survives idr-rc? Merging two calls before counting
  gives the merged result one more `idr.inc`; cheap, but to be measured.
