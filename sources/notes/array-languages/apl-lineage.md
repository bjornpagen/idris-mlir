# APL lineage: what an Idris-hosted typed array language should take from it

Cluster `apl-lineage`, read 2026-10-09. Every claim below is cited to a file stored under
`sources/` (staged at `scratchpad/selfhost/apl/stage/sources/`, same relative layout) by path
and line, or by section anchor for the HTML editions. Line numbers are the stored file's own
(`grep -n`); for HTML they point at the raw markup. Where a source could not be stored, that is
said and its claims are cited to the unstored copy's page and marked so.

Sources read:

| Path under `sources/` | What it is |
| --- | --- |
| `papers/iverson-1962-programming-language/APL1.htm` | Iverson, *A Programming Language* (1962): preface, Ch. 1, Ch. 3 |
| `papers/iverson-1980-notation-tool-of-thought/tot1.htm` | Iverson, Turing lecture (CACM 1980) |
| `papers/bernecky-1980-operators-enclosed-arrays/opea1.htm` | Bernecky & Iverson, *Operators and Enclosed Arrays* (1980) |
| `papers/bernecky-1983-satn45-rank-operator/satn45a.htm` | SATN-45, the rank operator as shipped in SHARP APL (1983) |
| `papers/iverson-1987-dictionary-of-apl/APLDictionary1.htm` | Iverson, *A Dictionary of APL* (1987) |
| `papers/hui-1995-rank-uniformity/rank1.htm` | Hui, *Rank and Uniformity* (APL95) |
| `papers/hui-2009-rank-operator/*.htm` | Hui, *Rank Operator: An Idea Worth Borrowing* (Dyalog '09 slides) |
| `docs/j/help/dictionary/*.htm` | Hui & Iverson, *J Dictionary* (web edition) |
| `docs/bqn/**` | BQN documentation at `5abbab96` |
| `papers/hsu-2019-data-parallel-compiler/hsu-dissertation.pdf.txt` | Hsu, dissertation (repository text; the PDF is over the cap and not stored) |
| `code/co-dfns/**` | Co-dfns compiler at `07363409` |

Not stored (see the catalogue): Hui & Kromberg, *APL Since 1978* (HOPL IV 2020; ACM gold OA,
403 to scripted fetches); Bernecky, *An introduction to function rank* (APL88; closed).

---

## 0. The thesis in one page

The APL line converged, over 1962–1995, on one array model and one generalisation mechanism,
and the mechanism is exactly what a dependently typed host can make static:

1. **An array is a shape and a row-major list of atoms; a k-cell is the subarray of the last k
   axes; the remaining axes are the frame.** Dictionary of APL
   (`papers/iverson-1987-dictionary-of-apl/APLDictionary1.htm`, II.A "Arrays", line 426 ff.),
   SATN-45 (`papers/bernecky-1983-satn45-rank-operator/satn45a.htm`, lines 149–189), J
   (`docs/j/help/dictionary/dicta.htm`, line 66), BQN (`docs/bqn/doc/array.md`, "Cells",
   lines 110–120).
2. **Every function is defined on cells of a fixed rank and lifted over any frame by one rule:**
   apply to each cell, then assemble the frame of results (`satn45a.htm`, lines 172–189;
   `APLDictionary1.htm`, `<a name="assembly">` line 705; `docs/j/help/dictionary/dictb.htm`,
   lines 32–84). "The definition of any verb need specify only its behaviour on cells of the
   intrinsic ranks, and the extension to arguments of higher rank occurs systematically"
   (`dictb.htm`, line 84 ff.).
3. **The rank operator reassigns those cell ranks** (`f⍤r`, `u"r`, `𝔽⎉r`), so one
   generalisation mechanism replaces axis brackets, outer products, "each" over rows, and
   batched linear algebra (`satn45a.htm` examples; Hui 2009 `app1.htm`, `app2.htm`;
   `docs/bqn/doc/rank.md`, lines 171–183).
4. **Uniform functions** (result shape a function of argument shapes only) **have shape
   calculators, and the calculators compose** (`papers/hui-1995-rank-uniformity/rank1.htm`,
   §2 line 390 ff., Appendix B line 994). Hui used this only to pick faster code paths at run
   time; an Idris type *is* the shape calculator, checked statically.
5. Every hard case the dynamic languages carry (agreement errors, the zero frame, fill
   elements, permissive assembly of ragged results) is a case where the shape calculator was
   not known before running. With shapes in types, they become either compile-time errors or
   facts the compiler knows; nothing about rank needs a ceiling.

The lowering consequence: a rank-lifted function is a `linalg.generic` whose frame axes are
`parallel` iterators and whose cell axes are the function's own (parallel or reduction)
iterators, with the indexing maps saying which argument axes each cell reads
(`docs/mlir/docs/Dialects/Linalg/_index.md`, lines 98–99, 178–185, 254–275). Hui's "integrated
rank support" (never build the cells; stride through the argument) is precisely what an
indexing map is (`rank1.htm`, §1 line 278 ff.).

---

## 1. Iverson, *A Programming Language* (1962)

`papers/iverson-1962-programming-language/APL1.htm` (preface, Ch. 1 §1.1–1.23, Ch. 3).

**Key ideas.**
- The book's thesis: one notation, presented whole, then applied to microprogramming, search,
  sorting and logic to show its universality (preface, the opening paragraphs of `APL1.htm`).
- Operators on structured operands: reduction (§1.8, line 1495), and the *generalized matrix
  product* `f.g` for any pair of functions (§1.11, line 2266). These are the seed of APL's
  "operators produce families of functions".
- **Levels of structure (§1.20, line 3966).** Iverson restricts the book's notation to two
  levels (vector, matrix) and says how to remove the limit: index an operator by the axis it
  applies to (`/j`) and treat "tensor" as the general array of arbitrary rank. The 1962
  language is rank ≤ 2 by notational accident, and the author already names the
  generalisation.
- **Trees as flat arrays (§1.23, line 4526 ff.).** A tree is a *node vector* plus a *degree
  vector*; in two particular orders (the "full left list" and "full right list", line 6957,
  i.e. preorder and level order) the degree and node vectors alone determine the tree
  (degree vector at line 4912; full left list matrix at 8989). Leaf count is `+/(d=0)`, root
  count `ν(d) – +/d` (text after line 4912). This is the earliest form of the representation
  Hsu builds his compiler on (§10 below); Hsu cites the book for it (dissertation PDF printed
  p. 60, not stored).

**Steal.** The flat, ordered encoding of trees (node vector plus one small integer structure
vector) as the representation for nested data that must be compiled densely.

**Avoid.** The book's notation itself (superscripts, subscripts, row/column operator pairs
such as `/` and `//`, §1.20): it is exactly the rank-2 specialisation Iverson himself flags.

**Limits.** Only the preface, Ch. 1 and Ch. 3 are transcribed online; chapters 2 and 4–7 are
not in the library.

---

## 2. Iverson, *Notation as a Tool of Thought* (1979 Turing lecture, CACM 1980)

`papers/iverson-1980-notation-tool-of-thought/tot1.htm`.

**Key ideas.**
- Five properties of a good notation: ease of expressing constructs, suggestivity, subordination
  of detail, economy, amenability to formal proof (§1, line 158 ff.).
- **Subordination of detail by arrays, names and operators** (§1.3, line 437 ff.): "functions
  defined on vectors are extended systematically to arrays of higher rank"; an operator applies
  to functions to produce functions (`+/`, `×/`, `∧/`); the inner product `f.g` (line 640 ff.)
  and outer product `∘.f`; `p⌊.+q` is a shortest-path step, `p×.*q` builds a number from its
  prime exponents. Dualities `f/v ←→ ig g/ f v` (`×/v ←→ *+/⍟v`; De Morgan) hold for reduce,
  scan and inner product alike (§1.2, line 302 ff.; §4.1, line 2353).
- **Economy** (§1.4, line 709 ff.): a few primitives and three operators cover the paper;
  ambivalence (one symbol, monadic and dyadic meanings) economises symbols; *no precedence*,
  every function takes as right argument the whole expression to its right (line 804).
- **Proof** (§1.5, line 840 ff.; §4): proof by exhaustion via outer products over a finite
  domain (`∧/,(d∘.∧d)=~(~d)∘.∨(~d)`), proof by identity chains annotated with the law used,
  induction over recursive definitions; associativity of inner product is proved formally (§4).
- Partitioning identities (§4.2, line 2390): `f/v ←→ (f/k↑v) f (f/k↓v)` for associative `f`,
  any compression split for associative-commutative `f`, identity element for the empty
  case; extended to matrices for `+.×` (identities D.1, D.2).

**Steal.**
- The partitioning identities are the algebra that licenses tiling and parallel reduction:
  associativity gives `k↑`/`k↓` splitting (tiles), commutativity gives arbitrary partitions
  (shards), and the identity element gives the empty tile. A typed array language should carry
  "associative", "commutative" and "has identity" as facts about the operand of reduce and scan
  (an Idris interface with laws, e.g. a monoid), because these are exactly the facts a
  `linalg` reduction iterator and a parallel scan need.
- Inner and outer product as *operators over arbitrary function pairs*, not just `+.×`: `∨.∧`
  (reachability), `⌊.+` (shortest path), `×.*`. Each lowers to the same `linalg.generic` shape
  as a matrix product with a different combiner and reducer.
- Exhaustive proof over small finite domains with outer products: a cheap test oracle for
  algebraic properties of operands (a test checks the law, not an exact op sequence).

**Avoid.** Right-to-left evaluation without precedence and ambivalent symbols are syntax
choices for an interactive notation; an Idris-hosted language inherits Idris's syntax and
should take the semantics (operators, rank) and leave the glyphs.

**Limits.** Written for 1979 APL: first-axis/last-axis conventions and axis brackets (`⌽[1]m`,
`+/[2]m`, §1.3) predate the rank operator; the lecture's §5.3 lists extensions it wanted but
did not have (line 3385).

---

## 3. Bernecky & Iverson, *Operators and Enclosed Arrays* (1980)

`papers/bernecky-1980-operators-enclosed-arrays/opea1.htm`.

**Key ideas.**
- **Enclose / disclose** (§A, line 78 ff.): `<a` is a rank-0 encoding of any array; `><a` is
  `a`; disclose of an array of enclosures assembles them, and requires the disclosed elements to
  share a shape (otherwise an error). Matching (`≡`) compares shape then elements recursively.
- **On (`⍤`)** (§B.1, line 157 ff.): `f⍤j` applies `f` on the subarrays given by axes `j`;
  "the result can be considered as a frame of shape s which contains subarrays each of the
  (necessarily common) shape sir"; result shape `s,sir`. Dyadic frames must agree, "however, if
  one is empty, then the corresponding argument is used with each subarray of the other
  argument" — explicitly "a useful generalization of the notion of scalar extension". The paper
  introduces the term *cells* and *cell identities* (line 233).
- **With (`¨`)**, the dual (§B.2, line 255 ff.): `f¨g b →← gi f g b` and
  `a f¨g b →← gi (g a) f g b`, with *formal inverses* assumed where only a one-sided inverse
  exists (square/square-root, enclose/disclose; line 278). Example: the length of a vector is
  `+/¨(*¨2)` (line 299). This is the operator J calls `&.` and BQN calls `⌾` (Under).
- **Along (`⍥`)** (§B.3, line 319 ff.): split along one axis, then reduce/scan/permute the
  resulting collection; fixes where the new axis goes for scan.
- **Representations** (§C.1, line 518 ff.): enclose gives any value (a word, a polynomial
  coefficient vector, a rotation matrix) a scalar representation, so array operators apply to
  collections of such values; the derivation `p¨>/v` multiplies a family of polynomials.

**Steal.** The dual/Under operator as the general "work in another representation" combinator,
with its two defining identities; and the "frame of common-shape results" assembly rule, stated
before the rank operator existed.

**Avoid.** Formal inverses assumed where none exists: a typed language should require an
actual inverse (or, as BQN does, a structural selection: §9) as part of the operand's type.

**Limits.** Axis-list syntax (`f⍤(<1 3)`) names arbitrary axes, not leading/trailing cells;
SATN-45 replaced it by integer ranks (§4).

---

## 4. SATN-45, *Language Extensions of May 1983* (the rank operator ships)

`papers/bernecky-1983-satn45-rank-operator/satn45a.htm` (Bernecky, Iverson, McDonnell,
Metzger, Schueler).

**Key ideas (the definition, lines 46–201).**
- `f⍤r`: a non-negative `r` is the number of final axes `f` applies to; a negative `r` the
  number of leading axes excluded (line 80 ff.). Magnitudes beyond the argument's rank clamp.
  A general argument is a 3-vector (monadic, left, right ranks), shorter ones extended by
  `⌽3⍴⌽r` (line 105).
- "If a function has rank r, then the subarrays along the last r axes of its arguments are the
  cells of the array. The remaining axes are the frame of the array" (lines 149–152). Worked
  example: `⌹` (rank 2) on shape `8 7 6 5 4`: cells `5 4`, frame `8 7 6`.
- **Semantics** (lines 172–189): apply `f` to each cell of shape `(-r)↑⍴⍵`, get results of a
  common shape `sir`, assemble into shape `((-r)↓⍴⍵),sir`.
- **Agreement**: dyadic frames must match or one must be a scalar, extended by reshape — "a
  generalization of scalar extension" (line 199).
- **Empty frame convention** (line 201): if the frame contains 0, the result cell shape is
  taken to be empty.
- **Ranks are assigned per primitive** (Domains table, line 606 ff.): `⌹` monadic 2, dyadic 2;
  `⍴` left 1 (rank 1 shape vector) right infinite; scalar functions rank 0; several primitives
  still "unassigned" in 1983.
- Examples show the operator replacing axis brackets and special cases: grade of each row,
  rotate each plane by a different amount (`(1-⍳4)⌽⍤1 2 b`), catenate a scalar to each matrix
  (`y,⍤0 2 b`), reshape each plane, index-of per row, table lookup, and `⌹` extended to
  stacks of matrices "rather than by looping".

**Steal.**
- The definition verbatim as the semantics of the typed operator: cell rank per argument,
  frame = the rest, result shape = frame ++ cell-result shape. In Idris this is a type:
  `rank : (f : Array c a -> Array c' b) -> Array (frame ++ c) a -> Array (frame ++ c') b`
  with `frame` and `c` as `Vect`s of sizes (erased where they must be, §0).
- **Batched primitives come for free**: `⌹` on a stack is `⌹⍤2`. Every rank-2 kernel (matrix
  product, inverse, solve) becomes batched by the operator, which in MLIR is extra `parallel`
  iterators on the same `linalg` op (`docs/mlir/docs/Dialects/Linalg/_index.md`, line 254 ff.)
  — no batched variants to write.

**Avoid.** The empty-frame convention (result cell shape `⍬` when the frame is empty of cells)
is a run-time guess forced by not knowing the result-cell shape; with a typed result shape the
compiler knows it (§6, §8).

**Limits.** Dyadic agreement is "identical or scalar" here; J later chose *prefix* agreement
(§6, §8).

---

## 5. Iverson, *A Dictionary of APL* (1987)

`papers/iverson-1987-dictionary-of-apl/APLDictionary1.htm`.

**Key ideas.**
- Grammar of parts of speech: nouns, verbs, adverbs, conjunctions, copula, punctuation
  (II, line 216 ff. in the text rendering; the HTML anchors from line 426).
- **Arrays** (II.A, line 426 ff.): rank = number of axes; *k-cells* are the last k axes; the
  rest of the shape is the *frame* relative to k-cells; a *zero frame* has a 0 in it, and "an
  empty frame is *not* a zero frame" (lines 522–525); the *major cells* are the cells of rank
  one less than the array, and `{`, grade and friends act on major cells (line 530 ff.);
  negative cell ranks count frame axes.
- **Ranks of verbs** (II.B.2, line 662): every verb has three intrinsic ranks, monadic, left,
  right; defining `⌽` on lists defines it on every array.
- **Result assembly** (`<a name="assembly">`, line 705): results of different rank get leading
  unit axes; results of different shape are padded (`ms↑a`) to the max shape. The zero frame:
  "the shape of the individual result is determined by applying the function to a surrogate
  argument having the shape required for the argument cell" (line 746); when surrogates
  disagree, "the smallest shape over all surrogate arguments" (line 756).
- **Degenerate cases** (line 812): rank is an upper bound; `⌽` of a scalar is itself; `⌹` of a
  list treats it as a one-column table.
- **Agreement** (line 827): frames identical or one empty; infinite rank always extends; the tie
  conjunction relaxes agreement to a given number of leading frame axes, which gives outer
  products of any depth (`m 0 .+ m`).

**Steal.** The three-ranks-per-verb discipline (a function's type names its cell rank for each
argument), major cells as the default unit of structural functions (the leading axis; §9), and
the explicit separation of empty frame from zero frame.

**Avoid.** Padding ragged results (`ms↑a`) and the surrogate-argument evaluation for zero
frames. Both are the language guessing a shape it could not know. A typed language rejects
ragged results unless the user boxes them (an array of arrays), and computes the zero-frame
result shape from the type.

**Limits.** A dictionary, not a semantics: the assembly and surrogate rules are stated in prose
with no account of side effects or errors raised by the surrogate call.

---

## 6. Hui, *Rank and Uniformity* (APL95)

`papers/hui-1995-rank-uniformity/rank1.htm`. The most compiler-relevant paper of the lineage.

**Key ideas.**
- **An executable model of rank in 15 lines of J** (§0, lines 86–266; Appendix A.0): effective
  rank `er` clamps a (possibly negative) rank to `0..#$y`; `fr`/`cs` split the shape into frame
  and cell shape; `cells` boxes the cells; `rag`/`lag` reconcile frames; `asm` assembles.
- **Agreement choices made explicit** (line 155 ff.): *scalar* agreement (one frame empty),
  *suffix* agreement (one frame a suffix of the other), *prefix* agreement (one frame a prefix
  of the other, each cell reshaped "with the excess in the other frame"). "All three are proper
  generalizations of scalar extension"; J adopts prefix agreement "because it best fits the
  emphasis on leading axes" (line 170).
- **Assembly** (line 215 ff.): results brought to common rank by leading unit axes, then common
  shape by padding; "a design choice: the individual results could be required to have a
  common shape without further intervention, but this permissive assembly proves useful" (line
  226).
- **Zero frame** (line 266): no cells to apply to, so the result-cell shape is indeterminate; "in
  J, the shape is calculated if v is uniform; otherwise v is applied to a cell of fills" (line
  275).
- **Integrated rank support** (§1, line 278 ff.): for specific verbs, `v"r` is implemented inside
  the verb, striding through the argument "without explicitly constructing each row vector";
  measured speed-ups of `v"r` with IRS over the general routine on an 8000×23 matrix range from
  1.8× (`-:!.0"1`) to 157.3× (`{."1`, first column) (table around line 375). Gains come from
  (a) exploiting the verb's properties, (b) not building cells, (c) not re-validating per cell.
- **Uniform verbs** (§2, line 390 ff.): `v` is uniform if result shape depends only on argument
  shapes and result rank only on argument ranks: there are calculators `vs`, `vr` with
  `$v y ↔ vs $y`. Scalar functions and ravel are uniform; `i.` is not (`i.3`, `i.4`); `{.` is
  not, but `m&{.` with a fixed left argument is. Compositions of uniform verbs are uniform with
  composed calculators. Then `u@v y ↔ u"(vr m<.#$y) v y`: a per-cell composition can be
  rewritten into whole-array calls, measured 24× faster for `*:@+` on two 8000-element vectors
  (line 457). The set of uniform verb forms is closed under `@ @: & &: n&v v&n`, hooks, forks,
  `v"r`, `v^:n`, `v~`, `v/`, `v/.`, `v\`, `v\.` (end of §2). "It appears that a calculus on
  rank alone suffices to produce much benefit" (line 518).
- **Appendix B** (line 994): rank and shape calculators for every uniform J primitive, and a
  counterexample pair for every non-uniform one.

**Steal (this is the core of the design).**
- **Uniformity is a type.** A uniform verb is exactly a function whose result shape is a
  function of its argument shapes, i.e. a dependently typed function
  `(s : Shape) -> Array s a -> Array (vs s) b`. Hui's calculus on shapes is type checking.
  Appendix B is a ready list of the shape functions for the primitive vocabulary.
- **Non-uniform verbs are dependent pairs.** `i.n` has shape `[n]`, determined by a *value*:
  in Idris `iota : (n : Nat) -> Array [n] Nat` is uniform once `n` is in the type; where `n` is
  only known at run time the result is `(n ** Array [n] Nat)`. Hui's "m&{. is uniform" is the
  same move: fix the shape-determining argument and the verb becomes uniform.
- **Integrated rank support = indexing maps.** Never materialise cells; the cell axes become
  inner iterators of one `linalg.generic` and the frame axes outer `parallel` iterators
  (`docs/mlir/docs/Dialects/Linalg/_index.md`, lines 178–185, 254–275). IRS in J is per-verb C
  code; in MLIR it is the default, because the indexing map is the stride.
- **The `u@v` rewrite is fusion licensed by uniformity.** Hui rewrites per-cell composition
  into whole-array application because the calculators say the cells line up; MLIR's
  elementwise fusion and producer–consumer fusion of `linalg` on tensors does the same when
  the indexing maps compose.
- **Prefix (leading-axis) agreement**, chosen for the same reason as Hui and BQN (§9).

**Avoid.** Permissive assembly (padding) and applying a verb to a cell of fills to learn a
shape. Both disappear when shapes are in types: the result-cell shape is the type's, padded
results are type errors unless boxed, and the zero frame needs no evaluation at all.

**Limits.** The uniformity calculus was proposed, not implemented ("It remains to implement a
calculus of uniform verbs", end of §2); measurements are 1995 J on a 486/50.

---

## 7. Hui, *Rank Operator: An Idea Worth Borrowing* (Dyalog '09)

`papers/hui-2009-rank-operator/`.

**Key ideas.**
- A 6-line dfns model of `⍤` (`model1.htm`): `effrank`, `cells` (enclose along the last
  `effrank` axes), `assemble` (add leading unit axes to a common rank, then mix), and `R` that
  maps over cells with `¨` (`model2.htm`–`model4.htm` step through it).
- **Outer and inner product from rank** (`app1.htm`, `app2.htm`): `x +⍤0 ∞ y` (written
  `+R 0 16`) equals `x ∘.+ y`; `dot←{⍺ ⍺⍺{⍺⍺⌿⍺ ⍵⍵ R ¯1 +⍵}⍵⍵ R 1 16 +⍵}` reproduces
  `+.×` and `∧.=`.
- Axis-bracket forms that APL could not express (`⍋[1]`, a user function `[1]`) all become
  `R 1` (`eg1.htm`).
- IRS timings (`irs2.htm`): `0 {"1 x` on a 100×100000 array 1.5e-5 s and 1,856 bytes with IRS
  versus 0.042 s and 1.05 MB with the cells built.
- History (`history.htm`): Iverson's *Operators and Functions* §6 (1978), Whitney 1982,
  *Rationalized APL* 1983, SATN-45 1983, ISO Extended APL 2001.

**Steal.** The derivations of outer and inner product from rank: the typed language needs
*one* lifting operator plus reduce, and `∘.f`, `f.g`, "each row", "each plane" are library
definitions, each lowering to one `linalg.generic`. The IRS timings are the cost of building
cells; a design that materialises cells has to recover them by fusion.

**Limits.** Slides, not a paper; claims are illustrated, not argued.

---

## 8. The J Dictionary

`docs/j/help/dictionary/`.

**Key ideas.**
- Nouns are homogeneous: "the atoms of any array must belong to a single class: numeric,
  literal, symbol, or boxed" (`dicta.htm`); k-cells and frames (line 66); an *item* is a cell of
  rank one less, "an atom has one item, itself" (line 88).
- Verbs (`dictb.htm`): rank conjunction (line 32 ff.); result assembly pads with "an
  appropriate fill element: space for a character array, 0 for a numeric array, and a boxed
  empty list for a boxed array" (`<a name="fill">`, line 56); **prefix agreement**: "one frame
  must be a prefix of the other" (line 96), so `3 4 5 * i. 3 4` multiplies each row by one
  scalar; "if a frame contains 0, the verb is applied to a cell of fills" (line 112).
- `u"n` (`d600v.htm`): full rank `3$&.|.n`; negative rank is complementary,
  `u"(-r) y ↔ u"(0>.(#$y)-r)"_ y` (line 31). `u"v` takes the ranks of another verb
  (`d600xv.htm`), and `b.` reports a verb's ranks (`intro20.htm`, line 83).
- Composition and rank inheritance (`intro20.htm`, line 142): `f@g` inherits the rank of `g`
  (applied per cell of `g`); `f@:g` has infinite rank (applied to the whole result). The same
  pair exists for `&`/`&:`.
- Under (`d631.htm`): `u&.v y ↔ vi u v y`, `x u&.v y ↔ vi (v x) u (v y)` where `vi` is the
  obverse, applied per cell of `v`'s rank (line 29); "each" is defined as `&.>` (line 57);
  duals with respect to negation, log and negation (line 67 ff.). The obverse of a verb is
  defined for self-inverse primitives, a table of inverse pairs, bonded invertible dyads, some
  scans, and user-specified `:.` (`d202n.htm`).
- Insert and table (`d420.htm`): `u/y` applies `u` between the *items* (major cells) of `y`
  (line 27); the dyad `x u/ y ↔ x u"(lu,_) y` is the outer product (line 60); an empty `u/`
  gives the verb's neutral (line 68).
- Trains (`dictf.htm`): hook and fork; "the ranks of the hook and fork are infinite" (line 43).

**Steal.**
- **Prefix agreement over suffix broadcasting.** It is what the rank operator composes with
  (frames are leading axes) and what keeps a rank-polymorphic function's frame a *prefix* of
  every argument's shape — a property an Idris type can state (`shape = frame ++ cell`).
- **The `@` versus `@:` distinction** (per-cell versus whole-result composition) as two
  different combinators with different types, never inferred from context.
- **`u"v`: rank as an attribute of a function**, inspectable and transferable. In a typed
  setting the rank is part of the function's type and is therefore always available.
- Insert over major cells (not over atoms) — the leading-axis reduction that BQN keeps (§9).

**Avoid.** Fill-padded assembly and cell-of-fills evaluation for zero frames (same reasons as
§5, §6); obverses that are approximate (`d202n.htm` lists computed obverses such as a
numerically iterated inverse for `^~`): an Under in a typed language should require a lawful
inverse or a structural selection.

**Limits.** The web Dictionary is the 2001 text; NuVoc (the current J reference) is behind a
Cloudflare challenge and was not fetched.

---

## 9. BQN (documentation at `5abbab96`)

`docs/bqn/`.

**Key ideas.**
- **What an array is** (`doc/array.md`): axes must be independent ("the length of the second
  axis depends completely on the position in the first" in nested lists; "in a BQN array
  differing lengths simply aren't representable", line 84); the array is complete; rank,
  length, shape, bound (line 98 ff.); cells defined by index prefixes, "Cells are the center of
  the leading axis model" (lines 110–120); a formal definition as a map from bounded index lists
  (line 128); "an array can always be packed flat: the shape and the elements. This strided
  representation makes branchless and cache-friendly primitive algorithms much easier" (line
  138).
- **The based model** (`doc/based.md`): atoms are not arrays (line 17 ff.); arrays are an
  inductive type (line 41 ff.); APL2's nested model identifies an atom with its enclosure and
  so is not inductive and creates "inversions where the depth of a particular array depends on
  its rank" (line 49 ff.); the boxed model of SHARP/J uses arrays as the base case and pushes
  the depth-0 boundary up one level (line 57 ff.). Thesis: "APL took a wrong turn around 1981"
  (line 13).
- **Depth** (`doc/depth.md`): depth is max element depth plus one, atoms 0, empty arrays 1
  (lines 64–72); several primitives test the depth of `𝕨` to decide single-axis versus
  multi-axis behaviour (line 79 ff.); the Depth modifier `⚇` generalises Each the way Rank
  generalises Cells (line 111 ff.).
- **The leading axis convention** (`doc/leading.md`): structural functions act on the first
  axis (major cells), and Rank reaches later axes (line 5); multi-axis left arguments apply to
  leading axes (line 79 ff.); **leading axis agreement**: "all axes of the lower-rank argument
  are matched with the leading axes of the higher-rank one" — the opposite of NumPy/Julia
  trailing broadcasting (line 98 ff.); for a rank-k array there are exactly k+1 shapes that can
  combine with it without changing rank, the prefixes of its shape (line 118).
- **Cells and Rank** (`doc/rank.md`): `𝔽˘` is `𝔽⎉¯1` (line 62 ff.); negative ranks count frame
  axes, ranks clamp, and "there's no option for ¯0 … but ∞ serves that purpose" (lines
  124–140); frame and cells (line 142 ff.), with the defining identity
  `F⎉k x ←→ >F¨<⎉k x` (line 152); the matrix product is `+˝∘×⎉1‿∞`, which also gives the
  matrix–matrix product because `×` and `+˝` work on leading axes (lines 171–183); frames use
  leading axis agreement, cell shapes are left to `𝔽`, giving "two layers of prefix agreement"
  (lines 187–199); nested Rank gives table-of-cells `𝔽⎉∞‿¯1⎉¯1‿∞` (line 209).
- **Fill** (`doc/fill.md`): the fill is inferred, not part of the array; used only by Take,
  Reshape with `↑`, Nudge, Merge/Join of empty arrays, and Cells/Rank with an empty frame (line
  7); for empty frames an implementation "may try to find it by running `𝔽` using a cell of
  fills … not allowed to produce side effects. If it doesn't work, the result cell shape is
  assumed to be `⟨⟩`" (line 45). The author lists "Empty arrays lose type information" as the
  first of BQN's problems: "Fills are BQN's solution for deeper structure, but they're
  incomplete" (`commentary/problems.md`, line 11).
- **Under** (`doc/under.md`): one principle, `(𝔾 𝕨𝔽⌾𝔾𝕩) ≡ 𝕨𝔽○𝔾𝕩` (line 51); *structural*
  Under when `𝔾` only moves elements (it records what `𝔾` selected and writes `𝔽`'s results
  back; line 45, §"Structural Under" line 55); *computational* Under via Undo otherwise (line
  85); "Structural Under is the same concept as a (lawful) lens" (line 83).
- **Insert vs Fold** (`doc/fold.md`, "Insert" line 141 ff.): `𝔽˝` reduces over major cells and
  knows the identity's shape from the argument; APL2's `⍪⌿` is a different (element-wise)
  reduction, written `∾¨˝` in BQN (line 176 ff.).
- **Merge and array theory** (`doc/couple.md`, line 38 ff.): Merge (`>`) checks the inner arrays
  form a homogeneous array and reinterprets; it cannot produce a 0 in the middle of a shape
  without a fill — "arrays are a richer model than nested lists".
- **Compilation** (`implementation/compile/intro.md`, `fusion.md`): C's types are "temporally
  homogeneous", array element types "spatially homogeneous" (line 31); static typed array
  languages (Futhark, Dex, MLIR/XLA) are named as compilation targets (line 61 ff.); fusion
  must be cut at size-changing primitives such as Replicate, giving two levels of fusion
  (blocking/tiling, then register fusion) (`fusion.md`, lines 9–11, "Blocking" line 13 ff.,
  "Low-level fusion" line 34 ff.).
- **Co-dfns versus BQN** (`implementation/codfns.md`): Co-dfns stores the AST as parent and
  sibling vectors; BQN's compiler instead reorders a token list so tree walks become scans
  under the right ordering, with a single iteration in the whole compiler (line 17); recent
  Co-dfns relaxes the strict array style (lines 11, 19); the author's verdict on array-style
  compilers in general: "In short: **no**" without a good reason (line 37); and the wish for
  "not really a type system but an *axis* system" — knowing two variables are indexed by the
  same axis, and that `i⊏a` and `i⊏b` are compatible but `a` and `i⊏b` are not (line 53). The
  re-measurement: BQN's self-hosted compiler runs between the same speed and half the speed of
  a Java compiler for BQN; Co-dfns' 10× over Chez nanopass was against a slow baseline (lines
  57–70).

**Steal.**
- **Leading axis agreement and the leading axis convention** as the only broadcasting rule:
  frames are prefixes, so `Array (frame ++ cell)` is the one shape form the type system needs,
  and the rank operator is the only way to reach inner axes. This rules out trailing (NumPy)
  broadcasting, which would need a second shape form (suffix) and a second agreement rule.
- **Based arrays**: atoms are not arrays; `Array s a` is an inductive type over any element
  type `a`, so `Array s (Array t b)` (nested) and `Array (s ++ t) b` (flat) are *different
  types*, and `merge : Array s (Array t b) -> Array (s ++ t) b` is total when the inner shape
  `t` is uniform (in the type). Ragged nesting is `Array s (n ** Array [n] b)`, explicitly a
  different thing. This is the BQN model with the shape check moved to compile time.
- **`F⎉k x ←→ >F¨<⎉k x` as the specification** of the rank operator, and Each as rank 0 under
  enclose: the typed operator is defined by split-map-merge and implemented without the split
  (§6, IRS).
- **Structural Under = lenses over index maps.** A structural `𝔾` (take, drop, transpose,
  select, reverse, a cell) is an affine or permutation index map; `𝔽⌾𝔾` is "compute `𝔽` on the
  view, write back into the same positions", which is `tensor.extract_slice` /
  `tensor.insert_slice` (or a `linalg.generic` whose output indexing map is the inverse view)
  in destination-passing style. A typed Under takes a lens (get, put, laws), not a guessed
  inverse.
- **The "axis system"** the BQN author asks for is what dependent types give: an axis is a named
  size index; `a` and `b` agree when their types share the frame; `i⊏a : Array [m] e` when
  `i : Array [m] (Fin n)` and `a : Array [n] e`.
- **Fusion cut at size-changing primitives** (Replicate/compress, Group): a lowering that fuses
  maps and reductions greedily but materialises at filters, which is where `linalg` fusion stops
  anyway (filters are not `linalg.generic`).

**Avoid.**
- Fill elements as an inferred property and empty-frame evaluation by running `𝔽` on fills: the
  author's own first-listed problem (`commentary/problems.md`, line 11). With shapes in types,
  the empty case has a known result shape and needs neither.
- Depth tests that change a primitive's behaviour (`doc/depth.md`, line 79 ff.): a typed API
  separates "one axis" and "many axes" into two functions (or a sum type), not a run-time depth
  check.
- Positive/negative rank to encode cell versus frame and the resulting "negative zero" problem
  (`commentary/problems.md`, line 131; `doc/rank.md`, line 140): a typed rank operator should
  take a *cell shape* (or a frame length) as a type-level datum, with two named forms
  (`cells k`, `frame k`), not a signed integer.

**Limits.** Dynamically typed; the documentation is design commentary by one author, partly
opinion (marked as such in the files).

---

## 10. Hsu, *A Data Parallel Compiler Hosted on the GPU* (dissertation, 2019)

Stored: `papers/hsu-2019-data-parallel-compiler/hsu-dissertation.pdf.txt` (repository text
extraction; its prose is mostly missing because the PDF's body fonts have no Unicode map, its
code is intact). The PDF (30.7 MB, over the cap) was read in place; prose claims cite its
printed page numbers and are marked *[PDF, not stored]*.

**Key ideas.**
- **Desiderata for vector machines** *[PDF p. 58]*: no recursion, no branching, small
  integer/float values, contiguous allocation, sequential reads, minimal memory, minimal data
  dependence in control flow, data-parallel operations; the record/ADT representation of trees
  (pointer per edge, (N×192)+E×128 bits for N nodes and E edges, p. 56) fails all of them.
- **Representations** *[PDF pp. 59–80]*: linearised trees go back to Iverson 1962 (p. 60; §1
  above). The *depth vector* (preorder, each node's depth) is compact and makes subtrees
  contiguous but needs a search to find parents (pp. 60–62). The AST is an *inverted table*
  (one vector per field, not a vector of records) with interned symbols and small enumerations
  for type and kind (pp. 66–69): `d t k n` (p. 70). A *path matrix* (N×D) makes any two nodes
  comparable (common ancestor by `+.=`) at N×D memory (pp. 72–77). The *parent vector*
  `p[i]` (roots point to themselves, so every element is a valid index and no null test is
  needed) gives linear memory, cheap appends, and partial ordering: only sibling order matters
  (pp. 77–80).
- **Depth to parent** (§3.3, pp. 81–88): the naive form is quadratic; the efficient one groups
  node ids by depth with Key and finds each node's parent by *interval index* into the previous
  depth's group — `p⊣2{p[⍵]←⍺[⍺⍸⍵]}⌿⊢∘⊂⌸d⊣p←⍳≢d` (stored text, line 883; Co-dfns `D2P`,
  `code/co-dfns/cmp/global.apl` line 47) — O(n) work, O(log n + log m) critical path (p. 88).
- **The walking idiom** (§3.4, pp. 89–96): bottom-up traversal by pointer chasing to a fixed
  point, `r←I@{t[⍵]≠3}⍣≡⍨p` (nearest enclosing function for every node at once; stored text,
  lines 965–984); constant critical path per step, iterations bounded by tree depth (p. 95). The
  "subterranean technique": node ids are indices into every column, so ids are computable data,
  not opaque pointers (p. 95).
- **Lifting by tail catenation** (§3.5, pp. 96–102): `p,←n[i]←(≢p)+⍳≢i` appends copies of the
  lifted function nodes and reuses the old slots as variable references; because only sibling
  order matters, appended roots need no reordering.
- **The 17-line compiler** (Appendix B; stored text, lines 2228–2245): passes PV (parent vector
  and contour), LF (lift functions), WX (wrap expressions), LG (lift guards), CI (count index
  rank), LX (lift/flatten expressions), SL (slots), FR (frames), XN (exports), AV (resolve
  variables).
- **Three traversal patterns** (§5.2, pp. 176–180): *Each* (per-node, no edges; most passes),
  *Walk* (`I@{…}⍣≡`, bottom-up), *Key* (group children under parents); plus precomputed
  "skip" pointer vectors (ropes) to shorten walks (p. 179). Edge mutation is a bulk update of
  `p` or a permutation followed by pointer correction (pp. 180–181). Node deletion is
  replicate-by-0 followed by the "garbage collection idiom" `(⍸M)(⊢-1+⍸)(~M)⌿p`, which shifts
  every pointer by the number of deleted nodes before it (interval index again) (pp. 182–185).
- **Critical paths of the primitives** (Tables 1–2, pp. 37–38): structural functions constant;
  replicate, where, grade, index-of, interval index, set operations logarithmic; Each, Rank,
  outer product constant; inner product, reduce/scan, Key logarithmic.
- **Measured results** (Ch. 4): the input AST costs about 4 bytes per node in Dyalog (Table 4,
  p. 149: 63.7 MB at 16.7M nodes versus 1,051 MB Racket and 1,485 MB Chez); GPU speed-up over
  the Dyalog CPU interpreter about 6× at the largest size, tracking the bandwidth ratio (p.
  152); speed-ups over the Racket nanopass reference "33x to 200x on the CPU and GPU at large
  sizes", individual passes beyond 1500× (p. 157); over Chez nanopass 9.4× (CPU) and 56.1×
  (GPU) on average at scale (p. 169); 17 lines / 760 tokens / 948 AST nodes versus 1012 lines /
  20,947 tokens / 14,680 nodes for nanopass (Table 5, p. 156). GPU timings exclude transfer
  (p. 150) and the GPU version was a C++/ArrayFire compile of the same code (p. 151).
- **Limitations he names** (§5.4, pp. 190–191): unfamiliarity; "the dearth of statically typed
  features in current APL language implementations, and it remains an open question whether
  explicit static typing in the code would be a fundamental improvement"; tree transforms are
  only part of a compiler's time.

**Steal.**
- **For representing nested and tree-shaped data inside a dense array language**: an inverted
  table of fields plus a parent vector (or, for read-mostly use, a depth/offset vector) is the
  flat encoding of an `Array s (n ** Array [n] b)` or a tree, with every traversal expressed by
  Each, Key (segmented reduction), Walk (pointer jumping) and interval index. These lower to
  `linalg`/`scf` over integer index vectors; pointer jumping is a `scf.while` around a gather.
  This is how a ragged or recursive structure can stay in the dense compilation path instead of
  falling back to boxed cells.
- **Roots point to themselves**: an index vector whose every element is in range needs no null
  check, so gathers through it need no masks — a refinement type (`Vect n (Fin n)`) in Idris.
- **The garbage-collection idiom** is the general "compact and renumber" step (stream
  compaction plus exclusive scan of the deletion mask); it is how a filter on a pointer-linked
  structure stays dense.
- **Critical-path tables** as a cost model for choosing lowerings: constant-path primitives fuse
  freely; logarithmic ones (scan, sort, search, Key) are fusion boundaries or need their own
  parallel algorithm.

**Avoid.**
- **Hosting the compiler in this style.** The BQN author's re-measurement and verdict
  (`docs/bqn/implementation/codfns.md`, lines 37, 57–70) and Hsu's own GPU caveats (transfer
  excluded; unoptimised ArrayFire code, p. 153) argue against rewriting this compiler's passes
  as array programs: the claim worth taking is the *representation and its idioms* for user
  data, not the hosting decision.
- Fixed-point iteration (`⍣≡`) as an unbounded loop in compiled user code without a bound: its
  critical path is the tree depth (p. 95); a typed version should carry the bound (depth) or
  use pointer doubling (log depth).
- The "negative values are symbols, non-negative are node ids" overloading of one column
  (p. 101): compact, but two meanings in one integer is exactly the kind of fact this
  repository keeps in types (a sum type, lowered to the same integer).

**Limits.** One compiler, of a small dfns subset; nanopass as the only baseline; GPU numbers
from a hand-translated build (also stated in `docs/bqn/implementation/codfns.md`, line 11).

---

## 11. Co-dfns source (`07363409`, v5.7.1)

`code/co-dfns/`.

**Key ideas, in the code.**
- `cmp/global.apl`: node types are a small enumeration `(A B C E F G H K L M N O P S T V X Z)←1+⍳18`
  (line 5); `D2P` (depth to parent, line 47) is the dissertation's interval-index algorithm;
  `P2D` (lines 48–51) computes depths from parents by repeated pointer chasing and then a
  preorder permutation.
- `cmp/PS.apl`: the parser is itself array code; brace nesting depth is a running sum,
  `d←+⍀bi←bm[i]` of `({`=1, `}`=¯1) with balance errors found by comparing against running
  minima (lines 88–92), and `p←D2P d` builds the tree (lines 192–193); brackets and parentheses
  become nodes by the same `+⍀` depth trick and a second `D2P` (lines 276–292).
- `cmp/TT.apl`, the transformation pass, shows the idioms at work:
  - deletion with pointer correction:
    `p t k n lx vb pos end⌿⍨←⊂msk` then `p vb(⊣-1+⍸⍨)←⊂⍸~msk` (lines 5–6, repeated at 11, 42,
    57, 68, 243–244);
  - ancestor propagation to a fixed point: `msk←{⍵∧⍵[p]}⍣≡…` (line 5), `r←I@{msk[⍵]}⍣≡⍨p`
    (scope of every node, line 18);
  - lifting dfns to the top level by appending and redirecting parents (lines 79–81);
  - a frame-slot allocator that colours an interference matrix with a randomised
    maximal-independent-set loop (lines 207–219) — quadratic, as the BQN notes say
    (`docs/bqn/implementation/codfns.md`, line 25).
- `cmp/GC.apl` emits C against a runtime library; `cmp/CC.apl` shells out to `cl`, `gcc` or
  `clang` per OS; the macOS command hard-codes `-arch x86_64` (line 39). `docs/PERFORMANCE.md`
  classes primitives by GPU behaviour (fused, embarrassingly parallel, complexity-preserving,
  complexity-changing, unparallelised, CPU-only) and introduces the critical-path model.

**Steal.** Concrete, tested implementations of each idiom of §10 to transcribe (as *ideas* —
the code is AGPL and must not be copied into this repository) into an Idris library of
tree-on-arrays operations whose types state the invariants (`p : Vect n (Fin n)`, acyclic,
roots self-pointing), lowered by the same frontend path as other dense loops.

**Avoid.** Per-OS branches in the build step (`cmp/CC.apl`, lines 1–51), and an `x86_64`
assumption on macOS: both are what this repository forbids outside the target entry. The
untyped column conventions (negative `n` for symbols) noted above.

**Limits.** No tests or runtime were vendored; the passes are not the dissertation's 17 lines
but a later, larger compiler (251 lines in `TT.apl`).

---

## 12. Sources not stored and what they would add

- **Hui & Kromberg, *APL Since 1978*** (PACMPL 4(HOPL) 69, 2020, DOI 10.1145/3386319; Crossref
  licence CC-BY 4.0; OpenAlex/Semantic Scholar: gold OA, CC-BY-SA): the authoritative history of
  rank, leading axis, J, k/q and Dyalog after 1978. `dl.acm.org` returns 403 to scripted fetches
  and the library does not bypass it; a browser download would obtain it. Nothing here cites it.
- **Bernecky, *An introduction to function rank*** (APL88, DOI 10.1145/55626.55632, pp. 39–43;
  closed): the formal introduction of function rank. SATN-45 (§4) and Hui 1995 (§6), both
  stored, cover its definitions.

---

## 13. Synthesis for an Idris-hosted typed array language lowered to MLIR

### 13.1 The type of an array and of a rank-polymorphic function

- `Array : (s : List Nat) -> Type -> Type`, a shape and a row-major backing (the APL model:
  `docs/bqn/doc/array.md`, lines 122–138; `APLDictionary1.htm`, line 426 ff.). Rank is
  `length s`; there is no maximum, because nothing in the model has one (§0).
- **Leading-axis lifting** is one combinator:
  `lift : (Array c a -> Array d b) -> Array (f ++ c) a -> Array (f ++ d) b`, and its dyadic form
  with prefix agreement of frames (`docs/j/help/dictionary/dictb.htm`, line 96;
  `docs/bqn/doc/leading.md`, line 98 ff.): `lift2 : (Array c1 a -> Array c2 b -> Array d e) ->
  Array (f ++ c1) a -> Array (f ++ g ++ c2) b -> Array (f ++ g ++ d) e` with the shorter frame
  `f` repeated over the excess `g` (Hui's prefix agreement, `rank1.htm`, line 155 ff.).
  Rank-as-integer (`⍤r`, negative ranks, clamping) is not needed: the cell shape `c` is in the
  type, which removes BQN's negative-zero problem (`commentary/problems.md`, line 131).
- A **uniform** function (`rank1.htm`, §2) is any function with this kind of type; a
  non-uniform one returns a dependent pair. Every function on arrays is therefore one or the
  other, and the compiler knows which from the type, not from a run-time check.
- Each is `lift` at cell shape `[]` under the element type; outer product is `lift` with left
  cells `[]` and right cells `s` (`d420.htm`, line 60; Hui 2009 `app1.htm`); inner product is
  `lift` with cells `[k]`×`[k, …]` and a reduce (Hui 2009 `app2.htm`;
  `docs/bqn/doc/rank.md`, lines 171–183). Batched linear algebra is `lift` over a rank-2 kernel
  (`satn45a.htm`, `⌹` example).

### 13.2 What disappears because shapes are static

| Dynamic-APL mechanism | Why it exists | Typed replacement |
| --- | --- | --- |
| Agreement errors at run time | frames unknown until run time (`satn45a.htm`, line 199) | type error at elaboration |
| Permissive assembly / padding (`APLDictionary1.htm`, line 705; `rank1.htm`, line 226) | result cells of different shape | rejected; ragged results must be boxed as `Array f (n ** Array [n] b)` |
| Zero-frame surrogate / cell-of-fills evaluation (`APLDictionary1.htm`, line 746; `dictb.htm`, line 112; `docs/bqn/doc/fill.md`, line 45) | result-cell shape unknown with no cells | result-cell shape is the type's `d`; no evaluation |
| Fill elements (`dictb.htm`, line 56; `docs/bqn/doc/fill.md`) | Take/Reshape/Merge on empties | explicit default argument (`take : (n : Nat) -> (pad : a) -> …`) or a `Monoid`/`Default` constraint |
| Depth tests that switch behaviour (`docs/bqn/doc/depth.md`, line 79 ff.) | one primitive, two meanings | two functions or a sum type |
| Obverse guessing for Under (`d202n.htm`) | no inverse in the operand | lens (structural) or a verified iso (computational) as the operand's type |

### 13.3 Lowering to MLIR, with no rank ceiling

- A `lift` of a body whose cells are read at affine indices is a single `linalg.generic`:
  frame axes are `parallel` iterators, cell axes are the body's own iterators, and the indexing
  maps carry Hui's IRS strides (`rank1.htm`, §1; `docs/mlir/docs/Dialects/Linalg/_index.md`,
  lines 98–99, 178–185, 254–275). The number of loops is `length f + length c`, a literal after
  monomorphisation; nothing in `linalg.generic` bounds it. Leading-axis frames make the frame
  iterators outermost, which is the order tiling and SPMD sharding want.
- Reductions inherit Iverson's partitioning identities (§2): associativity gives tiled
  reduction, commutativity gives arbitrary sharding, the identity element gives the empty tile;
  the operand's interface supplies them, and they decide whether a `reduction` iterator may be
  split.
- Uniform composition (`u@v ↔ u"(vr …) v`, `rank1.htm`, §2) is producer–consumer fusion of
  generics; fusion stops at size-changing ops (compress, group, unique), as BQN's notes argue
  (`implementation/compile/fusion.md`, lines 9–11) and as `linalg` does.
- Structural Under lowers to `tensor.extract_slice`/`insert_slice` (or a generic whose output map
  is the view) in destination-passing style, the same ops bufferization already handles.
- Shape functions for the primitive vocabulary are Hui's Appendix B (`rank1.htm`, line 994),
  which is also what MLIR's shape inference expects ops to provide
  (`docs/mlir/docs/ShapeInference.md`, "Shape functions", line 22).
- Ragged and tree-shaped data stays dense with Hsu's representation (§10): a parent or offset
  vector plus field columns, with Each/Key/Walk/interval-index, lowered to generics over index
  vectors and `scf.while` for bounded pointer jumping.

### 13.4 What not to take

- Glyph syntax, ambivalent symbols and right-to-left evaluation (§2): notation choices, not
  semantics.
- APL2's nested model (atoms equal their enclosures): not an inductive type
  (`docs/bqn/doc/based.md`, line 49); Idris's types are inductive, so the based model is the
  only coherent one.
- Trailing-axis (NumPy) broadcasting: a second agreement rule incompatible with leading-axis
  lifting (`docs/bqn/doc/leading.md`, line 100).
- Writing the compiler itself as array code (§10, §11; `docs/bqn/implementation/codfns.md`,
  line 37).
