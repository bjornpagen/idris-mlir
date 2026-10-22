<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane idris-dialect-side: the Idris side's view of the dialect

*Written (2026-10-21), at e96bb991 plus the working tree's uncommitted
proposal. Scope: `foreign/idr/tools/idris-mlir-tblgen.cpp`;
`compiler/src/IdrisMLIR/{Dialect,Registry,MLIR,Encoding,Emit,Syntax}/`,
`Registry.idr`, `MLIR.idr`, `Emit.idr`, `SyntaxSamples.idr`.*

## 1. Reading notes

### §0-§4

- Goal (§0 head): the cutover covers "the Idris side's generated mirror of
  the dialect"; every `.td` definition churned, nothing in C++ restates an
  ODS fact. The same rule binds the Idris mirror: what it restates by hand
  is a second copy.
- §2 brief: 191 ops, 13 types, 10 attributes; `idris-mlir-tblgen`
  "generates the Idris side's view of the dialect from the same records"
  (citing b9d4d592: "the dialect's table is one ODS record on both
  sides"). The op surface (§2's list) is what `Dialect/Idr.idr` mirrors;
  every rename §5.8 proposes lands here.
- §2: `tools/` is 3,450 lines, of which `idris-mlir-tblgen.cpp` is 3,255
  (measured below): the custom backend is nearly all of `tools/`.
- §2: `Idr_Runtime<"symbol">` ties a primitive op to its runtime function.
  The Idris side does not read the symbol (checked in §3): it builds the
  op, and the registry's hooks (AGENTS.md's `Faster`) name the op by its
  generated primitive constructor.
- §3: walls are all in the C++ pipeline; none is on the Idris side's
  writing of the module, but the stage-1 module (71 MB of MLIR, proposal
  0001) is written by the frontend, so the format the Idris side writes
  (bytecode, §2) is on that path.
- §4: one fact, one place; declare, don't write; hard cutover.

### §5.1 mlir-analysis

- Nothing in this subsystem runs a solve. Bears indirectly: F3 (every
  attribute or type created on a hot path grows the context): the
  frontend's output decides how many distinct attributes and types the
  parser uniques (locations, `#idr.types`, string attributes); D2/D3
  (what effects buy upstream) decides which effect facts the Idris side
  needs to see at all (none today, as far as the emitter reads: checked in
  §3 below).
- A7: `loadBaselineAnalyses`; not ours.

### §5.2 mlir-ods (read most carefully)

- **F1** (read): a backend is `bool(const RecordKeeper&, raw_ostream&)`
  registered with `GenRegistration`, run by `MlirTblgenMain`;
  `tblgen-to-irdl` (28-line main, 583-line backend) is "the shape of
  `idris-mlir-tblgen`".
- **F2** (read): the `mlir::tblgen` wrappers (`Operator`, `Argument`,
  `Attribute`, `Property`, `AttrOrTypeDef`, `Interfaces`, `SideEffects`,
  `Trait`, `EnumInfo`, `Constraint`, `Format`) compute the derived facts
  once (flattened traits, decorators, variadic segments, inferred result
  types); "a backend that reads raw `Record` fields recomputes those facts
  and drifts from what the C++ sees". `OpPythonBindingGen.cpp` (1,532
  lines) is the closest model of a foreign-language view.
- **F3**: op families generated from lists (`llvmBuilder` fields,
  linalg OpDSL, arith's TableGen classes).
- **D3/D4**: properties and `EnumInfo` (one record → C++ enum, stringify,
  symbolize, attr/prop/type parameter; the Python generator reads the same
  record). The Idris mirror should read `EnumInfo` the same way.
- **D1**: `TypeDef` parameters and `assemblyFormat`; **D2**: a mutable type
  is always written as text in bytecode
  (`BytecodeWriter.cpp:893-900`); **G1**: attributes/types with no
  `-gen-bytecode` encoding go as text; our patches 03, 25 are in the
  reader.
- **M7**: `Idr_Runtime<"symbol">` = a `NativeOpTrait` injecting
  `getRuntimeSymbol()`, a `RuntimeFunction` interface, one
  interface-rooted lowering pattern, "and `idris-mlir-tblgen` reading the
  same record".
- **M8**: op families from lists (the ~60 platform ops, signedness
  families); many ops vs one op with an enum is §5.8's.
- **M12**: "`idris-mlir-tblgen` should read the wrappers": one
  `GenRegistration` per Idris view, in a tool on `MlirTblgenMain`.
- **M14**: bytecode: types and attributes as text unless `-gen-bytecode`.
- Recipe rows bearing here: 12 (runtime symbol), 14 (closed sets as
  `EnumInfo`), 15 (grade as `TypeDef` with `EnumParameter`), 21 (bytecode
  encodings), **22 (the Idris side's view: `idris-mlir-tblgen` over the
  wrappers; deletes "hand mirrors")**, 23 (families from lists).
- Design 4 (ranked 4th): "`idris-mlir-tblgen` on the wrappers, op families
  from lists ... Deletes: the backend's own reading of raw records,
  hand-written family members."
- **W5** (mine): does `idris-mlir-tblgen` read raw `Record` fields or the
  wrappers; what does it recompute? **W8** (mine, shared with
  driver-pipeline): does any stage write or read bytecode; are our
  attributes and types in it as text?

### §5.3 llvm

- **E1**: `!instances<T>`, `defset`, `foreach`, `assert` compute and check
  record sets in `.td` itself.
- **E2**: `GenericTable`/`SearchIndex`: the emitter lives inside
  `llvm-tblgen`, not a library, so a custom backend cannot link it.
- **E3** (read): `mlir-tblgen` is a driver over a registry; `MlirTblgenMain`
  is the `main` a custom tool links "to get every upstream generator plus
  its own"; backends read through the typed wrappers "so a backend that
  mirrors the dialect into another language reads traits and effects as
  data, not by matching strings in `.td` text".
- **E4**: X-macros are TableGen's poor relation; "an enum and a table
  generated from records, which both C++ and any other mirror (our Idris
  side) read".
- **M10**: `idris-mlir-tblgen` should be a `GenRegistration` in a tool on
  `MlirTblgenMain`, reading traits and effects as typed data.
- **I8**: a list in C++ that mirrors records is generated.
- **Q-llvm-5** (owner; evidence from me): one TableGen tool, a
  `GenRegistration` on `MlirTblgenMain`, reading `Operator` and
  `SideEffect`, "so one tool generates both the C++ and the Idris mirror".
- A2/E5: no RTTI, no exceptions; LLVM's static-constructor rule
  (`GenRegistration` globals are tolerated in a build tool).

### §5.4 modular

- **F18** (read): `driver-tblgen` (1,686 lines) parses records into typed
  C++ views, validated with TableGen errors before any generator runs,
  generators registered by name in a `BackendRegistry`, the errors tested;
  a checksum of every dialect `.td` compiled into the compiler.
- **Design 9**: "`idris-mlir-tblgen` as parse-once": records into a typed
  model, validated with TableGen errors, errors tested; optionally a
  checksum of the `.td` records compiled into both the compiler and the
  generated Idris mirror, "so two artifacts from different records are
  refused when they meet". One fact stays one place; the checksum only
  detects a stale copy.
- F12: Modular's ODS: 380 assembly formats against 17 custom; families as
  ODS base classes (`POP_ArithmeticBinaryOp`).
- F17 (forbidden by our rules): "a curated dialect list to keep in sync by
  hand" (`KGENVerifier.cpp:32-50`): the shape of any hand list on our Idris
  side.

### §5.5 cxx26 (read most carefully)

- A1/A2: no reflection, no contracts, partial expansion statements at the
  pin; concepts, `consteval`, deducing `this`, pack indexing, binding
  packs, `= delete("reason")` present. A6: all of it works under
  `-fno-rtti -fno-exceptions`.
- **D1** (the boundary rule, rank 1): over ops the set is open, dispatch is
  MLIR's; over our own C++ types the set is closed: sums and templates,
  never `isa`, `virtual` or a kind tag. In the tblgen backend all types are
  ours or `llvm::Record`, so its C++ falls under the "our own types" half
  (its ladders over `Record` classes are reads of TableGen records, open to
  the backend only as `isSubClassOf` string tests).
- **D2** (`match` over `std::variant`, banning `holds_alternative`/
  `get_if` outside it; finding 12: `std::visit` falls off a cliff past 11
  alternatives).
- **D4a** (read, the one directly on this lane): "A list over IR is
  generated ... `idris-mlir-tblgen` already reads every record ... An op's
  runtime symbol (`Idr_Runtime<"symbol">`), its refusal category, its
  effect row: each is emitted to C++ and to Idris from the one record,
  never typed into a C++ `switch`." D4b: a C++-only list is one
  `constexpr` table checked by `consteval`.
- **D9**: "None of it touches D4a: a fact about IR stays in ODS, because
  TableGen is what feeds both C++ and the Idris side. Reflection is less of
  a lever for us than it looks."
- 5.5.2: "every list it [reflection] would derive comes from TableGen when
  ODS describes the thing (it already holds the records, and
  `idris-mlir-tblgen` already reads them)".
- D8: `std::expected<T, Reason>` where the failure is data (a refusal's
  category, generated from ODS).
- Q1 (input to §8 Q1): D1's line; Q2: ban `std::visit`.

### §5.6 ecosystem

- **F2** (read): ClangIR's `CIRLoweringEmitter.cpp` (377 lines) walks
  `getAllDerivedDefinitions("CIR_Op")` and emits one lowering pattern per
  op from fields on the base class (`hasLLVMLowering`, `llvmOp`): "the
  fact 'this op lowers to that LLVM op' is one ODS field". 5.6.5 names it
  "a model for `idris-mlir-tblgen`".
- D6: IREE writes its analysis answer into a type and regrets the lossy
  mapping; the frontend's grades already are this on our side (the Idris
  side writes them; checked in §3).

### §5.7 library

- L3 / M6: interned, structural program tables built then frozen;
  "a structural type identity where today's is nominal (§5.8)". If §5.8's
  DS3 picks structural or indexed data types, the Idris side's printing of
  `!idr.data<@T>` changes with it (cost noted in §5).
- B3: no whole-module use-def chains; not ours.

### §5.8 dialect-design (read most carefully)

- **Summary** (1)-(5): one grade attribute inside the type; one op per
  computation, enum where variants share structure; consumption as
  `Read`+`Free`; IO ordered by effects on a resource tree, not tokens;
  Mojo erases lifetimes in one step after checking.
- **N1** (naming): `family.verb`, every op in exactly one family named
  after its type or resource; today's prefixes are partial. **N2**: no
  implicit semantics in names; candidates `put_sint/uint/double`, `show_*`,
  `int_head_s/u`, `double_head`, six stat times, eight clocks.
- **T2/T4/DS1**: `!idr.g<T, #idr.grade>` with one enum of legal grades and
  a `GradeAttrInterface`; unrestricted grade = bare `T` (T3). The Idris
  side writes grades today (`Emit`/`Encoding`); DS1 changes the syntax and
  the set the Idris side must be able to write. DD-Q1 (normalize
  `!idr.lin<i64>` to `i64`?).
- **T6/DS2**: function types carry conventions and effects; DS2.1 deletes
  `!idr.world`, `world.new`, world operands. The frontend threads the world
  today; DS2.1's cost lands in `Emit` (the world operand on every IO op and
  call it writes) and in the dialect mirror (`Dialect/Idr.idr`).
- **DS3**: recursive data types: immutable table on `program` (DS3.1),
  identified mutable types (DS3.2), structural with de Bruijn (DS3.3).
  The Idris side writes the table today (`#idr.types`); DS3.1 is closest
  to what it writes.
- **DS4** (first mapping, conjecture): `check.*` five ops into one
  `idr.check %cond, <reason>`; `crash`/`crash_str` into one terminator;
  `divs/divu/...` into `arith`; `shls/shlu` into one shift; `put_*` into
  `str.show_*` plus one `io.write` (O5); six stat ops into one multi-result
  `io.file.stat`; eight clocks into `io.clock <kind>`; `tabulate`/
  `tabulate_io` into one; `con/field/tag` into `data.con/field/tag`;
  `func/call/return` into `func.*` possibly; `match_lit` into
  `scf.index_switch`; **`Idr_Runtime<"symbol">` kept ("it is the op's one
  meaning, AGENTS.md"), `Primitive` implied by it.** Every row that merges
  ops into one op with an enum changes how the Idris side names and builds
  the op, and how the registry maps a primitive to an op (DD-Q5).
- **S1/S2/S3** (syntax): every op a declarative assembly format; aliases
  generated (`!List_Nat`); constructors and fields stored as indices,
  printed by name. Bears directly on how the Idris side writes text (if it
  writes the generic form, S1 is invisible to it; checked in §3).
- **DD-Q5** (owner; evidence from me): may one op with an enum map to
  several runtime functions, selected by a table generated from ODS, where
  `Idr_Runtime<"symbol">` ties one op to one function today?
- **DD-Q8** (owner; evidence from me): is every name open, including `con`,
  `dup`, `drop` and the `idr` namespace itself?
- Wave-2 questions addressed to "`ods`, `frontend-mirror` and `solvers`
  lanes": this lane is the frontend mirror; of the list, the ones that
  fall here are: which (quantity, permission) pairs occur (the Idris side
  is where every grade is first written), and every op with a `UnitAttr`,
  an optional operand or an enum (the Idris side's builders show which the
  frontend sets).

### §5.9 mlton

- C2: MLton spends a new IR type where the representation change is large
  and a checked invariant where it is an absence. M1: we keep one dialect
  from the frontend to lowering, so every fact the frontend writes must be
  in a type of that dialect. Design 2 (case as a terminator after
  defunctionalization) does not change what the frontend writes (it
  writes before defunctionalization). Design 3 / Q-O3: immutable
  `!idr.data` naming a tycon, bodies in one table op: the frontend writes
  that table today (checked in §3).

### §5.10 rc

- A11 (read): Koka's counting ops are untyped externals found by name
  comparison (`getName name == nameDrop`): the counterexample to any
  primitive identified by a string on our side (the registry's names,
  checked in §4).
- G2: quantity 1 is the future promise only (Brady): a linear binder does
  not mean unique; the frontend's `!idr.lin` writing must not be read as
  uniqueness.
- R1.1: function parameter and result grades in types: the frontend
  writes function types; whatever grades it writes are R1's input.

### §5.11 oom

- Nothing direct. C2 (MLIR's context never frees uniqued storage): the
  frontend's output decides how many distinct attributes the reader
  uniques (every location, every string, the data table). W8 (attributes
  created per function) partly starts at what the frontend writes.

### §6-§9

- §6: "The Idris side is in scope and may be refactored heavily,
  representation first, within the subset both hosts compile."
- §8.2 **Q3** (owner; evidence from me): "Churning the `.td` files changes
  what `idris-mlir-tblgen` generates for the Idris side: is the frontend
  cut over in the same change?"
- §8.2 **DD-Q8** (renames), §8.3 **DD-Q5** (one op, several runtime
  functions), §8.10 **Q-llvm-5** (one TableGen tool): with Q3, the four
  owner questions this lane gives evidence for.
- §9: D1-D3 only; nothing decided on the dialect or the mirror.

### Proposal 0003 (facts once): items in this subsystem

- Status line (read, `0003:13-18`): "the dialect's binary format no longer
  read by hand: a data type's text is its name and the program's table
  holds every body once, one ODS record read and written by both sides'
  generated code, which self-hosting's S3 forced (the owner, 2026-10-19:
  'we cannot have the binary format be read by hand')". So the Idris side
  writes bytecode through generated code (checked in §2).
- **B5** (`0003:143-147`): "the registry resolved and thrown away.
  `validate` resolves every entry and returns only `Maybe Refusal`; about
  twenty call sites then re-derive hooks through `show n` and a string
  map, and `foreignHook` re-parses spec strings per entry."
- **B7** (`0003:152-154`): "an instance's identity printed for C++. The
  frontend holds `link.definition : Address` and emits only `show`; C++
  keys specialization nodes by the string. Emit a typed identity."
- **A5** (`0003:163-165`): a library module without installed source
  becomes `UnknownLoc` (`MLIR/Bytecode.idr`, `MLIR/Text.idr`).
- **D1** (`0003:172-174`): Emit's use counts quadratic (`mostUses`).
- The static lifetime (`0003:238-239`): "every lifetime a constant can
  carry prints and parses (the dialect's syntax, on the Idris side too,
  regenerated by `tools/dialects.sh`)".
- Data types carry no location (`0003:287-291`): "the body holds the
  declaration's location, written by the frontend".
- `idris-mlir-tblgen` matches a record by name (`0003:418-420`):
  `getName() == "Idr_TagParameter"`; `byteCountOf` maps `Idr_AbiCount`
  defs by name.
- Idris-side leftovers (`0003:443-448`): `MkStatement` with no results
  (`Emit/Operations.idr`, `SyntaxSamples.idr`); four "gives no result"
  internal errors (`Operations.idr` in `effect`, `Emit/Tensors.idr`): a
  constructor that needs `NonEmpty o.results`.

## 2. What the subsystem is

### 2.1 Files and sizes (measured)

`wc -l` over each file, at e96bb991:

| part | files | lines | written by |
| --- | --- | ---: | --- |
| `foreign/idr/tools/idris-mlir-tblgen.cpp` | 1 | 3,255 | hand (C++) |
| `Dialect/` (idr 1,765, arith 356, math 296, memref 212, tensor 146, ub 32, builtin 32) | 7 | 2,839 | generated, checked in |
| `Syntax/` (idr 595, arith 275, memref 82, math 49, ub 42, tensor 14, builtin 14) | 7 | 1,071 | generated, checked in |
| `Encoding/` (builtin 596, idr 85) | 2 | 681 | generated, checked in |
| `MLIR.idr`, `MLIR/{Text,Parts,Bytecode}.idr` | 4 | 1,403 | hand |
| `Emit.idr`, `Emit/*` (Bodies 587, Tensors 547, Operations 353, Monad 136, Closures 132, Index 91, Declarations 71, Types 28) | 9 | 2,053 | hand |
| `Registry.idr`, `Registry/*` (Primitives 525, Entry 520, Recognized 303, Libraries 142, Name 27) | 6 | 1,608 | hand |
| `SyntaxSamples.idr` | 1 | 355 | hand (a test program) |

Command: `cd compiler/src/IdrisMLIR && cat Dialect/*.idr Syntax/*.idr
Encoding/*.idr | wc -l` (4,591 generated) and the same per group.

### 2.2 What it does, end to end (read)

1. **Generation** (`tools/dialects.sh generate`, run by `make build`):
   `idris-mlir-tblgen` (a `GenRegistration` set over `MlirTblgenMain`,
   `idris-mlir-tblgen.cpp:3221-3255`) writes three Idris modules per
   dialect of the contract (`idr`, `builtin`, `arith`, `math`, `ub`,
   `memref`, `tensor`: `tools/dialects.sh:79-90`): `-gen-idris-syntax`
   (enums, types and attributes as Idris sums with printers),
   `-gen-idris-dialect` (one builder per op, the guards of partial ops, the
   discardable attributes, the primitive sums), `-gen-idris-bytecode`
   (codes and encoders of the bytecode records, idr and builtin only). Each
   module ends with a fingerprint of the records and of the generator's
   source (`tools/dialects.sh:93-106`); `tests/dialects-current` checks
   them. The same tool also writes **C++ and text for the rest of the
   tree** from the same records (`include/idr/IR/CMakeLists.txt:15-28`):
   `idris_rt_ops.h` and `IdrRuntimeAbi.inc` (the runtime's C prototypes and
   the ABI table the lowering reads), `IdrGuards.inc`, `IdrBigToWord.inc`,
   `IdrRules.txt`, `IdrRuleCategories.inc`, `IdrPassRoles.txt`,
   `IdrPassStages.txt`. Upstream's `mlir-tblgen` writes the dialect's own
   C++ (`IdrOps.h.inc` and kin, `IdrBytecode.cpp.inc`): two tools over one
   record set.
2. **The Idris vocabulary** (`MLIR.idr`): `MlirType` and `MlirAttr` are
   hand sums of the builtin types and attributes the frontend writes
   (`MLIR.idr:69-78, 95-113`) plus one constructor per dialect holding the
   generated sum and its cached text (`Idr`, `Arith`, `UB`, each with a
   `Spelling`, `MLIR.idr:47-54`). An `Op` is the generic form: a name
   string, operand `Value`s (an SSA name string and a type), inherent
   attributes, regions, discardable attributes, result types
   (`MLIR.idr:258-284`).
3. **Emission** (`Emit*`): a paramorphism over the frontend's `Term`
   (`Emit/Bodies.idr:359-587`) appends `Statement`s through the generated
   builders, inserting each partial op's guard ops first
   (`Emit/Operations.idr:57-82`), lifting each lambda and delay into a
   function named by a hash of its generic text
   (`Emit/Closures.idr:113-132`), and builds the program's table of data
   types once (`Emit/Index.idr:65-85`).
4. **The handoff** (`MLIR/Bytecode.idr`): a hand-written MLIR bytecode
   writer, version 6 (`:767-775`), writes each top-level function as Emit
   finishes it (`writeTopLevel`, `:657-661`). Types and attributes with a
   bytecode record are encoded natively by the generated encoders (idr's
   `q`, `fn`, `lazy`, `box`, `dest` and `#idr.types`; builtin's function,
   ranked tensor, memref, array, dictionary, type and string attributes and
   locations: `:420-487`); **every other type and attribute is its text**
   inside the bytecode (`Textual`, `:211-214, 329-346`). Every op is
   flagged registered and its inherent attributes go in its attribute
   dictionary; the properties section is empty (`:12-19, 775`), so the
   reader moves them into properties by `Operation::setAttrs`
   (`upstream/25-bytecode-unregistered-properties/README.md`, "How this
   compiler met it"). **W8's answer:** the frontend writes bytecode, with
   our attributes and types partly as text.
5. **The registry** (`Registry*`): a table of `Entry`s, each a `Key`
   (an Idris `QName`, a `%foreign` `Spec` or a source `Spelling`), what it
   `Expect`s of the definition (a `Shape` of its type, or bodiless), and a
   `Hook` (`Registry/Entry.idr:221-320`), each hook `Faster` or `Stricter`
   (`:326-356`). Category 1 is Idris's backend contract (124 entries over
   IO, files, directories, process, terminal, errno, clocks, handles,
   iterators: `Registry/Primitives.idr`), category 2 the privileged
   knowledge (naturals, the array language, base's list, `mlir-linear`'s
   in-place types, outside-the-language refusals: `Registry/Recognized.idr`),
   and the library table (`Registry/Libraries.idr`). The hooks name ops by
   the generated primitive constructors (`IOPrim`, `PurePrim`).

### 2.3 Facts it holds or derives (read)

| fact | where it is held | source of truth |
| --- | --- | --- |
| every op's name, operands, attributes, regions, results | generated builders (`Dialect/*.idr`) | ODS (generated) |
| every idr type's and attribute's parameters and declarative syntax | generated sums and printers (`Syntax/*.idr`) | ODS (generated, but the format is re-parsed by our backend, `idris-mlir-tblgen.cpp:1845-1909`) |
| builtin types' and attributes' syntax | hand (`MLIR.idr:126-180`) | builtin's C++ printers (custom syntax; nothing generated, `Syntax/Builtin.idr` is empty) |
| bytecode codes and record layouts | generated encoders (`Encoding/*.idr`) | `IdrBytecode.td`, `BuiltinDialectBytecode.td` |
| bytecode framing (magic, version 6, section ids, op mask bits, `FileLineColRange` layout) | hand (`MLIR/Bytecode.idr:563-568, 351-370, 767-775`) | upstream's `mlir/Bytecode/Encoding.h` (not a record) |
| which type gets which record | hand switch (`MLIR/Bytecode.idr:419-439`, "the one switch over the kinds of type") | the bytecode records' `elems` |
| the default lifetime of a grade | hand, `maybe Lifetime.Heap id l` (`MLIR/Bytecode.idr:422`) | `Idr_LifetimeParam`'s `defaultValue` (`IdrTypes.td:278-280`) |
| `ShapedType::kDynamic` | hand constant (`MLIR.idr:117-119`) | upstream C++ |
| partial ops' guards | generated `Guarded` builders (`Dialect/Idr.idr:31-56`) | `Idr_Guarded` marks |
| which ops are Idris primitives, their arity, IO result shape | generated `PurePrim`, `IOPrim`, `primArity`, `ioResult` | `Idr_Primitive`, `Idr_PerformsIO`, world operands |
| a value's grade | `heldType` writes only `(one, plain, no lifetime)` (`Emit/Index.idr:58-59`) | the frontend's `Quantity` |
| a closure's grade from its captures | hand rule (`Emit/Bodies.idr:331-344`, "Essential: ... a type rule of the op") | the C++ verifier's type rule |
| each op's result types | every emitter computes them (generic form and bytecode require them) | the ops' C++ type rules |
| a lifted function's identity | hash of its generic text (`Emit/Closures.idr:122-124`) | its content |
| Idris library names and types the compiler knows | registry entries (`Registry/*.idr`) | the libraries (validated, `Frontend/Resolve.idr:268-299`) |

### 2.4 State and threading

- The generator runs once per build, single-threaded, no state across runs.
- `Emit` is a `StateT ES (Either String)` (`Emit/Monad.idr:22-47`): SSA
  counter, the region's statements, lifted functions, and `keys :
  SortedMap String String` from a lifted symbol to its **full generic
  text** (`:36-37`), kept for the whole owner function.
- The bytecode writer holds five `SortedMap` numberings keyed by text or
  bytes (`MLIR/Bytecode.idr:263-274`) for the whole module, and the
  encoded body of every top-level op until `finish`; each type or
  attribute's text is made once per distinct entry (77a7192b).
- The registry is pure data; `defHooks` indexes `Def` keys once
  (`Registry.idr:39-45`); `Foreign` and `Spelling` keys are a linear scan
  per query (`Registry.idr:51, 73-75`).
- The frontend is single-threaded (both hosts); nothing here is
  concurrent.

### 2.5 Who reads it

- The frontend's translation (`Frontend/Translate/*`, lane 15) reads the
  registry (`Frontend/Resolve.idr:175-299`, 23 call sites of
  `hooksOf`/`foreignHookOf`: `grep -rn 'hooksOf\|foreignHookOf'
  compiler/src/IdrisMLIR | wc -l`) and the generated `PurePrim`/`IOPrim`.
- The driver reads the bytecode (`idris-mlir`), through upstream's reader
  with patch 03 (`PINS.md:611-630`).
- The C++ side reads `IdrRuntimeAbi.inc`, `IdrGuards.inc`,
  `IdrBigToWord.inc`, `IdrRuleCategories.inc`; the tests read
  `IdrRules.txt`, `IdrPassRoles.txt`, `IdrPassStages.txt`;
  `tests/dialect-syntax` round-trips `SyntaxSamples`' module through the
  C++ reader ("the print itself is no part of the check",
  `tests/dialect-syntax/run:11-13`).

### 2.6 Measured counts

| count | value | command |
| --- | ---: | --- |
| idr op builders generated / named outside `Dialect/` | 191 / 66 | loop over `grep -oE '^[a-zA-Z0-9]+Op :' Dialect/Idr.idr`, `grep -rqw` outside `Dialect/` |
| arith / math / memref / tensor builders generated / named | 56/22, 46/12, 32/5, 21/11 | same |
| pure / IO / region primitives generated | 39 / 75 / 0 | `awk '/^data PurePrim/,/^$/'` etc. |
| primitive constructors no Idris code names | 9 (`PutList`, `PutDouble`, `DoubleHead` written by nobody on the Idris side; `BigToInt`, `BigFromDouble`, `BigToDouble`, `ToInt`, `StrFromChar`, `StrToDouble` written through their builders) | loop with `grep -rlw` excluding `Dialect/Idr.idr` |
| grades the frontend writes | 1 of 8 pairs: `(one, plain)`, no lifetime | `Emit/Index.idr:58-59`; `grep -rn 'QType' Emit` |
| `internal` error sites in `Emit/` | 21 | `grep -n 'internal (\|internal "' Emit/*.idr` |
| commits touching `Syntax/Idr.idr` / of which only its fingerprint line | 29 / 16 | `git log` + `git show --numstat` |
| registry rows | 124 in `Registry/Primitives.idr`; 54 written out in `Registry/Recognized.idr`, plus the refusal rows its `map`s make (threads, signals, processes) | `grep -cE '^\s+[\[,] (MkEntry\|cPrimitive\|cCall\|...)'` per file |
## 3. Reconciliation with the proposal

### 3.1 Findings and designs that touch this subsystem

| wave-1 item | verdict | evidence |
| --- | --- | --- |
| §5.2 F1, M12, Design 4; §5.3 E3, M10: `idris-mlir-tblgen` should be a `GenRegistration` on `MlirTblgenMain` | **holds already** (read) | `idris-mlir-tblgen.cpp:3221-3255`: eleven `mlir::GenRegistration`s; `main` is `mlir::MlirTblgenMain` (`:3255`); linked against `MLIRTblgenLib`, `MLIRTableGen` (`foreign/idr/CMakeLists.txt:229-235`). The shape §5.2 names (`tblgen-to-irdl`) is the shape we have. |
| §5.3 E3: `MlirTblgenMain` is "the main a custom tool links to get every upstream generator plus its own" | **refuted at the pin** (read) | `MLIRTblgenLib` is `MlirTblgenMain.cpp` alone (`.toolchain/llvm-project/mlir/lib/Tools/mlir-tblgen/CMakeLists.txt:3-4`); every upstream generator registers in a source of the `mlir-tblgen` executable (`mlir/tools/mlir-tblgen/CMakeLists.txt:8-35`). Our tool therefore has our generators only, and the build runs both tools over one record set (`include/idr/IR/CMakeLists.txt:16-28` ours, `:39-62` upstream's). "One tool generates both" (Q-llvm-5) means compiling upstream's generator sources into ours or an upstream patch that makes them a library. |
| §5.2 F2, W5: does the backend read raw `Record` fields or the wrappers; what does it recompute? | **holds in part** (read; W5 answered) | It reads `Operator`, `Argument`, `NamedAttribute`, `NamedProperty`, `NamedTypeConstraint`, `AttrOrTypeDef`, `AttrOrTypeParameter`, `EnumInfo`, `EnumCase`, `Dialect` (`:62-70, 96-103`). It bypasses them, recomputing a fact the wrapper holds, in: traits by a raw walk of `traits` through `TraitList`s (`:259-272`; `Operator::getTraits()` already flattens, `mlir/include/mlir/TableGen/Operator.h:304`); a parameter's optionality by comparing its default's C++ text with `getCppStorageType() + "()"` (`:1792`; `AttrOrTypeParameter::isOptional()` exists, `AttrOrTypeDef.h:106`); attribute kinds by storage-type strings (`:545-596`); parameter kinds by C++ type spellings (`:1710-1744`); bytecode members by their `cParser` template text (`:2449-2464`); `MutableType` by trait name (`:2101-2104`); `Idr_TagParameter` (`:1778`) and `Idr_AbiCount` defs by name (`:1066-1078`); the `CheckKind` and `Rule` enums by C++ class name (`:984-992, 3119-3134`); the result-as-order rule by an attribute named `predicate` (`:958-959, 2811`). It reads **no effect**: no `SideEffect` wrapper is included; IO is read off the `PerformsIO` trait (`:1481`) and world operands (`:821-824, 1445-1457`). The declarative type/attribute format is re-parsed by a hand subset parser (`:1845-1896`) and printed with a copy of upstream's spacing (`:1898-1909`), because upstream's format parser lives in the `mlir-tblgen` executable (`tools/mlir-tblgen/FormatGen.cpp:482`, `AttrOrTypeFormatGen.cpp`), not in a library. |
| §5.2 M7, row 12; §5.5 D4a: the runtime symbol is one record read by C++ and Idris | **holds** (read) | `-gen-runtime-abi-decls`/`-defs` (`:2753-2996`) read each `Idr_Runtime` mark (`markOf`, `:2878`) and `Idr_RuntimeFunction` records into `idris_rt_ops.h` and `Abi<Op>`; the C ABI of each operand is derived from its type constraint (`:862-963`). The Idris side does not read the symbol: it builds the op, and the symbol is the C++ lowering's. |
| §5.5 D4a: "its refusal category ... emitted to C++ and to Idris from the one record" | **holds** (read) | `-gen-rule-list`, `-gen-rule-categories` (`:3108-3172`); the Idris `Rule`, `RuleCategory` and `ruleCategory` are generated (`Syntax/Idr.idr:172-327`). "Its effect row": not emitted; nothing on the Idris side reads effects. |
| §5.2 row 22: the Idris view generated; deletes "hand mirrors" | **holds in part** (read) | Generated: builders, enums, idr/arith/ub types and attributes, encoders, guards, primitives. Hand mirrors left: builtin types and attributes and their syntax (`MLIR.idr:69-180`; `Syntax/Builtin.idr` is empty), bytecode framing (`MLIR/Bytecode.idr:563-568, 767-775`), the type-to-record switch (`:419-439`), the lifetime default (`:422`), `kDynamic` (`MLIR.idr:117-119`), the closure's grade rule (`Emit/Bodies.idr:331-344`), and every op's result-type rule (each emitter computes result types; the generic form and bytecode require them). |
| §5.2 M14, G1, D2; W8: bytecode on a hot path; our types and attributes as text | **holds** (read; W8 answered) | The frontend writes bytecode (`Emit.idr:3-7`). Native: idr `q`, `fn`, `lazy`, `box`, `dest`, `#idr.types` (`Encoding/Idr.idr`; `IdrBytecode.td:38-46, 57-68`) and builtin's function, ranked-tensor and memref types, array, dictionary, type and string attributes, and locations (`MLIR/Bytecode.idr:419-487, 347-395`). Text: idr `big`, `nat`, `str`, `token`, `world`, `data` (its name), `#idr.big`, `closure`, `instance`, `refusal`, `rule`, `world`; arith and ub attributes; builtin integer, `f64`, `index`, integer, float, bool, unit, symbol-ref and dense-array attributes, the identity map (`:329-346, 439, 487`). Upstream's builtin `IntegerType`, `IntegerAttr`, `FloatAttr`, `DenseArrayAttr` and others have records whose members a custom reader reads, so no encoder is generated (`Encoding/Builtin.idr:585-596`). Each distinct entry is parsed once by the reader; how much of the 71 MB stage-1 module is text payload is unmeasured (§8). |
| §5.2 D3, row 13: an op's configuration as properties (`EnumProp`, `IntProp`, `ConfinedProp`) | **collides with this side** (read) | The Idris writer writes no native property: every inherent attribute goes in the op's dictionary and `Operation::setAttrs` moves it into properties (`MLIR/Bytecode.idr:12-19`; `upstream/25-bytecode-unregistered-properties/README.md`, "How this compiler met it": "a property that is not an attribute (an `I32Prop`, an `EnumProp`) would stay a discardable attribute, its property at its default"). The generator refuses an op whose property is not an attribute and has no default (`idris-mlir-tblgen.cpp:1319-1330`), and skips one with a default (`:1325`). So row 13 for any op the frontend writes needs native property encoding on the Idris side, generated per op from ODS (upstream generates `writeProperties` in C++ only); or those properties stay attribute-backed. Lane 03's call; evidence here. |
| §5.2 M8, §5.8 N2, DS4 (families into one op with an enum) | **holds, with a constraint from this side** (read) | A primitive has no inherent attribute by construction: "no constructor could give one its value" (`:1393-1400, 1462-1464`). The registry maps each base primitive to one `IOPrim` (`Registry/Primitives.idr:255-266` for the six stat times, `:347-356` for the clocks). An `io.clock <kind>` would need the hook to carry the kind and the generator to accept an enum attribute on a primitive (DD-Q5, §6). |
| §5.5 D1, D2: closed sums of our own C++ types, visited exhaustively; no `get_if`/`holds_alternative` validators | **holds in part** (read) | Exhaustive `std::visit` over `GuardArgument` (6 alternatives, `:1225-1241, 3041-3051`) and `Primitive` (3, `:1598-1601`); validators: `std::holds_alternative<WordLoaded>` (`:1565`), `std::get_if<Omitted>` / `std::get<...>` pairs (`:1881-1886, 1980-1982, 2035-2037, 2050-2052, 2058-2060, 2489-2491, 2498-2502, 2646-2648`). |
| §5.4 F18, Design 9: a parse-once backend, errors tested; a checksum compiled into both artifacts | **holds in part** (read) | The backend refuses malformed records with `PrintFatalError` at each read (e.g. `:174, 278, 352-369, 1087-1131, 1453-1490`), but parses on demand inside each generator, not once into a typed model (`read`, `:2244-2323`, reads the dialect's records twice per dialect, once per generator invocation); no fixture of a malformed record was found (`grep -rln 'idris-mlir-tblgen' tests` finds only `file-size`, `no-behaviour-options` and `dialects-current`; *measured*). Each module carries a fingerprint of its records and of the generator's source (`tools/dialects.sh:93-106`), checked by `tests/dialects-current`, but not compiled into the compiler nor compared when the driver reads a module. |
| §5.6 F2: ClangIR's lowering emitter, fields on the base op class | **consistent** (read) | Our generator already writes C++ tables from op fields (`Idr_WordOp`'s `wordOp` → `BigToWord<Op>`, `:3071-3106`; guard marks → `Guarded<Op>`, `:3010-3060`). |
| §5.8 T4, DS1: illegal (quantity, permission) pairs unrepresentable | **evidence** (read, measured) | The frontend writes one grade: `QType One Plain t Nothing` (`Emit/Index.idr:58-59`), its only construction of `QType` outside the samples (`grep -rn QType compiler/src/IdrisMLIR/Emit`; the other match, `Emit/Bodies.idr:343`, reads one). The generated constructor is the full product, `QType : Quantity -> Permission -> ty -> Maybe Lifetime -> IdrType ty` (`Syntax/Idr.idr:476-499`), so the Idris side can build every pair; `SyntaxSamples.idr:109-114` writes `(one, own)` and `(many, borrow)` as text samples. |
| §5.8 DS2.1: no world value after the frontend | **cost here** (read) | The world is part of the generated vocabulary: IO primitives take it last and give it back (`idris-mlir-tblgen.cpp:1443-1457, 1636-1660`), `IOResult`/`ioResult`, `worldNewOp`, `Emit/Operations.idr:338-353`, `Emit/Tensors.idr:489-520`, the C ABI's `World` kind (`:716, 732, 821-824`). DS2.1 would delete those here; the translation's world-passing (lane 15) is the larger part. |
| §5.8 DS3.1: an immutable table on the program, types naming entries | **holds already on this side** (read) | The frontend builds the table once, sorted (`Emit/Index.idr:80-85`), as `#idr.types` on `idr.program` (`Emit.idr:83-84`); a data type is written by name (`Syntax/Idr.idr:518`). The C++ side's type is still the mutable `!idr.data` (lane 01). |
| §5.8 S1-S3 (assembly formats, aliases, names) | **invisible to the frontend** (read) | Ops are written in the generic form (`MLIR.idr:369-410`, `idris-mlir-tblgen.cpp:38-43`); only types' and attributes' declarative formats reach this side, as text entries. |
| §5.10 A11 (counting ops as untyped externals found by name) | **refuted for primitives, holds for op identity** (read) | Primitives are typed constructors (`PurePrim`, `IOPrim`) with arity in the type (`Types.idr:431`, `Op : (p : PurePrim) -> ... -> Prim (primArity p)`). But an op in the Idris IR is a name string (`MLIR.idr:262`), its dialect the text before the first dot (`MLIR/Bytecode.idr:282-289`). |
| §5.7 L3, §5.9 Design 3 (interned, frozen program tables) | **evidence** (read) | The writer numbers each type and attribute by its text or bytes in a `SortedMap` (`MLIR/Bytecode.idr:184-206, 263-274`): an intern table on the Idris side, keyed by printed content. |
| 0003 B5 (the registry resolved and thrown away) | **holds** (read) | `validate` resolves each entry with `lookupCtxtExact` and returns `Maybe Refusal` (`Frontend/Resolve.idr:268-299`); `hooksOf n = hooks (Def (qname n))` rebuilds a string key with `show n` (`:41-42, 177-178`) and searches `defHooks` per call; `foreignHook` re-parses every entry's specs per call (`Registry.idr:55-56, 73-75`). |
| 0003 B7 (an instance's identity printed for C++) | **holds** (read) | `InstanceAttr key.origin (argumentsText key.arguments)` (`Emit/Declarations.idr:30-31`, `Emit/Index.idr:76`): an `#idr.instance` of strings. |
| 0003 A5 (`UnknownLoc` for a library module without source) | **holds** (read) | `MLIR/Bytecode.idr:377`, `MLIR/Text.idr:187`. |
| 0003 D1 (Emit's use counts quadratic) | **holds** (read) | `mostUses` (`Emit/Bodies.idr:56-131`) walks the whole scope at every `let` (`:385`), case field (`:420`), lambda (`:485`) and parameter (`Emit/Declarations.idr:45`). |
| 0003 "`idris-mlir-tblgen` matches a record by name" | **holds** (read) | `:1778`, `:1066-1078`; and further cases in §4. |
| 0003 Idris-side leftovers (a statement with no results buildable; four "gives no result" errors) | **holds** (read) | `Statement.result : Maybe String` (`MLIR.idr:280-284`); `Emit/Operations.idr:345-352`, `Emit/Tensors.idr:504-505, 518-519`. |

### 3.2 Wave-2 questions of §5 answered here

- **§5.2 W5** (the backend's reading): above, row "§5.2 F2, W5".
- **§5.2 W8** (bytecode on a stage; our attributes and types as text):
  above, row "§5.2 M14". The stage is the frontend-to-driver handoff, every
  program; the driver reads it with patch 03 (`PINS.md:611-630`), and
  writes no bytecode of its own on the pipeline's path (*measured*:
  `grep -rn 'writeBytecodeToFile\|BytecodeWriterConfig' foreign/idr/lib
  foreign/idr/tools` finds none; lane 13 to confirm the tools' flags).
- **§5.8 "which (quantity, permission) pairs occur, what the lifetime
  parameter holds, who reads each"**: on this side, one pair, `(one,
  plain)`, and never a lifetime (`Emit/Index.idr:58-59`). Every other pair
  and every lifetime is written by passes (lane 01 counts them).
- **§5.8 "every op with a `UnitAttr`, an optional operand or an enum"**:
  of what the frontend writes, `idr.func`'s `total` and `no_inline`
  (unit) and `instance` (optional) (`Emit/Declarations.idr:56-58`,
  `Emit/Closures.idr:93`), `idr.program`'s `stage` (an enum, always
  `Higher`, `Emit.idr:83`), `arith`'s `overflowFlags` (`Emit/Tensors.idr:321,
  343`), predicates of `idr.big.cmp`, `idr.str.cmp`, `arith.cmpi`/`cmpf`
  (`Emit/Operations.idr:252-296`). The builders also expose `arg_attrs`
  and `res_attrs` on `func`, `call` and `apply`, which the frontend never
  sets (`Dialect/Idr.idr:65-67, 238-240, 396-398`).
- **§5.8 "for every pair or family flagged in DS4"**: on this side, the
  frontend picks the op per signedness (`divs`/`divu`, `mods`/`modu`,
  `shls`/`shlu`, `shrs`/`shru`, `to_char_s`/`_u`, `show_sint`/`_uint`,
  `from_sint`/`_uint`: `Emit/Operations.idr:220-228, 257, 270, 278`) and
  writes no `put_sint`, `put_uint`, `put_double`, `double_head`,
  `int_head_*` at all (they are made by C++ canonicalization, §2.6). The
  six stat times and the eight clocks are one primitive each, from one
  base primitive each (`Registry/Primitives.idr:255-266, 347-356`).
- **§5.4 "every option or flag that selects between two
  implementations"**: none in this subsystem (*read*).
- **§5.3 "every switch on an enum of ours that appears in more than one
  place"**: on this side, `withHook` and `kind` both switch on `Hook`
  (`Registry/Entry.idr:335-356, 400-426`); §4 lists it.
## 4. Issues

Exhaustive over the subsystem's files. Paths: `tblgen` is
`foreign/idr/tools/idris-mlir-tblgen.cpp`; Idris paths are under
`compiler/src/IdrisMLIR/`. All *read* unless marked. Two categories have
no entry: **per-target** (the writer writes bytes one at a time, "so no
byte order is assumed", `MLIR/Bytecode.idr:27-28`; the generator has no
target case) and **budget** (no cap or round count in any file here).

### 4.1 `idris-mlir-tblgen.cpp`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| T01 | tblgen:117-128 | list | Idris's keywords copied by hand; the source is the fork's lexer (`compiler/idris/src/Parser/Lexer/Source.idr:196-204`), the same 41 words today. | Delete: every generated binder takes one fixed suffix (`'`), which no keyword and no helper ends with, so no name can collide (T02 goes too). Cost: primed names in generated signatures (owner's taste, §6 new Q). |
| T02 | tblgen:154-162, 2540-2543 | list | Names generated bodies use unqualified, which must track `MLIR/Text.idr`'s exports and the generator's own templates. | Delete with T01, or qualify every helper (`Text.commaSeparated`). |
| T03 | tblgen:168-177 | list | Prelude constructor names a generated constructor may not take (`[]` reads as any `Nil`). | Keep: essential (Idris's list sugar); it refuses and names the ODS to rename. |
| T04 | tblgen:236-249, 534-541, 559-596, 1708-1744, 1967-1970 | cpp | Generated Idris built from `formatv` templates with `{0}` holes; `maker` re-reads a template's text to eta-reduce it (`:242-249`). | A small typed Idris-expression tree (application, lambda, literal, hole), printed once; `maker` is a function on it. Unrepresentable: a hole the template misplaces. |
| T05 | tblgen:259-272 | upstream | Marks found by walking raw `traits` through `TraitList`s, a recursive `std::function`; `Operator::getTraits()` flattens and deduplicates (`mlir/include/mlir/TableGen/Operator.h:304`, `lib/TableGen/Operator.cpp:767-813`). | Filter `op.getTraits()` by `getDef().isSubClassOf(name)`; the walk and the `std::function` go. |
| T06 | tblgen:950, 1362, 1365, 1437-1438, 1481, 1596, 2307, 3014 | list | Traits asked by C++ class-name strings (`"::idr::NoReturn"`, `"::idr::PerformsIO"`, `"::idr::Primitive"`, `"::idr::GuardedOp"`, `AttrSized*Segments`), each spelled at its use. | One `constexpr` table of the marks the generator reads, each spelled once (§5.5 D4b), or the records compared. |
| T07 | tblgen:305-392, 537, 1761, 1768, 2118-2121 | state | The enum set is a `std::map<std::string, Enum>` filled as a side effect of reading types, attributes and ops, with a `spellings` flag set wherever a syntax needs one. | Compute the enums reached, and which need spellings, as data after the read; no mutation from the readers. |
| T08 | tblgen:442-457 | idris | Each generated `Eq` is one clause per case (`Rule`'s 28, `Syntax/Idr.idr:177-207`). | `x == y = value x == value y`, one clause; generated size and both hosts' compile time. |
| T09 | tblgen:521-529, 827-832 | list | TableGen's `I`, `F` (width 64) and `Index` mapped by hand to the hand `MlirType` constructors (`MLIR.idr:69-78`): one fact in three places. | Generated with the builtin vocabulary (M01). |
| T10 | tblgen:545-596 | ladder | `attributeKind`: an if-chain over storage-type strings to hand `MlirAttr` constructors; anything else becomes an untyped `MlirAttr`. | A table keyed by the attribute constraint's record, generated beside the builtin sum (M01); the untyped fallback stays for interface attributes (essential: an open set). |
| T11 | tblgen:605-704, 692-704 | cpp | Arity as a `char` sentinel (`'1'`, `'?'`, `'*'`) threaded through `listOf`, `segments`, `builderBound`, `emitClause`. | `enum class Arity { Single, Optional, Variadic }`; an unknown arity unrepresentable. |
| T12 | tblgen:787-797, 2849-2855 | list | A C ABI kind spelled as a string in a record (`Idr_CType`'s `abiKind`), parsed back by `kindSpelled`. | Kinds as TableGen defs of one class, compared as records; the C++ enum emitted from them as `:2961-2969` already emits its text. |
| T13 | tblgen:799-819 | list | `abiWord` a string too, and `constraintWords` a second list of the kinds it may name. | As T12. |
| T14 | tblgen:821-854 | upstream | Integer width and float width read from raw `bitwidth` and `allowedTypes` fields of upstream's `I`/`F`. | Keep: `mlir::tblgen::TypeConstraint` exposes no width; essential until it does. |
| T15 | tblgen:944-963, 2811 | list | "An i1 result with an attribute named `predicate` is a three-way order": a role found by an attribute's name. | A mark (a trait, or the predicate's attribute class) carries the role. |
| T16 | tblgen:984-992 | list | The guard kinds found as the enum whose C++ class is named `CheckKind`. | The mark's `kind` field typed by the enum's class; or gone with DS4's one `idr.check <reason>` (§5). |
| T17 | tblgen:1001-1015 | list | Guard ops found by the presence of a raw `checkKind` field on any `Op`. | As T16. |
| T18 | tblgen:1110-1132 | ladder | A guard's count classified by type tests (word, i64, `byteCountOf`) in order. | Keep while guards are counts: essential to the three counts; DS4 reshapes it. |
| T19 | tblgen:1064-1078 | list | `byteCountOf` maps `Idr_AbiCount` defs by name strings (0003). | A field on the count record, or `isSubClassOf`; the name table goes. |
| T20 | tblgen:1157-1189 | idris | Generated `Guard.operand : Nat` (a position) and `WordOf : MlirType -> Count` (any type) let a guard name an operand the op lacks and a word that is none; both are internal errors in Emit (`Emit/Operations.idr:67, 82`). | `Fin n` over a `Vect n Value` of operands; `WordOf` over a word sum. Unrepresentable: both internal errors. |
| T21 | tblgen:1198-1285 | cpp | `Bound`: four parallel vectors (`operands`, `results`, `starts`, `lengths`) matched by group index. | One `struct Group { name, start, length }` per group. |
| T22 | tblgen:1293-1387, 2317-2318 | dead | A builder for every op: 125 of 191 `idr` builders, 34 of 56 `arith`, 34 of 46 `math`, 27 of 32 `memref`, 10 of 21 `tensor` are named by no Idris code (§2.6, *measured*). | Builders only for the ops the frontend's stage admits, declared in ODS (a stage class per op; lanes 03 and 13). Unrepresentable: the frontend building a `cell`, `dup`, `drop` or `own.*` op. |
| T23 | tblgen:1319-1330, 1422-1441 | ods | A property that is no attribute is refused (no default) or skipped (default): the writer's dictionary convention (B11) forbids §5.2 row 13's properties on every op the frontend writes. | Lane 03 decides; evidence in §3.1. If native properties come, the generator also emits each op's property encoder. |
| T24 | tblgen:1295-1296 | — | No op with successors. | Keep: essential; the frontend writes structured regions only. |
| T25 | tblgen:1335-1338 | idris | A `UnitAttr` becomes a `Bool` implicit (`funcOp {total', noInline}`): ODS's flags restated as Idris flags. | Follows ODS: when an op's flag is split (§5.8 O1), the builder's flag goes with it. |
| T26 | tblgen:1369-1370, 1383, 1386 | idris | Every builder returns one untyped `Op`; its result count is checked only by MLIR's reader, and Emit names results by string (`r#i`). | Builders return an op indexed by its result count (`Op n`), a statement binding a `Vect n` of values; deletes `Statement.result : Maybe String` and its four internal errors (M09). |
| T27 | tblgen:1401-1491 | rederivation | A primitive's kind decided by its regions, the `PerformsIO` trait (one of §2's three "does IO") and its world operands. | Read IO from the one representation the owner keeps (DD-Q3, ods-Q2); the `PerformsIO` read goes with the trait. |
| T28 | tblgen:1393-1400, 1462-1464 | ods | "A primitive has no inherent attribute": an op with an enum (DS4's `io.clock <kind>`) cannot be a primitive. | The owner's (DD-Q5, §6). |
| T29 | tblgen:1499-1501, 1502-1581, 1653-1660 | idris | `ioOp : IOPrim -> List Value -> ...`: a list of the wrong length falls to an unguarded clause "which MLIR refuses where it reads the module"; `pureOp` already takes `Vect (primArity p)` (`:1630`). | `ioOp : (p : IOPrim) -> Vect (ioArity p) Value -> ...`. Unrepresentable: an IO primitive of the wrong arity; the refutable clause and its comment go. |
| T30 | tblgen:1469-1480, 1662-1678 | dead | Region primitives: none is generated (`IdrRegionPrim` has no constructor, *measured*). | Delete the branch and its `Idr_BodyRegion` read. |
| T31 | tblgen:1687-1691; get_if sites 1565, 1881-1886, 1980-1982, 2035-2037, 2050-2052, 2058-2060, 2489-2491, 2498-2502, 2646-2648 | cpp | `Written<T> = std::variant<T, Omitted>` consumed by `get_if`/`get` pairs: validators (§5.5 D2). | `std::expected<T, Omitted>` with `and_then`, or one `match`. |
| T32 | tblgen:1789-1801 | upstream | Optionality by comparing a default's C++ text with `getCppStorageType() + "()"`; `AttrOrTypeParameter::isOptional()` exists (`AttrOrTypeDef.h:106`). | Use it. Unrepresentable: an optional parameter read as required because its default is spelled differently. |
| T33 | tblgen:1710-1744 | ladder | `valueKind`: an if-chain over C++ type spellings, with `ends_with("Type")` as "a dialect's own type". | Classify by the parameter's TableGen class; the heuristic goes. |
| T34 | tblgen:1776-1785 | list | `Idr_TagParameter` by def name (0003). | `isSubClassOf`, as `Idr_SquareListParameter` beside it is. |
| T35 | tblgen:1822-2002, 1898-1909 | rederivation | A hand parser of the declarative type and attribute format and a copy of upstream's printer spacing (`tools/mlir-tblgen/FormatGen.cpp:482`), which no check needs (`tests/dialect-syntax/run:11-13`); upstream's parser is in the `mlir-tblgen` executable, not a library. | (a) every `idr` type and attribute encoded natively (bytecode records), so this side writes no `idr` text; text only for `arith` and `ub` attributes; or (b) an upstream patch that moves the format parser into `MLIRTableGen`. §5 recommends (a). |
| T36 | tblgen:2099-2104 | list | An identified type found by a trait named `MutableType`. | Record comparison; gone with DS3 (an immutable data type). |
| T37 | tblgen:2106-2200 | rederivation | The data table's Idris records and printers hand-written in C++ strings, restating `lib/IR/DataBody.cpp`'s syntax (`Plain` prints nothing, `instance`); the generated `CtorRole` admits `Label`, `Running`, `Forced`, which the frontend must never write (`:2112-2114`). | The table only as its bytecode records (it already is one, `IdrBytecode.td:57-68`); the generated body one alternative per kind with the frontend's roles only (0003's owed `Body`). Unrepresentable: a label, running or forced role written by the frontend. |
| T38 | tblgen:2206-2224 | attribute | Discardable attributes generated; the one the frontend writes is `idr.refusals`, the refused program's refusals on the module (`Emit.idr:104`). | An inherent attribute of a module-level refusal op or of the program op (lane 03); a refused module passes no pass today, so nothing drops it, but the rule is AGENTS.md's. |
| T39 | tblgen:2244-2323 | state | `read` builds the whole vocabulary for each generator; the syntax generator builds every op's text and discards it, the dialect generator every type's. | Read once into a typed model, then emit (§5.4 Design 9). |
| T40 | tblgen:2257-2287; `IdrAttrs.td:223` | list | The table found by a `holdsBodies` field; passes-only attributes by an opt-out `bit idris = 0`. | Subsumed by T22's stage declaration. |
| T41 | tblgen:2449-2464, 2506-2509 | list | Bytecode atoms keyed by the exact `cParser` template text of `BytecodeBase.td`; an unknown member is omitted silently. | Key by the member's record (`VarInt`, `String`, ...); refuse a record the writer needs. |
| T42 | tblgen:2484-2486 | — | `ArrayWithKnownSize` omitted. | Keep (no use). |
| T43 | tblgen:2702-2711 | list | The DSL's dialect (`"Idr"`) matched to ODS's (`idr`) without case. | The bytecode record names the ODS dialect record (a field of ours, or an upstream patch). |
| T44 | tblgen:2753-2996 | (lane 12) | The runtime ABI generators (C prototypes, `Abi<Op>`, helpers); `idris_rt_` required by string (`:2841`). | Lane 12 and 18; holds §5.2 row 12. |
| T45 | tblgen:3002-3060 | (lanes 02, 04) | `Guarded<Op>` for C++; an op whose guard counts bytes from a value may not list `GuardedOp` (`:3005-3009`): two kinds of guarded op by a limit of the representation. | Redesigned with DS4; noted for lanes 02, 04. |
| T46 | tblgen:3071-3106 | (lanes 09, 11) | `BigToWord` and the `GET_BIG_TO_WORD_LIST` comma list. | Generated already; keep. |
| T47 | tblgen:3174-3219 | (lane 13) | Pass roles and stages for tests; `Stage` is held twice in TableGen: `Idr_Stage` (`IdrOps.td:52-53`) and `IdrStage<"...">` (`Passes.td:49-57`). | Lane 13: one record set. |
| T48 | tblgen:60, 383-391 | — | The backend includes `idr/Support/Worklist.h`. | Keep, or plain set iteration once T07 is data. |
| T49 | tblgen:84, 261 | cpp | `std::function` for a recursive lambda. | Gone with T05; else deducing `this` (§5.5 D5). |
| T50 | `tools/dialects.sh:93-106` | state | The fingerprint covers the generator's source, so any edit of it (a comment included) restamps all fifteen modules: 16 of the 29 commits touching `Syntax/Idr.idr` changed only that line (*measured*, §2.6). | Fingerprint the records and the generated text only (the text already changes when the generator's output does); or stop checking the modules in (§6, new Q). |
| T51 | `tools/dialects.sh:9-11` | (lane 13) | Stale: says `-gen-idris-dialect` writes "the printer of each op's declarative syntax"; it writes none (tblgen:38-43). | Lane 13. |

### 4.2 `MLIR.idr`, `MLIR/Text.idr`, `MLIR/Parts.idr`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| M01 | MLIR.idr:69-78, 95-113 | list | Builtin types and attributes the frontend writes, a hand sum (`Syntax/Builtin.idr` is empty: builtin's syntax is C++). | Generated from builtin's bytecode records (`BuiltinDialectBytecode.td`), which hold each one; a hand encoder only for the records whose member has a custom reader (`IntegerType`, `IntegerAttr`, `FloatAttr`, dense arrays). |
| M02 | MLIR.idr:126-180 | rederivation | Hand printers of builtin syntax, restating builtin's C++ printers; read for text entries and content keys only. | Deleted with B05 and E05. |
| M03 | MLIR.idr:47-54, 77-78, 108-113, 182-202 | list | One constructor per dialect (`Idr`, `Arith`, `UB`) with a cached `Spelling`, and a hand smart constructor per dialect; a new dialect's attribute is an arm here, in `typeDialect`/`attrDialect`, in the writer and in the samples. | The dialect constructors generated from the one dialect list (`tools/dialects.sh:79-90`). |
| M04 | MLIR.idr:204-216 | list | `typeDialect`/`attrDialect` give dialect names as strings, which the writer numbers (`MLIR/Bytecode.idr:331, 336`). | A generated `Dialect` enum; the strings go. |
| M05 | MLIR.idr:115-119; Emit/Tensors.idr:140-143 | list | `dynamicExtent` restates `ShapedType::kDynamic`; `mixed` rebuilds upstream's mixed static/dynamic lists. | The builders of mixed lists take `List (Either Value Integer)` and write the sentinel themselves (generated, one place); the Idris constant goes. |
| M06 | MLIR.idr:243-248, 290-298; MLIR/Bytecode.idr:539-561, 597-600; Emit/Closures.idr:65-66 | idris | A value is an SSA name string ("the only identity a value has"): scopes are `SortedMap String Nat`, captures and renamings are name walks, results are named `r#i` by string, and "an operand that nothing in scope defines" is a runtime error of the writer. | A value is a number dense per function (its definition's position), names only in `NameLoc`s. Unrepresentable: an operand nothing defines; deletes the scope maps and the rename walks (M11, E04, E05). Both hosts compile it (plain `Nat`s). |
| M07 | MLIR.idr:258-269 | idris | One untyped `Op` record for every op (a name string, any operands, attributes, results). | T26 for result counts; a fully typed op per ODS op is heavier (§8). |
| M08 | MLIR.idr:271-275 | — | `Region = NoBlocks \| MkRegion` (at most one block). | Keep: essential, the frontend's structured form. |
| M09 | MLIR.idr:277-284 | idris | `Statement.result : Maybe String`: a statement of results can be built unnamed (0003). | T26. |
| M10 | MLIR.idr:304-329 | rederivation | The `Occurrence` walk, read to rederive captures and to bind scopes. | E04 and M06 delete both readers. |
| M11 | MLIR.idr:331-350 | state | `renameRegion` copies a whole region per renaming; `Emit/Closures.idr:120` runs two per lifted function, after two walks (`:116`, `:83`). | Gone with M06. |
| M12 | MLIR.idr:352-410 | rederivation | The generic-form printer, used only to make content keys (`Emit/Closures.idr:122`). | A structural hash (E05); the printer goes. |
| X01 | MLIR/Text.idr:124-142 | idris | A float's text relies on `prim__cast_DoubleString` printing the shortest round-trip decimal; the comment names Chez alone and strips Chez's subnormal suffix, a branch dead on the idris-mlir host (whose runtime prints Ryu's digits, `runtime/Doubles/Printing.cpp:3-18`). The hosts agree by coincidence of two implementations. | Write a double as its 64 bits (MLIR's hexadecimal float form), exact on both hosts by construction; `decimal` and the host assumption go. |
| X02 | MLIR/Text.idr:190-194; MLIR/Bytecode.idr:380-387 | list | "Report at caller" travels as the string `"library"` in a fused location's metadata. | A dialect attribute (`#idr.library`) generated on both sides. |
| X03 | MLIR/Text.idr:184-188; MLIR/Bytecode.idr:377 | rederivation | A library module without installed source is `UnknownLoc` (0003 A5). | 0003's fix. |
| X04 | MLIR/Text.idr:32-41, 46-52 | — | Two escapers, `quoted` (ASCII) and `utf8`. | Keep; `quoted` is for names MLIR spells in ASCII. |
| P01 | MLIR/Parts.idr:13-17 | — | `TypeRef`/`AttrRef` are entry numbers the writer mints. | Keep. |

### 4.3 `MLIR/Bytecode.idr`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| B01 | :3-29, 173-178, 351-370, 563-568, 767-775 | upstream | Bytecode framing by hand: magic, version 6, section ids, op mask bits, `FileLineColRange`'s layout (upstream writes it by hand too); its source is C++ constants (`mlir/Bytecode/Encoding.h`), no record. | Keep: essential while the writer is Idris; one module, each constant named as upstream names it. |
| B02 | :282-289 | rederivation | An op's dialect is the text before its name's first dot. | Builders give the dialect as the generated `Dialect` (M04). |
| B03 | :309-315 | list | `Dialect = IdrDialect \| BuiltinDialect`: the dialects with native encodings, by hand. | Generated from the dialect list. |
| B04 | :419-439 | ladder | "The one switch over the kinds of type": which constructor has which record, restating `IdrBytecode.td`'s `elems` and builtin's. | Generated: `-gen-idris-bytecode` pairs each record with the syntax constructor of the same name and emits the dispatch. |
| B05 | :211-214, 329-346, 439, 487 | rederivation | Every type and attribute without a record goes as its text, which the reader parses once per entry. | Records for every `idr` type and attribute (T35a). |
| B06 | :422 | list | `maybe Lifetime.Heap id l`: the ODS default (`IdrTypes.td:278-280`) restated. | The generator emits the default with the parameter (or the Idris value always holds a lifetime). |
| B07 | :430-438 | — | A memref's identity layout written as an affine-map text entry. | Keep: upstream's record names the layout. |
| B08 | :500-522 | list | Each table row written with no label and `by_name = 0`, since the frontend writes no label. | T37. |
| B09 | :539-561 | state | `bindRegion` builds a scope map per region, copying the outer scope into each nested one. | M06. |
| B10 | :184-206, 216-257 | state | Intern tables keyed by text or byte lists in `SortedMap` (`compareBytes` over `List Bits8`). | Measure first (77a7192b made the writer 16 times faster); with B05 and M06 the keys are structural. |
| B11 | :12-19, 580-588, 775 | ods | Inherent attributes in the op's dictionary, the properties section empty: the convention behind T23. | As T23. |
| B12 | :702-731 | — | Containers (`module`, `program`) nested by hand. | Keep. |

### 4.4 `Emit.idr`, `Emit/*`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| E01 | Emit/Index.idr:58-59; Emit/Monad.idr:76-83 | rederivation | `heldType` grades by `linear q t`, a `Bool`, with the world excepted by hand ("linear by its own type"): the type interface method `isLinearByType` (`IdrInterfaces.td:43-47`: "a grade of such a type is refused"; world, destination, cell, `IdrTypes.td:270-276`) restated for the world, as C++ code the generator cannot read. | A type trait in ODS (`Idr_LinearByType`) that the interface's default reads and the generator emits as `isLinearByType : IdrType ty -> Bool`; the exception goes (lanes 01, 02 own the interface). |
| E02 | Emit/Bodies.idr:331-344 | rederivation | A closure's grade re-read from its captures' MLIR types (`QType One`), restating the C++ type rule (the comment calls it essential). | Read the captures' `Val.use`, known before the op is built; the rule stays one place in C++ plus the one read here. Essential while the frontend writes result types. |
| E03 | Emit/Bodies.idr:56-131, 385, 420, 485; Emit/Declarations.idr:45 | rederivation | `mostUses` walks the scope at every binder (0003 D1). | Use summaries returned by the paramorphism (0003). |
| E04 | Emit/Closures.idr:35-52 | rederivation | Captures found by walking the built region for names used before defined; the term's free variables were known first. | Captures from the term (its free `Fin nv`s); `Seen` and `captures` go. |
| E05 | Emit/Closures.idr:113-132; Emit/Monad.idr:36-37 | state | A lifted function is named by a hash of its whole generic text, and the text is kept per symbol for the owner's life; each lift walks its region four times (`captures`, the rename of captures, `renumbered`'s numbering and its rename) and prints it once. | A structural hash of the `Op` (with M06, no renumbering); keep the hash and the value for the equality check. |
| E06 | Emit/Monad.idr:54-59 | idris | SSA names minted as strings `"%n"`. | Numbers (M06). |
| E07 | Emit/Monad.idr:134-136; Emit/Operations.idr:148-154 | idris | `madeAt` compares two `Bool`s; `coerce` cases on a pair of `Bool`s (boolean blindness). | A `Held = Plain \| Linear` sum computed once from (`Quantity`, `Ty`). |
| E08 | Emit/Monad.idr:100-102; Emit/Bodies.idr:188-214 | idris | A constructor taken apart is identified by a fresh name string; `renamed` compares strings through the whole environment per case. | A number (M06); the environment updated once per case. |
| E09 | Emit/Monad.idr:45-52 | idris | Every frontend bug is an `internal : String -> E a`; 21 sites (*measured*). | Each site below made unrepresentable or moved to the Term (lane 15). |
| E10 | Emit/Operations.idr:62-82 | idris | `count (WordOf t)` internal for a non-word; `splitAt g.operand` internal for a missing operand. | T20. |
| E11 | Emit/Operations.idr:338-353; Emit/Tensors.idr:504-505, 518-519 | idris | `Just n <- place ...` internal when an op of results gives none (0003). | T26. |
| E12 | Emit/Operations.idr:220-228, 257, 260-265, 270, 278 | — | The frontend picks the op per signedness (`divs`/`divu`, ...). | Keep: essential (two computations, §5.8 B3); DS4's moves into `arith` change these lines only. |
| E13 | Emit/Operations.idr:197-208 | — | `math1`: Idris's `UnaryMath` to `math` ops. | Keep: essential mapping between Idris's enum and upstream's ops. |
| E14 | Emit/Operations.idr:176-194; `foreign/idr/lib/IR/Layout/Layouts.cpp:235-249` | list | `CmpPredicate` to `arith`'s `CmpIPredicate` (signed and unsigned) and `CmpFPredicate`, by hand in Idris; the signed map again in C++. One fact twice. | Case fields of `CmpPredicate` in ODS naming `arith`'s cases (the generator already reads case fields, `tblgen:302-392`), emitted to Idris and to C++. |
| E15 | Emit/Bodies.idr:346-352, 371-377 | idris | A call's callee looked up by id with an internal error on a miss, and its arity checked at run time (`saturated`). | The term's call carries its callee's arity in its type (lane 15). |
| E16 | Emit/Bodies.idr:400-401, 496-497, 522-523 | idris | A match on a non-data, an application of a non-function, a force of a non-lazy are representable (`Val.type : Ty`). | A typed term (lane 15, 0003 C2); at least the scrutinee's data on the term. |
| E17 | Emit/Bodies.idr:487-488, 508-509, 513-514 | idris | "The result type of a lambda whose body never returns": result types as `Maybe Ty`. | The term carries the type (0003 C1, lane 15). |
| E18 | Emit/Bodies.idr:236-269, 409 | idris | A match is built from `tags : List Nat` and `cases : List Region` matched by position, as the builder takes them. | The builder takes `List (Nat, Region)` (a pairing the generator emits for an op whose tags attribute and case regions ODS pairs; lane 03 owns the op). |
| E19 | Emit/Bodies.idr:302-325 | idris | `plainHeld`, `evaluated`: `Bool` tests recomputed per suspension. | Minor; return the evidence (the plain value) instead. |
| E20 | Emit/Tensors.idr:74-123, 333-338, 363-365 | idris | Axes as `Nat`, internal when past the rank; `dimsOf` internal on a non-tensor. | `Fin rank` from a rank-indexed `TensorT` (lanes 11, 15). |
| E21 | Emit/Tensors.idr:162-183 | idris | `Fitting.Mismatch` is an internal error; the fit is decided structurally on `Ty`. | Essential in part (casts between static and dynamic extents); the mismatch case moves to the term's types. |
| E22 | Emit.idr:73-80 | state | Two functions on one symbol detected at run time with a `SortedSet String`. | Unique by construction of `FnId` (lane 15); the set goes. |
| E23 | Emit.idr:100-108 | attribute | Refusals as the discardable `idr.refusals` on the module. | T38. |
| E24 | Emit/Index.idr:65-78 | rederivation | The sum's kind and each constructor's role written separately for one `DataShape` (0003's "a body holds a kind beside its constructors' roles", on this side). | T37's one-alternative-per-kind body; `body` becomes one-to-one. |
| E25 | Emit/Index.idr:76; Emit/Declarations.idr:30-31 | list | An instance's identity printed into strings (0003 B7). | A typed identity (0003). |
| E26 | Emit/Declarations.idr:52-58 | ods | `no_inline` set on a lazy constant to keep one cell: a fact (a constant applicative form) written as a pass directive. | Lane 09 (a lazy constant as its own op, §5.8 O1). |

### 4.5 `Registry.idr`, `Registry/*`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| R01 | Registry/Entry.idr:221-356 | idris | Each `Hook`'s kind (`Faster`, `Stricter`) by a separate 21-arm function. | Index the hook by its kind (`Hook : Kind -> Type`); `kind` goes, and a function that takes only faster hooks says so in its type. |
| R02 | Registry/Entry.idr:367-426 | list | `Hooks`: twenty optional fields, `noHooks` positional over all twenty, `withHook` a 21-arm restatement: a new hook is five edits. | A dependent map from a hook tag to its payload (`Payload : HookTag -> Type`), each reader asking its tag; `noHooks` and `withHook` go. |
| R03 | Registry/Entry.idr:432-435 | idris | `meansExtern`: a `Bool` of six field tests, branched on by `Frontend/Profile.idr:384`. | A view returning what the extern means. |
| R04 | Registry/Entry.idr:134-148 | idris | `conforms` returns `Bool`; the mismatch is reprinted whole. | Return the first differing sub-shape (evidence). |
| R05 | Registry.idr:53-78; Registry/Entry.idr:39-51 | rederivation | Specs parsed from strings at every query; `foreignHook` scans the entries twice per `%foreign` definition (0003 B5). | Specs parsed once at the boundary (lane 17); `Foreign` keys indexed like `Def` keys. |
| R06 | Registry.idr:39-51; `Frontend/Resolve.idr:41-42, 177-178, 268-299` | rederivation | `validate` resolves every entry and returns only `Maybe Refusal`; every reader rebuilds a string key with `show n` and searches `defHooks` (0003 B5). | `validate` returns the resolved table keyed by the resolved name; every reader asks it. Unrepresentable: a hook found through a printed-name collision. |
| R07 | Registry.idr:51 | state | `Foreign` and `Spelling` keys looked up by a linear `filter` over all entries per query. | Indexed once (R05). |
| R08 | Registry/Name.idr:14-27 | — | `QName` as strings. | Keep at the boundary (the registry names library definitions in their source terms), resolved once (R06). |
| R09 | Registry/Primitives.idr:225-400 | — | 124 rows mapping a library primitive to a hook and a generated `IOPrim`/`PurePrim`. | Keep: Idris's backend contract (essential); §6 asks whether the op's row could name its Idris primitive in ODS. |
| R10 | Registry/Primitives.idr:255-266, 347-356 | (DD-Q5) | Six stat-time primitives and nine clock primitives, one op each. | Evidence for DS4 and DD-Q5 (§6). |
| R11 | Registry/Libraries.idr:58-77 | — | `Row` of three `Bool`s per library. | Keep: three independent policies, every combination meaningful (essential). |
| R12 | Registry/Libraries.idr:95-104 | — | Package names as strings, parsed once into `Origin`. | Keep (boundary). |
| R13 | Registry/Libraries.idr:121-126, 140-142 | list | `admittedFromPrimIO` and `assertion` name Idris definitions by strings outside the entries, and `validate` checks none of them. | Entries with hooks of their own (`Admitted`, `Assertion`): every name the registry knows in one table, all validated. |
| R14 | Registry/Primitives.idr:24-31 | — | `programEntry = "main"`, `codegenName = "mlir"`. | Keep: Idris's conventions. |
| R15 | Registry/Entry.idr:322-356, 503 | idris | AGENTS.md's `Faster` hook ("the body is the one meaning, and removing the hook leaves the same result") is a label read only by the mismatch message (`kind e.hook`, `:503`; *measured*: no other reader, `grep -rn 'kind e.hook\|Faster'`). Category 1's contract hooks (`PureCall`, `IOCall`, `ArrayCall` on `%foreign` and `%extern` definitions with no body) are labelled `Faster`, though removing one refuses the program (an unknown `%foreign` is an escape hatch, `Frontend/Resolve.idr:190`): they are the meaning the backend owes, not a faster one. | Three kinds, indexing the hook: `Contract` (a bodiless primitive's meaning), `Faster` (an `Expect` that requires the definition to have a body, validated), `Stricter`. Unrepresentable: a `Faster` hook on a definition with no body. Whether a test removes the `Faster` hooks and compares results is the owner's (NQ-14-6). |
| R16 | Registry/Entry.idr:445-454 | idris | `Typed` checks a shape but not that a body exists, so a `Faster` entry (category 2: `plus`, `pack`, `scalarBytes`) validates on a bodiless definition too. | R15's `Faster` expectation. |

### 4.6 Generated modules and `SyntaxSamples.idr`

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| G01 | `Encoding/Builtin.idr` | dead | 51 builtin encoders generated, 12 used (*measured*: loop over `^encode`, `grep -rqw`). | Generate only what the writer uses (the builtin vocabulary of M01). |
| G02 | `Encoding/Idr.idr:82-83`; tblgen:2527-2534 | idris | A composite record's members as a positional tuple (`(String, SumKind, List (String, CtorRole, Maybe AttrRef, Nat, ...), Maybe AttrRef)`). | A generated record per composite, its DSL names as fields. |
| G03 | `Syntax/Idr.idr:476-499` | idris | `QType` is the full product of quantity, permission, value and an optional lifetime. | DS1's one grade enum (lanes 01, 03); the generated constructor follows. |
| G04 | `Syntax/Idr.idr:430-445` | idris | `IdrCtor.role : CtorRole` admits the roles the frontend may not write. | T37. |
| G05 | `Syntax/Idr.idr:552` | list | `InstanceAttr (origin : String) (arguments : List String)`. | E25. |
| G06 | `Syntax/Idr.idr:497-499, 558` | (DS2) | `WorldType`, `WorldSpaceAttr`. | Follows DD-Q3. |
| G07 | `Dialect/Idr.idr:65-67, 238-240, 396-398` | dead | `arg_attrs`/`res_attrs` on `apply`, `call`, `func`, never set by the frontend. | T22's filter (an attribute the frontend never writes is not in its builder). |
| S01 | SyntaxSamples.idr:149-175 | list | The "every mnemonic sampled" property is good, but its arms restate the dialect constructors of `MlirType`/`MlirAttr` by hand. | Generated with M03. |
| S02 | SyntaxSamples.idr:109-114 | — | Samples of grades the verifier would refuse as values (`(one, own)`, `(many, borrow)`) as text. | Follows G03. |
## 5. Target design

What the subsystem becomes, applying the proposal; *conjecture* until the
owner rules. Each change states its representation, what it deletes, and
the skill's one line.

### 5.1 The changes

**TD1. One typed model of the records, read once, every generator
emitting from it** (§5.2 F2, M12; §5.4 F18, Design 9; T05-T07, T09-T19,
T32-T34, T36, T39, T41, T43). `idris-mlir-tblgen` first builds one
model of the dialect: ops (with their marks, from `op.getTraits()`),
types, attributes and parameters (with `isOptional()`, classified by
their TableGen classes), enums with their case fields, bytecode records
(by member class), and the ABI kinds as records. Each generator emits
from the model; nothing below it reads a raw field or compares a C++
spelling. Malformed records fail while the model is built, with one
fixture per refusal (a `tests/` planted `.td`, lane 19).
- *Deletes:* the trait walk and its `std::function`, the string ladders
  (`attributeKind`, `valueKind`, `kindSpelled`, `abiWordOf`,
  `byteCountOf`, `checkKinds`, the `predicate` rule, `atomOf`'s template
  keys), the default-text compare, the per-generator re-reads.
- *Line:* the check moves to one boundary (the model's construction),
  and every generator reads what it learned.
- *Two tools stay* (Q-llvm-5's evidence, §6): the records are the one
  source; two generators reading them through the same wrappers are not
  two copies of a fact.

**TD2. The handoff carries no `idr` text** (§5.2 row 21, M14; T35a,
B04, B05, M02, M12, X01, E05). Every `idr` type and attribute has a
bytecode record in `IdrBytecode.td`: the five parameterless types and
`#idr.world` trivially, `!idr.data` as a `String` name (the reader's
`cBuilder` looks the name up as the text parser does today),
`#idr.big` as its decimal `String`, `#idr.instance`, `#idr.closure`,
`#idr.rule`, `#idr.refusal` from members the DSL has. The pairing of a
record with the syntax constructor of the same name is generated
(`encodeIdrType`, `encodeIdrAttr`), replacing the hand switch. A lifted
function's key is a structural hash of its `Op` value, not of its text.
A double is written as its 64 bits wherever it is still text.
- *Deletes:* the declarative-format parser and the copied spacing
  (tblgen:1822-2002, ~180 lines), `idrTypeText`, `idrAttrText`,
  `Spelling` and the `idr`/`arith`/`ub` smart constructors' text,
  `genericForm` and `opText` (MLIR.idr:352-410), the full texts held in
  `ES.keys`, `floatLiteral`'s `decimal` and its Chez assumption, the
  writer's type switch. Text stays only for `arith`'s two flag
  attributes, `ub.poison` and the builtin types and attributes whose
  records need a custom reader (`i64`, `f64`, `index`, integer and float
  attributes), each a one-line printer.
- *Line:* unrepresentable: an `idr` type the Idris side spells otherwise
  than the C++ parser reads; the copy of the declarative format goes.
- *Depends on:* lane 01 (the data type's reader entry; DS3), lane 03
  (attribute definitions).

**TD3. A value is a number; a statement binds as many values as its op
gives** (M06, M07, M09, M11, T26, E04, E06, E08, B09; 0003's leftovers).
`Value` becomes a dense number per function (its definition's position:
block arguments, then results in order, the order the writer numbers them
in already, `MLIR/Bytecode.idr:544-561`); its name survives only as the
`NameLoc` the frontend already writes (`Emit/Monad.idr:126-136`).
Generated builders return `Op n` with `n` the op's result count where ODS
fixes it (a `Variadic` result gives `Op (length rs)`), and a statement
binds a `Vect n Value`. Captures come from the term's free variables, not
from a walk of the built region.
- *Deletes:* the writer's `Scope` maps and their copy per region,
  `renameRegion`, `renumbered`, `captures`, `Seen`, `Numbering`,
  `resultAt` and the `r#i` strings, `Statement.result : Maybe String`,
  the writer's "an operand that nothing in scope defines" error and four
  "gives no result" internal errors.
- *Line:* unrepresentable: an operand nothing defines; a statement of
  results with no values bound.
- *Two hosts:* `Nat`, `Fin` and `Vect` at quantity-0 indices; nothing
  dependent is stored in a field (the skill's subset).

**TD4. Guards and primitives indexed by arity** (T20, T29, E10).
Generated guards name their operand by `Fin n` over the builder's
`Vect n Value`; `WordOf` takes a word sum; `ioOp` takes `Vect (ioArity
p) Value` as `pureOp` already takes `Vect (primArity p)`.
- *Deletes:* the unguarded fallback clauses and their comment
  (tblgen:1499-1501, 1579-1580), two internal errors in
  `Emit/Operations.idr`.
- *Line:* unrepresentable: a guard on an operand the op lacks; an IO
  primitive of the wrong arity.
- *Survives DS4:* if the five checks become one `idr.check %cond,
  <reason>` after `arith` comparisons (§5.8 DS4), the guard records and
  `Count` change shape, and their positions stay `Fin`.

**TD5. Each fact both sides restate moves into ODS, generated to both**
(E01, E14, B06, M05, T12, T13, T15, T19, X02).
- `CmpPredicate`'s cases name `arith`'s `CmpIPredicate` (signed,
  unsigned) and `CmpFPredicate` cases as case fields, the mechanism the
  generator already has (tblgen:302-392), emitted to Idris and to C++
  (a `-gen-case-fields` beside `-gen-rule-categories`). Deletes
  `Emit/Operations.idr:176-194` and `lib/IR/Layout/Layouts.cpp:235-249`.
  *Line:* one fact, one place.
- "Linear by its type" as a type trait read by `ValueFacts`' default
  and emitted to Idris. Deletes `linear One WorldT = False`. *Line:* the
  exception is the rule's data.
- A parameter's default emitted with it. Deletes `maybe Lifetime.Heap`.
- The mixed static/dynamic lists written by the generated builder from
  `List (Either Value Integer)`. Deletes `dynamicExtent` and `mixed`.
- ABI kinds, counts and the order role as records and marks (T12, T13,
  T15, T19). Deletes the string tables.
- "Report at caller" as `#idr.library`. Deletes the `"library"` string
  on both sides.

**TD6. The frontend's vocabulary is its stage's** (T22, T40, G01, G07).
Each op says in ODS at which stages it is legal (lanes 03, 13); the
generator writes builders, encoders and attributes only for what the
`Higher` stage admits.
- *Deletes:* about 125 `idr`, 34 `arith`, 34 `math`, 27 `memref`, 10
  `tensor` builders and 39 builtin encoders no Idris code names (§2.6),
  the `idris = 0` opt-out, the never-set `arg_attrs`/`res_attrs`.
- *Line:* unrepresentable: the frontend building an op its stage
  forbids (a cell, a count, an ownership conversion); the program
  verifier's stage check (C++) and the Idris vocabulary read one
  declaration.

**TD7. The registry resolved once, its hooks typed** (R01-R07, R13,
R15, R16; 0003 B5).
`validate` returns the resolved table (keyed by Idris's resolved name),
and every reader asks it. Hooks are indexed by their kind (`Hook : Kind
-> Type`), with three kinds where there are two labels today: `Contract`
(the meaning a bodiless primitive is owed, category 1), `Faster` (whose
entry requires and validates a body, AGENTS.md's hook, R15, R16) and
`Stricter`; a definition's hooks a dependent map from a hook tag to its
payload, every name the registry knows an entry (the `PrimIO` admissions
and the assertions included), `%foreign` specs parsed once and indexed.
- *Deletes:* `kind`, `noHooks`, `withHook`, the twenty-field `Hooks`
  record, `meansExtern`'s six tests, per-query spec parsing, linear
  scans, `qname`'s per-lookup `show`, the side lists
  `admittedFromPrimIO` and `assertion`.
- *Line:* the check moves to the boundary (`validate`), and its answer
  is what every reader reads; unrepresentable: a `Faster` hook on a
  definition with no body, a name the registry knows but never validated.
- *Depends on:* lanes 15 and 17 (the readers, the fork's specs).

**TD8. The table of data types as the frontend writes it** (T37, E24,
B08, G02, G04; 0003's owed `Body`). The generated body is one
alternative per kind (plain, in place, base list), carrying only the
roles the frontend may write; the table's members are generated records,
not tuples.
- *Deletes:* the separate kind and per-constructor role in `body`, the
  `Nothing, 0` label slots the writer fills, the hand C++ string
  templates of the table's records and printers.
- *Line:* unrepresentable: a label, a running or a forced role written
  by the frontend; a kind that contradicts its roles.
- *Depends on:* lane 01 (`DataType::Body`, DS3).

**TD9. The backend's C++** (§5.5 D1, D2, D4b; T04, T07, T11, T21, T31,
T49): a typed Idris-expression tree instead of `formatv` templates;
`Arity` an enum; `Group` one struct; `std::expected<T, Omitted>` instead
of `get_if` pairs; no `std::function`.
- *Line:* the generator's own sums are closed and visited exhaustively.

**TD10. The registry's IO rows and the ops' records** (R09, R10; DD-Q5,
§6). Not recommended without the owner: whether an op's record names
the Idris primitive it implements (spec, name, module), so the
registry's 124 IO rows are generated. It would couple ODS to base's
spelling; today the registry is the one place that names a library
definition (`Registry.idr:11-15`).

### 5.2 Order inside the subsystem, and dependencies

1. **TD1** first: every other generator change is written against the
   model. No dependency.
2. **TD9** with TD1 (same file).
3. **TD5** next: each item is a small ODS addition plus a generated
   output; the `CmpPredicate` case fields and the lifetime default need
   no other lane; "linear by type" waits on lanes 01 and 02.
4. **TD4**, then **TD3**: TD3 touches every emitter (about 2,000 lines
   of `Emit`), TD4 the generated guard and primitive types it uses.
   Both stay inside this subsystem; TD3's capture change reads the
   term's free variables (lane 15 confirms the term exposes them).
5. **TD2** after lane 01's data-type decision (DS3) and lane 03's
   attribute redesign: it needs the final types and attributes.
6. **TD8** with lane 01's body redesign.
7. **TD6** after lanes 03 and 13 declare stages per op.
8. **TD7** with lanes 15 and 17.

**The dialect's redesign and renames on this side** (Q3, DD-Q8). The
vocabulary is regenerated by `make build`; the hand cost is every call
site that names a generated builder or constructor, *measured*: 73 uses
of `Idr.*Op` builders in `Emit` (`Operations` 42, `Bodies` 15, `Tensors`
13, three others 3), 70 of `Arith`/`Math`/`MemRef`/`Tensor`/`UB`/`Builtin`
builders, 41 + 10 in `SyntaxSamples`; and at most 220 uses of primitive
constructors outside `Dialect/` (`Registry/Primitives` 90,
`Frontend/Translate/Terms` 45, `Translate/Primitives` 31, `Growth/Sites`
22, others under 16; an overcount, since `Arg`, `Exit`, `Time` and kin
also match other names). Command: `grep -oE '\bIdr\.[a-zA-Z0-9]+Op\b' -r
--include='*.idr' compiler/src/IdrisMLIR | cut -d: -f1 | sort | uniq -c`,
and the same over the primitive constructors. A merge of ops (DS4) costs
more than a rename: each merged family changes the hook that names it
(R10) and the emitter that picks it (E12).
## 6. Evidence for the owner's questions

No answers; what the code says.

**Q3 (§8.2). Is the frontend cut over in the same change as the `.td`
files?**
- The mirror is regenerated, not edited: `tools/dialects.sh generate`
  (`make build`) writes all fifteen modules from the records
  (`tools/dialects.sh:79-90, 134-150`), and `tests/dialects-current`
  refuses a stale or hand-edited one. A `.td` change that keeps every op
  the frontend writes is invisible to `Emit` and the registry (the
  fingerprint-only commits, 16 of 29 touching `Syntax/Idr.idr`, are
  this case, §2.6).
- What breaks the Idris build is a change to an op, type, attribute,
  enum or primitive the frontend names: 73 `Idr.*Op` call sites, 70 of
  the upstream dialects' builders, the primitive constructors
  (`Registry/Primitives.idr` alone names 90), and the generated types
  the emitters match on (`QType`, `DataType`, `IdrSum`, `Guard`,
  `Check`, `Count`, `IOResult`) (§5.2, *measured*). Since both hosts
  must build the frontend (AGENTS.md), a `.td` change that removes or
  renames one of these cannot land without the Idris change in the same
  commit: the frontend would not compile.
- Four of the cutover's likely changes reach this side beyond renames:
  the world (DS2: IO primitives' shape, `IOResult`, the C ABI's `World`
  kind, `Emit/Operations.idr:338-353`); the grade (DS1: `QType`'s
  constructor, `heldType`); the checks (DS4: the guard records and
  `checked`, `Emit/Operations.idr:57-82`); properties (§5.2 row 13 against
  the writer's dictionary, §3.1).
- Ops the frontend does not write (125 of 191, §2.6) change nothing here
  but a regeneration.

**Q-llvm-5 (§8.10). One TableGen tool for the C++ and the Idris mirror?**
- `idris-mlir-tblgen` is already a set of `GenRegistration`s on
  `MlirTblgenMain`, reading `mlir::tblgen::Operator` and kin
  (`idris-mlir-tblgen.cpp:62-70, 3221-3255`); it already writes C++ for
  the rest of the tree (`IdrRuntimeAbi.inc`, `IdrGuards.inc`,
  `IdrBigToWord.inc`, `IdrRuleCategories.inc`, `idris_rt_ops.h`:
  `include/idr/IR/CMakeLists.txt:15-28`).
- It does not read `SideEffect` (no include; nothing on the Idris side
  reads an effect), and it bypasses the wrappers in the places T05-T19,
  T32-T34, T36, T41, T43 list.
- At the pin, `MLIRTblgenLib` is the driver alone; upstream's generators
  register in the `mlir-tblgen` executable's own sources
  (`mlir/lib/Tools/mlir-tblgen/CMakeLists.txt:3-4`,
  `mlir/tools/mlir-tblgen/CMakeLists.txt:8-35`). A single tool would mean
  compiling those sources into ours or an upstream patch that makes them a
  library; the same is true of the declarative-format parser our backend
  copies (`tools/mlir-tblgen/FormatGen.cpp`, `AttrOrTypeFormatGen.cpp`).
- Today the build runs both tools over one record set
  (`include/idr/IR/CMakeLists.txt:16-28` and `:39-62`).

**DD-Q5 (§8.3). One op with an enum mapping to several runtime
functions?**
- On this side the primitive is the unit: "a primitive has no inherent
  attribute: no constructor could give one its value"
  (`idris-mlir-tblgen.cpp:1393-1400`), and the generator refuses one that
  has (`:1462-1464`). A registry hook names one primitive constructor
  and the literal operands the call adds (`IOCall : IOPrim -> List Lit
  -> Hook`, `Registry/Entry.idr:232`), not attributes.
- The candidates map one base primitive to one op today: the six stat
  times (`prim__filetimeAccessTimeSec` and kin, each a separate base
  `%foreign` on a `FileTimePtr`, `Registry/Primitives.idr:255-266`), the
  six clocks plus `ClockValid`, `ClockSecond`, `ClockNanosecond` (each a
  separate Chez spec, `:347-356`). Base itself calls them one by one, so
  a multi-result `io.file.stat` would be a merge the frontend or a
  canonicalization performs, not a translation of one base call.
- The runtime ABI generator ties one op to one C function and refuses an
  op that "gives more than one value" (`:953-955`) or takes an attribute
  other than `predicate` (`:2804-2814`): an enum-selected function would
  be a new generated table (op, case) to symbol.

**DD-Q8 (§8.2). Is every name open, including `con`, `dup`, `drop` and
the `idr` namespace?**
- Op names reach the Idris side only through generated builders
  (`camel(mnemonic) ++ "Op"`, tblgen:1300-1302) and primitive
  constructors (the C++ class without `Op`, `:1465-1468`); the Idris side
  spells no op name itself ("so that the Idris side spells no op's name
  itself", `:1608-1609`). A rename is a regeneration plus the call sites
  of §5.2.
- `dup`, `drop` and every ownership op are written by no Idris code: no
  builder of theirs is named outside `Dialect/` (§2.6); `con` is written
  (`Idr.conOp`, `Emit/Operations.idr:312`; samples).
- The namespace `idr` appears on this side as: module names
  (`IdrisMLIR.Dialect.Idr`, `Syntax.Idr`, `Encoding.Idr`, from
  `tools/dialects.sh:85`), the sum names `IdrType`, `IdrAttr`, `IdrSum`,
  `IdrCtor` (from the module's last name, tblgen:2124-2125, 2330), the
  `Idr` constructor and `idr` smart constructor (`MLIR.idr:77-78,
  108-109, 182-192`), the dialect string `"idr"` (`MLIR.idr:207, 213`;
  `MLIR/Bytecode.idr:314`), the discardable `idr.refusals`, and the
  bytecode producer string `"idris-mlir"` (`MLIR/Bytecode.idr:769`).
  `grep -c` over these is small; the dialect string is three literals.

**Other §8 questions this code bears on.**
- **DD-Q1** (normalize `!idr.lin<i64>` to `i64`): the frontend grades
  any linear binder's type, words included, except the world
  (`Emit/Index.idr:58-59`, `Emit/Monad.idr:80-83`); `SyntaxSamples.idr:76`
  writes `!idr.q<one, plain, i64>` as a table field. Normalizing would
  change `heldType` and every `coerce` (`Emit/Operations.idr:148-154`).
- **DD-Q3 / ods-Q2** (the world; effects from types): the generator reads
  the world operand's type to shape IO primitives and their C ABI
  (`:821-824, 1443-1457, 2898-2900`); the frontend writes `world.new`
  (`Emit/Bodies.idr:587`) and threads the world through every IO op and
  `tabulate_io` (`Emit/Tensors.idr:489-520`).
- **DD-Q4** (signedness): the frontend holds signedness in `IntTy` and
  picks the signed or unsigned op (`Emit/Operations.idr:220-228`),
  arith's school on this side already.
- **DD-Q7** (our own function op): the frontend writes `idr.func` with
  `total`, `no_inline` and `instance` (`Emit/Declarations.idr:56-58`).
- **Q-O3** (facts into types; one table op): the frontend writes the
  table once, sorted, on `idr.program` (`Emit/Index.idr:80-85`,
  `Emit.idr:83-84`).
- **Q4** (measurements): this lane cannot measure the share of the
  stage-1 module that is text payload; §8 lists it.

### New questions for the owner

- **NQ-14-1. Checked-in generated modules.** The fifteen generated
  modules are in git "so that the Idris build needs no other step and a
  change of ODS shows as a change of the Idris it means"
  (`tools/dialects.sh:26-27`); their fingerprints cover the generator's
  source, so 16 of the 29 commits touching `Syntax/Idr.idr` restamped
  one line (§2.6). Keep them checked in (and fingerprint only the
  records and the output, T50), or make them build outputs of `make
  build`, which already runs the generator?
- **NQ-14-2. Native properties from the frontend.** The writer puts
  inherent attributes in each op's dictionary (B11), so every property an
  op the frontend writes holds must be an attribute (T23). Accept that as
  a constraint on the ODS redesign (§5.2 row 13 only for ops the frontend
  never writes), or generate each op's property encoder for the Idris
  writer?
- **NQ-14-3. The handoff's text.** TD2 encodes every `idr` type and
  attribute natively, deleting the copied declarative-format parser and
  the Idris printers; the alternative keeps text and patches upstream to
  make the format parser a library. Which?
- **NQ-14-4. Generated binder names.** T01's fix primes every generated
  parameter (`(lhs' : Value)`), so no keyword list is kept; or keep the
  list, copied from the fork's lexer. Which reads better to you?
- **NQ-14-5. ODS naming the Idris primitive** (TD10): should an op's
  record name the base primitive it implements, so the registry's IO
  rows are generated, or does the registry stay the one place that names
  a library definition?
- **NQ-14-6. The `Faster` property as a test.** Nothing checks AGENTS.md's
  "removing the hook leaves the same result" (R15). A mode that drops the
  category-2 `Faster` hooks and a test that compiles each program both
  ways and compares exit, output and refusals (no Chez involved, so no
  oracle in AGENTS.md's sense): wanted, or is the rule a review rule?
## 7. Deletion list

By change (§5); each goes in the change that makes it dead.

- **TD1** (`idris-mlir-tblgen.cpp`): `traitsOfClass`'s raw walk and its
  `std::function` (`:259-272`); `attributeKind`'s string chain
  (`:561-596`) and `integerEnum`'s storage compare (`:545-557`);
  `valueKind`'s spelling chain (`:1710-1744`); `kindSpelled`,
  `constraintWords`, `abiWordOf` (`:787-819`); `byteCountOf`'s name table
  (`:1066-1078`); `checkKinds` by class name (`:984-992`); the
  `predicate` rule (`:958-959`); `atomOf`'s template keys
  (`:2449-2464`); `fieldWith`'s default-text compare (`:1791-1792`);
  `definedKind`'s name compare (`:1778`); `isIdentified` (`:2101-2104`);
  `elemsOf`'s case-insensitive match (`:2702-2711`); the second `read` per
  generator (`:2244-2323` run twice).
- **TD2**: `elements`, `parameterName`, `spaced`, `Piece`, `Pieces`,
  `piecesOf`, `anchorOf`, `expression`, `append` (`:1822-2002`);
  `defOf`'s format handling (`:2046-2066`); the generated `idrTypeText`,
  `idrAttrText`, `idrTypeMnemonic`/`idrAttrMnemonic` texts and the table
  printers (`Syntax/Idr.idr:448-473, 522-534, 578-586`); `Spelling`,
  `MkSpelling` (`MLIR.idr:47-54`); `typeText`/`attrText` for `idr` and most
  builtin cases (`MLIR.idr:126-180`); `genericForm`, `opText`,
  `regionsText`, `regionText`, `argumentsText`, `statementsText`, `named`,
  `indent` (`MLIR.idr:352-410`); `Native`, `recordOf`, `native`
  (`MLIR/Bytecode.idr:401-439`); `textual`, `typeTextEntry`, and the
  `Textual` path for `idr` (`:211-214, 329-346`); `floatLiteral`'s
  `decimal` (`MLIR/Text.idr:136-142`); `ES.keys` holding texts
  (`Emit/Monad.idr:36-37`).
- **TD3**: `Scope`, `bindRegion`, `definedIn`'s maps, `operand`'s scope
  lookup and its error (`MLIR/Bytecode.idr:539-561, 597-600`);
  `Occurrence`, `walkRegion`, `renameRegion` (`MLIR.idr:304-350`);
  `resultAt`, `boundNames` (`MLIR.idr:286-298`); `Statement.result :
  Maybe String` (`MLIR.idr:282`); `Seen`, `seen`, `captures`,
  `Numbering`, `numbered`, `renamedBy`, `renumbered`
  (`Emit/Closures.idr:31-83`); `fresh`'s strings (`Emit/Monad.idr:54-59`);
  `keyOf`, `renamed`, `renamedAll` (`Emit/Bodies.idr:188-203`); the
  internal errors `Emit/Operations.idr:346, 352`, `Emit/Tensors.idr:505,
  519`.
- **TD4**: the unguarded fallback clauses (`idris-mlir-tblgen.cpp:1579-1580`
  and their comments `:1499-1501, 1653-1656`); `Emit/Operations.idr:67,
  82`'s internal errors.
- **TD5**: `cmpi`, `cmpf` (`Emit/Operations.idr:180-194`);
  `layout::signedPredicate` (`lib/IR/Layout/Layouts.cpp:235-249`, lane
  12's file, generated instead); `linear One WorldT = False`
  (`Emit/Monad.idr:81`); `maybe Lifetime.Heap id l`
  (`MLIR/Bytecode.idr:422`); `dynamicExtent` (`MLIR.idr:117-119`) and
  `mixed` (`Emit/Tensors.idr:140-143`); the `"library"` metadata string
  (`MLIR/Text.idr:194`, `MLIR/Bytecode.idr:386`) and its C++ reader (lane
  13).
- **TD6**: unused generated builders and encoders (§2.6); the `idris`
  bit's opt-out (`idris-mlir-tblgen.cpp:2266-2269`, `IdrAttrs.td:223`);
  the region-primitive branch (`:1469-1480, 1662-1678`).
- **TD7**: `kind` (`Registry/Entry.idr:335-356`), `Hooks`, `noHooks`,
  `withHook` (`:367-426`), `meansExtern` (`:432-435`); `defHooks`'s string
  keys and `hooks`' linear scan (`Registry.idr:39-51`); `declares`'
  per-call parse and `foreignHook`'s double scan (`Registry.idr:53-78`);
  `admittedFromPrimIO`, `assertion` as side lists
  (`Registry/Libraries.idr:121-142`); `qname`'s use per lookup
  (`Frontend/Resolve.idr:41-42, 177-178`, lane 15's file).
- **TD8**: `body`'s separate kind and roles (`Emit/Index.idr:69-78`);
  `ctorRows`' `Nothing, 0` (`MLIR/Bytecode.idr:518`); `identifiedOf`'s and
  `tableOf`'s string templates (`idris-mlir-tblgen.cpp:2115-2200`).
- **TD9**: `Kind`'s `{0}` templates and `maker` (`:236-249`); the `char`
  arity (`:692-704`); `Bound`'s parallel vectors (`:1198-1285`);
  `Written`'s `get_if` pairs (§4 T31).
- **T50**: the generator's source in the fingerprint
  (`tools/dialects.sh:93-106`, lane 13's file).

## 8. Risks, unknowns, measurements needed

- **Risk: TD3 is the largest change on this side** (every emitter, about
  2,000 lines), and it touches the code that writes the 71 MB stage-1
  module. It must keep the module byte-identical on every program
  (77a7192b's and b9d4d592's acceptance) and keep emit's time and peak
  (742 s and 4.53 GB at 08647d2e; under a minute and 3.74 GB at 77a7192b):
  numbers replace strings, so the writer's maps shrink (*conjecture*).
- **Risk: two hosts.** TD3 and TD4 use `Fin` and `Vect` at quantity 0 in
  types and plain `Nat`s at run time, inside the subset (the skill);
  `Op n` with `n` stored in no field is a parameter, not a dependent field.
  A record whose field's type depends on another field (an `Op` holding
  its own result count and a `Vect` of that length) would be refused by
  idris-mlir (`unsupported (dependent field)`): `n` must stay an index.
- **Risk: TD2 and the reader.** A native entry for `!idr.data` means the
  reader's builder resolves a name to the program's data type during
  reading, which is what the text parser does today; with DS3's redesign
  (lane 01) the entry changes again. Patch 03 (deferred entries, quadratic
  nesting) stays relevant to native nested entries.
- **Risk: TD6** needs stage legality declared per op in ODS; if lanes 03
  and 13 keep it as C++ facts per stage (`include/idr/IR/Func.h:65-111`),
  the filter has no source.
- **Unknown: how much of the stage-1 module is text payload** (TD2's
  payoff), and how long the reader spends parsing it. Measure: the count
  and byte size of `Textual` entries the writer emits on the self
  compile (an instrumented `entries`, `MLIR/Bytecode.idr:682-692`), and
  `idris-mlir` reading the module with `-mlir-timing`.
- **Unknown: the writer's intern maps' cost** (B10) on the stage-1 module:
  entries per table and lookup time, after 77a7192b.
- **Unknown: whether the term exposes its free variables** cheaply for
  TD3's captures (lane 15).
- **Measure: emit's profile** on the self compile after TD3, against
  77a7192b's record.
- **Measure: Idris compile time of the generated modules** under both
  hosts before and after TD6 (about 2,800 lines of builders, most unused).
- **Unknown: whether upstream would take** a patch making the
  declarative-format parser (`tools/mlir-tblgen/FormatGen.cpp`) and the
  generators library code (Q-llvm-5, NQ-14-3); no upstream discussion
  found (not searched).

## 9. Sources read

*Read in full:* `.claude/skills/representation-first/SKILL.md`;
`AGENTS.md`; `proposals/0003-facts-once.md`; `audits/p0/README.md`;
`foreign/idr/tools/idris-mlir-tblgen.cpp`; `compiler/src/IdrisMLIR/`
`MLIR.idr`, `MLIR/Text.idr`, `MLIR/Parts.idr`, `MLIR/Bytecode.idr`,
`Emit.idr`, `Emit/{Types,Index,Monad,Declarations,Closures,Operations,
Bodies,Tensors}.idr`, `Registry.idr`, `Registry/{Name,Entry,Primitives,
Recognized,Libraries}.idr`, `SyntaxSamples.idr`, `Encoding/Idr.idr`,
`Syntax/{Builtin,Tensor}.idr`, `Dialect/Builtin.idr`.
*Read in part (structure, the parts cited):* `Syntax/Idr.idr` (enums'
outline, types, attributes, `:170-595`), `Syntax/{Arith,Math,MemRef,UB}.idr`
(outline), `Dialect/Idr.idr` (`:1-140, 236-250, 394-400`, the primitive
sums), `Encoding/Builtin.idr` (`:1-60, 585-596`).
*Proposal:* `proposals/0000-mlir-native.md` §0-§4 in full; §5.1, §5.2,
§5.3, §5.4, §5.5, §5.6, §5.7, §5.8, §5.9 in full; §5.10 `:9500-9800` in
full and its findings' headings and A11, G2; §5.11 `:10290-10770` in full
and its findings' headings; §6-§9 in full.
*Other files of this repository (as cited):* `tools/dialects.sh`
(`:1-150`); `foreign/idr/include/idr/IR/CMakeLists.txt` (`:1-62`);
`foreign/idr/CMakeLists.txt` (`:220-262`); `foreign/idr/include/idr/IR/
IdrTypes.td` (`:270-312`), `IdrBytecode.td` (whole), `IdrInterfaces.td`
(`:30-52`), `IdrOps.td` (`:52-53`), `Transforms/Passes.td` (`:49-78`, by
grep); `foreign/idr/include/idr/IR/Func.h` (`:65-111`);
`foreign/idr/lib/IR/Layout/Layouts.cpp` (`:225-252`);
`compiler/src/IdrisMLIR/Frontend/Resolve.idr` (`:30-50, 170-200,
255-300`); `compiler/src/IdrisMLIR/Types.idr` (`:407-431`);
`compiler/idris/src/Parser/Lexer/Source.idr` (`:189-205`);
`runtime/Doubles/Printing.cpp` (`:1-40`); `upstream/03-bytecode-deferred-
quadratic/README.md` (`:1-40`); `upstream/25-bytecode-unregistered-
properties/README.md` (`:1-120`); `PINS.md` (`:70-84, 606-635`);
`tests/dialect-syntax/run`; `tests/dialect-text/run` (head);
`tests/dialects-current/run` (head).
*Pinned tree:* `.toolchain/llvm-project/mlir/include/mlir/TableGen/
AttrOrTypeDef.h` (accessors, by grep), `Operator.h` (`:270, 304`);
`mlir/lib/Tools/mlir-tblgen/CMakeLists.txt`; `mlir/lib/Tools/mlir-tblgen/
MlirTblgenMain.cpp` (by grep); `mlir/tools/mlir-tblgen/CMakeLists.txt`;
`mlir/tools/mlir-tblgen/FormatGen.cpp:482`,
`AttrOrTypeFormatGen.cpp:879` (by grep); `mlir/lib/TableGen/GenInfo.cpp`
(by grep).
*History:* `git log --oneline` of every path of the subsystem (128
commits on the Idris side, 11 on the generator); `git show` of b9d4d592
(message and stat), and the stats of 98c6315c, 73bba53f, 7987388b,
08647d2e, 66cc60e7, aca228c5, 77a7192b, 3934cc0c restricted to these
paths; the 29 commits touching `Syntax/Idr.idr` by `--numstat`.
*Measurements (commands in §2.6 and §5.2):* line counts; generated
builders against named ones per dialect; primitive constructors and
their uses; builtin encoders against used ones; internal-error sites;
fingerprint-only commits; registry rows; builder call sites.
