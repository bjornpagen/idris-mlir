# U15 — Emission: closures in symbol form, identified types, tensors, a bytecode handoff

## Permitted outcome
1. Mandatory. The frontend's handoff is MLIR bytecode: `IdrisMLIR.Emit.emit`
   writes one bytecode file by C22's exact encoding through the new
   `IdrisMLIR.MLIR.Bytecode`; no op text is written to the handoff.
2. Mandatory. Every lambda is a private `idr.func` named from content and
   an `idr.closure` of it over its captures; every suspension is
   `idr.delay %v` when its body is evaluated, else an `idr.func` and an
   `idr.suspend`; a closure or suspension holding a linear value is
   entered linear at once (C22 section 5). No `idr.lambda` and no region
   form of `idr.delay` is written.
3. Mandatory. Data types are C01's identified types with their bodies,
   spelled by C22 section 6; no `idr.data` or `idr.ctor` op is written;
   a box is `!idr.box` around the identified type.
4. Mandatory. No discardable attribute is written (no `idr.program`),
   and a function carries only the properties C22 section 4 lists.
5. Mandatory. Symbols: a translated function's is its id's name (C20),
   interned once, a repeat an internal error; the `'n` repeat counter is
   gone. A lifted function's is C21's `contentName` of its owner, its
   kind and its key; one function per distinct key per owner.
6. Mandatory. `MLIR.idr` writes ranked tensors and memrefs with static or
   dynamic dimensions (`Dim`), `DenseI64ArrayAttr` and `DictionaryAttr`,
   and gives each attribute's and type's dialect; the rank-only memref
   goes.
7. Mandatory. C20's array terms are written as 0003 §4.1's upstream ops
   through `IdrisMLIR.Emit.Tensors`, with `tensor.cast` at slots that
   differ only in static dimensions (C22 section 7).
8. Mandatory. `syntax-samples` writes its sample module as one bytecode
   file through the same writer, and still exits 1 naming every
   mnemonic of a generated sum no sample has.
9. Consumer adaptations (Mandatory): to C01 and C02 (the identified
   type's constructor, `idr.delay %value`, constructor references, the
   function's properties), to C11 (`idr.tie_shape`, the natural and index
   conversions), to C20 (`Ty`, the array terms, `Con.role`,
   `Data.promise`, ids as symbols), to C21 (`contentName`), all inside
   this lane's writes.

## Owner / exclusive writes
ownership.json's U15 entry, every path:
- `SRC/Emit.idr` (`compiler/src/IdrisMLIR/Emit.idr`): the bytecode
  writer replaces the text writer and `format`.
- `SRC/Emit` (`compiler/src/IdrisMLIR/Emit/`): `Bodies.idr`,
  `Declarations.idr`, `Index.idr`, `Monad.idr`, `Operations.idr`,
  `Types.idr` change; `Closures.idr` (lambdas and delays as functions:
  captures, renumbering, keys) and `Tensors.idr` (the array terms) are
  new.
- `SRC/MLIR.idr` (`compiler/src/IdrisMLIR/MLIR.idr`): C22 section 3.
- `SRC/MLIR` (`compiler/src/IdrisMLIR/MLIR/`): `Text.idr` unchanged;
  `Bytecode.idr` new.
- `SRC/SyntaxSamples.idr` (`compiler/src/IdrisMLIR/SyntaxSamples.idr`):
  the samples written as bytecode, the samples of the new types and
  attributes added.
- `compiler/syntax-samples.ipkg`: unchanged unless a module it builds
  needs naming.

Nothing is deleted whole.

**Excluded:**
- `compiler/idris-mlir.ipkg` and everything under `SRC/Frontend`,
  `SRC/Registry`, `SRC/Term.idr`, `SRC/Types.idr`, `SRC/Ids.idr`,
  `SRC/Loc.idr`, `SRC/Facts.idr`, `SRC/Graph.idr` (the ipkg's module
  list, `Program.idr`'s call of `emit`, `Dim`'s importers, the hash):
  U14.
- `SRC/Dialect`, `SRC/Syntax`, `SRC/Rule.idr` (generated) and
  `TL/idris-mlir-tblgen.cpp` (`foreign/idr/tools/`): U01. Never edit a
  generated module by hand.
- `tools/dialects.sh` (the `tensor` and `scf` lines): the coordinator.
- `IDR/Driver/Artifacts.cpp` (the `.mlirbc` name): U07.
  `IDR/Driver/Run.cpp` (the dialects it parses with): U06.
- `IDR/Transforms/Isolate` and `INC/Transforms/Isolate.h`: U02.
  `INC/IR/*`, `IDR/IR/*` (the identified type, `idr.delay %value`): U01.
  `INC/IR/IdrArrayOps.td` (`idr.tie_shape`): U11.
- `tests/` (the samples test, the handoff tests, fixtures): U17, U18.

## Read first
- `contracts.md`: C22 (yours, whole), C01, C02, C11, C20, C21, C24's
  "How `@f` finds its functions".
- 0004 (`proposals/0004-compile-time/README.md`): §2.7 (lines 359-431);
  §4 stage 1 (lines 674-777) and stage 2 (lines 779-786); §6's rows at
  lines 1245 (Emit's writer of the cycle mark), 1252 (the region round
  trip), 1260 (the program mark) and 1265 (names from counters); D18,
  D28, D29, D36, D37 (lines 1581-1588, 1647-1672, 1723-1732).
- 0008 §4.9 and §4.10 (`proposals/0008-data-oriented-frontend.md:404-548`):
  the attribute and type table, the lambda key, instance symbols.
- 0006 §4.5 (`proposals/0006-sharded-whole-program-compiler.md:447-466`):
  the name's width and the collision rule.
- 0003 (`proposals/0003-typed-apl/README.md`): §2's table (lines
  227-266); §4.1 (lines 611-648); §4.3 (lines 666-736); §4.5 (lines
  791-846); §13 (lines 1463-1480); D4, D13, D14, D39, D40 (lines 1796,
  1814-1817, 1923-1931).
- `array-drafts.json`'s FRONTEND entry, §1, §2 and §7 (the earlier draft
  of `Dim`, the tensor printer, the emission of each primitive and
  `fit`): what still holds is in C22; its `idr-raise` is now
  `idr-structure-loops`, its proposal number 0007 is 0003, and the
  frontend writes no `scf.parallel` in stage 1.
- The lane's sources, whole: `Emit.idr` (`:45-100`), `Emit/Bodies.idr`
  (`:160-170` deferred, `:330-358` lambda and delay, `:366-386` region
  primitives), `Emit/Declarations.idr` (`:31-79`), `Emit/Index.idr`
  (`:16-84`), `Emit/Monad.idr`, `Emit/Operations.idr` (`:51-64` coerce,
  `:157-273` guards, `:407-415` con), `Emit/Types.idr` (`:29-68`),
  `MLIR.idr` (`:36-63` types, `:69-105` attributes, `:207-329` text),
  `MLIR/Text.idr`, `SyntaxSamples.idr`.
- Their callers and the generated code that calls them:
  `Frontend/Program.idr:59-79, 196`; `Types.idr:78-140`;
  `Term.idr:84-130, 306-362`; `Dialect/Idr.idr:1-60, 1060-1100,
  2027-2045`; `Syntax/Idr.idr:90-150`.
- What symbol form replaces: `IDR/Transforms/Isolate/Isolate.cpp:47-176`
  (captures, order, the function's properties and location, the linear
  enter), `IDR/IR/OpsClosures.cpp:95-118` (`EvaluateDelay`), `:135-217`
  (the closure and suspension verifiers), `IDR/IR/Grades.cpp:136-158`
  (`holdsLinear`, `takenOnce`).
- Upstream bytecode, under `.toolchain/build/llvm-project` (`M` is
  `mlir`): `M/docs/BytecodeFormat.md`; `M/include/mlir/Bytecode/Encoding.h`;
  `M/lib/Bytecode/Writer/BytecodeWriter.cpp:239-330, 363-389, 639-659,
  739-1120`; `M/lib/Bytecode/Writer/IRNumbering.cpp:130-470`;
  `M/lib/Bytecode/Reader/BytecodeReader.cpp:462-499, 1232-1310,
  1314-1370, 1530-1554, 1905-1989, 2080-2160, 2376-2800`;
  `M/lib/IR/Operation.cpp:32-47`; `M/lib/AsmParser/Parser.cpp:1585-1630`;
  `M/lib/Dialect/LLVMIR/IR/LLVMTypeSyntax.cpp:143-230` (identified
  structs' cyclic spelling); `upstream/03-bytecode-deferred-quadratic/README.md`.
- base: `third_party/Idris2/libs/base/Data/Buffer.idr:37-460`,
  `System/File/Buffer.idr:45-66`; the registry's entries for them,
  `Registry/Primitives.idr:237, 450-505`.

## Fixed decisions
1. **The writer.** `IdrisMLIR.MLIR.Bytecode` holds an abstract `Writer`:
   a growable byte buffer per section over `Data.Buffer`, written byte by
   byte with `setBits8` (no word store, so no byte order is assumed),
   and the interning tables (strings, dialects, op names, attributes,
   types) in `IORef`s of `SortedMap` keyed by text. Numbers are given in
   first use. `writeTopLevel` encodes one top-level op into the module's
   body as Emit finishes it, so no Idris value of the whole module is
   held; `finish` writes the header and the sections of C22 section 2.
2. **Properties and attributes.** An op's properties are one
   `DictionaryAttr` written by its text, through the unregistered form
   (op names flagged 0); its discardable attributes another (none in an
   emitted module; the samples have some). Never the native property
   encoding.
3. **Isolation is position.** The module op and the ops of its block are
   isolated; nothing nested is. The writer does not inspect traits.
4. **Value numbers** follow C22 section 2. An operand is found by its SSA
   name in the names of the regions that hold it; SSA names are unique
   within a function, as Emit makes them (`Emit/Monad.idr:34-39`); a
   multi-result op's results are `%r#i` and a single result `%r`
   (`Operations.idr:452-462`).
5. **Lifting is from the emitted body.** Emit writes a lambda's or a
   delay's body into a collected block (`Monad.collect`), then
   `Emit.Closures` computes its captures from the statements (C22 section
   5), builds the function, renumbers its values in definition order and
   takes the key from `genericForm`. The capture set is therefore exactly
   what the body uses, constants never among them. The lifted function
   goes into the state's list of functions of the current owner; the
   state's table of the owner's keys gives one function per key.
6. **The evaluated suspension** is decided on the term, before anything
   is written, by C22 section 5's rule; it is EvaluateDelay's rule,
   which then has no other home.
7. **A linear closure** is entered at once (C22 section 5): `Val.use` is
   `One` for it, and `coerce` writes the use where a plain one is needed.
8. **Symbols** are the ids' names (C20). `Emit/Index.idr` keeps the
   lookup tables of data, constructors and functions and interns every
   symbol it writes into one set; a second function on a symbol is
   `internal`.
9. **Types.** `Emit/Types.mlirType` maps C20's `TensorT` and `MemRefT`
   (in `#idr.world`, C11 §1) through `Dim`, `DataT` through C01's
   identified type with the list of the data ids whose bodies are being
   spelled; it is total by a fuel of one body per data instance
   (`Index.dataCount`).
10. **Arrays.** `Emit/Tensors.idr` holds `indexConst`, `dimValue`, the
    coordinate and extent conversions (C11), `mixed` (operands and the
    static list with `dynamicExtent`), `forLoop` (an `scf.for` from 0 to
    a bound by 1 with iter args; a body that never returns yields
    `ub.poison`), and `fit` (`tensor.cast` at a slot that differs only in
    static dimensions, then `coerce`). `Bodies.alg` calls them for C20's
    `Tensor`, `Tabulate`, `TabulateIO`, `Reduce` and `Tie`. An array of
    records (`ColumnsT`) is held as its columns (`Monad.Parts`), one
    value per field, and every one of these acts on each column as C20
    §10 states; `Operations.effect` does the same for ordered ones.
11. **The samples.** `syntax-samples OUT` writes one file. The op samples
    keep one op per generated builder shape the frontend uses, and add an
    `idr.closure`, an `idr.suspend`, an `idr.delay %v` and a tensor op;
    the type and attribute samples cover every constructor of the
    generated sums and of `MlirType` and `MlirAttr`.

## Inputs
- C01: the identified data type's generated `IdrType` constructor (its
  identifier, its body with constructors in tag order, field types,
  kind, `instance`, role, promise), the identifier-only form for a
  spelling inside its own body, and `!idr.box` over it.
- C02: the generated builders after the cutover: `idr.delay` over one
  value, `idr.con` and the other constructor ops naming a constructor by
  its name within the type, `idr.func` with exactly C22 section 4's
  properties, no `programDiscardable` or `stackDiscardable`.
- C04: none read; emission refuses nothing, every failure is internal.
- C11: `idr.tie_shape`'s builder, and the natural-to-index (coordinate,
  unguarded), natural-to-extent (allocation, guarded) and
  index-to-natural conversion builders.
- C20: `Ty` (`TensorT`, `MemRefT`, no `ArrayT`), `Term`'s `Tensor`,
  `Tabulate`, `TabulateIO`, `Reduce`, `Tie` and the `TensorOp` they carry, `Con.role`,
  `Data.promise`, `FnId.name` and `DataId.name` as symbols, the deletion
  of `Region`.
- C21: `contentName : (owner, kind, key : String) -> String` in
  `IdrisMLIR.Ids`, `<owner>.<kind>.<hex16>` of XXH3-128's low 64 bits
  over the key's UTF-8 bytes.
- C12: nothing; C24: the location rule C22 section 4 keeps.

## Outputs
- C22, whole: the file and its encoding, the `IdrisMLIR.MLIR` and
  `IdrisMLIR.MLIR.Bytecode` declarations, `emit`, the module list, what
  the module holds, the symbol form, the data type spelling, the array
  emission. Consumers: U01, U02, U06, U07, U14, U17, U18 (C22 section 9).

## Implement
- **`MLIR.idr`.** `Dim`, `RankedTensorType`, `MemRefType (List Dim)`;
  `DenseI64ArrayAttr`, `DictionaryAttr`; `typeDialect`, `attrDialect`,
  `dynamicExtent`; `genericForm` (today's generic `frame` and
  `opText`, without locations); delete the rest of section 8 of C22.
  The module comment says the handoff is bytecode, attributes and types
  written as their assembly.
- **`MLIR/Bytecode.idr`.** The writer of fixed decisions 1 to 4: the
  buffer (`newBytes`, `byte`, `varint`, `string`, `bytes` appending
  another buffer, `size`), the tables, `encodeOp`, `encodeRegion` with the
  value base and the name scope, `writeTopLevel`, `finish`. Each failure
  returns `Left` with a message naming what is missing.
- **`Emit/Monad.idr`.** `ES` gains `owner : String` (the symbol of the
  translated function being written), `lifted : SnocList Statement` (its
  lifted functions, finished order) and `keys : SortedMap String String`
  (key to symbol, and symbol to key, of the owner's lifted functions).
- **`Emit/Closures.idr`.** `captures` (first use, outside definitions)
  and `renumbered` (values in definition order), both over `MLIR.idr`'s
  `walkRegion` and `renameRegion`, the one traversal of the contract
  syntax, so no op is taken apart or rebuilt here; `lift : Loc -> (kind :
  String) -> ... -> E (String, List Value)` building the function, its key
  and symbol, writing it once into `lifted`.
- **`Emit/Bodies.idr`.** `LamF`: collect the body, lift, `idr.closure`,
  the linear enter. `SuspendF`: the evaluated test; `idr.delay %v` or
  collect, lift, `idr.suspend`, the linear enter. Delete `deferred`,
  `regionSignature` and the `RegionF` case. The array cases call
  `Emit.Tensors`. `operands` uses `fit`.
- **`Emit/Declarations.idr`.** `function` returns the function and the
  owner's lifted functions, in order; no `breakLast`; `dataDecl` deleted.
- **`Emit/Index.idr`.** Symbols from the ids; the claim counter deleted;
  `dataCount`.
- **`Emit/Types.idr`.** As fixed decision 9.
- **`Emit/Operations.idr`.** `con` through C02's builder; the guards of
  world-ordered arrays on `MemRefT`; `IndexBelow` and its guard deleted
  with C20.
- **`Emit/Tensors.idr`.** As fixed decision 10, one function per C20
  array term.
- **`Emit.idr`.** `emit` through `MLIR.Bytecode`: a writer, each
  function and its lifted functions given to `writeTopLevel` as each is
  finished, the module op without attributes at the root's location
  given to `finish`. The module comment says what C22 says.
- **`SyntaxSamples.idr`.** As fixed decision 11.

Failure paths: every Emit failure is `Left` with a message, which
`Program.idr` reports as the compiler's internal error with the Core
(`Program.idr:66-79`); none is `unsupported`.

## Delete
- `Emit/Bodies.idr`: the `idr.lambda` and region `idr.delay` emission
  (`:330-358`), `deferred` (`:160-170`), `regionSignature` (`:172-179`)
  and the `RegionF` case (`:366-386`), which fed `idr-isolate`'s round
  trip; Isolate's naming `.lam<n>`, `.delay<n>` has no counterpart here.
- `Emit/Declarations.idr`: `dataDecl` (`:31-46`), the `breakLast`
  argument and the doc naming `break_last` and `idr-loop-breakers`
  (`:48-54, 73`), and the import of `Registry.Libraries` for `BreakLast`.
- `Emit.idr`: `programDiscardable` (`:91-93`), `format`, `written`,
  `top`, the text writer.
- `Emit/Index.idr`: `Taken`, `claim`, `claimAll` (`:27-55`), the `'n`
  repeats.
- `MLIR.idr`: `MemRefType Nat MlirType` and its printer (`:47, 61`),
  `Format`, the declarative branch of `frame`, `showModule`,
  `moduleText`, `topLevel`.
- `Emit/Operations.idr`: the `Below` guard, `guardOf IndexBelow`, `prim
  ix l IndexBelow` (`:174, 214, 266, 400-404`), the `ArrayT` cases.
- `SyntaxSamples.idr`: the two-file text output, `declarative`,
  `generic`, the `idr.lambda` and region `idr.delay` samples, the
  `idr.data` and `idr.ctor` samples, `programDiscardable`'s absence
  aside.

## NOT TO DO
- Do not edit the generated `SRC/Dialect/*`, `SRC/Syntax/*`,
  `SRC/Rule.idr` or `TL/idris-mlir-tblgen.cpp` (U01), even where a
  builder is missing: report it as a seam against C01, C02 or C11.
- Do not write, take apart or rebuild an op with `MkOp` anywhere but
  `MLIR.idr`: an op is made by its generated builder, and a walk over
  values is `MLIR.idr`'s; an op's shape is said once, in ODS.
- Do not keep a text handoff, a text mode, a flag or an environment
  variable choosing text or bytecode, or a second writer: text is
  MLIR's print of the file.
- Do not write the native property encoding, dialect versions,
  resources or use-list orders; do not mark a nested op isolated.
- Do not name a lifted function from a counter, from its position in
  the owner, or from its source location; do not widen a name on a
  collision.
- Do not emit `linalg`, `bufferization`, `affine` or `scf.parallel`, a
  constant tensor, `idr.scan` or `idr.scatter` (0003 D13, D16, D40).
- Do not add a guard to a typed access or drop a world-ordered one.
- Do not touch `Frontend/` or the ipkg (U14), the driver (U06, U07), or
  `idr-isolate`'s files (U02); Isolate's deletion is U02's.

## Tempting partial solutions
- **Keeping regions and letting `idr-isolate` outline them.** Rejected:
  the round trip is what 0004 deletes. Acceptance case: no emitted module
  holds `idr.lambda` or a region `idr.delay` (U18's spec check).
- **Computing captures from the term's free variables.** Rejected: a
  variable read only where Emit writes nothing (a match with no possible
  case) would become a parameter, a linear one unused. Acceptance case:
  the captures are what the body's statements use.
- **Keying a lifted function by its SSA text or with its locations.**
  Rejected: the key would move with every edit above it in the owner and
  with every line shift of the file. Acceptance case: U18's
  name-stability fixture keeps every lifted symbol of an unedited
  definition.
- **Writing ops as registered with merged inherent attributes.**
  Rejected: an inherent attribute of the wrong type is dropped silently
  by `setInherentAttr`; the generic form's conversion is the one the
  text parse uses. Acceptance case: a sample with every property kind
  reads back with its properties.
- **A per-op encoding of properties generated from ODS.** Rejected: a
  second copy of each op's property order that a toolchain bump moves.
  Acceptance case: no property order appears in the writer.
- **Keeping `EvaluateDelay`'s hoisting for later passes and writing
  every delay as a function.** Rejected: the evaluated suspension is the
  value said once (D37); a delay of a constructor would become a memo
  label. Acceptance case: `memo-shared-stream` and `stream-share` keep
  their outputs and live-cell marks.
- **Keeping `p'n` for symbols that print alike.** Rejected (0008 §4.10).
  Acceptance case: no counter in `Emit/Index.idr`; a repeat is internal.
- **Interning bytecode entries by structural equality of `MlirType`.**
  Rejected: text is what the entry is; one text, one entry.

## Acceptance
- Source review: no `lambdaOp`, region `delayOp`, `dataOp`, `ctorOp`,
  `programDiscardable`, `breakLast`, `claim`, `MemRefType Nat`,
  `showModule`, `moduleText` or `topLevel` in the lane's files; no
  `MkOp` in `Emit.idr`, `Emit/`, `MLIR/` or `SyntaxSamples.idr`; no module
  named after an input that has already erased facts (`Lifted`).
- The private-build-dir typecheck of `compiler/idris-mlir.ipkg` and
  `compiler/syntax-samples.ipkg` passes for every module of this lane,
  or fails only where a generated builder or a C20 or C21 declaration
  is not yet in the tree, each named as a seam.
- On the owner's machine (for the handoff, not run here): every program
  of `tests/programs` keeps its expected output; `idris-mlir-opt` reads
  every emitted `.mlirbc` and the samples' file and verifies them;
  `tests/compiler/dialect-syntax` passes on the bytecode samples; the
  bytecode read time on the stage-0 module is recorded against the
  11.7 s text parse (D36), and the attribute and type section's size
  beside it (0008 §4.9's O0); determinism at 1, 2 and 8 threads (the
  file is a function of the program).

## Stop and return
Done when every Mandatory outcome is in the source and the private
typechecks pass or fail only on named seams. Return the common
obligations' handoff, with the seams by file, declaration and contract:
the regenerated builders of C01 and C02, C11's builders, C20's terms
and `Ty`, C21's `contentName`, the `tensor` and `scf` lines of
`tools/dialects.sh`, `Artifacts.cpp`'s extension and the ipkg's module
list. Then stop.
