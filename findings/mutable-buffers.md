# Mutable buffers: arrays, byte buffers and mutable strings

Stream "mutable-buffers". This is the complete design for Idris arrays
(`Data.IOArray`, contrib's `LinArray`/`IArray`), byte buffers (`Data.Buffer`)
and strings built by mutation, on MLIR's tensor → bufferization → memref
path. It covers:
- the dialect types, ops and verifier rules;
- the runtime object;
- mutation, lifetimes and bounds checks;
- strings;
- the upstream recursion gap and what we do until it is fixed;
- what the path unlocks in five benchmarks-game programs.

It builds on, and does not repeat:
- linear-libs.md, which showed that linear arrays bufferize in place to C's
  machine code, found the recursion gap, and listed the backend-contract
  primitives;
- memory-theory.md, on linearity versus uniqueness, and on why boxes cannot
  take the bufferization path (§6.10);
- decision-linear-libraries.md: no language change, no library of our own,
  and array primitives get registry meanings;
- representation.md R5 (`Fin` as `index`, `idr.fin.enter`) and R12
  (contiguous `Vect` as `tensor`).

It corrects one thing those notes proposed: arrays are freed by our
counting, not by ownership-based buffer deallocation (§6, with evidence).

The evidence is in mutable-buffers-experiments.md: E1–E7 from the first
run, E8–E16 from this one. The sketches were checked with the pinned
`mlir-opt`, `mlir-translate` and musl `clang`, and the built
`idris-mlir-opt`. The upstream reports are drafted in
mutable-buffers-upstream.md.

## The questions

1. Which types, ops and verifier rules carry arrays, and which of them must
   be ours?
2. What is the runtime object: its cell kind, header, growth, the release
   of counted elements, and allocation through MLIR's hooks?
3. How does mutation work? Unique arrays should become plain stores, and
   shared ones should be copied, as Lean does.
4. Who decides when an array dies?
5. How are bounds checks removed, and what does a known length or a `Fin`
   index buy?
6. How do strings fit, as byte buffers under the same discipline?
7. What do we do about the upstream recursion gap until it is fixed?
8. What do fannkuch-redux, spectral-norm, k-nucleotide, reverse-complement
   and fasta need, and how do they map onto linalg and vector?

## The global maximum

An Idris program over arrays, byte buffers or strings compiles to the code a
C programmer would write:
- one allocation per array;
- loops of loads and stores, with no count traffic inside them;
- a copy only where the source semantics demand a second array;
- a bounds check only where nothing proves the index is in range;
- whole-array loops in `linalg`, where MLIR fuses and vectorizes them.

Three parties divide the work, and each does only what it alone can do:

- **The Idris side chooses the representation** of each array family, from
  its Idris type and its source semantics (the table below). It keeps
  quantity 1 in the type, and a closed length in the shape.
- **MLIR decides where the bytes go and what is in range.**
  - One-Shot Bufferize decides every in-place write and every copy,
    statically. A copy it inserts is Lean's copy-on-write decided at compile
    time, with no runtime test.
  - IntegerRangeAnalysis and ValueBounds decide which checks are dead.
  - `linalg` and `vector` generate the loops.
- **Our counting decides when an object dies.** Every array is one runtime
  object kind, allocated through MLIR's own hooks. The counting that already
  frees cells frees arrays too, and that is the one ownership system.

| Idris | semantics in Chez (the reference) | idr type | where the bytes go | lifetime |
|---|---|---|---|---|
| contrib `LinArray t`, `IArray t` | one mutable `IOArray` underneath (E2): reference semantics behind a linear API | `!idr.lin<tensor<?xE>>` at binders, `tensor<?xE>` between ops; `tensor<NxE>` when the length is closed | One-Shot, in place; any copy is a divergence from Chez, so it is rejected | counting, on the bufferized `memref` |
| `IOArray`/`ArrayData`, `IOMatrix` | shared and mutable | `memref<?xE>` from the start | the program; the world orders the IO | counting |
| `Buffer` | shared mutable bytes | `memref<?xi8>` | the program | counting |
| `String` | an immutable value | `!idr.str` (unchanged), plus a borrowed byte view `memref<?xi8>` | the runtime: an append that consumes its left side extends it in place | counting (the box discipline) |
| future contiguous `Vect n a` (R12) | a value | `tensor<?xa>` with value semantics | One-Shot; a copy is legal | counting |

`E` ranges over the types that may be stored: `i8`–`i64`, `f64`,
`!idr.data<@T>` (flattened), and the counted references `!idr.box`,
`!idr.fn`, `!idr.str`, `!idr.big`.

## 1. Types

**Builtin types carry the arrays; idr adds only what they lack.**

- **Values are `tensor`, objects are `memref`.**
  - A value array is `tensor<? x E>`, or `tensor<N x E>` when Emit knows a
    closed length (after specialization or compile-time evaluation,
    `newArray 16`).
  - An object is `memref<? x E>` with the identity layout. A slice (a
    `Buffer` range, a string's bytes) is `memref<?xE, strided<[1], offset: ?>>`.
  - Nothing new is needed for either.
- **Element types: the interface is the rule.**
  - `!idr.data`, `!idr.box`, `!idr.fn`, `!idr.str` and `!idr.big` implement
    `MemRefElementTypeInterface` (BuiltinTypeInterfaces.td:165-176: "model
    an entity stored in memory; have non-zero size").
  - `!idr.erased`, `!idr.world`, `!idr.lin` and `!idr.token` do not, so
    MLIR's own memref verifier rejects an array of them.
  - `tensor` accepts any non-builtin element and leaves the check to the
    element's dialect (BuiltinTypes.cpp:433-439). So our verifier applies
    the same membership test to tensors: one rule, stated once.
  - Today `memref<?x!idr.str>` is "invalid memref element type", and a
    tensor of idr types asserts inside One-Shot instead of failing
    cleanly (E4, E8).
  - With the interface, an array of counted references bufferizes like any
    other (E8, shown with the upstream `!ptr.ptr`, which implements it).
- **Arrays are runtime types.** `isFieldType` (Dialect.cc:121-128) is the
  one definition of "a runtime value". It gains ranked tensors and memrefs of
  element types. Then arrays can be parameters, results, `!idr.lin`
  payloads, fields and captures (memrefs only; see the verifier rules).
- **Quantity 1 survives bufferization, in the type.**
  - `LinType::verify` rejects `!idr.lin<tensor<?xi64>>` today (E8).
  - It should accept it, and `!idr.lin` should implement `TensorLikeType`
    when it wraps a tensor and `BufferLikeType` when it wraps a memref
    (Bufferization/IR/BufferizationTypeInterfaces.td). That is the upstream
    hook for custom types in One-Shot. It turns `!idr.lin<tensor<?xi64>>`
    into `!idr.lin<memref<?xi64>>`, so AGENTS.md's rule holds through the
    pass that would otherwise drop the fact.
  - After bufferization the fact is still load-bearing. `LinearUses`
    verifies it, and counting reads it: a `!idr.lin<memref>` is owned and
    moved, never incremented, so its final release is a free with no test.
- **A closed length is a shape.**
  - `tensor<16xi64>` makes every `tensor.dim` a constant.
  - IntegerRangeAnalysis then folds both halves of every check in a loop over
    the array (E11, `@f`).
  - This is the payoff of the frontend keeping closed indices in instance
    keys (representation.md R6).
- **A symbolic length is the dimension itself.**
  - `tensor.dim`/`memref.dim` *is* the ghost `n` (R12).
  - `tensor.empty(%n)` states `dim == %n` through its ValueBounds model
    (Tensor/IR/ValueBoundsOpInterfaceImpl.cpp:70).
  - A `Fin n` index is R5's `idr.fin.enter %i, %n`, with the ValueBounds
    fact `j < n`. A check Idris proved is never emitted, and any check
    derived from it folds against the same `%n`.
- **Reference semantics at the source is a fact to keep once there are two
  kinds of tensor.**
  - Today every tensor comes from `LinArray`, whose Chez semantics are
    reference semantics (E2), so "a copy is a divergence" holds for every
    tensor.
  - When value-semantic tensors arrive (R12's `Vect`), the difference must
    live in the tensor type, as an encoding (`tensor<?xi64, #idr.ref>`).
    The in-place check reads it, and `use-encoding-for-memory-space`
    carries it into the buffer type if a later pass needs it (E3,
    `enc.mlir`).
  - Not before then: until two kinds exist, nothing would read it.

## 2. Ops: none of ours for the data, one later for thawing

**Every array operation is an upstream op.** The primitives get registry
meanings (decision-linear-libraries.md), and a meaning is a short sequence of
upstream ops:

| entry | category | meaning |
|---|---|---|
| `prim__newArray n x` (IOArray.Prims:11) | 1 | `memref.alloc(n)` + `linalg.fill ins(x)`; for a counted `x`, `idris_rt_inc_n(x, n)` |
| `prim__arrayGet a i` | 1 | check `0 ≤ i < memref.dim`, crash otherwise; then `memref.load` |
| `prim__arraySet a i x` | 1 | the same check, then `memref.store` (for a counted element, the old one is released, §4) |
| `Data.IOArray.max` | 2 | `memref.dim (content arr)`. `MkIOArray` is not exported, so `maxSize` is always the array's length: faster, never different |
| `prim__newBuffer n` | 1 | `memref.alloc(n) : memref<?xi8>` |
| `prim__bufferSize b` | 1 | `memref.dim` |
| `prim__getBits{8,16,32,64}`, `Int*`, `Double`, and their setters | 1 | check `0 ≤ off ∧ off + w ≤ size`; then `vector.load %b[%off] : vector<wxi8>`, `vector.bitcast`, `vector.extract`. After `-O3` this is one unaligned load (E6) |
| `prim__copyData src so n dst do` | 1 | check both ranges; then `llvm.intr.memmove` over the two subviews. It is **not** `memref.copy`, which lowers to `memcpy` and is undefined on overlap, while Chez's `bytevector-copy!` is defined on it (E15) |
| `prim__setString b off s` / `prim__getString b off n` | 1 | a copy from or to `idr.str.bytes s` (§8) / `idris_rt_str_from_utf8` of the subview |
| `stringByteLength s` | 1 | `memref.dim (idr.str.bytes s)` |
| `System.File.Buffer.prim__readBufferData` / `writeBufferData`, `stdin`/`stdout` | 1 | runtime reads and writes on the subview. This is how the benchmarks do their I/O (§10) |
| `LinArray` `newArray n k` | 2 | `tensor.empty(n)`, a fill with `Nothing`, `idr.lin.enter`, then `k` applied to it |
| `write a i x` | 2 | Idris's own range test, then `tensor.insert (Just x)`; the result is `Res ok a'` |
| `mread a i` / `read` | 2 | the range test, then `tensor.extract` |
| `msize` / `size` | 2 | `tensor.dim` |
| `toIArray a k` | 2 | `k a`: the same tensor, used any number of times from then on |

Notes on the table:
- **Every raw access has a check.** The library's comment says an
  out-of-range `prim__arrayGet` is "undefined" (Prims.idr:8-10), but user
  code can import `Data.IOArray.Prims` and call it, and Chez raises. So the
  meaning crashes, as `idr.str.index` already does (`Idr_MayCrash`). Every
  check that a proof covers is removed by §7; nothing is left undefined.
- **Element representation.** `LinArray` and `IOArray` store `Maybe elem`,
  so the element is `!idr.data<@Maybe[E]>`: an array of structs whose
  layout is the cell body's layout (Layout.cc). Splitting it into a bitmap
  and a payload array (structure of arrays) is an Emit decision for later,
  once it is measured.

**External models, not new ops**, so that One-Shot sees through our control
flow and our linearity:
- `BufferizableOpInterface` on `idr.match`/`idr.match_lit` and `idr.yield`,
  as upstream has it for `scf.index_switch`: results alias the yielded
  values.
- `BufferizableOpInterface` on `idr.lin.use`/`idr.lin.enter`: an equivalent
  alias, with no read and no write, as for `tensor.cast`.

**Crossing into a cell is explicit, and costs nothing when the array is
fresh.**
- A tensor never sits in a cell (verifier rule 2). A value array that must
  be stored is materialized into an object with
  `bufferization.materialize_in_destination %t in restrict writable %obj`,
  where `%obj = memref.alloc`, and the memref is the field.
- `eliminate-empty-tensors` makes a freshly built array be built *in*
  `%obj`, with no copy (E3, `seal.mlir`).
- Reading one back is `bufferization.to_tensor %m` without `restrict`.
  One-Shot treats it as not writable, so a write copies first: a static
  copy-on-write.

**One op of ours, needed only later: `idr.array.unshare`.**
- `%m2 = idr.array.unshare %m : memref<?xE> -> memref<?xE>` consumes an
  owned reference. It returns the same object when that object's count is 1,
  and otherwise a copy (with its counted elements incremented), releasing
  the original. It is Lean's `lean_ensure_exclusive_array`.
- Its result is exclusive by construction, which is what licenses
  `bufferization.to_tensor %m2 restrict writable`. So a value array taken out
  of an exclusive cell (moved out by `idr.take`) is then updated in place.
- It is load-bearing twice:
  - counting treats it as a consuming use, so a still-shared handle
    arrives with count ≥ 2 and gets copied, which is correct;
  - One-Shot reads `restrict writable`.
- It is needed only when value arrays live in data structures and are
  updated after being read back. No benchmark here does that. Until it
  exists, static copy-on-write is correct.

## 3. Verifier rules

Each rule states what it rules out and which pass relies on it.

1. **Element types.** An element of a tensor or memref implements
   `MemRefElementTypeInterface`.
   - MLIR checks this for memrefs; our module verifier checks it for
     tensors.
   - Layout (element stride, object slots per element), counting (release
     on overwrite) and the runtime's release walk rely on it.
2. **No tensor in a cell.**
   - `idr.con` fields, closure captures and `idr.data` field types may be
     memrefs, never tensors.
   - One-Shot's analysis is sound only over SSA uses. A tensor stored in
     heap data would escape it, and a later in-place write would change the
     stored value.
3. **Linear arrays are linear.** `!idr.lin<tensor>` and `!idr.lin<memref>`
   fall under `LinearUses` like every linear type. That single use-def chain
   is what One-Shot's in-place analysis consumes (Bufferization.md,
   "Destination-Passing Style").
4. **No tensor after `idr-bufferize`.** This is a `ConversionTarget`-style
   module invariant. Counting and lowering never see a value array.
5. **In the owned stage, a memref is a counted reference.** Every owned
   memref is consumed exactly once on every path: the existing owned-stage
   rule, with one more type. Its consumer is the lowering, which emits the
   runtime's inc and dec on the allocated pointer.
6. **Header limits are compile errors.**
   - An element type with more than 255 object slots, or a stride of more
     than 65535 bytes, is `unsupported (type)` in Layouts.
   - The array header packs both into the info word, which
     review-external.md found unchecked for cells. Same fix: never let it
     overflow.

The in-place requirement for `LinArray` is not a verifier rule. It is
`idr-bufferize`'s rejection (§5), because only One-Shot's analysis knows it.
The property `idr-expect arrays-in-place=@f` (linear-libs.md §5) states it
for tests.

## 4. The runtime object

One cell kind for every array, byte buffer and bufferized tensor:

```c
/* An array: the header (kind IDRIS_RT_KIND_ARRAY; tag = the element stride
 * in bytes; objs = the object slots at the start of each element), the
 * byte length, then the elements, 16-byte aligned. */
typedef struct idris_rt_array {
  idris_rt_header header;
  uint64_t bytes;
} idris_rt_array;
```

- **Allocation through MLIR's own hooks.**
  - `finalize-memref-to-llvm{use-generic-functions}` calls
    `_mlir_memref_to_llvm_alloc`/`_free` (FunctionCallUtils.cpp:42-45). The
    runtime defines them:
    - alloc builds an array object with count 1, `objs = 0`, and the byte
      length;
    - free is `idris_rt_dec`.
  - So every buffer MLIR allocates is a counted object, and none of those
    allocation sites need a pattern of ours: One-Shot's allocations, its
    copies, and `expand-realloc`'s. E9 runs this with a 40-line C runtime:
    fill+sum does one allocation and one free, and an array held by a
    "cell" survives the function's own release and dies with the cell.
  - One-Shot runs with `buffer-alignment=0`, and the runtime returns
    16-byte-aligned data. Then the allocated and aligned pointers are equal
    (asserted in E9), and **one object slot holds an array in a cell**. The
    descriptor is rebuilt from the pointer and the header's byte length.
- **Arrays with counted elements.**
  - One lowering pattern of ours applies to `memref.alloc` whose element
    type has object slots. It calls `idris_rt_array_new(n, stride, objs)`,
    which zeroes the memory.
  - NULL is a valid empty slot: every runtime entry point accepts NULL
    (idris_rt.h:136-139). So "overwrite releases the old element" never
    reads garbage, and an unwritten slot is not a state that needs a guard.
    This is the sentinel technique applied to a slot.
- **Release.** At count 0, when `objs > 0`, the runtime walks `bytes /
  stride` elements and decrements their first `objs` words. It uses the
  existing worklist, so the stack stays constant. Then it frees the object.
- **Overwrite of a counted slot.** This is a rule of counting, not an op:
  - before a `memref.store` into a memref of counted elements, counting
    inserts `idr.dec` of the old slot (a `memref.load`);
  - a `memref.load` of a counted element is borrowed from the array, and
    counting takes a reference when the value must outlive a store or the
    array;
  - a `memref.copy` of counted elements increments every element
    (`idris_rt_array_copy`: `memcpy` plus the walk).

  Lean's `lean_array_set` releases the old element the same way (E7).
- **Constants.**
  - A compile-time array (`dense<...>`, a `memref.global constant`) is a
    persistent object: its header sits in `.rodata` with count 0, as static
    cells have today. That takes one lowering pattern for `memref.global`,
    so that a header precedes the data.
  - A write to a constant is a `to_tensor` of a non-writable buffer, so
    One-Shot copies it first. The constant is never written.
- **Growth.**
  - Idris arrays never change length.
  - `resizeBuffer` is Idris code (a new buffer, then `copyData`).
  - The one growing byte sequence is a string built by appending (§8).
    `memref.realloc` exists, but the pinned tree lowers it only through
    `expand-realloc`: allocate, copy, free (E15). Amortized doubling makes
    that O(1) per byte, so in-place `realloc` is not worth a pattern.
- **`idris_rt_array_unshare(p)`**, for `idr.array.unshare`: count 1
  returns `p`; otherwise it copies (with the walk) and releases `p`.
- **Accounting.** Arrays are live cells, so the `IDRIS_RT_LIVE=1` leak test
  covers them. In compile-time evaluation they come from the arena and are
  persistent, as cells are.

## 5. Mutation

- **Unique: a plain store.**
  - Idris's linear threading gives one SSA def-use chain per array.
  - One-Shot decides every write on it in place (linear-libs e1/e3; E3).
  - After bufferization a write is a `memref.store`: no count test, no
    branch, no call.
  - The in-place decision is the proof. It is made once per program point,
    at compile time, where Lean tests exclusivity at every `Array.set!`
    (E7).
- **Shared, with value semantics: copied, statically.**
  - When an old value is read after a write (a read-after-write conflict),
    One-Shot allocates and copies at the write.
  - That is exactly Lean's copy-on-write, decided at compile time: the
    branch Lean tests at runtime is folded away because the answer is known
    (E9 `shared`: one copy).
- **Shared, with reference semantics at the source (`LinArray`): rejected.**
  - A copy would print `Just 10` where Chez prints `Just 20` (E2).
  - `idr-bufferize` inspects `OneShotAnalysisState::isInPlace` for every
    tensor operand after the analysis. An out-of-place one is
    `unsupported (uniqueness)`, named by the conflict triple One-Shot
    already computes: the definition, the conflicting write, and the later
    read (E3, `print-conflicts`).
  - The driver is upstream's own sequence with the check between two public
    calls: `analyzeModuleOp`, then the check, then `insertTensorCopies`,
    then `bufferizeModuleOp` (E15).
- **Unknown until runtime: tested once.** A value array read out of a cell
  is thawed by `idr.array.unshare`: one count test, then plain stores.
  Counting never tests inside the loop.
- **Shared and mutable (`IOArray`, `Buffer`): always a plain store.**
  Aliasing is the semantics, the world orders the IO, and uniqueness never
  comes into it.

## 6. Lifetimes: counting, not ownership-based deallocation

linear-libs.md and memory-theory.md proposed
`ownership-based-buffer-deallocation` (OBD) for arrays. The evidence says
it is the wrong owner for Idris arrays, and that the counting we already
have is the right one:

- **OBD's function ABI copies where Idris code returns its argument.**
  - "A function must not return a MemRef with the same allocated base
    buffer as one of its arguments" (OwnershipBasedBufferDeallocation.md,
    "Function boundary ABI"). So a recursive array function gets a
    `bufferization.clone` per return (E3, E10).
  - Or, with `private-function-dynamic-ownership`, a runtime alias check
    with five heap arrays at every call site (E3).
  - Counting returns the argument by moving the reference. It has no ABI
    rule to satisfy.
- **OBD cannot see objects in cells.**
  - `IOArray` is a record holding its `ArrayData`.
  - Closures capture arrays.
  - OBD tracks SSA-visible buffers only (memory-theory §6.10).
- **Counting already exists and is verified.** A memref is one more counted
  type (rule 5), and borrow inference makes read-only array parameters
  borrowed, with no increment.
- **The hooks make the two meet anyway** (E9). A buffer that One-Shot
  allocates is already a counted object, so storing it in a cell needs no
  conversion.

So: **MLIR decides where the bytes go; counting decides when the object
dies.** "When" is the residue that MLIR provably cannot cover once arrays
live in heap data. Bufferization runs before counting:

```
idr-simplify, idr-defunctionalize, canonicalize,
idr-bufferize                 One-Shot analysis with SCC summaries (§9 W1),
                              the in-place check (§5), copies, rewrite
idr-drop-equivalent-results   §9 W2
canonicalize,
idr-stack,                    its escape summaries also cover memref.alloc
idr-rc,                       memref is a counted type
idr-tail-loops,               plus upstream's while→for uplift patterns (§7)
canonicalize, int-range-optimizations, the ValueBounds compare fold (§7),
idr-lower                     + finalize-memref-to-llvm{use-generic-functions},
                              the counted-element alloc and memref.global
                              patterns, cf.assert → the runtime's crash
```

Two consequences:
- **Counting's rule for regions relaxes.** Counts.cc:67-71 accepts only
  matches. It must also accept a region that binds no counted value, such as
  a `linalg.fill` or `linalg.generic` body over scalars.
- **Bufferization sees recursion, not loops.** Loops are formed after
  counting (E16). This is why the recursion gap (§9) is on the main path.

## 7. Bounds checks

Where the checks come from:
- Idris code: `writeArray`'s `pos < 0 || pos >= max arr`, and `LinArray`'s
  write and read.
- The primitives' meanings (§2).

What removes them, cheapest first:

1. **A closed length.** IntegerRangeAnalysis folds both halves
   (`int-range-optimizations`, E11 `@f`).
2. **The sign test** folds by range for any loop index (E5).
3. **The relational test `i < dim`.**
   - ValueBounds proves it for a loop over `[0, dim)` (E12, `vb4.mlir`), but
     no upstream pass folds an `arith.cmpi` with it. The only consumers are
     affine and linalg utilities (E5, E12).
   - Our residue is one canonicalization pattern: decide an `index`
     comparison with `ValueBoundsConstraintSet::compare`, looking through
     `arith.index_cast`. On our one 64-bit triple, `index` ↔ `i64` preserves
     signed order.
   - It is needed because Idris compares `Int`, there is no `index_cast`
     ValueBounds model, and `cmpi` of two casts is not canonicalized
     (E12, `ic.mlir`).
   - It is about 40 lines. It belongs upstream, next to
     `int-range-optimizations`, and we should offer it.
4. **Loops must be `scf.for` for 3 to apply.**
   - ValueBounds has induction-variable bounds for `scf.for` only
     (SCF/IR/ValueBoundsOpInterfaceImpl.cpp:115-121). `idr-tail-loops` makes
     `scf.while`.
   - `populateUpliftWhileToForPatterns` (SCF/Transforms/Patterns.h:77-81) is
     upstream C++ API that no pass exposes, so idr-tail-loops calls it.
   - For the Idris `Int` counter to be an `index`, R5/R13's narrowing
     (representation.md) is the representation fix. The cast-aware fold in
     3 covers the time before it.
5. **The array is loop-invariant, not loop-carried.**
   - After §9's W2, a function that threads its array returns nothing, so
     the loop does not carry the memref (E3, `loop.mlir`), and `memref.dim`
     is a loop invariant.
   - Were tensors ever loop-carried (linalg raising on tensors), upstream's
     `DimOfIterArgFolder` would miss `tensor.insert`: `isShapePreserving`
     follows `tensor.insert_slice` only (LoopCanonicalization.cpp:38-60;
     E12 `vb5` versus `vb7`). That is an upstream bug. Our pipeline does
     not need a workaround, so it is recorded in mutable-buffers-upstream.md
     to file, not pinned.
6. **`Fin n`.** A check Idris proved is not emitted at all. R5's
   `idr.fin.enter` carries `j < n` for everything derived from it.
7. **LLVM is the backstop.** Constraint elimination and IndVars remove what
   MLIR leaves in simple loops (E5).
   - MLIR still has to remove the check first where it matters: a loop body
     with an `scf.if` around the access cannot become a `linalg.generic`,
     and MLIR's vectorizer does not see through it.

A `Buffer` access checks `off + w ≤ size` with a constant `w`, and folds the
same way when `off` is an induction variable times `w`.

## 8. Strings under the same discipline

**A string stays an immutable counted object, `!idr.str`.**
- Idris strings are values that programs share persistently: list elements,
  map keys, the same literal everywhere. That is the box discipline:
  counting, plus reuse when exclusive.
- The tensor discipline would be wrong for them:
  - One-Shot resolves every conflict with an eager whole-string copy;
  - a string in a cell would escape the analysis (rule 2);
  - `tensor.concat` always allocates (E3, `concat.mlir`), so a string built
    by appending would be O(n²).

**Byte access is a borrowed view.**
- `idr.str.bytes %s : !idr.str -> memref<?xi8>` is a descriptor whose
  allocated pointer is the string object and whose aligned pointer is its
  first byte.
- So the view *is* a reference to the string. Counting knows what it
  borrows, and the view dies before the string does.
- It is load-bearing:
  - byte loops over strings become memref loops that linalg and LLVM
    vectorize (reverse-complement and k-nucleotide read their input this
    way);
  - `str.index` on a string whose ASCII bit is set (idris_rt.h:42) becomes
    one byte load.
- The view is read-only by construction: the Idris side's meanings are its
  only users, and the verifier rejects a `memref.store` whose target derives
  from `idr.str.bytes`.

**Mutation: an append that consumes its left side extends it in place.**
- `acc ++ line`, where `acc` dies at the append, becomes
  `idris_rt_str_append_owned(acc, line)`:
  - if `acc` is exclusive (count 1, not static) and its block has room, the
    bytes are copied into the slack and the lengths updated;
  - otherwise a new string with doubled capacity is made.
- Capacity is the allocator's usable size of the block (snmalloc knows it),
  so the header gains no word.
- The owned stage (idr-rc) decides "consumes", as it decides reuse.
  memory-theory.md §6.3's `idr.exclusive` indicator folds the count test
  where exclusivity is static, and it stays a runtime test otherwise.
- This is Lean's `lean_string_append`. It turns a loop of appends from
  O(n²) into amortized O(n).
- `fastConcat` and `fastPack` (Prelude/Types.idr:723-726, 855-858) get
  registry meanings: one allocation of the total length.

**Converting between byte buffers and strings copies.**
- `getString` and `str.from_utf8` validate and count UTF-8, which is O(n)
  anyway, so the copy costs nothing asymptotically.
- Sharing one object between a mutable `Buffer` and an immutable string
  would need a freeze protocol. No benchmark needs one.

## 9. The upstream recursion gap, and what we do until it is fixed

**The gap has two halves (E10).** Both come from
OneShotModuleBufferize.cpp:510-523: "We currently skip all function
argument analyses for functions that call each other circularly".

1. **Summaries.** A call to a function in a call cycle is assumed to read
   and write every tensor operand, and its results alias nothing known
   (FuncBufferizableOpInterfaceImpl.cpp:171-200). So a caller copies the
   array before *every* call of a read-only recursive function whose array
   it uses again. `readrec.mlir` shows two whole-array copies. A recursive
   binary search called n times is O(n²), silently.
2. **Result equivalence.** At buffer level, `drop-equivalent-buffer-results`
   compares return operands with block arguments syntactically, modulo
   casts (DropEquivalentBufferResults.cpp:65-75). It sees neither through
   `scf.if`/`idr.match` yields nor through a recursive call's result.
   - Under OBD this becomes a clone per return (`e5-rec.mlir`).
   - Under our counting it costs nothing in memory, but the memref stays
     loop-carried after idr-tail-loops. That keeps §7's step 5 from working,
     and it holds a register.

**Why it is central here.** Bufferization runs before loops exist (§6). So
every recursive array function meets it, tail-recursive ones included.

**The workaround: two small pieces that are the upstream patch, carried
locally.**

- **W1, in `idr-bufferize`: seed the SCC summaries, verify them, iterate.**
  - `FuncAnalysisState` is a public extension with public maps, and
    `analyzeModuleOp` never writes the `analyzedFuncOps` entry of a function
    in a cycle (E15). So, before calling it, the driver seeds each such
    function optimistically:
    - no tensor argument read or written;
    - each tensor result equivalent to the argument that its first returning
      path returns;
    - marked `Analyzed`.
  - After the analysis, it recomputes each function's real summary with
    upstream's own queries: `isValueRead` and `isValueWritten` on the block
    argument, and equivalence of the return operands.
  - If a function reads or writes more than was assumed, or has fewer
    equivalences, the driver weakens the seed and reruns from a fresh state.
  - Each round only adds reads and writes, or only removes equivalences, so
    this terminates.
  - At the fixpoint the assumption is the analysis's own conclusion. That
    is sound by induction on call depth: a call that returns has returned
    through a base case.
  - Public API only; no fork of upstream code.
- **W2, `idr-drop-equivalent-results`: the greatest fixpoint of
  upstream's pass.**
  - Result `i` of `f` is dropped when every return operand is either block
    argument `j`, or a value that reaches the return through region-branch
    yields and SCC calls whose operand `j` is such a value.
  - It starts from "all candidates" and removes the unsupported ones. The
    call-site rewrite is upstream's (DropEquivalentBufferResults.cpp:
    139-163).
  - `e5-fixed.mlir` is what it produces on `e5-rec.mlir`: `@rec :
    (index, index, memref) -> ()`, one allocation, no clone, no helper.
  - It is roughly 100 lines, a generalization of a 190-line upstream pass.

**By AGENTS.md, in the same change as W1 and W2:**
- `upstream/one-shot-recursive-boundaries/`, with `readrec.mlir` and
  `e5-rec.mlir` as reproducers and the report drafted in
  mutable-buffers-upstream.md;
- `tests/upstream/one-shot-recursive-boundaries/run`, which checks with the
  pinned `mlir-opt` that `readrec.mlir` still gets its two `memref.copy`s
  and `e5-rec.mlir` still keeps its result;
- a `PINS.md` entry `one-shot-recursive-boundaries` whose retire condition
  is exactly that test failing.

**The alternatives, and why not.**
- *Reject array recursion.* This is legal under AGENTS.md, but at
  bufferization time every array loop is still a recursion, so it would
  reject nearly all array code.
- *Form loops before bufferization.* Counting refuses loops (Counts.cc:67-71),
  and this still leaves non-tail recursion such as quicksort.
- *Copy silently.* Never: for `LinArray` a copy is a divergence (§5), and
  for everything else it is an unannounced change of complexity class.

## 10. What the benchmarks need, mapped onto linalg and vector

The wave-1 Idris ports (`scratchpad/research/benchmarks/k/`) use lists
because no array compiles today (E1). Each program below is what an
idiomatic array version needs.

| program | data | Idris API | MLIR form | vector |
|---|---|---|---|---|
| fannkuch-redux | three `Int` arrays of length n ≤ 12 (perm, perm1, count) | `IOArray Int`, or `LinArray Int` threaded | `memref.copy` of a subview for perm → perm1 (a `memcpy`); flips and rotations as `scf.while` swap and shift loops, in place | none from MLIR: the flip length is data-dependent. The C code's `pshufb` over a 16-byte permutation would need `n ≤ 16`, which no Idris fact states. Target: C's scalar loop in L1 |
| spectral-norm | u, v, t: `Double` arrays of n = 5500 | `LinArray Double` or `IOArray Double` | A·v and Aᵀ·v as `linalg.generic` `[parallel, reduction]`, with `A(i,j)` computed from `linalg.index`, never stored; the dots as `linalg.reduce` | vectorize over **rows**: tile `[4,1]` or `[8,1]`, `vector<4xf64>` accumulators, `j` sequential. IEEE order is kept, so the output is bit-identical (E13). Vectorizing `j` would reassociate, which Idris `Double` does not allow. Needs raising the loop nest to `linalg.generic` (no upstream pass exists: `affine-raise-from-memref` needs `affine.for`) |
| k-nucleotide | the input's third sequence as bytes; 2-bit codes; counts | `Buffer` (or `getLine` strings through `idr.str.bytes`); `IOArray Int` for tables | encoding as `linalg.map` over `memref<?xi8>` with a 256-byte table; the rolling code as an `scf.for` (a scan, which linalg cannot express); counting as load, add, store into `memref<4^k x i32>` for k ≤ 12, and an open-addressing table in two `IOArray`s (structure of arrays: keys, counts) for k = 18 | the encoding vectorizes (gathers, or LLVM's loop vectorizer); the histogram does not |
| reverse-complement | all of stdin as bytes | `Buffer` + `readBufferData`, grown by doubling (`resizeBuffer`), + `writeBufferData` | per record: remove the newlines (a compaction, `scf`); `out[i] = comp[in[n-1-i]]` as a `linalg.generic` whose input index is `n-1-i`; rewrapping at 60 as the index map `o - o floordiv 61` with a newline at `o mod 61 = 60` (affine) | MLIR emits `vector.gather` for both the reversed read and the lookup (E14), and x86 has no byte gather. LLVM's loop vectorizer, which knows reverse consecutive access, is the better backend here; linalg's value is fusing the rewrap |
| fasta | the ALU string, two cumulative-probability tables, a 61-byte line | `memref.global constant` tables; a `Buffer` of 61 bytes; `writeBufferData` | the LCG as a sequential `scf.for` (the output must be the same sequence); the lookup as `count(cum < r)`; the repeat part as `memref.copy` of ALU subviews (a `memcpy`) | the lookup is `vector<16xf64>` compare, `extui`, `vector.reduction <add>`: branch-free. The line buffer has a static shape, so it goes on the stack (`promote-buffers-to-stack`, or idr-stack) |

**What unlocks all five, in order:**
1. `Buffer` and `IOArray` primitives with registry meanings.
2. `System.File` stdin/stdout and `readBufferData`/`writeBufferData`.
3. The element interface on idr types.
4. The runtime array object and the allocation hooks.
5. Counting over memrefs.
6. The compare fold and the while→for uplift.

`LinArray` recognition, W1 and W2 come next. Raising to `linalg` comes last:
only spectral-norm's SIMD needs it, and it is our residue (no upstream
raising from `scf`).

## What this means for idris-mlir: the path

Each step is verified, and adopts the most upstream machinery available
at that point, before the next one starts.

1. **Types and the element rule.**
   - `MemRefElementTypeInterface` on data, box, fn, str and big.
   - `isFieldType` gains ranked tensors and memrefs.
   - `!idr.lin` gains `TensorLikeType`/`BufferLikeType`.
   - Verifier rules 1, 2, 3 and 6.
   - Tests: lit negatives for an erased element, a tensor field, and a
     `!idr.lin<tensor>` used twice.
2. **Runtime.**
   - `IDRIS_RT_KIND_ARRAY`, `_mlir_memref_to_llvm_alloc`/`_free`,
     `idris_rt_array_new`/`_copy`, and the release walk.
   - The `finalize-memref-to-llvm{use-generic-functions}` step in
     idr-lower.
   - Tests: E9's allocation and free counts, as an e2e test with
     `IDRIS_RT_LIVE=1`.
3. **Shared-mutable arrays: `IOArray` and `Buffer`, plus file I/O.**
   - Registry entries of category 1, and of category 2 for
     `Data.IOArray.max`.
   - Counting over memrefs (rule 5), with memref ops as borrows and memref
     fields as object slots.
   - The crash checks.
   - This compiles linear-libs benchmarks 10 and 11 and the five programs'
     array versions (except `LinArray`), matching Chez.
4. **Bounds checks.**
   - The ValueBounds compare fold (`index_cast`-aware).
   - `populateUpliftWhileToForPatterns` in idr-tail-loops.
   - Tests: `idr-expect` properties such as "no check left in `@f`", never
     op sequences.
5. **`LinArray` on the tensor path.**
   - `idr-bufferize`: analysis, the in-place check with the conflict
     triple, copy insertion, rewrite.
   - W1 and W2, with their upstream directory, test and PIN.
   - External models for `idr.match` and `lin.use`/`lin.enter`.
   - Tests: fill+sum and bubble in place; the E2 escape rejected with its
     triple; quicksort with no copy and no clone.
6. **Strings.**
   - `idr.str.bytes`.
   - The consuming append, and the ASCII byte-index fast path.
   - `fastConcat` and `fastPack` entries.
7. **`idr.array.unshare`,** when value arrays in data structures appear.
8. **Raising to linalg** for spectral-norm, once measured.

## Landed 2026-10-01: shared-mutable arrays (step 3 of the path, in part)

- **Types.** `!idr.data`, `!idr.box`, `!idr.fn`, `!idr.str`, `!idr.big` and
  `!idr.nat` implement `MemRefElementTypeInterface`; `isArray` is
  `memref<?xE>` (one dynamic dimension, identity layout) of a field type E
  at no grade, and `isFieldType` admits it, so an array is a parameter, a
  result, a field, a capture, and a `!idr.q` payload (`!idr.own<memref>`
  after idr-rc). Tensors are not field types yet (step 5).
- **Ops.** Three of ours, `idr.array.new %n, %x, %w`, `idr.array.get %a[%i],
  %w` and `idr.array.set %a[%i], %x, %w`, not `memref.load`/`store`: an
  element of a counted type moves in with its reference and comes out with
  one of its own, and the ops thread the world, which `memref` ops cannot
  carry. Their effects are their own (IO resource read and write, a crash
  where the index may be out of bounds, an allocation for `new`), and
  `getCrashCause` reports "array index out of bounds". `useOf` consumes
  the fill and the value set, and borrows the array.
- **Runtime.** `IDRIS_RT_KIND_ARRAY`: header (tag = element stride in bytes,
  objs = counted words per element), `uint64 length`, then the elements,
  each laid out as a cell's fields are (`Layouts::element`, with
  `CellInfo::array` checking the header's limits); `idris_rt_array_new`
  allocates through `rt::newCell` (arena-aware), and the release walk in
  rc.cc frees every element's object slots. Not yet: the
  `_mlir_memref_to_llvm_alloc` hooks and `finalize-memref-to-llvm`, which
  only upstream memref ops would need.
- **Lowering (Lower/Arrays.cc).** `new` is the runtime call, a
  `scf.for` storing the fill's components into each element with one inc
  per element, and one dec of the fill; `get` checks `index <u length`
  (crashIf), loads the components and increments the counted ones; `set`
  checks, decrements the old element's components and stores the new one.
- **Frontend.** `Ty` gains `ArrayT`, `IOOp` gains `Array ArrayOp Ty`
  (the element type fixed at the call from its one type argument), the
  registry (`Primitives.idr`) names `Data.IOArray.Prims.ArrayData`
  (`ArrayType`) and `prim__newArray`/`arrayGet`/`arraySet` (`ArrayCall`)
  as `%extern` definitions of the backend contract, and the emitter writes
  `memref<?xE>`.
- **Measured.** A sieve on `IOArray Bool` to 10^7: 0.219 s against Chez's
  7.76 s, live cells 0. fannkuch-redux on `IOArray Int`: 0.563 s against
  1.650 s on lists, 10.894 s for Chez's array version and 0.492 s for C.
  The element is `Maybe Int` (16 bytes, a tag per element), and every
  access carries Idris's own range test and ours: the structure-of-arrays
  split and the ValueBounds fold (§7) are what stand between this and C.
- **idr-expect** names a function by its Idris name: `@f` is `@f` and
  every clone of it, found through the `NameLoc` every emitted function
  carries and every clone keeps, where the clone-key attribute is stripped
  by idr-rc. So a fixture states `counts-nothing=@Main.mark` of the
  function the programmer wrote, however the passes rename it.
- **Deliberately not this slice.** `IOArray` is the escape hatch: it proves
  the cell, the counting and the lowering, and compiles imperative code to
  imperative code. The demo is `LinArray` (step 5): pure, linear, with the
  in-place decision One-Shot's, which is the next slice.

## Open questions

- **Structure of arrays for `Maybe` elements.**
  - `IOArray`'s `Maybe elem` slots cost a tag word per element (16 bytes for
    an `Int`).
  - Should Emit split them into a tag bitmap and a payload array? For
    `LinArray` over a fill loop that writes every slot, could the bitmap be
    proved all-`Just` and dropped? Only for loops over `[0, dim)`, I
    conjecture (linear-libs.md asked the same).
- **Read-only views as a type.** `idr.str.bytes` is read-only by a def-use
  rule. Would a memory space (`#idr.readonly`) be better, so that
  `memref.store` into a view fails MLIR's own type check? It is not clear
  that anything but the verifier would read it.
- **An ASCII refinement for strings.** The ASCII bit is a runtime fact
  (idris_rt.h:42). Literals and appends of ASCII are ASCII, so a static
  `!idr.str<ascii>` would let `str.index` be a load with no test. It needs a
  dataflow, and a measurement first.
- **Stack arrays.** Should idr-stack's escape summaries or upstream
  `promote-buffers-to-stack` place non-escaping arrays of static size on
  the stack? Upstream's pass uses `BufferViewFlowAnalysis`, which does not
  know that `idr.con` captures, so ours is the safe one.
- **Borrowed loads of counted elements.** A `memref.load` could stay
  borrowed until the next store to the same array. That is Perceus's rule
  for fields, extended to slots. It is a measurement question, not a
  soundness one.
- **Recursion as data.** Defunctionalizing the continuation of a non-tail
  recursion (quicksort's) into an explicit stack of frames would make every
  array recursion a loop before bufferization. That would remove W1 and
  W2's reason to exist, and linear-libs q5's stack overflow with them. It
  is the representation-first answer, and it is a large transformation.
  Conjecture.
- **Raising to linalg.** No upstream pass raises `scf` loops to
  `linalg.generic`. Is the residue a pattern over `scf.for` nests with
  affine loads and stores, or should registry-recognized whole-array
  functions be emitted as linalg directly?
- **Compile-time evaluation of array code.** idr-eval JITs lowered code
  from inside `idr-simplify`, before `idr-bufferize` runs. Code that
  touches arrays must be bufferized on that path too. A closed array result
  would come back as a `memref.global constant`: persistent, count 0, and
  copied before any write (§4). Unverified: whether Reify can build one.
