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
`findings/concurrency.md` §2, read at ee4ce8e and rechecked at 1677b8cb
and at ccc3e1dc, the launch base (README "Rulings at launch"). Where this file disagrees
with them, this file is the newer decision, and README "Rulings" says why.

## C0. What does not change

- **The semantics.** Every program prints, exits and crashes exactly as
  before: the same bytes, the same status, the same crash message at the
  same location, as every fixture's committed expected files state.
  Those files are the specification (`findings/decision-no-oracle.md`):
  no existing `expected-stdout`, `expected-exit` or `expected-crash`
  changes, except in a test C12 restates, and no test is compared with
  Idris's Chez backend or stock evaluator. What C9 adds means what the
  runtime documents (C9.2, C9.4).
- **Quantities and erasure.** Every quantity and erasure stays in the
  types (`!idr.erased`, `!idr.lin<T>`, `!idr.q`), and the verifier keeps
  checking it after every pass.
- **The targets.** Nothing assumes x86, Linux, ELF or musl outside the
  target entry. The runtime's OS calls go through `RT/Platform/Posix`,
  which serves both x86_64 Linux and arm64 macOS.
- **The closure symbol form inside the simplify loop.** `idr.closure`,
  `idr.suspend`, `#idr.closure`, `idr.apply` and `idr.force`, and the
  four `ForceOf*` patterns in `IDR/Dialect/Ops/Lazy.cc`, stay as they are
  (C4.4), except that `idr.force`'s operand may also be a memo box after
  `idr-defunctionalize` (C1.1 item 5, C5.1). `IDR/Canon/Feeds.cppm`'s rule that a force meets a suspension
  nothing else uses (1677b8cb) is kept, restricted to `!idr.lazy`
  operands (C3.4).
- **The unit size.** Every `.cc` or `.cppm` under `foreign/idr` or
  `runtime` stays at 400 lines or fewer, unless it is already listed in
  `T/spec/file-size/allowed`. A unit that grows past 400 is split in the
  same lane.

## C1. The hubs the coordinator writes

The coordinator applies C1 to the hub files at dispatch, from this text.
Lanes import the names below as if the hubs had already landed. The one
exception is C1.2's `idr-dead-values` lines, which go in with U01's
held-out group at integration step 5 (C13).

At the pin (llvm main 7208ba24, 20fcfadb) ODS formats are strict: a
declarative assembly format binds every inherent attribute (or has
`prop-dict`, which no `idr` op uses), `attr-dict` carries discardable
attributes only, and mlir-tblgen rejects a format that leaves one out
(`findings/llvm-trunk-mechanisms.md`, mechanism 2). Every format below
obeys it.

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
   // The trait is ::idr::ConsumesOperands<groups>::Impl: a ParamNativeOpTrait
   // names ::mlir::OpTrait:: unless its class sets the namespace, as
   // Idr_MayCrashTrait does.
   class Idr_ConsumesOperandsTrait<string groups>
       : ParamNativeOpTrait<"ConsumesOperands", groups> {
     let cppNamespace = "::idr";
   }
   class Idr_Consumes<string groups>
       : TraitList<[Idr_ConsumesOperandsTrait<groups>, Idr_ConsumingOpInterface]>;

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

   The other five follow the same pattern, each binding `$cause` in its
   format as `nonzero`'s does:

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

   `nonzero` and `nonempty` also have `Idr_Consumes<"0">` (C2.1). The
   trait behind it offers a `getEffects` (C1.4), as `Idr_MayCrash`'s
   does, and two bases' `getEffects` are ambiguous. So `Idr_CheckOp`'s
   `extraClassDeclaration` names the one a guard has, its crash's:

   ```tablegen
   let extraClassDeclaration = [{
     using ::idr::MayCrash<false>::Impl<ConcreteOpType>::getEffects;
   }];
   ```

   It is on all six, and changes nothing for the four that do not
   consume. A guard's effects are its crash's alone, as C2.1's row says.

3. **The total ops.** `Idr_MayCrash` is removed from these ops (from
   the IO, buffer and array classes, the crash interface they declared,
   `DeclareOpInterfaceMethods<Idr_MayCrashOpInterface>`):

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

   - **Pure:** `idr.div`, `idr.mod`, `idr.to_byte`, `idr.to_int`,
     `idr.str.index` and `idr.str.head` become `NoMemoryEffect` with
     `DeclareOpInterfaceMethods<ConditionallySpeculatable>`. Their
     speculatability is C3.3's rule. These six are the only total ops
     with a `getSpeculatability`.
   - **Allocating:** `idr.str.tail`, `idr.big.div`, `idr.big.mod` and
     `idr.big.from_double` keep `MemAlloc` on their result, as
     `Idr_MayCrash<1>` gave it. They declare no speculatability: an op
     that allocates was never speculatable, and is not now.
   - **IO, buffer and array:** `idr.io.write_bytes`, `idr.io.read_bytes`,
     the five `buffer_*` ops, `idr.array.get` and `idr.array.set` keep
     their IO and array effects, reported by their own `getEffects`
     without the crash. They declare no speculatability.

   The array ops' crash interface was declared on their class,
   `Idr_ArrayOp`, so `idr.array.new`, `idr.array.generate` and
   `idr.array.fold` lose it with `get` and `set`. That changes nothing.
   At the launch base none of the three had `Idr_MayCrash` or a crash
   cause: each `getCrashCause` returned nothing (`IDR/Dialect/Ops/Arrays.cc:54`,
   `:157-158`, at ccc3e1dc), since a negative size is an empty array,
   clamped where the array is made; the lowering checks an index only for
   `get` and `set` (`IDR/Lower/Arrays.cppm:155`); and the interface's one
   generic reader (`IDR/Facts/Infer.cppm:51`) asks for the cause, which
   was always absent.

   `UnitProp:$in_bounds` goes from `idr.array.get` and `idr.array.set`,
   with its `in_bounds` assembly keyword. `Idr_CrashOp` and
   `Idr_CrashStrOp` keep `Idr_MayCrash`.

4. **Regions** (C4). These ops are added under "Closures":

   ```tablegen
   def Idr_LambdaOp : Idr_Op<"lambda", [SingleBlock, Pure,
       AutomaticAllocationScope]> {
     let summary = "a closure whose body is its region; its captures are the values it uses from above";
     let results = (outs Idr_FnType:$result);
     let regions = (region SizedRegion<1>:$body);
     let assemblyFormat = "attr-dict `:` qualified(type($result)) $body";
     let hasVerifier = 1;
   }

   def Idr_DelayOp : Idr_Op<"delay", [SingleBlock, Pure]> {
     let summary = "a suspension whose body is its region; its captures are the values it uses from above";
     let results = (outs Idr_LazyValue:$result);
     let regions = (region SizedRegion<1>:$body);
     let assemblyFormat = "attr-dict `:` type($result) $body";
     let hasVerifier = 1;
   }
   ```

   Both are `Pure`, as `idr.closure` and `idr.suspend` are: building a
   closure runs nothing, so the body's effects are not the op's. The
   lambda's block takes the parameters of its `!idr.fn` type. The
   delay's block takes none. Each region ends in `idr.yield` of the
   result. `Idr_YieldOp`'s `ParentOneOf` gains `"LambdaOp"` and
   `"DelayOp"`, and its `RegionBranchTerminatorOpInterface` methods
   declare `getSuccessorRegions` beside `getMutableSuccessorOperands`, so
   that a yield in a lambda or a delay does not ask its parent as a
   region branch (C4.3):

   ```tablegen
   DeclareOpInterfaceMethods<RegionBranchTerminatorOpInterface,
       ["getMutableSuccessorOperands", "getSuccessorRegions"]>
   ```

5. **Memo sums** (C5):

   - `Idr_DataOp` gains `UnitAttr:$memo` and
     `OptionalAttr<FlatSymbolRefArrayAttr>:$labels`, and its format binds
     both after `closures` (strict formats, C1):

     ```tablegen
     let assemblyFormat = [{
       $sym_name (`box` $box^)? (`closures` $closures^)? (`memo` $memo^)?
       (`labels` $labels^)? attr-dict-with-keyword $body
     }];
     ```

   - On a memo sum `labels` lists the label functions, so that every
     interprocedural analysis between `idr-defunctionalize` and
     `idr-lower` sees each one as address-taken and keeps its body live.
     The attribute is on the module-level `idr.data`, whose attributes'
     symbol references resolve in the module. A reference inside the
     constructor would resolve in the data op's own table (review R12).
   - `Idr_CtorOp` gains `UnitAttr:$by_name`, bound after the field types:

     ```tablegen
     let assemblyFormat = [{
       $sym_name custom<FieldTypes>($field_types) (`by_name` $by_name^)? attr-dict
     }];
     ```

   - `idr.data` and `idr.ctor` are `Idr_PublicSymbol` (20fcfadb): a memo
     sum is public, as every declaration is, and no pass sets its
     visibility (a request to hide one is a fatal internal error).
   - `Idr_ForceOp`'s operand becomes
     `AnyTypeOf<[Idr_LazyValue, Idr_BoxValue]>:$suspension`. It gets no
     consumption trait (C2.1), and keeps its own `getEffects`.

6. **Flat constants** (C7). ODS generates `Idr_ConAttr`'s storage, as
   it does every other attribute's, from these parameters (C7.1):

   ```tablegen
   (ins "::mlir::SymbolRefAttr":$ctor, ArrayRefParameter<"::mlir::ArrayAttr">:$cells,
        OptionalParameter<"::mlir::Attribute">:$tail, "unsigned":$spine)
   ```

   `Idr_Attr` appends the self type, `AttributeSelfTypeParameter<"">:$type`,
   which is `NoneType` as for every `idr` constant. The storage is
   complete in `IDR/Dialect/Dialect/Initialize.cc`, which includes
   `IdrAttrs.cc.inc` and registers the attributes, so nothing is written
   by hand for it, and `Idr.h` declares no storage. The attribute keeps
   `hasCustomAssemblyFormat = 1`, `genVerifyDecl = 1` and
   `skipDefaultBuilders = 1`, and gets C7.2's builders and accessors:

   - ODS generates `getCtor()`, `getCells()`, `getTail()`, `getSpine()`
     and `getType()`, and the storage, whose key gives the generated
     `walkImmediateSubElements` and `replaceImmediateSubElements` over
     the parameters (MLIR's defaults for an ODS storage, C7.2);
   - `get(ctx, ctor, fields)` is the one `AttrBuilder`, declared without
     a body, and keeps its signature. ODS declares its `getChecked` twin
     beside it (`genVerifyDecl`);
   - `getRun`, `getField` and `getFields` are declared in
     `extraClassDeclaration` (ODS names every `AttrBuilder` `get`);
   - `isRun()`, `getRunLength()` and `getRunCells()` are defined there,
     inline, over the generated accessors: `getRunCells()` is a thin
     alias of `getCells()` for a run, and empty for a plain con.

   U19 defines the rest in `IDR/Dialect/Attrs/ConAttr.cc`: `get`,
   `getChecked`, `getRun`, `getField`, `getFields`, `parse`, `print` and
   `verify`. The two builders reach the storage through `Base::get` on
   canonical parameters.

7. **Primitives** (C8). A marker trait is added:

   ```tablegen
   // An op Idris names as a primitive: idris-mlir-tblgen generates its
   // constructor of `IdrPrim` (or `IdrRegionPrim`) for the Idris side.
   def Idr_Primitive : NativeOpTrait<"Primitive"> { let cppNamespace = "::idr"; }
   ```

   It goes on exactly the ops C8.1 lists. Its C++ trait,
   `idr::Primitive`, is a marker with no member, declared in `Idr.h`
   beside `idr::PerformsIO` (C1.4).

8. **Base's surface** (C9). A new file, `INC/IdrPlatformOps.td`, holds
   the ops of C9.2 and C9.3, and `IdrOps.td` includes it at the end. Each
   IO op there is an `Idr_IOOp` with `Idr_Primitive`, and lowers by
   `Idr_CallsRuntime` to `idris_rt_io_<suffix>`, where the suffix is its
   mnemonic after `io.`. Each `idr.handle.*` op is an `Idr_Op` with
   `Idr_CallsRuntime`, `Idr_Primitive` and the effects C9.3 gives it.

### C1.2 `INC/Passes.td`

- `IdrLower` loses its `jit` option.
- `IdrDeadValues` is removed, and `IdrSimplify`'s description names
  `remove-dead-values` where it names `idr-dead-values` (C11.2). These
  lines go in with U01's held-out group at integration step 5, not at
  dispatch: `IDR/Simplify/DeadValues/Pass.cc` defines the pass until then
  (C13). If U01's fix is ours (C11.2), they go in at step 3.
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

// The trait behind Idr_Primitive (C1.1 item 7): a marker with no member,
// which idris-mlir-tblgen reads from the records, written as PerformsIO is.
template <typename ConcreteType>
class Primitive : public mlir::OpTrait::TraitBase<ConcreteType, Primitive> {
private:
  Primitive() = default;
  friend ConcreteType;
  template <typename, template <typename> class...> friend class mlir::Op;
};
```

`ConsumesOperands` names `consumedEffects` before its declaration. The
coordinator orders the declarations so that it compiles. `Idr.h` declares
no storage class: `#idr.con`'s is generated (C1.1 item 6).

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

- The C clients of the header under `T/toolchain` follow both changes
  (U23): `runtime-api/rc.c` names `IDRIS_RT_KIND_THUNK`, and
  `runtime-start/start.c` and `page-size-mismatch/start.c` call the
  four-argument `idris_rt_start` (review R12).

- `idris_rt_start` becomes:

  ```c
  int idris_rt_start(int64_t (*body)(void), uint64_t cpu_features, int argc, char **argv);
  ```

  The runtime keeps `argc` and `argv` for `idr.io.arg_count` and
  `idr.io.arg`. `idris_rt_main_return` calls `rt::io::releaseHandles()`
  (C9.1) before it writes the live-cell count, so the strings the runtime
  holds for environment and directory handles are not counted as live.
  The comment on `idris_rt_main_return` says so.

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
  `!idr.str` is `const idris_rt_str *`, as for the header's existing
  string functions (`idris_rt_io_put_str`, `idris_rt_io_get_line`): a
  string operand is borrowed, and a string result is new. `i64` is
  `int64_t`, and an op whose only result is the world returns `void`.
  `idris_rt_io_exit` is `IDRIS_RT_NORETURN`, as `idris_rt_crash` is.
  U16 defines each function to its declaration as the header gives it.

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

  Already exported, and the one to call for an internal error:
  `llvm::reportFatalInternalError` (20fcfadb). `report_fatal_error` is
  not exported.

### C1.8 Generated and pinned files

- `CS/Dialect/Idr.idr` is regenerated by `tools/dialects.sh generate`
  after `IdrOps.td` and `idris-mlir-tblgen` change.
- `PINS.md` changes:
  - `clang-module-predeclared-new` already retired with the pin
    (20fcfadb); `clang-module-layout-forward-declaration`, the one clang
    entry left, stays as it is (C11.1);
  - `mlir-recursion` and `bytecode-deferred-quadratic` lose their list
    cases;
  - U01's bug gets an entry of its own, in U01's text: no site in our
    code, the workaround
    `upstream/16-remove-dead-values-unchanged-call/llvm.patch`, retired
    when the pin has the fix;
  - `remove-dead-values-unreachable` loses its `idr-dead-values` site
    and the retire clause about it, and `simplify-structural-fixpoint`
    names the new patch where it names `idr-dead-values`.

  If U01's fix is ours (C11.2), there is no new entry, and the two
  entries say that the round runs `remove-dead-values` itself.
- `upstream/06-remove-dead-values-unreachable/README.md` (the last
  paragraph of its `## Patch`) and
  `upstream/02-composite-fixed-point-sccp/README.md` (its
  `## Our workaround`) stop naming `idr-dead-values`, in U01's sentences. Both
  are pending LLVM submissions that another agent sends. The coordinator
  applies the sentences at integration, changes nothing else there, and
  tells the owner, together with the new `upstream/16-…` for
  `upstream/README.md`'s status table, which that agent keeps.
- U01's group, its `PINS.md` text, C1.2's `idr-dead-values` lines and
  the sentences of 02's and 06's READMEs go in one commit: AGENTS.md
  puts a patch's directory, its check, its `PINS.md` entry and the
  deletion of the workaround it replaces in the same change (README,
  Commit policy).
- `T/spec/file-size/allowed` follows the split units.

## C2. Ownership is declared where ops are defined (U03)

### C2.1 Consumption

Idris-mlir declares consumption once per op, in ODS. Two readers derive
from that one declaration:

- **`idr-rc`** asks `idr::consumes(operand)`, which says where a
  position takes over a reference, whatever the grade.
- **Every MLIR pass** sees `MemoryEffects::Free` on `ReferenceResource`.
  This applies only where the op has no other effect, and only where the
  operand's grade is `own` or `excl`, so only after `idr-rc`. An op that
  already reports effects is impure anyway, so it needs only the
  interface (review R2).

Before `idr-rc`, every op reports the effects it reports today. After
it, an op whose only effect is consumption is no longer dead to
`remove-dead-values`.

| Op | Groups taken over | Trait | Its effects |
|---|---|---|---|
| `idr.closure`, `idr.suspend` | `0` (captures) | `Idr_ConsumesOnly<"0">` | the trait's: `Free` on owned operands |
| `idr.yield` | `0` (results) | `Idr_ConsumesOnly<"0">` | the trait's |
| `idr.share`, `idr.nat.to_big` | `0` | `Idr_ConsumesOnly<"0">` | the trait's |
| `idr.con` | `0` (fields) | `Idr_Consumes<"0">` | its own `getEffects` and `getSpeculatability` in `IDR/Dialect/Ops/Con.cc` (U03), which also call `consumedEffects` |
| `idr.apply` | `1` (args) | `Idr_Consumes<"1">` | unknown, as today |
| `idr.lin.enter`, `idr.lin.use` | `0` | `Idr_Consumes<"0">` | today's ODS effects, unchanged |
| `idr.dest.write` | the value's group | `Idr_Consumes<...>` | today's ODS effects, unchanged |
| `idr.take`, `idr.reuse`, `idr.drop` | every group | `Idr_Consumes<...>` | today's ODS effects, unchanged |
| `idr.array.new` (fill), `idr.array.set` (value), `idr.array.generate` (fill), `idr.array.fold` (init) | that group | `Idr_Consumes<...>` | their own `getEffects` in `IDR/Dialect/Ops/Arrays.cc` (U04): today's, `set`'s without its crash (C1.1 item 3) |
| `idr.check.nonzero`, `idr.check.nonempty` | `0` | `Idr_Consumes<"0">` | the guard's crash effect. The guard takes the operand's reference, and its result holds it (review R5). `SameOperandsAndResultType` makes the result's type the operand's, so `idr-rc` grades the result exactly as it graded the operand (U03). |

The coordinator fills in the exact group index of each `...` when it
applies the table to `IdrOps.td`.

Only two kinds of row report the `Free`: `Idr_ConsumesOnly`'s, through
the trait, and `idr.con`'s, through `Con.cc`. Every other `Idr_Consumes`
row gets the trait and the interface and nothing else: its op already
reports effects, so it is impure anyway and no pass drops it as dead
(review R2). No `getEffects` but `Con.cc`'s calls `consumedEffects`:

- the effects of `idr.lin.enter`, `idr.lin.use`, `idr.dest.write`,
  `idr.take`, `idr.reuse` and `idr.drop` are ODS's, generated from their
  `Res<..., [MemAlloc<...>]>` and `Arg<..., [MemWrite]>` declarations.
  `IDR/Dialect/Ops/Lin.cc`, `Dest.cc` and `IDR/Ownership/Ops.cc` have
  no `getEffects` to extend;
- the array ops' `getEffects` stay their own, in `Arrays.cc`;
- `idr.apply`'s effects stay unknown.

**`idr.force` is not in the table.** Whether a force takes its cell over
is placement, as for a match's scrutinee (which `idr-rc` turns into an
`idr.take` where it dies), not a fact of the op:

- `consumes` is false for it;
- `idr-rc` makes a force that is its operand's last use an owned use
  (C5.4);
- `ForceOp::getEffects` (`IDR/Dialect/Ops/Lazy.cc`, U09) reports `Free`
  when its operand is owned.

**`useOf`.** `IDR/Ownership/UseOf.cppm`'s `useOf(operand, symbols)`
becomes `consumes(operand) ? Use::Consume : Use::Borrow`, with today's
call rule inside `consumes`. The `isa` list is deleted.

### C2.2 The owned stage is derived from the types, not stored (O6)

Views stay plain `T`, as today. A `borrow` grade on views would have to
change every op that reads a view, and each declares a plain operand
constraint (review R1):

- 31 operand declarations;
- `memref.dim`;
- the verifiers in `Con.cc`, `Field.cc` and `Matches.cc`.

That sweep is O6's alternative, not this cutover.

What goes is the attribute. The owned stage becomes a fact the types
already hold:

- **The predicate.** `bool ownership::inOwnedStage(ModuleOp)` is true
  when any value in the module (operand, result or block argument) has
  permission `own` or `excl`. It walks the module once. A caller that
  would ask per op asks once per pass and passes the answer down.
- **`idr-rc`** grades as it goes, so it hands its own stage to
  `Counting` and `isBorrowed` explicitly instead of asking the module.
- **The readers:**
  - the owned-stage verifier (`IDR/Ownership/Verify.cppm`) asks once
    per module verification;
  - `IDR/Ownership/OpChecks.cppm` needs no module query: a `dup`'s
    result and a `drop`'s operand are owned by their ODS types, which
    already witnesses the stage;
  - `IDR/Ownership/Borrowed.cppm` is passed the stage by its caller;
  - `IDR/Narrow/Words.cppm` (U21) asks once per pass.
- **A module with no `own` or `excl` value** has no counted reference
  to misjudge: every counted value in it is static, or never counted.

These are deleted:

- `idr.stage`;
- `IDR/Ownership/Stage.cppm`;
- the `idr.stage` entries in `IDR/Dialect/Verify/Attributes.cc` and
  `INC/IdrOps.td`.

`idr::view` is unchanged.

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

An IR operand a terminator needs where control never arrives (a yield
after a crash that does not return) is a value of the program too: the
op requires one, and no C++ tests it. A "placeholder" above is C++'s,
a value standing for "not computed yet".

Each lane applies this rule to the sites in its own files. A row counts
the sites to examine under it, not sentinels to delete: a site that
reads or builds the program's poison stays, with a comment where the
reason is not plain (README S5). The sites at ee4ce8e, the same at
1677b8cb and at ccc3e1dc:

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

The sentinel in `IDR/Specialize/ShapeOf.cppm` goes without changing what
Specialize decides: U21 keeps `CloneTable::settleBreaker` and the
binding-time join for raised clones (ccc3e1dc: a clone of a loop breaker
is a breaker, so `idr-simplify` ends), which
`T/idr/specialize/breaker-clones` and `T/programs/eval/latent-loop`,
`latent-loop-delay` and `latent-loop-accumulator` pin.

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
| `idr.array.get`, `idr.array.set` | `check.in_bounds` on the index, with the `arith.index_cast` of `memref.dim` of the array as the length | the `outOfBounds` text of `IDR/Dialect/Ops/Arrays.cc` |
| `idr.io.read_bytes`, `idr.io.write_bytes`, `buffer_get_string` | `check.range` on the offset, with the count (`$count`, `$len`) and `memref.dim` of the buffer | `a byte range outside the buffer` |
| `buffer_load`, `buffer_store` | `check.range` on the offset, with the word's byte size (a constant of the op's value type: 1, 2, 4 or 8) as the count | `a byte range outside the buffer` |
| `buffer_set_string` | `check.range` on the offset, with `idr.str.bytes_length` of the string as the count | `a byte range outside the buffer` |
| `buffer_copy` | two `check.range`s: `$src_offset` with `$len` in `$src`, and `$dst_offset` with `$len` in `$dst` | `a byte range outside the buffer` |

A total op has no `getCrashCause`. The runtime functions they call keep
assuming their preconditions, as they do today
(`IDR/Lower/RuntimeCalls.cppm`: "checked before the call, whose runtime
function assumes it does not"). The one exception at the launch base is
`idris_rt_buffer_at` (`RT/Io/Buffer.cppm`), which tests the byte range
itself for `buffer_copy`, `buffer_set_string`, `buffer_get_string`,
`read_bytes` and `write_bytes`. It computes only the address after the
cutover: `check.range` is the one test (U16). A guard crashes at its
own location, so a range crash now ends `at <file>:<line>:<column>`
after the unchanged cause, as every other guard's does (U05).

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

The rule is for the six pure total ops of C1.1 item 3: `idr.div`,
`idr.mod`, `idr.to_byte`, `idr.to_int`, `idr.str.index` and
`idr.str.head`, the only ones that declare `ConditionallySpeculatable`.
The allocating, IO, buffer and array total ops declare no
speculatability, so they are never speculatable, as they were not
before.

One of the six is speculatable only while each operand it guards is one
of:

- the result of a guard whose length operand is the length of the op's
  own string (review R6): for `idr.str.index`, the one whose guard takes
  a length, that length is `idr.str.length` of the op's string operand.
  For `nonzero`, `nonempty`, `byte` and `finite`, which take no length,
  it is the guard of that operand;
- a constant for which the guard's condition holds.

Otherwise it is `NotSpeculatable`. So when a guard is removed because a
path condition proves it, the op stays below that condition. When the
guard is present, the data dependence keeps the op below it.

The rule is written once, in `IDR/Dialect/Ops/Check.cc`, as
`idr::checkSpeculatability(Operation *, ArrayRef<unsigned> guardedOperands)`,
and the `getSpeculatability` of each of the six calls it (U04).

### C3.4 Folding

**A guard's folder** returns its operand exactly when one of these
holds (review R4):

- `nonzero`: `idr::knownNonZero` holds of the operand, as
  `IDR/Dialect/Crashes/KnownNonZero.cc` says today;
- `finite`: `idr::knownFinite` holds;
- `nonempty`: `idr::knownNonEmpty` holds. That includes a string built
  with a character or a number in it, such as `str.cons`;
- `in_bounds`, `byte` and `range`: the condition holds of constant
  operands;
- the operand is the result of an identical guard (same kind, same
  operands).

**A guard does not fold** in any other case. A failing constant guard
keeps its crash. **No folder reads an analysis:** proofs by range and
dominance are `idr-in-bounds`'s (C3.5).

**`IDR/Dialect/Crashes` stays.** Its three predicates are the guards'
folders now, not crash causes.

**The rewrites that matched a partial op's operand** look through a
`nonempty` guard:

- the `HeadOfCons` and `HeadOfShow*` patterns of
  `IDR/Dialect/Canonicalize.td`, with their `HeadOfChecked*` twins
  registered in `IDR/Dialect/Canonicalize/Strings.cc` (both the
  coordinator's, README S7);
- `IDR/Canon/Feeds.cppm`'s consumer test (U04): its string-builder case
  (`Feeds.cppm:137-138`) sees the guard and the `str.head` behind it.
  The two rules 1677b8cb added stay. A force meets a suspension nothing
  else uses (`:141-142`; the symbol form, C4.4), kept to `!idr.lazy`
  operands now that `idr.force` also takes a memo box (C1.1 item 5),
  whose force reads its cell and meets nothing. A box constructor is
  never folded with constants into static data (`:149-150`).

**One predicate per kind for constants.** It is
`idr::checkHolds(CheckKind, ArrayRef<Attribute>)` in `Check.cc`. The
guard's folder and every total op's folder call it, including
`foldDivision` in `IDR/Dialect/Ops/Generated.cc`, the total `div` and
`mod` folder (U04, review R12). `IDR/Canon/MatchPatterns.cppm` keeps
calling `knownNonEmpty`, which stays. A total op does not
fold when the predicate fails on its constants: the folder would compute
what the program never reaches, and APInt division by zero aborts the
compiler.

### C3.5 Proving guards: `idr-in-bounds` (U06)

`idr-in-bounds` keeps its index systems. Instead of setting
`in_bounds`, it erases each `idr.check.in_bounds` it proves, replacing
the guard's result with its operand.

It also erases any guard that:

- a dominating guard of the same kind and operands already checks;
- `IntegerRangeAnalysis` proves at its point.

`idr-expect`'s `in-bounds=@f` property becomes "no `idr.check.in_bounds`
is left in `@f`, and `@f` has an array access (`idr.array.get` or
`idr.array.set`)" (`IDR/Expect/InBounds.cppm`): the second half is
today's, and keeps a test from passing because its access was
simplified away. There is a new property, `no-guards=@f`: no
`idr.check.*` op is left in `@f`.

The `ub.poison` reads of C2.4's `IDR/InBounds` rows
(`Returned.cppm`, `Components.cppm`, `Lengths.cppm`) read the program's
poison (a value no run reads, which constrains nothing), so they stay.

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
- `Emit/Attributes.idr`'s `lifted` and `inherited` go too (review R12):
  `idr-isolate` gives an outlined function its attributes (C4.3 step 4).
  `own` keeps its meaning, with `inherited`'s one line inlined.
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
   lambda's parameters. Its results are the `!idr.fn` type's results (the
   lazy type's value for a delay), so a body that ends in
   `ub.unreachable` has them too.
3. **Move the body.** Move the body in. The captures are appended to the
   block's arguments, so permute them to the front. The region's own
   terminator, when it is an `idr.yield`, becomes `func.return`; the
   `idr.yield`s of matches nested in the body stay.
4. **Copy the attributes.** The new function gets `idr.break_last` when
   the enclosing function has it, and `idr.total` always: that is what
   `Emit` gives a lifted function today (`Emit/Attributes.idr`
   `inherited` and `lifted`). Its location is
   `NameLoc(<the enclosing function's NameLoc name>, <the region op's location>)`,
   as `Emit/Bodies.idr:181-182` gives a lifted function today:
   `idr-expect` finds a function's lifted code by that name
   (`IDR/Expect/Named.cppm`).
5. **Replace.** Replace the op with `idr.closure @name(captures)` or
   `idr.suspend @name(captures)`.

After the pass, no `idr.lambda` or `idr.delay` is left. The verifier of
each op (U08, `IDR/Dialect/Ops/Regions.cc`) checks:

- the block's arguments are the `!idr.fn` inputs, or none for a delay;
- every `idr.yield` matches the result type;
- for `idr.delay`, no value of world type is used from above, as
  `SuspendOp::verify` checks for captures today.

**The yield that ends a lambda or a delay.** `idr.yield` is a
`RegionBranchTerminatorOpInterface` for its other parents, a match and
an array loop, which are region branches. A lambda and a delay are not:
the body runs when the closure is applied or the suspension forced, not
when the op runs. The interface's default `getSuccessorRegions` casts
the yield's parent to `RegionBranchOpInterface`, which would fail for
them. Decided: the yield declares `getSuccessorRegions` (C1.1 item 4),
and U08 defines it in `IDR/Dialect/Ops/Regions.cc`:

- when the parent is an `idr.lambda` or an `idr.delay`, it gives no
  successor;
- otherwise it gives what the parent's `getSuccessorRegions` gives for
  the yield, as the default did.

The region ops' verifiers and `idr-isolate` read the body's terminator
directly, as an `idr.yield` or a `ub.unreachable`. They never ask a
lambda or a delay, or its yield, as a region branch.
`YieldOp::getMutableSuccessorOperands` stays in `Arrays.cc` (U04),
unchanged: with no successor, nothing asks it for a lambda's or a
delay's yield.

### C4.4 What phase 1 does not do

The simplify loop still sees the symbol form, so these stay:

- `ForceOfOneUse`, `ForceOfOneConstant`, `ForceInOneCase` and
  `ForceAtCapture`;
- `IDR/Canon/Feeds.cppm`'s rule that a force meets a suspension nothing
  else uses, built by `idr.suspend` or a `#idr.closure` constant, as an
  apply meets a closure (1677b8cb), kept to `!idr.lazy` operands (C3.4).
  An `if` passes its branches as
  suspensions, and with the force moved into the match each region
  calls its branch (`T/idr/canon/force-of-choice`,
  `T/programs/eval/lazy-branch-loop`). `idr-isolate` runs first, so a
  delay is an `idr.suspend` when `canonicalize` meets it;
- closure specialization for captured constants. Isolation already
  clones constants into the body, so most of its cases are gone before
  it runs.

The two region rules of `substrate.md` S1.1 are phase 2, which needs
regions to survive the simplify loop. This cutover does not do it.

## C5. Thunks are memo sums (U09, U10, U11, U12, U14, U15)

### C5.1 Defunctionalization makes them

`idr-defunctionalize` follows `!idr.lazy<T>` keys exactly as it follows
`!idr.fn` keys. `Slots.cppm` already follows `SuspendOp` and `ForceOp`.

**Arrays.** Slots also follows values through arrays, for both key
kinds, so that `IOArray (Lazy Int)`, which compiles today, keeps
compiling (review R7). There is one anchor per array element type, as
there is one per constructor field:

- written by `idr.array.new`'s fill, `idr.array.set`'s value and
  `idr.array.generate`'s yield;
- read by `idr.array.get`'s result and `idr.array.fold`'s element block
  argument.

**The memo sum.** Each lazy key with a known label set becomes one. An
empty set, a key the analysis never reaches, becomes a memo sum with no
label, only `@running` and `@forced`, so that no `!idr.lazy` is left:

```mlir
idr.data @lazy$<n> box memo labels [@<label fn>, ...] {
  idr.ctor @<label function>(captures...)  // one per label, named after it
  ...
  idr.ctor @running()
  idr.ctor @forced(T)
}
```

The rest of the conversion:

- **Always `box`.** A memo cell has an identity: two references see one
  memo.
- **`labels`** lists the label functions, so that interprocedural
  analyses keep their bodies live (C1.1 item 5). The verifier checks
  that it names exactly the label constructors.
- **Suspensions.** `idr.suspend @f(caps)` becomes
  `idr.con @lazy$n::@f(caps)`.
- **Constants.** A `#idr.closure<@f, [caps]>` constant at a lazy type
  becomes `#idr.con<@lazy$n::@f, [caps]>`.
- **Types.** `!idr.lazy<T>` becomes `!idr.box<@lazy$n>`. `idr.force`
  keeps its op and now takes the box.
- **Coercions** between keys are built as they are for closures, by
  rebuilding the label constructor in the other sum.
- **`AdaptLazy.cc` goes.** Its job, a lazy type that names a closure
  type, is now part of the key.
- **Numbering.** The sums are numbered by first appearance, as closure
  sums are.

**`by_name`** (O3, review R8). A label constructor is `by_name` when its
function reaches, through direct calls after conversion, an op with
`Idr_PerformsIO` other than an array or buffer op. That is an
observable effect: output, input, a file, a clock. `trace`'s forged
world reaches `put_str`, so it is `by_name`. `Linear.Array`, `runST`
and `strerror` forge worlds but reach only array and buffer ops,
`idr.world.new` (forging a world is no effect) or `idr.io.strerror`
(which reads the runtime's text of an errno and nothing else), so they
keep their memo.

Two more rules go with it:

- **A label that a static constant names is never `by_name`** (O3). A
  top-level constant names one value of the program, evaluated once, as
  Idris defines a top-level definition. A `trace` in it observes that one
  evaluation, so its cell memoizes: written once, by its first force, and
  read by every later force (C5.5).
- **`ForceOp::getEffects` reports `MemWrite` on `Idr_IOResource`** when
  its operand's sum has a `by_name` constructor, so a force that may run
  output stays in order with output.

U09 computes `by_name` with a walk over the label's call graph, with a
visited set.

**Unknown keys** (review R7). After `idr-defunctionalize` no `!idr.lazy`
type, no `idr.suspend` and no closure is left in a program.
`idr::defunctionalize::defunctionalize(ModuleOp)` returns, besides its
counts, the keys it could not convert (closures and suspensions):

- The pass (`IDR/Defunctionalize/Pass.cc`) reports each one as
  `unsupported (laziness)` or `unsupported (runtime closure)`, naming
  the op the value flows through where the analysis lost it.
- `idr-eval` calls the function, not the pass, on its scratch module
  (C6.4). If any key is left, every call of the round stays for runtime.

`checkNoClosures` (U13) keeps its internal error as the backstop. It
covers lazy values too.

**The verifiers.** `idr::isMemo(DataOp)` returns whether the `memo`
attribute is set. `DataOp`'s verifier checks:

- a memo sum is `box`;
- it has exactly one `@running()`, with no fields;
- it has exactly one `@forced(T)`, with one field;
- `labels` matches its label constructors.

`ForceOp`'s verifier accepts:

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
  - the label table and `numLabels`, with `IDR/Layout/FindLabels.cc`,
    the walk that builds it (1677b8cb moved it out of `Layouts.cppm`);
  - `codeName` and `lazyDoneName`;
  - every closure-only path of `PlaceClosures.cc`.

  No cell holds a code address any more.

### C5.3 What a force does (U11, `IDR/Lower/Closures.cppm`)

`idr.force %t` with `%t : !idr.box<@lazy$n>` lowers by one generic
pattern, the same for every memo sum. Its result is owned, as today. It
goes by the cell's tag.

**When `%t` is a view** (a plain `!idr.box`, C2.2), the memo protocol:

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
function borrow a parameter: its type is then plain, a view. Where
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
`idr.take`. Otherwise the operand is a view. `idr.force` is not in the
C2.1 table: `consumes` is false for it, and this rule is the one place
that makes it an owned use.

**Static memo cells are never `excl`.** The force trusts its grade, as
`LowerTake` does, and the one-shot protocol frees the cell and moves
the value out. A memo-sum constant is static data written by its first
force, never an atom: `IDR/Ownership/ReachesOnlyAtoms.cppm`'s
`onlyAtoms` counts a field-free box constructor as an atom only when
its declaration is not a memo sum, so a dup of a capture-free static
memo cell is a view, never `excl` (U03).

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
- **Defunctionalization first.** `IDR/Eval/Round.cppm` calls
  `idr::defunctionalize::defunctionalize(scratch)`, the function, not
  the pass. If it leaves any key, closure or suspension, every call of
  the round stays for runtime with `Unread::Why::Unreadable` and the
  reason "a closure the analysis cannot follow" (review R7). Nothing is
  evaluated unsoundly, and nothing is reported as an error.
- **The pipeline.** Otherwise it runs the rest of the C1.3 evaluation
  pipeline: `idr-lower`, `idr-meter`, then today's steps.
- **No code table.** `codesName` and the label loop go.
- **Reify.** It reads closure and memo sums per C5.7, and builds list
  spines with `ConAttr::getRun` (C7.2), never by nesting `get`.

### C6.5 The runtime (U15)

- **Crashes.** `idris_rt_crash` checks whether the process is an
  evaluation child; `rt::alloc::arenaActive` says so. If it is, it does
  what `idris_rt_eval_crash` does. `idris_rt_crash` and
  `idris_rt_main_return` are defined in `RT/Io/Ending.cppm`, which is
  U16's, so U16 writes both changes there: `idris_rt_crash` calls
  `idris_rt_eval_crash(msg, len)` first when `rt::alloc::arenaActive`
  (`rt.io` cannot import `rt.eval`, which imports it, so the call goes
  through the C entry), and `idris_rt_main_return` no longer declares or
  calls `idris_rt_release_persistent`, which U15 deleted with the kept
  list. `idris_rt_crash_str` is unchanged.
- **Arguments.** `idris_rt_start` stores `argc` and `argv` where
  `rt.start` exports them, as `rt::start::argumentCount()` and
  `rt::start::argument(int64_t)`. They are read by U16's
  `idr.io.arg_count` and `idr.io.arg`.

## C7. Constants are flat (U19, and every walker's lane)

### C7.1 The representation

A `#idr.con` is stored in one of two ways:

- **plain:** the constructor and its fields;
- **run:** `n >= 2` cells of one constructor `C`, linked through one
  field index `s` (the spine), ending in a tail.

ODS generates the storage (C1.1 item 6), and both forms store the same
parameters: the constructor, the cells (one `ArrayAttr` each), the tail
and the spine.

- **Plain:** one cell, holding all the fields; a null tail; spine 0.
- **Run:** the `n` cells, each holding its fields without the spine
  field; the tail; `s`.

**The canonical form** (review R3). One value has exactly one attribute,
so equality and uniquing still mean value equality:

1. A run has at least two cells, and a tail. Every cell has the
   constructor `C` and the spine `s`. A plain con has one cell, no tail
   and spine 0, so that the storage of one plain value is one storage.
2. `ConAttr::get(ctor, fields)` builds a run exactly when one field `i`
   is a `#idr.con` of `ctor`, and that field is either:
   - a run with spine `i`, which this cell is prepended to; or
   - a plain con of `ctor` none of whose fields is a con of `ctor`,
     which becomes the second cell, its field `i` the tail.

   Otherwise `get` builds a plain con. A cell whose same-constructor
   field is a run of another spine is plain (a zig-zag tree), and so is
   a tree cell with two such fields.
3. `ConAttr::getRun(ctor, spine, cells, tail)` gives what repeated `get`
   would give:
   - with one cell, it builds the plain con;
   - a tail that is a run of the same constructor and spine is merged;
   - a tail that is a plain con of `ctor` with no same-constructor field
     becomes the last cell.
4. The default ODS builder is skipped (`skipDefaultBuilders = 1`), and
   the verifier rejects a non-canonical run, and a plain con with a
   spine other than 0 or more than one cell.

### C7.2 The API (U19, `IDR/Dialect/Attrs/ConAttr.cc`)

```cpp
// U19 defines these, in ConAttr.cc.
static ConAttr get(MLIRContext *, SymbolRefAttr ctor, ArrayAttr fields);  // canonicalizes, as above
static ConAttr getRun(MLIRContext *, SymbolRefAttr ctor, unsigned spine,
                      ArrayRef<ArrayAttr> cells, Attribute tail);         // O(n)
Attribute getField(unsigned i) const; // O(1) for i != spine; the run from the second cell for i == spine
ArrayAttr getFields() const;          // correct for both forms; O(n) on a run, which builds its suffix

// ODS generates these, from the parameters.
SymbolRefAttr getCtor() const;
ArrayRef<ArrayAttr> getCells() const; // a plain con's one cell, or a run's cells
Attribute getTail() const;            // a run's tail; null for a plain con
unsigned getSpine() const;            // a run's spine index; 0 for a plain con

// The hub defines these inline, over the generated ones.
bool isRun() const;                       // the tail is not null
unsigned getRunLength() const;            // getCells().size(): 1 for a plain con
ArrayRef<ArrayAttr> getRunCells() const;  // a run's cells' non-spine fields; empty for a plain con
```

`getRunCells()` is a thin alias of the generated `getCells()`, not the
generated accessor itself: it keeps its meaning, empty for a plain con,
whose one cell is its fields. Both builders reach the storage through
`Base::get(ctx, ctor, cells, tail, spine, NoneType::get(ctx))` on
canonical parameters. `getChecked`, which ODS declares beside `get`
(`genVerifyDecl`), is `get` with the verifier's diagnostics.

**The walk rule.** A walker that follows a list's spine walks
`getRunCells()` and then `getTail()` in a loop. It never steps by
`getFields()[s]`, which costs O(n) per step on a run: about 5·10^9
pointers for the 10^5-element test. Reading one field of the head uses
`getField(i)`.

A walker that recurses into a constant's fields also reads a shared
sub-attribute once. A constant is a graph, not a tree:
`T/programs/eval/shared-result` computes one of 41 nodes with 2^41
paths, and a walk per path never ends. So 1677b8cb gave
`functionClosure` and Layout's label walk a set of the (attribute, type)
pairs they have read. A walker adapted to runs keeps such a set where it
has one.

**The builders.** A builder that conses cell by cell builds the list
with `getRun` instead:

- `IDR/Eval/Reify.cppm` (U14);
- `IDR/Eval/Encoding.cppm`'s `decodeResults` (U14), which today builds
  every result constant one `ConAttr::get` per cell
  (`Encoding.cppm:134`);
- `IDR/Fold/StringOfList.cc` and `IDR/Fold/Lists.cppm` (U04);
- `IDR/Ops/Untyped.cppm` (U04), which rebuilds a constant.

**The walkers**, each adapted to the walk rule by its lane's owner
(review R3):

| Walker | Lane |
|---|---|
| `IDR/Ops/Constants.cppm` (the constant verifier, after every pass) | U04 |
| `IDR/Lower/Lowering.cppm` `functionClosure` (it keeps its `seen` set) | U13 |
| `IDR/Eval/Encoding.cppm` (encode and decode) | U14 |
| `IDR/Defunctionalize/{Closures,Analysis,Converter,Slots}.cppm` | U09 |
| `IDR/Specialize/{KeyOf,Specialization,ShapeOf,UnrollSize}.cppm` (it keeps `CloneTable::settleBreaker` and the binding-time join for raised clones, ccc3e1dc) | U21 |
| `IDR/Sharing/Aliases.cppm` | U19 |
| `IDR/Ownership/ReachesOnlyAtoms.cppm`, `IDR/Facts/Passed.cppm` | U03 |
| `IDR/Layout/FindLabels.cc` (`noteValue`, moved out of `Layouts.cppm` by 1677b8cb; it goes with the label table, C5.2) | U10 |
| `IDR/Lower/StaticData.cppm` (lowers a run's cells with a loop) | U12 |

**Printing, parsing and walking.**

- The plain form prints as today. A run prints flat:

  ```
  #idr.con<@List::@Cons, run 1 [[e0], [e1], ...] tail #idr.con<@List::@Nil, []>>
  ```

  The parser reads both forms and canonicalizes.

- `walkImmediateSubElements` and `replaceImmediateSubElements` are the
  generated ones over the parameters, MLIR's defaults over the generated
  storage's key (`AttrTypeSubElements.h`). They see the constructor, each
  cell as an `ArrayAttr`, the tail directly, and the self type; a cell's
  fields are its `ArrayAttr`'s. A canonical run holds no run of its own
  constructor and spine, so a run of any length is one level deep to
  MLIR's printer, parser, bytecode and walks.
- A replace rebuilds through `Base::get` on the replaced parameters,
  without canonicalizing (MLIR prefers a `get` of exactly those
  parameters, and `ConAttr` has none). So a replace can produce a
  non-canonical run: for example, the tail replaced by a run of the same
  constructor and spine, which `getRun` would merge, or a cell's field
  replaced by a con of the run's constructor, which makes that cell one
  `get` keeps plain. The verifier rejects it, and `Base::get` asserts the
  verifier where assertions are on, as in the build. A pass that would
  make one rebuilds the constant with `get` or `getRun`.
- U19 checks that the printer, the parser and bytecode round-trip a
  10^4-cell run, as C12's `idr/constants/run` states.

`IDR/Dialect/Dialect/Constants.cc` keeps materializing it, since it is a
`ConAttr`.

### C7.3 What retires

The list cases of `mlir-recursion` and `bytecode-deferred-quadratic`
retire. The reserved compile stack and the reader patch stay for other
deep data. The coordinator edits their PINS entries.

## C8. One primitive set (U17, U18, U07)

### C8.1 Which ops are primitives

`Idr_Primitive` goes on every op that has no inherent attribute and
that the Idris side emits one-to-one for an Idris primitive. The
candidates:

- **Strings:** the `str.*` ops, `str.pack` and `str.concat` among them:
  each is attribute-free, and Emit writes each one-to-one for one Idris
  primitive, the Prelude's `fastPack` and `fastConcat`;
- **Bigs and naturals:** the `big.*` and `nat.*` ops, `nat.to_big` and
  `nat.from_big` among them (`natToInteger`, `integerToNat`);
- **IO:** `put_str`, `put_char`, `put_double`, `get_byte`, `get_line`,
  `write_bytes`, `read_bytes`, `eof` and `n_processors`;
- **Arrays:** `array.new`, `array.get` and `array.set`;
- **Buffers:** the five `buffer_*` ops;
- **The rest of today's set:** `crash_str`, `os`, `world.new`,
  `to_byte`, `to_int`, `double_head` and `io.put_list`. (`to_char`,
  `div`, `mod`, `shl` and `shr` carry the inherent `UnitAttr:$is_signed`,
  as do `int_head`, `str.show`, `str.to_int`, `big.from_int` and
  `put_int`, and `str.cmp` and `big.cmp` carry a predicate: they stay
  `Prim` constructors, `IntOp` and `IntShift` among them.);
- **New:** every op of C9.

`array.generate` and `array.fold` get it too. They are the region
primitives.

These do not get it:

- A candidate with an inherent attribute, such as a comparison predicate
  or a signedness unit: it stays a `Prim` constructor that Emit builds
  with the op's generated builder, as today.
- The six guards: Emit builds them with their generated builders
  (`Idr.checkNonzeroOp` and the rest) from `guardOf` (C8.3).
- `big.small` and `big.pred`, though attribute-free. Each has a
  precondition that no guard checks: `big.small`'s word fits the small
  range, which `idr-narrow` proved where it writes the op, and
  `big.pred`'s natural is not zero, which the match on a natural that
  Emit writes it in found. So no primitive may build either. Emit keeps
  writing `big.pred` in that match with its generated builder
  (`Idr.bigPredOp`, `Emit/Bodies.idr`), as today. The hub as applied
  left the trait off both, and that is accepted.

**One representation.** An op that is an `IdrPrim` constructor is never
also a `Prim` constructor (C8.3): the generated constructor is its one
name on the Idris side.

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

||| Whether the primitive performs IO (Idr_PerformsIO). Such a primitive
||| takes the world as its last operand and gives the next as its last
||| result, except WorldNew, which makes a world: it takes none and gives
||| one.
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

### C8.3 `CS/Types.idr`, `Term.Effect` and the hooks (U17, U07, U18)

**`Prim`** (U17). It keeps only what `IdrPrim` does not cover, the
constructors that are not one attribute-free `idr` op:

- `IntOp`, `IntShift`, `FloatOp`, `Negate`, `Math`, `Compare` and `Cast`
  map to `arith` and `math`, choosing by signedness and width;
- `ArrayLength`, which is `memref.dim` of the array and an
  `arith.index_cast`, no `idr` op;
- every op with an inherent attribute (C8.1).

Every constructor that is exactly one attribute-free `idr` op becomes
`Op IdrPrim`, and leaves `Prim`. U17 lists the mapping in its handoff.
Among them:

- `NatToBig` and `NatFromBig` are `Op NatToBig` and `Op NatFromBig`;
- `StrBuild Pack d` and `StrBuild Concat d` are `Op StrPack` and
  `Op StrConcat`. The `DataId` was the list operand's type, which a pure
  `Op p` takes from the operand itself (U17), and the frontend still
  reads it from the call (`Terms.idr`'s `builderCall`, U07). `Builder`
  (`Pack | Concat`) goes with `StrBuild`: it named the two ops a second
  time.
- `ArrayOp` (`NewArray | GetArray | SetArray`, `Types.idr:431`) goes the
  same way: it names `array.new`, `array.get` and `array.set`, which are
  primitives, a second time. The registry's `ArrayCall` and
  `Hook.ArrayCall` carry the `IdrPrim` (U18); U17 deletes `ArrayOp`, its
  `Show` instance and `Array`'s `ioArgs` case.

**`IOOp` and `ArrayLoop` go** (review R10), and so does the table of
operand types that went with them:

- IO primitives are `IdrPrim`s with `primPerformsIO p`.
- `ArrayLoop` is replaced by `IdrRegionPrim`.

**`Term.Effect`** (U07) becomes
`Effect : Loc -> IdrPrim -> List Ty -> List (Term a) -> DataId -> Term a`.
Its `List Ty` holds the type arguments that today's `IOOp` constructors
carry:

- `Array _ e` gives `[e]`;
- `BufferLoad t` and `BufferStore t` give `[t]`;
- every other one gives `[]`.

The frontend reads them from the call, as it does today
(`Frontend/Translate/Terms.idr` `ioCall` and the array case). They are
not looked up in a table.

**The hooks** (U18): `Hook.IOCall` carries an `IdrPrim`,
`Hook.ArrayLoop` an `IdrRegionPrim`, and `Hook.Builds` the `IdrPrim` of
the string it builds, `StrPack` or `StrConcat` (`Registry/Entry.idr`).
`Frontend/Translate/Hooks.idr` (`ioCallOf`, `arrayLoopOf`, `builderOf`)
joins U18.

**What a call does not supply** (README S11). `Hook.IOCall` carries the
primitive and the literal operands the call does not supply, which go
after its runtime arguments and before the world, which stays an IO
op's last operand: `IOCall IdrPrim (List Lit)`.
`prim__newBuffer` is `IOCall ArrayNew [LInt UInt8 0]`, since a new
buffer is zero bytes; every other entry carries `[]` (U18).
`Frontend/Translate/Terms.idr` (U07) reads them:

- the literals become operands after the call's own;
- an `IOCall` of a primitive without `Idr_PerformsIO` (`HandleIsNull`,
  `HandleString`) has no world and no `IORes`, and is `PrimApp (Op p)`;
- an array primitive's `[e]` is the element of the `ArrayT` among its
  operands or its result, as for `getBits8` and `setBits8`, whose buffer
  is an array of bytes.

**`exitWith` and the identity hooks** (U18's `Hook.Exits`, read by U07).
U07 translates `exitWith`'s body as written, with its one `believe_me`
(`PrimIO ()` to `PrimIO a`) as the action applied to the world followed
by `Unreachable`. `IdentityOnLastArgument` is the definition's last
runtime argument by its type, not its clause's last pattern:
`prim__castPtr` and `prim__forgetPtr` are point-free, binding only the
erased `t`. `Frontend/Profile.idr` (U18) walks only the type of a
definition with either hook, so their `believe_me` is not reached as an
escape hatch, and names `Signal` and `Process` where a trusted reach
meets them.

**Emit.** `Emit/Operations.idr` (U17) exports one function for an
effect:

```idris
effect : Index -> Loc -> IdrPrim -> List Ty -> List Val -> DataId -> E (Maybe Val)
```

It does four things:

- it emits the guard of C3.1 for a partial primitive (`guardOf`);
- it emits the op with `primOp`;
- it threads the world when `primPerformsIO p`: the world is the op's
  last operand and the next its last result, except for `WorldNew`,
  which takes none and gives one (C8.2);
- it builds the `IORes` instance named by the `DataId`.

`Emit/Bodies.idr`'s `EffectF` case (U07) calls it. Pure `Op p`
primitives go through the function Bodies already calls for `PrimAppF`,
which U17 keeps.

`guardOf : Prim -> List (Guard, Nat, String)` lives in
`Emit/Operations.idr` too: a list, since `buffer_copy` takes two range
guards (C3.1). It is the one place the Idris side knows a
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

`PrimIO.Ptr` and `System.Clock.OSClock` (`data OSClock : Type where
[external]`) get `WordType` registry entries beside `AnyPtr`'s. U18
adapts `Frontend/Translate/Types.idr`'s `WordType` handler to an applied
`Ptr t`.

**Who owns a string handle** (review R11):

- **A string read from a file** (`file_read_line`, `file_read_chars`)
  is the program's. Base frees it (`getStringAndFree`), and
  `handle_free` releases it.
- **The current directory's path** (`dir_current`) is the program's
  too. Base's `currentDir` reads it and frees it
  (`free $ prim__forgetPtr res`, `System/Directory.idr:82-89`), and
  `handle_free` releases it.
- **A string from `env_get`, `env_pair` or `dir_entry`** is the
  runtime's, as `getenv`'s and `readdir`'s bytes are in C, and base never
  frees it. The runtime keeps one string slot for the environment
  operations and one per open directory. Each is replaced by the next
  call of its kind and released by `dir_close` and at exit.
  `handle_free` of such a handle does nothing.
- **At exit.** `idris_rt_main_return` releases the whole handle table,
  through `rt::io::releaseHandles()` (U16), before it reports live
  cells. A program that reads its environment still ends with 0 live
  cells.

**`exitWith`.** Base's `exitWith` is `primIO . believe_me . prim__exit . cast`,
and `believe_me` is rejected. So the registry recognizes
`System.exitWith` by name, as `idr.io.exit` followed by
`ub.unreachable`. `idris_rt_io_exit` writes pending output, reports no
live-cell count, and exits with the status.

**Raw pointers.** `prim__castPtr` and `prim__forgetPtr` are identity
hooks. `RawPointer` stays only for `System.FFI`'s allocation primitives
(`prim__malloc` and its kin). The `ruledOut` entries for
`prim__getString`, `prim__nullPtr`, `prim__forgetPtr`,
`prim__nullAnyPtr`, `prim__getNullAnyPtr` and `System.getEnv` go.

### C9.2 The IO primitives

Every op below is `idr.io.<name>`, and its runtime function is
`idris_rt_io_<name>`. `h` is an `i64` handle and `s` is `!idr.str`. A
`Ptr String` result is a string handle, or null. Unless a row says
otherwise, an `Int` result is the C support function's value.

The meaning of each is the runtime's, documented beside its runtime
function (U16). It is written from the C support function its `%foreign`
spec names (`third_party/Idris2/support/c/`) and from POSIX, and C12's
tests state it in committed expected files. A failing call sets the
runtime's saved errno, which `idr.io.errno` and `idr.io.file_errno`
read.

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
| `prim__currentDir` | `dir_current` | `-> h` (a string handle the program owns, or null; C9.1) |
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

**Meanings settled during the swarm** (U16; README S10), where the C
support function, base's documentation and POSIX left a choice:

- `file_read_line`: null when the read fails before any byte, `""` at
  the end of the file, and a line a failure cuts short as it was read.
  Linux's and macOS's C libraries disagree on the first; the runtime
  gives one answer on both.
- `file_read_chars` reads bytes, as `idris2_readChars` does; a UTF-8
  sequence cut at the end becomes U+FFFD, as every string the runtime
  makes from bytes does.
- `exit` with a status outside 0 to 255 ends the program as a main
  return outside that range does: a crash that names the status, never
  the low 8 bits, which would make `ExitFailure 256` a success. U15
  exports the check from `rt.start` and U16's `exit` calls it.
- `file_write_line` writes every byte of its string; a path or an
  environment name handed to the C library ends at an embedded NUL.
- Closing handle 0, 1 or 2 flushes and leaves the stream open, since the
  runtime writes those descriptors itself.
- A failing `fclose` or `closedir` saves errno and frees the handle.
- `dir_entry` saves errno on every call, so it is 0 at the end of the
  directory, which base's `nextDirEntry` reads to tell the end from a
  failure.
- `prim__fPoll` names `idris2_fileSize` in its `%foreign`, as
  `prim__fileSize` does (base's `System/File/Meta.idr:22`), so the
  registry tells the two apart by their declared names: `fPoll` is
  `file_poll`, whether the file has input ready (`idris2_fpoll`'s
  meaning, which base's documentation states), waiting at most a second.

### C9.3 The handle ops

| Op | Operands -> results | Effects |
|---|---|---|
| `idr.handle.is_null` | `i64 -> i64` | `Pure` |
| `idr.handle.string` | `i64 -> !idr.str` (allocates) | `MemRead<Idr_IOResource>`, `MemAlloc` on the result |
| `idr.io.handle_free` | `h -> ()` | an `Idr_IOOp` |

### C9.4 `OSClock` is an immediate value

An `OSClock` is `seconds << 30 | nanoseconds`, with `seconds < 2^33`.
That covers every clock until the year 2242. An invalid clock is `-1`.
The clock primitives have `scheme:`, `RefC:` and `javascript:` specs
and no `C:` spec (`System/Clock.idr:119-204` in base), so U18 recognizes
them by their `scheme:` spec. Their meaning is the runtime's: base's
`ClockType` read through POSIX `clock_gettime`: `UTC` is `CLOCK_REALTIME`,
`Monotonic` is `CLOCK_MONOTONIC`, `Process` is
`CLOCK_PROCESS_CPUTIME_ID` and `Thread` is `CLOCK_THREAD_CPUTIME_ID`. A
reading that fails is invalid.
The two GC clocks are always invalid: no collector runs, and base makes
both optional (`isClockMandatory`). So `clockTime GCCPU` and
`clockTime GCReal` give `Nothing`. That is their documented meaning
(O2), and `programs/io/clock-monotonic` states it.

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
computed from captures that existed before the cell, so a heap memo cell
cannot reach itself. Idris has no recursive `let` of values.

A static memo cell can (the review's smaller points): a constant `fibs` whose forced
tail captures the constant itself. That cycle runs through persistent
cells, which are never counted, so nothing leaks:
`idris_rt_caf_release` releases what each static cell's forced value
holds, once, at exit (C5.5). The check therefore ignores it.

Before `idr-defunctionalize`, a closure's captures are not types yet. So
the check is complete from `idr-defunctionalize` on, and sound but
partial before it.

### C10.2 The in-place promise (U20, `IDR/Demand/`)

`idr-demand{promises=in-place}` runs after `idr-rc`. For every function
`f`, a parameter `p` is **promised** when both hold:

- `p`'s type has quantity 1;
- an `idr.reuse` in `f` takes its token from an `idr.take` of `p`
  (the review's smaller points). The take's operand is `p` itself, or the region
  argument a match of `p` binds it to.

That is a fact of `f`'s body, read from two ops. It needs no analysis
and no per-function property of `idr-expect`.

Every call of `f` must then pass a promised `p` with permission `excl`.
A call that passes it `own`, or as a plain view, is rejected:

```
unsupported (uniqueness): <caller> passes a shared <T> to <f>, which rebuilds it in place
```

The error goes at the call. When the argument is the result of an
`idr.dup`, a note at the dup says `shared here`. The pass reads that
from the operand's defining op: `ExclusiveAnalysis`'s lattice
(`Unknown`/`Exclusive`/`Shared`) keeps no reason, and C10.2 does not add
one.

Without `promises`, the pass does nothing. `--demand in-place` on
`idris-mlir-cc` (`IDR/Driver/Options.cppm`) runs it with the promise,
and so does `--directive demand-in-place` on `idris-mlir`
(`CS/Frontend/Main.idr`, as `no-eval` is passed today). O5 makes the
promise the default, later.

## C11. Upstream patches instead of workarounds (U01)

### C11.1 The clang crashes

Neither is U01's in this packet.

- **`clang-module-predeclared-new`** retired with the pin (20fcfadb).
  Main's clang compiles its unit on arm64 macOS,
  `IDR/Driver/Retarget.cppm` builds its feature string as `std::string`,
  and `PINS.md` and `upstream/README.md` record it. F-up-2 is done. The
  retirement is rechecked on x86_64 Linux when that toolchain is rebuilt
  at the pin (README "Qualification").
- **`clang-module-layout-forward-declaration`**
  (`upstream/11-clang-module-layout-forward-declaration`) crashes only
  the x86_64 Linux build. Its check has `targets` `linux`, and the clangs
  of 23.1.2 and of 7208ba24 both compile the report's unit on arm64
  macOS. This swarm runs on arm64 macOS, and no x86_64 Linux toolchain
  exists at the pin, so nothing here can reproduce, reduce or retire it.
  `IDR/Stack/Escape.cppm` keeps its `func::FuncOp` sets and its
  `PIN(clang-module-layout-forward-declaration)` marker. F-up-1 is the
  coordinator's, recorded NotRun with x86_64 Linux. Its README's plan
  stands for a Linux host: rerun the check at the pin, reduce, then
  either the pin moves past a fix on main (there are no backports) or a
  patch of ours goes in its directory.

### C11.2 `idr-dead-values`

The behaviour is upstream's, read at 7208ba24
(`findings/llvm-trunk-mechanisms.md`, "Every other entry, at 7208ba24").
`remove-dead-values` lists every call of a private function that
returns a value and calls `RewriterBase::eraseOpResults` on it
(`RemoveDeadValues.cpp:733`, through `dropUsesAndEraseResults`,
`:201-209`), which builds a new op even for an empty set
(`PatternMatch.cpp:278-314`). The patch of
`upstream/06-remove-dead-values-unreachable` leaves this as it is; its
README calls it a separate matter.

U01 reduces it to upstream ops and `mlir-opt`. If it reproduces, the
fix is a bug directory of its own,
`upstream/16-remove-dead-values-unchanged-call/`: a README with the
report, `## Patch` and `## Upstreaming plan` (not filed), the
reproducer, and `llvm.patch`, a `git diff` against 7208ba24 with its
test in `mlir/test`. It applies after 15 in name order, and alone too
(`tests/spec/upstream-patches`), so its hunks stay out of the lines 06's
patch changes. Its test hunk included: 06's patch appends its cases to
the end of `mlir/test/Transforms/remove-dead-values.mlir`
(`@@ -918,3 +918,100 @@`), and a hunk that appends there too has no
trailing context, so `git apply` anchors it to the end of the file: it
applies alone and fails after 06. The case goes before that file's last
split (the `// -----` at `:899`, before `@callee_with_dead_return`), or
in a test file of its own in `mlir/test/Transforms`. It tests a
fingerprint property, and `upstream/02-composite-fixed-point-sccp/llvm.patch`
is the model: its second RUN line of `mlir/test/Transforms/sccp.mlir`
runs `composite-fixed-point-pass{pipeline=sccp max-iterations=2}` under
`-verify-diagnostics`, so the test fails unless the pass's output is its
own fixed point. Its check is
`tests/upstream/remove-dead-values-unchanged-call`. The number is the
next free one: 12 to 14 are retired names that `PINS.md` and
`upstream/README.md` still cite.

06's `llvm.patch` is a pending LLVM pull request that another agent
sends, and the owner is told before it changes in substance. U01 edits
nothing under 06 or 02. The sentences of their READMEs that name
`idr-dead-values` change at integration (C1.8). If the fix can only be
made in 06's patch, U01 escalates with the diff, and the coordinator
tells the owner before anything under 06 changes, and records it in
06's README.

`IDR/Simplify`'s round then runs `remove-dead-values{canonicalize=false}`
where it ran `idr-dead-values`, after `idr-eval` and before
`symbol-dce`. Its canonicalization stays off, as `idr-dead-values` runs
it today, for the reason `IDR/Simplify/DeadValues.cppm` gives.
`IDR/Simplify/DeadValues.cppm` and `DeadValues/Pass.cc` go. Nothing else
in the loop changes: `IDR/Simplify/Pass.cc` builds it as upstream's
`composite-fixed-point-pass`, silent at its budget, between the two
passes that open and close a round, and its fixpoint test is that
pass's `OperationFingerPrint`. Nor do its loop breakers
(`IDR/Simplify/Breakers.cppm`), which end it: since ccc3e1dc a clone of
a breaker keeps `no_inline` through `idr-specialize`'s
`CloneTable::settleBreaker`, as `Breakers.cppm`'s header says, and
`T/idr/specialize/breaker-clones` and `T/programs/eval/latent-loop*`
pin it.

If it does not reproduce upstream, the bug is ours. U01 fixes it in
`IDR/Simplify`, says so, writes no `upstream/` directory, and the pass
still goes.

## C12. The discriminators (U22, U23)

Every row below must fail against the launch base (README, Engagement
contract; ee4ce8e does not build on the pinned toolchain), or show the
old mechanism, and pass after the cutover. The coordinator runs them
against the launch base's kept build between integration steps 4 and 5,
on today's toolchain (`work-units.md` "Integration"). Names are
directories under `T/`.

A `program` row is a fixture of `T/templates/program`, and its committed
expected files are its specification (C0): `expected-stdout`, and
`expected-exit`, `expected-crash` or `stdin` where the row names one.
U23 writes them from the row and the documented meaning of what the
program calls (C9), not from any run. They hold on both targets, so a
row prints nothing that C9 leaves to the C library or the host: no
`strerror` text, no unsorted directory order, no clock reading, no
`argv[0]`, no host variable's value. No row is compared with Idris's
Chez backend or stock evaluator.

| Test | Kind | What it shows | Proves |
|---|---|---|---|
| `reject/cycle-array-knot` | reject | `data Node = MkNode (IOArray Node)`, a knot written: `unsupported (cycle)`, naming `Node` | C10.1 |
| `programs/arrays/array-of-arrays` | program | `IOArray (IOArray Int)` compiles and runs | C10.1 is not too strong |
| `reject/signal-handler` | reject | `System.Signal.collectSignal`: `unsupported (signal)` | C9.5 |
| `reject/threads-concurrency` | reject | `System.Concurrency.makeMutex`: `unsupported (threads)` | C9.5 |
| `reject/process-system` | reject | `System.system "true"`: `unsupported (process)` | C9.5 |
| `reject/uniqueness-shared-rebuild` | reject, `--directive demand-in-place` | a shared list passed to a quantity-1 `map` that rebuilds in place: `unsupported (uniqueness)` naming the call | C10.2 |
| `programs/linear/leet-*` | program | every leet fixture compiles with `demand-in-place` and still `tests-nothing` | C10.2 is not too strong |
| `programs/io/files-roundtrip` | program | write a file, read it back by line and by chars, `fileSize`, `removeFile` | C9.2 |
| `programs/io/directory-listing` | program, `IDRIS_RT_LIVE=1` | `createDir`, `openDir`, `nextDirEntry` until `Nothing` (sorted), `closeDir`, `removeDir`; ends with 0 live cells | C9.2 |
| `programs/io/environment-arguments` | program, `IDRIS_RT_LIVE=1` | prints `length !getArgs` and never `argv[0]` (review R9); `setEnv "IDRIS_MLIR_T" "1"`, then `getEnv` of it twice; `getEnv` of an unset name gives `Nothing`; ends with 0 live cells | C9.1, C9.2 |
| `programs/io/clock-monotonic` | program | two monotonic readings, printed only as whether the second is not earlier; `clockTime GCCPU` and `clockTime GCReal` give `Nothing` | C9.4, O2 |
| `programs/eval/memo-shared-stream` | program, `IDRIS_RT_LIVE=1` | observes memoization without an effect (review R9): a top-level and a local `fibs` (`Stream` of exponential-cost cells), each shared by two consumers, sized so that recomputation exceeds the test's timeout, as `eval/lazy-double` is; ends with 0 live cells | C5.1, C5.3 |
| `programs/eval/thunk-consumes-list` | program, `IDRIS_RT_LIVE=1` | a thunk that consumes a 10^6-element list: peak live cells bounded, list reused in place (`reuses-in-place`) | C5.3 (captures moved) |
| `programs/arrays/lazy-elements` | program | an `IOArray (Lazy Int)` written with suspensions and forced twice, which compiles today, still compiles and runs (review R7) | C5.1 (arrays in Slots) |
| `programs/io/exit-with` | program, `expected-exit 3` | `exitWith (ExitFailure 3)` after output: the output is written, the status is 3, no live-cell report (review R11) | C9.1 |
| `programs/partial/self-forcing-caf` | program, `expected-crash` | a top-level lazy value that forces itself ends with `a suspension forced itself` | C5.3 |
| `programs/eval/closure-result-roundtrip` | program | a compile-time result holding a closure (a partially applied function in a list) is reified and run | C6.4, C5.7 |
| `programs/eval/deep-list-constant` | program | a computed 10^5-element list constant on an 8 MiB compile stack | C7 |
| `programs/basic/guards-messages-*` | five programs, one `expected-crash` each (a program crashes once), and `idr/guards/byte-message`, a lit test, for the byte no program reaches (README S13) | each of div by zero, `strIndex` out of range, `strHead ""`, `cast` of NaN to Int, a byte out of range, an array index out of bounds: the same message and location as at the launch base, each cause taken from an existing `expected-crash` or, where none covers it, from the launch base's source, at a location in `semantics/crash-location`'s format | C3 |
| `idr/guards/fold-*` | lit | each guard folds on a proving constant, does not on a failing one, folds under a dominating identical guard | C3.4 |
| `idr/guards/speculation` | lit | an `scf.while` whose condition is `%i < idr.str.length %s`, with `%s` and `%i` loop-invariant and `idr.str.index %s, %i` (its guard proved away) at the top level of the after region: `loop-invariant-code-motion` leaves the index in the loop. (`licm` visits only a loop body's top-level ops, `LoopInvariantCodeMotionUtils.cpp:75-87`, so an op inside an `scf.if` is never a discriminator.) | C3.3 |
| `idr/in-bounds/*` | lit | restated as "no `idr.check.in_bounds` left"; no `in_bounds` keyword anywhere | C3.5 |
| `idr/isolate/*` | lit | captures leading, constants cloned not captured, nested lambdas isolated innermost first, names `$lam<n>`/`$delay<n>` | C4.3 |
| `idr/defunc/memo-*` | lit | a lazy key becomes a `memo` box sum with `running`, `forced` and `labels`; a label that reaches `idr.io.put_str` is `by_name`; one that reaches only array ops is not; one a static constant names is not; no `!idr.lazy` remains | C5.1 |
| `idr/defunc/unknown-lazy` | lit, `-verify-diagnostics` | a suspension the analysis loses gives `unsupported (laziness)` at the op it flows through | C5.1 |
| `idr/lower/force-*` | lit | view force: one switch, direct call, `running` written before the call; `excl` force: free and no write | C5.3 |
| `idr/lower/static-thunk` | lit | a lazy constant lowers to a non-constant global with the thunk kind, listed in `@__idr_release_cafs`; a constant stream whose tail is that thunk lowers to a `constant` global pointing at it; every other static global is `constant` | C5.5 |
| `idr/lower/no-mode` | lit | `idr-lower` has no `jit` option (`--idr-lower=jit=1` is an unknown option) | C6.1 |
| `idr/lower/entry`, `idr/lower/meter` | lit | `@main(i32, ptr)`; ticks at entry and before each `llvm.sideeffect` | C6.2, C6.3 |
| `idr/ownership/consumed-effects` | lit | after `idr-rc`, `remove-dead-values` keeps an unused `idr.con` of owned fields; before it, `canonicalize` erases an unused `idr.con` | C2.1 |
| `idr/ownership/owned-stage` | lit, `-verify-diagnostics` | `idr-rc`'s output carries no `idr.stage`; a module with no `idr.stage` whose `!idr.own` value is never consumed is rejected by the owned-stage rule (at the launch base it passes, since the rule runs only under the attribute) | C2.2 |
| `idr/constants/run` | lit | a 10^4-cell run prints flat and round-trips through text and bytecode; a list built cell by cell and one built with `getRun` are the same attribute | C7 |
| `idr/verify/cycle` | lit | the verifier rejects the knot's types after defunctionalization | C10.1 |

Existing tests that name a retired mechanism are restated in the new
terms or deleted by U22 or U23. "Retired mechanism" means any name in
README's retired list. A test whose only purpose was the retired
mechanism is deleted, never kept as a red test.

Tests the cutover keeps as they are, with their committed files, since
they test what it keeps:

- those new at 20fcfadb and 1677b8cb (README L22);
- those new at ccc3e1dc, which pin the loop breakers that end
  `idr-simplify` (C2.4, C11.2): `T/idr/specialize/breaker-clones`, the
  raised-clone case of `T/idr/specialize/binding-times.mlir`, and
  `T/programs/eval/latent-loop`, `latent-loop-delay` and
  `latent-loop-accumulator`, whose `mlir.expect` reads
  `idr-simplify: every-cycle-has-breaker`;
- the expected files phase 1b (08a065e4) wrote where the oracle was, which
  are those tests' specification (C0): the `expected-stdout` of
  `T/idr/stack/hot-loop`, `T/programs/arrays/buffer-ops`,
  `arrays/linarray-bubble`, `stack/forever-until-crash` and
  `stack/io-loop-through-helper`;
  `T/toolchain/double-print/expected-doubles`;
  `T/toolchain/runtime-api/expected-operations`. Phase 1b also took
  every line for another backend out of the `expected` transcripts; a
  transcript a lane writes or restates keeps that form.

## C13. Verification

- **During the swarm, no lane runs** `make check`, `make build`,
  `make test`, `make test-idr`, `make test-mlir-tools`, cmake, ninja,
  the Idris compiler, or any suite. The tree is red mid-swarm by design:
  lanes write against declarations other lanes are writing.
  - `make check` is not build-free: it builds the test runner with Idris
    (`Makefile` `check: runner`). Its `spec/dialects-current` is red from
    the moment the coordinator applies C1.1 until integration step 2
    regenerates `CS/Dialect/Idr.idr`, and `spec/file-size` is red while
    any lane's unit is over 400 lines. A lane that runs it sees red it
    must not fix (review R13).
- **What a lane may run:**
  - the one spec test its acceptance names, from that test's directory,
    and nothing else:

    ```sh
    cd tests/spec/<name> && IDRIS_MLIR_ROOT=<repository root> sh run | diff - expected
    ```

    No spec test builds anything. A lane whose acceptance names none runs
    none.
  - U01 also runs the pinned `mlir-opt` and `idris-mlir-reduce` on its
    own reproducers, and its own check.
  - U01 may build a scratch `mlir-opt` to check that its patch compiles
    and that its `mlir/test` RUN line passes: it compiles the upstream
    files its patch changes (the pinned source with the patches before
    16 applied, 06's included, then its own) in a scratch directory
    outside the repository, and links them with an `mlir-opt` main
    against the static `libMLIR*.a` installed in
    `.toolchain/llvm-macos/lib`, as 06's README records its own check.
    Such a build has no test dialect, so a case that uses it does not
    parse there. It builds neither the tree nor the toolchain, and
    nothing of it enters the tree.
- **Held out** (review R13, restated for the pin of 20fcfadb). Lanes
  share one checkout, and U01 writes its work there as usual. All of it
  (C11.2), and C1.2's `idr-dead-values` lines, are out of the tree from
  integration step 3 until step 5, because each needs the rebuilt
  toolchain:
  - U01's new `llvm.patch`: `make build` runs `tools/verify-pins.sh
    llvm`, which refuses a toolchain whose stamp records other patches
    than `upstream/` carries;
  - its check, which expects the patched `mlir-opt`;
  - its `IDR/Simplify` change. At 7208ba24, with 02 to 07, 09 and 15,
    `remove-dead-values` still builds a new call for every call of a
    private function that returns a value (`RemoveDeadValues.cpp:733`;
    `RewriterBase::eraseOpResults`, `PatternMatch.cpp:278-314`, has no
    early return for an empty set). So the module's
    `OperationFingerPrint`, which upstream's `composite-fixed-point-pass`
    compares after each round (`CompositePass.cpp:69-103`;
    `IDR/Simplify/Pass.cc:114-128`), never repeats. Without
    `idr-dead-values` the loop would run `max-rounds` + 1 rounds, and
    `idr-simplify` would report `unsupported (compile-time budget)` for
    every program with such a call (`Pass.cc:134`, `:163-166`; `PINS.md`
    `simplify-structural-fixpoint`);
  - the removal of `idr-dead-values` from `Passes.td`, since
    `DeadValues/Pass.cc` defines it until then.

  At step 3, before `make check` and `make build`, the coordinator sets
  U01's group aside in two stashes, from the repository root, so that
  the patch comes back first:

  ```sh
  git stash push --include-untracked -m u01-rest -- \
    tests/upstream/remove-dead-values-unchanged-call foreign/idr/lib/Simplify
  git stash push --include-untracked -m u01-patch -- \
    upstream/16-remove-dead-values-unchanged-call
  ```

  C1.2's `idr-dead-values` lines are not in `Passes.td` then: a stash
  takes whole files, and `Passes.td` carries the rest of C1, so the
  coordinator writes those lines at step 5 and not before. At step 5 it
  pops `u01-patch`, runs `make bootstrap` (`tools/bootstrap.sh` applies
  every `upstream/*/llvm.patch` present), pops `u01-rest`, writes C1.2's
  lines, and runs `make build` (`work-units.md` "Integration").

  If U01's fix is ours (C11.2), nothing is held out and there is no
  rebuild. `IDR/Stack/Escape.cppm` is not held out: C11.1 leaves it as it
  is.
- **Integration** is the coordinator's, in the order of `work-units.md`
  "Integration". Repairs go through the owning lane.
- **Qualification:** README "Qualification".
