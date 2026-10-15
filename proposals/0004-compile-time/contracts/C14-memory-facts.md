## C14 Memory facts: the stack property, the in-place promise, counting over buffers

Producer: U08 (idr-stack, idr-rc, idr-demand; `lib/Transforms/Ownership`,
`Stack`, `Demand`, `lib/Analysis/Ownership`, `Escapes*`). Paths are under
`foreign/idr/` unless named; line numbers are the tree at a3e61f3a. A
declaration this contract names in another lane's file is written by that
lane exactly as given here; the lane is named with it.

### 1. `stack`, an inherent property of `idr.con` (0004 D19, §6)

**Declaration** (U01, `include/idr/IR/IdrOps.td`, `Idr_ConOp`, exactly as
C02 §2 writes it). Replaces the dialect's discardable `stack`
(`IdrBase.td:58`), whose helper `IdrDialect::StackAttrHelper` goes with it.
- `UnitAttr:$stack`, an inherent attribute, the last entry of
  `Idr_ConOp`'s `arguments`.
- In `assemblyFormat`, `` (`stack` $stack^)? `` comes right after the
  fields' closing `` `)` `` and before `attr-dict`: a con on the stack
  prints `idr.con @Cons(%x, %xs) stack : (...) -> ...`, a heap con as
  today.
- Generated, never hand-written: `bool ConOp::getStack()` and
  `void ConOp::setStack(bool)` (as `UnitAttr:$total` gives `FuncOp`
  `getTotal`/`setTotal`). A con built without it is a heap cell.

**Meaning.** True: idr-lower builds the cell in a slot of the entry block
of the function that holds the con, one slot per con, its header count 1
with `IDRIS_RT_STACK_CELL` (`runtime/idris_rt.h:104`); counting works on it
as on any cell, its fields are released when its count reaches 0 and its
memory is never freed; it is never exclusive and never reused.

**Invariants.**
- `getStack()` is true only on a con whose `unrestricted` result type is
  an `!idr.box`: `ConOp`'s verifier (U01) refuses any other, with the text
  of today's rule (`lib/IR/Verify/Attributes.cpp:30-35`, which goes).
- In the owned stage, a con with `getStack()` never has an exclusive
  result type: the owned-stage verifier (U01, today `Verify/Owned.cpp:207-209`)
  reads `getStack()`.
- No idr-rc reuse targets a stack con, and no take of a stack box gives
  a token any reuse builds in (U08, Reuses).

**Writer.** idr-stack alone sets it, on every con of the module, true or
false, each run (it decides every con again; a value it does not keep is
false afterwards). Every other pass keeps it: cloning or moving an op
keeps its inherent attributes; a pass that builds a new con builds a heap
cell.

**Readers.** U01: `ConOp::getEffects` (`AutomaticAllocationScopeResource`
when true, `lib/IR/OpsCon.cpp:33-45`), the owned-stage verifier. U08:
`Reuses` (`Reuses.cpp:159-167, 190-199`), `Exclusivity` (a stack con's value
is shared, `Exclusivity.cpp:115-120`). U10: `stackCell`
(`lib/Conversion/Cells.cpp:51-53`). U17: the `tests/idr/stack` fixtures,
which print it. The frontend never writes it (U15), and the generated
`Dialect/Idr.idr` has no `stackDiscardable` (U01).

### 2. The in-place promise (0004 §4 stage 1, D19, D29; 0003 D33)

**Representation.** The kind of an identified data type's body:
`SumKind::InPlace`, printed `in_place` (C01 §2), set once with the body. A
type *carries the promise* when `DataType data = dataTypeOf(type)` is
non-null and `data.hasBody() && data.getKind() == SumKind::InPlace`. The
frontend writes the kind on every instance of a type the registry names
as "rebuilt in place, exclusive" (C20, C22): the `mlir-linear` types.
Nothing else carries it, and no option, attribute or pass decides it.

**Meaning.** A function that takes a value of the type apart and builds in
its cell does so with no runtime test: every caller passes it holding the
cell alone.

**The check** (U08, `lib/Transforms/Demand/Demand.cpp`, pass `idr-demand`,
C12 row 14, after idr-rc). For every `idr.func` `f`:
- a *promised parameter* is an entry argument `p` of `f` with
  `isLinear(p.getType())`, whose type's identified data type carries the
  fact, and such that some `idr.reuse` in `f` takes its token from an
  `idr.take` of `p`, seen through `idr.lin.enter`, `idr.lin.use`,
  `idr.borrow` and the default region of a match on it;
- every `idr.call` of `f` passes, at each promised position, a value of
  type `!idr.excl<...>` (`idr::isExclusive`);
- a call that does not is a refusal with rule `uniqueness` (C04,
  `idr::refuse(call, Rule::Uniqueness)`), at the call, text `@<caller> passes a shared <name> to @<callee>, which
  rebuilds it in place` (`<name>` the identified type's `getName()`, C01), with
  a note `shared here` at the `idr.dup` that shared the value (seen
  through linear positions) when one did. When some failing call has such
  a dup, only those calls are reported; otherwise every failing call is.
- The pass changes nothing and preserves every analysis.

**Not this fact.** A linear array's promise (`LArray`, `!idr.lin<tensor>`)
is the links' `mustBufferizeInPlace` in One-Shot (C15, 0003 D33): tensors
and cells keep their promises in two representations, and neither is held
twice. idr-demand reads no tensor.

**Consumers.** U14 and U15 (write the kind), U01 (the kind and its
accessor), U08 (the check), U17 (dialect fixtures of the check), U18
(`tests/reject/uniqueness-shared-rebuild` and the `tests/programs/linear`
programs, with no fixture file and no option).

### 3. Counting over buffers (0003 §7, §8, D17, D18, D42)

Bufferization runs before counting, so idr-stack, idr-rc and everything
after them see memrefs, and no tensor (C15 §7). A *buffer* is any memref
value: its descriptor's allocated pointer is a runtime cell (C17 §1), so
it holds a reference, one count of that cell. An element is *counted*
when `holdsReferences` (C01) says so of the memref's element type.

| op | what counting does with it |
| --- | --- |
| `memref.alloc` (One-Shot's `allocationFn`, C15 §7) | a fresh cell, one reference, every counted element empty (C17 §3). Its result keeps the plain carrier and one use, the `idr.own.adopt` idr-rc's first step puts right after it, whose owned result every other use reads. Counting places nothing for the alloc's result itself. No op of ours allocates |
| `idr.own.adopt` (U01) | takes over the fresh reference of the `memref.alloc` it follows: its result is owned, and counting places it as any owned value |
| `memref.subview`, `memref.cast`, `memref.reinterpret_cast`, `memref.expand_shape`, `memref.collapse_shape`, `memref.transpose`, `idr.tie_shape` on a memref | its result is read from its source operand (`readFrom`): a view, alive as long as the source; a consuming use takes an `idr.dup` of it |
| `memref.copy` (One-Shot's `memCpyFn`, C15 §7) | borrows both operands; the runtime counts the elements it copies and the ones it overwrites (C17 §4) |
| `memref.dim`, `memref.extract_strided_metadata` | borrow their buffer |
| `memref.load` of a counted element | its result is read from the buffer (`readFrom`) and is never borrowed: idr-rc puts an `idr.dup` of it right after the load, which replaces its every other use. An element may be written while a view of it would still be read; a cell's field never is. The load itself takes no reference (C16 §4.4) |
| `memref.store` of a counted element | its value operand is the result of an `idr.own.give`, which idr-rc's first step puts right before it and which is the value's one producer: the give consumes the owned value and hands its reference to the store, which releases the element it overwrites and moves the value in (C16 §4.4, §5). Counting places nothing for the give's result |
| `idr.own.give` (U01) | consumes its operand (`Idr_Consumes<"0">`): its one use is the value operand of a counted `memref.store` |
| `memref.load`, `memref.store` of an uncounted element | borrow the buffer; the element is untracked |
| `scf.for` | a loop: control operands untracked; inits consumed (`lib/IR/Effects.cpp:39-40`); in the body the induction variable is untracked, each iter argument owned, `scf.yield` consumes; results owned; a value from outside the body is borrowed for the whole loop |
| a `linalg::LinalgOp` with `hasPureBufferSemantics()` none of whose payload arguments holds references | a loop: its buffers are borrowed; its payload runs once per index; a value from outside is borrowed for the whole op |
| a `linalg::LinalgOp` with pure buffer semantics one of whose payload arguments holds references | does not reach counting: idr-rc's first step turns it into its `scf.for` loops with upstream `linalg::linalgOpToLoops`, whose loads and stores the rows above count (C16: a structured op over elements of ours is loops before counting) |

- **The first step.** `mlir::LogicalResult idr::ownership::bufferForms(FuncOp)`
  (`include/idr/Transforms/Ownership.h`, U08) makes the last row's loops,
  then puts an `idr.own.adopt` after every `memref.alloc` (every other use
  of the allocation reads the adopt) and an `idr.own.give` before every
  counted `memref.store` (the store's operand 0 becomes the give's result),
  on every function in parallel, before reset/reuse and borrow inference
  read the module: both decide by which use consumes a value, and the give
  is where a stored value is consumed.
- **Classes** (U08): the result of a `memref.alloc` and of an
  `idr.own.give` are untracked: their one use moves their reference.
  Placement retypes the adopt's result as every owned value; the give's
  operand is a consuming use, which gets an `idr.dup` when its value is a
  view. The commit needs no case: neither op's result is followed, and an
  exclusive operand of a give is still owned (`isOwned`).
- **Exclusivity follows no buffer:** a buffer is never `!idr.excl<...>`;
  `ownership::followed` is boxes, unboxed sums and tokens (U08).
- **The regions idr-rc counts:** `idr.match`, `idr.match_lit` and the two
  loops above, each region one block. Any other is idr-rc's internal
  error.
- **Escapes** (idr-stack, before idr-rc) knows no memref op: a box stored
  into a buffer, or built under a `scf.for` or a linalg op, stays on the
  heap (`Escapes.cpp:162-176, 292`). Unchanged.

**The shared vocabulary U01 writes from this table** (one meaning for
idr-rc and the owned-stage verifier):
- `include/idr/IR/Ownership.h`: `bool idr::ownership::isIndexLoop(mlir::Operation *op);`
  replaces `isArrayLoop` (`:48-50`) and its definition
  (`lib/IR/Verify/Uses.cpp:111-118`): true for an `scf::ForOp`, and for a
  `linalg::LinalgOp` with `hasPureBufferSemantics()`; false for every
  other op. Comment: "Whether `op`'s region is the body of a loop over
  indices, which runs once per index it covers."
- `idr::ownership::readFrom(Value)` (`Uses.cpp:37-46`) also returns: the
  source operand of the view ops of the table's second row, and the memref
  operand of a `memref.load` whose element is counted.
- `bool idr::ownership::reachesOnlyAtoms(mlir::Value view);` with no
  declaration callback (today's `IR/Ownership.h:46`).
- `idr::consumes(OpOperand &, SymbolTable *)` (`lib/IR/Effects.cpp:17-42`):
  unchanged; `idr.own.give` answers by its `Idr_Consumes<"0">`, and
  `memref.store` is no consuming position (the give before it is).
- `holdsReferences` (C01) is true of every memref type; the counted type
  constraints of `idr.dup`, `idr.drop` and `idr.borrow`
  (`Idr_CountedValueType`, `IdrOwnershipOps.td:39`) take every memref
  type, any rank, static or dynamic, any layout.
- The owned-stage verifier checks the table after every pass: a counted
  `memref.load`'s one use is an `idr.dup` that is the next op of its
  block; a `memref.alloc` result's one use is an `idr.own.adopt`; a
  counted `memref.store`'s value is an `idr.own.give`'s result whose one
  use it is; `scf.for` and linalg buffer ops are walked as loops.

**The lowering U10 gives these** (C16 §4, §5): `idr.dup` and `idr.drop` of
a buffer count its cell, the descriptor's allocated pointer; a counted
`memref.load` is a plain load, with no increment; a counted `memref.store`
releases the old element's object slots, then stores; `memref.alloc` calls
`idris_rt_array_new` (C17 §3), `memref.copy` `idris_rt_memref_copy`
(C17 §4).

**The two boundary ops** (coordinator's decision of 2026-10-14; U01
declares them in `include/idr/IR/IdrOwnershipOps.td`, defines nothing
else for them, exactly). Upstream's buffer ops see plain carriers:
`memref.alloc`'s result is `AnyMemRef` (`AllocLikeOp`) and
`memref.store`'s value the memref's element type (`MemRefOps.td:2064-2067`),
so neither can hold `!idr.own<T>`, which placement gives an owned value
(`Placement.cpp:110`). These two ops are where the grade starts and ends
there, and change no count, as `idr.lin.enter` and `idr.lin.use` are for
linear values:

```tablegen
// Takes over the fresh reference of a buffer memref.alloc made, whose
// result is a plain memref: the owned stage's one way into a grade for an
// allocation of upstream's. Nothing at runtime.
def Idr_OwnAdoptOp : Idr_Op<"own.adopt", [Pure,
    TypesMatchWith<"the result is the buffer owned", "memref", "result",
                   "::idr::owned($_self)">]> {
  let summary = "takes over the fresh reference of a buffer memref.alloc made";
  let arguments = (ins AnyMemRef:$memref);
  let results = (outs Idr_OwnType:$result);
  let assemblyFormat = "$memref attr-dict `:` type($memref)";
  let hasVerifier = 1;   // the operand is a memref.alloc result, its one use
}

// Hands an owned value's reference to the memref.store that writes it,
// whose value is the plain carrier. Nothing at runtime: the store releases
// the element it overwrites and the value moves in.
def Idr_OwnGiveOp : Idr_Op<"own.give", [Idr_Consumes<"0">,
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    TypesMatchWith<"the result is the value without its reference", "value", "result",
                   "::idr::view($_self)">]> {
  let summary = "hands an owned value's reference to the store that writes it";
  let arguments = (ins Idr_OwnType:$value);
  let results = (outs AnyType:$result);
  let assemblyFormat = "$value attr-dict `:` type($value)";
  let hasVerifier = 1;   // one use: the value operand of a memref.store
}
```

- C++: `idr::OwnAdoptOp` and `idr::OwnGiveOp`, built by idr-rc alone as
  `OwnAdoptOp::create(b, loc, memref)` and `OwnGiveOp::create(b, loc,
  value)` (the result type inferred, as `BorrowOp::create(b, loc, value)`
  is); the give's effects are `consumedEffects` (`IdrDialect.h:73-76`).
  idr-rc builds both before it grades, on plain values, as it builds
  every op of the owned stage.
- Lowering (U10, C16): each is its operand's value; no runtime call.
- Consumers: U08 (makes them, `Reshape.cpp`'s `boundaries`, read by
  `Classes`), U01 (declares and verifies them), U10 (lowers them), U17
  (fixtures).

### 4. The exclusive copies (0004 §6, D18)

idr-rc gives the calls whose every followed argument is exclusive a copy
of their callee whose followed parameters are exclusive (step 4,
`lib/Transforms/Ownership/Specialize.cpp`).
- **Key:** (the original `idr.func`, its exclusive context: the ascending
  positions of its followed parameters, `ownership::followed`). One key
  per function at most, so one copy.
- **Name:** C21's rule `<owner>.<kind>.<hex16>` through U01's C++ helper:
  owner the original's symbol name, kind `excl`, key the positions in
  decimal joined by `,` (positions 0 and 2: the key `0,2`, the name
  `<owner>.excl.<hex16 of "0,2">`). Never a counter, never the symbol
  table's rename: a name the table already holds is a collision, an
  internal error at the original.
- **Made once,** in a round in which the key first appears, as a clone of
  the original that keeps every inherent fact of it, private, inserted
  right after its original. Keys are gathered for a whole round, in
  module order of their originals, before any copy is made.
- **Rounds:** solve, gather the keys, make the new copies, redirect every
  call whose arguments are all exclusive where some parameter is shared.
  A call is redirected once and a key made once, so a round that
  redirects nothing is the last. No counter bounds them.
- **An original** none of whose uses is left after the rounds is erased.
- **Consumers:** U17 (idr-expect finds a copy by structure, C24; the
  fixtures that named `<f>.excl`), U07 (the name is module content).

### 5. What idr-rc and idr-demand declare (C12)

`IdrRc` and `IdrDemand` have no option; their constructors are
`idr::createIdrRc()` and `idr::createIdrDemand()`; statistics as C12's
rows 13 and 14. The nested steps `idr-rc-place` and `idr-rc-commit` are
U08's `PassWrapper`s, built by idr-rc and registered nowhere:
`std::unique_ptr<mlir::Pass> idr::ownership::createRcPlace();` and
`createRcCommit();` in `include/idr/Transforms/Ownership.h`.
