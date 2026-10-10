# Reading notes: flattening nested data parallelism (cluster `flattening`)

Read 2026-10-09. Topic: **Flattened data: packed, columnar and nested layouts**. Focus asked
for: segmented representations (values plus segment descriptors), the flattening transformation
and its typing, how recursive and nested types flatten, the costs flattening introduces, and why
Data Parallel Haskell failed in practice where Futhark succeeds.

Every path below is relative to `sources/`. Sources this cluster stored are staged under
`flat/stage/sources/`; sources marked *(xref)* were stored by the `dataparallel` and
`apl-lineage` clusters and are staged under `apl/stage/sources/` (same relative paths once
committed); they were read here only for the claims cited. Page numbers are the printed ones
unless marked "PDF p."; "TR p." is the page index of the dvips PostScript.

## Sources

| Path | What | How read |
| --- | --- | --- |
| `papers/blelloch-1990-vector-models/Ble90.pdf` | Blelloch, *Vector Models for Data-Parallel Computing* (MIT Press 1990) | §3.5, §4.3–4.4, §5.2, §9.3, Ch. 10 in full; Ch. 11 skimmed |
| `papers/blelloch-1995-nesl/Nesl3.1.pdf` | NESL 3.1 report (CMU-CS-95-170) | §1, §3.1, App. C in full |
| `papers/blelloch-1994-portable-nesl/CMU-CS-93-112.ps`, `BHSZC94.pdf` | Implementation of a portable nested data-parallel language (TR 1993; JPDC 1994) | TR in full; journal scan checked page 1 |
| `papers/blelloch-1996-programming-parallel-algorithms/cacm/*.html` | Programming Parallel Algorithms (CACM 1996) | nodes 3–6, 9, 12 |
| `papers/keller-1998-flattening-trees/tflat.ps` | Keller & Chakravarty, Flattening Trees (Euro-Par 1998) | in full |
| `papers/chakravarty-2000-more-types/pure-funs.ps` | Chakravarty & Keller, More Types for Nested Data Parallel Programming (ICFP 2000) | in full |
| `papers/leshchinskiy-2006-higher-order-flattening/ho-flat.ps` | Leshchinskiy, Chakravarty & Keller, Higher Order Flattening (PAPP 2006) | in full |
| `papers/chakravarty-2007-dph-status/ndp.pdf` | Data Parallel Haskell: a status report (DAMP 2007) | in full |
| `papers/peytonjones-2008-harnessing-multicores/LIPIcs.FSTTCS.2008.1769.pdf` | Harnessing the Multicores (FSTTCS 2008) | in full |
| `papers/lippmeier-2012-work-efficient-vectorisation/icfp60-lippmeier.pdf` | Work Efficient Higher-Order Vectorisation (ICFP 2012) | in full |
| `papers/keller-2012-vectorisation-avoidance/vect-avoid.pdf` | Vectorisation Avoidance (Haskell 2012) | §1–3, §5–6 |
| `papers/bergstrom-2013-data-only-flattening/ppopp13-flat.pdf` | Data-Only Flattening (PPoPP 2013) | §1–3, §6–7 |
| `papers/larsen-2017-segmented-reductions/fhpc17.pdf` | Strategies for Regular Segmented Reductions on GPU (FHPC 2017) | §1–3, conclusions |
| `papers/elsman-2019-flattening-by-expansion/array19.pdf` | Data-Parallel Flattening by Expansion (ARRAY 2019) | in full |
| `papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` | Full Flattening of Nested Data Parallelism in the Futhark Compiler (MSc 2026) | Ch. 1–4, §5.1, §5.3, Ch. 7–8 |
| `code/nesl/**` | NESL 3.1 compiler and serial CVL | `ptrans.lisp`, `nest-ops.lnesl`, `types.lnesl`, `type.lisp`, `strip-recs.lisp`, `cvl/serial/{facilt,vprims}.c` |
| `docs/nesl/doc/{cvl,vcode-ref}.ps` | CVL manual 2.1, VCODE reference 2.0 | introductions and the segment-descriptor sections |
| `code/dph/**` | DPH libraries at the last commit | segment descriptors, `PData` instances, README |
| `code/ghc-vectoriser/**` | GHC's vectoriser before its 2018 removal | `Exp.hs` (vectorisation avoidance), `Generic/Description.hs`, `Type/Classify.hs`, SNAPSHOT (removal commit) |
| `docs/ghc-dph/*.md` | GHC wiki DPH pages | `data-parallel.md`, `-replicate.md`, `-benchmark-status.md` |
| *(xref)* `papers/henriksen-2019-incremental-flattening/paper.pdf` | Incremental Flattening (PPoPP 2019) | abstract, §1, §6–7 |
| *(xref)* `code/futhark/src/Futhark/Pass/Flatten.hs` | Futhark's full-flattening pass | header comment, lifted representation |
| *(xref)* `papers/hsu-2019-data-parallel-compiler/hsu-dissertation.pdf.txt`, `code/co-dfns/cmp/util.apl` | Hsu's dissertation; Co-dfns | via the apl-lineage notes, `D2P` |

## 1. Segmented representations

**Blelloch's definition.** A *segmented vector* is an ordered set of n segments and a vector of m
atomic values, each segment mapped onto a consecutive, possibly empty, block of the values, the
blocks adjacent and in segment order (`papers/blelloch-1990-vector-models/Ble90.pdf` §4.3, p. 67).
Any structure describing the segmentation is a *segment descriptor*; three are given: head-flags,
lengths and head-pointers (Fig. 4.2, p. 68). Head-flags cannot represent empty segments, and
empty segments are needed by the replicating theorem, so the book uses lengths; any descriptor can
be computed from any other in O(1) steps (p. 68, App. B). Segmented instructions run the
unsegmented instruction independently in each segment; each takes a constant number of
unsegmented calls, so its step complexity is O(1) and its element complexity a constant factor of
the unsegmented one (p. 68). Every segmented scan is at most two unsegmented scans (§3.5, p. 46).

**Nesting depth d is d vectors.** `[[2 3] [] [4 0 1]]` is the data `[2 3 4 0 1]` with the
descriptor `[2 0 3]`; depth three adds a descriptor of the descriptor; "a collection of depth d
can be represented with d vectors" (§9.3, p. 139). A collection of structures is a structure of
vectors ("drag-out", Fig. 9.4); a heterogeneous collection is one value vector per type plus a tag
vector, the tag vector needed only when order matters (p. 140); the mappings compose (Fig. 9.6).

**NESL's implementation.** A sequence is a pair of a value vector and segment descriptors:
`[[2,1],[7,0,3],[4]]` is `segdes1 = [3]`, `segdes2 = [2,3,1]`, `value = [2,1,7,0,3,4]`; the
outermost descriptor of length one is "seemingly redundant" but "critical when implementing nested
versions of user-defined functions"; sequences of fixed-size structures are several value vectors
sharing one descriptor (`papers/blelloch-1994-portable-nesl/CMU-CS-93-112.ps` §3.1, TR pp. 5–6).
The representation is itself declared in NESL: `(defrec (vector segdes a) (a any))`
(`code/nesl/neslsrc/types.lnesl` line 15), and `l-from-type` counts the flat slots of a type, 1
for a primitive, the sum for a pair, 1 plus the element's for a sequence
(`code/nesl/neslsrc/type.lisp` lines 169–184). `partition` and `flatten` are "the only user
accessible functions that deal with segments directly", so the segment representation can change
behind them (`code/nesl/neslsrc/nest-ops.lnesl` lines 31–60). VCODE has no scalar instructions,
"scalars are simply single-element vectors", an unsegmented vector is one segment, and the machine
form of a `segdes` is implementation-defined (`docs/nesl/doc/vcode-ref.ps` §1): the serial CVL
keeps the lengths (`code/nesl/cvl/serial/facilt.c` lines 89–104) and its segmented scans loop over
them, falling back to the unsegmented kernel when there is one segment
(`code/nesl/cvl/serial/vprims.c` lines 62–90); the Cray and CM back ends also keep boundary flags,
packed 64 to a word on the Cray (`papers/blelloch-1994-portable-nesl/CMU-CS-93-112.ps` §3.2,
§3.5.1). CVL descriptors live in vector memory and carry both the segment count and the element
count (`docs/nesl/doc/cvl.ps` §3, "Cvl Data Types").

**DPH's non-parametric arrays.** The array type is a type family indexed by the element type
(`papers/chakravarty-2007-dph-status/ndp.pdf` §4; `papers/peytonjones-2008-harnessing-multicores/LIPIcs.FSTTCS.2008.1769.pdf`
§4, pp. 392–396): `PA Int` an unboxed byte array; `PA (a,b)` a length and the two component
arrays, so zip and unzip are O(1); `PA ()` only a length; `PA (PA a)` the flat data plus a segment
descriptor of (start, length) pairs, so `concatPA` and `unconcatPA` are O(1) projections
(pp. 394–395). The sparse matrix `[:[:(0,15),(2,9),(3,20):], [::], [:(3,46):]:]` is four unboxed
arrays (p. 395). Sums are a boolean (later tag) selector plus one array per alternative, with the
index vector cached so that indexing is not a scan (p. 404); the library's `USel2` holds tags,
indices and both element counts (`code/dph/dph-prim-seq/Data/Array/Parallel/Unlifted/Sequential/USel.hs`
lines 28–33) and `PData (Sum2 a b) = PSum2 Sel2 (PData a) (PData b)`
(`code/dph/dph-lifted-vseg/Data/Array/Parallel/PArray/PData/Sum2.hs` lines 25–28).

**Virtual segments.** Lippmeier et al. stratify the descriptor into three layers
(`papers/lippmeier-2012-work-efficient-vectorisation/icfp60-lippmeier.pdf` §4, Figs. 3–4,
pp. 3–4): `Segd` (lengths and their exclusive scan, `indices`), `SSegd` (for each physical
segment, the source data block and start: segments may be scattered over several blocks) and
`VSegd` (a `segmap` from virtual to physical segments, which may repeat). Seven invariants: equal
field lengths, every segmap entry and source in range, `indices` the scan of `lengths`, and every
physical segment and data block reachable (the last two bound the physical size by the logical
size, needed for append and for reductions not to duplicate work; p. 4). Demotion and promotion
convert between the layers (§5.3, pp. 7–8); a contiguous array is recognisable because it needs
only a `Segd`, which rewrite rules exploit (§6, p. 10). The code keeps lazy "redundant" and
"culled" forms and a manifest flag (`code/dph/dph-prim-seq/Data/Array/Parallel/Unlifted/Sequential/UVSegd.hs`
lines 64–80) and stores a lazily pre-concatenated copy beside the nested array
(`code/dph/dph-lifted-vseg/Data/Array/Parallel/PArray/PData/Nested.hs` lines 32–47).

**Futhark's irregular arrays.** An irregular array is ⟨S, F, O, D⟩: segment sizes, flags (first
element of each non-empty segment), offsets (exclusive scan of S) and flat data; element q of
segment j is `D[O[j] + q]` (`papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` §3.5.1,
pp. 29–31). Only the outer irregular dimension gets metadata; each segment's inner regular shape
is kept as per-segment size arrays, and nested irregular maps are collapsed into one sequence of
segments, so "a single level of segment metadata is always sufficient" (§3.5.2, pp. 31–32). The
pass passes a lifted array as `[num_data, segs, flags, offsets, elems]`
(*(xref)* `code/futhark/src/Futhark/Pass/Flatten.hs` lines 225–228; header comment lines 3–55).

**Other layouts.** Manticore's flattened arrays are a rope of data plus a *shape tree* whose leaves
are (start, end) pairs (`papers/bergstrom-2013-data-only-flattening/ppopp13-flat.pdf` §3, Fig. 2,
pp. 2–3). Blelloch's *v-tree* stores a tree as two vectors, the left- and right-parenthesis
positions of each vertex in Euler-tour order, vertices in preorder; depth, descendant counts and
flag propagation are scans (`papers/blelloch-1990-vector-models/Ble90.pdf` §5.2.1–5.2.2,
pp. 84–87). Hsu's compiler keeps the AST as an inverted table with a parent vector built from a
depth vector by `D2P` (*(xref)* `code/co-dfns/cmp/util.apl` line 47; dissertation §3.3 via the
apl-lineage notes).

## 2. The transformation and its typing

**Replicating and flattening (Blelloch).** *Replicating* turns a routine on one data set into one
on many sets in parallel; *flattening nested parallelism* is replicating plus the representation
change (`papers/blelloch-1990-vector-models/Ble90.pdf` §10.1, pp. 143–146). Theorem 1 (access-
restricted replicating): for an access-restricted routine R there is Rs on n inputs with element
complexity under k1·Σ e(R, Ai) and step complexity under k2·max s(R, Ai) (p. 148). Access-
restricted means fork-and-join conditionals with a constant number of branches, *contained*
programs, memory accessed only absolutely, by stack or stack-relative, and equal stack depth at
every join (p. 149). The proof is constructive: replace every instruction by its segmented
version, every vector by a segmented vector and every scalar by a vector, and triple the addresses
(p. 152). General indirect addressing breaks it, since simulated machines would touch different
locations (§10.5, pp. 152–153). Conditionals use *branch-packing*: pack the segments of each
variable used in a branch to the machines taking it, run the branch, merge (§10.6.1, pp. 154–156);
packing costs a constant factor because unbounded nesting of conditionals arises only through
recursion, where the pack happens at the call (p. 156). The step bound holds only for *contained*
programs, whose evaluation trees are totally ordered by inclusion (§10.6.2, pp. 157–160).

**NESL's compiler.** Apply-to-each (`over`) becomes: bind the descriptor and data of the
sequence, distribute every free variable of the body over the segments with `prim-dist`, and call
the parallel versions of the functions (`code/nesl/neslsrc/ptrans.lisp` `conv-over`, lines
86–110; `conv-func`; a closed constant is distributed too, `conv-constant`, lines 224–228).
Conditionals in a parallel context first count the true flags; if none or all are true only one
branch runs; if both branches are simple, `vselect` picks elementwise; otherwise the indices of
each branch are packed, each branch runs on its free variables gathered at those indices, and the
results are merged (`conv-if`, lines 174–215). The report names this "stepping-up and
stepping-down", plus a test that skips a branch no subcall takes, needed for termination
(`papers/blelloch-1994-portable-nesl/CMU-CS-93-112.ps` §3.1, TR p. 6). All polymorphic functions
are specialised to their types, which needs the whole program (§3.1).

**Typed formulations.** Keller and Chakravarty give a flat kernel language Fkl whose only
nested-array primitives are F (concat), S (the descriptor) and P (rebuild), with
P(F(xs), S(xs)) = xs, and in which every primitive p has a vectorised form p↑ and nothing like
(p↑)↑ is needed (`papers/keller-1998-flattening-trees/tflat.ps` §3.1, pp. 4–5). Chakravarty and
Keller split flattening into *vectorisation* (every function f becomes a pair ⟨f, f↑⟩; inside f↑ a
variable is *parallel* if bound by the lifted lambda and *scalar* otherwise, and a scalar variable
is replicated to the size of the parallel context, `x↑vs = rep (len v) x`) and *specialisation* of
the primitives to the flattened representation (`papers/chakravarty-2000-more-types/pure-funs.ps`
§2.3, §5, pp. 3–7). The type translation `[|τ|]` (Fig. 3a, p. 7) is: `[|()|] = Int`,
`[|Int|] = Int × IntArr`, `[|τ1 × τ2|] = [|τ1|] × [|τ2|]`,
`[|τ1 + τ2|] = BoolArr × [|τ1|] × [|τ2|]`, `[|τ1 → τ2|] = [|τ1|] → [|τ2|]`,
`[|[|τ|]|] = [|Int|] × [|τ|]`; it commutes with the transformation of each function (p. 6). The
primitives are type-indexed and specialised with Hinze's generic programming, which also gives
separate compilation for polymorphic code (§6.3, §7.1, pp. 9–10). Vectorisation itself is not
type-directed, so recursive and polymorphic types do not complicate it (§7.1, p. 10).

**Higher order.** Lifting a partial application drags the whole captured array into a branch and
ignores the selector, so the lengths no longer match (`papers/leshchinskiy-2006-higher-order-flattening/ho-flat.ps`
§2, pp. 3–4). The fix: closure-convert first; an array of functions is an *array closure*, one
code pair (scalar, lifted) and an array environment, so pack, permute and index act on the
environment (§3, pp. 4–6); combining closures of different functions yields a closure whose
environment is a sum and whose code dispatches (§4, pp. 6–7); nested `mapP` becomes one `mapP↑`
that expands the environment by the segment lengths (§5, pp. 7–8). Harnessing the Multicores gives
the full rules with their type invariants (Fig. 6, p. 399): V⟦e⟧ : V_t⟦τ⟧, L⟦e⟧ n : PA V_t⟦τ⟧;
V_t turns every `->` into the closure type `:->` and every `[::]` into `PA`; a literal or global in
lifted context is `replicatePA n`; a lambda builds `Clo`/`AClo`; a lifted conditional splits the
environment by the condition, runs each branch on its part with an `n == 0` guard (without it a
recursive function recurses forever), and `combinePA`s the results (pp. 398–400). `mapP_L` is
`unconcatPA xss (fl (expandPA xss env) (concatPA xss))` (p. 403).

**Futhark's full flattening.** Distribution rewrites a map nest into single-statement maps; rules
replace each by a segmented operation; segmented operations lower to scans over flags
(`papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` Ch. 3, pp. 23–38). *Uniformity*: a
value is variant if it may differ between iterations of the surrounding nest; an array whose
shape depends on a variant value is non-uniform, and non-uniformity is exactly what makes
parallelism irregular; with every array's shape recorded, uniformity is decidable syntactically and
conservatively by where the shape's values are bound (§2.2.3, p. 15). A recursive function lifts
to a lifted function that partitions base-case from recursive-case iterations and calls itself
once on all recursive ones, with a width-zero guard; Futhark itself has no recursion, so this is
not exercised (§5.3.4, pp. 60–61).

**Futhark's incremental flattening (regular only).** For each map nest the compiler emits several
semantically equal versions, outer parallelism only with the rest sequential, an inner level
mapped to a workgroup, or full flattening, guarded by predicates on run-time sizes whose
thresholds are autotuned (*(xref)* `papers/henriksen-2019-incremental-flattening/paper.pdf` §1–3;
code size up to four times, §1). It is "a generic extension to the flattening algorithm for
regular nested data parallelism" (§7).

**Flattening by hand, as a library.** `expand sz get xs` equals
`flatMap (\x -> map (get x) (iota (sz x))) xs`, built from scan, scatter, map and gather only, with
O(M) work and O(log M) span for M output elements; no nested parallelism is needed in the host
language (`papers/elsman-2019-flattening-by-expansion/array19.pdf` §1–3, pp. 15–18).

## 3. How recursive and nested types flatten

- **Nesting.** One descriptor per level of statically known nesting
  (`papers/blelloch-1990-vector-models/Ble90.pdf` §9.3, p. 139), or one level per irregular map
  after collapsing (`papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` §3.5.2, pp. 31–32).
- **Recursive types (trees).** Keller and Chakravarty admit recursive record types whose recursive
  occurrence is only under a vector (`Node (MassPnt, [Node])`), so recursion ends at empty
  vectors; every recursive occurrence becomes `[[x]]`, handled by F, S and P, and a value is a
  chain of levels, one data vector and descriptor per tree level, of statically unknown length,
  terminated by a maybe-type marker (`papers/keller-1998-flattening-trees/tflat.ps` §2–3.2,
  pp. 3–7). The primitives are instantiated per type by adding declarations until closed;
  termination holds because the recursive variable occurs only as a vector element (§3.3,
  pp. 7–9). They excluded sums: "Handling sum types efficiently in flattening seems much harder
  than recursive types" (p. 4).
- **Sums and lists.** Chakravarty and Keller then add sums by selectors; an array of lists becomes
  a selector of nil/cons plus the conses, recursively, as many levels as the longest list, the last
  level an empty selector whose components are never touched; a parallel forest of rose trees is
  a list of levels of (node values, descriptor of the next level)
  (`papers/chakravarty-2000-more-types/pure-funs.ps` §4.1, pp. 5–6). The lifted `case` must not
  touch a component that represents an empty array, since that component may be the undefined end
  of a recursive structure (§6.2, p. 9). Choosing `[:[Int]:]` (array of sequential lists) or
  `[:[:Int:]:]` (fully flattened) is a declarative granularity control (§2.2, p. 3).
- **Cost of indexing.** Indexing an array of a compound type costs the depth of the extracted
  element, since the element is spread over the levels (§6.1.4, p. 9).
- **In DPH.** User types are converted to a generic sum-of-products representation and fixed
  `PA` instances (`papers/peytonjones-2008-harnessing-multicores/LIPIcs.FSTTCS.2008.1769.pdf`
  §6.4, p. 404; `code/ghc-vectoriser/compiler/vectorise/Vectorise/Generic/Description.hs` lines
  36–109). A data type is vectorised only if some type in its definition is, so every type
  reaching `[::]` is and enumerations are not
  (`code/ghc-vectoriser/compiler/vectorise/Vectorise/Type/Classify.hs`, header comment). Barnes-Hut
  stores its quadtree as `Node Mass Location [:Tree:]`, giving one level per array element of a
  list (Harnessing §4.3, p. 395).
- **Measured.** Encoding the Barnes-Hut tree as a NESL vector spent 0.5 s of 1.75 s (29%) in
  operations the encoding introduced, on one processor
  (`papers/keller-1998-flattening-trees/tflat.ps` §4, p. 9); with the rose-tree representation
  the hand-derived code reached a relative speed-up of 15 on 20 Cray T3E processors and an absolute
  one of about 4 (`papers/chakravarty-2000-more-types/pure-funs.ps` §8.1, p. 11).
- **Futhark** omits recursive data types and function recursion by design
  (`papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` §2.4, p. 18); trees are encoded by
  hand.

## 4. The costs flattening introduces

1. **Replication of free variables.** NESL copies every free variable into every instance of an
   apply-to-each; the work is W(e2) + Σ W(e1) + Length × Σ Size(c) over free variables c, so
   `{a[i] : i in b}` costs #a·#b (`papers/blelloch-1995-nesl/Nesl3.1.pdf` App. C, pp. 58–59).
   In DPH this is the `replicatePA` in `mapP_S` and the `expandPA` in `mapP_L`
   (`docs/ghc-dph/data-parallel-replicate.md`). smvm copies the dense vector per non-zero, and
   `treeLookup` copies its table on every level of the recursion, "space consumption that is
   exponential in the depth" (same page). Lippmeier: flattening preserved depth but not work;
   "severe, and sometimes even exponential, blow-up"; `retrieve` goes from O(n) to O(n²)
   (`papers/lippmeier-2012-work-efficient-vectorisation/icfp60-lippmeier.pdf` §1–2, pp. 1–2). The
   cause is index-space transforms (replicate, pack, append, permute) that the contiguous
   representation can only express by copying (§3, p. 3). Virtual segments make `replicates`
   linear in the segmap, `replicate n x` O(n) whatever x holds, pack and combine linear in the
   flags, append linear in the lengths (§4–5.6, pp. 4–9), and reductions over replicated segments
   can sum each physical segment once ("dynamic hoisting", §5.4, pp. 8–9). Futhark leaves
   replication implicit: read `is[II1[p]]` instead of materialising `is_rep`, and for irregular
   values replicate only sizes and offsets that point back into the original data (`O_rep`)
   (`papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` §4.1, pp. 39–41). Each level of
   nesting multiplies the replicated size, up to the work of the whole nest (§3.7.3, p. 38).
2. **Rewrite rules cannot be the fix.** A rule `index_l c (replicate c xs) ys = index_s c xs ys`
   changes asymptotic complexity, fires only if producer and consumer meet, which an unknown
   closure or a recursive call prevents, so programs became "unrunnable" after small changes, "a
   slippery slope to suffering" (`papers/lippmeier-2012-work-efficient-vectorisation/icfp60-lippmeier.pdf`
   §6.1, p. 10).
3. **Index-space overflow.** Virtual copies can exceed the address space (10 × 500 million = 5·10⁹
   virtual elements), which is why the segmap is explicit (§5.4.1, p. 9).
4. **Space.** Flattening can still raise space complexity: `furthest` needs O(n²) space for the
   distances where the nested program needs O(n) (§5.5, p. 9); full flattening of dense matrix
   multiplication suffers a polynomial space increase
   (`papers/bergstrom-2013-data-only-flattening/ppopp13-flat.pdf` §2, p. 2). NESL's interpreter
   copies on single-element updates unless a reference count shows the last reference
   (`papers/blelloch-1994-portable-nesl/CMU-CS-93-112.ps` §3.3, TR p. 9).
5. **Conditionals.** Splitting, packing and combining every live variable, so both branches run
   one after the other over packed data (Harnessing Fig. 6). The depth bound needs containment;
   Riely and Prins' example worsens complexity independent of representation (Lippmeier §5.6,
   p. 9; NESL App. C, pp. 59–60, with the `power` example and its fix). NESL avoids the packing
   when all or no flags are set or both branches are simple (`code/nesl/neslsrc/ptrans.lisp`
   lines 174–215). Vectorisation avoidance measured the trade: avoiding the split/combine wins
   when the load is balanced and on few cores, loses scalability under imbalance; a tail-recursive
   `simpleRec` is two orders of magnitude slower fully vectorised, because vectorisation prevents a
   simple loop (`papers/keller-2012-vectorisation-avoidance/vect-avoid.pdf` §5.4–5.5, pp. 10–11).
6. **Intermediate arrays.** Vectorisation turns every scalar intermediate into an array, moving
   register values through memory; relying on fusion to undo it is fragile, depends on inlining
   (conservative under sharing, impossible for recursion), slows compilation, and GHC's back end
   did not optimise the fused code (`papers/keller-2012-vectorisation-avoidance/vect-avoid.pdf` §1,
   p. 1). Without avoidance `accel` is 13 traversals, with it 1 (one parallel subexpression: 3)
   (§2.3, p. 3); a fused pipeline was more than 3× faster with avoidance (§5.3, pp. 9–10);
   compile time about 25% lower (§5.7, p. 12). GHC implemented it as `encapsulateScalars`, minimal
   or aggressive (`code/ghc-vectoriser/compiler/vectorise/Vectorise/Exp.hs` lines 154–226,
   `vectAvoidInfo` lines 1042–1190). NESL's interpreter paid one library call per vector operation
   and could not fuse; a separate VCODE compiler clustered loops by size inference
   (`papers/blelloch-1994-portable-nesl/CMU-CS-93-112.ps` §3.4, §5, TR pp. 9, 16).
7. **Too much parallelism and lost locality.** Full flattening exploits all parallelism, more than
   the hardware uses, and dissolves the regular structure tiling relies on
   (`papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` Ch. 1, p. 7, Ch. 4, p. 39); NESL on
   GPUs "performed poorly in practice due to high memory usage and communication costs caused by
   excessive parallelization" (*(xref)* `papers/henriksen-2019-incremental-flattening/paper.pdf`
   §6). Perfect load balancing redistributes after every length change; DPH removes it with the
   rule `splitD (joinD xs) = xs`, accepting imbalance
   (`papers/peytonjones-2008-harnessing-multicores/LIPIcs.FSTTCS.2008.1769.pdf` §7.2–7.4,
   pp. 407–409); indexing a balanced array means communication
   (`papers/chakravarty-2000-more-types/pure-funs.ps` §6.1.4, p. 9).
8. **Segmented operations need several kernels.** One workgroup per segment underuses the machine
   for few large segments and many tiny ones; Futhark chooses among large-segment, small-segment
   and sequential-segment kernels at run time, 1.3–1.7× over a scan-based version on Rodinia
   (`papers/larsen-2017-segmented-reductions/fhpc17.pdf` §1–3, Conclusions, pp. 42–50).
9. **Semantics and boundaries.** Lifting a lazy function forces all elements, so `h x (1/x)` may
   raise where the source did not; DPH accepted "the slight change in semantics"; marshalling
   between vectorised and plain code changes representations and is "potentially very expensive"
   (`papers/peytonjones-2008-harnessing-multicores/LIPIcs.FSTTCS.2008.1769.pdf` §6.5,
   pp. 405–406).

## 5. Why DPH failed in practice and Futhark succeeds

**DPH, from its own record.**
- The first measured results were on hand-vectorised code; "the syntactic sugar and the compiler
  transformations ... have not been implemented yet" (`papers/chakravarty-2007-dph-status/ndp.pdf`
  §8, p. 7). Hand-vectorised smvm scaled linearly but was 3.6× slower than C on one Xeon core
  (252 ms against 70 ms), blamed on GHC's back end (pp. 7–8).
- On 3 December 2010 the compiled benchmarks: SMVM "Fusion doesn't work. Vectorised program 1000x
  slower than the C version", out of memory at 2000×2000; BarnesHut "fusion doesn't work"
  because recursive dictionaries are not inlined, and the LLVM build takes 30 minutes; QuickSort
  does not compile (SpecConstr loop); QuickHull 6× slower than `Data.Vector`
  (`docs/ghc-dph/data-parallel-benchmark-status.md`, Summary).
- The work-complexity bug was found in practice and fixed only in 2012, with single-threaded
  numbers, parallel stream fusion not yet adapted to the new representation, and no formal proof
  (`papers/lippmeier-2012-work-efficient-vectorisation/icfp60-lippmeier.pdf` §1, §7, pp. 1, 11).
- "Work on the DPH project stopped around 2010 ... In June 2018 the implementation was removed"
  (`docs/ghc-dph/data-parallel.md`); the removal commit: "Poor DPH and its vectoriser have long
  been languishing" (`code/ghc-vectoriser/SNAPSHOT.md`). The libraries' last commit is 2016
  (`code/dph/SNAPSHOT.md`).

**Reading the record.** DPH took the most general route at every step: all of Haskell (higher-order
functions, laziness, type classes, separate compilation, polymorphic recursion) vectorised by
default, its asymptotics then depending on optimisations it did not control (GHC's inliner,
SpecConstr, rewrite rules, a back end not built for loops). Each fix (avoidance, virtual segments)
arrived as a separate paper and a partial implementation, while the original promise was
whole-program performance. The literature itself names the shape: DPH "continues to reflect the
SIMD orientation of its predecessors" on multicores
(`papers/bergstrom-2013-data-only-flattening/ppopp13-flat.pdf` §7, related work, p. 10); "compiler-based flattening has
proven challenging to implement efficiently in practice"
(`papers/elsman-2019-flattening-by-expansion/array19.pdf` §8, p. 22).

**Futhark, from its record.**
- A deliberately restricted language: no recursion, no recursive data types, regular arrays,
  sizes tracked in types (`papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` §2.4, p. 18).
- It flattened only regular nested parallelism (moderate, then incremental flattening), mapping
  a few top levels to the hardware and sequentialising the rest, with several versions chosen at
  run time and autotuned (*(xref)* `papers/henriksen-2019-incremental-flattening/paper.pdf` §1, §7;
  Hashemi §2.5, pp. 20–21). Irregular parallelism was sequentialised or rejected, and flattened by
  the programmer with a library (`papers/elsman-2019-flattening-by-expansion/array19.pdf` §9:
  "pay-as-you-go").
- Full flattening came last, in 2026, applied only where the uniformity analysis finds irregular
  parallelism, with replication left implicit, scalar statements kept together and uniform nests
  kept regular. It passed all 2,544 tests; geometric mean 0.99 against the old compiler on 523
  datasets (9 of 96 entry points slower by more than 10%, `lud` 1000× slower without an
  annotation because the intra-block version is lost); natural nested SpMV 296× faster than the
  old compiler and within 0.3% of the hand-flattened `expand` version; compile time +4.7%
  (`papers/hashemi-2026-full-flattening/amir-msc-thesis.pdf` §7.3–7.4, pp. 74–78; §8, pp. 79–80).

**The difference, in one line each.** DPH flattened everything and tried to recover performance;
Futhark sequentialised by default and flattened where the data said so. DPH's representation
started unable to express sharing; Futhark's started with indirection through offsets. DPH's
correctness of cost depended on fusion firing; Futhark's cost model was in the IR (segmented ops,
versions, thresholds). DPH served a general language; Futhark restricted the language to what it
could compile well. NESL was in between: a first-order language, an interpreter that won on
irregular sparse data (10× over Cray Fortran on very sparse matrices) and lost on dense data to
interpretive overhead (`papers/blelloch-1994-portable-nesl/CMU-CS-93-112.ps` §5, Fig. 13,
TR pp. 15–16).

## 6. What idris-mlir should take

idris-mlir context used (read, not from the sources): arrays are `memref`s with world-ordered ops
and `idr.array.generate`/`fold` lowered to `linalg.generic`; proposal 0004 rejects
`IArray 1 (IArray 1 a)` for rank 2 because a cell per row is "not contiguous, and no linalg op
sees its rank"; "indexed vectors do not imply contiguous storage"; "erased does not mean
constant"; multiplicities live in types; one representation per concept; shards are one runtime
per core (`AGENTS.md`, `proposals/0004-typed-apl/README.md`, `proposals/0005-shards.md`). Items below are
conjecture unless they restate a source.

1. **A ragged array is one flat buffer plus offsets and lengths, not a cell per row.** Store
   (offsets, lengths) as DPH's `Segd` does (lengths plus their scan, `code/dph/.../USegd.hs`
   lines 37–41), derive flags only where a scan needs them, and never use head-flags alone (they
   cannot say "empty", `Ble90.pdf` p. 68). This is the missing representation behind 0004's
   rejected nested rank 2: the regular case is one memref with a stride; the irregular case is a
   data memref and two index memrefs, which `linalg` and `scf.forall` can still traverse.
2. **Columnar arrays of data types, generated from the type.** An array of records is a record of
   arrays; an array of a sum is a tag vector (with cached per-constructor indices) plus one array
   per constructor; a nullary constructor costs only a count (`pure-funs.ps` Fig. 3a;
   Harnessing pp. 393–395, 404). Generate it from one description of the constructor shape, as
   GHC's `Generic/Description.hs` does, and do not keep a second hand-written copy (AGENTS' one
   representation rule).
3. **Uniformity is an SSA question MLIR already answers.** A value defined above a parallel
   region is invariant in it; an array whose size operand is defined inside is non-uniform
   (`amir-msc-thesis.pdf` §2.2.3). In MLIR this is region dominance, so the regular/irregular split
   needs no new analysis on the Idris side. Idris types may say more (a `Vect n` with `n` bound
   outside), but an erased index is not a constant, so the size must still be a runtime operand.
4. **Flatten data, not control, on CPUs.** With shards on cores and a single-thread-first rule,
   data-only flattening (`ppopp13-flat.pdf`) matches better than vectorising control: keep loops and
   recursion as `scf`, store nested data flat, and use segmented reductions as kernels.
5. **Never materialise replication.** Read a free variable through the segment index (`is[II1[p]]`)
   or share segments through a segmap; keep `replicate` O(length) (`amir-msc-thesis.pdf` §4.1;
   `icfp60-lippmeier.pdf` §4). In MLIR this is a gather from the original memref inside the
   consumer's region, not a copy.
6. **Vectorisation avoidance by default.** Scalar statements stay inside one `linalg.generic`
   body; only a statement that contains inner parallelism is distributed (`vect-avoid.pdf`;
   `amir-msc-thesis.pdf` §4.2). The existing `idr.array.generate` with a nested fold already has
   this shape.
7. **Decide degree of parallelism at run time.** Multi-version a nest behind size predicates, as
   incremental flattening does, rather than fixing it with a static heuristic
   (*(xref)* `henriksen-2019-incremental-flattening/paper.pdf`); a `scf.if` on sizes.
8. **Trees for the self-hosted compiler as tables.** Level-by-level storage
   (`tflat.ps` §3.2), parent vectors (*(xref)* Co-dfns `D2P`) or Euler-tour v-trees
   (`Ble90.pdf` §5.2) turn tree passes into scans and gathers over flat arrays; this fits the
   compiler's recent moves to `Linear.Array` tables.
9. **Linearity licenses the in-place steps.** NESL avoided copies on update by reference counts
   at run time (`CMU-CS-93-112.ps` §3.3); idris-mlir has quantity 1 in types, so the flat buffers
   of a linear nested array can be updated in place with no test. Flattening must carry
   `!idr.lin` through to the component arrays.
10. **State the cost model and test it.** NESL's work/depth rules, including the free-variable
    term, are a checkable property: a test can assert that a flattened program's work is within a
    constant of the source's on inputs where replication would blow up (`Nesl3.1.pdf` §1.5,
    App. C).

## 7. What idris-mlir should avoid

- **Full higher-order vectorisation as the default.** DPH's record (§5 above).
- **Representations that cannot express sharing**, so that replication copies
  (`icfp60-lippmeier.pdf` §3).
- **Recovering asymptotics with rewrite rules or fusion** (`icfp60-lippmeier.pdf` §6.1;
  `vect-avoid.pdf` §1): a cost guarantee must come from the representation and the lowering.
- **Lifting lazy code** (Harnessing §6.5): Idris is strict, but `Lazy` and `Inf` arguments must
  not be forced by a lifted operation.
- **Arrays of arbitrary closures.** If closures appear in parallel arrays, they must be array
  closures (one code, an array of environments, `ho-flat.ps` §3); mixing different functions
  serialises (§4).
- **32-bit segment indices** where virtual sizes can exceed them (`icfp60-lippmeier.pdf` §5.4.1).
- **Losing the regular case.** A pass that makes a nest irregular loses the workgroup/tiled
  version (`amir-msc-thesis.pdf` §8.1, `lud`); regular nests must stay `linalg` with their rank.

## 8. Limits

- **Not stored, not read:** Blelloch and Sabot, JPDC 8 (1990), the original flattening paper
  (Elsevier, no open copy; DOI 10.1016/0743-7315(90)90087-6); Keller's thesis (TU Berlin 1999);
  Leshchinskiy's thesis (TU Berlin 2005, on DepositOnce); the unabridged "Flattening trees" (TU
  Berlin 98-6) and Lippmeier's TR UNSW-CSE-TR-201208; Riely and Prins on containment; Blelloch
  and Greiner, ICFP 1996 (provable time and space for NESL); Bergstrom and Reppy, ICFP 2012
  (NESL on GPUs); Sevald-Krause's BSc thesis (2023); Blelloch's "Prefix sums and their
  applications" (on the author page, covered by the book's §3–4). Claims about them are second
  hand.
- **Evidence quality.** NESL's numbers are 1993 hardware; DAMP 2007 and FSTTCS 2008 measure
  hand-vectorised code or none; Lippmeier's are single-threaded; the DPH benchmark page is a
  2010 wiki snapshot; Hashemi's is a student thesis, not peer reviewed, on one GPU per experiment
  with untuned thresholds. Nothing was measured here.
- **Copies.** The JPDC 1994 article is a scan without text; it was checked visually and the claims
  cite the technical report. Three DPH-era papers are preprints from the Wayback Machine; the
  ICFP 2000 copy is the camera-ready.
- **Cross-check for the apl-lineage material:** `D2P` and `P2D` are defined in
  `code/co-dfns/cmp/util.apl` lines 47–48, not in `cmp/global.apl` as `code/co-dfns/SNAPSHOT.md`
  and the apl-lineage notes say.
- **Futhark's flattening code** was read only in its header and lifted representation; the
  incremental-flattening paper only in its framing and conclusions.
