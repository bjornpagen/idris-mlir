# Notes: packed and serialized tree representations (cluster `packed-trees`)

Read 2026-10-09. Every stored source below was read in full (prose, figures, tables; for the
code, the pass headers, design notes and the data definitions named). Paths are relative to
`sources/` as staged. Section numbers are the papers' own; "TR" is the LoCal technical report.

| Short | Stored path | What it is |
| --- | --- | --- |
| Gibbon-17 | `papers/vollmer-2017-packed-tree-transforms/LIPIcs.ECOOP.2017.26.pdf` | first Gibbon: fully serialised pre-order trees, traversal effects, end witnesses, destination cursors |
| LoCal | `papers/vollmer-2019-local/paper.pdf`, `papers/vollmer-2019-local/TR741.pdf` | location calculus; offsets and indirections; region runtime (TR App. C); formal semantics and proof (TR App. D) |
| ParLoCal | `papers/koparkar-2021-efficient-tree-traversals/ms.tex` (+ `appendix.tex`, `gibbon_table.tex`) | parallel location calculus; region-upon-steal; fragmentation |
| GC-24 | `papers/koparkar-2024-mostly-serialized-gc/paper.pdf` | generational GC for mostly serialised heaps |
| CNF | `papers/yang-2015-compact-normal-forms/ezyang15-cnf.pdf` | GHC compact regions; `code/ghc/rts/sm/CNF.c`, `code/ghc/libraries/ghc-compact/GHC/Compact.hs` |
| Marmoset | `papers/singhal-2024-marmoset/` (`intro.tex`, `overview.tex`, `design.tex`, `eval.tex`) | choosing field order of packed constructors from access patterns |
| Allais | `papers/allais-2023-serialised-data/` (`desc.tex`, `hexdump.tex`, `pointers.tex`, `poking.tex`, `serialisation.tex`, `timing.tex`, `limitations.tex`, `*.idr.tex`, `*.csv`) | Idris 2 library: serialised data with erased-tree-indexed pointers |
| Gibbon code | `code/gibbon/` (pin `41e650f1`) | the passes and runtime, cited by file |

Cross-links already in the library: `papers/bernardy-2018-linear-haskell/hlt.tex` §"Computing
directly with serialised data" (the `Packed`/`Needs` linear write-pointer API that Gibbon-17's
cursor types mirror); `papers/reinking-2021-perceus` and `papers/lorenzen-2023-fp2` (the
reference-counting and in-place reuse that a packed representation competes with);
`papers/johansson-2002-heap-architectures` (copying messages between heaps, the setting of CNF).

## 1. Definitions and the representation

- **Packed (serialised) tree.** A pointer-free pre-order serialisation: a one-byte tag per
  constructor followed immediately by its fields, children inline; the C tree of Fig. 1 takes 96
  bytes as structs, 29 packed (24 data + 5 tag bytes), so the spine shrinks from 72 bytes to 5
  (Gibbon-17 §1, Fig. 1). A list of 100 `Cons Int` cells is 901 contiguous bytes (GC-24 §1 fn. 1).
  Traversal in serialisation order is a linear scan (Gibbon-17 §1; LoCal §2 Fig. 1 `sumPacked`).
- **Packed tree = dense CNF.** A CNF is the transitive closure of a value with no escaping
  pointers stored contiguously; a packed tree is the same closure with no pointers at all.
  CNF keeps object layout (code unchanged); packing changes layout and so requires rewriting the
  code (Gibbon-17 §1).
- **Location (not region).** A symbolic exact start address of one value; no two constructors
  share a location; a region is a buffer that holds many (Gibbon-17 §4.1; LoCal §3). Locations
  are introduced only relative to others: `start r`, `l + 1` (after the tag), `after (T@l)`
  (after a whole value); no arithmetic (LoCal Fig. 2; ParLoCal §2.1).
- **End witness.** A pointer to the end of a value = the start of the next field; at runtime
  just a pointer (Gibbon-17 §4.1, §4.3). LoCal abstracts layout behind the end-witness judgement
  `τ;⟨r,is⟩;S ⊢ew ⟨r,ie⟩` (LoCal §3.3; TR App. D.5.1).
- **Traversal effect.** `traverse(α)`: the function reads every byte of the value at α and so can
  return its end witness. `case` is the only expression that induces it (LoCal §4.1).
- **Cursor types.** `Has([A,B])` read cursor, `Needs([A,B],C)` linear write cursor, `End(l)`;
  `write :: (Needs(a:rst,b), a) -> Needs(rst,b)`, `read :: Has(t:rst) -> (Has(rst), t)`,
  `finish :: Needs([],T) -> Has([T])` — session-type-like protocols, still a pure language
  (Gibbon-17 §4.3–4.4). The same `Packed`/`Needs` API appears in Linear Haskell
  (`papers/bernardy-2018-linear-haskell/hlt.tex`, "Writing serialised data").
- **LoCal typing.** `Γ;Σ;C;A;N ⊢ A';N'; e : τ@l^r`: Σ materialised locations, C how locations
  relate, A per-region allocation pointer, N nursery of allocated-but-unwritten locations
  (removed on write: written exactly once). Allocating the right subtree before the left is
  materialised is a type error; destination passing is enforced by `l' ≠ l` premises (LoCal
  §3.2, Fig. 4, Table 1). Type safety by progress and preservation over a store typing with
  three invariant families: allocation order follows C, every materialised location has an end
  witness, each address written once (LoCal §3.3.1; TR App. D.5–D.6).

## 2. When a tree can be packed

- **No sharing, unique destination.** Each constructor result and each call returning packed
  data must flow to one destination; sharing (`let x = f t in Node x x`) or two fixed locations
  unifying (`if _ then x else y` at packed type) yields ⊤ in the location lattice (Gibbon-17
  §4.1–4.2). Repair: inline, or copy (`Node x (copyTree x)`) (Gibbon-17 §4.2); in LoCal-era
  Gibbon, an indirection constructor `I (Ind T)` added to every datatype instead: `id x = I x`,
  `let x = _ in Node x (I x)` (LoCal §5; ParLoCal §4.3 `IndPtr`; `code/gibbon/gibbon-compiler/src/Gibbon/Passes/RemoveCopies.hs`
  turns `copy_T` calls into `IndirectionE`). Scalars are always copied (ParLoCal §4.3).
- **Fixed versus fresh locations.** Function parameters and pattern-bound fields have fixed
  locations; constructor sites have fresh ones; only fresh ones unify; two fixed unifying means
  an indirection or copy is needed (LoCal §5; header of
  `code/gibbon/gibbon-compiler/src/Gibbon/Passes/InferLocations.hs`, "Basic Strategy", "Program
  repair"). Every function is first given distinct input and output regions (`convertFunTy`,
  same file), and the type system forbids `f [lx lx]` (ParLoCal §2.1).
- **Traversal order.** Fully serialised data favours whole-tree, in-order traversals: maps and
  folds over ASTs (Gibbon-17 §6.2). Out-of-order access costs extra traversal: `rightmost` on a
  height-12 tree ran 150× slower packed than with pointers (Gibbon-17 §6.1 "Pathological
  cases"); a misaligned post-order traversal of a pre-order tree ran about 35× slower than
  aligned (Marmoset `eval.tex` AddOneTree).
- **Payload density.** The gain shrinks as leaves carry more scalar words (Gibbon-17 Fig. 6).
- **Allocation order.** In-order allocation (`mkList`) packs; out-of-order allocation
  (accumulator `reverse`, building the right subtree first) puts each cell in its own region
  linked by indirections — "a traditional linked list", 4× slower than the pointer version in
  legacy Gibbon (GC-24 §2, Figs. 2–3). Cons-heavy code (`coins`) was the one benchmark where
  Parallel Gibbon lost to MPL, OCaml and GHC (ParLoCal §5.3).
- **Acyclic only.** LoCal builds DAGs, never cycles; a pure strict language cannot create heap
  cycles (LoCal §6; ParLoCal §4.7).
- **Closed world.** Representation selection needs the whole program, like MLton; alternatives
  are programmer annotations or conservative random-access info at compilation-unit boundaries
  (ParLoCal §4 footnote).

## 3. How traversals compile (the Gibbon pipeline)

Gibbon-17's five steps (§4): (1) infer traversal effects, (2) insert traversals where an end is
missing, (3) route end witnesses as extra returns, (4) destination-cursor-passing style, (5) C.

- **Effect inference** is a whole-program fixpoint that starts with every function traversing
  every packed input and shrinks monotonically (Gibbon-17 §4.1;
  `code/gibbon/gibbon-compiler/src/Gibbon/Passes/InferEffects.hs`, `initialEnv`, `fixpoint`). It is
  optimistic: it assumes dummy traversals will be inserted (Gibbon-17 §4.1).
- **Routing end witnesses**: `add1 :: Tree_α → (End(α̂), Tree_β)`; `let start_y = end_x`;
  static-size fields at `start + offset`; the end of the last field is the end of the value;
  bindings may name not-yet-bound ends, fixed by a reordering pass; source order is irrelevant
  (`sum1`/`sum2`) (Gibbon-17 §4.3; `code/gibbon/.../Passes/RouteEnds.hs` header steps 1–3;
  `Passes/FindWitnesses.hs` header explains the reorder).
- **Destination cursors**: every constructor/call returning packed data gets a destination;
  functions take output cursors and return end cursors; `switch` reads one tag byte and binds a
  cursor to the fields (Gibbon-17 §4.4). Locally a packed value is "dilated" to a
  `(start,end)` pair because conditionals need to return extra end state; calling conventions do
  not change, call sites mediate (Gibbon-17 §4.4; `code/gibbon/.../Passes/Cursorize.hs` header,
  "Cursor insertion, strategy one").
- **Codegen**: unarise tuples, cursors become `char*`, read/write are pointer ops, C in SSA form
  (Gibbon-17 §4.5). LoCal lowers to NoCal (`readTag`, `readInt`, `readCursor`, `writeTag`, …),
  where writes can be reordered into memory order because only location data dependencies order
  them (LoCal §4.4, Fig. 7).
- **Checked IR between passes**: LoCal runs full region/location type checking between every
  pair of LoCal→LoCal passes (LoCal §4); the current pipeline calls `L2.tcProg` after almost every
  pass (`code/gibbon/gibbon-compiler/src/Gibbon/Compiler.hs` lines 690–848).
- **Current pass order (packed backend)**: `inferLocations` → `regionsInwards` →
  `simplifyLocBinds` → `reorderLetExprs` → `fixRANs` → `L2.flatten` → `removeCopies` →
  `inferEffects` → either `addTraversals` (Gibbon1/no-RAN) or `addRAN` on the *L1* program and
  location inference again, then `findWitnesses`, `removeCopies`, `inferEffects`,
  `addTraversals` → `parAlloc` → `inferRegScope` → `writeOrderMarkers` → `routeEnds` →
  `inferFunAllocs` → `addRedirectionCon` → `followPtrs` → `fromOldL2` → `threadRegions2` →
  `hoistBoundsCheck` → `cursorize` → `reorderScalarWrites` → L3 → `unariser` → `lower` (L4)
  (`code/gibbon/gibbon-compiler/src/Gibbon/Compiler.hs`, with Note [Repairing programs]).
- **Region scope**: a region whose value escapes is global, else dynamic, decided by a path from
  the `letregion` to the result; all regions are "infinite" (growable)
  (`code/gibbon/.../Passes/InferRegionScope.hs`, "Region scoping rules"). Region multiplicities
  `Bounded n | Infinite | BigInfinite` exist in the IR (`code/gibbon/.../L2/Syntax.hs`,
  `Multiplicity`).
- **Region and end-of-chunk threading**: calls get region cursors prepended; output regions are
  threaded like output locations because a callee may move to a new chunk
  (`code/gibbon/.../Passes/ThreadRegions2.hs` header).
- **Typed library alternative (Idris 2)**: Allais gets the same "seamless" programming without a
  compiler: `Pointer.Mu cs t` is a record `{muBuffer : Buffer; muPosition : Int; muSize : Int}`
  with phantom description `cs` and an erased (quantity 0) tree `t`; a trusted core (`poke`,
  `out`, `(#)`, `copy`, `execSerialising`) reflects buffer reads into the index; `layer`, `view`,
  `fold`, `deserialise` are then correct by construction and return `Singleton (Data.sum t)` etc.
  (Allais `pointers.tex`, `poking.tex`, `bufferfold.tex`, `limitations.tex`;
  `SaferIndexed.idr.tex` blocks `pointermu`, `csum`). The universe is
  `Desc (rightmost : Bool) (static : Nat) (offsets : Nat)` with `None`, `Byte`, `Prod`, `Rec`
  (`Rec : Desc r 0 (if r then 0 else 1)`), at most 255 constructors (Allais `desc.tex`;
  `Serialised/Desc.idr.tex` blocks `desctype`, `desc`).

## 4. Indirections and random access

- **Dummy traversals** (Gibbon1): a synthesised `traverseTree y` to reach a later field —
  "dead code with the correct location" — simple and linear, but can turn O(log n) into O(n)
  (Gibbon-17 §4.2, §7.1; `code/gibbon/.../Passes/AddTraversals.hs`).
- **Layout information** (Gibbon-17 §7.1): pointer-style indirection (size of the left subtree,
  to jump to the right child) and rope-style (size of all children, to truncate a traversal).
  Not needed for the first child; only on constructors whose traversals skip; offsets, not
  64-bit pointers. Proposed encodings: `NodeTag <size_left> <left> <right>` with 4-byte sizes,
  or UTF-8-style variable-length (Gibbon-17 §2.1.2).
- **LoCal offsets and indirections** as datatype annotations: `data T = K1 T (Ind T) | K2 T
  (Offset T) | K3 T`; offsets allocated with the tag; `case` uses an offset instead of the
  end-witness rule; type safety extends straightforwardly (LoCal §3.4). The compiler adds a
  4-byte relative offset after the tag for each field used but not reachable; adding random
  access invalidates inferred locations, so the compiler backtracks to before find-traversals —
  at most once, since adding random access to one type never enlarges the set needing it (LoCal
  §4.2). Implemented by adding a `Node^` constructor with a `CursorTy` RAN field to the *L1*
  program and rerunning location inference; old clauses are kept so a size threshold can still
  prefer dummy traversals (`code/gibbon/.../Passes/AddRAN.hs` header, "Adding random access
  nodes", "When does a type 'needsRAN'", "Keeping old case clauses around").
- **Whole-program cost of random access**: one function demanding random access changes the
  representation for every function using that type; datatypes are not duplicated
  automatically (LoCal §4.2). `repMax = propagateConst (findMax t) t`: offsets keep `findMax`
  logarithmic but slow `propagateConst`; together 480 ms versus under 440 ms apart (LoCal §7.2).
- **Tag budget**: indirection, random-access and end-of-chunk tags share the 256 one-byte tags
  (TR App. C fn. 6). The runtime reserves 255 redirection, 254 indirection, and 253–250 for the
  collector (cauterised, copied-to, copied, scalar)
  (`code/gibbon/gibbon-rts/rts-c/gibbon_rts.h`). Allais caps constructors at 255
  (`desc.tex`, `fitsInBits8`).
- **Allais's format** stores an 8-byte offset for every argument whose size is not static
  except the rightmost, after the tag: node = tag, `o` offsets, then interleaved subtrees and
  `s` bytes; units occupy nothing and pair nesting is invisible; a header carries the encoded
  description for a load-time check (Allais `desc.tex` "Interlude", `hexdump.tex`). Offsets are
  relative, so a subtree is copied with one `copyData` of a buffer slice (Allais
  `serialisation.tex` "Copying Entire Trees").
- **Choosing field order instead of pointers** (Marmoset): a field-access graph from the CFG
  (uniform branch weights) and def-use chains; data-flow edges are rigid, control-flow edges
  allow let code motion; attributes scalar/recursive/self-recursive/inlineable; an ILP with
  costs `Csucc < Cafter < Cpred < Cbefore` (inverted when the target field is inlineable) and
  objective `Σ c_e p_e`, or a greedy walk; per-program global layout by summing all functions'
  constraints (Marmoset `design.tex` §3.2–3.7). Putting a list's tail before its payload
  (`Cons' List' Int`) gives a structure-of-arrays effect: tags contiguous ("a unary encoding of
  array length"), payloads contiguous (Marmoset `design.tex` "Structure of arrays").

## 5. Mutation

- None of the Gibbon systems mutates packed data in place; inserting into an immutable packed
  tree writes new nodes into a fresh buffer pointing back with indirections (Gibbon-17 §8;
  LoCal App. A.1 `treeInsert`: a log-size output of 677 bytes). Cap'n Proto's destructive insert
  is the only in-place variant measured (LoCal Table 2 `insertDestr`).
- Parallel Gibbon adds mutation only for arrays of scalars, through a Linear Haskell
  `inplaceUpdate :: Int -> a -> Array a ⊸ Array a`; in-place update of densely encoded algebraic
  data is future work (ParLoCal §4.6, §7; LoCal §8).
- Allais: no in-place update; whether the linear quantity could make it safe "remains to be
  seen"; `map` over a buffer costs about the same as deserialise+map+serialise (Allais
  `limitations.tex`, `timing.tex` "Traversing the Full Tree").
- CNF admits only immutable, fully evaluated data; mutable objects, functions and pinned byte
  arrays raise `CompactionFailed`; immutability is what keeps a compact self-contained (CNF
  §3.1; `code/ghc/libraries/ghc-compact/GHC/Compact.hs` haddock; `code/ghc/rts/sm/CNF.c` Note
  [Compact Normal Forms], invariants (1)–(2)).
- GC-24's collector relies on immutability: the remembered set never shrinks, chains of
  indirections can be short-circuited, old-to-old pointers need no barrier beyond refcounts
  (GC-24 §3.3 fn. 5, §3.5).

## 6. Parallel traversal

- Reads in parallel need offsets to the later children; without them the traversal is
  necessarily sequential (ParLoCal §2.2). Writes to different regions are trivially parallel;
  writing fields of one constructor in parallel needs the `after` dependency broken (§2.2).
- **Region-parallel LoCal**: every `let` may run in parallel with its body; at most one task
  allocates per region; the parent sees an I-var for the child's start; `after` on an I-var
  location yields an indirection to a fresh region, joined later by writing one pointer (the
  `linkFields` metafunction makes a linked list of field regions); merges only add information,
  so joins are deterministic (ParLoCal §3.1–3.2). Type safety proved for task sets: every I-var
  supplied by exactly one other well-typed task; stores of tasks remain well formed across
  merges (§3.3–3.4, `appendix.tex`). Mechanically tested in PLT Redex (§3.2).
- **Implementation**: parallel tuples desugar to spawn/sync (series-parallel only, no futures);
  `ParAlloc` turns `letloc l2 = after x` for a spawned `x` into a fresh region tied back after
  `sync` (ParLoCal §4.2, §4.5; `code/gibbon/.../Passes/ParAlloc.hs` header). Fresh regions are
  made only when a steal happened (compare Cilk worker IDs before the spawn and in the
  continuation): fragmentation proportional to actual, not potential, parallelism (§4.5).
- **Granularity drives representation**: serialising only the bottom two levels of a binary tree
  removes 75% of pointers, leaving pointers 11% of memory; choose task granularity and the data
  representation follows (ParLoCal §4.1). Hand-written forerunner: packed `add1` with
  pointer-style indirections and a Cilk spawn cutoff at depth 5 (Gibbon-17 §7.2.1).
- Allais names parallelism as untapped and ParLoCal as the model to follow (Allais
  `timing.tex`, `related-work.tex`).

## 7. Measured results

| Claim | Number | Source |
| --- | --- | --- |
| packed vs bump-allocated pointers, `add1` | 1.75× geomean; 18× vs malloc; pointer version uses 6× memory | Gibbon-17 §6.1, Fig. 5 |
| packed vs GC'd languages, microbenchmarks | up to 100× | Gibbon-17 §6.1, Fig. 4 |
| Racket AST passes beyond cache | fold 2.5–3×, map 2× (small trees: pointers fine) | Gibbon-17 §6.2, Fig. 7 |
| Racket corpus size | 1 GB source, 485 MB stripped, 102 MB packed | Gibbon-17 §6.2 |
| hand-written parallel packed `add1`, 16 cores | ~11× self-relative; 34× faster than GHC on 1 core, 223× on 16 | Gibbon-17 §7.2.1, Fig. 9 |
| kd-tree point correlation with rope indirections | 56% less memory; up to 35% faster | Gibbon-17 §7.2.2 |
| LoCal (Gibbon2) geomean | 202× / 2.6× / 3.2× / 17.9× faster than Gibbon1 / NonPacked / CNF / Cap'n Proto; 0.96 / 2.6 / 3.2 / 9.8× on equal asymptotics | LoCal §7.2, Table 2 |
| asymptotic repairs | `rightmost` 175 ns vs 56 ms; `treeInsert` 0.87 µs vs 0.38 s; `id` 2.1 ns vs 0.32 s | LoCal Table 2 |
| sizes, binary tree 2^25 leaves | 335 MB packed vs 1.34 GB CNF vs 1.61 GB Cap'n Proto; 603 MB with offsets | LoCal Table 2 |
| Twitter hashtags from disk | 9.1M tweets in 0.39 s; 6× / 12× over RapidJSON lexer / parser; 257 MB vs 2117 MB (CNF) vs 735 MB (Cap'n Proto) per GB of JSON | LoCal §7.3, Fig. 8 |
| Racket ASTs from disk | 131 ms vs 71.1 s Racket `read`: 543×; 7.1× discounting IO | LoCal §7.4 |
| Parallel Gibbon, 48 threads | 31.7–43.5× over sequential Gibbon for most; single-thread overhead mostly < 3% | ParLoCal §5.2, `gibbon_table.tex` |
| Parallel Gibbon vs others | 1 thread 1.93× / 2.53× / 2.14×; 48 threads 1.92× / 3.73× / 4.01× vs MPL / OCaml / GHC | ParLoCal §1, §5.3 |
| fragmentation cost | 3.03–6.75% (geomean 4.74%) slower later traversal with region-upon-steal; 476.9% geomean with region-upon-spawn and no granularity control | ParLoCal §5.2, fragmentation table |
| GC-Gibbon small allocations | 3.79× / 0.46× / 1.09× vs legacy Gibbon / GHC / Java; memory 47% of legacy | GC-24 §5.1, Tables 1, 3 |
| GC-Gibbon bulk traversals | 1.02× / 2.19× / 1.5× vs legacy / GHC / Java | GC-24 §5.1, Table 2 |
| CNF serialisation, bintree 2^23 leaves | 0.322 s vs 6.929 s Binary vs 12.72 s Java; size 320 MB vs 80 MB Binary (4× expansion) | CNF Tables 1–2 |
| CNF mmap | 21.3× faster full load of 1 GB; one middle tweet 0.26 s vs 26.6 s | CNF §5.4 |
| Marmoset | 1.14–54× over Gibbon; 1.6–38× over MLton; `ListLength` 62.34 s → 1.50 s | Marmoset `intro.tex`, `eval.tex` |
| Allais (Idris 2, Chez backend), depth 20 | `rightmost` 445 ms deserialise-then-run vs 14.8 µs on buffer; `swap` 793 ms vs 17.5 ms with slice copy; `sum` and `map` about equal | Allais `rightmost.csv`, `swap.csv`, `sum.csv`, `map.csv`, `timing.tex` |

## 8. Memory management of packed data

- **Regions as chunk lists**: constant-size first chunk, doubling (to 1 GB, then 1 GB chunks);
  locations are interior pointers; metadata in a *footer* so the payload grows towards it and the
  chunk end doubles as the bounds check; a reserved end-of-chunk tag links chunks (TR App. C;
  ParLoCal §4.7; GC-24 §2 Fig. 1). LoCal's growable regions start at 64 KB and pay bounds checks
  that Gibbon1's huge guard-paged regions avoid (LoCal §7.2 fn. 5; TR App. C).
- **Region-level reference counts**: `letregion` sets 1, exit decrements; inter-region pointers
  are immutable, so instead of a remembered set each chunk records an outset "chunk A points to
  region B"; freeing a chunk decrements the regions it points to; one live chunk keeps the whole
  region (TR App. C; ParLoCal §4.7). No backup tracing collector (ParLoCal §4.7).
- **Generational GC for mostly serialised heaps** (GC-24): young generation of bump-allocated
  regions, minor collections copy (compacting, inlining young indirection targets) into old
  regions with deferred region refcounts (§1, §3). Pretenuring: the first chunk of a region is
  young, later chunks old (§3.3). Partially written objects are cauterised at every live
  allocation cursor; construction resumes in the old generation, so a write barrier records
  old-to-young indirections (§3.3, §3.5). Minimal indirections after collection (Def. 3.1) by
  bumping the young allocation pointer downwards and evacuating roots in address order (§3.1).
  Sharing kept by forwarding where 9 bytes fit and "burning" (one-byte tag) where not, with
  bounded rightward scans and interval tables as slow paths (§3.4;
  `code/gibbon/gibbon-rts/rts-ng/src/notes.md`). Pointer encoding: the offset to the chunk footer
  in the 16 high bits of a 48-bit pointer, capping chunks at 65 KB (GC-24 §4;
  `GIB_TAG_BITS`/`GIB_MAX_CHUNK_SIZE 65500` in `code/gibbon/gibbon-rts/rts-c/gibbon_rts.h`).
  A static analysis bounds region sizes to avoid 1 KB regions holding one cons cell (GC-24 §4).
- **CNF**: a compact is a chain of blocks treated by the GC as one object: never traced, kept
  alive whole by any pointer into it; membership found in O(1) from the block descriptor;
  appending is a Cheney copy that uses the compact as its scan queue; sharing not preserved by
  default (hash table 1.5–2× slower in the paper, "10x slower" in today's haddock); "GC" by
  copying into a new compact (CNF §3.2, §4.2–4.3; `code/ghc/libraries/ghc-compact/GHC/Compact.hs`;
  `code/ghc/rts/sm/CNF.c` Note [Compact Normal Forms]). Import adjusts pointers unless loaded at
  the original address; info pointers trusted by binary checksum (CNF §4.4).

## 9. What idris-mlir should take

1. **A layout fact belongs in the type.** LoCal's located types `T@l^r`, its nursery
   discipline and its `Ind`/`Offset` datatype annotations make the layout something every pass
   must keep and a checker can verify between passes (LoCal §3.2, §3.4, §4). This is the shape
   AGENTS.md asks for (`!idr.lin`, `!idr.erased` checked after every pass): a packed
   representation would be a type (a packed type with its per-field offset/indirection choice),
   not a discardable attribute, and a verifier would check location order like `L2.tcProg` does
   (`code/gibbon/gibbon-compiler/src/Gibbon/Compiler.hs`).
2. **End witnesses are SSA values.** Gibbon's routing of end-of-value pointers as extra returns
   and the "dilated" `(start,end)` convention (Gibbon-17 §4.3–4.4; `Cursorize.hs` header) map onto
   multiple results and block arguments; no reordering pass like `FindWitnesses` should be needed
   when dominance is checked by MLIR (conjecture).
3. **Destination passing with linear write cursors.** `Needs`/`Has` are linear protocols in a
   pure language (Gibbon-17 §4.4; `papers/bernardy-2018-linear-haskell`). Idris already has the
   quantity 1 needed to state them in a trusted library (Allais `limitations.tex`) or, in the
   compiler, as `!idr.lin` cursors.
4. **Representation chosen by the compiler from access patterns, repair before refusal.**
   Default to dense; add per-constructor offsets only for fields some function cannot reach in
   order; prefer reordering fields (Marmoset) to adding pointers; keep a copy/indirection
   repair for sharing (LoCal §4.2, §5; Marmoset `design.tex`). Idris's whole-program view after
   monomorphisation is the same closed world Gibbon relies on (ParLoCal §4 footnote).
5. **Relative offsets, not absolute pointers, inside a packed value**, so a subtree is a byte
   slice that copies with one memcpy and can be written to disk or a message unchanged (Allais
   `serialisation.tex` "Copying Entire Trees"; LoCal §3.4). This fits proposal 0005's "values
   cross only inside messages" (`proposals/0005-shards.md`): a packed value is already a
   message (conjecture).
6. **Granularity decides representation in parallel code**: fresh region only on steal;
   serialise below the task cutoff (ParLoCal §4.1, §4.5). Relevant to shards (`proposals/0005-shards.md`; conjecture).
7. **Region-level counting fits the existing counted runtime.** A packed value is one counted
   cell with an outset of the regions it points into (TR App. C), so it should slot under
   `runtime/Rc` reference counting without a tracing collector (conjecture); CNF shows the same "one object
   to the memory manager" stance from the GC side (CNF §4.2).
8. **Allais as a test program.** It is plain Idris 2 over base's `Data.Buffer` (`newBuffer`, `getBits8`,
   `setBits8`, `getInt`, `setInt`, `copyData`, `createBufferFromFile`, `writeBufferToFile` in
   `SaferIndexed.idr.tex`), which AGENTS.md makes runtime primitives; its erased indices and
   `Singleton` results are exactly the quantity-0 facts idris-mlir must keep; its own limitation
   "generic programs are not specialised and partially evaluated" (Allais `limitations.tex`) is
   what idris-mlir's specialisation and compile-time evaluation passes exist to remove.

## 10. What idris-mlir should avoid

- **Tagged pointers.** Gibbon packs a 16-bit footer offset into the high bits of 48-bit
  pointers and caps chunks at 65 KB because of it (GC-24 §4; `gibbon_rts.h`). AGENTS.md requires
  heap references to stay raw, untagged addresses; keep chunk metadata findable another way
  (aligned chunks, side tables).
- **Dummy traversals as the default repair**: they change asymptotic complexity silently
  (Gibbon-17 §6.1, 150×; LoCal Table 2). If a layout cannot give an access its complexity, add an
  offset or report it; never miscompile silently, and never degrade asymptotics silently.
- **A second copy of the layout.** Gibbon adds random-access nodes to the L1 program and reruns
  location inference, keeping old case clauses alongside (`AddRAN.hs` header); offsets live in
  datatype definitions *and* inferred locations. AGENTS.md's one-representation rule asks for
  the layout to be stated once and the rest derived.
- **A collector linked as a shared library.** GC-Gibbon's Rust collector is a `cdylib` linked to
  the generated C (GC-24 §4); everything here links statically.
- **Fixed 4- or 8-byte offsets everywhere** without measurement: Allais stores 8 bytes per
  non-rightmost recursive field; LoCal's offsets nearly doubled `rightmost`'s input (335 MB →
  603 MB, LoCal Table 2).
- **Assuming linearity implies a packed buffer is owned.** AGENTS.md: "A linear binder does not
  imply unique heap ownership." Gibbon's in-place array update rests on Linear Haskell
  (ParLoCal §4.6); in idris-mlir the uniqueness of a packed buffer would have to come from
  `idr-rc`'s counts, not from the binder.
- **Unchecked trust boundaries**: Allais's `readFromFile` postulates the erased tree once the
  header matches and skips bounds checks in the paper (Allais `pointers.tex`); CNF trusts info
  pointers by binary checksum (CNF §4.4). Loading packed data from outside the program needs a
  validating reader, or the unsupported error.

## 11. Limits of the evidence

- All Gibbon results come from a first-order, monomorphic, strict subset compiled whole-program
  to C with GCC, on x86 Xeon/Threadripper machines (Gibbon-17 §6; LoCal §7; ParLoCal §5; GC-24 §5;
  Marmoset §5.1). No ARM or macOS measurement exists; nothing measures Apple's data-memory-
  dependent prefetcher against packed buffers.
- Benchmarks are mostly synthetic balanced trees plus Racket ASTs, Twitter metadata, a blog
  list, kd-trees and a five-pass toy compiler (ParLoCal §5.4); Marmoset itself says "big"
  programs are out of reach because Gibbon lacks modules, FFI and general IO (`eval.tex`
  "Scale of Evaluation"). In the five-pass x86 compiler, most of the run time and of the parallel
  speedup is `assignHomes`, a pass dominated by environment lookups (ParLoCal §5.4).
- Parallel speedups use hand-placed parallel tuples and fixed cutoffs; automatic granularity is
  future work (ParLoCal §4.1, §7). The implementation depends on Cilk; the current README says
  parallelism is "temporarily not available" on Ubuntu 22.04 because newer GCC lacks Cilk
  (`code/gibbon/README.md`).
- GC-24 covers sequential mutators only; old-generation tracing and a parallel collector are
  future work (GC-24 §7). Its chunk cap costs bulk traversals slightly (Table 2).
- Marmoset's speedups compare against Gibbon's own pointer-based fallback; its cost constants
  are "best intuition" and branch weights are uniform (`design.tex` §3.2, §3.6); the solver is
  IBM CPLEX through generated Python (`design.tex` §4).
- Allais measured on the Chez backend of Idris 2 with 25 runs; the absolute times say nothing
  about a native backend; the library lacks buffer growth, sharing and parametrised types
  (`timing.tex`, `limitations.tex`).
- CNF's numbers come from the 2015 prototype in a modified GHC, on 10 GbE and InfiniBand (CNF §5); the hash-table cost of sharing
  has since been documented as 10× (`GHC/Compact.hs`).
- Licences: the Gibbon snapshot has no licence (`code/gibbon/SNAPSHOT.md`); the CNF author copy
  says "Not for redistribution"; LoCal is ACM ©.
