# QTT as representation: one graded type algebra for everything Idris 2 proves

Stream "qtt-representation". The user's words: "we need to be able to
aggressively optimize edwin brady's wet dream, representation first." Brady's
own words, closing the QTT paper: "We should not let the type checker keep
this information to itself!" (brady-2021-idris2-qtt, conclusion.tex).

This note designs the IR type system that keeps what Quantitative Type Theory
lets Idris 2 prove, so that a whole-program optimizer can use it. Each fact is
mapped onto the MLIR mechanism that already consumes it, wherever one exists.

**What it builds on, and does not repeat:**
- facts-ledger.md: the ledger of every Idris fact, and the audit of the
  dialect;
- memory-theory.md: linearity versus uniqueness, and the exclusivity design
  (`!idr.own`, `!idr.uniq`, `!idr.cell`, the foldable `i1`, the DataFlow
  lattice);
- mlir-ownership-types.md: the owned stage as types;
- representation.md: Nat, Fin and Vect representations, ghosts (R11), tensors
  (R12), collapsible families (R14);
- linear-libs.md: the linear libraries and their benchmark suite;
- architecture.md: the solver, the phases, and rule R1 ("where a fact lives");
- decision-linear-libraries.md: no language change, no library of our own.

**What is new here:**
- one type constructor with a product grade, in place of a family of
  wrappers;
- the reading of idr-rc as the elaboration of QTT's implicit structural rules;
- ghosts designed around what ValueBounds can actually see;
- erased proofs of order relations as `nuw`, with evidence (e1);
- match grades by Idris's `rigMult`;
- the steadfast census;
- grades that are transparent to value analyses;
- a staged roadmap in which every step has its consumer.

**Evidence.**
- Code: the pinned Idris 2 (`third_party/Idris2/src`, `libs/`), idris-mlir
  (`compiler/src`, `foreign/idr`) and the pinned MLIR
  (`.toolchain/llvm-project/mlir`).
- Papers, read in full: Brady 2021 (all its sections), Bernardy et al. 2018
  (the TeX), Marshall et al. 2022 and Marshall & Orchard 2024 (the text
  extracted from the stored PDFs).
- Experiments: `qtt-experiments.md` (e1, e2).

**What I could not read**, stated so no claim leans on it silently:
- McBride's "I Got Plenty o' Nuttin'" and Atkey's LICS 2018 QTT are not in
  `sources/papers`, and the egress proxy blocks their hosts (bentnib.org,
  strath.ac.uk).
- Granule's ICFP 2019 paper is not stored. Its core calculus is recapped in
  Marshall & Orchard 2024 §3, which I read instead.
- The stored Wadler 1990 is PostScript with bitmap fonts, so its text cannot
  be extracted. His claims are quoted through Marshall et al. 2022
  (pp. 349-350).

Where a claim about McBride or Atkey appears, it is what Brady and Marshall
report of them. It is marked as such.

## The questions

1. What does QTT let Idris 2 prove, fact by fact? Where is each proved, and
   can our frontend get it?
2. For each fact:
   - which IR carrier (a type, an op or an attribute), and why;
   - which verifier rule;
   - which optimizations it licenses;
   - which MLIR mechanism consumes it;
   - how it lowers.
3. Is there one type algebra that carries all of them? Graded `!idr.q<g, T>`,
   or separate wrappers?
4. How do grades survive specialization, inlining, defunctionalization,
   evaluation, MLIR's own passes and idr-rc?
5. In what order can this land so that every step is load-bearing when it
   lands, and what test or benchmark proves it?

## The answer in one page

### The global maximum

**One type constructor carries every quantitative fact:**

```
!idr.q<(u, p), T>       u ∈ U = {0, 1, ω}              Idris's usage grade: the future
                        p ∈ P = {·, borrow, own, excl}  ownership permission: the past
```

- **`u` is QTT's.**
  - It is the `{0, 1, ω}` semiring on every binder: parameters, fields,
    arrows, lets, case blocks and pattern variables.
  - Its addition and multiplication are Idris's `|+|` and `|*|`.
  - Its order is Idris's `rigSafe`: a value of grade `l` may fill a position
    of grade `r` only when `r ≤ l` (LinearCheck.idr:170).
- **`p` is Marshall's.**
  - It is the permission side of "Functional Ownership through Fractional
    Uniqueness": `excl` is `*A`, `own` is `&1` with a count, `borrow` is
    `&f` with `f < 1`, and `·` means no reference obligation.
  - It exists only in the owned stage, and only on counted types.
- **Spellings are sugar over one C++ class.** The canonical forms are:
  - `T` for `(ω, ·)`;
  - `!idr.lin<T>` for `(1, ·)`;
  - `!idr.erased` for an anonymous `(0, ·)`;
  - `!idr.ghost<T>` for `(0, ·)` with identity;
  - `!idr.own<T>` and `!idr.uniq<T>` for `(ω, own)` and `(ω, excl)`;
  - `!idr.q<(1, own), T>` in general.
- **Illegal states are not constructible.** The type's verifier admits only
  canonical grades:
  - no nesting;
  - `u = 0 ⇒ p = ·`;
  - `p ≠ · ⇒ T` is counted;
  - the world only at `(1, ·)`;
  - `(ω, ·)` is spelled `T`.

**The theory it implements.**
- The value stage is a *graded base*, like QTT and Linear Haskell: a grade on
  every binder.
- The owned stage is a *linear base* with a uniqueness modality, like
  Marshall's LCU and Granule. Marshall & Orchard 2024 §3 name the two styles
  and cite work on relating them.
- **idr-rc is the translation between them.** QTT's context addition
  `Γ1 + Γ2` is contraction, and its scaling by `0` is weakening. Both are
  implicit in the value stage. Perceus makes them explicit, as `dup` and
  `drop`.
- So Idris's `u = 1` is a *proof that no contraction of this binder is ever
  needed*. The owned-stage verifier can hold idr-rc to that proof (rule V6
  below).
- Uniqueness is the other half, a fact about the past, which Idris does not
  prove (memory-theory §1). The compiler infers it into `p`.

**Every grade has a consumer**, and wherever one exists it is MLIR's:

| grade or companion | read by |
|---|---|
| `u = 0` | the 1:0 type conversion; ghosts feed `tensor.dim` and ValueBounds once realized |
| `u = 1` | the verifier (no second use, no `dup`); one-shot closures; the programmer's demand; the steadfast census |
| `p = excl` | the foldable `i1` (canonicalization, SCCP); One-Shot's `writable` arguments; LLVM `noalias` |
| totality and effects on `!idr.fn` | LICM, CSE, DCE, through `ConditionallySpeculatable` and `MemoryEffectOpInterface` |
| erased order proofs (ghost relations) | `nuw`/`nsw`, IntegerRangeAnalysis, ValueBounds |

### Why one constructor and not wrappers

The decision is argued in full below. The core is canonicity:
- Wrappers compose freely. The dialect therefore already guards against the
  states they admit:
  - `LinType::verify` rejects `lin<lin>`, `lin<erased>` and `lin<world>`
    (Dialect.cc:130-136);
  - `Idr_CountedType` admits `lin<i64>` (facts-ledger).
- The owned stage would add `own<lin<T>>` versus `lin<own<T>>`: two spellings
  of one state.
- A product grade has one spelling per state. The semiring operations the
  passes need live in one place:
  - `rigMult` for fields;
  - capture scaling for closures;
  - subsumption at calls.

MLIR's own precedent for a fact carried in a type's parameter is
`tensor<…, #encoding>`, the sparse tensor dialect's encoding on a builtin
type. Builtin scalars have no such slot, so a wrapper with a grade parameter
is the idiom that works for `i64` and `!idr.box` alike.

### The table: each fact, its carrier, and who reads it

| Idris fact | where Idris proves it; frontend | IR carrier | verifier rule | licenses | MLIR consumer | lowering |
|---|---|---|---|---|---|---|
| grade on a parameter, lambda, let or arrow | `RigCount` on binders (Core/TT/Binder.idr), `linearCheck`; read by `binderOf` (Resolve.idr:84) | the position's type `!idr.q<(u,·),T>` | V2 use bound; V3 fill-by-order (`func.call`'s own type check) | one-shot closures; demand | MLIR's call, return and branch verifiers (type equality) | grades stripped, 1:1 |
| grade on a constructor field | Pi binders of the data constructor; read (Translate/Types.idr:308-315) | `idr.ctor` field type | V5: a match region argument = field grade · scrutinee grade (`rigMult`, ProcessDef.idr:219) | deep linearity (LList spine); the steadfast census | none; ours | stripped |
| case-block grades | `getArgUsage`/`updateUsage` rewrite the case block's type (LinearCheck.idr:440, 593); already read (e1) | parameter types | as for parameters | unused linear environment becomes q0 and absent | `remove-dead-values` | 1:0 |
| quantity 0, anonymous (types, dictionaries, content-free proofs) | `eraseArgs` (Context.idr:307) | `!idr.erased` (ConstantLike) | V7 confinement | absent at runtime | 1:0 type conversion | nothing |
| quantity 0 with identity (indices, relational proofs) | the same binders; the frontend knows which indices a fact mentions | `!idr.ghost<T>` block arguments or fields, `idr.erase %v`; never ConstantLike when symbolic | V7, V8, V9 | "erased is not constant" by construction; relational facts | realized into `tensor.dim`/`index`, then ValueBounds and IntegerRangeAnalysis | 1:0 |
| erased order proof `(0 _ : LTE n m)` | an LTE-shaped family (recognized by shape, like `calcNaty`) | `idr.fact.le %n, %m` over relevant or realized values (ValueBoundsOpInterface) | operands `index`/integer or ghost | `subi nuw`; unchecked `pred`; trip counts | ValueBounds, `arith` overflow flags, IntegerRangeAnalysis | deleted; `nuw` stays on the arithmetic |
| `%World` | primitive, linear by `PrimIO` | `!idr.world`, intrinsic `(1,·)` | V2; world only at `(1,·)` | ordering only | IO resource effects | 1:0 |
| linear resources (LIO, sessions, typestate) | `1` binders; indices at q0 | grades plus q0 indices; LIO's `Usage` becomes a clone key | as above | typestate at zero cost; one-shot continuations | inliner, after specialization | stripped |
| uniqueness, from linear creation | none in Idris; follows by induction when every binder of a type is 1 (Wadler's steadfast) | the census over grades, then `excl` | V6; `excl` needs a folded provenance | untested reuse; no counting for the type | canonicalization of the `i1` | `excl` → `noalias` |
| uniqueness, from whole-program callers | none; inferred | `excl` at function boundaries; `idr.exclusive` `i1` inside | memory-theory §6.5 | static reuse, in-place update, count-free | DataFlow framework (interprocedural sparse), SCCP, canonicalize | `noalias`, plain stores |
| borrowing, fractional permissions | none in Idris; its erased mentions are 0-borrows (N5) | `p = borrow` (plain `T` in the owned stage); `idr.borrow` scoped by SSA | borrow liveness | the fractional join (read, then update) | none; ours | nothing |
| totality, coverage, size-change | `checkTotal`, coverage, `sizeChange`; read (Programs.idr) | effect and totality property on `!idr.fn` and functions; exhaustive matches | effects agree with the callee | LICM, CSE, DCE of pure total calls; `will_return` | `ConditionallySpeculatable`/`MemoryEffectOpInterface` external models on `func.call`; LICM `isPure` | `will_return`, `memory_effects` |
| Nat, Fin, Vect indices as ranges and lengths | ZERO/SUCC `calcNaty`, constructor return indices | `!idr.nat`; `idr.fact.lt %i, %n`; `tensor<?xT>` with dim = the realized ghost | constants within bounds | narrowing to `index`; no bounds work | IntegerRangeAnalysis (`setToEntryState`), ValueBounds, `tensor.dim` | `index`/`i64`, `range` |
| data facts: detag and collapsible, `!*`, `Res`, newtype with the world | `safeErase`, `detagabbleBy`, `newtypeArg` (Context.idr:95-113, 307-310) | field grades; erased collapsible fields; the newtype layout | as above | absent proofs; derivable fields | DCE | 1:0 |

The rest of this note gives the evidence, then each fact in turn, then how
grades survive transformations, then the decision on one algebra, and the
roadmap.

## Part 1. What QTT proves, and what Idris 2 does with it

### 1.1 The theory, as the sources state it

- **Quantities on binders, not on types or results.**
  - "In QTT, multiplicities are associated with *binders*, not with return
    values or types. This is a design decision of QTT, rather than of Idris,
    and has the advantage that we can use a type linearly or not, depending
    on context" (Brady, protocols.tex:15-19).
  - The IR consequence: a grade belongs to a *position* (a parameter, a
    field, a capture, an arrow's domain), and an SSA value inherits it from
    the position it was bound at. A function result has no grade (memory-theory N3).
- **The semantics of 1.**
  - "if an expression `f x` is evaluated exactly once, `x` is evaluated
    exactly once" (linearity.tex:9-13).
  - "A function which takes an argument with multiplicity 1 promises that it
    will not share the argument in the future; there is no requirement that
    it has not been shared in the past" (erasure.tex:30-33).
- **The semantics of 0.**
  - "not available at run time"; "Erased arguments are still relevant *at
    compile time*" (idris2.tex:369-372).
  - "the `0` multiplicity for `d` means that we can still *talk* about it"
    (docs tutorial/multiplicities.rst, the Door example).
  - Uses in erased positions do not count (linearity.tex Remark, the
    `Ordered xs` example). This is memory-theory's N5.
- **The semiring.**
  - QTT allows any semiring, and Idris 2 fixes `{0, 1, ω}` (erasure.tex:7-15).
  - Brady's future work asks for quantity polymorphism and other quantities
    "like Granule" (conclusion.tex).
  - Bernardy et al. 2018 §"Extending multiplicities" sketch a borrowing
    multiplicity `β` with `1 < β < ω` and `β+β = 1+β = 0+β = 1+1 = β`
    (hlt.tex:3057-3100). Borrowing thus appears as a *grade* in their design.
  - Marshall & Orchard 2024 grade the *uniqueness* side instead (`&p`).
- **Graded base and linear base.**
  - Marshall & Orchard 2024 §3 ("Note on Linear Haskell") distinguish systems
    where "all function types come with a grade (sometimes called 'graded
    base')" from those where "values are linear by default and graded values
    are wrapped inside a modality (called 'linear base')".
  - Idris is graded-base. Our value stage is graded-base, and the owned stage
    (after `dup` becomes explicit) is linear-base.
- **Granule's structural rules** (Marshall & Orchard 2024 §3.2).
  - Context addition adds grades: this is contraction.
  - `0 · Γ` in the variable rule: this is weakening.
  - `der` makes a linear assumption from a grade-1 one: this is dereliction.
  - `approx` coarsens `r` to `s` when `r ⊑ s`: this is subsumption.
  - Promotion carries a side condition, `¬resourceAllocator(t)`: promoting
    an allocator in call-by-value would share one allocation.
  - The IR has the same hazard, and closes it by effects: `idr.con` has an
    `Allocate` effect, so CSE never merges two fresh cells (memory-theory
    §6.4).
- **Linearity versus uniqueness.**
  - "uniqueness typing is a *non-aliasing analysis* while linear typing
    provides a *cardinality analysis*. The former aims at in-place updates
    and related optimisations, the latter at inlining and fusion"
    (hlt.tex:2884-2889). So uniqueness serves in-place update, and
    linearity serves inlining and fusion.
  - Their future work proposes "to use the multiplicity annotations … as
    cardinality *declarations*" for inlining (hlt.tex:3030-3055). That is
    the one optimization that `u = 1` licenses directly (§2.3 below).
- **Steadfastness.**
  - Wadler 1990, as Marshall et al. 2022 quote it: "values of linear type
    have exactly one reference to them, and so require no garbage
    collection" (p.349). That holds only in systems where linear and
    non-linear worlds are separate.
  - "dereliction means we cannot guarantee a priori that a variable of
    linear type has exactly one pointer to it" (p.350, quoting Wadler's later
    article).
  - Steadfast types restrict dereliction and promotion to recover uniqueness
    (p.350).
  - This is the theory behind the steadfast census (§2.6).
- **McBride and Atkey, second hand.**
  - Brady: QTT is Atkey's system "following initial ideas by McBride"
    (idris2.tex:355-356).
  - Marshall & Orchard: `{0,1,ω}` "for capturing linear logic with
    `!A ≡ □ω A` [McBride 2016]" (m24 §3.2).
  - What the design uses from them is exactly what Brady states: binders
    carry grades, and the 0-fragment is unrestricted "contemplation". I
    could not check Atkey's realisability semantics for the stronger claim
    that 0-graded data is *irrelevant to the result*. The design needs only
    the weaker, operational claim that Idris's erasure check enforces (a q0
    binder is never inspected at runtime), which the frontend already
    relies on.

### 1.2 What Idris 2 checks, precisely (upstream code)

Memory-theory §2 covers variables, application, lambdas and pattern variables.
What this stream adds:

- **Let.**
  - `lcheckBinder … (Let fc rigc val ty)` checks the value at
    `rig |*| rigc` (LinearCheck.idr:374-377).
  - A `let 1` reaches the compiled Core: e1's
    `let 1 = Main.dropHead(#0)`.
  - Brady: "The multiplicities of the `let` bindings are inferred from the
    values being bound" (linearity.tex, io_bind).
- **Case blocks.**
  - `checkCase` checks the scrutinee at ω, and on a `LinearMisuse` retries at
    1 (TTImp/Elab/Case.idr:384-407).
  - The case block is a separate definition. Its environment variables that
    are linear become erased in the *local* environment (`mkLocalEnv`,
    Case.idr:269-276) and are passed as arguments.
  - When the caller is linearity-checked, `getArgUsage` infers each linear
    argument's use across all clauses as `Use0`, `Use1`, `UseKeep` or
    `UseAny`, rejecting inconsistent branches (LinearCheck.idr:440-560).
  - `updateUsage` then *rewrites the case block's type*: `Use0` becomes
    erased and `Use1` becomes linear (:593-603).
  - e1 shows the result in the compiled Core:
    `case block 843 in pick (w Bool) (1 Main.L)`. The frontend reads it like
    any type, so **case-alternative grades already reach the IR**, including
    Idris's inference that an unused linear environment variable is
    quantity 0.
- **As-patterns.**
  - `lcheck … (As …)` checks both sides (LinearCheck.idr:331-335).
  - `getCaseUsage` looks through `As` to the pattern (:448-449).
  - The frontend compiles `As` to its pattern (Terms.idr:130). The as-name is
    the scrutinee itself (e1's `asPat`: `MkPair(#2, #1)`), so no cell is
    rebuilt. This is already optimal, and there is nothing to carry.
- **Pi invariance.** Function types are invariant in their argument's
  quantity (Core/Unify.idr:1059, `if cx /= cy`). So `!idr.fn` needs no
  subtyping on grades.
- **Definition multiplicity.**
  - `GlobalDef.multiplicity` (Context.idr:313) marks `0`-definitions, which
    are types only.
  - The stock backends skip them (Compiler/Common.idr:181, 241). The frontend
    only follows runtime references, so it never sees them.
- **The stock backends use quantities only for erasure.**
  - `grep isLinear|linear|RigCount|multiplicity src/Compiler` finds only the
    definition-multiplicity tests above.
  - `eraseArgs` drives `mkDropSubst` (CompileExpr.idr:33-35, 223).
  - RefC's reuse map (RefC.idr:208-218) is Perceus-like and runtime-tested.
    It reads no quantity.
  - **No Idris backend exploits linearity.**
- **Other quantity-derived data in `GlobalDef`.**
  - `safeErase`: positions "collapsible relative to non-erased arguments"
    (Context.idr:308-310, computed by `detagSafe`, TTImp/Elab/Utils.idr:19-35).
  - `detagabbleBy` on type constructors (:110).
  - `newtypeArg : Maybe (Bool, Nat)`, whose Bool is "no %World in the
    structure, … safe to completely erase" (:95-103).
  - `inferrable`, `specArgs` (:311-312).
- **Erased matches.**
  - The docs: "it is an error to try to pattern match on an argument with
    multiplicity 0, unless its value is inferrable from elsewhere"
    (multiplicities.rst, `badNot` and `sNot`).
  - e2 shows that Idris's case tree then matches the *relevant* argument.
  - The erased-match guard (Cases.idr:95) is reached only when the tree
    splits on an erased index. That needs the detag relation (§2.8).
- **Parametricity.** "a function is *only* parametric in `a` if `a` has
  multiplicity `0`" (multiplicities.rst, `notId`). §2.12 covers it.

### 1.3 What the libraries encode with quantities

- **`libs/linear`.**
  - `-@` is `(1 _ : a) -> b`, and `!*` is `MkBang : a -> !* a`, an ω field
    in a wrapper (Data/Linear/Notation.idr).
  - `Consumable` and `Duplicable` are interfaces. `Consumable Int` is
    `believe_me (\ 0 i => ())`, with the comment "crucially we don't have
    `Consumable World`" (Data/Linear/Interface.idr).
  - `Copies n x` is `n` linear copies of *the same* value, a Nat-graded
    exponent (Data/Linear/Copies.idr).
  - `LList` and `LVect` have linear fields.
- **LIO** (Control/Linear/LIO.idr).
  - `data Usage = None | Linear | Unrestricted` is a grade *as a runtime
    value* (:18).
  - `ContType` computes the continuation's binder grade from it (:63-65).
  - `Bind {u_act : _}` is runtime-relevant, and `runK` matches on it
    (:84-86).
  - Brady: "`u_a` is run time relevant. However, in practice it is removed by
    inlining" (protocols.tex).
- **`libs/papers` Data/Linear/Inverse.** `Inverse a = a -@ ()`: linear
  continuations as data, which are one-shot closures.

### 1.4 What idris-mlir keeps today

- **Frontend.**
  - `Binder = Gone | Held Use Ty` (Types.idr:118), with `useOf` and
    `binderOf` (Resolve.idr:78-85).
  - Lets carry `Use` (Terms.idr:111-120).
  - `Quantity = Q0 | Q1 | QW` exists for registry shapes (Types.idr:21).
- **Emit.**
  - `binderType`: `Gone` → `!idr.erased`, `Held Once` → `!idr.lin<T>`
    except the world (Emit/Types.idr:36-40, Monad.idr:74-77).
  - `coerce` writes `lin.use` and `lin.enter` between modes
    (Operations.idr:47-58).
  - Every erased value is the one `idr.constant #idr.erased`
    (Operations.idr:68-70).
- **Dialect.**
  - `LinType` (IdrOps.td:86-98) and `LinType::verify` (Dialect.cc:130-136).
  - `quantityOf`: erased is 0; lin and world are 1 (Dialect.cc:138-142).
  - `LinearUses` counts uses on the worst path, and a repetitive region
    counts twice (Dialect.cc:324-395). `verifyLinearity` applies it
    (:397-420).
  - `lin.enter` and `lin.use` allocate on `LinResource`, so CSE never merges
    them. Their folders cancel pairs (IdrOps.td:1022-1055).
  - A closure with a linear capture must be applied or entered at once, a
    special case (Ops.cc:794-808).
  - `bindsField` admits binding an ω field linearly (Ops.cc:587-592).
- **Passes.**
  - The specializer keeps a linear leaf only if its shape dies at the call
    (Specialize.cc:186-190), and treats erased values as closed
    (Specialize.cc:163).
  - Defunctionalization keeps linear slots (Defunctionalize.cc:882, 959).
  - Borrow inference keeps q1 parameters owned (Borrow.cc:53).
  - `idr-expect quantities-kept` checks that no parameter or field widens
    (Expect/Quantities.cc; tests/idr/expect/quantities.mlir).
- **Lowering.** Lowering strips all of it. q1 removes no work anywhere
  (facts-ledger §1, review-external-2).

### 1.5 MLIR facts that shape the design (pinned tree)

- **ValueBounds sees only `index`/integer or shaped values.**
  - `ValueBoundsOpInterface` bounds "index-typed and/or shaped value-typed
    results/block arguments", and a block argument must belong to an entry
    block (Interfaces/ValueBoundsOpInterface.td:14-60).
  - The constraint set asserts index-or-integer, or shaped
    (lib/Interfaces/ValueBoundsOpInterface.cpp:108-140).
  - **A custom ghost type cannot be a ValueBounds variable.** §2.8 designs
    around this.
  - The upstream models are in arith, affine, scf, tensor, memref, linalg
    and gpu (the `*/IR/ValueBoundsOpInterfaceImpl.cpp` files).
- **IntegerRangeAnalysis is non-relational and seeds entry states by an
  override.** `setToEntryState` (Analysis/DataFlow/IntegerRangeAnalysis.h:74)
  can be overridden to seed from types; mlir-idioms §6.1 covers the rest.
- **LICM hoists only `isPure` ops**, that is memory-effect-free *and*
  speculatable (Transforms/Utils/LoopInvariantCodeMotionUtils.cpp:117). So
  totality has a direct upstream consumer: `ConditionallySpeculatable`.
- **`func.call` declares no `MemoryEffectOpInterface`.** Its traits are
  `CallOpInterface, MemRefsNormalizable, SymbolUserOpInterface`
  (Dialect/Func/IR/FuncOps.td). An external model can therefore attach
  effects and speculatability.
- **The interprocedural DataFlow framework** joins arguments over call sites
  (lib/Analysis/DataFlow/SparseAnalysis.cpp:263, `visitCallableOperation`).
- **LLVM attributes are available.**
  - `will_return`, `memory_effects` and `no_unwind` on `llvm.func` and
    `llvm.call` (LLVMOps.td:860-861, 2043-2064).
  - `llvm.noalias`, `llvm.nonnull`, `llvm.dereferenceable` and `llvm.range`
    as argument attributes (LLVMDialect.td:48-59).
- **The bufferization pipeline** is in the pin: `one-shot-bufferize`,
  `ownership-based-buffer-deallocation`, `buffer-deallocation-simplification`
  and `promote-buffers-to-stack` (Bufferization/Transforms/Passes.td:14, 155,
  389, 572).
- **No MLIR linear-type verifier exists.** Ours runs after every pass, so any
  upstream pass that broke linearity would be caught.
  - CSE cannot merge `lin.*`: they are `MemAlloc`.
  - LICM cannot hoist them: they are not `isPure`.
  - A region that repeats counts twice in `LinearUses`.

## Part 2. The facts, one by one

Each fact gives: the proof and the frontend's access; the carrier; the
verifier rule; what it licenses; the MLIR consumer; the lowering.

The verifier rules V1-V9 are defined once, in §3.2.

### 2.1 Grades on parameters, lambdas, lets and arrows

- **Proof and access.** `RigCount` on every `Pi`/`Lam`/`Let` binder, checked
  by `linearCheck`. The frontend reads it already (§1.4). Nothing is missing.
- **Carrier.** The position's type, `!idr.q<(u,·),T>`.
  - A parameter's grade is its block argument's type.
  - An arrow's grade is inside `!idr.fn<(!idr.q<…>) -> (…)>`.
  - A let is an SSA value entered at its grade, as today.
  - *Why a type:* a type is the one place no pass can drop a fact (AGENTS.md),
    and MLIR's own verifiers then check it at every call, return and branch
    for free: `func.call` requires operand types equal to parameter types.
- **Verifier.**
  - V2: at most one runtime use per path for `u = 1` (today's `LinearUses`).
  - V3: a value fills a position of equal type. The only grade changes are
    explicit ops: `lin.enter` (dereliction, ω→1), `lin.use` (the one use,
    1→ω), `idr.erase` (anything→0).
- **Licenses.**
  - By itself, in a strict language with first-order values, nothing: an
    argument is already a value, so no work is duplicated.
  - Its payoff is through closures (§2.3), the census (§2.6), the demand
    (memory-theory §6.11) and V6 in the owned stage.
  - This is exactly Bernardy's reading: linearity is a cardinality
    declaration, and cardinality matters for *unevaluated* things, which in
    Idris are closures and `Lazy`.
- **MLIR consumer.** The builtin call, return and branch verifiers.
- **Lowering.** Grades are stripped, 1:1.

### 2.2 Grades on constructor fields, and the match rule

- **Proof and access.**
  - The data constructor's Pi binders. The frontend reads them
    (Translate/Types.idr:308-315), and Emit writes them into `idr.ctor`'s
    field types.
  - The *pattern variable* rule is `rigMult c rig`: field grade times
    scrutinee grade (TTImp/ProcessDef.idr:219).
  - Its consequences are opposite in the two directions:
    - a linear field of an ω scrutinee is ω (the docs' `getLin : Lin a -> a`
      example: "x is unrestricted");
    - an ω field of a linear scrutinee is ω (memory-theory's `twoTails`).
- **Today.**
  - Emit uses the scrutinee before the match (`lin.use`), since match
    scrutinees are plain (Emit/Bodies.idr:51-54).
  - The region binds each field at the *field's* grade.
  - `bindsField` additionally admits binding an ω field at 1, which Idris
    never does (facts-ledger audit).
  - So a q1 field of an ω scrutinee is bound at 1. That is stricter than
    Idris but sound.
  - The scrutinee's grade is lost at the match, which matters for the next
    point.
- **Carrier.**
  - The match takes its scrutinee *at its grade*: `idr.match %xs :
    !idr.lin<!idr.box<@LList>>` consumes it.
  - Region argument `i` has type `q(g_scrutinee · g_field_i, T_i)`.
  - *Why:* this is the only rule under which deep linearity is visible in
    the IR. A q1 `LList` binds its tail at `1·1 = 1`, all the way down the
    spine. The steadfast census (§2.6) and exclusivity (memory-theory §6.2,
    "why deep") need exactly that.
- **Verifier.** V5: region argument grades equal `rigMult`. It replaces
  `bindsField`, a guard, with a computed type.
- **Licenses.**
  - Deep linearity: every cell of a q1 `LList` reached by matching is
    itself q1.
  - With freshness (§2.6), every cell is exclusive, with no per-level test.
    That is the static in-place path for `llist-reverse`, `llist-map` and
    `llist-bubble` (linear-libs §3, items 1, 4, 5).
- **MLIR consumer.** None; the grade algebra is ours. A match already
  implements `RegionBranchOpInterface`, so region arguments keep their types
  through every upstream control-flow pass.
- **Lowering.** Stripped.

### 2.3 Grades on arrows and closures: one-shot functions

- **Proof and access.**
  - A lambda checked in an ω context erases linear variables from its scope
    (`eraseLinear`, LinearCheck.idr:234-239). So a closure that captures a
    q1 value can only be used linearly (memory-theory A4).
  - Arrow grades are exact, by Pi invariance.
  - The frontend has both: it builds `Lam` with a `Binder`, and knows the
    captures' binders.
- **Carrier.**
  - `idr.closure`'s result type is `!idr.lin<!idr.fn<…>>` whenever a capture
    has `u = 1`.
  - That is QTT's lambda rule read as a type: a closure used `k` times uses
    its captures `k` times, so a q1 capture forces the closure to `u ≤ 1`.
  - `Lazy` of a q1 value is the same (`lcheck … (TDelay …)`,
    LinearCheck.idr:340, checks the value at the context's grade).
- **Verifier.** V4: the closure's grade is at most the minimum of its
  captures' grades. This replaces the special case at Ops.cc:794-808
  ("applied where it is made, or entered into a linear type") with the
  generic V2 on the closure's own type.
- **Licenses.**
  - **Moves instead of copies at the apply.** A q1 closure is consumed by its
    apply. After defunctionalization the apply is a match that takes the
    closure sum apart: the captures move out, with no `inc`, and the closure
    cell is dead after the match, so it can be reset and reused. Today apply
    *borrows* its callee (Counting.cc `useOf`), so every capture of even a
    one-shot closure is inc'd (memory-theory pitfall 6).
  - **Inlining with no duplication risk.**
    - A q1 continuation that defunctionalization resolves to one label is
      called at most once per evaluation of its creator.
    - If it is also created at exactly one site, the callee is a
      continuation in Fluet and Weeks' sense and can be contified.
    - This is the cardinality use Bernardy et al. propose, made checkable.
    - LIO's `Bind` continuations and `io_bind`'s `k` are all q1
      (PrimIO: `io_bind : (1 act : IO a) -> (1 k : a -> IO b) -> IO b`).
- **MLIR consumer.** The upstream inliner, with the profitability callback
  reading the grade: a q1 callee reached once is always profitable.
- **Lowering.** Stripped. The closure representation is defunctionalization's.

### 2.4 Lets and case alternatives

- **Proof and access.** Covered by 2.1 and 2.2, plus the case-block grades of
  §1.2, which the frontend already receives (e1).
- **Carrier, verifier, consumers.** As 2.1 and 2.2.
- **Worth making explicit.**
  - Case blocks inferred `Use0` become quantity-0 parameters. `remove-dead-values`
    already deletes them.
  - The inferred `Use1` makes an environment variable that is linear in the
    outer function linear in the case block. Deep linearity survives Idris's
    case-block lifting, and that is what `llist-bubble` (linear-libs item 4,
    "the canary for reuse across Idris case blocks") depends on.
  - architecture.md step 2, case blocks as regions or join points, must keep
    these grades on the join point's block arguments. A join point is a
    block, and its arguments are typed, so it does.

### 2.5 Linear resources as zero-cost state: `%World`, LIO, sessions

- **Proof and access.**
  - **World.** `PrimIO a = (1 x : %World) -> IORes a` and
    `MkIORes : (result : a) -> (1 w : %World) -> IORes a` (linearity.tex,
    io_bind). Only the root creates a world (Registry/Recognized.idr).
  - **LIO.** Its `L` tree and `Usage` values (§1.3).
  - **Sessions.** `Channel : Actions -> Type` with the protocol at q0 and the
    channel at 1 (sessions.tex).
  - **ATM and Door typestate.** The state is a q0 index; the handle is 1
    (protocols.tex; multiplicities.rst).
- **Carrier.**
  - The world is `!idr.world`, whose grade is intrinsically `(1,·)`. V1
    rejects a world at any other grade, which replaces `modeOf Once WorldT = Plain`
    (Monad.idr:75) and `LinType::verify`'s world case with one rule.
  - A typestate index is `!idr.erased`, or a ghost when a fact mentions it.
  - LIO's `Usage` is a runtime value that selects a *type*. The IR cannot
    carry a type chosen at runtime, so it becomes a specialization key: a
    construction site's `u_act` is static. linear-libs §4.3 already proposes
    splitting `Bind` per usage at the Idris side. With grades, each split
    constructor's continuation field has a closed grade, `0`, `1` or `ω`.
- **Verifier.** V1 (the world is `(1,·)`); V2.
- **Licenses.**
  - *Zero cost* means three things, and the types give all of them.
  - **The state costs nothing.** The index is q0, so it has zero components
    (Layout.cc:103-104). An abstract resource with no relevant fields is
    UNIT-shaped.
  - **The protocol costs nothing.** The ordering is data dependence on q1
    handles, which is exactly what SSA already is. No `IO` sequencing is
    needed for a linear resource (the Door section of the docs: "we don't
    need to run operations on that resource in an `IO` monad").
  - **The interpreter costs nothing.** LIO's `runK` over a statically known
    `L` tree specializes away. Its continuations are q1, so §2.3 lets them
    be inlined or contified, not allocated. Target: linear-libs item 7,
    `lio-resource`: no `Bind`/`Pure1`/`Action` cells, and the counter in a
    register.
  - A world never enters a closure (Ops.cc:792-793). With grades this is V4
    as a special case: a world capture is q1, so the closure is q1.
- **MLIR consumer.**
  - IO ordering: the `IOResource` effects.
  - The typestate: nothing needs to consume it, because it costs nothing by
    construction.
- **Lowering.** 1:0 for the world and the indices.

### 2.6 Uniqueness: from linear creation, and from whole-program callers

memory-theory.md designs exclusivity. This section states how the algebra
carries it, and adds one Idris-derived source, the census.

**(a) From linear creation: the steadfast census.**
- **Proof.**
  - Suppose that in the whole monomorphic program every *binder position*
    of type `T` has `u = 1`: parameters, fields, captures and lets.
  - Suppose also that every *value* of `T` is created by a constructor, not
    a constant.
  - Then dereliction never applies to `T`, since no ω binder of `T` exists
    to derelict from. By induction on execution, every value of `T` is
    referenced once. This is Wadler's steadfast type (Marshall et al. 2022,
    p.350).
  - It is protocols.tex's argument for `newArray` ("if this is the only way
    of constructing an Array, then all arrays are guaranteed to be used
    linearly, so we can have in-place update"), stated about the IR's
    positions instead of a library's promise.
- **Access.**
  - The census reads the grades of every position of `T` in the module:
    function types, `idr.ctor` field types, `!idr.fn` domains, and match
    region arguments (by V5).
  - A call *result* has no grade, so the census counts a result as fine
    only when it is immediately entered into a q1 position.
  - It is a module walk over types, cheap and exact, with no dataflow.
- **Carrier.**
  - A type that passes the census is *declared steadfast*.
  - The exclusivity analysis (memory-theory §6.5) then starts every value of
    it at `excl` instead of `⊥` and never needs a join.
  - Its failure is a *demand violation*: the programmer wrote only q1
    binders for `T`, so a site that is not exclusive gets a remark naming it.
    This is memory-theory's P3, made automatic for types whose author
    evidently meant it: `LList`, `LinArray`, `ATM`, `Channel`.
- **Soundness boundaries.**
  - Escape hatches are already rejected (memory-theory §7.1-7.2).
  - A leaking library (decision-linear-libraries: contrib's `newArray`)
    fails the census, because its escape creates an ω binder of the type.
    So the census never trusts an API; it reads the program.
  - Compiler-made sharing breaks steadfastness and must be excluded:
    compile-time constants, `idr.stack` cells, and CSE. A census type's
    constructors must never be folded into constants: `materializeConstant`
    refuses `excl`.
- **Verifier.** V6 in the owned stage: no `idr.dup` whose operand has
  `u = 1`. For a census type this becomes "no `dup` of `T` at all", checked
  locally after every pass.
- **Licenses.** Untested reuse, no `inc`/`dec` for the type, count-free
  cells. memory-theory §6.6 lists these as conjecture; the census is how the
  compiler proves them.
- **MLIR consumer.**
  - The foldable `i1`: canonicalization and SCCP delete the runtime test.
  - For arrays, One-Shot Bufferize: a census array type is writable
    everywhere.

**(b) From whole-program caller analysis.**
- This is memory-theory §6.5 unchanged: the sparse forward interprocedural
  analysis, cloning mixed callers, and the commit into `excl` at function
  boundaries.
- **Carrier.** `p = excl` on parameters and results (spelled `!idr.uniq<T>`).
  Inside bodies it is provenance plus the `i1` from `idr.exclusive`.
- **Lowering.**
  - `excl` becomes `llvm.noalias` on the pointer parameter.
  - That is sound: the cell and its deep graph are reachable only through
    this pointer for the call's duration, which is exactly LLVM's `noalias`
    contract. It is proved rather than guessed, unlike C's `restrict`.

### 2.7 Borrowing and fractional permissions

- **Proof.**
  - Idris proves no borrow. It has no borrow syntax, and every ω use may
    retain.
  - But Idris does prove *0-borrows*: uses in erased positions do not count
    (N5). A linear `xs` can be mentioned in `(0 _ : Ordered xs)` any number
    of times. That is a permission-0 reference: it may *name* the value,
    never touch it.
  - Marshall's permissions exclude 0 ("the typing rules we provide can never
    produce a value with permission 0", m24 §5). QTT's 0-grade is exactly
    that missing point, and it is the ghost.
- **Carrier.**
  - `p = borrow`, spelled plain `T` in the owned stage (mlir-ownership-types).
  - `idr.borrow %a : !idr.own<T> -> T`, scoped by SSA liveness.
  - `idr.erase %a : T -> !idr.ghost<T>` for 0-borrows. It is *not a use*
    (V9), so it cannot demote exclusivity (memory-theory test 9,
    `g xs = f xs xs Refl`).
- **Why no fraction values.** memory-theory §6.9 argued it; I agree.
  - Fractions would be needed only if borrows could live in data. Idris has
    no such thing, and the IR forbids it: a borrow is plain `T` and cannot
    be stored without a `dup`, which is the loss rule.
  - `split` and `join` become "several borrows of one owner, all dead before
    the owner's consuming use", which SSA dominance decides.
  - Marshall's existential identifiers are SSA identity.
  - Bernardy's `β` grade (§1.1) is the same idea as a grade instead of a
    permission. We need it in neither place.
- **Verifier.**
  - Borrow liveness (mlir-ownership-types).
  - The disjointness rule of memory-theory pitfall 10: one op may not lend a
    field of a value it consumes.
- **Licenses.**
  - The fractional join: read a unique value, then update it in place (e3 in
    memory-theory: `total' ys + total' (bump ys)`).
  - Partial borrows: read the head while the tail is updated.
- **MLIR consumer.** None upstream; bufferization's ABI is fixed (memory-theory
  §6.10).
- **Lowering.** Nothing.

### 2.8 Erasure; ghosts; "erased is not constant"

- **Proof and access.**
  - Quantity 0 on binders: `eraseArgs`, and field `Pi` binders. The frontend
    reads them (`binderOf … Gone`).
  - It also knows *which* erased value is which: the implicit `n` of
    `Vect n a`, the `n` of `Fin n`, the indices of a proof's type.
- **The carrier has two forms, by type.**
  - **`!idr.erased`**, anonymous. It is used for types, dictionaries and any
    erased value no fact mentions.
    - It may be `ConstantLike` (`#idr.erased`) and CSE may merge it: two
      anonymous erased values are indistinguishable, because nothing can
      observe which one it is.
  - **`!idr.ghost<T>`** is `(0,·)` *with identity*, for an erased value that
    some fact mentions.
    - Its producers are block arguments (erased parameters), match region
      arguments (erased fields), and `idr.erase %v` of a relevant value.
      `idr.erase` is `Pure`, and CSE may merge two erasures of *the same* SSA
      value, which is sound because they are the same ghost.
    - A closed ghost (a normal form such as `3`) is a typed constant
      `#idr.ghost<3> : !idr.ghost<!idr.nat>`, and it *is* constant.
    - **A symbolic ghost has no constant form.** The dialect's constant
      materializer refuses `!idr.ghost<T>` unless the attribute is closed.
      OperationFolder abandons any fold whose materialization fails (memory-theory
      §6.4, FoldUtils.cpp:275-300).
  - *Why a type and not an op flag:* "erased is not constant" (AGENTS.md)
    then holds by construction.
    - Today every erased value is the one `ConstantLike` `#idr.erased`, and
      CSE merges them all (representation.md). That is harmless only while
      no fact mentions an erased value.
    - With the two forms, whether a value may be merged is decided by its
      type: anonymous values merge, symbolic ghosts cannot even be written
      as constants.
    - The specializer's rule becomes a type rule: it may key on closed
      ghosts (they are constants, representation.md R6) and never on
      symbolic ones (Pattern.cc:22 tests `ErasedType` today).
- **Verifier.**
  - V7, confinement: a value with `u = 0` appears only in 0-positions: q0
    parameters, fields, arguments, ghost operands of fact ops, and
    `idr.erase` results.
  - V8: no symbolic ghost constant.
  - V9: `idr.erase`'s operand does not count as a use.
- **The key design constraint: ValueBounds cannot see a custom type** (§1.5).
  So a ghost cannot be a ValueBounds variable, and a ghost Nat cannot be
  plain `index` either: an `index` value would lose its quantity from the
  type, which AGENTS.md forbids. The resolution is *realization*.
  - **In the value stage**, ghosts carry identity only. Facts about them are
    fact ops (§2.9, §2.10) whose ghost operands are `!idr.ghost<T>`.
  - **At the representation pass** (representation.md's `idr-represent`),
    every ghost a fact still needs is *realized*: replaced by a relevant
    `index` that equals it. There are three sources, in order:
    1. the relevant value it was erased from (`idr.erase %v` → `%v`);
    2. `tensor.dim %t, 0` of a tensor whose length it is (representation.md
       R12);
    3. its closed value.
  - From then on the facts are stated in builtin vocabulary:
    - equal lengths are *the same SSA value*, which CSE and ValueBounds see
      trivially;
    - bounds are ValueBounds constraints on `index` values, which the arith,
      scf, affine, tensor and linalg models then use.
  - A ghost that cannot be realized is one that nothing at runtime needs.
    Its facts are dropped with it, which costs speed only, never soundness.
- **Why this is enough.**
  - Where a ghost relates two runtime things (a `Fin n` against a
    `Vect n`'s length, two vectors' equal lengths in `zipWith`), a runtime
    witness exists once the vector is a tensor: `tensor.dim`.
  - While `Vect` is a list of cells there is no bounds check to remove.
    Idris's `index` is structural recursion, and its absurd cases are
    already unreachable. So the relational facts matter exactly when the
    tensor exists.
  - This is proved by the structure of the facts, not measured.
- **Licenses.**
  - Sound use of relational facts: bounds, equal lengths, trip counts.
  - Symbolic indices kept distinct across inlining: two inlined calls with
    different `n` stay different ghosts, where today's constants would
    merge.
- **MLIR consumer.** The 1:0 type conversion; after realization, ValueBounds
  and CSE.
- **Lowering.** 1:0. Every `!idr.ghost` and fact op is gone before
  `idr-lower`, and the lowering asserts it.

### 2.9 Erased proofs of order relations: `LTE` as `nuw`

- **Proof.**
  - e1's `sub : (m, n : Nat) -> (0 _ : LTE' n m) -> Nat` compiles to an
    unchecked `idr.big.pred %0` on `m`. Idris's case tree used the erased
    proof to make `m`'s zero case unreachable.
  - The IR relies on the fact, and does not *state* it: the proof is
    `!idr.erased`, and the recursive call passes a fresh `#idr.erased`.
  - With Nat as a word (representation.md R1, R5), the same fact licenses
    `arith.subi %m, %n overflow<nuw>`, and so SCEV trip counts and the
    removal of a Nat's overflow path.
- **Access.**
  - The frontend recognizes an **order-shaped family** by its constructors,
    as `calcNaty` recognizes Nat-likes:
    - two constructors;
    - `LZ : P Z n`;
    - `LS : P m n -> P (S m) (S n)`.
  - `Data.Nat.LTE` has this shape, and so do the user's own copies (e1's
    `LTE'`). The recognition is a proof about constructor signatures, not a
    name list, so it needs no registry entry and trusts no library.
  - The same shape rule gives `LT` (via `LTE (S m) n`), `GT` and `GTE`, as
    definitions over LTE.
  - `NonZero n` and `IsSucc n` are one-constructor families indexed by
    `S k`: they give `n ≥ 1`. That is the `divNatNZ` guard that
    facts-ledger's `knownNonZero` recomputes from constants.
- **Carrier.**
  - A fact op at function entry, and at every match that binds such a proof:
    `idr.fact.le %n, %m`, with operands the relevant Nats the proof's type
    indexes, or ghosts when they are erased.
  - It is an *op*, because a type cannot mention SSA values, and never a
    discardable attribute.
  - It is `Pure` with no results: it states the fact where it holds. It
    implements no runtime behaviour.
- **Verifier.** Operands are Nat-typed, or ghosts of Nat. The op appears only
  where a proof of that type is in scope (checked by the frontend; the IR
  cannot see proofs, since they are q0).
- **Licenses.**
  - `nuw` on `n - m` and on `pred` when narrowed.
  - Unchecked `pred` (already implicit).
  - Loop trip counts (`m - n` iterations).
  - Crash facts, in place of `knownNonZero`.
- **MLIR consumer.**
  - ValueBounds, after realization, since the operands are then `index`: the
    op implements `ValueBoundsOpInterface` and states `n ≤ m`.
  - IntegerRangeAnalysis is non-relational, so it uses only the closed half
    (for example, `n ≥ 1` from `NonZero`).
  - The narrowing pass (representation.md `idr-narrow`) reads both to put
    `overflow<nuw>` on `arith.subi`.
- **Lowering.** The op is deleted; the `nuw` flag stays on the arithmetic and
  reaches LLVM.

### 2.10 Nat, Fin and Vect indices as ranges and lengths

representation.md R1, R5, R6, R11 and R12, and facts-ledger §6, design the
representations. Here are the QTT-specific parts.

- **Nat.**
  - `!idr.nat` is a non-negative type, so IntegerRangeAnalysis seeds `≥ 0`
    through a `setToEntryState` override (mlir-idioms §6.1).
  - Nothing grade-specific, except the transparency rule below.
- **Fin.**
  - `Fin N` with `N` closed is `!idr.fin<N>`, seeded `[0, N)`.
  - `Fin n` with `n` symbolic is a relevant Nat plus `idr.fact.lt %i, %n`,
    with `%n` a ghost. This is representation.md's `idr.fin.enter`, made a
    fact op like §2.9's so that one mechanism serves both.
- **Vect.**
  - The length is a ghost of the vector: the frontend emits
    `idr.fact.len %v, %n` at binding sites where both are in scope.
  - At representation, when R12's proofs hold, `%v` becomes `tensor<?xT>`
    and `%n` is realized as `tensor.dim %v, 0`.
  - `zipWith`'s two ghosts are one `%n`, so both tensors' dims are one SSA
    value. `linalg.map`'s shape agreement, and every upstream ValueBounds
    query, is then trivially true.
- **LTE** is §2.9.
- **Transparency rule** (new, and cheap).
  - `lin.enter`, `lin.use`, `idr.borrow` and `idr.erase` are value
    identities. They must implement `InferIntRangeInterface` (result range =
    operand range), and `ValueBoundsOpInterface` for `index` values (result
    = operand).
  - Today `lin.use` implements neither (IdrOps.td:1047-1055), so a range
    would stop at every linear boundary once range analysis runs. A grade
    must never hide a value from a value analysis; it only restricts how
    often the value is used.
- **MLIR consumers.**
  - IntegerRangeAnalysis and `int-range-optimizations`.
  - ValueBounds, after realization.
  - `tensor.dim`.
  - `scf.for`, raised by upstream uplift (architecture I.1).
- **Lowering.** `index`/`i64`, and `llvm.range` on `Fin N` values at function
  boundaries.

### 2.11 Totality (with coverage and size-change)

- **Proof and access.**
  - `checkTotal` (Core/Termination.idr:101), coverage, and
    `GlobalDef.sizeChange`.
  - The frontend reads them (facts-ledger §4-5) into `idr.total`, exhaustive
    matches, and the rejection of polymorphic recursion.
  - The user's `assert_total` is rejected, so the fact is Idris's own.
- **Carrier.**
  - On closures: inside `!idr.fn<(A) -> (R), #idr.eff<total, …>>`, since a
    closure has no callee symbol to hang a fact on (mlir-idioms §5.5).
  - On `func.func`: a dialect attribute verified by the dialect
    (`verifyOperationAttribute`, as today).
  - This is the one fact here that may live in a discardable attribute:
    losing it costs speed, never soundness. Passes can drop attributes but
    never invent them, which is architecture.md rule R1.
  - Grades are the opposite case. Dropping a grade (widening 1 to ω) would
    unlock a `dup` of a value Idris proved single, so grades are types.
- **Verifier.** A call's callee facts must agree with the `!idr.fn` type it
  was defunctionalized from.
- **Licenses.**
  - Speculation of pure total calls: LICM, and hoisting out of matches.
  - CSE and DCE of pure total calls (facts-ledger's `length xs` computed four
    times).
  - `will_return`.
  - A tighter linear rule: on total paths "at most once" is "exactly once".
    The owned stage's "exactly once" (V2) holds on every path that does not
    end in `ub.unreachable`, and totality means no other path diverges.
  - Size-change gives decreasing parameters (for binding times and
    `scf.for`).
- **MLIR consumer.** External models on `func.call` and `idr.apply`:
  - `MemoryEffectOpInterface`, read from the callee's effects;
  - `ConditionallySpeculatable`: speculatable iff total and cannot crash.

  Upstream LICM requires `isPure` (LoopInvariantCodeMotionUtils.cpp:117),
  and CSE and `remove-dead-values` read effects. Our `Facts/Moves` and
  `RemoveUnusedCall` go.
- **Lowering.**
  - `will_return` and `memory_effects` on `llvm.func`.
  - Only for functions that are total *and* cannot crash, because a crash
    calls a `noreturn` helper (mlir-idioms §6.3).

### 2.12 Data facts that come with quantities

- **Erased fields and collapsible families.**
  - `safeErase` / `detagSafe` (TTImp/Elab/Utils.idr:19-35) marks positions
    whose value is determined by an unerased argument's tag.
  - A field of a collapsible family (LTE's proof field, a `Dec`'s evidence)
    is `!idr.erased` by the frontend's own proof, never by assumption
    (representation.md R14; facts-ledger's `Elem` caution).
  - Consumer: DCE. It is the `Dec (LTE m n)` case, which today carries a
    counted big and a closure (facts-ledger).
- **Derivable relevant fields** (e2).
  - In `(b ** SBool b)` the relevant `b` is a function of `s`'s tag, because
    `SBool` is detaggable by its index.
  - Carrier: a useless-field decision (representation.md R7) whose proof is
    the detag relation. The field becomes absent, and a read of it becomes a
    match on the other field's tag.
  - Conjecture on frequency: dependent pairs over singleton families are
    common in verified code and rare in Prelude code.
- **`!*` (`MkBang : a -> !* a`).**
  - This is the grade change `1 → ω` as a data type.
  - Under the match rule (V5), its field binds at `1 · ω = ω`.
  - Representation: a one-field, one-constructor newtype, so it has zero
    cost already. It *must* be erased, since libs/linear wraps every element
    of `LList (!* Int)` in it (linear-libs items 1, 4, 5).
- **`Res` (`(#) : (val : a) -> (1 r : t val) -> Res a t`).**
  - An ω value paired with a q1 resource whose *type* depends on the value.
  - Representation: an unboxed product (Layout.cc's `Sop`). The resource
    field keeps `u = 1` by V5, and the dependency is q0.
- **Newtype containing the world.** `newtypeArg`'s Bool
  (Context.idr:95-103) is the fact that erasing a match on the newtype is
  safe unless it contains `%World`. The world is `(1,·)` by V1, so the
  census of a type's fields answers the same question from our types.
- **`Copies n x`.**
  - `n` linear copies of the same value.
  - For values with no identity (scalars), `Copies n x` is `x` plus the
    ghost `n`. Conjecture, and rare.
- **Parametricity.**
  - A function is parametric in `a` only if `a` is q0 (docs).
  - After monomorphisation, instances that differ only in q0 type arguments
    with *equal representations* compute the same machine code. LLVM's
    MergeFunctions pass finds that from the IR alone, so the Idris fact adds
    compile time only.
  - Not load-bearing for speed; noted for completeness.

## Part 3. The type algebra

### 3.1 The grade

`G = U × P`:
- `U = {0, 1, ω}` with Idris's operations (Algebra/ZeroOneOmega.idr):
  - `+` is `0+x = x`, `1+1 = ω`, `ω+x = ω`;
  - `·` is `0·x = 0`, `1·x = x`, `ω·ω = ω`;
  - the order is `0 < 1 < ω`, and a value at `l` fills a position at `r`
    only if `r ≤ l`.
- `P = {·, borrow, own, excl}`:
  - `·` means "no obligation": the value stage, and non-counted types;
  - `borrow` holds no reference, and lives while its owner does;
  - `own` holds one reference, consumed exactly once;
  - `excl` is `own` whose cell graph is deeply exclusive (memory-theory
    §6.2).

  The conversions follow Marshall et al.: `excl → own` is free (share);
  `own → excl` needs `idr.copy` (clone); `own → borrow` is `idr.borrow`,
  scoped.

One C++ value class, `idr::Grade`, implements `+`, `·`, `≤`, `join` and
`canonical`. It is used by:
- the verifier (V1-V9);
- Emit's contract, where Idris's `Use` is the `U` component;
- the specializer: leaves take `field · argument` grades;
- defunctionalization: captures keep their grades, and the closure's grade
  is the minimum of its captures';
- idr-rc's type converter;
- the census;
- `quantities-kept`, which compares `U` components.

### 3.2 The verifier rules, stated once

- **V1, canonical types.** The type's `verify`:
  - `T` is not itself graded;
  - `u = 0 ⇒ p = ·`;
  - `p ≠ · ⇒ counted(T)`, through the one "holds references" interface
    (mlir-idioms §3.5);
  - the world only at `(1,·)`;
  - `(ω,·)` is never constructed: the builder returns `T`.
- **V2, use bound per path** (generalized `LinearUses`):
  - `u = 0`: no runtime use;
  - `u = 1`, value stage: at most one;
  - `p ∈ {own, excl}`: exactly one on every path not ending in
    `ub.unreachable`;
  - otherwise unrestricted.
- **V3, positions.** Grades change only through the explicit ops: `lin.enter`,
  `lin.use`, `idr.erase`, `idr.borrow`, `idr.dup`, `idr.copy`, `idr.share`.
  Everything else is type equality, which MLIR's call, return and branch
  verifiers already enforce.
- **V4, closures.** `grade(closure) ≤ min(grade(capture_i))` in `U`.
- **V5, matches.** Region argument `i` has type
  `q(u_scrutinee · u_field_i, T_i)`. The scrutinee is taken at its grade.
- **V6, contraction.** In the owned stage, `idr.dup`'s operand has
  `u ≠ 1`. For a census type, there is no `dup` of it at all.
- **V7, ghost confinement.** `u = 0` values only in 0-positions.
- **V8, no symbolic ghost constants.** No `!idr.uniq` or `excl` constants
  either (memory-theory §6.4).
- **V9, erasure is not a use.** V2 does not count `idr.erase` operands, or
  the ghost operands of fact ops.

**What these delete:**
- `LinType::verify`'s special list;
- `bindsField`'s extra case;
- the closure special case (Ops.cc:794-808);
- `modeOf`'s world special case;
- `Idr_CountedType`'s admission of `lin<i64>`;
- the `idr.stage` switch, once the owned grades exist (mlir-ownership-types).

**The cost:** one generalized counter and one type-level check.

### 3.3 Graded type or wrappers: the decision

| criterion | separate wrappers (`lin`, `erased`, `ghost`, `own`, `uniq`) | one `!idr.q<(u,p), T>` |
|---|---|---|
| canonical form per state | no: `own<lin<T>>` and `lin<own<T>>`; `lin<erased>` must be rejected | yes: the builder normalizes; V1 is the whole list |
| semiring operations (`rigMult`, capture scaling, subsumption) | spread over each pass's `isa` chains | `Grade`'s operators, once |
| ghosts keep their type | needs a second erased type anyway | `(0,·)` with `T`, for free |
| ODS constraints ("an owned operand") | `Idr_OwnType` | `Idr_Graded<"p == own">`, a type predicate; equally checkable |
| stage legality | per-type rules | a `ConversionTarget` over grades: the value stage admits `p = ·`, the owned stage requires `p ≠ ·` on counted types |
| lowering | one conversion per wrapper | one conversion: strip, or 1:0 when `u = 0` |
| readability of IR dumps | good | the same: the spellings are kept as sugar |
| migration cost | none | moderate: `LinType`/`ErasedType` uses become `QType` queries; Emit's text is unchanged thanks to the sugar |
| builtin types (tensor, vector, index) | wrapping hides them from their dialect's passes | the same, which is why a grade must be *stripped* (`lin.use`) before a tensor op. For tensors, the idiom that would keep the grade *inside* the type is the tensor encoding (open question) |

**Verdict: one type.**
- It turns every guard in the first column into a normalization.
- It makes the semiring a data structure instead of a set of case analyses.
- It gives ghosts their type without a second mechanism.

The wrappers' readability survives as spellings. This is the principle
document's "change the representation so the case stops being expressible".

## Part 4. How grades survive transformations

**Specialization.**
- Clone keys are shapes whose leaves are SSA values, and each leaf keeps its
  type, and so its grade.
- A leaf that is a field of a static constructor passed at grade `g` gets
  `g · g_field`, computed by `Grade` (V5's rule applied at compile time).
- The existing guard stays: a q1 leaf moves into a clone only if its shape
  dies at the call (Specialize.cc:186-190).
- Symbolic ghosts are never key constants (V8 makes them unwritable as
  constants). Closed ghosts are constants and may be keys: representation.md
  R6's closed indices.
- `quantities-kept` then compares clone parameters by location, as today.

**Inlining.**
- MLIR's inliner substitutes call operands for block arguments, and V3's
  type equality makes the grades match.
- The `lin.enter`/`lin.use` pair left at the seam folds, and each value that
  remains keeps its type (IdrOps.td:1024-1031).
- Ghosts substitute as SSA values: two inlined calls with different `n` keep
  two ghosts. Today's anonymous constants would merge, which is the hazard
  §2.8 removes.
- A q1 callee inlined into an ω context is fine: that is dereliction at the
  call, which was already there as a `lin.enter`.

**Defunctionalization.**
- Captures become fields of the closure sum, keeping their grades
  (Defunctionalize.cc:882, 959).
- By V4, a closure with a q1 capture is itself q1, so its sum value is q1.
- The apply is a match on it that consumes it, so by V5 the captures bind at
  `1 · 1 = 1` and move out. This is the one-shot path of §2.3.
- An arrow's grade `!idr.fn<(!idr.q<(1,·),A>) -> …>` becomes the apply
  function's parameter grade.

**Compile-time evaluation.**
- A closed call ignores ghosts: they are irrelevant to the result, as
  Specialize.cc:163 already assumes.
- Results come back as constants, which are ω, and enter q1 positions by
  `lin.enter`. Constants are never `excl` (V8), so an evaluated value that
  enters an in-place loop is `idr.copy`'d once (memory-theory §6.7).

**MLIR's own passes.**
- CSE never merges `lin.*`, `idr.dup` or `idr.con` (allocation effects), but
  does merge `idr.erase` of the same value (sound).
- LICM never hoists a grade op, because they are not `isPure`.
- `remove-dead-values` may delete an unused q1 parameter, which respects
  "at most once" (Idris guarantees one use except on unreachable paths), and
  unused ghosts, once their fact ops are gone.
- Canonicalization's folds must not duplicate a q1 value (`readOnce`,
  Ops.cc:392-398). V2 after every pass catches any that did.
- SCCP and DeadCodeAnalysis see through grade ops by the transparency rule
  (§2.10).

**idr-rc**, the elaboration of QTT's structural rules. A `TypeConverter` maps:
- `(u,·)` on a counted `T` to `(u, own)`;
- borrow inference then relaxes positions to plain `T` (`(u, borrow)`). Keep
  Borrow.cc's rule: q1 parameters stay owned, since a consumed-once
  parameter gains nothing from borrowing;
- the exclusivity analysis commits `excl`.

Counting inserts `dup` (contraction) and `drop` (weakening) explicitly. V6
holds idr-rc to Idris's proof that a `u = 1` value needs no contraction.

**Lowering.**
- `u = 0` values have no components (a 1:0 conversion). The rest are
  stripped.
- `p = excl` becomes `llvm.noalias`.
- An `idr.*` grade or ghost reaching the LLVM dialect is an error.

## Part 5. The roadmap

Each step lands with its consumer and its proof. The ordering interleaves
with architecture.md Part II, whose step numbers are marked A1, A2, and so
on.

0. **Now, with no new representation.**
   - Tests that `assert_linear` is rejected (memory-theory §7.1) and that
     `believe_me` stays rejected. The census and exclusivity depend on both.
   - *Proof:* two profile tests.
1. **Grades transparent to value analyses.** Lands with A3 (the solver with
   IntegerRangeAnalysis and `int-range-optimizations`).
   - `InferIntRangeInterface` on `lin.enter`/`lin.use`.
   - *Load:* without it, ranges stop at every linear boundary the moment
     range analysis runs.
   - *Proof:* an `idr` lit test where a `Char` range crosses a linear
     parameter and `int-range-optimizations` folds the `cmpi` behind it.
2. **One graded type** (Part 3).
   - **Landed 2026-09-30 (the type):** `!idr.q<GRADE, T>` with
     `idr::Grade` (quantity, permission), the spellings `!idr.lin<T>`,
     `!idr.erased` and `!idr.world` parsed and printed by the dialect (the
     erased value's carrier is `none`, the world's its token, which never
     appears at another grade), V1 as `QType::verify`, and the helpers
     `gradeOf`, `graded`, `isLinear`, `isWorld`, `isErased`. Emit and the
     tests are unchanged, through the spellings.
   - **Landed 2026-09-30 (V5):** `idr.match` takes its scrutinee at its
     grade, and each case binds the constructor's fields at
     `u_scrutinee · u_field` (`idr::fieldType`, Idris's `rigMult`; the
     world stays at its own grade). Emit no longer uses a linear scrutinee
     before the match: the match is the use. What a region needs of the
     whole value it gets honestly: the default region takes a linear
     scrutinee back as its argument (`default(%t: !idr.lin<T>)`), and a
     variable naming the scrutinee inside a case names the constructor
     rebuilt from the fields the case bound (`Val.rebuild` in Emit), which
     the owned stage builds in the cell the match took apart. Record eta
     does not fold through a match on a linear value, and the region
     inlining pattern leaves a match on a linear value whose source is not
     a plain value: the match is the take. `quantities-kept` checks bound
     fields as it checks parameters. The `bindsField` guard is gone.
   - `QType` with `Grade`; the spellings `lin`, `erased` and `world` kept as
     sugar; V1-V5 and V9 as one verifier.
   - The match takes its scrutinee at its grade.
   - The closure grade rule replaces Ops.cc:794-808, and `bindsField` goes.
   - *Load at landing:* it deletes four guards and gives deep linearity
     (V5).
   - *Proof:*
     - `quantities-kept` extended to match region arguments ("the tail of a
       q1 `LList` cell is q1");
     - a verifier-negative lit test per rule;
     - linear-libs' `llist-*` user copies still compile and match Chez.
3. **Ghosts and relational proofs, together with Nat as a word.** Lands with
   A1 (Nat) and representation.md R5.
   - `!idr.ghost<T>`, `idr.erase`, and the constant rule (V7, V8).
   - Order-shaped families by shape; `idr.fact.le`/`lt`, with
     `ValueBoundsOpInterface`.
   - `idr-narrow` puts `nuw` on Nat subtraction where a fact proves it.
   - *Load:* the first consumer (`nuw`, unchecked `pred`) lands in the same
     change.
   - *Proof:*
     - e1's `sub` narrows to `index` with `subi … overflow<nuw>`: a lit
       check on the narrowed IR, and a check that `nuw` reaches LLVM;
     - output equal to Chez;
     - a Nat loop benchmark (for example `sub` over 10^8) against Chez and C.
4. **Totality and effects in types.** Lands as A6.
   - `#idr.eff<…>` on `!idr.fn`, and external `MemoryEffectOpInterface` and
     `ConditionallySpeculatable` models on `func.call` and `idr.apply`.
   - *Load:* upstream LICM, CSE and `remove-dead-values` consume it;
     `Facts/Moves` and `RemoveUnusedCall` go.
   - *Proof:*
     - facts-ledger's `length xs` computed once, not four times: an
       `idr-expect` property counting the calls of a callee in a function,
       stated as "at most one call of @length on each path";
     - a tail loop with a pure total call hoisted, shown by upstream LICM's
       statistics.
5. **Owned grades** (mlir-ownership-types; memory-theory step 2). Lands as A7.
   - **Landed 2026-09-30 (the types and ops):** after `idr-rc` every value
     that holds references is `!idr.own<T>` (one reference of its own) or
     plain `T` (a view, alive while its owner holds its reference);
     `idr.dup` (view → own), `idr.drop` (own), `idr.borrow` (own → view)
     replace `idr.inc`/`idr.dec`; borrow inference writes function types
     (an owned parameter or result is `own<T>`, a borrowed parameter plain
     `T`) and `idr.borrowed` is gone; `idr.take` gives owned fields and an
     owned token, `idr.reuse` takes them. The position table (`useOf`) is
     now mostly ODS: consuming operands are `Idr_OwnType`, reading operands
     plain, and the graded results (`Idr_AtAnyGrade`) let a producer's
     result be owned directly. Constants are views, and a `dup` of one
     lowers to nothing. The verifier still walks paths (it must, for the
     join of alternatives and the loops idr-tail-loops makes), but on
     types: owned values exactly once, views alive while their owner
     holds, a loop's condition passing views on with their owners.
     `idr.stage` stays as the marker that the counting ops are legal and
     that signatures are graded; V5 (the match at its scrutinee's grade)
     is next, now that a scrutinee can be `own<T>`.
   - `(u, own)`, plain `T` for borrowed, `dup`/`drop`/`borrow`; V2 exact;
     V6.
   - *Load:* it deletes `idr.stage` and Verify.cc's path interpreter.
   - *Proof:*
     - verifier negatives, including "dup of a q1 value";
     - `counts-nothing`/`reuses-in-place` unchanged;
     - the compile time of verification on the largest bench module is no
       worse.
6. **Exclusivity and the census.**
   - **Landed 2026-09-30 (the grade, the analysis, the untested take):**
     `!idr.excl<T>` is the permission `Excl` of the graded type, an owned
     value that holds the only reference to every cell of its cell graph.
     `idr-rc` infers it after counting (`Ownership/Exclusive.cc`):
     `ExclusiveAnalysis`, a `SparseForwardDataFlowAnalysis` on MLIR's
     solver with the lattice `Unknown < Exclusive < Shared`, optimistic as
     SCCP is, with `DeadCodeAnalysis` for reachability and a constant
     lattice that knows no constant (a region only a constant would skip
     is the canonicalizer's to fold, not the solver's to leave ungraded).
     Provenance is the rule: a constructor of exclusive box fields, the
     fields and token a take of an exclusive value gives (the token of a
     nullary constructor stays shared: its cell may be the atom), a call
     every return of which is exclusive, a parameter every caller passes
     exclusive. A dup is shared unless of an atom; a stack cell, a share
     and anything from outside the module are shared. `idr.share` gives an
     exclusive value on as owned (identity at lowering) and is inserted
     where an exclusive value meets an owned position and, before the
     solver, at the consuming use of a value some view of which was
     duplicated (here, or in a callee that borrows it). The commit writes
     the grade into value and function types; a linear value of an
     exclusive one is `!idr.q<(1, excl), T>`. The verifier holds the two
     rules the grade needs: no dup of a view rooted at an exclusive value,
     and an exclusive constructor's box fields exclusive. `idr-lower`
     takes an exclusive value apart with no count test and builds in an
     exclusive token with no null test. `tests-nothing=@f` states the
     property, and rbtree's `ins` holds it: every take and reuse in it is
     exclusive, and the gate's rbtree (n = 4 200 000) runs in 0.84 s
     where it ran 1.37 s after TRMC (same machine, 4 cores, load about
     1.5). A dup of static data now runs nothing (the lowering read the
     constant through the no-rollback driver's replaced value). Not yet:
     the per-constructor cover (cfold), cloning a function for its
     exclusive call sites, `noalias` from `excl`, freeing an exclusive
     tree without reading its counts.
   - Demand remarks for census types.
   - *Load:* static reuse.
   - *Proof:*
     - memory-theory §8's must and must-not lists (`in-place=@f`,
       `exclusive-param`);
     - linear-libs items 1, 4, 5 with 0 allocations per pass;
     - llist-bubble against Chez (today 2.6x slower);
     - the Lin1 counterexample still prints Chez's output.
7. **One-shot closures.**
   - Apply consumes a q1 closure (defunctionalized as a take); the inliner's
     profitability reads q1.
   - *Load:* captures move, and the closure cell is reused.
   - *Proof:*
     - linear-libs item 7 (`lio-resource`): `no-heap-allocation=@loop`, no
       `L` cells;
     - an `idr-expect` property "no `inc` of a capture of a q1 closure".
8. **LLVM facts from grades.** Lands with A9.
   - `excl` → `noalias`; totality → `will_return`; `Fin N` → `range`;
     narrowed Nats → `nuw`.
   - *Proof:* a lit check on the LLVM dialect module for each attribute, and
     the bench suite against Chez and C (nbody, a list update loop).
9. **Tensors with realized ghosts.** Lands with A8 and representation.md R12.
   - `idr.fact.len`, realization to `tensor.dim`, `Fin n` bounds as
     ValueBounds; `excl` arrays `writable` for One-Shot.
   - *Proof:*
     - the `vect` e2e `dot` becomes `vector.reduction`;
     - `arrays-in-place` (linear-libs §5);
     - linarray-fill-sum and linarray-bubble at C's speed.
10. **Conjectures, only once something needs them.**
    - An `idr.ghost` region, the 0-fragment as an `IsolatedFromAbove`,
      pure-only region, for ghost arithmetic (`n + m`) when a fact needs a
      computed index that realization cannot supply.
    - Grades in tensor encodings.
    - Derivable fields (e2's `(b ** SBool b)`).

## Open questions

- **A grade inside a tensor type.** Would `tensor<?xf64, #idr.grade<(1,excl)>>`
  survive the tensor and linalg ops and reach One-Shot Bufferize, so that
  `excl` becomes `writable` without a boundary op? Many tensor ops require
  matching encodings, or drop them. Untested.
- **The census and results.**
  - Counting a call result as fine only when it is immediately entered into
    a q1 position is conservative.
  - Is it enough for `LList` code written with `-@` everywhere, or do
    results flowing through `let` (which Idris infers at the value's grade)
    break it?
  - Measure on the linear-libs corpus once the libraries compile (their
    R1-R6 rejections).
- **Order-shaped families beyond LTE.**
  - Which other relational families (`Elem`, `Subset`, `InBounds`) have an
    arithmetic meaning worth a fact op?
  - `Elem` is not collapsible (facts-ledger), so its position is
    information, not a relation.
- **Ghost arithmetic.** How often does a fact need a *computed* index (`n + m`)
  that realization cannot supply? If never outside tensors, the ghost region
  is never needed.
- **Atkey's semantics.** Does QTT's realisability model give more than the
  operational erasure guarantee? For example, that 0-graded arguments cannot
  affect a result's *identity*, which would let CSE merge calls differing
  only in symbolic ghosts. This is unverified: I could not read the paper
  (egress blocked). Until it is checked, such calls are not merged.
- **Idris soundness.** Any known Idris 2 linearity bug would break V6's
  premise that `u = 1` means no contraction. For example `UseUnknown` around
  holes; holes are rejected by the profile. The rest is unaudited
  (memory-theory §9).

Sources: [Atkey, LICS 2018 (Strathprints)](https://strathprints.strath.ac.uk/64031/) and
[bentnib.org](https://bentnib.org/quantitative-type-theory.html), located by
web search and not readable from this environment.
