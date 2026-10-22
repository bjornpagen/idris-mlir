<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the narrow e-graph, in MLIR's form

Status: written 2026-10-21 for D106 and D107
(`proposals/0000-mlir-native.md:1557-1592`, *read*), with D108 and D109
(`:1593-1620`). D106 keeps the e-graph narrow: it replaces greedy
rewriting on our ops and nothing else (D98, `:1446-1465`), its rules are
today's local patterns with the choice per arm, algebra and theorem rules
only one-way and narrowly triggered.
D107 builds the optimizer's e-graph from MLIR's own mechanisms in C++,
upstream first and patched where they fall short, its rules and laws
generated from the dialect's Idris specification; it leaves this file one
question: the e-graph's exact MLIR form. Two forms are weighed: **E**, the
research `eqsat` dialect and its Tamagoyaki pipeline (classes as ops in
the IR, e-matching through a PDL lowering, the hash-cons from CSE,
analyses through the dataflow framework), and **T**, a pass holding its
own compact tables over MLIR's ops, Cranelift's aegraph style
(`egraph.md` §4, narrowed). Effectful ops stay in D103's partial-order
skeleton (`:1508-1525`) in both.

Grounds as in the siblings: *read* (path:line or URL), *measured*,
*read (agent)* (read by this task's reading agent where named),
*recalled*, *conjecture*, *decision* (proposed here, open to review).
MLIR at the pin in `.toolchain/llvm-project` (`M/` below is its `mlir/`).
Nothing was built or run; nothing in the repository changed but this
file. The record of the route D107 did not take is `machine.md`, whose
bug catalogue (§2 there, 77 real bugs of egg, egglog and Cranelift, every
one read) this file uses.

## 0. In plain words

- **The narrow job is small.** On real code the frontend's largest
  per-function e-graph is 2,534 nodes, the median function 3 ops, and the
  local rules (set A) cost 0.28-1.35 s over the whole frontend on one
  thread and never reach a budget (`workloads.md` §0, §4, *measured*
  there). Any form that holds a function's floating ops, applies about a
  dozen rule families, joins each node with its rewrites and extracts
  greedily is enough. The form is chosen for what it makes unwritable and what it
  reuses, not for speed (D97).
- **E reuses the most upstream machinery and fits our IR least.** Its own
  authors scope it to "only pure, straight-line code fragments" and leave
  structured control flow, which needs scope-aware rewriting and
  extraction, unexplored (Tamagoyaki `paper.tex:626-634`, *read* in
  `egraph.md` §1.3). Our matches are regions, and the choice per arm is
  the one new thing D106 asks for. Its classes live in the IR, whose
  normal form no verifier checks; its e-matching lowering exists only in
  xDSL (Python); its working C++ (Tamagoyaki, 5,174 lines) keeps ranks
  in a map keyed by pointers and vendors a private MLIR header.
- **T reuses what upstream has for this job and needs no upstream
  patch.** It is `egraph.md`'s Tier 1, an acyclic e-graph with rules at
  insertion and no rebuild, which is Cranelift's running form. It reuses
  the effect interfaces (through our one effect query), the traits and
  folds (constants only: a fold may rewrite its own op, which
  a question must never do), the rewriter and builder for writing back,
  the parallel nested pass. Its tables are dense typed arrays; rules come
  from the specification as `constexpr` tables read by templates; D41's
  templates are its analyses directly, with no hook and no dataflow state
  per value.
- **What C++ can make unwritable, and what it cannot.** Typed ids per
  kind, ids that never leave the pass, classes immutable once made (so no
  id goes stale and no rebuild exists to stop early), enums for every
  choice, phases as types moved from one to the next, analyses computed
  once by a meet, positive weights and an acyclic graph by construction,
  no pointer-keyed map, no recursion. C++ cannot check linearity (a use
  after a move compiles) or bounds (an index is a number): those become a
  lint and a minting discipline, named in §3.4.
- **Recommendation: T** (*decision*, for the owner, §6): `egraph.md` §4's
  engine narrowed to D106's scope, in the solver layer, named as what it
  is. The "upstream patched" step of AGENTS.md is weighed, not skipped:
  `eqsat` is not upstream (no RFC found), and adopting it means carrying
  a research dialect, a PDL lowering ported from Python, and scope-aware
  extraction as our patches.

## 1. What the narrow scope needs

| need | from | in E | in T |
| --- | --- | --- | --- |
| the floating ops of one function, hash-consed | `egraph.md` §2.1 (the effect query decides) | `equivalence.class` ops grouping values in the IR | a node table per function, dense ids |
| set A: known-constructor field and match, uniform arms, folds, big-integer folds, `lin.use(lin.enter)`, eta on the refined scrutinee (D105), `str.head` of `str.cons`, leaf inlining | `workloads.md` §1.3 (*read*) | PDL patterns, applied without replacing | rules from `constexpr` tables, applied at insertion |
| the choice per arm (case-of-case where some arms fold) | `workloads.md` §3.3: 22-29% of sites mixed (*measured* there) | not expressible: classes are block-local, regions are not explored | a skeleton rule over the region tree with per-arm costs (§4) |
| one-way algebra, narrowly triggered | D106 | a PDL pattern with a benefit | a rule with `Simplify` direction (`egraph.md` §3.1) |
| D103's skeleton: effectful ops ordered per resource, one-way rules | D103 | the ops stay as IR ops between classes | skeleton arrays per region, never hash-consed |
| D41's analyses (words, intervals) | D41 | the paper's dataflow lattices met per class; no solver in the code (§2.1) | the template instantiated over the domain, one array per class |
| writing back | `egraph.md` §4.2 step 7 | an extraction pass, then a replacement pass | scoped elaboration through `RewriterBase` |
| determinism at any thread count | DP-34, `egraph.md` §4.4 | IR order | walk-order ids, table-order rules, ties by id |

## 2. E: the `eqsat` dialect and Tamagoyaki, against our IR

### 2.1 What it is

Two papers and one implementation, by Merckx, Lopoukhine, Coward, Cheng,
De Sutter and Grosser: the `eqsat` dialect (arXiv 2505.09363, EGRAPHS
2025, an xDSL prototype; `[E]` below), Tamagoyaki, "E-graphs as a
persistent compiler abstraction" (arXiv 2602.16707; `[T]`, the TeX at
`/tmp/eqsat-research/tamagoyaki/x/paper.tex`), and its C++ repository
(github.com/jumerckx/Tamagoyaki at 94c395cf, pinned to llvm-project
040a6419, Apache-2.0; `[TY]`). All *read (agent)* at the lines named,
in `/tmp/eg-mlirform/read/`, except where marked *read*.

- **Representation.** `equivalence.class`, `equivalence.graph` (a graph
  region, so a cycle such as `a + 0 → a` is a use before its definition)
  and `equivalence.yield` (`[T]:605-617`, *read*). A class op exists only
  for a class of more than one member (`[T]:595-601`). Its invariants: a
  class's members are its operands, and a value a class consumes has no
  other use, so the use list is the node-to-class lookup and the class's
  result's uses are its parents (`[T]:662-705`). The union-find is chains
  of classes in the paper (`[T]:693`) and an optional `leader` operand in
  the code (`[TY] include/EquivalenceDialect.td:113-121`). No verifier
  checks this normal form; an unbounded greedy rewrite restores it
  (`EquivalenceDialect.td:137-144, 203-222`).
- **E-matching.** Rules are upstream PDL. The lowering to `pdl_interp`
  is reimplemented in xDSL, the Python MLIR, with `ematch.get_class_vals`
  per operand step, `ematch.dedup` after each made op, and
  `ematch.union` for `replace`, nothing erased (`[T]:729`, *read*; xDSL
  `conversion.py:1640-1667, 2357-2360, 2449-2464`). The C++ runs the
  result on upstream's PDL bytecode with `apply_rewrite` and
  `apply_constraint` hooks (`[TY] src/EmatchTransforms.cpp:62-126`), which
  needs a vendored copy of MLIR's private `lib/Rewrite/ByteCode.h`
  (`[TY] vendor/mlir/Bytecode.h`); no LLVM patch. The lowering exists
  only in xDSL (`[TY] docs/guides/end-to-end.md:79-84`).
- **Hash-cons and rebuild.** The key is upstream's
  `OperationEquivalence` with commutativity ignored
  (`[TY] vendor/mlir/SimpleOperationInfo.h`); the table a fork of
  `ScopedHashTable` with erase and a tree of scopes
  (`include/Utils/MutableScopedHashTable.h`); ranks in a `DenseMap` keyed
  by pointers (`include/Utils/ScopeRepIndex.h:50-53`); rebuild egg's,
  deferred (`src/Utils/CongruenceEngine.cpp:208-435`). The paper admits
  more work than egg at creation and rebuild (`[T]:707-714`).
- **Analyses.** The paper meets MLIR's dataflow lattices per class
  (`[T]:786-806`); no `DataFlowSolver` is in the C++ or its case studies,
  and the working code is xDSL's, which asserts single-use classes
  (`eqsat_pdl_interp.py:604`). Upstream's `IntegerValueRange` has only a
  join, a range union (pinned `M/include/mlir/Interfaces/InferIntRangeInterface.h:140-146`,
  *read (agent)*), not the meet a class needs.
- **Extraction.** A selection pass writes the chosen member's index, a
  replacement pass keeps it (`[T]:767-778`). Greedy selection stops
  silently after 100 sweeps (`[TY] src/EquivalenceTransforms.cpp:331-334`);
  an ILP (HiGHS) has no time limit (`src/EquivalenceSelectIlp.cpp:19-46`);
  extracted ops are reordered by `computeTopologicalSorting`, safe only
  because all are pure (`[T]:771-773`).
- **Control flow and effects.** "Only pure, straight-line code
  fragments" (`[T]:627-634`, *read*); PDL cannot match regions
  (`[E]:833`). The code nests graphs inside speculatable ops' regions
  (`scf.for`, `src/EquivalenceTransforms.cpp:187-218`) and leaves
  non-speculatable ops unhashed (`src/Utils/HashConsPatternRewriter.cpp:73-78`).
  `cranelift-mlir` in the same repository is a Cranelift-style skeleton
  (`cranelift-mlir/src/Cranelift/CraneliftPasses.cpp:41-209`) that builds
  its graph at module level from a function pass (`:90, 224-241`) and
  recurses through `std::function`.
- **Limits and determinism.** `max-iters` 4, `max-nodes` unlimited
  (`include/EmatchDialect.td:207-218`); every iteration re-walks every op
  in IR order. The Herbie runs hit a 4,000-node cap on every benchmark,
  so rewrite order shapes the result (`[T]:854, 889-891`).
- **Measured** by its authors: saturation at 0.78× egg's speed on
  Herbie's rules (`[T]:901-913`); never against `canonicalize`. The
  nearest such figure is DialEgg's: 162 ops in 4,939 ms against
  `canonicalize`'s 0.6 ms (CGO 2025, §8.5, *read (agent)*).
- **Its gain**: the e-graph is IR, so it persists across passes and
  prints as MLIR. Nothing of it is upstream in LLVM; no RFC was found.

### 2.2 What it reuses upstream

- the IR itself as the store: operations, use lists, the printer, the
  verifier, `mlir-opt` for debugging;
- PDL, `pdl_interp` and the bytecode matcher (`M/lib/Rewrite/ByteCode.cpp`),
  through hooks and a vendored private header;
- `OperationEquivalence::computeHash` and `isEquivalentTo`, CSE's
  hashing (`M/lib/Transforms/Utils/CSE.cpp:27-44`, *read*), with a forked
  scoped table;
- `computeTopologicalSorting` for the write-back.

### 2.3 What our IR would need it patched for

- **Regions.** An `idr.match` is a region per case (AGENTS.md's control
  flow rule); E's classes are per block and its authors leave scopes
  unexplored. Placing a pure value into the arm that uses it, hoisting it
  out of a loop, and choosing per arm are the jobs `egraph.md` §2.2 and
  D106 give the e-graph. Scope-aware matching and extraction over
  classes in nested regions is research, not a patch.
- **The skeleton.** D103 orders effectful ops per resource subtree with
  one-way rules. In E they stay ordinary ops between classes; the
  one-way skeleton rules are destructive patterns run outside the
  e-graph, which is today's greedy driver again for those rules (D98
  removes it).
- **Non-destructive application.** Upstream's pattern application
  replaces (`RewriterBase::Listener::notifyOperationReplaced`,
  `M/include/mlir/IR/PatternMatch.h:370-403`, *read*); E's union and
  dedup live in a lowering that exists only in Python. Carried, it is a
  port of xDSL's e-matching lowering into upstream's C++
  `PDLToPDLInterp`, plus a patch exposing `PDLByteCode`'s match and
  rewrite in place of the vendored private header, as
  `upstream/<bug>/llvm.patch` with tests and a plan (*conjecture* on
  size: thousands of lines, from xDSL's `conversion.py` at over 2,400).
- **The normal form, verified.** A class's operands having no other use
  must be a verifier rule (or unwritable), not repaired by an unbounded
  greedy rewrite: D98 removes greedy rewriting, and AGENTS.md forbids a
  fixpoint with no bound in a pass that only optimizes.
- **Pointer-keyed state.** Ranks in a `DenseMap` over pointers and a
  hash-cons keyed by `Operation *` are what AGENTS.md's C++ rules forbid
  for per-node state of ours; carried, they would be rewritten over dense
  ids, which is most of T's table anyway.
- **CSE's limits over our ops.** CSE skips ops with multi-block regions
  and treats only a single read as a removable effect (`CSE.cpp:250-290`,
  *read*), so the key it lends covers our floating ops and nothing else.
- **Rules that expand a term** (`x → log(exp(x))`) cannot be written in
  PDL (`[T]:850`); D106's one-way rules mostly shrink, so this binds
  little.
- **Rules from the specification.** `specgen` would print PDLL or PDL as
  it prints TableGen (an output, not a language of ours, `AGENTS.md`
  "Anything of ours above the C++ is Idris"); the bytecode interpreter
  runs them.

### 2.4 Bugs it leaves writable

The IR is the store, so every class is a mutable op. A pattern, a fold
(which may rewrite its op in place, §3.2), or another pass between two
e-graph steps can change a member without the class knowing: the stale
id and missed-congruence classes of `machine.md` §2.1 (egg E2, E7;
egglog G2, G6; Cranelift W10), now in IR form, with no type to stop them.
Its documented analyses are dataflow states per value, the shape
AGENTS.md records at 627 GB when the state was the whole program's
(ffa91113), and upstream's interval lattice has no meet. Its silent caps
(100 sweeps, 4 iterations) are reasons a result changes with no type to
say so.

## 3. T: a pass with its own tables over MLIR's ops

### 3.1 The pass: `egraph.md`'s Tier 1, which D107 brings back

`egraph.md` recommended for P0 a region-tree acyclic e-graph per
function with rules applied eagerly, and left saturation for later
(`egraph.md:62-72, 81-85`, *read*). D106's scope is that Tier 1, and it is
Cranelift's running form, not research:

1. *Number* one function's ops, values and regions once, in walk order
   (perf-sources R5): dense ids, each region its depth.
2. *Classify* each op by the one effect query (D9): floating, unique,
   ordered, region, pinned (`egraph.md` §2.1). The ordered and region ops
   form D103's skeleton, per region, in arrays.
3. *Build* the floating ops in walk order: children to their classes; a
   hit in the hash-cons, scoped by region depth as Cranelift's is, maps
   the result; a miss makes the node, computes its analyses, and runs the
   rules rooted at its kind, each result built the same way and joined to
   the new node's class as it is made. Work per insertion is capped in
   program units, and the function's budget is B nodes per op counted
   from the program alone (D108): a spent cap keeps the original form,
   less optimized, never refused.
4. *No rebuild.* A class is complete when it is made and never changes
   after: SSA walk order builds every operand's class before its users,
   so a rule rooted at a new node sees finished classes. "Once we create a
   node, we never update it" (Cranelift's account, `egraph.md` §1.2).
   Cranelift measured what this loses: two equalities in about four
   million nodes (*read* there); on our IR it is unmeasured, since
   `workloads.md` saturated set A (an upper bound). A rebuild is added if
   a measurement shows the gap, not before.
5. *Skeleton rules*, one-way, in order: a guard proved or refuted, a match
   on a known constructor spliced, the choice per arm (§4).
6. *Extract* greedily, bottom-up in creation order, ties to the larger id
   (`egraph.md` §4.2 step 6).
7. *Elaborate* the region tree from the skeleton: each operand's best node
   placed in the current scope unless an enclosing scope holds it, hoisted
   when no operand is defined in the loop, constants rematerialized per
   use region, a unique node at most once per path (`egraph.md` §4.2
   step 7), written through `RewriterBase`.
8. The pipeline's verifier runs after it, as after every pass.

### 3.2 What it reuses upstream, and the one hazard

- **Effects**: `MemoryEffectOpInterface` and our ops' rows, through D9's
  one query; never a second classifier.
- **Traits**: `Commutative`, `Idempotent`, `Involution`, read into rule
  tables by D51's backend (`egraph.md` §3.3), never restated.
- **Folds, for constants only.** An op's fold is its meaning and the
  constant analysis calls it (`egraph.md` §3.3). But a fold may rewrite
  its own op: `foldCommutative` moves constant operands to the end in
  place and reports success "if the op was modified"
  (`M/lib/IR/Operation.cpp:862-878`, *read*), and an in-place fold is
  MLIR's convention. A question answered by mutating IR is a recorded
  bug (1b2e31da, AGENTS.md). So the pass calls `Operation::fold` only
  when every operand's class holds a constant (where the trait fold moves
  nothing), on input ops, and keeps an attribute result; a fold that
  answers with a value or would need a non-constant operand is not asked.
  The identities a partial fold finds (`x + 0`) come from rules generated
  from the specification and from traits. A rule-made node is never
  folded through an `Operation`: our ops' folds are D41's templates,
  called directly; an upstream op a rule makes is rare in set A (its
  right sides select existing classes or make constants).
- **Writing back**: `OpBuilder` and `RewriterBase` with its listener
  (`PatternMatch.h:370-403`), so upstream's notifications and the
  verifier see ordinary edits.
- **Threading**: a nested function pass under the pass manager, one arena
  per worker, no state shared (`egraph.md` §4.4).
- **Not reused**: CSE's map (the hash-cons is the pass's own table over
  typed keys), PDL (rules are generated tables, matched by templates),
  the dataflow framework (analyses are arrays per class).
- **Patches**: none needed for the narrow scope.

### 3.3 Rules from the specification, and D41's templates

- The rules and laws are data in the specification, generated into the
  C++ as the TableGen is, never run in Idris (D109). `specgen` prints,
  per rule, the root kind, the pattern flattened in
  preorder, the conditions as enum values with operands, the right side
  as a builder program over slots, and the direction, as `constexpr`
  tables (`egraph.md` §3.4); the engine's matchers are templates over
  them, indexed by root kind when the compiler is built (D7; perf-sources
  R1). The same rules reach the elaborator's side only as far as it needs
  them (D107: congruence, no rules).
- D41's templates instantiate over the analysis domain inside the engine
  (`Analysis` concept, `egraph.md` §4.3): the folder over words is the
  constant analysis, the interval instance the range analysis. No hook,
  no link-time symbol, no `DataFlowSolver`; the D86 strain of
  `one-engine.md` §5.3 is gone with D86.

### 3.4 The facts, in C++ (D7), that make `machine.md`'s bug classes unwritable

| bug class (`machine.md` §2.1) | in T | what C++ cannot do, and the substitute |
| --- | --- | --- |
| ids mixed or out of range (egg E3, E10) | `enum class ClassId : std::uint32_t`, `NodeId`, one type per table; an id is minted only by the table that holds it (private constructor, the table a friend); no id leaves the pass (its API takes a function and returns edits) | bounds are not static: an id is in range by minting, not by type |
| a stale id after a merge (E2, G6, W10, W15) | classes are immutable once made (§3.1 step 4): nothing merges after creation, so no stored id goes stale. Cranelift removed its union-find for the "fairly subtle bugs" the canonical-versus-latest split caused (wasmtime #10471, `machine.md` §2.1) | none needed |
| matching a graph mid-repair, a query that writes (G2, G22) | no repair phase exists; the pass's phases are types moved one into the next, `Built` → `Extracted` → elaborated edits, and a rule sees only finished classes | a use after a move compiles: `bugprone-use-after-move` (clang-tidy) and Clang's typestate attributes (`consumable`, `callable_when`, `return_typestate`, *recalled*) are lints, not types |
| rebuild that never ends or stops early (E7, G9, E11) | no rebuild; insertion recursion is capped per insertion and the build is one walk | none needed |
| analyses not merged or not monotone (E1, W20) | a class's datum is computed once, when the class is made, from its members' data by a meet from a closed set of lattices (D41's domains, a concept) | none needed |
| extraction cycles, overflow (E2, E12, G19, X1) | the graph is acyclic by construction; `Weight` holds `weight - 1`, positive by type; costs saturate in a fixed-width type | none needed |
| choices as flags (E4, G4, R2) | every choice an enum (`Outcome`, `Direction`, the class of an op), never a `bool` (AGENTS.md) | none needed |
| pointer-keyed state, nondeterminism (E20, G16) | dense ids from one walk; the hash-cons keyed by (kind, type id, properties id, child classes), the type and properties ids interned per function in walk order (`egraph.md` §4.1), so no address enters a hash; the table is probed, never iterated for a result | none needed |
| unbounded recursion (W13), aliasing (W6) | explicit stacks (D33); tables owned by one arena per worker, handed out as spans | none needed |
| an operand not available where used (W11, W12) | each node records its available region (Cranelift's available block), and elaboration places by the region tree | the placement's correctness is the elaborator's code, reviewed and tested |

## 4. The choice per arm

- **What it is.** Case-of-case moves an outer match into the arms of an
  inner one; where some arms then fold and others do not, the best
  program copies the outer match only into the arms that gain
  (`workloads.md` §3.3: 155,586 sites in the inlined frontend, 22% mixed,
  29% in the benchmarks, *measured* there). Greedy rewriting must choose
  for all arms at once; the e-graph chooses per arm by cost.
- **In T.** A skeleton rule (`egraph.md` §4.2 step 4): for each arm, the
  outer match's result in that arm is a class whose members are "the outer
  match on this arm's value" and, where it folds, the folded value; the
  extraction cost per arm decides, and elaboration copies the outer
  match into the arms that chose it. The arm is a scope in the region
  tree; whether `best` is per scope is `unknowns.md` U12, and for this
  rule it is per arm by construction.
- **In E.** Not expressible without scope-aware classes (§2.3).

## 5. Side by side

| | E: `eqsat` classes in the IR | T: own tables over MLIR's ops |
| --- | --- | --- |
| store | the IR | dense typed arrays, one arena per function |
| matching | PDL, `pdl_interp`, bytecode, patched for union | generated `constexpr` tables, template matchers |
| hash-cons | `OperationEquivalence` keys in a forked scoped table; ranks keyed by pointers | own open addressing over typed keys, scoped by region depth |
| classes | merged by union, rebuilt | immutable once made; no rebuild (Tier 1) |
| analyses | dataflow lattices met per class (paper); none in its C++ | D41's templates over per-class arrays |
| regions, choice per arm | graphs nested in speculatable ops' regions; no scope-aware choice; research | the region tree, scoped placement, per-arm costs |
| skeleton (D103) | non-speculatable ops left in place, unhashed; `cranelift-mlir` a skeleton prototype at module level; skeleton rules destructive, outside | arrays per region, one-way rules in the pass |
| folds | patterns and in-place folds on the IR | constants only, attribute results |
| upstream reused | most: IR, PDL bytecode, `OperationEquivalence`, topological sort | effects, traits, folds, builder, rewriter, pass manager |
| upstream patched | the e-matching lowering ported from xDSL into `PDLToPDLInterp`; `PDLByteCode` exposed; scopes (research) | none |
| bugs left writable (`machine.md` §2.1) | stale classes in mutable IR; rebuild's classes; general dataflow state | use after move and bounds, as lints; Tier 1's missed equalities, unmeasured |
| limits | `max-iters` 4, `max-nodes` unlimited, greedy extraction silently capped at 100 sweeps | B nodes per op from the program (D108), caps per insertion in program units; a spent cap keeps the original form |
| debugging | prints as MLIR | needs a dump of its tables (Tracy zones, a printer) |
| persists across passes | yes | no: rebuilt at each of D98's points |

## 6. Recommendation, and the owner's decision

*Recommendation*: **T** (*decision*, open to review), because the narrow
scope's one new demand, the choice per arm, needs regions that E's
authors left unexplored; because T needs no upstream patch where E needs
research-sized ones; and because T's typed tables and phases make the
recurring bug classes of real engines unwritable or linted, where E's
mutable IR leaves the most frequent of them (stale and non-canonical
classes) writable. What E buys and T gives up: the e-graph printed and
verified as MLIR, and kept across passes; D98's points rebuild it each
time, which at these sizes costs milliseconds (`workloads.md` §4).

*For the owner, one question*: **is the optimizer's e-graph T (a pass
with its own typed tables over MLIR's ops, `egraph.md` §4's Tier 1
narrowed, in the solver layer as our own solver) or E (the research
`eqsat` dialect, carried with its PDL lowering ported from xDSL and
extended to regions)?** T costs our own
solver of about the size `egraph.md` §4 estimated, narrowed, and a
printer of its tables for debugging; E costs carrying a research dialect
and its patches, and the region work its authors did not do.

*For the coordinator to record, if the owner takes T*: `egraph.md` §4's
Tier 1 is the pass's design, narrowed to D106 (no Tier 2, rules at
insertion, no rebuild until a measurement asks, the choice per arm as a
skeleton rule); folds called with constant operands only (§3.2); §3.4's table as the pass's review list;
`one-engine.md` §5's boundary, hooks and printed engine withdrawn with
D86.

## 7. Sources

- Ours: `AGENTS.md`; `proposals/0000-mlir-native.md` (D2, D7, D9, D41,
  D97-D109); `audits/p0/design/egraph.md` (§1.2, §1.3, §2.1, §3, §4);
  `egraph-full/workloads.md` (§0, §1.3, §3.3, §4, §5), `machine.md`
  (§2, §4.2, §4.5), `unknowns.md` (U12);
  `foreign/idr/lib/Transforms/Pipeline.cpp:85-120`,
  `foreign/idr/lib/IR/Canon/`, `Fold/`.
- MLIR at the pin: `lib/Transforms/Utils/CSE.cpp:24-330`,
  `include/mlir/IR/OperationSupport.h:1386-1451`,
  `lib/IR/Operation.cpp:620-665, 855-890`,
  `include/mlir/IR/PatternMatch.h:370-480`,
  `include/mlir/Rewrite/PatternApplicator.h:49-85`,
  `include/mlir/Analysis/DataFlowFramework.h:325`.
- Outside: Tamagoyaki and the `eqsat` dialect (Merckx et al., EGRAPHS
  2025, arXiv 2505.09363; arXiv 2602.16707), its TeX at
  `/tmp/eqsat-research/tamagoyaki/x/`; DialEgg (Zayed and Dubach, CGO
  2025), `/tmp/eqsat-research/dialegg/repo`; Cranelift's aegraph through
  `egraph.md` §1.2. Read by this task's agent: arXiv 2505.09363 and
  2602.16707 (sources in `/tmp/eg-mlirform/read/`), Tamagoyaki at
  94c395cf and its case studies, xDSL at 64fa206e, the DialEgg paper
  (doi:10.1145/3696443.3708957) and artifact.
