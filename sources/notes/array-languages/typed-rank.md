# Typed rank polymorphism and shape typing

Notes for an Idris-hosted typed array language compiled through MLIR (proposal 0004's rank
above 1). Cluster `typed-rank`. Written 2026-10-09.

Every source claim cites the stored file under `sources/` (staged at
`scratchpad/selfhost/apl/stage/sources/`, same relative layout; `shivers-2019-remora` and
`docs/mlir/` are already in the repository's `sources/`; `code/mlir/include/mlir/Dialect/...`
paths are the sibling cluster's staged MLIR excerpts at the LLVM pin). Claims are marked like
the proposals: **read** (in the cited file), **checked** (run here; the probe files are in
`scratchpad/selfhost/apl/idris-probe/`, typechecked with the repository's Idris 2
`0.8.0-1c630e67c`), **conjecture** (my synthesis, not in any source). PDF citations give the
section and the printed page; TeX and code citations give `file:line`.

- [0. What the cluster answers](#0-what-the-cluster-answers)
- [1. Remora](#1-remora): ESOP 2014, semantics 2019, constraints 2018, dissertation 2020, code
- [2. Gibbons: Naperian functors](#2-gibbons-aplicative-programming-with-naperian-functors)
- [3. Xi and Pfenning: DML bound checks](#3-xi-and-pfenning-eliminating-array-bound-checking)
- [4. Trojahner and Grelck: Qube](#4-trojahner-and-grelck-qube)
- [5. Futhark size types (2021, 2023)](#5-futhark-size-types)
- [6. Type-level Nat solvers: Diatchki, natnormalise](#6-type-level-nat-solvers)
- [7. Decidability, in one table](#7-decidability-in-one-table)
- [8. What this means for 0004: rank with no ceiling](#8-what-this-means-for-0004-rank-with-no-ceiling)
- [9. Not stored, and open questions](#9-not-stored-and-open-questions)

## 0. What the cluster answers

**How shapes and ranks are expressed in types.** Three families.
1. *An index language beside the terms* (Dependent ML, Remora, Qube): types are indexed by a
   small sorted language, never by program terms. DML: linear integer and boolean indices
   (read: `papers/xi-1998-dml-bounds/pldi98dml.pdf` §2.4, p. 3). Remora: two sorts, `Dim`
   (naturals with `+`) and `Shape` (sequences of naturals with `++`); an array type is
   `Arr τ ι` (read: `papers/slepak-2019-semantics/formalism.tex:9-26`, `:425-436`). Qube: an
   integer sort and a sort family `idxvec(i)` of integer vectors of length `i`, with
   `++`, `take`, `drop` (read: `papers/trojahner-2009-qube/paper.pdf` §3.1, p. 647).
2. *Sizes as term variables* (Futhark): only array sizes may appear in types, written as
   variables or constants (2021) or arbitrary integer expressions compared syntactically
   (2023); no rank polymorphism, arrays of arrays (read:
   `papers/henriksen-2021-size-types/paper.pdf` abstract and §7;
   `papers/bailly-2023-size-dependent/paper.pdf` abstract).
3. *Host-language type-level programming* (Gibbons in Haskell): a rank-r array is
   `Hyper '[f1, ..., fr] a`, a type-level list of dimension functors; size is the functor
   (`Vector n`) (read: `papers/gibbons-2017-naperian/aplicative.pdf` §5, pp. 14–17).

**How rank polymorphism is typed and elaborated.** Remora is the only source that types the
full Iverson model. A function's type states its *cells* only; an argument of shape `s` has
frame `f` where `s = f ++ c` and `c` is the expected cell shape; the *principal frame* is the
join of the function array's frame and all argument frames in the prefix order (J's prefix
agreement), and the result is `Arr τ' (principal ++ ι')` (read:
`papers/slepak-2019-semantics/figs.tex:328-352`, T-App; `formalism.tex:530-542`). Frame
polymorphism is implicit; cell polymorphism is explicit Π/∀ that type inference instantiates
(read: `papers/slepak-2020-dissertation/Dissertation.pdf` abstract, p. v). Elaboration turns
implicit lifting into explicit `map` over the principal frame plus `rep` (cell replication)
per argument (read: Dissertation §11.1, pp. 159–164; `code/remorac/src/remora-internal/map_replicate_ast.ml:255-294`).

**How shape arithmetic is solved.** Checking with all indices given needs only validity of
single equalities, decided by canonical forms: a Dim is a constant plus coefficients per
variable, a Shape is a flattened concatenation of single Dims and Shape variables (read:
`formalism.tex:464-524`; `papers/slepak-2018-constraint/paper.pdf` §3). Inferring index
arguments needs ∀∃ word equations over the free monoid on N with Presburger generators;
Remora solves them with Makanin's algorithm parameterized by a dimension theory and an ILP
back end (read: Dissertation ch. 7, pp. 101–114). DML generates linear constraints, eliminates
existentials, and refutes negations with Fourier–Motzkin (read: `pldi98dml.pdf` §3.1–3.2).
Qube maps vector constraints to the array property fragment after splitting `++`/`take`/`drop`
and hands linear constraints to an SMT solver (read: `paper.pdf` §6, pp. 660–662). Futhark
uses unification only, syntactic on size expressions (read: Bailly §4.2, p. 36). GHC plugins:
an SMT solver with improvement (Diatchki) or sum-of-products normalization (natnormalise)
(read: §6 below).

**What is decidable.** See [§7](#7-decidability-in-one-table). The headline: the universal
fragment of the shape theory (checking) is linear time; the existential fragment
(Makanin) is decidable but NP-hard and PSPACE; the ∀∃ fragment that inference produces is
undecidable in general (Durnev: ∀∃³ positive already), and Remora restricts constraints to
conjunctions in a mixed-prefix fragment it can decide (read: `slepak-2018-constraint/paper.pdf`
§5; Dissertation §5.3 pp. 68–69, §7.3 pp. 113–114).

**What it means for Idris.** Idris 2 decides index equality by conversion. Shapes as erased
indices work exactly where conversion and unification already do the canonical-form work,
and Remora's typing rule is expressible as a library when shapes are outer-first snoc lists
(checked, [§8.2](#82-the-idris-side-shapes-as-erased-snoc-list-indices)). Where they do not
(associativity of `++` and commutativity of `+` on open terms, a frame extended by an opaque
shape variable), a library lemma or a reflection tactic must supply the proof (checked). The
compiler, which reads checked TT, then has every frame and cell shape it needs to emit
`linalg` with no rank limit ([§8.3](#83-the-mlir-side-frames-and-cells-as-indexing-maps)).

## 1. Remora

### 1.1 ESOP 2014: the first static type system for Iverson's model

Stored: `papers/slepak-2014-remora/paper.pdf` (LNCS), `paper-full.pdf` (with appendices).

**Key ideas (read).**
- Every function has an expected rank per argument; an argument of higher rank is viewed as a
  frame of cells; arguments' frames must be prefixes of one frame, cells of the smaller frames
  are duplicated ("prefix agreement", from J) (`paper-full.pdf` §2.1, Fig. 1).
- Untyped core: application is itself lifted, so arrays of functions may appear in function
  position, generalizing APL from SIMD to MIMD (§3, Fig. 2). Reduction rules `nat`
  (naturalize ∞ and negative ranks against the actual argument), `lift` (duplicate cells into
  the principal frame), `map` (split into an array of applications), `collapse` (frame of
  equal-shape arrays to one array) (§3.2, Figs. 4–5).
- The empty-frame dilemma: lifting over a frame with a zero has no cells to inspect, so the
  result cell shape is unknowable dynamically; J probes the function with a fill cell, which is
  unsafe for effectful or input-dependent functions (§3.2). Types settle it: the typed
  reduction is type-directed and carries annotations precisely so empty frames get the right
  shape (§4.3).
- Typed Remora: a DML-style separate index language, `Nat` and `Shape` sorts with `+`; ∀ over
  atom types (a type variable may not stand for an array type, so `A(S) t` means "any scalar");
  Π over indices; Σ replaces boxes; type equivalence identifies `A(S m...)(A(S n...) τ)` with
  `A(S m... n...) τ` (§4.1–4.2, Figs. 6–8). T-App finds each term's frame and takes the
  maximum in the prefix order; no maximum means ill-typed (§4.2).
- Decidability: index equivalence is decided in the combined theory of naturals and lists of
  naturals, cited as decidable via Nelson–Oppen (§4); soundness by progress and preservation
  (§4.4, appendix C). Data-dependent result shapes (`iota`, `reshape`, `readvec`, `filter`-like
  `copy`) return dependent sums; variants `iota1`/`iotak` trade generality for a known rank
  (appendix A table, appendix B).

**Steal.** The frame/cell decomposition as the *only* lifting rule, with prefix agreement:
it is static (decided from shapes), needs no size-1 stretching, and every lifted argument is
read at a prefix of the loop indices. The empty-frame answer: the result cell shape comes from
the type, never from running the function. Typed `Σ` for data-dependent shapes, with
rank-specialized variants (`iota1`) so the common case stays unboxed.

**Avoid.** Fully explicit type and index application in the surface (the paper's own future
work says it is unusable without inference, §5). Negative and ∞ ranks as runtime
naturalization: the typed version replaces them by explicit index application, and so should
we. The ESOP index theory's `+` on shapes (later replaced by `++`).

**Limits.** No implementation beyond a Redex model; no inference; no compilation; the
decidability argument is a citation, not a procedure (the 2019 paper corrects it, §1.2).

### 1.2 The Semantics of Rank Polymorphism (2019)

Stored: `papers/slepak-2019-semantics/` (TeX).

**Key ideas (read).**
- Two kinds of types, `Atom` and `Array`; arrays only contain atoms; a box is an atom holding
  an array of hidden shape, typed by Σ (`formalism.tex:181-217`). Σ can hide any part of a
  shape: a vector of unknown length, a matrix with 3 rows and at least 2 columns
  (`(Shp 3 (+ 2 c))`), shapes whose leading axis is 10 (`(++ (Shp 10) s)`), ragged arrays as
  arrays of boxes, and raggedness on any axis (`formalism.tex:108-179`). The type thereby marks
  where implicit parallelism is irregular (`formalism.tex:164-168`).
- Index language: `Dim` and `Shape` sorts, `+` and `++` the only operators; types of `append`,
  major-axis and minor-axis `mean` show the role of a trailing `Shape` variable
  (`formalism.tex:39-90`). Quantifying over `Array`-kinded types is sugar for Π over a shape
  and ∀ over an atom type (`formalism.tex:92-106`).
- Index theory: the free monoid on N with associativity, identities, equidivisibility and a
  length homomorphism `L`; prefix subtraction as a partial operator
  (`formalism.tex:425-462`, `figs.tex:416-440`). Product of dimensions is deliberately not in
  the index language, to stay in Presburger arithmetic: `ravel` returns a box
  (`formalism.tex:320-330`).
- Type checking needs only validity of isolated equalities, decided by canonical forms, with a
  completeness argument by interpretations (`formalism.tex:464-524`). Shapes form a lattice
  under prefix order with ⊤ for incompatible shapes; a finite join that is not ⊤ means the
  shapes are totally ordered and the join is one of them (`formalism.tex:530-542`).
- Static semantics with unique typing, "particularly important" because types drive the
  reduction (`formalism.tex:544-568`). Typing rules `figs.tex:167-353`: T-Array, T-Frame, the
  empty forms T-0A/T-0F carrying their types, T-Box, T-Unbox (whose result frame is the box
  array's shape), T-TApp and T-IApp (which also lift over arrays of polymorphic functions), and
  T-App with the principal frame `⊔{ι_f, ι_a...}`.
- Dynamic semantics: `lift` replicates function and argument atoms into the principal frame
  with `Rep`/`Split`/`Concat`, `map` turns an equal-frame application into a `frame` of
  scalar-frame applications, `collapse` flattens a frame of arrays (`figs.tex:457-610`).
- Partial type erasure: types become indices (array types become their shapes; functions,
  ∀, Π, Σ and base types become the scalar shape); ∀-bound type variables become index
  variables; index binders (`Iλ`, `unbox`) survive erasure because the indices they bind
  change program behaviour. A bisimulation proves erased and explicit programs step in lock
  step (`type_erasure.tex:1-139`). Erasure "moves the decision about how to break arguments
  into cells from the function's type into the application term", the last step before
  explicit `map`/`replicate` (`conclusion.tex:40-54`).
- Related: DML assumes a fully decidable index theory, Remora's is not (Durnev); Gibbons's
  embedding "defines much of the rank-polymorphic lifting machinery in terms of
  transposition" (`related_work.tex:142-170`).

**Steal.** The two-sort index language and its canonical form, exactly. The prefix-order
lattice: the principal frame is always one of the frames, so it needs no arithmetic. The
erasure result as a design rule: what must survive to run time is shapes, never types, and
only where a binder introduces them (this is the QTT quantity question in Idris terms:
dimension and shape binders that reach an `Iλ`/`unbox` are used at ω, everything else is 0).
Σ for data-dependent and ragged shapes, with the type saying which axes are ragged.

**Avoid.** Run-time type annotations everywhere (the formal semantics needs them; the erasure
section shows they reduce to shapes). Products in types: Remora keeps them out for
decidability; a compiler can still know the product of a frame (it is `tensor.dim`
arithmetic), it just should not need to *prove* things about it.

**Limits.** No inference (deferred), no compiler; the canonical-form decision is for the
universal fragment only.

### 1.3 Rank polymorphism viewed as a constraint problem (ARRAY 2018)

Stored: `papers/slepak-2018-constraint/paper.pdf`.

**Key ideas (read).**
- Checking an application is two conditions: each parameter's cell shape is a suffix of the
  actual argument shape (the rest is the frame), and all frames are prefixes of one principal
  frame (§3). As first-order formulas these are ∃-completions (`prefix(l,r) ≡ ∃c. l ++ c = r`)
  under ∀ for the environment's index variables, but the checker never sends that mixed
  formula to a solver: canonical forms decide each suffix check in the universal fragment, the
  completions *are* the frames, and the principal frame is a linear search (§3).
- Inference introduces existentials for index arguments and frames:
  `∀a... ∃e..., f... . ⋀ (f_i ++ ι_i = κ_i)`; a solution for `e` in terms of `a` is what
  elaboration inserts (§4). Cell-rank-polymorphic functions (`reduce`, `append`, `scan`) make
  the split ambiguous (`(Shp 3 4)` as frame `(Shp)`+cell `(Shp 3 4)` or frame `(Shp 3)`+cell
  `(Shp 4)`); the convention is a scalar frame, i.e. no frame existential for them (§4).
- ∀* and ∃* fragments are decidable, ∀*∃* and ∃*∀* are not; plan: treat universal variables as
  fresh generators and solve the existential fragment, since Makanin's boundaries never fall
  inside a generator, which is exactly the treatment a universal needs (§5). Existential
  fragment is NP-hard (it embeds Presburger arithmetic: N is the free monoid on one generator);
  universal fragment is linear time by associativity (§5).

**Steal.** Split checking from inference: the checker stays in the linear-time universal
fragment by computing frames, not guessing them. The scalar-frame convention for
cell-polymorphic primitives, which makes their instantiation unique.

**Avoid.** Sending mixed-quantifier shape formulas to a general solver.

**Limits.** A plan, no implementation (the dissertation is the implementation).

### 1.4 The dissertation (2020)

Stored: `papers/slepak-2020-dissertation/Dissertation.pdf`.

**Key ideas (read).**
- Thesis: the implicit, data-driven control structure of higher-order rank-polymorphic
  programs can be identified statically by a type system suited to the style (§1.1, p. 2).
  Function types describe cells only; frame polymorphism is implicit and identified by the
  typing rules; cell polymorphism is explicit (abstract, p. v).
- Ch. 6, local inference: no principal types even without ∀ (`app+` of a rank-1 `x` and `y`
  appended and added to a 5-vector has six monomorphic types and no most general one), so
  polymorphism is declared by annotation and inference only *instantiates* (pp. 73–74). Rank
  annotations on parameters (`(x 1)`) stay in the surface because they are shorter and let
  inference relate dimensions (`vec+` must unify the two lengths) (p. 74). Bidirectional
  synthesis/checking/application judgments à la Dunfield–Krishnaswami, each producing the
  elaborated term (pp. 74–75, §6.3). An *archive* Φ of dimension equalities outlives the
  scopes of the existentials it mentions, because facts like "even" and "multiple of three"
  must combine into "multiple of six" (pp. 76–78, §7.1 p. 103).
- The application rules introduce existential *argument frame* and *frame extension* shape
  variables and equate `fun-frame = arg-frame ++ extension` or the converse, curried one
  argument at a time (§8.2.1 pp. 124–126; code
  `code/revised-remora/bidirectional.rkt:277-429`, rules `app:->*f` and `app:->*a`).
- Solver interface `Γ;Φ ⊢ I ≐ I' ⊣ Γ';Φ'`: extend Γ with solutions and fresh existentials and
  Φ with the minimal equivalence relation on dimensions for one alignment of shape-variable
  boundaries; several alignments mean several outputs (`(shape a b c d e) ≐ (++ s t s)` gives
  three) (Proposition 6.2.1, pp. 79–80).
- Ch. 7: the solver returns Skolem functions, not a model: existentials written in terms of
  universals, plus the dimension equivalence that makes the solution valid (§7.1, p. 102).
  Makanin's algorithm (generalized equations as column-spanning bases, transport of a
  carrier's bases into its dual, Delannoy-number alignments, pruning by an ILP on element
  populations per column) (§7.2.1–7.2.2, pp. 104–111). *Makanin(T)*: element equality
  delegated to a theory T (Presburger here); aliased columns produce dimension equalities; the
  universals are eliminated Presburger-style and the remaining validity query goes to an ILP
  solver as unsatisfiability of the negation; a counterexample rejects that alignment
  (§7.2.3, pp. 111–112). Free monoid from free semigroup by first choosing which sequence
  variables are empty, O(2ⁿ) worst case but few in practice (§7.2, p. 103).
- Mixed prefix (§7.3, pp. 113–114): a universal shape variable becomes a fresh generator, so no
  column boundary can fall inside it and any solution that depends on its internals is ruled
  out; quantifier order is ignored during search and solutions are filtered by whether a
  Skolem function would need a later universal. The price: in ∃* any boolean combination of
  equations is one equation, in (∀∃)* it is not, so shape constraints are restricted to
  conjunctions.
- Costs: Makanin is doubly exponential deterministic time in the worst case, but typical
  rank-polymorphic constraints avoid it: frames never overlap themselves, and with one
  variable the algorithm degenerates to peeling generators off the ends (§5.3, pp. 69–70).
  Newer algorithms (Plandowski, Jeż recompression) are faster but need generator equality up
  front, which Presburger generators do not give (pp. 71, 171).
- Ch. 8: elaboration soundness; a corpus of synthetic and APL/J-style samples (stencils,
  matrix product) elaborated by hand-traced derivations; annotations are rare because most
  local functions are used monomorphically (§8.2 pp. 123ff; ch. 12 p. 169). No timings or
  performance measurements are reported.
- Part III: compilation targets surveyed (APL machines, TAIL to Futhark, SISAL/APEX, SAC, TeIL,
  Tensor Comprehensions, XLA/Glow/TVM) (§9.1–9.2, pp. 145–148). Erasure (ch. 10). Explicit
  iteration (§11.1, pp. 159–164): IR forms `map I_f T_c e_f e_a...` (one frame for function
  and all arguments, result cell type kept for empty frames), `rep I_f I_g T e` (replicate
  cells into a larger frame), `s-app` (scalar-frame application), optional `t-map`/`i-map`;
  the translation subtracts each frame from the principal frame with a meta-level monus,
  emits one `rep` per argument and one `map`. Advice: do not erase types before annotating
  frames and shapes (p. 159). After eager erasure the same translation needs runtime
  `%shape-of`, `%monus`, `%longest` (Fig. 11.5, pp. 163–166).
- §11.2 (pp. 165–167): once application no longer iterates, merge the index and term levels
  (Iλ and i-app become ordinary λ and application). Arrays can be a flat buffer of atoms with
  cell-polymorphic functions taking "their shape arguments as products of dimensions"; only
  shape-of and I/O need the full shape. A low-level IR of `manifest` arrays and `view`s
  (index-function composition) makes transpose, rotate, reverse and `rep` free until
  materialization (Mullin's mathematics of arrays).
- Future (§12.1, pp. 170–171): records and dataframes via rank-polymorphic field projection;
  faster word-equation algorithms; a calculus with a more general β to justify fusion instead of
  materialized replication.

**Steal.**
- *Inference only instantiates*: polymorphic definitions are annotated, uses are inferred. This
  is Idris's own discipline (no let-generalization of dependent types), so the fit is natural.
- *Frames are computed, cells are declared*: in a surface language, the argument's cell
  shape is what the programmer writes (a rank or a cell type), the frame is what the
  elaborator finds.
- *The `map`/`rep` translation* and the advice to annotate frames before erasing: our
  compiler sees checked TT with every index present, which is the best possible moment.
- *Shape variables collapse to products at run time* (§11.2), which is the key to compiling
  rank polymorphism with no fixed rank ([§8.3](#83-the-mlir-side-frames-and-cells-as-indexing-maps)).
- *Views instead of materialized `rep`/transpose*, which MLIR expresses as indexing maps.

**Avoid.**
- Building a word-equation solver. Makanin(T) is a research artifact with doubly exponential
  worst case, an external ILP binary (Inez), and ambiguity resolved by backtracking over
  derivations. Our compiler does not infer types (Idris does), so the solver problem only
  appears if the *Idris* side needs it, and there the restricted forms of [§8.2](#82-the-idris-side-shapes-as-erased-snoc-list-indices) avoid it.
- Run-time `%shape-of`/`%monus`/`%longest` (the eager-erasure path): every frame is static in
  checked TT.
- Arrays of functions as a performance feature: MIMD application is real but rare; remorac
  lowers it by defunctionalization (`map_replicate_ast.ml:195-231`), which this compiler
  already does for closures.

**Limits.** No measured performance anywhere in the Remora line; the compiler (remorac)
stops at a `Map`/`Rep` IR; the inference implementation is a Redex model calling Racket and
an OCaml ILP solver.

### 1.5 The code

Stored: `code/remora/`, `code/revised-remora/`, `code/remorac/`, `code/makanin-algo/`.

**Read.**
- The run-time lifting in the Racket prototype (`code/remora/remora/dynamic/lang/semantics.rkt:27-170`):
  expected ranks per argument (`all` becomes the argument's rank, lines 42-60); principal
  frame by folding `prefix-max` over `shape minus last r` of each argument (62-74);
  cell and frame sizes as products (78-89); and the replication rule: result cell `i` takes
  function cell `i / (P/F_fun)` and argument cell offset `csize * (i / (P/F_arg))` where `P`
  and `F` are frame *sizes* (92-132). Prefix agreement is what makes this a quotient. Empty
  frame: the result shape comes from an annotation, else an error (139-158).
- The explicit model (`code/revised-remora/typing-rules.rkt:299-325`): `type-app` gets each
  argument frame by `drop-suffix` of the cell shape and the principal frame by
  `largest-frame`; both work on `normalize-idx` canonical forms (797-823), and index
  equivalence is syntactic equality of normal forms (line 570 comment).
- The 2014 model computes frames by `frame-contribution` and `largest-frame` over
  "frame-structs" (`code/remora/semantics/dependent-lang.rkt:137-150`, `:298-335`).
- remorac (`code/remorac/src/remora-internal/typechecker.ml`): `idx_equal` compares a Dim as a
  constant plus a multiset of variables and shapes pointwise (181-193); `frame_contribution`
  peels the argument type until it equals the cell type (284-302); `prefix_max` (323-343); the
  `App` case assembles the principal frame (408-435). `map_replicate_ast.ml`: indices become
  term values (129-156; "We can determine how to split an array into mapping pieces given just
  the total number of pieces"), `Rep` per argument and one `Map` per application (255-294), a
  defunctionalized `apply` for arrays of functions (195-231). `design.txt` explains why the
  argument-expansion annotation exists: `Map` treats all arguments alike, so `Rep` must first
  give every argument the application's frame.
- makanin-algo (`code/makanin-algo/solve.rkt:11-50`): `solve-monoid-eqn*/t` returns a stream of
  solutions with the equivalence relation on constants, the interface the dissertation's
  Proposition 6.2.1 needs; `code/revised-remora/makanin-wrapper.rkt` maps the classes back to
  dimension equalities and rejects any class mixing a universal shape variable with anything
  else (its `update-env`).

**Steal.** The quotient formula is the run-time meaning of a broadcast along trailing frame
axes; in MLIR it is simply an indexing map that omits those loop dimensions (no division).
remorac's pass structure (types, then frames, then expansions, then erase, then `Map`/`Rep`)
is the right order. **Avoid.** Racket/Redex and Inez as dependencies; the code is study
material only and has no licence (except remorac, BSD-3).

## 2. Gibbons: APLicative programming with Naperian functors

Stored: `papers/gibbons-2017-naperian/aplicative.pdf`, `aplicative.hs`.

**Key ideas (read).**
- Claim: no custom type system is needed; Haskell's (GADTs, promoted kinds, type families,
  classes) captures the compatibility checks and *generates* the liftings by type-driven code
  inference (abstract, §1.2, pp. 1–4).
- A dimension must be a functor of fixed shape: applicative (`pure` = replicate, `<*>` = zip),
  *Naperian* (representable: `f a ≅ Log f → a`, with `lookup`, `tabulate`, `positions`), so
  transposition `f (g a) → g (f a)` is total; foldable and traversable for reductions and
  scans (§3–4, pp. 8–13). `Log (Vector n) = Fin n`; pairs, perfect trees, binary-indexed block
  vectors are dimensions too (pp. 11–14).
- `Hyper :: [* → *] → * → *` with `Scalar` and `Prism :: Hyper fs (f a) → Hyper (f : fs) a`;
  the type-level list is *innermost first* (pp. 14–16). Reduce on the innermost axis; reach
  other axes by `transposeHyper` (p. 17).
- Alignment: `Alignable fs gs` when `fs` is a prefix of `gs` (instances read as a logic
  program), lifted binary operators align both arguments to `Max fs gs`, a partial type
  family; `IsCompatible` gives a readable error (§6, pp. 17–19). Because lists are
  innermost-first, this aligns *trailing* axes: a 3-vector aligns with the rows of a 2×3
  matrix (`Max '[Three, Two] '[Three]`, p. 18), the NumPy direction, the opposite of J's prefix
  agreement used by Remora.
- Symbolic `ReplR` and `TransT` constructors make replication and transposition O(rank);
  forced only by folds and traversals (§7, pp. 19–22). A flat `Flat fs a` (one `Array Int a`
  with the shape only in the type) and a sparse variant (§8, pp. 22–23).
- "There is no need for any sophisticated solver for size constraints; the existing
  traditional unification algorithm suffices", even with `Add`/`Mult` type families for
  append/concat/group (§9, p. 24). Shapes are data-independent: no `iota` of a computed size,
  no `filter` (§9.1, p. 24).

**Steal.** The Naperian structure is the semantic core of a regular dimension: `Fin n` as
positions, `tabulate`/`lookup` as the two directions, transposition total. In Idris this is
`Vect n` with `Fin n`, already in base, and it is exactly what a `linalg.generic` body sees
(an index per dimension). Shape compatibility by *proof search over a prefix relation* (the
`Alignable` logic program) instead of an equation solver: Idris auto-implicits do this
(checked, [§8.2](#82-the-idris-side-shapes-as-erased-snoc-list-indices)). Symbolic
replication/transposition as views: in MLIR, indexing maps and `linalg.transpose`/`broadcast`
folded into consumers.

**Avoid.** Innermost-first trailing-axis alignment: it is NumPy broadcasting, whose MLIR trait
`Broadcastable` has run-time-dependent meaning for dynamic sizes (undefined behaviour when two
dynamic sizes differ and neither is 1) (read:
`sources/docs/mlir/docs/Traits/Broadcastable.md:22-80`); prefix agreement never consults a
size. Nested `Hyper (Vector ...)` at run time (Gibbons flattens it himself, §8); dictionary
passing for `Shapely`/`Count` (`hreplicate` needs the class to build the result, p. 16): in
Idris the shape must then be a runtime argument, which [§8.2](#82-the-idris-side-shapes-as-erased-snoc-list-indices) avoids by reading sizes off the arrays.

**Limits.** Only unary and binary scalar operators are lifted; reranking is by explicit
transposition; no arrays of functions; no data-dependent shapes; no performance claims (p. 4).

## 3. Xi and Pfenning: eliminating array bound checking

Stored: `papers/xi-1998-dml-bounds/pldi98dml.pdf`.

**Key ideas (read).**
- A conservative extension of ML: indices are a separate language (linear integer and boolean
  expressions with a phase distinction from terms), singleton types `int(n)` connect run-time
  integers to indices, Π for universal and Σ for existential indices; an unindexed `int array`
  means `Σn. int array(n)`, the boundary between annotated and unannotated code (§1, §2.1–2.4,
  pp. 1–3).
- Bidirectional elaboration generates constraints with ∀, ∃, ∧ and implication from pattern
  matches; existentials are eliminated *before* the solver (they always could be in the
  examples, with no theory of why); linear constraints are negated and refuted by Fourier
  elimination with an integer tightening step; non-linear constraints are rejected (§3.1–3.2,
  pp. 4–5).
- `filter` returns `[n:nat | n <= m] 'a list(n)`; KMP keeps checks where invariants are too deep
  (`subCK`) (§2.4, appendix A).
- Measured (Tables 1–3, pp. 6–7): constraints solved in 0.01–1.37 s per program; annotations
  2–16 per program; with checks removed, run time drops 12% to 79% (bcopy 79% on MLWorks,
  matrix multiplication 45% on SML/NJ), eliminating 10⁶–10⁸ checks per run.

**Steal.** Singletons as the bridge between run-time sizes and indices: in Idris, a size used
at run time is an ω-quantity `(n : Nat)` (or the array's own stored size) whose value the type
mentions; `Fin n` indices make an access provably in bounds, so the frontend need never emit a
check for it (this compiler's `idr-in-bounds` proves checks after the fact; a `Fin`-indexed
`index` makes the check never exist). Existential elimination before solving. Checks kept
explicit where proofs are too deep (DML's `subCK`, Futhark's coercions).

**Avoid.** Element-indexing as the main programming model (Remora's critique: whole-array
operations make bounds irrelevant, `slepak-2019-semantics/intro.tex:119-127`); a bespoke
Fourier–Motzkin solver in the compiler.

**Limits.** Rank-1 arrays and lists; no shapes; an incomplete solver; 1998 hardware numbers.

## 4. Trojahner and Grelck: Qube

Stored: `papers/trojahner-2009-qube/paper.pdf` (personal-use copy; see its README).

**Key ideas (read).**
- Arrays are `[|data|shape|]` with the row-major linear index formula; only arrays are values,
  and elements ("quarks") may be integers, functions, index functions, tuples of arrays and
  dependent pairs (§2–3, pp. 644–650).
- Index language: sort `idx` and sort family `idxvec(i)`; vector terms built from scalars, by
  element-wise linear operations, `vec(l,i)`, `++`, `take`, `drop`; subset sorts `{idx in a..b}`
  and `{idxvec(l) in v..w}` (§3.1, p. 647). Array type `[Q|i]`; singletons `num(i)` and
  `numvec(i)`; `⊥Q` as the element type of empty arrays, a subtype of every element type
  (§3.2, p. 648).
- Shape-generic programming by with-loops `gen x < shp of cellshape with e` and a
  lexicographic `loop` for reductions; `map`, `cpxmul` on `s ++ [2]`, generalized selection
  `gsel`, `iota` with dependent pairs, `msel`, and an inner product `ip` whose
  matrix/vector/scalar products are partial applications to ranks (§4, pp. 651–653).
- Constraint resolution (§6, pp. 660–662): scalar judgments are linear arithmetic checked by
  SMT (refute the negation); vector judgments become formulas in the *array property fragment*
  (∀ i. guard ⇒ value constraint on `a[i]`), decidable by instantiating the quantifier at
  finitely many indices; `take`/`drop`/`++` cannot be expressed there (they relate different
  indices), so a preprocessing step splits vector variables at the lengths the constraints
  imply and splits concatenations; when the lengths do not determine a split (e.g. `y ++ v`
  against `s1 ++ s2` with incomparable lengths) the program is rejected. Authors report never
  rejecting a valid program this way (p. 662) and propose indexing vector sorts by segment
  lengths to make splitting syntactic.
- Counterexamples: a rejected program comes with concrete index values from the SMT model
  (§8, p. 663).

**Steal.** The idea that shape vectors are vectors of symbolic length whose structure
(concatenation points) is part of the sort: this is the same canonical form as Remora's, and
the "segment" sort they propose is what makes splitting syntactic, i.e. the components of a
canonical shape ([§8.3](#83-the-mlir-side-frames-and-cells-as-indexing-maps)). The with-loop is
`linalg.generic`/`tensor.generate` already. `⊥` element type for empty arrays (Idris: an empty
array literal needs its element type from context, as Remora requires).

**Avoid.** Explicit element indexing as the core loop body (no lifting); bounds on every index
through range types; monomorphic element types (noted by Henriksen §7 and Bailly §6).

**Limits.** A calculus; no polymorphism, no recursion in the core; the compiler is announced,
not measured.

## 5. Futhark size types

Stored: `papers/henriksen-2021-size-types/paper.pdf`, `papers/bailly-2023-size-dependent/paper.pdf`.

**Key ideas, 2021 (read).**
- Sizes in types are variables or constants only; existential return types `∃x.μ`; `let`
  opens existentials implicitly and closes them in the result (t-let), or binds them as `int`
  variables explicitly (t-let-sz); size application `e d`; `iota d : [d]int` when `d` is a
  size, `∃x.[x]int` otherwise; a dynamic coercion `e ⊲ τ` changes sizes only, checked at run
  time (§2, Figs. 1–3). Soundness for terminating programs (§3).
- Regularity is preserved by forbidding instantiation of a type variable with a type that
  mentions a size not in scope (t-inst admits only basic types), so `map (λx. iota x) y` and
  `map (λx. filter f x) y` are ill-typed (§4, Figs. 8–9). Size-lifted type parameters `'~a`
  admit existential results in negative position only, never as array elements (§5).
- In Futhark: non-trivial size expressions are let-bound to names (ANF), Hindley–Milner with
  size variables unified like type variables, implicit size parameters compiled to explicit
  arguments filled from the argument types at each call (§5).
- Experience (§6): the 12,000-line benchmark suite (44 programs from Rodinia, FinPar, Parboil,
  Accelerate and others) needed 66 dynamic coercions, mostly in input-packing code;
  idioms changed to `tabulate_2d` and `indices` instead of `iota (f x)` inside `map` and
  `zip xs (iota (length xs))`; students used it without type-theory background.
- No rank polymorphism by design: arrays of arrays fit ML-style polymorphism (§7). Empty arrays
  are excluded from the formalism (§8).

**Key ideas, 2023 (read).**
- Sizes may be arbitrary `int` expressions; size equality is purely syntactic; size
  polymorphism with implicit arguments (`∀[n]`), instantiated by unification on expressions
  (abstract; §2; §4.2 p. 36). Syntactic on purpose: with `tricky [n][m] = λ(x : [n+m]int).(n,m)`,
  `tricky (iota (1+2))` and `tricky (iota (2+1))` differ, so arithmetic normalization would
  let the inference algorithm's arbitrary choices change results (p. 36).
- *Witnesses*: a size is witnessed by a type if it appears directly as an array size; only
  witnessed existentials are allowed, so their values can be read off the array (`wit`, §2.1,
  p. 31). Subtyping `t-relax` replaces any size expression by a fresh existential (Fig. 3).
- Causality: a fixed right-to-left evaluation order decides when sizes are available; programs
  that need a size before its existential is bound are rejected (§4.1).
- Instantiation can duplicate computation of size expressions; ANF fixes it (§4.2.1). Negative
  sub-expressions in sizes (`unflatten : [n·m] → [n][m]`, `snd : [2+n] → int`) break safety
  without refinements `n ≥ 0` (§4.2.2, p. 37).
- Equality proofs as an abstract `eq [n][m]` module with axioms and a coercion (Fig. 8, §5.1);
  at run time each dimension is one 64-bit integer, no other overhead (§5.2, p. 37).
- Motivation explicitly against Idris's `(p : Nat ** Vect p elem)`: `length (filter p xs)` is
  ill-typed until the pair is unpacked (§1, pp. 29–30).

**Steal.** Automatic existential bookkeeping and witnesses: a data-dependent size need not be a
separate run-time value or a dependent pair the programmer unpacks; it is the array's own
dimension. In MLIR it is literally `tensor.dim` of a `?` dimension. The regularity rule (no
existentially sized element types inside an array) as the condition under which an array of
results is a tensor and not an array of boxes. Explicit, named dynamic coercions as the escape
hatch (here: an explicit `unsupported` or a checked coercion, never a silent one). One integer
per dimension at run time.

**Avoid.** Syntactic size equality as the only equality (programmers hit `n+m ≠ m+n`; Bailly
§7 lists it as future work). Futhark's `tricky` hazard does not arise in Idris for erased
sizes (quantity 0 cannot change behaviour), only for ω sizes. The absence of rank polymorphism.

**Limits.** No rank polymorphism; formalisms exclude empty arrays and type polymorphism.

## 6. Type-level Nat solvers

Stored: `papers/diatchki-2015-smt/` (TeX), `code/type-nat-solver/`, `code/ghc-typelits-natnormalise/`.

**Diatchki (read).**
- A GHC type-checker plugin called after the solver reaches an inert state (one of three
  designs considered; chosen to *extend*, not replace, GHC's solver) (`paper.tex:408-463`).
- Inputs: given, derived and wanted constraints; outputs: solved wanteds, detected
  inconsistency, and *improvements*: new given or derived equalities for the rest of GHC
  (`paper.tex:510-575`). Theory: `Nat` with `+`, constant `*`, `<=?` (`paper.tex:581-630`).
- Import: terms outside the theory are named by fresh variables, which generalizes the
  constraint and is sound for refutation (`paper.tex:632-703`); naturals are integers plus
  non-negativity assertions (`paper.tex:695-703`).
- Consistency by satisfiability; unsat-core minimization by an O(n²) push/pop search when the
  solver lacks cores (`paper.tex:745-854`). Improvement: to a constant (get a model, prove
  `x ≠ v` unsat), to a variable (pairs equal in the model), to a linear relation `y = A x + B`
  from two models, validated by the solver (`paper.tex:856-1029`). Solving: prove each wanted
  under the givens (`paper.tex:1031-1080`). No evidence (proof terms) produced
  (`paper.tex:1065-1080`). Proof of concept, CVC4 over SMT-LIB, not measured
  (`paper.tex:1082-1137`).
- The plugin loop is Nelson–Oppen: purify by naming foreign terms, check each theory, exchange
  equalities between variables; disjunctions would need search, which GHC lacks
  (`paper.tex:1242-1345`).

**natnormalise (read).**
- Normal form "sort-of sum of products" for `+ - * ^` over `Nat`, subtraction as `+ (-1)*`,
  exponents flattened; equality = syntactic equality of normal forms
  (`code/ghc-typelits-natnormalise/src/GHC/TypeLits/Normalise/SOP.hs:1-77`).
- Unification results `Win`/`Lose`/`Draw subst` with rules such as `(a + c) ~ (b + c) ⟹ a := b`,
  `(2 + a) ~ 5 ⟹ a := 3`, `(i*a) ~ j ⟹ a := j/i` when divisible
  (`Unify.hs:410-485`); term-by-term matching only when it yields a single unifier
  (`Unify.hs:620-646`).
- Natural-number safety: `isNatural`/`canBeNatural` guard subtraction; the opt-in
  `allow-negated-numbers` is unsound and documented with a `Fin 0` counterexample
  (`src/GHC/TypeLits/Normalise.hs:1-80`).

**Steal.** For Idris, where the type checker is fixed (third_party is unmodified), the analogue
of a plugin is *library-side*: a normal form for `Dim` (constant + coefficients, natnormalise's
SOP restricted to Presburger as Remora does) and for `Shape` (Remora's flattened
concatenation), with a reflection tactic or a decision function that returns an equality proof
when normal forms agree; the improvement idea (derive the equality that lets unification
instantiate a metavariable) is the useful part, not the SMT round trip. Nelson–Oppen as the
architecture if the index theories ever grow.

**Avoid.** An external SMT process in the type checker (and in this repository: no oracle, no
foreign tools at compile time beyond the toolchain). Truncating subtraction or "allow negated
numbers": sizes are naturals and differences need a `≤` proof.

**Limits.** Neither is measured. Both are GHC-specific in mechanism.

## 7. Decidability, in one table

| Problem | Status | Source |
| --- | --- | --- |
| Equality of two Dims (Presburger terms, no quantifiers) | linear time by normal form (constant + coefficients) | `slepak-2019-semantics/formalism.tex:464-485` |
| Equality / prefix / suffix of two Shapes, all variables universal (type checking) | linear time by flattening `++` (canonical form), then Dim equality componentwise | `formalism.tex:486-524`; `slepak-2018-constraint` §3, §5 |
| Principal frame given the frames | linear search in the prefix lattice; join is one of the frames | `formalism.tex:530-542`; `slepak-2018-constraint` §3 |
| Existential word equations (free monoid, finite alphabet) | decidable (Makanin); NP-hard; PSPACE (Plandowski); Jeż: nondeterministic linear space | Dissertation §5.3 pp. 69–71; `slepak-2018-constraint` §5–6 |
| ∀*∃* or ∃*∀* word equations | undecidable; positive ∀∃³ already (Durnev) | Dissertation §5.3 pp. 68–69; `slepak-2018-constraint` §5 |
| Remora inference constraints (conjunctions, universals as generators, Presburger elements) | decided by Makanin(T) + quantifier filtering; disjunctions excluded | Dissertation §7.2.3–7.3 pp. 111–114 |
| Full theory of sequences | undecidable (Durnev, Marchenkov) | Dissertation §5.3 p. 68 |
| Product of dimensions in indices | kept out (Peano arithmetic undecidable); `ravel` boxes | `formalism.tex:320-330` |
| DML linear constraints after ∃-elimination | Presburger (decidable); Fourier elimination used, sound but incomplete | `pldi98dml.pdf` §3.1–3.2 |
| Qube vector constraints | array property fragment decidable; with `take`/`drop`/`++` undecidable in general, handled by splitting or rejection | `trojahner-2009-qube/paper.pdf` §6 |
| Futhark size equality | syntactic (unification); everything else is a dynamic coercion | `bailly-2023-size-dependent/paper.pdf` §4.2 |
| GHC Nat with `+`, constant `*`, `<=?` | linear arithmetic via SMT (Diatchki); non-linear terms named away | `diatchki-2015-smt/paper.tex:581-703` |
| Rank-polymorphic types without ∀ | no principal types (`app+`) | Dissertation ch. 6 pp. 73–74 |

## 8. What this means for 0004: rank with no ceiling

0004 §3.7 today (read: `proposals/0004-typed-apl/README.md:268-298`): rank-r arrays when the rank is a
literal after monomorphisation and the elements are words; otherwise "the library's definition
compiles as written: a rank erased at quantity 0 is not a constant the compiler may assume".
The prior art says the second branch need not be a fallback. Below, each step is marked.

### 8.1 What the type must carry, and what the run time must carry

- The index structure (which dimensions are equal, which shape is a prefix of which) is the
  type's; the dimension *values* are the array's (Futhark witnesses, Bailly §2.1; Remora
  erasure keeps only shapes, `type_erasure.tex:68-123`; remorac keeps only sizes,
  `map_replicate_ast.ml:129-156`). This matches AGENTS.md's "erased does not mean constant":
  an erased `Shape` index is never read as a value; its *form* is. (conjecture, from the cited
  reads)
- So an array is a backing plus its run-time sizes (one integer per dimension, Bailly §5.2),
  and in MLIR a `tensor<?x...x?xE>` whose rank is the number of components of the index's
  canonical form ([§8.3](#83-the-mlir-side-frames-and-cells-as-indexing-maps)), whose sizes
  are `tensor.dim`, and whose equalities between dynamic sizes are SSA facts the
  `ValueBoundsOpInterface` constraint set can be asked about (read:
  `sources/code/mlir/include/mlir/Interfaces/ValueBoundsOpInterface.td:14-60`). (conjecture)

### 8.2 The Idris side: shapes as erased snoc-list indices

- **Outer-first snoc lists make frames inferable.** Idris's `SnocList.(++)` recurses on its
  *right* argument (read: repository `third_party/Idris2/libs/prelude/Prelude/Types.idr:424-427`).
  With `Arr : SnocList Nat -> Type -> Type` and a lifted function
  `Arr (f ++ [<n]) a -> Arr f b`, applying it to `Arr [<3,4,5] Int` reduces the argument type
  to `f :< n` and unification solves `f = [<3,4]` from the argument alone; the same with cons
  lists fails (`Can't solve constraint between: [3, 4, 5] and ?s ++ [?n]`). (checked:
  `idris-probe/Probe4.idr` passes, `Probe5.idr` fails) This is Remora's "cell type declared,
  frame found" (`slepak-2018-constraint` §3) done by Idris's own unifier, in row-major order.
- **Cell-shape variables need instantiation.** With the cell a shape variable `c`,
  `f ++ c = [<3,4,5]` is ambiguous (`Probe3.idr` fails); giving `{c = [<4,5]}` works
  (`Probe.idr`, `test2`). (checked) This is exactly Remora's scalar-frame convention for
  cell-polymorphic primitives and its "inference only instantiates" (§1.3, §1.4): the library
  states the cell, or the call site does.
- **The principal frame by proof search, read off the evidence.** An `Agree f1 f2` relation
  (one is a prefix of the other, constructors `AL`/`AR` over a `Prefix` relation) found by
  `auto` search, and the result frame `principal ok` computed from the evidence rather than
  from lengths, types matrix + vector (`[<2,3]` and `[<2]`), infers the result frame with no
  expected type, rejects `[<2,3]` with `[<3]`, and handles a symbolic prefix
  (`Arr (f :< 3)` with `Arr f`). (checked: `Probe9.idr` `mv`, `mv'`, `poly`; `Probe7.idr`
  rejects). Computing the join from lengths instead gets stuck on `length f >= length f`
  (`Probe8.idr`), the universal-fragment problem in miniature. This is Gibbons's `Alignable`
  logic program (§6, p. 18) with J's prefix direction.
- **Opaque extensions need a lemma.** When the extension is itself a shape variable
  (`Arr (f ++ g)` with `Arr f`), search does not find `Prefix f (f ++ g)` even with a `%hint`;
  passing the lemma `AR (prefixAppend g)` explicitly works (`Probe10.idr` fails,
  `Probe11.idr` passes). Associativity of `++` on open terms is not definitional
  (`Can't solve constraint between: a ++ b and a`, `ProbeAssoc.idr`). (checked) These are
  the cases Remora's canonical form decides; in Idris they need a tactic (elaborator reflection
  in the library, which normalizes both sides to Remora's flattened form and emits the
  `appendAssociative`-style proof) or a small set of library lemmas. Upstream Idris is not
  changed. (conjecture)
- **Dims.** Keep Remora's choice: `+` only, no products in indices; a product appears only as a
  run-time size (`ravel` returns a Σ, `reshape` takes a target shape and a checked or proved
  size equality). Commutativity needs `plusCommutative` (base) or the same tactic with
  natnormalise's normal form restricted to linear terms. (conjecture, from
  `formalism.tex:320-330` and `SOP.hs`)
- **Data-dependent shapes.** Σ, as Remora and DML do, but with Futhark's automation where Idris
  allows it: a `filter` returning `(m ** Arr [<m] a)` whose `m` is the array's own dimension
  at run time (witnessed, so never stored twice); rank-specialized variants (`iota1`) so a
  vector result is not a fully hidden shape. Arrays of Σ (ragged) are a distinct type and stay
  boxed. (conjecture)
- **Quantities.** Shape indices at quantity 0 in the array type; sizes the program computes
  with at ω (singletons, DML's `int(n)`); index binders that the erased program still needs
  (Remora's `Iλ`/`unbox`, `type_erasure.tex:111-115`) are exactly the ω ones. QTT already
  records this, so no separate analysis is needed. (conjecture)

### 8.3 The MLIR side: frames and cells as indexing maps

- **A lifted application is one structured op.** The principal frame's components are the
  parallel loop dimensions; each argument's indexing map is the identity on the first |F_i|
  frame components followed by its cell dimensions; an argument whose frame is a proper prefix
  simply omits the trailing frame dimensions, which is replication without materializing it
  (Remora's run-time quotient rule, `semantics.rkt:92-132`; Gibbons's `ReplR`, §7). In MLIR
  this is `linalg.generic` with projected-permutation indexing maps, or `linalg.broadcast`
  (read: `sources/code/mlir/include/mlir/Dialect/Linalg/IR/LinalgStructuredOps.td:55`,
  `:474-497`). Function-position frames (arrays of functions) are an extra operand indexed the
  same way, then defunctionalized (`map_replicate_ast.ml:195-231`). (conjecture)
- **Cells of rank > 0.** If the cell function lowers to a structured op, lifting prepends the
  frame's parallel dimensions to its iteration space and to every indexing map (batching); a
  matrix product lifted over a frame is a batched contraction, still one generic. If the cell
  body is not structured, the frame becomes an `scf.forall` over the frame with
  `tensor.extract_slice` cells and `tensor.parallel_insert_slice` results, which upstream
  tiling and fusion already handle. (conjecture)
- **No rank ceiling: one loop per canonical component.** A canonical shape is a sequence of
  single Dims and shape variables; a universal shape variable is never split by any valid
  typing (no column boundary inside a universal, Dissertation §7.3 p. 113; `makanin-wrapper.rkt`
  rejects classes that mix one). So inside a definition polymorphic in rank, lower each shape
  variable to *one* dimension of size `product` of its run-time sizes, as Dissertation §11.2
  (pp. 165–166) and remorac (`map_replicate_ast.ml:129-156`) already do for the whole array.
  The lowered op's rank is the number of components, a compile-time constant even when the
  variables' ranks are unknown; the caller, which knows its own components, reshapes at the
  call boundary with `tensor.collapse_shape`/`expand_shape`, whose reassociation is then static
  (read: `sources/code/mlir/include/mlir/Dialect/Tensor/IR/TensorOps.td:1091`, `:1176-1195`).
  No unranked tensor is needed, and `linalg` results are ranked (read:
  `LinalgStructuredOps.td:146`, `linalg.generic` results are `Variadic<AnyRankedTensor>`). A monomorphic call site that
  specializes the definition gets the full rank back and the uncollapsed loops. (conjecture)
  Example: `mean : Arr (f ++ [<n]) Double -> Arr f Double` with `f` unknown lowers to a
  generic on `tensor<?x?xf64>` (frame collapsed, `n`), parallel then reduction; called on
  `tensor<3x4x5xf64>` it is preceded by `collapse_shape [[0,1],[2]]` and followed by
  `expand_shape` back to `3x4`.
- **Empty frames.** The result's `tensor.empty` takes the frame sizes and the cell sizes from
  the output type's index instantiated at the call; no probe of the function is ever needed
  (ESOP §3.2, §4.3). A lifted function whose output cell shape is existential produces an array
  of Σ (boxes), not a tensor (Futhark's t-inst regularity rule, Henriksen §4). (conjecture)
- **What not to use.** MLIR's `Broadcastable` trait and TOSA/NumPy-style implicit broadcasting:
  trailing-axis alignment with size-1 stretching decided at run time
  (`Broadcastable.md:22-80`), the semantics prefix agreement exists to avoid. (read + conjecture)
- **What this gives 0004.** The `tabulate`/`index`/`map`/`zipWith` surface of §3.7 becomes the
  cell-level vocabulary; `lift` (frame found by unification, principal frame by evidence)
  becomes the one lifting combinator the frontend recognizes; the rank-r restriction to
  literal ranks becomes "one loop per canonical component", with specialization when the rank
  is a literal and collapsed components when it is not. Fusion, tiling, vectorization and
  bufferization stay upstream's. (conjecture)

## 9. Not stored, and open questions

- Not stored: Diatchki's published ACM PDF (closed; the author's TeX from the plugin
  repository is stored instead). Slepak's thesis TeX (not located). Jay's FISh and shapely
  types, Thatte 1991, Keller et al. Repa, Elsman–Dybdal TAIL, Mullin's mathematics of arrays,
  Makanin 1977, Plandowski 2004, Jeż recompression, Durnev 1995, Karhumäki et al. 2000, Bradley–
  Manna–Sipma array property fragment, Dunfield–Krishnaswami bidirectional typing, Gundry's
  units-of-measure plugin, the Thoralf plugin (Haskell 2018): cited above through the stored
  sources, not fetched (outside this cluster's list).
- Open: whether Idris's `auto` search can be made to use a `Prefix f (f ++ g)` hint (it did not
  here); whether an elaborator-reflection tactic deciding Remora's universal fragment is fast
  enough on real code; how Σ-typed (ragged) arrays should lower (offset arrays plus one flat
  backing, or `sparse_tensor` encodings); whether batching a structured cell function over a
  frame should be a frontend rewrite or a transform-dialect step.
