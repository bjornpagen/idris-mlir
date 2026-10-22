<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the machine, the layer the whole e-graph pass is written in

**Closed 2026-10-21 by D107** (`proposals/0000-mlir-native.md:1568-1592`,
*read*): the route this file designs is not taken. There is no Idris
engine printed as MLIR, no sparse library or library layer in P0; the
optimizer's e-graph is built from MLIR's mechanisms in C++
(`mlir-form.md`), the elaborator keeps its own union-find in Idris, and
only the rules and laws are shared. Kept as the record, unexpanded; §13's
questions are moot. What still applies elsewhere: the bug catalogue and
§2's classes (for the C++ pass); §4.2's distance-to-parent union-find
(for the elaborator's own); §5.3's lesson that a running body builds its
proofs from `Bool` tests; and U-M1 (§8), a stock-Idris bug that deletes a
write behind a forged world, which any stock-host body of a linear array
meets.

Status when written: 2026-10-21, for the owner's "we may need to write a
runtime that builds on our idris sparse tensors types to handle the
additional higher level constructs no? so we can fully represent the
entire pass in idris? ... let's flesh it out", re-centred twice while it
was written: first "we should push very hard on qtt to really make it
fast and representation first ... let's make something perfect for us",
then D97
(`proposals/0000-mlir-native.md:1430-1445`, *read*): the e-graph is "for
shared representation, elegance, and pushing qtt extremely hard to remove
bugs", "every table quantity 1 and updated in place, bounds and capacities
erased proofs, the engine's phase an erased index, so a misuse is
unwritable and no check is printed. Speed is measured, never the reason."
So the headline here is the bugs this layer makes unwritable (§2); speed
is §9. It designs the layer between D87's sparse library and the engine
of `one-engine.md`: union-find, hash-consing with fresh ids, growing
tables, worklists and rebuild, analyses' and extraction's tables,
schedules and budgets. `AGENTS.md`'s line numbers below are of the
working tree when this was written; other work was editing it. The siblings are cited, not redone:
`speed.md` (where the time goes), `sparse-mlir.md` (what the sparsifier
compiles), `sparse-library.md` (the library), `one-engine.md` (the route),
`unknowns.md` (U2, U8, U9, U17, U18), `workloads.md` (real per-function
sizes), `payoffs.md`; `synthesis.md` had not appeared.

Grounds: *read* (path:line or URL), *measured* (a command I ran, its build,
input and machine), *measured (agent)* (a run by this task's agents,
outputs under `/tmp/eg-machine/`), *recalled*, *conjecture*, *decision*
(a design this file proposes, open to the owner's and the coordinator's
review; none is settled by being written here). Ours at HEAD e96bb991 with
the working tree's proposal; MLIR at the pin in `.toolchain/llvm-project`.
Machine: Apple M2 Max (virtual), shared, load average 5 to 9 during the
runs. Tools: stock Idris 0.8.0-1c630e67c on the Chez in `.toolchain/`;
Apple clang 21.0.0 for C; **Homebrew LLVM/MLIR 22.1.8
(`/opt/homebrew/opt/llvm@22`), not our pin**, for every MLIR measurement,
each labelled 22.1.8. Nothing in the repository was built, run or changed
except this file. The Idris sketch (987 lines) is in
`/tmp/eg-machine/sketch/`, the C drivers in `/tmp/eg-machine/c/`, the
printed MLIR in `/tmp/eg-machine/*.mlir`, the bug catalogue (77 entries,
every one read in its issue, pull request or diff) in
`/tmp/eg-machine/bugs/catalogue.md`.

## 0. In plain words

- **It is not a runtime.** `runtime/` holds the one meaning of each
  primitive, in C and C++, and "no primitive has an implementation in
  Idris" (`AGENTS.md:253-261`, *read*). This layer adds no primitive. It is
  a library of data structures written in plain Idris over two generating
  sets the tree already has: `mlir-array`'s linear arrays and base's
  fixed-width words (hashing is `Bits64` multiply, xor and shift). Call it
  **the machine**: `libs/mlir-machine`, beside `mlir-array` and D87's
  `mlir-sparse` (*decision*, §1).
- **Written once, two interpretations, both type-checked and run.** The
  machine is an interface (tagless-final): words, positions, linear tables,
  and loops that end by their form. Each construct is written once over it.
  The *running* interpretation is its one meaning on the stock host (the
  elaborator's); the *printing* one emits upstream `arith`, `scf` and
  `memref` (the C++ optimizer's). In the sketch, the union-find and the
  hash-cons written once printed MLIR that 22.1.8 parsed, lowered and
  compiled; the union-find also ran on Chez. Every count agrees: the
  union-find's across Chez, printed MLIR and hand C, the hash-cons's
  across printed MLIR and hand C, its hash across Chez and C (*measured*,
  §5).
- **What QTT makes unwritable** (§2): ids of another graph (a brand), ids
  out of range (`Fin`), a stale root after a merge (roots indexed by the
  class count), a match on an unrebuilt graph and a query that writes (the
  phase as indices; a frozen snapshot beside a growing table), a union that
  forgets the repair or the analysis (union's type), a rebuild that stops
  early or never (its measure), a cycle in the union-find (distances, not
  parents), aliasing and uninitialised tables (linear tables, zero a valid
  state), unbounded recursion and loops with no end (no `while`). Of the
  77 real bugs found in egg, egglog, Cranelift's aegraph and others, 46
  fall in classes this design makes unwritable, 16 stay possible (unsound
  rules, wrong `make` functions, placement, extraction's tie choices,
  containers, subsumption), and 15 concern features it does not have
  (explanations, merge functions, ILP extraction); the split is my
  reading of each row (§2.1).
- **What linearity buys the printed code** (§3): a table value is its
  buffer, so nothing is ever copied; no bounds check, null test, cycle
  guard or "is it rebuilt?" flag is printed. Aliasing freedom does not
  reach LLVM today: MLIR's `func-to-llvm` drops argument attributes on
  memref arguments (`FuncToLLVM.cpp:416`, *read*), and adding `noalias` by
  hand bought nothing measurable on the hash-cons (*measured*, 22.1.8).
- **Memory** (§6): the engine never grows a table. Every table has a
  capacity the caller fixes, in its type; the one test that can stop a run
  is `caseRoom`, and a full table is the budget's stop: less optimized,
  never refused. The closing schedule has no such test in its type. The
  C++ passes zeroed buffers, because zero is a valid state of every table.
- **Two findings that change other files.** (1) The stock compiler deletes
  a write behind a forged world: Idris's identity optimization judges a
  `let` by its body and ignores an effectful value (`Identity.idr:31-38`,
  *read*), so a minimal program prints 0 instead of 7 (*measured*). Every
  stock-host body of `LArray` must make its result depend on its effect,
  and the bug is a carried patch to stock Idris (§8). (2) The elaborator
  can run the source itself through the running interpretation; the
  printed Idris form of `one-engine.md` is a copy it does not need (§5.6).
- **Performance, measured but not the reason.** The printed union-find is
  1.11× hand C and the printed hash-cons 1.23× (*measured*, 22.1.8). What
  loses is the combinators' shape, not the abstraction, and one of them
  (`search` returning a position, not what it learned) is a
  representation fix (§9).
- **For the owner, one at a time** (§13): 0015 D3's ban on hash tables as
  library code; whether the elaborator runs the source or a printed copy;
  how much of the phase rests on a trusted kernel.

## 1. The name, and where it lives

### 1.1 Not a runtime, and no new primitive

- `runtime/` is the one meaning of the primitives the runtime implements,
  and an op of inline arithmetic has its one meaning in a C++ template
  (`AGENTS.md:253-261`, *read*). A union-find or a hash table is neither:
  it is a data structure over arrays and words. Writing it in Idris
  implements no primitive.
- What it stands on (*read*):
  - `mlir-array`'s linear arrays: `withArray`, `read`, `write`, `shape`,
    `freeze`, `thaw`, `grow` (`libs/mlir-array/Array/Core.idr:196-236`),
    and the growable `Linear.Vec` (`Linear/Vec.idr:34-128`). Today they
    are bodiless externs meaning dialect ops (D42); 0009 D45 gives them
    stock-host bodies, as `sparse-library.md:532-537` plans.
  - base's `Bits64` and `Bits32`: `*` wraps, `xor`, `shiftR` by a
    `Fin 64` (`third_party/Idris2/libs/base/Data/Bits.idr:19-20, 106`).
  - D87's sparse library for the relational kernels over frozen
    snapshots (§4.6).
- **Primitives considered and not needed**, each with its reason:
  - a hash function: two multiplies, an xor and a shift (`HashCons.mix`).
    The stock host and C agree bit for bit on it (*measured*,
    `MixCheck.idr` against `c/mix.c`, four inputs including a wrapping
    product);
  - an allocator: the engine allocates nothing (§6), and the stock host
    makes arrays with `withArray`;
  - an unchecked index: a position is a `Fin`, so no check exists to skip;
  - count-leading-zeros: a power-of-two size is an erased `Pow2` beside
    its run-time value;
  - atomics: one engine per function, one thread;
  - a prefetch hint: it has no meaning to give a body; considered only if
    a measurement asks.
- So the layer is a library above primitives, in the strict sense
  `AGENTS.md:165-174` describes for `libs/`: plain Idris over base's and
  the compiler's own primitives.

### 1.2 Where it lives (*decision*, coordinator, for review)

| part | place | why |
| --- | --- | --- |
| the interface, the running interpretation, and the general constructs (ids, union-find, hash-cons, worklist, lattice store) | `libs/mlir-machine` | not e-graph specific: O7's unification, 0015's layer 1 and Translate's worklist want the same union-find and table; 0015 D2 forbids a consumer's own copy |
| the e-graph's phases, rebuild, extraction, schedules | `libs/mlir-relational/.../EGraph/` (0015 D4's package) | `one-engine.md` §3's place |
| the printing interpretation | `specgen` | it emits MLIR through D51's printers (`one-engine.md` §6.1); `libs/` never prints |
| the rules | the specification's rule language (`egraph.md` §3.1) | unchanged |

Not under `IdrisMLIR.*`, since the fork consumes it (`AGENTS.md:626-627`).

## 2. The headline: bugs made unwritable (D97)

### 2.1 The catalogue against the design

77 real bugs were found and read: egg 21, egglog 29, Cranelift's aegraph
20, extraction-gym 3, Ruler 3, Herbie 1 (*measured (agent)*,
`/tmp/eg-machine/bugs/catalogue.md`, every row cited to its issue, pull
request or commit). The table groups them by class; each row names the
mechanism of this design that makes the class unwritable, or says why
none can. Counted row by row (*conjecture*, a reading of each bug against
§4): 46 unwritable (egg 12, egglog 20, Cranelift 10, others 4), 16 still
possible (egg 3, egglog 3, Cranelift 8, others 2), 15 about features this
design lacks (egg's explanations and ILP extractor E8, E13-E15, E19, its
VM order E5; egglog's merge functions, planner and term printing G10, G12,
G14, G20, G24, G29; Cranelift's W2, W9; extraction-gym's ILP X3).

| class | real instances (catalogue ids) | what makes it unwritable here | kind |
| --- | --- | --- | --- |
| an id of another graph, or out of range | E3 (`Id` was a bare `u32`, egg #36), E10 (a VM read past a node's children, egg #129), G18 (ids of one term DAG given to another's extractor, egglog #528, open) | every id is `Id g v n`: a position below `n` (`Fin n` when run) under a brand `g` that `withGraph` binds as a fresh type variable; a node's arity is its kind's table, not a user `matches` | erased index, rank-2 brand |
| a stale, non-canonical id used after a union | E2 (costs looked up with un-`find`ed ids, egg 5905358), G3, G6 (a merge with an un-`find`ed value, egglog #121), W5 (the remat bit read from the canonical node), W10 (the union-find moved ids already stored as GVN keys, wasmtime #6126), X2 | `union` finds both roots itself, so no union of a non-root can be written; a table keyed by class takes a `Root g c`, indexed by the class count `c`, which every merge lowers, so a root of before a merge does not type-check against the graph after it; within a round every stored id is canonical as of the round's start and nothing rewrites one until rebuild | erased index |
| matching or querying a graph that is not rebuilt | G2 (`check` depended on whether a rebuild had run, egglog #105), G26 (stale rows visible in a scan) | the graph is `EGraph g v tab n p c` with `p` repairs pending; matching takes `p = 0` only, and only `rebuild` produces it | phase index |
| a query that writes, an action that reads the round's rows | G22 (egglog #772; fixed by typed contexts, PR #856) | `freeze` splits a clean graph into a `Frozen` snapshot, the only thing a join reads, and a `Growing` table, the only thing an action writes; `thaw` joins them, dirty. In MLIR they are disjoint views of one buffer | linear ownership, phase index |
| a union that forgets its repair, rebuild that ends with work left | E7 (rebuild returned with `analysis_pending` non-empty, egg db3e97d), R1 (an analysis changed and reported no change, Ruler #46), R2 | a merging union's only result is `Joined : EGraph … (S p) c'` with `c = S c'`: the repair is pushed by the type; an analysis that changes pushes onto the same pending count, so "clean" is one fact, `p = 0` | erased index |
| a rebuild or saturation that does not end | G9 (a merge on identical tuples rebuilt forever, egglog #287), W13 (unbounded recursion, wasmtime #7874), E11 (exponential rebuild from duplicate entries, egg #239) | the machine has no `while`: a loop is counted (`upTo`), a strict descent (`downward`) or a bounded search (`search`); rebuild's measure is classes plus pending, which a repair lowers and a merge keeps (§4.5); a queued class is never pushed again, so the worklist has no duplicates and fits in `n` | erased proof, the machine's form |
| a cycle in the union-find | none found in the catalogue's union-finds (it notes none in egglog's core) | the table stores each class's distance down to its parent: whatever it holds, a parent is never above its child (§4.2) | representation |
| analyses not merged, not monotone, not a lattice | E1 (class data not recomputed on congruence, egg 0de75c9), W20 (alias analysis not a lattice, wasmtime #13990), R1 | the analysis tables are fields of the graph, merged by `union` itself; a datum is written only by `meetInto`, whose meet comes from a closed sum of `arith` lattices (`sparse-library.md` §2.5's `Merge`), so the stored value only falls whatever `make` returns | linear ownership, closed sum |
| extraction cycles, overflow, a node from the wrong class | E2, E12 (`AstSize` overflow), G17 (cost width per platform), G19, X1 (cycles), X2 (wrong class) | weights are positive by type, so a strict improvement can never close a cycle; every class starts from its creation node, whose children were created first, so every class has a finite term; costs are fixed-width words on every target and saturate at a typed top; `best[c]` is written only at `find(class of m)` | erased proof, representation |
| a limit that reports the wrong ending, nondeterminism | E4 (a time limit reported `Saturated`, egg #58), G4, R2, E20 and G16 (hash order leaked into results), E21 (shift overflow in back-off), G28 | `Round` is `Saturated` or `Stopped`, and `Stopped` is built only from `caseRoom`'s full branch; no wall time exists; the hash table is probed, never iterated for a result; constants fix the hash on every target; a shift's amount is a static `Fin 64` | closed sum, static fact |
| aliasing and uninitialised memory | W6 (a cloned instruction aliased its argument list), W19 (uninitialised arena memory, Miri) | every table is quantity 1: one owner, no alias; zero is a valid state of every table (all roots, all slots empty, all fills empty), so the boundary's zeroed memory is a legal graph | linear ownership, representation |
| identity by name, a user equality on nodes | E9 (a user `Eq` ignored children, egg #70), G27 (fresh-name collision, egglog #1006), G11 | keys are compared by the machine's own `eqIx`; identity is an id, never a name | closed interface |
| a non-linear pattern unchecked, a variable read before bound | E6 (egg #143), G23 (egglog #865, open) | a pattern's variables are `Fin n` of its context (`egraph.md` §3.1), repeated ones become an equality filter (`sparse-mlir.md` §2.3), and a condition is read in the apply, after every variable is bound | erased index |

### 2.2 What stays possible, and why

- **Unsound rules and laws** (E16, E17, H1, R3, W4, W7; `unknowns.md` U3:
  one wrong pair merged `0` with `1`). Types check type preservation,
  binding, linearity and the subsume discipline (`egraph.md` §3.2); the law
  itself, for a primitive, is a declared fact checked by search
  (`egraph.md` §3.5). Essential: Idris cannot prove a runtime function's
  law against the runtime.
- **A wrong `make`** (E17, E18). The analysis is D41's template, the
  folder's own meaning (`one-engine.md` §5.3), so it cannot disagree with
  the folder; it can still be wrong. Essential.
- **Extraction's choices** (W17; `workloads.md` §3.3). Tree cost ties
  and saturation make a choice arbitrary; positive weights rule out
  cycles, not bad picks. Sharing-aware cost is research (`egraph.md`
  §10.3).
- **Placement** (W8, W11, W12: an operand not available where it is
  used, a rematerialization placed against a hoist).
  It is the adapter's, over the region tree (`one-engine.md` §5.4);
  whether `best` is per scope is `unknowns.md` U12, open.
- **Subsumption** (G13, W14). `Simplify`'s replacement (`egraph.md`
  §3.1) kept as a flag on a row re-opens both; kept as a move of the row
  out of the live view into a retired table, it would not (*conjecture*,
  not designed here).
- **Crashing and trapping ops in the floating class** (W3; `unknowns.md`
  U2) and unique
  nodes made by a rule (U8): the rule language's `Make` indexed by the
  kind's class, as U8 settles; not this layer's.
- **Variadic ops and containers** (G8, G21): our ops are variadic
  (`unknowns.md` U9); if a variadic list is a container table, the same
  canonicalization risk returns. Open with U9.

## 3. QTT: each fact, what it deletes from the printed code, who pays

| fact, and how it is held | what the printed MLIR does not contain | who pays |
| --- | --- | --- |
| a table is quantity 1 (`(1 _ : tab t n)`), every operation gives it back | no `memref.copy` anywhere: the printer maps every version of a table to one buffer, sound only because no old version can be read (*measured*: neither printed module holds a copy or an `alloc`) | the source threads each table by hand (`x # t <- read t i`); a branch must hand its tables to both arms, which the printer does by name (§5.4) |
| two tables are two linear values | `noalias` on their pointers, in principle; at the pin it is dropped by `func-to-llvm` for memref arguments (`FuncToLLVM.cpp:397-424`, the TODO at `:416`, *read*); added by hand to the LLVM IR, the hash-cons was no faster (185.8 against 194.1 ms, noise, *measured*, 22.1.8) | an upstream patch if a scan ever measures the need (§8) |
| a position is `Ix n`, a `Fin n` when run | no bounds check on any `memref.load` or `store` | the stock host builds a `Fin` from a number with an erased proof; a `Dec` built at run time would cost the number in steps (§10) |
| a fill is `Fill n`, a number from 0 to `n` (`Fin (S n)`) | no second count beside the fill; the room test is one `arith.cmpi uge` | the source must take the next position from `caseRoom`, never compute it |
| a capacity is `Sz n`, the number `n` itself | no "capacity" read from a header; the extent is the caller's argument | the boundary passes it (§6.3) |
| a slot is `Opt n`: none or a position | no separate "occupied" flag; empty is 0, so zeroed memory is empty | ids are stored plus one |
| a size is a power of two, an erased `Pow2 (S s)` | `arith.andi` with `s`, never `arith.remui` | the boundary passes a power of two; the running interpretation uses `restrict` (a remainder), which agrees by arithmetic: a remainder by `2^k` is the low `k` bits (not measured: the hash-cons did not run on Chez) |
| a shift's amount is a static `Fin 64` | no poison shift, no guard on the amount | none |
| the union-find holds distances down (`below` truncates at 0) | no cycle guard, no rank array, no "is root" flag: a root is distance 0 | two ops (`minui`, `subi`) where C subtracts once (§9) |
| the phase is `p` pending repairs; clean is `p = 0` | no "rebuilt?" flag, no rebuild-skipped test (egglog tests one, `egglog-bridge/src/lib.rs:785-797`, *read (agent)*); the loop's own exit is the only test | `union`, `rebuild`, `freeze`, `thaw` and `meetInto` are a trusted kernel whose types claim the phase (§10) |
| frozen snapshot beside a growing table | no write to a row a join reads, so a join's loads may be hoisted; no "visible to this round?" test | the split is two views; a lookup reads the hash-cons, never the growing rows |
| the measure of rebuild (classes + pending) | no iteration count, no fuel | an erased proof in each step's type |
| a rule's `Make` exists only in the exploring schedule (`one-engine.md` §2.3) | the elaborator's printed or run code has no full-table test at all | none |
| a class's datum written only by `meetInto` | no "did it change?" comparison outside the meet | the meet is from a closed sum |

## 4. The constructs

Each with what its type carries, what cannot be written, and the MLIR it
prints to. The sketch's code is cited where it exists; the rest is
*decision* with its type stated.

### 4.1 Ids, fills, slots, sizes

```idris
data Ty : Type where
  W64  : Ty                    -- a word: i64, wraps
  Bit  : Ty                    -- a test: i1
  Ix   : (0 n : Nat) -> Ty     -- a position below n: index (i32 in a table)
  Fill : (0 n : Nat) -> Ty     -- 0 to n places taken: index
  Opt  : (0 n : Nat) -> Ty     -- a position below n, or none: index, 0 for none
  Sz   : (0 n : Nat) -> Ty     -- the number n itself: index
```

- Run: `Fin n`, `Fin (S n)`, `Maybe (Fin n)`, `Singleton n`, `Bits64`,
  `Bool` (`Eval.El`, *measured* type-checks). Printed: `index` in
  registers, `i32` in tables, `arith.index_castui` on load and
  `arith.index_cast` on store (`Print.stored`).
- The graph's brand `g` and class count `c` index `Id g v n` and `Root g
  c` (*decision*; `Id` is in `Phase.idr`, `Root` is not sketched).
- Unwritable: an id of another graph, an id past the capacity, a fill
  past it, a slot that is neither empty nor an id.

### 4.2 The union-find: distances, path halving, the least root

```idris
find : Machine v tab m => {0 n : Nat} ->
       (1 _ : UF tab n) -> v (Ix n) -> m (Res (v (Ix n)) (const (UF tab n)))
find uf x = M.do
    r # T uf' [] <- downward x (T uf []) step
    pure (r # uf')
  where
    step : (1 _ : Vals v tab [Table (Ix n) n]) -> v (Ix n) ->
           m (Res (v (Ix n)) (const (Vals v tab [Table (Ix n) n])))
    step (T u []) y = M.do
      d # u <- read u y
      MkBang p <- below y d
      dp # u <- read u p
      MkBang g <- below p dp
      MkBang gap <- below y g
      u <- write u y gap
      pure (g # T u [])
```

(`UnionFind.idr`, 59 lines with `union`; *measured*: type-checks, runs,
prints.)

- **The representation.** Each class holds the distance down to its
  parent, `below` subtracts and stops at 0, and a class at distance 0 is a
  root. Whatever the table holds, a parent is never above its child, so
  every table is a forest whose roots are the least ids of their trees
  (`egraph.md:666-667`'s determinism, now a fact of the data), no cycle can
  be written, and `downward` ends because each step goes strictly down
  (its running form recurses on `SizeAccessible` of the position,
  `Eval.descend`). Path halving is "point at the grandparent", one write,
  no branch: at a root it writes the root's 0 again.
- **Union** finds both roots and links the larger under the smaller,
  `distance = hi - lo`, with no branch: when the roots are one it writes a
  0 at a root. It returns `MkMerge kept absorbed`; the typed graph-level
  `union` (`Phase.idr`) turns "absorbed ≠ kept" into `Joined`, which pushes
  the repair. egglog's union-find is the same algorithm (least root, path
  halving, `union-find/src/lib.rs:87-120`, *read (agent)*) with the
  invariant unstated.
- **Rank**: not kept. Union by least id is the determinism `egraph.md`
  §4.4 asks for, and path halving bounds the amortized cost
  (*recalled*: Tarjan and van Leeuwen).
- **Zero is the start**: every class its own root. The C++ passes zeroed
  memory; the stock host fills with `FZ`.
- **MLIR**: one `scf.while` per `find` whose body is two loads, one store
  and seven `arith` ops (§5.4).
- **Unwritable**: a cycle; a parent above its child; a "root" flag
  disagreeing with the parent; a union of non-roots.

### 4.3 The hash-cons: open addressing, lookup or insert, fresh ids

`HashCons.idr` (112 lines, *measured*: type-checks, prints, runs from C):

- **Slots** are three columns of `S s` entries, `S s` a power of two: two
  key columns (`Ix n`) and a class column (`Opt n`). Zeroed slots are
  empty. Keys sit in the slots, so a lookup never reads the node table
  (egglog's entries hold a 32-bit fingerprint and a row id and compare the
  key in the row, `table/mod.rs:138-141`, *read (agent)*; keeping the key
  in the slot is what lets the join read frozen rows while the apply
  probes).
- **Probing** visits `h xor j` for `j` below `S s`: a permutation of the
  slots, so the search visits each slot once and ends by its count
  (`search`). A key's hash is `HashCons.mix`, constants only.
- **`make`** returns the class (`Opt n`, none when stopped) and the fill
  after. A node is made exactly when the fill grew: that is the "changed"
  of the round, read from the representation, never a flag (egglog G4,
  Ruler R2 were that flag wrong).
- **The full case is the budget.** An empty slot found with no room in
  the node table (`caseRoom`'s full branch), or no slot found at all, both
  return none: the run stops, the function is less optimized, nothing is
  refused (`AGENTS.md:196-198`). Slots at twice the node capacity make
  the second unreachable in practice; it stays a legal outcome, not an
  impossible arm.
- **Tombstones and rehash** (*decision*, not sketched): rebuild re-keys a
  node by marking its old slot moved (a third slot state) and inserting the
  canonical key; a hit on another class is a union. When moved slots
  exceed half (egglog compacts at more than `max(16, len/2)` stale rows,
  `table/mod.rs:1125-1135`, *read (agent)*), the live slots are rehashed
  into a second slot array the caller passes: two linear slot arrays, the
  type naming which is live, swapped by `rehash`, so neither is ever
  copied or allocated.
- **MLIR**: an `scf.while` over the probes with an `scf.if` per probe, then
  an `scf.if` tree for hit, make or stop (§5.4). No call, no allocation.
- **Unwritable**: two classes for one key within a round (a key is
  inserted only on a miss of the same epoch); a user equality; a probe
  past the table; a "full" that refuses.

### 4.4 Node tables: columns per kind, frozen and growing

- One table per node kind, columnar, its arity fixed by the kind:
  children columns (`Ix n`), and the per-node facts the adapter needs
  (type, properties, region: `one-engine.md` §5.1's `Tables`). A row's
  class at birth is its own position, so node and class ids share one
  space of `n`. Per-program kinds and variadic ops are `unknowns.md` U9,
  open; this layer's tables are fixed-arity, and a variadic op is either a
  chain of fixed-arity nodes or a CSR column (`one-engine.md` §5.1's
  `childStart, child`).
- **`freeze` and `thaw`** (`Phase.idr`): a clean graph splits into a
  `Frozen g tab n f` (the `f` rows made before the round, read-only) and a
  `Growing … f p c` (appends from `f` on, the hash-cons, the union-find).
  This is the semantics egglog has (staged writes become visible next
  round) made a type; it is also what makes fusing the apply into the join
  legal (`sparse-mlir.md` U-S3), since nothing the join reads is written.
  In MLIR, two `memref.subview`s of one buffer, disjoint.
- **Sorted runs** (egglog sorts by timestamp only and indexes lazily,
  `hash_index/mod.rs:102-152`; Soufflé keeps insert-only B-trees and Brie,
  never moving items, *read (agent)*). Here an index a join needs is a
  sorted copy into a caller buffer, assembled as a sparse tensor
  (`sparse-mlir.md` §2.2), rebuilt from the frozen rows when the round
  starts; refreshing only the appended rows is `sparse-mlir.md` §2.7's
  incremental form, research.

### 4.5 Worklist and rebuild

- **The worklist** is a growing table of `Ix n` and its fill, capacity `n`,
  beside a queued mark per class (a column of bits). A merge pushes its
  absorbed root, which is absorbed once; an analysis whose datum falls
  pushes its class (§4.7); a class already queued is not pushed again. So
  no entry repeats and `n` is the exact capacity (egg's exponential
  rebuild, E11, was duplicates; its fix was a unique queue).
- **Rebuild** is egg's deferred rebuild (`sources/papers/willsey-2021-egg/
  03-rebuilding.tex`, *read* by `speed.md`): pop an absorbed root; for each
  node using it (a use list threaded through the node rows, §4.4's
  columns, spliced on union in O(1), *decision*), re-key it through the
  hash-cons; a hit on another class is a union, which pushes.
- **Its end, as a type.** The state carries the class count `c` and the
  pending count `p`: a merge is `c → c - 1, p → p + 1`, a pop is
  `p → p - 1`, so `c + p` falls by one each step and the loop ends at
  `p = 0`, the clean graph; with analyses, the remaining height of their
  lattices joins the measure (§4.7). `Merged` in `Phase.idr` states the merge's
  half (`Joined : … (S p) c' -> (0 _ : c = S c') -> …`, *measured*:
  type-checks). The machine combinator this needs, a loop whose state is
  indexed by an erased measure, is designed and not sketched: its state's
  slot list is a function of the erased measure,
  `{ss : (0 k : Nat) -> List Slot}`, which the printer can read at run time
  because a slot's MLIR type never depends on `k` (*conjecture* until
  written).
- **The closing schedule** (the elaborator's) uses the bag instead (§4.6),
  and its measure is `one-engine.md` §2.3's `ClassesLeft`.

### 4.6 Batch insertion through the bag

- `sparse-library.md` §5 dedupes a round's new nodes by appending them to
  an `LBag` and `build Once` (a sort, then runs). This design keeps the bag
  for what sorting does well and the hash-cons for what a probe does well
  (*decision*):
  - **the closing schedule's congruence**: canonicalize every row, append
    to a bag, `build`, union the outputs of equal keys, repeat while a
    union merged. No capacity can be exceeded (the rows are the input's),
    so its type has no full case, as `one-engine.md` §2.3 requires;
  - **the exploring schedule's full rehash** after many tombstones;
  - **node creation** stays the hash-cons: a probe per node costs what the
    dense engine pays (§9), where a sort costs 95-118 ns per tuple and
    twenty times the join (`sparse-mlir.md` §6, *measured* there on
    22.1.8).

### 4.7 Analyses' lattice tables

- One dense table per analysis and per class, its element a word or a
  position; its meet a closed sum (`sparse-library.md` §2.5's `Merge`:
  least, greatest, wrapping sum, bitwise or, and, xor), commutative,
  associative and idempotent by the primitive.
- Written only by `meetInto : (1 _ : EGraph …) -> Root g c -> v t ->
  m (Changed …)`, which meets and, when the value changed, pushes the
  class: one pending count for congruence and analyses, so egg's E7
  cannot be written. `union` meets the absorbed class's datum into the
  kept one's: E1 cannot be written.
- `make` whose meaning is C++ (D41) is `one-engine.md` §5.3's hook; its
  result is met, never stored raw, so the table stays monotone whatever
  the hook returns (*decision*).
- **The open edge**: a domain of great height (intervals) can re-push a
  class many times; rebuild's measure then needs the height, or a
  widening. Open, with D41's interval domain.
- MLIR: `memref.load`, an `arith.minui`-family op, `memref.store`.

### 4.8 Extraction's tables

- `best` per class: cost in the high 32 bits and node id in the low ones,
  so one `minui` is the argmin with deterministic ties (`sparse-mlir.md`
  §2.8's representation). Weights are positive by type (a successor), so
  a strict improvement never closes a cycle.
- **Start**: each class's creation node, in creation order. A node is made
  only from classes that exist, so its children's creation nodes come
  first: one forward pass gives every class a finite term, and egglog's
  G19 (classes with no finite cost) cannot arise. Then sweeps, each
  lowering some cost or ending (costs are naturals that only fall).
- Costs saturate at a typed top on every target (G17 was a 32-bit cost on
  wasm); a tie at the top is W17's weakness, kept (§2.2).
- MLIR: the sweep as `sparse-mlir.md` §2.8's kernel over a frozen index,
  or a loop over node rows; both compile there (22.1.8).

### 4.9 Schedules and budgets

- `Round` (`Phase.idr`) is `Saturated` or `Stopped`, each holding a clean
  graph; `Stopped` comes only from a full table. No time, no iteration
  limit as a stop (`speed.md` §4); a per-rule match cap is a match table
  of fixed capacity, full meaning "this rule rests this round" (egg's
  back-off, `run.rs:869-877`, *read* by `speed.md`).
- The closing schedule's `Action` has no `Make` (`one-engine.md` §2.3), so
  its tables never grow and its `Outcome` has one case.

## 5. Written once, two interpretations

### 5.1 The interface

`Machine.idr` (127 lines, *measured*: type-checks under stock Idris,
`%default total`, no hole, no `believe_me`, no `assert_total`). Its
parameters are the interpretation: `v` a scalar, `tab` a table, `m` the
order of effects, determined by `m`.

```idris
interface Machine (0 v : Ty -> Type) (0 tab : Ty -> Nat -> Type) (0 m : Type -> Type) | m where
  ret  : (1 _ : a) -> m a
  bind : (1 _ : m a) -> (1 _ : (1 _ : a) -> m b) -> m b
  word : Bits64 -> m (!* v W64)
  mul, xor : v W64 -> v W64 -> m (!* v W64)
  shr  : v W64 -> Fin 64 -> m (!* v W64)
  below : v (Ix n) -> v (Ix n) -> m (!* v (Ix n))          -- never above its first
  wrap : (0 _ : Pow2 (S s)) -> v (Sz (S s)) -> v W64 -> m (!* v (Ix (S s)))
  read  : {t : Ty} -> (1 _ : tab t n) -> v (Ix n) -> m (Res (v t) (const (tab t n)))
  write : {t : Ty} -> (1 _ : tab t n) -> v (Ix n) -> v t -> m (tab t n)
  upTo     : {ss : _} -> v (Fill n) -> (1 _ : Vals v tab ss) -> (body) -> m (Vals v tab ss)
  downward : {ss : _} -> v (Ix n) -> (1 _ : Vals v tab ss) -> (step) -> m (Res (v (Ix n)) …)
  search   : {ss : _} -> v (Fill w) -> (1 _ : Vals v tab ss) -> (probe) -> m (Res (v (Opt w)) …)
  caseOpt, caseBit, caseRoom : … two continuations, each printed as a region
  -- and eqIx, bit, both, asWord, minIx, maxIx, whole, none, some, taken
```

- **Effects are the data's order.** A table is threaded, so every read and
  write is ordered by the table it touches; `m` is linear (`bind` takes a
  linear continuation) so a table can pass through it. A scalar comes back
  as `!* (v t)`, used freely.
- **Control has three forms, each ending by its form**: a counted loop, a
  strict descent, a bounded search, plus branches. A staged program cannot
  case on a printed value; it branches through `caseOpt`, `caseBit` and
  `caseRoom`, whose continuations the printer prints as the two regions of
  one `scf.if`.
- **What a loop or branch carries** is `Vals v tab ss`: scalars, and tables
  by ownership, `ss` a list of slots the printer reads to print
  `iter_args` and `scf.yield`. Each slot kind is its own constructor, so no
  field's representation depends on an erased value (the subset's rule).
- **Facts ride on values.** An earlier form passed evidence (`LT f n`) to
  continuations; the printer cannot build a proof about sizes it never
  learns. Carrying the fact in the value's type (`Fill n` splits into full
  or a position below `n`) needs no evidence at all: the skill's "prefer
  indices and views" was the working form.

### 5.2 A construct written once

`find` above, `union`, `mix`, `probe` and `make`: no line of them names an
interpretation. The type checker sees only the interface, so each holds
in every interpretation (Reynolds's abstraction theorem, *recalled*): the
printed code makes exactly the tests the running code makes, and accesses
exactly the positions whose bounds the running code's types prove.

### 5.3 The running interpretation: the one meaning, on the stock host

`Eval.idr` (126 lines): `El` maps `Ix n` to `Fin n`, `Fill n` to
`Fin (S n)`, `Opt n` to `Maybe (Fin n)`, `Sz n` to `Singleton n`; a table
is a linear array; `m` is `Now`, the identity, linear in its value.
`downward` recurses on `SizeAccessible`, `upTo` and `search` on the count
left, `caseRoom` compares once and builds the position with an erased
proof.

*Measured* (`RunUF.idr`: unions of pseudo-random pairs, then every pair's
two finds, then a find per class; stock Idris on Chez):

| classes, unions | Chez, through the interface | hand C `-O2` (`c/uf.c`) | classes left (both) | pairs apart (both) |
| --- | --- | --- | --- | --- |
| 10,000, 20,000 | 0.16 s | 0.5 ms | 204 | 0 |
| 100,000, 200,000 | 0.37 s | 5.6 ms | 1,977 | 0 |
| 1,000,000, 2,000,000 | 3.58 s | 58.0 ms | 19,161 | 0 |

About 9 million finds at 1,000,000 classes: about 0.4 µs per find on
Chez, 6.4 ns in C, a factor of about 60. `unknowns.md` U18 measured a
union-find written directly over the same primitives at 0.3 µs per union,
two finds each (*measured* there), so going through the interface may
cost the stock host up to two or three times direct code (*conjecture*:
the workloads differ, and neither run separated the phases). Two lessons
from getting there, both *measured*:

- **A decision built at run time costs the number in steps.** With
  `isLT` deciding the descent, the 100,000 run took 24.9 s, quadratic;
  with a `Bool` test and the proof erased (`choose`, `ltOpReflectsLT`, as
  `Linear.Vec` already does) it took 0.37 s. The skill's warning
  (`SKILL.md:87-88`) is the rule for every running body.
- **The stock compiler deletes a forged-world write** (§8, U-M1).

### 5.4 The printing interpretation

`Print.idr` (327 lines, *measured*: type-checks): `v` and `tab` are SSA
names, `m` is a builder. `downward` prints an `scf.while` whose before
region runs the step once; `upTo` an `scf.for`; `search` an `scf.while`
with an in-bounds `scf.if`; a branch passes its tables to both regions by
name (the linear `Vals` is consumed once, and two fresh `Vals` with the
same names are made, legal since a printed table is a name). The same
`find` printed and canonicalized by 22.1.8:

```mlir
%0:2 = scf.while (%arg2 = %arg1) : (index) -> (index, index) {
  %1 = memref.load %arg0[%arg2] : memref<?xi32>
  %2 = arith.index_castui %1 : i32 to index
  %3 = arith.minui %arg2, %2 : index
  %4 = arith.subi %arg2, %3 : index            // the parent
  %5 = memref.load %arg0[%4] : memref<?xi32>
  %6 = arith.index_castui %5 : i32 to index
  %7 = arith.minui %4, %6 : index
  %8 = arith.subi %4, %7 : index               // the grandparent
  %9 = arith.minui %arg2, %8 : index
  %10 = arith.subi %arg2, %9 : index
  %11 = arith.index_cast %10 : index to i32
  memref.store %11, %arg0[%arg2] : memref<?xi32>
  %12 = arith.cmpi ult, %8, %arg2 : index
  scf.condition(%12) %8, %arg2 : index, index
} do { ^bb0(%arg2: index, %arg3: index): scf.yield %arg2 : index }
```

Upstream's canonicalizer dropped the memref `iter_args` the printer
carries for every table, as it was meant to (*measured*). Both printed
modules (`/tmp/eg-machine/uf.mlir`, `hc.mlir`) went through `mlir-opt`
(canonicalize, cse, scf-to-cf, memref, arith, index, cf, func to LLVM),
`mlir-translate` and `clang -O2`, and ran from C on the workloads above
(*measured*, 22.1.8):

| kernel | printed, best of 5 (3) | hand C | agreement |
| --- | --- | --- | --- |
| union-find, 1M classes, 2M unions, 5M finds | 70.1 ms | 63.0 ms | classes left 19,161 in Chez, printed and C |
| hash-cons, 2^22 slots, 2M capacity, 4M keys | 185.8 ms | 150.8 ms | 2,000,000 made, 612,464 stops, in both; no key twice, every key found again with its class |

### 5.5 What the sketch is, and is not

Built: the interface, both interpretations, the union-find and the
hash-cons written once (each run and printed), the phase types and the
typed operations' signatures (`Phase.idr`, 75 lines, signatures only).
Not built: rebuild and its measured-loop combinator, tombstones, rehash,
analyses, extraction, the join over sparse snapshots, the hooks, and any
check under idris-mlir (no idris-mlir is built here).

### 5.6 The elaborator runs the source, not a printed copy

`one-engine.md` has `specgen` print the engine twice, MLIR and Idris, the
elaborator taking the printed Idris (`one-engine.md:29-38`, *read*;
D86's "an Idris form generated from the same source", `0000:1255-1256`).
The running interpretation makes the Idris printing unnecessary: the fork
imports `mlir-machine` and the engine source and instantiates them at
`Eval`. That deletes `libs/mlir-relational-egraph` (every file generated),
the Idris printer for the engine, and one row of D67's manifest, and the
body the stock host runs is the source the types were checked on, not a
print of it. What unfolding buys the elaborator is nothing: the closing
schedule has no rules to unfold. Its cost: the stock host passes the
interface's dictionary (within a small factor of direct code, §5.3); under
idris-mlir the instance is a constant at every call, which D58's
specialization removes (*conjecture*). This amends a recorded ruling, so
it is the owner's (§13, question 2).

## 6. Memory: growth under the budget

### 6.1 The rule (*decision*)

1. **No table the machine writes ever grows.** Its capacity is the
   caller's, in its type (`Sz n`, `Fill n`); a position past it cannot be
   written.
2. **The one test that can stop a run is `caseRoom`.** Its full branch is
   the budget's stop: the run ends with `Stopped`, the graph as it is is
   extracted, the function is less optimized, and nothing is refused
   (`AGENTS.md:196-198`). A match table at its cap rests one rule for one
   round, the back-off of `speed.md` §4.
3. **The closing schedule has no `caseRoom`.** It never makes a node, its
   congruence goes through the bag (§4.6), and its type has no stop.
4. **Sparse kernels never hold growing state.** They read frozen
   snapshots assembled over caller buffers, which copy nothing
   (`sparse-mlir.md` §1.5, *measured* there). A kernel with a sparse output
   grows by `memref.realloc` (`sparse-mlir.md` §1.6, *read* there) and has
   no failure path, so it is admitted only behind a counting kernel whose
   dense result `caseRoom` tests against the scratch region's room: a
   match set that does not fit rests the rule (*decision*; it costs a
   second join, 1× against 2.3× for materializing, `sparse-mlir.md` §0).
   The scratch region is the caller's; sparse codegen's allocations reach
   it through `_mlir_memref_to_llvm_alloc`, as `sparse-library.md:511-517`
   decided, and are freed before the engine returns. `sparse-mlir.md` §9's
   question 1 is answered by this, unless U-S3 lands (§8).
5. **Zero is a valid state of every table**: all roots, all slots empty,
   all fills and pending counts empty. Zeroed pages cost the OS nothing to
   give.

### 6.2 Sizes

The node capacity is the budget, `B × ops(f)` (`egraph.md` §4.5). On real
code the largest e-graph is 2,534 nodes and the largest per-function arena
112-237 KB (`workloads.md` §4.1, *measured* there), so every table sits in
cache and `i32` ids never press. `unknowns.md` U17's tension (a budget
larger than the host's memory) is the owner's there; nothing here
changes it.

### 6.3 What the C++ boundary passes

*Decision*, printed into `Engine.h.inc` by `specgen` (`one-engine.md`
§5.1).

| buffer | element | capacity, derived once from the node capacity `N` | initial |
| --- | --- | --- | --- |
| per kind, child columns and per-node facts | `i32` | `N` | the input's nodes |
| union-find | `i32` | `N` | zero |
| hash-cons slots, live and spare | `i32` × 3 | a power of two ≥ `2N`, with its exponent | zero |
| worklist | `i32` | `N` | zero |
| use lists (head per class, next per child slot) | `i32` | `N`, `N × arity` | zero |
| analysis tables | per domain | `N` | zero, the lattice's top |
| `best` | `i64` | `N` | zero |
| match tables, per rule | `i32` | the match cap | zero |
| scratch for sparse kernels | bytes | a multiple of `N`, measured at stage 1 | none |
| fills and counts | `index` | in and out | the input's |

One derivation from `N` in the header's constructor; the engine reads
every capacity from its argument's extent, and the `Pow2` fact from the
constructor's type.

## 7. The shared representation (D97)

What the elaborator (O7, on the stock host and, after `make self`,
compiled by idris-mlir) and the optimizer (the printed MLIR in the C++
tools) share, and what each shared piece's type proves on both sides:

| shared piece | elaborator | optimizer | proved once, for both |
| --- | --- | --- | --- |
| the machine interface and `Eval` | runs it | prints it | every access in bounds, no loop without an end, no table aliased or copied |
| ids, brands, roots | metas and Core terms numbered densely | ops numbered by the adapter | no id of another graph, none past the capacity, no stale root |
| union-find | meta unification | congruence and rules | a forest by construction, least roots, deterministic |
| worklist, rebuild, phases | the closing rebuild (bag) | the exploring rebuild (hash-cons) | clean means nothing pending; rebuild ends |
| hash-cons | none (the closing schedule makes nothing) | node creation | one class per key in a round |
| lattice store | none (`egraph.md:901`: O7 needs no analysis) | D41's analyses | merged on union, monotone |
| schedules | `Closing`, one outcome | `Exploring`, `Saturated` or `Stopped` | a budget stops, never refuses; the closing run cannot stop |
| rules and laws | congruence only | the specification's rules | type preservation, binding, linearity, subsume (`egraph.md` §3.2) |
| fixtures | the harness | `make test-unit` | the committed expected files, neither side the other's oracle (`one-engine.md` §6.3) |

Not shared, by the problem: the signatures (Core's terms, `idr`'s ops),
the adapters, and which schedule each runs (one-engine's `Schedule`
index). The guarantee travels to the printed MLIR by printing the same
checked source, and to the stock host by running it.

## 8. Upstream first

| # | change | where | size | research? | carried? |
| --- | --- | --- | --- | --- | --- |
| U-M1 | stock Idris's identity optimization judges a `let` by its body and ignores its value (`third_party/Idris2/src/Compiler/Opts/Identity.idr:31-38`, *read*), so a function whose result is its argument after an effectful `let` becomes the identity and the effect vanishes; the inliner's unused-let deletion (`Inline.idr:200-206`) is its neighbour | stock Idris, applied to the copy the bootstrap builds | a few lines: a non-`NotInline` let whose value is not pure is not an identity; plus a test | no | yes, needed: `LArray`'s stock-host bodies hit it. Reproducer `/tmp/eg-machine/idbug/Bug.idr`: `set (MkArr d) i x = let () = unsafePerformIO (…arraySet…) in MkArr d` prints 0 for 7, the log shows `found identity flag for: Bug.set` (*measured*). Nothing is sent to Idris (`upstream/README.md`) |
| U-M2 | `func-to-llvm` drops argument attributes for types that expand to several arguments (`FuncToLLVM.cpp:415-420`, the TODO); the bare-pointer convention keeps them but needs static shapes (`TypeConverter.cpp:593-602`, *read*). The patch maps `llvm.noalias` on a memref to its descriptor's pointers | MLIR | about 30 lines and a FileCheck test (*conjecture*) | no | not now: no measured need (§3) |
| U-M3 | a hash level in the sparse compiler (Finch has one, freezing it costs all its entries, `speed.md` §3.5) | MLIR's level types, iterators, codegen, Merger | thousands of lines (*conjecture*) | yes | no: the hash-cons is the machine's table |
| U-M4 | sparse outputs that grow into caller memory or delete | sparsifier codegen | `sparse-mlir.md` U-S3, U-S4 | yes | no: growing state is the machine's (§6.1) |

`sparse-mlir.md`'s U-S1 (seeking intersection) is unchanged.

## 9. Performance against the dense C++ (measured, not the reason)

- **The target** is `speed.md` §2's engine: dense `u32` ids, one
  open-addressing table per op, an array union-find, rules as loops. The
  printed code matches it when: each kind and rule is its own loop nest
  (no tag dispatch: one table per kind); every access is an unchecked
  `memref.load` or `store`; scalars live in `iter_args`, never memory;
  the hash is a few `arith` ops inline; no call in a matcher's loop (hooks
  only in the apply, `sparse-mlir.md` §2.9); nothing allocates in a loop.
  The printed union-find and hash-cons have all of these (§5.4).
- **What loses, measured or read in the printed code:**
  - `search` returns a position and the caller probes it again
    (`hc.canon.mlir`: the slot recomputed and the class column reloaded
    after the loop). The hand loop acts where it stops. The fix is the
    representation-first one: `search` returns what its body learned, a
    staged sum, not a position to re-read (*decision*).
  - the in-bounds test is its own `scf.if` inside the probe loop, where
    the hand loop has one condition;
  - the truncating subtraction is two ops where C has one (`minui`,
    `subi`), kept so that both interpretations mean the same on every
    state, reachable or not;
  - the call boundary: the C baseline inlines its `find`, the printed one
    is called across an object (LTO would remove it, *conjecture*);
  - the per-probe mask computed in the loop (LLVM hoists it, *recalled*).
  Together: 1.11× on the union-find, 1.23× on the hash-cons (§5.4).
- **What would lose more** (*conjecture*): the dictionary leaking into the
  printed code (it cannot: printing runs the instance, so the MLIR has no
  indirection); a sparse output materializing matches (2.3× the join,
  `sparse-mlir.md` §0) or counted then materialized (1×); rebuild by full
  re-scan on long schedules (1.4 ms per idle iteration at 100k nodes,
  `speed.md` §2.2), which the worklist and use lists avoid.
- **Not measured**: rebuild, the joins, extraction, the stock host's
  printer time on the whole engine.

## 10. What it costs

- **Proof burden.** `Fin` positions need an erased proof at every
  construction (`natToFinLT … {prf}`), and each running body must build
  its proofs from `Bool` tests, never from `Dec` built at run time (§5.3).
  The phase's transitions (`union`, `rebuild`, `freeze`, `thaw`,
  `meetInto`) are a trusted kernel: their types claim "clean", "frozen",
  "merged", which their code establishes and Idris does not check against
  table contents. Proofs over contents ("every stored id is a root") are
  research; the kernel is small and listed.
- **Linearity on the stock host** (*measured*, each hit while writing the
  sketch):
  - Idris's `Pair` holds unrestricted fields, so a pair of tables is a
    linear pair of our own (`Phase.Both`); a signature with `Pair`
    type-checks and every body using it fails;
  - a linear value inside an unrestricted expression (`s :: names vs`)
    is refused: helpers return `!* List String`;
  - a branch's two continuations each want the tables: the running
    interpretation calls one, the printer both, from names;
  - a `let` pattern on a linear `Res` inside a `let` block with erased
    bindings is refused ("not accessible"); a `case` works;
  - a large `do` block whose type is postponed took minutes to fail
    (`search`'s region); given its own signature it checks in about a
    second.
- **The subset idris-mlir compiles** (*conjecture*, no idris-mlir here):
  the running interpretation is a type family (`El`) applied to slot
  types inside `Vals`; whether every use is fixed by specialization, or a
  field's representation depends on an erased value somewhere, is the
  first check when the frontend first compiles `mlir-machine`.
- **The stock host is about 60× C** on the union-find (§5.3). The
  elaborator's unions per definition decide whether that matters
  (`unknowns.md` U18).
- **The discipline.** A staged program branches and loops only through
  the machine; an Idris `if` on a printed value cannot be written, which
  is the point and the price (`one-engine.md` §2.2).

## 11. What it changes in `one-engine.md` and `sparse-library.md`

`one-engine.md`:
- §0, §1, §3, §4 step 1, §6.1: the elaborator runs the source through
  `Eval`; `libs/mlir-relational-egraph` and the engine's Idris printing
  go (if the owner takes §13 question 2).
- §2.2: the `Machine` sketched there gains its working form (§5.1): tables
  threaded linearly, facts on values, three loop forms, `Vals`; the
  `Table : Input | Output` split becomes `Frozen` and `Growing`, which say
  more.
- §5.1: the header's `Tables` gains §6.3's buffers (spare slots, use
  lists, worklist, match tables, scratch) and the `Pow2` fact; the
  union-find's comment "representative = smaller id" becomes "distance to
  the parent, 0 at a root".
- §5.2: "the engine allocates nothing" holds for the machine; sparse
  temporaries go through the scratch region behind a count (§6.1 item 4).
- §8 item 6: the stock host's speed is measured (§5.3).

`sparse-library.md`:
- §5's union-find on `Linear.Vec` becomes the machine's distance table on
  a linear array of fixed capacity (it never grows); its "capacity grows
  by copying at doubling" goes for every engine table.
- §5's insertion through the bag stays for the closing schedule and the
  full rehash; node creation is the hash-cons (§4.6).
- §6 step 1: `LArray`'s stock-host bodies over `ArrayData` primitives,
  not `Data.IOArray` (`unknowns.md` U18's 4-5×), each write's result
  depending on its effect until U-M1 lands.
- §6's route table: under G the library's generating set is also an
  interface; the machine is that interface's first instance pair.

## 12. The design, in one place

The machine is `libs/mlir-machine`: a tagless-final interface whose
tables are quantity-1 values and whose positions, fills and sizes carry
their bounds in their types; a running interpretation that is the one
meaning on the stock host (linear arrays, `Fin`, erased proofs from `Bool`
tests); and the general constructs written once over it: a union-find
of distances with path halving and least roots, an open-addressing
hash-cons with keys in the slots and fresh ids at the fill, a worklist of
absorbed roots, and a lattice store written only by meeting. Over it,
in `mlir-relational`, the e-graph's phases are indices (pending repairs,
classes, a brand, frozen and growing), rebuild ends by classes plus
pending, extraction starts from creation nodes with positive weights, and
a round ends saturated or stopped by a full table. `specgen` holds the
printing interpretation, which turns the same source into `arith`, `scf`
and `memref`, with sparse kernels only over frozen snapshots. No primitive
is added, nothing grows, and every stop is a budget.

## 13. For the owner, one at a time

Each waits for the one before it.

1. **May the hash-cons, union-find and worklist be library code in Idris
   over linear arrays?** 0015 D3 says "What upstream lacks (hash tables,
   strings, tries, data-dependent control) becomes `idr` ops or runtime
   primitives, never hand code in the library"
   (`proposals/0015-relational-core.md:229-235`, *read*). *A*
   (recommended): amend D3 for the machine. It buys the D97 form: one
   source run and printed, its invariants in Idris's types, and no C++
   meaning for a data structure; upstream has every piece of it (`arith`,
   `scf`, `memref`), so nothing is lacking but the composition. It costs
   D3's rule that a library never hand-writes what an op could mean, and
   0015's throughput gate applies to it as written. *B*: the hash-cons as
   an `idr` op or a runtime primitive: its meaning in C++, a call in the
   printed code, the elaborator calling the runtime, and the types stop at
   the call.
2. **Does the elaborator run the engine's source, or a printed Idris
   copy?** D86 recorded "an Idris form generated from the same source"
   (`0000:1255-1256`). *A* (recommended): run the source through `Eval`
   (§5.6). It buys one generated package, one printer and one manifest
   row fewer, and the stock host runs what Idris checked. It costs the
   interface's dictionary on Chez (within a small factor of direct code,
   §5.3) and an amendment to D86. *B*: as recorded: a second printer and generated
   package, with nothing to unfold for the closing schedule.
3. **How much rests on a trusted kernel?** The phase indices hold only if
   `union`, `rebuild`, `freeze`, `thaw` and `meetInto` keep the promises
   their types make about table contents. *A* (recommended for P0): those
   five, listed, reviewed and searched (the fixtures of
   `one-engine.md` §6.3 and the running/printed agreement of §5.4), with
   contents unproved. *B*: prove the contents (every stored id a root,
   every slot's key its node's), research-sized proofs over linear arrays
   before the engine lands.

*For the coordinator to record* (settled by AGENTS.md or the evidence):
- U-M1 carried as `upstream/<NN>-identity-effectful-let/` with the
  reproducer, a `tests/upstream-…` check and a `PINS.md` entry; `LArray`'s
  bodies make each write's result depend on it meanwhile;
- `search` returns what its body learned (§9), a fix to the machine
  before the engine is written over it;
- the machine's place (§1.2), the bag and hash-cons split (§4.6), the
  boundary's buffers (§6.3), and §6.1's growth rule as the answer to
  `sparse-mlir.md` §9 question 1;
- U-M2 recorded and not carried until a scan measures the need.

## 14. Sources

- Ours: `AGENTS.md` (working tree); `.claude/skills/representation-first/SKILL.md`;
  `proposals/0000-mlir-native.md` (D15, D16, D41-D43, D48, D57, D60, D67,
  D69, D84-D87, D91, D97-D100); `proposals/0015-relational-core.md`
  (§0-§5, D1-D10); `audits/p0/design/egraph.md` (§3, §4, and `:666-667`,
  `:901`); `audits/p0/design/one-source.md` (§5-§6, §10);
  `audits/p0/design/egraph-full/{one-engine,speed,sparse-mlir,sparse-library}.md`
  (whole), `unknowns.md` (§0, U8, U17-U19, §5, §6), `workloads.md` (§0,
  §4, §5), `payoffs.md` (§0); `libs/mlir-array/{Array/Core.idr,Linear/Vec.idr}`;
  `libs/mlir-linear/Linear/Notation.idr`; `upstream/55-lazy-case-scrutinee/README.md`.
- Stock Idris at the pin: `third_party/Idris2/src/Compiler/Opts/Identity.idr`
  (whole), `src/Compiler/Inline.idr:185-215`,
  `libs/prelude/PrimIO.idr:90-110`, `libs/base/Data/IOArray/Prims.idr`,
  `libs/base/Data/{Fin,Nat,Bits}.idr`, `Control/WellFounded.idr`.
- MLIR at the pin: `lib/Conversion/FuncToLLVM/FuncToLLVM.cpp:72-130,
  392-424`, `lib/Conversion/LLVMCommon/TypeConverter.cpp:593-602`,
  `lib/Dialect/LLVMIR/IR/LLVMDialect.cpp:4755-4785`.
- Outside code, read by this task's agents at the lines cited: egglog
  6b42f908 (`core-relations/src/{table,hash_index,uf,free_join,row_buffer}`,
  `egglog-bridge/src/lib.rs`, `union-find/src/`), egg 73975c98
  (`src/{egraph,unionfind,eclass,run}.rs`); Soufflé from its papers only
  (CC 2016, PMAM 2019 Brie, PACT 2019 eqrel's PiggyList; no source tree
  was local). Issue trackers through `gh`: egraphs-good/egg, egglog,
  extraction-gym; bytecodealliance/wasmtime; uwplse/ruler;
  herbie-fp/herbie (every URL in `/tmp/eg-machine/bugs/catalogue.md`).
- *Recalled*: Carette, Kiselyov and Shan's tagless-final staging (JFP
  2009); Reynolds's abstraction theorem (1983); Tarjan and van Leeuwen on
  path halving with arbitrary linking.
- Scaffolding, not committed: `/tmp/eg-machine/sketch/` (`Machine`,
  `Eval`, `Print`, `UnionFind`, `HashCons`, `Phase`, `LArr`, `RunUF`,
  `PrintUF`, `PrintHC`, `MixCheck`), `/tmp/eg-machine/c/` (`uf.c`,
  `drive.c`, `hcdrive.c`, `mix.c`), `/tmp/eg-machine/{uf,hc}*.mlir`,
  `/tmp/eg-machine/idbug/Bug.idr`, `/tmp/eg-machine/bugs/catalogue.md`.
