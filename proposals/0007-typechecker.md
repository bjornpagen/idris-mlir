# 0007: a state-of-the-art type checker and elaborator

**Status:** proposed (2026-10-09). Nothing here is built.

**Goal.** The fork's elaborator (compiler/idris, upstream Idris 2's,
now our code) becomes a type checker that is faster than Lean 4 and F* on
measurable workloads, while implementing Idris 2 fully.

**Sources.** Under `sources/`, topic "Fast dependent type checking and
elaboration"; reading notes in `sources/notes/type-checking/`.

**Leads, not mandates.** Array programming (0004), flattened data (0006), a
relational core, and SMT were all candidates. This proposal keeps what the
evidence supports and says why for each.

**Claims** are marked: *read*, *measured*, *conjecture*, *decision*.

## 1. Where the time goes today, and the first step

Nothing is measured yet. Decision: stage T0 measures before anything
changes.
- the per-phase profile of elaborating base and the frontend itself:
  parsing, desugaring, unification, normalisation and conversion, instance
  and auto search, coverage, totality, TTC write;
- `logTime` (Core.Context.Log) and a sampling profile of stage 0 on Chez,
  committed as the baseline record.

Every target below is a ratio to that baseline, or to a named external
benchmark.

## 2. The design, by layer

### 2.1 Terms: flat, hash-consed, with explicit sharing (adopted)

- **Representation.** Terms live in an arena as flat nodes (0006's columnar
  layout), with de Bruijn indices in terms and levels in values.
  Hash-consing gives every distinct subterm one integer id.
- **What it deletes.**
  - Syntactic equality becomes an integer comparison.
  - Conversion checking only normalises when ids differ.
  - Normal forms, weak-head normal forms and definitional-equality results
    are cached in tables indexed by id.
- **Evidence.**
  - Lean 4's kernel relies on sharing and caches for exactly this (*read*
    `code/lean4`, `papers/demoura-2021-lean4`).
  - Hash-consing is a standard technique (*read*
    `papers/filliatre-2006-hash-consing`).
  - Kovács's smalltt shows what careful representation buys over Agda, Coq,
    Lean and Idris on elaboration benchmarks (*read* `code/smalltt`, whose
    README holds the comparison).

### 2.2 Evaluation: glued normalisation by evaluation, then compiled (adopted)

- **Evaluation.** NbE with glued values: an unfolded value plus a cheap
  delayed form, so conversion can decide without unfolding. Approximate
  conversion is tried first, and metacontext operations are cheap (*read*
  `code/smalltt`, `code/elaboration-zoo`).
- **Compiled reduction.** For heavy evaluation (proofs by reflection,
  compile-time evaluation, large `decide`), terms are compiled to native
  code through idris-mlir's own MLIR backend, Coq's `native_compute` done
  with our compiler (*read* `papers/gregoire-2002-strong-reduction`,
  `papers/boespflug-2011-full-throttle`). idris-mlir already JIT-compiles
  closed calls for compile-time evaluation (idr-eval's LLJIT); the
  elaborator reuses that path.

### 2.3 Unification and instance search (adopted)

- **Unification.** Dynamic pattern unification with postponement (*read*
  `papers/abel-2011-dynamic-pattern-unification`,
  `papers/gundry-2012-dynamic-pattern-unification`, `code/pattern-unify`),
  over the hash-consed terms.
- **Instance and auto search are tabled,** as in Lean 4 (*read*
  `papers/selsam-2020-tabled-typeclass`). It is bounded by a counted budget,
  never wall time, so it is deterministic. Swift's type checker is the
  warning: overloads combined with constraint solving blow up without
  bounds (*read* `docs/swift`, `papers/benes-2025-simple-essence-of-overloading`).

### 2.4 Shape arithmetic and dependent rewrite (adopted, shared with 0004)

- **Polynomial normalisation of `Nat` expressions in conversion.** Commutative
  ring laws make `n * m = m * n` and `n + 0 = n` definitional, with no
  rewrite needed. This is the theory decided in 0004's `types.md`.
- **Rewrite,** in increasing order of reach:
  - Refl elimination when the rewritten side is a variable;
  - telescope generalisation when it is a term;
  - a search over which occurrences form the motive, with one bitmask per
    candidate, checked cheaply on hash-consed terms;
  - a diagnostic that names the blocking dependency when none fits.

  *Read* `papers/mcbride-2000-elimination-motive`,
  `papers/cockx-2016-unifiers-as-equivalences`.

### 2.5 Decision procedures: search outside, checked inside (adopted, bounded)

A solver never decides a proof. It searches, and the result becomes a term
the kernel checks.
- **Lean's `bv_decide` is the model:** a SAT solver produces an LRAT
  certificate, which a verified checker accepts (*read*
  `papers/cruzfilipe-2017-lrat`, `papers/pollitt-2023-lrat-cadical`,
  `docs/lean-reference-manual`).
- **SMT** through MLIR's `smt` dialect and SMT-LIB export, with
  certificates in Alethe or cvc5's proof format, reconstructed into terms
  (*read* `papers/schurr-2021-alethe`, `papers/barbosa-2022-proof-production`,
  `papers/armand-2011-smtcoq`, `papers/blanchette-2016-hammering`).
- **F* trusts its solver; this design does not.** F*'s and Dafny's model
  (*read* `papers/swamy-2016-fstar-mumon`, `papers/leino-2010-dafny`) is
  rejected, because a solver's answer is not an Idris term, and trusting it
  would be a `believe_me` in the type checker. Mariposa's measurements of
  solver instability are a second reason (*read* `papers/zhou-2023-mariposa`).
- **Uses:**
  - shape inequalities;
  - bounds that Presburger cannot decide;
  - the test-time verification of idr rewrites (Alive2-style; *read*
    `papers/lopes-2015-alive`).
- **Determinism.** Solver limits are counted resources, and certificates are
  cached by query hash, so builds stay byte-identical.

### 2.6 A small kernel, and fast checking (adopted)

- **Kernel and elaborator separate,** by the de Bruijn criterion (*read*
  `papers/pollack-1998-believe-machine-checked-proof`). The kernel checks
  elaborated terms. An independent re-checker can run in tests, as
  lean4lean and nanoda do for Lean (*read* `code/lean4lean`,
  `code/nanoda_lib`, `papers/carneiro-2024-lean4lean`).
- **Kernel speed target:** Metamath Zero's checking speed as the bar (*read*
  `papers/carneiro-2020-metamath-zero`, `code/mm0`); Dedukti and Kontroli for
  λΠ checking (*read* `papers/assaf-2016-dedukti`, `papers/farber-2022-kontroli`).

### 2.7 Parallelism (adopted where independent; GPU rejected for now)

- **What runs in parallel.**
  - Definitions whose signatures are known check independently.
  - Modules check in dependency order.
  - Both are maps over the module graph: one frontend process per module
    today, and shards (0005) once they exist.

  Isabelle's and Coq's asynchronous proof processing are the precedent
  (*read* `papers/wenzel-2009-parallel-isabelle`, `papers/barras-2015-async-coq`),
  and Newton's parallel type checking measures the speedups available
  (*read* `papers/newton-2016-parallel-type-checking`).
- **The array core is used where the work is regular:**
  - constraint generation over a flat AST;
  - size-change closure as Boolean matrix products;
  - batched conversion of hash-consed terms.
- **Datalog and the relational core:** used for the constraint store and for
  e-graph closure of equalities (*read* `papers/jordan-2016-souffle`,
  `papers/madsen-2016-datalog-to-flix`, `papers/bembenek-2020-formulog`). The
  library is the shared `mlir-relational` recorded in
  `../bumbledb/proposals/0003-idris-port.md` §4.5. Decision: it gets its own
  idris-mlir proposal when the first consumer is built, and is not
  duplicated here.
- **Rejected for now: GPU type checking and interaction-net normalisation.**
  The evidence is research-grade: the GPU front ends in Voetter's thesis
  (*read* `papers/voetter-2021-gpu-frontend-thesis`), HVM2 (*read*
  `papers/taelin-2024-hvm2`), and parallel interaction nets (*read*
  `papers/mackie-2016-parallel-interaction-nets`). Revisit when a measured
  case shows elaboration bound by normalisation that the CPU paths cannot
  serve.

## 3. Rules it keeps

- **Idris 2, fully.** QTT, erasure, totality, interfaces, auto search and
  elaborator reflection keep their meaning for programs over the upstream
  prelude and base. The frontend still consumes checked TT, with its
  representation now flat.
- **No trusted oracle and no escape hatch** in the checker.
- **Deterministic, byte-identical outputs.**
- **Whole-program compilation,** and both targets.

## 4. Staged plan, each stage with its proof

| Stage | Content | Proof |
| --- | --- | --- |
| T0 | per-phase baseline of elaborating base and the frontend | committed record |
| T1 | flat, hash-consed terms (0006 F6) | base and the frontend elaborate with identical TTCs; ≥ 1.5× faster than T0 |
| T2 | glued NbE, caches, approximate conversion | smalltt's benchmark set within 1.5× of smalltt; ≥ 2× over T1 on conversion-heavy files |
| T3 | tabled instance search, bounded | instance-heavy files ≥ 2× over T2; no regression elsewhere |
| T4 | Nat normalisation in conversion; the rewrite ladder | 0004's shape-equality corpus never blocks; upstream's rewrite failures listed in tests become passes |
| T5 | separate kernel and an independent re-checker in tests | every TTC of base re-checked |
| T6 | compiled reduction through idris-mlir | reflection benchmarks ≥ 10× over T2's interpreter |
| T7 | parallel elaboration (processes, then shards) | wall time on base ≤ (1 / cores × 1.5) of T6's |
| T8 | certificates from SAT/SMT, checked as terms | a fixture where the search succeeds and the kernel checks the result |

The headline target, *conjecture until measured*: elaborating a
mathlib-scale Idris corpus faster than Lean 4 elaborates a comparable one,
judged on smalltt's cross-system benchmarks first, because they exist and
are comparable.

## 5. Rejected alternatives

- **Trusting a solver (F*, Dafny):** see 2.5.
- **GPU type checking, now:** see 2.7.
- **Rewriting the elaborator from scratch:** it would break Idris 2
  compatibility and lose the corpus proofs. The fork is changed stage by
  stage, each stage proved by identical TTCs.

## 6. Decisions

- D1. Measure first (T0); every target is a ratio to a recorded baseline.
- D2. Flat, hash-consed terms and glued NbE are the core representation.
- D3. Solvers search; the kernel checks; nothing is trusted.
- D4. A separate small kernel, re-checked in tests.
- D5. Parallelism by independent definitions and modules; GPU deferred
  until measured.
- D6. The relational core gets its own proposal when first built.
