# Fusion and deforestation: MLIR fuses, Idris supplies the facts, a small residue is ours

Stream "fusion". Experiments, commands, IR excerpts and the timing table are
in `findings/fusion-experiments.md` (X1–X4). This file builds on:
- architecture.md: the IR stack, the solver, join points, `scf.for` raising;
- representation.md: R6 closed-length `Vect`, R11 ghosts, R12 contiguous
  `Vect` as `tensor`;
- facts-ledger.md: size-change dropped, `%transform` ignored, `List`'s
  fields unrestricted;
- memory-theory.md: exclusivity, reuse, the tensor path for arrays.

None of those is repeated here beyond a pointer.

Status of claims:
- **measured**: I ran it (X1, X2);
- **read**: a file:line, or a paper section;
- **conjecture**: my judgment, untested.

## The questions

1. What is the global maximum for fusion and deforestation in idris-mlir? What
   representation do Idris pipelines lower to, so that MLIR's own machinery
   (scf, linalg on tensors, affine fusion, bufferization, vectorization) does
   the fusing?
2. What can and can't MLIR fuse, precisely? What is the residue that needs
   home-rolled fusion, and how small can it be?
3. Where does each intermediate survive today, and which pass would remove
   it?
4. How do Idris's facts (quantities, uniqueness, totality, size-change,
   lengths) beat GHC here, and where don't they?
5. How does fusion compose with reuse, bufferization, defunctionalization,
   specialization and compile-time evaluation?
6. What is the concrete IR design: the load-bearing pieces, rules as data,
   the place in the pipeline, named remarks, and an opt-in error? Which
   test suite, and which staged path?

## Short answer

- **Today nothing fuses, and every pipeline overflows the stack** (measured,
  X1).
  - `sum (map f [1 .. n])` builds two lists: one in `takeUntil` and one in
    `mapImpl`. Both are non-tail recursions, and the program segfaults
    between n = 2e5 and 4e5.
  - The seven other pipelines fail the same way, some from n = 5e4.
  - Chez and MLton also build every list (580 MB to 2 GB of RSS at n = 1e7).
    C runs the same pipelines in 0.001–0.057 s at 1e7.
- **The global maximum has one decision fact and three representations**
  (§1).
  - The fact: *is the length a runtime value before the first element is
    produced?*
  - If it is, the sequence is an index space: `tensor<?xT>`, and the
    recursion schemes over it are `linalg.generic`. MLIR fuses them
    (elementwise fusion, shape folding, affine fusion), then bufferizes and
    vectorizes (measured end to end, X2 e3–e6).
  - If it isn't, the pipeline is a `!idr.stream<T>`: a compile-time-only
    type, whose steps are regions. It is fused by region composition and
    lowered to `scf.while`. That is our residue: about ten ops, eight
    shrinking rules, and one lowering.
  - A sequence that is shared or escapes is materialized once, in the
    flattest form its facts allow, and reuse applies to it (§6).
- **What MLIR fuses and what it doesn't** (measured, §2):
  - it fuses linalg elementwise chains;
  - it fuses a map into a reduction only if the reduction keeps a data input;
  - `affine-loop-fusion` fuses across a buffer and deletes it, but only with
    `maximal=true` for a symbolic extent, and never for loops with
    `iter_args`;
  - tile-and-fuse with the default control fuses a reduction's init into the
    loop and **computes the wrong sum**;
  - nothing in MLIR fuses through heap cells, recursive calls,
    data-dependent lengths, early exits, or IO consumers. Those are the
    residue.
- **The facts** (§5).
  - Totality with the crash effect licenses interleaving and speculation.
  - Idris 2's call-by-name `Lazy`/`Inf` means stream fusion never loses
    sharing.
  - Single use comes from SSA after specialization, not from QTT: the
    Prelude's `List` has unrestricted fields, so `(1 xs : List a)` says
    nothing about its tail.
  - Size-change classifies structural recursion without names and keeps the
    machinery unfolding-free.
  - `Vect` lengths are tensor shapes and trip counts.
- **The path** (§9) starts with three small loop fixes that remove today's
  segfaults with no fusion at all:
  - record eta;
  - case blocks as continuations;
  - canonical `scf.while`.

  Then come streams, recognition, the index-space lowering to linalg, `Vect`
  as tensors, and the residue's completeness.

---

## 1. The global maximum

**One sentence.** Every Idris sequence pipeline that could be a loop is one,
by construction of its representation:
- index-space data is `tensor` and its schemes are `linalg`, so MLIR fuses,
  bufferizes and vectorizes it;
- everything else is a stream that cannot exist at runtime, so it is either
  lowered into a loop or explicitly materialized;
- every materialization is reported, and can be rejected on demand.

### 1.1 The decision fact and the three representations

| class | decided by (Idris fact) | representation | who fuses | lowered to |
|---|---|---|---|---|
| **index space** | length known before production: a range's bounds; a `Nat`-driven builder (`build (S k) = x :: build k ...`); `replicate n`; a `Vect n` with a relevant or ghost `n` that meets R12's proofs; a length-preserving transform of one of these | `tensor<?xT>`, dim = the Idris length (static `N` → `tensor<Nx…>`/`vector<N×…>`); a filtered sequence is a (values, `tensor<?xi1>` keep mask) pair of the source's length | **MLIR**: `linalg-fuse-elementwise-ops` (with our control function), `resolve-ranked-shaped-type-result-dims`, One-Shot Bufferize, `affine-loop-fusion`/`affine-scalrep` for buffers that survive, the vectorizer | `linalg.generic` → loops, `vector` |
| **stream** | anything else that is a pipeline: a cons-list or `Stream` source, data-dependent length (`takeWhile`, `unfoldr`, `iterate`, dependent `concatMap`), early exit (`any`, `elem`, `find`), an IO consumer (`traverse_`), a right fold | `!idr.stream<T>`: compile-time only, used exactly once (§7.1) | **ours**: rules F0–F8 (§7.3), region composition, no unfolding | `scf.while`; then MLIR uplift to `scf.for`, LICM, canonicalize |
| **survivor** | shared (≥ 2 uses), escaping (returned, stored, passed to an unrecognized function), or consumed by a recursion that is not a scheme (tree folds) | the flattest the facts allow: a `tensor` buffer if the length is known (R12), else cons cells built by a constant-stack loop | nobody: it exists once; reuse and bufferization make it cheap | buffer, or cells with reuse (Perceus/FP²) |

The split follows the representation, not a heuristic:
- a tensor needs its size at allocation (destination-passing style);
- a stream needs no size, but cannot be indexed or shared.

Futhark draws the same line ("the size is always a runtime value when an
array exists", representation.md on Henriksen §2-3). It leaves filter out of
its fusion paper for the same reason (Henriksen 2017 §4, p. 7).

### 1.2 What the maximum looks like on the eight pipelines

| pipeline | class | result after the design | evidence |
|---|---|---|---|
| `sum (map f [1 .. n])` | index space (generators only) | one counted loop; LLVM closes the sum, as for C | e3: upstream passes only, 0.0000 s at 1e8 |
| `foldl (+) 0 (map (*3) (filter p [1 .. n]))` | index space, filter as a mask | one loop with a `select`, no buffer | e5: 0.231 s at 1e8, C 0.249 s |
| `length (zip [1 .. n] (map (*2) [1 .. n]))` | index space | `min(n, n)`: no loop at all | e6: `arith.minui` only |
| `sum [x * y \| x <- [1 .. n], y <- [1 .. 100], p]` | stream (concatMap; the inner space is independent, so index space is possible too) | two nested loops, no list | conjecture; §7.3 F5 |
| `traverse_ printLn (map f [1 .. n])` | stream (IO consumer) | one loop that writes | conjecture; needs S0a |
| user `total' 0 (bump (upto 1 n))` | recognized like the Prelude's | as `summap` | conjecture; §7.2 |
| `Vect 4 Double` chain | index space, static shape | `vector<4xf64>` ops, one `vector.contract`, ordered reduction, zero cells | e4 |
| `Vect m Double` chain from `build m` | index space (`Nat` driver of length m) | one loop, no cells, no buffer | e3's route, conjecture for this program |

### 1.3 "Never builds a list", as a property with named exceptions

A pipeline that builds a list at runtime is always one of these:
- shared;
- escaping;
- consumed by a non-scheme recursion;
- rejected by the effect rules (§5.2).

Each case is a named `missed` remark (§7.6). With the demand option each
becomes `unsupported (fusion): <reason>`. Nothing else is allowed to
materialize: the `!idr.stream` verifier (V4) makes a silently unfused stream
unrepresentable.

---

## 2. What MLIR can and cannot fuse (measured at the pin)

| mechanism | fuses | does not fuse | evidence |
|---|---|---|---|
| `linalg-fuse-elementwise-ops` (`FuseElementwiseOps`, `areElementwiseOpsFusable`) | chains of parallel generics: `map∘map`, `zipWith∘map`, generator → map; an elementwise producer into a reduction whose other inputs cover every loop dimension | a producer that isn't all-parallel; a producer through an `outs` operand; **an input-less generator into a reduction that has no other input**: the fused op would have no operand defining its extent (`ElementwiseOpFusion.cpp:183-209`) | e1: 2 generics left, the n-element tensor survives; e5: with a mask input, everything fuses |
| shape folding (`resolve-ranked-shaped-type-result-dims`, canonicalize) | `tensor.dim` of any linalg result, back to the `tensor.empty` sizes | n/a | e6: `length (zip …)` = `arith.minui` |
| tile-and-fuse (`scf::tileConsumerAndFuseProducersUsingSCF`, `transform.structured.fuse`) | producers into tiles of a consumer, including input-less generators | **correctness hazard**: the default `fusionControlFn` fuses destination producers (`TileUsingInterface.h:302-309`), so tiling a reduction along its reduction dimension resets the accumulator every tile | e1-tf: 38818 instead of 338450 at n = 100 |
| `affine-loop-fusion` + `affine-scalrep` | a producer loop into a consumer through a memref, and deletes the memref | loops with results (`iter_args`) in either role (`LoopFusion.cpp:890-893`, `:931-934`); symbolic extents under the default cost model (`isFusionProfitable`, `:500`, `:1049`); non-affine loops (`scf.*`) | e2 (no), e2b (no), e2c static (yes), e2b `maximal=true` (yes) |
| One-Shot Bufferize | in-place writes when the operand is dead and writable (uniqueness) | the function boundaries of recursive functions (`OneShotModuleBufferize.cpp:518-523`, memory-theory §6.10) | read |
| vectorizer (`vectorize_children_and_apply_patterns`) | static-shape generics to `vector` ops; mul-add to `vector.contract`; reductions as `llvm.vector.reduce.fadd(acc, v)` with no `reassoc`, which is **ordered**, the order of `foldl` | reassociation is not introduced for `fastmath<none>` | e4 |
| `scf` uplift (`populateUpliftWhileToForPatterns`) | `scf.while` → `scf.for` | a before region with anything but one `cmpi` (`UpliftWhileToFor.cpp:34-41`), predicates other than `slt`/`sgt` (`:93-94`) | read; idr-tail-loops' loops never match |
| `scf` fusion | siblings only (`scf-parallel-loop-fusion`) | producer-consumer between `scf.for`/`scf.while` | read |
| anything | n/a | **heap cells** (`!idr.box` fields); **recursive calls** (the inliner refuses cycles); **data-dependent lengths** (a tensor needs its size at allocation); **early exit** (linalg has no break); **IO in a body** (linalg iterations are unordered); **right folds on cells** (no reverse traversal without a stack or a buffer) | the residue |

**What this means.**
- For data on tensors, MLIR's fusion is complete enough to be *the* fusion
  engine.
- For generators, it has one gap: an input-less generator feeding a lone
  reduction. The all-upstream route around it is e3: bufferize, then
  `convert-linalg-to-affine-loops`, then `affine-loop-fusion{maximal}`. It
  works, but `maximal` ignores the cost model and fuses producers into
  *every* user (`runGreedyFusion`'s third phase, `LoopFusion.cpp:829-835`),
  so it would recompute a producer we chose to share.
- The design therefore lowers a reduction whose inputs are all input-less
  generators straight to `scf.for`: one pattern, part of the residue. It
  should also file the gap upstream (a feature report in `upstream/`), so
  that the pattern can be deleted when upstream accepts input-less producers.
- The design never uses `transform.structured.fuse`'s default control along
  a reduction dimension. If it ever does, the miscompile needs its
  `upstream/` report first (AGENTS.md).

---

## 3. Today: where each intermediate survives, and what removes it

The dumps are in X1. The times are best of 3; "segv" is a stack overflow.

| pipeline | intermediates, and the function that builds them | why it is not a loop | segv from | at 1e7: Chez / MLton / C | removed by (§7, §9) |
|---|---|---|---|---|---|
| summap | `[1..n]`: `takeUntil$spec` case block (2 cell sites); `map`: `mapImpl$spec$1` | both are cons-after-call (non-tail); `%transform "tailRecMap"` ignored (`Types.idr:608`) | 4e5 | 3.55 s / `Overflow` / 0.001 s | range → index space; map, sum → linalg; S2–S3 |
| chain | + `filter`'s case block | the same; `tailRecFilter` ignored (`:642`) | 4e5 | 3.15 / 2.78 / 0.032 | filter as a mask (e5); S3 |
| lenzip | two ranges, `map`, `zipWith (,)` cells; `length` returns a big | non-tail; `length` via `natToInteger` | 1e5 | 8.14 / 4.18 / 0.002 | shape folding (e6): no loop; S3 |
| compr | outer range; `listBindOnto` accumulates reversed; `reverseOnto` | `listBindOnto` is tail-recursive, but the range isn't | 1e6 | 11.6 (at 1e6) / timeout / 0.293 (1e6) | concat_map (F5), accumulate-then-reverse (F7); S5 |
| trav | range, `map`; `foldr` over IO | **one missing canonicalization**: `con MkIORes(field %5[0], field %5[1])` is `%5` (record eta), and blocks the tail call | 1e6 | 35.7 / n/a / 4.2 (musl `printf`) | S0a (eta) makes the fold a loop; then IO fold over the range; S2 |
| userpipe | `upto` (unfold via a case block), `bump` (map with take/reuse) | non-tail; the case block receives a constant Bool (architecture §3.1) | 4e5 | 2.88 / n/a / 0.001 | recognition of user code (same schemes); S0b, S2 |
| vstat | 5 cells per iteration (2 on the stack); `zipWith` by reuse | `loop` ↔ case block is mutual recursion, and the stack cells' `alloca`s block LLVM's tail call (`vstat.ll:101-102, 223`) | 1e5 | 2.27 / n/a / 0.057 | S0b (join points); R6 static tensors/vectors (e4); S4 |
| vdyn | `build`, two `map`s, `zipWith` | non-tail | 1e5 | 16.1 / n/a / 0.030 | `Nat`-driven builder as index space; S4 |

What the table says:
- **Each fold is already a loop, and each producer is a non-tail
  recursion.** Every segfault is a producer or a transformer.
- Without fusion, TRMC (a constant-stack `collect`) alone would stop the
  crashes, but not the allocation.
- Fusion removes both.

---

## 4. The literature, and what each line contributes

| work | idea | why it is fragile, or what it costs | what we take |
|---|---|---|---|
| Wadler 1990, deforestation (link-only; Sørensen p. 2, p. 14) | unfold/fold composition of *treeless* definitions; *linear* terms avoid duplicated work | a syntactic class; termination needs the restriction; higher-order extensions are hard | linearity = SSA single use (V1); schemes are a syntactic class checked locally |
| Gill, Launchbury, Peyton Jones 1993, foldr/build (link-only) | Church encoding: `foldr k z (build g) = g k z` | producers and consumers must be written in `foldr`/`build` form and inlined at the right phase; `zip` does not fuse | push fusion for `concatMap` and folds (F5, F6) |
| Svenningsson 2002, destroy/unfoldr (not in sources) | co-Church (pull) encoding | `filter` needs recursion in the stepper | pull for `zip` (F4) |
| Coutts et al. 2007, stream fusion (link-only) | pull streams with `Skip`, so every combinator is non-recursive; the rule `stream (unstream s) = s` | relies on GHC's case-of-case and SpecConstr to remove `Step` and state boxes; `concatMap` with a non-static inner stream does not fuse | `Skip` as a terminator; F0 is `stream/unstream` |
| Hinze, Harper, James 2010 (cited by Kovács 2024 p. 18) | push = Church, pull = co-Church; each fuses what the other can't | n/a | support both, as regions allow (below) |
| Kiselyov et al. 2017, strymonas; Kobayashi and Kiselyov 2024 | staging guarantees fusion; push and pull combined; complete only in the 2024 version (Kovács 2024 p. 25) | needs a staged host language | the guarantee by construction: a stream is not a runtime value |
| Kovács 2022 §2.4 (`paper.tex:593-618`) | fusion as a binding-time improvement; in 2LTT the guarantee is formal; "converting back to lists from colists is not necessarily total" | n/a | the meta-level type `!idr.stream` (V3); the totality caveat for `takeUntil` (§5.2) |
| Kovács 2024 §4 (pp. 18-21) | `Pull : (S : MetaTy) → … → Pull A`; running = `foldr` tabulated into mutually tail-recursive functions; `concatMap` with dependent state; `foldl` with no closures | n/a | streams as regions with `Step` terminators; the running of a stream is `scf.while` |
| Sørensen, Glück, Jones 1996; Mitchell 2010 | supercompilation subsumes deforestation and fuses by structure, not by name (Mitchell §2.3, p. 4) | whistles and generalization (Mitchell §2.6); compile time; the repo's own history of blow-ups under expanding transformations (architecture §2) | recognize by structure, never unfold: classification, not supercompilation |
| Henriksen 2017, Futhark §4 | SOAC rules F1–F7; fuse along a single dependency edge (T2 reductions); horizontal fusion otherwise; uniqueness for in-place | filter out of scope; explicit indexing blocks fusion | single-edge fusion = V1; linalg for SOACs; uniqueness for survivors |
| GHC RULES (Mitchell p. 9; Kovács 2022 §2.4) | user-written rewrite rules plus inlining phases | (1) match by name: "redefining map locally would inhibit the fusion"; (2) phase ordering with inlining; (3) no check of confluence or termination; (4) silent failure; (5) work duplication guarded only by occurrence analysis; (6) `Step` and state removal depends on SpecConstr; (7) `foldl` via `foldr` needs arity analysis (Kovács 2024 p. 20) | none of the mechanism; every one of the seven is answered by representation (§5.3) |
| MLton (`SSASimplify.adoc`) | **no fusion pass** among its 23 SSA passes; contification, flattening, `useless`, and cheap allocation with a generational GC; stacks grow on the heap | n/a | why (conjecture): SML functions may raise or do IO, so interleaving `map f (map g xs)` is observable, and MLton has no effect types; it makes allocation cheap instead. **Measured**: MLton builds every list (624 MB–1.5 GB at 1e7) but never overflows |
| Perceus (Reinking 2021), FP² (Lorenzen 2023) | reuse of dead cells; `fip` programs allocate nothing; any map over a polynomial type can be made in place (FP² §3, p. 8) | `fbip` recursion is not constant-stack (FP² p. 6) | the survivor path (§6.1) |

**Push and pull, with regions.**
- A consumer fold over a `concat_map` lowers to nested loops. That is push,
  and needs no dependent state.
- `zip` of two streams lowers to one loop that steps both states. That is
  pull.
- `zip` over a `concat_map` makes the inner state explicit: a (flag, inner
  state) pair in `scf.while`'s carried values, which is Kovács's dependent
  state spelled with `i1` and poison.
- So the region representation reaches strymonas's completeness without
  staging. This is conjecture until F4 and F5 are implemented together.

---

## 5. How Idris's facts beat GHC here, and where they don't

### 5.1 The table

| fact | what it buys for fusion | GHC | the honest limit |
|---|---|---|---|
| **call-by-name `Lazy`/`Inf`** (Idris 2's semantics: Chez's `defaultLaziness` is `(lambda () e)`, with memoization only under a directive, `Common.idr:318-331`; our `Delay` is a closure, `Terms.idr:126`) | a `Stream` producer is recomputed on every force anyway, so **fusing it can never lose sharing**, and there is no memo question | call-by-need: a let-bound lazy list has shared work that fusion must not duplicate; hence occurrence analysis, the one-shot and state hacks | this is Idris 2's operational choice, not QTT |
| **single use** | work-safe fusion: a producer with one consumer is fused without recomputation | occurrence analysis on let-bound lists | **SSA after specialization gives it, not QTT.** Pattern variables of a q1 scrutinee get the field's quantity (facts-ledger, checked), and the Prelude's `List` has ω fields, so `(1 xs : List a)` promises nothing about the tail |
| **QTT 1 on deeply linear data** (`LList`: `(::) : a -@ LList a -@ LList a`, `libs/linear/Data/Linear/LList.idr:11-13`) | a whole traversal consumed once *across function boundaries*, even without inlining: an `LList` parameter can be passed as a stream | Linear Haskell has the same, rarely used | rare in Prelude-style code; the deep-linear element type also makes `collect` exclusive by construction (§6.1) |
| **purity by type, and the linear world** | IO can only be in the consumer that threads `%World`, so the order of effects is explicit in the fold's accumulator | purity by type too | same as GHC |
| **totality + crash-freedom** (the effects lattice: none/crash/diverge/io; `idr.total`) | (a) **interleaving**: fusion reorders the producer's and consumer's bodies, which is legal unless both sides can fail (§5.2); (b) **speculation**: filter-as-mask computes the map on dropped elements, and maximal affine fusion recomputes; both need `effects<none>`; (c) `mustprogress`/`willreturn` on the fused loop | under laziness foldr/build preserves meaning up to `seq`, so GHC does not need totality | Idris is strict, so we do need it. The ranges use `assert_total` over a `covering` `takeUntil` (`Types.idr:1122-1126`): trusted, as Idris trusts it. Kovács 2022: colist → list "is not necessarily total" |
| **size-change** (`GlobalDef.sizeChange`) | (a) **recognition without names**: a self-call whose list argument is `Smaller` (a field of the scrutinized parameter) is structural recursion, a catamorphism, whatever the function is called, in the Prelude or the user's code; (b) **termination of the machinery**: recognition classifies each function once and rules only shrink, so there is no unfolding and no whistle | RULES match names (Mitchell p. 9); user recursion does not fuse | dropped after the frontend today (facts-ledger §5). Recognition can check the same property locally on the IR (the argument is a match-bound field); the Idris edge is the cross-check |
| **lengths** (closed `Vect N`, ghost `n`, range bounds, a `Nat` driver) | shapes and trip counts: static N → `vector<N×…>`, full unrolling, `vector.contract` (e4); symbolic n → `tensor.dim`, `scf.for` bounds, SCEV closed forms (e3); `zipWith : Vect n a → Vect n b → …` needs no `min` and no bounds check; `length` is O(1) (e6) | none | needs ghost identity (R11) and R12's proofs for symbolic `Vect` |
| **closed world + monomorphisation** | every Prelude combinator is a first-order clone with its function argument inlined (`mapImpl[Int, Int]$spec$1` has `f`'s body, X1); recognition sees it | separate compilation; needs INLINE pragmas and phases | clones may lose the size-change mapping; keys keep parameter identity (architecture, open question) |
| **uniqueness (inferred, memory-theory)** | survivors are updated in place: `collect` over an exclusive source writes into its cells; bufferization's `writable` | none | inferred, never read off q1 |

### 5.2 The effect rule that licenses interleaving

Fusion evaluates producer step k+1 after consumer step k, where the unfused
program runs all producer steps first. Let E(P) and E(C) be the effect sets of
the two regions, drawn from {crash, diverge, io}:
- **legal** if E(P) = ∅, or E(C) = ∅. A pure side commutes with anything,
  with one exception: a diverging producer must not be moved before a
  crashing consumer. Unfused, the program loops and never crashes (Sørensen
  p. 14: "more terminating").
- **legal** if E(P) ⊆ {crash} and E(C) ⊆ {crash} *and* at most one of them
  can crash on this program. Two crash causes whose order changes print
  different messages.
- **IO** is allowed only in the consumer. The world is its accumulator, and
  the producer is pure.
- **otherwise**: materialize, with remark `effects(<producer>, <consumer>)`.

Speculation (a filter mask, recomputation) needs E = ∅ for the speculated
region.

### 5.3 GHC's fragilities, answered by representation

| GHC fragility | answer here |
|---|---|
| (1) name matching | structural recognition after monomorphisation (§7.2) |
| (2) phase ordering with inlining | recognition runs once, after the simplify loop; it needs no inlining of recursive functions, because it replaces the *call* with non-recursive regions |
| (3) no confluence or termination check | a finite table of shrinking rewrites on ops; each removes an op, so the greedy driver terminates by measure (MLIR's canonicalization contract, architecture I.3) |
| (4) silent failure | every materialization is a named remark; demand turns it into an error (§7.6) |
| (5) work duplication | V1: a stream has exactly one use *by type*; shared data is a survivor, never a stream |
| (6) `Step`/state boxes need SpecConstr | `Step` is a terminator and the state is block arguments: there is nothing to allocate, hence nothing to remove |
| (7) `foldl` via `foldr` needs arity analysis | `fold` is a region with accumulators, with no closures (Kovács 2024 p. 20) |

---

## 6. Composition with the rest of the compiler

### 6.1 Reuse (Perceus, FP²) and uniqueness

- **Fusion first, reuse for survivors.**
  - A fused intermediate has no cell to reuse, which beats any reuse.
  - Reuse then applies to what must exist: a shared list, a list read from
    input, a tree.
- **`collect` over `of xs` with `xs` exclusive** writes its outputs into
  `xs`'s cells in order: map in place, the FP² `fip` map.
  - The token of each consumed cell becomes the destination of each
    produced one.
  - No allocation and no stack, where `bump` today is a non-tail recursion
    with a runtime reuse test (X1).
  - Needs the exclusivity indicator of memory-theory §6 path step 3.
- **TRMC.** A `collect` whose source is not exclusive builds fresh cells in
  a loop.
  - Either by destination passing (memory-theory's hole cell);
  - or by accumulating reversed and then reversing in place. The reversed
    list is fresh, hence exclusive, so the reverse reuses every cell: two
    passes, constant stack, n cells.
- **Trees.** Tree recursions are not loops (FP² p. 6: `smap` is `fbip`,
  not `fip`), so they are the residue of the residue.
  - Reuse makes them allocation-free when the input is unique.
  - A hylomorphism (a tree built by an unfold and consumed by a fold) could
    be fused into one recursion that never builds the tree. That is a late
    stage and conjecture (S8).

### 6.2 Bufferization

- Linalg fusion runs on tensors *before* bufferization, so the tensors that
  remain are exactly the survivors.
- One-Shot Bufferize then writes in place where the operand is dead and
  writable. Writable comes from exclusivity (memory-theory §6.10): for
  example, `map f v` on a unique `v` reuses `v`'s buffer.
- Ownership-based deallocation frees the survivors;
  `promote-buffers-to-stack` and `buffer-loop-hoisting` handle small or
  static ones (e1d).
- Recursion must be gone before bufferization: One-Shot Module Bufferize
  skips recursive functions' boundaries. Recognition turns recursive
  functions into region ops at their call sites, so bufferization never sees
  the recursion.

### 6.3 Defunctionalization

- `Stream`'s tail is a thunk, `!idr.fn<() -> Stream T>` (X1: `countFrom`'s
  `lam53` captures `(i, step)`).
- After defunctionalization a thunk is a constructor of a closure sum: a
  **label** (which step function) plus **captures** (the state). That *is*
  Coutts's `∃s. (s, s → Step a s)`: defunctionalization turns codata into a
  state machine.
- When the label is loop-invariant (it is: `countFrom` always rebuilds
  `lam53`), specializing the consumer on the label with the captures as
  holes makes the state first-order. `takeUntil` then becomes `upto`, an
  unfold over one `i64`.
- Needed: closure-shape keys with dynamic captures in `idr-specialize`,
  GHC's SpecConstr for functions. The key attribute exists
  (`#idr.key_closure`); dynamic captures as holes are the extension
  (conjecture that it suffices).
- Recognition runs after defunctionalization, so it sees first-order steps.

### 6.4 Specialization and compile-time evaluation

- Recognition needs specialized clones: a `map` whose `f` is unknown still
  fuses, since the region contains `idr.apply %f(%x)`, but it won't
  vectorize.
- Fusion does not feed back into the simplify loop, so there is no new
  interaction with the phase-ordering history (architecture §2).
- Closed pipelines are evaluated at compile time before fusion ever sees
  them (X1: `[1 .. 100]` became a static list). Fusion only treats what is
  left for runtime.

### 6.5 Stack cells, rc and tail loops

- **idr-stack.** Fusion runs before idr-stack. Stack cells must not end up
  in a frame that makes a tail call: they did, in `vstat` (X1), and that
  turned a loop into stack growth.
- **idr-rc.** It sees only survivors.
- **idr-tail-loops.** It must emit the canonical `scf.while` (compare-only
  before region), so that upstream uplift gives `scf.for` (§2).

---

## 7. The IR design

### 7.1 Load-bearing pieces

**Type `!idr.stream<T>`.** It is a compile-time-only sequence of `T`, and
`T` keeps quantities: `!idr.stream<!idr.lin<A>>` for `LList` elements.

Its verifier rules, each with what it makes unrepresentable:

| rule | statement | makes unrepresentable | read by |
|---|---|---|---|
| V1 | every `!idr.stream` value has exactly one use | duplicated producer work (Wadler's "linear terms"; Futhark's single edge) | rule F0 needs no use check; the rules may move regions freely |
| V2 | its user is a stream op in the same block | a stream crossing control flow | the rules and the lowerings match local DAGs only |
| V3 | never a block argument, function argument or result, `idr.con` field, closure capture, or region yield (except `concat_map`'s inner terminator) | **a stream at runtime** (Kovács's `MetaTy`) | lowering: nothing to represent |
| V4 | no stream op is legal at `idr-lower` (`ConversionTarget`) | **silently unfused**: every stream is lowered to a loop or to linalg, or explicitly `collect`ed, with a remark | the demand error |

**Ops.** Every op has regions for its steps, and the regions capture
loop-invariant values from above, as `scf` regions do.

| op | role | regions and terminators | read by |
|---|---|---|---|
| `idr.stream.unfold %seed… : !idr.stream<T>` | a producer, a state machine | `^step(%s…)`, ending in `idr.stream.yield %x, %s'…`, `idr.stream.skip %s'…` or `idr.stream.done` | F1–F4, F6 |
| `idr.stream.range %lo, %hi {step, inclusive}` | a counted producer: its length is a function of its operands | none | the index-space lowering (tensor dim), `scf.for` trip counts |
| `idr.stream.of %xs : !idr.box<List T>` | traversal of cells; owned or borrowed by type | none | F0, and `collect`'s reuse of exclusive cells |
| `idr.stream.elements %t : tensor<?xT>` | traversal of index-space data (`Vect` as a tensor) | none | the index-space lowering |
| `idr.stream.map`, `filter`, `take_while` | transformers | `^(%x) → idr.stream.yield %y` / `%keep : i1` | F1–F3 |
| `idr.stream.zip %a, %b` | the pull pair | none | F4 |
| `idr.stream.concat_map %s` | the push nest | `^(%x)` building an inner stream, ending in `idr.stream.inner %t` | F5 |
| `idr.stream.fold %s iter(%acc = …)` | the consumer | `^(%acc…, %x)`, ending in `idr.stream.continue %acc'…` or `idr.stream.break %r…`; IO threads `!idr.world` through `%acc` (linear, as today) | F6, the lowerings |
| `idr.stream.collect %s : … -> !idr.box<List T>` or `-> tensor<?xT>` | an explicit materialization; its result type is the representation choice | none | the survivor path; remarks; F0, F7 |

Why `range` is its own op and not an `unfold` with a counter step: the
index-space fact (the length is an arithmetic function of the operands)
lives in the op, not in a pattern that guesses it.
- A canonicalization turns a counted `unfold` into `range`: a single
  integer state, `next = s + c` with `c` constant, and `done` on
  `cmp(s, bound)` with an invariant bound. This is the same test as
  upstream uplift (`UpliftWhileToFor.cpp`), applied before lowering, so that
  linalg sees it.
- The one subtle case: `[minInt .. maxInt]` has 2^64 elements, and its
  length does not fit `index`. That instance stays an `unfold`, and the
  loop is not a tensor.

### 7.2 Recognition: recursion schemes, by structure

The pass is `idr-recognize-schemes`. It runs once, after
`idr-simplify`/`idr-defunctionalize`.
- It classifies each self-recursive function by the shape of its body.
- At each call of a classified function, it replaces the call with stream
  ops whose regions are clones of the function's non-recursive parts.
- The function stays for its other callers, and `symbol-dce` removes it
  when none remains.

The driver of a scheme is a list parameter (or a `Nat`, or a `Stream`).
Every recursive call passes a field of the driver's match: size-change
`Smaller`, checked locally. Every other argument is either invariant
(`Same`, and captured by the regions) or an accumulator.

| scheme | body shape (after specialization) | becomes | examples (X1) |
|---|---|---|---|
| left fold | `match xs { Nil → h(acc); Cons(x, t) → tail call g(step(acc, x), t) }`, possibly with an early `return` (break) | `fold (of xs)` | `foldl` clones, `total'`, `lengthTR`, `elem`; `traverse_` once record eta exists (it is a left fold with the world as accumulator) |
| map / filter / mapMaybe | `Cons(x, t) → Cons(f x, g t)` / `if p x then Cons(x, g t) else g t` / `case f x of Just y → Cons(y, g t); Nothing → g t`; `Nil → Nil` | `collect (map/filter (of xs))` | `mapImpl$spec`, `filter$spec`, `bump`, `Vect`'s `map` |
| zipWith | recursion on two drivers' tails at once | `collect (map (zip (of xs) (of ys)))` | `Data.Zippable.zipWith` clones, `Vect`'s `zipWith` |
| unfold | no list driver; leaves are `Nil`, `Cons(e, g(next))`, `Cons(e, Nil)`, or `g(next)` (skip) | `collect (unfold)` | `upto`, `takeUntil ∘ countFrom` (after closure-shape specialization, §6.3) |
| `Nat`-driven unfold | `g Z … = Nil; g (S k) … = Cons(e, g k …)` | `collect (map (range 0 m))` | `build` in vdyn; `replicate` |
| accumulate-then-reverse | a left fold whose accumulator only grows by prepending (`reverseOnto acc (f y)`), with `reverse acc` at `Nil` | `collect (concat_map f (of xs))` (F7) | `listBindOnto`: comprehensions, the list monad |
| right fold, not to a list | `Cons(x, t) → k(x, g t)` with `k` not a constructor | index space: a downward loop; cells: not fused (remark `right-fold-on-cells`) | `foldr (-) 0` |
| anything else | two recursive calls, recursion on a non-field, mutual recursion that is not a case block | not recognized (remark `unrecognized(<shape>)`) | tree folds; S8 |

**Why this is not a fusion engine.**
- Recognition is a classifier of shapes, like idr-tail-loops' tail-call
  test.
- It never unfolds a recursion, so it has nothing to stop.
- The same classifier handles the Prelude and the user's functions, because
  after monomorphisation both are first-order clones.
- **A registry entry** ("faster, never different",
  `Registry/Recognized.idr:1-5`) is needed only where a Prelude definition
  hides its scheme behind arithmetic Idris cannot see. Today there is one
  such case: the `Range` instance's `compare`-then-`takeUntil` for `[x .. y]`
  (`Types.idr:1122-1126`). It is recognized structurally anyway once
  `takeUntil ∘ countFrom` is an `unfold` and the counted-unfold
  canonicalization applies. A registry entry is the fallback, diffable
  against Chez.

### 7.3 Rules as data

A finite table. Each rule is a pattern on stream ops, and removes at least
one op. Its facts are named; its id appears in the remarks.

| id | before | after | facts consumed | owner |
|---|---|---|---|---|
| F0 | `of(collect s)` | `s` | `collect`'s result has one use (SSA) | ours (`stream/unstream`) |
| F1 | `map f (unfold st)` | `unfold st'` (apply `f` at `yield`) | §5.2 | ours |
| F2 | `filter p (unfold st)` | `unfold st'` (`yield` if p, else `skip`) | §5.2 | ours |
| F3 | `take_while p (unfold st)` | `unfold st'` (`done` if not p) | §5.2 | ours |
| F4 | `zip (unfold a) (unfold b)` | `unfold (a × b × buffer)` | §5.2 | ours (pull) |
| F5 | `fold (concat_map f s)` | `fold s` whose body folds `f x` | §5.2 | ours (push: nested loops) |
| F6 | `fold (unfold st)` / `fold (of xs)` | `scf.while` (canonical form when the state is a counter) | none | ours → MLIR uplift, LICM |
| F7 | `reverse(prepend-accumulating fold)` | `collect` in order | the accumulator is only prepended to, and used once | ours |
| F8 | `fold (range …)` with all regions pure, no break, no world | `scf.for` with `iter_args` | E = ∅ | ours (closes the §2 generator gap) |
| L1 | an index-space DAG (sources `range`/`elements`; `map`, `zip`, `filter`; consumers without break or world; `collect` to tensor) | one `linalg.generic` per op on `tensor<?xT>`: filter is a keep mask, zip slices both to `min` | lengths; E = ∅ for speculated regions | ours emits, **MLIR fuses** |
| L2 | linalg ∘ linalg | fused generic | `ControlFusionFn`: the producer has a single use, or a cheap body (no calls, ≤ k ops) | **MLIR** `populateElementwiseOpsFusionPatterns` |
| L3 | `tensor.dim` of results | the source lengths | none | **MLIR** `resolve-ranked-shaped-type-result-dims` |
| L4 | static shapes | `vector` ops, `vector.contract`, ordered reductions | `fastmath<none>` on Double | **MLIR** vectorizer |
| L5 | producer and consumer loops through a surviving buffer | one loop | single consumer (see §2 on `maximal`) | **MLIR** `affine-loop-fusion` + `affine-scalrep` |

- The F rules are `RewritePattern`s registered as the stream ops'
  canonicalization. They build regions, which DRR cannot, so they are C++;
  the table above *is* their specification.
- Each rule gets one lit test that states its property, not the output's
  op sequence: "no `!idr.stream` remains, and the result equals the unfused
  one under `--validate`" (architecture §5.2).
- Rules F1–F5 check §5.2 by reading the effects lattice (architecture I.2)
  on the regions' ops and calls. A rule that fails its condition does not
  fire. The remaining `collect` produces the `effects` remark.

### 7.4 The two lowerings

**`idr-streams-to-tensors`** (L1). Each maximal index-space DAG becomes
tensors:
- `range lo hi` → `tensor.empty(%len)` plus a generator generic
  (`linalg.index`);
- `elements %t` → `%t`;
- `map` → a parallel generic;
- `zip a b` → `extract_slice` both to `min(len a, len b)`. For
  `Vect n a × Vect n b`, where both lengths are the same ghost, there is no
  slice;
- `filter p` → a keep-mask generic. Downstream folds `select` on the mask,
  downstream maps carry it;
- `fold` → a reduction generic, its accumulator a rank-0 tensor (never a
  `linalg.fill`: see the e1 hazard);
- `collect` → the tensor itself. A masked collect needs compaction, which
  is a sequential scf loop into a buffer of the source's length, then a
  slice.

Then run `linalg-fuse-elementwise-ops` with the control function,
canonicalize, and `resolve-ranked-shaped-type-result-dims`. A reduction left
with only input-less generator inputs becomes F8's `scf.for`.

**`idr-streams-to-loops`** (the residue: F6 and `collect`).
- A `fold` over an `unfold` is `scf.while` over (state…, acc…):
  - the step region is inlined;
  - `yield` runs the fold body;
  - `skip` loops;
  - `done` and `break` exit.

  A counter-shaped state emits the compare-only before region, so that
  upstream uplift makes `scf.for`.
- `collect` to cells is the §6.1 loop.

**Example**, `sum (takeWhile (< k) (map f (iterate g x)))`, a data-dependent
length, hence a stream. After F1, F3 and F6:

```mlir
%r:2 = scf.while (%s = %x, %acc = %c0) : (i64, i64) -> (i64, i64) {
  %y = <f's body on %s>
  %go = arith.cmpi slt, %y, %k : i64
  scf.condition(%go) %s, %acc : i64, i64       // done when not (y < k)
} do {
^bb0(%s: i64, %acc: i64):
  %y = <f's body on %s>                         // CSE'd with the before region by LICM/CSE, or carried
  %a = arith.addi %acc, %y : i64
  %s2 = <g's body on %s>
  scf.yield %s2, %a : i64, i64
}
```

### 7.5 The facts handed to MLIR

| fact | Idris source | MLIR carrier | MLIR consumer |
|---|---|---|---|
| length before production | range bounds; `Nat` driver; `Vect` closed `N` or ghost `n` (R11) | `tensor.empty(%n)` sizes; static shapes | linalg loop bounds; `tensor.dim` folding (e6); `scf.for` bounds; SCEV (e3 closed form) |
| equal lengths | `Vect n a`, `Vect n b` share the ghost `n` | the same SSA `%n` in both `tensor.empty`s | no `min`/slice; ValueBounds (R5) |
| purity, totality, crash-freedom | effects lattice, `idr.total` | only ops with no memory effects in linalg bodies; `llvm.loop.mustprogress` | elementwise fusion clones bodies freely; speculation in masked maps |
| single use / work safety | SSA after specialization; V1 | use counts | `ControlFusionFn`; affine fusion's first greedy phase (`maxSrcUserCount=1`) |
| exclusivity | inferred (memory-theory) | writable arguments; no aliasing | One-Shot in-place decisions |
| floating-point order | Idris's evaluation order | `fastmath<none>`; reduction iterators lowered in index order; ordered `vector.reduction` with an accumulator | vectorizer, LLVM (e4: no `reassoc`) |
| trip counts | size-change, `Nat`, lengths | `scf.for`/`affine.for` bounds | LLVM unrolling, vectorization, closed forms |

### 7.6 Place in the pipeline

Today (`Registration.cc:15-31`) the steps are idr-simplify, then
idr-defunctionalize, then canonicalize, then idr-stack, and so on. With
fusion:

```
idr-simplify                        (inline, specialize, evaluate at compile time)
idr-defunctionalize, canonicalize
idr-recognize-schemes               NEW: calls of recursion schemes → !idr.stream ops
canonicalize                        rules F0–F8 (stream-op canonicalization) + remarks
idr-streams-to-tensors              NEW: index-space DAGs → tensor + linalg (L1)
linalg-fuse-elementwise-ops{ctl}    upstream (L2), then canonicalize,
resolve-ranked-shaped-type-result-dims (L3)
idr-streams-to-loops                NEW: the residue → scf.while / scf.for; collect → loops
uplift patterns (populateUpliftWhileToForPatterns), loop-invariant-code-motion   upstream
idr-stack, idr-rc, idr-tail-loops   existing, on survivors only
[vectorize static shapes]           upstream (L4)
one-shot-bufferize, ownership-based-buffer-deallocation,
promote-buffers-to-stack, buffer-loop-hoisting                  upstream
convert-linalg-to-affine-loops, affine-loop-fusion, affine-scalrep, lower-affine   upstream (L5)
idr-lower, …                        existing
```

Why it goes there:
- After the simplify loop, because functions are monomorphic clones with
  their function arguments inlined.
- After defunctionalization, because `Stream` thunks are data.
- Before idr-stack and idr-rc, because counting and reuse should see only
  survivors, and because stack cells in a tail-calling frame break loops
  (X1).
- The array half is the phase-4 array pipeline of architecture I.5.

### 7.7 Named remarks, and the opt-in error

**Remarks.** The category is `idr-fuse`, through MLIR's remark engine (as
the simplify loop already uses it, `Simplify.cc:20-22`).
- `passed <rule> at <loc>`: for example
  "F1: `map` fused into the unfold of `[1 .. n]`".
- `analysis index-space(<source>, <length expr>)` or
  `analysis stream(<why not an index space>)`.
- `missed materialized(<reason>) at <loc>`. The reason is an enum, not
  free text:
  - `shared(<use locs>)`;
  - `escapes(returned | stored | passed to <fn>)`;
  - `unrecognized(<shape>)`;
  - `effects(<E(P)>, <E(C)>)`;
  - `right-fold-on-cells`;
  - `tree-recursion`;
  - `length-overflow` (`[minInt .. maxInt]`).

This is One-Shot's `print-conflicts` idea (memory-theory §6.11), applied to
fusion.

**Opt-in error.** The language is unchanged: there is no pragma, and the
profile rejects unknown ones.
- An `idris-mlir` option, `--demand fused=Main.f`, the same mechanism
  memory-theory proposes for `fip`.
- It turns every `missed` remark reached from `Main.f` into
  `unsupported (fusion): <reason> at <loc>`.
- Without the option, a program is never rejected for failing to fuse
  (P1 of memory-theory §6.11: never miscompile, always report).

---

## 8. The suite: pipelines that must become allocation-free loops

The properties are `idr-expect` properties, stated in the `mlir.expect` form
the e2e runner already reads (`<step>: <property>…`,
`tests/e2e/v1/known-constructor/mlir.expect`).
- Existing: `no-heap-allocation=@f` (`Passes.td:352-385`).
- New, each defined once as a checker:
  - `constant-stack=@f`: no call reachable from @f is on a call-graph
    cycle, so every recursion became a loop;
  - `fused=@f`: after the rules, no `idr.stream.collect` in @f;
  - `no-buffer=@f`: after bufferization, no `memref.alloc` whose size
    depends on a runtime value.

Every test also runs against Chez (the existing oracle). "C" is the measured
C loop (X1, `ref/`). The targets are for n = 1e7 (1e6 for compr), best of 3,
and are **≤ 1.25 × C or C + 3 ms**, whichever is larger (process start is
about 1 ms).

| # | pipeline | properties (after `idr-lower` unless stated) | C (s) | target | Chez (s) |
|---|---|---|---:|---:|---:|
| P1 | `sum (map f [1 .. n])` | `no-heap-allocation`, `constant-stack`, `no-buffer`, `fused` (after canonicalize) | 0.001 | 0.004 | 3.55 |
| P2 | `foldl (+) 0 (map (*3) (filter p [1 .. n]))` | same | 0.032 | 0.040 | 3.15 |
| P3 | `length (zip [1 .. n] (map (*2) [1 .. n]))` | same, plus: no loop in the root (the length is `min`) | 0.002 | 0.005 | 8.14 |
| P4 | `sum [x * y \| x <- [1 .. n], y <- [1 .. 100], p]` | same | 0.293 (1e6) | 0.366 | 11.6 |
| P5 | `traverse_ printLn (map f [1 .. n])` | `no-heap-allocation`, `constant-stack` | 4.2 (musl `printf`; I/O-bound) | ≤ C | 35.7 |
| P6 | user `total' 0 (bump (upto 1 n))` | as P1 | 0.001 | 0.004 | 2.88 |
| P7 | `Vect 4 Double` chain in a loop | `no-heap-allocation`, `constant-stack`; the body is `vector` ops (by property: no `idr.con`) | 0.057 | 0.071 | 2.27 |
| P8 | `Vect m Double` from `build m`, then map/map/zipWith/foldl | as P1 | 0.030 | 0.038 | 16.1 |
| P9 | `sum (takeWhile (< k) (map f (iterate g x)))` (a stream) | as P1 | measure | 1.25 × C | measure |
| P10 | `sum (map f xs)` with `xs` read from input | only the input list is allocated: `fused`, one traversal | measure | 1.25 × C | measure |
| P11 | `let xs = map f [1 .. n] in sum xs + length xs` (shared) | exactly one buffer of n words, zero cells; `length` is the dim | measure | 1.25 × C | measure |
| P12 | `map f` over an exclusive list that is returned | `reuses-in-place=@f`, `constant-stack` | n/a | no allocation | n/a |
| P13 | `foldr (-) 0.0 [1.0 .. x]` | ordered: same digits as Chez; `constant-stack` | measure | 1.25 × C | measure |
| P14 | `index i (map f v)` on `Vect n` | no `map` remains: one `f` call | n/a | O(1) | n/a |

Negative tests, one per remark reason:
- `shared` (P11 without the tensor path);
- `effects` (a crashing `div` in a map over a `partial` producer);
- `tree-recursion`;
- `length-overflow`.

Each is checked twice: the remark is emitted, and `--demand` rejects with
that reason.

---

## 9. The staged path

Each step is useful alone, names what it consumes, and names what it makes
true in §8.

- **S0. Loops first** (no fusion; small; removes today's segfaults in
  `trav`, `vstat` and `upto`).
  - (a) **Record eta** as a folder of `idr.con`:
    `con C(field x[C,0], …, field x[C,k]) → x`, when C is the only
    constructor or `x` is known to be C, and every field is read exactly
    once (linear fields included). It makes every raised IO fold a tail
    loop (X1, `trav`).
  - (b) **Case blocks as continuations** (architecture Part II step 2). The
    `loop` ↔ case-block cycle in `vstat` and `upto` becomes a self loop.
  - (c) **idr-tail-loops emits the canonical `scf.while`**, so that
    `populateUpliftWhileToForPatterns` applies.
  - Makes: `constant-stack` for the folds and the IO fold. It is
    prerequisite for every loop fusion produces.
- **S1. `!idr.stream`, its ops, V1–V4, and `idr-streams-to-loops`.** Tested
  on hand-written IR (`tests/idr/stream/`), with `constant-stack` and the
  JIT-based differential check. Load-bearing: S2 targets these ops, and V4
  is the demand error's hook.
- **S2. Recognition of the list schemes and rules F0–F3, F6, with
  remarks.**
  - Schemes: left fold, map/filter/mapMaybe, unfold. `collect` to cells by
    reverse-and-reverse-in-place (§6.1).
  - Makes P1, P2, P5, P6 allocation-free and constant-stack by the stream
    path alone. It also makes the ignored `%transform "tailRec…"` rules moot
    for every recognized function.
- **S3. `range`, the index-space lowering (L1), the upstream linalg fusion
  (L2, L3), F8, and bufferization.**
  - Makes P3 O(1), P1 and P2 at C speed, and P11 one buffer.
  - Files the §2 generator-gap feature report under `upstream/`.
- **S4. `Vect` as tensors.**
  - R6: closed indices are static shapes.
  - R11 and R12: ghost `n` as the tensor dim.
  - `elements`, and `Nat`-driven unfolds as `range`.
  - Makes P7, P8, P14. Deletes `Vect`'s cell representation where R12's
    proofs hold.
- **S5. Completeness of the residue.**
  - F4 (zip), F5 (concat_map), F3 with break, F7 (accumulate-then-reverse);
  - closure-shape specialization for `Stream` thunks (§6.3), so that
    `takeUntil ∘ countFrom` is an unfold without the registry.
  - Makes P4, P9, P10.
- **S6. `--demand fused=…` and the three new `idr-expect` properties**; the
  negative tests.
- **S7. Composition with exclusivity.** `collect` over an exclusive `of xs`
  reuses `xs`'s cells, and survivors' tensors are `writable`. Makes P12.
  Needs memory-theory's path steps 2-4.
- **S8 (conjecture). Hylomorphisms over trees.** An unfold of a polynomial
  functor consumed by a fold, fused into one recursion without the tree:
  the only home-rolled step beyond lists. Do it only if a benchmark shows
  the need.

What stays upstream throughout:
- linalg fusion, shape folding, bufferization, deallocation,
  stack promotion, vectorization;
- `scf` uplift, LICM;
- affine fusion and scalar replacement;
- the remark engine and the greedy rewrite driver.

What is ours:
- one type, about ten ops, four verifier rules;
- one classifier;
- nine rewrite rules (F0–F8);
- two lowerings;
- one `ControlFusionFn`.

---

## Open questions

1. **The generator gap upstream.** Would upstream accept that
   `areElementwiseOpsFusable` fuse an input-less producer into a reduction,
   taking the extent from the producer's `outs` operand? If so, F8 goes
   away. Otherwise F8 stays, a single pattern.
2. **`affine-loop-fusion{maximal}` and sharing.** Upstream has no option
   that disables the cost model while keeping `maxSrcUserCount = 1`
   (`LoopFusion.cpp:817-835`). L5 is therefore safe only where no buffer is
   shared by decision. Should the design skip L5 until upstream has that
   option (a small feature request), relying on L2 and F8?
3. **Crash order.** Is "at most one side can crash" (§5.2) decidable
   cheaply from the effects lattice, or should any two crash-capable
   regions simply not interleave? The latter is simpler, and loses little
   (conjecture).
4. **Size-change after specialization.** Clone keys keep parameter
   identity, but erased and hole parameters shift positions
   (architecture's open question). Recognition's local check (the argument
   is a match-bound field) may suffice alone. Is the Idris edge then only a
   cross-check?
5. **Masked collect.** Compaction after a filter-to-tensor is a sequential
   loop today. Is a two-pass count-then-write (exact size, no slice) better
   for the survivors that need a tensor?
6. **`Stream` via closure-shape specialization** (§6.3). Does
   `idr-specialize` with dynamic captures as key holes terminate within
   the existing clone budget? The label is invariant, so there is one clone
   per (function, label). Conjecture: yes.
7. **Double `foldl` vectorization.** The ordered `llvm.vector.reduce.fadd`
   is serial. Should Double reductions skip vectorization of the reduction
   (keeping the map vectorized), to avoid lane shuffles? Measure.
