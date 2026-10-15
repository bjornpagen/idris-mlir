## C24 Expect properties

`idr-expect` is the test API of the dialect suite and of every
`mlir.expect` file: a test names a property, never the ops that happen to
show it. This contract fixes the pass entry, the C++ declarations, every
property after the cutover, and how a property finds the functions it is
stated of. Producer: U17, alone. Consumers: U06 (the pass's row in C12,
and `idris-mlir-opt`'s `registerAllPasses`, which the fixtures need for
upstream passes), U18 (every `mlir.expect` under `tests/programs`, and
`tests/lib/expect.sh`, `properties.sh`, which call the pass), U16 (C23:
the location rule of deduplication below), U11, U12, U03 (each supplies
one predicate a property reads, listed under "Predicates read from other
lanes").

### The pass entry (C12's row; U06 writes it)

`IdrExpect`, argument `idr-expect`, anchor `ModuleOp`, as C12 fixes it:
the one option `ListOption<"holds", "holds", "std::string", "The
properties that must hold">`, a test API (0004 §6, "Kept") that selects
which checks run, never how anything compiles; dependent dialects `idr`,
`func`, `arith`, `math`, `ub`, `memref`, `tensor`, `scf`. Its description
names no property: the list is held once, as the comment on each
property's declaration in `Expect.h` and the names `lookup` knows. No
property needs another dialect loaded: a property that looks for linalg
or vector ops tests an op's dialect or interface, and finds none when the
dialect was never loaded.

### The header (`foreign/idr/include/idr/Transforms/Expect.h`, U17)

Replaces today's header (`Expect.h:1-109`). Exactly these declarations:

```cpp
namespace idr {
#define GEN_PASS_DECL_IDREXPECT
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::expect {
using Check = mlir::LogicalResult (*)(mlir::ModuleOp module, mlir::AnalysisManager &analyses,
                                      llvm::StringRef argument);
Check lookup(llvm::StringRef name);
mlir::InFlightDiagnostic fail(mlir::Location loc, llvm::StringRef property);
std::string where(mlir::Operation *op);
// Whether `fn` is made from the code written as `f` (the rule below).
bool names(mlir::FunctionOpInterface fn, llvm::StringRef f);
llvm::SmallVector<mlir::FunctionOpInterface> named(mlir::ModuleOp module, llvm::StringRef function,
                                                   llvm::StringRef property);
llvm::SmallVector<mlir::Operation *> rootsOf(mlir::ModuleOp module, llvm::StringRef function,
                                             llvm::StringRef property);
// The functions the body of `fn` names by a symbol use, in walk order.
llvm::SmallVector<mlir::Operation *> callees(mlir::SymbolTable &symbols, mlir::Operation *fn);
llvm::SmallVector<llvm::SmallVector<mlir::Operation *>>
cycles(llvm::ArrayRef<mlir::Operation *> nodes,
       llvm::function_ref<llvm::SmallVector<mlir::Operation *>(mlir::Operation *)> edges);
// One function per property, each of type Check: noClosures, noHeapAllocation,
// oneClone, notCalled, quantitiesKept, reusesInPlace, movesOut, countsNothing,
// noGuards, testsNothing, resetsUnshared, reusesEveryCell, contified,
// factsAsMarked, outputFused, foldsBalanced, constantStack, countedLoop,
// wordLoop, structuredLoops, typedReads, inPlace, fused, largestFunction,
// vectorized, narrowedLanes, cellsFit.
} // namespace idr::expect
```

`names`, `named` and `rootsOf` lose today's `SymbolTable &` parameter
(`Expect.h:56-67`): the rule reads no symbol table. `referencedBy`
(`Expect.h:71`), which read `idr::References`, is replaced by `callees`,
which reads symbol uses (`SymbolTable::getSymbolUses`), as `constant-stack`
already does (`Expect/ConstantStack.cpp:41-50`), so idr-expect depends on
no analysis of the optimizer.

### How `@f` finds its functions (`Expect/Named.cpp`)

`names(fn, f)` holds exactly when one of these holds:
1. `fn`'s symbol is `f`;
2. `fn`'s own location names `f`: a `NameLoc` whose name is `f` is reached
   from `fn->getLoc()` through `NameLoc` children and `FusedLoc` members
   (any metadata, so Emit's `fused<"library">` wrapper is seen through);
   `CallSiteLoc` and `OpaqueLoc` are not entered.

Nothing else: no `instance` fact, no `clone` key, no symbol table, no
chain. Why each source of a copy satisfies rule 2:
- Emit writes every function's location as `NameLoc(<Idris definition>,
  <span>)` (`Emit/Declarations.idr:79`), and a lambda's or delay's function
  as `NameLoc(<its enclosing definition>, <its span>)`, as Isolate writes
  it today (`Isolate/Isolate.cpp:126-129`; C22 keeps both).
- A copy a pass makes (a specialization node, `.acc`, `.trmc`, `.excl`, an
  arity raising) is an `Operation::clone` of its original and keeps its
  location.
- Deduplication keeps one function of each class and gives it the
  location `FusedLoc::get(ctx, {<each member's location>})`, members in
  the class's symbol order (C23). So the code of a merged function is
  found in the one kept.

A hand-written fixture names a function by its symbol, or gives it
`loc("f")` where the test must find its copies too.

`named(module, function, property)` strips the leading `@`; an empty name
fails with `expected <property>: no function named`; no match fails with
`expected <property>: no function <function>, and no copy of it`.
`rootsOf` is the module itself for an empty argument, else `named`'s
functions.

### The properties after the cutover

Each property is one `Check` in its own unit under `lib/Transforms/Expect/`.
Every error is `expected <name>: <what>` at the place it fails.

| Property | Unit | Rule (what fails) |
| --- | --- | --- |
| `no-closures` | `Closures.cpp` | an `idr.closure`, an `idr.apply`, or an `idr.constant` of a `ClosureAttr` whose type is not lazy |
| `no-heap-allocation[=@f]` | `Allocation.cpp` | an op with an `Allocate` effect on a resource other than `LinResource` and `AutomaticAllocationScopeResource`, an `idr.closure`, an `idr.suspend`; with `=@f`, in @f and every function reached through `callees`; a reached function without a body, and an `idr.apply` of a value not made in the function |
| `one-clone=@f` | `Clones.cpp` | the `idr.call`s whose callee `names` f reach more than one symbol, or none |
| `not-called=@f` | `NotCalled.cpp` | an `idr.call` whose callee `names` f |
| `quantities-kept=<file>` | `Quantities.cpp` | a binder (function parameter, match-bound field) whose quantity differs from the emitted module's, binders keyed by location as today (`Quantities.cpp:39-60`). Constructor fields are no longer compared: a data type's body is set once (C01), and the emitted module, parsed into the same context, names the same types, so a field's quantity cannot change under one name |
| `reuses-in-place=@f` | `ReusesInPlace.cpp` | an `idr.con` of a box type in @f, or no `idr.reuse` |
| `moves-out[=@f]` | `MovesOut.cpp` | no world-ordered array read in the roots moves its element out (C11's world-ordered get and its `moves` fact) |
| `counts-nothing=@f` | `CountsNothing.cpp` | an `idr.dup` or `idr.drop` in @f, other than a dup of a constant |
| `no-guards=@f` | `Guards.cpp` (new; today's `InBounds.cpp:80-89`) | an op of `GuardOpInterface` in @f |
| `tests-nothing=@f` | `TestsNothing.cpp` | a take of, or a reuse into, a value whose type is not exclusive; or no take |
| `resets-unshared[=@f]` | `ResetsUnshared.cpp` | a take with a token whose cell its function gives a second reference |
| `reuses-every-cell=@f` | `ReusesEveryCell.cpp` | an `idr.drop` of a take's token for a constructor with fields, the fields read from the identified type's body (C01) |
| `contified` | `Continuations.cpp` | a private function with one use, a call from another function that it calls back |
| `facts-as-marked` | `Facts.cpp` | an op whose `expect.facts` mark differs from `drop move delay` as the dialect answers them |
| `output-fused` | `Output.cpp` | an `idr.io.put_str` of what `writtenInPieces` recognizes |
| `folds-balanced` | `Folds.cpp` | the dialect's fold leak count is not 0 |
| `constant-stack=@f` | `ConstantStack.cpp` | a cycle of references from @f with a member that refers to another member by anything but a `musttail` call |
| `counted-loop=@f` | `CountedLoop.cpp` | an `scf.while` in @f, or no `scf.for` |
| `word-loop=@f` | `Words.cpp` | every loop of @f holds a big or natural (`narrow::isBig`), or @f has no loop |
| `structured-loops[=@f]` (new) | `StructuredLoops.cpp` | a loop in the roots for which `idr::structure::structurable` answers true (it would still be structured), or no `linalg` op in the roots |
| `typed-reads=@f` (new) | `TypedReads.cpp` | an index operand of a `tensor.extract`, `tensor.insert`, or a dynamic offset of a `tensor.extract_slice` or `tensor.insert_slice` in @f, that is the result of a `GuardOpInterface` op, looked through `arith.index_cast` and `arith.index_castui`; or no such access in @f |
| `in-place[=@f]` (new) | `InPlace.cpp` | an op in the roots for which `idr::bufferize::copies` answers true (C15: a `memref.copy` whose target a `memref.alloc` made; a copy of a slice into a live buffer is the slice's meaning, no such copy); or no value whose type, its grade stripped (`unrestricted`), is a `MemRefType` in the roots |
| `fused=@f` (new) | `Fused.cpp` | a result of a `linalg::LinalgOp` in @f with exactly one use, that use a `linalg::LinalgOp`; or no `linalg::LinalgOp` in @f |
| `largest-function=<n>` (new) | `Sizes.cpp` | an `idr.func` with a body whose size by `idr::inlineSize` is above n (n a decimal integer; another argument fails with `expected largest-function: name the bound, as largest-function=<n>`) |
| `vectorized[=@f]` | `Vectorized.cpp` | no vector-dialect op in the roots, or a `linalg.generic` with a parallel dimension and a body of words alone |
| `narrowed-lanes[=@f]` | `NarrowedLanes.cpp` | as today (`NarrowedLanes.cpp:51-104`), with one change: the ops `idr::narrow::accumulations(loop)` returns (U09's rule of what idr-narrow-lanes leaves wide, `include/idr/Transforms/Narrow.h:115-121`: the ops that only combine into a vector the loop carries) are no lane the property counts, since a sum is as wide as the program made it |
| `cells-fit` | `CellsFit.cpp` | a box constructor's cell, or an array's element, holding more counted references than `layout::mostObjects`, reported at the module and named by the data type and the constructor through C01's `layout::Holders::overflows(Components &, function_ref<void(DataType, std::optional<unsigned> tag, ArrayRef<Type>, unsigned)>)` |

**Deleted properties** (their units go): `every-cycle-has-breaker`
(`EveryCycleHasBreaker.cpp`) and `breaks-last` (`BreaksLast.cpp`), with
the loop breakers; `in-bounds=@f` and `bounds-checked=@f`
(`InBounds.cpp:51-78`), with `idr-in-bounds` and `inbounds::accessedArray`;
`pure-array-loops[=@f]` (`PureArrayLoops.cpp`), with `idr.array.generate`
and `idr.array.fold`, replaced by `structured-loops`. A request for a
deleted name is `idr-expect: no property named <name>`, the error every
unknown name gets (`Expect.cpp:39-43`).

### Predicates read from other lanes

A property that states what a pass guarantees asks the pass's own test,
so the rule is held once:
- C11 (U11): `bool idr::structure::structurable(mlir::Operation *loop);`
  in `include/idr/Transforms/StructureLoops.h`: true exactly for a loop
  the patterns of `idr-structure-loops` rewrite.
- C15 (U12): `bool idr::bufferize::copies(mlir::Operation *op);` in
  `include/idr/Transforms/Bufferize.h` (C15 section 2: a `memref.copy`
  whose target a `memref.alloc` made).
- C08 (U03): `int64_t idr::inlineSize(idr::FuncOp fn);` in
  `include/idr/Analysis/Inline.h`: the size the inline decisions and the
  10,000-op caller cap (D25) read, what a walk of the body counts.
- C11 (U11): the world-ordered array read that moves its element out, and
  its accessor (today `ArrayGetOp::getMoves()`, `MovesOut.cpp:26`).
- C01 (U01): `DataType::getCtor(unsigned)`, `Ctor::fields`,
  `DataType::getName()`, `layout::Holders::overflows` with C01 §9's
  callback; C02's `TakeOp::getDataType()` and `TakeOp::getTag()`.
- `idr::narrow::runsAtMostOnce(scf::ForOp)`, `idr::narrow::isBig(Type)`
  and `idr::narrow::accumulations(Operation *)` in
  `include/idr/Transforms/Narrow.h` (U09's file; `NarrowedLanes.cpp`,
  `Words.cpp`).

### Invariants

- idr-expect changes nothing and preserves every analysis
  (`Expect.cpp:46`).
- A property reports every place it fails, one error each, and fails if it
  reported one.
- An unknown name is an error, so a misspelled or deleted property cannot
  pass.
- No property reads a function's name except through `names`, and none
  reads `instance`, `clone` or a specialization key.
