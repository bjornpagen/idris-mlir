<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the unknown unknowns of the one e-graph engine

Status: written 2026-10-21 for D85 to D87 (`proposals/0000-mlir-native.md:1232-1273`),
at the owner's "let's try to answer the unknown unknowns". The design under
test: one full equality-saturation engine written once in Idris over D87's
sparse library, printed as MLIR for the C++ optimizer and as Idris for the
elaborator, rules from the dialect's specification, budgets that leave code
less optimized and never refuse. This file asks what nobody has asked yet,
beyond `design/egraph.md` §10 and the siblings `one-engine.md`,
`sparse-mlir.md`, `sparse-library.md` and `speed.md`, settles what a cheap
experiment settles, and queues the rest. The owner named the stress case
during the work: parser combinators, linear ones over a quantity-1 byte
buffer most of all ("it stress tests like every part of our compiler",
2026-10-21); §4 is its questions. `workloads.md`, which builds the parser
workload, had not appeared when this was written, so nothing here rests on
it.

Grounds: *read* (path:line, or a URL), *measured* (command and input
named; scripts in `/tmp/eg-unknowns/`), *recalled*, *conjecture*,
*decision* (a ruling Dn). Ours at HEAD e96bb991 with the working tree's
proposal. Tools: stock Idris 0.8.0-1c630e67c on the Chez in `.toolchain/`;
Apple clang; Homebrew LLVM/MLIR 22.1.8 (`/opt/homebrew/opt/llvm@22`),
**not our pin**, so every MLIR measurement is labelled 22.1.8; egg at
73975c98 and the egglog 3.0.0 (6b42f90) binary that `speed.md`'s agent
built under `/tmp/egraph-full-speed/`; Python 3.15 for a toy e-graph
(semantics only, never speed). Machine: Apple M2 Max (virtual), shared,
load average 9 to 28 during the runs, so times are rough and ratios
within one run are what to read. Nothing in the repository was built or
changed except this file.

## 0. In plain words

- **Five findings that change something.**
  1. *`total` does not mean crash-free.* Stock Idris reports
     `g x = div x 0` total, and it crashes (*measured*, U1). Every place
     the design reads "total" as a licence to delete or float a call must
     read the derived effect row instead, and AGENTS.md's "a function
     proved `total` ... may be deleted when unused" meets a crash it did
     not foresee: an owner question.
  2. *One wrong rule pair collapses a whole function.* `0 / x → 0` and
     `x / x → 1`, each right whenever the divisor is non-zero, merged
     `0` with `1` and every root of a six-root function with every other
     (*measured*, U3). And the textbook rule set (`x * 0 → 0` first among
     the culprits) changed the meaning of 2 of 6 roots when a crashing
     operation sat in the pure graph (*measured*, U2). The floating class must hold no
     operation that can crash, by construction.
  3. *The parser stress case explodes under plain rules.* An alternation
     of n keyword parsers under associativity, swapping alternatives whose
     first bytes differ, and left factoring grew 216, 3,888, 58,320 and
     787,320 `Alt` nodes for n = 4, 6, 8, 10, and did not finish at 12 in
     300 s (*measured*, egglog, U27). The fix is a representation (a
     disjoint alternation as a map keyed by first byte), not a budget.
  4. *Combinator laws cannot be rules over closures.* After
     defunctionalization a new lambda is a new label and a new function, a
     module change a parallel function pass may not make; before it, an
     optimization would run ahead of the refusals (*read*, U25). Combinator
     fusion has to come from specialization, inlining, case-of-case and
     known-case folds over first-order code.
  5. *The sparse engine's relations meet our IR's shape badly.* Our ops are
     variadic (32 variadic operand lists, matches with thousands of
     regions) and their kinds are per program (a family's constructors, a
     callee), while `sparse-mlir.md` prints one fixed-arity kernel per op
     kind before any program exists (*read*, U9); and a rule cannot mint a
     type on a worker, so any rule whose right side needs an index-term
     type the function lacks cannot fire (*read*, U10).
- **What a real engine showed that the toy could not.** egglog extracts a
  different equal-cost program at 1 thread and at 8, each stable
  (*measured*, U5). egg's proofs cost 2.1× the run's time and 3.9× its
  memory at 157k nodes, and 2.7 s for one explanation (*measured*, U4).
- **What the toy did not show.** Adding one rule changed no function it
  could not match, and a larger budget never gave a dearer program (12 and
  128 trials, U6, U7). Both stay open for a real engine.
- **Cheap answers.** Chez runs the elaborator's union-find at 1 to 1.5 µs
  per union over `Data.IOArray`, 4 to 5 times slower than over primitive
  arrays and about 65 times C (*measured*, U18); printed kernels cost about 6 ms
  of sparsifier and 45 ms of `clang -O3` each, linearly (22.1.8, U21);
  MLIR carries Idris source lines into DWARF (22.1.8, U20); nothing
  upstream in MLIR is an e-graph (*read*, U22).
- **For the owner, one at a time** (§6): effects inside the graph or not;
  what wins when the node budget exceeds the host's memory; whether a
  crashing `total` call may be deleted; the parser buffer's
  representation; whether the optimizer may raise peak memory.

## 1. Meaning and soundness

### U1. Does Idris's `total` exclude a crash?

- **Why it matters.** `egraph.md` floats "a call whose row is empty (a
  `total` callee, D13)" (`egraph.md:304`) and gives its rule language a
  `Total` condition that licenses deleting calls (`egraph.md:565`, E6 at
  `:966-973`: "legal only when every label of `f` is `total` (D13:
  deleting calls deletes their crashes and loops)"). AGENTS.md:138-141:
  "a function proved `total` carries no divergence effect, may be deleted
  when unused".
- **What breaks if not.** A rule or a dead-code step reading `total`
  deletes a crash eager evaluation must run.
- **Experiment** (*measured*, `/tmp/eg-unknowns/idris/Tot{,2,3,4}.idr`,
  stock Idris on Chez):
  - `idris_crash` is `partial` (*read*, `third_party/Idris2/libs/prelude/Builtin.idr:204-206`),
    and a total function calling it is refused ("Calls non covering
    function Builtin.idris_crash").
  - `g : Int -> Int; g x = div x 0` under `%default total`: `:total g`
    answers "Tot4.g is total". Run, `printLn (divz 7)` ends with "ERROR:
    Unhandled input for Prelude.Num.case block in div at
    Prelude.Num:128:3--130:40", exit 1. `Integer` the same.
  - The prelude's `div` is `case y == 0 of False => prim__div_Int x y`
    with no `True` arm under `%default total` (*read*,
    `third_party/Idris2/libs/prelude/Prelude/Num.idr:6, 90-95, 127-133`);
    the same shape in user code is refused ("Calls non covering function
    Tot3.case block in f"). The checker treats the prelude's method as
    total and the user's identical case as not: an upstream
    inconsistency, recorded here for the fork's maintainers.
  - Upstream's Chez backend also deleted `let _ = divz 7` (the program
    printed "after divz" before the next crash), the optimizer behaviour
    AGENTS.md already names (`AGENTS.md:131-134`).
- **Answer.** Settled as fact: `total` is not crash-free. What licenses
  deletion or floating is the derived row having neither `crash` nor
  `divergence` (D22, D27); the `Total` condition of `egraph.md` §3.1 and
  E6 becomes a row condition. Whether an unused crashing call in total
  code is deleted is the language's meaning: owner question 3 (§6).

### U2. Can anything in the floating class crash?

- **Why.** Equality saturation's rules drop subterms (annihilators,
  cancellations); a dropped subterm that can crash takes its crash with
  it. `egraph.md` §3.1's `safe` proof governs dropped *uses*, not dropped
  *crashes*.
- **Breaks.** Textbook-sound rules become miscompiles.
- **Experiment** (*measured*, `toy/t1_unsound.py`: six random roots of
  depth 3 over `+ - * /` with `/` crashing on zero, ten standard rules,
  three rounds, 3,000-node budget, 64 environments): with the *sound* rule
  set, program 0 had 2 of 6 roots whose extracted program differs from
  the original on some input. Checking each union (U3) named the first
  wrong one: `x * 0 → 0` dropping a crashing `/`. After it, 111 later
  unions, most of them associativity, distribution and factoring, also disagree
  (*measured*, `toy/t3.py`): they are right, but their classes were
  already polluted, so only the first disagreement names a culprit.
- **Answer.** Settled: the engine is sound only if no floating op can
  crash. Our IR already moves partial checks into skeleton guards whose
  refined result the total op reads (D21), so this is a prerequisite to
  hold for every op, not a new mechanism: every runtime primitive that
  can fail (string indexing, big-integer division, `handle.string`'s
  undeclared crash, `egraph.md:323-328`) is split into a guard and a total
  op before it may float, and the row classifier (§2.1 of `egraph.md`)
  is the one place that decides it.

### U3. How far does a wrong rule spread, and what catches it before it ships?

- **Why.** A destructive pass with a wrong pattern breaks the sites it
  matches. An e-graph unions, and congruence carries the union to every
  term built on it.
- **Experiment** (*measured*, `toy/t2.py collapse`): roots
  `(a-a)/(a-a)`, `(b+1)*c`, `b*c`, `c+1`, `c`, `b*c+1`; sound rules plus
  the pair `0 / x → 0`, `x / x → 1`. Sound: 11 classes, no two roots equal.
  With the pair: **2 classes, `0 = 1`, all 15 pairs of roots equal**.
- **What catches it** (*measured*, `toy/t1_unsound.py`): validating every
  union by extracting its two classes just before the merge and running
  both on inputs. Uniform 32-bit inputs found the first bad union in 2 of
  5 programs; a dictionary of edge values (`0, ±1, ±2, 2³¹-1`) in 4 of 5
  (the fifth showed none with either). For `f64` (*measured*, `c/floatlaw.c`,
  100M uniform bit patterns against a nine-entry dictionary): `x + 0.0 →
  x` failed at uniform draw 6,213 (a NaN payload) and at dictionary entry
  1 (`-0.0`); `x - x → 0.0` and `x * 0.0 → 0.0` fail on infinities and
  `-0.0`; `x * 1.0 → x` could not be tested, because LLVM folds it in the
  harness.
- **Answer.** Settled in direction: `egraph.md` §3.5's search must seed
  its inputs from a dictionary of edge values (the testing skill's §3),
  must check rule *pairs* through congruence and not rules alone (each
  rule of the pair above is true off zero), and must run the float laws
  bit for bit. One more fact for the rule source: upstream marks
  `arith.addf`, `mulf` and the float min/max family `Commutative`
  (*read*, `mlir/include/mlir/Dialect/Arith/IR/ArithOps.td`, 20 ops); read
  as laws (`egraph.md:610-612`), commutation can change which NaN payload
  propagates on a target (*conjecture*), so float laws need their own
  check before upstream's traits are read as rules.

### U4. When a program is miscompiled, how is the guilty rewrite found?

- **Why.** A destructive pass is bisected by pass and by pattern. A
  saturated e-graph's output depends on every union, and turning a rule
  off changes every later id.
- **Experiment, proofs** (*measured*, `egg/`, egg's explanations on its
  math benchmark, 23 rules, 7 seeds): at 30k nodes, run 0.27 s → 0.41 s,
  RSS 54 MB → 194 MB; at 157k nodes, run 1.31 s → 2.76 s (2.1×), RSS
  348 MB → 1.36 GB (3.9×), and one explanation took 2.69 s.
- **Experiment, replay** (*measured*, `toy/t1_unsound.py`): with a
  deterministic engine the unions form a sequence; checking each union by
  running its two sides on dictionary inputs named the first wrong union
  and its rule (program 0: union 23, `self/`; program 4: union 15,
  `self/`), with nothing kept during normal runs.
- **Answer.** Settled in direction: never keep proofs on (2× time, 4×
  memory); replay the one function with union checking on, which needs
  only determinism (U5) and the union log. Open: whether a checking
  replay is a "behaviour-selecting option" in AGENTS.md's sense; its
  output is identical, so it reads as a diagnostic (*conjecture*; L14's
  call on actions, `egraph.md:720-726`).

### U5. Is the result the same at any thread count and any hash order?

- **Why.** Byte-identical output at any thread count is a P0 promise
  (`egraph.md:718-726`, DP-34).
- **Experiment** (*measured*, `parser/x8.egg`, `x64.egg`, egglog 3.0.0,
  three runs each at `-j 1` and `-j 8`): each thread count is stable, and
  the two differ: at `-j 1` and `-j 8` egglog extracts two different
  equal-cost alternations (`parser/j1.txt`, `j8.txt`). The state of the
  art's tie-breaking follows thread scheduling.
- **Answer.** Settled for the design as written: one function's e-graph
  is serial, ids in walk order, ties by id. Two consequences stand. (a)
  Parallelism inside one e-graph, which `speed.md` §5 says would be the
  only lever on the largest function's wall, must assign ids
  deterministically or give up byte identity. (b) Ties by creation id
  make the output depend on rule order (U6); a tie broken by a total
  order on content (kind, then children's best costs, then their content
  ranks) removes that, at the price of computing the rank.

### U6. Does adding one rule change functions it never matches?

- **Why.** Under a budget, which nodes fill the table depends on every
  rule's matches; ids, ties and the budget's cut move with them. If so,
  every rule added changes code everywhere, and golden outputs and
  bisection degrade.
- **Experiment** (*measured*, `toy/t2.py stability`, six programs of eight
  roots, budgets 150 and 400 nodes, one added rule on `-`): in no run did
  a root without `-` change its extraction (0 of 18 such roots per
  budget).
- **Answer.** Not observed in the toy; open. Cheapest real check: at
  stage 1, add one rule and diff the output of every function where it
  matched nothing.

### U7. Can a larger budget give worse code?

- **Why.** AGENTS.md's budget rule says a spent budget leaves code "less
  optimized"; that presumes more budget is never worse. Greedy tree-cost
  extraction is monotone in tree cost by construction; real cost (sharing,
  counting, `egraph.md` §5) need not be.
- **Experiment** (*measured*, `toy/t2.py monotone`, 8 programs, budgets 60
  to 380 nodes in steps of 20, cost with sharing counted once): DAG cost
  never rose in 128 steps.
- **Answer.** Not observed; open, and tied to U23: it matters exactly
  when extraction's cost differs from the cost the program pays.

## 2. Representation inside the engine

### U8. What happens to a rule that builds an identity-bearing node?

- **Why.** `egraph.md` §2.3-2.4 keep every `Allocate`-on-`identity`
  producer (linear values, `in_place` values, memo cells, D34's cells) out
  of the hash-cons. Saturation reaches a fixpoint only because building
  an existing node is a no-op.
- **Experiment** (*measured*, `toy/t2.py unique`): one rule `cell x →
  cell x` whose right side is never hash-consed made one node per round
  and was still going after 50 rounds; the same rule hash-consed
  saturated in one round with two nodes.
- **Answer.** Settled: a rule may never make a unique node. In the rule
  language that is a type: `Make` indexed by the kind's class, with no
  constructor for a unique kind (as `one-engine.md` §2.3 already denies
  `Make` to the closing schedule). Rewrites that need a fresh cell
  (case-of-case copying a linear constructor, E9) stay skeleton rules,
  applied once, outside saturation.

### U9. Do variadic ops and per-program kinds fit fixed-arity printed relations?

- **Why.** `sparse-mlir.md` §2.1 keeps "one tuple table per operator kind
  `f` of arity `k`", with each rule printed as its own kernel before any
  program exists; `one-engine.md` §5.1 passes children as CSR. Our ops are
  variadic: 32 `Variadic<` operand lists across our `.td` files and
  `idr.match`'s `VariadicRegion` (*measured*, `grep -c "Variadic<"` over
  `foreign/idr/include/idr/IR/*.td`; `IdrMatchOps.td:33`), a call's arity
  is its callee's, a `con`'s its constructor's, and a family's
  constructors exist only in the program (D48).
- **Breaks.** A rule over `field_i (con C xs)` (the known-case fold, the
  first rule anyone writes) has no fixed-rank kernel; a match of 20,000
  cases is one node of arity 20,000.
- **Cheapest experiment.** Print the known-case fold over a
  `Child(node, position, class)` relation, which has fixed rank for every
  arity, and measure its join beside `sparse-mlir.md` §6's.
- **Answer** (*conjecture*). The two sibling designs disagree and must
  meet: either kinds stay the dialect's (static) with variadic children in
  a positional relation (every pattern gains one atom per child, a join
  cost to measure), or per-program kinds go to a C++-side table, which
  means the printed kernels are generic over kinds and lose the
  per-kind specialization `speed.md` §2.3 credits for most of its 7-9×.
  Not settled; it decides how much of `speed.md`'s factor survives.

### U10. Where does a new intermediate node's type come from?

- **Why.** E-classes are typed (`egraph.md` §2.5) and no type is made on
  a worker (`AGENTS.md:443`; `egraph.md:662-665`: "a per-run intern of the
  function's types, built serially before the parallel walk"). A rule's
  right side may need a type the function never held: reassociating
  `(xs ++ ys) ++ zs` over `Vect` needs `Vect (m + p)`.
- **Breaks.** Either such rules cannot fire, or the engine makes uniqued
  MLIR types under the context's lock (the contention `AGENTS.md`'s
  98c6315c line records), and MLIR's uniqued types are never freed, so a
  saturation that mints index terms grows the context for the rest of
  the compile (*recalled*: storage uniquer allocations live as long as
  the context).
- **Answer** (*conjecture*, from the cited rules). The engine holds D48's
  index language as its own data (terms interned per function, beside the
  node table), and a type is made only at elaboration, serially, for the
  extracted nodes. This is a core shape (which structure holds the fact),
  for the coordinator to settle with this evidence and the owner to
  review.

### U11. Can the sparse relational engine hold binders?

- **Why.** D85's full form puts pure region ops in the graph
  (`egraph.md` E10, §10.3); the parser case is closures and continuations
  all the way down. Region arguments need slotted classes or De Bruijn
  indices; slotted classes carry renamings per node and symmetry groups per
  class (*recalled*: Schneider et al., PLDI 2025, read only by summary in
  `egraph.md:251-255`), which are not tuples of class ids.
- **Cheapest experiment.** Encode one slotted rule (β-like substitution
  into a match arm) as relations with explicit slot columns and count the
  atoms; compare against the De Bruijn baseline the typed follow-up
  measures (`sources/papers/wu-2026-slotted-egraphs/appendix_eval.tex:47-48`,
  *read*: "Java egglog + De Bruijn" is one of its baselines).
- **Answer.** Open (*conjecture*: slots do not map to fixed-rank sparse
  relations without a renaming relation per node). Whether D85's region
  terms are in P0 at all is scope (owner question 1 covers it with
  effects).

### U12. Is a class's best node the same at every use?

- **Why.** Cranelift needs `subsume` because a class may hold a node using
  a value unavailable where the class is used (`egraph.md:146-152`).
  Under full saturation most rules are `Equal`; the `eqsat` authors say
  scoping is "not revealed by inspecting the graphical e-graph structure;
  ... encoded only in the IR" (*read* through a search summary of
  arXiv 2505.09363).
- **Breaks.** One global "best node per class" picks a node whose
  operand exists only inside a match arm, for a use outside it.
- **Answer** (*conjecture*). With SSI (refined values are new values,
  `egraph.md` §2.2) a rule's right side uses only classes its left side
  bound, but a bound class may itself hold nodes of different
  availability; extraction then has to be per (class, scope depth), the
  cost Cranelift avoids by never keeping a narrower member. Cheapest
  check: count, at stage 1, classes whose members' available regions
  differ. Open.

### U13. Is the effect skeleton inside the graph in D85's full form?

- **Why.** `egraph.md` kept effects out of the graph (the region skeleton)
  and so kept extraction greedy and linear; eggcc threads one state value
  and its extraction is NP-complete even to find a valid one, statewalk
  DP O(k·n²) in width k (`speed.md` §1.4). Our tree has several ordering
  resources (D27); a skeleton that is a partial order per resource
  subtree (E11) multiplies the widths (*conjecture*).
- **Answer.** Not settleable by experiment: D85 reversed the two tiers, so
  whether "full research form" means effects inside is the owner's scope
  call (§6, question 1). Everything else in the design changes with it:
  extraction's algorithm, U12, and the cost of every function.

### U14. Can a parallel function pass read a callee's effects?

- **Why.** Classifying `idr.call` reads the callee's row; the e-graph may
  narrow a callee's row while another worker reads it.
- **Answer** (*read*, settled). MLIR forbids it: a pass "must not inspect
  the state of operations that are siblings of the current operation"
  (`.toolchain/llvm-project/mlir/docs/PassManagement.md:29-31`). AGENTS.md
  already puts the callee's row on the call (`AGENTS.md:470`), so the
  e-graph reads the call's copy. A narrowing reaches callers only after a
  module step re-derives rows; interprocedural gains come from
  alternating module steps and function passes, never from one pass.

### U15. How many times does each function pay for saturation?

- **Answer** (*read*, settled; the multiple *conjecture*). The e-graph runs
  at four pre-counting points (`egraph.md` §6), and as the inliner's
  simplification pipeline (L18 I7) it runs up to `max-iterations` = 4
  times per SCC (`.toolchain/llvm-project/mlir/include/mlir/Transforms/Passes.td:329-331`),
  each run from nothing. `speed.md` §5 estimates one run per function;
  the real figure is that times roughly 4 to 8. The alternative is
  Tamagoyaki's persistent e-graph across passes, which `egraph.md` §10.3
  rejected because every pass would read a second form of the program; the
  multiple above is the price of that rejection, to be measured.

### U16. Do specialization copies multiply the engine's work?

- **Answer** (*read*, settled with one check). D58's layout copies differ
  in their pure programs and genuinely need their own saturation. D89's
  hold copies and the at most 4^k lifetime-mode copies
  (`audits/p0/design/lifetimes/static-handles.md:381-385`) change counting
  and allocation, not the value program; mode copies are made by the
  lifetimes lowering's decide step (`lifetimes/lowering.md:60-72`). As long
  as every copy axis that leaves the pure program unchanged is applied
  after the e-graph's last point, nothing is saturated twice; applied
  before, it would saturate identical programs, a known fact paid for
  again (D10). The pipeline order (L18 §2.1) must state it.

### U17. What happens when the node budget exceeds the host's memory?

- **Why.** The budget is `B × ops(f)` (`egraph.md` §4.5). Per node, the
  dense engine used 3.07 GB for 7,997,421 nodes, 384 B, and egglog
  9.37 GB, 1.17 KB (*derived* from `speed.md` §2.2's measurements). The
  largest function at stage 1 is 1.6M to 13M nodes at B = 16-64
  (`speed.md` §5, *conjecture* there): 0.6 to 5 GB dense, on one worker,
  beside seven others.
- **Breaks.** "Every size is the program's or the host's, never a round
  constant" (`AGENTS.md:241-242`). A budget in program units can exceed a
  small host and kill the compiler on one function (acceptance then
  depends on the machine, against `AGENTS.md:176`); a budget from the
  host's memory makes the output depend on the machine (against
  byte-identical output).
- **Answer.** A real tension, for the owner (§6, question 2). Cheapest
  measurement first: the largest function's arena at stage 1 (U1's
  instrument in `egraph.md` §7).

### U18. How fast is the elaborator's engine on the stock host?

- **Why.** The shipped frontend is the one stock Idris builds
  (`one-engine.md:422-424`), so the elaborator's closure runs on Chez in
  production, not only in bootstrap; `one-engine.md` §8 item 6 calls its
  speed unmeasured.
- **Experiment** (*measured*, `idris/Stock.idr`, `StockP.idr` against
  `c/stock.c`, n random unions over n ids with path halving, n inserts
  into an open-addressing hash-cons):

  | kernel, n = 4M | Chez, `Data.IOArray` | Chez, `ArrayData` prims | C `-O2` |
  | --- | --- | --- | --- |
  | union-find | 5.85 s user | 1.23 s | 0.09 s |
  | hash-cons inserts | 5.68 s | not run | 0.05 s |
  | sorted-list merge join | 0.05 s beyond building the lists | | 0.01 s |

  About 1.4 µs per union over `IOArray`, 0.3 µs over the primitive
  arrays; `IOArray` stores a `Maybe` per cell
  (`third_party/Idris2/libs/base/Data/IOArray.idr:10-11`), which is the
  4-5×.
- **Answer.** Settled per operation; the total is open until the
  elaborator's unions per definition are counted at stage 1.
  `sparse-library.md:534` puts the union-find over `Data.IOArray`; its
  `Maybe` costs 4-5× on the stock host, so the library should choose a
  representation without it (whether base's `ArrayData` primitives are
  reachable from `libs/` under idris-mlir is for that file).

### U19. Does anything in the engine recurse on the input's size?

- **Answer** (*read*, settled with one check). D33 forbids it in our
  tools. The printed kernels and loops are iterative (`sparse-mlir.md`
  §2.6-2.8), extraction is a sweep, and Cranelift's elaborator keeps
  explicit stacks (`egraph.md:156-161`). Two places to check with a
  fixture of a 100k-deep extracted chain (a reassociated `++`): the C++
  adapter's write-back of the extraction into regions, and MLIR's own
  recursion over the nesting the extraction produces (D33's upstream
  list). The printed Idris runs on Chez's heap-grown stack, and under
  idris-mlir on D31's frame stacks.

### U20. Can the printed engine be debugged and profiled at its source?

- **Experiment** (*measured*, 22.1.8, `mlir/dbg.mlir`): ops located at
  `loc("Relational/EGraph/Source/UnionFind.idr":42:9)`, lowered with
  `--ensure-debug-info-scope-on-llvm-func="emission-kind=LineTablesOnly"`,
  translated and compiled with `clang -O2 -g`, give a DWARF line table
  whose file is `UnionFind.idr` with lines 39, 42 and 45.
- **Answer.** Settled for the toolchain: a sampled profile or a debugger
  can point at the Idris source. Open: a tagless-final source
  (`one-engine.md` §2) has no call-site positions unless each machine
  call carries one (*conjecture*: Idris has no call-site location without
  elaborator reflection); otherwise lines point into the committed
  `Engine.mlir`, which is usable.

### U21. What do printed kernels cost the build?

- **Experiment** (*measured*, 22.1.8, `mlir/k{1,10,100,400}.mlir`: N copies
  of `sparse-mlir.md`'s join kernel): `mlir-opt --sparsifier` 0.07, 0.10,
  0.61, 2.45 s; `mlir-translate` and `clang -O3 -c` 0.18, 0.69, 4.35,
  19.2 s; objects 8 KB to 1.86 MB (4.6 KB per kernel).
- **Answer.** Settled: linear, about 6 ms plus 45 ms per kernel per
  target. A rule of n atoms prints n semi-naive variants, so 300 rules are
  roughly 750 kernels, 40 s per target (*conjecture* on the rule count); a
  Ruler-style synthesized rule set of thousands is minutes per target,
  which D7's measured build cost must carry.

### U22. Upstream first: what does MLIR's own e-graph work offer?

- **Answer** (*read*, 2026-10-21, settled). Nothing upstream: no RFC and
  no pull request found (web searches), and `egraph.md:186-195` found none
  at the pin. The `eqsat` dialect and its PDL-based e-matching are in
  xDSL, Python (arXiv 2505.09363 and 2602.16707); DialEgg shells out to
  egglog (`egraph.md:196-202`); E-Path (arXiv 2605.28694) is a four-page
  CFG proposal. AGENTS.md:508's order (upstream, patched, ours) has no
  first step to take; the one upstream mechanism that could carry
  matching is `pdl_interp`'s compiled matcher, which Tamagoyaki extended
  outside upstream. Recorded as the alternative D86 did not take.

### U23. Does the cost model see what counting and the hardware will pay?

- **Why.** Extraction runs before counting; hash-consing merges equal
  constructions, which counting then pays for in `dup`s and lost in-place
  rebuilds (`egraph.md` E7, §5). A cost per target would make the
  extracted program differ per target, and the target is decided in one
  place (AGENTS.md's targets section).
- **Answer.** Open (*conjecture*): keep one target-neutral table in
  program units (allocations, calls, counted uses), leave instruction
  costs to LLVM, and measure `egraph.md` §10.3's k-candidate extraction
  with counting's walk on stage 1 before trusting any estimate.

### U24. May the optimizer raise a program's peak memory?

- **Why.** Sharing an equal value and hoisting extend lifetimes: a large
  structure built twice, far apart, becomes one structure live across
  everything between (*recalled*: the space leaks GHC's full laziness and
  CSE cause). D26's frame-limited property allows it, since the value is
  live; the program's peak memory can still grow by the structure's size,
  or by a factor where it happens in a loop.
- **Answer.** A promise to users, so the owner's (§6, question 5).
  Cheapest measurement: peak footprint of the program suite with and
  without hash-consing of constructions.

## 4. The stress case: parser combinators over a quantity-1 buffer

### U25. Where does the e-graph sit relative to defunctionalization and specialization?

- **Why.** A combinator tower is closures; its laws are about closures.
- **Answer** (*read*, settled). After defunctionalization every closure is
  a label of a closed sum and an application a dispatch; a law whose
  right side builds a new lambda (`(p >>= f) >>= g = p >>= \x -> f x >>= g`)
  needs a new label and a new function, a change to the module a
  function pass may not make (`PassManagement.md:33-36`). Before
  defunctionalization the e-graph would optimize ahead of the refusals
  (`AGENTS.md:176-178`; `egraph.md` §2.10). So combinator fusion is what
  specialization by label (L18), inlining, case-of-case and known-case
  folds over `Result` do to first-order code, which are directional
  rewrites; saturation adds value only on the algebra left after that.
  Open: whether that fuses a real tower, which is `workloads.md`'s parser.

### U26. Which parser laws are true?

- **Experiment** (*measured*, `parser/peg.py`, PEG choice, all inputs over
  `{a,b,c}` up to length 4): right distribution `(p <|> q) >> f = (p >> f)
  <|> (q >> f)` fails (input `abc`); left factoring `f >> (p <|> q) = (f
  >> p) <|> (f >> q)` and associativity hold.
- **Answer.** Settled: parser laws depend on the library's choice
  semantics, so they can only be the library's proven theorems (E6), never
  generic laws. Idris has no function extensionality (*recalled*), so a
  parser law is stated pointwise, `(b : Buf) -> run (..) b = run (..) b`,
  and the harvester matches it at application sites after specialization.
  A theorem about a quantity-1 buffer is fine as stated: equality types
  are quantity 0 (*conjecture*).

### U27. Does the alternation explode, and what removes it?

- **Experiment** (*measured*, egglog 3.0.0, `parser/gen.py`: an alternation
  of n keyword parsers `Seq (Chr c) (K i)`; rules: `<|>` associativity both
  ways, swap of adjacent alternatives whose first bytes differ, left
  factoring of a shared first byte):

  | rules | n | `Alt` nodes | wall |
  | --- | --- | --- | --- |
  | assoc + swap + factor | 4, 6, 8, 10 | 216; 3,888; 58,320; 787,320 | 0.01; 0.01; 0.26; 11.4 s |
  | assoc + swap + factor | 12 | did not finish | > 300 s |
  | assoc + factor | 8, 16, 32, 64 | 120; 816; 5,984; 45,760 | ≤ 0.53 s |
  | assoc + factor, 64 alternatives over 8 first bytes, interleaved | 64 | 45,760, and no factoring (64 `Seq` remain) | 0.55 s |

- **Answer.** Settled in direction. Associativity alone is cubic and
  cannot bring same-byte alternatives together; commutation is
  exponential. The representation-first answer is to make order among
  disjoint alternatives unrepresentable: a first-set analysis turns a
  disjoint alternation into one node mapping first bytes to parsers (a
  dispatch, which the lowering makes a switch), so factoring is merging two
  entries of one key and no permutation exists (*conjecture* on the node's
  shape; it needs U9's variadic nodes). The same reading applies to the
  arithmetic case `speed.md` measured, where one associativity rule made
  91% of matches.

### U28. Are the buffer's reads pure?

- **Why.** If the input is a quantity-1 buffer whose reads are `contents`
  reads (D27), every read is ordered, the combinator body is skeleton, and
  the e-graph sees little. If it is a quantity-1 handle to immutable
  bytes, reads have no resource (`AGENTS.md:493`: "Immutable memory has no
  resource"), peeks float, merge and hoist across `<|>`, and only the
  release is ordered.
- **What linearity still guarantees** (*read*, `egraph.md` §2.3): each
  combinator call that consumes and returns the buffer produces a linear
  value, never merged; un-factoring (`f >> (p <|> q)` into its
  duplicated form) is linear-safe only when failure hands the buffer back
  unconsumed, so the library's failure result must carry it.
- **Answer.** The library's representation decides the engine's yield on
  the owner's killer case: for the owner (§6, question 4).

## 5. Ranked by how much each could change the design

| rank | question | what it could change | state |
| --- | --- | --- | --- |
| 1 | U13 effects inside the graph | extraction's algorithm (greedy or NP-complete), every function's cost | owner |
| 2 | U9 variadic ops, per-program kinds | whether rules print as per-kind kernels at all; how much of `speed.md`'s factor survives | open, coordinator |
| 3 | U25 closures and defunctionalization | what the engine can do for the killer case; saturation's share of it | settled by reading |
| 4 | U27 alternation blow-up | a dispatch node in the representation, not a budget | measured; direction settled |
| 5 | U10 types of new nodes | the engine holds its own index terms | coordinator, for owner review |
| 6 | U17 budget against the host's memory | the budget's unit; a rule of AGENTS.md against another | owner |
| 7 | U1 and U2 crashes | the floating class and every deletion condition | measured; meaning to owner |
| 8 | U28 the buffer's reads | the engine's yield on parsers | owner |
| 9 | U11 binders | whether region terms fit the sparse engine | open |
| 10 | U12 per-scope extraction | extraction's size and shape | open |
| 11 | U3 and U4 wrong rules | the soundness search and the debugging path | measured; settled in direction |
| 12 | U15 runs per function | the compile-time estimate (×4 to 8) | settled by reading |
| 13 | U8 identity-bearing nodes | a type in the rule language | measured; settled |
| 14 | U24 peak memory | a promise, possibly a cost term | owner |
| 15 | U18 stock-host speed | the library's array representation | measured |
| 16 | U23 cost against counting | trust in extraction | open |
| 17 | U5, U6, U7 determinism, stability, monotonicity | tie-breaking by content; parallelism inside one graph | U5 measured; U6, U7 open |
| 18 | U26 parser laws | where parser rules come from | measured; settled |
| 19 | U14, U16, U19, U20, U21, U22 | none of the design; each a check or a record | settled |

**Settled here:** U1 (fact), U2, U5 (for a serial engine), U8, U14, U15,
U16, U19, U20, U21, U22, U25, U26, U27 (direction), U3 and U4
(direction), U18 (per operation).
**Open:** U6, U7, U9, U10, U11, U12, U23.

## 6. For the owner, one at a time

Each waits for the one before it to be settled.

1. **Does D85's full form put effectful ops inside the e-graph?** Inside:
   eggcc's form, effect-safe extraction NP-complete to find, statewalk
   widths multiplied by our several ordering resources; it buys heap reads
   moved across crashes and loops (E11). Outside: `egraph.md`'s skeleton,
   greedy linear extraction; it gives up E11. Who pays: compile time and
   the extractor's complexity, against E11's run-time gains (U13).
2. **When `B × ops(f)` nodes would exceed the host's memory, which rule
   wins?** Identical output on every machine (the compiler ends with a
   named out-of-memory on a small host, so acceptance depends on the
   machine), or never running out (the budget read from the host, so output
   depends on the machine). A constant cap chosen for the smallest host is
   the round constant AGENTS.md forbids (U17).
3. **May an unused call of a `total` function that can crash be
   deleted?** Idris reports `div x 0` total and it crashes (U1). Reading
   AGENTS.md's "a function proved `total` ... may be deleted when unused"
   literally deletes the crash; reading "a crash happens where evaluation
   reaches it" keeps it. Recommended: deletion requires the derived row to
   carry neither `crash` nor `divergence`. Costs: fewer deletions in total
   code that divides; buys: the crash eager evaluation promises.
4. **Is a linear parser's input a quantity-1 handle to immutable bytes, or
   a mutable buffer?** Immutable: peeks float and fuse across `<|>`, and
   only the release is ordered. Mutable: every read is ordered, and the
   e-graph sees almost nothing of a parser. Who pays: the library's users,
   who cannot write into the input of the first (U28).
5. **May an optimization raise a program's peak memory?** If not, sharing
   and hoisting need a lifetime term in the cost and some merges are
   refused; if so, users meet space growth that the source does not show
   (U24).

## 7. Sources

- Ours: `AGENTS.md`; `.claude/skills/{representation-first,testing-by-search}/SKILL.md`;
  `proposals/0000-mlir-native.md` (D13, D19 to D21, D24, D27, D30, D33,
  D41, D48, D57, D58, D63, D65, D69, D84 to D90);
  `audits/p0/design/egraph.md` (whole); `egraph-full/{one-engine,sparse-mlir,sparse-library,speed}.md`;
  `audits/p0/design/lifetimes/{static-handles,lowering}.md` (the lines
  cited); `foreign/idr/include/idr/IR/*.td` (counts);
  `third_party/Idris2/libs/{prelude/Builtin.idr,prelude/Prelude/Num.idr,base/Data/IOArray.idr,base/Data/IOArray/Prims.idr}`.
- MLIR at the pin: `docs/PassManagement.md:22-40`,
  `include/mlir/Transforms/Passes.td:325-335`,
  `include/mlir/Dialect/Arith/IR/ArithOps.td` (the `Commutative` list).
- Papers in the tree: `sources/papers/wu-2026-slotted-egraphs/appendix_eval.tex:47-48`.
- Web (2026-10-21): eqsat, Merckx et al., [arXiv 2505.09363](https://arxiv.org/pdf/2505.09363);
  "E-Graphs as a Persistent Compiler Abstraction", [arXiv 2602.16707](https://www.alphaxiv.org/abs/2602.16707);
  DialEgg, [github.com/AzizZayed/DialEgg](https://github.com/AzizZayed/DialEgg);
  E-Path, [arXiv 2605.28694](https://arxiv.org/abs/2605.28694);
  HEC, [arXiv 2506.02290](https://par.nsf.gov/servlets/purl/10710641);
  searches of llvm-project pull requests and the LLVM Discourse found no
  e-graph work.
- Scaffolding, not committed, all under `/tmp/eg-unknowns/`:
  `idris/{Tot,Tot2,Tot3,Tot4,Stock,StockP}.idr`; `c/{stock,floatlaw}.c`;
  `toy/{eg,t1_unsound,t2}.py` and their outputs `t1.out`, `t2.out`;
  `egg/` (egg with explanations, against egg 73975c98 by path);
  `parser/{gen,gen_noswap,peg}.py`, the generated `.egg` files, `j1.txt`,
  `j8.txt`; `mlir/{dbg.mlir,k*.mlir}`.
