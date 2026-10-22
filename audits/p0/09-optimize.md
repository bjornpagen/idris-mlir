<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane 09: optimize (the optimizer, specialization, inlining)

Scope: `foreign/idr/lib/Transforms/Optimize/`, `lib/Transforms/Specialize/`,
`lib/Transforms/Inline/`, `lib/Analysis/Inline.cpp`, and their headers.

Status: complete (2026-10-21). Everything here is read from source; nothing was built or run.

## 1. Reading notes

Each note: the proposal's section and finding ID, what it says (as the
proposal marks it), and why it bears on optimize. *read* unless marked.

**The skill and AGENTS.md.**
- Skill, "Map onto MLIR's grain": one op per semantics; shared shape is
  an interface; declare, don't write; use the `AnalysisManager`,
  `SymbolTable`/`SymbolUserMap`, `PassInstrumentation` and `Passes.td`.
  A switch on a tag is a polymorphism not yet named; a check whose
  result is thrown away is a validator; a string that names a thing is
  a missing type. Every handoff line names the state made
  unrepresentable, the check moved to a boundary, or the branch deleted.
- AGENTS.md: inlining, specialization, constant propagation "terminate
  by construction (a fixed sequence, a bottom-up order) and may stop at
  a budget; a spent budget leaves the program less optimized and never
  rejects it. A round count, a fixpoint that has to be reached ... is
  never a reason to refuse." Acceptance is a property of the program,
  never of the optimizer. No pass may drop multiplicities; quantity 1 is
  `!idr.lin<T>`; no proved fact in a discardable attribute. Megamorphic
  constructs are refused by the frontend, never compiled to a uniform
  boxed form: so after the frontend every site's set is finite, and
  specialization's job is to compile it away, not to decide acceptance.

**§2, §3 (the brief and the walls).**
- §2: the pipeline runs `contify, optimize (inline and specialize, each
  function once, bottom-up), symbol DCE, columns, canonicalize and CSE`;
  `Optimize`'s demand is listed among "analyses that live inside
  passes"; `lib/Analysis/Inline` among our analyses.
- §3 rows that are ours: 3a96c407 and 7987388b, "`idr-optimize`: 75
  million pattern attempts ... patterns matching any op"; 98c6315c,
  "`idr-optimize`: threads queued on the context's write lock ... a
  mutable type's facts read under the context's lock"; 16005000,
  "upstream `remove-dead-values`: 52 GB" (the drop that moved "what no
  caller reads" into specialization).

**§5.1 mlir-analysis.**
- E1: `CallGraph` costs 150-700 B per function; `eraseNode` is O(nodes);
  the upstream inliner is the one client of bottom-up SCC order and
  parallelizes only inside one SCC (`Inliner.cpp:517-560`): serial on a
  call graph of singleton SCCs.
- E2: `SymbolUserMap` is a 64-bucket `SetVector` per used symbol.
- F1: the threading contract: whole-program facts in a module-level
  analysis, read through `getCachedParentAnalysis` by nested function
  passes; child maps created serially before the parallel loop.
- F3: a mutable type's mutation takes a shard's writer lock; reads of
  its mutable part are not synchronized; anything that creates
  attributes on a hot path grows the context and takes its locks.
- 5.1.2 item 4 and QA3: `remove-dead-values` split in two (per-function
  upstream; a bit per parameter and result over the call graph, ours).
  Item 7: a wavefront over the SCC DAG is the solver layer's.
- Design 1: a module-level summary analysis solved over SCCs bottom-up
  "iterated inside a recursive SCC up to a budget that only leaves facts
  less precise".
- W6: is every per-function pass anchored on functions?

**§5.2 mlir-ods.**
- E1: an any-op (`MatchAnyOpTypeTag`) pattern is merged into every op's
  list; the 75 million attempts of 3a96c407 "are what the any-op list
  does by design". E2: the greedy driver re-walks, re-queues ancestors
  (patch 62), simplifies regions; non-convergence returns `failure()`
  which must not become a rejection. E3: the walk driver, one
  post-order walk, terminates by construction, "AGENTS.md's shape for an
  optimization".
- M6: "`idr-optimize`'s 'each function once, bottom-up' is a fixed order
  over the call graph; within one function, a one-shot rewrite is the
  walk driver's contract, not the greedy driver's fixpoint."
- M10, W6: 98c6315c's lock "came from a uniquing or mutating call on a
  read path (wave 2 checks)"; is the body complete before threads read
  it? D2: mutable types are text in bytecode and cannot be mutated in a
  transient scope.
- Design 2 "Rooted rewriting": "one-shot rewrites (inline and specialize
  bottom-up, lowering to runtime calls) on the walk driver".
- W2: every `MatchAnyOpTypeTag` pattern and the ops it really matches.
  W9: do passes that change nothing mark all analyses preserved?

**§5.3 llvm.**
- B5/I5: a hot callback is a template, a cold one `function_ref`.
- B7/I7: per-node state in a vector indexed by a dense number; a
  `DenseMap`/`DenseSet` allocates 64 buckets on first insert.
- B8/M4: `lib/Support/Scc.cpp` is "by its name, a hand-rolled
  `scc_iterator`".
- C1: the Attributor's budget forces the pessimistic state: precision,
  never soundness. C2: IPSCCP's function specialization "runs over the
  solved state, bounded".
- D1: `llvm::parallelFor` inside an MLIR pass is a second pool beside
  the context's; `mlir::parallelForEach` is the one to use.
- M8: whole-program solves level by level over the condensation with
  `mlir::parallelForEach`, each SCC writing only its own nodes; 98c6315c
  is "a fact kept in a uniqued mutable type rather than in frozen
  analysis data".
- M9, Q-llvm-2: analyses a refusal rests on: no budget; optimization
  analyses may stop at one and take the pessimistic state; never an
  error.
- S1: one graph, one state vector, templates; giant SCC (Q-llvm-7).

**§5.4 modular (read most carefully).**
- F3: `CallGraphBase`/`SCCGraph` (CRTP; SCCs by `scc_begin`, a
  dependency count per SCC, fork-join from leaves, `doAnalysis` iterated
  within an SCC, `doRewrite` bottom-up). F4: the deduplicator's
  callee-first order makes one pass transitive.
- F8 `AutomaticInline.cpp:104-500`: bottom-up inlining over
  `CallGraphBase`, each caller waiting on its callees' chains, an inner
  function pipeline run on each function once its callees are done
  (`completeFunctionProcessing`) from a per-thread `PassManager`,
  callees in the caller's SCC never inlined, cost model `numOps <
  threshold`. This is our `idr-optimize`'s shape almost exactly.
- F10, F15: shared state named by type (`Shared<T>`, `ThreadLocalCache`,
  immutable-after-construction, per-worker cache merged at the end).
- F11, F22: the elaborator is demand-driven from roots, keyed by an
  interned `(ParameterExprArrayAttr, GeneratorOpInterface)`, suspension
  instead of recursion, deduplicated after, shrinks generators before
  instantiating ("fewer, smaller, simpler generators are faster to
  instantiate"); its parametric inliner works from the leaves because
  inlining from the roots "splats callgraph into a tree".
- F23: Mojo's limits degrade except an opt-in depth cap; the parametric
  inliner caps at 5,000 ops and does not iterate cycles.
- F24: Mojo erases origins and traits before monomorphizing; we must
  not (grades survive specialization).
- 5.4.2 item 2: our `optimize`'s bottom-up inline-and-specialize is "a
  summary per function, callees first", a candidate client of one
  schedule. Item 8: "Mojo's elaborator is our specializer's closest
  relative"; our rules forbid its one refusing limit and keep the rest.
- Design 1 deletes "`optimize`'s own bottom-up scheduling"; Design 5:
  instances keyed by interned arguments, cached in two tiers, facts read
  by many threads in immutable attributes: "98c6315c unrepresentable";
  "wave 2 decides whether our specializer should also become
  demand-driven from roots with suspension (Mojo's elaborator) or stay
  'each function once, bottom-up'".
- Q-M5 (the owner's): specializer shape. Wave-2 items: which analyses
  are summaries and do they compute their own SCC order (`Inline`,
  `optimize`); every fact read from `!idr.data` by many threads; every
  option selecting between two implementations.

**§5.5 cxx26.**
- D1: dispatch once where the set is open (MLIR interfaces, traits,
  rooted patterns), then typed code; never a concept or `isa` that lists
  ops. D2: closed sums of our own types through one exhaustive `match`;
  `holds_alternative`/`get_if` outside `match` are validators. D3:
  solver templates instantiated once with `extern template`. Finding
  13: a template callback costs 2-3x a `function_ref` to compile.
- Wave-2 items: every `function_ref`, `std::variant`, `holds_alternative`.

**§5.6 ecosystem.**
- C3, D2: IREE turns DFX's spent budget and a fixed-point pipeline's
  round count into errors: exactly what AGENTS.md forbids.
- A4, H3, item 2: one call graph (CIRCT's `InstanceGraph`), cached and
  kept up to date by the passes that change calls (optimize among them),
  preserved by name. Design 1's `ProgramGraph` with `replaceCall`.
- Item 5, Q-E3: a budget degrades a site, never fails a pass.
- W-E1: which analyses derive call-graph or SCC facts on their own
  (`Inline`, optimize's bottom-up order); which passes change calls
  without telling anyone. W-E3: analyses computed by more than one
  pass. W-E4: facts in discardable attributes. W-E5: every budget and
  whether it fails. W-E7: per-function `DenseMap<Value, ...>` state.

**§5.7 library.**
- M5, L5 "Clones as keys": specialization, frames and grade contexts
  first compute the set of keys each function needs (interned, equal keys
  one id), then materialize each distinct key once; termination from
  keys drawn from a finite alphabet (Mitchell, H1), "so a budget only
  ever limits profitability". Made unrepresentable: two clones of one
  key; a termination argument resting on a count.
- H4: GCC's virtual clones (bodiless call-graph nodes describing how to
  derive a body) so later analyses compose over decisions.
- M6, L3: build, then freeze; 98c6315c is a mutable nominal type read
  while it may change.
- M11, L6: a pattern matching any op is a full scan; analyses kept
  current across rewrites by listener deltas.
- Wave-2 items: for each specializer, what its key is, whether keys come
  from a finite alphabet, whether any budget decides termination; which
  patterns are not rooted; where a parallel pass reads a mutable type.

**§5.8 dialect-design.**
- B9: a function pass may not inspect siblings; a type whose body lives
  in a sibling declaration cannot be read by a parallel function pass.
- T6, DS2.1, DD-Q7: conventions and effects in the function type, or an
  inherent property of the call checked by `verifySymbolUses`, or an
  analysis.
- DS3: `!idr.data` options (immutable table on the `program` op indexed
  by position; identified types mutated once; structural de Bruijn).
- DS4: `closure`, `apply` legal only before defunctionalization
  (`ConversionTarget`); `func`, `call`, `return` possibly `func.*`.

**§5.9 mlton (read most carefully).**
- A2, A4: each IR's optimizer is a list of records with the ordering
  reasons as data; each pass establishes or states its precondition.
- B2, G2.1: per-node state is a property created and destroyed by the
  pass; "state lives on the node, typed, and dies with the pass".
- D1: `Monomorphise` is one pass with no worklist: a cache per
  polymorphic binding from type-argument vectors to instances, thunks
  forced in reverse so a body is monomorphised after all its uses have
  requested instances; cost linear in the output; termination by the
  program's scoping.
- E2, E3: the shrinker (two linear sweeps per function, label meanings,
  known-case, backward dead-code) is the normal form, called by 19
  passes on each function they rewrote; no pattern driver anywhere.
- F1 *Inline*: the decision is a pure function of the call graph,
  computed once before any rewrite; SCCs leaves-first; a function in a
  singleton SCC that does not call itself is inlined iff
  `(numCalls - 1) * (size - small) <= product`, where `size` already
  counts the inlined size of callees decided earlier; `small = 60,
  product = 320`; `sizeMax` stops counting at the budget; recursive
  functions never inlined; the budget only leaves code uninlined; each
  function shrunk once after.
- F2 *RemoveUnused*: one demand-driven traversal over two-point cells
  (used per variable/label/function/tycon, coned/deconed per
  constructor, may-return/raise per function): liveness, reachability,
  dead constructors, fields, arguments, returns, in one linear analysis.
  This is the MLton counterpart of what 16005000 moved into our
  specialization ("what no caller reads").
- F5 *Polyvariance*: duplicates a let-bound higher-order function at each
  reference when `(numOccurrences - 1) * (size - small) <= product`
  (`small = 30, product = 300, rounds = 2`), before the flow analysis,
  so 0CFA sees separate copies.
- G2.7: facts written into the IR's types; every analysis recomputed by
  the pass that needs it, affordable because each is linear. G2.9:
  immutable functions with a lazy cached CFG.
- H table: 3a96c407/7987388b have no counterpart (no pattern driver);
  98c6315c: facts never inside the type.
- M7 "The optimizer's driver": one linear per-function normalizer; M8
  "The inliner is already MLton-shaped": what MLton adds is the decision
  computed in full before any rewrite, sizes counting already-inlined
  callees, an early-exit size count, recursive functions never inlined.
  M9 "Specialization against the flow analysis": MLton duplicates before
  closure analysis; we specialize after defunctionalization.
- Design 5: one linear normalizer run by each pass over what it changed
  (folders, known-constructor fold, `walkAndApplyPatterns` rooted at
  named ops, `simplifyRegions`); deletes "any-op patterns in
  `idr-optimize`". Design 7: specialize higher-order functions before
  the label solve. Design 1: deletes per-analysis worklists.
- Q-O4 (owner): the order of specialization against the flow analysis.
  Wave 2: Q-W5 (is `optimize`'s specialization polyvariance; what does
  it recover that the label solve merged); Q-W9 (which `idr-optimize`
  patterns are rooted at any op, and which are folds, known-constructor
  folds, or block simplifications upstream already does).

**§5.10 rc.**
- R2 and rc-Q2: grade as one more specialization key in `idr-optimize`
  (Lobster specializes per ownership in call-graph order, E1); the order
  problem: grades would have to be known at `idr-optimize`, which runs
  before counting.

**§5.11 oom.**
- C4: GHC's simplifier budget is deterministic (ticks in program units)
  but rejects the program; ours must have the measure without the
  consequence. C7: budgets in program units, never bytes or seconds, for
  determinism (stage 2 = stage 3). A4: "inlining, specialization and
  every optional pass may stop at a count of ops, rewrites or clones".
  oom-2 (owner).

**§6-§9.** No decisions bear on optimize beyond D2 (own solvers allowed,
honest) and D4 (no code). Owner questions this lane gives evidence for:
Q-M5, Q-O4, QA3, Q-llvm-2, Q-E3, oom-2 (and, adjacent, rc-Q2, Q-M1,
Q-E1, Q-llvm-7, ods-Q6, QL4).

**proposals/0003-facts-once.md, the items that are this lane's** (*read*):
"`givesBack` solved twice: idr-optimize's summaries go at the pass's end
and `Tail/Returned.cpp` solves it again"; "The optimizer rescans each wave
(`Waves.cpp` `enable`) and restamps every call's effects each round
(`Component.cpp` `writeCallEffects`)"; "A consumer form cloned per request
though interned, and named by printing after hashing already decided it
(`Consumer.cpp`)"; "A raise node's consumer (`Specialize/Consumer.cpp`,
`Raise.cpp`) is built at `UnknownLoc`, then every pushed op is overwritten
with the callee's return"; "the optimizer matching inner statistics by
name strings (`Optimize/Component.cpp`)"; "B7, an instance's identity
printed for C++ ... C++ keys specialization nodes by the string";
"`SpecKeyAttr`'s `origin` means the owner while `Node::origin` means the
program's function"; "`Effects.cpp` preserves only `SymbolTable` ... so
Contify rebuilds `CallCycles`". Each is checked against the code in §4.

## 2. What the subsystem is

### 2.1 Files and sizes (*measured*)

Command: `wc -l` over each file, from `foreign/idr`.

| file | lines | what it is |
| --- | ---: | --- |
| `include/idr/Analysis/Inline.h` | 64 | MLton's rule: `kLeafSize` 40, `kSmall` 60, `kProduct` 320, `kCallerCap` 10,000; `Facts{size, inlines}` |
| `lib/Analysis/Inline.cpp` | 34 | `inlineSize` (a walk), `factsOf` |
| `include/idr/Transforms/Inline.h` | 36 | `inlineCalls(FuncOp, function_ref<Callee(StringAttr)>)` |
| `lib/Transforms/Inline/Inline.cpp` | 168 | the inline step; beta reduction of a sibling (`dispatched`, `callsOnlyBeside`, `betaReduces`) |
| `include/idr/Transforms/Optimize.h` | 275 | `Solved`, `Summary`, `Callee` (Final/Sibling/Pending), `Node`, `Scc`, `ReadySet`, `InnerCounts`, `InnerRun` |
| `include/idr/Transforms/OptimizeScheduler.h` | 170 | `NodeAction`, `Finished`, `Analyses`, `Turn`, `Step`, `Scheduler` |
| `lib/Transforms/Optimize/Optimize.cpp` | 120 | the pass, the inner pipeline |
| `lib/Transforms/Optimize/ReadySet.cpp` | 133 | the ready set's build and its reader queries |
| `lib/Transforms/Optimize/Component.cpp` | 278 | one component's turn, on a worker |
| `lib/Transforms/Optimize/Waves.cpp` | 355 | the waves and what is settled between them |
| `lib/Transforms/Optimize/Contify.cpp` | 137 | idr-contify (its design is lane 10's) |
| `include/idr/Transforms/Specialize.h` | 400 | keys, node phases, `Schedule`, `Nodes`, `Forms`, `Order`, and every helper |
| `include/idr/Transforms/SpecializeState.h` | 66 | `Requester`, `Nodes::State` |
| `lib/Transforms/Specialize/Specialize.cpp` | 135 | node phases: claim, build, insert, ready |
| `lib/Transforms/Specialize/Requests.cpp` | 324 | requests, the termination rule, the redirect walk |
| `lib/Transforms/Specialize/Keys.cpp` | 246 | composing keys; `closuresFixed`, `sharesClosure`, `appliesBuiltClosures` |
| `lib/Transforms/Specialize/Order.cpp` | 226 | the homeomorphic embedding, lifting |
| `lib/Transforms/Specialize/Patterns.cpp` | 163 | `shapeOf`, `rebuild`, hole counting |
| `lib/Transforms/Specialize/Consumer.cpp` | 201 | raising: `consumerOf`, `Forms`, `decide` |
| `lib/Transforms/Specialize/Raise.cpp` | 132 | a raise node's body |
| `lib/Transforms/Specialize/Specialization.cpp` | 72 | a spec node's body |
| `lib/Transforms/Specialize/Redirect.cpp` | 83 | calling a node |
| `lib/Transforms/Specialize/RedirectPass.cpp` | 48 | idr-redirect, an inner step |
| `lib/Transforms/Specialize/Report.cpp` | 42 | idr-binding-times, a remark pass |
| **total** | **3,908** | 2,897 in `.cpp`, 1,011 in headers |

Coupled to it and read for this audit, but owned elsewhere:
`lib/Transforms/Identity/Identity.cpp` (95) and
`lib/Transforms/Effects/Constants.cpp` (209), the two other inner steps,
which take the `ReadySet` at construction; `include/idr/Transforms/InnerPasses.td`
(73); `Passes.td:207-304` (the three pass records); `Analysis/{CallCycles,
BindingTimes,Identities,Constants,Effects}.h` (lane 05);
`lib/IR/Func/Func.cpp:189-230` (`bodyEffect`, `componentEffects`,
`writeEffects`); `compiler/src/IdrisMLIR/Emit/Declarations.idr:52-57` (the
one writer of `no_inline`).

Token counts over the 3,908 lines (*measured*:
`grep -rn -- TOKEN <the files above> | wc -l`, run with bash):

| token | count | token | count |
| --- | ---: | --- | ---: |
| `isa<` | 20 | `std::variant<` | 8 |
| `dyn_cast<` | 23 | `std::visit` | 15 |
| `isa_and_nonnull<` | 2 | `std::get_if` | 13 |
| `function_ref<` | 4 | `std::holds_alternative` | 9 |
| `std::function<` | 1 | `std::get<` (unchecked) | 8 |
| `DenseMap<` | 9 | `std::mutex` | 6 |
| `DenseSet<` / `SetVector<` / `MapVector<` | 2 / 2 / 1 | `lock_guard` | 15 |
| `OnceWorklist` | 10 | `virtual` | 5 |
| `.walk(` / `.walk<` | 7 / 2 | `template <` | 0 |
| `std::optional<` | 65 | `internal error` | 9 |
| `parallelFor` / `failableParallelForEach` | 1 / 1 | `MatchAnyOpTypeTag` | 0 |

### 2.2 What it is, as a design (*read*)

idr-optimize is one pass on `idr.program` (`Passes.td:236-237`, stage
First to First) because inlining reads a sibling function, which a nested
pass may not (`Optimize.cpp:6-14`). It runs its own scheduler:

1. **The ready set** (`ReadySet.cpp:27-75`): one `Node` per function the
   program holds, grouped into `Scc`s taken from `CallCycles` (upstream's
   `CallGraph` walked with `scc_iterator`, `CallCycles.h:1-20`), with each
   body walked again in parallel to count call sites and link components
   (`ReadySet.cpp:34-74`).
2. **Waves** (`Waves.cpp:323-353`): every queued step (a member's start or
   resume) runs as one component's turn, in parallel
   (`failableParallelForEach`, `:337`), or serially when the context has an
   action handler (`:334-335`). Between waves, on the pass thread
   (`settle`, `:297-321`): made nodes are inserted into the program in name
   order, finished components publish their summaries (`finalize`,
   `:283-295`), parked requests become waits or merge components
   (`want`, `:181-192`), and `enable` rescans every component for the next
   wave (`:59-84`).
3. **A turn** (`Component.cpp:252-276`): the members it takes up get what
   they give back and their binding times (`takeUp`, `:230-250`); each
   member runs rounds (`runMember`, `:176-206`): an inline step
   (`Inline.cpp:116-168`, MLton's rule under a caller cap of 10,000 ops)
   and the inner pipeline (`Optimize.cpp:51-74`: idr-identity,
   canonicalize, cse, idr-redirect, idr-constants), once more per batch of
   specialization nodes its redirect step was given, parking the member
   when a node of the batch is not final; then one fixed last inline step
   (`:191-204`). When every member is done, the component's summaries are
   read off its final bodies (`finish`, `:212-222`).
4. **Specialization** (`Specialize/`): idr-redirect walks a function's
   calls (`Requests.cpp:256-322`); each call of a final callee is decided
   once (`Consumer.cpp:152-188`): a raise key (callee + the consumer form
   of its one-use dispatch, `Consumer.cpp:43-65`), else a spec key (owner +
   one pattern per parameter at fixed binding times, `Keys.cpp:198-244`);
   a call of a sibling that passes closures built for it alone gets a spec
   key over them (`Requests.cpp:279-281`). A request is judged against the
   keys its requester was given and its request chain: refused if it
   grows one (homeomorphic embedding, `Order.cpp:131-164`), lifted where
   it differs in scalars (`Order.cpp:217-224`), which terminates by
   Kruskal's theorem (`Requests.cpp:27-40`). The first request makes the
   node, named from the key's canonical hash (`Requests.cpp:133-158`); one
   worker claims and builds it detached (`Specialize.cpp:77-108`); it is
   placed between waves.

### 2.3 Every fact it holds or derives (*read*)

| fact | where it lives | computed | read by | dies |
| --- | --- | --- | --- | --- |
| call sites per function | `Node::Held::calls` (`Optimize.h:105-107`) | `ReadySet.cpp:39-42`, at run start | `factsOf` | run end |
| call graph and components | `CallCycles` (lane 05) and again `Scc::callers`, `unfinishedCallees` | `ReadySet.cpp:44-74` | `enable`, `finalize` | run end |
| binding time per parameter | `Solved::times`, then `Summary::times` | `bindingTimesOf` at `takeUp` (`Component.cpp:245`) | `seenBy`, `composeKey` | run end |
| the argument a function gives back | `Solved::givesBack`, `Summary::givesBack` | `identities::givesBackOf` (`Component.cpp:238-239`) | idr-identity | run end (re-solved by idr-returned-arguments, 0003) |
| effects of a component | `Summary::effects`, `FuncOp`'s and every `CallOp`'s `effects` property | `componentEffects` (`Component.cpp:215`) | canonicalize, cse, the program verifier, `consumerOf` | kept in IR |
| constants a call returns | `Summary::constants` | `returnedConstants` (`Component.cpp:218`) | idr-constants | run end |
| inline verdict and size | `Summary::facts` | `factsOf` (`Component.cpp:219-220`) | `inlineCalls` | run end |
| "a step of a recursion" | `Node::Made::stepOfRecursion` (`Optimize.h:113`) | `Scheduler::stepOfRecursion` at insert (`Waves.cpp:222-249`) | `finish` | run end |
| "a request passed a shared closure" | `specialize::Node::sharedClosure` (`Specialize.h:109`) | `requestSpec` (`Requests.cpp:221`) | `stepOfRecursion` | run end |
| a node's request chain | `specialize::Node::parents` (`Specialize.h:105`) | `grant` (`Requests.cpp:153-155`) | `chainOf` | run end |
| keys given per requester, by owner | `Requester::given` (`SpecializeState.h:46`) | `Requester::give` | `requestSpec` | run end |
| a key's node | `Nodes::State::byKey`, `byName` | `grant` | redirect, insert | run end |
| a node's name | `ContentNames` from `canonicalHash(key)` | `grant` (`Requests.cpp:139-140`) | the program (symbol) | kept in IR (the key is not) |
| consumer forms | `Forms::byHash`, `byForm` (detached `FuncOp`s) | `Forms::intern` | `buildRaise` | run end |
| sizes of constants | `Order::sizes` (`Specialize.h:329`) | `Order::size` | `atMost` | run end |
| Idris's proof of termination | `FuncOp`'s `total` | cleared by `absorb` (`Inline.cpp:156`, `Contify.cpp:109`) | effects (`bodyEffect`) | kept in IR |
| "a lazy constant whose cell every use shares" | `FuncOp`'s `no_inline` | the frontend (`Declarations.idr:52-57`: `f.arity == 0 && lazyResult f.result`) | `factsOf` (`Inline.cpp:29`) | kept in IR |

### 2.4 Threading (*read*)

- *Pass thread:* the ready set's build (one `parallelFor` over bodies,
  `ReadySet.cpp:35`, on the context's pool), then per wave `gather`,
  `settle` and `enable`. The analysis manager is nested for every function
  before the first wave (`Optimize.cpp:93-94`) and for each made node in
  `insert` (`Waves.cpp:270`), as upstream's inliner does (§5.1 F1).
- *Workers:* one component's turn each; a turn writes only its members'
  bodies and states and reads final functions' bodies (which nothing
  writes again) and its own siblings.
- *Shared mutable state on the workers' path:* `Nodes::State::mutex`, one
  lock for the whole node table, held across `Order::grows`, `chainOf`,
  every lift and the canonical printing of a new key's name
  (`Requests.cpp:174-222`, `:139-140`), and taken per call by `find`
  (`Specialize.cpp:56-59`, from `Requests.cpp:258, 278`) and `seenBy`
  (`Requests.cpp:243-247`); `Forms::mutex`, held across
  `deduplicate::sameFunction` (`Consumer.cpp:123-133`); `pipelinesMutex`
  per inner run (`Component.cpp:86-97`); and the `MLIRContext`'s uniquer,
  whose sharded writer locks every attribute a worker creates takes
  (§5.1 F3): every key pattern (`KeyConAttr::get`, `ArrayAttr::get`,
  `SpecKeyAttr::get`, `Keys.cpp:85-90, 242`; `Order.cpp:94-109, 223`), every
  name (`FlatSymbolRefAttr::get`, `Requests.cpp:146`; `StringAttr::get`,
  `Consumer.cpp:136`), every `FunctionType` (`Consumer.cpp:100`,
  `Raise.cpp:122-123`), and the `CallSiteLoc` upstream's `inlineCall`
  makes per distinct location it inlines (`InliningUtils.cpp:55-80` at the
  pin). None of these attributes is freed before the context dies.
- *98c6315c's lock* is gone from this path: the data type's facts
  (`dataTypeOf`, `isClosures`, `isMemo`, `getCtor`, read at `Keys.cpp:54,
  106-119`, `Patterns.cpp:40`, `Inline.cpp:94-106`) are now fields of a
  type sealed whole before any pass reads it (98c6315c's message), and no
  pass of this subsystem defines a data type (`grep Declarations` over the
  files finds none).
- *Determinism:* turns of one wave touch disjoint components; built nodes
  are inserted by name (`Waves.cpp:305-309`); requests are handed out by
  name (`Specialize.cpp:71-73`). One order leaks (§4, OPT-48).

## 3. Reconciliation with the proposal

### 3.1 The proposal's findings and designs, against the code

| finding or design | verdict | the code that shows it |
| --- | --- | --- |
| §3, 3a96c407 / 7987388b: "`idr-optimize`: 75 million pattern attempts ... patterns matching any op" | holds as history; the state is fixed | `grep -rn MatchAnyOpTypeTag lib include tools` finds nothing (*measured*); the inner canonicalize runs only rooted patterns. What remains of the class is the greedy driver itself, run to its fixpoint once per round per member (`Optimize.cpp:64-66`), lane 04's to replace (§5.2 E2, §5.9 E3). |
| §3, 98c6315c: "threads queued on the context's write lock ... a mutable type's facts read under the context's lock" | holds as history; holds in part as a class | The `mutate`-on-read is gone (98c6315c's message; the facts are fields of a type sealed whole). Still on the workers' path: one mutex over the whole node table held across the embedding checks, lifts and canonical printing (`Requests.cpp:174-222`, `:139-140`), and the context uniquer's shard locks for every key, name, type and `CallSiteLoc` a worker creates (§2.4). §4's "no global lock on a hot path" is not met. |
| §5.1 E1: upstream's inliner is parallel only inside one SCC | holds; it is why the ready set exists | Our scheduler is upstream's inliner shape generalized across SCCs: a pool of pipeline copies (`Component.cpp:83-98` against `Inliner.cpp:520-560` at the pin), every function's analysis manager nested before the parallel loop (`Optimize.cpp:91-94` against `Inliner.cpp:538-541`), SCCs from `scc_iterator` (`CallCycles.h:1-9`). |
| §5.1 F1: whole-program facts in a module-level analysis, read through `getCachedParentAnalysis` | holds in part | The inner steps get the ready set by construction (`InnerPasses.td:45, 58, 70`; `Optimize.cpp:51-74`), not from the analysis manager: the ready set changes between waves, so it cannot be a cached analysis. Their reads are safe by the ready set's discipline (a final function is never written again, `Optimize.h:58-60`). |
| §5.1 F3: attributes created on a hot path grow the context for good and take its locks | holds | §2.4's list; keys are attributes "for MLIR's uniquing ... no op holds one" (`IdrAttrs.td:215-220`), so every key a refused or lifted request built stays in the context. |
| §5.1 item 7: a wavefront over the SCC DAG is the solver layer's to provide | holds; we have one, ad hoc | `Waves.cpp:323-353`. It also grows the graph mid-run (made nodes, `insert`, `Waves.cpp:259-275`) and merges components when waits close a cycle (`Waves.cpp:181-192`), which no static SCC schedule does. |
| §5.2 E3, M6, design 2: one-shot rewrites on the walk driver | holds in part | idr-identity is on `walkAndApplyPatterns` (`Identity.cpp:81`); the inline and redirect steps are one walk over a list taken first (`Inline.cpp:121`, `Requests.cpp:260`); canonicalize is the greedy driver (`Optimize.cpp:64-66`). |
| §5.2 M10, W6: what took 98c6315c's lock | holds, answered | `mutate` on every read of `holdsReferences`/`holdsWorld`, from the flow edges and lifetimes the workers' verifier asks of every value (98c6315c's message). The body is complete before any thread reads it now. |
| §5.3 B7, I7: per-node containers cost 64 buckets each | holds | `Requester` per requesting function holds a `DenseMap` and a `SetVector` (`SpecializeState.h:46-47`); `Order::grows` builds a fresh `DenseMap` per call (`Order.cpp:132`). |
| §5.3 D1: `llvm::parallelFor` inside a pass is a second pool | holds; not violated here | `mlir::parallelFor` (`ReadySet.cpp:35`) and `failableParallelForEach` (`Waves.cpp:337`) run on the context's pool. |
| §5.3 I3, I5; §5.5 D2: one exhaustive match; hot callbacks as templates | holds | `get_if` ladders over `Callee` (`Inline.cpp:135-147`) and `Key` (`Consumer.cpp:163-183`); `function_ref`s whose static type is always the ready set's lookup (`Inline.h:31-32`, `Inline.cpp:62-63, 91-92`). |
| §5.3 / §5.5: `virtual` only where the set is open | refuted here | `specialize::Schedule` (`Specialize.h:121-139`) has one implementation, `ReadySet` (`Optimize.h:216`; `grep` finds no other). |
| §5.4 F8: Mojo's `AutomaticInline` | holds; the code says so | `Optimize.h:9-11`. Differences: waves with a barrier (ours) against per-node async readiness (Mojo); MLton's rule (ours) against `numOps < threshold`; siblings inlined as beta reduction (`Inline.cpp:83-112`) where Mojo never inlines inside an SCC. |
| §5.4 F11, F22, design 5: Mojo's elaborator, instances keyed by interned arguments | holds in part | Our nodes are demand-driven (made by the first request, `Requests.cpp:133-158`), keyed by uniqued attributes, and a requester *suspends* (parks) until its nodes are final (`Component.cpp:162-172`, `Waves.cpp:54-84`): Mojo's suspension. Not Mojo's: we start from every held function, not the root; one lock, no per-worker front. |
| §5.4 item 8: our grades must survive specialization | holds, vacuously | idr-optimize runs at stage First (`Passes.td:236-237`), before idr-rc writes grades (`Pipeline.cpp:41-49` after `:82`); keys hold constructors and constants only (`Keys.cpp:58-63`, `Patterns.cpp:55-74`). |
| §5.4 design 1: one call-graph schedule deletes "`optimize`'s own bottom-up scheduling" | holds in part | The static part (components callees first, a count of unfinished callees per component, `Optimize.h:200-213`) is `SCCGraph`'s. The dynamic part (nodes added mid-run, waits, merges) is ours alone; the schedule must offer it or the ready set stays a client with an extension. |
| §5.6 A4, item 2: one call graph, maintained, preserved by name | refuted today | `CallCycles` is built three times in a row: idr-effects (`Effects.cpp:31`, preserves only `SymbolTable`, `:39`), idr-contify (`Contify.cpp:128`, preserves `SymbolTable`, `TypeGraph`, `Layouts`, `:133`), idr-optimize (`Optimize.cpp:85`); and the ready set walks every body a fourth time for its edges (`ReadySet.cpp:34-74`). Contify says no function changes cycle (`Contify.cpp:29-32`), so its `CallCycles` could be kept up to date. |
| §5.6 item 3: summaries in a typed table, never in attributes | holds, with one cache | `Summary` on the node (`Optimize.h:55-67`). Effects also go into the IR as inherent properties of every function and call (`Waves.cpp:285`, `Component.cpp:73-81`; `IdrOps.td:143-151, 216-220`): not discardable, but a copy of the callee's summary on each call (§5.8 DS2.1's "cache with one source"). |
| §5.6 item 5, Q-E3: a budget degrades, never fails | holds | §6, Q-E3. |
| §5.7 L5: clones as keys, from a finite alphabet | holds in part | Keys are computed first and each distinct key is materialized once (`byKey`, `Requests.cpp:136-151`), named from its content. The alphabet is not finite (keys hold scalars, strings, bigs, runs); lifting (`Order.cpp:79-112`) turns a differing scalar into a hole, and the embedding is a well-quasi-order over shapes (`Requests.cpp:27-40`): termination by construction, no count. |
| §5.7 L3: build, then freeze | holds for the data table, not for the node table | The node table is mutated under one lock for the whole run (`SpecializeState.h:50-62`). |
| §5.8 B9: a function pass may not read siblings | holds; it is idr-optimize's reason to be a program pass | `Optimize.cpp:6-9`. |
| §5.9 F1, M8: "the inliner is already MLton-shaped" | holds in part | Same rule and numbers (`Analysis/Inline.h:21-25`; MLton's `small = 60, product = 320`), the leaf size 40 (MLton's `inlineLeafB` size, *recalled*). Not MLton's: the verdict is taken per callee when its component finishes (`Component.cpp:219-220`), not once for the program before any rewrite; a made node counts 1 call however many requesters call it (`Optimize.h:177-181`); a caller cap (`kCallerCap`); recursive code is inlined as beta reduction (`Inline.cpp:83-112`) and as made nodes whose keys fix closures alone (`Waves.cpp:222-249`), each case added after an unrolling blow-up (7232d3e9, f0a42001, ed9b2a0b, d69ae5d6). |
| §5.9 F2: RemoveUnused | no counterpart since 16005000 | No pass of the `idr` level erases an unused parameter or result: `grep -rn "eraseArguments\|eraseResults\|eraseResult(" lib` outside `Conversion/` finds only `Specialization.cpp:68` (the parameters a key replaced), `Trmc.cpp:258` and `ReturnedArguments.cpp:126` (*measured*). §6, QA3. |
| §5.9 E3, M7, design 5: one linear normalizer run by each pass over what it changed | holds in shape, not in cost | Each rewrite (inline, redirect) is followed by the inner pipeline on that function (`Component.cpp:157-160`): MLton's "normal form between passes", but with the greedy fixpoint and an SCCP solve per round instead of a linear shrinker. |
| §5.9 G2.1: state lives with the pass | holds | `ReadySet` and `Nodes` are locals of `runOnProgram` (`Optimize.cpp:85-90`). |
| §5.10 R2, rc-Q2: grade as a specialization key | refuted as the pipeline stands | Grades do not exist yet at idr-optimize (stage First). |
| §5.11 C7, A4: budgets in program units | holds | Ops and call sites only (`Analysis/Inline.h:23-30`), and one fixed step (`Component.cpp:191-204`). |

### 3.2 Wave-2 questions answered, by ID

*§5.1.4.*
- **W1** (V, B, P, F, regions per op at each solve): not measurable
  without a built compiler. What bounds the solves here: idr-constants
  solves one function at a time (`Constants.cpp:188-193`), and inlining
  keeps every function at or under `kCallerCap` = 10,000 ops
  (`Analysis/Inline.h:30`, `Inline.cpp:148-151`; Inline.h:26-29 says this
  bound exists for the per-body passes), except a function that was over
  it before inlining began.
- **W2** (each analysis's lattice): binding times, one two-point value per
  parameter, per component (`BindingTimes.h`); what a function gives back,
  one `optional<unsigned>` per function, a greatest fixpoint per component
  (`InnerPasses.td:36-38`); inline facts, one per function; constants, a
  `Lattice<ConstantValue>` per value per function on upstream's solver
  with `DeadCodeAnalysis` (`Constants.cpp:188-193`, Design 1's shape of
  §5.1 already: summaries through a hook). None is per program point.
- **W3** (`getPredecessors` and kin): none in these files (`grep`). The
  raise build walks a match's regions once per raise (`Raise.cpp:70-75`).
- **W5** (attributes on a hot path): yes; §2.4 lists them. Keys are made
  even for requests that are then refused or lifted (`Keys.cpp:242`
  before `Requests.cpp:201-216`).
- **W6** (passes anchored on functions): idr-optimize must be a program
  pass (B9); its inner pipeline runs per function through `runPipeline`
  under our scheduler (`Component.cpp:94`), not the pass manager's
  adaptor. idr-contify and idr-binding-times are program passes.
- **W7** (backward analyses' callee resolution): none here; idr-constants
  is a forward solve with `setInterprocedural(false)`
  (`Constants.cpp:188`).

*§5.2.4.*
- **W1** (hand `getEffects`): none in these files. The pass writes the
  `effects` property that `CallOp`'s hand `getEffects` reads (lane 02).
- **W2** (`MatchAnyOpTypeTag`): none.
- **W3** (`verify()`): none in these files; two internal-error checks of
  built functions (`Specialization.cpp:27-30`, `Specialize.cpp:89-94`).
- **W4** (`isa` over ops): `Patterns.cpp:28` (`ConstantOp,
  arith::ConstantOp`: "a constant the dialect rebuilds"), `:35` (`ConOp,
  LinEnterOp`: "builds part of a shape"), `Inline.cpp:53` (`LinUseOp,
  LinEnterOp`: a grade-only change, `throughLinear`'s fact),
  `Inline.cpp:51, 71` (`MatchOp` only, where `Raise.cpp:70` asks
  `MatchOpInterface`), `Consumer.cpp:164` (`ReturnOp`). 34 of the 45
  `isa`/`dyn_cast` are over our key attributes, not ops (§4, OPT-60).
- **W6**: answered in 3.1.
- **W9** (passes that change nothing preserve everything): idr-redirect,
  idr-identity and idr-constants do (`RedirectPass.cpp:35-36`,
  `Identity.cpp:83-84`, `Constants.cpp:195-196`); idr-contify does
  (`Contify.cpp:130-131`). idr-optimize preserves `TypeGraph` and
  `Layouts` only (`Optimize.cpp:116`), though it keeps `SymbolTable`
  current itself (`Waves.cpp:269`).

*§5.3.4.*
- **Worklists**: `OnceWorklist` (a `SetVector`, `Worklist.h:67-93`) for
  steps (`Waves.cpp:325`), the component searches (`:128, 152`), the
  request chain (`Requests.cpp:93`), dead shapes (`Patterns.cpp:103`) and
  each requester's queue (`SpecializeState.h:47`). Node identity is a
  pointer. The component searches are graph reachability done again per
  question (OPT-34).
- **`DenseMap`s per node**: `Requester::given` and its `SetVector`, one
  each per requesting function (`SpecializeState.h:46-47`); a fresh
  `Embeddings` per `grows` call (`Order.cpp:132`). The rest are one per
  run.
- **`function_ref`s** (4): three take the ready set's lookup, whose type
  is known (`Inline.h:31-32`, `Inline.cpp:62-63, 91-92`); the fourth is
  `ConstantsOf` (lane 05). One stored `std::function`, `RunPipeline`
  (`OptimizeScheduler.h:101`), because `Pass::runPipeline` is protected.
- **Variants** (8): `Callee`, `Node::Origin`, `Node::State`, `Step`,
  `Key`, `specialize::Node::state`, `Want`, `Source`; each of at most four
  alternatives (a `switch` in libc++). 15 `std::visit` are exhaustive; the
  validators are 13 `get_if`, 9 `holds_alternative` and 8 unchecked
  `std::get` (§4).
- **`Scc.cpp`**: not used here; `CallCycles` is upstream's `CallGraph`
  and `scc_iterator`.
- **Mutexes** (6): §2.4. All parallelism is on the context's pool.
- **`DataFlowSolver`**: idr-constants, per function (S2 already).
- **`switch`**: none in these files.

*§5.4.4.*
- **Summaries over the call graph**: idr-optimize, callees first, with its
  own wave order built on `CallCycles` (`ReadySet.cpp:44-54`) and grown by
  merges; the inline verdict, per function, read by callers.
- **State copied per region or edge**: none here.
- **Predecessors of region successors**: none here.
- **A `getEffects` or `verify` because an attribute changes meaning**: the
  call's `effects` property changes what canonicalize and cse may do with
  the call (lane 02's).
- **Release builds verifying after every pass**: every inner step is run
  through `runPipeline`, which verifies the function after each of its
  five passes, per round (`Optimize.cpp:10-12`).
- **`CallOpInterface`**: `idr.call` implements it already (`IdrOps.td:210`).
- **Facts read from `!idr.data` by many threads**: `Keys.cpp:54, 106-119,
  182`; `Patterns.cpp:40, 146`; `Inline.cpp:94-106`; `Waves.cpp:244`
  (through `closuresFixed`). Lock-free since 98c6315c.
- **An option selecting two implementations**: `hasActionHandler()`
  selects a serial loop or `failableParallelForEach` (`Waves.cpp:334-337`);
  the output is the same by construction, but the two paths are two.

*§5.5.4.* Sorted in W4 above and §4. `virtual`: the closed `Schedule`.
No templates, no CRTP.

*§5.6.4.*
- **W-E1** (call-graph facts derived on their own): `ReadySet.cpp:34-74`
  (edges and call counts by a second walk); `Analysis/Inline.cpp:25-28`
  and `Waves.cpp:228-234` (whether a function calls itself, where
  `CallCycles::callsItself` exists, `CallCycles.h:49-52`, though stale for
  made nodes); `componentEffects` tests membership by symbol lookups
  (`Func.cpp:207-219`) the ready set's `Node::scc` already answers.
  Passes that change calls without telling anyone: idr-optimize and
  idr-contify both; neither updates `CallCycles`.
- **W-E3** (analyses computed by more than one pass): `CallCycles`
  (three, above); effects (idr-effects, then idr-optimize's `finish`);
  what a function gives back (idr-optimize, then idr-returned-arguments,
  0003); binding times (idr-optimize's `takeUp` and idr-binding-times'
  report, `Report.cpp:28-36`).
- **W-E4** (facts in discardable attributes): none; effects are inherent.
- **W-E5** (budgets): §6, Q-E3. None becomes a failure.
- **W-E6** (queries walking a match's regions): `callsOnlyBeside` climbs
  each sibling call's region parents (`Inline.cpp:69-77`); `push` walks
  a match's regions per raise (`Raise.cpp:70-75`). Linear per query.
- **W-E7** (`DenseMap<Value, ...>` per function): none.

*§5.7.4.* Specializer keys: `SpecKeyAttr(origin, patterns)` and
`KeyRaiseAttr(callee, form)`; not a finite alphabet (lifting restores
finiteness per shape); no budget decides termination. No unrooted
pattern.

*§5.8.4.* Ops with a `UnitAttr` that changes what may be done: `idr.func`'s
`no_inline` (a lazy constant whose cell every use shares, derived by the
frontend from the signature) and `total` (cleared by `absorb`).

*§5.9.4.*
- **Q-W5** (is specialization polyvariance; what does it recover): it is
  constructor specialization by offline binding times (`Keys.cpp:7-22`),
  run after defunctionalization, so a closure is a constructor of its
  sum and a key over it recovers, per call site, the one label the label
  solve merged into the sum; raising (`Consumer.cpp:43-65`) moves an
  apply's dispatch into the callee whose tails build the closure. It
  recovers only what is visible as an `idr.con` chain at the call
  (`Patterns.cpp:55-74`): a closure that reaches the call through a
  varying parameter, a field or a match result stays in the merged sum.
  MLton's polyvariance changes what 0CFA sees for every flow; ours
  repairs call sites after it.
- **Q-W8** (contify): no dominator tree; one `SymbolUserMap` and
  `CallCycles`, one sweep in program order, moving only a function of one
  call from a member of its own cycle (`Contify.cpp:80-123`): Fluet and
  Weeks restricted to the case where the one call site dominates.
- **Q-W9** (any-op patterns in idr-optimize): none.

*§5.10.4.* R2 needs grades at idr-optimize; they are written after it.

*§5.11.4.* **W7**: state sized by a product of two program quantities:
`grows` checks a request against every earlier key of its owner given to
the requester and on its chain (`Requests.cpp:184-193`); `reaches` and
`merge` search the component graph per wait (OPT-34, OPT-35); a node per
distinct key, bounded by the well-quasi-order but not by a constant.
**W8**: keys are created per call and held by no IR, the natural
candidates for a transient scope, which the context allows only
single-threaded (§5.1 F3; `MLIRContext.h:149-190` at the pin), so not on
the workers.

## 4. Issues

All *read* unless marked. Paths are relative to `foreign/idr` unless they
start with `compiler/`. "§5" designs are the proposal's; "T-n" are this
document's §5 changes.

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| OPT-01 | `include/idr/Analysis/Inline.h:21-25` | budget | MLton's numbers (`kLeafSize` 40, `kSmall` 60, `kProduct` 320): a verdict of keep leaves a call, never a refusal; counted in ops and call sites, deterministic. | Keep (program units, §5.11 A4); the verdict becomes a sum (OPT-04). |
| OPT-02 | `include/idr/Transforms/Passes.td:239-277` | list | The pass description restates the four numbers and an older termination rule ("a key that embeds a key on its own request chain is not made"; the code refuses a key that *grows* one, judged also against keys given before, and lifts, `Requests.cpp:11-26`) and "the pipeline runs on the function again, up to its size". A prose copy that has drifted. | The description states the property and names the rule's home; the numbers live once, in the header. |
| OPT-03 | `include/idr/Analysis/Inline.h:26-29` | rederivation | "only a callee of one call can build a giant body" is false for made nodes, which count one call each (OPT-12). | Goes with OPT-12. |
| OPT-04 | `include/idr/Analysis/Inline.h:34-39, 52`; `lib/Analysis/Inline.cpp:29` | ladder | The verdict is `bool inlines` from four reasons folded into booleans: `shared`, `callsItself`, `no_inline`, and the caller's `stepOfRecursion` (`Component.cpp:219-220`). | T4: `Verdict = Keep(Reason) \| Leaf \| Weighed \| Beta`, `Reason` a closed enum, decided once from the node's kind and its component. |
| OPT-05 | `lib/Analysis/Inline.cpp:14-18` | rederivation | `inlineSize` walks a body; called by `factsOf` (`:21`), per inline step on the caller (`Inline.cpp:124`), per sibling inlined (`Inline.cpp:144`), on every function for a remark (`Optimize.cpp:109-110`), and by `Expect/Sizes.cpp:25`; the inline step already keeps the size current (`Inline.cpp:158`). | The turn holds the size of its members (walked once at take-up, updated by each inline); `inlineSize` stays for the expect property. |
| OPT-06 | `lib/Analysis/Inline.cpp:21-28` | rederivation | Two walks per verdict (size, then calls); "calls itself" derived again, where `CallCycles::callsItself` answers for a held function (`CallCycles.h:49-52`) and nothing records a made node's self-edge. | The schedule records each node's self-edge when its redirect makes it (T1); the verdict reads the component. |
| OPT-07 | `lib/Analysis/Inline.cpp:29`; `include/idr/IR/IdrOps.td:140-141, 161` | attribute | `no_inline`, a `UnitAttr` the frontend derives from the signature (arity 0, lazy result) and the inliner reads as "keep": a lazy constant whose cell every use shares is not a function. | T4 with OPT-82: its own representation on the Idris side and its own op (the op is lanes 03, 14, 15's); the flag and its branch go. |
| OPT-08 | `include/idr/Transforms/Inline.h:31-32` | cpp | `inlineCalls` takes `function_ref<Callee(StringAttr)>` whose callable is always the ready set's lookup bound to a reader (`Component.cpp:150`): a callback threaded through code that knows its static type (§5.3 M3). | Takes `const ReadySet &` and the reader's node; with T2 the step is an inner pass given both. |
| OPT-09 | `lib/Transforms/Inline/Inline.cpp:49-56` | ladder | `dispatched` recurses through `isa<LinUseOp, LinEnterOp>`, restating the grade-only-change fact `throughLinear` reads (`Idr_SameValue`, 0c98b266), and asks `dyn_cast<MatchOp>` only, where raising asks `MatchOpInterface` (`Raise.cpp:70`). | Read the trait and the interface; goes with OPT-10 if the beta step is one mechanism. |
| OPT-10 | `lib/Transforms/Inline/Inline.cpp:59-112, 140-144`; `lib/Transforms/Specialize/Requests.cpp:279-281`; `Keys.cpp:178-196`; `Consumer.cpp:190-199` | rederivation | Two mechanisms for one transformation, the beta step of a recursion: inline a sibling that is handed a closure built for it alone (d69ae5d6), and redirect such a call to a spec node keyed on those closures (2a02891f), both added 2026-10-19. | T4: one mechanism, the node of kind `Beta`, inlined by the verdict; `betaReduces`, `callsOnlyBeside`, `dispatched` and `Sibling`'s inline arm go (*conjecture* that the node path covers every case the inline path does; a fixture per case decides). |
| OPT-11 | `lib/Transforms/Inline/Inline.cpp:100`; `Keys.cpp:166`; `Keys.cpp:188` | rederivation | Three copies of "a closure built for this call alone" (an `idr.con` through grades, its value and its entry each used once). | One predicate, read once per call; ideally a fact of the value's type (a linear closure, §5.7 L1), which lanes 01 and 15 decide. |
| OPT-12 | `include/idr/Transforms/Optimize.h:177-181`; `include/idr/Analysis/Inline.h:46-48` | budget | A made node counts one call however many requesters call it, so the weighed rule (`(1-1)·(size-60) = 0 ≤ 320`) inlines it into every requester, bounded only by the caller cap. MLton's rule weighs the product of size and calls. | Owner's choice (Q-opt-2): count requesters (known only once every caller has run), or weigh made nodes only as `Leaf` or `Beta`. |
| OPT-13 | `lib/Transforms/Inline/Inline.cpp:133-147` | cpp | A `get_if<Final>` / `get_if<Sibling>` / else ladder over the `Callee` sum (§5.3 I3). | One exhaustive match; with OPT-10 the `Sibling` arm goes. |
| OPT-14 | `lib/Transforms/Inline/Inline.cpp:116-168`; `Component.cpp:73-81, 148-160`; `Waves.cpp:285, 291-292` | state | The inline step and the effect stamps mutate a function outside any pass, between `runPipeline` calls, and nothing invalidates its nested analysis manager; upstream CSE caches `DominanceInfo` and preserves it (`mlir/lib/Transforms/CSE.cpp:37, 51, 56` at the pin), so the next round's CSE reads an analysis of the body before inlining. *Conjecture* on the effect: our regions are single-block, so dominance is answered by op order, and the stale part is per-region entries keyed by `Region *`. | T2: the inline step and the stamps are passes of the inner pipeline, so the pass manager invalidates; no mutation outside a pass. |
| OPT-15 | `Inline.cpp:121`; `Requests.cpp:260`; `Component.cpp:76`; `Waves.cpp:199-200`; `Analysis/Inline.cpp:25` | rederivation | Five walks re-find the same `idr.call`s of one body per round (inline, redirect, effect stamps, a built node's waits, the verdict); §5.3 M12's "walk once". | The turn's view of its member lists its calls once per round (T2), each step reads it. |
| OPT-16 | `include/idr/Analysis/Inline.h:30`; `Inline.cpp:148-151` | budget | `kCallerCap` = 10,000 ops: a call past it stays a call (`++capped`); also what bounds the per-function solves of the inner pipeline (`Inline.h:26-29`). Never fails; in ops. | Keep (§5.11 A4); state in its comment that it bounds the inner solves' memory, the A1 line. |
| OPT-17 | `include/idr/Transforms/Optimize.h:127-130, 150-155, 186-190`; `Component.cpp:169, 266`; `Waves.cpp:286-288` | state | A node's phase is held twice (`state` Waiting/Parked/Done and `published`, whose presence is "final"); `finalize` moves `times` out of the Done state, leaving a representable invalid state; three unchecked `std::get`s assume a phase the type does not carry. | T2: one phase sum `Waiting \| Parked{on, solved} \| Done{solved} \| Final{summary}`; a step that needs a phase takes it. |
| OPT-18 | `include/idr/Transforms/Optimize.h:109-115`; `include/idr/Transforms/Specialize.h:108-109` | ladder | `Made::stepOfRecursion` and `specialize::Node::sharedClosure` are booleans feeding the verdict: a node's kind written as flags. | T4: a node's kind as a sum (`Held \| Spec(key) \| Raise(key) \| Beta(labels)`, a spec node of a recursive origin a `Step`), decided once at grant. |
| OPT-19 | `include/idr/Transforms/Optimize.h:159-163`; `Waves.cpp:190` | state | `waiting()` scans `waitsOn` each time `enable` asks, every wave; `is_contained` on insert. | T1: a count of unmet waits per member, decremented when a target becomes final, as `unfinishedCallees` is. |
| OPT-20 | `include/idr/Transforms/Optimize.h:193, 207-212`; `Waves.cpp:150-176` | upstream | Components merge by repointing every member's `scc` and appending `callers` as member proxies: a hand union-find. | T1: LLVM's `IntEqClasses` (or `EquivalenceClasses`) over component ids. |
| OPT-21 | `include/idr/Transforms/Optimize.h:220-246`; `ReadySet.cpp:81-131`; `Requests.cpp:108-111, 240-252` | list | Every reader question names functions by `StringAttr` (`byName`, `held`, `finalCallee`, `knownCallee(reader, name)`, `sameComponent`, `originOf`): about eight hash lookups and two lock acquisitions per call per redirect. A name used as an identity. | T1: each call's callee resolved once to a node (the graph's edge), dense node ids after that. |
| OPT-22 | `include/idr/Transforms/Specialize.h:119-139`; `Optimize.h:216` | cpp | `specialize::Schedule` is a virtual interface with one implementation (`grep` finds no other): runtime dispatch over a closed set. | Delete; the table takes the ready set (T1). |
| OPT-23 | `Waves.cpp:342-345`; `Optimize.cpp:111-114` | upstream | Remarks report progress and the largest function, but no footprint of the run's state (§5.9 G2.10, design 6; §5.11 A2). | The tables' sizes (nodes, keys, waits) as remark metrics per wave, and the per-pass footprint record if oom-3 says so. |
| OPT-24 | `include/idr/Transforms/OptimizeScheduler.h:101`; `Optimize.cpp:96-98` | cpp | `RunPipeline` is a stored `std::function` because `Pass::runPipeline` is protected. | The scheduler is the pass's member (or the pass's own code); no erased callable. |
| OPT-25 | `include/idr/Transforms/OptimizeScheduler.h:154-158`; `Component.cpp:83-98` | upstream | Copies of the inner pipeline made on demand under a mutex; upstream keeps a fixed pool of `numThreads` with an atomic flag each (`Inliner.cpp:520-560`). | Upstream's shape. |
| OPT-26 | `lib/Transforms/Optimize/Optimize.cpp:64-66` | budget | The inner canonicalize is the greedy driver to its fixpoint, once per round per member, `maxIterations` 10 by default; non-convergence is ignored (`testConvergence` false, `Canonicalizer.cpp:88-91` at the pin). Never fails. | Lane 04's normalizer (§5.9 design 5, §5.2 E3) replaces it; measured on the stage-1 module. |
| OPT-27 | `lib/Transforms/Optimize/Optimize.cpp:107-114` | rederivation | A walk of every function for the "largest" remark metric, run whether or not remarks are on (the walk precedes the `if`). | The size is known per node at finish (OPT-05); read it there, inside the remark. |
| OPT-28 | `lib/Transforms/Optimize/Optimize.cpp:116` | upstream | Preserves only `TypeGraph` and `Layouts`, though it keeps `SymbolTable` current (`Waves.cpp:269`). | Preserve what it maintains (T1: the program graph too). |
| OPT-29 | `lib/Transforms/Optimize/ReadySet.cpp:34-74` | rederivation | A second walk of every body for call counts and component edges, beside `CallCycles`' `CallGraph` built from the same calls (W-E1). | T1: one program graph gives edges, counts and components. |
| OPT-30 | `lib/Transforms/Effects/Effects.cpp:31, 39`; `Contify.cpp:128-133`; `Optimize.cpp:85` | rederivation | `CallCycles` (a `CallGraph` and an SCC walk) built three times in a row: idr-effects changes no call yet preserves only `SymbolTable`; idr-contify keeps every cycle (`Contify.cpp:29-32`) yet does not preserve it. | T1: the program graph maintained in place by contify and preserved by idr-effects (§5.6 design 1). |
| OPT-31 | `ReadySet.cpp:68, 106`; `Waves.cpp:202` | state | `byName.at` and an assert where a call's callee is not a node: a lookup that can miss turned into an abort. | T1: an edge holds its node; nothing to look up. |
| OPT-32 | `Component.cpp:73-81, 84, 213-214`; `Waves.cpp:291-292` | rederivation | Each final callee's effects copied onto every call of it before each inner run and at finish (0003: "restamps every call's effects each round"); a cache of the summary on each call. | Lane 02 decides where a call's effects live (§5.8 DS2.1, DD-Q7). Here: each call stamped once, when its callee becomes final (T2). |
| OPT-33 | `Component.cpp:109-125` | list | The inner cse's statistics matched by the strings `"cse"`, `"num-cse'd"`, `"num-dce'd"` (0003). | An inner step of ours on upstream's `eliminateCommonSubExpressions` (`CSE.h:31-42` at the pin) counting into its statistic, or no inner cse counts. |
| OPT-34 | `Waves.cpp:127-140, 164, 188` | state | `reaches` searches the component graph per wait recorded and per component in a merge: graph reachability recomputed per question, quadratic in the worst case. | T1: the waits added in a wave condensed once (`scc_iterator` over the waits graph), merges by union-find. |
| OPT-35 | `Waves.cpp:150-176` | state | `merge` searches forward, then calls `reaches` per component found, then `erase_if` over every component. | Goes with OPT-20 and OPT-34. |
| OPT-36 | `Waves.cpp:59-84` | state | `enable` rescans every component every wave: components × waves (0003). | T1: a component is queued when its count of unfinished callees reaches zero (`Waves.cpp:293-294`) or a parked member's last wait is met (§5.4 F3's dependency counts). |
| OPT-37 | `Component.cpp:176-206` | budget | The member loop and its "fixed last step" (one more inline step and pipeline, `:191-204`) duplicate the park logic (`:183-187`, `:197-203`); the step is a fixed sequence that only leaves calls. | One loop whose exit is "no new request and nothing inlined" (inlining is bounded by the cap); the duplicated arm goes. |
| OPT-38 | `Component.cpp:215`; `lib/IR/Func/Func.cpp:207-219` | rederivation | `componentEffects` tests membership of each callee by `SymbolTable::lookup`, which `Node::scc` already answers. | The turn passes its members' set (T1); lane 02 owns the effect sum. |
| OPT-39 | `Component.cpp:230-250` | state | `bindingTimesOf` is called per held member over all held members (each call walks the component again); a `holds_alternative<Held>` filter. | One solve per component returning every member's times (lane 05's analysis). |
| OPT-40 | `Waves.cpp:333-337` | cpp | A context flag (`hasActionHandler`) selects a serial loop or `failableParallelForEach`: two paths, equal output by construction. | One loop: `failableParallelForEach` already runs serially when the context's threading is off (§5.3 D1), so the pass turns threading off while a handler is installed. |
| OPT-41 | `Waves.cpp:222-249` | rederivation | `stepOfRecursion` walks the origin's body for a self call (`CallCycles::callsItself` exists), reads `members.size() > 1`, `get_if<SpecKeyAttr>`, `sharedClosure`, `closuresFixed`, and labels by name: four facts combined at insert. | T4: the node's kind (OPT-18), decided at grant from the key and the origin's component. |
| OPT-42 | `Waves.cpp:259-275` | state | One `Scc` heap object per made node; an unchecked `std::get<Built>`. | T1: dense ids; the phase sum (OPT-17). |
| OPT-43 | `Waves.cpp:283-295` | state | `finalize` leaves the Done state with a moved-from `times` (OPT-17). | Goes with OPT-17. |
| OPT-44 | `Waves.cpp:348-351` | state | A postcondition (essential): "the ready set stopped with @f not final", an internal error. | Keep as the schedule's postcondition; with T1's counters, the message names the component and its unmet count. |
| OPT-45 | `Contify.cpp:88-89` | rederivation | A `SymbolUserMap` of the whole program (a 64-bucket `SetVector` per used symbol, §5.1 E2) to find each function's one use: the call graph's caller edges again. | T1's program graph gives callers (lane 10 owns contification). |
| OPT-46 | `Contify.cpp:34-42, 100` | ladder | A function holding an unreachable second block left by an earlier move of the same sweep is skipped ("a move this run does not make"): a case made by when the cleanup runs. | Erase the unreachable block at each move, which the program graph updated in place allows (lane 10). |
| OPT-47 | `Contify.cpp:133` | upstream | `CallCycles` not preserved though the sweep keeps every cycle. | OPT-30. |
| OPT-48 | `Requests.cpp:91-104, 153-155, 194-200` | state | A node's `parents` are pushed in lock order, so `chainOf` returns its keys in an order that depends on which worker took the lock first, and `differing()` lifts against the *first* same-shape key: with two same-shape keys on a chain the lifted key, and the node, depend on the schedule. A determinism leak (*read*; *conjecture* that the case occurs in a program). | The chain is a set: parents sorted by name when the wave settles, or the lift taken against every same-shape key at once. A one-thread-against-many test (Q-llvm-6). |
| OPT-49 | `include/idr/Transforms/SpecializeState.h:50-62`; `Requests.cpp:133-158, 172-223`; `Specialize.cpp:56-59` | state | One mutex over the node table, held across `Order::grows` against every earlier key, `chainOf`, every lift, `sharesClosure`'s walk and the canonical printing of a new key's name (`canonicalHash`), and taken per call by `find` and `seenBy`: a global lock on the workers' path (§4's bar). | T3: decide and digest outside the lock against what the requester was given (its own, owned by its turn); the shared table only inserts keys, sharded by owner. |
| OPT-50 | `Specialize.cpp:110-127` | state | `insert` scans the owner's placed nodes, a lock per `find`, comparing names: O(k) per node, O(k²) per owner. | Insert a wave's nodes in one sorted batch (settle sorts already). |
| OPT-51 | `include/idr/Transforms/Specialize.h:141-191` | cpp | `Nodes`' `const` members write shared state through a pointer ("the const members write under one lock"): a const interface over mutation. | T3: a typed handle per writer, or `Shared<T>` whose `modify` names the write (§5.4 F10). |
| OPT-52 | `include/idr/Transforms/SpecializeState.h:28-48` | state | A `Requester` per requesting function holds a `DenseMap` by owner name and a `SetVector`: two 64-bucket tables per function (§5.3 B7). | T3: held by the requester's turn as a small sorted vector; no table in the shared state. |
| OPT-53 | `include/idr/Transforms/Specialize.h:96-98`; `IdrAttrs.td:244` | list | `specialize::Node::origin` is the program's function; `SpecKeyAttr`'s `origin` is the owner (0003). | Rename the key's parameter `owner` (and the Idris side, if it ever reads the key). |
| OPT-54 | `include/idr/Transforms/Specialize.h:62-63` | cpp | `RaiseKey = std::variant_alternative_t<1, Key>`: a type named by its position in a variant. | Name `KeyRaiseAttr` directly; with T3 the key sum is ours. |
| OPT-55 | `include/idr/Transforms/Specialize.h:252-268` | state | `Forms`: `std::unordered_map` beside LLVM's ADT; a mutex held across `deduplicate::sameFunction`; forms kept as detached `FuncOp`s. | T3: interned in the run's arena by the deduplicator's structural hash (lane 06's), read lock-free once inserted. |
| OPT-56 | `Consumer.cpp:119-145` | rederivation | A consumer is named by printing its canonical text and digesting it after `hashFunction` already decided its class (0003). | A stable structural digest computed in the hash's own walk (lane 06's hash). |
| OPT-57 | `Consumer.cpp:95`; `Raise.cpp:40-48, 96` | rederivation | The consumer is built at `UnknownLoc`, and every op pushed into a tail takes the terminator's location: the consumer's own locations are lost (0003). | `CallSiteLoc(op, term)`, as upstream's inliner stacks locations (`InliningUtils.cpp:44-47`). |
| OPT-58 | `Consumer.cpp:59-63` | rederivation | Effects read as bits by hand (`bitEnumContainsAny(..., crash \| io)`, `diverge && performsIO`). | Lane 02's one effects model (resources, §5.8 EF2) answers "may this callee interleave with IO". |
| OPT-59 | `Consumer.cpp:152-188`; `Requests.cpp:172, 276-283` | cpp | `FailureOr<std::optional<Want>>` and `FailureOr<std::optional<SpecGrant>>` thread through every caller to carry two internal errors (digest collisions, `Consumer.cpp:142`, `Requests.cpp:139-142`). | A decision sum `Keep \| Spec \| Raise`; internal errors as `llvm::Error` at the table's boundary. |
| OPT-60 | `Patterns.cpp:67-76, 122-154`; `Keys.cpp:79-84, 104-134`; `Order.cpp:39-51, 66-71, 98-105, 147-186`; `Specialization.cpp:49` | ladder | A key's pattern is an open `mlir::Attribute`, dispatched over four cases (hole, constructor, constant constructor, scalar) by 34 lines of `isa`/`dyn_cast` in 14 functions (*measured*: `grep -n "isa<\|dyn_cast<\|isa_and_nonnull<"` over `Keys.cpp`, `Patterns.cpp`, `Order.cpp`, `Specialization.cpp`, piped to `grep -c "KeyHoleAttr\|KeyConAttr\|ConAttr\|BigAttr\|StringAttr\|TypedAttr"`). | T3: the pattern grammar as a closed sum: `#idr.key_hole`, `#idr.key_con`, `#idr.key_const` under one attribute interface, `SpecKeyAttr`'s patterns constrained to it; one exhaustive `match` in C++. |
| OPT-61 | `Order.cpp:38-46` | ladder | A scalar's kind is a `pair<TypeID, const void *>` from an `isa` ladder. | Goes with OPT-60: `key_const`'s kind is its type, one field. |
| OPT-62 | `Order.cpp:131-139` | state | `grows` builds a fresh `Embeddings` `DenseMap` per call (64 buckets on first insert), once per earlier key per request. | One memo per request, or per run keyed by interned pairs (T3). |
| OPT-63 | `Order.cpp:23-33, 178-211` | cpp | (Essential.) Constant sizes as `APInt`: a shared part counts once per use, so a tree size can exceed 64 bits. | Keep; it is the measure the embedding is defined by. |
| OPT-64 | `Keys.cpp:84-90, 242`; `Order.cpp:94-109, 223`; `Requests.cpp:146`; `Consumer.cpp:100, 136`; `Raise.cpp:122-123` | state | Keys, names and function types created on workers in the `MLIRContext`, never freed, each taking a uniquer shard's lock (§5.1 F3), keys of refused and lifted requests included. | T3: keys hash-consed in a run arena freed with the pass; the context sees only the node's name. |
| OPT-65 | `Keys.cpp:119` | cpp | `std::get_if<role::Label>(...)->fn` dereferences an unchecked `get_if`: "a closure sum's constructor is a label" is in the type's kind, not in the C++ type. | Lane 01's typed body view (0003, "a data type's body ... one alternative per kind"). |
| OPT-66 | `Keys.cpp:61-63`; `include/idr/Transforms/Specialize.h:295-296` | cpp | "Calling a node or a held function" as `std::optional<SpecKeyAttr> own` plus `bool intoNode`. | T4: the callee's node kind (OPT-18) decides once. |
| OPT-67 | `Keys.cpp:150-156`; `Specialize.h:306-307`; `Waves.cpp:245` | cpp | `closuresFixed` returns `optional<SmallVector<StringAttr>>` whose `nullopt` and empty list are read together as `!labels \|\| labels->empty()`. | A sum `FixesData \| FixesClosures(non-empty labels)`. |
| OPT-68 | `Patterns.cpp:27-30` | ladder | `isa_and_nonnull<ConstantOp, arith::ConstantOp>` restates `ConstantLike` plus "the dialect rebuilds it". | `m_Constant` and the dialect's materializer, which `rebuild` already calls (`Patterns.cpp:134-135`). |
| OPT-69 | `Patterns.cpp:35` | ladder | `isa_and_nonnull<ConOp, LinEnterOp>` ("builds part of a shape") restates `Idr_BuildsValue` (7987388b) and the grade-only change. | Read the traits (lane 02). |
| OPT-70 | `Patterns.cpp:55-74` | cpp | `shapeOf` appends a leaf and pops it back when a linear entry wraps a hole (`:70`). | Return the pattern and its leaves as a value; no undo. |
| OPT-71 | `Consumer.cpp:163-164` | ladder | "The callee returns" as `isa<ReturnOp>` of its terminator. | `ReturnLike`, or the never-returning terminator as its own trait (§5.8 DS4 `NoReturn`; lane 03). |
| OPT-72 | `Consumer.cpp:190-199` | cpp | `decideApplied` repeats `decide`'s spec tail (`:180-187`). | One function. |
| OPT-73 | `Specialization.cpp:27-30` | dead | An internal error for patterns ≠ parameters, unreachable: `composeKey` zips the call's arguments with the parameters and `lift` keeps the length. | Delete. |
| OPT-74 | `Specialize.cpp:85-94` | state | `build` looks the owner up again by name and has an internal error for an owner the claimant may not read, a state the grant excludes (`Requests.cpp:299-301` asserts it). | The node holds its owner from the grant; the lookup and the error go. |
| OPT-75 | `Specialization.cpp:38-56`; `Redirect.cpp:29-49`; `Pipeline.cpp` (16005000's comment) | rederivation | A spec node takes one parameter per hole whether its body reads it or not, and no pass of the `idr` level drops an unused parameter or result: 16005000's "clones keep only the holes of what their callers' known values leave open" holds of holes, not of reads. | T5 (QA3, Q-opt-3). |
| OPT-76 | `Requests.cpp:121-125` | list | A node's kind spelled `"spec"`/`"raise"` for its name, one more switch over the key. | From the key sum (T3), one place. |
| OPT-77 | `Requests.cpp:240-252` | state | `seenBy` takes the lock and does four name lookups per call to decide "same component". | T1's node handles and component ids. |
| OPT-78 | `Report.cpp:26-39`; `Passes.td:294-304` | rederivation | idr-binding-times recomputes binding times per component for one fixture (`tests/specialize-binding-times`), apart from the run's own (which sees merges and made nodes). | Binding times one cached analysis over the program graph's components, read by both. |
| OPT-79 | `Identity.cpp:76-77`; `Constants.cpp:178-179` | state | Each inner step finds its reader by name and asserts it exists: a lookup that can miss. | T2: the step is given the member it runs on with the run. |
| OPT-80 | `include/idr/Transforms/Specialize.h:228` | list | `using Consumer = idr::Elimination`: two names for one thing. | One name. |
| OPT-81 | `Consumer.cpp:48`; `Keys.cpp:201` | rederivation | The world excluded by a type test at each use (`holdsWorld`, `isWorld`): "does IO" read off operand types. | Lanes 02 and 03 (DD-Q3, ods-Q2). |
| OPT-82 | `compiler/src/IdrisMLIR/Emit/Declarations.idr:52-57`; `compiler/src/IdrisMLIR/Dialect/Idr.idr:396-398` | idris | `shared = f.arity == 0 && lazyResult f.result` becomes `noInline`, a `Bool`: a kind of top-level definition computed as a flag (Boolean blindness), though `TFn` is already indexed by `arity` (`Term.idr:525-534`). | T4: a lazy constant as its own constructor of the frontend's top-level definitions, emitted as its own op; the generated `noInline` argument goes when the op does. |
| OPT-83 | `Optimize.h:9-11`; `Analysis/Inline.h:3, 21`; `Contify.cpp:8-9`; `Requests.cpp:34-35`; `Order.cpp:116-117` | cpp | Comments cite designs and papers ("Mojo's AutomaticInline", "MLton's", "Fluet and Weeks", "Kruskal's theorem, Dickson's lemma"), which AGENTS.md says comments do not do. | Say why the code is as it is; the sources go to the pass's description or a proposal. |
| OPT-84 | `Component.cpp:8-36`; `Waves.cpp:207-249`; `Inline.cpp:83-112`; `Keys.cpp:94-146`; commits 7232d3e9, f0a42001, ed9b2a0b, d69ae5d6, 2a02891f | ladder | Inlining and specialization interleave per round, and each unrolling they produced was answered with one more rule (`stepOfRecursion`, `sharedClosure`, `closuresFixed`, `betaReduces`, `appliesBuiltClosures`): patching the trace (the skill's Insight 1) over one missing coordinate, what kind of node a call reaches. | T4, and the owner's Q-opt-1. |

## 5. Target design

What idr-optimize becomes, applying the proposal. Five changes carry the
weight (T1 to T5); T6 to T9 are smaller. Every claim about what a change
buys is *conjecture* until measured on the stage-1 module (§8).

### T1. One maintained program graph, and a schedule driven by counts

*Representation.* The call graph is the solver layer's `ProgramGraph`
(§5.6 design 1, §5.4 design 1; lane 05 owns it): functions numbered
densely, callees and callers in compressed rows, call-site counts and
components part of it, built once, kept current in place by the passes
that change calls (idr-contify: erase a vertex and an edge; idr-optimize:
an inline removes one edge and adds the callee's, a redirect replaces
one, a made node adds a vertex), and preserved by name. idr-optimize's
ready set is a view over it: per component a count of unfinished callees,
per parked member a count of unmet waits, both decremented when a target
becomes final; a component is queued when its count reaches zero
(Modular's dependency counts, §5.4 F3). Components that a wave's new waits
join into one are found by condensing those waits once (`scc_iterator`)
and merged in an `IntEqClasses` over component ids. Every reader question
takes a node id, resolved once per call when the edge is recorded.

*What it deletes.* `ReadySet.cpp:34-74` (the second walk of every body);
`Waves.cpp:59-84` (`enable`'s rescan), `:127-140` (`reaches`), the
searches of `:150-176` (`merge`); `Node::waiting()` and `waitsOn`'s
linear checks; `Scc::callers` as member proxies; the two `byName` maps and
the string-keyed reader API (`held`, `finalCallee`, `knownCallee`,
`sameComponent`, `originOf`); `specialize::Schedule` and its five
`virtual`s; two of the three `CallCycles` builds before the pass
(OPT-29, 30, 34-36, 19-22, 31, 45, 47, 77).

*The line.* A component is queued exactly when its last callee becomes
final, so the per-wave rescan, the per-wait search and the name lookups
are deleted; the call graph is built once and kept current by the passes
that change calls.

*What stays, and why.* The barrier between waves stays where MLIR puts it:
a dynamic pipeline may run only on an op nested under the pass's
(`mlir/lib/Pass/Pass.cpp:574-577` at the pin), so a made node is inserted
into the program before its first turn, and nesting an analysis manager
inserts into a map that pipelines on other functions read
(`Pass.cpp:591`; §5.1 F1), so that happens with no turn running. Whether
the barrier idles threads enough to matter is §8's first measurement. If
it does, Mojo's way out is a per-thread `mlir::PassManager` run directly
on each function (§5.4 F8), which needs no nesting under the pass but
loses the parent's cached analyses and, as Mojo runs it, the verifier
after each inner pass, which AGENTS.md keeps for the grades (*conjecture*
that this is all it costs us). The wave is still where determinism is
fixed (name order of placements).

### T2. Every mutation inside a pass; one phase per node

*Representation.* The inline step becomes a pass of the inner pipeline
(`idr-inline-final`, say), made per run with what it reads, as idr-identity,
idr-redirect and idr-constants already are (`InnerPasses.td:16-71`); so
does the stamping of final callees' effects on calls, which runs once per
call when its callee becomes final (until lane 02 decides where a call's
effects live). A node's phase is one sum, `Waiting | Parked{on, solved} |
Done{solved} | Final{summary}`, and a step that needs a phase is handed
it. Each inner step is given the member it runs on with the run, not its
name to look up.

*What it deletes.* Mutation of a function outside the pass manager
(`Component.cpp:148-160`, `:73-81` as called from the scheduler), hence
analyses cached across a mutation (OPT-14); `published` beside `state`,
the moved-from Done (`Waves.cpp:286-288`), the unchecked
`std::get<Node::Done>`, `std::get<Node::Parked>`, `std::get<Built>`;
`nodeOf` plus `assert` in idr-identity and idr-constants (OPT-17, 32,
42, 43, 79). The inline step also gains the verifier and instrumentation
every other inner step has.

*The line.* An analysis cached across a mutation of the function is
unrepresentable, because no mutation happens outside a pass; and a final
node holding a stale "done" state cannot be built, because final is a
phase, not a second field.

### T3. Keys as a closed sum in a run arena; the node table without a global lock

*Representation.* A key's pattern is one of three cases, `Hole | Con{tag,
fields} | Const{attribute}` (a constant constructor and a scalar are both
`Const`, distinguished by the attribute they hold, which the IR already
uniqued). Keys are our own data, held by no op (`IdrAttrs.td:215-220`), so
they are hash-consed in the run's arena (CIRCT's interned allocator,
§5.6 A6; Zig's intern pool, §5.7 G3), freed with the pass, and dispatched
by one exhaustive `match` (§5.5 D2). A node's name is the digest of a
canonical byte encoding of its key, computed by the arena's own walk with
the same `digestOf` (`Symbols.h:253`), so names stay stable across runs
and machines (stage 2 = stage 3). What a requester was given, and its
request chain, live in the requester's turn, which one worker owns; the
shared table only inserts a key or finds its node, sharded by owner. The
decision (compose, judge, lift, digest) runs with no lock, against the
requester's own state. Parents gathered in a wave are sorted by name when
it settles. Consumer forms are interned by the deduplicator's structural
hash (lane 06) in the same arena.

*What it deletes.* The 34-line ladder over key attributes and `kindOf`'s
opaque pair (OPT-60, 61); `KeyHoleAttr`, `KeyConAttr`, `SpecKeyAttr`,
`KeyRaiseAttr` as context attributes (`IdrAttrs.td:221-256`, if no op or
the Idris side comes to need them); the fresh `Embeddings` map per call
and `Order::sizes`' map keyed by context attributes (memos on arena
nodes); `Requester`'s two tables per function; the one mutex and the
`const` interface over it; `Forms`' `unordered_map`, mutex and detached
`FuncOp`s; canonical printing under the lock (OPT-49 to 52, 54 to 56,
62, 64, 76).

*The line.* A key is one of three cases by type and lives as long as the
run: the ladder, the context's growth and its locks on the workers' path,
and the global lock over judgement are deleted; and the order of a
request chain cannot leak into a node, because the chain is sorted where
it is gathered (OPT-48).

*If the owner keeps keys as attributes* (they print, and the Idris side
may one day read them): the same sum in ODS, three attribute kinds under
one `Idr_KeyPattern` interface with `SpecKeyAttr`'s patterns constrained
to it, keeps the ladder's deletion and loses only the arena's.

### T4. One coordinate for what a call reaches: node kinds and a typed verdict

*Representation.* A made node's kind is decided once, when its key is
granted: `Raise{key}`; `Beta{labels}` when the key fixes closures alone,
of labels outside the origin's component, none shared (what
`closuresFixed`, `sharedClosure` and the label test of
`Waves.cpp:222-249` compute today); `Step` for any other spec node of a
recursive origin; `Spec` otherwise. A held function's kind is `Held`. The
inline verdict is a function of the kind and the node's component:
`Keep(Cycle | Step) | Leaf | Weighed{size, calls} | Beta`. The beta step of
a recursion is one mechanism, a `Beta` node (the redirect path of
2a02891f), and the verdict inlines it. A lazy constant whose cell every
use shares is not a function: the Idris side gives it its own constructor
of top-level definitions (`TFn` is indexed by `arity` already,
`Term.idr:525-534`), Emit writes it as its own op (lanes 03, 14, 15
choose the op), and the inliner never sees it.

*What it deletes.* `factsOf`'s `shared` parameter and its self-call walk,
`no_inline` and `getNoInline()`, `Made::stepOfRecursion`,
`specialize::Node::sharedClosure`, `Scheduler::stepOfRecursion`,
`specializesOn`'s `intoNode`, `composeKey`'s `optional<SpecKeyAttr> own`
(the callee's kind carries it); `betaReduces`, `callsOnlyBeside`,
`dispatched` and the `Sibling` arm of the inline step; two of the three
copies of "built for this call alone"; Emit's `shared` and the generated
`noInline` argument (OPT-04, 06, 07, 09-11, 13, 18, 41, 66, 82, 84).

*The line.* What a call reaches is one sum decided at the grant, and the
verdict reads it: the five rules added after five unrollings become one
coordinate, and a lazy constant is no longer a function the inliner has to
be told to leave alone.

*Essential, kept distinct.* `Beta` and `Step` are two cases because the
problem has two: a node that consumes what its caller built, and a step of
a recursion on static data whose next step is another node. Folding them
behind a flag is what the code does today.

*Open.* OPT-12 (made nodes counted as one call) is the owner's (Q-opt-2):
counting requesters needs every caller to have run, which the bottom-up
order does not give; weighing made nodes only as `Leaf` or `Beta` gives up
inlining a `Spec` or `Raise` node of one real caller.

### T5. Demand on signatures, in the summary (gated on QA3)

*Representation.* Each summary gains a bit per parameter, "read by the
body" (MLton's removeUnused cells, §5.9 F2; Modular's dead-argument pass,
§5.4 F8), solved when the component finishes: a parameter is read unless
its only uses are arguments at a callee's unread parameter; callees are
final, so their bits are known, and inside a component the bits are a
least fixpoint over a finite lattice (bits only rise), so it terminates by
construction. A final callee's unread parameters are erased from its
signature (the root's excepted: it is called from outside), and each
caller's turn drops the operand at its call, as it already touches every
call of a final callee. Unread results need demand from callers, which run
after: a callers-first pass over the same graph (§5.4 design 1's second
direction), or left to raising where a dispatch consumes the result
(`Consumer.cpp:43-65`).

*What it deletes.* Nothing of ours; it restores what 16005000 dropped
without a whole-program liveness state (OPT-75), and so the `dup` at the
caller and the `drop` in the callee that counting inserts for every
unread owned argument (*conjecture*, from `Pipeline.cpp` 16005000's
comment: "what it alone removed ... counting drops like any other dead
owned value").

*The line.* What no callee reads of a parameter is a bit in its summary,
decided where the callee becomes final: no state per value of the
program exists to run out of.

### T6 to T9, smaller

- **T6. Determinism, tested.** OPT-48's fix (T3), and a test that runs
  idr-optimize with one thread and with many and compares the modules
  byte for byte (Q-llvm-6, QL4); lane 19 owns the test API.
- **T7. Locations kept.** A raise node's pushed ops take
  `CallSiteLoc(op, term)` and the consumer function its dispatch's
  location (OPT-57).
- **T8. One loop per member.** The member's loop ends when a round asks
  for no new node and inlines nothing; the duplicated park arm and the
  "fixed last step" go (OPT-37).
- **T9. Words that do not drift.** The pass description states the
  property and names where the rule lives (OPT-02); comments say why, not
  whose (OPT-83); `SpecKeyAttr`'s `origin` becomes `owner` (OPT-53).

### Order inside the subsystem, and what it waits on

1. **T3** first: it touches only `Specialize/` and is independent of the
   rest; it waits on lane 06 for the structural hash of consumer forms.
2. **T1**: waits on lane 05's program graph (and its threading
   conventions, lane 13); idr-contify's maintenance is lane 10's.
3. **T2**: after T1 (the node ids); waits on lane 02 for where a call's
   effects live, which decides whether the stamping pass exists at all.
4. **T4**: after T3 (kinds read keys); the lazy constant waits on lanes
   03, 14 and 15; the typed closure body (OPT-65) on lane 01.
5. **T5**: last, and only if the owner answers QA3 this way; it needs T1's
   callers-first direction for results.
6. **T6 to T9** ride with the change that touches their lines. Lane 04's
   normalizer replaces the inner canonicalize (OPT-26) whenever it lands;
   nothing here depends on it.

## 6. Evidence for the owner's questions

Evidence only; the owner decides.

**Q-M5 (Mojo's demand-driven elaborator, or bottom-up?).**
- *What we have is already a hybrid.* Bottom-up over the components of the
  held functions (`ReadySet.cpp:44-61`, `Waves.cpp:59-84`); demand-driven
  nodes, made by the first request of a key (`Requests.cpp:133-158`),
  keyed by uniqued attributes (`Specialize.h:60-62`), so a duplicate is
  never made rather than merged after (Mojo merges after, §5.4 F4, F22);
  and Mojo's suspension: a requester parks until its nodes are final and
  is resumed (`Component.cpp:162-172`, `Waves.cpp:72-80`).
- *What bottom-up costs, in our code.* Every held function is optimized
  before its callers, including those then inlined whole into their one
  caller and erased by the symbol-dce after (`Optimize.cpp:3-4`); a made
  node's verdict is taken before any of its callers has run, so it counts
  one call (OPT-12); and interleaving inlining with specialization took
  five rules, each after an unrolling (OPT-84; 7232d3e9: 1,196 to 62,352
  lines; ed9b2a0b: sortedmap 6,810 to 101,550 lines, 140 s to 10.8 s
  CPU after the fix; f0a42001: 108 s to 5 s).
- *What Mojo's shape is about.* Mojo's elaborator instantiates generators
  over type and value parameters; our frontend already monomorphizes
  types (AGENTS.md), and our specializer works on values after
  defunctionalization (constructors and closures, `Keys.cpp:7-22`), nearer
  MLton's polyvariance or constructor specialization than elaboration.
  Mojo's one refusing limit (an opt-in depth cap, §5.4 F23) is forbidden
  here; ours ends by a well-quasi-order and lifting
  (`Requests.cpp:27-40`).
- *Threading.* The wave barrier is MLIR's requirement more than the
  schedule's (T1: a dynamic pipeline needs a nested op,
  `Pass.cpp:574-577`; nesting the analysis manager is not thread-safe);
  Mojo's `AutomaticInline` avoids that constraint by running its inner
  pipeline on a per-thread `mlir::PassManager` of its own, not through
  `Pass::runPipeline` (§5.4 F8, `InliningUtils.h:70-90` there), and with
  the verifier off (§5.4 F16); the price is the parent pass's analysis
  manager and, in Mojo, verification. Which of those AGENTS.md lets us pay
  is the question T1 leaves open.

**Q-O4 (specialize higher-order functions before the label solve?).**
- Our specialization recovers what the label solve merged only where the
  closure is an `idr.con` chain visible at the call (`Patterns.cpp:55-74`)
  or a dispatch consumes a callee's result (`Consumer.cpp:43-65`); inside
  a node only closures specialize again (`Keys.cpp:19-22, 58-63`). A
  closure reaching a call through a varying parameter, a field or a match
  result stays in its merged sum.
- Three of the last week's fixes were closures inside recursions after
  defunctionalization: continuations that capture the one before
  (ed9b2a0b), a sibling handed a closure built for it (d69ae5d6), a bind
  handing the next statement its continuation (2a02891f). These are the
  flows polyvariance before 0CFA splits by copying the function.
- Our machinery assumes the program is first-order: a key's closure is a
  constructor of its sum (`Keys.cpp:51-56`), and the ready set's graph is
  the whole graph only once every apply is a call (`ReadySet.cpp:7-11`).
  A polyvariance pass would run at stage Higher, before idr-optimize can.
- MLton's own budget for it, `rounds = 2, small = 30, product = 300`
  (§5.9 F5), never refuses.
- Measurement that decides it: §8, item 5.

**QA3 (`remove-dead-values`: split, or the whole module?).**
- Since 16005000, no pass of the `idr` level erases an unused parameter
  or result (*measured*: §3.1's grep). Specialization keeps a parameter
  per hole, read or not (`Specialization.cpp:38-56`); raising takes a
  result's demand only where a dispatch in the same block is its one use
  (`Consumer.cpp:43-65`).
- After lowering, LLVM's `O3` pipeline runs (`lib/Target/Optimize.cpp:57-63`),
  whose dead-argument elimination removes unused arguments of internal
  functions (*recalled*); the `dup` and `drop` counting inserted for an
  unread owned argument are runtime calls it cannot remove
  (*conjecture*).
- What our code offers a signature solver: a schedule that finalizes every
  callee before its callers and a summary per function written once
  (`Optimize.h:55-67`), which is where a bit per parameter can be solved
  and the callee's signature narrowed before any caller runs (T5). Results
  need the other direction.
- The intraprocedural half: canonicalize and cse already delete dead pure
  ops per function, inside idr-optimize (`Optimize.cpp:64-67`) and after it
  (`Pipeline.cpp:92-94`); dead results of a match are lane 04's.

**Q-llvm-2, Q-E3 (budgets).**
- Every budget here is counted in the program's units and only leaves
  code less optimized: MLton's numbers (`Analysis/Inline.h:21-25`); the
  caller cap of 10,000 ops (`:30`; a capped call stays a call,
  `Inline.cpp:148-151`); one fixed last round per member
  (`Component.cpp:191-204`); the greedy driver's 10 iterations, whose
  non-convergence the canonicalizer ignores (OPT-26). `grep` for
  `chrono`, `seconds`, `bytes` and `Memory` over the files finds nothing:
  no budget in bytes or time (*measured*).
- Specialization has no budget at all: it ends by the embedding order and
  lifting, by construction.
- No refusal rests on any analysis here: the subsystem emits no
  `unsupported` (*measured*: `grep unsupported`), and its only failures
  are internal errors (two digest collisions, two built-function checks,
  one postcondition; §4 OPT-44, 59, 73, 74). None turns a spent budget
  into an error, as IREE's passes do (§5.6 C3).

**oom-2 (the compiler running out; budgets in program units).**
- What the subsystem's memory is sized by: nodes, bounded by the
  well-quasi-order but by no constant; keys, attributes the context never
  frees (OPT-64); per-requester tables (OPT-52); per-function solver state,
  bounded by the caller cap (OPT-16).
- Where a named line on pressure would go: the per-wave progress remark
  (`Waves.cpp:342-345`) and the Tracy zone per member (`Component.cpp:177`)
  already name the wave and the function being optimized.
- Every budget is in ops or calls (above): the output does not depend on
  the machine, which is what stage 2 = stage 3 needs (§5.11 C7).

**Adjacent questions this code bears on.**
- **rc-Q2 (specialization by grade).** idr-optimize runs at stage First
  (`Passes.td:236-237`), before idr-rc writes grades; its keys hold
  constructors and constants only. R2 needs a specializer after counting,
  or optimize moved after grading.
- **Q-M1, Q-E1 (one schedule, three solve shapes).** idr-optimize is the
  largest client of a call-graph schedule, and the one that grows the
  graph mid-run and merges components (T1).
- **Q-llvm-7 (the giant component).** A component's members run one after
  another in one turn (`Component.cpp:257-269`): a giant component is one
  worker's whole share. idr-contify, before it, folds one-call members
  into their callers.
- **Q-llvm-6, QL4 (determinism).** Waves and name order make the output
  independent of the schedule, but for OPT-48.
- **ods-Q6, Q-M2, Q-O5 (verification).** Each inner step runs through
  `runPipeline`, which verifies the function after each of the five
  passes, every round, every member (`Optimize.cpp:10-12`); the program
  pass is verified again after idr-optimize. The inline step is the one
  rewrite no verifier sees until the next inner pass (OPT-14).
- **Q-E2 (where a summary lives).** Of the summary, effects go into the IR
  (functions and calls); what a function gives back, binding times,
  constants and inline facts die with the run, and what it gives back is
  solved again by idr-returned-arguments on the lowered module (0003;
  lane 10).

**New questions for the owner.**
- **Q-opt-1. Interleave, or MLton's order?** Keep inlining and
  specialization interleaved per round (today, with T4's kinds), or
  specialize to completion first and then decide inlining once on the
  final graph with true call counts (§5.9 F1), then normalize? Interleaving
  finds keys only inlining exposes (a constructor visible after a callee
  is inlined); separating them makes OPT-12 and OPT-84 disappear, and loses
  those keys unless specialization runs a second time.
- **Q-opt-2. A made node's call count** (OPT-12). Count its requesters,
  which is known only once every caller has run, or weigh a made node only
  as a leaf or a beta step?
- **Q-opt-3. Keys outside the context** (T3). Keys are held by no op. May
  they be the run's own interned data, freed with the pass and taking no
  context lock, or must they stay attributes so that tools can print them?
- **Q-opt-4. Our half of a split QA3.** If `remove-dead-values` is split,
  may the signature half live in idr-optimize's summary (T5), parameters
  bottom-up and results in a callers-first pass, rather than in a
  separate solver?

## 7. Deletion list

By file and symbol; the change that deletes it in brackets. Paths under
`foreign/idr` unless marked.

- `lib/Transforms/Optimize/ReadySet.cpp`: the constructor's walk of every
  body and its edge linking (`:34-74`); `finalCallee`, `knownCallee`,
  `sameComponent` as name lookups (`:81-107`) [T1].
- `include/idr/Transforms/Optimize.h`: `Node::waiting()`, `Node::waitsOn`,
  `Node::published` (into the phase sum), `Node::Made::stepOfRecursion`,
  `Node::stepOfRecursion()`, `Node::calls()` as it is, `Scc::callers` as
  member proxies, `ReadySet::byName`, the base `specialize::Schedule`
  [T1, T2, T4].
- `include/idr/Transforms/OptimizeScheduler.h` and `Waves.cpp`:
  `Scheduler::enable` (`Waves.cpp:59-84`), `Scheduler::reaches`
  (`:127-140`), `merge`'s searches (`:150-176`), `Scheduler::stepOfRecursion`
  (`:222-249`), the `hasActionHandler` branch (`:333-337`),
  `Scheduler::RunPipeline` [T1, T4, OPT-24, OPT-40].
- `lib/Transforms/Optimize/Component.cpp`: `inlineStep`, `round` and
  `writeCallEffects` as scheduler code (they become inner passes, or the
  stamping goes with lane 02's decision); the duplicated park arm and the
  fixed last step of `runMember` (`:191-204`); `addInnerStatistics`'
  string matching (`:109-125`) [T2, T8, OPT-33].
- `lib/Transforms/Inline/Inline.cpp`: `dispatched`, `callsOnlyBeside`,
  `betaReduces` (`:47-112`) and the `Sibling` arm (`:140-144`);
  `include/idr/Transforms/Inline.h`'s `function_ref` parameter [T4, OPT-08].
- `include/idr/Analysis/Inline.h`, `lib/Analysis/Inline.cpp`: `Facts::inlines`
  (into the verdict sum), `factsOf`'s `shared` parameter, its self-call
  walk and its `getNoInline()` read; the comment of `:26-29` [T4].
- `include/idr/Transforms/Specialize.h`: `Schedule`; `RaiseKey`;
  `specialize::Node::sharedClosure`; `Forms` as it is (its
  `std::unordered_map`, mutex and map of detached `FuncOp`s);
  `Order::Embeddings` per call; `closuresFixed`'s `optional<SmallVector>`;
  `composeKey`'s `optional<SpecKeyAttr> own`; `Consumer` (alias);
  `decideApplied`; `appliesBuiltClosures` and `sharesClosure` (into the
  node's kind); the `const` members of `Nodes` that write [T3, T4].
- `include/idr/Transforms/SpecializeState.h`: `Requester` (moved into the
  turn), the one `Nodes::State::mutex` as a global lock, `byName` [T3].
- `lib/Transforms/Specialize/Specialize.cpp`: `Nodes::find` as a locked
  lookup per call; `build`'s owner lookup and its internal error
  (`:88-94`); `insert`'s scan (`:116-123`) [T3, OPT-74, OPT-50].
- `lib/Transforms/Specialize/Requests.cpp`: `originOf`, `seenBy`'s lookups,
  `kindOf`'s strings; `chainOf` in lock order (sorted instead) [T1, T3].
- `lib/Transforms/Specialize/Keys.cpp`, `Order.cpp`, `Patterns.cpp`,
  `Specialization.cpp:49`: the 34 `isa`/`dyn_cast` lines over key
  attributes; `Order.cpp`'s `kindOf` and `isScalar`; `Order::sizes` keyed
  by context attributes; `specializesOn`'s `intoNode`; `Patterns.cpp`'s
  `constant()` and `isShapeOp` ladders and `shapeOf`'s pop [T3, T4,
  OPT-68 to 70].
- `lib/Transforms/Specialize/Consumer.cpp`: the digest by printing
  (`:134-136`), `UnknownLoc` (`:95`), the `FailureOr<std::optional<...>>`
  plumbing [T3, T7, OPT-59].
- `lib/Transforms/Specialize/Raise.cpp`: `locate`'s overwrite (`:40-48`)
  [T7].
- `lib/Transforms/Specialize/Specialization.cpp:27-30`: the unreachable
  internal error [OPT-73].
- `include/idr/IR/IdrAttrs.td:215-256`: `Idr_KeyHoleAttr`, `Idr_KeyConAttr`,
  `Idr_SpecKeyAttr`, `Idr_KeyRaiseAttr`, if Q-opt-3 takes keys out of the
  context; else they are replaced by the three-case sum [T3].
- `include/idr/IR/IdrOps.td:116, 140-141, 161`: `idr.func`'s `no_inline` and
  its description, once the lazy constant has its own op (lanes 03, 14,
  15) [T4].
- `compiler/src/IdrisMLIR/Emit/Declarations.idr:52-57`: `shared`,
  `noInline = shared`, `lazyResult`; the generated `noInline` argument of
  `compiler/src/IdrisMLIR/Dialect/Idr.idr:396-398` with the regenerated
  mirror [T4].
- `include/idr/Transforms/Passes.td:239-277`: the restated numbers and the
  stale termination prose [T9].
- `lib/Transforms/Specialize/Report.cpp:26-39`: its own computation of
  binding times (it reads the cached analysis) [OPT-78].
- `lib/Transforms/Identity/Identity.cpp:76-77`,
  `lib/Transforms/Effects/Constants.cpp:178-179`: `nodeOf` and its assert
  [T2].
- `lib/Transforms/Optimize/Contify.cpp:88-89, 100`: the whole-program
  `SymbolUserMap` and the one-block skip (lane 10's to confirm) [T1].

## 8. Risks, unknowns, measurements needed

**Risks.**
1. *The biggest: T4 changes what gets inlined.* Every change to this
   rule in the last week was answered by a compile-time blow-up somewhere
   (7232d3e9: one program 25.6 s; f0a42001: 108 s in idr-optimize;
   ed9b2a0b: about twenty programs timing out). Folding the five rules into
   node kinds is a representation change with behavioural reach, and no
   built compiler exists in this checkout to measure it. Each kind needs a
   fixture that holds its property (a `Beta` node leaves no allocation,
   as `lazy-branch-loop` holds no-heap-allocation; a `Step` node is never
   inlined), and the compile-time table of ed9b2a0b rerun.
2. *T1's barrier may be MLIR's to keep.* Per-node readiness without waves
   needs nesting an analysis manager and inserting an op while other
   workers run pipelines; upstream allows neither concurrently
   (`Pass.cpp:574-591`). If the idle time per wave is large, the remedy is
   an upstream change, not ours.
3. *T3's names must not move.* A node's name is its key's digest, and a
   second idr-optimize run calls a node it finds by name (ed6c2dff); a new
   canonical encoding must give equal names for equal keys on every
   machine and thread count (stage 2 = stage 3).
4. *T5 narrows signatures.* A function named by a closure label
   (`role::Label`, `Inline.cpp:106`, `Keys.cpp:119`) is used by something
   other than calls; narrowing it must count that use as an unknown caller
   (upstream patch 29's lesson, §5.1 B4). The root keeps its signature.
5. *OPT-14 may be a latent miscompile or nothing.* A stale dominance
   answer on a single-block region is impossible, on a reused `Region *`
   it is not; it is a contract broken either way.

**Unknowns, and the measurement for each** (the build machine's; none
can run here). Commands are the tools' as the tree has them; the
counting properties would be new idr-expect properties (lane 19).
1. *Waves on the stage-1 module*: their number, turns per wave, and each
   wave's idle time against its longest turn. The per-wave
   `idr-optimize`/`progress` remark (`Waves.cpp:342-345`) gives the counts;
   the Tracy zones per member (`Component.cpp:177`) and per thread
   (`profile::ThreadTrace`, `:253`) give the idle time.
2. *Node table pressure*: nodes made, requests refused, lifts, keys created,
   and the time `Nodes::State::mutex` is held (a Tracy zone around
   `requestSpec`'s critical section); the context's attribute count
   before and after idr-optimize.
3. *OPT-12's code growth*: calls inlined whose callee is a made node with
   more than one requester, and the bytes they add.
4. *OPT-48*: one thread against many on the stage-1 module, modules
   compared byte for byte (`--mlir-disable-threading` against the
   default).
5. *What specialization leaves of the label solve* (Q-O4, §5.9 Q-W1): the
   matches on closure sums after idr-optimize and the number of cases of
   each.
6. *What 16005000 left* (QA3): parameters of final bodies with no use, and
   the `dup`/`drop` pairs counting inserts for them.
7. *Where a round's time goes*: identity, canonicalize, cse, redirect,
   constants and the verifier after each (`-mlir-timing` sees inner
   pipelines through pass instrumentation; *conjecture* that the verifier
   rows appear), for ods-Q6 and lane 04.
8. *Component sizes* (Q-llvm-7): the distribution, and the largest
   component's share of idr-optimize's time.
9. *Largest function after idr-optimize*, against `kCallerCap`
   (`largest-function` property, `Expect/Sizes.cpp`), and how many calls
   the cap kept (`idr-optimize`'s `capped` statistic).

## 9. Sources read

**Read in full, in this order.** `.claude/skills/representation-first/SKILL.md`;
`AGENTS.md`; `proposals/0000-mlir-native.md` §0 to §4, §5.1 to §5.9 in
full (§5.4 and §5.9 twice), §5.10 (findings A1 to A8, E, F, G and
5.10.2 to 5.10.4), §5.11 (5.11.2 to 5.11.4; C2 to C7), §6 to §9;
`proposals/0003-facts-once.md`; `audits/p0/README.md`.

**The subsystem, line by line.** Every file of §2.1's table:
`foreign/idr/include/idr/Analysis/Inline.h`, `lib/Analysis/Inline.cpp`,
`include/idr/Transforms/{Inline,Optimize,OptimizeScheduler,Specialize,SpecializeState}.h`,
`lib/Transforms/Inline/Inline.cpp`,
`lib/Transforms/Optimize/{Optimize,ReadySet,Component,Waves,Contify}.cpp`,
`lib/Transforms/Specialize/{Specialize,Requests,Keys,Order,Patterns,Consumer,Raise,Specialization,Redirect,RedirectPass,Report}.cpp`.

**Around it.** `foreign/idr/lib/Transforms/Identity/Identity.cpp`,
`lib/Transforms/Effects/Constants.cpp`, `include/idr/Transforms/{Effects,Identity}.h`,
`include/idr/Transforms/InnerPasses.td`, `include/idr/Transforms/Passes.td`
(`:33-65`, `:100-121`, `:207-304`, `:612-627`, `:817-842`),
`lib/Transforms/Pipeline.cpp` (the pass order), `include/idr/IR/IdrOps.td:100-240`
(`idr.func`, `idr.call`), `include/idr/IR/IdrAttrs.td:215-256` (the keys),
`include/idr/Analysis/{CallCycles,BindingTimes}.h`, the declarations of
`Identities.h`, `Constants.h`, `Effects.h`, `include/idr/IR/Symbols.h:1-140,
253-321`, `include/idr/Support/Worklist.h:67-93`,
`lib/IR/Func/Func.cpp:189-230`, `lib/Transforms/Expect/Sizes.cpp`,
`lib/Target/Optimize.cpp:57-63` (by grep), `lib/Transforms/Deduplicate/`
(by grep); `compiler/src/IdrisMLIR/Emit/Declarations.idr:30-75`,
`compiler/src/IdrisMLIR/Dialect/Idr.idr:396-398`,
`compiler/src/IdrisMLIR/Term.idr:525-534`; the list of `tests/` touching
these passes (by `ls` and `grep`), `tests/raise-shared-key` (head).

**History.** `git log --oneline` over the subsystem's paths (30 commits);
messages read in full: 98c6315c, 3a96c407, 7987388b, 16005000 (with its
diff of `Optimize.cpp` and `Pipeline.cpp`), 0a884489, d69ae5d6, 2a02891f,
ed9b2a0b, 7232d3e9, ed6c2dff, f0a42001, 5e944aca, bfdcac70 (message and
stat); the file-creation commits (1e1a3827, c7aa7b62, bfdcac70, a4156c54,
c5cc3ba6) by `git log --diff-filter=A`.

**The pinned tree** (`.toolchain/llvm-project/mlir`, 7208ba24):
`include/mlir/Transforms/Inliner.h` (`:27-155`),
`lib/Transforms/Utils/Inliner.cpp` (`:255-310`, `:500-575`),
`lib/Transforms/Utils/InliningUtils.cpp` (`:40-80`, `:300-330`),
`lib/Transforms/CSE.cpp:30-60`, `include/mlir/Transforms/CSE.h` (by grep),
`lib/Transforms/Canonicalizer.cpp:80-95`, `include/mlir/Transforms/Passes.td`
(by grep), `include/mlir/Transforms/GreedyPatternRewriteDriver.h` (by grep),
`include/mlir/Transforms/WalkPatternRewriteDriver.h` (by grep),
`lib/Pass/Pass.cpp:555-600`.

**Commands run** (all read-only): `wc -l`; `grep -rn` and `grep -c` over
the files named; `git log`, `git show -s`, `git show --stat`,
`git show <commit> -- <paths>`; `sed -n` and `cat -n` for reading.
