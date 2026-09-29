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
  (Translate/Instances.idr:382-409), fields (Translate/Types.idr:308-315),
  arrows (Types.idr:252-258), lambdas and lets (Translate/Terms.idr:309-323).
  Stored as `Binder = Gone | Held Use Ty` (Types.idr:117-118).
- **Emit keeps:** in types. `Gone` → `!idr.erased`, `Held Once` →
  `!idr.lin<T>` (the world stays `!idr.world`, linear by rule),
  `Held Many` → `T` (Emit/Types.idr:115-119, Emit/Monad.idr:244-247).
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
  Patterns.cc:144-150). Never earlier.
- **LLVM receives:** nothing. q1 removes no work anywhere (lmap above).

### 2. Erasure: `eraseArgs`/`safeErase` and `!idr.erased`

- **Idris computes:** `findErased` → `(eraseArgs, safeErase)`
  (TTImp/Elab/Utils.idr:19-58), stored at ProcessType.idr:171-180 and
  `updateErasable` (Utils.idr:61-73); fields at Core/Context/Context.idr:307-310.
  `safeErase` = positions whose value is determined by a detaggable
  unerased argument (`detagSafe`, Utils.idr:19-35).
- **Frontend reads:** the binder quantities directly (equivalent to
  `eraseArgs`: Translate/Closed.idr:240-251, Instances.idr:391-394).
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
  - a q1 parameter's pattern variables are only as linear as their fields
    (checked above), so uniqueness of a q1 list is of its first cell;
    inference must propagate it field by field ("the tail of a unique cell
    whose count is 1 is unique if the cell held the only reference to it"
    is not a static fact);
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
  (Translate/Programs.idr:184-189) into `Facts.terminating`
  (Programs.idr:210; its `provenance` is written, never read);
  `isCovering` into `Ctx.complete` (Programs.idr:200-203). `Impossible`,
  and `Unmatched` in a covering definition, become `Unreachable`; otherwise
  `Crash` (Translate/Cases.idr:33-49). Constructors the tree omits become
  alternatives of the same kind (Cases.idr:64-70).
- **Emit keeps:** `idr.total` (Emit/Attributes.idr:73; inherited by lifted
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
  positive constant counts as decreasing (Specialize/BindingTimes.cc:163-223,
  182-188).
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
  and `add 1` (Terms.idr:424-434); matches become `CaseNat`
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
  (Types.idr:341-350); `classify` makes them compile-time `DictParam`s
  keying the instance (Instances.idr:395-403); a runtime-chosen
  implementation is rejected (:400-401); matches on dictionaries select now
  (Cases.idr:77, 137-159).
- **Emit/passes/LLVM:** nothing left to keep: every method call is a direct
  call. Fully exploited.

### 8. Data type facts: newtype, enum, recursive, ConInfo, detagging

- **Idris computes:** ConInfo NIL/CONS/NOTHING/JUST/ENUM/RECORD/UNIT/ZERO/SUCC
  (Core/CompileExpr.idr:19-29; ProcessData.idr:291-390); newtype argument
  (`findNewtype`, :235-247, into `DCon newtypeArg`, Context.idr:94-103);
  detag positions (above); `mutwith`.
- **Frontend reads:** ZERO/SUCC only. Recursion it computes itself, per
  instance (Programs.idr:233-246), which is more precise than `mutwith`.
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
  (Frontend/Profile.idr:290-293).
- **Passes:** idr-inline decides by MLton's size rule alone (Inline.cc:36-38,
  107-108); `no_inline` comes only from loop breakers.
  `%transform "tailRecLength" List.length = List.lengthTR`
  (libs/prelude/Prelude/Types.idr:588) is ignored, so `length` is a
  non-tail recursion (list.ll:135-160).
- **LLVM receives:** nothing.

### 10. Primitive ranges: Int, Integer, Nat, Double, Char

- **Idris:** `PrimType` (Core/TT/Primitive.idr); meaning is the runtime's.
- **Frontend/Emit:** fixed widths with signedness on the op
  (Types.idr:54-97; Operations.idr:120-203); wrapping arith without
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
  (Programs.idr:256-292); forged worlds rejected (Profile.idr:392-395,
  Terms.idr:303).
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
| `idr.library` | LB, barely | only LoopBreakers.cc:204 (breaker choice) |
| `idr.effects` (on func) | LB | |
| `idr.stack` | LB | ConOp effects (Ops.cc:339), ResetReuse, lowering |
| `idr.origin` | half dead | its presence marks a clone (LoopBreakers.cc:200, Simplify.cc:115); its value is read only by idr-expect (Expect/Clones.cc:24) and duplicates `spec_key`'s origin; nothing checks the two agree |
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
| `idr.io.get_char`, `idr.io.exit` | **dead** | no producer: `IOOp = PutStr \| PutChar \| GetByte` (Types.idr:355-356); only tests and the lowering's list mention them (Lower/Patterns.cc:450). `io.exit` never returns yet yields a world |
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

## The 10 biggest unexploited facts, by payoff

1. **Uniqueness (the caller half of linearity).** Payoff: the README's
   promise, reuse without a test, no counts for values unique over their
   life. Representation: a parameter/value type `!idr.uniq<T>` computed by a
   call-graph fixpoint (review-external-2.md, steps 1-4), verified by the
   owned-stage walk: a `!idr.uniq` value is made by `idr.con`/`idr.reuse`
   or received as `!idr.uniq`, and is never `idr.inc`'d; `idr.reset`/
   `idr.take` of it have no exclusivity test.
2. **Nat-likes are naturals, and small.** Payoff: asymptotic. `plus`,
   `mult`, `minus`, `natToInteger`, `compareNat` are O(n) recursions over
   bigs today (list 01:181-196), where upstream rewrites them to O(1)
   (Constructor.idr:81-93); every loop over a Nat calls the big runtime.
   Representation: `!idr.nat` (non-negative; `pred` and zero tests inline on
   the small word; `big.pred` defined by type), registry hooks for the
   seven natHack functions (Faster kind, Chez-diffable), and for Fin and
   lengths of in-memory structures a word type `!idr.index` (a Fin bounded by
   a runtime length fits a word: the structure it indexes has that many
   cells in memory).
3. **Referential transparency of total, effect-free calls.** Payoff:
   general; `length xs` four times on every path (list 01:609-623). MLIR's
   CSE never merges `func.call`. Representation: calls of functions with
   `#idr.effects<none>` and `idr.total` as an op whose memory effects are
   derived from the callee's facts (or func.call's effects answered from the
   callee through an interface), so CSE and LICM treat them as pure before
   idr-rc.
4. **Index-shaped vectors.** Payoff: numeric code; `Vect 3 Double` is three
   linked cells with RC traffic (vect.ll:986-1060). Representation: keep the
   length as a ghost operand of the type, `!idr.box<@Vect, n>` with `n` an
   SSA ghost value (§2), so that a static `n` selects an unboxed product
   `!idr.data<@Vect$3>` (no cells, no tags) and a runtime `n` may select a
   contiguous layout when every use is index-compatible. AGENTS.md: indexed
   does not imply contiguous; this makes it a choice the compiler proves.
5. **Immutable cells, told to LLVM.** Payoff: load CSE across runtime calls
   in tight loops. Idris values never change after construction except under
   reuse, which writes a new value into a dead cell. Representation in the
   lowering: `!invariant.group` loads with a `launder.invariant.group` at
   `idr.reuse`; `nonnull` + `dereferenceable(cell size)` on box parameters
   and match-bound pointers; `!range [0, n)` on tag loads; `noalias` on
   fresh cells.
6. **ConInfo layouts.** Payoff: a pointer compare instead of a load and
   mask per match; one indirection less per recursive newtype.
   Representation: a verified layout property on `idr.data`
   (`#idr.layout<nullable @Nil>` for NIL/NOTHING-shaped boxes: the nullary
   constructor is the null pointer; newtype-by for single-field
   single-constructor recursive instances), read by Layouts.
7. **Detagging by indices.** Payoff: no tag tests where an index decides the
   constructor, and matches on erased indices with several alternatives
   compile instead of being rejected (Cases.idr:91-95). Representation: the
   data declaration carries, per constructor, the index pattern that selects
   it (from `detagabbleBy`), and matches on the ghost index of fact 4 fold.
8. **Size-change graphs, kept.** Payoff: BindingTimes becomes a read, its
   unproved `arith.subi` heuristic goes, and total functions whose recursion
   decreases a parameter get `mustprogress`/`willreturn` and a depth bound
   the stack pass can use. Representation: a per-parameter `decreasing`
   property in the function's type (a clone's parameters inherit it by the
   key's holes), verified to stay on a parameter that recursive calls pass a
   proper part of.
9. **Propositions have no content.** Payoff: `Dec (LTE m n)` is a Bool,
   `isLTE` does no big arithmetic, `No` holds no closure (list.mlir:46-48).
   A type all of whose constructors are selected by its indices, with fields
   that are themselves such types (LTE, not Elem: see Open questions), has
   at most one value per index; with its indices erased it carries only its
   tag. Representation:
   the frontend computes it (from `detagabbleBy`, recursively) and emits the
   field type as `!idr.erased` plus the tag, never `!idr.big`.
10. **Totality and effects, told to LLVM; and library-asserted transforms.**
    Payoff: modest per call, broad. Representation: lower `idr.total` +
    `idr.effects<none>` to `willreturn mustprogress nounwind`; read
    `%transform` rules from `Defs.transforms` into the registry as Faster
    hooks (tail-recursive `length`, `map`, `filter`, `++`), diffed against
    Chez like every hook.

## Guards and special cases a better representation would remove

- Translate/Cases.idr:71-74: a `BigT` match is a Nat match if any
  alternative is a constructor, else a literal match. With `NatT` distinct
  from `BigT`, the type decides. Same for Terms.idr:276-285 (`succArg`),
  :424-434 (`natConstructor`), Emit/Bodies.idr:237-254 (`CaseNat`),
  Lower/Predecessors.cc (pred as `big.sub` 1). Representation: `!idr.nat`.
- Specialize/BindingTimes.cc:182-188: an Int counted down by a positive
  constant counts as decreasing, "unlike a Nat it may pass zero".
  Representation: Idris's size-change fact on the parameter, or `!idr.nat`.
- Translate/Cases.idr:91-95: "a match on an erased value with more than one
  alternative" is rejected. Representation: detagging relation (fact 7).
- Translate/Recursion.idr:57, 113-134: reads `sizeChange` only to reject,
  then drops it. Representation: keep it (fact 8).
- Dialect.cc:245-250: box-ness must agree between declaration and type.
  Representation: one source (the type), or the declaration and a single
  nominal type.
- Ops.cc:164-176: tags must be 0..n-1 in order. Representation: derive the
  tag from the position; drop the attribute.
- Ownership/ResetReuse.cc:19-25 and Lower/Runtime.cc:147-154: the runtime
  exclusivity test. Representation: `!idr.uniq<T>` (fact 1).
- Ownership/Borrow.cc:53: a q1 parameter is forced owned. With `!idr.uniq`
  the decision is typed; without it this is the only use of q1.
- Ops.cc:791-810: a closure with a linear capture must be applied or entered
  at once. Representation: `idr.closure` returns `!idr.lin<!idr.fn>` when
  any capture is linear, and the ordinary linearity rule covers it.
- Ops.cc:392-398, Canonicalize/Field.cc, Apply.cc:17-26,
  Dialect.cc:149-171 (`throughLinear`, `readOnce`): every fold must see
  through `lin.enter`/`lin.use` pairs. The pair exists so that a value's
  linear journey stays visible (IdrOps.td:1025-1033). Conjecture: a
  verifier rule on positions (a `!idr.lin` position may be filled by a
  plain value, counted as that value's use) would let the pair ops go and
  the helpers with them; it needs a proof that no pass can then duplicate
  the value without the verifier noticing.
- Ops.cc:20-46 (`knownNonZero`, `knownFinite`, `knownNonEmpty`): facts
  recomputed by chasing definitions, constants only. Erased proofs that
  would license the same conclusions (`NonZero y` in `divNatNZ`,
  libs/base/Data/Nat.idr:53-61) are `!idr.erased` and carry nothing.
  Representation (conjecture): a fact-carrying erased type,
  `!idr.erased<#idr.nonzero<...>>`, whose presence folds the check.
- Lower/Matches.cc:57-59: no default means the last case is the default.
  Representation: exhaustive matches verified (cases ∪ default ⊇
  constructors), with impossible constructors listed as such.
- Facts/Functions/Of.cc:15-19: a function without `idr.effects` "may do
  anything"; `partial` lives in a second attribute (`idr.total`),
  combined by hand in Inherit.cc:9-19. Representation: one required
  `#idr.facts<...>` on every function with a body, keeping provenance
  (Idris's totality versus inferred effects) as a field, so absence is not a
  state.
- Dialect.cc:493 versus Counting.cc:9-38: two definitions of "holds
  references". Representation: one predicate, used by both.
- Facts.idr:24-36 and Programs.idr:62, 143: `Provenance` is written and
  never read.
- Inline.cc:36-38, 107-108: the size rule ignores 469 library `%inline`s.
  Representation: carry Idris's `Inline`/`NoInline` flags as function
  properties the inliner reads before its rule.

## Open questions

- Would `!idr.nat` stay compatible with idr-eval's reification and the
  runtime's single representation of each integer (idris_rt.h:88-92)? The
  small word of a Nat is the same word; only the type changes, so probably.
- Fact 4's ghost operands: MLIR has no ghost values; an erased SSA value of
  a new type `!idr.ghost<!idr.nat>` that lowers to nothing is the nearest
  fit. Does remove-dead-values drop ghost-only parameters that a later
  specialization needs? It drops unused `!idr.erased` ones today.
- Fact 9 needs care: a proposition's value is determined by its indices only
  when every constructor is detaggable by indices at every level. `Elem x
  xs` is not a proposition when `xs` has duplicates (two `There`/`Here`
  paths), so its position is information; LTE is one. The frontend must
  compute it, not assume it for every Nat-like type.
- How much of fact 3 survives idr-rc? Merging two calls before counting
  means the merged result gets one more `idr.inc`; cheap, but it should be
  measured.
