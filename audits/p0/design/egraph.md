<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: equality saturation, and the search the representation exposes

Status: written 2026-10-21 for D57 (which reopens G's DP-25) and D69
(`proposals/0000-mlir-native.md:959-972, 1093-1100`, read in the working
tree at D69). D57 approved optimization by search over the legal choices
the representation exposes, equality saturation among them, and left its
form and place to this document. D69 then brought 0015's R4 (its e-graphs)
into P0 with 0011's O7 and asked that they be "the machinery of D57's
optimizer search, built once". This document says what the state of the
art does, how an e-graph meets our IR, where it sits, what it costs, what
it would find, what is research, and whether one engine can serve both the
frontend and the optimizer.

Grounds: *read* (a path:line I read; for web sources the page or the
source tree, named), *measured* (a command I ran), *recalled* (from memory,
not re-read), *conjecture*, *decision* (a ruling Dn or a coordinator
decision Cn). Ours at HEAD e96bb991 with the working tree's proposal;
MLIR at the pin 7208ba24 (`.toolchain/llvm-project`). Outside code cloned
into `/tmp/eqsat-research/`: wasmtime at aceb6b0f (Cranelift's
`codegen/src/egraph/`, `opts/`), the DialEgg artifact
(`AzizZayed/dialegg-cgo-artifact`, archived), and the arXiv sources of
Tamagoyaki (2602.16707v2), eggcc (2609.31887) and Peggy (1012.1802).
Nothing was built or run. IR below is illustrative; ops that do not exist
yet are proposals of the lanes named beside them.

## 0. In plain words

- **What the record says.** Two forms are proven. Full equality
  saturation (egg, egglog) finds rewrites a fixed pass order cannot,
  because nothing is destroyed until extraction; on whole programs it
  costs about eleven times a production compiler (eggcc: 7.9 s plus 1.5 s of
  extraction against LLVM -O3's 0.83 s on the same programs, *read*), and
  extraction once effects are in the graph is NP-complete. Cranelift's
  acyclic e-graph applies rules once, when a node is made, never rebuilds,
  and puts pure nodes back by a scoped walk of the dominator tree; it has
  shipped since 2022, at 7-8% more compile time than a classic pipeline
  for about 2% faster code, and its author now judges the
  "sea of nodes with a skeleton" part fundamental and the many-forms part
  nearly free and nearly idle for a rule set written to only improve
  (*read*).
- **Our IR is a better host than Cranelift's.** Regions are the dominator
  tree (D19: one block per region until the lowering). The effect tree
  (D27), read through its one query API, decides what floats. The IR is
  already in SSI form where it matters: a case binds its refined value, a
  guard returns its operand refined (D21), `idr.assume` scopes an index
  equation, so a fact learned on a path is a new value and a global
  e-graph needs no colours. Construction of an unrestricted value is pure
  (C3), so hash-consing is the compile-time hash-consing C3 wanted, and
  every value whose identity a promise reads is `Allocate` on `identity`,
  which a hash-cons never merges.
- **Linearity survives sharing, by representation.** Quantity is in the
  type and e-classes are typed; every producer of a linear value has an
  identity and is never merged; a rule cannot use a quantity-1 variable
  twice, which the specification checks when it builds; elaboration never
  puts two copies of a node that consumes a linear value on one path; and
  the linearity verifier after the pass is the check it always was. Peggy
  (2009) and eggcc (2026) both met this wall (a heap or state value used
  linearly) and paid for it in their extractors; we avoid it in the
  representation.
- **The design, in two tiers.** Tier 1 is a region-tree acyclic e-graph,
  one per function, as the one simplifier of `idr` functions before
  counting: rules from the Idris specification applied eagerly, typed
  e-classes, D41's templates as the constant and interval analyses,
  extraction by a cost table the specification generates, and scoped
  elaboration that does common subexpressions, hoisting out of loops,
  sinking into the regions that use a value, rematerialization and dead
  code in one walk. Tier 2 is bounded saturation with exploration rules
  (laws, theorems Idris proved, region rewrites, effect reordering, an
  extraction that sees counting): the owner's "nasty, unintuitive"
  optimizations, and research.
- **D69, plainly.** One engine across the Idris/C++ boundary cannot be
  built under AGENTS.md (no C export or foreign call in either direction;
  the frontend runs on Chez; the passes are C++), and sharing its state
  would be unsound (conversion is not transitive; the elaborator's closure
  must be complete where the optimizer's must stop at a budget). What can
  be built once is the specification: the rule language and its laws, the
  extraction model, the termination argument (room left in a finite
  universe), the rules, and the fixtures. Each side owns one small core.
- **Recommendation.** Tier 1 inside P0, as the replacement of the greedy
  canonicalization redesign at the `idr`-level points, not beside it;
  Tier 2 after P0, each piece its own measured cutover; the Idris side's
  R4 in P0 limited to what O7 consumes. Three owner questions, queued
  (§10.5).

## 1. The state of the art, read for mechanisms

### 1.1 egg and egglog

- **Rebuilding** (*read*, `sources/papers/willsey-2021-egg/03-rebuilding.tex:99-230,
  354-420`, via wave 1 §5.7 E1): a merge only pushes the class onto a
  worklist; one `rebuild` per iteration deduplicates it and repairs one
  layer of parents; an iteration is a read-only search, a write-only apply
  and one rebuild. The paper measures congruence maintenance 88× and
  saturation 21× faster than rebuilding on every merge.
- **E-class analyses** (*read*, `04-tricks.tex:72-240`): a domain with
  `make(n)` from the children's data, `join` on a merge and an idempotent
  `modify`, under the invariant that a class's datum is the join of
  `make` over its nodes; the rebuild worklist restores it. Constant
  folding is the example. "Without these properties, egg may fail to
  restore the analysis invariant on rebuild, or it may not terminate."
- **Extraction** (*read*, `04-tricks.tex:331-370`): with a local cost
  (a node's cost from its symbol and its children's costs) the cheapest
  term is a bottom-up fixpoint, itself an analysis; a cost may read
  analysis data.
- **Schedules and limits** (*read*, `05-impl.tex:157-173`,
  `06-case-studies.tex:36-41`): the default backoff scheduler bans a rule
  that matches in exponentially growing places; Herbie "sharply limits"
  the e-graph's size and time, and "when the timeout is exceeded,
  simplification fails altogether".
- **egglog** (*read*, wave 1 §5.7 E3; `zhang-2023-egglog/overview.tex:120-220`):
  Datalog with equality: functions whose `:merge` resolves a conflict by
  a lattice join or a union, a functional database canonicalized by
  rebuilding, e-matching as a relational query under a worst-case optimal
  join (`zhang-2022-relational-ematching`), semi-naive evaluation; 3.34×
  over egg without semi-naive and 9.27× with it (the paper's
  measurement). It calls egg "artificially limited to a single type and a
  single analysis".

### 1.2 Cranelift's acyclic e-graph

Read in source (wasmtime aceb6b0f, `cranelift/codegen/src/egraph/mod.rs`,
`elaborate.rs`, `cost.rs`, `opts/README.md`, `opts/skeleton.isle`) and in
its author's account (C. Fallin, "The acyclic e-graph: Cranelift's
mid-end optimizer", 2026-04-09, *read* through a fetch that summarizes):
- **The skeleton.** Side-effecting instructions stay in the CFG's layout;
  pure ones float. "We have defined all impure values to have their own
  identity" (blog). Loads go through alias analysis for redundant-load
  elimination and store-to-load forwarding (`mod.rs:3-6, 145-152`).
- **Rules applied when a node is made.** `insert_pure_enode` looks the
  node up in a scoped GVN map; a new node is optimized at once by the ISLE
  rules, every result joined to the original by binary union nodes
  (`mod.rs:207-296, 351-463`). "Once we create a node, we never update
  it": the graph is acyclic by construction, with no rebuild and no
  parent pointers (blog).
- **Caps in program units** (`mod.rs:126-137, 362-377`):
  `MATCHES_LIMIT` 5 results per rule call, `ECLASS_ENODE_LIMIT` 5 nodes
  per class, `REWRITE_LIMIT` 5 levels of recursive rewriting,
  `EXTRACTOR_FUEL` 500 iterator steps. A spent cap keeps the original
  form.
- **Available block.** Each node records the dominator-tree block nearest
  the root where its arguments are all available, and enters the GVN map
  at that depth, so two loop-invariant copies in sibling scopes still
  meet (`mod.rs:257-330, 465-474`).
- **`subsume`.** "Any rule that removes value-uses in its right-hand side
  that previously existed in its left-hand side MUST use `subsume`",
  because "some e-nodes in the e-class are more equal than others": a
  member may use a value not available where the class is used
  (`opts/README.md:24-45`). Rules are directional, never worse on the
  right, and general associativity and commutativity are avoided:
  "additional rules are cheaper than additional e-nodes" (`:1-22, 47-80`).
- **Skeleton rewrites** are a second, destructive entry point: a
  conditional trap that never traps is removed, a branch on a known
  condition becomes a jump (`opts/skeleton.isle:1-60`).
- **Scoped elaboration** (`elaborate.rs:19-90`; blog): demand-driven from
  the skeleton's operands, a memo map with an overlay per dominator
  subtree, a value re-placed in a sibling subtree when needed there too,
  hoisting into a loop's preheader when no operand is defined inside the
  loop, constants rematerialized per block, dead code removed "for free".
  The elaborator's stacks are explicit, not recursion (`:83-86`).
- **Cost and extraction** (`cost.rs:1-30`; blog): a per-opcode cost plus
  the inputs', ×1024 per loop level up to two, saturating; shared
  substructure counted anew at each use; one dynamic-programming pass in
  topological order. Optimal extraction once nodes are shared is NP-hard
  (a reduction from weighted set cover); sunk-cost accounting, top-down
  traversals and covered-leaf tracking were tried after Dagstuhl and none
  improved the trade-off.
- **Production numbers** (blog, the author's measurements on
  Sightglass): a first prototype round-tripping through `egg` with no
  rules cost 23% compile time where the whole mid-end it replaced was
  about 10%; the aegraph beats a classic pipeline with the same rules by
  about 2% run time, at 7-8% more compile time (parity in 2023, the gap
  from rule growth); keeping many forms instead of picking eagerly is
  worth about 0.1% run time at 0.005% compile time; a class averages 1.13
  nodes; skipping saturation lost two equalities in about four million
  nodes.
- **Verdict** (blog): "the sea-of-nodes-with-CFG aspect of this mid-end
  works great"; the multi-representation part "may not (yet?) be pulling
  its weight", because Wasm input is already optimized and the rules
  exclude associativity-style identities. Control-flow rewriting is the
  gap; RVSDG "seems like the most principled option".

### 1.3 E-graphs in and around MLIR

- **Upstream at the pin** (*measured*: `grep -rli "e-graph\|egraph\|equality saturation"`
  over `mlir/include mlir/lib mlir/docs` finds only graph-region and
  SPIR-V graph files): no e-graph. What upstream has that an e-graph
  uses: graph regions (`RegionKindInterface.h:25-50`, `HasOnlyGraphRegion`);
  the `Commutative`, `Idempotent` and `Involution` traits and no
  associativity trait (`IR/OpBase.td:73-79`); CSE as a scoped hash table
  over the dominator tree (`Transforms/Utils/CSE.cpp:20, 50-90`), which
  skips an op with a multi-block region (`:256-259`); PDL and
  `pdl_interp`. A web search found no upstream RFC for an e-graph dialect
  (*read*, 2026-10-21; absence *conjecture*).
- **DialEgg** (Zayed and Dubach, CGO 2025; the artifact *read*): each
  block is printed as an egglog text file and egglog is run through
  `std::system` (`src/EqualitySaturationPass.cpp:14-80`); an op outside
  the supported list becomes opaque (`src/Egglog.h:60-98`); only
  single-result ops (README); a region is a term of blocks
  (`src/base.egg`); no effect model. The e-graph is discarded on return
  (Tamagoyaki's related work, `paper.tex:1046-1050`).
- **`eqsat` / Tamagoyaki** (Merckx, Lopoukhine, Coward, Cheng, De Sutter,
  Grosser; EGRAPHS 2025 and arXiv 2602.16707v2, source *read*):
  `equivalence.class`, `equivalence.graph` (a graph region, for cycles)
  and `equivalence.yield` (`paper.tex:605-617`); the union-find as class
  chains in the IR (`:690-705`); e-matching by an adapted PDL lowering
  with `ematch.union` and `ematch.dedup`, the hashcons reused from CSE
  (`:729-760`); extraction as a selection pass and a replacement pass
  (`:764-778`); analyses through MLIR's dataflow framework, a class's
  `visit` the meet of its operands (`:790-800`). Its scope: "only pure,
  straight-line code fragments"; structured control flow "requir[es] the
  rewriting process and extraction to be aware of scopes. In this work,
  we do not explore" it (`:626-634`). It admits more work at class
  creation and rebuild than a library (`:707-713`). Its gain: the e-graph
  persists across passes.
- **SEER** (Cheng, Coward et al., ASPLOS 2024; *read* through a search
  summary): MLIR to egg through its own language; control-flow rewrites
  are existing MLIR passes run as rewrites, alternating with data-path
  saturation.

### 1.4 Control flow and effects inside an e-graph

- **Peggy** (Tate, Stepp, Tatlock, Lerner; LMCS 2011, source *read*):
  program expression graphs with `θ` (loop values), `eval`, `pass` and
  `φ`; the heap a threaded `σ` summary; a Pseudo-Boolean solver picks the
  program and takes most of about 1.5 s per method, with a one-minute
  timeout hit by about 1% of methods (`eval2.tex:17-19, 147-168`). Its
  wall is ours: "heap values must be used linearly in the CFG. Linear
  values complicate the reversion ... This approach, unfortunately, is
  not complete"; in under 3% of methods "we simply do not optimize the
  method" (`implementation.tex:98-120`). Its proposed fix: string
  diagrams, where "strings cannot be forked, capturing the linear quality
  of the values" (`concl.tex:22-42`).
- **eggcc and statewalk DP** (Flatt, Pal, Zhang, Tjoa et al., OOPSLA 2026;
  arXiv 2609.31887, source *read*): RVSDG in egglog; effectful operators
  thread a state value that "must be used linearly"
  (`02-background.tex:208-220`); congruence makes effect-unsafe terms
  unavoidable in the graph (`03-overview.tex:46-55`); finding any
  effect-safe extraction is NP-complete; statewalk DP runs in O(kn²) for
  statewalk width k (abstract), mean width 33.15, 520× faster than ILP
  extraction; eggcc spends 7.925 s outside extraction and 1.536 s in it
  against LLVM -O3's 0.834 s (`nightly/jscomputedmacros.tex`,
  `10-eval.tex:91-100`).
- **Julia's IR** (arXiv 2502.17075, abstract *read*): "CFG skeleton
  relaxation" to rewrite pure and effectful calls; an ILP extraction that
  respects dominance.

### 1.5 Binders and conditions

- **Slotted e-graphs** (Schneider, Rossel, Shaikhha, Goens, Koehler,
  Steuwer; PLDI 2025; *read* through a search summary): e-classes
  parameterized by slots for their free variables, terms stored modulo
  renaming, substitution built in. The library holds a typed follow-up
  (`sources/papers/wu-2026-slotted-egraphs/main_compressed.tex:27-44`).
- **Colored e-graphs** (Singher and Itzhaky, arXiv 2305.19203, search
  summary): one structure for many coarsened congruences, one per
  assumption. Contextual saturation in egglog is in progress (Hou et al.,
  arXiv 2507.11897, abstract *read*).
- **Optimism** (Arbore, Cheung, Willsey, arXiv 2511.20782, abstract
  *read*): pessimistic e-class analyses are imprecise on loops, and a
  naive optimistic one is unsound; they give a sound combined algorithm.

### 1.6 Extraction and termination

- Greedy bottom-up extraction is exact for a tree cost and ignores sharing
  (`sources/papers/yang-2021-tensat/main.tex:595-604`); ILP extraction
  with cycle filtering is Tensat's (`:605-640`); treewidth-parameterized
  optimal extraction and a differentiable one are cited by Tamagoyaki
  (`paper.tex:559-561`, not read). With sharing it is NP-hard (§1.2); with
  effects, NP-complete even to find a valid one (§1.4).
- Termination of saturation is undecidable: single-instance termination
  is R.E.-complete and for all terms Π₂-complete; weak term acyclicity is
  a sufficient syntactic criterion (Suciu, Zhang et al., arXiv 2501.02413,
  *read* through a search summary); a terminating, even canonical,
  rewriting system need not terminate under saturation, and associativity
  alone can diverge (Zhang and Flatt, EGRAPHS 2023, same). So every
  system bounds: egg's limits and backoff, Herbie's size and time,
  Tensat's `k_multi` (`main.tex:575`), Cranelift's caps.

### 1.7 What the record answers, per question

| question | egg / egglog | Cranelift | Tamagoyaki | eggcc / Peggy |
| --- | --- | --- | --- | --- |
| side effects | outside the graph | ordered skeleton, pure floats | refused (pure straight-line) | a state value threaded linearly; extraction NP-complete |
| control flow | none | CFG skeleton, never rewritten but by destructive skeleton rules | refused (scf "non-trivial") | RVSDG regions (eggcc), θ/φ (Peggy) |
| linear values | none | none | none | the wall both hit |
| cycles | allowed, filtered at extraction | none by construction | graph regions | allowed |
| termination | budgets | caps per insertion | budgets | budgets, solver timeouts |
| compile time | Herbie limits it | +7-8% over classic | 1.18× faster than Herbie's | ~11× LLVM -O3 (eggcc) |
| what it buys | rule-driven search | GVN, LICM, sinking, rules in one pass; ~2% | persistence across passes | LLVM-class output from rules |

## 2. How it meets our IR

### 2.1 What enters the e-graph: the effect query decides

One classification, a fold over each op's declaration form through D9's
one query API (L01 §2.2's five forms and typed rules), never a list of
ops (D47) and never a second classifier (AGENTS.md: "a second effect
classifier (04 C26)"):

| class | declared effects | e-graph treatment | examples |
| --- | --- | --- | --- |
| **floating** | none | hash-consed node; rules; analyses; placed by elaboration, duplicated into sibling regions where needed | `arith`, `con`/`closure`/`delay` of an unrestricted value (C3), `field` where the type fixes the constructor (L04 I10), `idr.reindex`, runtime builders of immutable values before counting (L01 I2), a call whose row is empty (a `total` callee, D13) |
| **unique** | only `Allocate` on `identity` of its results | a node with its own identity (never hash-consed), placed once per path, deletable when unused (affine) | `lin.cast` (L13 §3), a linear or owned result, a value of an `in_place` family (L01 I1), an unforced memo cell (L18 I2), a rebuild token's producer (C1, amended) |
| **ordered** | any ordering atom (`io`, `runtime_state`, `exit`, `crash`, `divergence`, `read`/`write` on `contents`, `count`, `memo_state`) | skeleton, in order per region; directional skeleton rules only | guards, `idr.crash`, IO, buffers, a call with a non-empty row, `memo.run` |
| **region** | recursive (its regions' plus its own) | skeleton in Tier 1; a pure one is a term in Tier 2 | `idr.match`, `idr.join`, `idr.loop`, `idr.lifetime`, `idr.assume`, `scf.if` and `scf.index_switch` (L13 §2.1) |
| **pinned** | any, plus a fact a promise reads on the call | skeleton; the fact is copied, never recomputed | a call whose tail kind is tail (D30), a D34 site (§2.8) |

Three facts make the floating class large and exact:
- *C3*: building an unrestricted value is pure, so two equal ones merge
  and an unused one goes. Hash-consing is then C3's "compile-time
  hash-consing of immutable values", by construction.
- *D13*: a callee Idris proved `total` carries no divergence; with an
  otherwise empty row its call floats, merges and dies when unused. A
  partial callee's call carries `divergence` and stays in the skeleton,
  so eager evaluation's crash or loop happens where it did.
- *D21*: a total op stays below its guard by data dependence, since it
  reads the guard's refined result; the e-graph needs no effect edge for
  it, and cannot hoist the op above the guard because its operand is
  defined there.

What the classification raises: a declaration that lies becomes a
miscompile. An op declared pure that crashes (L01 F-list: `handle.string`
declares no crash) is deleted when unused, and the crash goes. L01 I3
(every declaration is what its runtime function does, checked by
`tests/runtime-effects`) is therefore a prerequisite of the e-graph, not
an improvement beside it.

### 2.2 Regions and join points (D19)

- **The region tree is the dominator tree.** Until `convert-scf-to-cf`
  every region holds one block (L13 §1.5). Dominance inside a function is
  then nesting plus order within a block, so Cranelift's scoped
  elaboration over the dominator tree becomes a walk of the region tree,
  and its "available block" becomes the *available region*: the deepest
  scope among a node's operands' scopes, which lie on one chain of the
  tree (as Cranelift's arguments lie on one chain of dominators,
  `mod.rs:298-330`). MLIR's own CSE has the same shape (§1.3).
- **The skeleton is the region tree.** In each region, the ordered and
  region ops in their order; pure nodes float between them. Elaboration
  places a node in the outermost region where it is available and that
  is not above a loop it need not leave (D19's loops: recursive join
  regions, `idr.loop` per L09), and duplicates it into sibling regions
  instead of speculating it above a match (the default; the cost model
  may choose otherwise, §5).
- **Leaves.** A node's leaves are values the e-graph does not see
  through: function parameters, case fields and the refined case value
  (G DP-37), join parameters, loop-carried values, `idr.lifetime`
  tokens (D63), and results of skeleton ops. Seeing through none of them
  is what keeps Tier 1 acyclic (Cranelift's argument, applied to region
  arguments instead of block parameters).
- **SSI makes contextual facts global.** Inside `case @Cons<v1>(%x, %tl)`
  the knowledge that the scrutinee is a `Cons` is not an equality that
  holds in one region of a global graph (which would need colours or
  contexts, §1.5); it is the refined value `!idr.ctor<..., @Cons>` the
  case binds, a new SSA value that exists only there, whose facts are
  facts everywhere it exists. The same holds for a guard's refined result
  and for `idr.assume`'s scope. So D21 and G DP-37, chosen for counting,
  also let the e-graph be global with no colours. Where SSI is missing
  (a fact about a value used both inside and outside a region), the fact
  is not used; that is incompleteness, never unsoundness.
- **Join points** are skeleton: `idr.join` holds its join region, each
  `idr.jump` is a terminator with typed arguments (D19, D25). Tier 1
  rewrites across them only by skeleton rules: case-of-case becomes GHC's
  form, the outer match moved into a join region that the inner arms jump
  to (`design/match-and-counting.md` §6), and a jump whose argument is a
  known constructor may instead receive a copy of the continuation, where
  the known-case fold then removes the constructor. Which of the two a
  site takes is a cost decision (§5), not a pattern's order (§9, E9).

### 2.3 Quantities and linearity

The question: a linear value is used once; an e-graph shares. Does
sharing break linearity, and what keeps it?

What breaks it elsewhere (*read*): Peggy's heap and eggcc's state are
linear, and a congruence can always build a term that uses them twice
(§1.4). Both repair it in the extractor, at a cost (incompleteness; an
NP-complete search).

What keeps it here, each a representation:
1. *The quantity is in the type* (`!idr.lin<T>`, AGENTS.md), and e-classes
   are typed (§2.5), so a class is linear or not, never both.
2. *Every producer of a linear value has an identity.* `lin.cast` to
   quantity 1, a linear call result, a closure with a linear capture
   (`Idr_LinearWhenACaptureIs`) and a `con` with a linear field all
   declare `Allocate` on `identity` of the result (L13 §3; L01 §2.2's
   `NewIdentity`), so no two linear values are ever merged and no linear
   value is rebuilt by hash-consing. They are the *unique* class of §2.1.
3. *A rule cannot use a quantity-1 variable twice.* The rule language
   (§3.1) gives each variable its quantity; a rule whose right side uses a
   quantity-1 variable more than once is rejected when the specification
   builds (an erased proof, `UsesAtMostOnce`). This is Peggy's "strings
   cannot be forked", stated in Idris's own quantities: the owner's
   "dogfood QTT" (D48) applied to the optimizer's rules.
4. *Elaboration never puts two copies on one path.* A node that consumes
   a linear value, or is unique, may be placed in each of two sibling
   regions (the IR's linearity is affine per path: "used at most once on
   every path", `Verify/Linearity.cpp:3-6`, via L13 §3) but is never
   rematerialized or hoisted so that one path runs it twice. "Consumes a
   linear value" is a one-bit analysis (the join of the operands' bits).
5. *The linearity verifier runs after the pass*, as after every pass
   (AGENTS.md); a violation is an internal error, never a refusal.

Extraction then needs no linearity search: a linear class is used by
exactly the consumer that used it before (its producer is unique and its
one use is the original), every rule replacing that consumer uses it at
most once, and extraction picks one node per class. Effects are kept out
of the same trap by not threading them through the graph at all in
Tier 1 (§2.1's skeleton), which is what makes extraction greedy and
linear-time where eggcc's is NP-complete.

What quantities license, honestly (L13 §3): the `lin.cast` round trip,
deleting an unused linear producer (affine), a known-case fold on a
linear `con`. They do not license sinking free of duplication or any
in-place rewrite; exclusivity does that, and it is counting's (§2.9).

### 2.4 Promises that read identity: one fact for three

Three promises read whether a value is fresh, and each is decided from
the program as the frontend wrote it:
- D24's in-place promise reads exclusivity at the call (L01 I1: a value of
  an `in_place` family takes its identity where it is produced; C1's
  amendment: the rebuild is a linear token consumed by `idr.rebuild`);
- a memo cell's state is written while references to it live (L18 I2);
- D34's destination: the cells a TRMC site builds first and fills through
  `!idr.dest` (§2.8).

All three are one fact, `Allocate` on `identity` of the result, and the
e-graph reads one class (§2.1's *unique*): never merged, hoisted into
another path or folded into static data, deletable when unused. So CSE,
constant folding or record eta can no longer turn two exclusive arguments
into one shared one (L18 I2 counterexample (c); L01 I1), and no
optimization adds a refusal. The third (D34's cells) is not yet declared
so; this document proposes it to L01 and L10 (§10.5, coordinator items).

### 2.5 Families and indices: typed e-classes; analyses only where types are silent

- **Typed classes.** A class holds values of one MLIR type: grade, family
  and index terms included (D48, D58, D59). Two nodes whose types differ
  cannot be one class, so a rewrite cannot change a value's type, and
  every fact the type states (a known index fixing the layout, `Fin n`
  bounded below `n`, a refined constructor, a quantity) is a fact of the
  class with no analysis.
- **`idr.reindex`** (L04 §2.5) is a floating node from one type to a type
  equal under the scope's refinement. It is never unioned with its
  operand (their types differ); rules see through it by matching it, and
  it folds away where its two types are equal.
- **Analyses exist only for facts no type holds:** a constant, an
  interval, the possible constructors of a value whose type does not fix
  one, "consumes a linear value", and the cost. Each is a semilattice
  whose class datum is the *meet* of its nodes' facts: every node of a
  class computes the same value, so every node's fact holds of it, and
  more nodes give more information.
- **Index refinement prunes.** D48's substitution erases impossible case
  regions in the same rewrite (L04 §2.7); after D58's specialization by
  layout class, a match on a value of known index has one case, which a
  skeleton rule splices.

### 2.6 D41's templates are the analyses

D41's one function per inline operation, generic over a numeric domain
(L13 §2.3), is exactly an e-class analysis's `make`:
- the `Word` domain on constants is the constant analysis (a constant
  held as `{bits, width}` in the arena, never an attribute made on a
  worker, perf-sources R3), and the one runtime fold read off the
  generated ABI table (L13 §2.6) folds the runtime ops' constants;
- the `Ranges` domain is the interval analysis, through upstream's
  `InferIntRangeInterface` transfer functions, seeded from a `Fin n`
  operand's type (L13 I8);
- the `Arith` domain stays the expansion at the lowering (D41), outside
  the e-graph.

So a guard whose condition the interval analysis proves is folded by a
skeleton rule, and one it refutes becomes `idr.crash` of its cause and
site, D13's statically certain crash with no run-time test (L13 I2). The
template's identities that L13 `static_assert`s (`euclid<Quotient>(a, 1) =
a`, `shift(a, 0) = a`) are the e-graph's rules for those ops, printed from
the one source (§3.3): the arithmetic is written once.

### 2.7 Lifetimes (D63)

A lifetime is an SSA token that `idr.lifetime` yields for its region. To
the e-graph it is a leaf available only inside that region, so every node
that reads it (a view, an allocation into the lifetime) is available only
there: elaboration cannot hoist it out, by the same availability rule
that places everything else. No lifetime fact needs an analysis.

### 2.8 Tail calls and destinations are pinned (D30, D34)

- A call in tail position never grows the stack (D30), its tail kind
  held on the call. The e-graph treats such a call as pinned skeleton:
  no rule wraps it in another operation and no extraction places it
  under one. The e-graph may *create* tail calls (a reassociation that
  puts a self call on one side, §9 E5), which the pass that decides tail
  kinds then reads.
- A TRMC site (D34) is read off the program as the frontend wrote it,
  before counting (L10). Its call is pinned, and the constructor cells
  between it and the return are the destinations the loop builds first:
  their identity is what the promise reads, so they are *unique* (§2.4),
  never merged with an equal cell elsewhere (which would share a
  destination) and never rewritten into another shape.

### 2.9 Counting: before, and what comes after

- **Before counting.** The e-graph runs on the value program: values are
  immutable, construction is pure (C3), there is no `dup`, `drop`, token
  or cell. That is where algebra is clean.
- **Never after counting.** Counting's ops write `count` and `heap`;
  they are ordered, so an e-graph would see a skeleton and little else.
- **Counting's own choices are bounded searches**, D57's other half: which
  token a construction takes (C1's total order is one choice among the
  legal pairings), borrowed or owned at a join parameter, the key copies
  of a join region (match-and-counting §7), the specializer's keys and
  inline verdicts (L18 §2.2). Each is finite and ends by construction;
  none is equality saturation.
- **Extraction anticipates counting, approximately** (§5): a counted
  value used twice pays a `dup` and a `drop`; a construction whose layout
  is a cell pays an allocation unless a cell of that layout dies on the
  path (C1's reuse); sharing an equal construction that two consumers
  would each have rebuilt in place costs those in-place rebuilds. The
  exact cost needs the counted program (§10.3).

### 2.10 Acceptance never moves

The e-graph runs after every analysis a refusal rests on: the label solve
and `idr-knots` (L18 I1: nothing that optimizes runs before them), D24's
rule read right after defunctionalization (L08). It refuses nothing; its
budget leaves code less optimized (AGENTS.md); and by §2.4 it cannot make
an exclusive argument shared, so it cannot add a uniqueness refusal.

## 3. Rules from the Idris specification (D16)

### 3.1 The rule language

A rule is data, typed by what it rewrites, with its side conditions as
typed facts. A sketch in the real shape (nothing compiled):

```idris
-- A signature: the node kinds, their arities and sorts. For the optimizer
-- it is generated from the dialect's specification and the admitted
-- upstream ops (D51); for a tactic it would be Core's.
record Signature where
  constructor MkSignature
  Sort  : Type
  Kind  : Type
  arity : Kind -> Nat
  dom   : (k : Kind) -> Vect (arity k) Sort
  cod   : Kind -> Sort

-- Pattern variables carry a quantity and a sort.
Ctx : Signature -> Nat -> Type
Ctx sig n = Vect n (Quantity, sig.Sort)

data Pat : (sig : Signature) -> Ctx sig n -> sig.Sort -> Type where
  Var : (i : Fin n) -> Pat sig ctx (snd (index i ctx))
  Op  : (k : sig.Kind) -> All (Pat sig ctx) (sig.dom k) -> Pat sig ctx (sig.cod k)

-- A side condition is a closed sum of facts an analysis or a type holds.
data Cond : Ctx sig n -> Type where
  Constant : Fin n -> Cond ctx                    -- the constant analysis
  InRange  : Fin n -> Interval -> Cond ctx        -- D41's Ranges domain
  Possible : Fin n -> List Ctor -> Cond ctx       -- the constructor analysis
  Total    : Fin n -> Cond ctx                    -- the callee, or every label of a closure
  Exact    : Domain -> Cond ctx                   -- the domain does not wrap (D41's `wraps`)

data Direction = Simplify   -- the right side replaces the left (Cranelift's subsume)
               | Equal      -- both kept, extraction chooses

record Rule (sig : Signature) where
  constructor MkRule
  ctx   : Ctx sig n
  lhs   : Pat sig ctx s
  rhs   : Pat sig ctx s                    -- same sort: no rule changes a type
  conds : List (Cond ctx)
  dir   : Direction
  0 bound  : Covers lhs rhs                -- every right-side variable occurs on the left
  0 linear : UsesAtMostOnce One rhs        -- a quantity-1 variable occurs at most once
  0 safe   : Removes lhs rhs `Implies` (dir = Simplify)
             -- a rule that drops a use of a non-constant value must replace
```

The last proof is Cranelift's `subsume` rule (§1.2) made a type: a rule
that drops a use of a value from its left side can only be `Simplify`,
because an `Equal` member using a value not available where the class is
used would be wrong to pick.

### 3.2 What its types prove, and what they cannot

- *Proved when the specification builds*: type preservation (the index
  `s`), every right-side variable bound, linearity of quantity-1
  variables, the subsume discipline, every condition naming a variable of
  the rule, each condition's fact one the engine provides (a closed sum).
- *Not provable in Idris*: the law itself for a primitive. AGENTS.md: "No
  primitive has an implementation in Idris: its one meaning is the
  runtime's". That `big.add` is associative, or that `str.append` is, is a
  declared fact of the primitive, trusted as its documented semantics
  are, and checked by search (§3.5).
- *Provable, and proved, for ordinary functions*: an equation over
  functions with bodies, like base's `mapFusion`, is a theorem Idris
  checked (§3.3, research).

### 3.3 Where rules come from, each fact once

- **Laws on ops.** An op's entry in the specification lists its laws
  (`Assoc`, `Comm`, `Identity c`, `Annihilator c`, `Idempotent`,
  `Involution`), and the generator derives the rules; the law is the one
  fact (C4 already names the exactly associative runtime operations). For
  admitted upstream ops, `Commutative`, `Idempotent` and `Involution` are
  upstream's traits, read by D51's backend, never restated; associativity,
  which upstream has no trait for, is declared in the admitted list.
- **D41's identities**, printed from the template's facts (§2.6).
- **`Spec.Rewrites`**, L13 §2.5's records (the output compositions, the
  head of a show), restated in this language. L13 printed them as DRR;
  here they are printed once, to the e-graph, and DRR is not printed. Their
  `HasOneUse` constraints go: a use count is a destructive rewrite's
  profitability guess, and in an e-graph legality alone gates and the
  cost decides.
- **Upstream folds, called, never restated.** An upstream op's `fold` is
  its meaning and the constant analysis calls it; its canonicalization
  patterns are destructive and run in upstream's canonicalizer before the
  e-graph (§6). No rule of ours repeats one.
- **Theorems** (Tier 2, research, §10.3): an equation Idris proved over
  total functions (base proves `mapFusion`, `lengthMap`,
  `lengthReplicate`, `reverseInvolutive`, `dropFusion`, `filterAppend`,
  `appendAssociative`, *read* `third_party/Idris2/libs/base/Data/List.idr:1004-1122`),
  read once by the frontend from checked TT into a typed table and
  instantiated per specialized instance, with `Total` conditions on the
  functions it deletes calls of.

### 3.4 What the generator prints

`specgen` stays a printer (one-source §6.3): it prints constexpr tables,
never matcher code. Per rule: the root kind, a flattened pattern (node
kinds and variable slots in preorder), the conditions as enum values with
operands, the right side as a builder program over slots, the direction.
The hand C++ engine (§4) reads the tables through templates; rules are
indexed by root kind at compile time (perf-sources R1: every root set a
compile-time list). Nothing is built per function (R2: AGENTS.md's
defunctionalization pattern set, 51a4771b).

### 3.5 Soundness by search

Two oracles AGENTS.md and the testing skill allow:
- *The runtime's documented semantics*: for every law on a primitive,
  random operands through the runtime functions on both sides of the law,
  at every width the op admits, on the four targets.
- *Two forms of one closed expression* (the skill's `Fuzz.idr` family):
  for every rule, a generated program holding the left side and one
  holding the right, compiled and run, outputs compared. The committed
  expected outputs of the program suite stay the specification of the
  whole.

## 4. The engine in C++

### 4.1 Data

Per function, an arena freed when the function is done (perf-sources R5,
R6; D7):
- dense `NodeId`, `ClassId` (`uint32_t`), in walk order;
- nodes in one array: kind (the generated enum), result type id (a per-run
  intern of the function's types, built serially before the parallel
  walk, so no type is made on a worker, R3), properties id, children as an
  offset into one child array (CSR), the available region;
- the union-find as a parent array, the representative the smaller id
  (deterministic);
- the hash-cons as open addressing over `(kind, type, properties, child
  classes)`, scoped by region depth as Cranelift's scoped map is;
- each analysis's datum in an array per class; costs in an array per
  class.
No map keyed by `Value`, `Operation *` or `Block *` (AGENTS.md; perf-sources
R6), no recursion on the input's size (D33; Cranelift's elaborator is
iterative for the same reason).

### 4.2 The pass

1. *Number.* One preorder walk gives ops, values and regions dense ids,
   each region its depth and loop depth (perf-sources R5).
2. *Classify* each op by the effect query (§2.1).
3. *Build, Tier 1.* In walk order, each floating op: children to their
   representatives; a hit in the scoped hash-cons maps the result; a miss
   makes the node, runs `make` for each analysis, and runs the rules
   rooted at its kind, each right side built recursively and capped
   (rules per call, depth, class size, all in program units); `Simplify`
   results replace, `Equal` results join by union.
4. *Skeleton rules*, in order, reading the analyses: a guard proved or
   refuted (§2.6), a match on a known constructor spliced, a statically
   certain crash made plain, case-of-case and its copy (§2.2), the output
   compositions.
5. *Saturate, Tier 2 only*: rounds of read-only matching, write-only
   apply and one rebuild (egg's discipline), the node arena's capacity
   the budget (§4.5).
6. *Extract*: each class's cheapest node by the cost table, bottom-up in
   creation order (acyclic in Tier 1), ties to the larger id (the
   rewritten form, as Cranelift breaks them, `elaborate.rs:111-124`).
7. *Elaborate* the region tree from each region's skeleton: demand each
   operand's best node; place it in the current scope unless an overlay
   of an enclosing scope holds it; hoist out of a loop when no operand is
   defined in it and the cost says so; rematerialize constants per use
   region; place a unique or linear-consuming node at most once per path
   (§2.3); write the ops into the IR; erase the originals left unused.
8. The pipeline's verifier runs after the pass, as after every pass
   (linearity, grades, rows covering their derivation, L14 §1.1's D22
   correction).

### 4.3 Templates and concepts

`idr::egraph::EGraph<Sig, Analyses, Cost>`, with concepts `Signature`
(the generated kind enum, arity and sort tables), `Analysis` (a lattice
with `make`, `meet` and an idempotent `modify`, the solver layer's
`Lattice` concept of §5.2), and `CostModel` (an ordered, saturating
monoid). One explicit instantiation for the `idr` signature behind
`extern template` (D7); a second only if Tier 2's region terms need one.
Over ops the one dynamic dispatch is the effect query's interface call per
`Operation *` (the open set MLIR forces); below it everything is typed.

### 4.4 Threading and determinism

A nested function pass, parallel under the pass manager; no state shared
between functions; the arena per worker. Output byte-identical at any
thread count (DP-34): ids in walk order, rules tried in table order,
representatives and ties by id. Each function's run is a trace zone, not
an action a debug counter may skip (L14 §1.2: skipping is a budget of
zero; harmless here, since the e-graph decides no acceptance, so an
action is allowed for bisection, *decision* left to L14).

### 4.5 Budgets

Every bound is in program units and only stops: Tier 1's per-insertion
caps; Tier 2's arena capacity, `c × ops(f)` nodes, so saturation ends when
the arena is full or a round adds nothing. A spent budget keeps the
graph as it is and extraction proceeds: the function is less optimized,
never refused (AGENTS.md). The constants are debt, measured at stage 1
before they are fixed, written once in the specification (D58's practice
for its shape budget).

## 5. The cost model

Integers in program units, saturating (Cranelift's `Cost`), generated from
the specification:
- **per node**: the op's cost class from its specification entry (an
  inline operation, a runtime call by its entry's class, a load), plus
  its children's;
- **allocation**: a `con` whose result's layout is a cell (D48's layout
  function, D58's classes) costs an allocation; at a closed inline layout
  it costs its components only (`#Vect[3]` is three words, no cell);
- **loop depth**: ×1024 per level of the node's placement, saturating
  (Cranelift's), so hoisting wins;
- **code size**: each copy elaboration places, so sinking into many
  regions is weighed against computing once above;
- **counting**, estimated: one `dup` and `drop` per extra use of a class
  whose layout holds a count (not static, not inline, not exclusive); a
  construction that a dying cell of its layout could take on the path is
  cheaper (C1's reuse); sharing an equal value that two consumers would
  each rebuild in place costs those rebuilds. Hash-consing is therefore
  not free under counting, and the extraction must see it (§10.3 for the
  exact form).
Nothing is timed at compile time; the table is a compile-time constant.

## 6. Where it sits, what it replaces, what it keeps

Pipeline order is L18 §2.1's.

| point | today (`Pipeline.cpp`) | with the e-graph |
| --- | --- | --- |
| defunctionalization, knots, dedup, contify | — | unchanged; nothing before knots optimizes (L18 I1) |
| idr-optimize, specialize phase, per member | canonicalize, cse, idr-constants (L18 §2.1's inner steps) | the e-graph pass, then idr-constants (upstream SCCP, kept: optimistic through loop-carried values, which a pessimistic e-class analysis is not, §1.5) |
| idr-optimize, inline phase | — | the e-graph pass as upstream `Inliner`'s simplification pipeline (L18 I7) |
| after columns, before structure loops | canonicalize, cse (`:92-94`) | upstream canonicalize filtered to upstream dialects' own patterns (L13 §2.4's derived filter), then the e-graph pass |
| after bufferization, before counting | canonicalize, cse (`:115-117`) | the same pair as the row above |
| after linalg-to-loops, after returned-arguments, the lowered module | canonicalize, cse | unchanged: upstream dialects; our ops reach there with their folds only |
| counting and after | — | never (§2.9) |

**What it replaces** (proposed; the deletions are the coordinator's to
record):
- at the `idr`-level points, the greedy canonicalizer and CSE pair for our
  ops: CSE is the hash-cons; the canonicalizer's work on our ops is the
  rules;
- the movement patterns: `SinkConsumer`, `SinkIntoRegions`, `MoveOut` (twice),
  and case-of-case's movement become elaboration's placement
  (`Canon/Sink.cpp`, `Canon/MoveOut.cpp`, part of `Canon/CaseOfCase.cpp`);
- `MergeIdenticalRegions` becomes hashing of region contents at
  elaboration (`Canon/Merge.cpp`), with `#idr.site` a property so two
  crashes at two sites never merge (L13 I3);
- `StaticCase`, `FieldOp::canonicalize`'s enclosing-match walk and
  `DropEmptyStringCase` become the constructor analysis and skeleton
  rules;
- the fold probe that clones a consumer per question (`Canon/Feeds.cpp:75-93`,
  04 C12, 1b2e31da) goes: the e-graph adds the candidate and the cost
  decides;
- the phase-ordering cycle class (c179ab2d) becomes unrepresentable:
  both placements are held and one is extracted; nothing moves back;
- L13 §2.5's DRR printing: the same records printed once, as rule tables;
- L13 §2.4's configuration stays for the upstream canonicalizer where it
  still runs, with its two carried patches.

**What it keeps.** Folds (an op's meaning, called by both the e-graph and
the upstream canonicalizer); upstream canonicalization of upstream ops;
SCCP; upstream's inliner; contification; the specializer (which gains the
e-graph's classes as a source of keys, §9 E8); deduplication by partition
refinement (DP-26), which needs a greatest fixpoint (functions equal
unless told apart, merged inside cycles) where an e-graph's congruence is
a least one, so the two are not one mechanism.

## 7. Its cost for the compiler, at stage-1 scale

- **Scale** (*measured* by others, perf-sources §0): 75-82 MB, 63,464-69,773
  Core functions, 114,110 `idr.func` at S2.1, matches of tens of
  thousands of cases; on the order of a million ops (*conjecture*, wave 1
  §5.7.3).
- **Tier 1** is linear in ops times a capped number of rule attempts per
  insertion, plus one elaboration walk, per function, in parallel. The
  one production reference is Cranelift's +7-8% over a classic pipeline
  with the same rules (*read*, on Wasm, not our IR). On our IR its time
  is *conjecture* until measured; it replaces the canonicalize and CSE
  pair (at two `idr`-level points, `Pipeline.cpp:92-94, 115-117`, and in
  every round of idr-optimize's inner pipeline), so the measure is the
  pair's time against the pass's.
- **Memory**: a node of about 24-32 bytes (*conjecture* from §4.1's
  fields), a few nodes per op in Tier 1 (Cranelift's classes average 1.13
  nodes), the arena per worker freed per function: the largest function
  bounds the peak. A 20,000-case match is one function: its skeleton holds
  20,000 regions, walked once at build and once at elaboration; nothing
  revisits the match per change inside it (perf-sources C12's cause is
  absent by construction).
- **Tier 2** is bounded by the arena (`c × ops`); eggcc's ~11× of LLVM -O3
  is the warning (*read*); so Tier 2 runs per function under that
  capacity, never over the whole program, and only where its gain is
  measured.
- **What is measured before the constants are fixed** (U1's instrument,
  perf-sources §5): per-pass time and peak footprint at stage 1; nodes per
  op; class sizes; rule hit counts per rule (a rule that never fires is
  deleted); extraction and elaboration time; the largest function's
  arena; the same with one thread and many, byte for byte.

## 8. D69: one engine for the frontend and the optimizer?

### 8.1 What each consumer needs

- **O7** (0011 §4.6, 0015 §3): the elaborator's constraint store and
  postponement as semi-naive evaluation (0015's layer 2), and meta-to-meta
  unification on layer 3's union-find, "never the conversion cache, since
  conversion with unfolding is not transitive" (0011 §4.6, *read*). Later,
  R5's saturation offered to tactics, whose proof term the kernel checks
  (0015 §3; 0013 §2.5). Plain Idris over base, both hosts, total with no
  fuel (0015 §1; AGENTS.md).
- **The optimizer** (D57): congruence over pure ops, rules from the
  specification, analyses, cost extraction, elaboration into regions;
  per function, parallel, after defunctionalization; C++ under MLIR,
  where the IR lives.

### 8.2 One implementation across the boundary: not buildable

Each way to run one implementation on both sides breaks a rule:
- *The C++ passes calling a compiled Idris engine* needs a C export of
  compiled Idris, which AGENTS.md bans ("Do not implement ... `%extern` as
  a C export, a C calling convention"), and a bootstrap cycle: the C++
  passes are built by clang before idris-mlir exists, so they would need
  the compiler's output to build.
- *The frontend calling a C++ engine* needs a foreign call from Idris,
  banned, and impossible on the stock host: the frontend runs on Chez and
  reaches no `%extern` (0015 §1; AGENTS.md's two hosts).
- *The optimizer moved into Idris* needs the IR read back into Idris
  after defunctionalization (a mirror of the dialect on the Idris side,
  an AGENTS.md "never" unless generated), runs at Chez speed in stage 0,
  and contradicts "Idris does types; MLIR does programs" and D7.
- *The elaborator moved into C++*: the fork is Idris; no.

### 8.3 Shared state: not sound, and nothing to share

- *Conversion is not transitive* (0013 §2.1, *read*: a closure over
  conversion successes "would make the answer depend on evaluation
  order"). An e-graph's congruence closure over Core terms would be such
  a closure. On the Idris side the sound parts are the union-find over
  metas (metas are unknowns, so their identity is an equivalence),
  hash-consing (syntactic identity), and rules whose output the kernel
  re-checks (R5). On the optimizer's side congruence is sound because a
  pure op is a function of its operands (§2.1, given exact declarations).
- *Two termination contracts.* The elaborator's verdict is acceptance, so
  its closure must be complete on what it closes over; 0015 §1 forbids a
  library budget there ("a spent budget would fail a proof by a count").
  The optimizer's must stop at a budget (D57). One argument serves both,
  "room left in a finite universe" (the representation-first skill's
  sanctioned measure, never fuel): the elaborator's universe is the
  program's own terms, which union-find and congruence never leave, so the
  closure is complete; the optimizer's is an arena of `c × ops` nodes,
  which rules may fill, so it is incomplete and no acceptance reads it.
- *Disjoint lifetimes and languages.* Metas are solved before the TTC is
  written; the optimizer starts after defunctionalization, over `idr` ops.
  No class of one is meaningful to the other.

### 8.4 What is built once, and what each side owns

| part | built once (where) | Idris side: `libs/mlir-relational` layer 3 | C++ side: the solver layer (D2) |
| --- | --- | --- | --- |
| rule language, laws of an e-graph (congruence, the analysis invariant, subsume) | Idris types in layer 3 (§3.1); the dialect's specification states its rules in them | rules over Core's signature (R5) | rules over the `idr` signature, read as generated tables (§3.4) |
| union-find | the algorithm's statement; deterministic representatives | plain Idris; O7's meta-to-meta unification | a parent array per function |
| congruence and rebuilding | one invariant, egg's discipline | hash-consing and meta classes only (§8.3) | full congruence over pure ops |
| e-matching | relational in principle (a join) | layer 1's generic join | per-root tables (rooted rules); a join for multi-patterns in Tier 2 |
| analyses | `Analysis` with its lattice laws as erased proofs | none in O7 | D41's domains, constructors, the linear bit |
| termination | room left in a finite universe | the program's terms (complete) | an arena of `c × ops` (a budget) |
| extraction model | cost algebra (ordered saturating monoid), acyclic greedy DP, tie by id | a proof term by size (R5) | a program by the specification's costs |
| conformance | committed fixtures (e-graphs and expected classes and extractions) | runs them | runs them; the two cores also searched against each other on the shared fragment, a second implementation we own (testing skill) |

What this needs from P0's other decisions: the specification depends on
layer 3's rule-language module, which amends C7's "depends on `base`
alone" (both are plain Idris, both hosts); and 0015 §3's line "Saturation
over `idr` IR would be a proposal against the cutover's stage 6 that
replaces its canonicalization whole" becomes this document, amended in the
same change as D69 asks.

### 8.5 What D69 buys in P0, plainly

- One engine across the boundary: not buildable, and not sound to share.
- One machinery in the sense of one specification, one algorithm design,
  one termination argument, one extraction model and one set of
  fixtures: buildable, and recommended.
- Two small cores remain, one per side of the boundary AGENTS.md draws
  (0008 D13: each whole-program fact on the side that owns it; 0015 D6).
  This is two implementations of an algorithm, not a fact held twice; the
  facts (rules, laws, costs) are generated from one source, and the cores
  are held together by the fixtures and a search between them.
- On the Idris side, O7 consumes the union-find and, at most, hash-consing;
  layer 3's saturation, relational e-matching and slotted binders have no
  consumer in P0 (their consumer is R5, not in P0). Building them in P0
  would build code no P0 path runs; 0015 §0's own rule takes a stage when
  its consumer is next. Owner question (§10.5).

## 9. What it finds that today's pipeline cannot

Each: the program, what the e-graph holds, what makes it legal, the tier,
why today's pipeline misses it. Programs are illustrative.

- **E1. Two canonicalizations that fight.** c179ab2d: case-of-case and
  yield-fields moved one constructor in opposite directions for ever;
  the fix moved the consumer two levels in one rewrite, and termination
  "rests on that case analysis" (04 C08). The e-graph holds both
  placements and extracts one. *Tier 1.* Today: correct only by a combined
  rewrite and a case analysis no type states.
- **E2. Sink to fold, per arm.** A value computed above a three-way match
  folds with the known constructor in two arms and is used opaquely in
  the third: elaboration places one copy per arm, two of them fold, the
  third computes. Legal: the value is floating. *Tier 1.* Today:
  `SinkIntoRegions` must first ask whether the consumer folds, by cloning
  it (`Feeds.cpp:75-93`).
- **E3. Guards an index proves.** `index i xs` with `i : Fin n` and
  `xs : Vect n`: the interval analysis seeded from `Fin n` folds
  `check.in_bounds`; with D59, `replicate 3 x` is `#Vect[3]`, D58 makes it
  three inline words, and the access is a field read. Legal: the type.
  *Tier 1.* Today: the guard stays (L13 I8).
- **E4. Integer algebra that wrapping arithmetic forbids.** For
  `Integer`, `(x * 2) \`div\` 2` is `x` and `(n + 1) - 1` is `n`; for
  `Int` the first is false (it wraps). The rule's condition is
  `Exact Integer`, D41's `wraps = false` as a typed fact; with intervals,
  what remains narrows to word arithmetic. *Tier 1 (directional rules).*
  Today: no rule; narrowing reads ranges only.
- **E5. Reassociation by declared laws.** `putStr ((a ++ b) ++ c)` on
  strings: concatenation is exactly associative (C4); the e-graph holds
  `a ++ (b ++ c)` and the composed output `put_str a; put_str b; put_str c`,
  and extraction builds no string at all; where a string is kept, right
  nesting copies `a` once instead of twice. In a self-recursive body,
  reassociation can move the self call to one side of `⊕`, the shape
  `idr-accumulate` turns into a loop (C4). *Tier 2 (associativity is an
  `Equal` rule).* Today: L13 §2.5's rule splits one level of append.
- **E6. Theorems as rules.** `length (map f xs)` is `length xs` by base's
  `lengthMap`; `map g (map f xs)` is `map (g . f) xs` by `mapFusion`;
  `reverse (reverse xs)` is `xs`. The first deletes n cells and n calls
  of `f`, legal only when every label of `f` is `total` (D13: deleting
  calls deletes their crashes and loops); the second changes the order of
  `f`'s and `g`'s calls, legal when both are total; `appendAssociative`
  makes `(xs ++ ys) ++ zs` cost `|xs| + |ys|` cells instead of
  `2|xs| + |ys|`. *Tier 2, research* (§10.3). Today: nothing reads a proof
  of an equation.
- **E7. Share or keep apart.** C3 merges two equal constructions; if each
  would have been rebuilt in place by its own consumer, sharing makes the
  first consumer copy. With counting in the cost, extraction keeps them
  apart there and merges them elsewhere. *Tier 1 with §5's estimate; exact
  in Tier 2.* Today: CSE merges whatever is equal and pure.
- **E8. Specialization keys hidden in classes.** L18 I7's `h y = k (wrap y)`
  with `wrap y = Just y`: after leaf inlining the class of the argument
  holds `con @Just(y)`; the redirect reads the class, not the extracted
  node, and specializes `k` on `Just _`. *Tier 1.* Today: the key is
  missed when the call is seen before the constructor.
- **E9. Case-of-case, copied or joined, per arm.**
  `case (case x of A => Just 1; B => lookup k m) of Nothing => d; Just v => v + 1`:
  arm `A` takes a copy of the outer match and folds it (no `Just` cell);
  arm `B` jumps to one join region (no copy of a large continuation).
  *Tier 1 (a skeleton rule with a local cost); Tier 2 (globally).* Today:
  case-of-case copies or does not, by the pattern's own test.
- **E10. Array algebra before bufferization.** `index (tabulate n g) i`
  is `g i`; `fold_last (+) 0 (tabulate n g)` needs no array. D43's
  generating ops are tensor values before bufferization, so these are
  pure rewrites over region terms (the generator's body instantiated at
  `i`). Upstream's linalg fusion stays upstream's; these rules are for our
  ops it does not know. *Tier 2 (region terms with binders).* Today: no
  rule over the generating ops.
- **E11. Moving heap reads across a crash.** D21 makes the heap a sibling
  of the crash: an array read may move above a guard that does not guard
  it, out of a loop. The skeleton becomes a partial order per resource
  subtree, built inside the pass from the declared effects (never a world
  in the IR, D20). *Tier 2, research* (eggcc's statewalk extraction is the
  nearest mechanism). Today: canon moves nothing past an effect
  (04 §6).

## 10. The design, its cost, what is research, and where it goes

### 10.1 The strongest design

- **One engine per side**, the optimizer's in the solver layer, named for
  what it is: an e-graph over one function's pure value program, typed,
  acyclic in Tier 1, its skeleton the region tree, its classification the
  effect query, its analyses D41's domains plus constructors and the
  linear bit, its rules generated from the specification in a rule
  language whose types prove type preservation, binding, linearity and
  the subsume discipline, its extraction greedy over a generated cost
  table, its elaboration one walk of the region tree that is CSE,
  hoisting, sinking, rematerialization and dead code.
- **Tier 1** is the one simplifier of `idr` functions at the four
  pre-counting points (§6). **Tier 2** adds bounded saturation and the
  research items, each a measured cutover.
- **D69**: one specification and design shared with layer 3 of
  `mlir-relational`; two cores; fixtures and a search between them.

### 10.2 Its cost

- Code (*conjecture*): Cranelift's e-graph core is 2,458 lines of Rust
  (*measured*: `wc -l` over `egraph/{mod,elaborate,cost}.rs`) beside its
  ISLE rules; egglog's core about 4,200 (wave 1 §5.7 E3, *read*). Ours,
  with region-tree elaboration and typed classes, is of that order, plus
  the rule language and the generator's tables.
- Compile time: unmeasured on our IR; Cranelift's +7-8% is the only
  production figure, Tier 2 a multiple bounded by its arena (§7).
- Prerequisites it makes blocking: exact declarations (L01 I3,
  `tests/runtime-effects`); the identity rule for in-place values, memo
  cells and D34's cells (§2.4); refined case binding (G DP-37); crash
  sites as properties (L13 I3); tail kinds on calls (D30).
- Risk under D56: one more engine in the one build. Tier 1's risk is
  bounded by construction (no saturation loop, capped work per insertion);
  Tier 2's is not, which is why it waits.

### 10.3 What is research

*Doable, bleeding edge, never promised until measured:*
- theorem-harvested rules: equations Idris proved over total functions,
  read once from checked TT, instantiated per specialized instance, with
  `Total` conditions (E6); the same fact R5's tactics would read;
- pure region ops as terms (RVSDG's γ, eggcc), with slotted binders for
  region arguments and D48's index levels (E10);
- the skeleton as a partial order per resource subtree, with statewalk
  extraction (E11);
- extraction that sees counting: extract k candidates, run counting's
  walk (linear per function, C1) on each, keep the cheapest counted
  program; E7 exactly;
- index-equation reassociation: a rule whose right side differs in an
  index term, wrapped in `idr.reindex` and justified by an index law Idris
  proved, once D48's index language grows (0010);
- rule synthesis in the manner of Ruler (`pal-2023-ruler`, stored): rules
  found offline from the runtime's semantics, checked by §3.5's search,
  committed into the specification; a synthesizer kept in the tree would
  be Idris (D15).

*Open problems, never promised:* optimal extraction with sharing (NP-hard)
or with effects (NP-complete); termination of unbounded saturation
(undecidable); optimistic analyses combined with rewriting on loops (one
recent algorithm, not production); a persistent e-graph across passes
(Tamagoyaki's aim), which would make every pass read a second form of the
program.

### 10.4 Inside P0's cutover, or after it

**Recommendation: Tier 1 inside P0; Tier 2 after.**

For Tier 1 inside:
- P0 rewrites canonicalization anyway (L13's configuration and DRR
  printing, 04 T4's one view of a match, the fourteen region patterns,
  §6). Under D56 nothing is built before the cutover is whole, so writing
  the greedy redesign now and an e-graph later writes canonicalization
  twice and culls one: the hard-cutover rule (D6) says write the final
  form once.
- Tier 1 is not research: it is Cranelift's production design since 2022,
  bounded by construction, and our IR fits it better than Cranelift's (the
  region tree is the dominator tree; SSI removes contexts; the effect
  query and C3 decide what floats).
- Every fact it reads is already P0's: the effect API (D9, D27), C3, D41's
  domains, D48's typed families, refined case binding, guard refinement
  (D21), tail kinds (D30), D24's identity, lifetimes as tokens (D63), the
  specification (D16), dense ids and arenas (perf-sources R5, R6), and
  determinism (DP-34). Nothing in it waits on another proposal.
- It deletes causes P0 already names: patterns on every visit of a many-region
  op (perf-sources C12), the clone-per-question probe (C13), phase
  cycles (c179ab2d), and DRR's one-use guesses.
- D69 already brings an e-graph into P0; the optimizer is the consumer
  that has a P0 path.

Against it, and why it does not decide: one more engine in D56's one
build, measured only at qualification. Its work is capped per insertion
and its walk linear, so its failure mode is a constant to tune, not a
wall; and the alternative's cost is certain (a redesign built and culled).

For Tier 2 after: it is where the owner's "nasty, unintuitive"
optimizations are, and where the record shows an order of magnitude in
compile time, NP-hard extraction and undecidable termination. Each item
lands as its own cutover with its measurement, extending Tier 1's engine
and rule language, never beside them.

### 10.5 Questions and records

*For the owner, one at a time, each with its full context in this file:*
1. **D69's "built once"** (§8): read as one specification, one design and
   one set of fixtures, with a core on each side of the boundary
   (recommended); the only literal "one engine" readings move a consumer
   across the boundary and each breaks a rule (§8.2).
2. **Tier 1 inside P0** (§10.4): the e-graph as the one simplifier of
   `idr` functions before counting, replacing L13 §2.4-2.5's greedy
   redesign at those points (recommended), or after P0, with the greedy
   redesign built and culled.
3. **R4's scope in P0** (§8.5): layer 3's union-find and hash-consing for
   O7, its saturation, relational e-matching and slots at R5
   (recommended), or layer 3 whole in P0 with no P0 consumer on the Idris
   side.

*For the coordinator to record, if the owner takes the recommendations:*
rules printed once as e-graph tables, DRR not printed (amends L13 §2.5 and
G DP-66); C7's specification depends on layer 3's rule-language module;
D34's destination cells declared `Allocate` on `identity` (L01, L10); L01
I3 made a prerequisite of the e-graph; 0015 §3's non-consumer line
replaced by this design; L14's choice of trace zone or action for the
pass's per-function unit.

## 11. Sources

- Ours: `AGENTS.md`; `.claude/skills/{representation-first,testing-by-search}/SKILL.md`;
  `proposals/0000-mlir-native.md` (§2 whole, D57 to D69; §3 C1, C3, C4;
  §5); `proposals/0015-relational-core.md` (whole), `0011-data-oriented-frontend.md`
  (§4.6 to §4.8, §8, D12), `0013-typechecker.md` (§2.1 to §2.3);
  `audits/p0/verify/{status,L01-effects-ops,L02-effects-rows,L04-families,L13-ops-canon,L14-analyses,L18-defunc-optimizer}.md`;
  `audits/p0/synthesis/G-coordinator-decisions.md` (DP-25, DP-26, DP-29),
  `F-decisions.md` (DP-25); `audits/p0/04-canon.md` (§6, C08, C12, C60,
  QL5); `audits/p0/wave1/5.7-library.md` (E1 to E3, M11, §5.7.3);
  `audits/p0/design/{perf-sources,match-and-counting,one-source}.md`;
  `foreign/idr/lib/IR/Canon/{CaseOfCase,Sink}.cpp`,
  `foreign/idr/lib/Transforms/Pipeline.cpp`;
  `third_party/Idris2/libs/base/Data/List.idr:992-1122`.
- MLIR at the pin: `include/mlir/IR/{RegionKindInterface.h,OpBase.td}`,
  `lib/Transforms/Utils/CSE.cpp`, `include/mlir/Dialect/Arith/IR/ArithOps.td`.
- Cranelift (wasmtime aceb6b0f): `cranelift/codegen/src/egraph/{mod,elaborate,cost}.rs`,
  `cranelift/codegen/src/opts/{README.md,skeleton.isle}`; C. Fallin,
  "The acyclic e-graph: Cranelift's mid-end optimizer",
  <https://cfallin.org/blog/2026/04/09/aegraph/> (read 2026-10-21), and
  the EGRAPHS 2023 slides <https://cfallin.org/pubs/egraphs2023_aegraphs_slides.pdf>
  (not read).
- Papers in `sources/papers/`: `willsey-2021-egg` (03, 04, 05, 06),
  `zhang-2023-egglog` (overview, implementation), `zhang-2022-relational-ematching`,
  `yang-2021-tensat`, `wu-2026-slotted-egraphs`, `pal-2023-ruler`,
  `koehler-2021-sketch-eqsat` (listed, not read).
- Papers fetched (source read in `/tmp/eqsat-research/`): Tate, Stepp,
  Tatlock, Lerner, "Equality Saturation: a New Approach to Optimization",
  LMCS 2011, arXiv 1012.1802; Merckx et al., "E-Graphs as a Persistent
  Compiler Abstraction", arXiv 2602.16707v2 (and "eqsat", arXiv
  2505.09363, not read); Flatt et al., "Efficient Extraction for
  Effectful E-graphs", OOPSLA 2026, arXiv 2609.31887, doi:10.1145/3839530.
- Code fetched: DialEgg artifact <https://github.com/AzizZayed/dialegg-cgo-artifact>
  (Zayed and Dubach, CGO 2025, doi:10.1145/3696443.3708957).
- Read through abstracts or search summaries only (weaker ground): Schneider
  et al., "Slotted E-Graphs", PLDI 2025, doi:10.1145/3729326; Singher and
  Itzhaky, "Colored E-Graph", arXiv 2305.19203; Hou, Laddad, Hellerstein,
  "Towards Relational Contextual Equality Saturation", arXiv 2507.11897;
  Arbore, Cheung, Willsey, "Optimism in Equality Saturation", arXiv
  2511.20782; Suciu, Zhang et al., "Semantic foundations of equality
  saturation", arXiv 2501.02413; Zhang and Flatt, "Ensuring the
  termination of equality saturation for terminating term rewriting
  systems", EGRAPHS 2023; Cheng, Coward et al., "SEER", ASPLOS 2024,
  doi:10.1145/3620665.3640392; "Equality Saturation for Optimizing
  High-Level Julia IR", arXiv 2502.17075.
