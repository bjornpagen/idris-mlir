## C10 Effects and constants summaries

Producer: U05. The one effects summary (0004 D16, D34, D38) and the
interprocedural constants summary (D16, §4 stage 9): their C++
declarations, who calls each and when, the two passes that run them, and
the invariants every other lane may rely on. Paths are under
`foreign/idr/` unless named; `M/` is `.toolchain/build/llvm-project/mlir`.
Line numbers are the tree at a3e61f3a.

### 1. What replaces what

Today effects are computed three ways: the `idr::Effects` analysis with
idr-effects (`include/idr/Analysis/Effects.h:26-72`,
`lib/Analysis/Effects.cpp:66-101`, `lib/Transforms/Effects/Effects.cpp:63-118`),
the by-name walk (`lib/Transforms/Defunctionalize/ByName.cpp:30-89`), and a
clone's first facts (`lib/Transforms/Specialize/Clones.cpp:49-66`).
Constants cross calls only through module SCCP in every round
(`lib/Transforms/Simplify/Round.cpp:56`). After the cutover:

| Concept | One home (file, owner U05) | Called by |
| --- | --- | --- |
| What a run of a function may do, before the conversion, with the observable bit | `idr::ModuleEffects` (`include/idr/Analysis/Effects.h`, `lib/Analysis/Effects.cpp`) | U02's idr-defunctionalize, right after its label solve |
| Which memo labels are `by_name` | `idr::ModuleEffects::byName` (same files) | U02, when it sets a memo sum's body (C01) |
| A component's entries and call-site effects in the ready set | `idr::writeCallEffectsOnReady`, `idr::writeEntriesOnFinal` (same files) | U03's ready set; idr-effects |
| What a call returns, per result | `idr::ConstantSummaries` (`include/idr/Analysis/Constants.h`, `lib/Analysis/Constants.cpp`) | U03's ready set (publish); idr-constants (lookup) |
| A call's results in a function's own solve | `idr::SummarizedConstantPropagation` (same files), upstream's `visitExternalCall` hook | idr-constants |
| idr-effects, the test entry | `lib/Transforms/Effects/Effects.cpp` | `idris-mlir-opt`, U17's tests |
| idr-constants, the inner pipeline's last step | `lib/Transforms/Effects/Constants.cpp` (new) | U03's inner pipeline |

`lib/Transforms/Defunctionalize/ByName.cpp` is deleted; its decision is
`ModuleEffects::byName`. Nothing else computes an entry: a function the
ready set makes (a specialization node) has no `effects` until
`writeEntriesOnFinal` writes its first.

### 2. The lattice and the graph

A summary is what a run of a function may do:
- `effect`, the dialect's `idr::Effect` bits (`include/idr/IR/IdrAttrs.td:151-174`):
  `io`, `crash`, `diverge`;
- `observable`, whether the run may perform an effect the program's
  outside observes. It is narrower than `io`: an array, a buffer and a
  forged world are `io` and not observable (`IdrInterfaces.td:75-84`).

A function's own part, from one walk of its body: `diverge` unless it has
`total`; `crash` where an op's `MayCrashOpInterface::getCrashCause()` is
set; `io` where it holds an `idr.world.new`, or where a parameter's type
may hold a world (`Holds::mayHoldWorld`, `include/idr/Analysis/Holds.h:28`);
`observable` where an op's class carries the `ObservableIO` trait. This is
today's `local` (`lib/Analysis/Effects.cpp:48-62`) with the observable bit
added and the world parameter moved into it.

The graph: a function runs
- the callee of each `idr.call` in its body (a *call* run);
- before the conversion, each label of the key of an `idr.apply`'s callee
  (a call run), and each label of the key of an `idr.force`'s cell (a
  *force* run), both from U02's label solve through `LabelsRun`;
- after the conversion, each label of the memo sum an `idr.force` reads
  (a force run): with `DataType data = idr::dataTypeOf(operand type)`, the
  `idr.func` named `data.getCtors()[tag].name` for every `tag` where
  `data.isLabel(tag)` (C01 §3, §6: a label constructor's name is its
  function's symbol name). No `idr.apply`, closure type or lazy type
  exists after the conversion (C06 postcondition 1).

Making a closure or a suspension runs nothing: what its label may do
counts where it is applied or forced. That replaces today's counting at
the maker and at the call that is passed it (`Effects::passed`,
`lib/Analysis/Effects.cpp:151-187`): after defunctionalization no closure is
passed to a call, so a call's effects are its callee's (D38).

Transfer along a run to a target `t`:
- `effect`: `t`'s whole `effect`, for call and force runs alike (forcing a
  cell may run its label);
- `observable`: `t.observable` along a call run; along a force run
  `t.observable` and `t` not static, that is, `byName(t)`. A cell that
  keeps its value performs its effect at its first force alone, so
  forcing it again repeats nothing; a `by_name` cell runs its label at
  every force.

A label is *static* when an `idr.constant` anywhere in the module holds
`#idr.closure<@t, captures>` with as many captures as `t` has parameters:
a suspension written as a constant names one value of the program,
evaluated once (today's rule, `ByName.cpp:57-69`, read before the
conversion: the frontend writes a static suspension as a closure constant
of a lazy type that captures every parameter, as
`SuspendOp::verifySymbolUses` demands of a suspension, `lib/IR/OpsClosures.cpp:195-217`).

`byName(t)` = `t.observable` and `t` not static.

The solve is bottom-up over the strongly connected components of the
graph, callees first (`idr::components`, `include/idr/Support/Scc.h:23-24`):
a component's summary is the or of every member's own part and of every
run from a member to a target outside it, through its transfer; each
member gets the component's summary. It is one pass, since the lattice is
finite and the transfers are monotone.

### 3. `include/idr/Analysis/Effects.h`

```cpp
#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Holds.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

// What an absent `effects` means: everything a call may do. No writer
// stores it; a writer removes the attribute instead.
constexpr idr::Effect anyEffect = idr::Effect::io | idr::Effect::crash | idr::Effect::diverge;

// What a run of a function may do.
struct EffectSummary {
  idr::Effect effect = idr::Effect::none;
  bool observable = false;
  bool operator==(const EffectSummary &other) const = default;
};

// Before defunctionalization's conversion: appends to `labels` the label
// functions `op`, an idr.apply or an idr.force, may run, those of the key
// of its callee or its cell. Called from worker threads; it reads only.
using LabelsRun =
    llvm::function_ref<void(mlir::Operation *op, llvm::SmallVectorImpl<idr::FuncOp> &labels)>;

// The effects summary of a whole module before the conversion (section 2),
// solved in the constructor, each body walked on a worker into its own
// slot, the components summed serially. It never changes afterwards.
class ModuleEffects {
public:
  ModuleEffects(mlir::ModuleOp module, const Holds &holds, const mlir::SymbolTable &symbols,
                LabelsRun labelsRun);

  // Whether `label`, a label of a memo key, runs at every force: a run of
  // it may be observed, and it is not static.
  bool byName(idr::FuncOp label) const;

  // Writes every function's `effect` as its `effects`, the full set as no
  // attribute, and every idr.call its callee's, so the module verifies
  // under C02 §4's equality. Called once the conversion has made its calls.
  void writeEntries() const;

private:
  const mlir::SymbolTable &symbols;
  llvm::SmallVector<idr::FuncOp> functions;              // module order
  llvm::DenseMap<mlir::Operation *, unsigned> positions; // into `functions`
  llvm::SmallVector<EffectSummary> summaries;            // by position
  llvm::DenseSet<mlir::Operation *> statics;              // static labels
};

// After the conversion: appends to `labels` the label functions `force`
// may run, the label constructors of the memo sum its cell is (section 2).
// The ready set's graph takes these edges from it.
void forcedLabels(idr::ForceOp force, const mlir::SymbolTable &symbols,
                  llvm::SmallVectorImpl<idr::FuncOp> &labels);

// D38's first moment. When `component`, a strongly connected component of
// the ready set's graph, becomes ready: every idr.call in a member whose
// callee is outside `component` gets that callee's entry as its
// `effects`, absent for absent. Every such callee is final then.
void writeCallEffectsOnReady(llvm::ArrayRef<idr::FuncOp> component,
                             const mlir::SymbolTable &symbols);

// The ready set's recomputation and D38's second moment. When every member
// of `component` is final: each member's entry from its final body
// (section 2, the effect bits only, a run outside the component reading the
// target's `effects`), written on every member; then every idr.call in a
// member whose callee is a member gets that entry.
void writeEntriesOnFinal(llvm::ArrayRef<idr::FuncOp> component, const Holds &holds,
                         const mlir::SymbolTable &symbols);

} // namespace idr
```

Fixed choices:
- `byName` takes only a function of the module the constructor read; any
  other is an internal error (an assertion).
- A callee or label name that the symbol table does not resolve is an
  internal error (an assertion): the closed world (C03) makes every callee
  an `idr.func` of the module with a body.
- Writing an entry or a call's `effects` uses the generated accessors
  (`setEffectsAttr`, `removeEffectsAttr`); an equal value is not rewritten.
  The full set is always the attribute's absence, so equal entries are
  equal attributes and D38's equality is a pointer comparison.
- `writeCallEffectsOnReady` and `writeEntriesOnFinal` write only the ops of
  `component`'s members and read only their bodies, the targets' `effects`
  and the symbol table, so the ready set may run them for disjoint
  components on different threads.
- Neither ever grows an entry by design: inlining, specialization and
  cleanup only remove what a body runs. Nothing checks it; determinism at
  1, 2 and 8 threads and the call-site verifier (C02) are the checks.

### 4. `include/idr/Analysis/Constants.h`

```cpp
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/IR/Operation.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <shared_mutex>

namespace idr {

// What a call of a function returns, one lattice value per result:
// uninitialized where the function has no return, a constant, or unknown.
using ConstantResults = llvm::SmallVector<mlir::dataflow::ConstantValue, 1>;

// The constants summaries of one run of the ready set, built empty by the
// module's analysis manager. The ready set publishes a component's when the
// component is final; idr-constants reads them from any thread.
class ConstantSummaries {
public:
  explicit ConstantSummaries(mlir::Operation *module);

  // The published results of the function named `callee`, or none while
  // its component is not final.
  std::optional<ConstantResults> lookup(mlir::StringAttr callee) const;

  // When every member of `component` is final: what each returns, read from
  // its final body, published for its callers.
  void publish(llvm::ArrayRef<idr::FuncOp> component);

private:
  mutable std::shared_mutex mutex;
  llvm::DenseMap<mlir::StringAttr, ConstantResults> published;
};

// Upstream's sparse constant propagation on one function, with a call's
// results taken from its callee's published summary.
class SummarizedConstantPropagation : public mlir::dataflow::SparseConstantPropagation {
public:
  SummarizedConstantPropagation(mlir::DataFlowSolver &solver, const ConstantSummaries &summaries);

  void visitExternalCall(
      mlir::CallOpInterface call,
      llvm::ArrayRef<const mlir::dataflow::Lattice<mlir::dataflow::ConstantValue> *> arguments,
      llvm::ArrayRef<mlir::dataflow::Lattice<mlir::dataflow::ConstantValue> *> results) override;

private:
  const ConstantSummaries &summaries;
};

} // namespace idr
```

Fixed choices:
- The solve is upstream's (`M/include/mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h:93-104`)
  with `mlir::dataflow::DeadCodeAnalysis`, on one `idr.func`, with
  `DataFlowConfig().setInterprocedural(false)`: every call goes to
  `visitExternalCall` (`M/lib/Analysis/DataFlow/SparseAnalysis.cpp:229-243`,
  the hook at `M/include/mlir/Analysis/DataFlow/SparseAnalysis.h:316-321`),
  and no symbol of the module is resolved (`DeadCodeAnalysis.cpp:410-417`:
  an `idr.func` holds no symbol table).
- `visitExternalCall`: an `idr.call` whose callee has published results
  joins each result's lattice with the summary's value at its position;
  every other call sets its results to the entry state, as upstream's
  default does. A call to a member of the caller's own component never
  finds a published summary, since the component is not final while any
  member runs, so the answer does not depend on the order of the members.
- `publish` reads each member's final body, whose last step was
  idr-constants: result `i` is the join, over every `idr.return` of the
  body, of `ConstantValue(c, d)` where the operand is defined by a
  constant-like op (`m_Constant`) holding `c` in dialect `d`, and of
  unknown otherwise; with no `idr.return`, every result is
  uninitialized. The solve's rewrite has already replaced every operand
  its lattice holds constant, so this is the solve's answer but where a
  return sits in a block the solve found dead and nothing erased yet,
  which reads as unknown.
- The table is keyed by symbol name; names do not change inside the ready
  set (they come from content, D18), and a dropped function's summary is
  never read again. Lookups share the mutex; `publish` takes it alone.
- What every caller passes is not summarized (0004 §4 stage 9):
  specialization (C09) is how a static argument reaches a callee.

### 5. The passes

Declared by U06 in `Passes.td` (C12), both in
`include/idr/Transforms/Effects.h` (`GEN_PASS_DECL_IDREFFECTS`,
`GEN_PASS_DECL_IDRCONSTANTS`), defined in U05's units.

`IdrEffects`, `idr-effects`, anchor `::mlir::ModuleOp`, statistics
`numIO "io"`, `numCrash "crash"`, `numDiverge "diverge"` (functions whose
entry holds the bit), no dependent dialect, unit
`lib/Transforms/Effects/Effects.cpp`. On a defunctionalized module: the
graph of section 2 after the conversion, its components callees first,
and for each, `writeCallEffectsOnReady` then `writeEntriesOnFinal`: the
ready set's writes with no optimization between them. A module that still
holds an `idr.apply` or forces an `!idr.lazy` value is an error at that op
("idr-effects runs on a defunctionalized module"). Description for U06:

> Writes `effects` on every `idr.func` and every `idr.call` of a
> defunctionalized module, as the ready set of idr-optimize writes them:
> bottom-up over the components of the graph in which a function runs its
> calls' callees and the labels of the memo sums it forces. A function's
> entry is what a run of it may do: `io` where it takes a world, as a
> parameter or in data one holds, or forges one; `crash` where it reaches
> an op that may crash; `diverge` where it reaches a function without
> `total`, itself included. A call's `effects` is its callee's. The full
> set is no attribute. A module that still applies a closure or forces a
> suspension is refused: only defunctionalization's label solve knows
> what those run.

`IdrConstants`, `idr-constants`, anchor `::idr::FuncOp`, statistic
`numConstants "constants"` (values replaced by a constant), dependent
dialect `::mlir::arith::ArithDialect`, unit
`lib/Transforms/Effects/Constants.cpp`. It reads
`getCachedParentAnalysis<idr::ConstantSummaries>()`; without it, the error
"internal error: idr-constants runs inside idr-optimize, which holds the
constants summaries of its module" and pass failure, as idr-identity does
today (`lib/Transforms/Identity/Identity.cpp:50-55`). It solves, then
replaces every value whose lattice holds a constant with one an
`mlir::OperationFolder` materializes in the lattice's dialect, and erases an op all of whose results were replaced when
`mlir::wouldOpBeTriviallyDead` holds; it marks every analysis preserved
when it replaced nothing. The rewrite is U05's own code: upstream's is a
static function of `M/lib/Transforms/SCCP.cpp:38-122`. Description for U06:

> Sparse conditional constant propagation through one function, a call's
> results taken from its callee's summary: what the callee returns, read
> from its final body once its component is final. A step of
> idr-optimize's inner pipeline, the last, after int-range-optimizations,
> so that a function's final body states its summary; it reads the
> summaries idr-optimize holds and runs nowhere else.

### 6. Invariants other lanes rely on

1. After idr-defunctionalize, every `idr.func` carries its stage-4 entry
   and every `idr.call` its callee's, from `ModuleEffects::writeEntries`,
   the full set as no attribute; until then neither carries any, which
   C02 §4's equality accepts (absence is every effect on both sides).
2. In the ready set a call takes its callee's final entry when its caller
   becomes ready (a callee outside the component) or when the component
   finishes (a member), D38; an entry is rewritten once, when its
   component finishes, and never after; a stage-4 entry is an upper bound
   of the final one, so a call or a member read before then is read
   soundly. Wherever the module is verified (C03 §2: at the end of a
   module pass), every call's `effects` equals its callee's entry.
3. `by_name` in a memo sum's body (C01) is `ModuleEffects::byName` of the
   constructor's label, decided before the body is set (D29, D34).
4. A constants summary is read only after its component is published, so
   every solve's answer is a function of final bodies.

### 7. Consumers by lane

- U02: in idr-defunctionalize, after the label solve and before any sum is
  made, constructs `idr::ModuleEffects effects(module, holds, symbols,
  labelsRun)` with `getAnalysis<idr::Holds>()`, the module's
  `mlir::SymbolTable`, and a `LabelsRun` reading C06's solve; sets each
  memo constructor's `by_name` from `effects.byName(label)`; calls
  `effects.writeEntries()` once, after the per-function conversion, so
  that the dispatch calls it makes get their callees' entries (the
  conversion keeps each `idr.func` op and its inherent attributes,
  `Patterns.cpp:264-280` today); deletes `markByName`'s
  declaration (`include/idr/Transforms/Defunctionalize.h:269`) and its call
  (`Defunctionalize/Pass.cpp:105`).
- U03: the ready set's graph has a force run's edges as well as the calls'
  (section 2): for every `idr.force` in a function, an edge to each label
  `idr::forcedLabels` appends, beside `mlir::CallGraph`'s call edges, so a memo label
  is final before a function that forces it and its entry is read at one
  value on every schedule. The driver takes `getAnalysis<idr::ConstantSummaries>()`
  beside `Holds` before any task runs, so idr-constants finds it cached.
  With the members' functions (`Scc::members`' `Node::fn`, in member order)
  and the module's symbol table, which changes only at a quiescent point
  (C07 §5.2), the scheduler calls `writeCallEffectsOnReady(members,
  symbols)` when a component becomes ready, before its inline decisions;
  `writeEntriesOnFinal(members, holds, symbols)` and then
  `summaries.publish(members)` when it finishes, both before any member
  becomes final; its inner pipeline ends with `idr::createIdrConstants()`,
  after `int-range-optimizations`. These replace the hooks C07 §6 names
  for C10 (`idr::effects::atReady`, `idr::effects::atFinal`,
  `idr::constants::atFinal`, `idr::constants::createSolvePass`) and
  `Node::constants`: a hook taking C07's `Scc` and `ReadySet` would make
  U05's libraries call `ReadySet::nodeOf`, defined in U03's, while U03's
  call U05's, a cycle of libraries; and idr-effects, which has no ready
  set, runs the same two functions.
- U04: deletes `giveFirstFacts` (`Clones.cpp:49-66`) and its call; a
  redirected call takes its node's entry, read from the node's record
  once the node is final, as `Redirect.cpp:31-34` reads a clone's today;
  `idr::anyEffect` stays where `Redirect.cpp` reads it.
- U01: `CallOp::verifySymbolUses` checks `mayDo(call) == mayDo(callee)`
  (C02 §4); the memo sum's body gives each label constructor's name, its
  function's symbol (C01 §3, §6).
- U06: declares both passes as section 5 says (C12).
- U09: the calls `.acc` and `.trmc` make copy the effects of the call or
  function they replace, as `Accumulate.cpp:51, 140` and `Trmc.cpp:65` do
  today; the copy's function keeps its origin's entry.
- U17: idr-effects tests run on defunctionalized modules; idr-constants is
  tested through idr-optimize; the fixture of D38 (a call to a pure callee
  whose result is unused is gone after idr-optimize).
