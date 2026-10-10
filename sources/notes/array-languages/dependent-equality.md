# Dependent equality: shape arithmetic and the rewrite problem

Cluster notes for an Idris-hosted, shape-typed array language compiled through MLIR
(proposal 0004, rank above 1 with no ceiling). The question: why rewriting by an equation
fails under dependent types, the algorithms that avoid the failure, the solvers that decide
type-level `Nat` arithmetic, and what the language needs so that `n * m = m * n`,
`n + 0 = n` and `prod [n, m] = prod [m, n]` never block a user.

Every path below is relative to the repository root and names the stored copy under
`sources/` (staged on 2026-10-09; see `catalogue/dependent-equality.md`). PDFs are cited by PDF
page (`p.N`) and section; PostScript by page of the dvips file; TeX, code and docs by line.
Items marked *(other cluster)* were staged by a sibling cluster the same day and are only
cross-linked here.

- [1. The problem in one page](#1-the-problem-in-one-page)
- [2. Sources](#2-sources)
  - [Idris 2's own rewrite and with](#21-idris-2-rewrite-and-with)
  - [McBride, Elimination with a Motive](#22-mcbride-2000-elimination-with-a-motive)
  - [McBride and McKinna, The view from the left](#23-mcbride-and-mckinna-2004-the-view-from-the-left)
  - [Goguen, McBride, McKinna, Eliminating dependent pattern matching](#24-goguen-mcbride-mckinna-2006-eliminating-dependent-pattern-matching)
  - [Cockx et al., Unifiers as equivalences, and the thesis](#25-cockx-devriese-piessens-2016-unifiers-as-equivalences-and-cockx-2017-thesis)
  - [Cockx et al., Overlapping patterns](#26-cockx-piessens-devriese-2014-overlapping-and-order-independent-patterns)
  - [Cockx, Type theory unchained; Agda REWRITE](#27-cockx-2020-type-theory-unchained-and-agdas-rewrite-rules)
  - [Allais, McBride, Boutillier, New equations for neutral terms](#28-allais-mcbride-boutillier-2013-new-equations-for-neutral-terms)
  - [Agda with-abstraction and rewrite](#29-agda-with-abstraction-and-rewrite)
  - [Lean 4 rw, subst, generalize, simp, omega](#210-lean-4-rw-subst-generalize-simp-omega)
  - [Rocq rewrite, generalize dependent, dependent rewrite, ring, lia](#211-rocq-rewrite-generalize-dependent-dependent-rewrite-ring-lia)
  - [Frex](#212-allais-brady-corbyn-kammar-yallop-2025-frex)
  - [ghc-typelits-natnormalise](#213-ghc-typelits-natnormalise)
  - [Diatchki, Improving Haskell types with SMT](#214-diatchki-2015-improving-haskell-types-with-smt)
  - [Xi, Dependent ML](#215-xi-2007-dependent-ml)
  - [Henriksen and Elsman, size-dependent types](#216-henriksen-and-elsman-2021-towards-size-dependent-types)
  - [egg, egglog, slotted e-graphs](#217-equality-saturation-egg-egglog-slotted-e-graphs)
  - [Brady, Idris 2 QTT](#218-brady-2021-idris-2-qtt)
  - [MLIR's shape dialect](#219-mlirs-shape-dialect-witnesses)
- [3. Synthesis: what the array language needs](#3-synthesis-what-the-array-language-needs)
- [4. Not stored](#4-not-stored)

## 1. The problem in one page

Rewriting with `prf : x = y` replaces a goal `G[x]` by `G[y]` through the eliminator of
equality, whose motive is `P = \v => G[v]`. The motive is computed by *abstraction*: find
the occurrences of `x` in `G` and replace them by a bound variable. Three things go wrong.

1. **The motive is ill-typed.** If some subterm `s` of `G` has a type that mentions `x`, and
   only `x`'s occurrences, not `s`, are abstracted, then `\v => G[v]` contains `s` at type
   `T[x]` where `T[v]` is now expected. McBride's `Abst` tactic notes "of course, P[y; x]
   may not be well-typed" (`sources/papers/mcbride-2000-elimination-motive/elim.ps`, p.15,
   §8); Agda's manual gives the canonical case, abstracting `fst p` in `H (fst p) (snd p)`
   (`sources/docs/agda/doc/user-manual/language/with-abstraction.lagda.rst:1055-1090`); Lean
   reports "motive is not type correct" with the same explanation
   (`sources/code/lean4/src/Lean/Meta/Tactic/Rewrite.lean:57-73`). For arrays the case is
   routine: in `index (reshape (transpose a)) i`, with `a : Array [n, m] e` and
   `i : Fin (n * m)`, rewriting `n * m` to `m * n` in the goal also hits `i`'s type unless
   `i` is generalised too.
2. **Abstraction finds the wrong occurrences.** Abstraction is up to conversion, so it can
   miss syntactically different but convertible occurrences or, worse, catch too many.
   Idris 2 abstracts every subterm of the *normal form* of the goal that converts with the
   left-hand side (`sources/code/idris2/src/Core/Normalise.idr:243-251`); Lean only tries
   subterms whose head symbol and arity match (`sources/code/lean4/src/Lean/Meta/KAbstract.lean:30-67`);
   Rocq rewrites only instances identical to the first match
   (`sources/docs/rocq/doc/sphinx/proofs/writing-proofs/equality.rst:183-189`).
3. **Equations that are not constructor equations cannot be matched away.** Dependent
   pattern matching on `Refl : n * m = m * n` needs unification to solve `n * m =?= m * n`.
   Unification decides only constructor-headed problems; for anything else it *fails*, a third
   outcome beside positive and negative success
   (`sources/papers/cockx-2016-unifiers-as-equivalences/paper.pdf`, p.3, §2). Cockx's thesis
   shows the shape-arithmetic version of the problem as future work: matching on
   `Vec A (l m)` when `l` is an arbitrary function
   (`sources/papers/cockx-2017-dependent-pattern-matching-thesis/thesis.pdf`, PDF p.141,
   printed p.129, §5.1 "Partial unification").

The remedies fall into five families, each represented below:
(a) generalise a telescope so the motive is well-typed by construction (McBride's
constraint-by-equation, Agda's Δ1/Δ2 split, Lean's `subst`, Rocq's `generalize dependent`);
(b) eliminate equations by proof-relevant unification (Goguen et al., Cockx);
(c) make the equation *definitional* so there is nothing to rewrite (overlapping clauses,
REWRITE rules, ν-rules);
(d) decide the arithmetic with a normaliser or solver (ring/`lia`, `omega`, Frex,
natnormalise, SMT, DML's Fourier–Motzkin);
(e) restrict the size language so the problem cannot arise (Futhark).

## 2. Sources

### 2.1 Idris 2: rewrite and with

Stored: `sources/code/idris2/src/TTImp/Elab/Rewrite.idr`, `src/Core/Normalise.idr`,
`src/Core/GetType.idr`, `src/TTImp/ProcessDef.idr`, `src/TTImp/Elab/Utils.idr`,
`src/TTImp/WithClause.idr`, `libs/prelude/Builtin.idr`, `libs/base/Data/Nat.idr`, all at the
`third_party/Idris2` pin (addendum `sources/code/idris2/SNAPSHOT.dependent-equality.md`). The
repository's fork (`compiler/idris/src/TTImp/Elab/Rewrite.idr`) differs only in threading the
delayed-elaboration reference.

**Key ideas.**
- Equality is `data Equal : forall a, b . a -> b -> Type` with one constructor
  `Refl : {0 x : a} -> Equal x x`, heterogeneous in its statement
  (`libs/prelude/Builtin.idr:123-125`). The rewrite lemma is
  `rewrite__impl : {0 x, y : a} -> (0 p : _) -> (0 rule : x = y) -> (1 val : p y) -> p x`,
  registered by `%rewrite Equal rewrite__impl` (`Builtin.idr:155-159`). The predicate and the
  rule are at quantity 0 and the value at quantity 1: **a rewrite costs nothing at run time
  and preserves linearity.**
- `elabRewrite` (`Rewrite.idr:65-100`): normalise the rule's type to read `lhs`, `rhs` and the
  type of `lhs` (`getRewriteTerms`, 30-44); normalise the expected type again (it may have
  been delayed, 79-81); call `replace` to substitute a fresh name for every subterm of the
  normal form convertible to `lhs` (85); bind it as the predicate `\rwarg => ...` (89-91);
  compute its type with `getType` (92-93); fail with `RewriteNoChange` if the rewritten type
  still converts with the original (96-99).
- `replace'` (`Normalise.idr:243-305`) walks the normal form; at every node it first asks
  `convert defs env lhs tm` (248-250), so abstraction is up to conversion at every subterm,
  and it re-quotes with an emptied context (`clearDefs`) so the result is a normal form.
- `getType` is documented as getting "the type of an already typechecked thing"
  (`src/Core/GetType.idr:10`), and the predicate is never checked before
  `checkRewrite` elaborates `rewrite__impl pred rule tm` against the expected type
  (`Rewrite.idr:142-151`). An ill-typed motive therefore surfaces as whatever error that
  application raises, not as a motive error. `checkRewrite` is wrapped in `delayOnFailure`
  (`Rewrite.idr:117`), so a rewrite whose goal still has unsolved metavariables is retried later.
- `with`: `checkClause`'s `WithClause` case (`ProcessDef.idr:441-548`) elaborates the
  with-value, splits the environment into what the value needs and the rest
  (`keepOldEnv`/`findSubEnv`, 460; `bindNotReq`/`bindReq` in `Elab/Utils.idr:87-125`),
  abstracts the value from the *not-required* part of the type with the same `replace`
  ("magic with", 474-488), generates an auxiliary with-function (510-514) and re-elaborates the
  with-clauses against it (`WithClause.idr`). The `Syntactic` flag abstracts against an
  emptied context, so occurrences are found without unfolding definitions (481-483). With
  `proof`, the equation `Refl {x = wval}` is passed along (515-523).
- `Data.Nat` proves the lemmas users rewrite with (`plusZeroRightNeutral` at
  `libs/base/Data/Nat.idr:451`, `plusCommutative` at 465, `multRightSuccPlus` at 570, ...),
  each by induction, because `plus` recurses on its first argument only and `n + 0` does not
  reduce (the docs: `sources/docs/idris2/docs/source/proofs/definitional.rst:162-180`,
  `proofs/patterns.rst:190-240`).

**Steal.** The quantity discipline of `rewrite__impl`: proofs and motives at 0, the value at 1.
Every equality proof the array language produces must stay at quantity 0 so it erases to
nothing (Brady's QTT paper, §2.18). The `with ... proof` mechanism and `Syntactic` abstraction
are the right primitives for views over shapes (§2.3).

**Avoid.** Re-quoting the goal as a normal form: a shape expression such as
`product (map f dims)` is unfolded and the user's goal is replaced by its normal form. Abstracting
by conversion at every node of the normal form is quadratic in the worst case and finds
occurrences the user did not write. Not checking the motive: when it is ill-typed, the user
sees an unrelated unification error.

**Limits.** No generalisation of dependent hypotheses (unlike Agda's `with`, `rewrite` only
touches the goal); no occurrence selection; no arithmetic beyond conversion.

### 2.2 McBride 2000, Elimination with a Motive

Stored: `sources/papers/mcbride-2000-elimination-motive/elim.ps` (19 pp.).

**Key ideas.**
- An elimination rule is parametric in its conclusion, the *motive* Φ; using a hypothesis
  means choosing Φ from the goal (p.1-2, §2). For an instantiated hypothesis
  (`m ≤ 0`, `xxs : Vect A (s m)`), the motive is indexed over the whole domain, so the goal
  is *generalised and constrained by equations*: Φ x⃗ ↦ ∀y⃗. x⃗ = t⃗[y⃗] → P[y⃗] (p.3-4, §2.3-2.4).
- The equations are heterogeneous ("John Major" equality, p.5, §3): `a = b` may relate
  values of different types, but elimination is only for the homogeneous case; it is
  equivalent to axiom K. Equations over a telescope stay solvable left to right, since solving
  the first unifies the types of the next.
- `BasicElim` (p.6-9, §5): (1) *targetting* unifies the user's targets with the rule's
  targetting expressions until the rule is "fully targetted"; (2) the motive is the goal with
  equations inserted, refined by *fixing* parametric, large and irrelevant premises and
  *deleting* constraints `x_j = y'_i` that only duplicate an argument (p.7-8, §5.2); (3)
  refinement applies the rule to `refl` proofs (p.8-9, §5.3).
- `Unify` (p.9-10, §6) eliminates the equational premises by six transitions (deletion,
  coalescence, conflict, injectivity, substitution, cycle) on first-order constructor terms;
  conflict, injectivity and cycle are derived per datatype as elimination rules ("no
  confusion", "no cycles", §7.3-7.4).
- *Elimination with abstraction* (p.14-15, §8): the recursion of a function induces a relation
  (`x + y = z`) and an elimination rule for it (`+-elim`); a goal that mentions `x + y` is
  first transformed by `Abst` to `∀x. e = x → P[x]` and then eliminated. The paper says
  outright that `P[y⃗; x]` "may not be well-typed". Rewriting by a law `s = t` is `AbstElim`
  with the rule derived from `=-elim` (p.15).
- Derived eliminators give derived pattern matching: `Vect-snoc-elim`, `N-plus-rec`,
  `N-compare`, which splits the plane into `y + s x`, diagonal, `x + s y` (p.16-17, §9).

**Steal.** Constraint by equation: never abstract an instantiated index, generalise it to a
variable plus an equation, then let unification or a solver discharge the equation. For an
array op whose argument has shape `[n * m]`, the elaborator should introduce
`k`, `k = n * m` instead of rewriting inside the type. Also the principle that a rule comes
with "operating instructions" (what it targets, p.6), which is what an array combinator's
type signature already is.

**Avoid.** The heterogeneous equality with K is not needed in Idris 2's homogeneous use and is
the source of the without-K problems Cockx later fixed (§2.5); Idris's `Equal` is
heterogeneous in statement but `rewrite` uses it homogeneously.

**Limits.** First-order constructor unification only; arithmetic equations such as
`n * m = m * n` are left as premises.

### 2.3 McBride and McKinna 2004, The view from the left

Stored: `sources/papers/mcbride-2004-view-from-left/view.ps` (47 pp., preprint).

**Key ideas.**
- Programs are elaborated by *programming problems* on the left: patterns are specialised by
  unification, and `with` (written `|` in Epigram) adds an intermediate value to the
  left-hand side (p.31-32, §5).
- *Abstracting from types* (p.32-33, §5.1, Fig. 12): the `with` rule abstracts the elaborated
  term `s` from the label and from the context (`abst`, "an inverse to substitution"), and
  "these abstractions must be typechecked again, to ensure that replacing the elaborated term
  s by a variable has not compromised validity". The helper function is checked in the
  extended context; the main program calls it. This is the rule Idris 2 and Agda implement.
- *Views* (p.33-36, §6): a datatype family whose constructors' indices are computed terms,
  `Compare x (x + s y)`, `Compare x x`, `Compare (y + s x) y`, proved total by `compare`;
  matching on it instantiates the *arguments* `m`, `n` with arithmetic patterns. `absDiff`
  then needs no subtraction. A view is an elimination operator `T-view : ∀t P. ... → P t`
  (§6.1, p.35); the language derives it from the covering function.

**Steal.** Views are the user-facing answer to shape arithmetic: a `Split n` view with the one
constructor `MkSplit : (q, r : Nat) -> Split (q * d + r)` lets tiling code *match* `n` as
`q * d + r` instead of rewriting into it; `Compare` lets slicing match `n` as `i + s k`. For
reshape, a view `Factor (n * m)` exposes the factors. The re-check of the abstraction (Fig. 12)
is the property that Idris's `rewrite` lacks.

**Avoid.** The paper's views cost a runtime value of the view type; in an array language
views over shapes must be at quantity 0 or their constructors must be erasable (indices are
erased; only the decision, if any, remains).

**Limits.** The abstraction is still syntactic modulo conversion; the paper does not address
equations the user did not anticipate with a view.

### 2.4 Goguen, McBride, McKinna 2006, Eliminating dependent pattern matching

Stored: `sources/papers/goguen-2006-eliminating-dependent-pattern-matching/paper.pdf` (20 pp.).

**Key ideas.**
- Dependent pattern matching (Coquand) is translated into a type theory with eliminators
  (Luo's UTT) plus K, preserving reduction: every clause holds as a computation rule of the
  translated term (abstract, p.1; Theorem 24, p.18).
- Patterns carry *inaccessible terms* (Brady's terminology) for what specialisation forces
  rather than what is matched: `inv (f s) (imf s) ↦ s` (p.3-4, §2-2.1).
- Programs are recognised as *splitting trees*; coverage is decidable (Lemma 5, §2.2).
- The equipment (p.14-15, §4.1-4.2): heterogeneous `Eq`, `case_D`, `Below_D`/`rec_D` for
  structural recursion (course of values), `NoConfusion_D`.
- Unification transitions (Lemma 16, p.15): deletion, solution, injectivity, conflict, cycle,
  each *as a term*. Specialisation by unification (Definition 19, p.16) iterates them with
  three outcomes: negative success (conflict or cycle), positive success with a most general
  idempotent unifier, or failure when no transition applies.
- `Comp-f` computation types (Definition 22-23, p.17-18) let the translation remove the
  function symbol while keeping the clauses as reductions.

**Steal.** The split between *matched* and *forced* positions: an array function's shape
arguments are forced (inaccessible) by the array argument's type and need no run-time check,
which is what lets the compiler erase them. The three-outcome contract of unification is the
interface a shape solver must also honour: proved, refuted (a type error at the user's
program point), or *stuck* (ask for a proof or a run-time coercion).

**Avoid.** Relying on K-based deletion silently: it is fine in Idris 2 (which has K), but the
translation itself is not needed by a compiler that consumes checked TT; the compiler should
consume Idris's case trees, as AGENTS.md requires.

**Limits.** Unification is over constructor forms; `n + m = k` fails.

### 2.5 Cockx, Devriese, Piessens 2016, Unifiers as equivalences, and Cockx 2017 (thesis)

Stored: `sources/papers/cockx-2016-unifiers-as-equivalences/paper.pdf` (14 pp., personal-use
copy); `sources/papers/cockx-2017-dependent-pattern-matching-thesis/thesis.pdf` (166 pp.).

**Key ideas.**
- Syntactic unification ignores types and is unsound in dependent settings:
  `(Bool, true) = (Bool, false)` in `Σ A:Set. A` cannot be refuted without UIP, and
  injectivity of `sing` would prove injectivity of a type constructor (p.1-2, §1).
- Unification problems are *telescopes of equations* (Definition 1, p.4, §2.1-2.2), with each
  equation's type depending on the solutions of the previous ones (equality "lying over").
- A unifier is a telescope map `σ : Γ' → Γ(ē : ū ≡ v̄)`; a **most general unifier is an
  equivalence** `Γ(ē : ū ≡_Δ v̄) ≃ Γ'`; a disunifier is an equivalence with `⊥`
  (Definitions 2-4, p.4, §2.3). Rules are equivalences and compose (§4), so soundness is
  checked once per rule, inside the theory.
- Unification has three outcomes (p.3, §2): positive success, negative success, or failure
  "because there is no unification rule that applies", which "is unavoidable in general".
- Reverse unification rules generalise indices before injectivity (p.9, §6.2).
- The thesis's future work (PDF p.141-142, printed p.129-130, §5.1): *custom unification
  rules* supplied by the user as a proof of `(f x ≡ f y) ≃ (x ≡ y)`, admissible if they are
  "strong" and metavariable-free; *partial unification* that hands the stuck equations
  (`e₁ : l m ≡ zero`, `e₂ : l m ≡ suc n`) to the user as named proofs. Strong rules keep the
  clauses definitional; Coq's Equations uses non-strong rules and gets clauses that hold only
  propositionally (§5.1 "Unifiers versus strong unifiers").
- On why `m + n` and `n + m` differ: "if m and n are variables then m + n and n + m will
  never evaluate to the same result no matter how hard we try" (PDF p.21, §1.1).

**Steal.** A shape solver plugs into elaboration exactly as a *unification rule*: when the
unifier is stuck on `n * m =?= m * n`, a solver that returns an equivalence (concretely: a
proof term, at quantity 0) is a sound extension. Partial unification is the right user
interface for shapes the solver cannot decide: bind the residual equation as a named,
erased proof the user (or a library tactic) must supply.

**Avoid.** By-fiat solver answers (no evidence) inside unification: they break the
"equivalence" guarantee and, in this project, the rule that no pass may drop or forge what
Idris proved.

**Limits.** Idris 2's unifier is not Agda's; adopting the framework means changing the forked
elaborator in `compiler/idris`, which accepts programs upstream Idris 2 rejects.

### 2.6 Cockx, Piessens, Devriese 2014, Overlapping and order-independent patterns

Stored: `sources/papers/cockx-2014-overlapping-patterns/paper.pdf` (22 pp.).

**Key ideas.** Clauses are read as definitional equalities with *any-match* semantics, so
`plus` may be defined with the four clauses `plus zero y`, `plus (suc x) y`, `plus x zero`,
`plus x (suc y)` and `n + 0 ↦ n` holds by computation (p.3, §1; p.10, §3-4); commutativity
then has a two-line proof (p.10). Completeness reuses the case-tree coverage check
(Proposition 1); confluence is checked by unifying each pair of left-hand sides and
requiring the right-hand sides to agree under the most general unifier (Proposition 2, p.12,
§5). Costs: first-match semantics is lost, case-tree compilation needs catch-all subtrees,
translation to eliminators is lost (p.10, §4).

**Steal.** The idea that the equations users need about shape arithmetic (`n + 0`,
`n + suc m`, `n * 1`, `n * 0`) can hold by computation, checked by a confluence test, instead of
being proved and rewritten.

**Avoid.** Commutativity and associativity cannot be clauses (their left-hand sides are not
patterns over constructors).

**Limits.** Only equations whose left side is the defined function applied to constructor
patterns.

### 2.7 Cockx 2020, Type theory unchained, and Agda's REWRITE rules

Stored: `sources/papers/cockx-2020-type-theory-unchained/paper.pdf` (27 pp., CC-BY);
`sources/docs/agda/doc/user-manual/language/rewriting.lagda.rst`.

**Key ideas.**
- A proved (or postulated) `p : ∀x̄. f ū ≡ v` registered with `{-# REWRITE p #-}` extends
  *definitional* equality: instances of `f ū` reduce to `v` (p.2, §1). This is equality
  reflection restricted to oriented rules, so logical consistency is not at stake; confluence
  and termination are (p.21-22, §6).
- With `+zero : m + zero ≡ m` and `+suc` as rules, `+comm` goes through unchanged (p.4-5,
  §2.1; the manual, `rewriting.lagda.rst:54-109`). Allais et al.'s ν-rules for `map` and `++`
  are expressible (p.5, §2.2).
- Conditions on a rule (p.12, §3.2): linearity (relaxed to "at least once"), well-typedness
  of both sides at the same type, neutrality of the left-hand side. Matching is higher-order
  and non-linear, all rules apply in parallel (§3.3).
- Agda only checks local confluence (`--confluence-check`: overlapping left-hand sides must
  be joinable and every rule must satisfy the triangle property,
  `rewriting.lagda.rst:331-350`); termination is unchecked (p.22, §6).
- Matching does not reduce pattern-matching definitions, so the `++-assoc` rule for `Vec`
  fails at `n = zero` because the implicit length `{n + m}` has reduced to `{m}`;
  `primRewriteNoMatch` defers that subterm to a conversion check
  (`rewriting.lagda.rst:119-203`).
- Future work (p.22, §6): *local* rewrite rules on module parameters, and *custom η-rules*
  ("any vector of length zero definitionally equal to []").

**Steal.** The vector `++-assoc` example is exactly the array problem: the length index is a
`+` expression that must be matched modulo arithmetic. Rules over shape functions (`n + 0`,
associativity of `+` and `*`, `prod (xs ++ ys) = prod xs * prod ys`, `length (map f xs)`) are
orientable and safe; the language library can ship them as built-in reductions on a
`Shape` type.

**Avoid.** User-defined rewrite rules in general: they change definitional equality per
module, break subject reduction when non-confluent, and are not Idris 2. Commutativity is not
orientable: `m + n ⟶ n + m` loops; it needs normalisation to a canonical order (§2.12-2.13),
not a rule.

**Limits.** No termination check; local confluence only.

### 2.8 Allais, McBride, Boutillier 2013, New equations for neutral terms

Stored: `sources/papers/allais-2013-new-equations-neutral-terms/main.tex`.

**Key ideas.**
- Three relations: oriented computation (βδι), typed judgmental equality with η, and
  propositional equality (`main.tex:107-150`). *ν-rules* are equations between neutral terms
  with the same "nut" (the stuck variable) that hold by Boyer–Moore induction on the nut: `xs
  ++ [] = xs`, `(xs ++ ys) ++ zs = xs ++ (ys ++ zs)`, `map id xs = xs`, `map f (map g xs) =
  map (f . g) xs`, `map f (xs ++ ys) = ...`, `fold` fusion (Table "ν-rules",
  `main.tex:160-185`).
- Normalisation in three stages: βδι evaluation to weak-head normal form, η-expansion by
  type, then ν-rearrangement of stuck spines; the last two never produce a constructor-headed
  term, so ordinary evaluation stays complete for canonical forms (`main.tex:368-450`).
  A sound and complete decision procedure for a simply-typed calculus with lists, fold, map and
  append is formalised in Agda (§Formalization, Correctness, `main.tex:607-1260`).
- Scaling to type theory (`main.tex:1262-1351`): Pollack's syntax-directed typing relies on
  evaluation reaching constructors, hence the mantra "A ν-rule may restart computation
  *within* its contractum but *never* in its enclosing context"; criteria for user ν-rules:
  βδι-ν and ν-ν critical pairs convergent, and termination (e.g. a precedence order such as
  `++ > map > fold`).

**Steal.** This is the cleanest design for shape arithmetic in conversion: canonicalise
*neutral* `Nat`/shape expressions (sums of products of shape variables) *after* ordinary
evaluation, never emitting constructors. Closed shapes still compute; open shapes compare by
normal form. Commutativity is handled by sorting, which is a normal form, not a rule. The
same applies to array combinators: `map f (map g a)` and `reshape (reshape a)` are ν-rules.

**Avoid.** Letting users add ν-rules without the critical-pair and termination checks.

**Limits.** Formalised only for simply-typed lists; the dependent case is planned, not done.

### 2.9 Agda: with-abstraction and rewrite

Stored: `sources/docs/agda/doc/user-manual/language/with-abstraction.lagda.rst`.

**Key ideas.**
- With-abstraction generalises the goal *and the types of the other arguments* over the
  scrutinee (lines 90-171); this generalisation "is not always type correct" (165-168).
- `f ps rewrite eq = v` is `f ps with lhs | eq` followed by `... | .rhs | refl = v`
  (564-604): rewriting *is* with-abstraction plus a match on `refl`, so it inherits both the
  generalisation and its failure modes. `with e in eq` keeps the equation (636-697).
- Translation (888-977): infer the scrutinee types; split the context Δ into Δ1, the smallest
  part in which the scrutinees are typed, and Δ2 (possibly reordered); generalise Δ2 and the
  goal over the scrutinees so that the *normal form* of the result mentions none of them;
  **check that Δ1 → C is type correct**; add an auxiliary function. Worked translations show
  which arguments end up before or after the with-arguments (979-1053).
- Cost (867-885): normalising the goal and argument types and re-checking the generalisation
  can be expensive.
- Ill-typed abstraction (1055-1090): `with fst p` in `H (fst p) (snd p)` fails with
  "fst p != w of type A when checking that the type ... of the generated with function is
  well-formed".

**Steal.** The Δ1/Δ2 split and the explicit well-formedness check: abstract the scrutinee from
every hypothesis that can be generalised, and check the result before using it. Idris's
`bindNotReq` (§2.1) already does the split; its `rewrite` should share it.

**Avoid.** Error messages that print only the generated type; report the subterm whose type
mentions the abstracted term.

### 2.10 Lean 4: rw, subst, generalize, simp, omega

Stored: `sources/code/lean4/` (snapshot at `7cd10322`).

**Key ideas.**
- `kabstract` (`src/Lean/Meta/KAbstract.lean:16-67`): a subterm is a candidate only if its
  head index and argument count match the pattern's (49-50); only then `isDefEq`; occurrences
  are counted and selected with `occs`, rolling back the metavariable context for
  unselected matches (52-64). If the pattern is a free variable and all occurrences are wanted,
  plain `abstract` is used (32-33).
- `MVarId.rewrite` (`src/Lean/Meta/Tactic/Rewrite.lean:28-90`): `kabstract` the left-hand
  side, fail if nothing was found (48-51), build `motive := fun _a => eAbst` and **`check
  motive`**; on failure, the error "motive is not type correct" explains the three-step
  process and suggests `occs`, `simp` or `conv` (57-73). A second check rejects a motive
  whose instantiation changes the type of the expression ("Motive is dependent", 74-79). The
  proof is `congrArg` (82).
- `subst` (`src/Lean/Meta/Tactic/Subst.lean:17-117`): requires one side to be a free
  variable not occurring in the other (28-33), *reverts* the variable, the equation and
  everything depending on them (34), eliminates with `Eq.rec` when the goal depends on the
  equation and `Eq.ndrec` otherwise (68-72), and avoids an ill-typed motive when the goal
  depends on `h : a = b` by abstracting a fresh `hAux : b = a` and using `hAux.symm`, sound by
  proof irrelevance (97-108).
- `generalize` (`src/Lean/Meta/Tactic/Generalize.lean:30-50`) reports "result is not type
  correct"; its transparency is lowered to `implicit` because keyed `isDefEq` matching at
  default transparency hit "max recursion depth" on `((2 ^ 7) + a) - 2 ^ 7` (80-128).
- Docstrings (`src/Init/Tactics.lean`): `rw` tries `rfl` afterwards (629-637); `simp` handles
  dependencies by congruence lemmas (700-729 and the `rw` error text); `omega` decides linear
  arithmetic over `Nat` and `Int` with `/` and `%` by literals, splitting on natural
  subtraction, `min`, `max` (1541-1572).

**Steal.** (1) Check the motive and say why it failed. (2) Keyed matching: compare only
subterms with the pattern's head and arity, never the whole normal form. (3) `subst` is the
robust primitive when one side of the equation is a variable: revert dependents, eliminate,
re-introduce. Shape equations with a variable side (`k = n * m` introduced by generalisation)
are exactly this case. (4) `omega`'s fragment (linear `Nat`/`Int` with literal `*`, `/`, `%`)
covers bounds and offsets in slicing and tiling.

**Avoid.** Default-transparency unfolding during matching (Lean's own issue #3524 note).

**Limits.** `omega` is linear: `n * m = m * n` with both variables is outside it; Lean uses
`ring`-style normalisation (Mathlib) for that.

### 2.11 Rocq: rewrite, generalize dependent, dependent rewrite, ring, lia

Stored: `sources/docs/rocq/doc/sphinx/...` (snapshot at `29f5238e`).

**Key ideas.** `rewrite` rewrites the instances identical to the first match found in
depth-first order; it does not see occurrences under binders that mention the bound variable
(`proofs/writing-proofs/equality.rst:108-230`). `generalize dependent t` generalises `t` and
every hypothesis that depends on it (`proof-engine/tactics.rst:1666-1669`); `apply`'s
second-order case abstracts `t1 … tn` from the target to instantiate a motive, and `pattern`
does it by hand (722-731). `dependent rewrite` rewrites with an equality of dependent pairs
`existT B a b = existT B a' b'` (`reasoning-inductives.rst:1181-1194`). `dependent
destruction`/`dependent induction` are McBride's BasicElim: `generalize_eqs` replaces indices
by variables constrained by (JMeq) equalities, then `simplify_dep_elim` solves them, possibly
using K (1698-1800). `ring` normalises both sides of a (semi)ring equation to the unique
canonical sum of monomials (`addendum/ring.rst:27-45`, 113-130); `lia` decides linear integer
arithmetic over `Z`, `nat`, `N` by linear Positivstellensatz refutations and cutting planes,
complete for linear integer arithmetic (`addendum/micromega.rst:184-231`).

**Steal.** `ring`'s canonical sum of monomials is the decision procedure for the
commutative-semiring fragment of shape arithmetic; `lia` for the linear fragment with
inequalities. Both produce proof terms by reflection.

**Avoid.** First-match-only rewriting; JMeq-based generalisation (needs K).

### 2.12 Allais, Brady, Corbyn, Kammar, Yallop 2025, Frex

Stored: `sources/papers/allais-2025-frex/` (TeX; PACMPL 9 ICFP 2025).

**Key ideas.**
- Simplifiers are designed from universal algebra: a *fral* (free algebra) gives a canonical
  representative of terms modulo a theory's axioms; a *frex* (free extension) does the same
  while evaluating the concrete elements (`new-intro.tex:1-120`). For commutative monoids the
  free extension of `C` by `n` variables is `C × ℕⁿ`: `-6 + (x+3) + (y+x)` evaluates to
  `(-3, 2, 1)` and reifies to `-3 + 2x + y`.
- The universal property gives a design method: equip the representation with the operations,
  prove the axioms, define the map out, prove uniqueness; failure at each step diagnoses a
  missing operation, an unused equation or junk (`overview.tex`, "Homomorphisms, Free
  Models/Algebras, and Free Extensions").
- Implemented in Idris 2 (and Agda), with guaranteed termination, soundness and completeness
  for the declared class of equations, proof extraction, and goal extraction by Idris 2's
  elaborator reflection (`abstract.tex`; `reflection.tex`).
- Measured (`evaluation.tex`): under 0.1 s for terms of size up to 6 (commutative) or 14
  (non-commutative); below 1 s up to size about 30; over 10 s only for some terms of size 45 or
  more, attributed to Idris 2's evaluator (Idris 2 0.5.1).
- Lessons for Idris 2 (`idris2.tex`): most cost is the evaluator; sharing preserved by
  introducing a metavariable for every implicit argument; a `continue` operation to resume
  blocked unification without re-quoting; conversion of blocked problems compares heads first.

**Steal.** Frex is the existing, Idris 2 native, proof-producing solver for exactly the
monoid/commutative-monoid fragment of shape arithmetic, and its design (normal form as the
free model; evaluate concrete parts) is the right shape for a `Shape` normaliser: a shape
expression is a polynomial with natural coefficients over shape variables, i.e. an element
of the free commutative semiring extension of `ℕ`. The proof it produces is erased at
quantity 0, so it costs nothing at run time.

**Avoid.** Running the solver as type-level computation for large shape terms inside the
type checker's evaluator; the timings show the cliff. A native normaliser in the elaborator,
or reflection that builds the proof once, is needed for size 30+ expressions (a rank-8
reshape product is already that size).

**Limits.** The users must state the equation or use reflection, and Idris 2's reflection
hands the driver the *normalised* goal: `(x+1)+y = x+(1+y)` arrives as `(x+1)+y = x+S y`, where
`S y` is an atom distinct from `y`, so the monoid solver infers a false equation and fails
(`reflection.tex:130-145`, examples in `reflection-listings.tex:1-20`); Agda quotes without
normalising. Normalisation turns literal arithmetic into constructors (`1 + y` reduces to
`S y`) before any solver sees it, so a shape normaliser must read `S` as `1 +`. The
evaluation measures only the monoid and commutative-monoid simplifiers.

### 2.13 ghc-typelits-natnormalise

Stored *(other cluster)*: `sources/code/ghc-typelits-natnormalise/` (same revision
`44c1a880`).

**Key ideas.** Nat equalities over `+`, `-`, `*`, `^` are decided by normalising both sides to
a *sum-of-products* form and comparing syntactically (`README.md`; grammar in
`src/GHC/TypeLits/Normalise/SOP.hs:1-80`); subtraction is `a + (-1)*b` over integers with
`isNatural` guards; `(x+2)^(y+2)` normalises to `4*x*(2+x)^y + 4*(2+x)^y + (2+x)^y*x^2`.
`unifyNats` returns `Win`, `Lose` or `Draw [substitution]` and finds unifiers such as
`(a + c) ~ (b + c) ⟹ a := b` and `(2 + a) ~ 5 ⟹ a := 3` (`Unify.hs:410-618`). The evidence it
gives GHC is a `mkPluginUnivCo` coercion, i.e. by fiat (`Normalise.hs:493`, 924).

**Steal.** The SOP normal form and the three-valued result with improving substitutions, so
that `n + 1 = m + 1` solves `n := m` and literal equations solve variables.

**Avoid.** Evidence by fiat. In this compiler the proof must exist (quantity 0) so that the
checked TT is honest.

### 2.14 Diatchki 2015, Improving Haskell types with SMT

Stored *(other cluster)*: `sources/papers/diatchki-2015-smt/paper.tex`.

**Key ideas.** A type-checker plug-in hands GHC's inert constraints on `Nat` to an SMT solver
(linear arithmetic) after GHC's own solver reaches an inert state (`paper.tex` §3.3). Terms
outside the theory are *named* and replaced by variables, which generalises the constraint
(a proof of the general constraint covers the original; a refutation of the general one is
sound only as a refutation) (§4.2, `paper.tex:632-660`). Consistency check, unsat-core style
conflict minimisation, and *improvement*: ask for a model, then prove that a variable must
equal its model value or another variable, or lies on a linear relation (§4.4-4.6,
`paper.tex:872-960`). No evidence is produced beyond "the SMT solver said so"
(`paper.tex:1068-1076`).

**Steal.** Naming foreign subterms (abstraction to atoms) before solving: an array shape that
contains `length xs` or a user function becomes an opaque atom, so the solver works on a
closed theory. Improvement (deriving `x ~ 8` from `2*x ~ 16`) is what lets inference fill in
shapes.

**Avoid.** An external SMT process in the type checker (portability, determinism, evidence),
and by-fiat evidence.

### 2.15 Xi 2007, Dependent ML

Stored: `sources/papers/xi-2007-dependent-ml/paper.pdf` (75 pp., preprint). See also
*(other cluster)* `sources/papers/xi-1998-dml-bounds/pldi98dml.pdf` for bound-check
elimination.

**Key ideas.** DML(L) is parameterised by a *type index language* L completely separate from
run-time terms; index terms are pure, and singleton types `int(n)` connect them to run-time
values (p.3-4, §1). Lists are indexed by length: `append : 'a list(m) * 'a list(n) -> 'a
list(m+n)` (Fig. 1, p.3); existential indices for `filter` (`[n:nat | n <= m]`, Fig. 2, p.4).
Type equality is decided by a constraint relation over L (§3.1); `L_int` has integer
arithmetic (§3.3.2). Indices erase (§4.5). Constraint solving (§7, p.50-51): nonlinear
constraints are rejected outright; linear ones are negated and refuted by Fourier–Motzkin
elimination with a GCD tightening step for integers ("sound but incomplete"); Fourier–Motzkin
"is almost always superior to the simplex method" on the constraints met in practice. Array
subscripting with a precondition `i < n` removes bound checks; programs fall back to checked
`arraySub` when the invariant is not expressed (Fig. 28-29, p.52-53).

**Steal.** Equality of index terms decided by a constraint solver *as part of type
equality*, with indices erased; the separation of index language from programs (the shape
language is a small first-order theory, not arbitrary Idris functions); explicit fallback to a
checked operation when a fact is not provable.

**Avoid.** Rejecting nonlinear constraints: products of dimensions are nonlinear
(`n * m`); a commutative-semiring normaliser is needed in addition to linear arithmetic.

### 2.16 Henriksen and Elsman 2021, Towards size-dependent types

Stored *(other cluster)*: `sources/papers/henriksen-2021-size-types/paper.pdf`; its successor
*(other cluster)* `sources/papers/bailly-2023-size-dependent/paper.pdf`.

**Key ideas.** Futhark's sizes in types are restricted to *variables and constants*; anything
else is let-bound to a fresh name, existentially if necessary, with the origin remembered for
error messages (p.8, §5 "Nontrivial size expressions"). Explicit size coercions are checked
at run time. On 12,000 lines of benchmarks: 66 dynamic coercions, mostly in input handling;
`backprop` needs coercions because `n + 1` split into `1` and `n` is inexpressible (p.9, §6).
Idioms change: `tabulate_2d`, `indices : [n]a -> [n]i64` instead of `iota (length xs)`
(p.10). Sizes are erased from types because arrays carry their shape at run time anyway
(p.10, §7).

**Steal.** Explicit, checked coercions as the escape hatch, with the origin of every
generated size name kept for diagnostics. Library combinators that return the relation in
the type (`indices`) instead of computing a size.

**Avoid.** The restriction itself: the task here is "no ceiling"; `n + 1`, `n * m` and
products of shapes must be first-class. Futhark's own successor
(`bailly-2023-size-dependent`) lifts it.

### 2.17 Equality saturation: egg, egglog, slotted e-graphs

Stored in the repository: `sources/papers/willsey-2021-egg/`,
`sources/papers/zhang-2023-egglog/`, `sources/papers/wu-2026-slotted-egraphs/`.

**Key ideas.** egg answers "are these two terms equal under these axioms" by adding both to an
e-graph, saturating with the axioms as rewrites and testing whether they share an e-class;
on TASO's axiom checks it was 15× faster than Z3 (`willsey-2021-egg/02-background.tex:415-450`).
E-class analyses attach lattice data to classes (`04-tricks.tex:72-110`), e.g. a constant or a
canonical polynomial. Slotted e-graphs add binding and canonical bag/set children for AC
operators (`wu-2026-slotted-egraphs/main_compressed.tex:27-44`). Proof production for
egglog is future work (`zhang-2023-egglog/old-related-work.tex:119-120`).

**Steal.** For *program* rewriting on the MLIR side (fusing `reshape`/`transpose`/`map`),
not for type equality: shape terms in the e-graph can carry their canonical SOP polynomial as
an e-class analysis so that shape-equal arrays merge.

**Avoid.** E-graphs as the type-level decision procedure: saturation is not a normal form,
may not terminate, and produces no proof term in the egg/egglog versions stored here.

### 2.18 Brady 2021, Idris 2 QTT

Stored in the repository: `sources/papers/brady-2021-idris2-qtt/`.

**Key ideas used here.** Quantity 0 arguments are erased; types and proofs live at 0. This is
why a shape equality proof is free at run time, and why shape *indices* in an array type are
erased (AGENTS.md: `!idr.erased`), while the run-time shape, if needed, is separate data.

### 2.19 MLIR's shape dialect witnesses

Stored in the repository: `sources/docs/mlir/docs/Dialects/ShapeDialect.md`.

**Key ideas.** Shape computations are lowered in three stages: error-carrying values,
*constrained* form with explicit evidence (`!shape.witness` from `shape.cstr_eq`, consumed by
`shape.assuming` regions), and asserting form (`assert`) for code generation (lines 9-25,
104-160). `shape.const_witness true` is the folded witness
(`.toolchain/llvm-project/mlir/include/mlir/Dialect/Shape/IR/ShapeOps.td:927-939`).

**Steal.** This is MLIR's counterpart of the equality proof: an equality Idris *proved*
lowers to no witness at all (static shapes, or `shape.const_witness true`); a Futhark-style
checked coercion lowers to `shape.cstr_eq` guarding the region that relies on it.

## 3. Synthesis: what the array language needs

The language: `Array : (shape : Vect r Nat) -> Type -> Type` (rank `r` and shape at quantity
0, element type monomorphised), with `reshape`, `transpose`, `concat`, `flatten`, slicing and
tiling. Typical obligations: `prod [n, m] = prod [m, n]` (reshape of a transpose),
`n * m = m * n`, `n + 0 = n`, `(a + b) + c = a + (b + c)` (concat), `q * d + r = n` (tiling),
`i + k < n` (slicing).

1. **Decide shape equality by normal form, not by user rewriting.** Shape expressions are
   terms of the commutative semiring `(ℕ, +, *, 0, 1)` over shape variables and opaque atoms.
   Their equational theory is decided by normalising to a sum of products with sorted
   monomials (Rocq `ring`, §2.11; natnormalise SOP, §2.13; Frex's free extension, §2.12).
   Because Idris evaluation turns `1 + k` into `S k` before any solver sees it, the
   normaliser must read `S` as `1 +` and literals as constants (Frex's reflection pitfall,
   §2.12); anything else (a user function, `length xs`) is named as an atom (§2.14).
   Two designs:
   - *Library level* (no change to Idris 2): a `Shape` normaliser in `libs/` in the style of
     Frex, producing an erased proof `normalise s = normalise t -> s = t`; the array API states
     its obligations as `auto` arguments or uses elaborator reflection to extract the goal.
     It stays Idris 2 (AGENTS.md: the compiler implements Idris 2 over prelude and base), and
     the proofs are real (no by-fiat evidence, §2.13-2.14). Cost: type-level evaluation speed
     (Frex's timings, §2.12).
   - *Conversion level* (in the forked elaborator, `compiler/idris`): canonicalise neutral
     shape arithmetic after evaluation, as ν-rules do (§2.8), so `n * m` and `m * n` are
     *definitionally* equal and no proof is ever written. Ordinary evaluation stays complete for
     constructor forms (Allais's mantra). This changes Idris 2's definitional equality, which
     AGENTS.md's "implements Idris 2 fully" does not forbid but which makes programs accepted
     here and rejected upstream; it is a decision for the proposal.
2. **Linear facts by a decision procedure.** Bounds for slicing and tiling (`i + k < n`,
   `q * d + r = n` with literal `d`) are linear integer arithmetic: Fourier–Motzkin with GCD
   tightening (DML, §2.15) or `omega`'s procedure (§2.10) or `lia` (§2.11). Non-linear facts
   in the variables are the semiring normaliser's job.
3. **Rewrite safely when users do rewrite.** Adopt Lean's checks (§2.10): keyed matching on
   the goal as written, not its normal form; type-check the motive and report the offending
   subterm; generalise dependent hypotheses with the Δ1/Δ2 split (Agda, §2.9; McBride's
   constraint by equation, §2.2); fall back to `subst` when one side is a variable.
4. **Generalise instead of abstracting instantiated indices.** When an argument's shape is a
   compound expression, introduce `k` and `k = e` (McBride §2.2, Diatchki's naming §2.14,
   Futhark's let-binding §2.16) so that unification sees variables and the solver sees one
   equation.
5. **Treat the solver as a unification rule with three outcomes** (Cockx §2.5, Goguen §2.4):
   proved (an erased proof), refuted (a type error at the user's line, with the unsat core,
   §2.14), stuck (partial unification: a named, erased obligation the user discharges, or an
   explicit checked coercion, §2.16).
6. **Views for arithmetic patterns.** Provide `Compare`, `Split d n`, `Factor` views (§2.3)
   so tiling and blocking code match shapes as `q * d + r` instead of rewriting.
7. **Built-in reductions on shape functions.** `prod (xs ++ ys) = prod xs * prod ys`,
   `length (xs ++ ys) = length xs + length ys`, `map`-fusion on shape vectors: orientable,
   confluent rules (Cockx §2.7, Allais §2.8); commutativity only via the normal form.
8. **Erase everything at quantity 0, lower what is proved to static MLIR.** Shapes and proofs
   are quantity 0 (§2.1, §2.18). After monomorphisation, literal shapes give static
   `tensor<4x8xf32>` types and `tensor.expand_shape`/`collapse_shape` whose verifier checks
   products of static sizes; symbolic shapes give `?` dimensions with the run-time shape
   carried as `index` values; only unproved, explicitly coerced equalities produce run-time
   checks (`shape.cstr_eq`/`cf.assert`, §2.19). A proved equality never reaches MLIR.

## 4. Not stored

- Cockx, Tabareau, Winterhalter, "The Taming of the Rew", POPL 2021,
  https://doi.org/10.1145/3434341: HAL served the Anubis bot challenge; not evaded.
- Cockx, Devriese, Piessens, "Eliminating dependent pattern matching without K", JFP 26
  (2016), https://doi.org/10.1017/S0956796816000174, and Cockx and Devriese, "Proof-relevant
  unification", JFP 28 (2018), https://doi.org/10.1017/S095679681800014X: both open, both
  revised as chapters of the stored thesis; not stored separately.
- Grégoire and Mahboubi, "Proving equalities in a commutative ring done right in Coq",
  TPHOLs 2005, https://doi.org/10.1007/11541868_7: the open copy is on HAL (Anubis); the
  algorithm is documented in the stored Rocq `ring.rst`.
- Agda's `Rewriting.hs` and `LHS/Unify.hs`, Lean's `omega` and `simp` implementations,
  Mathlib's `ring`: not taken (the stored documentation and the stored Lean core files cover
  the behaviour cited).
- OpenAlex lookups: the API's shared daily budget was exhausted (HTTP 429) on 2026-10-09;
  Crossref and the arXiv abstract pages were used for identifiers instead.
