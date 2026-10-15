## C01 Identified data types

Producer: U01. Decision: 0004 D29 (§4 stage 1), D19, D48. Mechanism:
LLVM's identified structs (`M/include/mlir/Dialect/LLVMIR/LLVMTypes.td:153-280`,
`M/lib/Dialect/LLVMIR/IR/LLVMTypes.cpp:469-524`, storage
`M/lib/Dialect/LLVMIR/IR/TypeDetail.h:200-262`, cyclic syntax
`M/lib/Dialect/LLVMIR/IR/LLVMTypeSyntax.cpp:52-80, 132-240`). `M/` is
`.toolchain/build/llvm-project/mlir`.

A data type is a type identified by its name whose body, its constructors,
is set once. `idr.data` and `idr.ctor` are deleted. Nothing reads a data
type from the symbol table: a pattern, a verifier and a pass read the type.

### 1. What is deleted

- `Idr_DataOp`, `Idr_CtorOp`, `Idr_PublicSymbol` (`IdrOps.td:105-176`),
  `lib/IR/OpsData.cpp` (its content moves into the type), the
  `PublicSymbol` trait (`IdrDialect.h:216-235`).
- From `include/idr/IR/Symbols.h`: `getSumName`, `lookupData` (both),
  `lookupCtor` (all three), `declarationOf`, `constructorOf`, `listCons`,
  `listElement`, `isMemo(DataOp)`, and the callback parameter of
  `holdsReferences`.
- `!idr.data<@T>` and `!idr.box<@T>` as symbol names
  (`IdrTypes.td:25-38`).
- `Layouts::box(CtorOp)`, `Components::declaration`,
  `Components::sum(StringAttr)`, `SumLayout::fields` keyed by name,
  `boxable(DataOp)`, `Holders`' `Operation *at` callback argument.

### 2. ODS (`include/idr/IR/IdrBase.td`, `IdrTypes.td`)

```tablegen
// IdrBase.td
def Idr_SumKind : I32EnumAttr<"SumKind", "what sum a data type is", [
    I32EnumAttrCase<"Plain", 0, "plain">,       // an Idris data type
    I32EnumAttrCase<"BaseList", 1, "list">,     // base's List: nil, then cons
    I32EnumAttrCase<"InPlace", 2, "in_place">,  // mlir-linear's: rebuilt in place, exclusive
    I32EnumAttrCase<"Closures", 3, "closures">, // made by idr-defunctionalize, one ctor per label
    I32EnumAttrCase<"Memo", 4, "memo">]> {      // made by idr-defunctionalize: labels, running, forced
  let cppNamespace = "::idr";
  let genSpecializedAttr = 0;
}

// IdrTypes.td
def Idr_DataType : Idr_Type<"Data", "data", [MutableType, MemRefElementTypeInterface]> {
  let summary = "a data type, identified by its name, whose body is its constructors";
  let parameters = (ins StringRefParameter<"the data type's identifier">:$name);
  let storageClass = "DataTypeStorage";   // idr::detail::DataTypeStorage, lib/IR/Types.cpp
  let genStorageClass = 0;
  let skipDefaultBuilders = 1;
  let hasCustomAssemblyFormat = 1;
  let extraClassDeclaration = [{ ... §3 ... }];
}

def Idr_BoxType : Idr_Type<"Box", "box", [MemRefElementTypeInterface]> {
  let summary = "a reference to a cell that holds a value of a data type";
  let parameters = (ins "::idr::DataType":$data);
  let assemblyFormat = "`<` qualified($data) `>`";
  let builders = [TypeBuilderWithInferredContext<(ins "::idr::DataType":$data), [{
    return $_get(data.getContext(), data); }]>];
}

def Idr_SumType : AnyTypeOf<[Idr_DataType, Idr_BoxType]>;   // unchanged name
```

Boxing is the value's type alone: a value of a data type `T` held in place
is `T`; held through a cell it is `!idr.box<T>`. The kind says nothing of
boxing. `Idr_SumValue`, `Idr_SumView`, `Idr_BoxValue` keep their names and
predicates over the two classes.

### 3. C++ (`include/idr/IR/IdrDialect.h`, generated `IdrTypes.h.inc`)

Declared in `IdrDialect.h` before the generated types:

```cpp
namespace idr {
namespace detail { struct DataTypeStorage; }

// One constructor of a data type's body. Its tag is its position.
struct Ctor {
  mlir::StringAttr name;            // unique within the body
  llvm::ArrayRef<mlir::Type> fields;
  bool byName = false;              // a memo sum's label alone (D34)
  bool operator==(const Ctor &) const = default;
};
} // namespace idr
```

`class idr::DataType` (members declared in ODS `extraClassDeclaration`,
defined in `lib/IR/Types.cpp`):

```cpp
// The data type named `name`, made without a body if the context has none
// of that name. It is the same type for the context's whole life.
static DataType get(mlir::MLIRContext *context, llvm::StringRef name);
static DataType getChecked(llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
                           mlir::MLIRContext *context, llvm::StringRef name);
// Sets the body, once. The same body again succeeds; another body, or a body
// that is not a well-formed sum (§5), fails with an error from `emitError`.
mlir::LogicalResult setBody(llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
                            SumKind kind, llvm::ArrayRef<Ctor> ctors, InstanceAttr instance);
llvm::StringRef getName() const;
bool hasBody() const;
SumKind getKind() const;                    // requires hasBody()
llvm::ArrayRef<Ctor> getCtors() const;      // tag order; empty without a body
const Ctor &getCtor(unsigned tag) const;
InstanceAttr getInstance() const;           // null when the body has none
// The tag of the constructor named `name`, or nothing: O(log n).
std::optional<unsigned> getTag(llvm::StringRef name) const;
bool isMemo() const;                        // hasBody() && kind == Memo
bool isClosures() const;                    // hasBody() && kind == Closures
// A label's constructor: every constructor of a closure sum, every one of a
// memo sum but its two states.
bool isLabel(unsigned tag) const;
// A memo sum's states, its last two constructors.
unsigned getRunningTag() const;             // getCtors().size() - 2
unsigned getForcedTag() const;              // getCtors().size() - 1
// base's list (kind BaseList): nil is constructor 0, cons constructor 1.
static constexpr unsigned listNil = 0, listCons = 1;
mlir::Type getListElement() const;          // getCtor(listCons).fields[0]
```

`class idr::BoxType`: `static BoxType get(DataType data)`,
`DataType getData() const`.

`IdrDialect.h` keeps `memoRunning = "running"`, `memoForced = "forced"`
(`IdrDialect.h:290-291`): the names a maker gives a memo sum's states.

Value-level helpers, `include/idr/IR/Symbols.h` (the header's purpose
becomes "what a data type's body says, beyond the type's own accessors"):

```cpp
namespace idr {
// The data type a value of `type` is of: `type` itself or the data of its
// box, through a grade; null for any other type.
DataType dataTypeOf(mlir::Type type);
// Whether a value of `type` is a box: a cell (through a grade).
bool isBoxed(mlir::Type type);
// Whether a value of `type` holds a reference a count accounts for. An
// unboxed sum holds what its constructors' fields hold, read from its body.
bool holdsReferences(mlir::Type type);

// The elimination of a value that begins at one of its uses: the dispatch
// on the value, or on one field of it, each read through the one use of a
// linear value, where the value may first pass a linear position entered
// and used at once (the coordinator's decision from C09 §5). The last step
// is the dispatch, an idr.match whose scrutinee has a data type of kind
// closures, in place of today's idr.apply (Symbols.h:58-75).
struct Elimination {
  LinEnterOp enter;   // the pair that only moves the value into a linear
  LinUseOp exit;      // position and out again, or null
  FieldOp field;      // null: the value itself is dispatched on
  LinUseOp use;       // null: what is dispatched on is not linear
  MatchOp dispatch;
};
std::optional<Elimination> eliminationAt(mlir::OpOperand &use);
}
```

### 4. Syntax

```
data-type ::= `!idr.data<` string-literal `>`
            | `!idr.data<` string-literal `,` sum-kind `[` (ctor (`,` ctor)*)? `]`
                         (`instance` instance-attr)? `>`
ctor      ::= symbol-name `(` (type (`,` type)*)? `)` (`by_name`)?
sum-kind  ::= `plain` | `list` | `in_place` | `closures` | `memo`
box-type  ::= `!idr.box<` data-type `>`
```

- The name-only form is written, and parsed, only inside the body of the
  type it names (`tryStartCyclicPrint` / `tryStartCyclicParse`, as
  `LLVMTypeSyntax.cpp:58, 159-196` do); anywhere else the parser refuses it:
  "a data type is written without its body only inside its own body".
- A body parsed for a type that already has one is checked equal
  (`setBody`), so a type written in full in several places parses.
- The printer gives each data type an alias, its name shortened as
  `Asm.cpp:23-44` shortens it (`!List_Nat`); the alias of a recursive type
  is defined with its self-references in the name-only form. A box has no
  alias of its own: `!idr.box<!List_Nat>`.
- Example (base's list of naturals):

```mlir
!List_Nat = !idr.data<"Prelude.Types.List[Prelude.Types.Nat]", list [@Nil(),
    @Cons(!idr.nat, !idr.box<!idr.data<"Prelude.Types.List[Prelude.Types.Nat]">>)]
    instance #idr.instance<"Prelude.Types.List", ["Prelude.Types.Nat"]>>
```

- One `MLIRContext` holds one type per name for its life: two
  `--split-input-file` chunks that write one name write one body.
- Bytecode: the dialect gives the type no bytecode form, so the writer
  stores its assembly, as upstream does for identified structs (D36); a
  recursive type names itself in its text.

### 4a. The Idris side (generated into `compiler/src/IdrisMLIR/Syntax/Idr.idr`)

`idris-mlir-tblgen -gen-idris-syntax` writes, for the one identified type
(a TypeDef with the `MutableType` trait), these declarations in place of
today's `DataType : (name : String) -> IdrType ty` (`Syntax/Idr.idr:102`):

```idris
namespace SumKind
  public export
  data SumKind = Plain | BaseList | InPlace | Closures | Memo
-- Show SumKind: "plain" "list" "in_place" "closures" "memo" (C04 §4's rule)

||| One constructor of a data type's body: its name, its fields' types, and
||| whether every force of it runs it (a memo sum's label alone).
public export
record IdrCtor ty where
  constructor MkIdrCtor
  name : String
  fields : List ty
  byName : Bool

||| A data type's body: what sum it is, its constructors in tag order, and
||| the Idris instance it is of, the instance's origin and arguments.
public export
record IdrSum ty where
  constructor MkIdrSum
  kind : SumKind
  ctors : List (IdrCtor ty)
  instanceOf : Maybe (String, List String)

-- in data IdrType:
  ||| `!idr.data`: a data type, identified by its name; written without its
  ||| body only inside its own body
  DataType : (name : String) -> (body : Maybe (IdrSum ty)) -> IdrType ty
  ||| `!idr.box`: a reference to a cell that holds a value of a data type
  BoxType : (data' : ty) -> IdrType ty
```

`idrTypeText` writes them in §4's syntax: `Nothing` as the name-only form,
`Just` with the constructors by `symbol`, fields by `t`, `by_name` when set,
and `instance #idr.instance<origin, [args]>` with `utf8` strings. Emit
writes `Just` at a type's first occurrence in the module and wherever it is
not inside its own body, `Nothing` inside it (C22).

### 5. Invariants (checked once, by `setBody`; a type with a body has them)

1. Constructor names are distinct; a name is a symbol name (any string).
2. Every field type is an `isFieldType` type (`Grades.h`).
3. `byName` only on a label of a memo sum.
4. `memo`: at least the two states; the last two constructors are
   `running` with no field and `forced` with one; the rest are labels.
5. `list`: two constructors; constructor 0 has no field; constructor 1
   has two, the second `!idr.box<T>` (through a grade) of the type itself.
6. Nothing else constrains `plain`, `in_place` or `closures`.
7. A tag is a position, `[0, getCtors().size())`; `idr.tag` folds and
   ranges read the size (`OpsCon.cpp:223-255` without the scan).

Rules of the whole program, which need its values, are C03's (a box's
2^16 tags, a memo sum only boxed, containment acyclic, every type with a
body).

### 6. Who makes a data type

- The frontend writes every `plain`, `list` and `in_place` type in its
  first, full occurrence of the emitted module (U15, C22); the registry
  names `list` and `in_place` (U14, C20).
- idr-defunctionalize makes every `closures` and `memo` type (U02, C06),
  with `byName` decided by the effects summary before the body is set
  (U05, C10).
- A pass that would change a body makes a new type instead, through
  `DataRemap` (§7). No other way to change a body exists.

A label constructor's name is the label function's symbol name; a site that
builds one (`idr.con`, `#idr.con`) is a symbol use of the label (C02 §1).
A plain constructor's name is no module symbol's: the frontend's
constructors are short Idris names and its functions qualified ones.

### 7. Remaking data types (`include/idr/IR/Symbols.h`, `lib/IR/Symbols.cpp`)

```cpp
namespace idr {
// The data types of a module remade where a body would change. A type whose
// body holds a changed type, or a remade one, is remade, transitively; every
// other type stays itself. A remade type is named
// contentName(old name, `kind`, key) (C21), the key being its new body with
// every data type in it written by its old name, so the name needs no new
// name first; its kind, constructor names, `byName` and instance are the old
// type's. Every new body is set when the remap is made.
class DataRemap {
public:
  // The replacement of `type`, neither a data type nor a box (a closure, a
  // suspension, a tensor), or nothing to look inside it. `owner` is the data
  // type whose field `field` of constructor `tag` holds `type` (a field's
  // replacement may be keyed by where it is held, its anchor, not by its
  // type), or null where `type` is met anywhere but in a body. It may give a
  // data type whose body its caller sets later, and what it gives is looked
  // inside in turn (a tensor's buffer of a remade element).
  using Leaf = std::function<std::optional<mlir::Type>(mlir::Type type, DataType owner,
                                                       unsigned tag, unsigned field)>;
  // The remap keeps `leaf` and asks it once per (type, owner, tag, field).
  // Every occurrence of a type of `boxed` outside a box becomes a box of it.
  DataRemap(mlir::ModuleOp module, llvm::StringRef kind, Leaf leaf,
            llvm::ArrayRef<DataType> boxed = {});
  // The type `type`, met anywhere but in a body, becomes.
  mlir::Type map(mlir::Type type);
  // Every attribute, result type and block argument type under `root`,
  // mapped (AttrTypeReplacer::recursivelyReplaceElementsIn).
  void retype(mlir::Operation *root);
  // The data types remade, old to new, in old-name order.
  llvm::ArrayRef<std::pair<DataType, DataType>> remade() const;
  // Failure when a body could not be set: a remade name already holding
  // another body (a collision), reported as an internal error at the module.
  mlir::LogicalResult status() const;
};
}
```

A name collision is an internal error at the module, never a rename; the
caller checks `status()` and fails its pass.

### 8. The type graph (`include/idr/IR/TypeGraph.h`)

`TypeGraph(mlir::Operation *module)` walks every type the module's ops
name (attributes, results, block arguments) and every body those hold.
Nodes: every data type, numbered first in name order, then every array in
the order met. Edges: from a data type to what its fields name through a
grade (a data type held in place or in a box, an array), from an array to
its element's. Declarations change:

```cpp
DataType declaration(unsigned at) const;        // null for an array
bool boxed(unsigned at) const;                  // some value or field holds it in a box
bool inlined(unsigned at) const;                // some value or field holds it in place
llvm::ArrayRef<unsigned> successors(unsigned at) const;   // all edges
llvm::SmallVector<DataType> containsItself() const;       // through in-place edges, name order
```
`node`, `type`, `isArray`, `size`, `components`, `knots`, `cycle`,
`isInvalidated`: as today (`TypeGraph.h:28-56`).

### 9. Layouts (`include/idr/IR/Layout.h`)

```cpp
namespace idr::layout {
struct SumLayout {                  // as today, but fields by tag
  mlir::Type tag;
  llvm::SmallVector<mlir::Type> slots;
  llvm::SmallVector<bool> counted;
  // For each constructor, by tag: for each field, the slots of its components.
  llvm::SmallVector<llvm::SmallVector<llvm::SmallVector<unsigned>>> fields;
  llvm::SmallVector<mlir::Type> types() const;
  unsigned offset() const;
};
class Components {                  // as today, minus declaration()
public:
  // `boxed`: data types measured as if every value or field holding one in
  // place held a box of it (what fit weighs before it makes the boxes).
  explicit Components(mlir::ModuleOp m, llvm::ArrayRef<DataType> boxed = {});
  const SumLayout &sum(DataType type);
  ... components, counted, objects, getModule: unchanged
};
// Whether `data` may become a box without changing what an op means: one
// constructor, or a closure sum under the header's tags.
bool boxable(DataType data);
class Holders {
public:
  explicit Holders(mlir::ModuleOp m, llvm::ArrayRef<DataType> boxed = {});
  // Each holder whose cell counts more object slots than a header: a
  // constructor (`tag`) of a data type some value holds boxed, or the element
  // of an array of an unboxed sum (`tag` empty).
  void overflows(Components &parts,
                 llvm::function_ref<void(DataType type, std::optional<unsigned> tag,
                                         llvm::ArrayRef<mlir::Type> held, unsigned objects)> each);
};
// Decides the boxes that make every cell fit, widest first (ties by name),
// then makes them with one DataRemap of kind "box"; returns how many.
unsigned fit(mlir::ModuleOp module);
}
namespace idr {
class Layouts : public layout::Components {
public:
  const layout::SumLayout &sum(DataType type) const;
  // The cell of constructor `tag` of `type`, a type some value holds boxed.
  const layout::Cell &box(DataType type, unsigned tag) const;
  ... every other member: unchanged (Layout.h:246-279)
};
}
```

Components of a memref or a tensor (the coordinator's ruling with C16/C17;
a constant's header is in front of its data, so the element-0 pointer is
the cell's past its header and never carried): `[cell pointer (counted),
i64 offset when a strided layout's is dynamic, one i64 per dynamic size,
one i64 per dynamic stride of a strided layout]`, every one but the first
uncounted. `Layouts::element(word)` is one slot of the word at offset 0,
stride its size.

### 9a. The owned stage's vocabulary (`include/idr/IR/Ownership.h`, C14 §3)

```cpp
namespace idr::ownership {
// The value a field was read from: an idr.field's operand, a match's
// scrutinee for its case arguments, the source of a view of a buffer
// (memref.subview, cast, reinterpret_cast, expand_shape, collapse_shape,
// transpose, idr.tie_shape), or the buffer a counted element is loaded from.
mlir::Value readFrom(mlir::Value value);
// Static data that reaches no cell but atoms, read from the constant's
// data type and the type it is held at (no declaration callback).
bool reachesOnlyAtoms(mlir::Value view);
// An scf.for, or a linalg op with pure buffer semantics: a body run once
// per index (replaces isArrayLoop).
bool isIndexLoop(mlir::Operation *op);
}
```

`holdsReferences` is true of every memref and tensor type.

### 10. Consumers (by lane)

U02 (makes `closures`/`memo` types, remaps frontend types holding closures,
reads bodies: `Decide`, `Keys`, `Converter`, `Patterns`, `Declare`,
`Labels*`; `layout::fit`), U03 (`Holds` on TypeGraph; `References::closureLabel`
becomes `isLabel`), U04 (keys name a constructor by type and name;
`Identities*`), U05 (memo labels, `byName` before the body is set), U08
(`Reshape`, `Take`, `Reuses`, `Uses`, `Values`, `Exclusivity`, `Stack`:
`Layouts::box(type, tag)`, `holdsReferences`, `kind == InPlace`), U09
(`WhileDo`, `Lengths`), U10 (every data-type read in `lib/Conversion`;
erases no declaration: the types lower through the type converter), U11
(element types), U14 (registry roles `list`, `in_place`), U15 (writes the
types, C22), U16 (`Deduplicate`: no declaration to compare or hold), U17
(`CellsFit`, `Quantities`, `ReusesEveryCell`, fixtures).
