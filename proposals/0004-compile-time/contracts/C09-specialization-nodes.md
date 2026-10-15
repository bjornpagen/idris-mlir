## C09 Specialization nodes

Producer: U04. Consumers: U03 (the ready set implements `Schedule` and
calls the node table and the two summaries, C07 §4 to §6), U01 (the key
attributes, `Elimination`), U05 (a node's entry, C10), U06 (the two
registry rows, C12), U17 and U18 (fixtures, names), and the lanes that stop
reading the clone fact (U08, U09, U16, U17). Paths are under
`foreign/idr/` unless named; `M/` is `.toolchain/build/llvm-project/mlir`.
Line numbers are the tree at a3e61f3a. Authority: 0004 §2.5, §2.7, §4
stages 6 and 8, §6, D14, D15, D18, D39, D45, D47.

### 1. What replaces what

| Today | After the cutover |
| --- | --- |
| `idr-specialize`, a module pass raising and cloning in generations (`lib/Transforms/Specialize/Specialize.cpp:44-82`) | no pass: `idr-redirect`, a step of the inner pipeline, requests each call's key of `Nodes` and calls the key's node at once; the ready set builds each node once and runs it like any function (C07 §5.3) |
| `CloneTable` (`include/idr/Analysis/Specialize.h:54-99`) | `idr::specialize::Nodes`, one per run of `idr-optimize`, keyed by content |
| `CloneAttr`, `KeyClosureAttr`, `KeyApplyAttr`, `KeyApplyFieldAttr` | deleted; `KeyRaiseAttr` is new (section 2); `KeyHoleAttr`, `KeyConAttr`, `SpecKeyAttr` stay as C02 §3 says, held by no op |
| `<owner>.spec<n>`, `<owner>.raise<n>` (`Clones.cpp:40-41`) | `<owner>.spec.<hex16>`, `<callee>.raise.<hex16>` (section 3) |
| `kClonesPerOwner = 1024`, owner-wide, refusing (`Specialize.h:56-59`, `Clones.cpp:30-33`) | `kKeysPerOwner = 1024`, per requesting function, stopping (D39) |
| `giveFirstFacts` (`Clones.cpp:49-66`) | deleted: a node has no `effects` until C10's `idr::writeEntriesOnFinal` |
| `settle`, the clones' `no_inline` (`Clones.cpp:91-110`) | deleted |
| raising on an `idr.apply` (`Raise.cpp`, `Consumer.cpp:26-62`) | raising on the dispatch (section 5) |
| `BindingTimes`, `Identities` built whole per round (`BindingTimes.cpp:226-286`, `Identities.cpp:47-106`) | filled per component by `solve` when it is ready (D47); a node's binding times written once by its build |

### 2. Keys

A key is a uniqued dialect attribute (C02 §3) that no op holds, so equal
keys are one attribute.
- A **spec key** is `#idr.spec_key<"owner", [p0, p1, ...]>`, one pattern
  per parameter of the owner, the function the node is cloned from: the
  call's callee, or, when the callee is a spec node, that node's owner, the
  callee's key filled with the call's patterns (today's `fill`,
  `Keys.cpp:96-114`). A pattern is `#idr.key_hole<i>` (a runtime leaf, the
  node's parameter `i`; holes are numbered left to right over the
  patterns), `#idr.key_con<"T", "C", [fields]>` (constructor `C` of the
  data type named `T`, built or constant; a constant run is keyed as its
  cells, today's `keyOfConstant`, `Keys.cpp:40-75`), or a scalar constant
  attribute. A value entered into a linear type is keyed as the value: the
  position's type says it is linear. A pattern's type is its position's:
  the owner's parameter, or the field type of the enclosing constructor in
  its data type's body (C01). The key holds no type.
- A **raise key** is `#idr.key_raise<"callee", "form">`: the callee's symbol
  and the consumer's form (section 5). A raise node owns the spec keys
  composed at calls of it.

`KeyRaiseAttr` (U01, `IdrAttrs.td`, replacing `KeyApplyAttr` and
`KeyApplyFieldAttr`):

```tablegen
def Idr_KeyRaiseAttr : Idr_KeyAttr<"KeyRaise", "key_raise"> {
  let summary = "the key of a clone that runs its consumer at its callee's tails";
  let parameters = (ins "::mlir::StringAttr":$callee, "::mlir::StringAttr":$consumer);
  let assemblyFormat = "`<` $callee `,` $consumer `>`";
}
```

A key's text is the key attribute printed by `mlir::Attribute::print`.

### 3. Names

A node's symbol is C21's `contentName(owner, "spec", keyText)` or
`contentName(callee, "raise", keyText)`, `<owner>.<kind>.<hex16>`. A name
made for two different keys, or one that a function of the module that is
no node already holds, is an internal error at the requesting call,
`internal error: two keys name <name>: <key1> and <key2>` (C21's text),
raised by `Nodes` where it interns the name: never a merge, never another
name. `idr-optimize` runs once per module; a run on its own output can meet
its own names and stops there with that error.

### 4. The node table: `include/idr/Transforms/Specialize.h` (U04)

```cpp
namespace idr {

#define GEN_PASS_DECL_IDRREDIRECT
#define GEN_PASS_DECL_IDRBINDINGTIMES
#include "idr/Transforms/Passes.h.inc"

class BindingTimes;
class Holds;

// idr-redirect calls a raise node: the call and its consumer become one call.
struct RaiseAction : support::TaggedAction<RaiseAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-raise";
};

// idr-redirect calls a specialization node.
struct SpecializeCloneAction : support::TaggedAction<SpecializeCloneAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-specialize-clone";
};

} // namespace idr

namespace idr::specialize {

// The distinct keys one requesting function asks of one owner, in its
// call-site order over every run of its pipeline and its build, an
// already-made key counted like a new one. A key past it is not requested:
// its call stays.
inline constexpr unsigned kKeysPerOwner = 1024;

// A node: made once per key, by the first request of it. A SpecKeyAttr key
// makes a spec node, a KeyRaiseAttr key a raise node.
struct Node {
  mlir::Attribute key;
  mlir::StringAttr owner;          // the function it is cloned from
  mlir::FlatSymbolRefAttr name;    // section 3
  idr::FuncOp fn;                  // null until build
};

// What the ready set tells the table (U03's ReadySet implements it); both
// are safe from any worker.
class Schedule {
public:
  virtual ~Schedule() = default;
  // The function the module holds under `name`, inserted nodes included,
  // or null.
  virtual idr::FuncOp lookup(mlir::StringAttr name) const = 0;
  // Whether no pass writes `fn` again: its component is final.
  virtual bool isFinal(idr::FuncOp fn) const = 0;
};

class Nodes {
public:
  // Empty; idr-optimize takes it with getAnalysis.
  Nodes(mlir::Operation *module, mlir::AnalysisManager &am);
  ~Nodes();
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Before the first task; the three outlive the run.
  void start(const Schedule &schedule, BindingTimes &times, const Holds &holds) const;

  // The node `fn` is, or null.
  const Node *find(mlir::StringAttr fn) const;

  // The nodes `requester` asked for since the last take, each once, in the
  // order first asked, never the requester itself.
  llvm::SmallVector<Node *> takeRequests(idr::FuncOp requester) const;

  // True for exactly one caller per node: the one to build it.
  bool claim(Node &node) const;

  // The node's function, built detached from its owner's final body
  // (section 6), named, its binding times written, its calls redirected
  // once, the node its requester; then `takeRequests(node.fn)` gives what
  // that walk asked for. A failure is an internal error, emitted.
  mlir::LogicalResult build(Node &node) const;

  // Puts the built function into `module`: after its owner, then past every
  // node whose name sorts before its own. Serial: at a quiescent point.
  void insert(Node &node, mlir::ModuleOp module) const;

  // The redirect step over `fn` (section 6): idr-redirect's and build's.
  // `redirected` counts the redirects, `changed` says whether anything
  // changed. A failure is an internal error, emitted.
  mlir::LogicalResult redirectCalls(idr::FuncOp fn, unsigned &redirected, bool &changed) const;

  struct State;

private:
  std::unique_ptr<State> state;
};

} // namespace idr::specialize
```

Fixed choices:
- The table's state is behind one pointer and one `std::mutex`: the
  passes of the inner pipeline reach the table through their parent's
  cache, which hands out a const reference (`getCachedParentAnalysis`),
  so the const methods write that state.
- A request is the one way a node is made: it checks the budget and the
  name, makes the node if its key has none, and records it under the
  requester. A key's node is one object for every requester, and its name
  is known before it is built, so a call is redirected at once.
- `isInvalidated` returns `!pa.isPreserved<Nodes>()`.
- The pieces the table is built from (`Pattern`, `shapeOf`, `rebuild`,
  `composeKey`, `consumerOf`, `formOf`, `decide`, the node bodies) are in
  the header's `idr::specialize::detail`, for U04's units alone.

### 5. Raising after defunctionalization

A call is raised when its one result's one use is, through C01's
`idr::Elimination` steps (a linear position entered and used at once, a
field, the one use of a linear value), the scrutinee of an `idr.match` on
a value whose data type is of kind closures (C01 `isClosures`): a
dispatch, what an apply became (C06 postcondition 3). The match is in the
call's block; the call only computes, or every op between it and the
dispatch only computes (`idr::onlyAllocates`); no operand type of the call
may hold a world (`Holds::mayHoldWorld`); the callee is final and returns
from its one block. These are today's conditions (`Consumer.cpp:26-47`)
with the apply read as the dispatch. `Elimination` ends in that match (U01:
`MatchOp dispatch` for today's `ApplyOp apply`, `Symbols.h:66-75`).

- **The consumer's form** is a detached private `idr.func @consumer` whose
  parameters are the call's result, then the consumer's free values (the
  values its steps and match read that are defined outside it) in the
  order a pre-order walk of the match first reads them, whose body is a
  copy of the steps and the match returning the match's results, printed
  by `Operation::print` with
  `OpPrintingFlags().printGenericOpForm().enableDebugInfo(false)`. Two
  consumers have one form exactly when they are the same code on the same
  values. `build` parses the form back (`mlir::parseSourceString`, no
  verification), so a raise node is a function of its key.
- A raise node's parameters are the callee's, then the free values; its
  results the match's. Its body is the callee's with the consumer pushed
  to every tail: the return's operand and, through each `idr.match` or
  `idr.match_lit` whose result reaches the return and has no other use,
  the yields of its regions (today's `push`, `Raise.cpp:95-139`); every
  pushed op takes the location of the terminator it is pushed to.
- **Who may raise.** A function that is no node raises any call that meets
  the conditions. A raise node raises only with its own form, so a pushed
  copy that meets a call at a tail becomes a call of the node of
  `(that callee, its own form)`, itself when the callee is its own. A spec
  node raises nothing.

### 6. Building a node, and the redirect step

**`build(node)`**, from the owner's final function (`Schedule::lookup`):
- *Spec*: `Operation::clone` of the owner, keeping its location,
  `instance`, `total` and every fact but `effects`, which is removed (C10);
  named, private. Each owner parameter whose pattern is a hole becomes the
  next new parameter; any other is replaced at the entry by its pattern
  rebuilt (a constructor by `idr.con`, a scalar by the dialect's
  `materializeConstant`, a linear position by `idr.lin.enter`) over new
  parameters for its holes, each op at the location of the parameter it
  replaces. Parameter `i` holds hole `i`.
- *Raise*: as section 5, `effects` and `res_attrs` removed.
- Then the node's binding times are written (section 7), and
  `redirectCalls(node.fn)` runs with the node as requester, so a call of
  its owner with its own key, a fixed parameter passed on unchanged, is
  already its own call when its component becomes ready.

**`redirectCalls(fn)`**, one pre-order walk of `fn`'s `idr.call`s, each
taken once, in walk order, a call the walk has erased skipped:
1. *Decide* (`detail::decide`): if the call raises (section 5), its raise
   key, owner its callee; else, if its callee is final and its arguments
   compose a key (today's `composeKey`, `Keys.cpp:144-195`: the
   binding-time rule, `kUnrollLimit` 32, the closed-call rule, the
   linear-leaf rule; "a closure" read as "a value of a data type of kind
   closures"), its spec key; else nothing.
2. *Request* the key under `fn`: past `kKeysPerOwner` distinct keys of
   that owner the call stays as it is.
3. *Redirect*, inside `support::perform<RaiseAction>` or
   `support::perform<SpecializeCloneAction>` on the call: a raise replaces
   the dispatch by a call of the node with the call's operands and the
   free values, then erases the steps and the call; a spec replaces the
   call by a call of the node with the leaves and erases the shapes no op
   uses any more (today's `eraseUnused`). The new call takes the node's
   `effects` when the node is final, none otherwise. A skipped action
   leaves the call as it was.
4. A call whose callee is a final node and whose `effects` differs from
   the node's entry takes it (D38, C10 §7).

**`idr-redirect`** (C12's `IdrRedirect`, unit `RedirectPass.cpp`) reads
`getCachedParentAnalysis<idr::specialize::Nodes>()`; without it, "internal
error: idr-redirect runs inside idr-optimize, which holds the
specialization nodes of its module" and pass failure. It runs
`redirectCalls` on its function, adds to `numRedirected`, and preserves
every analysis when nothing changed.

### 7. Binding times: `include/idr/Analysis/Specialize.h` (U04)

```cpp
namespace idr {

enum class BindingTime : uint8_t { Free, Fixed, Decreasing, Bounded, Other };
llvm::StringRef nameOf(BindingTime time);

class BindingTimes {
public:
  BindingTimes(mlir::Operation *module, mlir::AnalysisManager &am); // empty
  ~BindingTimes();
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // Each member of `component` without binding times gets them, from the
  // members' bodies as they are: Free for each parameter when `component`
  // is one function that calls itself nowhere. Safe on disjoint components
  // from different workers.
  void solve(llvm::ArrayRef<idr::FuncOp> component);
  // A node's, written by its build once: its owner's, by its key.
  void inherit(mlir::StringAttr fn, llvm::SmallVector<BindingTime> times);

  std::optional<BindingTime> of(mlir::StringAttr fn, unsigned index) const;
  llvm::SmallVector<BindingTime> of(mlir::StringAttr fn) const;
};

// The binding times `solve` gives the members of `component`, in its order.
llvm::SmallVector<llvm::SmallVector<BindingTime>>
bindingTimesOf(llvm::ArrayRef<idr::FuncOp> component);

} // namespace idr
```

The classes and the interpretation are today's (`Specialize.h:101-118`,
`BindingTimes.cpp:63-212`) over the `idr.call`s between members; the
closure sites (`:177-183`) and the raised clones' inheritance
(`:214-285`) go. A spec node's binding time of hole `i` is its owner's of
the parameter whose pattern holds hole `i`; a raise node's are its
callee's for the callee's parameters and `Other` for the free values.
Each function's binding times are written once: a node's by its build, a
function the module held by `solve` when its component is ready. So a
node's recursion, which goes where its owner's goes, is judged by its
owner's.

### 8. Identities: `include/idr/Analysis/Identities.h` (U04)

```cpp
namespace idr {

class Identities {
public:
  Identities(mlir::Operation *module, mlir::AnalysisManager &am); // empty
  ~Identities();
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // The greatest fixpoint inside `component`, its callees' answers read
  // frozen. Safe on disjoint components from different workers.
  void solve(llvm::ArrayRef<idr::FuncOp> component);

  // The argument `function` gives back, if its component is solved and it
  // gives one back. idr-identity reads it (U03), unchanged.
  std::optional<unsigned> givesBack(mlir::StringAttr function) const;
};

} // namespace idr
```

The rule is today's (`Identities.h:3-22`, `IdentitiesRecord.cpp:3-29`,
`IdentitiesRebuilds.cpp:3-13`). A call relies on its callee returning when
the callee's entry has no `diverge`: the call's own `effects` for a callee
outside the component (C10's `idr::writeCallEffectsOnReady` wrote it),
the member's `effects` for one inside. A constructor, a case and a memo
sum are read from the data type (C01), never from the symbol table.

### 9. What the ready set does (U03, C07)

1. Before any task: `getAnalysis` of `BindingTimes`, `Identities` and
   `Nodes`; `nodes.start(set, times, holds)`.
2. When a component is ready, after `idr::writeCallEffectsOnReady`:
   `times.solve(members)`, `identities.solve(members)`.
3. The inner pipeline holds `idr::createIdrRedirect()` after CSE.
4. After each pipeline run and each build: `takeRequests`, `claim`,
   `build`, then `insert` at a quiescent point (C07 §5.3).
5. Nodes that request one another form one component (C07 §5.4).
6. The inline decisions count one call per request of a node (D14).
7. A call of a node made during its requester's loop has the node's
   entry before the requester's component finishes: C09's redirect step
   writes it when it runs after the node is final.

### 10. Invariants

- **Termination by construction.** Spec keys are finite by the
  binding-time rule (`Keys.cpp:7-15`), a node's parameters judged by its
  owner's (section 7), and each key's node is made once (0004 §2.5).
  Raise keys are finite: a form is one a function that is no node holds,
  or the requesting raise node's own, over finitely many callees.
  `kKeysPerOwner` bounds width and never refuses.
- **Determinism.** A node's body is a function of its key and its owner's
  final body; its name of its key; its place of the names; a function's
  requests of its own body in walk order. No count reads an arrival order.
- **No refusal.** Nothing here emits `unsupported`; a broken invariant is
  `internal error: ...`.

### 11. Deleted declarations

`Clone`, `CloneTable`, `kClonesPerOwner`, `specialize::Statistics`,
`Closure` (the pattern), `Call`, `Entry`, `Slot`, `labels`, `makeClone`,
`giveFirstFacts`, `canonicalizeAndCollect`, `settle`, `Specializer`,
`GEN_PASS_DECL_IDRSPECIALIZE`; units `lib/Transforms/Specialize/Clones.cpp`
and `lib/Analysis/Specialize.cpp`.

### 12. Consumers by lane

- U01: `KeyRaiseAttr` (section 2) for `KeyApplyAttr` and
  `KeyApplyFieldAttr`; `Elimination` ending in the dispatch (section 5);
  `CloneAttr`, `KeyClosureAttr` and `idr.func`'s `clone` gone (C02 §3).
- U03: section 9; `ReadySet` implements `Schedule`; idr-identity reads
  `Identities::givesBack`.
- U05: a node's `effects` is absent until `idr::writeEntriesOnFinal` (C10).
- U06: C12's rows for `IdrRedirect` and `IdrBindingTimes`; no
  `IdrSpecialize`.
- U08 (`Rc.cpp:70-73`, `Ownership/Specialize.cpp:53`), U09
  (`Accumulate.cpp:121`, `Trmc.cpp:169`), U16 (`Deduplicate.cpp:276-282,
  317-331`), U17 (`Expect/Named.cpp`): no clone fact to strip or read.
- U17: the debug-counter fixture skips `idr-specialize-clone`; the budget
  fixture makes 1,025 distinct requests of one owner from one function.
- U18: generated names carry `.spec.` or `.raise.` and 16 hex digits.
