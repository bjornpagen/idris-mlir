<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: effects and the e-graph, checked on real IR

Status: written 2026-10-21. Begun for the owner's "we need to think about
this more" on `unknowns.md` U13 (effectful ops inside the e-graph or in a
skeleton outside it); re-centred, at the coordinator's request, on
checking D103 (`proposals/0000-mlir-native.md:1508-1525`), which the owner
ruled while this ran: effectful ops stay outside the e-graph, in a
skeleton that is a partial order per resource subtree, "c.", resting on
reasoning, "a contradiction returns it to the owner". D106 and D107
(`:1557-1592`) narrow the e-graph to MLIR's own mechanisms in C++,
replacing greedy rewriting on our ops. This file counts, on real IR, what
each design leaves fixed per resource, how much freedom the partial order
gives over one line, whether any real case needs a cost-chosen order on
one resource, and what MLIR's effect interfaces give the skeleton. The
wider design space is kept short (§4).

Grounds: *read* (path:line or URL), *measured* (command and input named;
scripts and raw output in `/tmp/eg-effects/`), *recalled*, *conjecture*,
*decision* (a ruling Dn). Ours at HEAD e96bb991 with the working tree.
Real IR: the modules the frontend emitted on the stock host for 33
programs and for the frontend itself, which `workloads.md` built and left
in `/tmp/eg-workloads/emit/*/module.mlirbc.mlir` (its §1.1); parsed with
its parser (`scripts/mlirparse.py`) and, for "-inl", after its inlining
approximation (`scripts/inline.py`, 64-op callees, 2,000-op callers, its
§1.3). Tools: Python 3 (counting only), Apple clang 21 `-O2` (the
extraction experiment). No MLIR or LLVM tool ran; Homebrew's 22.1.8 was
not used. Machine: Apple M2 Max (virtual), 8 cores, shared, load average
6 to 7, so times are rough and ratios within one run are what to read.

## 0. The verdict on D103, plainly

- **The evidence does not contradict D103's choice.** No real case was
  found that needs a cost-chosen order on one resource (§2.3), and the
  one function hand-lowered with mutable reads, writes and guards gives
  the same program under every design (§3).
- **It contradicts one premise, and that returns to the owner.** D103
  says effect order "cannot be broken by the engine". One order the
  engine can break is not an effect at all: a read of a linear array
  before the in-place write that consumes it. The frontend drops it
  (`LArray.read` gives back the same SSA array, *read*,
  `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr:1570-1578`), so
  in the e-graph the read is a floating `tensor.extract` that placement
  may put after the `tensor.insert`; bufferization reading the grade
  (D71) then reads the overwritten element. 217 such reads in the
  inlined benchmarks (§1.3). D103 holds only with one more rule (§5).
- **D103's freedom is legal and almost never available.** On the
  inlined frontend (5.25 M ops) the partial order frees 21 of the
  224,572 pairs of ordered ops that one line orders (0.009%); 210 (0.09%)
  if `array.get` stops declaring a count write; 13 of 7,193 (0.18%) over
  the 33 programs (*measured*, §2.2). Calls carry their callee's derived
  row, and 92.6% of the frontend's ordered ops write memory and may
  crash at once, so they conflict with everything; 98% of regions hold
  at most one ordered op.
- **D103's reason for rejecting (d) is imprecise, its choice is not.**
  Effect-safe extraction is NP-complete only when effectful terms have
  alternatives; with tokens inside and every effectful rule subsuming,
  each token class has one member and eggcc's statewalk width is 1, so
  extraction is polynomial too (*read*, `07-np.tex`, `06-tiger.tex:467-503`;
  *measured*, §3). (c) still wins on D20 (no world value anywhere), D107
  (MLIR's interfaces give it nearly free, §2.4) and one fact held once.
- **A finding for the coordinator.** `array.get` declares a `Write` on
  `idr.count` (`effect-vocabulary.md:297`, *read*): every two reads
  conflict, and no read is redundant, though counting, which runs after
  the e-graph, places the element's dup as it does for `field` (§1.2).

## 1. What is ordered in our IR, by resource

### 1.1 The census

*measured*, `census.py MODULE inl defunc` (and `raw`): each op classified
by D27's tree from the op table of `effect-vocabulary.md` §3 (world
operands ignored, D20); each function's row derived by a fixpoint over
calls (D22), a function without `total` seeded with `divergence` (D13);
an `idr.apply` or `idr.force` given the union of the rows of every
closure of its callee's type (defunctionalization over the closed
program, an upper bound on what it resolves). An op is *ordered* when
its own, recursive or call effects hold any atom but `alloc` on the heap
or identity. Counts are ordered ops carrying each atom (an op counts
under each it carries).

| input | ops | ordered | crash | divergence | contents | count | io | runtime_state | exit | memo_state |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 33 programs, -inl | 231,520 | 13,315 (5.8%) | 10,351 | 9,670 | 327 | 30 | 636 | 0 | 0 | 0 |
| the frontend, emit | 693,423 | 77,893 (11.2%) | 75,584 | 76,065 | 75,298 | 75,192 | 4,412 | 4,343 | 4,131 | 0 |
| the frontend, -inl | 5,254,168 | 374,344 (7.1%) | 371,441 | 353,546 | 352,379 | 352,259 | 5,161 | 5,092 | 4,857 | 0 |

Which atoms an ordered op carries together (*measured*, same runs):
- **The frontend, -inl**: contents+count+crash+divergence 346,483
  (92.6%); crash alone 19,686; contents+count+crash+divergence+io+exit+runtime_state
  4,787; divergence alone 2,209; contents+count alone 572; contents alone
  47; io alone 40.
- **The 33 programs, -inl**: crash+divergence 6,865; crash 3,108;
  divergence 2,671; io 268; contents+crash+io 216; contents+count+crash
  20; contents alone 7.

What it means:
- **Reads of immutable memory float in every design** and are not in
  the table: strings, bigs, fields, frozen arrays have no resource
  (AGENTS.md:498, *read*). They are most of what the e-graph sees: 43.6%
  to 48.6% of ops float (`workloads.md` §2).
- **Crash and divergence dominate the programs**: partial code and
  failing checks, ordered among themselves in every design (D21: crashes,
  exit and output stay ordered among themselves).
- **The frontend's mutable memory is its IORefs.** `Data.IORef`'s read
  and write are `array.get`/`array.set` on a one-element array (37 and
  35 specializations, *measured* by grep in the emitted module); the
  `Core` monad's actions carry contents and count. They are neither
  quantity 1 nor exclusive, so D61's per-parameter part does not split
  them; all of it is one `contents` resource.
- **memo_state is zero** at this point: memo cells (`memo.run`) are made
  later in the pipeline; `idr.delay`/`force` are closures here.
- **count is not counting.** The e-graph runs before counting
  (`egraph.md` §2.9), so no `dup`/`drop` exists; every count atom here
  is `array.get`'s own declared write (§1.2).

### 1.2 `array.get`'s count write

`array.get` returns "the element ... with a reference of its own"
(`foreign/idr/include/idr/IR/IdrArrayOps.td:309-311`, *read*), so the
vocabulary gives it `Read` on contents and `Write` on count
(`effect-vocabulary.md:297`). Before counting this is a counting decision
carried early: `field` of a cell reads a value counting will dup and
declares no count write (`effect-vocabulary.md:281`). Its cost under any
skeleton: two reads conflict (W/W on count), so reads never pass each
other; a read with a write is not trivially dead, so an unused read
stays; and a repeated read cannot be the first one's value without
dropping an increment. Measured: dropping it raises the frontend's free
pairs from 21 to 210 (§2.2) and, in §3's function, lets every design
remove the repeated read of `p[0]`. Recommended (*conjecture*, for the
coordinator): before counting, `array.get` is a borrowing read with
`Read` on contents only, and counting places the element's dup.

### 1.3 Orders that are not effects: linear arrays

A linear array is a tensor value before bufferization, so its reads and
writes are pure ops (`tensor.extract`, `tensor.insert`) and in no
skeleton. Idris orders them by linearity: `read : (1 _ : LArray s a) ->
Index s -> Res a (const (LArray s a))` (`libs/mlir-array/Array/Core.idr:211`,
*read*). The frontend writes `read l i` as `Res (extract l cs) l`, the
same `l` (*read*, `Terms.idr:1570-1578`); after `lin.use`/`lin.enter`
(`fannkuch-linear`'s `Linear.Vec.read`, *read* in the emitted module) and
the `lin.cast` round trip the e-graph licenses (`egraph.md` §2.3), the
extract and the next insert read one value. Nothing but block order says
the extract comes first.

*measured* (`census.py`, extracts whose array a later op of the region
re-enters or consumes): 58 in fannkuch-linear, 134 in qsort, 15 in
unionfind, 10 in k-nucleotide after inlining; spectral-norm-linear's 75
read frozen arrays and are free. A Cranelift-style elaborator places a
pure node at its first demand (`egraph.md` §1.2), which may come after
the insert. Under One-Shot's analysis that is a copy; under D71's "reads
the grade" it is a read of the new element. The same hazard holds under
a one-line skeleton; D103 did not create it, but its sentence that
effect order cannot be broken does not cover it.

## 2. What each design leaves fixed, and the freedom (c) adds

### 2.1 The designs on our tree

- **(a) one state thread inside** (eggcc, Peggy): every ordered op is an
  e-node on one state; nothing is fixed a priori; extraction must find an
  effect-safe term, NP-complete in general (*read*, eggcc `07-np.tex`).
- **(b) one line per region outside** (Cranelift's skeleton, `egraph.md`
  §2.1): every ordered op of §1.1 in program order.
- **(c) a partial order per resource subtree outside** (D103): the same
  ops, no alternatives; two conflict when their resources are on one
  root path and one writes (`effect-vocabulary.md` §4.1).
- **(d) one quantity-1 token per subtree inside**: §4.
- **Upstream on the conflict**: the pinned MLIR's resources form the
  tree D27 needs (`Resource::getParent`, `isSubresourceOf`,
  `isDisjointFrom`, `mlir/include/mlir/Interfaces/SideEffectInterfaces.h:131-154`,
  *read*).

### 2.2 The freedom, measured

*measured*, same runs: per region, the pairs of ordered ops one line
orders, against those the transitive closure of conflicts in program
order orders.

| input | pairs under (b) | ordered under (c) | free under (c) | free if `array.get` declares no count write |
| --- | --- | --- | --- | --- |
| 33 programs, -inl | 7,193 | 7,180 | 13 (0.18%) | 13 |
| the frontend, emit | 35,088 | 35,068 | 20 (0.06%) | 194 (0.55%) |
| the frontend, -inl | 224,572 | 224,551 | 21 (0.009%) | 210 (0.09%) |

Why so little:
- **Regions are small.** Ordered ops per region in the inlined frontend:
  none 1,586,312; one 191,689; two 59,706; three 10,375; four 2,611; five
  or more 2,625; the largest 82. In the programs: 72,396; 6,496; 1,848;
  591; 58; 177; the largest 10. A case block is a function of its own and
  an IO bind a closure at emit (`workloads.md` §2), and the inlining
  approximation does not inline an action run by a bind.
- **Rows are unions.** A call is ordered by its callee's whole row; a
  call that may crash and writes an IORef conflicts with every other.
- **E11's own sites**: a contents read whose row holds nothing else
  (count aside) occurs 575 times in the inlined frontend and 6 times in
  the programs; one placed after a guard it does not read, 2 and 0.
  `payoffs.md` found no E11 instance in source (`:408`).

These are at emit and approximate inlining; after defunctionalization,
specialization and contification regions grow and rows sharpen
(*conjecture*). §3's function is what a fully inlined loop looks like.

### 2.3 Does any real case need a cost-chosen order on one resource?

- *measured*: regions holding two or more primitive writes of `contents`,
  or two or more primitive IO writes: 0 in the 33 programs and 0 in the
  inlined frontend (primitives stay in their library actions at this
  stage).
- *measured* (§3): in fannkuch-redux's `rev`, fully inlined, the arm's
  two writes are to indices the arm proves distinct; keeping both orders
  changes no cost, and the statewalk DP finds width 1.
- *read*: IO has one order by meaning (D20, D27); crash, exit and output
  stay ordered (D21); a different order on `contents` matters only to a
  cost model that sees memory-level parallelism or store forwarding,
  which LLVM schedules after us.
- **Answer**: none found. D103's claim stands on the evidence available.

### 2.4 What MLIR gives the skeleton, and what our query adds

Given by MLIR (*read*, pinned tree):
- the declarations: `MemoryEffectOpInterface`, ODS `MemRead`/`MemWrite`/
  `MemAlloc`/`MemFree` on a resource and a value, `RecursiveMemoryEffects`
  (a match's effects are its regions'), `ConditionallySpeculatable`;
- the tree and its test: `isDisjointFrom` (`SideEffectInterfaces.h:151-153`);
- queries: `isPure`, `isMemoryEffectFree`, `wouldOpBeTriviallyDead`,
  `getEffectsRecursively`, `isSpeculatable` (`:540-583`);
- **redundant reads across a crash, for free**: CSE merges two read-only
  ops unless an op between writes a resource not disjoint from what they
  read (`mlir/lib/Transforms/Utils/CSE.cpp:219-231`), so with D27's tree
  and a read that declares only `Read` (§1.2), a repeated read across a
  guard merges in upstream's CSE, with no code of ours.

Not given by MLIR (*read*):
- **hoisting a read**: upstream LICM moves only `isPure` ops
  (`LoopInvariantCodeMotionUtils.cpp:117`);
- **a call's effects**: an op without the interface is assumed to write
  everything (`CSE.cpp:205-210`);
- **a partial order or placement windows** over effectful ops: no
  upstream analysis builds one outside `affine`;
- the conflict of two effect instances as a function: CSE inlines it.

What our effect query adds (D9's one API, generated from the
specification): the derived row on `idr.call` (D22), without which every
call is a barrier; D61's per-parameter part; D102's licence (crash and
divergence block deletion and floating); "an allocation conflicts with
nothing" (as CSE reads writes only); the conflict as a generated table
over the tree; and per op of a region its window, the last conflicting op
before it and the first after, one walk per resource, O(ops × resources),
with no transitive closure.

## 3. One real function, extracted four ways

*measured*, `/tmp/eg-effects/exp/extract.cpp`, built with `clang++
-std=c++20 -O2`, run `./extract K {plain|count} REPS`. The function:
fannkuch-redux's `flips` with `rev` inlined (`bench/fannkuch-redux/Main.idr`),
`get`/`set` as emitted (a `check.in_bounds` guard, then `array.get` or
`array.set` on the IOArray's memref; `readArray.case0`'s lambda in the
emitted module, *read*): `h <- get p 0`, then K iterations of rev's arm
unrolled, each `get p i; get p j; set p i b; set p j a`, so 4 guards, 2
reads, 2 writes. Rules: a guard of an index already guarded is removed
(the array's length is fixed); a read of an index read since the last
contents write is the earlier value; (d2) also commutes the arm's two
writes, keeping both orders.

| K | design | kept: guards, reads, writes | free pairs | width | time |
| --- | --- | --- | --- | --- | --- |
| 16 | b | 32, 32, 32 | — | — | 2.6 µs |
| 16 | c | 32, 32, 32 | 2,064 of 4,560 | — | 11.4 µs |
| 16 | d1 | 32, 32, 32 | — | 1 | 8.5 µs |
| 16 | d2, statewalk DP | 32, 32, 32 | — | 1 | 9.4 µs |
| 16 | d2, brute force | 32, 32, 32 | — | 65,536 walks | 11.5 ms |
| 20 | d2, brute force | 40, 40, 40 | — | 1,048,576 walks | 245 ms |
| 1,024 | b | 2,048 × 3 | — | — | 0.11 ms |
| 1,024 | c (closure) | 2,048 × 3 | 8,389,632 | — | 320 ms |
| 1,024 | d1 | 2,048 × 3 | — | 1 | 1.1 ms |
| 1,024 | d2, statewalk DP | 2,048 × 3 | — | 1 | 1.0 ms |

- **Every design keeps the same program**: half the guards go, the
  repeated read of `p[0]` goes (by the last-store map in b and c, by
  hash-consing in d). With `count`, the repeated read stays in every
  design (33 reads at K = 16).
- **(c)'s freedom is real here and changes nothing**: 45% of pairs are
  free (guards against memory ops), and no placement lowers the cost;
  the order is LLVM's to schedule.
- **(d2)'s alternatives change nothing**: both orders of the two writes
  cost the same, and the extractable sets agree, so the DP's width stays
  1; brute force over walks grows as 2^K.
- **Cost**: the closure in (c) is cubic in a region's ordered ops; at
  real sizes (82 at most) it is negligible, and §2.4's windows avoid it.

## 4. The design space, briefly

- **(a) inside, one thread.** eggcc: state threaded linearly through every
  effectful operator (`02-background.tex:213-224`); congruence on
  effectful subterms makes unsafe terms unavoidable (`03-overview.tex:46-55`);
  any effect-safe extraction NP-complete (`07-np.tex`, the reduction
  needs equalities between effectful terms); statewalk DP O(k·n²) in
  width k, pure-only rules never raise k (`06-tiger.tex:467-503`). Peggy:
  a solver per method, under 3% of methods left unoptimized
  (`egraph.md` §1.4). *read*.
- **(b) one line.** Cranelift's skeleton (`egraph.md` §1.2): loads stay in
  the skeleton, redundant loads go by alias analysis, only pure nodes
  move.
- **(c) partial order outside** (D103): §2.
- **(d) inside, one quantity-1 token per subtree.** Its complexity
  depends on one rule-language fact: if every rule whose right side
  builds an effectful node subsumes it (Cranelift's `subsume`), each
  token class keeps one member, the statewalk is unique, and extraction
  is greedy; if rules keep effectful alternatives, it is eggcc's problem
  with several walks at once, whose DP state is a tuple over tokens
  (*conjecture*: widths multiply, as `unknowns.md` U13 says). Reads
  borrow a token instead of threading it, so reads commute and a
  repeated read is one node by hash-consing; the borrow must precede the
  token's consumer, the same rule §1.3's linear reads need. Its tokens
  would live only inside the pass (D20).
- **(e) pure regions as terms** (RVSDG's γ and θ, eggcc), effects still
  outside: 74.0% of matches in the inlined frontend (466,904 of 631,074)
  and 76.3% in the programs have no ordering atom (*measured*); D106's
  narrow scope leaves them skeleton, with case-of-case chosen per arm.
- **Julia's CFG skeleton relaxation** (Merckx, Besard, De Sutter,
  arXiv 2502.17075 §3.5-3.6, *read*): side-effecting calls in the
  skeleton; a rule marked `unsafe` that matches one removes the call from
  the skeleton, with no token and its soundness left to the rule's
  author; extraction an ILP over every skeleton statement as a root, a
  node selected in a dominating root reusable (HiGHS; 0.8-169 ms on 26
  to 337 classes). Ours is the sound form: the derived row decides
  (D102), never a rule's author.
- **Others, 2023-2026** (*read*): colored e-graphs (Singher, Itzhaky,
  arXiv 2305.19203) keep one union-find per assumption for contextual
  equalities, where we use refined case values (D105); e-hypergraphs
  (Tiurin, Barrett, Ghica, Hu, arXiv 2406.15882) give monoidal, non-copying
  wires a semantics and DPO rewriting, no engine or extraction, the
  theory under (d) and Peggy's string diagrams; extraction parameterized
  by treewidth, 2^O(w²)·poly(n) (Sun, Zhang, Ni, arXiv 2408.17042);
  Tamagoyaki (arXiv 2602.16707) handles pure straight-line code only
  (`paper.tex:627-630`); "Optimism in Equality Saturation" (Arbore et al.,
  arXiv 2511.20782) e-graphs the data-flow graph beside a CFG and treats
  no memory. None gives effects inside with polynomial extraction beyond
  eggcc's width parameter.

## 5. What D103 needs, and the one decision

- **Kept as ruled**: the skeleton is the region tree's ordered ops, no
  alternatives, one-way skeleton rules; reads of immutable memory float;
  windows per op from the effect query (§2.4); CSE's hierarchy test
  already merges repeated reads across a crash.
- **Its cost, honestly**: one walk per region per resource for the
  windows, and a read-hoisting step upstream lacks; on today's IR it buys
  0.009% to 0.18% of pairs (§2.2) and no measured run time.
- **For the coordinator**: `array.get` declares no count write before
  counting (§1.2).
- **For the owner, one question**: an order the engine can break that is
  not an effect (§1.3). Either (A) a linear array's read gives back a new
  array value, as Idris's `Res` already does, so the order is data and
  the read joins the unique class (costs: one result per read and a
  `lin` round trip per read in the IR; buys: placement cannot break it,
  and the fact the types state is kept), or (B) elaboration places every
  non-consuming use of a quantity-1 value before its consuming use, one
  rule written once (costs: a rule outside the e-graph's data that every
  placement must obey; buys: no change to the IR). Recommended: (A), the
  lossless form; without either, D103's promise does not hold for linear
  arrays.

## 6. Reproduction

- `/tmp/eg-effects/census.py MODULE {raw|inl} [defunc] [nocount]`, on
  `/tmp/eg-workloads/emit/<prog>/module.mlirbc.mlir`; output in
  `/tmp/eg-effects/out/<prog>.{raw,inl,inlnc,inl2}.json`
  (`self.inl.json`: 62 s single-threaded).
- `/tmp/eg-effects/exp/extract.cpp`: `clang++ -std=c++20 -O2 -o extract
  extract.cpp; ./extract 16 plain 50; ./extract 16 count 20`.
- eggcc's and Tamagoyaki's paper sources as `egraph.md`'s agent fetched
  them, `/tmp/eqsat-research/{eggcc,tamagoyaki}/x/`.
