# Contracts: the representation cutover

Every declaration a lane consumes is fixed here by name and shape. Lanes
write against this text from the first minute; the owner named in
`ownership.json` writes the file. A conflict between this file and the
live tree goes to the coordinator, who edits this file and re-dispatches
the lane. No lane resolves it.

Path roots, as `ownership.json` spells them:

- `IDR` is `foreign/idr/lib`;
- `INC` is `foreign/idr/include/idr`;
- `RT` is `runtime`;
- `CS` is `compiler/src/IdrisMLIR`;
- `T` is `tests`.

The evidence is `findings/substrate.md` (S1 to S6, §3) and
`findings/concurrency.md` §2, read at ee4ce8e. Where this file disagrees
with them, this file is the newer decision, and README "Rulings" says why.

## C0. What does not change

- **The semantics.** Every program prints, exits and crashes exactly as
  before: the same bytes, the same status, the same crash message at the
  same location. Chez stays the oracle, and `tests/lib/chez-divergences`
  gains no class except `gc-clock` (C9.6).
- **Quantities and erasure.** Every quantity and erasure stays in the
  types (`!idr.erased`, `!idr.lin<T>`, `!idr.q`), and the verifier keeps
  checking it after every pass.
- **The targets.** Nothing assumes x86, Linux, ELF or musl outside the
  target entry. The runtime's OS calls go through `RT/Platform/Posix`,
  which serves both x86_64 Linux and arm64 macOS.
- **The closure symbol form inside the simplify loop.** `idr.closure`,
  `idr.suspend`, `#idr.closure`, `idr.apply` and `idr.force`, and the
  four `ForceOf*` patterns in `IDR/Dialect/Ops/Lazy.cc`, stay as they are
  (C4.4).
- **The unit size.** Every `.cc` or `.cppm` under `foreign/idr` or
  `runtime` stays at 400 lines or fewer, unless it is already listed in
  `T/spec/file-size/allowed`. A unit that grows past 400 is split in the
  same lane.

## C1. The hubs the coordinator writes

The coordinator applies C1 to the hub files at dispatch, from this text.
Lanes import the names below as if the hubs had already landed.

### C1.1 `INC/IdrOps.td`

1. **The reference resource and the consumption trait** (C2.1):

   ```tablegen
   def Idr_ReferenceResource : Resource<"::idr::ReferenceResource">;

   def Idr_ConsumingOpInterface : OpInterface<"ConsumingOpInterface"> {
     let cppNamespace = "::idr";
     let description = "An op that takes over the reference an operand holds.";
     let methods = [
       InterfaceMethod<"Whether the operand at `number` is taken over.",
                       "bool", "consumesOperand", (ins "unsigned":$number), "",
                       [{ return $_op.consumedByTrait(number); }]>,
     ];
   }

   // `groups`: the ODS operand groups the op takes over, as "0" or "0, 2".
   class Idr_Consumes<string groups>
       : TraitList<[ParamNativeOpTrait<"ConsumesOperands", groups>,
                    Idr_ConsumingOpInterface]>;

   // An op whose only effect is what it takes over, reported by the trait.
   class Idr_ConsumesOnly<string groups>
       : TraitList<[Idr_Consumes<groups>, MemoryEffectsOpInterface, AlwaysSpeculatable]>;
   ```

   The ops get them as the C2.1 table says. `Pure` is removed from each
   op that gets `Idr_ConsumesOnly`.

2. **The guards** (C3). There are six ops in a new section,
   "Guards". Each has `Idr_MayCrash<>` and one `StrAttr:$cause`, and
   the six share one interface method of `Idr_MayCrashOpInterface`:
   `getCrashCause` returns the cause. The `nonzero` guard is shown in
   full:

   ```tablegen
   class Idr_CheckOp<string mnemonic, list<Trait> traits = []>
       : Idr_Op<"check." # mnemonic, !listconcat(traits, [Idr_MayCrash<>])> {
     let extraClassDefinition = [{
       std::optional<::llvm::StringRef> $cppClass::getCrashCause() { return getCause(); }
     }];
     let hasFolder = 1;
   }

   def Idr_CheckNonzeroOp : Idr_CheckOp<"nonzero", [SameOperandsAndResultType]> {
     let summary = "the value, which must not be zero, else the program crashes";
     let arguments = (ins AnyTypeOf<[Idr_Int, Idr_BigValue]>:$value, StrAttr:$cause);
     let results = (outs AnyTypeOf<[Idr_Int, Idr_BigValue]>:$checked);
     let assemblyFormat = "$value `,` $cause attr-dict `:` type($value)";
   }
   ```

   The other five follow the same pattern:

   | Op | Operands | Result | Holds when |
   |---|---|---|---|
   | `idr.check.in_bounds` | `I64:$index, I64:$length` | `I64:$checked` (the index) | `0 <= index < length` |
   | `idr.check.nonempty` | `Idr_StrValue:$str` | the string | the string has at least one byte |
   | `idr.check.byte` | `I64:$value` | `I64:$checked` | `0 <= value <= 255` |
   | `idr.check.finite` | `F64:$value` | `F64:$checked` | the value is neither NaN nor infinite |
   | `idr.check.range` | `I64:$offset, I64:$count, I64:$size` | `I64:$checked` (the offset) | `0 <= offset`, `0 <= count`, `offset + count <= size`, without overflow |

   Every guard also has `DeclareOpInterfaceMethods<InferIntRangeInterface>`
   except `finite` and `nonempty`. Its result's range is the operand's
   range clamped by the condition.

3. **The total ops.** `Idr_MayCrash` is removed from these ops:

   - `Idr_DivisionOp` (`idr.div`, `idr.mod`);
   - `Idr_ToByteOp`, `Idr_ToIntOp`;
   - `Idr_StrTailOp`, `Idr_StrIndexOp`, `Idr_StrHeadOp`;
   - `Idr_BigDivisionOp` (`idr.big.div`, `idr.big.mod`);
   - `Idr_BigFromDoubleOp`;
   - `Idr_IOTransferOp` (`idr.io.write_bytes`, `idr.io.read_bytes`);
   - `Idr_BufferAccessOp` (`buffer_load`, `buffer_store`,
     `buffer_copy`, `buffer_set_string`, `buffer_get_string`);
   - `Idr_ArrayGetOp`, `Idr_ArraySetOp`.

   Each one's other effects stay as they are:

   - an allocating total op keeps `MemAlloc` on its result, as
     `Idr_MayCrash<1>` gave it;
   - a pure one becomes `NoMemoryEffect` with
     `DeclareOpInterfaceMethods<ConditionallySpeculatable>`; its
     speculatability is C3.3's rule;
   - an IO, array or buffer op keeps its IO and array effects.

   `UnitProp:$in_bounds` goes from `idr.array.get` and `idr.array.set`,
   with its `in_bounds` assembly keyword. `Idr_CrashOp` and
   `Idr_CrashStrOp` keep `Idr_MayCrash`.

4. **Regions** (C4). These ops are added under "Closures":

   ```tablegen
   def Idr_LambdaOp : Idr_Op<"lambda", [SingleBlock, RecursiveMemoryEffects,
       AutomaticAllocationScope]> {
     let summary = "a closure whose body is its region; its captures are the values it uses from above";
     let results = (outs Idr_FnType:$result);
     let regions = (region SizedRegion<1>:$body);
     let assemblyFormat = "attr-dict `:` qualified(type($result)) $body";
     let hasVerifier = 1;
   }

   def Idr_DelayOp : Idr_Op<"delay", [SingleBlock, RecursiveMemoryEffects]> {
     let summary = "a suspension whose body is its region; its captures are the values it uses from above";
     let results = (outs Idr_LazyValue:$result);
     let regions = (region SizedRegion<1>:$body);
     let assemblyFormat = "attr-dict `:` type($result) $body";
     let hasVerifier = 1;
   }
   ```

   The lambda's block takes the parameters of its `!idr.fn` type. The
   delay's block takes none. Each region ends in `idr.yield` of the
   result. `Idr_YieldOp`'s `ParentOneOf` gains `"LambdaOp"` and
   `"DelayOp"`.

5. **Memo sums** (C5):

   - `Idr_DataOp` gains `UnitAttr:$memo`, printed `memo` after
     `closures`.
   - `Idr_CtorOp` gains `UnitAttr:$by_name`.
   - `Idr_ForceOp`'s operand becomes
     `AnyTypeOf<[Idr_LazyValue, Idr_BoxValue]>:$suspension`. It gets
     `Idr_Consumes<"0">`, and keeps its own `getEffects`.

6. **Flat constants** (C7). `Idr_ConAttr` gets custom storage; its
   parameters are:

   ```
   (ins "::mlir::SymbolRefAttr":$ctor, "::mlir::ArrayAttr":$stored,
        "::mlir::Attribute":$tail, "unsigned":$spine)
   ```

   It also gets `hasCustomAssemblyFormat = 1`, `genVerifyDecl = 1`, and
   the builders and accessors of C7.2. ODS does not generate
   `getFields()`; C7.2 declares it. The existing builder,
   `get(ctor, fields)`, keeps its signature.

7. **Primitives** (C8). A marker trait is added:

   ```tablegen
   // An op Idris names as a primitive: idris-mlir-tblgen generates its
   // constructor of `IdrPrim` (or `IdrRegionPrim`) for the Idris side.
   def Idr_Primitive : NativeOpTrait<"Primitive"> { let cppNamespace = "::idr"; }
   ```

   It goes on exactly the ops C8.1 lists.

8. **Base's surface** (C9). A new file, `INC/IdrPlatformOps.td`, holds
   the ops of C9.2 and C9.3, and `IdrOps.td` includes it at the end. Each
   IO op there is an `Idr_IOOp` with `Idr_Primitive`, and lowers by
   `Idr_CallsRuntime` to `idris_rt_io_<suffix>`, where the suffix is its
   mnemonic after `io.`. Each `idr.handle.*` op is an `Idr_Op` with
   `Idr_CallsRuntime`, `Idr_Primitive` and the effects C9.3 gives it.

### C1.2 `INC/Passes.td`

- `IdrLower` loses its `jit` option.
- `IdrDeadValues` is removed (C11.2).
- New passes:

  | Pass | Def | Anchor | Options | Summary |
  |---|---|---|---|---|
  | `idr-isolate` | `IdrIsolate` | `ModuleOp` | none | "Make every idr.lambda and idr.delay an idr.closure or idr.suspend of an outlined function" |
  | `idr-entry` | `IdrEntry` | `ModuleOp` | none | "Make the lowered root the program's entry: @__idr_main and @main" |
  | `idr-meter` | `IdrMeter` | `ModuleOp` | none | "Count a tick of the evaluator's meter at every function entry and every loop that may not end" |
  | `idr-demand` | `IdrDemand` | `ModuleOp` | `ListOption<std::string> promises` ("in-place") | "Reject a program that breaks a promise it was asked to keep" |

- `IdrInBounds`'s summary becomes "Remove every guard whose condition
  holds where it runs".

### C1.3 The pipeline, `IDR/Dialect/Registration/PipelineSteps.cc`

The program's steps, in order:

1. `idr-isolate`
2. `idr-contify`
3. `idr-simplify`
4. `idr-defunctionalize`
5. `canonicalize`
6. `idr-stack`
7. `idr-accumulate`
8. `idr-rc`
9. `idr-demand`
10. `idr-trmc`
11. `idr-tail-loops`
12. `idr-narrow`
13. `idr-in-bounds`
14. `idr-lower`
15. `idr-entry`
16. then today's steps from `idr-vectorize` on, unchanged.

Each step keeps its existing comment. The comment on `idr-in-bounds`
becomes: "On the loops and words idr-narrow leaves, where its index
systems see the most."

The evaluation pipeline lives in `IDR/Eval/Round.cppm` and belongs to
U14:

- `idr-defunctionalize`
- `idr-lower`
- `idr-meter`
- then today's steps from `convert-linalg-to-loops` on, unchanged.

The driver runs `idr-demand` as written (no promises) unless it was given
`--demand in-place`. Then it runs it as `idr-demand{promises=in-place}`
(C10.2, U20).

### C1.4 `INC/Idr.h`

These declarations are added. The definitions belong to the owners
named.

```cpp
// The resource a consumed reference is freed from (C2.1).
struct ReferenceResource : mlir::SideEffects::Resource::Base<ReferenceResource> {
  llvm::StringRef getName() const final { return "idr.reference"; }
};

// The trait behind Idr_Consumes: the ODS operand groups an op takes over.
template <unsigned... Groups>
struct ConsumesOperands {
  template <typename ConcreteType>
  class Impl : public mlir::OpTrait::TraitBase<ConcreteType, Impl> {
  public:
    bool consumedByTrait(unsigned number) {
      auto *op = static_cast<ConcreteType *>(this);
      return ((number >= op->getODSOperandIndexAndLength(Groups).first &&
               number < op->getODSOperandIndexAndLength(Groups).first +
                            op->getODSOperandIndexAndLength(Groups).second) || ...);
    }
    // Used by ops whose only effect is what they take over (Idr_ConsumesOnly).
    void getEffects(llvm::SmallVectorImpl<
        mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>> &effects) {
      consumedEffects(this->getOperation(), effects);
    }
  };
};

// Whether `operand`'s position takes over the reference its value holds:
// an idr op says so by ConsumingOpInterface; a return, a yield of scf, a
// condition's carried values and a while's inits do; a call does unless
// the callee borrows the parameter. U03, IDR/Dialect/Effects/Consumed.cc.
bool consumes(mlir::OpOperand &operand);

// A Free of ReferenceResource on each operand of `op` that `consumes`
// names and whose grade is own or excl; nothing before idr-rc. U03,
// same file.
void consumedEffects(mlir::Operation *op,
    llvm::SmallVectorImpl<mlir::SideEffects::EffectInstance<mlir::MemoryEffects::Effect>> &effects);

// Whether a value of `type` holds a reference a count accounts for. An
// unboxed sum answers through its declaration, found from `scope`. U03,
// IDR/Dialect/Types/Counted.cc.
bool holdsReferences(mlir::Type type, mlir::SymbolTableCollection &symbols,
                     mlir::Operation *scope);

// Whether `data` is a memo sum (C5.1). U09, IDR/Dialect/Ops/Data.cc.
bool isMemo(DataOp data);
```

`ConsumesOperands` names `consumedEffects` before its declaration. The
coordinator orders the declarations so that it compiles.

### C1.5 `RT/idris_rt.h`

- `#define IDRIS_RT_KIND_CLOSURE 1u` becomes `#define IDRIS_RT_KIND_THUNK 1u`.

  A thunk cell is laid out as a box: tag, objs and object slots first.
  The tag says which state it is in (C5.3). Freeing reads it as it reads
  a box. Only the kind tells a memo cell, which may be written, from a
  box, which may not.

- The comment on the header's count 0 becomes:

  > 0: persistent. Static data, the results of compile-time evaluation
  > and the cells of its arena are never counted and never freed.
  > Everything a persistent object points to is persistent, except a
  > static memo cell (kind IDRIS_RT_KIND_THUNK), which its first force
  > writes once and whose forced value is counted and released by
  > idris_rt_caf_release.

- `idris_rt_lazy_kept` and its comment are removed. This is added:

  ```c
  /* Releases what a persistent memo cell holds (its object slots), once,
   * when the program ends: @__idr_release_cafs calls it on each of the
   * module's static thunks. A cell that was never forced holds only
   * persistent captures, and then nothing is released. */
  void idris_rt_caf_release(void *cell);
  ```

- `idris_rt_start` becomes:

  ```c
  int idris_rt_start(int64_t (*body)(void), uint64_t cpu_features, int argc, char **argv);
  ```

  The runtime keeps `argc` and `argv` for `idr.io.arg_count` and
  `idr.io.arg`.

- `idris_rt_crash` now ends an evaluation child the way
  `idris_rt_eval_crash` does, with the same report on the report
  descriptor and the same status, when it is called inside
  `idris_rt_eval_begin`'s child. The comment says so.
  `idris_rt_eval_crash` stays for the evaluator's own runtime code;
  lowered code never calls it.

- The `idris_rt_eval_tick` comment says that `idr-meter` inserts its
  calls.

- There is one declaration per op of C9.2 and C9.3. The name is
  `idris_rt_<mnemonic with dots as underscores>`, and the parameters and
  result are the op's operands and results without the world.
  `!idr.str` is `idris_rt_str *` and `i64` is `int64_t`.

### C1.6 `CS/Rule.idr`

Four rules are added to `Rule`, `Show Rule` and `allRules`:

| Constructor | Phrase | Doc comment |
|---|---|---|
| `Cycle` | `cycle` | A mutable cell whose type can reach itself: counting would leak the knot (`decision-acyclic-heap.md`). |
| `Uniqueness` | `uniqueness` | A value passed shared where a promise asked for it exclusive (`--demand in-place`). |
| `Signal` | `signal` | A signal handler, which runs an effect at a time the world does not name. |
| `Process` | `process` | Process creation (`system`, `popen`), outside the language until the owner decides (O4). |

### C1.7 The build lists

- `foreign/idr/CMakeLists.txt`:
  - the areas `Isolate` and `Demand` join the `foreach(area ...)` list,
    in alphabetical order;
  - `idr_isolate` and `idr_demand` join `idr_dialect`'s link list.
- `IDR/Dialect/CMakeLists.txt` gains:
  - `Ops/Check.cc` (U04);
  - `Ops/Regions.cc` (U08);
  - `Effects/Consumed.cc` (U03);
  - `Types/Counted.cc` (U03).
- `IDR/Dialect/Dialect.cppm` re-exports every new op, attribute,
  interface, trait, resource and pass constructor of C1.1 to C1.4.
- `IDR/Mlir.cppm` re-exports the upstream names lanes report in their
  handoff as used and not exported. Known now:
  - `mlir::makeRegionIsolatedFromAbove`;
  - `mlir::getUsedValuesDefinedAbove`;
  - `mlir::createCanonicalizerPass` (its `GreedyRewriteConfig`
    overload);
  - `mlir::SideEffects::EffectInstance`;
  - `mlir::OpTrait::TraitBase`.

### C1.8 Generated and pinned files

- `CS/Dialect/Idr.idr` is regenerated by `tools/dialects.sh generate`
  after `IdrOps.td` and `idris-mlir-tblgen` change.
- `PINS.md` changes:
  - the two clang entries retire;
  - `mlir-recursion` and `bytecode-deferred-quadratic` lose their list
    cases;
  - `remove-dead-values-unreachable` names its new fixpoint hunk.
- `T/spec/file-size/allowed` follows the split units.

## C2. Ownership is declared where ops are defined (U03)

### C2.1 Consumption

Idris-mlir declares consumption once per op, in ODS. Two readers derive
from that one declaration:

- `idr-rc` asks `idr::consumes(operand)`, which tells it where a
  position takes over a reference, whatever the grade;
- every MLIR pass sees `MemoryEffects::Free` on `ReferenceResource`, but
  only where the operand's grade is `own` or `excl`, which is only after
  `idr-rc`.

Before `idr-rc`, every op keeps the purity it has today. After it, an
unused `idr.con` of owned fields is not dead to `remove-dead-values`.

| Op | Groups taken over | Trait | Its other effects |
|---|---|---|---|
| `idr.con` | `0` (fields) | `Idr_ConsumesOnly<"0">` | none |
| `idr.closure` | `0` (captures) | `Idr_ConsumesOnly<"0">` | none |
| `idr.suspend` | `0` (captures) | `Idr_ConsumesOnly<"0">` | none |
| `idr.yield` | `0` (results) | `Idr_ConsumesOnly<"0">` | none |
| `idr.share` | `0` | `Idr_ConsumesOnly<"0">` | none |
| `idr.nat.to_big` | `0` | `Idr_ConsumesOnly<"0">` | none |
| `idr.apply` | `1` (args) | `Idr_Consumes<"1">` | unknown, as today |
| `idr.lin.enter`, `idr.lin.use` | `0` | `Idr_Consumes<"0">` | today's, plus `consumedEffects` in `IDR/Dialect/Ops/Lin.cc` (U03) |
| `idr.dest.write` | the value's group | `Idr_Consumes<...>` | today's, plus `consumedEffects` in `IDR/Dialect/Ops/Dest.cc` (U03) |
| `idr.take`, `idr.reuse`, `idr.drop` | every group | `Idr_Consumes<...>` | today's, plus `consumedEffects` in `IDR/Ownership/Ops.cc` (U03) |
| `idr.array.new` (fill), `idr.array.set` (value), `idr.array.generate` (fill), `idr.array.fold` (init) | that group | `Idr_Consumes<...>` | today's, plus `consumedEffects` in `IDR/Dialect/Ops/Arrays.cc` (U04) |
| `idr.force` | `0`, taken over only when owned (C5.4) | `Idr_Consumes<"0">` | today's, plus `consumedEffects` in `IDR/Dialect/Ops/Lazy.cc` (U09) |

The coordinator fills in the exact group index of each `...` when it
applies the table to `IdrOps.td`. `IDR/Ownership/UseOf.cppm`'s
`useOf(operand, symbols)` then becomes
`consumes(operand) ? Use::Consume : Use::Borrow`, with today's call rule
inside `consumes`. The `isa` list is deleted.

### C2.2 The view is a grade

`idr-rc` writes `(u, borrow)` on every value of a counted carrier that
it treats as a view, where it writes plain `T` today. It never writes
plain `T` on such a value. A counted carrier is one that the ODS
constraint `Idr_CountedValueType` admits, looking through the grade. So
`idr::view(type)` keeps its signature and returns:

- `(quantity, Borrow)` for a counted carrier;
- `(quantity, ·)` otherwise.

An unboxed sum that holds no reference is graded `borrow` too. The
grade is then true but says nothing, and no count is emitted for it
(C2.3 decides that).

A function is in the owned stage when any operand, result or block
argument in it has permission `borrow`, `own` or `excl`. That is a fact
of its types. These read it there:

- the owned-stage verifier (`IDR/Ownership/Verify.cppm`, exactly once);
- `IDR/Ownership/OpChecks.cppm` (dup and drop are only legal in it);
- `IDR/Ownership/Borrowed.cppm` (a parameter is borrowed when its type's
  permission is `borrow`);
- `IDR/Narrow/Words.cppm` (U21: a big is counted when its grade is
  `own`, `excl` or `borrow`).

New verifier rule (U03): in a function in the owned stage, no value of a
counted carrier has permission `·`.

`idr.stage`, `IDR/Ownership/Stage.cppm` and the `idr.stage` entries in
`IDR/Dialect/Verify/Attributes.cc` are deleted.

### C2.3 One "holds references"

`idr::holdsReferences` (C1.4) replaces the private `counted(Type)` of
`IDR/Ownership/Counting.cppm` and every other walk that decides whether
a type holds references from its declaration. `Layouts::counted`, which
says which *lowered components* are counted pointers, is a different
question and stays (U10).

### C2.4 No sentinel values in C++

C++ that uses `ub.poison` to mean "no value" switches to `std::optional`
or a null `Value`. That covers:

- creating one as a placeholder;
- testing `isa<ub::PoisonOp>` to mean "nothing was there".

A `ub.poison` that is a value of the program is left alone. That covers:

- a value the defunctionalization analysis never reaches;
- the operand the `remove-dead-values-unreachable` patch passes;
- a poison an upstream pass made.

Each lane applies this rule to the sites in its own files. The sites at
ee4ce8e:

| File | Sites | Lane |
|---|---|---|
| `IDR/Lower/Cells.cppm` | 5 | U11 |
| `IDR/Lower/StaticData.cppm` | 2 | U12 |
| `IDR/Lower/Lowering.cppm` | 2 | U13 |
| `IDR/Lower/TailPosition.cppm` | 1 | U13 |
| `IDR/Lower/Matches.cppm` | 1 | U13 |
| `IDR/Lower/Loops.cppm` | 1 | U13 |
| `IDR/Lower/Facts.cppm` | 1 | U13 |
| `IDR/Narrow/Facts.cppm` | 3 | U21 |
| `IDR/Narrow/Versions.cppm` | 1 | U21 |
| `IDR/Narrow/Naturals.cppm` | 1 | U21 |
| `IDR/Tail/Returned.cppm` | 1 | U21 |
| `IDR/Tail/Loop.cppm` | 1 | U21 |
| `IDR/Specialize/ShapeOf.cppm` | 1 | U21 |
| `IDR/InBounds/Returned.cppm` | 2 | U06 |
| `IDR/InBounds/Components.cppm` | 2 | U06 |
| `IDR/InBounds/Lengths.cppm` | 1 | U06 |
| `IDR/Ownership/Placement.cppm` | 1 | U03 |
| `IDR/Ownership/IsStatic.cppm` | 1 | U03 |
| `IDR/Ownership/ExclusiveAnalysis.cppm` | 1 | U03 |
| `IDR/Ownership/Commit.cppm` | 1 | U03 |
| `IDR/Facts/Evaluation.cppm` | 1 | U03 |
| `IDR/Verify/Linearity.cppm` | 1 | U02 |
| `IDR/Defunctionalize/Sums.cppm` | 1 | U09 |
| `IDR/Defunctionalize/Converter.cppm` | 1 | U09 |

## C3. A partial op is a guard and a total op (U04, U05, U06, U17)

### C3.1 Which guard each partial op takes

| Total op | Guard on the operand | Cause (the crash message today, unchanged) |
|---|---|---|
| `idr.div`, `idr.mod` | `check.nonzero` on the divisor | `division by zero` |
| `idr.big.div`, `idr.big.mod` | `check.nonzero` on the divisor | the cause `Idr_BigDivisionOp` reports today |
| `idr.to_byte` | `check.byte` on the value | `a byte outside 0 to 255` |
| `idr.to_int`, `idr.big.from_double` | `check.finite` on the value | `cast of a non-finite Double`, and the one `BigFromDoubleOp` reports today |
| `idr.str.index` | `check.in_bounds` on the index, with `idr.str.length` of the string as the length | `string index out of range` |
| `idr.str.head`, `idr.str.tail` | `check.nonempty` on the string | the causes their ops report today |
| `idr.array.get`, `idr.array.set` | `check.in_bounds` on the index, with `memref.dim` of the array as the length | the `outOfBounds` text of `IDR/Dialect/Ops/Arrays.cc` |
| `idr.io.read_bytes`, `idr.io.write_bytes`, the five `buffer_*` ops | `check.range` on the offset, with the count and `memref.dim` of the buffer | `a byte range outside the buffer` |

A total op has no `getCrashCause`. The runtime functions they call keep
assuming their preconditions, as they do today
(`IDR/Lower/RuntimeCalls.cppm`: "checked before the call, whose runtime
function assumes it does not").

### C3.2 Who builds guards

- **Emit** (U17). The Idris side emits the guard right before the total
  op, and passes the guard's result in place of the operand. A partial
  primitive is the pair. There is no flag and no second path.
- **C++ passes that build a total op** on an operand that is not
  already proved: they build the guard too. U04 lists those creators in
  its handoff. Each lane fixes its own files, and U04 fixes `IDR/Fold`
  and `IDR/Ops`.
- **Nothing builds a total op without its guard unless the condition is
  proved where it runs.**

### C3.3 Speculation

A total op is speculatable only while each operand it guards is one of:

- the result of its guard op;
- a constant for which the guard's condition holds.

Otherwise it is `NotSpeculatable`. So when a guard is removed because a
path condition proves it, the op stays below that condition. When the
guard is present, the data dependence keeps the op below it. The rule
is written once, in `IDR/Dialect/Ops/Check.cc`, as
`idr::checkSpeculatability(Operation *, ArrayRef<unsigned> guardedOperands)`,
and every total op's `getSpeculatability` calls it (U04).

### C3.4 Folding

- **A guard folds to its operand** when the condition holds:
  - the operand is a constant;
  - `IntegerRangeAnalysis` proves it (`in_bounds`, `byte`, `nonzero` on
    integers, `range`);
  - its type proves it (a `!idr.nat` is never negative);
  - it is a `nonempty` of a constant non-empty string.
- **A guard whose operand is the result of an identical guard** (same
  kind, same operands) folds to that result.
- **A failing constant guard does not fold.** The crash stays.
- **One predicate per guard kind** lives in `Check.cc`, as
  `idr::checkHolds(CheckKind, ArrayRef<Attribute>)`. The guard's folder
  and every total op's folder call it. A total op does not fold when the
  predicate fails, because the folder would compute what the program
  never reaches, and APInt division by zero aborts the compiler.

### C3.5 Proving guards: `idr-in-bounds` (U06)

`idr-in-bounds` keeps its index systems. Instead of setting
`in_bounds`, it erases each `idr.check.in_bounds` it proves, replacing
the guard's result with its operand.

It also erases any guard that:

- a dominating guard of the same kind and operands already checks;
- `IntegerRangeAnalysis` proves at its point.

`idr-expect`'s `in-bounds=@f` property becomes "no `idr.check.in_bounds`
is left in `@f`" (`IDR/Expect/InBounds.cppm`). There is a new property,
`no-guards=@f`: no `idr.check.*` op is left in `@f`.

### C3.6 Lowering (U05)

Each guard lowers to the comparison today's lowering emits for its op
(`IDR/Lower/RuntimeCalls.cppm` `crashCondition`; `Scalars.cppm`
`LowerToByte`; `Arrays.cppm`; `Buffers.cppm`), followed by
`runtime.crashIf(..., cause)` and the result replaced by the operand.
The patterns live in a new `IDR/Lower/Checks.cppm`, partition
`idr.lower:checks`, which exports `populateCheckPatterns`. `crashCondition`
and every `getCrashCause()`-driven check in the total ops' lowering are
deleted. The crash message text and location stay those of the partial
op today. A guard gets the location the partial op had.

## C4. Deferred computation as regions (U07, U08)

### C4.1 What Emit writes

For an Idris `\x => e`, Emit writes:

```mlir
%f = idr.lambda : !idr.fn<(A) -> (B)> {
^bb0(%x: A):
  ...                       // the body, using enclosing values directly
  idr.yield %r : B
}
```

For `Delay e` (`Term.Suspend` today), Emit writes:

```mlir
%t = idr.delay : !idr.lazy<T> {
  ...
  idr.yield %v : T
}
```

A body that never returns ends in `ub.unreachable`, as a match region's
does. Emit's location for the region op is the lambda's.

### C4.2 The Idris side

- `Term.Lam` becomes `Lam : Loc -> Binder -> Term (Under 1 a) -> Term a`.
- `Term.Suspend` becomes `Suspend : Loc -> Term a -> Term a`.
- `TermF`, `hmap`, `para` and `printer` follow.
- `lam`, `delay` and `freeVars`'s closure-conversion use go, and so does
  `Emit/Bodies.idr`'s `lifted`, with the state's `lifted` field and its
  readers in `Emit/Declarations.idr` and `Emit/Monad.idr`.
- `Label` goes from `Ids.idr` if nothing else reads it. U07 checks with
  grep.
- `ArrayGen` and `ArrayFold` become one constructor:

  ```idris
  ||| A region op of the dialect (an `IdrRegionPrim`) applied to operands,
  ||| its body binding the block arguments the primitive declares, and
  ||| its results the `IORes` instance named.
  Region : {k : Nat} -> Loc -> (prim : IdrRegionPrim) -> (types : List Ty)
        -> List (Term a) -> Term (Under k a) -> DataId -> Term a
  ```

  `k` is `regionArity prim`. Both `IdrRegionPrim` and `regionArity` are
  generated (C8.2). `types` are the element and accumulator types
  today's two constructors carry. Emit has one case for `RegionF`.

### C4.3 `idr-isolate` (U08, `IDR/Isolate/`)

The pass runs first in the pipeline (C1.3). It walks innermost first
(post-order). For each `idr.lambda` and `idr.delay`:

1. **Isolate.** Call
   `makeRegionIsolatedFromAbove(rewriter, body, cloneIntoRegion)`, where
   `cloneIntoRegion` returns true for `idr.constant` and
   `arith.constant`. A constant is cloned into the body, never captured.
2. **Outline.** Create a private `func.func` named
   `<enclosing function's symbol>$lam<n>`, or `$delay<n>` for a delay.
   `n` counts the regions of that function in walk order from 0, and
   `SymbolTable::insert` renames on a collision. Its arguments are the
   captures first, in the order the call returned them, then the
   lambda's parameters. Its result is the yield's.
3. **Move the body.** Move the body in. The captures are appended to the
   block's arguments, so permute them to the front. Each `idr.yield`
   becomes `func.return`.
4. **Copy the attributes.** Copy onto the new function the attributes
   `Emit` put on a lifted function today: the owner's inherited
   attributes, and the lifted mark (read `Emit/Bodies.idr`'s `lifted`
   and `Owner.inherited` for the list). Its location is the region op's.
5. **Replace.** Replace the op with `idr.closure @name(captures)` or
   `idr.suspend @name(captures)`.

After the pass, no `idr.lambda` or `idr.delay` is left. The verifier of
each op (U08, `IDR/Dialect/Ops/Regions.cc`) checks:

- the block's arguments are the `!idr.fn` inputs, or none for a delay;
- every `idr.yield` matches the result type;
- for `idr.delay`, no value of world type is used from above, as
  `SuspendOp::verify` checks for captures today.

### C4.4 What phase 1 does not do

The simplify loop still sees the symbol form, so these stay:

- `ForceOfOneUse`, `ForceOfOneConstant`, `ForceInOneCase` and
  `ForceAtCapture`;
- closure specialization for captured constants. Isolation already
  clones constants into the body, so most of its cases are gone before
  it runs.

The two region rules of `substrate.md` S1.1 are phase 2, which needs
regions to survive the simplify loop. This cutover does not do it.

## C5. Thunks are memo sums (U09, U10, U11, U12, U14, U15)

### C5.1 Defunctionalization makes them

`idr-defunctionalize` follows `!idr.lazy<T>` keys exactly as it follows
`!idr.fn` keys. `Slots.cppm` already follows `SuspendOp` and `ForceOp`.
Each lazy key with a known, non-empty label set becomes a memo sum:

```mlir
idr.data @lazy$<n> box memo {
  idr.ctor @<label function>(captures...)  // one per label, named after it; by_name when its function has the io effect
  ...
  idr.ctor @running()
  idr.ctor @forced(T)
}
```

The rest of the conversion:

- The sum is always `box`. A memo cell has an identity: two references
  see one memo.
- `idr.suspend @f(caps)` becomes `idr.con @lazy$n::@f(caps)`.
- A `#idr.closure<@f, [caps]>` constant at a lazy type becomes
  `#idr.con<@lazy$n::@f, [caps]>`.
- Types `!idr.lazy<T>` become `!idr.box<@lazy$n>`. `idr.force` keeps its
  op and now takes the box.
- Coercions between keys are built as they are for closures, by
  rebuilding the label constructor in the other sum.
- `AdaptLazy.cc` goes. Its job, a lazy type that names a closure type,
  is now part of the key.
- The sums are numbered by first appearance, as closure sums are.

A ctor is `by_name` when the label function's `idr.effects` contains
`io`. Its function forges a world, as a trusted `unsafePerformIO` does.

**After `idr-defunctionalize`, no `!idr.lazy` type and no `idr.suspend`
op is left.** A lazy key the analysis cannot know is an internal error:
"internal error: a suspension is left after idr-defunctionalize". It is
the same rule as `checkNoClosures`, which now covers lazy values too
(U13).

`idr::isMemo(DataOp)` returns whether the `memo` attribute is set.
`DataOp`'s verifier checks that a memo sum is `box`, and that it has
exactly one `@running()` with no fields and one `@forced(T)` with one
field. `ForceOp`'s verifier accepts:

- a lazy value whose result is its `T`;
- a box of a memo sum whose `@forced` field type is the result type.

### C5.2 Layout (U10)

- **One size for every state.** A memo sum's cells all have one size:
  the largest of its constructors' cells. A cell is allocated in one
  state and written into another, so it must fit each.
- **The info word.** It is `tag | objs << 16 | IDRIS_RT_KIND_THUNK << 24`,
  with the tag and objs of the state the cell is in. Each state lays out
  its fields as a box does, object slots first.
- **The tags.** Each constructor's tag is its position. The lowering
  reads `running` and `forced` by name, never by number.
- **Deleted from Layout:**
  - `Layouts::closure(label)`;
  - `Layouts::forced(id)` and the `forcedCells` map;
  - the label table and `numLabels`;
  - `codeName` and `lazyDoneName`;
  - every closure-only path of `PlaceClosures.cc`.

  No cell holds a code address any more.

### C5.3 What a force does (U11, `IDR/Lower/Closures.cppm`)

`idr.force %t` with `%t : !idr.box<@lazy$n>` lowers by one generic
pattern, the same for every memo sum. Its result is owned, as today. It
goes by the cell's tag.

**When `%t` is a view** (grade `borrow` or `·`), the memo protocol:

| Tag | What happens |
|---|---|
| `forced v` | Load `v`, inc its counted components, return it. |
| `running` | Crash with the cause `a suspension forced itself`. |
| `L(caps)` | Load the captures. Write the `running` info word: the captures now belong to the forcer, so there is no inc and no dec. Call `L`'s function directly with them. Store `v` and the `forced` info word, keeping bit 31 (a stack cell). Inc `v`'s counted components once more for the cell. Return `v`. |
| `L(caps)`, `by_name` | Load the captures, inc each, call, return. Nothing is written. |

**When `%t` is owned and `excl`** (the one-shot force), there is no
memo:

| Tag | What happens |
|---|---|
| `L(caps)` | Load the captures, free the cell's memory with `idris_rt_free_cell`, call, return. |
| `forced v` | Load `v` (moved out, no inc), free the cell, return. |
| `running` | Crash as above. |

**When `%t` is owned but not `excl`:** the memo protocol, then a dec of
`%t`.

The dispatch over a cell's labels is a `switch` on the tag, one
direct call per label. A sum with one label needs no switch on its
labels.

**Captures and borrowed parameters.** `idr-rc` may make a label
function borrow a parameter: its type then has permission `borrow`. Where
the captures moved out (the view protocol and the `excl` row), the forcer
owns each capture once:

- it passes an owned parameter that reference;
- it passes a borrowed one, then decs it after the call.

In the `by_name` row the cell keeps its captures:

- an owned parameter gets an inc;
- a borrowed one gets the cell's reference as it is.

`populateLazyPatterns` keeps its name and holds this pattern.
`LowerSuspend` goes: no `idr.suspend` reaches the lowering.

### C5.4 Who decides the grade of a force (U03)

`idr-rc` passes the operand of `idr.force` owned when the force is its
last use, and `excl` when `ExclusiveAnalysis` proves it, as it does for
`idr.take`. Otherwise the operand is a view. `idr.force` is in the C2.1
table (group 0, taken over only when owned).

### C5.5 Static thunks (U12, `IDR/Lower/StaticData.cppm`)

- **The global.** A constant of a memo-sum box lowers to a private,
  non-constant `llvm.mlir.global`. Its initializer is the cell's image:
  header count 0, the `L(caps)` info word with kind
  `IDRIS_RT_KIND_THUNK`, and the persistent captures. Every other static
  cell stays `constant`. The `frozen` flag goes; the kind is what marks a
  cell a force may write.
- **Why not thread-local.** Static data can point at a static thunk: a
  constant stream's tail is one. A thread-local global's address is not
  a link-time constant, so a `constant` global could not hold it. So the
  memo cell stays one per process in this cutover. The per-shard copy of
  `concurrency.md` §2.4 belongs to the shards work. The thunk kind is what
  lets that work find every such cell.
- **`@__idr_release_cafs`.** StaticData collects every such global, and
  idr-lower emits `func.func private @__idr_release_cafs()`. It calls
  `idris_rt_caf_release` on the address of each, then returns. It is
  emitted even when the module has none, so that `idr-entry` can call it
  without asking. It is built by `StaticData::emitReleaseCafs(OpBuilder &)`
  (U12). `Runtime::finish()` (U11) calls it, and `lowerModule` (U13)
  calls `runtime.finish()` where it called the old code emission.
- **The only written static data is these memo cells**, each written
  once by its first force, and each marked by its kind. The runtime keeps
  no list of them.

### C5.6 The runtime (U15)

- `idris_rt_lazy_kept`, the `Kept` list and
  `idris_rt_release_persistent`'s walk of it go.
- `idris_rt_caf_release` releases the object slots of a persistent cell,
  which is `releaseKept`'s body today.
- `idris_rt_main_return` no longer walks a list. `@__idr_main` calls
  `@__idr_release_cafs` before it (C6.4).
- Freeing treats `IDRIS_RT_KIND_THUNK` as it treats a box. There is no
  closure release; the closure kind is gone.

### C5.7 Reify (U14)

A memo-sum box in an evaluation result reads back as follows:

| State | Reads back as |
|---|---|
| `L(caps)` | `#idr.closure<@L, [caps]>`, at the lazy type of the original module |
| `forced v` | refused with `Unread::Why::Memoized`, as today |
| `running` | refused with `Unread::Why::Unreadable` |

A closure sum's box or unboxed value reads back as
`#idr.closure<@label, [captures]>`. The label is the constructor's leaf
name; `IDR/Facts/ClosureLabel.cppm`'s `closureLabel` says which sums are
closure sums. The code table goes.

## C6. One evaluation mode (U11, U13, U14, U15)

### C6.1 The lowering has no mode

- `lowerModule(ModuleOp)` takes no flag.
- `Runtime(ModuleOp, Layouts &)` takes none, and has no `isJit()`.
- Every cell is allocated with `idris_rt_cell`.
- `inc` and `dec` are always emitted. In the evaluator's arena every
  cell is persistent, so they do nothing there, as `idris_rt.h` already
  says.
- A crash always calls `idris_rt_crash` (C1.5).
- `idr.may_loop` always lowers to `llvm.sideeffect`.
- `Facts::apply` always runs.
- `StackCell` marks are lowered the same way everywhere. `idr-stack`
  runs after the simplify loop, so evaluation never sees one.
- `populateClosurePatterns`, `Runtime::code`, `codeType`, `emitCode`,
  `emitClosure`, `emitSuspension`, `doneCode`, `storeForcedInfo` and
  `distinguish` go.

### C6.2 `idr-meter` (U13, `IDR/Lower/Meter.cppm`, `IDR/Lower/Meter/Pass.cc`)

The pass runs after `idr-lower` on the evaluation pipeline only. For
every defined `func.func`:

- at the entry block's start, it inserts a call of `idris_rt_eval_tick`;
- right before each `llvm.call_intrinsic "llvm.sideeffect"` (the
  lowered `idr.may_loop`), it inserts another.

The callee is declared as an `llvm.func` if absent.

### C6.3 `idr-entry` (U13, `IDR/Lower/Entry.cppm`, `IDR/Lower/Entry/Pass.cc`)

The pass runs after `idr-lower` on the program pipeline only. It moves
`findRoot`, `requiredCpuFeatures` and `emitMain` out of
`Lowering.cppm`, with these changes:

- The root's kind comes from its lowered signature: `() -> i64` returns
  the status, and `() -> ()` returns 0.
- `@__idr_main` calls the root, then `@__idr_release_cafs`, then
  `idris_rt_main_return`.
- `@main` is `(i32, !llvm.ptr) -> i32` and passes `argc` and `argv` to
  `idris_rt_start` (C1.5).
- Runtime functions are declared as `llvm.func` where absent, with the
  attributes `Runtime::call` gives today (`noreturn` on crashes,
  `zeroext` on narrow arguments).

### C6.4 The evaluator (U14)

- **Scratch.** `IDR/Eval/Scratch.cppm` builds the scratch module as
  today.
- **Pipeline.** `IDR/Eval/Round.cppm` runs the evaluation pipeline of
  C1.3 on it. `idr-defunctionalize` runs first, so the closures and
  thunks of the calls become sums before lowering. A call whose scratch
  module still holds a closure after it is left for runtime, with the
  reason "a closure the analysis cannot follow". Nothing is evaluated
  unsoundly.
- **No code table.** `codesName` and the label loop go.
- **Reify.** It reads closure and memo sums per C5.7. It builds list
  spines with `ConAttr::getRun` (C7.2), never by nesting `get`.

### C6.5 The runtime (U15)

- **Crashes.** `idris_rt_crash` checks whether the process is an
  evaluation child; `rt::alloc::arenaActive` says so. If it is, it does
  what `idris_rt_eval_crash` does.
- **Arguments.** `idris_rt_start` stores `argc` and `argv` where
  `rt.start` exports them, as `rt::start::argumentCount()` and
  `rt::start::argument(int64_t)`. They are read by U16's
  `idr.io.arg_count` and `idr.io.arg`.

## C7. Constants are flat (U19, with U12 and U14)

### C7.1 The representation

A `#idr.con` is stored in one of two ways:

- **plain:** the constructor and its fields;
- **run:** `n >= 2` cells of one constructor `C`, linked through one
  field index `s` (the spine), ending in a tail.

The run form stores the constructor, then `n` arrays of the non-spine
fields, one per cell, then the tail and `s`. `getFields()` reads both
forms the same way. For a run cell it returns the cell's non-spine
fields, with the next cell at index `s`. That next cell is the same run
at offset `k + 1`, and when only the tail is left it is the tail.

**The canonical form.** `ConAttr::get(ctor, fields)` builds a run
whenever exactly one field is a `#idr.con` of the same constructor
symbol, plain or run. So one value has one attribute, and equality and
uniquing still mean value equality. A tree constructor with two fields
of its own constructor stays plain.

### C7.2 The API (U19, `IDR/Dialect/Attrs/ConAttr.cc`)

```cpp
static ConAttr get(MLIRContext *, SymbolRefAttr ctor, ArrayAttr fields);  // canonicalizes, as above
static ConAttr getRun(MLIRContext *, SymbolRefAttr ctor, unsigned spine,
                      ArrayRef<ArrayAttr> cells, Attribute tail);         // O(n): reify and list folders use it
SymbolRefAttr getCtor() const;
ArrayAttr getFields() const;          // as today, for both forms
bool isRun() const;
unsigned getRunLength() const;        // 1 for a plain con
```

Prepending one cell to a run copies the run. So a builder that conses
cell by cell builds the list with `getRun` instead:

- `IDR/Eval/Reify.cppm` (U14);
- `IDR/Fold/StringOfList.cc` and `IDR/Fold/Lists.cppm` (U04).

**Printing, parsing and walking.**

- The plain form prints as today. A run prints flat:

  ```
  #idr.con<@List::@Cons, run 1 [[e0], [e1], ...] tail #idr.con<@List::@Nil, []>>
  ```

  The parser reads both forms.

- `walkImmediateSubElements` and `replaceImmediateSubElements` visit the
  cells' fields and the tail directly, never a nested run. A run of any
  length is therefore one level deep to MLIR's printer, parser, bytecode
  and walks.

**What uses it.**

- `IDR/Lower/StaticData.cppm` (U12) lowers a run to its static cells
  with a loop, not by recursion.
- `IDR/Dialect/Dialect/Constants.cc` keeps materializing it, since it is
  a `ConAttr`.

### C7.3 What retires

The list cases of `mlir-recursion` and `bytecode-deferred-quadratic`
retire. The reserved compile stack and the reader patch stay for other
deep data. The coordinator edits their PINS entries.

## C8. One primitive set (U17, U18, U07)

### C8.1 Which ops are primitives

`Idr_Primitive` goes on every op that has no inherent attribute and
that the Idris side emits one-to-one for an Idris primitive. The
candidates:

- **Strings:** the `str.*` ops;
- **Bigs and naturals:** the `big.*` and `nat.*` ops;
- **IO:** `put_str`, `put_char`, `put_double`, `get_byte`, `get_line`,
  `write_bytes`, `read_bytes`, `eof` and `n_processors`;
- **Arrays:** `array.new`, `array.get` and `array.set`;
- **Buffers:** the five `buffer_*` ops;
- **The rest of today's set:** `crash_str`, `os`, `world.new`, `to_char`,
  `to_byte`, `to_int`, `double_head`, `div`, `mod`, `shl`, `shr` and
  `io.put_list`;
- **New:** every op of C9.

`array.generate` and `array.fold` get it too. They are the region
primitives.

These do not get it:

- A candidate with an inherent attribute, such as a comparison predicate
  or a signedness unit: it stays a `Prim` constructor that Emit builds
  with the op's generated builder, as today.
- The six guards: Emit builds them with their generated builders
  (`Idr.checkNonzeroOp` and the rest) from `guardOf` (C8.3).

`idris-mlir-tblgen` fails on an `Idr_Primitive` op that has an
inherent attribute. That keeps the rule true.

### C8.2 What `idris-mlir-tblgen -gen-idris-dialect` adds (U17)

The generator adds these to `CS/Dialect/Idr.idr`:

```idris
||| The dialect's primitives (ops with Idr_Primitive and no region), one
||| constructor each, named after the op's C++ class without `Op`.
public export
data IdrPrim = StrAppend | StrCons | ... | FileOpen | ...

||| The dialect's region primitives.
public export
data IdrRegionPrim = ArrayGenerate | ArrayFold

||| The block arguments a region primitive's body takes.
public export
regionArity : IdrRegionPrim -> Nat

||| Whether the primitive takes and gives the world (Idr_PerformsIO).
export
primPerformsIO : IdrPrim -> Bool

||| The operation of a primitive on operands, with its result types
||| (a primitive has no inherent attribute).
export
primOp : IdrPrim -> List Operand -> List MlirType -> Operation

export
regionOp : IdrRegionPrim -> List Operand -> Region -> List MlirType -> Operation
```

The names follow the C++ class names, so for example
`Idr_FileOpenOp` gives `FileOpen` and `Idr_StrAppendOp` gives
`StrAppend`. ODS defines those class names (C1.1, C9.2).

### C8.3 `CS/Types.idr` (U17)

- **`Prim`.** It keeps the constructors that are not one op:
  - `IntOp`, `IntShift`, `FloatOp`, `Negate`, `Math`, `Compare` and
    `Cast` map to `arith` and `math`, choosing by signedness and width;
  - `NatFromBig`, `NatToBig`, `StrBuild` and `ArrayLength`.

  Every constructor that is exactly one `idr` op becomes `Op IdrPrim`.
  U17 lists the mapping in its handoff.
- **`IOOp` and `ioArgs` go.** IO primitives are `Op p` with
  `primPerformsIO p`. Operand types come from the primitive's Idris
  type, which the registry entry already has.
- **`ArrayLoop` goes,** replaced by `IdrRegionPrim`.
- **Emit.** `Emit/Operations.idr` has one generic case for `Op p`: it
  passes operands, threads the world when `primPerformsIO p`, builds the
  `IORes` instance, and emits the guard of C3.1 before each partial
  primitive. That last is a table from `Prim` to the guard,
  `guardOf : Prim -> Maybe (Guard, operand index, cause)`, in
  `Emit/Operations.idr`. It is the one place the Idris side knows a
  guard.

### C8.4 The registry (U18)

`CS/Registry/Primitives.idr` maps each Idris primitive name to `Op p`,
`Region p` or a remaining `Prim` constructor. It keeps every existing
entry, with the same Idris names and shapes. It adds the entries of C9.

## C9. Base's surface is runtime primitives (U16, U18)

### C9.1 A pointer is a runtime handle

A `Ptr t` or `AnyPtr` value is an `i64` handle:

- `0`, `1` and `2` are the standard streams, as today;
- `-1` (all ones) is the null handle;
- any other value is a slot of the runtime's handle table, which holds a
  file, a directory, a file time or a string.

No address ever reaches Idris code. `%foreign` is excluded in user code,
so every pointer a program can hold comes from a recognized primitive.
So the pointer operations base's wrappers use are handle operations:

| Idris | Op or hook |
|---|---|
| `prim__nullAnyPtr`, `prim__nullPtr` | `idr.handle.is_null` (`i64 -> i64`, 1 when null) |
| `prim__getNullAnyPtr` | a literal handle, `-1` (registry `Handle (LInt UInt64 18446744073709551615)`) |
| `prim__forgetPtr`, `prim__castPtr` | identity (registry hook on the last argument) |
| `prim__getString` | `idr.handle.string` (`i64 -> !idr.str`; reads the slot's string, one new reference; `MemRead<Idr_IOResource>`, so it stays before the slot's release) |
| `prim__free` (System.FFI) | `idr.io.handle_free` (releases the slot; the string it held loses a reference) |

`PrimIO.Ptr` gets a `WordType` registry entry beside `AnyPtr`'s. U18
adapts `Frontend/Translate/Types.idr`'s `WordType` handler to an applied
`Ptr t`.

`RawPointer` stays for what is still raw: `prim__malloc` and
`prim__castPtr` of a non-handle. The `ruledOut` entries for
`prim__getString`, `prim__nullPtr`, `prim__forgetPtr`,
`prim__nullAnyPtr`, `prim__getNullAnyPtr` and `System.getEnv` go.

### C9.2 The IO primitives

Every op below is `idr.io.<name>`, and its runtime function is
`idris_rt_io_<name>`. `h` is an `i64` handle and `s` is `!idr.str`. A
`Ptr String` result is a string handle, or null. Unless a row says
otherwise, an `Int` result is the C support function's value.

The meaning of each is the C support function its `%foreign` spec names
(`third_party/Idris2/support/c/`). Chez is the test oracle. A failing
call sets the runtime's saved errno, which `idr.io.errno` and
`idr.io.file_errno` read.

**Files** (`System.File.*`):

| Idris primitive | Op | Operands -> results |
|---|---|---|
| `prim__open` | `file_open` | `s path, s mode -> h` (null on failure) |
| `prim__close` | `file_close` | `h -> ()` |
| `prim__error` | `file_error` | `h -> i64` |
| `prim__fileErrno` | `file_errno` | `-> i64` |
| `prim__readLine` | `file_read_line` | `h -> h` (a string handle) |
| `prim__readChars` | `file_read_chars` | `i64 max, h -> h` |
| `prim__readChar` | `file_read_char` | `h -> i64` |
| `prim__writeLine` | `file_write_line` | `h, s -> i64` |
| `prim__flush` | `file_flush` | `h -> i64` |
| `prim__seekLine` | `file_seek_line` | `h -> i64` |
| `prim__removeFile` | `file_remove` | `s -> i64` |
| `prim__fileSize` | `file_size` | `h -> i64` |
| `prim__fPoll` | `file_poll` | `h -> i64` |
| `prim__fileIsTTY` | `file_is_tty` | `h -> i64` |
| `prim__fileTime` | `file_time` | `h -> h` (a file-time handle) |
| `prim__filetimeAccessTimeSec` and the five siblings | `file_atime_sec`, `file_atime_nsec`, `file_mtime_sec`, `file_mtime_nsec`, `file_ctime_sec`, `file_ctime_nsec` | `h -> i64` |
| `prim__chmod` | `file_chmod` | `s, i64 -> i64` |

The existing file ops change in two ways:

- `idr.io.read_bytes`, `idr.io.write_bytes` and `idr.io.eof` serve any
  open file handle, besides 0, 1 and 2.
- Reads on handle 0 go through the runtime's input buffer
  (`RT/Io/Input.cppm`), and writes on handles 1 and 2 through its output
  path (`RT/Io/Output.cppm`). So `fGetLine stdin` and `getLine` share
  one buffer, and file writes and `putStr` keep their order.

**Directories** (`System.Directory`):

| Idris primitive | Op | Operands -> results |
|---|---|---|
| `prim__currentDir` | `dir_current` | `-> h` (a string handle) |
| `prim__changeDir` | `dir_change` | `s -> i64` |
| `prim__createDir` | `dir_create` | `s -> i64` |
| `prim__removeDir` | `dir_remove` | `s -> ()` |
| `prim__openDir` | `dir_open` | `s -> h` (null on failure) |
| `prim__closeDir` | `dir_close` | `h -> ()` |
| `prim__dirEntry` | `dir_entry` | `h -> h` (a string handle, or null at the end) |

**The process** (`System`):

| Idris primitive | Op | Operands -> results |
|---|---|---|
| `prim__getArgCount` | `arg_count` | `-> i64` |
| `prim__getArg` | `arg` | `i64 -> s` |
| `prim__getEnv` | `env_get` | `s -> h` (a string handle, or null) |
| `prim__getEnvPair` | `env_pair` | `i64 -> h` |
| `prim__setEnv` | `env_set` | `s, s, i64 -> i64` |
| `prim__unsetEnv` | `env_unset` | `s -> i64` |
| `prim__sleep` | `sleep` | `i64 -> ()` |
| `prim__usleep` | `usleep` | `i64 -> ()` |
| `prim__time` | `time` | `-> i64` |
| `prim__getPID` | `pid` | `-> i64` |
| `prim__exit` | `exit` | `i64 -> ()` (pending output written; does not return) |

**The terminal** (`System`, `System.Term`):

| Idris primitive | Op | Operands -> results |
|---|---|---|
| `prim__enableRawMode` | `term_raw` | `-> i64` |
| `prim__resetRawMode` | `term_reset` | `-> ()` |
| `prim__setupTerm` | `term_setup` | `-> ()` |
| `prim__getTermCols` | `term_cols` | `-> i64` |
| `prim__getTermLines` | `term_lines` | `-> i64` |

**Errors** (`System.Errno`):

| Idris primitive | Op | Operands -> results |
|---|---|---|
| `prim__getErrno` | `errno` | `-> i64` |
| `prim__strerror` | `strerror` | `i64 -> s` |

**Clocks** (`System.Clock`):

| Idris primitive | Op | Operands -> results |
|---|---|---|
| `prim__clockTimeMonotonic`, `prim__clockTimeUtc`, `prim__clockTimeProcess`, `prim__clockTimeThread`, `prim__clockTimeGcCpu`, `prim__clockTimeGcReal` | `clock_monotonic`, `clock_utc`, `clock_process`, `clock_thread`, `clock_gc_cpu`, `clock_gc_real` | `-> i64`, an `OSClock` (C9.4) |
| `prim__osClockValid`, `prim__osClockSecond`, `prim__osClockNanosecond` | `clock_valid`, `clock_second`, `clock_nanosecond` | `i64 -> i64` |

### C9.3 The handle ops

| Op | Operands -> results | Effects |
|---|---|---|
| `idr.handle.is_null` | `i64 -> i64` | `Pure` |
| `idr.handle.string` | `i64 -> !idr.str` (allocates) | `MemRead<Idr_IOResource>`, `MemAlloc` on the result |
| `idr.io.handle_free` | `h -> ()` | an `Idr_IOOp` |

### C9.4 `OSClock` is an immediate value

An `OSClock` is `seconds << 30 | nanoseconds`, with `seconds < 2^33`.
That covers every clock until the year 2242. An invalid clock is `-1`.
The two GC clocks are always invalid, since no collector runs, so
`clockTime GcCpu` and `clockTime GcReal` give `Nothing`. This is the
divergence class `gc-clock`, which U23 adds.

Because the value is immediate, a clock reading never allocates and no
handle leaks.

### C9.5 What stays outside, by name (U18)

| What | Rule | Registry change |
|---|---|---|
| `System.Signal` (16 foreign definitions) | `signal` | each `prim__` of the module, and its public functions, `ruledOut ... Signal` |
| `System.Concurrency` (21 foreign definitions) | `threads` | `ruledOut ... Threads`, as `Prelude.IO`'s `fork` is |
| `prim__system`, `prim__popen`, `prim__pclose`, `prim__popen2` and its five accessors (`System`, `System.File.Process`) | `process` | `ruledOut ... Process` |

### C9.6 Both targets

Every runtime function lives under `RT/Platform/Posix/` or `RT/Io/`.
Where Linux and macOS differ, the difference sits in one function of
`RT/Platform/Posix/`, selected by the target's macros, never in `RT/Io`:

- `stat`'s time fields are `st_atim` on Linux and `st_atimespec` on
  macOS;
- the clock ids;
- `TIOCGWINSZ`.

## C10. The promises, checked (U02, U20)

### C10.1 The cycle check (U02, `IDR/Verify/Cycles.cppm`)

The `idr.program` verifier builds the type reachability graph. Its
nodes are the module's data declarations and array element types. Its
edges go from a declaration to the declarations and arrays its fields'
carriers name, through unboxed sums and grades. Arrays are memrefs of a
field type.

A cycle that passes through an array edge is rejected:

```
unsupported (cycle): an array of <T> can hold a reference to itself through <T> -> <U> -> ... -> <T>
```

That names every type on the cycle, at the location of the first
`idr.array.new` of the element type, or else the module.

Memo sums are not mutable edges. A memo is written once, with a value
computed from captures that existed before the cell, so it cannot reach
itself. Idris has no recursive `let` of values.

Before `idr-defunctionalize`, a closure's captures are not types yet. So
the check is complete from `idr-defunctionalize` on, and sound but
partial before it.

### C10.2 The in-place promise (U20, `IDR/Demand/`)

`idr-demand{promises=in-place}` runs after `idr-rc`. For every function
`f`, it takes each parameter `p` that meets both conditions:

- `p`'s type has quantity 1;
- `f` matches `p` and rebuilds a constructor of the same size from its
  cell, which the `reuses-in-place` property of `idr-expect` already
  recognizes.

Every call of `f` must then pass `p` with permission `excl`. A call that
passes `own` or `borrow` is rejected:

```
unsupported (uniqueness): <caller> passes a shared <T> to <f>, which rebuilds it in place; it is shared because <the reference that made it shared>
```

The error goes at the call. The second clause names the dup, or the
use that kept the value alive (read from `ExclusiveAnalysis`'s reason).

Without `promises`, the pass does nothing. `--demand in-place` on
`idris-mlir-cc` (`IDR/Driver/Options.cppm`) runs it with the promise,
and so does `--directive demand-in-place` on `idris-mlir`
(`CS/Frontend/Main.idr`, as `no-eval` is passed today). O5 makes the
promise the default, later.

## C11. Upstream patches instead of workarounds (U01)

### C11.1 The two clang crashes

For each of `clang-module-layout-forward-declaration` and
`clang-module-predeclared-new`, U01:

1. reduces the report's unit with the pinned clang;
2. finds the fix: a backport (the predeclared-new case is likely #189252)
   or a patch of its own;
3. writes it as `upstream/<bug>/llvm.patch`;
4. completes the README's `## Patch` and `## Upstreaming plan`;
5. makes `tests/upstream/<bug>/run` report "no longer crashes" against
   the patched clang;
6. writes `IDR/Stack/Escape.cppm`'s sets as `SetVector<Operation *>` and
   `IDR/Driver/Retarget.cppm`'s feature string as `std::string`, with
   their `PIN` markers gone.

### C11.2 `idr-dead-values`

U01 reduces "remove-dead-values rebuilds a call when nothing is erased"
to upstream ops and `mlir-opt`. If it reproduces, the fix is a hunk in
`upstream/remove-dead-values-unreachable/llvm.patch`: the pass leaves an
op untouched when it erases none of its operands or results. Its
reproducer is added beside the others, and a check goes in
`tests/upstream/remove-dead-values-unreachable`. `IDR/Simplify`'s round
then runs upstream `remove-dead-values`, and
`IDR/Simplify/DeadValues.cppm` and `DeadValues/Pass.cc` go.

If it does not reproduce upstream, the bug is ours. U01 fixes it in
`IDR/Simplify`, says so, and the pass still goes.

## C12. The discriminators (U22, U23)

Every row below must fail against the tree at ee4ce8e, or show the old
mechanism, and pass after the cutover. Names are directories under `T/`.

| Test | Kind | What it shows | Proves |
|---|---|---|---|
| `reject/cycle-array-knot` | reject | `data Node = MkNode (IOArray Node)`, a knot written: `unsupported (cycle)`, naming `Node` | C10.1 |
| `programs/arrays/array-of-arrays` | program, Chez | `IOArray (IOArray Int)` compiles and runs | C10.1 is not too strong |
| `reject/signal-handler` | reject | `System.Signal.collectSignal`: `unsupported (signal)` | C9.5 |
| `reject/threads-concurrency` | reject | `System.Concurrency.makeMutex`: `unsupported (threads)` | C9.5 |
| `reject/process-system` | reject | `System.system "true"`: `unsupported (process)` | C9.5 |
| `reject/uniqueness-shared-rebuild` | reject, `--directive demand-in-place` | a shared list passed to a quantity-1 `map` that rebuilds in place: `unsupported (uniqueness)` naming the call | C10.2 |
| `programs/linear/leet-*` | program | every leet fixture compiles with `demand-in-place` and still `tests-nothing` | C10.2 is not too strong |
| `programs/io/files-roundtrip` | program, Chez | write a file, read it back by line and by chars, `fileSize`, `removeFile` | C9.2 |
| `programs/io/directory-listing` | program, Chez | `createDir`, `openDir`, `nextDirEntry` until `Nothing` (sorted), `removeDir` | C9.2 |
| `programs/io/environment-arguments` | program, Chez | `getArgs`, `getEnv "HOME"`, `setEnv`, `getEnv` again | C9.1, C9.2 |
| `programs/io/clock-monotonic` | program | two monotonic readings, the second not earlier; `GcCpu` gives `Nothing` | C9.4 |
| `programs/eval/memo-shared-stream` | program, Chez, `IDRIS_RT_LIVE=1` | `fibs` shared by two consumers forces each cell once (a trace through a trusted forged world counts forces) | C5.3 |
| `programs/eval/thunk-consumes-list` | program, `IDRIS_RT_LIVE=1` | a thunk that consumes a 10^6-element list: peak live cells bounded, list reused in place (`reuses-in-place`) | C5.3 (captures moved) |
| `programs/partial/self-forcing-caf` | program, `expected-crash` | a top-level lazy value that forces itself ends with `a suspension forced itself` | C5.3 |
| `programs/eval/closure-result-roundtrip` | program, Chez | a compile-time result holding a closure (a partially applied function in a list) is reified and run | C6.4, C5.7 |
| `programs/eval/deep-list-constant` | program | a computed 10^5-element list constant on an 8 MiB compile stack | C7 |
| `programs/basic/guards-messages` | program, `expected-crash` × 6 | each of div by zero, `strIndex` out of range, `strHead ""`, `cast` of NaN to Int, a byte out of range, an array index out of bounds: the same message and location as at ee4ce8e | C3 |
| `idr/guards/fold-*` | lit | each guard folds on a proving constant, does not on a failing one, folds under a dominating identical guard | C3.4 |
| `idr/guards/speculation` | lit | `licm` does not hoist `idr.str.index` out of the `scf.if` that proved its guard away | C3.3 |
| `idr/in-bounds/*` | lit | restated as "no `idr.check.in_bounds` left"; no `in_bounds` keyword anywhere | C3.5 |
| `idr/isolate/*` | lit | captures leading, constants cloned not captured, nested lambdas isolated innermost first, names `$lam<n>`/`$delay<n>` | C4.3 |
| `idr/defunc/memo-*` | lit | a lazy key becomes a `memo` box sum with `running` and `forced`; a world-forging label is `by_name`; no `!idr.lazy` remains | C5.1 |
| `idr/lower/force-*` | lit | view force: one switch, direct call, `running` written before the call; `excl` force: free and no write | C5.3 |
| `idr/lower/static-thunk` | lit | a lazy constant lowers to a non-constant global with the thunk kind, listed in `@__idr_release_cafs`; a constant stream whose tail is that thunk lowers to a `constant` global pointing at it; every other static global is `constant` | C5.5 |
| `idr/lower/no-mode` | lit | `idr-lower` has no `jit` option (`--idr-lower=jit=1` is an unknown option) | C6.1 |
| `idr/lower/entry`, `idr/lower/meter` | lit | `@main(i32, ptr)`; ticks at entry and before each `llvm.sideeffect` | C6.2, C6.3 |
| `idr/ownership/consumed-effects` | lit | after `idr-rc`, `remove-dead-values` keeps an unused `idr.con` of owned fields; before it, `canonicalize` erases an unused `idr.con` | C2.1 |
| `idr/ownership/borrow-grade` | lit | `idr-rc`'s output has `borrow` views and no `idr.stage` | C2.2 |
| `idr/constants/run` | lit | a 10^4-cell run prints flat, round-trips through text and bytecode, and `getFields` walks it | C7 |
| `idr/verify/cycle` | lit | the verifier rejects the knot's types after defunctionalization | C10.1 |

Existing tests that name a retired mechanism are restated in the new
terms or deleted by U22 or U23. "Retired mechanism" means any name in
README's retired list. A test whose only purpose was the retired
mechanism is deleted, never kept as a red test.

## C13. Verification

- **During the swarm, no lane runs** `make build`, `make test`,
  `make test-idr`, `make test-mlir-tools`, cmake, ninja, the Idris
  compiler, or any test. The tree is red mid-swarm by design: lanes
  write against declarations other lanes are writing.
- **Exceptions:**
  - `make check`, which builds nothing, may run anywhere;
  - U01 may run the pinned clang and `mlir-opt` on its own reproducers.
- **Integration** (coordinator):
  1. `make check`
  2. `make build`
  3. `make test`
  4. `make test-idr`
  5. `make test-mlir-tools`

  Repairs go through the owning lane. Then rerun.
- **Qualification:** README "Qualification".
