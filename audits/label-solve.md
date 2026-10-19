<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The label solve is quadratic because of how it represents sets

`tests/defunc-tag-limit` times out (60 s) in `idris-mlir-opt --idr-defunctionalize`.
The cause is not the size of the answer. The pass emits **one** sum of
65,537 constructors. The label solve (`foreign/idr/lib/Analysis/Labels.cpp`)
reaches that answer with about 4.3·10^9 `(node, label)` work items and
stores as many labels, because each class of its union-find owns a copy of
its set. The measured growth is quadratic in both time and memory. At
65,536 labels the run would need roughly 300 GB.

This audit covers four things, in this order:
1. How the solve works now, and where the quadratic time and space come from.
2. Which nodes end up with the same set, and what the general case allows.
3. A representation in which a node never owns a set. That makes the blow-up
   impossible to express, gives the same keys and sums as today, and has a
   stated bound.
4. Every other place in the compiler that follows the same pattern. Three of
   them also sit on this fixture's path, so they must be fixed before it
   can pass.

No compiler source was changed. The measurements used `build/dev`, a Debug
build from 2026-10-19 04:15. It includes every change to the files involved,
the last of which landed at 02:35. A Python prototype of the proposed solve
and the scaled inputs are in `/private/tmp/label-solve/` (`proto.py`, `in*.mlir`).

## 1. How the solve works now

### The graph (LabelSites.cpp)

`Graph::walk` runs over the program once. For each op it asks `flowEdgesOf` for the
op's flow edges and keeps those that carry a label (a closure or a
suspension). A *point* is one of three things:
- a value (a function's parameter counts as its entry block argument);
- an anchor (a field of a data type, the elements of a shaped type, or the
  forced state of a lazy type);
- a function's result, identified by its name and position.

`keyOf` normalizes each point to a `PointKey`, and `nodeOf` gives each key
one `Node`. The edge kinds are:
- `Flow` becomes `link(from, to, linkOf(carriers))`. That is `Include` for a
  closure carrier and `Unify` for a suspension, since a suspension's two
  points share one cell.
- `Unify` merges two classes. `sink` also unifies, when an operand moves
  into a second point, so that every use has one slot.
- `Source` gives a node its label (`reach(node, label)`).
- `Constant` expands closure constants into a label plus captures, and lays
  constructor constants out at their field anchors.
- `Dispatch` registers an `idr.apply` or `idr.force` on its callee's class.
  Every label already in that class is owed a firing.

### The solve (Labels.cpp)

The solve is a union-find over nodes. Each class holds:

```c++
struct Class {
  llvm::SmallVector<Label, 2> labels;      // sorted by number, owned by the class
  llvm::SmallVector<Node, 2> successors;   // Include targets
  llvm::SmallVector<Dispatch, 1> dispatches;
};
```

The worklist is `OnceWorklist<std::variant<Arrival, Firing>>`, where
`Arrival = (Node, Label)` and `Firing = (Dispatch, Label)`. It is a
`SetVector`: every pair that ever enters it is kept, both in a vector and in
a `DenseSet`.

The operations are:
- `reach(to, l)`: binary search in the root's sorted vector, then a sorted
  insert, then push `Arrival{root, l}`.
- `arrive(node, l)`: for **each successor** of the class, `reach(next, l)`;
  for each dispatch, push `Firing{d, l}`.
- `fire(d, l)`: link the call's arguments to the label's parameters, and the
  label's results to the call's results.
- `include(from, to)`: record a successor and `reach` it once per label the
  source already holds.
- `unify`: `set_difference` twice plus `set_union`, then queue each one-sided
  label as an arrival.
- `solve()`: once the worklist is empty, `attrOf(classes[root].labels)` runs
  for **each root**. It maps label numbers to `FlatSymbolRefAttr`, **sorts
  them by name** (labels are numbered in the order met, not by name), and
  calls `ArrayAttr::get`, which hashes the whole array. Equal sets come out
  as the same attribute, but each root pays for the sort and the hash first.

The result, `labels::Solution`, is already linear: one `ArrayAttr` pointer
per node (`std::vector<mlir::ArrayAttr> labels`), plus the `nodes` and
`sinks` maps. The quadratic part is all inside `Graph`.

### How the solution is read

| reader | what it reads |
| --- | --- |
| `Labels::labelsOf(Value / FlowPoint / FlowAnchor)`, `runs`, `sinkOf`, `function` | `Labels.h` |
| `Slots::keyWith` / `anchorKey` (`Defunctionalize/Keys.cpp`) | `Key{unrestricted(carrier), labelsOf(point)}`. A key is a carrier plus the solve's uniqued `ArrayAttr`, so equal sets give equal keys |
| `Slots::widen` (`Moves.cpp`) | `sinkOf` per use, then `within(a, b)` (subset) |
| `Slots::body`, `labelTag` (`Declare.cpp`) | the key's labels, in name order, as constructors and tags (binary search) |
| `Slots::name` (`Decide.cpp`) | `keyText`: the carrier digest, then each label. A sum's name is a hash of its key's content |
| `observableRuns` (`Pass.cpp`, `Analysis/Effects.cpp`) | `runs(runner)` for every apply and force |
| `SlotTypeConverter` (`Converter.cpp`) | `sinkKey`, `needsCoercion(from, to)` (key equality), `coerce` (one rebuild per constructor of `from`) |
| `--idr-expect=labels=...` (`Expect/Closures.cpp`) | the converted sums, not the solve |

Every reader wants one of three things: a set's **identity** (key equality,
names, tags), its **members in name order** (bodies, dispatch arms), or a
**subset** test (`within`). None of them needs a node to own a copy.

### Where the quadratic work and space come from

In this fixture, n = 65,536. There are n+1 labels: `@l1`…`@ln` and `@base`.

1. **Arrivals are pairs.** One `Arrival` exists per `(class, label)` in the
   final solution. In this program that is (n+5)(n+1) + n + 1 pairs, all
   held by the `OnceWorklist`'s vector and `DenseSet`. This follows the
   termination rule written in `include/idr/Support/Worklist.h`: *"A value
   whose lattice grows with the program, a set over the program's labels
   ... Its solve is a OnceWorklist over (element, member) pairs instead."*
   That rule turns the termination witness into data whose size is
   elements × members.
2. **Each arrival walks every successor.** `@grow`'s `%k` has n+1 successors:
   the n captured parameters `@li.%k`, plus `%r`. Each of its n+1 labels
   arrives once, so that is (n+1)² calls to `reach`. Each call is a find, a
   binary search and a hash-set insert.
3. **Each class owns its set.** n+5 classes each hold the same n+1 labels,
   about 4.3·10^9 `Label`s at 4 bytes each (17 GB) at n = 65,536.
4. **`attrOf` per root.** n+5 roots each sort n+1 `FlatSymbolRefAttr` by
   string comparison, then hash them, and all of them get back the one
   uniqued attribute. That is O(n² log n) string comparisons.

#### Measured curve

Inputs come from the fixture's awk RUN line with 65536 replaced by n.

| n labels | `IdrDefunctionalize` | wall / CPU | peak RSS |
| ---: | ---: | ---: | ---: |
| 1,000 | 1.56 s | 1.85 / 2.02 s | 148 MB |
| 2,000 | 10.4 s | 11.2 / 7.9 s | 374 MB |
| 4,000 | 69.9 s | 71.0 / 34.3 s | 1.23 GB |
| 8,000 | 337.7 s | 339.8 / 150.2 s | 4.69 GB |

CPU time grows ×3.9, ×4.3 and ×4.4 per doubling of n, and memory ×2.5,
×3.3 and ×3.8. Both are quadratic, with constants that are still settling.
At 4,000 and 8,000, wall time is well above CPU time: the run is bound by
memory. Peak RSS at n = 8,000 works out to about 73 B per stored pair.
Extrapolated to n = 65,536 that is about 300 GB, and nearly three hours
of debug CPU time even if the memory were there.

Single-threaded profiles (`sample`, Debug build) split the time like this:

| n | pass | solve: worklist | solve: `attrOf` sort | `Slots::remake` | `layout::fit` | `widen` |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 1.81 s | 0.93 s | 0.40 s | 0.11 s | 0.16 s | 0.01 s |
| 2,000 | 5.55 s | 2.89 s | 1.54 s | 0.32 s | 0.34 s | 0.02 s |
| 4,000 | 45.7 s | 28.9 s | 11.5 s | 1.7 s | 1.4 s | 0.07 s |

The top of the profile is `std::__lower_bound` in `reach`,
`DenseSet<Work>::LookupBucketFor` in `OnceWorklist::push`, and `std::sort`
in `attrOf`. The remaining quadratic columns (`remake`, `layout::fit`,
`widen`) and the verifier are covered in section 4. They are separate
quadratics on this same fixture's path.

The prototype (`proto.py`) counts work on the same graph:

| n | today: `reach` calls | today: pairs = stored labels | proposed: class steps | proposed: label work | proposed: interned labels |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 1,008,007 | 1,008,007 | 4,003 | 1,000 | 2,002 |
| 4,000 | 16,032,007 | 16,032,007 | 16,003 | 4,000 | 8,002 |
| 65,536 | (≈4.3·10^9) | (≈4.3·10^9) | 262,147 | 65,536 | 131,074 |

## 2. Which nodes share a set, and why

### This program

These are the points that hold labels, with their edges. All the edges are
`Include`: no suspension appears, and every use moves into a single sink, so
nothing is unified.

| node | in-edges | set |
| --- | --- | --- |
| `%b` (main) | source `@base` | {base} |
| `%v_i` (case i of `@grow`), i = 1..n | source `@li` | {li} |
| `L` = `@loop`'s `%k` | `%b`, `%g` | F |
| `G` = `@grow`'s `%k` | `L` | F |
| `%r` (`@grow`'s `match_lit` result) | `%v_1`…`%v_n` (case yields), `G` (default yield) | F |
| `Res` = `@grow`'s result | `%r` (return) | F |
| `%g` (`@loop`'s call result) | `Res` | F |
| `P_i` = `@li`'s `%k`, i = 1..n | `G` (capture) | F |

Here F = {base, l1..ln}. One dispatch, the `idr.apply %k(%n)` in `@loop`,
sits on `L`'s class. It fires n+1 times, and each firing adds no edge,
because the apply takes and returns `i64`.

- **`L → G → %r → Res → %g → L` is a cycle of inclusions.** Each node on it
  contains the next, so all five are equal in every solution. Today they are
  five classes holding five copies of F.
- **Each `P_i` has one input, `G`, and no source of its own,** so its set is
  exactly `G`'s. Nothing else can ever flow into it. A firing links a call's
  arguments only to the parameters past a label's captures. `P_i` is a
  capture parameter (`labelEdges` in `IR/FlowOps.cpp`), so no dispatch can
  target it. Today each of the n classes `P_i` stores its own copy of F, and
  each of F's labels walks all n of them.
- **Distinct sets:** F, {base} and the n singletons. That is n+2 sets with
  Σ|S| = 2n+2 labels. Every slot whose key is F shares one sum. After the
  pass widens `%v_i` and `%b` into F's key, the pass reports `1 sums` and
  n+1 constructors (`--mlir-pass-statistics` at n = 4 reports 1 sum and 5
  constructors). The answer is linear. Only the way it is held is quadratic.

### The general case: what can and cannot be made subquadratic

The constraint system has three parts:
- inclusion `S(a) ⊆ S(b)`;
- equality, from a unification;
- conditional edges: for each pair (dispatch d, label l ∈ S(callee d)), the
  label's argument and result edges.

This is Andersen-style inclusion analysis, or 0CFA. Its worst case is cubic
in time, and no subcubic algorithm is known for the general problem
(Heintze & McAllester, *On the cubic bottleneck in subtyping and flow
analysis*, LICS 1997). An adversarial program can also hold Θ(N·L) labels
in genuinely distinct sets. That is not an artefact, though: every distinct
set of a slot becomes its own sum, with one constructor per label. So no
representation can promise subquadratic time for every program while
keeping the same results. What a representation *can* make impossible is:
- the same set existing twice;
- work per `(node, label)` for a node whose set is just one of its inputs';
- a per-root name sort.

Those three are everything this fixture pays for. The options:

| technique | what it does here | verdict |
| --- | --- | --- |
| **Hash-consed sets** (one object per distinct set, union memoized) | `P_i`, `G` and the cycle all point at one F. Space for sets becomes Σ over *distinct* sets | **adopt**. MLton's own 0CFA does this: `closure-convert/abstract-value.fun` line 42, `structure Lambdas = UniqueSet (...)`, with `send` propagating `Lambdas.-` differences. Our port kept MLton's union-find and `coercedTo` but dropped `UniqueSet` (`sources/code/mlton`) |
| **A node points at a class or a set instead of owning one** | already true for unified points (union-find), and for the Solution's output (one `ArrayAttr` per node) | **adopt for the solve's classes**: a `Class` holds a set id |
| **Cycle collapsing** (Tarjan per wave, or Hardekopf & Lin's lazy/hybrid cycle detection) | merges the 5-node cycle into one class | **adopt**, as an SCC condensation at the start of each wave. It is order-independent and terminates structurally; online LCD needs a heuristic trigger |
| **Offline variable substitution / HVN / HU** (Hardekopf & Lin, SAS 2007) | would merge each `P_i` into `G` before solving | **do not adopt**. It needs a second, offline statement of which points a firing can target (parameters past the captures, call results), which duplicates the firing rule. The topological rule "one distinct input set: take its id" gives `P_i` F's identity in O(1) without that second copy. HVN would only save union-find nodes, a constant factor |
| **Difference propagation** | after the first wave, only classes downstream of new edges are recomputed, and only labels new to a dispatch fire | **adopt**, between waves. Within a wave the topological order already makes each class's set final before any successor reads it, so there are no deltas to send |
| **The key's sum as the unit** | a key's label part *is* a set identity. The final `ArrayAttr` is the interned set's printed form, made once per distinct set | **adopt**. `SetId` → `ArrayAttr` is a memo, and `Key` is unchanged |
| **MLIR `DataFlowSolver`** | lattices are stored per anchor and own their value (`Lattice<ValueT>` holds a `ValueT`). A join copies the value. Each change re-visits every dependent. There is no SCC merging, and two anchors cannot share a state. Function results and field anchors would need `GenericLatticeAnchor`s, and an indirect callee is not resolved | **not a fit**. Its per-anchor state is exactly the per-node copy being removed. An `Attribute`-valued lattice would share storage, but would still re-propagate on every change (n² visits here, each with an O(n) join) |
| **MLIR attribute uniquing for the sets themselves** | the final sets are already uniqued `ArrayAttr`s in the `MLIRContext` | **keep for final sets only**. An `MLIRContext` never frees an attribute, so intermediate sets from later waves belong in an interner local to the solve (`llvm::DenseSet`/`FoldingSet` over a `BumpPtrAllocator`), freed when the solve ends |

## 3. The proposed representation

### The data: a class holds a set's identity, never a set

```c++
// A label's rank among the program's labels in name order, given once,
// before the solve: a set's runs are already in the order its ArrayAttr
// and its sum's tags use.
enum class Label : std::uint32_t {};

// An interned label set. Equal sets are one id; SetId{0} is the empty set.
enum class SetId : std::uint32_t {};

class SetTable {                       // local to the solve
public:
  SetId intern(llvm::ArrayRef<Label> sortedUnique);
  SetId unite(llvm::ArrayRef<SetId> inputs);       // see below
  llvm::ArrayRef<Label> members(SetId set) const;  // sorted by rank
  bool contains(SetId set, Label label) const;     // binary search
private:
  llvm::BumpPtrAllocator storage;
  std::vector<llvm::ArrayRef<Label>> sets;         // by id
  llvm::DenseMap<llvm::ArrayRef<Label>, SetId> ids; // content -> id
  llvm::DenseMap<llvm::ArrayRef<SetId>, SetId> unions; // memo, keys in storage
};

struct Class {
  SetId labels;                               // the one field that was a vector
  llvm::SmallVector<Node, 2> successors;
  llvm::SmallVector<Dispatch, 1> dispatches;
};
```

`SetTable::unite(inputs)`:
1. Drop the empty set and duplicate ids.
2. If no id is left, the result is the empty set. If one is left, the
   result is that id, and no label is read.
3. Otherwise, look up the memo by the sorted id tuple.
4. Otherwise, take the largest input. If every other input is a subset of it
   (a binary search per label of the smaller inputs), the result is the
   largest input.
5. Otherwise, do one k-way merge and intern the result.

### The solve: waves over the condensed inclusion graph

The build (`LabelSites.cpp`) is unchanged, with three exceptions:
- `include` only records the edge;
- `reach` from a source adds to the node's own source set;
- labels are ranked by name after the walk (O(L log L)).

The solve then repeats the following until no firing adds an edge:

1. **Condense.** Run Tarjan's SCC algorithm over the roots' successor edges
   (`llvm::scc_iterator` over a `GraphTraits` of the union-find roots, or a
   local Tarjan). Merge each component into one class, the same way `unify`
   merges. A cycle of inclusions is an equality in every solution, so this
   preserves results.
2. **Sweep.** In topological order, set
   `S(C) = unite({own(C)} ∪ {S(P) : P → C})`. Each class is computed once per
   wave, after all of its predecessors. In waves after the first, only
   classes downstream of a new edge or merge are recomputed.
3. **Fire.** For each dispatch d on a class whose set changed, push
   `Firing{d, l}` for each label of the change, using the
   `OnceWorklist<Firing>` that exists today. `fire` adds the label's edges.
   An `Include` edge marks its target dirty. A `Unify` merges two classes
   (`S = unite({S(a), S(b)})`).
4. **Stop** when the wave's firings added no edge and no merge.
5. **Hand over.** Build the `ArrayAttr` once per distinct live `SetId`
   (a memo from `SetId` to `ArrayAttr`, with no sort, since ranks are name
   order). Every node's entry is its root's attribute, as today.

**Termination by construction.** A wave is one Tarjan pass and one sweep,
each a loop over a finite range. A wave after the first exists only because
the firings of the wave before it, each new to the
`OnceWorklist<Firing>`, added an edge or a merge. Firings are drawn from the
finite set of dispatches × labels. No count and no fuel are involved.

### Invariants

- **I1. A set exists once.** `SetTable` maps content to id one-to-one. Two
  classes with equal sets hold equal ids, and no class stores labels.
- **I2. A class with one distinct input set holds that set's id.** Its
  computation touches no label.
- **I3. No cycle of inclusions survives a wave's condensation.** The sweep
  reads a predecessor only after it is final for the wave.
- **I4. A firing is the only per-label unit of work,** and each
  `(dispatch, label)` fires once. Each firing is a dispatch arm that the pass
  emits as a case of the apply's `idr.match`, or of a force's dispatch
  function.
- **I5. Ranks are name order,** so a set's members, its `ArrayAttr` and its
  sum's tags share one order. `labelTag`'s binary search stays valid.

### What it deletes

From `Labels.h` and `Labels.cpp`:
- `Arrival`, the `Work` variant and its `std::visit` in `solve`;
- `Graph::arrive`;
- `reach`'s sorted insert and the arrival it pushes;
- `include`'s per-label loop;
- `unify`'s `onlyInto`/`onlyFrom`/`both` and the arrivals it queues (it
  becomes `unite` on the two ids);
- `Class::labels` as a vector;
- `attrOf`'s sort and its per-root call;
- "numbered as met" (`labelId`'s lazy numbering becomes a rank).

The sentence in `Support/Worklist.h` that tells a set-valued solve to use
`(element, member)` pairs is replaced by the argument above: a once-set of
firings, plus a sweep over a finite DAG.

`OnceWorklist<Firing>`, the union-find, the build and `Solution` all stay.
Readers see the same `ArrayAttr`s.

### The bound

Define:
- P: points with a node;
- E: edges, static and fired;
- L: labels;
- F: firings, Σ over dispatches of |S(callee)|, which is the number of
  dispatch arms the pass emits;
- C: Σ |S| over the distinct final sets, which is at most the constructors
  the pass emits (`numConstructors`);
- W: waves;
- M: the label work done inside `unite`.

Then:
- **Time:** O(L log L + W·(P + E)·α(P) + M + F + C).
- **Space:** O(P + E + F + Σ|S| over the live interned sets). At the end of
  the solve the live sets total C. Intermediate sets that no class
  references can be dropped after each wave, by counting references on
  `SetId`s.

What bounds M is the following. A class whose inputs are one distinct set
costs O(indegree) and reads no label (I2). Otherwise, `unite` costs
O(Σ |smaller inputs| · log L) when the result is the largest input, or
O(Σ |inputs|) to build a new set that is strictly larger than each of
them. Each distinct input tuple is paid for once (the memo). A program that
can force M to grow beyond its output is one with genuinely overlapping,
distinct unions. That is the inclusion analysis's own cost (the cubic
bottleneck), and today's solve pays it too, plus the duplication on top.

**The case this fixture tests can no longer be expressed.** "n nodes each
holding a copy of one n-label set" cannot be represented (I1). "Each of the
set's labels visiting each of the n nodes" is not a unit of work (I2, I4).
For `defunc-tag-limit` the numbers are:
- P = E = 2n+6;
- W = 1, because the one dispatch adds no edge;
- M = n, the cycle class's union of n+1 singletons;
- F = n+1;
- C = 2n+2.

So the solve is **O(n log n)**, and the log comes only from the name ranking.
The prototype measures 262,147 class steps, 65,536 label steps and 131,074
interned labels at n = 65,536, against about 4.3·10^9 today.

### Keeping results identical, and how a test checks it

Both solves compute the **least** solution of the same monotone system,
over a finite powerset lattice: the same inclusions, the same equalities and
the same conditional edges, so the solution is unique. Condensation equates
only sets that are equal in every solution. The sweep computes, for the
edges present, the least sets that satisfy them. Firings add exactly the
edges whose condition holds, and the loop stops exactly when none is new.
So every point gets the same set. With name ranks, that gives the same
`ArrayAttr`, so the same `Key`, the same sum, the same content-hashed name
and the same tags.

On the evidence side, `proto.py` runs today's algorithm and the proposed one
on 3,000 random constraint graphs. Those graphs include unifications and
dynamic edges, and 1,785 of them need two to seven waves. Every node got
the same set in both.

The tests:
- **The existing fixtures state the keys by behaviour.** These are the
  `defunc-*` fixtures (`defunc-many-labels`, `defunc-growing`, `defunc-cycle`,
  `defunc-coerce`, `defunc-memo-*`, `defunc-lazy`, `defunc-sum-names`,
  `defunc-capture-field`, `defunc-choice`, `defunc-curried-apply-poison`,
  `defunc-evaluated`, `defunc-force-call`, `defunc-grades`,
  `defunc-ioref-closure`, `defunc-match-field`, `defunc-state`,
  `defunc-unreached-cell`, `defunc-untaken-region`), together with
  `effects-forced-labels`, `effects-memo-label`, `expect-closures` and the
  `lazy-*` and `runtime-closure-*` programs. They check
  `--idr-expect=labels=@f:result:[...]` and `%differential`, and they must
  pass unchanged.
- **`defunc-tag-limit` within its timeout** is the regression check for the
  bound. It passes only once the downstream quadratics in section 4
  (`within`, `DataRemap`'s field walker, the verifier's `namesLabels`) are
  fixed as well.
- **One property, written once, over every defunc fixture:** "the solution
  is closed and justified." The checks, against the `Solution`:
  - every `Include` edge gives `S(from) ⊆ S(to)`;
  - every unification gives `S(a) = S(b)`;
  - every source's label is in its node's set;
  - every fired label's edges hold;
  - every label in `S(v)` has a source that reaches v along the edges, which
    is leastness.

  It would be an `idr-expect` property, or an assertion pass for tests
  only. It states the contract of the solve, not its trace.
- **A one-time migration check, not committed:** solve every program under
  `tests/` both ways and compare `labelsOf` point by point, as the prototype
  does on random graphs. The old solve is deleted in the same change, so
  nothing in the suite compares against it.

## 4. The same pattern elsewhere

The pattern takes three forms:
- a copy of a set or map per node or per value that can grow to n × n;
- a fresh walk per value over a structure whose size is a set;
- a fixpoint over an inclusion graph.

| # | site | pattern | bound | evidence | verdict |
| ---: | --- | --- | --- | --- | --- |
| 1 | `Analysis/Labels.cpp`, `LabelSites.cpp` | each class owns a sorted label vector; a `(node, label)` once-worklist; a name sort per root | Θ(P·L) time and space even when the output is O(P + L) | sections 1 and 2 | **replace** (section 3) |
| 2 | `Support/Worklist.h` (the doctrine) | "a set-valued solve is a OnceWorklist over (element, member) pairs" | elements × members, by design | the comment that produced item 1 | **rewrite** the rule: a once-set of the output-sized events, plus a sweep over a finite DAG |
| 3 | `Transforms/Defunctionalize/Moves.cpp` `within` | `all_of(a.labels, is_contained(b.labels))`: a linear scan per label | O(\|a\|·\|b\|) per widened value. Here n closures × (n+1) = 4.3·10^9 pointer comparisons | 0.07 s at n = 4,000, quadratic | **fix with the solve**: binary search in the name-ordered `ArrayAttr` (O(\|a\| log \|b\|)), or a subset query on the solve's set ids. Needed for the fixture |
| 4 | `IR/DataRemap.cpp` `remakeAll`, per-field `AttrTypeWalker named` | a fresh walker per field, post-order, with `skip` on `DataType`. In MLIR's `AttrTypeWalker::walkImpl` a post-order walk visits sub-elements *before* the callback, so the skip skips nothing, and a `DataType`'s sub-elements are all its labels (`IdrTypes.td`) | fields × labels: (n+1) fields of the sum, each walking n+1 labels. Runs twice (`Slots::remake`, `layout::fit`) | remake 0.11 / 0.32 / 1.7 s and fit 0.16 / 0.34 / 1.4 s at n = 1k / 2k / 4k; the profile is the fresh walker's visited-map rehash | **fix**: `walk<WalkOrder::PreOrder>` (the walk wants only the outermost data types of a shape, which is what its `skip` already says), or one walker shared across fields. Needed for the fixture |
| 5 | `IR/Verify/Program.cpp` `namesLabels` (from `stageRules` per value, and `verify::program` per constructor field) | `Type::walk` makes a fresh post-order walker per call, so every label of every sum in the type is visited per value | values × labels: 2n values of the sum type in `@grow` and `@li`, plus n+1 fields. Runs at every verification: after the pass, and again before printing | parsing, verifying and printing the pass's own output takes 2.3 s at n = 1,000 and 6.6 s at n = 2,000 (single-threaded); in a sampled run at 2,000, `namesLabels` accounts for 2,540 of the 8,976 samples in `verifyOpAndDominance`, across threads | **fix**: pre-order with `skip` at `DataType` (the function's own comment says a data type's body is checked once per type, in `verify::program`), or a per-type cached fact. Needed for the fixture |
| 6 | the cause behind 4 and 5: `DataType`'s immediate sub-elements are its labels (so that `SymbolDCE` and symbol-use queries see them) | any fresh walker per op or value pays \|labels\| per sum it meets | — | — | **keep the sub-elements** (they are the symbol uses) but never walk per value. Also affected: upstream `walkSymbolRefs` (a fresh pre-order walk per op's attribute dictionary) visits every label of each sum in an `idr.func`'s `function_type`. That costs functions × labels for every `SymbolUserMap` (`Analysis/Effects.cpp`, `Optimize/Contify.cpp`, `Optimize/Waves.cpp`) and `SymbolDCE` (`Pipeline.cpp`) after defunctionalization: n functions × n labels in this fixture's program, if those passes run on it. The same goes for `Defunctionalize/Pass.cpp`'s `ConstantOp` legality, which walks each constant per legality query. Measure these once items 1, 3, 4 and 5 are fixed |
| 7 | `Analysis/BindingTimes.cpp` | `bindingTimesOf(fn, component)` interprets the whole component over `(function, tuple)` pairs, and is called once per member (`Optimize/Component.cpp` `takeUp`, `Specialize/Report.cpp`) | k members × (k·t function visits) per call cycle of k functions: quadratic in the cycle's size | not measured | **flag**. The tuples are relative to the member asked about, so sharing one solve needs abstract values relative to every member. Precision must stay the same. Worth its own design |
| 8 | `Analysis/Escapes.cpp`, `EscapesDetail.h` | `Reach::loops`: a sorted `SmallVector` per value, with sorted insertion, copied at every join in a `Lattice<Escape>` | values × loops per function | not measured; loops per function are few | **low risk**, same shape. If loop counts grow, the lattice value becomes an interned set id |
| 9 | `Transforms/Specialize/Specialize.cpp` | `Requester::give`: `is_contained` over a `SmallVector` used as a set (k² for k keys of one origin). `chainOf` walks the ancestor chain per new key (d² over a chain of d) | bounded by the specializations emitted | not measured | **low risk**. The ancestor comparison is the growth check itself. `give` could use a `SetVector` |
| 10 | `Conversion/TailPosition.cpp` | per call, a walk of the rest of its function along `Liveness`' per-block live-in sets | calls × blocks per function | not measured | **flag**: a per-node walk over a reachable region |
| 11 | `Analysis/Effects.cpp` `observableRuns`, `Converter.cpp` `coerce`, `Decide.cpp` `keyText`, `Declare.cpp` `body` | per runner, coercion or key, the key's labels | Σ over keys or dispatches of \|S\|, which is the size of what the pass emits | — | **fine** (output-sized) |
| 12 | `Analysis/Identities.cpp` (drops of `(member, candidate)`), `Narrow/Versions.cpp` (`(value, condition)` goals in one loop), `Analysis/Effects.cpp` (one entry per function), `DataRemap` `remakeAll`'s shared walker, `TypeGraph`'s shared pre-order walker | once-worklists over bounded pairs, or a single walker | linear, or bounded by arity or one loop | — | **fine** |

Fixing the label solve alone does not make `defunc-tag-limit` pass. Items 3,
4 and 5 are each quadratic in the label count on this program, and at
n = 65,536 each would take minutes. They belong in the same change. Each fix
is one line of representation: a binary search over a name-ordered set, and
a pre-order walk whose `skip` means what it says.
