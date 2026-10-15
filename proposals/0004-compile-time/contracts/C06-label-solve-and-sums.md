## C06 The label solve and the sums

Producer: U02. Consumers: U05 (the effects summary resolves every
`idr.apply` to its labels through `Labels`, D34), U03, U04, U08, U10, U12
(they read the module `idr-defunctionalize` leaves: the postconditions
below), U06 (the pass's registry entry and place), U17 (fixtures and
properties).

Defunctionalization is total (0004 §2.4): every key becomes a sum, the
label analysis has no unknown element (D10), the world is closed by the
verifier (D7, C03), and the pass fails only with an internal error.

### The solve: `foreign/idr/include/idr/Analysis/Labels.h` (U02)

MLton's 0CFA (`sources/code/mlton/mlton/closure-convert/closure-convert.fun:246-391`,
`abstract-value.fun:42-148`) on the edges the ops declare (C05), solved
once in the constructor, on our own graph and worklist: MLIR's
`DataFlowSolver` is not used (it propagates whole lattices, has no
union-find, and its interprocedural mode needs dead-code analysis and
constant propagation over the whole module, `loadBaselineAnalyses`,
today's `lib/Analysis/Labels.cpp:315`).

```cpp
namespace idr {

// The index in its constructor of field `i` of a run's cell, which holds
// every field but the spine.
inline unsigned cellField(unsigned i, unsigned spine);

// Calls `visit(field, index)` for each field of `con` with its index in
// the constructor: a plain con's fields, or a run's cells without their
// spine field, then its tail, which fills the last cell's spine.
inline void eachField(ConAttr con, llvm::function_ref<void(mlir::Attribute, unsigned)> visit);

// The solve's own representation (nodes, classes, sets, the graph and its
// worklist), private to Labels.cpp and LabelSites.cpp; no other file
// names it.
namespace labels { class Graph; }

class Labels {
public:
  Labels(mlir::Operation *module, mlir::AnalysisManager &am);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<Labels>() || !pa.isPreserved<mlir::SymbolTable>();
  }

  // The labels a closure or suspension at a point may be: a uniqued
  // ArrayAttr of FlatSymbolRefAttr in name order, the empty ArrayAttr
  // where no label reaches. A point whose carrier is not keyed holds the
  // empty set. Two equal sets are one attribute.
  mlir::ArrayAttr labelsOf(mlir::Value value) const;
  mlir::ArrayAttr labelsOf(const FlowPoint &point) const;

  // The labels `op` runs: an idr.apply those of its callee, an idr.force
  // of a lazy cell those of its cell; the empty set for any other op.
  mlir::ArrayAttr runs(mlir::Operation *op) const;

  // The one point `operand` moves its value into at its op, or nothing:
  // an operand of a carrier that is not keyed, and the callee and the
  // arguments of a dispatch, which move per label.
  std::optional<FlowPoint> sinkOf(mlir::OpOperand &operand) const;

  // The dispatches of the module, in walk order.
  llvm::ArrayRef<mlir::Operation *> dispatches() const;

  // The function of `label`, from the module's table.
  FuncOp function(mlir::StringAttr label) const;
};

} // namespace idr
```

Every answer is read-only once the constructor returns (every path of the
union-find compressed, every set's attribute made), so U05's `LabelsRun`
may call `runs` and `function` from worker threads.

`LabelSet`, `LabelLattice`, `FieldAnchor`, `ElementsAnchor`,
`FieldLabels`, `holdsClosure`, `closures`, `closureConstants`,
`suspensions`, `suspensionConstants`, `applies`, `labelsFor`, `escapes`,
`failed` and `fieldType` are deleted from the header.

**Representation** (D12, 0004 §2.8), all private to `Labels.cpp` and
`LabelSites.cpp`:
- A node per point: a keyed value, a parameter or result of a function
  (a parameter is its entry block argument's node), an anchor. No node
  exists for a value of an unkeyed type: first-order values carry no flow.
- Nodes are classes of a union-find; a class holds its set, its inclusion
  successors and its dispatch handlers.
- A set is a sorted array of label numbers, a label numbered when first
  met, hash-consed in the solve's own uniquing table, with a join cache;
  the answer to a query is the set's ArrayAttr in name order, made once
  per set when the solve ends, so no answer depends on the numbering.
- Propagation sends only the difference between sets, from a worklist,
  never by recursion.
- A dispatch handler adds, for each label that reaches its callee, the
  edges of C05's Dispatch rule, as the label arrives.
- The graph is built by one walk of the module calling `flowEdgesOf` on
  every op, constants expanded by C05's rule with one memo per solve.

**Invariants.** Every set is a finite set of the module's functions, and
there is no unknown, no top and no escape: a public function is the root,
which takes or returns no keyed value (C03), and no function is external
(C03). A label in a set fits the point's carrier (C05, D27). Each operand
has at most one sink. The sets are the least solution, so they depend on
the module alone, not on walk or worklist order. *Threshold:* the solve
under 10 s of wall on the stage-0 module (0004 §2.8, §10), measured on the
owner's machine.

### The key decision: `foreign/idr/include/idr/Transforms/Defunctionalize.h` (U02)

Private to U02's files except the pass's create function, which
`Passes.td` (U06) generates. A key is `(carrier, labels)`, the carrier the
point's type without its grade, the labels the solve's ArrayAttr. Every
key converts; there is no `UnknownKey`, `unknownKeys`, `convertible`,
`canCoerce`, sealing cascade, `numClosures` or `markByName`.

### The sums

Made after the label solve and the effects summary, before the
conversion, each body set once (D29, D34):

| Key | Identified type (C01) | Name (C21) | Value type |
| --- | --- | --- | --- |
| closure, labels `@L1..@Ln`, n >= 1 | kind closures; one constructor per label in name order, named by `FlatSymbolRefAttr @Li`, its fields the converted types of `Li`'s leading `captures` parameters at their grades (`captures` = `Li`'s parameter count less the carrier's input count) | `contentName("fn$", "sum", keyText)` | the type, or `!idr.box` of it when the key is on a cycle of "a capture holds a value of that key" (today's rule, `Decide.cpp:49-95`) |
| closure, no label | kind closures, no constructor | `contentName("fn$", "sum", keyText)` | the type |
| lazy, labels `@L1..@Ln`, n >= 0 | kind memo; one constructor per label in name order, named by `@Li`, its fields `Li`'s converted parameters, `by_name` exactly when C10's `ModuleEffects::byName(Li)`; then `running` (no field), then `forced` (one field: the forced anchor's converted type) | `contentName("lazy$", "sum", keyText)` | `!idr.box` of the type |
| a user data type `T` whose body names a keyed carrier or a remade type, transitively | remade by C01's `DataRemap` of kind `defun`: the same kind, constructors (names, order, `by_name`) and `instance` as `T`, with converted field types; its `leaf` gives a keyed carrier at a field or an element its key's sum value type | C01 §7's rule: `contentName(T's name, "defun", key)` | as `T`'s values: `T′`, or `!idr.box<T′>` |

- `contentName(owner, kind, key)` is C21's C++ helper: `<owner>.<kind>.`
  followed by the 16 hex digits of the low half of XXH3-128 of `key`.
  `fn$` and `lazy$` hold a `$`, which no Idris name does, so no sum's name
  meets a user type's.
- `keyText` = the carrier printed by MLIR's type printer, then, for each
  label in name order, a NUL byte and the label's name.
- The memo constructors `running` and `forced` are `memoRunning` and
  `memoForced` (`include/idr/IR/IdrDialect.h:290-291`).
- A name made for two different keys is an internal error, raised where
  the name is interned (0004 §4 stage 1).
- Order: every sum is made by name (`DataType::get`, C01) first; then the
  `DataRemap` remakes the user types, its `leaf` answering from the keys;
  then every sum's body is set (`setBody`), its field types mapped through
  the remap and the keys. A body is never set twice.
- The `leaf` U02 gives the remap needs the position a closure or
  suspension is held at, since a field's key is its anchor's, not its
  type's: C01 §7's leaf is called as `leaf(type, owner, tag, field)`, the
  last three naming the body field whose type `type` is (owner null for a
  type held anywhere else), and asked once per (type, owner, tag, field).
  It answers a keyed field with its field key's sum value type (`!idr.lin`
  kept), a shaped type whose element is keyed with the shaped type over
  the element key's sum, and nothing for any other type.
- Every type a value or signature of the module has is remade once,
  serially, into a table; the conversion reads the table, and a type it
  does not hold is one the conversion made, which is its own remade type.
- A box past the runtime's 2^16 tags is the one refusal left,
  `unsupported (layout)`, by U01's verifier of the type with its rule
  (C04, D48); defunctionalization never refuses.

### The conversion

Per function, in parallel (`mlir::failableParallelForEach` over the
module's `idr.func` ops, `applyFullConversion` on each), after every type
above exists. Each task first makes its function's plan, the types and
keys of its own values and the sink key of each of its operands, from the
decision (frozen: every sum, remade type, signature, constant and remade
value type is made before any task starts) and the solve (frozen), then
its own converter, target and patterns over that plan. No task reads
another function's op: a callee's signature is the decision's table.
Rollback is on, so no value or operand the plan names is freed while the
task runs.

### Postconditions (what every later lane reads)

1. No value, block argument, parameter, result, field of an identified
   type reachable from the module, or element type has a closure or lazy
   carrier; no `idr.closure`, `idr.suspend`, `idr.apply` or `idr.delay` is
   left; every `idr.force` takes `!idr.box` of a memo sum.
2. A former `idr.closure @L(c...)` or `idr.suspend @L(c...)` is
   `idr.con @L(c'...)`, `c'` the captures moved into `L`'s parameter keys
   and held at the field grades; a former `idr.delay %v` is `idr.con
   @forced(%v')`; a closure constant is a `ConAttr` of `@L` in its sum.
3. A former `idr.apply %k(a...)` on key `(F, [@L1..@Ln])`, n >= 1, is
   `idr.match %k [@L1, ..., @Ln]`, one region per label in name order, each
   binding `Li`'s captures at the scrutinee's grade and yielding the
   results of `idr.call @Li(captures..., a'...)` moved into the apply's
   result keys; these calls carry no `effects` (the ready set writes them,
   D38). An apply on a key with no label (no value ever reaches its
   callee) is `ub.poison` of each result type.
4. A value moving between two closure keys is rebuilt by an `idr.match`
   over the source sum whose region for `@L` builds `@L` of the target,
   whose labels contain the source's (0004 §2.4 step 6). A lazy key never
   moves into another: lazy flows unify (C05).
5. Every function's signature is its points' types; every constant is
   converted to its slot.
6. `layout::fit` (C01) then boxes the values whose cells would count too
   many references, as today (`Pass.cpp:106`).
7. Labels are kept alive only by the symbol uses of the constructors and
   matches that name them (D29).

### The pass's entry (U06 writes it in `Passes.td`; C12)

`idr-defunctionalize`, `::mlir::ModuleOp`, after `idr-deduplicate` and
before `idr-contify` (0004 §4 stages 3 to 5), `dependentDialects =
["::mlir::ub::UBDialect"]`, statistics:

```tablegen
  let statistics = [
    Statistic<"numSums", "sums", "Closure and memo sums made">,
    Statistic<"numConstructors", "constructors", "Label constructors over every sum made">,
    Statistic<"largestBoxedSum", "largest-boxed", "Labels of the largest boxed closure sum">,
    Statistic<"numBoxed", "boxed", "Records and closure sums made boxes so that the cells holding them fit">,
  ];
```

`largestBoxedSum` is the record D48 and 0004 §2.5 ask for, read with
`--mlir-pass-statistics`; it is assigned the maximum, never summed. The
`idr-isolate` entry is deleted.

### The effects summary (D34)

`Pass.cpp` constructs C10's `idr::ModuleEffects` once, after the solve and
before the sums, with `getAnalysis<idr::Holds>()`, the module's symbol
table and a `LabelsRun` that appends the functions of `Labels::runs(op)`;
sets each memo constructor's `by_name` from `ModuleEffects::byName`; and
calls `writeEntries()` once, after the conversion. Nothing else in U02
computes an effect.
