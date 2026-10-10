# Elaborators and kernels: what makes dependent type checking fast

Notes of the elaborators cluster (topic: Fast dependent type checking and elaboration),
2026-10-09. Every claim is cited to a stored path. Paths are relative to `sources/` as staged
in `scratchpad/selfhost/tc/stage/sources/` (they become `sources/...` on merge); paths
starting `compiler/` are this repository's fork of Idris 2, read in place at HEAD `05070421`
plus the uncommitted working tree; `papers/brady-2021-idris2-qtt/`,
`papers/ullrich-2019-counting-immutable-beans/` and `code/idris2/` are already in the
repository. A claim is marked **measured** (a published number with its benchmark and
machine), **read** (what the code or text does) or **claimed** (an assertion its source does
not back with a number).

Contents: 1 what was read; 2 what dominates elaboration time; 3 term representations; 4
caches; 5 conversion and unification; 6 instance search; 7 compiled normalization; 8
parallelism and incrementality; 9 SMT in F*; 10 every published speed comparison; 11 the Idris
2 elaborator this repository forks; 12 what idris-mlir's type checker should take; 13 what to
avoid; 14 limits of this evidence; 15 cross-links.

## 1. What was read

Papers (all read in full unless noted): `papers/demoura-2021-lean4/` (Lean 4, CADE 2021),
`papers/selsam-2020-tabled-typeclass/` (and its `anc/` data), `papers/carneiro-2024-lean4lean/`,
`papers/gregoire-2002-strong-reduction/` (staged by the kernels cluster; read here),
`papers/boespflug-2011-full-throttle/`, `papers/wenzel-2009-parallel-isabelle/`,
`papers/wenzel-2013-read-eval-print/` (the evaluation and protocol sections),
`papers/barras-2015-async-coq/`, `papers/swamy-2016-fstar-mumon/` (sections 1, 7, 8),
`papers/martinez-2019-meta-fstar/` (sections 2.2, 4–6; the formal sections skimmed),
`papers/gross-2024-scalable-proof-engine/` (sections 1–4 and 6–7; the construction in 5
skimmed), `papers/brady-2021-idris2-qtt/` (conclusion), `papers/ullrich-2019-counting-immutable-beans/`
(only as cited by the Lean 4 paper).

Code: `code/smalltt/` (README in full; `CoreTypes.hs`, `Evaluation.hs`, `Unification.hs`,
`Elaboration.hs` head), `code/elaboration-zoo/` (`GluedEval.hs`, `05-pruning/README.md`),
`code/lean4/` kernel (`type_checker.{h,cpp}` caches, `whnf`, `is_def_eq_core`, lazy delta;
`expr.h`; `replace_fn.cpp`; `instantiate.cpp`; `runtime/sharecommon.h`;
`library/instantiate_mvars.cpp` header) and elaborator (`Meta/ExprDefEq.lean` approximations,
delta heuristics and caches; `Meta/WHNF.lean` cache; `Meta/SynthInstance.lean` structure;
`Language/Lean.lean` incrementality notes), `code/lean4lean/` (`README.md`,
`EquivManager.lean`, cache fields of `TypeChecker.lean`), `code/nanoda_lib/` (`README.md`,
`util.rs` arena and caches, `tc.rs` `def_eq`).

Docs: `docs/lean-reference-manual/Manual/Releases/v4_{8,17,18,19,23}_0.lean`,
`docs/agda/doc/user-manual/{tools/performance.rst,language/lossy-unification.lagda.rst,language/opaque-definitions.lagda.rst}`,
`docs/pop-in-fstar/book/under_the_hood/uth_smt.rst` (staged by the SMT cluster; read here).

Idris 2 (this repository's fork): `compiler/idris/src/Core/Value.idr`,
`Core/Normalise/{Eval,Convert}.idr`, `Core/Unify.idr` (structure, Term/Closure instances,
`solveConstraints`), `Core/AutoSearch.idr` (structure), `Core/Context.idr` (lookup),
`TTImp/Elab/{Delayed,Ambiguity}.idr` (comments).

## 2. What dominates elaboration time

The sources disagree because they measure different workloads; the useful result is the
list of distinct cost centres, each with its evidence.

1. **Proofs, in proof-heavy developments.** "Checking proofs requires most of the total
   runtime" (Isabelle; `papers/wenzel-2009-parallel-isabelle/parallel-isabelle.pdf` §1.3,
   claimed as an observation). In the Odd Order Theorem proofs are 60% of the non-blank text
   and "Coq spends 90% of its time on them" (**measured**, no machine stated for this figure;
   `papers/barras-2015-async-coq/full.tex` lines 237–238).
2. **Conversion that falls back to evaluation.** When a check needs real computation, the
   reducer dominates: the 4-colour reducibility check "represents most of the computation
   time of the whole proof" (`papers/boespflug-2011-full-throttle/cpp11.pdf` §4); Lean 4.19
   made well-founded definitions opaque because kernel reduction of them "tends to be
   prohibitively slow" (`docs/lean-reference-manual/Manual/Releases/v4_19_0.lean`, the #5182
   entry, line 57).
3. **Unification heuristics that unfold too much.** The Lean elaborator's defeq carries
   comments on specific performance fixes: reducing projections before comparing structure
   instances because "unifying the field instances slowed down unification" (issue 1986),
   and the projection-first step in lazy delta to stop unfolding an expensive term
   (`code/lean4/src/Lean/Meta/ExprDefEq.lean` lines 2500–2535;
   `code/lean4/src/kernel/type_checker.cpp` lines 969–979). Agda added `--lossy-unification`
   for the same cost, "most dramatically when reducing an application of `f` would produce a
   large term" (`docs/agda/doc/user-manual/language/lossy-unification.lagda.rst` lines 49–51).
4. **Instance search.** In Lean 3's mathlib, 26,401 typeclass queries took at least 20 ms
   each, 1,601 s in total, median 34 ms, 99th percentile 318 ms, maximum 13.6 s, 70 of them
   over 1 s (**measured**, computed here from
   `papers/selsam-2020-tabled-typeclass/anc/mathlib_typeclass_queries_ge20ms.csv`, whose
   column is in microseconds despite its `milliseconds` header; mathlib commit `9ac26cb6`
   per `anc/README`; machine not stated). Queries took "upwards of ten seconds" and
   traversed one diamond tower "upwards of twenty-five thousand times"
   (`papers/selsam-2020-tabled-typeclass/typeclass.tex` lines 294–295).
5. **Metavariable bookkeeping and term size.** Normal forms are "extremely large", so quoting
   to beta-normal forms "reliably destroys performance" (`code/smalltt/README.md` lines
   228–233, claimed); the nested-pair test `pairTest` is exponential in Agda, Coq, Lean and
   Idris 2 and instant in smalltt (**measured**, `code/smalltt/README.md` lines 735–746). Coq
   evar contexts are named, so each evar costs linear space in the binders above it and
   fresh-name generation is quadratic (`papers/gross-2024-scalable-proof-engine/rewriting.tex`
   lines 651–659). Coq's `let` typing rule substitutes into the type once per binder, so a
   linear-size proof still checks in quadratic time: about 1 s at 2,000 binders and 10 s at
   7,000 (**measured**, lines 781–795; machine not stated in the text read).
6. **Things outside elaboration.** Parsing is cheap but not free: "on mathlib we average 41ms
   parsing per 1000 LoC" (**measured**, no machine; `code/lean4/src/Lean/Language/Lean.lean`
   lines 30–31); megaparsec made old smalltt about 40 times slower than flatparse, which
   parses 2–3 million lines per second (`code/smalltt/README.md` lines 645–649, machine of
   the benchmark section). Serialization "often takes a quadratic hit" (`vecTest`: Agda 1.128 s
   elaboration vs 4.098 s total, Idris 4.465 vs 6.277; `code/smalltt/README.md` lines
   732–739). Garbage collection: 5–15% of Isabelle session time (Wenzel 2009 §5.2); more than
   20% for the largest Odd Order files (`papers/barras-2015-async-coq/full.tex` lines
   932–937); GHC RTS arena settings are worth "easily 30-50%" (claimed,
   `code/smalltt/README.md` lines 586–594).

## 3. Term representations

**Core terms with cached metadata (Lean kernel).** Expressions are locally nameless (`bvar`
de Bruijn indices inside terms, `fvar` names for entered binders;
`code/lean4/src/kernel/expr.h` lines 66–82). Each node carries a 64-bit data word with the
hash, flags (`has_fvar`, `has_expr_mvar`, ...) and the loose-bound-variable range, read in
O(1) (`expr.h` lines 124–155). Instantiation skips any subterm whose loose-bvar range is below
the offset (`code/lean4/src/kernel/instantiate.cpp` lines 16–22, 60–62), so substitution does
not walk closed subterms. The bit-packing is a soundness hazard: the range is 20 bits of the
word and the overflow check once returned 0, which "effectively turns on all of the
optimizations", an exploitable bug found by failing a proof
(`papers/carneiro-2024-lean4lean/main.tex` lines 630–642).

**Values with closures (NbE; smalltt, elaboration-zoo).** Elaboration outputs core syntax
with de Bruijn indices; evaluation produces values with closures (`Closure Env Tm`) and
de Bruijn levels for neutral variables (`VLocalVar Lvl Spine`), so going under a binder is
`appCl` with a fresh level and no term traversal (`code/smalltt/src/CoreTypes.hs` lines
23–67; `code/smalltt/src/Evaluation.hs` lines 26–32, 162–181). "Smalltt uses no substitution
operation whatsoever" (`code/smalltt/README.md` lines 170–174). The README argues Lean's
kernel substitution plus memoization "ends up being slower and more complicated than a
straightforward NbE implementation" (lines 165–168; claimed, no benchmark isolating it).

**Glued values.** A head that is a top-level definition evaluates to `VUnfold head spine
~unfolded`: the neutral spine is built eagerly, the unfolded value lazily, and application
acts on both (`code/smalltt/src/CoreTypes.hs` line 42; `code/smalltt/src/Evaluation.hs` line
37; `code/elaboration-zoo/GluedEval.hs` lines 5–53). Conversion can force the unfolding,
quotation can stop at the head, and work is shared between the two. Three quote modes
(`UnfoldAll`, `UnfoldMetas`, `UnfoldNone`) choose per use (`Evaluation.hs` lines 178–181).
Elaboration passes pairs `G {g1, g2}`: the least-reduced value (for printing and
solutions) and a forced one (for computing) (`code/smalltt/README.md` lines 400–417). The cost
is "a noticeable constant overhead"; disabling glueing would make ForceTree 2x faster
(`code/smalltt/README.md` lines 246–251, 809–812; the second **measured** on the benchmark
machine).

**Hash-consing.** nanoda interns every expression in an `IndexSet` arena and refers to it by
a 32-bit index whose top bit selects the persistent export DAG or the per-check DAG, so
equality of pointers is structural equality and every cache is keyed by a 32-bit integer
(`code/nanoda_lib/src/util.rs` lines 34–69, 394–400); loose-bvar count, `has_fvars` and hash
are cached per node (lines 518–534). Lean's kernel does not hash-cons on construction but
has a separate maximal-sharing pass (`code/lean4/src/runtime/sharecommon.h`) and caches
traversals by `(pointer, offset)` only for nodes whose reference count says they may be
shared (`code/lean4/src/kernel/replace_fn.cpp` lines 22–40; `expr.h` lines 345–364).
Kovács argues hash-consing does not address the dominant blow-up, beta-reduction, and skips
it (`code/smalltt/README.md` lines 270–294; claimed). Gross et al. show the opposite failure:
without sharing under binders, proof-producing rewriting is quadratic, and Lean and Coq
each rely on pointer sharing plus memoization ("developments using the proof engine have
come to rely on the speedups") (`papers/gross-2024-scalable-proof-engine/rewriting.tex`
lines 683–688, 724–732).

**Named contexts cost.** Coq's evar contexts are named, so trivial substitutions take linear
space; Gross et al. conclude a compact identity-substitution representation "is only
naturally available for de Bruijn representations" (`rewriting.tex` lines 651–657). Isabelle's
nominal kernel closes a term over a binder in O(1), which "does not scale to dependently
typed proof assistants" (lines 764–768). Aehlig et al. reported a significant gain moving
variables from strings to de Bruijn (cited at line 1365).

**Contextual metavariables.** A meta is a function over its scope; smalltt stores the scope
as a bitset mask (`LvlSet`) and builds the spine from the environment
(`code/smalltt/src/Evaluation.hs` lines 60–77; `code/smalltt/src/Elaboration.hs` lines
36–57). Operations are linear in the local scope, measured "not a significant bottleneck in
realistic user-written code" (claimed, `code/smalltt/README.md` lines 214–221).

## 4. Caches

| System | Cache | Key | Notes |
| --- | --- | --- | --- |
| Lean kernel | infer (two: check / infer-only), `whnf_core`, `whnf`, unfold | expression (structural hash) | `code/lean4/src/kernel/type_checker.h` lines 26–42; `whnf` does not cache easy cases (`type_checker.cpp` lines 702–736) |
| Lean kernel | `is_def_eq` success and failure pair sets | ordered by hash | not a union-find: `is_def_eq` "is not transitive, so taking a transitive closure of successful pairs would make its result depend on evaluation order" (`type_checker.h` lines 33–41); the arguments-first step in lazy delta records failures (`type_checker.cpp` lines 995–1006) |
| lean4lean | the same, but defeq via a union-find `EquivManager` | expression | `code/lean4lean/Lean4Lean/EquivManager.lean`; `TypeChecker.lean` lines 19–23. The C++ kernel at the Lean pin has moved away from union-find (above); the two disagree |
| nanoda | `eq_cache` of sorted pointer pairs, `defeq_fail_cache` keyed with the eager-mode flag, instantiate/abstract/level-substitution caches by `(ptr, offset)` | 32-bit pointers | `code/nanoda_lib/src/tc.rs` lines 957–1006; `util.rs` lines 175–199; `union_find.rs` exists but `tc.rs` does not use it |
| Lean elaborator | defeq cache, two kinds: permanent (no metavariables, standard config) and transient (instantiated keys, so a backtracked assignment cannot poison it); not cached if constraints were postponed during the check | `DefEqCacheKey` | `code/lean4/src/Lean/Meta/ExprDefEq.lean` lines 2438–2480, 2550–2565 |
| Lean elaborator | whnf cache only for closed terms without expression metavariables | config + expression | `code/lean4/src/Lean/Meta/WHNF.lean` lines 1039–1075 |
| Lean elaborator | `instantiateMVars` linear in nested delayed assignments, with a `scope_cache` to keep sharing | — | `code/lean4/src/library/instantiate_mvars.cpp` header |
| Lean elaborator | `realizeValue`, "parallelism-aware caching of `MetaM` computations" | — | `docs/lean-reference-manual/Manual/Releases/v4_23_0.lean` line 697 |
| smalltt | approximate occurs check visits each active solved meta at most once (per-meta cache of the last checked meta) | meta index | `code/smalltt/src/Unification.hs` lines 52–65; `code/smalltt/README.md` lines 530–542 |
| Idris 2 (fork) | none for conversion, whnf or inference; definitions looked up by name on every unfolding | — | §11 |

Two design rules fall out. Cache only what is a function of its key: the Lean kernel can
cache defeq results because kernel terms have no metavariables and free variables are
globally unique (`type_checker.h` lines 33–37), and the elaborator splits caches by whether
metavariables are present for the same reason. And caching a semi-decision procedure
transitively changes its answers (the kernel comment above).

## 5. Conversion and unification

**Kernel conversion (Lean, lean4lean, nanoda).** `is_def_eq_core`: quick structural check and
the success cache; `whnf_core` without delta and with cheap projections; proof
irrelevance; lazy delta reduction; then constants, fvars, projections; `whnf_core` again;
application congruence; eta; structure eta; string literals; unit eta
(`code/lean4/src/kernel/type_checker.cpp` lines 1128–1203; the same list in prose,
`papers/carneiro-2024-lean4lean/main.tex` lines 537–554). Lazy delta unfolds the side with
the greater definitional height first; with equal heads and regular hints it first tries the
arguments, caching failure (`type_checker.cpp` lines 962–1018). Closed `Nat` terms reduce
by bignum arithmetic, and a closed `t` against `Bool.true` is fully reduced, the path proofs
by `decide` take (lines 1051–1062, 1133–1146). Carneiro: the worst case is "galactically
large", so heuristics keep re-checking "within the same ballpark as when it was first
checked" (`main.tex` line 538), and the kernel is incomplete and has fuel and depth limits
(lines 466–482). Lean's type theory does not even terminate (the Abel–Coquand example,
lines 457–476).

**Elaborator unification (Lean).** Pattern unification with five stated conditions, and
seven named approximations (A1–A7: unfold let-variables, quasi-patterns, first-order
approximation, constant approximation, ...) controlled by configuration
(`code/lean4/src/Lean/Meta/ExprDefEq.lean` lines 807–960); eleven lazy-delta heuristics
(lines 1830–1849). Implicit-argument defeq is postponed to a second pass
(lines 280–410). The kernel and the elaborator implement conversion twice.

**smalltt's bounded speculation.** Three states: Rigid (may solve metas; on equal defined
heads, try the spines in Flex, and on failure unfold and continue in Full), Flex (no meta
solutions, no unfolding), Full (unfold everything). Unification "backtracks at most once on
any path" and never makes approximate meta solutions (`code/smalltt/README.md` lines
327–397; `code/smalltt/src/Unification.hs` lines 321–382). Lean and Coq permit approximate
solutions (`f ?0 = f ?1` solved by `?0 := ?1`), Agda does not (README lines 335–340); Agda's
opt-in `--lossy-unification` is that approximation, sound but incomplete
(`docs/agda/doc/user-manual/language/lossy-unification.lagda.rst` lines 8–31, 63–72).

**Solutions that stay small.** Eta-short solutions first, retrying eta-long on failure;
spine eta-contraction `?0 x y = ?1 x y` to `?0 = ?1` (`code/smalltt/README.md` lines 419–452;
`Unification.hs` lines 259–307). Solutions are quoted without unfolding any definition or
solved meta, while scope and occurs conditions are still checked modulo full beta through
three quote modes (rigid, flex with a validity flag, full check), with `Irrelevant` standing
for a variable that only occurs in an unfolding that vanishes (README lines 454–504;
`Unification.hs` lines 82–213). Partial renamings are arrays from levels to levels
(`Unification.hs` lines 29–46, 219–249).

**Pruning.** When a solution would mention a variable outside the meta's scope, a fresh meta
over fewer arguments replaces the offending one, if its type still makes sense; also used to
intersect spines and to accept non-linear spines whose repeated variables are unused
(`code/elaboration-zoo/05-pruning/README.md`). The dynamic-pattern-unification papers staged
by the unification cluster (`papers/abel-2011-dynamic-pattern-unification/`,
`papers/gundry-2012-dynamic-pattern-unification/`) carry the theory.

**Meta freezing.** Metas are solvable only within one top-level definition (as in Agda);
frozen metas cannot be solved, which bounds occurs checking to the active block
(`code/smalltt/README.md` lines 506–542).

## 6. Typeclass and instance search

Tabled resolution keeps a table from each subgoal (up to alpha-equivalence) to its answers
and its waiting consumers, a generator stack and a resume stack; a subgoal already in the
table is consumed from its answers, so a diamond is solved once and a cycle terminates under
the bounded-term-size assumption (`papers/selsam-2020-tabled-typeclass/typeclass.tex`
lines 353–473, the algorithm in its Figure 1). Environments are persistent, so suspending
and resuming a branch is O(1) (lines 553–572). The table key is the goal with unassigned
metas renamed to canonical names; a one-bit "contains a metavariable" flag per subterm
lets normalization skip ground subterms, which avoids tabling's usual quadratic cost on
`Append` (lines 574–600). Instances are indexed by a discrimination tree (lines 604–614).
Lean's implementation follows this layout (`code/lean4/src/Lean/Meta/SynthInstance.lean`
lines 50–110, 165, 191–199, 474–590, 644) with a heartbeat budget (lines 20–30).

**Measured:** on a failing tower of diamonds, Lean 3, Coq, Agda and Scala all blow up
exponentially (each passes 10 s by a tower height of about 10–17) while tabled Lean 4 stays
near zero up to height 100 (`papers/selsam-2020-tabled-typeclass/figures/diamonds_perf.png`;
`typeclass.tex` lines 655–692). Machine and system versions are not stated; the benchmarks
are synthetic because mathlib queries could not be ported (lines 657–660).

Idris 2 resolves `auto` and interface arguments by depth-bounded backtracking search that
runs the elaborator under `catch` per candidate, with no table
(`compiler/idris/src/Core/AutoSearch.idr` lines 42–150, 372–430). Diamonds therefore cost
what they cost Lean 3.

## 7. Compiled normalization

**Bytecode (Coq `vm_compute`).** Strong reduction by compiling to a ZAM variant that treats
a free variable as an accumulator collecting its arguments, then reading back
(`papers/gregoire-2002-strong-reduction/strong-reduction.pdf` §§2–4). **Measured** on a
Pentium III 1 GHz, 256 MB (Coq 7, Figures 5–6): factorial 9 normalization 14.2 s vs Coq CBV
61.6 s and lazy 466 s; parity of factorial 9 0.447 s vs 46.9 s and 4.82 s; equivalence tests
20–100x faster than the lazy checker; the 4-colour reducibility checks 33–45x faster than
Coq and as fast as OCaml bytecode (1.68–69.6 s vs 1.18–73.1 s), with native OCaml a further
3.5–5.6x; Coq's standard library 3% slower (135 s vs 131 s) because compilation buys nothing
when terms are already normal (§6).

**Native (Coq `native_compute`).** Translate CIC terms to OCaml with accumulators and use the
stock compiler; "untyped normalization by evaluation" (`papers/boespflug-2011-full-throttle/cpp11.pdf`
§1). **Measured** (Table 1, 64-bit and 32-bit machines with 4 GB, CPU not stated): BDD
21.98 s bytecode vs 11.36 s native; 4-colour 3 h 7 min vs 34 min 47 s; Lucas–Lehmer 29.80 s
vs 8.47 s (standard reduction 10 min 10 s); RecNoAlloc 14.32 s vs 1.05 s; typically a 2–5x
gain over bytecode, 7–14x without allocation. The table does not say whether OCaml
compilation time is included. The compiler joins the trusted base (Conclusion).

**F*.** A slow Krivine-machine normalizer for conversion and unification, plus a CBV NbE
evaluator "vastly more efficient" (claimed, no figure), plus native plugins: metaprograms
extracted to OCaml and dynamically linked (`papers/martinez-2019-meta-fstar/paper.tex`
lines 4912–5040). Native execution of the `canon_semiring` tactic is about 5x faster than
interpretation (0.212 s vs 1.156 s; **measured**, lines 5387–5398, 5485; machine not
stated).

**Lean.** The kernel evaluates closed `Nat` operations by bignums and `reduceBool` by
compiled code, which lean4lean calls "unsound by design" because compiled code can be
decoupled from the kernel's definition (`papers/carneiro-2024-lean4lean/main.tex`
lines 524–535).

**Reflection beats proof-producing rewriting.** In Coq, `setoid_rewrite` on Fiat
Cryptography ran out of memory past 60 GB at 4 limbs; `rewrite_strat` took 70 min at 4 limbs
and extrapolates to 11 h at 5 and "1000x the age of the universe" at 17; Lean did one limb in
under a minute and did not finish two limbs in four hours (**measured**, machine not stated
in the text read; `papers/gross-2024-scalable-proof-engine/rewriting.tex` lines 520–597).
A reflective rewriter gives a 10–1000x speed-up over the original pipeline, and its extracted
OCaml is about 10x faster than running in Coq's kernel (lines 1951–1975).

## 8. Parallelism and incrementality

The enabling property is "practical proof irrelevance": nothing downstream needs a proof,
only that it was checked, so proofs become futures (Isabelle "proof promises",
`papers/wenzel-2009-parallel-isabelle/parallel-isabelle.pdf` §§1.3, 3–4) or opaque proofs
processed later (Coq, `papers/barras-2015-async-coq/full.tex` lines 225–245, 448–470).

**Measured, Isabelle 2009** (first-generation Mac Pro, 4 cores, Poly/ML 5.2.1; §5): 3.2x
relative and 3.0x absolute speedup on 4 cores for HOL-Auth and HOL-Nominal, below 1.3x for
the sequential HOL bootstrap; 3–10% overhead best case, 22% worst; about 5x on 8 worker
threads (preliminary, other people's machines); first attempts reached only 1.5–2.0x before
tuning the scheduler, removing global state and enlarging the heap; the stop-the-world GC is
5–15% of the time and sits on Amdahl's sequential fraction.

**Measured, Coq 8.5 asynchronous processing** (Xeon 2.3 GHz, 12 cores; full.tex lines
887–946): Odd Order latency for using the last file after changing the first: Coq 8.4 about
2.5 h on one core, 90 min on two, one hour at best; with proofs deferred, 12 min on one core,
8 on two, 7 on twelve; checking all proofs on 12 cores then takes 13 more minutes, 20 in
total, 166% of the ideal. Workers are OS processes because OCaml then had no shared-memory
parallelism; state is marshalled, with unwanted data swapped for keys in a key-weak table
(lines 563–611). The kernel change was under 300 lines (line 561).

**Lean 4.** Kernel checking in parallel to elaboration (4.17, #6368), code generation in
parallel (4.18, #6770), theorem bodies elaborated in parallel to each other and to other tasks
(4.19, #7084), parallelism-aware caching (4.23, #9798), on top of snapshot trees from 4.8
(#3014) (`docs/lean-reference-manual/Manual/Releases/v4_17_0.lean` lines 33–34;
`v4_18_0.lean` lines 417–431; `v4_19_0.lean` lines 50–53, 390–408; `v4_23_0.lean` line 697;
`v4_8_0.lean` line 183). **No release note gives a speedup.** Within a command, incremental
reuse uses promise-backed snapshot trees and syntactic comparison
(`code/lean4/src/Lean/Language/Lean.lean` lines 82–130).

**External checkers.** lean4lean checks modules in parallel but is benchmarked single-threaded
because of memory (`papers/carneiro-2024-lean4lean/main.tex` line 764); nanoda has a
thread-count option (`code/nanoda_lib/src/util.rs` line 891) and no benchmark.

**Idris 2** has none of this: one elaboration thread, no proof futures (§11).

## 9. SMT in F*

F* encodes every pure term into one uninterpreted sort `Term`, boxes primitives, guards
recursive definitions with fuel (`--initial_fuel`/`--max_fuel`, retrying the query at
increasing fuel) and inversion with ifuel, and steers Z3 with quantifier patterns
(`docs/pop-in-fstar/book/under_the_hood/uth_smt.rst` lines 188–330, 496–740). The prelude
alone is about 150,000 lines of SMT2 per query file (lines 240–270). Proofs can be "flaky":
the same query succeeded 4 of 5 times under `--quake`; Z3 is deterministic only in a strict
sense and a renamed variable can change the answer (lines 1396–1440). Recorded unsat cores
("hints") can fail to replay when instantiation depended on facts outside the core (lines
1854–2010).

**Measured** (Meta-F*, machine not stated): proving Poly1305's `poly_multiply` by SMT alone
succeeds 0.5% of the time at the default resource limit and 24% at 100x, over 200 seeds; with
the `canon_semiring` tactic first it succeeds 100% at the default limit in 3.07 s total
(native) (`papers/martinez-2019-meta-fstar/paper.tex` lines 5360–5486). A related lemma is
proven automatically "about 32%" of the time (line 1403). Verifying generated parsers for
enumerations of size 10 takes 690 s by SMT only, 63 s by a tactic only, 19.4 s with a 5-line
context-pruning tactic before SMT (lines 5560–5585). F* 2016 (Core E5 1620v3, 16 GB, F*
0.9.1.1, Z3 4.4.0): 6,500 lines of metatheory check in 3 min 12 s; 2,416 lines of TLS verify
in 40 s; a 4,466-line handshake proof (8,577 lines in Coq) takes "over half an hour"
(`papers/swamy-2016-fstar-mumon/paper.pdf` §§7–7.3). Hyper-heaps sped up "some benchmarks"
by "more than a factor of 20" (§5, no benchmark named: claimed). F* relies on Z3 even for
reduction, and controlling it "requires intimate knowledge of F*'s SMT encodings" (§7.2).

## 10. Every published speed comparison found

| Comparison | Numbers | Benchmark | Machine / versions | Source | Caveats |
| --- | --- | --- | --- | --- | --- |
| smalltt vs Agda, Coq, Lean, Idris 2: elaboration | stlc10k: 0.306 / 16.160 / N/A / 12.982 / 129.635 s; stlcSmall10k: 0.072 / 22.8 / 1.388 / 5.244 / 13.496 s; stlcSmall1M: 8.725 s / TL / 149 / 615 / OOM | generated Church-coded STLC files | Intel 1165G7, 16 GB, 28 W; Agda 2.6.2, Coq 8.13.2, Lean 4 nightly 2021-11-20, Idris 2 with PR 2203 | `code/smalltt/README.md` 652–722 | five years old; systems do different work (Agda/Idris serialize, Lean compiles); smalltt times are warm reloads, 20–30% faster than first loads; Agda had a parse blow-up on large files |
| same: asymptotics | idTest, pairTest: smalltt 0.000 s, all others TL; vecTest elab 0.078 / 1.128 / 0.769 / 0.244 / 4.465 s | `bench/asymptotics.*` | as above | `code/smalltt/README.md` 725–746 | Lean elaboration linear on pairTest, its compilation exponential |
| same: raw conversion | NatConv10M 0.712 / 19.7 / SO / 61.1 / 173.88 s; TreeConv23 3.325 / 13.7 / 4.699 / 0.001 / 25.38 s | `bench/conv_eval.*` | as above | `code/smalltt/README.md` 749–782 | Lean's 0.001 s are approximate-conversion shortcuts, not evaluation |
| same: evaluation | ForceTree23: smalltt 4.372, Agda 15.93, Coq vm_compute 0.731, Coq compute 5.407, Lean reduce 62.7, Lean eval 5.52, Idris 2 OOM; NfTree23: smalltt 3.023 vs Coq 4.99–7.187 | `bench/conv_eval.*` | as above | `code/smalltt/README.md` 784–814 | Coq's VM wins light allocation; smalltt wins normalization, attributed to GHC's RTS |
| lean4lean vs C++ kernel | Lean 37.01 vs 44.61 s; Batteries 32.49 vs 45.74 s; Mathlib (+B.+Lean) 44.54 vs 58.79 min (1.21–1.40x) | re-checking compiled packages | i7-1255U 2.1 GHz, single-threaded, mathlib4 rev 526c94c | `papers/carneiro-2024-lean4lean/main.tex` 764–778 | the abstract says "20% and 50%" (line 88), the table 21–40% |
| Tabled vs SLD instance search | Lean 4 flat to tower height 100; Lean 3, Coq, Agda, Scala exceed 10 s at height about 10–17 | synthetic failing diamond tower; `Append` | not stated | `papers/selsam-2020-tabled-typeclass/` Figures 2a–b, lines 655–692 | synthetic only |
| vm_compute vs Coq interpreter | 10–100x vs lazy, 1.1–100x vs CBV; 4-colour 33–45x; stdlib 3% slower | factorial, Church arithmetic, 4-colour, stdlib | Pentium III 1 GHz, 256 MB, Coq 7 | `papers/gregoire-2002-strong-reduction/strong-reduction.pdf` §6 | 2002 hardware |
| native_compute vs vm_compute | 2–5x typical, 7–14x without allocation; 4-colour 3 h 7 min → 34 min 47 s | BDD, 4-colour, Lucas–Lehmer, Mini-Rubik, Cooper, RecNoAlloc | 64- and 32-bit, 4 GB, CPU not stated | `papers/boespflug-2011-full-throttle/cpp11.pdf` Table 1 | compile time inclusion not stated |
| Isabelle parallel checking | 3.0–3.2x on 4 cores; under 1.3x for HOL; about 5x on 8 threads | HOL-Auth, HOL-Nominal, HOL sessions (2–15 min) | Mac Pro 4 cores, Poly/ML 5.2.1 | `papers/wenzel-2009-parallel-isabelle/parallel-isabelle.pdf` §5 | 8-thread figure preliminary |
| Coq asynchronous proofs | latency 1 h → 7 min (12 cores); full check about 4x faster on 12 cores; 20 min total | Odd Order Theorem | Xeon 2.3 GHz, 12 cores, Coq 8.4 vs 8.5 | `papers/barras-2015-async-coq/full.tex` 887–946 | one development |
| Proof-producing vs reflective rewriting | setoid_rewrite OOM at 4 limbs; rewrite_strat 70 min at 4 limbs; Lean > 4 h at 2 limbs; reflective 10–1000x faster; extracted 10x faster than kernel | Fiat Cryptography | not stated in the text read | `papers/gross-2024-scalable-proof-engine/rewriting.tex` 520–597, 1951–1975 | extrapolations beyond 4 limbs |
| SMT alone vs tactic + SMT | 0.5–24% vs 100% success; 690 s vs 19.4 s (parsers, size 10) | Poly1305 lemma, 200 seeds; parser generator | not stated | `papers/martinez-2019-meta-fstar/paper.tex` 5387–5585 | |
| Idris 2 self-build | about 90 s | Idris 2 building itself | Dell XPS 13, Ubuntu | `papers/brady-2021-idris2-qtt/conclusion.tex` 194–198 | 2021, no breakdown |

Claims of speed with no benchmark behind them in the stored sources: Lean 4's "new
elaboration procedure is more general and efficient than those implemented in previous
versions" (`papers/demoura-2021-lean4/paper-kit.pdf` §5); Lean 4's parallel elaboration
(release notes, §8); nanoda (README has no benchmark); F*'s NbE evaluator being "vastly more
efficient" (Meta-F* line 4966); F*'s "factor of 20" for hyper-heaps; smalltt's argument that
NbE beats Lean's substitution kernel (no isolating benchmark); Agda's `--lossy-unification`
and opaque definitions (documented as performance features, no numbers); the custom
exceptions "roughly 1/5 the overhead" (an old, unpublished benchmark,
`code/smalltt/README.md` lines 615–617).

## 11. The Idris 2 elaborator this repository forks

Read in `compiler/idris/src/` (HEAD `05070421` and working tree):

- **Values are thunks without update.** `Closure` is `MkClosure opts locals env term` or an
  evaluated `MkNFClosure` (`Core/Value.idr` lines 107–113). Arguments are pushed as unevaluated
  closures under CBN (`Core/Normalise/Eval.idr` line 141), and forcing a variable re-evaluates
  its closure (`evalLocClosure`, lines 223–226); results are written back only in specific
  case paths (`updateLocal`, line 252). Default evaluation is CBN (`Core/Value.idr`,
  `defaultOpts`). This is call-by-name, not call-by-need: repeated use of an argument repeats
  its evaluation.
- **Binders are host functions.** `NBind` holds its scope as `Defs -> Closure -> Core NF`
  (`Core/Value.idr` lines 128–129), so every comparison under a binder re-runs evaluation.
- **"Glued" is not glued.** `Glued` pairs a `Core (Term)` and a `Core (NF)` computation, not
  memoized: each `getNF` re-normalizes (`Core/Normalise/Eval.idr` lines 20–35, 602–608).
  There is no lazy unfolding branch per head as in §3.
- **Conversion normalizes both sides first.** `Convert Term` is
  `convGen ... !(nf defs env x) !(nf defs env y)` (`Core/Normalise/Convert.idr` lines
  430–432); argument lists are evaluated in full before a cheap head comparison
  (`allConv`, lines 125–134). No defeq, whnf or infer cache exists.
- **Unification** checks syntactic equality, then normalizes both sides
  (`Core/Unify.idr` lines 1291–1314). Against a metavariable it quotes and re-evaluates with an
  emptied context (`clearDefs`) to avoid unfolding, then retries with definitions
  (lines 1316–1350): an unbounded version of smalltt's rigid/flex/full idea, paid by
  quote/eval round trips. Postponed constraints are retried by scanning every guess until no
  progress (`solveConstraints`, lines 1514–1522), which is quadratic or worse when many
  constraints wait.
- **Every unfolding looks the name up.** `evalRef` calls `lookupCtxtExact` on each
  reference and checks the timer (`Core/Normalise/Eval.idr` lines 295–312). Spines are linked
  lists, and meta arguments are appended to the stack with `++` (line 269).
- **Search** is depth-bounded backtracking with no tabling (§6); ambiguous names elaborate
  every alternative under `catch` (`TTImp/Elab/Ambiguity.idr` lines 390–450).

The measured consequence is §10's smalltt rows: Idris 2 was the slowest system on elaboration
(stlc10k 129.6 s, 424x smalltt, 10x Lean) and ran out of memory on ForceTree22–23. Brady
reports only a 90 s self-build (`papers/brady-2021-idris2-qtt/conclusion.tex` lines
194–198), and says Idris 2 follows smalltt by "minimising substitution of unification
solutions" (line 196). These numbers are 2021; the fork has not been measured by this pass.

## 12. What idris-mlir's type checker should take

1. **NbE with de Bruijn indices in terms, levels in values, closures for binders, and no
   substitution.** Smalltt's design is the only one measured to beat every production
   system on elaboration by one to two orders (§10). Closure entry is O(1); quotation
   converts levels to indices once.
2. **Glued heads and paired values.** Lazily unfolded `VUnfold` heads, three quote modes and
   `G` pairs keep meta solutions, error messages and serialized terms small without a second
   evaluator (§3). This also serves this compiler's own output: what Emit receives should be
   the unfolding-minimal term.
3. **Bounded speculation in unification** (Rigid/Flex/Full, one backtrack per path) and no
   approximate meta solutions by default (§5). Approximate solutions (Lean, Coq, Agda's lossy
   mode) are faster on some conversions (TreeConvM in §10) but change which programs mean
   what; offer them per definition, as Agda's `INJECTIVE_FOR_INFERENCE` does, if at all.
4. **Eta-short solutions, spine eta-contraction, pruning with typed metas, meta freezing
   per top-level block, and the per-meta occurs-check cache** (§5).
5. **Kernel-style caches where the key determines the answer.** For closed,
   metavariable-free terms: infer, whnf and defeq success/failure caches as plain pair sets
   (not union-find, per the current Lean kernel's reasoning, §4). For terms with
   metavariables: a transient cache keyed on instantiated terms, dropped when constraints
   were postponed (§4).
6. **Cached per-node metadata in the term arrays**: hash, loose-variable range, has-meta and
   has-free-variable bits, read in O(1) to skip traversals (Lean `expr.h`, nanoda `util.rs`).
   Store the range wide enough or check it, never by a silently saturating field
   (`papers/carneiro-2024-lean4lean/main.tex` lines 630–642).
7. **Hash-consed core terms as 32-bit indices into arenas** (nanoda), so equality and cache
   keys are integer compares. This fits the array-programming direction of the
   representation work: terms as columns of a table, not boxed trees. Hash-consing does not
   replace NbE's sharing of beta-reductions (§3), so it belongs to the stored core terms, not
   to values.
8. **Tabled instance search** with persistent state, alpha-normalized keys short-circuited
   by a has-meta bit, discrimination-tree indexing and a fuel budget (§6). Whether Idris's
   `base` interface hierarchy already produces diamond towers deep enough to matter is not
   measured here (recalled: `Monad`/`Applicative`/`Functor` form one); the exponential case
   is reachable by construction once user hierarchies grow.
9. **Proofs as futures.** Quantity-0 arguments and proofs are, by QTT, never needed at run
   time, which is exactly Isabelle's "practical proof irrelevance"; check proof bodies of
   total, erased-only definitions in parallel and late, with the type known first
   (Isabelle 3.0–3.2x on 4 cores; Coq latency 1 h to 7 min, §8). This would fit the
   one-runtime-per-core model of proposal 0005 (`proposals/README.md`, the 0005 entry) if
   elaboration of a definition were a task; conjecture.
10. **A compiled evaluator for closed, total computation**, staged: the NbE interpreter
    for open terms; compiled code (this compiler's own MLIR pipeline) for closed heavy
    computation, as `vm_compute`/`native_compute` did (2–45x, §7). AGENTS.md already makes
    the runtime the one meaning of every primitive, which is the condition for doing this
    soundly; Lean's `reduceBool` shows the failure mode when compiled code can diverge from
    the definition (§7).
11. **SMT only behind a decision procedure that normalizes first**, for side conditions such
    as shape arithmetic: F*'s measurements say raw SMT on nonlinear goals is unstable
    (0.5–24% success) and that canonicalize-then-SMT or prune-then-SMT is both robust and
    faster (§9). Keep SMT out of conversion.
12. **A fast parser and an RTS tuned for allocation** (flatparse 2–3 MLOC/s; GC 5–20% of
    checking time; arena sizing 30–50%, §2). Here, the runtime is ours.
13. **A benchmark suite from day one**, reusing smalltt's files (`code/smalltt/bench/`)
    translated to Idris, plus instance-search diamonds and a large real library, run on both
    targets: every system in §10 that was measured improved, and every unmeasured claim in
    §10 remains a claim.

## 13. What to avoid

- Locally nameless or named contexts for metavariables (Coq's quadratic evar contexts,
  Gross et al., §2–3).
- Substituting `let` bodies into types during checking (Coq's quadratic `let` rule, §2).
- Re-evaluating thunks (Idris 2's CBN closures) and re-normalizing "glued" pairs (§11).
- Normalizing both sides before comparing (Idris 2's `Convert Term`), instead of comparing
  heads and spines lazily with unfolding by definitional height (Lean, smalltt).
- Retrying all postponed constraints in a loop (Idris 2's `solveConstraints`); wake only the
  constraints blocked on a newly solved meta.
- Untabled backtracking instance search (§6).
- Two independent conversion implementations (Lean's kernel and Meta) drifting apart; this
  repository's AGENTS.md already forbids holding one concept twice.
- Unbounded optimism in conversion (smalltt README lines 341–347) and caches whose answers
  depend on evaluation order (Lean kernel comment, §4).
- Trusting compiled evaluation that is not tied to the definitions it replaces (`reduceBool`).
- SMT as the reducer (F* §7.2): controlling reduction through encodings needs "intimate
  knowledge" of them.

## 14. Limits of this evidence

- The only cross-system elaboration benchmark is smalltt's, run in 2021 by smalltt's author
  on synthetic files; Lean 4 was a 2021 nightly and Idris 2 a 2021 branch. Nothing here
  measures Lean 4.19+'s parallel elaboration, current Agda, Rocq 9, or this fork.
- Smalltt has no inductive types, pattern matching, universes or termination checking
  (`code/smalltt/README.md` lines 86–94); its speed is for the fragment it implements.
  Kovács says himself it is "not as nearly as fast as it could possibly be" and lacks
  real-world tuning (lines 48–56).
- Several sources state no machine (tabled resolution, native_compute's CPU, Meta-F*,
  Gross et al.'s main text).
- Lean 4's tabled resolution was evaluated only synthetically; the mathlib CSV is Lean 3
  SLD data.
- Lean 4's parallel elaboration has no published speedup in the stored release notes.
- Agda's performance page is a stub (`docs/agda/doc/user-manual/tools/performance.rst`
  line 11).
- Not stored: the Lean 4 thesis or any Lean elaborator paper with measurements (none was
  sought beyond the plan); Agda's `agda-bench` results (no publication located); Kovács's
  `normalization-bench` repository (cited at `code/smalltt/README.md` line 599, not
  fetched).

## 15. Cross-links

- Staged by other clusters of this pass and used here: `papers/gregoire-2002-strong-reduction/`
  (kernels cluster), `docs/pop-in-fstar/book/under_the_hood/uth_smt.rst` (SMT cluster),
  `papers/abel-2011-dynamic-pattern-unification/` and
  `papers/gundry-2012-dynamic-pattern-unification/` (unification theory),
  `papers/farber-2022-kontroli/` and `code/kontroli/` (concurrent proof checking for Dedukti),
  `papers/zhou-2023-mariposa/` (SMT instability), `papers/carneiro-2020-metamath-zero/`.
- Already in the repository: `papers/brady-2021-idris2-qtt/`,
  `papers/ullrich-2019-counting-immutable-beans/` (the Lean 4 compiler's reference counting,
  cited by `demoura-2021-lean4` §3), `papers/kovacs-2022-staged/`,
  `papers/kovacs-2024-closure-free/`, `code/idris2/`, `docs/idris2/`.
- Same project, other clusters' files: `code/lean4/` (dependent-equality and SMT clusters),
  `docs/agda/` (dependent-equality cluster), `docs/pop-in-fstar/` (SMT cluster); this
  cluster's additions are recorded in each folder's `SNAPSHOT.elaborators.md`.
