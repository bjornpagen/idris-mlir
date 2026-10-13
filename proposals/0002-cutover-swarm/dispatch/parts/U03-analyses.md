# U03 — References, Effects and Holds as analyses, TypeGraph in IdrIR, one SCC utility; idr-effects writes facts on functions and calls

Mandatory findings: F-state-3 F-state-4 F-state-5 F-pass-7

## Permitted outcome

1. **`idr::References`**, an analysis on the module: per `idr.func`, the
   sites that name a function, its op count, whether it calls, whether
   it calls something unknown, and the strongly connected components of
   that graph. One parallel walk per function, then one serial merge.
   Every consumer reads it through the pass manager. Mandatory.
2. **`idr::Effects`**, an analysis on the module: io, crash and diverge
   per function, from `References`, `Holds` and one parallel walk of each
   body, propagated once over `References::components()`. It keeps no
   state outside the analysis manager. Mandatory.
3. **`idr::Holds`**, an analysis on the module: `mayHoldWorld(Type)` and
   `mayHoldClosure(Type)`, two bits per declaration computed in its
   constructor from `TypeGraph`, immutable, read from any thread.
   Mandatory.
4. **`idr::TypeGraph`** in `IdrIR`: containment among declarations and
   arrays, its components, the knot verdicts and `containsItself()`. The
   module verifier constructs it directly; passes take it from the
   manager. Mandatory.
5. **One strongly-connected-components utility** in `IdrSupport`:
   `idr::components` and `idr::stronglyConnected`, today's
   `IDR/Graph/Scc.cppm` unchanged in meaning, the one source of
   components for every graph of ours. Mandatory.
6. **`idr-effects`** as a `ModuleOp` pass in `IdrEffects`: it writes
   `effects` on every `idr.func` from `Effects` and on every `idr.call`
   from its callee's effects joined with what the closures it is passed
   may do, in parallel per function, removing the attribute where the
   value is the full set. It marks `References`, `Effects`, `Holds`,
   `TypeGraph`, `Layouts` and `SymbolTable` preserved when it wrote, and
   everything when it wrote nothing. Mandatory.
7. **`IDR/Graph` and `IDR/Facts` deleted**, every unit and both
   `CMakeLists.txt`, with each unit that is not an analysis named for
   the lane that takes its logic (Delete). Mandatory.

The lane writes no consumer. Each consumer's adaptation is named by lane
in Outputs so that each lane finds its call in its own dispatch.

## Owner / exclusive writes

New:

- `INC/Analysis/References.h`, `IDR/Analysis/References.cpp`
  (`IdrAnalysis`)
- `INC/Analysis/Effects.h`, `IDR/Analysis/Effects.cpp` (`IdrAnalysis`)
- `INC/Analysis/Holds.h`, `IDR/Analysis/Holds.cpp` (`IdrAnalysis`)
- `INC/IR/TypeGraph.h`, `IDR/IR/TypeGraph.cpp` (`IdrIR`)
- `INC/Support/Scc.h`, `IDR/Support/Scc.cpp` (`IdrSupport`)
- `IDR/Transforms/Effects` (one unit, `IDR/Transforms/Effects/Effects.cpp`,
  the pass) and `INC/Transforms/Effects.h` (`IdrEffects`)

Deleted:

- `IDR/Graph`, every file, `IDR/Graph/CMakeLists.txt` included.
- `IDR/Facts`, every file, `IDR/Facts/CMakeLists.txt` included.

**Excluded:**

- `INC/Transforms/Passes.td`, `INC/IR/IdrOps.td`: the coordinator's,
  written from R01 and R40. `IdrEffects`'s text there is R40's.
- `IDR/Analysis/CMakeLists.txt`, `IDR/IR/CMakeLists.txt`,
  `IDR/Support/CMakeLists.txt`, `IDR/Transforms/CMakeLists.txt`: the
  coordinator's, filled from the unit list this lane reports.
- `IDR/Verify/Cycles.cppm`, `IDR/Verify/Program.cppm`: U02 deletes them.
  `Cycles.cppm:31-128` is the source of `TypeGraph`; the knot's
  rendering (`Cycles.cppm:130-217`) and the message of
  `Program.cppm:127-128` stay with the module verifier under
  `IDR/IR/Verify`, U02's.
- `IDR/IR/Func` (U02): `CallOp::getEffects`, `CallOp::verifySymbolUses`
  (the containment rule), `FuncOp::verify`.
- `INC/IR/Symbols.h` (U01): the symbol helpers this lane calls.
- `INC/IR/Layout.h` (U10): `idr::Layouts`, which `idr-effects` names
  only to preserve it.
- `INC/Analysis/Tail.h`, `IDR/Analysis/Tail.cpp` (U09): the tail-position
  predicates of `IDR/Graph`.
- `INC/Transforms/Narrow.h` (U11): `runsAtMostOnce`.
- `IDR/Transforms/Simplify` (U04, `idr-loop-breakers`, `idr-contify`,
  `idr-round-facts`), `IDR/Transforms/Inline` and
  `IDR/Analysis/Inline.cpp` (U05), `IDR/Analysis/Specialize.cpp` and
  `IDR/Transforms/Specialize` (U06), `IDR/Transforms/Defunctionalize`
  (U07), `IDR/Analysis/Identities.cpp` (U13), `IDR/Transforms/Expect`
  (U15): the consumers.
- `IDR/Dialect/CMakeLists.txt`, `IDR/Ownership/CMakeLists.txt`: the
  coordinator's to delete.
- `T/idr`: U21 writes every fixture.

## Read first

- `contracts.md`:
  - C0 (the pin: confirm every upstream signature recalled here).
  - C1.1: the `TypeGraph`, `IDR/Graph`, `IDR/Facts` and
    `IDR/Facts/Pass.cc` rows; the rules (headers, includes, links, the
    CMake lists and the deletion table, unit size, state).
  - C1.2, "Functions": `Idr_FuncOp` (its leading comment: effects absent
    means anything; no writer stores the full set) and `Idr_CallOp`
    (`OptionalAttr<Idr_EffectAttr>:$effects`, its comment).
  - C1.3: the `idr-effects`, `idr-loop-breakers`, `idr-round-facts` rows.
  - C2.0 (every bullet; the third lists the helpers of
    `INC/IR/Symbols.h`; the sixth, nests preserve nothing).
  - C2.1, all of it: the table, Invalidation, Obligations, Construction,
    the reading rule, the components utility.
  - C2.2 (the call's effects; first facts of a new function).
  - C3.2 (the round), C4 (the module verifier's use of `TypeGraph`),
    C9.1 (the call-effects fixture).
  - C10: R01, R07, R09, R11, R12, R14, R15, R29, R40, R43, R44, R47.
- `findings.md` F-state-3, F-state-4, F-state-5, F-pass-7; F-state-1
  and F-state-2 for the mechanisms the analyses replace.
- `IDR/Graph/References.cppm`: :19-44 (the API), :50-81 (the walk;
  :59-77 the four kinds it records today).
- `IDR/Graph/Scc.cppm`: :1-8 (why LLVM's iterative Tarjan), :13-28 (the
  private `Vertex` and its `GraphTraits`), :36-57 (`components`),
  :64-85 (`stronglyConnected`).
- `IDR/Graph/SymbolUses.cppm` :15-23, `RefersTo.cppm` :15-21,
  `FieldsOf.cppm`, `IsSelfCall.cppm`, `InTailPosition.cppm`,
  `InTailPositionModuloConstructor.cppm`, `ModuloAt.cppm`,
  `PassesOnPrevious.cppm`, `Trips.cppm`: what leaves the lane (Delete).
- `IDR/Facts/Infer.cppm`: :24-53 (the rules of io, crash and diverge;
  :38-43 a closure's effect counts where it is passed), :65-122 (the
  stamps), :128-203 (`Found`, `local`; :160-203 the walk), :205-227
  (`propagate`), :238-325 (`run`; :285-301 the table, the scope, the
  memo and the per-type world cache; :311-321 io from a world parameter
  after propagation).
- `IDR/Facts/Pass.cc`, all of it: :17-21 the state and its copy
  constructor, :22-36 the run, :38 the member.
- `IDR/Facts/Effects.cppm` :12-45, `Of.cppm` :16-24, `Record.cppm`
  :15-22, `Inherit.cppm` :22-28, `Inlined.cppm` :14-17,
  `BreaksLast.cppm` :12, `TakesWorld.cppm` :14-17, `ClosureLabel.cppm`
  :16-19, `Passed.cppm` :19-38 and :51-87 (the type gate at :57),
  `Contained.cppm` :25-65, `MayHoldWorld.cppm` :19-22,
  `MayHoldClosure.cppm` :19-23, `CallEffects.cc` :1-26 (the resource
  model) and :38-69.
- `IDR/Verify/Cycles.cppm` :1-8 and :19-30 (why only an array closes a knot, and
  why the check is partial before defunctionalization), :31-128 (the
  graph class that becomes `TypeGraph`).
- `IDR/Verify/Program.cppm` :118-144 (the second DFS that
  `containsItself` replaces; the message at :127-128).
- `IDR/Dialect/Symbols/LookupSymbol.cc` :119-126 (a lookup without a
  table scans the module) and the memo unit beside it, :15-120 (what
  `Holds` answers, and why its answers were per thread).
- The consumers, at their use sites: `IDR/Simplify/Breakers.cppm`
  :59-124; `IDR/Inline/Decisions.cppm` :37-98; `IDR/Inline/Pass.cc`
  :34-43 and :57; `IDR/Specialize/BindingTimes.cppm` :101-131;
  `IDR/Specialize/Specializer.cppm` :73-104; `IDR/Specialize/Raise.cppm`
  :164, :178, :218; `IDR/Specialize/Specialization.cppm` :247;
  `IDR/Identity/Rebuilds.cppm` :228; `IDR/Simplify/Contify.cppm` :93;
  `IDR/Expect/Facts.cppm` :18-30; `IDR/Expect/BreaksLast.cppm` :27-32;
  `IDR/Defunctionalize/Decided.cppm` :102-106; `IDR/Dialect/Ops/Lazy.cc`
  :83.
- `INC/IdrOps.td` :429-439 (`Idr_Effect`, `Idr_EffectAttr`);
  `INC/Passes.td` :8-31 (`IdrEffects`), :111-125 (`IdrLoopBreakers`).
- `sources/docs/mlir/docs/PassManagement.md` "Analysis Management"
  (:214-325): the two constructor forms (:223-226), `isInvalidated`
  (:231-238), `getCachedParentAnalysis` (:252-253), every analysis
  invalidated unless marked (:301-306); "Tree Display Mode"
  (:1168-1195) for the `(A)` rows.
- At the pin, `mlir/include/mlir/Pass/AnalysisManager.h`
  (`AnalysisModel`, `PreservedAnalyses::isPreserved`, `AnalysisMap::invalidate`),
  `mlir/include/mlir/IR/Threading.h` (`parallelForEach`),
  `mlir/include/mlir/IR/SymbolTable.h` (`SymbolTable::lookup`), and the
  ODS accessors generated for an `OptionalAttr` (`get<Name>Attr`,
  `set<Name>Attr`, `remove<Name>Attr`).
- `T/idr/effects/*.mlir` (their RUN lines), `T/idr/canon/unused-call.mlir`
  :1-3, `T/idr/verify/cycle.mlir` :1-3, `T/idr/verify/module.mlir` (the
  contains-itself case).

## Fixed decisions

**Where each class lives.** `References`, `Effects` and `Holds` are in
namespace `idr`, one header each under `INC/Analysis`, one `.cpp` each
under `IDR/Analysis`, library `IdrAnalysis`. `TypeGraph` is in namespace
`idr`, `INC/IR/TypeGraph.h` and `IDR/IR/TypeGraph.cpp`, library `IdrIR`,
so the module verifier constructs it with no link to `IdrAnalysis`. The
components utility is in namespace `idr`, `INC/Support/Scc.h` and
`IDR/Support/Scc.cpp`, library `IdrSupport`, which includes no header of
the dialect, so `IdrIR` links it.

**Immutable after construction.** Each analysis is built whole in its
constructor and never changes afterwards: no `mutable` member, no lazy
fill, no method that writes. A function pass reads one through
`getCachedParentAnalysis<T>()` from a worker thread, so an analysis that
filled itself on first ask would race. That is why the memo's answers
were per thread (F-state-2), and why these analyses compute everything up
front. A query that is not stored (`Effects::passed`, `TypeGraph::knots`,
`TypeGraph::containsItself`) is a `const` computation over the stored
members and remembers nothing.

**Parallel construction, module-ordered slots.** `References` and
`Effects` compute their per-function parts with `mlir::parallelForEach`
over the indices of the function list (`llvm::seq<size_t>`), one slot
per function in module order, and merge serially in that order. A worker
reads only its own function's body, the `SymbolTable` analysis
(`SymbolTable::lookup` is a read of its map) and analyses already built;
it inserts into no shared container and emits no diagnostic. The merge
and every fixpoint are serial. Results depend on module order and walk
order only, never on the thread count. `Holds` and `TypeGraph` walk the
`idr.data` ops alone, which are few beside the bodies, and stay serial.

**The value of an effect is `idr::Effect`.** The ODS bit enum
(`INC/IdrOps.td:429-439`) is the one form. The three-flag struct
(`IDR/Facts/Effects.cppm:12-45`) held the same fact a second time and
goes. `anyEffect` is the constant `Effect::io | Effect::crash |
Effect::diverge`, defined once in `Effects.h`. A reader tests a bit with
`bitEnumContainsAny`. No writer stores `anyEffect`: it removes the
attribute, and an absent attribute reads as `anyEffect`.

**Invalidation is transitive.** Each `isInvalidated` returns true unless
the analysis and every analysis it reads, directly or through another,
are preserved. For `Effects` that adds `TypeGraph` to C2.1's four,
because it holds a reference to `Holds`, and MLIR erases `Holds` when
`TypeGraph` is not marked even if `Holds` is. No obligation of C2.1
marks one without the other, so the extra test changes nothing for a
pass that keeps them; it keeps `Effects` from holding a dangling
reference under one that does not.

### `References` (`INC/Analysis/References.h`)

```cpp
class References {
public:
  // One reference: `target` is named by `at`, the idr.call, idr.closure,
  // idr.suspend or idr.con that names it, or the op whose attribute holds
  // the constant that does.
  struct Site { idr::FuncOp target; mlir::Operation *at; };
  References(mlir::Operation *module, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;
  llvm::ArrayRef<idr::FuncOp> functions() const;             // every idr.func, module order
  llvm::ArrayRef<Site> of(idr::FuncOp fn) const;             // walk order; empty for one without a body or one it did not see
  bool hasCall(idr::FuncOp fn) const;                         // any CallOpInterface, idr.apply included
  bool callsUnknown(idr::FuncOp fn) const;                    // a call of anything but idr.call or idr.apply, or a name the table lacks
  int64_t ops(idr::FuncOp fn) const;
  llvm::ArrayRef<llvm::SmallVector<idr::FuncOp>> components() const;  // of the graph of the sites, callees first
  bool isRecursive(idr::FuncOp fn) const;                     // on a component of two or more, or names itself
};
// The function a constructor of a sum of closures names: the one rule of a
// closure label, for References' sites and Effects::passed.
mlir::StringAttr closureLabel(mlir::SymbolTable &symbols, mlir::SymbolRefAttr ctor);
```

- **Representation.** The functions are one `SmallVector<idr::FuncOp>`
  in module order and one `DenseMap<mlir::Operation *, unsigned>` from a
  function to its position, built first, serially, so that workers turn
  a resolved target into a position with a read. The sites are one flat
  `SmallVector<Site>` with one offset per function (`of` returns the
  slice), not a map of vectors: one allocation, walked in order by every
  consumer. `hasCall`, `callsUnknown` and `isRecursive` are one
  `llvm::BitVector` each, by position; `ops` is a `SmallVector<int64_t>`.
  `components()` is `SmallVector<SmallVector<idr::FuncOp>>`.
- **What a site is.** What today's two walks record between them: the
  callee of an `idr.call`, of an `idr.closure`, of an `idr.suspend`
  (`References.cppm:59-73`); a `#idr.closure` in any attribute of any op
  (:74-77, `Infer.cppm:195-200`); the label of a constructor of a sum of
  closures, by `idr.con` or by `#idr.con` (`Infer.cppm:174-177`,
  :191-192, :198-199; the rule is `ClosureLabel.cppm:16-19`, now
  `closureLabel`). The last kind is what `Effects` needs and today's
  graph lacked. No sum exists while the round runs (`idr-defunctionalize`
  follows `idr-simplify`, C1.4), so the breakers, the inline decisions
  and the binding times see the graph they see today.
- **One site per `idr.call`, first among its op's sites.** A verified
  module resolves every `idr.call`'s callee (`verifySymbolUses`, C4), so
  every call has its site and `idr-effects` finds every call among the
  sites without a walk.
- `callsUnknown` is `Infer.cppm`'s `unknown` from :168-173 and :193-194:
  a `CallOpInterface` that is neither `idr.call` nor `idr.apply`, or a
  name of any of the five kinds the table lacks. It is kept beside the
  sites so that `Effects` walks no body for it.
- The constructor takes `am.getAnalysis<mlir::SymbolTable>()` and
  resolves every name in it with `lookup<idr::FuncOp>`. It keeps no
  reference to the table after construction. `isInvalidated` returns
  `!pa.isPreserved<References>() || !pa.isPreserved<mlir::SymbolTable>()`.
- `components()` is `idr::components` over the positions, one edge per
  distinct target in first-seen order, computed in the merge. It is the
  graph `BindingTimes` builds today (`BindingTimes.cppm:113-122`) and the
  one `Effects` propagates over. The breakers and the inline decisions
  build their own graphs (one excludes `no_inline` functions and drops
  breakers as it goes, `Breakers.cppm:73-102`; the other counts call
  sites only, `Decisions.cppm:57-70`) from `of()` with
  `idr::components` or `idr::stronglyConnected`.

### `Effects` (`INC/Analysis/Effects.h`)

```cpp
constexpr idr::Effect anyEffect = idr::Effect::io | idr::Effect::crash | idr::Effect::diverge;
class Effects {
public:
  Effects(mlir::Operation *module, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;
  idr::Effect of(idr::FuncOp fn) const;              // what a call of fn may do, from the module as it is; anyEffect for one it did not see
  bool takesWorld(idr::FuncOp fn) const;             // a world in a parameter, or in data one holds
  idr::Effect passed(mlir::Value value) const;       // what the closures `value` holds may do when applied
  static idr::Effect declared(idr::FuncOp fn);       // what the fact on fn says; anyEffect when fn is null, external or unmarked
};
```

- The constructor takes `References`, `Holds` and `mlir::SymbolTable`
  from `am` and keeps a `const` reference to each for `passed`.
  `isInvalidated` returns true unless `Effects`, `References`, `Holds`,
  `TypeGraph` and `mlir::SymbolTable` are all preserved.
- **Representation.** One `DenseMap<mlir::Operation *, unsigned>` from
  a function to its position, a `SmallVector<idr::Effect>` of the
  answers and an `llvm::BitVector` of `takesWorld`, by position.
- **The rules are `Infer.cppm:24-53`, unchanged.** A function without a
  body is `anyEffect`; one without `total` diverges; one whose body holds
  a `MayCrashOpInterface` op with a cause crashes; one whose body holds
  an `idr.world.new` performs io; one that `callsUnknown` is `anyEffect`;
  each reaches what its sites name, and the bits flow from a function to
  those that reach it. io is added where `takesWorld` holds, after the
  flow and not through it (:311-321). `takesWorld` is
  `TakesWorld.cppm:14-17` over `Holds::mayHoldWorld`.
- **One propagation, no worklist.** `propagate` (:205-227) iterates a
  worklist to the least fixpoint. Over `References::components()`,
  callees first, the same fixpoint is one pass: a component's bits are
  the or of its members' local bits and of the bits of every target of
  its members' sites outside it, all of which are final already; every
  member gets them. Linear in sites, the same answer.
- **`passed`** is `Passed.cppm:51-87`: a constant, a closure, a
  constructor of a sum of closures, and a value moved through
  `idr.lin.enter` or `idr.lin.use` hold what they are made of; any other
  value that `Holds::mayHoldClosure` admits is `anyEffect`; a value whose
  type cannot hold a closure adds nothing (:57), now one map lookup. The
  label of a closure is resolved in the `SymbolTable` and read with
  `of`, the analysis's own answer, where today reads the written
  attribute (:19-21); a label the table lacks is `anyEffect`. Its caller
  is `idr-effects`.
- **`declared`** is `Of.cppm:16-24` on `idr.func`'s accessor:
  `fn.getEffectsAttr()`, never a string. It is static because it reads
  the op alone. A pass that runs after `idr-effects` in a round reads it
  for a callee (U06's first facts, U13's identities) and takes the lag
  `T/idr/effects/stale.mlir` :2-6 describes.
- **The per-function reuse goes.** `Infer.cppm:65-122` hashes every op
  of every body into a SHA1 each round to find the bodies that did not
  change, and :238-283 keeps the previous round's answers on the pass
  instance. The manager is the one cache: an analysis is recomputed when
  it is invalidated and not otherwise. When any body changed, every
  function is walked once by `References` and once by `Effects`, in
  parallel, where today every body was walked once, serially, to hash it
  and the changed ones again. The saving the cache bought was the
  propagation and the interface lookups on unchanged bodies, linear in
  the module and small beside one rewrite.

### `Holds` (`INC/Analysis/Holds.h`)

```cpp
class Holds {
public:
  Holds(mlir::Operation *module, mlir::AnalysisManager &am);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;
  bool mayHoldWorld(mlir::Type type) const;
  bool mayHoldClosure(mlir::Type type) const;
};
```

- **Representation.** Two bits per declaration in one
  `DenseMap<mlir::StringAttr, uint8_t>` keyed by the declaration's symbol
  name, as `Contained.cppm` looks a type's declaration up by name. It
  keeps no reference to `TypeGraph` after construction.
- The constructor takes `am.getAnalysis<TypeGraph>()` and walks its
  components callees first. A declaration may hold a world when a field
  of one of its constructors, through its grade, is a world, or when a
  declaration it reaches may; it may hold a closure when such a field is
  `!idr.fn`, when the declaration is a sum of closures, or when one it
  reaches may. Every member of a component gets the component's bits.
  That is `Contained.cppm:42-63` with the two predicates of
  `MayHoldWorld.cppm:20` and `MayHoldClosure.cppm:20-22`, computed for
  every declaration at once.
- A query removes the grade first (`unrestricted`); a world holds a
  world; `!idr.fn` holds a closure; `!idr.data<@X>` and `!idr.box<@X>`
  answer `@X`'s bits, and false when `@X` is not declared
  (`Contained.cppm:51-54`); everything else, an array included, holds
  neither. An array is where today's walk stops, and `Holds` stops there
  too: it does not follow `TypeGraph`'s array edges (R43 records this as
  a seam for another packet).
- `isInvalidated` returns `!pa.isPreserved<Holds>() || !pa.isPreserved<TypeGraph>()`.

### `TypeGraph` (`INC/IR/TypeGraph.h`)

```cpp
class TypeGraph {
public:
  explicit TypeGraph(mlir::Operation *module);
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;
  unsigned size() const;
  std::optional<unsigned> node(mlir::Type type) const;     // of a declaration's value type or an array type, through its grade
  mlir::Type type(unsigned at) const;
  bool isArray(unsigned at) const;
  idr::DataOp declaration(unsigned at) const;              // null for an array or an undeclared type
  llvm::ArrayRef<unsigned> successors(unsigned at) const;
  llvm::ArrayRef<llvm::SmallVector<unsigned>> components() const;  // callees first, computed once
  llvm::SmallVector<llvm::SmallVector<unsigned>> knots() const;
  llvm::SmallVector<unsigned> cycle(unsigned array, llvm::ArrayRef<unsigned> component) const;
  llvm::SmallVector<idr::DataOp> containsItself() const;
};
```

- It is `Cycles.cppm:31-128` made public and complete: the nodes
  (:33-53, :104-112), the edges through grades (:116-122), `knots`
  (:64-72, with its early return when no node is an array), `cycle`
  (:77-100), the accessors above, and the components, computed once in
  the constructor with `idr::components(successors)`.
- **Node order.** The constructor numbers every declaration first, in
  module order (:33-36), so a declaration's node is its module position
  among the `idr.data` ops; field and element types follow as the list
  grows. Every order-dependent answer follows from that.
- **`containsItself()`** replaces `Program.cppm:118-144`, the verifier's
  second DFS. Over the subgraph whose nodes are the unboxed declarations
  (`declaration(at)` non-null and not `box`) and whose edges are
  `TypeGraph`'s between them, it returns every declaration on a cycle (a
  component of two or more, or a node with an edge to itself), sorted by
  node, which is module order. The edges are `TypeGraph`'s, seen through
  grades: a field `!idr.lin<!idr.data<@X>>` holds `@X` inline as the bare
  field does, so a cycle through it is the same infinite value. Today's
  DFS reads the bare type only (:135); a verdict that changes is reported
  (Escalate if).
- Its constructor takes `(Operation *)` alone: it reads no other
  analysis, the manager accepts that form (PassManagement.md :223-226),
  and the module verifier builds one directly. `isInvalidated` returns
  `!pa.isPreserved<TypeGraph>()`.
- **Readers.** The module verifier (C4, U02) reads `containsItself`,
  `knots`, `cycle`, `type`, `isArray` and `declaration`, and owns the two
  messages and their placement. `Holds` reads `components`, `successors`,
  `declaration` and `isArray`. `idr-defunctionalize`'s boxing (U07)
  reads `node`, `successors`, `components` and `declaration` with
  `getAnalysis<TypeGraph>()`.

### The components utility (`INC/Support/Scc.h`)

```cpp
llvm::SmallVector<llvm::SmallVector<unsigned>> components(llvm::ArrayRef<llvm::SmallVector<unsigned>> successors);
template <typename Node>
llvm::SmallVector<llvm::SmallVector<Node>> stronglyConnected(llvm::ArrayRef<Node> nodes, llvm::function_ref<llvm::SmallVector<Node>(Node)> successors);
```

- `Scc.cppm:36-57` and :64-85, unchanged in meaning: callees first, the
  order depending only on node order and successor order.
  `stronglyConnected` is a thin template in the header that numbers the
  nodes and calls `components`; `components` is in `Scc.cpp`.
- `Scc.cpp` keeps today's private `Vertex` and its
  `llvm::GraphTraits<const Vertex *>` (:13-28) in an anonymous namespace
  and walks it with `llvm::scc_begin`: LLVM's iterative Tarjan, so a
  call chain of any depth takes no recursion. It is the one unit of ours
  that does; C2.1's rule sends every other graph here.
- The header includes `llvm/ADT/ArrayRef.h`, `llvm/ADT/DenseMap.h`,
  `llvm/ADT/SmallVector.h` and `llvm/ADT/STLFunctionalExtras.h`, and no
  header of the dialect or of MLIR.

### `idr-effects` (`IDR/Transforms/Effects/Effects.cpp`, `INC/Transforms/Effects.h`)

- A `ModuleOp` pass generated from `IdrEffects` in
  `INC/Transforms/Passes.td` (`GEN_PASS_DEF_IDREFFECTS`), built by its
  generated `createIdrEffects()`, its struct named `IdrEffectsPass` in an
  anonymous namespace so that it does not shadow the analysis. Its three
  statistics `io`, `crash`, `diverge` count the functions whose effects
  have the bit (an absent attribute has all three), every run.
- **The plan is the analyses.** `Effects &effects = getAnalysis<Effects>()`,
  which builds `SymbolTable`, `TypeGraph`, `Holds` and `References`
  through the manager where they are not cached; then
  `const References &refs = getAnalysis<References>()`, cached by now.
  No `runPipeline`, so both references hold for the run.
- **The rewrite, in parallel per function.** Before the loop, the pass
  builds the seven `EffectAttr` values below `anyEffect` once, so no
  worker creates an attribute. Then `mlir::parallelForEach` over the
  positions of `refs.functions()`, each with a slot of four counts and
  a changed flag, and its own `IRRewriter`:
  - the function: `effects.of(fn)`; when it differs from what
    `fn.getEffectsAttr()` holds, `modifyOpInPlace` with `setEffectsAttr`
    of the prebuilt value, or `removeEffectsAttr()` for `anyEffect`;
  - each site of `refs.of(fn)` whose `at` is an `idr.call`: the value
    `effects.of(site.target)` or'd with `effects.passed(arg)` for each of
    the call's arguments, written the same way on the call. `passed`
    stops as soon as the value is `anyEffect`.
  A worker writes only ops of its own function and the function op
  itself, and reads only analyses and its own ops: `of` and `passed`
  read no attribute of another function. The inherent attributes live
  in the op's properties, so a write rebuilds no attribute dictionary.
  The IR it leaves is the same for every thread count.
- **Preservation.** The slots are summed serially into the statistics.
  If no slot changed anything, `markAllAnalysesPreserved()`. Otherwise
  `markAnalysesPreserved<idr::References, idr::Effects, idr::Holds,
  idr::TypeGraph, idr::Layouts, mlir::SymbolTable>()`: the pass changed
  `effects` attributes only, which none of the six reads (`Effects`
  reads bodies, `total` and the analyses). It does not preserve
  `CloneTable`, `BindingTimes` or `Identities`, which read effects.
- `INC/Transforms/Effects.h` holds `#define GEN_PASS_DECL_IDREFFECTS`
  and the include of `idr/Transforms/Passes.h.inc`, and nothing else;
  U14's pipeline includes it for `createIdrEffects()`.
- The pass has no failure path: the analyses always answer.

**The reading rule.** A module pass reads an analysis with
`getAnalysis<T>()`; a function pass with `getCachedParentAnalysis<T>()`
and fails with an internal error naming the analysis when it is absent
(C2.0, C2.1). No consumer constructs `References`, `Effects`, `Holds` or
`TypeGraph` by hand inside a pass; `TypeGraph`'s direct constructor is
for the module verifier, which has no manager.

## Inputs

- `idr::FuncOp`, `idr::CallOp` (C1.2), through their generated
  accessors: `getTotal()`, `getEffectsAttr()`, `setEffectsAttr()`,
  `removeEffectsAttr()`, `isExternal()`, `getBody()`, `getSymNameAttr()`,
  `getArgumentTypes()`; `CallOp::getCalleeAttr()`, `getArgs()`,
  `getEffectsAttr()`, `setEffectsAttr()`, `removeEffectsAttr()`.
- `idr::Effect`, `idr::EffectAttr` (`INC/IR/IdrOps.td`, unchanged).
- `idr/IR/IdrDialect.h` (C1.1): `DataOp` (`getValueType`, `getBox`,
  `getClosures`, `getCtors`), `CtorOp` (`getFieldTypes`), `ClosureOp`,
  `SuspendOp`, `ConOp`, `WorldNewOp`, `LinEnterOp`, `LinUseOp`,
  `ApplyOp`, `ClosureAttr`, `ConAttr`, `FnType`, `DataType`, `BoxType`,
  `MayCrashOpInterface`, `idr::unrestricted`, `idr::isWorld`,
  `idr::isArray`.
- `mlir::SymbolTable` as the analysis every module pass holds (C2.0).
- `idr::Layouts` (`INC/IR/Layout.h`, U10), by name, for
  `markAnalysesPreserved`.
- The `IdrEffects` definition in `INC/Transforms/Passes.td` (R40):
  `ModuleOp`, statistics `io`, `crash`, `diverge`, no `dependentDialects`.
- The round of C3.2, which fixes where each analysis is read.

## Outputs

Declarations, by name: `idr::References` with `idr::closureLabel`
(`INC/Analysis/References.h`); `idr::Effects` with `idr::anyEffect`
(`INC/Analysis/Effects.h`); `idr::Holds` (`INC/Analysis/Holds.h`);
`idr::TypeGraph` (`INC/IR/TypeGraph.h`); `idr::components`,
`idr::stronglyConnected` (`INC/Support/Scc.h`); `createIdrEffects`
through `INC/Transforms/Effects.h`.

Units: `IDR/Analysis/References.cpp`, `IDR/Analysis/Effects.cpp`,
`IDR/Analysis/Holds.cpp` (`IdrAnalysis`); `IDR/IR/TypeGraph.cpp`
(`IdrIR`); `IDR/Support/Scc.cpp` (`IdrSupport`);
`IDR/Transforms/Effects/Effects.cpp` (`IdrEffects`).

Consumers, each adapting in its own lane:

- **U02, the module verifier:** `TypeGraph graph(module)`;
  `graph.containsItself()` for the contains-itself message on the first
  declaration it returns (`Program.cppm:127-128`); `knots()` and
  `cycle()` for the knot message. **`CallOp::getEffects`** reads the
  call's own `effects` (R07) and looks nothing up; **`verifySymbolUses`**
  refuses a call whose effects lacks its callee's. Neither includes a
  header of this lane but `TypeGraph.h`.
- **U04, `idr-loop-breakers`:** `getAnalysis<References>()` in place of
  the table and the walk at `Breakers.cppm:60` and :76; its graph from
  `of()` and `idr::components(edges)` as :73-121; `fn.getBreakLast()`
  for `breaksLast` (:47); `markAnalysesPreserved<References, Effects,
  Holds, TypeGraph, Layouts, SymbolTable>()` when it marked a breaker
  (`no_inline` is read by none of them), `markAllAnalysesPreserved()`
  when it marked none. **`idr-contify`:** `fn.absorb(callee)` (R01) at
  `Contify.cppm:93`. **`idr-round-facts`:** `getAnalysis<Holds>()`
  among the five it computes.
- **U05, `InlineDecisions`:** `am.getAnalysis<References>()` in place of
  `Decisions.cppm:42`; `isa<idr::CallOp>(site.at)` at :59 and :87;
  `idr::stronglyConnected` at :77; the clone callback calls
  `absorb(callee)` (R01). **The force preparation:** `ForceOfOneConstant`'s
  `mayRunWithin` walks `References::of` from the label in place of
  `refersTo` (`Lazy.cc:83`, R06); a new function takes `total` and
  `effects` from the callee whose body it copies.
- **U06, `BindingTimes` and `idr-specialize`:** `References &` from the
  manager in place of `BindingTimes.cppm:101-102` and
  `Specializer.cppm:88`; `References::components()` for :113-122;
  `Interpreter` keeps a `const References &`. A clone's first effects
  (R29, the rule of `Inherit.cppm:22-28`) are `Effects::declared(origin)`
  or'd with `declared(label)` for each label, and `Effect::io` when one
  of the clone's argument types `Holds::mayHoldWorld`; the full set is
  no attribute. `idr-redirect` reads the call's own effects for the
  raise condition and `Holds` for the takes-a-world test (R15), not
  `Effects`.
- **U07, `idr-defunctionalize`:** `getAnalysis<TypeGraph>()` for the
  self-containing slots; `idr::stronglyConnected<Key>` from `Scc.h` at
  `Decided.cppm:102`; its call pattern keeps `effects` (C2.4).
- **U08, U13 (`Recursion`), U15 (`ConstantStack`,
  `EveryCycleHasBreaker`, `BreaksLast`):** `idr::stronglyConnected` from
  `INC/Support/Scc.h` at `Borrow.cppm:119`, `Recursion.cppm:76`,
  `ConstantStack.cppm:74`, `EveryCycleHasBreaker.cppm:27`,
  `BreaksLast.cppm:32`.
- **U13, `Identities`:** the call's own `getEffectsAttr()` or
  `Effects::declared(callee)` with `bitEnumContainsAny(…, Effect::diverge)`
  at `Rebuilds.cppm:228`.
- **U15, `idr-expect`:** `fn.getBreakLast()` at `BreaksLast.cppm:27`;
  `facts-as-marked` (`Facts.cppm:18-30`) asks the call's interface, which
  answers from the attribute `idr-effects` writes.
- **U09, U10, U11, U12:** the predicates and the use index of
  `IDR/Graph`, at the homes R09 and R12 give (Delete).

## Implement

- **`IDR/Support/Scc.cpp`, `INC/Support/Scc.h`.** Move `Scc.cppm` as
  is: the file comment of :1-8 without the names of its users, the
  `Vertex` and its traits, `components` in the `.cpp`, the template in
  the header. Namespace `idr`.
- **`IDR/IR/TypeGraph.cpp`, `INC/IR/TypeGraph.h`.** `Cycles.cppm:31-128`
  as a public class over `mlir::Operation *` (cast to `ModuleOp`): the
  node list grows while it is read (:38-52); an edge goes through
  `unrestricted` to a `DataType`, a `BoxType` or an array (:116-122);
  `components()` once in the constructor; `node(Type)` const applies
  `unrestricted` and reads the index. `knots` reads the stored
  components instead of recomputing them. `containsItself` builds the
  successor lists of the unboxed-declaration subgraph by position,
  calls `idr::components`, keeps the nodes of each component of two or
  more and of each self-loop, sorts them, and maps them to their
  `DataOp`. The file comment says why only an array closes a knot
  (`Cycles.cppm:1-8` and :19-30). Failure: none; the
  verdicts are the verifier's to render.
- **`IDR/Analysis/References.cpp`.** The constructor: list the
  functions and their positions; then `parallelForEach` over the
  positions, each worker walking its function's body once
  (`References.cppm:50-81` widened to the five kinds): count ops, set
  `hasCall` for any `CallOpInterface`, resolve each name in the
  `SymbolTable` into a `Site` (an `idr.call`'s first), set
  `callsUnknown` for a `CallOpInterface` that is neither `idr.call` nor
  `idr.apply` or a name the table lacks, and keep the distinct target
  positions in first-seen order. Every op's attribute dictionary is
  walked for `#idr.closure` and `#idr.con`, as `Infer.cppm:195-200` does.
  The merge concatenates the slots into the flat site list and its
  offsets, builds the edge lists, calls `idr::components`, and sets
  `isRecursive` from each component of two or more and each self-edge.
  `closureLabel` is `ClosureLabel.cppm:16-19` over
  `symbols.lookup<idr::DataOp>(ctor.getRootReference())`. Failure: none;
  a name the table lacks is `callsUnknown`, not an error.
- **`IDR/Analysis/Holds.cpp`.** From `am.getAnalysis<TypeGraph>()`, the
  components callees first; for each component, the or of its
  declarations' leaf tests (a world; `!idr.fn`; a sum of closures) and
  of the bits already stored for its non-array successors that are
  declarations; each declaration's name gets the bits. The queries as
  in Fixed decisions.
- **`IDR/Analysis/Effects.cpp`.** From `References`, `Holds` and the
  `SymbolTable`: `parallelForEach` over the positions, each worker
  computing its function's local bits (`anyEffect` when external or
  `callsUnknown`, with no walk; otherwise diverge when `!getTotal()`,
  then one walk of the body for a `MayCrashOpInterface` with a cause and
  an `idr.world.new`, interrupted once both bits are set) and its
  `takesWorld` (any argument type `Holds::mayHoldWorld`). The merge
  propagates over `References::components()` as Fixed decisions says,
  then `of = reached | (takesWorld ? io : none)`. `passed` is
  `Passed.cppm:28-38` and :51-87 with the type gate from `Holds`, the
  label by `closureLabel` and the table, and `of` for the label's
  effect. `declared` reads `getEffectsAttr()`.
- **`IDR/Transforms/Effects/Effects.cpp`.** The pass as in Fixed
  decisions. Its file comment says what it writes and why the call
  carries its own fact (an op hook has no table, and a closure's effect
  counts where it is passed); nothing about keeping answers.
- **Headers.** `References.h`, `Effects.h` and `Holds.h` include
  `idr/IR/IdrDialect.h` first among ours, then what they read
  (`Effects.h` includes `References.h` and `Holds.h`; `Holds.cpp`
  includes `idr/IR/TypeGraph.h`), then
  `mlir/Pass/AnalysisManager.h` and `mlir/IR/SymbolTable.h`.
  `TypeGraph.h` includes `idr/IR/IdrDialect.h` and
  `mlir/Pass/AnalysisManager.h`; `TypeGraph.cpp` includes
  `idr/Support/Scc.h`. The pass includes `idr/IR/IdrDialect.h`,
  `idr/Analysis/Effects.h`, `idr/Analysis/References.h`,
  `idr/Analysis/Holds.h`, `idr/IR/TypeGraph.h`, `idr/IR/Layout.h`,
  `idr/Transforms/Effects.h`, `mlir/IR/PatternMatch.h` and
  `mlir/IR/Threading.h`.
- **Links.** `IdrAnalysis` links `IdrIR` (which links `IdrSupport`);
  `IdrEffects` links `IdrAnalysis` and `IdrIR`.
- **Comments** say why in the surrounding density: why the analyses
  are immutable and built in parallel slots; why a sum's constructor is
  a reference; why one pass over the components is the fixpoint; why an
  array stops the hold walk; why the call carries its effects. They
  cite no document.
- Every file at most 400 lines.

## Delete

Every unit of `IDR/Graph` and `IDR/Facts`, each with where its logic
goes:

| Unit | Fate |
| --- | --- |
| `IDR/Graph/Graph.cppm`, `IDR/Graph/CMakeLists.txt` | gone (the module and its list) |
| `IDR/Graph/References.cppm` | `References` |
| `IDR/Graph/Scc.cppm` | `IDR/Support/Scc.cpp`, `INC/Support/Scc.h` |
| `IDR/Graph/RefersTo.cppm` | gone; its users read `References::of` (U04's breakers, U05's `ForceOfOneConstant`) |
| `IDR/Graph/SymbolUses.cppm` | gone; its users build one `mlir::SymbolUserMap` over a `SymbolTableCollection` local to the run (U08, U09's `Returned`, U10's `TailCallPlan`, U12's `Lengths`) |
| `IDR/Graph/InTailPosition.cppm`, `InTailPositionModuloConstructor.cppm`, `ModuloAt.cppm`, `PassesOnPrevious.cppm`, `IsSelfCall.cppm` | `INC/Analysis/Tail.h`, `IDR/Analysis/Tail.cpp` (U09, `idr::tail`), which U08 and U13 include |
| `IDR/Graph/FieldsOf.cppm` | a static of `IdrTail` (U09, `idr-trmc`) |
| `IDR/Graph/Trips.cppm` | `idr::narrow::runsAtMostOnce` in `INC/Transforms/Narrow.h` (U11), which U15 includes |
| `IDR/Facts/Facts.cppm`, `IDR/Facts/CMakeLists.txt` | gone |
| `IDR/Facts/Infer.cppm` | `Effects`; the stamps (:65-122), `Inferred`, `Cache`, `Entry`, `Seen`, `reachesCurrent` (:229-236), the module check (:239-242), the worklist `propagate` (:205-227) and the per-type world cache (:293-300) are gone outright |
| `IDR/Facts/Pass.cc` | `IDR/Transforms/Effects/Effects.cpp`; the `inferred` member (:38) and the copy constructor that reset it (:20) are gone |
| `IDR/Facts/Effects.cppm` | gone; `idr::Effect` is the one form |
| `IDR/Facts/Of.cppm` | `Effects::declared` |
| `IDR/Facts/Record.cppm` | the write in `idr-effects`; no helper writes `effects` for other passes |
| `IDR/Facts/Inherit.cppm` | the specializer's own lines (U06, Outputs) |
| `IDR/Facts/Inlined.cppm` | `FuncOp::absorb` (R01), called by U04 and U05 |
| `IDR/Facts/BreaksLast.cppm` | `getBreakLast()` at the two call sites (U04, U15) |
| `IDR/Facts/TakesWorld.cppm` | `Effects::takesWorld` |
| `IDR/Facts/ClosureLabel.cppm` | `idr::closureLabel` in `References.h` |
| `IDR/Facts/Contained.cppm`, `MayHoldWorld.cppm`, `MayHoldClosure.cppm` | `Holds` |
| `IDR/Facts/Passed.cppm` | `Effects::passed` |
| `IDR/Facts/CallEffects.cc` | gone; the external model on `func.call` and `registerCallEffects` (:66-69) have no place once `idr.call` declares the interface; its resource model is `CallOp::getEffects` (U02), over the call's own attribute |

Mechanisms this lane's analyses retire, deleted where they live:
`HoldMemo` (`IDR/Dialect/Symbols/HoldMemo.cc`, declared in
`INC/Idr.h:527-553`, opened at `Infer.cppm:291`, `Inline/Pass.cc:41`,
`Simplify/Pass.cc:105`, `Canonicalize/Pass.cc:98`; U01 deletes the unit
and the declaration, U04 and U05 the openings in their passes); the
`SymbolScope` opened at `Infer.cppm:290` (deleted with `Infer.cppm`);
the `inferred` state on the effects pass (F-state-3); the per-query
callee and label lookups of `CallEffects.cc:42-45` through
`lookupSymbol` (F-state-5); the `SymbolTable` constructed at
`Breakers.cppm:60`, `Decisions.cppm:42` and `Infer.cppm:289` (F-pass-7).

## NOT TO DO

- Do not keep any form of the stamp cache: no hash of a body, no
  previous-round answers, no `unique_ptr<Cache>`, no member on the pass.
- Do not fill `Holds`, `References`, `Effects` or `TypeGraph` lazily or
  through a `mutable` member, and do not cache a `const` query's answer:
  function passes read them concurrently.
- Do not insert into a shared container, emit a diagnostic or create an
  attribute from a `parallelForEach` worker; do not let a worker of
  `idr-effects` read another function's attributes.
- Do not make `Holds` see through an array.
- Do not write `effects` anywhere but in `idr-effects`, and do not
  export a helper for other passes to write it with. The specializer's
  and the force preparation's first facts are theirs (U06, U05).
- Do not implement `CallOp::getEffects` or `verifySymbolUses`, and do
  not attach an external model to `idr.call` or `func.call` (U02).
- Do not walk a body in `idr-effects`: the calls are `References`'
  sites.
- Do not add an analysis beyond the four, a member to the C2.1 rows
  beyond `closureLabel`, an option to `idr-effects`, or a statistic.
- Do not write the knot or contains-itself diagnostic: the messages and
  their placement are the module verifier's (U02).
- Do not specialize `llvm::GraphTraits` or call `llvm::scc_begin`
  outside `IDR/Support/Scc.cpp`.
- Do not read or write a fact by string: no `getAttr("idr.`,
  `hasAttr("idr.`, `setAttr("idr.` in any file of this lane.
- Do not touch `INC/IR/Symbols.h` (U01), `IDR/IR/Func` and
  `IDR/IR/Verify` (U02), `IDR/Transforms/Simplify` (U04),
  `IDR/Transforms/Inline` (U05), `IDR/Transforms/Specialize` (U06),
  `INC/Analysis/Tail.h` (U09), `INC/IR/Layout.h` (U10),
  `INC/Transforms/Narrow.h` (U11).
- Do not write a fixture; describe the evidence in the handoff for U21.
- Do not keep a `.cppm`, a partition or a `thread_local`.

## Stop and return

Done when: the six headers and six `.cpp` files of Owner / exclusive
writes exist with the APIs of Fixed decisions; `IDR/Graph` and
`IDR/Facts` are gone with their `CMakeLists.txt`; every file is at most
400 lines; `grep -rn 'SHA1\|bodyStamp\|Inferred\|thread_local\|std::atomic\|mutable\|getAttr("idr\.\|scc_begin'`
over the lane's files finds only `scc_begin` in `IDR/Support/Scc.cpp`.

Return:

- the changed paths against the seven outcomes;
- the unit lists: `IdrAnalysis` (`References.cpp`, `Effects.cpp`,
  `Holds.cpp`), `IdrIR` (`TypeGraph.cpp`), `IdrSupport` (`Scc.cpp`),
  `IdrEffects` (`Effects.cpp`), with the links of Implement;
- the names supplied (Outputs);
- `Verification: NotRun (swarm policy)`;
- hub text: none beyond R40 for `IdrEffects`; for
  `IDR/IR/CMakeLists.txt`, whether `IdrIR` links `MLIRPass` for
  `PreservedAnalyses` (shared with `Layouts`), as found at the pin;
- the seams, at least these:
  - `Holds` stops at an array as today (R43);
  - `Effects::isInvalidated` also tests `TypeGraph`, which C2.1's column
    leaves to `Holds`; the contract's column can say "and what those
    read";
  - `closureLabel` is a free function in `References.h`, not in C2.1's
    row;
  - `IDR/Support/Scc.cpp` is the one specialization of `GraphTraits`;
    C2.1's sentence can name it;
  - `containsItself` sees through grades where `Program.cppm:135` did
    not, and its first declaration may differ from the DFS's when the
    first declaration in module order that reaches a cycle is not on it;
  - any pinned signature that differs from the one recalled here
    (`parallelForEach`, the `remove<Name>Attr` accessor,
    `AnalysisMap::invalidate`), with the spelling written.

## Acceptance

- **`T/idr/effects/idr-effects.mlir`** (RUN lines :1-2, the second
  running `--idr-effects` twice): every function carries the fact it
  carries today, as `idr.func`'s own `effects` (`#idr.effects<none>`,
  `<crash>`, and no attribute where today's is all three); every call
  carries its own; the second run writes nothing, and `-mlir-timing`
  shows no `(A)` row under it.
- **`T/idr/effects/{queries,stale,call-effects,crash,div,alloc,io,loop,read-past-drop,inlined-proof}.mlir`:**
  the answers `facts-as-marked` reads are the call's interface over the
  attribute this lane writes (U02, U15). `queries.mlir` :50-66 and
  `stale.mlir` :13-47 enumerate the facts: a total function that only
  computes is `none`; one without `total` diverges; a guard crashes; a
  world parameter is io; `applies` given `@square` is `none`, given
  `@divides` crashes, given a parameter may do anything; `external` is
  all three; `proved_calls_partial` diverges. U21 writes them on
  `idr.func` and `idr.call`, running `--idr-effects` first (C9.1).
- **`T/idr/func/call-effects`** (U21): `--idr-effects` writes each call's
  effects, and the call's effects always contain its callee's, so
  `verifySymbolUses` accepts every module `idr-effects` leaves.
- **`T/idr/canon/unused-call.mlir`** under `--idr-effects --canonicalize`:
  an unused call of a pure, total callee goes; one given a crashing
  closure stays.
- **`T/idr/verify/cycle.mlir`** (:1-3): `knots()` and `cycle()` give the
  verifier the components and the shortest cycle of today's
  `Cycles.cppm:64-100`, so the message `unsupported (cycle): an array of
  … can hold a reference to itself through … -> … -> …` is byte for
  byte the expected one, at parse and after `--idr-defunctionalize`.
  **`T/idr/verify/module.mlir`**: the contains-itself case gives the
  same message on the same declaration from `containsItself()`.
- **Determinism:** `T/determinism/threads-*` (U22) compile with one
  thread and with the pool; the emitted modules and the effects on every
  function and call are identical.
- **`--mlir-timing` in tree mode** on `every-interfaces-export`, per
  round of C3.2 (R47): `(A) idr::References` appears under
  `idr-effects`, `idr-inline` and `idr-specialize` and nowhere else;
  `(A) idr::Effects` under `idr-effects` only; no `(A)` row under
  `idr-loop-breakers`; `(A) idr::Holds` and `(A) idr::TypeGraph` never
  under `idr-round-facts` in a round whose `idr-effects` built them.
  The `idr-effects` rows' User time exceeds their Wall time under the
  pool on that program.
- **Source conditions:** no `SHA1`, `bodyStamp`, `Inferred`, `Cache`,
  `thread_local`, `std::atomic`, `mutable`, `static` mutable object or
  string-read attribute in the lane's files; `scc_begin` and
  `GraphTraits` only in `IDR/Support/Scc.cpp`; `IDR/Graph` and
  `IDR/Facts` do not exist; no file of `IdrIR` includes
  `idr/Analysis/`.
- **Tempting partial:** keeping the stamps "because the rounds reuse
  most functions". Rejected: the hash walks every body anyway, and the
  manager is the one cache this packet allows.
- **Tempting partial:** a `Holds` that remembers each type on first ask.
  Rejected: function passes read it from worker threads.
- **Tempting partial:** `idr-effects` walking bodies for the calls, or
  `getEffects` looking the callee up. Rejected: the calls are
  `References`' sites, and a lookup from an op hook scans the module
  (F-state-5).
- **Tempting partial:** a serial `idr-effects` loop "since it only
  writes attributes". Rejected: the `passed` queries per call argument
  are the pass's work, and they separate by function.

## Escalate if

1. **A verdict of `containsItself` changes.** If a fixture of `T/idr`
   or a program of the corpus holds an unboxed declaration on a cycle
   only through a graded field (refused now, accepted by
   `Program.cppm:118-144`), or if no grade can wrap an unboxed
   declaration in a field at all, report the fixture or the program and
   the declaration; the coordinator rules on refusing it or reading the
   bare type.
2. **A verified module holds an `idr.call` with no site.** If, at the
   pin, the module verifier does not run `verifySymbolUses` on a module
   `idr-effects` receives (so a call's callee may be missing from the
   `SymbolTable` analysis), `idr-effects` leaves that call's attribute
   stale. Report the pipeline position and the fixture.
