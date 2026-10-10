# Data-parallel functional array compilers: notes for an Idris-hosted typed array language on MLIR

Cluster `dataparallel`. Sources: Futhark (fusion, flattening, uniqueness, size types, memory,
rank-polymorphic elaboration), Dex (index sets, pointful arrays, effects, AD), Accelerate
(skeletons, sharing recovery, delayed-array fusion), SaC (with-loops, shape hierarchy,
with-loop folding/fusion/scalarisation), Lift and RISE/ELEVATE (rewrite rules, strategies as
a language). Every path below is relative to the library root `sources/` (staged under
`stage/sources/`); PDF page numbers are physical pages of the stored PDF ("PDF p."), TeX and
code references are line numbers of the stored file.

The reader in mind is proposal 0004 (`proposals/0004-typed-apl/README.md`), whose section 3.7 limits
rank above 1 to literal ranks and dense word elements, and the AGENTS.md rules: Idris does
types, MLIR does programs; one representation per concept; facts Idris proved live in types.

Contents: [1 Futhark](#1-futhark) · [2 Dex](#2-dex) · [3 Accelerate](#3-accelerate) ·
[4 SaC](#4-sac) · [5 Lift](#5-lift) · [6 RISE and ELEVATE](#6-rise-and-elevate) ·
[7 Cross-cutting synthesis](#7-cross-cutting-synthesis) · [8 What was not stored](#8-what-was-not-stored)

---

## 1. Futhark

Stored: `papers/henriksen-2017-futhark` (PLDI 2017, already in the library),
`papers/henriksen-2013-t2-fusion`, `papers/henriksen-2017-futhark-thesis`,
`papers/henriksen-2019-incremental-flattening`, `papers/munksgaard-2022-memory-optimizations`,
`papers/schenck-2024-automap`; cross-linked (staged by the typed-rank cluster, byte-identical
to what this cluster fetched): `papers/henriksen-2021-size-types` (ARRAY 2021),
`papers/bailly-2023-size-dependent` (FHPNC 2023). Code: `code/futhark/` at
`304c56ff73c48f1842ed3971fe19805a3a85c766`; docs: `docs/futhark/`.

### 1.1 The IR: SOACs, redomap/screma, and the target SegOps

- **Source SOACs and their types.** `map : (α→β) → Πn.[n]α → [n]β`, `reduce`, `scan`, plus
  `redomap ⊙ f d xs ≡ reduce ⊙ d (map f xs)` and `scanomap` likewise; SOACs take and return
  *tuples of arrays* (arrays of tuples are eliminated) so one SOAC can consume and produce
  several arrays (`papers/henriksen-2019-incremental-flattening/paper.pdf`, §2, PDF p. 2-3,
  Figure 1).
- **Why redomap exists.** `red ⊕ e . map f ≡ red ⊕ e . map (foldl g e) . split_p` (list
  homomorphism promotion): recording the *fold function* g rather than f gives a richer fusion
  algebra and an efficient sequentialisation per thread (`papers/henriksen-2013-t2-fusion/paper.pdf`,
  §2.1, PDF p. 3). In the thesis the redomap fold function returns m+l values, m reduced and l
  "mapped results", and the construction guarantees mapped results do not depend on the
  accumulator, which is "crucial for generating parallel code"; this is what makes *horizontal*
  fusion of `map` with `reduce` possible (`papers/henriksen-2017-futhark-thesis/thesis.pdf`, §7.1,
  PDF p. 115-116).
- **Today's IR.** At the pinned revision the map/scan/reduce family is one constructor,
  `Screma SubExp [VName] (ScremaForm rep)` with `ScremaForm { scremaLambda, scremaScans,
  scremaReduces, scremaPostLambda }`, beside `Hist`, `Stream` and a new nonuniform
  `FlatMap` whose lambda returns a segment size `k` and whose result comes back as
  (data, shape array, flag array, offset array) — the segmented-array encoding made an IR
  construct (`code/futhark/src/Futhark/IR/SOACS/SOAC.hs`, lines 81-146).
- **Target constructs.** `segmap_l Σ e`, `segred_l`, `segscan_l` are perfect map nests whose
  innermost operator is map/redomap/scanomap, annotated with a hardware *level* l; a level-l
  construct may contain only level l−1 constructs and sequential code
  (`papers/henriksen-2019-incremental-flattening/paper.pdf`, §2.1, PDF p. 3). In code:
  `SegOp lvl rep = SegMap lvl SegSpace … | SegRed … | SegScan … | SegHist …`
  (`code/futhark/src/Futhark/IR/SegOp.hs`, lines 367-373).

**Steal.** A *small closed set of second-order array combinators whose bodies are lambdas* is
exactly the shape of `linalg.generic` (iteration domain + region). Futhark's experience says the
combinator set should be chosen for its *fusion algebra and its sequentialisation*, not its
surface elegance (thesis §7.1, PDF p. 115: "not as aesthetically pleasing … but … fusion
properties are much more powerful" and "permit an efficient mapping to parallel code"). For us:
one structured op family (`linalg.generic` with parallel and reduction iterators covers
map/redomap/segred; `linalg.reduce`, `scf.forall`, `tensor` ops cover the rest) and *no*
second array IR of ours that mirrors it (AGENTS.md "one thing, one representation"). The
tuple-of-arrays rule (SOA) maps to multi-result generics.

**Avoid.** Futhark's own SOAC IR is a parallel universe to MLIR's; building an `idr.soac`
dialect that restates `linalg` would duplicate it. Also avoid `scan` as a fusion barrier
(the 2013 algebra had "scan2 is unfusable", `papers/henriksen-2013-t2-fusion/paper.pdf`,
§3.4, PDF p. 8); the thesis adds map-scan fusion (§7, PDF p. 114).

### 1.2 Fusion: T2 graph reduction, never duplicate work

- **Rule.** "The fusion algebra used by the Futhark compiler has as its central goals to never
  duplicate computation, and never reduce available parallelism" (thesis §7, PDF p. 114).
- **Mechanism (2013).** Fusion is a bottom-up data-flow analysis whose equations model T2
  reducibility of the producer-consumer graph: a producer SOAC with a single incoming edge is
  fused into its consumer, and the graph is reduced again, so a producer used by *several*
  consumers can still be fused once those consumers have merged (`papers/henriksen-2013-t2-fusion/paper.pdf`,
  §3.1, PDF p. 5-6, Figure 8). Six "don't fuse" cases are explicit: moving a use across an
  in-place update, incompatible SOAC pairs, fusing from outside into a loop or lambda (changes
  complexity), two consumers on one execution path, a producer used outside SOAC inputs, two
  outputs of one producer consumed by different SOACs (§3.1, PDF p. 6, Figure 9).
  `composeRes`/`unionRes` merge results for same-path and disjoint-path regions (PDF p. 7,
  Figure 11); the four fusion conditions are on PDF p. 8; the algebra (map∘map, filter∘filter,
  reduce∘filter, reduce∘map ⇒ redomap, redomap∘map, redomap∘filter) is Figure 14 (PDF p. 9).
- **Mechanism (now).** A graph over one body, built on `fgl`, with edge kinds
  `Alias | InfDep | Dep | Cons | Fake | Res` and node kinds `StmNode | SoacNode | TransNode |
  ResNode | FreeNode | MatchNode | DoNode`; nested bodies are single nodes
  (`code/futhark/src/Futhark/Optimise/Fusion/GraphRep.hs`, lines 1-15, 70-98). `Cons` edges are
  how consumption (uniqueness) constrains fusion. Horizontal and vertical fusion live in
  `code/futhark/src/Futhark/Optimise/Fusion.hs` (header lines 3-6; horizontal attempt near line
  615; pass entry `fuseSOACs`, line 762).
- **Interaction with in-place updates.** Fusion may not move a read across an update, and a
  fused SOAC may consume *more* than its constituents did; the fix is a copy for each input the
  fused SOAC consumes that no original did (thesis §7.2.2, PDF p. 122).
- **Optimality.** Choosing among incompatible fusions "is equivalent to graph clustering, an
  NP-hard problem"; Futhark is greedy in bottom-up order and has "not yet in practice observed
  cases where the greedy approach leads to suboptimal code" (thesis §7.2.1, PDF p. 121).
- **Measured.** Turning fusion off: k-means ×1.42, LavaMD ×4.55, Myocyte ×1.66, SRAD ×1.21,
  Crystal ×10.1, LocVolCalib ×9.4 slower; OptionPricing, N-body, MRI-Q and SGEMM *fail* for
  lack of memory (thesis §10.1.5, PDF p. 163).

**Steal.** (1) The *no-duplication, no-parallelism-loss* contract as the legality condition of
our fusion, stated once as a checkable property (a verifier-style assertion over the
before/after op counts per index), not as a heuristic. (2) Multi-consumer fusion: upstream's
`linalg-fuse-elementwise-ops` fuses a producer whose result only the consumer reads
(proposal 0004 §3.4); Futhark shows that the multi-consumer case is reachable *without*
duplication when consumers are themselves merged first (horizontal fusion into one
multi-result generic). That is a rewrite we can contribute upstream (multi-result generic
merge) rather than a pass of ours. (3) Consumption edges in the fusion graph: our grades
(`!idr.lin`) must block a fusion that moves a read past a consuming write — One-Shot's RaW
analysis already does this on tensors (`docs/mlir/docs/Bufferization.md`, lines 183-201, 385-447),
so the Futhark lesson is to *fuse on tensors before bufferization* and let One-Shot decide
in place afterwards, which is what 0004 does.

**Avoid.** A bespoke fusion algebra per pair of combinators (Dex's critique, §2.6 below). Do
not fuse into a loop or lambda from outside (Futhark case 3): it changes asymptotic cost.

### 1.3 Flattening: moderate, incremental, and now full

- **Moderate flattening** rules G4-G7 (reduce/map interchange, map-transpose to rearrange, map
  distribution across let, map/loop interchange) need a static heuristic for where to stop
  (`papers/henriksen-2019-incremental-flattening/paper.pdf`, §3.1, PDF p. 4-5).
- **Incremental flattening.** Rule G3: on a map with inner parallelism generate three versions
  — `e_top` (parallel at level l, body sequential), `e_middle` (parallel at l, inner
  parallelism at l−1, i.e. workgroup/local memory), `e_flat` (keep flattening at l) — guarded
  by `if Par(Σ') ≥ t_top then e_top else if Par(e_middle) ≥ t_intra then e_middle else e_flat`;
  the thresholds are program arguments, autotuned (§3.2, PDF p. 5, Figure 3). Versions are
  exponential in nest depth, but depth is static because there is no recursion (§1, PDF p. 2).
  Default threshold 2^15; OpenTuner with a tree-aware cost function that short-circuits
  repeated paths (§4.2, PDF p. 7). Cost: ~4× compile time, ~3× binary size vs moderate
  (§5.1, PDF p. 8).
- **Measured.** LocVolCalib beats hand-written FinPar on small/medium on K40; matrix multiply
  picks version (1) for n<5 then (2) (Figure 2, PDF p. 4); approximated full flattening is
  "more than an order of magnitude" slower on OptionPricing (§5.3, PDF p. 10). Local memory
  overflow is not handled (§4.1, PDF p. 7).
- **Today.** The pass is `flattenSOACs` with uniform/nonuniform distinction ("uniform when its
  size … and control flow is invariant to the map-nest"), DPH-style vectorisation avoidance,
  incremental and intrablock flattening, and the stated goal that "*any* Futhark program must be
  compilable parallel GPU code" via irregular maps
  (`code/futhark/src/Futhark/Pass/Flatten.hs`, lines 1-56;
  `code/futhark/src/Futhark/Pass/Flatten/Incremental.hs`, lines 1-38). Pipeline position:
  after `standardPipeline` (simplify, inline, CSE, `fuseSOACs`) and before tiling, histogram
  optimisation and memory passes (`code/futhark/src/Futhark/Passes.hs`, lines 52-110).

**Steal.** The *multi-versioning with a runtime predicate on available parallelism* is the
right answer to "how many of the rank-r loops are parallel" on CPU too (proposal 0005's SPMD
path): emit `scf.if (par ≥ t)` around two versions — outer dims parallel with the inner nest
sequential and tiled, or the inner nest parallel — with the threshold a module attribute
derived from the target (as 0004 reads `L1_cache_size_in_bytes` from DLTI). The rank being in
the type is what makes `Par(Σ)` a product of known sizes. **Avoid** autotuning as a required
step (it makes builds non-reproducible and our tests check behaviour, not timings); keep one
default threshold from the target entry. **Limit:** the whole technique presumes regular,
static-depth nesting.

### 1.4 Uniqueness types and in-place updates

- **Surface.** `a with [i] = v` (source construct; `let b = a with …`), `*[n]t` parameters
  ("consuming") and `*` returns ("fresh/alias-free"); after an in-place update or passing to a
  consuming parameter, the array and every alias are consumed and may not be used on any later
  path (`docs/futhark/docs/language-reference.rst`, lines 1457-1501; thesis §2.5.1, PDF p. 35-37).
  `scatter dest is vs` consumes `dest` (thesis PDF p. 37).
- **Rules.** Alias analysis judgement `Σ ⊢ e ⇒ ⟨σ1…σn⟩`: SOAC results are fresh, a scalar read
  does not alias, a slice does, `if` unions branches, a call returning `*τ` has no aliases,
  otherwise it aliases all non-consumed arguments (thesis §5.3.1, Figures 32-33, PDF p. 89-91).
  Checking uses *occurrence traces* ⟨C, O⟩ (consumed, observed) and a sequencing judgement
  ⟨C1,O1⟩ ≫ ⟨C2,O2⟩ derivable iff nothing consumed on the left is used on the right; a `map`
  body may consume only its own parameters, which counts as consuming the corresponding input
  array — so different rows may be updated in parallel (§5.3.2, PDF p. 90-91).
- **Checked again on the core IR.** The IR type checker re-implements the trace:
  `Occurence {observed, consumed}`, `seqOccurences`, and the `Consumption` semigroup that
  raises "referenced after being consumed" (`code/futhark/src/Futhark/IR/TypeCheck.hs`, lines
  187-252), plus `consumeOnlyParams` for lambdas (lines 387-409). Source-level checking is
  `code/futhark/src/Language/Futhark/TypeChecker/Consumption.hs` (`LetWith` at line 907,
  `Update` at 926, return-alias check at 209).
- **Higher-order limits.** A function that consumes an argument may not be passed as a
  higher-order argument; a `let` whose right side does an in-place update may not bind a
  function (`docs/futhark/docs/language-reference.rst`, lines 1529-1546).
- **Measured.** Without in-place updates k-means is ×8.3 slower, LocVolCalib ×1.7, and
  OptionPricing's Brownian bridge is not expressible (thesis §10.1.5, PDF p. 163).
- **Memory-level successor.** The IR gains memory blocks and *index functions* built from
  LMADs (offset plus (stride, size) per dimension) so slicing, transposition and reshape are
  O(1) and can cross `if`/`loop` without manifestation; "if the memory annotations are deleted,
  the program remains semantically unchanged" (`papers/munksgaard-2022-memory-optimizations/paper.pdf`,
  §I-II, PDF p. 2). *Short-circuiting* computes an array directly in the memory of the
  array it is later written into (turning the update into a no-op), legal when an LMAD
  non-overlap test proves no interference (Theorem (Non-Overlap), PDF p. 9); 1.1-2× impact,
  NW and LUD beat Rodinia's hand-written code by 1.1-1.5×, ~10% compile time (abstract and
  PDF p. 9). In code: `optimiseSeqMem/GPUMem/MCMem` (`code/futhark/src/Futhark/Optimise/ArrayShortCircuiting.hs`,
  lines 40-46), run after explicit allocations (`code/futhark/src/Futhark/Passes.hs`,
  `seqmemPipeline`, `gpumemPipeline`).

**Steal.** (1) The *occurrence-trace* formulation is a precise statement of what our
`!idr.lin` grade promises an array write; 0004 §3.6 checks it by asking One-Shot. Futhark
shows the two-level design is sound practice: check at the source (Idris QTT does this for us)
*and re-check on the IR after every pass* (Futhark's IR checker does exactly this) — our
verifier's role. (2) A map body may consume its own row: the rank-r version of 0004's
"a thread of writes is a tensor when it is linear" is a `linalg.generic`/`scf.forall` whose
`outs` slice per iteration is written in place (`tensor.parallel_insert_slice`), which One-Shot
already bufferizes in place when there is no RaW. (3) Short-circuiting is One-Shot plus
*empty-tensor elimination* in MLIR terms: compute the producer into the destination's slice.
Upstream already has the mechanism (`docs/mlir/docs/Bufferization.md`, destination-passing
style, lines 87-140); LMAD index functions are memref strided layouts. Do not write our own.
**Avoid** Futhark's restriction that consuming functions are not first-class: Idris's
quantities on function arguments (`(1 _ : IArray …) -> …`) already type it, so the
defunctionalised closure carries the grade and nothing needs banning. **Limit:** whole-array
alias granularity ("after `let a = b[0]`, a aliases all of b", 2013 paper §2.2, PDF p. 4);
the memory-level analysis recovers precision only for LMAD-describable access.

### 1.5 Size types

- **Core design (ARRAY 2021).** Sizes in types are *only variables or constants*; existential
  return types `∃x.μ` for `filter`/`iota e`; `let` implicitly opens existentials; explicit
  `let [x̄] x : τ = e` binds sizes as `int`s; `e ⊲ τ` is a runtime-checked size coercion;
  abstract sizes (`★`) have no runtime representation
  (`papers/henriksen-2021-size-types/paper.pdf`, §2, Figures 1-3, PDF p. 2-4). Soundness is
  proved for the monomorphic core (§3). Irregular arrays are excluded because type variables
  instantiate only with types whose sizes are in scope: `map (λx. iota x) y` is ill-typed
  (§4, PDF p. 8).
- **In Futhark.** HM inference extended with *nonrigid size variables* unified like type
  variables and generalised at `let`; implicit size parameters `[n]` become explicit
  parameters filled from argument types; *size-lifted* type parameters `'~a` may be
  instantiated with existential return types but never as array elements (§5, PDF p. 9).
  Experience: 66 dynamic size coercions across ~12,000 lines of benchmarks, mostly in input
  packing; idioms like `map (λi → map … (iota (f x))) …` need the size hoisted
  (§6, PDF p. 9-10). The rules are in `docs/futhark/docs/language-reference.rst`,
  lines 1170-1371 (unknown sizes, coercion `:>`, causality restriction).
- **FHPNC 2023.** Sizes may be *arbitrary expressions*, size equality is *syntactic*, size
  polymorphism is implicit arguments, and existential bookkeeping is automatic; the paper
  contrasts Idris's `filter : … -> Vect len elem -> (p : Nat ** Vect p elem)`, which forces the
  user to unpack the pair (`papers/bailly-2023-size-dependent/paper.pdf`, abstract and §1,
  PDF p. 1-2). Futhark's current docs: "Sizes can be any expression of type i64 that does not
  consume any free variables" (`docs/futhark/docs/language-reference.rst`, lines 1195-1199).
- **Thesis-era size IR.** Every array-typed variable in scope has an `i32` variable in scope
  per dimension; functions take extra size parameters and return `∃d.` sizes; existentials are
  introduced liberally and then removed by inlining and simplification; *function slicing*
  derives size-only functions to precompute result sizes before a map (thesis §6, PDF p.
  97-103). Hoisting sizes out of parallel loops is what makes flattening possible (§6 intro).

**Steal.** We already have the strong version: Idris `Vect n`/`Fin n` with full dependent
types, so we need none of Futhark's restrictions on the *checker*; the lesson is about
*representation after erasure*. (1) Futhark's invariant "every dimension of every array in
scope is a variable in scope" is precisely what MLIR's `tensor<?x?xf32>` + `tensor.dim` gives,
and what 0004 §3.7's `Vect rank Int` shape record gives at run time. Steal the *function
slicing* trick: when a map's result size depends on the element, compute the size from a
sliced copy of the body before the map so the result is regular and preallocated. (2)
Bailly et al. name exactly Idris's ergonomic gap (dependent pairs for `filter`); in our setting
the answer is library design (return `(n ** IArray [n] a)` and provide combinators), not type
system surgery. **Avoid** making shapes a second, separate type-level language (Remora/DML
style; Dex's related-work critique, `papers/paszke-2021-dex/main.tex`, lines 2026-2031) —
Idris's shapes are ordinary `Vect Nat`, one representation.

### 1.6 AUTOMAP: rank polymorphism as elaboration

- **Idea.** Functions keep rank-monomorphic types; *applications* get implicit `map_N` and
  `rep` (replicate/broadcast) inserted during inference. Rule 1: minimise the number of
  inserted maps and reps; ties are ambiguities and are rejected. Rule 2: one application gets
  maps or reps, never both (`papers/schenck-2024-automap/paper.pdf`, §2.1-2.2, PDF p. 4-5).
  Example: `lerp vs ws t` elaborates to `map3 lerp vs ws (rep t)` (PDF p. 5).
- **Properties.** Well-typedness, determinism, disambiguation (ambiguity fixable by explicit
  maps), forwards and backwards consistency (§2.3, PDF p. 6).
- **Algorithm.** Each application is annotated `△(M, R)` with rank variables; constraints over
  ranks (sums of integers and rank variables) are solved by an ILP whose objective is the total
  number of inserted operations; `M ∨· R` becomes `M ≤ U·b_M, R ≤ U·b_R, b_M + b_R ≤ 1`
  (§5-6, Table 2, PDF p. 15).
- **Measured.** 54% of map operations removable in real benchmarks; type checking 2.5× slower
  on average (§1, PDF p. 3).

**Steal.** This is the cleanest available answer to "rank above 1 without a separate
rank-polymorphic type system": rank polymorphism is a *surface elaboration* that produces
ordinary nested maps, which the compiler then sees as one `linalg.generic` of rank r. In our
architecture it belongs on the Idris side as elaboration (an `%auto`-style search or
interface resolution over `Vect` shapes), never in MLIR; MLIR only ever sees explicit loops.
**Avoid** an ILP in the type checker of a dependently typed language (Idris elaboration
is already search-heavy); the minimal-insertion rule can be implemented as interface
resolution with ranks known after monomorphisation. **Limit:** cannot express functions that
are themselves rank-polymorphic in a principled cell/frame sense (Remora's model); it is
lifting at call sites only.

### 1.7 Futhark: what to take for 0004, summarised

- Fusion and flattening only ever touch a closed, regular, static-depth structure — the same
  restriction 0004 makes when it says "a dense program builds its arrays whole". Keep it.
- In-place updates are a *type* fact (uniqueness), checked at the source and re-checked on the
  IR; the optimisation that exploits them is memory-level (short-circuiting) and is exactly
  One-Shot + empty-tensor elimination upstream.
- Size information lives as ordinary integer variables in scope; existentials are removed by
  inlining and simplification, not by a solver.

---

## 2. Dex

Stored: `papers/paszke-2021-dex` (TeX), `code/dex/` at `25e2e389b90403ae2f8d67fb6d52f47d23c439ee`.

### 2.1 Index sets as types, tables as memoised functions

- **Two forms.** `for i:n. e` builds a table, `xs.i` indexes it; the table type is
  `n=>a` with `n` an *index set*; `for` bounds are inferred from how `i` is used
  (`papers/paszke-2021-dex/main.tex`, §2.1, lines 290-344). Matrix product:
  `for i j. sum (for k. x.i.k * y.k.j)`, where using the same `k` in both arrays makes the
  type checker equate those dimensions (lines 320-343).
- **The class.** `interface IndexSet a where size : Int; ordinal : a -> Int; fromOrdinal : Int
  -> a` — finiteness plus a bijection with `[0, size)`, which also fixes iteration order for
  effects (main.tex lines 782-805). In code: `interface Ix(n|Data)` with `size'`, `ordinal`,
  `unsafe_from_ordinal`; `Fin(n) = %Fin(n)` (`code/dex/lib/prelude.dx`, lines 315-322).
- **Richer index sets.** Tuples of index sets are index sets (`(a,b)` instance with
  `idiv`/`rem` on ordinals, `code/dex/lib/prelude.dx`, lines 430-437), so `x : n=>m=>Float` and
  `y : (n & m)=>Float` convert by `for (i,j). x.i.j`: a type-safe reshape that "does not require
  the type system to solve systems of Diophantine equations" (main.tex lines 812-831). Range
  index sets (`RangeFrom i`, `RangeTo i`, ...) give triangular tables with `Add` instances
  (`code/dex/lib/prelude.dx`, lines 336-401).
- **Dependent tables.** The core type is `TabPiType :: IxDict r n -> Binder r n l -> Type r l
  -> TabPiType r n` — the element type may mention the index (`code/dex/src/lib/Types/Core.hs`,
  lines 210-216); the paper notes this generalisation and omits it (main.tex lines 2008-2024).
- **Duality.** `(\x. e) y` and `(for x. e).y` reduce alike; "Arrays are in fact just a
  representation for a fully memoized function"; `view i:n. e` is a lazy table (pure body)
  used for slices without copies (main.tex lines 747-781).
- **Type system.** Value-dependent: arbitrary *bound values* may appear in types, so type
  equality stays syntactic (up to α); cost: two variables bound to equal values are different
  types (main.tex lines 726-745). Typing rules `TypeFor`, `TypeView`, `TypeIndex`, `TypeSlice`
  (Figure, lines 680-725).

**Steal — this is the main import for rank above 1.** Idris already has `Fin n`, and a table
`Fin n -> a` *is* Dex's `n=>a` up to memoisation. The index-set interface is a three-method
Idris interface; tuples/products of index sets give rank r as *one* index type
`(Fin n1, …, Fin nr)` whose `ordinal` is the row-major offset — i.e. the shape is a type, the
layout is the `ordinal` function, and `reshape` between `n=>m=>a` and `(n,m)=>a` is free.
Concretely for 0004 §3.7: replace `IArray : Nat -> Type -> Type` with a vector `Vect r Int` of
sizes by an array indexed by an *index-set type* (`IArray (Fin n, Fin m) a`, or a shape
`Vect r Nat` lifted to a product of `Fin`s), so that: indexing is total (no bounds check when
the index came from a `for`, main.tex line 1857); rank is not a separate literal but the
arity of the product, which monomorphisation fixes; and MLIR gets `tensor<n×m×…>` with the
`ordinal` of the product as the identity row-major layout. Non-`Fin` index sets (ranges,
sums) become `affine_map`/`tensor.expand_shape`/`collapse_shape` patterns where they are
affine, and a view (lazy table) otherwise.

**Avoid.** Value-dependent types with syntactic equality is a step *down* from Idris; we
already have definitional equality. Do not adopt Dex's "tables of functions" as a runtime
representation (§2.3 below shows they defunctionalise them away anyway).

### 2.2 Effects for parallelism: `State` vs `Accum`

- `runState`/`get`/`:=` serialise a loop; `Accum` allows only `+=` on references of
  `VectorSpace` (later: any `Monoid`) type and no read until the handler ends, so updates are
  associative and parallelisable (main.tex lines 383-470; types at lines 446 and 452).
  Reference slicing `(!) : Ref h (n=>a) -> n -> Ref h a` is pure (lines 472-505).
- Reduction patterns are indexing patterns of the accumulator: never indexed = complete
  reduction; indexed by a subset of loop indices = regular segmented reduction; indexed by data
  = histogram (main.tex lines 1781-1811). Dex does not yet exploit the distinction (line 1811).
- Work efficiency: `histogram_dex` is O(n+k) sequentially *and* parallel, where combinator
  languages must either sequentialise or pay O(nk) (lines 1746-1780).

**Steal.** The `Accum` discipline is a type-level statement of "this loop's only cross-iteration
communication is an associative reduction into these places", which maps one-to-one to
`linalg.generic` reduction iterators (complete/segmented) and to a histogram op
(`scatter`-with-combine) when the index is data. In Idris it is a linear (quantity-1)
accumulator reference that the body can only `+=` — expressible today as a library type with
a restricted API; the compiler reads the *pattern of indices* to choose generic reduction
vs segmented vs histogram. **Avoid** Dex's effect system as a new language feature; Idris's
linearity and an abstract API give the same guarantee.

### 2.3 Compilation: simplify to first order, inline `for` = fusion, destinations

- **Simplification.** A context-producing translation `e ⇝ E^d, v` removes all higher-order
  functions; `SFor` turns a table of closures into a table of their captured data plus a
  `view` that rebuilds each closure (main.tex lines 847-1000, rule at 960; full rules at
  2385). Non-work-increasing by construction (only values are substituted).
- **Fusion is inlining.** "all fusion rules can be seen as instances of inlining followed by
  reduction"; a `for` whose result is consumed once is inlined at its index site, and the
  effect system says which inlinings are legal (main.tex lines 1813-1850).
- **Parallelism.** Decided per `for`; nested parallel `for`s are flattened "largely analogous to
  … Futhark" with `Accum` ≈ reduce and `State` ≈ loop (lines 1714-1745).
- **Type-directed lowering.** Index-set types remove bounds checks for `for`-made indices;
  full nested array types allow AoS→SoA and a single flat unboxed buffer per array with a few
  integers for offsets (lines 1851-1870).
- **Lowering in code.** `lowerFullySequential`: `for` becomes `seq`, arrays become `Dest`s,
  destination-passing elides copies, every `Place` writes each element once
  (`code/dex/src/lib/Lower.hs`, lines 30-60). An earlier MLIR backend supported scalar ops
  only and errors on array indexing, `case` and higher-order ops
  (`code/dex/src/old/MLIR/Lower.hs`, lines 48, 87-99); it lives under `src/old/`.
- **Measured.** Versus Futhark 0.18.6 on Hotspot, Pathfinder, MRI-Q, Stencil: somewhat
  faster serially on CPU, somewhat slower on GPU, worst on small inputs (main.tex lines
  1871-1950).

**Steal.** (1) *Fusion as inlining of index-defined producers* is exactly how MLIR's
`linalg` elementwise fusion works (the producer's body is substituted into the consumer's at
the consumer's indexing map); keep the Dex framing: a pure `tabulate`/`generate` that is read
once is never materialised. (2) Destination-passing lowering is MLIR's DPS; Dex had to write
it, we get it from One-Shot. (3) Bounds-check elision by index-set types: our
`idr.check.in_bounds` (0004 §3.2) can be *omitted at emission* when the index is a `Fin n`
value produced by a loop over `n` — an Idris-proved fact; carry it in the type of the index
(an erased `Fin`-ness), not in an attribute (AGENTS.md: facts in types). **Avoid** Dex's
choice to forbid recursion (main.tex line 674); Idris programs recurse, and 0004 already
handles recursion via `idr-tail-loops`. **Limit:** Dex's MLIR attempt stalled at scalars —
the hard part is the array/HOF lowering, which is why MLIR's tensor/linalg path, not a scalar
dialect mapping, is the target.

### 2.4 Parallelism-preserving AD (for completeness)

- `linearize` (forward mode, producing a *structurally linear* tangent function) then
  `transpose` (reverse the linear function, accumulating cotangents into `Accum` references);
  indexing transposes to `ref!i += ct`, which stays parallel (main.tex lines 1127-1330,
  1664-1690). The linear arrow `-o` is documentation only (line 1155).

**Steal (later).** Idris has a real linear arrow; Dex's unenforced `-o` is enforceable for us.
Not needed for 0004.

---

## 3. Accelerate

Stored: `papers/chakravarty-2011-accelerate`, `papers/mcdonell-2013-accelerate-optimising`.

### 3.1 Design (DAMP 2011)

- **Shapes as snoc lists.** `data Z = Z`, `data tail :. head = tail :. head`, `DIM2 = Z :. Int
  :. Int`; `Array sh e`; `Shape`/`Elt` classes; shape-polymorphic `fold` reduces the innermost
  dimension; `replicate`/`slice` use type families `FullShape`/`SliceShape` over slice
  specifiers (`papers/chakravarty-2011-accelerate/paper.pdf`, §2.1-2.6, PDF p. 2-3, Table 1).
- **Stratification.** `Acc` (collective array computations) vs `Exp` (scalar code, no
  recursion or iteration, to avoid SIMD divergence; no nested parallelism) (§2.4, PDF p. 2).
- **Compilation.** HOAS reified, converted to typed de Bruijn with GADTs; each collective op
  is an *algorithmic skeleton* (hand-written CUDA template) instantiated by splicing scalar
  code; compiled kernels memoised by AST hash; runtime (JIT) compilation (§3-5, PDF p. 3-5).
- **Measured.** Dot product takes "almost precisely twice as long as CUBLAS" because it is
  two kernels (§6, PDF p. 9).

### 3.2 Optimisation (ICFP 2013)

- **Sharing recovery.** Without it, Black-Scholes is "almost twenty times slower" than CUDA
  (`papers/mcdonell-2013-accelerate-optimising/paper.pdf`, §2, PDF p. 2). Algorithm: prune
  shared subterms using stable names and an occurrence map, float them to the lowest dominating
  node, bind with `let` — preserving tree structure and types (§3, PDF p. 3-4).
- **Fusion in two phases.** Producers (`map`, `zipWith`, `backpermute`, `generate`,
  `replicate`, `slice`) vs consumers (`fold`, `scan`, `permute`, `stencil`).
  Producer/producer fusion is AST tree contraction; consumer/producer fusion happens at code
  generation by specialising the consumer skeleton with the producer's index function;
  producer-after-consumer (`map g . fold f z`) is *not* fused; work is never duplicated
  (§4.1, PDF p. 6). Delayed arrays: `data DelayedAcc a = Done (Acc a) | Yield sh (sh -> e) |
  Step sh' (sh' -> sh) (e -> e') (Idx …)`; `mapD f (Yield sh g) = Yield sh (f . g)` (§4.2,
  PDF p. 7). `Step` keeps the access pattern structured (an index transform plus a value
  transform) rather than an opaque index function.
- **Measured.** Fusion roughly doubles dot product, still slightly behind CUBLAS (index
  conversion overhead); n-body without fusion needs O(n²) space and fails beyond ~5k bodies,
  and hand CUDA is still >10× faster because it uses shared memory; Black-Scholes beats the
  NVIDIA reference (§5, PDF p. 9).

**Steal.** (1) The producer/consumer classification is the right *lowering* split: producers
are index functions (affine maps in `linalg`), consumers are the ops with a reduction or
scatter structure. MLIR's elementwise fusion and `transform.structured.fuse` are the two
phases. (2) `Step` over `Yield`: keep index transforms *structured* (affine, permutation,
slice) so the backend can see access patterns — in MLIR this is the difference between an
`affine_map` indexing map and a `tensor.extract` with computed indices inside the body.
Prefer the former when the Idris index expression is affine in the loop indices (0004 §3.7
already says this). (3) The snoc-list shape `Z :. Int :. Int` is a precedent for shapes as an
inductive type: in Idris it is `Vect r Nat` or a `List Nat` index, with rank-polymorphic
`fold` over the innermost dimension expressible directly. **Avoid** the embedded-DSL
architecture (sharing recovery exists only because the host language hides `let`; we compile
Idris TT, where sharing is explicit) and JIT skeletons (we compile ahead of time, statically
linked). **Limit:** no nested parallelism, no general recursion in `Exp`; shared-memory tiling
was left as "an open research problem" (ICFP 2013 §5.4, PDF p. 9) — MLIR's tiling covers it.

---

## 4. SaC

Stored: `papers/grelck-2006-sac`.

- **Arrays are (shape vector, data vector).** `reshape(shp, data)` is the only constructor
  besides with-loops; `shape`, `dim`, and `sel(idx_vec, a)` where a *shorter* index vector
  selects a sub-array: `shape(sel(iv, a)) = shape(shape(a)) − shape(iv)` (Lemma 1 and eqs. 1-6,
  `papers/grelck-2006-sac/paper.pdf`, §2.2, PDF p. 11-14). Scalars are rank-0 arrays.
- **With-loops.** `with { (lb <= iv < ub step s width w) : e; default : d } genarray(shp)` /
  `modarray(a)` / `fold(op, neutral)`; generators define *sets* of indices (multi-generator
  partitions, grids, blocks), so evaluation order is free and fold operators must be
  associative and commutative (§2.3, PDF p. 15-18).
- **Types.** A three-layer hierarchy per element type: `int[*]` (any rank) ⊃ `int[.,.]`
  (rank known) ⊃ `int[3,7]` (shape known); overloading dispatches on the most specific layer;
  inference tries to make every expression as specific as possible and *specialises*
  functions to concrete shapes (§2.4, PDF p. 19-20; §3.1, PDF p. 22).
- **Programming methodology.** Everything aggregate (element-wise arithmetic, reductions,
  shifts, rotations) is written in SaC as rank-invariant with-loops in the standard library;
  programs are compositions (§2.5, PDF p. 20-21).
- **Compiler.** Functionalisation to SSA, type inference and specialisation, a fixed-point
  cycle of high-level optimisations, then memory management by *reference counting* (which is
  what makes destructive updates of stateless arrays possible), de-functionalisation back to
  loops, C code (§3.1, PDF p. 22-23; RC motivation §2.1, PDF p. 10).
- **With-loop folding** (vertical): replace a reference to a with-loop-defined array at an
  index that is an *affine function* of the consumer's index by the producer's element
  expression, removing the temporary and a barrier (§3.2, PDF p. 24-25).
- **With-loop fusion** (horizontal): with-loops with similar generators and no dependence
  become one *multi-operator* with-loop computing several arrays and folds in one sweep
  (minval and maxval together) (§3.3, PDF p. 27-28).
- **With-loop scalarisation** (nested): a with-loop whose elements are with-loops (arrays of
  complex numbers as 2-vectors) becomes one with-loop over the concatenated index space,
  removing per-element temporaries (§3.4, PDF p. 29-30).
- **Multithreading.** Only with-loops run in parallel, master/worker per with-loop; uniqueness
  ("classes") keeps state out of with-loop bodies (§4.1, PDF p. 33). No performance figures in
  this paper (§5, PDF p. 41-42).

**Steal.** (1) *Shape-hierarchy specialisation* is exactly our monomorphisation story for rank:
0004 §3.7's "rank is a literal after monomorphisation" is SaC's AKD layer; going further,
specialise to AKS (static shapes) when sizes are compile-time known — which compile-time
evaluation already gives us — and lower AKS to static `tensor<3x7xf32>` types, AKD to
`tensor<?x?xf32>`, and only AUD (unknown rank) to the library's generic code. This is "no
ceiling" with a clear ladder rather than a cliff. (2) The three with-loop optimisations are,
one-for-one, linalg elementwise fusion with affine maps (folding), multi-result generic
merging (fusion), and collapsing nested generics into one of higher rank (scalarisation —
crucial for `IArray n (IArray m a)` which 0004 §7 rejects as "a cell per row": scalarisation
is the transformation that makes the nested form contiguous when the inner shape is uniform).
(3) Sub-array selection with a short index vector is a typed operation in Idris
(`sel : Vect k Nat → IArray (k ++ rest) a → IArray rest a`) and is `tensor.extract_slice`
with rank reduction. **Avoid** runtime reference counting as the in-place mechanism for
*pure* arrays: we have static linearity for those (the RC path remains for shared counted
arrays, 0004 §3.5). Avoid generators with step/width as language primitives; they are
`affine_map`s with strides, i.e. a library-level index-set. **Limit:** single-level parallelism
(only with-loops), no nested-parallel story.

---

## 5. Lift

Stored: `papers/steuwer-2015-lift`.

- **Primitives.** High-level `map`, `zip`, `reduce`, `split n`, `join`, `iterate n`,
  `reorder`, with sizes in array types (`[A]_I`, sizes are variables, naturals, products and
  powers) and a *restricted dependent type* only for sizes
  (`papers/steuwer-2015-lift/paper.pdf`, §3, Figure 4, PDF p. 2-3). Low-level OpenCL
  primitives: `mapWorkgroup`, `mapLocal`, `mapGlobal`, `mapSeq`, `reduceSeq`, `reducePart`,
  `toLocal`/`toGlobal`, `splitVec`/`joinVec`, `reorderStride` (Figure 5, PDF p. 3).
- **Rewrite rules.** Algorithmic rules (split-join `map f → join ∘ map (map f) ∘ split n`,
  reduce decompositions, reorder, cancellation, fusion of map∘map and reduceSeq∘mapSeq) and
  OpenCL rules (map to the thread hierarchy with nesting legality, local memory, vectorisation
  "only allowed to be applied once" per map) (§4, Figures 6-7, PDF p. 4-6).
- **Correctness.** Denotational semantics; type soundness theorem; each rule proved by
  equational reasoning, e.g. split-join (§5, PDF p. 6-8).
- **Search.** Monte-Carlo descent over rule applications plus numeric parameters, measuring
  generated code (§6, PDF p. 10).
- **Measured.** Up to 20× over clBLAS on CPU (asum, small); matches CUBLAS on scal/asum/dot,
  +20% on small gemv, within 5% on large; up to 4.5× over clBLAS on AMD gemv; on par with
  NVIDIA SDK Black-Scholes on GPUs and 2.2× on CPU (§9, PDF p. 11).

**Steal.** The idea that *every* optimisation is a small, separately provable rewrite between
semantically equal programs, with hardware structure (thread hierarchy, vector width) expressed
as low-level *ops* introduced by rules. MLIR adopted this lineage explicitly: "Similarly to
LIFT, Linalg uses local rewrite rules" (`docs/mlir/docs/Rationale/RationaleLinalgDialect.md`,
lines 173-199). For us: write each array rewrite as an upstream-style pattern with a stated
equation, and test the equation (AGENTS.md: tests check the property a pass guarantees).
**Avoid** stochastic search in the compiler (non-reproducible builds; we prefer a
deterministic default plus target facts). **Limit:** point-free combinator programs, no type
inference ("mostly designed as an intermediate representation", per Dex's related work,
`papers/paszke-2021-dex/main.tex`, lines 2008-2016).

---

## 6. RISE and ELEVATE

Stored: `papers/hagedorn-2020-elevate`. Related, already in the library:
`papers/lucke-2024-transform-dialect`, `papers/koehler-2021-sketch-eqsat`,
`papers/ragankelley-2013-halide`.

- **RISE.** A λ-calculus with data-parallel primitives (`map`, `reduce`, `zip`, `split`,
  `join`, `transpose`, `generate`) and dependent function types over kinds `nat` and `data`;
  sizes are arithmetic formulae; data types (arrays `n.δ`, pairs, `idx[n]`, scalars, vectors)
  are separated from function types "to prevent functions from being stored in memory"; no
  general recursion, so every program terminates. Low-level primitives (`mapSeq`,
  `mapSeqUnroll`, `mapPar`, `reduceSeq`, `toMem`, `mapVec`, `asVector`, `asScalar`) are
  introduced only by rewriting (`papers/hagedorn-2020-elevate/paper.pdf`, §3.1-3.2, Figure 4,
  PDF p. 6-8). Code generation is *strategy-preserving*: it makes no implementation decision
  (§3.3, PDF p. 8).
- **ELEVATE.** `type Strategy[P] = P => RewriteResult[P]` with `Success | Failure`;
  combinators `id`, `fail`, `seq` (`;`), `lChoice` (`<+`), `try`, `repeat`; traversals
  `all`, `one`, `some` as a type class per program type, plus RISE-specific `body`,
  `function`, `argument`; `topDown`, `bottomUp` (§4, PDF p. 8-12). Normal forms as strategies:
  BENF (β/η) and DFNF (every higher-order primitive fully applied, data flow explicit), which
  make syntactic matching reliable (§5.1, PDF p. 13-14). Scheduling primitives (`tile`,
  `split`, `reorder`, vectorise, parallelise) are *user-definable* compositions, e.g.
  `tileND` (§5, PDF p. 16-17).
- **Measured.** Matrix multiply strategies equivalent to TVM's schedules: competitive with
  TVM, about 110× over the baseline; 657 rewrite steps for the baseline, ~40,000-63,000 for the
  optimised versions, under two seconds each; binomial filter: Halide 10-15% faster; and all
  optimisations were expressible without touching the algorithm, whereas Halide and TVM needed
  algorithm changes for array packing (§6, PDF p. 24-25).

**Steal.** The separation is already in MLIR: payload IR + *transform IR* driven by the
transform dialect (`docs/mlir/docs/Dialects/Transform.md`, lines 1-30;
`papers/lucke-2024-transform-dialect`). ELEVATE's lesson for us is the discipline:
optimisation strategies are *programs* built from small rewrites with explicit traversal, and
codegen afterwards decides nothing. 0004 §3.4 already uses `transform.structured.fuse`; the
steal is to write *all* our array schedules (tile, fuse, vectorise, parallelise for SPMD) as
transform-dialect sequences derived from target facts, kept in one place, so a new target is
a new sequence and not a new pass (AGENTS.md: a new target is a new entry). Normal forms
before matching (DFNF) correspond to running canonicalisation and `linalg` generalisation
before transform matching. **Avoid** exposing a scheduling language to Idris users now: the
user writes Idris; schedules are the compiler's. **Limit:** RISE has no recursion and no
in-place updates; ELEVATE strategies are hand-written per program in the paper.

---

## 7. Cross-cutting synthesis

### 7.1 Pointful vs point-free, and how each compiles

| System | Style | Compiles by | Rank above 1 |
| --- | --- | --- | --- |
| Futhark | point-free SOACs over nested regular arrays | fusion algebra on SOACs, then flattening to SegOps | arrays of arrays, regular by size types; AUTOMAP elaborates rank-polymorphic applications |
| Dex | pointful `for`/`.` over index sets | simplify to first order; fusion = inlining `for`; destination lowering | tables of tables; product index sets flatten |
| Accelerate | point-free combinators, shape snoc lists | skeleton instantiation; delayed producers fused into consumer skeletons | `Array (Z:.Int:.Int) e`, shape-polymorphic ops |
| SaC | pointful with-loops over index vectors | with-loop folding/fusion/scalarisation; RC memory | `int[*]`/`int[.,.]`/`int[3,7]`, specialised |
| Lift/RISE | point-free combinators with sizes | rewrite rules (+ search or ELEVATE strategies) to low-level primitives | arrays of arrays with size arithmetic |

Pointful code (Dex, SaC, and Idris's `tabulate (\i => …)`) compiles to the *same* target as
point-free code once index expressions are affine: an index function per input is a
`linalg.generic` indexing map. Point-free code makes fusion a rule system (Futhark, Lift);
pointful code makes it inlining (Dex) or index substitution (SaC folding, Accelerate
`Yield`). MLIR's `linalg.generic` is the meeting point: regions are pointful, indexing maps are
point-free index transforms.

### 7.2 Concrete recommendations for revamping 0004 §3.7 (rank above 1)

1. **Shapes are types; ranks are not a ceiling.** Index arrays by index-set *types*
   (Dex, §2.1): `Fin n`, products of them, and a few affine index sets (ranges). Rank is the
   arity of the product and is fixed by monomorphisation; when shapes are also compile-time
   known (compile-time evaluation), lower to static tensor types (SaC's AKS, §4). Only a rank
   that stays a run-time value falls back to the library, and even then the backing is one
   flat cell with a shape vector (SaC's (shape, data), §4).
2. **Rank-polymorphic code by elaboration, not by a second type system** (AUTOMAP, §1.6):
   ordinary Idris functions on elements, lifted at call sites; the compiler sees explicit
   nested maps and collapses them (SaC scalarisation, §4) into one generic of rank r.
3. **Nested arrays are not rejected but collapsed.** `IArray n (IArray m a)` with a uniform
   inner size is the same object as `IArray (n,m) a` (Dex product index sets, §2.1; Futhark
   regularity by size types, §1.5); scalarisation is a raise in `idr-tensorize`, guarded by the
   uniformity proof Idris already has (the inner `m` is the same `Vect`/`Fin` index).
4. **Fusion legality = no duplicated work, no lost parallelism, no read moved past a consuming
   write** (Futhark §1.2), stated as a checked property; mechanisms are upstream (elementwise
   fusion, `transform.structured.fuse`, a multi-result merge contributed upstream for horizontal
   fusion).
5. **In-place by type, exploited at memory level**: linearity in the type (Futhark uniqueness,
   §1.4), One-Shot + empty-tensor elimination as short-circuiting (Futhark SC 2022), and a
   map body may consume its own row (`scf.forall` + `tensor.parallel_insert_slice`).
6. **Reductions by structure**: an `Accum`-style linear accumulator API (Dex §2.2) whose index
   pattern picks complete / segmented / histogram lowering.
7. **Multi-versioned parallelism** for the SPMD path (Futhark incremental flattening, §1.3)
   with thresholds from the target entry, not autotuning.
8. **Schedules as transform-dialect programs** (ELEVATE §6), derived from DLTI target facts,
   one sequence per target.
9. **Bounds checks elided by index types** (Dex §2.3): an index of type `Fin n` produced by a
   loop over `n` needs no `idr.check.in_bounds`; the fact rides in the (erased) type.

### 7.3 Things every one of these systems gave up that we should not

- Recursion (Dex, RISE, Accelerate `Exp`): Idris recurses; tail loops and the module
  bufferization analysis handle it (0004 §3.5).
- A real linear type (Dex's `-o` is unenforced, Futhark's uniqueness is a separate system):
  Idris QTT supplies it.
- Full dependent shapes (Futhark restricted sizes to variables in 2021, then to syntactic
  equality in 2023; Lift/RISE restrict to arithmetic): Idris has them, and erasure (quantity 0)
  is how they cost nothing at run time — but "erased does not mean constant" (AGENTS.md):
  a size erased at 0 is still a run-time `tensor.dim`, which is why the shape record exists.

---

## 8. What was not stored

- **Duplicates avoided:** `henriksen-2021-size-types` and `bailly-2023-size-dependent` were
  already staged by another cluster with identical bytes (SHA-256 `23f28e37…` and `7af837d8…`);
  cross-linked, not stored again. `henriksen-2017-futhark` (PLDI) and
  `hovgaard-2018-defunctionalisation` are already in the library.
- **Not fetched (scope):** Futhark "Data-Parallel Flattening by Expansion" (ARRAY 2019,
  `futhark-lang.org/publications/array19.pdf`), "Design and GPGPU Performance of Futhark's
  Redomap Construct" (ARRAY 2016, `array16.pdf`), Hashemi's 2026 MSc thesis on full flattening
  (`student-projects/amir-msc-thesis.pdf`, the work behind `FlatMap`); SaC "With-Loop Fusion for
  Data Locality and Parallelism" (IFL 2005) and with-loop scalarisation papers (cited by
  `grelck-2006-sac`, refs 29-30); McDonell's PhD thesis (UNSWorks 1959.4/55818, CC-BY-NC-ND);
  Lift follow-ups (position-dependent arrays, Pizzuti et al. 2019); Atkey et al. 2017
  (strategy-preserving compilation for RISE). All are open-access candidates for a later pass.
- **Blocked:** UNSW `cse.unsw.edu.au/~chak/papers/*` returns 403 (author copies obtained from
  McDonell's site instead); Grelck's live UvA page returns 404 (Wayback snapshot used).
