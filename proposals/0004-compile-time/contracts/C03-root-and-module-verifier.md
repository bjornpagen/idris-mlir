## C03 The root and the module verifier

Producer: U01. Decisions: 0004 D7, D28, D31, §4 stage 2. The closed world is
a verified invariant and needs no mark: `idr.program` goes
(`IdrBase.td:58`, `Verify/Attributes.cpp:22-29`).

### 1. Every function is defined; the root is the one public function

`idr::FuncOp::verify()` (`lib/IR/Func/Func.cpp`), which reads only the op:

- An `idr.func` without a body is refused: "expects a body: every function
  of the program is defined in it". The early return for an external
  function (`Func/Func.cpp:85-86`) goes.
- A public `idr.func` is the root, so its type is `() -> i64` or
  `(!idr.world) -> (...)` (today's two, `Verify/Program.cpp:32-40`).

So no verified module has an external `idr.func`; `isExternal()` stays only
because `FunctionOpInterface` asks it. The tests of it in analyses and
passes before lowering go (D7); the lowered `func.func` and `llvm.func`
keep theirs (the runtime's declarations).

### 2. The module rules run from the root's symbol-use verifier

`idr.func` declares `DeclareOpInterfaceMethods<SymbolUserOpInterface>`.
`FuncOp::verifyRegions` first holds every op nested in the body to the flow
rule, `idr::verifyFlow(op)` (C05; `lib/IR/Func/Func.cpp` includes
`idr/IR/Flow.h`), then linearity and the owned stage as today.
`FuncOp::verifySymbolUses(SymbolTableCollection &)` of a public function
runs the module rules on its parent module; a private one's does nothing.
Upstream calls `verifySymbolUses` once per verification of the module, after
every op of it is verified, on one thread (`M/lib/IR/SymbolTable.cpp:484-500`),
and never when a pass manager verifies one function: so the rules may assume
every op's own verifier passed, and no function pass meets them. A module
with no public function is a fragment, which gets each function's rules
only (D28).

```cpp
// include/idr/IR/Verify.h
namespace idr::verify {
// The module's rules, run by its root's symbol-use verifier: one public
// function; every data type its ops hold, or a body holds, has a body; a
// box's data type has at most IDRIS_RT_TAG_LIMIT constructors, else the
// refusal `layout` (C04); a memo sum is held only in a box; containment in
// place is acyclic; no array can reach itself (`knots`, the refusal `cycle`).
mlir::LogicalResult program(mlir::ModuleOp module);
mlir::LogicalResult knots(mlir::ModuleOp module, const TypeGraph &graph);  // as today
}
```

The rule "every sum or box type names a declaration of its kind"
(`Verify/Program.cpp:46-90`) goes: a type carries its body (C01). The type
walk is one `TypeGraph` of the module (C01 §8).

### 3. Diagnostics (fixtures check these words)

- `'idr.func' op expects a body: every function of the program is defined in it`
- `'idr.func' op is the root, so its type must be () -> i64 or (!idr.world) -> (...), not <type>`
- `'builtin.module' op expects exactly one public function (the root), found <n>`
  (reported once: the symbol-use walk stops at its first failure)
- `unsupported (layout): the boxed type "<name>" has <n> constructors, and a boxed type has at most 65536` (at the module)
- `'builtin.module' op holds the memo sum "<name>" in place; a memo sum is held only in a box`
- `'builtin.module' op holds the data type "<name>", which has no body`
- `'builtin.module' op holds the data type "<name>", which contains itself in place; a recursive type is held through a box`
- the `cycle` refusal: as today's text (`Verify/Knots.cpp:100`), at the first
  `idr.array.new` in the program's source that makes one of the cycle's
  arrays, else at the first `idr.con` in the program's source of a type on
  the cycle (a data type has no location of its own), else at the module.
  So `tests/reject/cycle-ioref-knot` moves from the type's line (16) to the
  constructor's (18): NEEDS-ACCEPTANCE for U18.

### 4. Consumers

U02 (the corpus and stage 0 verify), U08, U09, U10 (no `isExternal()` on
`idr.func`), U15 (emits one public root, every function with a body, no
`idr.program`), U17 (fragments with no root or one root, every function
defined; the fixtures of §3), U18.
