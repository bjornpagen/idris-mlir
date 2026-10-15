## C05 The flow interface

Producer: U02. Consumers: U01 (calls the flow rule from `idr.func`'s region
verifier, including `idr/IR/Flow.h` in `lib/IR/Func/Func.cpp`), U06 (calls
the registration function on every registry a module is read with), U05
(reads the solve built on it, C06), U17 (fixtures), U02 itself (the label
solve and the key decision read it, through `flowEdgesOf` only). U01 and
U11 declare nothing in ODS: every op holds the interface as an external
model, so `IdrDialect.h` includes none of it (the coordinator's ruling of
2026-10-14).

One representation of closure flow: an op that holds, takes or gives a
value of a closure or lazy carrier declares how that value moves, as data,
and the label solve (C06) and the key decision read exactly those edges.
Nothing else in `foreign/idr` decides how a closure moves: no op list, no
per-op case in an analysis, no second table (0004 §2.2 change 2, D8;
today's two tables are `lib/Analysis/Labels.cpp:68-123` and
`lib/Transforms/Defunctionalize/Moves.cpp:27-79, 209-247`, which go).

### Files

| File | Owner | Content |
| --- | --- | --- |
| `foreign/idr/include/idr/IR/IdrFlow.td` | U02 | the ODS interface below, exactly |
| `foreign/idr/include/idr/IR/Flow.h` | U02 | the vocabulary below, then `#include "idr/IR/IdrFlow.h.inc"`; it includes `idr/IR/IdrDialect.h`, never the other way round |
| `foreign/idr/lib/IR/Flow.cpp` | U02 | `#include "idr/IR/IdrFlow.cpp.inc"`, every op's edges as an external model, `registerFlowInterfaceExternalModels`, `flowEdgesOf`, `verifyFlow` |
| `foreign/idr/lib/IR/Func/Func.cpp` | U01 | `#include "idr/IR/Flow.h"`; `verifyFlow(op)` on each op nested in the body, from `FuncOp::verifyRegions` |
| `foreign/idr/include/idr/IR/CMakeLists.txt` | coordinator | the two `mlir_tablegen` lines below, in the `IdrOpsIncGen` target |
| `foreign/idr/lib/IR/CMakeLists.txt` | coordinator | `Flow.cpp` in `IdrIR`; `MLIRTensorDialect` in its `LINK_LIBS` |

Build lines (coordinator), before `add_public_tablegen_target(IdrOpsIncGen)`
in `include/idr/IR/CMakeLists.txt` (the interface generator writes only the
interfaces of the file it reads, `include/idr/IR/CMakeLists.txt:4-6`):

```cmake
set(LLVM_TARGET_DEFINITIONS IdrFlow.td)
mlir_tablegen(IdrFlow.h.inc -gen-op-interface-decls)
mlir_tablegen(IdrFlow.cpp.inc -gen-op-interface-defs)
```

### ODS: `include/idr/IR/IdrFlow.td`

```tablegen
#ifndef IDR_FLOW
#define IDR_FLOW

include "mlir/IR/OpBase.td"

def Idr_FlowOpInterface : OpInterface<"FlowOpInterface"> {
  let cppNamespace = "::idr";
  let description = [{
    An op that holds, takes or gives a closure or a suspension declares
    how each one moves: into its results or region arguments, into an
    anchor, into a function's parameters or results, or through a
    dispatch. It declares only edges no upstream interface declares: a
    branch's and a region branch's forwarded values are read from
    BranchOpInterface and RegionBranchOpInterface.
  }];
  let methods = [
    InterfaceMethod<[{
        Adds to `edges` every edge along which a closure or a suspension
        this op holds, takes or gives moves. An op with no value of a
        closure or lazy carrier adds nothing.
      }],
      "void", "getFlowEdges", (ins "::idr::FlowEdges &":$edges)>,
  ];
}

#endif // IDR_FLOW
```

No op declares it in ODS, so the interface has no trait verifier; its
check is the flow rule's (below), which `idr.func`'s verifier runs.

### `include/idr/IR/Flow.h` (U02)

```cpp
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>

namespace idr {

// Whether a value of `type` is a closure or a suspension, at any grade:
// the values that carry labels. A value of any other type carries none,
// whatever it holds: an anchor holds the labels of its parts.
inline bool isKeyed(mlir::Type type) { return isClosureType(type) || isLazyType(type); }

// Where closures or suspensions are held for every value of a kind, not
// for one value: a field of a constructor of a data type, the elements of
// every shaped value of an element type, the forced state of every cell
// of a lazy type. Each holds values of one carrier.
struct FlowAnchor {
  enum class Kind : std::uint8_t { Field, Elements, Forced };
  Kind kind = Kind::Field;
  // Field: the identified data type, ungraded and unboxed. Elements: the
  // element type. Forced: the lazy type, ungraded.
  mlir::Type type;
  // Field: the constructor's tag and the field's index.
  unsigned ctor = 0;
  unsigned field = 0;

  static FlowAnchor fieldOf(mlir::Type data, unsigned ctor, unsigned field) {
    return {Kind::Field, data, ctor, field};
  }
  static FlowAnchor elementsOf(mlir::Type element) { return {Kind::Elements, element, 0, 0}; }
  static FlowAnchor forcedOf(mlir::Type lazy) { return {Kind::Forced, lazy, 0, 0}; }
  bool operator==(const FlowAnchor &other) const {
    return kind == other.kind && type == other.type && ctor == other.ctor &&
           field == other.field;
  }
};

// One end of an edge: a use that moves its value (only ever a `from`), a
// result or block argument (only ever a `to`), an anchor, or a parameter
// or result of a function, by its name.
struct FlowPoint {
  enum class Kind : std::uint8_t { Operand, Value, Anchor, Parameter, Result };
  Kind kind = Kind::Value;
  mlir::OpOperand *operand = nullptr;
  mlir::Value value;
  FlowAnchor anchor;
  mlir::FlatSymbolRefAttr function;
  unsigned index = 0;

  static FlowPoint of(mlir::OpOperand &operand) {
    FlowPoint point;
    point.kind = Kind::Operand;
    point.operand = &operand;
    return point;
  }
  static FlowPoint of(mlir::Value value) {
    FlowPoint point;
    point.kind = Kind::Value;
    point.value = value;
    return point;
  }
  static FlowPoint of(FlowAnchor anchor) {
    FlowPoint point;
    point.kind = Kind::Anchor;
    point.anchor = anchor;
    return point;
  }
  static FlowPoint parameter(mlir::FlatSymbolRefAttr function, unsigned index) {
    FlowPoint point;
    point.kind = Kind::Parameter;
    point.function = function;
    point.index = index;
    return point;
  }
  static FlowPoint result(mlir::FlatSymbolRefAttr function, unsigned index) {
    FlowPoint point = parameter(function, index);
    point.kind = Kind::Result;
    return point;
  }
};

// The edges ops declare, as data, in the order they were added.
class FlowEdges {
public:
  struct Edge {
    enum class Kind : std::uint8_t {
      // Every label `from` holds, `to` holds.
      Flow,
      // `from` and `to` hold one set: a cell both share.
      Unify,
      // `to` holds `label`.
      Source,
      // The constant part `constant` is held at `to`.
      Constant,
      // `call`, a CallOpInterface whose callee is a value, runs each label
      // its callee holds.
      Dispatch,
    };
    Kind kind;
    FlowPoint from;
    FlowPoint to;
    mlir::FlatSymbolRefAttr label;
    mlir::Attribute constant;
    mlir::Operation *call = nullptr;
  };

  void flow(FlowPoint from, FlowPoint to) {
    list.push_back({Edge::Kind::Flow, from, to, {}, {}, nullptr});
  }
  void unify(FlowPoint a, FlowPoint b) {
    list.push_back({Edge::Kind::Unify, a, b, {}, {}, nullptr});
  }
  void source(mlir::FlatSymbolRefAttr label, FlowPoint to) {
    list.push_back({Edge::Kind::Source, {}, to, label, {}, nullptr});
  }
  void constant(mlir::Attribute part, FlowPoint at) {
    list.push_back({Edge::Kind::Constant, {}, at, {}, part, nullptr});
  }
  void dispatch(mlir::CallOpInterface call) {
    list.push_back({Edge::Kind::Dispatch, {}, {}, {}, {}, call.getOperation()});
  }

  llvm::ArrayRef<Edge> edges() const { return list; }
  void clear() { list.clear(); }

private:
  llvm::SmallVector<Edge, 4> list;
};

// Adds to `edges` every edge `op` declares: its FlowOpInterface edges, and
// the forwarded values of BranchOpInterface, of
// RegionBranchTerminatorOpInterface and of RegionBranchOpInterface's
// entry, each a Flow from the operand to the successor input, for values
// of a closure or lazy carrier only. The one reader of closure flow.
void flowEdgesOf(mlir::Operation *op, FlowEdges &edges);

// The flow rule, which idr.func's verifier runs on every op of its body.
// An op with FlowOpInterface: each edge it declares joins two ends of one
// carrier (the type without its outermost grade), from an operand of its
// own, an anchor, a parameter or a result, to a result or region argument
// of its own, an anchor, a parameter or a result. Any other op: every
// operand, result and block argument whose type isKeyed is a forwarded
// operand or a successor input of a branch or a region branch, or an
// argument of a non-entry block. Fails with an error at `op` naming the
// edge or the value otherwise.
mlir::LogicalResult verifyFlow(mlir::Operation *op);

// Attaches FlowOpInterface to every op of ours that holds, takes or gives
// a closure or a suspension, and to the upstream ops that move one or make
// one from nothing: tensor.insert, tensor.extract, tensor.from_elements,
// tensor.splat, tensor.yield, ub.poison. Every registry a module is read
// with takes it.
void registerFlowInterfaceExternalModels(mlir::DialectRegistry &registry);

} // namespace idr

#include "idr/IR/IdrFlow.h.inc"
```

`isKeyed` moves here from `include/idr/Analysis/Labels.h:204`, which no
longer defines it.

### The edges of each op

`O(x)` is `FlowPoint::of(operand)`, `V(x)` `FlowPoint::of(value)`,
`F(T, c, i)` the field anchor of data type `T` (the operand's or result's
identified type, ungraded and unboxed), constructor tag `c` (the tag of
the constructor the op names within `T`'s body, C01) and field `i`,
`E(e)` the elements anchor of element type `e`, `Z(l)` the forced anchor
of lazy type `l` (ungraded), `P(f, i)` and `R(f, j)` parameter `i` and
result `j` of function `f`. An edge is added only for an end of a keyed
type; an op none of whose values is keyed adds nothing.

| Op (owner of its ODS) | Model | Edges |
| --- | --- | --- |
| `idr.call` (U01) | Flow.cpp, external model | for each argument `i`: Flow `O(arg i)` → `P(callee, i)`; for each result `j`: Flow `R(callee, j)` → `V(result j)` |
| `idr.return` (U01) | Flow.cpp, external model | for each operand `j`: Flow `O(operand j)` → `R(enclosing function, j)` |
| `idr.constant` (U01) | Flow.cpp, external model | when its value is a `ClosureAttr` or a `ConAttr`: Constant `value` at `V(result)` |
| `idr.con` (U01) | Flow.cpp, external model | for each field operand `i`: Flow `O(field i)` → `F(T, c, i)`, `T` the result's type |
| `idr.field` (U01) | Flow.cpp, external model | Flow `F(T, c, index)` → `V(result)`, `T` the operand's type |
| `idr.match` (U01) | Flow.cpp, external model | for each case region `r` and each of its block arguments `i`: Flow `F(T, tag of cases[r], i)` → `V(arg)`, `T` the scrutinee's type; the results come from the yields through RegionBranchOpInterface |
| `idr.closure @f` (U01) | Flow.cpp, external model | Source `@f` → `V(result)`; for each capture `i`: Flow `O(capture i)` → `P(f, i)` |
| `idr.suspend @f` (U01) | Flow.cpp, external model | Source `@f` → `V(result)`; for each capture `i`: Flow `O(capture i)` → `P(f, i)`; Unify `R(f, 0)` with `Z(result type)` |
| `idr.delay %value` (U01, C02) | Flow.cpp, external model | Flow `O(value)` → `Z(result type)`; the result holds no label |
| `idr.force` (U01) | Flow.cpp, external model | when the operand is lazy: Flow `Z(operand type)` → `V(result)` |
| `idr.apply` (U01) | Flow.cpp, external model | Dispatch: the op |
| `idr.lin.enter`, `idr.lin.use` (U01) | Flow.cpp, external model | Flow `O(operand 0)` → `V(result)` |
| `idr.yield`, `idr.match_lit` (U01) | none | RegionBranchTerminatorOpInterface and RegionBranchOpInterface, read by `flowEdgesOf` |
| `idr.array.new` (U11, C11) | Flow.cpp, external model | Flow `O(fill)` → `E(element type of the array)` |
| `idr.array.set` (U11, C11) | Flow.cpp, external model | Flow `O(value)` → `E(element type of the array)` |
| `idr.array.get` (U11, C11) | Flow.cpp, external model | Flow `E(element type of the array)` → `V(value)` |
| `idr.tie_shape`, `idr.nat.to_extent` (U11) | none | no keyed value: a whole array is not keyed |
| `tensor.insert` | Flow.cpp, external model | Flow `O(scalar)` → `E(element type of dest)` |
| `tensor.extract` | Flow.cpp, external model | Flow `E(element type of tensor)` → `V(result)` |
| `tensor.from_elements` | Flow.cpp, external model | for each element: Flow `O(element)` → `E(element type of result)` |
| `tensor.splat` | Flow.cpp, external model | Flow `O(input)` → `E(element type of result)` |
| `tensor.yield` | Flow.cpp, external model | Flow `O(operand 0)` → `E(element type of the parent's result)` (the parent is `tensor.pad` or `tensor.generate`) |
| `ub.poison` | Flow.cpp, external model | nothing: a poison is no value the program computes |
| `cf.br`, `cf.cond_br`, `cf.switch`, `scf.*` | none | BranchOpInterface, RegionBranchOpInterface, RegionBranchTerminatorOpInterface, read by `flowEdgesOf` |

`idr.lambda`, the region form of `idr.delay` and `idr.array.generate` and
`idr.array.fold` do not exist after the cutover (D37; C02; C11) and get no
edges. A whole tensor or memref is not keyed: its element moves only
through `E` (0003 §4.5, D28, D41).

### What the solve makes of an edge (C06 implements it)

- **Flow** is inclusion. Its carrier being lazy makes it a Unify: a memo
  cell is shared, so its sets are unified, never coerced (MLton's rule
  for mutable cells, `sources/code/mlton/mlton/closure-convert/abstract-value.fun:123-148`).
- **One sink per operand.** A second Flow from one operand unifies its
  target with the first (a `scf.for` init reaches the iteration argument
  and the result alike).
- **Constant** at a point of carrier `t`: a `ClosureAttr` of `@f` at a
  closure carrier is Source `@f` there, each capture `i` a Constant at
  `P(f, i)`; at a lazy carrier the same and Unify `R(f, 0)` with `Z(t)`;
  a `ConAttr` at a data carrier `T` is, for each field `i` of the
  constructor it names (runs walked by cells, `eachField`, C06), a
  Constant at `F(T, c, i)`; any other part holds no label. A shared part
  at one point is expanded once per solve.
- **Dispatch** of a call with callee `k`, arguments `a` and results `r`:
  each label `@f` reaching `k` adds Flow `O(a i)` → `P(f, captures + i)`,
  `captures` being `f`'s parameter count less `a`'s length, and Flow
  `R(f, j)` → `V(r j)`.
- **Parameters** of a function with a body are its entry block's
  arguments: `P(f, i)` and `V(entry argument i)` are one point.

### Invariants

- The flow rule holds on every op nested in every `idr.func` body after
  every pass: U01's `FuncOp::verifyRegions` calls `verifyFlow` on each op
  of the body (today it walks the body at `lib/IR/Func/Func.cpp:84-93`).
  An op with a model is checked edge by edge (ends and carriers); an op
  without one is checked for a declaration of every keyed value. A
  registry without `registerFlowInterfaceExternalModels` therefore fails
  verification on the first closure, loudly.
- Every edge an op declares joins two ends of one carrier (D27); a label
  enters a point only along such an edge from the op that named it, whose
  own verifier fits the label to its carrier
  (`ClosureOp::verifySymbolUses`, `lib/IR/OpsClosures.cpp:155-171`;
  `SuspendOp::verifySymbolUses`, `:201-217`). Parameter and result ends
  are checked by the op's `verifySymbolUses` or verifier
  (`lib/IR/Func/Call.cpp:41-75, 106-118`).
- No edge has an unknown end, and there is no edge kind for one.
- After `idr-defunctionalize` no value is keyed, so every op adds no edge.

### Constructors

Only the models in `Flow.cpp` and `flowEdgesOf` add edges. Only the label
solve (C06) and the flow rule read them. Only U06's tools call
`registerFlowInterfaceExternalModels`, on every registry a module is read
with (the driver's handoff registry, `idris-mlir-opt`'s,
`idris-mlir-reduce`'s), and each includes `idr/IR/Flow.h` for it.
