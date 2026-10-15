## C22 The emitted module: symbol-form closures, identified type syntax, tensor types, bytecode

Producer: U15. What the frontend hands the driver, and the Idris-side API
that writes it (`compiler/src/IdrisMLIR/MLIR.idr`, `MLIR/`, `Emit.idr`,
`Emit/`). Line numbers are the tree at a3e61f3a. `M/` is
`.toolchain/build/llvm-project/mlir`.

### 1. The file

- One file per program, MLIR bytecode, written by `IdrisMLIR.Emit.emit` at
  the path the frontend's `-o` names. The driver names that path
  `<base>.mlirbc` (`Artifacts.cpp:41` writes `base + ".mlir"` today; U07
  changes the extension). The driver reads it with `parseSourceFile`,
  which tells bytecode by its magic (`M/lib/Parser/Parser.cpp:47-48,
  62-63`); nothing in the driver changes for the format.
- Text is never the handoff. The readable module is MLIR's own print of
  the file (`idris-mlir-opt <file>.mlirbc`, `-mlir-print-ir-*`).
- The frontend writes the file whole or not at all: on an Emit failure
  `Frontend/Program.idr:66-79` removes it, as today.

### 2. The encoding (exact)

Every choice below is fixed; the writer has no mode.

- Header: the bytes `4D 4C EF 52`; the version as a varint, **6**
  (`kVersion`, `M/include/mlir/Bytecode/Encoding.h:53`); the producer
  `idris-mlir`, NUL-terminated.
- Sections, each once, none aligned, in this order: IR (4), attribute and
  type offsets (3), attributes and types (2), dialects (1), strings (0),
  properties (8, empty: its length is 0). The reader finds sections by id
  (`BytecodeReader.cpp:1936-1958`); the order is fixed so the file is a
  function of the module. No resource sections.
- Varints are PrefixVarInt (`docs/BytecodeFormat.md`, "Variable-Width
  Integers"; `BytecodeWriter.cpp:239-247, 639-659`), written byte by byte.
- **Strings:** each distinct string once, numbered in first use; the
  section is the count, the sizes (each with its NUL) in reverse order,
  then the strings, each NUL-terminated (`BytecodeWriter.cpp:373-383`).
- **Dialects:** each dialect an op name, attribute or type of the module
  belongs to, numbered in first use, written as `(name << 1) | 0`: no
  dialect version.
- **Op names:** numbered in first use; the section then holds their count
  and groups `(dialect, count, (name << 1) | 0 ...)`, one group per
  maximal run of one dialect in number order. The flag is 0, "not
  registered": the writer has no registry. Reason: the reader then takes
  an op's properties as one dictionary attribute and sets them with
  `setPropertiesFromAttribute` (`BytecodeReader.cpp:2569-2583`,
  `M/lib/IR/Operation.cpp:38-44`), the function the generic text form's
  parse calls (`M/lib/AsmParser/Parser.cpp:1624`), so a module reads as
  its generic text would, and the writer needs no op's native property
  encoding.
- **Attributes and types:** each distinct text one entry, numbered in
  first use (attributes and types apart), written as its assembly,
  NUL-terminated, flag 0 (no custom encoding): the bytecode's own
  fallback, which the pinned writer takes for every mutable type
  (`BytecodeWriter.cpp:889-899`) and which D36 decides. The offset section
  holds the two counts, then per run of one dialect `(dialect, count,
  (size << 1) | 0 ...)`. An entry's dialect is its constructor's
  (`attrDialect`, `typeDialect`, section 3). Locations are attributes
  (`loc(...)`, `M/lib/AsmParser/AttributeParser.cpp:137-146`).
- **Ops:** name; the mask byte; the location; when the op has
  discardable attributes, one `DictionaryAttr` of them (kHasAttrs); when
  it has properties, one `DictionaryAttr` of them (kHasProperties, the
  unregistered form: an attribute number in the op); the result count and
  types; the operand count and value numbers; regions. Never successors
  or use-list orders.
- **Isolation:** the module op and each op of its block are written
  isolated, their regions in a nested IR section; every other op's
  regions inline. Value numbers start at 0 in an isolated op's regions; a
  region's values are its block's arguments, then the results of its ops
  in order; a nested region's numbers start after every value of the
  regions that hold it, up to the isolated scope, and the regions of one
  op share that start (`IRNumbering.cpp:130-165`,
  `BytecodeReader.cpp:1814-1835`).
- **Regions and blocks:** a region is one block (`MLIR.Region`): `1`,
  its value count, then `(ops << 1) | hasArguments`; arguments as
  `(type << 1) | 1` and the location; a block with arguments ends its
  header with one `0` byte (no use-list orders).

### 3. The Idris API

`IdrisMLIR.MLIR.Text`: unchanged exports (`quoted`, `utf8`, `symbol`,
`separated`, `commaSeparated`, `array`, `SymbolRef`/`MkSymbolRef`,
`symbolRef`, `Signature`/`MkSignature`, `signature`, `floatLiteral`,
`twos`). The generated modules (U01) keep calling them.

`IdrisMLIR.MLIR` (exact, everything else in it is private):

```idris
namespace MlirType
  ||| A dimension of a shaped type: an extent the type fixes, or one the
  ||| value carries, written `?`.
  public export
  data Dim = Static Nat | Dynamic

namespace MlirAttr
  public export
  data MlirAttr : Type                            -- declared here, defined below

namespace MlirType
  public export
  data MlirType
    = IntegerType Nat
    | F64Type
    | IndexType
    | NoneType
    | RankedTensorType (List Dim) MlirType   -- dims outermost first; no encoding
    | MemRefType (List Dim) MlirType (Maybe MlirAttr)  -- identity layout; the memory space
    | FunctionType (Signature MlirType)
    | Idr (IdrType MlirType)

export Eq Dim
export covering typeText : MlirType -> String     -- tensor<?x3xf64>, memref<?xi64, #idr.world>
export typeDialect : MlirType -> String           -- "builtin", or "idr" for Idr

namespace MlirAttr
  public export
  data MlirAttr
    = UnitAttr | BoolAttr Bool | IntegerAttr Integer MlirType
    | FloatAttr Double MlirType | StringAttr String | SymbolRefAttr SymbolRef
    | TypeAttr MlirType | ArrayAttr (List MlirAttr)
    | DenseI32ArrayAttr (List Nat)
    | DenseI64ArrayAttr (List Integer)              -- array<i64: ...>
    | DictionaryAttr (List (String, MlirAttr))      -- {a = ..., b}
    | Idr (IdrAttr MlirType MlirAttr)
    | Arith (ArithAttr MlirType MlirAttr)
    | UB (UBAttr MlirType MlirAttr)

export covering attrText : MlirAttr -> String
export attrDialect : MlirAttr -> String           -- "builtin", "idr", "arith", "ub"
||| ShapedType::kDynamic, an entry of a static-index array an operand gives
||| (M/include/mlir/IR/BuiltinTypeInterfaces.td:288).
export dynamicExtent : Integer                    -- -9223372036854775808

public export NamedAttr : Type                    -- (String, MlirAttr)
export unitIf : String -> Bool -> List NamedAttr
export attrIf : String -> (a -> MlirAttr) -> Maybe a -> List NamedAttr
export covering dictionary : String -> String -> List NamedAttr -> String
public export data Location = At Loc | Named Shown Loc
export location : Location -> String              -- loc(...), as today
public export record Value, Argument, Op, Region, Statement   -- unchanged shapes
||| The names a statement binds its results to: its name for one result,
||| `name#i` for each of several, as operands name them.
export boundNames : Statement -> List String
||| A region's values in order: block arguments, then per statement its
||| op's operands, its name and bound names, then its regions.
public export data Occurrence = Uses Value | Binds Value | Defines String (List String)
export walkRegion : (a -> Occurrence -> a) -> a -> Region -> a
||| Every value renamed, where defined and where used.
export renameRegion : (String -> String) -> Region -> Region
||| An op in MLIR's generic form without the locations of what it holds:
||| what the op is, wherever it stands. Content keys hash it (section 5).
export covering genericForm : Op -> String
```

`Format`, `frame`'s declarative branch, `showModule`, `moduleText` and
`topLevel` go (section 8). `dictionary` stays for the generated
`printOp`s (U01's output) until they go.

`IdrisMLIR.MLIR.Bytecode` (new):

```idris
export Writer                                     -- abstract
export newWriter : IO (Either String Writer)
||| Encodes one top-level op of the module, isolated, after those before it.
export covering writeTopLevel : Writer -> Statement -> IO (Either String ())
||| Writes the file: the module op `m` at `at`, whose one region holds the
||| ops given to writeTopLevel in order (m's own region holds none).
export covering finish : Writer -> File -> Location -> Op -> IO (Either String ())
```

It uses only base's `Data.Buffer` (`newBuffer`, `setBits8`, `setString`,
`stringByteLength`, `copyData`), `Data.IORef` and `System.File.Buffer`'s
`writeBufferData`, each a runtime primitive of the registry
(`Registry/Primitives.idr:237, 458-505`), so stage 1 of `make self`
compiles it. Failures it reports: an operand no op in scope defines
(`"an operand <name> that nothing in scope defines"`), and a failed
allocation or write; each is the compiler's internal error.

`IdrisMLIR.Emit` (unchanged signature, the frontend's one call):

```idris
export covering emit : File -> Source -> IO (Either String ())
```

`Frontend/Program.idr:66-79` (U14) opens the file `WriteTruncate` and
calls it, as today.

Emission's own modules (no other lane calls them): `IdrisMLIR.Emit.Closures`
(`lift : Loc -> (kind : String) -> List Argument -> List Statement ->
List MlirType -> E (String, List Value)`) and
`IdrisMLIR.Emit.Tensors` (`coordinate`, `fit`, `tensorOp`, `tabulate`,
`tabulateIO`, `reduce`, `tie` over `data Stated = OfArray Val | OfNatural
Val`). `IdrisMLIR.Emit.Index.Index` holds `datas`, `cons`, `fns` and
`dataCount`; `Emit.Monad.ES` gains `owner`, `definition`, `lifted`,
`keys`, made by `initial : String -> Shown -> ES`.

Modules emission adds, for the ipkg (U14) and `tools/dialects.sh`
(coordinator): `IdrisMLIR.MLIR.Bytecode`, `IdrisMLIR.Emit.Closures`,
`IdrisMLIR.Emit.Tensors`, and the generated `IdrisMLIR.Syntax.Tensor`,
`IdrisMLIR.Syntax.SCF`, `IdrisMLIR.Dialect.Tensor`,
`IdrisMLIR.Dialect.SCF` (lines `tensor Tensor
$mlir_include/mlir/Dialect/Tensor/IR/TensorOps.td` and `scf SCF
$mlir_include/mlir/Dialect/SCF/IR/SCFOps.td` in `dialects()`,
`tools/dialects.sh:76-85`). The pinned `idris-mlir-tblgen` already
generates both: `Dialect.Tensor` has `emptyOp`, `extractOp`, `insertOp`,
`dimOp`, `castOp`, `extractSliceOp`, `insertSliceOp`, `collapseShapeOp`,
`expandShapeOp`, `padOp`, `yieldOp`, whose static index lists are
`MlirAttr` (`DenseI64ArrayAttr`); `Dialect.SCF` has `forOp` and
`yieldOp` (read: generated into a scratch directory from the pinned ODS).

### 4. What the module holds

- The dialects of the emitted module: `builtin`, `idr`, `arith`, `math`,
  `memref`, `ub`, `tensor`, `scf`. Nothing else (no `func`, `linalg`,
  `bufferization`, `affine`). The driver parses with exactly these (C12).
- One `builtin.module` at the root's location (`Emit.idr:91`), with no
  attribute. Its block holds `idr.func` ops only: for each function of
  `Source.fns`, in order, the function, then each function its lambdas
  and delays became, in the order their bodies were finished (an inner
  body before the body around it), each once.
- No `idr.data`, no `idr.ctor` (D29), no `idr.lambda`, no region form of
  `idr.delay` (D37), no discardable attribute on any op: no
  `idr.program` (D28), no `idr.stack` (D19). The root, `Source.root`, is
  the one `idr.func` without `sym_visibility`; every other has
  `sym_visibility = "private"`.
- A function's properties: `sym_name`, `function_type`,
  `sym_visibility` as above, `total` when `facts.terminating` (always,
  for a lifted function: it has no loop of its own, a recursion going
  through a function of the program), `no_inline` for a function of no
  parameters whose result is lazy (one shared cell,
  `Emit/Declarations.idr:67-70`), and `instance` of its key for a
  translated function (none for a lifted one). Never `break_last`,
  `effects`, `clone`, `arg_attrs`, `res_attrs`.
- Locations: a function at `NameLoc(<its Idris definition>, <its span>)`;
  a lifted function at `NameLoc(<its owner's Idris definition>, <the
  lambda's or delay's span>)` (C24 finds a definition's code by it); in
  library code wrapped as `fused<"library">[...]` (`MLIR.idr:148-157`);
  a parameter at its Idris name over the function's span; every op at
  its term's span, a binder's value at the binder's name.
- Symbols: a translated function's symbol is `f.id.name`, which C20
  makes the instance's symbol (`Term.keyText`: the print, or the print,
  `;` and 16 hex digits). Emit interns every symbol it writes; two
  functions on one symbol are an internal error. No `'n` repeat
  (`Emit/Index.idr:21-60` goes).

### 5. Closures and suspensions in symbol form (§4 stage 1, §2.7, D37)

- **A lambda** `Lam l name b body` is a lifted function `F` and
  `idr.closure @F(<captures>) : (<capture types>) -> !idr.fn<(<b held>) ->
  (<result>)>` at `l`.
- **The captures** are the values the emitted body uses that nothing in
  it defines, in the order of first use (an op's operands before what
  its regions hold, statements in order), each once. A constant is not
  one: Emit writes literals where they are used, inside the body. A
  variable bound to a constructor a match took apart is captured as the
  fields the body's rebuild uses, as isolation captured them
  (`Isolate.cpp:105-110`).
- **`F`**: parameters the captures (at their types, located at the
  lambda's span), then the lambda's parameter (`binderType b`, at
  `Named name l`); one result, the body's type, or, for a body that
  never returns, the type the context expects (no expected type is an
  internal error, as `Bodies.idr:164-170`). Its body is the emitted body
  with each capture's uses renamed to its parameter, ending in
  `idr.return` of the value held plain, or in `ub.unreachable`.
- **A suspension** `Suspend l body` whose body is *evaluated* is written
  where it is: the body's ops, then `idr.delay %v : !idr.lazy<T>` (C02's
  builder). A body is evaluated when it is a literal; a variable whose
  value is not linear (its constructor rebuilt, if it was taken apart,
  from fields none of which the constructor holds at quantity one, each
  evaluated in turn); or a constructor application none of whose fields
  is of quantity one and whose arguments are evaluated. These are the
  bodies whose ops are only constants and constructors of plain values,
  which `EvaluateDelay` hoisted (`OpsClosures.cpp:95-118`), which goes.
  Any other suspension is a lifted function `G` of its captures alone,
  one result `T`, and `idr.suspend @G(<captures>) : (<capture types>) ->
  !idr.lazy<T>`.
- **Linear captures:** a closure or suspension that captures a value of
  quantity one is linear itself: Emit writes `idr.lin.enter` of it at
  once (`!idr.lin<...>`), and holds that value at quantity one; a plain
  use writes `idr.lin.use`, as for any linear value. This is the
  verifier's rule (`Grades.h:100-117`) as a type: the value is used once.
- **Names from content (D18, C21):** `F`'s symbol is `contentName owner
  "lam" key` and `G`'s `contentName owner "delay" key` (C21's
  `<owner>.<kind>.<hex16>`), where `owner` is the symbol of the
  translated function the body is in, and `key` is `genericForm` of the
  lifted function with `sym_name` empty and its values numbered in
  definition order (parameters `%0`... then each result in order). Two
  bodies of one owner with one key are one function: it is written once
  and both ops name it. Two keys on one name are an internal error,
  never a merge (0006 §4.5).

### 6. Data types (D29, C01)

- `DataT d` is written as C01's identified data type of `d`, through
  C01 §4a's generated constructors: `Idr (DataType d.name body)` with
  `body = Just (MkIdrSum kind ctors (Just (d.key.origin,
  d.key.arguments)))` or `Nothing` (below). `ctors` are `d.cons` in tag
  order, each `MkIdrCtor c.id.name (binderType of each field) False`.
  `kind` is the one fact the registry gives the type (C20): `BaseList`
  when its constructors play `ListNil` and `ListCons`, `InPlace` when
  `d.promise` is `Just InPlace`, `Plain` otherwise; the frontend makes no
  `Closures` or `Memo` sum (C01 §6). A `Box` instance is `Idr (BoxType
  <the data type>)` (D29: boxing is the value's type alone).
- Spelling follows C01's printer: the body wherever the type's text
  appears, except inside its own body, transitively, where its
  identifier alone names it (LLVM's identified structs,
  `M/lib/Dialect/LLVMIR/IR/LLVMTypeSyntax.cpp:143-199`). Emit builds the
  `MlirType` with the stack of types whose bodies it is spelling. In the
  bytecode each distinct spelling is one entry and every use its number
  (0008 §4.9).
- Ops name a constructor by its name within its value's type (C02's
  `idr.con`, `idr.field`, `idr.take`, `idr.reuse`, `idr.dest.of`
  builders); a match's case keys are the constructors' flat names, as
  today (`Bodies.idr:285`).

### 7. Types and arrays (0003 §2, §4.1, D4, D13, D14, D39)

- `TensorT ds e` is `tensor<ds x E>` (`RankedTensorType ds E`), never
  with an encoding; `MemRefT ds e` is `memref<ds x E, #idr.world>`
  (`MemRefType ds E (Just (Idr WorldSpaceAttr))`, C11 §1: every memref the
  frontend writes is an array a world orders). Quantity one is
  `!idr.lin<...>` around a tensor, as for every type
  (`Emit/Types.idr:59-63`).
- At every slot whose type differs from the value's only in which
  dimensions are static (a call's argument, a constructor's field, a
  return, a match's join, a closure's parameter and result, a loop's
  carried value) Emit writes `tensor.cast` to the slot's type (0003 D39);
  a tensor that differs from a tensor slot otherwise is an internal error.
  `idr.tie_shape`'s result is its operand's type, so a `Tie` needs no cast.
- C20's array terms are written in their sequential meaning, upstream
  ops only (0003 §4.1, D13) through `Emit.Tensors`: a dimension is
  `arith.constant` of a static extent or `tensor.dim`; an element read
  `tensor.extract`, a cell read `tensor.extract_slice`; a write
  `tensor.insert` or `tensor.insert_slice`; a new array `tensor.empty`
  and an `scf.for` nest inserting each element; a fold along the last
  axis an `scf.for` carrying the accumulator in `iter_args`, a scan the
  same loop inserting each accumulator; `take`, `drop` `extract_slice`;
  `++` `tensor.empty` and two `insert_slice`; `reshape`
  `collapse_shape` then `expand_shape`; `pad` `idr.nat.to_extent` of the
  total then `tensor.pad`; a tie `idr.tie_shape` (C11 §3, §4). Sizes are
  `arith` on `index` with `nsw nuw`. A coordinate becomes `index` at its
  access, unguarded (0003 D4): `idr.big.to_int` then
  `arith.index_castui`, and back `arith.index_castui` then
  `idr.big.small` (C11 §2); an extent at an allocation, guarded, through
  `idr.nat.to_extent` (C11 §2). Every loop is C11 §3's `scf.for` from 0 by
  1, without `unsignedCmp`. A body
  that never returns in an `scf.for` ends in `scf.yield` of `ub.poison`
  of each carried type, `scf.for`'s block needing `scf.yield`.
- A world-ordered tabulation (C20's `TabulateIO`) is the nest of
  `tabulate` carrying the world too; the body's `IORes` is taken apart by
  an `idr.match` of its one constructor yielding the element and the
  world; its value is the `IORes` of the array and the last world.
- A cell whose size its type leaves dynamic has no size before the first
  cell is made: a `Tabulate` or `TabulateIO` of such cells is an internal
  error until C20 gives the cell's extents (a seam, reported).
- An array of records (C20's `ColumnsT k ds r`, 0003 D44) is written
  one-to-N, as C20 §10 states: one value per field of `r`'s constructor,
  in field order, nested columns flattened depth first, wherever the type
  stands (parameters, results, block and region arguments, constructor
  fields, captures, operands, loop-carried values); a value of quantity
  one is each column at quantity one. In Emit a value is held whole, as a
  constructor a match took apart, or as its columns (`Monad.Parts`:
  `Whole | Taken ConId (List Val) | Columns (List Val)`), and
  `Types.heldTypes`, `operandsOf`, `fromNames` and `freshVal` give its
  types, operands, and values from result or argument names. A read
  gathers (one `tensor.extract` or slice per column, then `idr.con`); a
  write scatters (the record's fields, by `idr.field` or as a match took
  them apart, each into its column); an extent is the first column's;
  take, drop, join, reshape and pad act on every column (pad's cell taken
  apart); a tie ties every column's leading dimensions to the same sizes;
  a new array is a `tensor.empty` per column. An ordered array of records
  is one memref per column: a new one fills each with its field of the
  fill, a get loads each and builds the record, a set stores each field,
  the world threaded through them, the guard checked once on the first
  column. A suspension of an array of records has no type
  (`!idr.lazy` holds one value): an internal error, C20 permitting one.
- World-ordered arrays (`MemRefT`) are written as today
  (`Emit/Operations.idr:157-273`), their guards kept (0003 §13).

### 8. Retired by this contract (U15 deletes them)

`Emit.idr`'s text writer and `format`; `MLIR.idr`'s `Format`, the
declarative branch of `frame`, `showModule`, `moduleText`, `topLevel`,
the rank-only `MemRefType Nat`; `Emit/Index.idr`'s `claim` and
`claimAll`; `Emit/Declarations.idr`'s `dataDecl` and its `break_last`;
`Emit/Bodies.idr`'s `idr.lambda` and region `idr.delay` emission,
`deferred`, `regionSignature` and the region-primitive case. Their
predecessors in C++ (`idr-isolate`, `EvaluateDelay`) are U02's and
U01's.

### 9. Consumers by lane

- U01: the generated `Syntax/*` and `Dialect/*` call section 3's
  `IdrisMLIR.MLIR` and `MLIR.Text` names; the identified type's
  generated constructor and printer (C01), the `idr.delay %value`,
  `idr.con` and `idr.func` builders (C02) are what Emit calls; the
  generated `printOp`s have no reader after this contract.
- U02: the module is in symbol form with no region form of a closure or
  suspension, every closure- or lazy-typed value made by `idr.closure`,
  `idr.suspend`, `idr.delay %v`, or carried along a declared edge.
- U06: the driver parses the dialects of section 4 (C12).
- U07: `Artifacts.cpp` names the module `<base>.mlirbc`.
- U14: `Frontend/Program.idr` calls `emit`; `Types.idr` imports `Dim`;
  the ipkg lists section 3's modules.
- U17: `quantities-kept=<file>` reads the `.mlirbc` (C24); dialect
  fixtures are in this form.
- U18: `tests/compiler/dialect-syntax` reads the samples as bytecode
  (`syntax-samples OUT.mlirbc`, one argument: the module of every type,
  attribute and op sample, written by `MLIR.Bytecode`; every function
  private, a fragment; its expected print is NEEDS-ACCEPTANCE);
  `handoff-round-trip`, `handoff-readable` and `module-location` read the
  `.mlirbc`; a spec check that no `idr.lambda`, region `idr.delay`,
  `idr.data` or discardable attribute is in any emitted module.
