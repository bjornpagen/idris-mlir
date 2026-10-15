## C07 The ready set

Producer: U03, alone. Consumers: U04 (`ReadySet` as its `Schedule`, and
when its table and analyses are called), U05 (when its effects writes and
constants summaries are called; the force edges), U06
(the two passes'
create functions, C12), U17 (the per-node action, the fixtures of "each
function once"), and, for `include/idr/Support/Scc.h`, U01 (`TypeGraph`),
U02 (`Decide.cpp`), U08 (`Borrows`, `EscapesCycles`) and U17
(`Expect/Cycles.cpp`). Paths are under `foreign/idr/`. Line numbers are
the tree at a3e61f3a.

The design is 0004 §4 stages 5 to 9 (D13, D14, D15, D16, D25, D38, D39,
D47): one bottom-up ready set over the components of the call graph, each
function processed once its callees are final, Mojo's AutomaticInline
(`sources/code/modular/Mojo/lib/Transforms/AutomaticInline.cpp:380-501`)
rebuilt on `Scc.h` and MLIR's thread pool, specialization requests as
nodes made once, summaries computed callee first. Where C09 and C10 fix
their own declarations, this contract calls them as they fix them.

### 1. Files (U03)

| Path | Holds |
| --- | --- |
| `include/idr/Transforms/Optimize.h` (new) | the declarations of section 3 and the `GEN_PASS_DECL` of `IdrOptimize` and `IdrContify` |
| `lib/Transforms/Optimize/Optimize.cpp` (new) | the `idr-optimize` pass: building the ready set, the inner pipeline, the end; the `static_assert(LLVM_ENABLE_STATS, ...)` that pass statistics need (PINS.md names this directory as its site) |
| `lib/Transforms/Optimize/ReadySet.cpp` (new) | `ReadySet`, `Scc::leader` |
| `lib/Transforms/Optimize/Component.cpp` (new) | a component's turn (section 4.3) |
| `lib/Transforms/Optimize/Waves.cpp` (new) | the waves and what happens between them (section 5) |
| `lib/Transforms/Optimize/Contify.cpp` (new) | `idr-contify` (section 7) |
| `include/idr/Transforms/Inline.h`, `lib/Transforms/Inline/Inline.cpp` (both rewritten) | the inline step (section 4.3) |
| `include/idr/Analysis/Inline.h`, `lib/Analysis/Inline.cpp` (both rewritten) | C08 |
| `include/idr/Transforms/Identity.h`, `lib/Transforms/Identity/Identity.cpp` | `idr-identity`, reading `Identities::givesBack` (C09 §8) through its parent's cache |
| `include/idr/Analysis/References.h`, `lib/Analysis/References.cpp` | section 8 |
| `include/idr/Analysis/Holds.h`, `lib/Analysis/Holds.cpp` | section 9 |
| `include/idr/Transforms/Canonicalize.h` | the one configuration, unchanged in code |
| `include/idr/Support/Scc.h`, `lib/Support/Scc.cpp` | section 2 |

Deleted: `lib/Transforms/Simplify/` whole, `include/idr/Transforms/Simplify.h`,
`lib/Transforms/Inline/Prepare.cpp`.

### 2. `include/idr/Support/Scc.h`

Unchanged in code: `idr::components(ArrayRef<SmallVector<unsigned>>)`
and `idr::stronglyConnected<Node>(ArrayRef<Node>, function_ref<SmallVector<Node>(Node)>)`
keep their signatures and results (`Scc.h:23-52`), LLVM's iterative
Tarjan, callees first, a result that depends only on the order of the
nodes and of each successor list. The header comment drops "a loop
breaker is none" (`Scc.h:6-7`). Every graph of ours goes through it; the
ready set's call graph is one of them.

### 3. `include/idr/Transforms/Optimize.h`

Exactly this (the file as written):

```cpp
// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-optimize, the first-order optimizer: one bottom-up ready set over the
// components of the call graph, run in waves. A function is taken up once
// every component it calls into is final; it inlines its calls into final
// callees, runs the inner pipeline once, and runs both again only for
// what its cleanup and its specialization requests exposed. And
// idr-contify, which runs before it. (The ready set is Mojo's
// AutomaticInline design rebuilt on Scc.h and MLIR's thread pool.)
#ifndef IDR_TRANSFORMS_OPTIMIZE_H
#define IDR_TRANSFORMS_OPTIMIZE_H

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Inline.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Specialize.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

namespace idr {

#define GEN_PASS_DECL_IDROPTIMIZE
#define GEN_PASS_DECL_IDRCONTIFY
#include "idr/Transforms/Passes.h.inc"

class BindingTimes;
class ConstantSummaries;
class Holds;
class Identities;

namespace optimize {

struct Scc;

// The start of one node's work in idr-optimize, once per node; its IR unit
// is the node's function. Listed by -log-actions-to; idris-mlir-opt's
// debug counter may skip it, and a skipped node stays as it was.
struct NodeAction : support::TaggedAction<NodeAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-optimize-node";
};

// One function of the ready set: a function the module held when
// idr-optimize began, or a specialization node it made.
class Node {
public:
  // The function; for a made node, null until the node table builds it.
  idr::FuncOp fn;
  // The node table's node this one is; null for a function the module
  // held.
  specialize::Node *made = nullptr;
  // What the inline rule reads: `calls` when the node is made, the rest
  // when its component is final.
  inlining::Facts facts;

  // Whether its component is final: its facts are written and nothing
  // writes the function again. Set between waves only, so it is the same
  // for every reader of a wave.
  bool isFinal() const { return final; }

private:
  friend class ReadySet;
  friend class Scheduler;

  // A made node not yet built, then (as every node starts) one not taken
  // up, one parked on the nodes in `waitsOn`, or one done. A member's turn
  // writes its state; the rest changes between waves.
  enum class State : uint8_t { Unbuilt, Waiting, Parked, Done };

  bool final = false;
  Scc *scc = nullptr;
  State state = State::Waiting;
  bool inModule = true;
  llvm::SmallVector<Node *> waitsOn, waiters;
  // What its last turn requested and could not have yet, resolved between
  // waves.
  llvm::SmallVector<specialize::Node *> asked;
};

// A component of the ready set's graph, callees first. A component of made
// nodes grows when a request would park a node on itself.
struct Scc {
  // Module order; a merge appends the merged members.
  llvm::SmallVector<Node *> members;
  // The components with a call or a force into this one.
  llvm::SmallVector<Scc *> callers;
  unsigned unfinishedCallees = 0;
  Scc *mergedInto = nullptr;
  // What this component is after every merge.
  Scc &leader();
};

// The ready set of a module as idr-optimize drives it, and the node
// table's view of the schedule. Its maps change only between waves, so
// lookup and isFinal may be called from any worker of a wave.
class ReadySet final : public specialize::Schedule {
public:
  ReadySet(mlir::Operation *module, mlir::AnalysisManager &am);
  ~ReadySet() override;
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<ReadySet>();
  }

  // The node of the function named `name` the module holds; null for none.
  Node *nodeOf(mlir::StringAttr name) const { return byName.lookup(name); }
  // How many nodes it holds: the module's functions and the made nodes.
  size_t nodeCount() const { return all.size(); }
  idr::FuncOp lookup(mlir::StringAttr name) const override;
  bool isFinal(idr::FuncOp fn) const override;

private:
  friend class Scheduler;
  std::vector<std::unique_ptr<Node>> all;
  std::vector<std::unique_ptr<Scc>> sccs;
  llvm::DenseMap<mlir::StringAttr, Node *> byName;
  llvm::DenseMap<specialize::Node *, Node *> byMade;
};

// The inner per-function pipeline, run once per node and again by the
// bounded local loop, into `pm`, a manager on idr.func.
void buildInnerPipeline(mlir::OpPassManager &pm);

// What the scheduler reads and writes besides the ready set: the module's
// symbol table and the analyses the pass took before any task, so that
// the inner pipeline's passes find them cached.
struct Analyses {
  mlir::ModuleOp module;
  ReadySet &set;
  mlir::SymbolTable &symbols;
  const Holds &holds;
  ConstantSummaries &summaries;
  BindingTimes &times;
  Identities &identities;
  const specialize::Nodes &nodes;
  mlir::AnalysisManager am;
};

// One component's turn in a wave: the members it takes up and those it
// resumes, and what the turn left for the pass thread to settle.
struct Turn {
  Scc *scc = nullptr;
  llvm::SmallVector<Node *> starters, resumed;
  // The nodes of the table this turn built, each with what its build
  // requested.
  llvm::SmallVector<std::pair<specialize::Node *, llvm::SmallVector<specialize::Node *>>> built;
  bool finished = false;
  uint64_t inlined = 0, capped = 0;
};

// The ready set's scheduler, which idr-optimize alone runs. A wave is the
// turn of every component that can go on: its callees final, its members
// in the module and parked on nothing, run in parallel. Between waves, on
// the pass thread with no turn running, made nodes go into the module,
// finished components become final, requests are recorded or merged, and
// the next wave is read off what is final. So every turn reads a fixed
// set of final functions, and the output is the same at any thread count.
class Scheduler {
public:
  using RunPipeline = std::function<mlir::LogicalResult(mlir::OpPassManager &, mlir::Operation *)>;

  Scheduler(Analyses in, RunPipeline run);

  // Runs the waves. Failure when a turn failed, having emitted its
  // diagnostic, or when a node was left not final.
  mlir::LogicalResult run();

  uint64_t inlined() const { return numInlined; }
  uint64_t capped() const { return numCapped; }
  uint64_t made() const { return numMade; }

private:
  // A turn, on a worker (Component.cpp).
  mlir::LogicalResult turn(Turn &turn);
  // One member's loop from its next inline step: whether it was parked.
  mlir::FailureOr<bool> runMember(Node *node, bool resumed, Turn &turn);
  mlir::LogicalResult runInner(idr::FuncOp fn);
  // Builds each requested node this worker claims, and what its build
  // requests in turn.
  mlir::LogicalResult build(llvm::ArrayRef<specialize::Node *> requests, Turn &turn);
  void finish(Scc &scc);

  // Between waves, on the pass thread (Waves.cpp).
  llvm::SmallVector<Turn> nextWave();
  mlir::LogicalResult settle(llvm::MutableArrayRef<Turn> wave);
  mlir::LogicalResult insert(Node *node);
  void finalize(Scc &scc);
  Node *nodeOfMade(specialize::Node *made);
  mlir::LogicalResult want(Node *requester, Node *node);
  bool reaches(Scc &from, Scc &to);
  mlir::LogicalResult merge(Scc &into, Scc &from);

  Analyses analyses;
  RunPipeline runPipeline;

  // Copies of the inner pipeline, one per worker that runs one; a copy is
  // made when every copy is in use.
  mlir::OpPassManager inner;
  std::mutex pipelinesMutex;
  std::vector<std::unique_ptr<mlir::OpPassManager>> pipelines;
  llvm::SmallVector<mlir::OpPassManager *> idle;

  uint64_t numInlined = 0, numCapped = 0, numMade = 0, numFinal = 0;
};

} // namespace optimize
} // namespace idr

#endif // IDR_TRANSFORMS_OPTIMIZE_H
```

`Scheduler`, `Turn` and `Analyses` are declared here because the tree
keeps no header beside a unit (`tests/spec/no-local-headers`);
idr-optimize alone constructs one. No unit holds a `std::atomic`
(`tests/spec/mlir-layout`): what workers share is fixed for a wave. Nothing outside U03's files writes a `Node` or an `Scc`.
`ReadySet` is C09's `Schedule`: `lookup` and `isFinal` read `byName`,
which changes only between waves, so the table may call them from
any worker.

### 4. What idr-optimize does

`idr-optimize` (C12's `IdrOptimize`, statistics `numInlined "inlined"`,
`numCapped "capped"`, `numErased "erased"`, `numNodes "nodes"`) is one
module pass, as upstream's inliner is: inlining reads a sibling of the
function it rewrites, which a nested pass may not, and the ready set is
what makes the read safe (0004 §4 stage 6;
`sources/docs/mlir/docs/PassManagement.md:29-34`).

#### 4.1 Building the ready set (on the pass thread, before any task)

1. With `getAnalysis`, so that the inner pipeline's passes find them
   cached: `mlir::SymbolTable`, `Holds` (section 9, frozen),
   `idr::ConstantSummaries` (C10 §4), `idr::BindingTimes`,
   `idr::Identities` and `idr::specialize::Nodes` (C09 §4, §7, §8), then
   the `ReadySet`; then `nodes.start(set, times, holds)` (C09 §9.1).
2. `ReadySet`'s constructor makes one node per `idr.func` in module order,
   `facts.calls` from one walk of every body (one slot per function,
   `parallelFor`, merged in module order). Its graph: the `Call` edges of
   upstream's `mlir::CallGraph` of the module between `idr.func` nodes
   (deterministic: `MapVector` nodes, `SetVector` edges in walk order;
   the external and unknown nodes are no vertex), then a force edge from a
   function to every label `idr::forcedLabels` (C10 §3) gives for each
   `idr.force` in it, so a label is final before a function that forces
   it. Components from `idr::components` over the nodes in module order,
   each node's successors in that order. One `Scc` per component, members
   in module order, with `callers` and `unfinishedCallees` from the edges
   between components.
3. `getAnalysisManager().nest(fn)` for every function, serially, so that
   `runPipeline`'s own `nest` never inserts while workers read
   (`M/lib/Transforms/Utils/Inliner.cpp:543-546` does the same).
4. Copies of the inner pipeline, one per worker running one, taken from
   an idle list under a mutex and made when every copy is in use.

#### 4.2 The inner pipeline (`buildInnerPipeline`)

On `idr.func`, in this order, run with `Pass::runPipeline` so that the
verifier and the instrumentation stay on (0004 §4 stage 6, §8 rank 2):

1. `idr::createIdrIdentity()` (C12; reads `Identities::givesBack`, C09 §8);
2. `idr::createCanonicalizerPass()` (`Canonicalize.h`, the one
   configuration; its match patterns are case of known constructor);
3. `mlir::createCSEPass()`;
4. `idr::createIdrRedirect()` (C09 §6: each call's key requested of the
   table and the call made a call of the key's node at once);
5. `mlir::arith::createIntRangeOptimizationsPass()`;
6. `idr::createIdrConstants()` (C10 §5: the constants solve with the
   callees' published summaries).

#### 4.3 A component's turn (`Component.cpp`, on a worker)

A turn names a component, the members it takes up (`starters`) and the
parked members it resumes (`resumed`); section 5 says which. It reads
its own members and the functions final before its wave, and writes its
own members alone.

**Taken up.** Over the starters' functions in member order:
`idr::writeCallEffectsOnReady(members, symbols)` (C10 §3, D38), then
`times.solve(members)` and `identities.solve(members)` (C09 §7, §8,
§9.2, D47). Then each starter's loop under `NodeAction` (a member the
debug counter skips is left as it is, done), then each resumed member's,
in member order, each in a zone named by its function
(`profile::ThreadTrace` at the top of the turn, `IDR_ZONE`, C12 §5).

**One member's loop:**

```
first = !resumed; asked = resumed
loop:
  inline step:  each idr.call of the function at the step's start, in walk
                (pre-)order, whose callee's node is final, is inlined with
                mlir::inlineCall (cloned) when worthInlining(callee.facts,
                callee.fn.getNoInline()) and fitsCap(size, callee.facts.size);
                the caller absorbs the callee's totality (FuncOp::absorb);
                size starts at inlineSize and grows by callee.size - 1 per
                inline; a call the cap keeps counts in the turn's capped.
  if !first and the inline step inlined nothing and !asked: done
  pipeline:     the inner pipeline on the function
  requests:     nodes.takeRequests(fn) (C09); each node this worker
                claims is built (nodes.build), and what its build requests
                in turn; asked = whether any was requested
  if a requested node is not final before this wave: parked, the
                requests kept in `asked` for the pass thread
  first = false
```

A resumed loop runs the pipeline once more, so the redirect step gives a
call of a node now final its entry (C09 §9.7). A callee whose body is not
one block, or that `allowSingleBlockOptimization` refuses, is not inlined
at a call inside a single-block region (upstream's
`Inliner.cpp:720-769`). The loop is the bounded local loop of 0004 §4
stage 6. It ends: an iteration that goes on inlined a call into a final
callee, and the final callees below a caller form a finite DAG whose
cycles are never inlined; or it requested new nodes, and the keys one
function asks of one owner are finite by C09's binding-time rule and at
most `kKeysPerOwner` (D39), each given once by `takeRequests`. Reaching
the cap stops inlining into the caller; it never rejects. There is no
iteration counter. Which turn of a wave builds a node changes nothing:
its body is a function of its key and its owner's final body.

**Finish.** When every member of the component is done after the turn:
`idr::writeCallEffectsOnReady(members, symbols)` once more, since every
callee outside the component is final now, the nodes its members asked
for among them, so a call redirected to a node before the node was final
takes its entry (a member whose inline step inlined nothing after its
wait keeps such a call, and C02's equality verifier would refuse it);
then `idr::writeEntriesOnFinal(members, holds, symbols)` and
`summaries.publish(members)` (C10 §3, §4); each member's `facts.size`
(`inlineSize`), `facts.leaf` (no `idr.call` in the body) and
`facts.onCycle` (two or more members, or a call of itself). The turn
says it finished; the component becomes final between waves.

#### 4.4 The end (on the pass thread, after the pool drained)

- No node may be left not final: one is a broken termination argument,
  "internal error: idr-optimize: the ready set stopped with @<f> not
  final".
- Dead functions are erased serially in module order: every private
  `idr.func` that no symbol use reaches from a public one (the root),
  counted in `numErased` (0004 §4 stage 6, "dead functions are erased
  afterwards, serially, in module order").
- A remark `finished` (category `idr-optimize`, `Analysis`) with the
  metrics `nodes`, `made`, `largest` (the largest final `facts.size`) and
  `capped`, from the pass thread.
- Preserved: `Holds`, `TypeGraph` and `Layouts`, since no type changes;
  nothing else. The ready set, C09's table and analyses and C10's
  summaries are never preserved, so a later run starts empty.

### 5. The waves (`Waves.cpp`)

#### 5.1 A wave

`Scheduler::run` repeats: read the next wave off the ready set; run its
turns with `mlir::failableParallelForEach` (serially when the context has
no threading); settle them; emit a `progress` remark (metrics `final`,
`nodes`, `made`) from the pass thread. With no turn left it ends (4.4).
A failed turn stops the run; its diagnostic was emitted.

The next wave is every component, in the ready set's order (the module's
components callees first, then made nodes' in the order they were made),
that is not final, whose callee components are all final, and that has
work: its members not taken up yet, all of them, once every one of them
is built, in the module and parked on nothing (`starters`); and its
parked members whose waits are all met (`resumed`). Each component is in
one turn, so the turns of a wave touch disjoint functions.

#### 5.2 Between waves

On the pass thread, with no turn running, in this order:

1. The turns' counts are summed into the scheduler's (the pass adds them
   to its statistics at the end).
2. Every node the turns built goes in, in name order: its ready-set node
   (made in `byMade` when new: `facts.calls = 1`, a component of its
   own), `nodes.insert(*n, module)` (after its owner and the owner's nodes
   whose names sort before its own, C09 §4; its owner may be a node made
   in this run), the symbol table (a name already there is an internal
   error, D18), `byName`, `nest`. `numNodes` counts them.
3. Every component whose turn finished becomes final: its members' `final`
   set, its callers' counts lowered, its waiters' waits on it removed.
4. Every request a turn could not follow, from the parked members in wave
   order and then the built nodes by name, is recorded: nothing when its
   node is final or in the requester's component, a merge (5.3) when the
   wait would close a cycle, a wait otherwise.

So `byName`, `byMade`, the module's top-level block, the symbol table, the
analysis manager's children, `final` and every wait change only here;
within a wave every reader sees them fixed. `runPipeline`'s `nest` of a
new function inserts into a map pipelines on other functions read, which
is why a function goes into the module only here.

#### 5.3 Merging

A requester `R` that asks for a node `N` that is not final, where `N`
reaches a member of `R`'s component through `waitsOn` edges, would be
parked on itself. Every component on such a path then merges into `R`'s:
one `Scc` whose members are theirs, every wait between two members
removed. A member not taken up yet is taken up with the others not taken
up yet when they all can be (5.1). The members finish together, so the
summaries see the cycle, and none inlines another (a member is not final
while its component runs). The waits of a wave are recorded in a fixed
order, and the cycles they close do not depend on it: the components and
when their members are taken up are a function of the requests. Only
made nodes are waited on, so a merge that would take in a component of
the module's functions is an internal error. A made node has no
`effects` until its component finishes (C10 §1): a call of a member not
final gets none when taken up and its entry at the finish (D38).

#### 5.4 Determinism (0004 §4, "Determinism rules")

A body is a function of its own body, its final callees' bodies, the
summaries written when it was taken up, and the nodes it requested;
calls are inlined in walk order; a node is made once per key, named from
its key (C09 §3) and placed by its owner and its name; finality and
waits change only between waves, in a fixed order; erasure is serial, in
module order, at the end; every map that is iterated is ordered. The
output is byte-identical at 1, 2 and 8 threads (`tests/determinism`).
C03 runs the module rules from the root's `verifySymbolUses`, which a
pipeline on one function never calls (`M/lib/IR/SymbolTable.cpp:484-500`),
so verifying any function, the root included, reads nothing beside it.

### 6. Calls into C09 and C10 (declared by their producers)

| When | Call | Producer |
| --- | --- | --- |
| before any task | `getAnalysis` of `ConstantSummaries`, `BindingTimes`, `Identities`, `specialize::Nodes`; `nodes.start(set, times, holds)` | C10 §4; C09 §4, §9.1 |
| building the graph | `idr::forcedLabels(force, symbols, labels)` | C10 §3 |
| a turn takes members up | `idr::writeCallEffectsOnReady(members, symbols)`, then `times.solve(members)`, `identities.solve(members)` | C10 §3; C09 §7, §8 |
| the inner pipeline | `idr::createIdrIdentity()`, `idr::createIdrRedirect()`, `idr::createIdrConstants()` | C12; C09 §6; C10 §5 |
| after each pipeline run and each build | `nodes.takeRequests(fn)`, `nodes.claim(n)`, `nodes.build(n)` | C09 §4, §9.4 |
| between waves | `nodes.insert(n, module)` | C09 §4 |
| a turn finishes its component | `idr::writeCallEffectsOnReady(members, symbols)`, then `idr::writeEntriesOnFinal(members, holds, symbols)`, then `summaries.publish(members)` | C10 §3, §4 |

`members` is the list of the members' functions in member order. A call
that fails is an internal error: it emits its diagnostic, the turn fails,
the wave stops and idr-optimize fails.

### 7. `idr-contify` (0004 §4 stage 5)

A module pass (C12's `IdrContify`, statistic `numContified
"contified"`), before idr-optimize. A private `idr.func` whose one use is
an `idr.call` from another function of its component of the call graph
(`idr::components`) is moved into that call with `mlir::inlineCall`
(`shouldCloneInlinedRegion = false`), the caller absorbs its totality,
the call and the function are erased through the symbol table; sweeps
repeat, the components taken anew, until one moves nothing. This is
MLton's contification (Fluet and Weeks; `mlton/ssa/contify.fun:309-330`)
where a structured body can hold it: a function with one call site
returns to one place, and its only predecessor dominates it; a second
call site would need a branch out of a match region, which a body of
regions cannot hold. A function on no cycle with its caller is left to
the ready set, which inlines a function of one call under the cap
(C08); a member of a cycle is what the ready set never inlines. The
single-block rule of 4.3 applies. Each sweep that moves a function erases
one, so the pass ends.

### 8. `include/idr/Analysis/References.h`

Kept for its consumers outside the optimizer (U08's `Borrows`, and any
lane that wants a function's references), which the optimizer itself no
longer reads (0004 §2.7). Declarations after the cutover:

```cpp
namespace idr {
class References {
public:
  struct Site { idr::FuncOp target; mlir::Operation *at; };
  References(mlir::Operation *module, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;
  llvm::ArrayRef<idr::FuncOp> functions() const;
  llvm::ArrayRef<Site> of(idr::FuncOp fn) const;
  bool hasCall(idr::FuncOp fn) const;
  int64_t ops(idr::FuncOp fn) const;
  llvm::ArrayRef<llvm::SmallVector<idr::FuncOp>> components() const;
  bool isRecursive(idr::FuncOp fn) const;
};
void walkStoredAttributes(mlir::Operation *op, llvm::function_ref<void(mlir::Attribute)> visit);
} // namespace idr
```

A site is every symbol reference in an op's stored attributes (inherent
and discardable, `walkStoredAttributes`) that the module's table resolves
to an `idr.func`: a call's callee, a closure's or suspension's label, a
constant's, a label constructor's (C06 postcondition 2: named by its
label), a dispatch match's case. Deleted: `callsUnknown` (the world is
closed, D7: every symbol resolves) and `closureLabel` (it read `idr.data`;
a label constructor's name is its function's symbol, C01 §6, C02 §1, so a
reader resolves the name or asks `DataType::isLabel`). `ops` equals
`inlineSize`.

### 9. `include/idr/Analysis/Holds.h`

API unchanged (`mayHoldWorld`, `mayHoldClosure`, `Holds.h:26-32`),
computed once before the optimizer and read frozen (D47); its walk reads
C01's identified types through `TypeGraph` instead of `idr.data`
(`Holds.cpp:48-69`). `mayHoldClosure` is true for a closure, a sum of
kind closures (C01), or data with a field that may.

### 10. Invariants

- Each node's first step runs once (`NodeAction` begins once per node).
- A node reads another function's body only when that function is final;
  a final function is never written again; no worker reads the module's
  top-level list, a map of section 3 or the analysis manager's children
  while one changes.
- No count, round, fixpoint or budget refuses a program: the cap and C09's
  key budget stop optimizing; a broken invariant is an internal error.
- No fingerprint, seed mark, discardable attribute or counter-made name
  exists in the ready set or its inner pipeline.
