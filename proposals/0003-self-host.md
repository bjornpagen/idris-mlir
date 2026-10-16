<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Self-hosting: `make self` finishes

**Status:** in progress (2026-10-16). S1 is done
(`bench/profiles/2026-10-15-self-s1.md`). These S2 fixes are in:
- the TTC decoder runs at stock speed (da9492a9);
- no escape hatch or erased match is left (4d190757);
- keys spell a Nat literal by its value (d1dc847e);
- the handoff writes each data type once, S2.1.

The self-compile's frontend step now finishes and writes a 75 MB module in
742 s of emit at 4.53 GB (`bench/profiles/2026-10-16-self-emit.md`), past
the polymorphism refusals that wait on the owner's ruling (§3.2(b)). It takes 0005's former §2 (self-hosting's steps 4 to 6) and
its decisions D10, D11 and D16 (their text at b843d8b5). Goal: the
frontend (`compiler/src`) and the fork (`compiler/idris`), compiled by
idris-mlir itself, stages 1 to 3, stage 2 the same as stage 3, on both
targets. None of 0013's features is needed: stage 0 emitted the whole of
the frontend and the fork with no frontend refusal (F0, 44495199,
`bench/profiles/2026-10-14-f0-stage0.md`; *measured*). Claims are marked
*read* (the path), *measured* (the record), *recalled*, *conjecture*,
*decision*.

## 1. What it changes

- `tools/self.sh` (D6): each stage runs its frontend alone, then the
  pipeline on the module it wrote, each half under its own `peak_memory`;
  each stage builds from a fresh copy of the sources at one path; stages
  2 and 3 compare the TTCs of `compiler/src` too.
- The fork and the frontend, wherever idris-mlir refuses them (§3), in
  their own code, representation first. No rule of the compiler changes.
- Nothing else: the pipeline, the runtime and the rules are what the
  waves before built.

## 2. Where it stands

What `make self` does (*read*, `Makefile:210-257`, `tools/self.sh`):
`prefix` installs the pinned Idris's packages into the checkout prefix
with the Chez frontend, `libs` installs `libs/`, `self-fork` installs the
fork as `idris-compiler`; then `self.sh` copies `compiler/src` once
(`:31-32`) and for N = 1..3 runs stage N-1's `idris-mlir` (stage 1: `make
build`'s, whose frontend runs on Chez) on `IdrisMLIR/Frontend/Driver.idr`
with `-p idris-compiler -mlir-timing --num-threads=$ncpu`, under
`peak_memory` (`:44`), copies the same C++ driver into each stage (`:54`),
and compares stage 2 with stage 3 by `cmp` on `idris-mlir-front`, its
`.mlirbc` and its `.core` (`:63-68`). Only the frontend is self-compiled.

Where it stopped: stage 1 never finished. A 4 h 23 min attempt and a
restarted one stopped inside the Simplify rounds (*measured* then, logs
not kept; the compile-time proposal at dcb087d2, "What stands"); a 51-min
attempt sat in IdrInline (HANDOFF.md, 2026-10-13). F0 then measured the
rounds on the stage-0 module (58,236 functions, 294 MB of text, about
140 s of frontend): round 1 447 s, sixteen rounds and no fixpoint, over
2,000 s extrapolated, 5.27 GB to 7.65 GB peak, and defunctionalize still
refusing `Idris.Parser.directive.lam4` after round 16 (*measured*). Stage 0
on Chez: 58,305 functions in 137 s at 9.1 GB (2026-10-10, HANDOFF.md).

Since: the pipeline cutover (c7aa7b62, 5d5f3312) deleted the rounds and
made defunctionalization total, right after emission; the representation
wave (bfdcac70) made the frontend's reduction structural; 0002 (d06ed15c)
made the frontend total and added the guard of §3.2(a); 0001 is
integrating. Nothing has been built or run since c7aa7b62 (*read*,
proposals/README.md), so every item of §3.2 and §3.3 is unmeasured.

## 3. Blockers

### 3.1 Known by reading

| Site | What | Rule |
| --- | --- | --- |
| `compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:33` | `%prefix_record_projections off` in a user module, added by d06ed15c | `user pragma`: `Frontend/Profile.idr:161-162`; only `discharged` (`:125-126`) passes |
| `compiler/idris/README.md:467-472`; `Idris/Desugar.idr:1189, 1236, 1379`; `TTImp/TTImp.idr:482-490`; `Idris/Syntax.idr:900-920` | `SyntaxInfo` holds terms (`startExpr`, `usingImpl`, an interface's parents and defaults), a term's local block holds `IPragma`, and the desugarer's interface, implementation and `%hide` fixity actions capture `Ref Syn SyntaxInfo`: an IORef whose element type reaches it | `cycle`: `foreign/idr/lib/IR/Verify/Knots.cpp`, a type-graph knot through an array, checked at every verification once defunctionalization makes captures types (`lib/IR/TypeGraph.cpp:18-20`, `Verify/Program.cpp:305`). *Conjecture*, strong: F0 never got past defunctionalize, so this never ran on the fork |
| `compiler/idris/idris-compiler.ipkg` | `Idris.Host` (0001's lane I, `src/Idris/Host.idr`) is not in its module list | the fork does not install it; the frontend's imports fail |
| `compiler/idris-mlir.ipkg:46` | still lists `IdrisMLIR.Frontend.Host`, deleted | the frontend does not build |
| `tools/policies.txt:33-34, 38-46, 48-54` | name the `assert_total` of `Frontend/Host.idr` and of Finite, and the `covering` definitions of Terms, Cases and `translateInstance`, all gone; Finite's `covering translateFrom` is not named | `tests/spec/no-fuel` requires each listed line in its file |

The last three are 0001's integration (*read*, live tree). With them,
0001's R4 holds in the live tree: no `assert_total`, `believe_me`, hole or
`%MkWorld` in `compiler/src` or `libs/` (*read*, a search), the trust in
Idris's compiler is the fork's (`Idris/Host.idr`), and the frontend's
`covering` chain is `Finite.translateFrom` (`Finite.idr:296`),
`Programs.translateIOProgram` (`:150`), `Program.program` (`:140`) and
`Driver`'s `perform`, `frontend` and `main` (`:284, 310, 333`). Every import
of the frontend and the fork resolves to the prelude, base or the fork
(*read*); neither reaches a thread, process, signal, finalizer or
deprecated buffer name, and the fork declares no `%foreign` or `%extern`
and spells no escape hatch (*read*).

### 3.2 Not yet run on the fork or on code written since F0

- (a) **An implementation whose method Idris does not prove ends.** The
  owner narrowed the 47f97059 ruling on 2026-10-15 (*decision*): a
  definition Idris does not prove ends is refused only where a normaliser
  would run it (`host.normalise`, `host.normaliseAll`, through
  `Closed.normalisedBy`), never by lambda-only simplification, which runs
  nothing (`Closed.lambdasApplied`, now what `Terms.settle` uses). The
  owner's reason: the project is a good optimizing compiler producing good
  code, and a total compiler compiles a partial program without running it.
  The fork's 92 `%default covering` modules (about 343 implementations,
  *read*) meet the refusal only where the head path must run one of their
  definitions to learn a static value (`Closed.idr`'s `normaliseAll` and
  `normalise` sites); S1 counts them.
- (b) **The request-chain rule**, which refuses a chain that grows once and
  stops (`Frontend/Finite.idr:123-130`, `Polymorphism`; 47f97059), and its
  data-instance form: never run on the fork (0013, feature 2).
- (c) **The erased match** (`Translate/Cases.idr:585-590`, `Match`) on
  `Proof/`, Finite and 0001's typed identities. Their erased matches read
  so far have one constructor (`Finite.idr:247`, `Access`;
  `Proof/Requests.idr:351-352`), which `Cases.idr:579-583` admits, and the
  runtime decision uses `So`, not base's primitive `DecEq`, whose
  `believe_me` (`base/Decidable/Equality.idr:140-143`) is refused even from
  base (`Profile.idr:319`) (*read*); the rest is unmeasured.
- (d) **The fork's elaborator on `compiler/src`.** `make typecheck` checks
  the frontend with the stock Idris only (`Makefile:369-372`); stage 1
  elaborates it with the fork's, a different Idris (one known bug open,
  `TTImp/Elab/Case.idr:394-404`, HANDOFF.md). Not run since 2026-10-10.

### 3.3 Pipeline and scale

What kept stage 1 from finishing, the rounds, is deleted. In their place,
never run: the label solve, the bottom-up ready set with MLton's inline
rule once and the caller cap (`kCallerCap = 10000`, `tools/policies.txt`),
and code generation in bins of 2^15 LLVM instructions, at self scale. LLVM's
share is measured only at test scale (3.8%, F0). Unknown too: the
bytecode handoff's size, the frontend's memory without the text printer,
and the native frontend's speed. Two facts of the tools stand in the way
of measuring it: the driver removes the `.mlirbc` when any later step fails
(`foreign/idr/include/idr/Driver/Artifacts.h:105-111`), and `peak-kib`
is one figure, the larger of the frontend child and the pipeline
(`tools/host.sh:129-158`, wait4's `ru_maxrss`).

### 3.4 Two hosts

On `make self`'s path, none beyond §3.2(d) (*read*). `libs/` is not on it:
neither the frontend nor the fork imports a module of it (*read*), its
`%extern` primitives run under idris-mlir alone (AGENTS.md), and `make
test`'s programs are what compile it there. Off the path: the test
machinery cannot compile under idris-mlir, which AGENTS.md requires.
`tests/Runner.idr:42, 53, 57` call `system` (`process`, outside the
language), and `tests/Main.idr` imports `Test.Golden` and `Language.JSON`,
packages outside the table (`Registry/Libraries.idr:102`, refused at
`Profile.idr:289-290`).

## 4. The plan

- **S0, integration** (typecheck machine; 0001's coordinator). The three
  integration rows of §3.1; Closed.idr's pragma deleted, renaming what it
  kept apart (lane I's file). Verified: `make typecheck`, `make check`.
- **S1, the census** (typecheck machine, no LLVM; this proposal). `make
  typecheck` (the dialect modules), `make fork frontend`, the checkout
  prefix, `libs` and the fork installed by the Chez frontend, then
  `idris-mlir-front --prefix P -p idris-compiler --timing T --core C -o M
  IdrisMLIR/Frontend/Driver.idr` on a copy of `compiler/src`, under
  `peak_memory`. It reports every independent refusal and every error of
  the fork's elaborator in one run (`Profile.idr:240-251`), and when none,
  writes the module. Recorded under `bench/profiles/`: the refusals, and
  once S2 has made it exit 0, the handoff's functions, operations and
  bytes, the phases, and the frontend's peak memory (0005's old step 4).
- **S2, the fixes** (typecheck machine; this proposal: the fork is ours,
  the frontend's files after 0001 releases them). Each S1 refusal, by D2;
  the `SyntaxInfo` knot, by D3. Verified: S1 again, exit 0; `make
  typecheck`; `make check`; the fork and the frontend still build on the
  stock Idris; no closure in `ImpDecl` captures a cell (review).
- **S3, the pipeline** (owner's machine, arm64 macOS, after 0002's build
  and acceptance). `idris-mlir M -o front -mlir-timing` from S1's module
  (a `.mlirbc` input is read, never removed: `lib/Driver/Artifacts.cpp:
  64-66`), with `tools/profile.sh`. A refusal (`cycle`, `uniqueness`) or
  internal error is fixed where its rule's design is. Recorded: the label
  solve against 10 s and the optimizer against 600 s (the pipeline
  cutover's §10 at 484d6403), the pipeline's peak memory apart. D4 says
  when a figure holds back S4.
- **S4, `make self` on arm64 macOS** (owner's machine). `tools/self.sh` as
  D5 and D6 amend it. Verified: stage 2 = stage 3; each stage's time and
  peak memory, and D5's record, in HANDOFF.md.
- **S5, `make self` on x86_64 Linux** (the Linux machine, after 0005's
  Linux build and suite). The same, there. `make self` holds then (D8).

After it, not in it: G1 (0005, re-cut to follow `make self`), the test
machinery under both hosts (D7), the toolchain bump (0004), and
0013's features, which may start then.

### S2.1 The handoff writes each data type once

Part of S2: the next blocker after d1dc847e. A frontend that admits the
pending polymorphism refusals reached emit on the self compile (62,634
functions, 5,861 data instances) and never wrote the module (*measured*,
/tmp/0014-S2b, /tmp/0014-S2c). The cause is the format. Every type entry is
its own text (`MLIR/Bytecode.idr:5-7, 221-224`), and the text of a data type
holds the body of every data type it holds, except inside its own body
(`foreign/idr/lib/IR/DataBody.cpp:105-156`, built by `Emit/Index.idr:92-129`).
That text has one body for each simple path through the type graph. On the
self module the graph has 14,200 field references and mutually recursive
groups of 54, 53, 28, 28 and 14 instances. One instance's text has more than
300 M bodies (*measured*: exact count against the dumped graph, matching
every data entry of `programs/data/sortedmap`). No writer can emit that.

**Representation.** A data type is written once per module: its body is in
the module's table of data types, and every other occurrence names it by its
place in the table. Each type and attribute that can hold a data type is
written as an entry of its own, which refers to what it holds by entry
number. Entries are numbered by what they hold, not by their text. Bytecode
holds no data type's text. The cutover changes every `.mlirbc`, and nothing
else the frontend writes (*decision*, the coordinator, 2026-10-16).

#### (1) The entries

Notation: `v` is a PrefixVarInt, `sv` a zigzagged one
(`BytecodeWriter.cpp:253-255`), `b` one byte. `s` is a string, written as
its number in the string section. `t` and `a` are type and attribute entry
numbers. `a?` is `v 0` for none and `v 2n+1` for entry `n`
(`BytecodeWriter.cpp:411-417`). `[x]` is `v` count, then that many `x`. An
entry's first `v` is its code, its record's place in its dialect's `elems`
(`BytecodeDialectGen.cpp:107-124`). Every such entry is flagged custom in the
offset section (`BytecodeReader.cpp:1336-1338`).

The idr dialect: a new `foreign/idr/include/idr/IR/IdrBytecode.td`, in
upstream's DSL (`mlir/IR/BytecodeBase.td`), read by `mlir-tblgen
-gen-bytecode -bytecode-dialect="Idr"` (*decision*). Its records, verbatim
for every write set:

    include "mlir/IR/BytecodeBase.td"
    class Idr_Enum<string name> :
      WithParser <"succeeded(readEnum($_reader, $_var, ::idr::symbolize" # name # "))",
      WithBuilder<"$_args",
      WithPrinter<"$_writer.writeVarInt(static_cast<uint64_t>($_getter))",
      WithType   <"::idr::" # name>>>> { string enumName = name; }
    def Idr_TableRef : WithType<"::mlir::ArrayAttr", Attribute>;
    def DataType : DialectTypeNoPrint<(type
      WithGetter<"::mlir::ArrayAttr()", Idr_TableRef>:$table,
      WithGetter<"uint64_t(0)", VarInt>:$index)> {
      let cBuilder = "::idr::DataType::member(reader, table, index)"; }
    def QType : DialectType<(type Idr_Enum<"Quantity">:$quantity,
      Idr_Enum<"Permission">:$permission, Type:$value)> {
      let cBuilder = "QType::getChecked([&]() { return reader.emitError(); }, context, $_args)"; }
    def FnType : DialectType<(type WithType<"::mlir::FunctionType", Type>:$function_type)>;
    def LazyType : DialectType<(type Type:$value)>;
    def BoxType : DialectType<(type WithType<"::idr::DataType", Type>:$data)>;
    def DestType : DialectType<(type Type:$value)> {
      let cBuilder = "DestType::getChecked([&]() { return reader.emitError(); }, context, $_args)"; }
    def DataTable : DialectAttribute<(attr
      WithParser<"succeeded(::idr::DataType::readTable($_reader, $_var))",
      WithBuilder<"$_args", WithPrinter<"", WithType<"::mlir::ArrayAttr">>>>:$table)> {
      let cType = "::mlir::ArrayAttr"; let cBuilder = "table"; let printerPredicate = "false"; }
    def IdrDialectTypes : DialectTypes<"Idr"> {
      let elems = [DataType, QType, FnType, LazyType, BoxType, DestType]; }
    def IdrDialectAttributes : DialectAttributes<"Idr"> { let elems = [DataTable]; }

So the idr type entries, by code, are:

| Code | Type | Layout |
| --- | --- | --- |
| 0 | data type | `a` (the table), `v` index |
| 1 | `q` | `v` quantity value, `v` permission value, `t` value |
| 2 | `fn` | `t` (a builtin function type) |
| 3 | `lazy` | `t` |
| 4 | `box` | `t` (a data type) |
| 5 | `dest` | `t` |

The idr attribute entry with code 0 is the table, whose layout is in (2).
The enum values are ODS's (`IdrBase.td:80-88, 104-107, 124-127`).
`IdrBytecode.td` includes only `BytecodeBase.td`, as upstream's bytecode
files do, because ODS's own `class Type` and other names would sit beside
the DSL's defs. `Idr_Enum` names the C++ enum, and the Idris enum of the
same name.

The builtin entries are upstream's records, not restated
(`BuiltinDialectBytecode.td`):
- `ArrayAttr` (attribute code 0, `[a]`, :35);
- `DictionaryAttr` (code 1, `[a a]`, name then value, :52-61);
- `TypeAttr` (code 6, `t`, :72);
- `FunctionType` (type code 2, `[t] [t]`, :269);
- `MemRefType` and `MemRefTypeWithMemSpace` (codes 10 and 11, `[sv] t a`
  and `a [sv] t a`, :328-345);
- `RankedTensorType` (code 13, `[sv] t`, :155).

Every other kind stays a text entry, as now: builtin integer, `f64`,
`index`, `none`; idr `str`, `big`, `nat`, `world_carrier`, `token`; strings,
integers, floats, symbol references, dense arrays, locations; and every idr,
arith and ub attribute. None of them can hold a data type the handoff writes
(*read*: what `Emit` and `Dialect/*.idr` build). If a text entry held one,
the C++ parser would refuse it (`DataBody.cpp:151-156`), so that boundary
exists already. `DictionaryAttr::get` sorts its entries
(`BuiltinAttributes.cpp:141`), so the writer keeps the op's own order.

Where the DSL falls short (*read*), and what custom C++ remains, all of it
in a new `foreign/idr/lib/IR/Bytecode.cpp`:
- **The data type is read-only.** The pinned writer never asks a dialect to
  encode a mutable type (`BytecodeWriter.cpp:894-899`). The generator still
  emits a printer under a false predicate, so its getters must compile
  (`BytecodeDialectGen.cpp:333-347`); hence `DialectTypeNoPrint` with
  constant getters. `idris-mlir-opt --emit-bytecode` keeps writing data types
  as text, which the parser keeps reading. Upstream's own precedent: LLVM's
  identified struct has no encoding and is written as text. LLVM's recursive
  debug-info attributes cut their cycles in the IR, with `recId` and
  `isRecSelf` (`LLVMDialectBytecode.td:184-205`).
- **The table can't be declared in the DSL.** The DSL parses members into
  independent locals and builds once at the end
  (`BytecodeDialectGen.cpp:206-304`). A body's field must name members the
  read has already made, so the payload is one custom member: `static
  LogicalResult DataType::readTable(DialectBytecodeReader &, ArrayAttr
  &table)`.
- **There is no enum kind in BytecodeBase.td.** `Idr_Enum` names a helper,
  `template <typename E> LogicalResult readEnum(DialectBytecodeReader &, E &,
  std::optional<E> (*)(uint32_t))`, which refuses a value that is no case.
- **The generated builder has no checked form.** It falls back to `get` for
  a type whose `getChecked` takes a context
  (`BytecodeImplementation.h:476-505`), so `QType` and `DestType`, which
  verify, name their own `getChecked`.
- **A field of the table is no entry.** `FieldReader`, a
  `DialectBytecodeReader` that forwards everything to the reader it wraps,
  overrides only `readType(Type &)`, which reads a field as in (2). Through
  it the generated readers of idr's records and builtin's interface
  (`BuiltinDialectBytecode.cpp:550-575`) read records nested in the table
  unchanged.
- **Dispatch and registration.** `static Type DataType::member(...)`
  bound-checks `index` and returns that entry of the table, which must be a
  `TypeAttr` of a `DataType` whose body is set. The interface is as builtin's
  (`:550-575`), over the generated dispatch, and is registered by
  `detail::addBytecodeInterface(IdrDialect &)` from
  `IdrDialect::initialize` (`lib/IR/Dialect.cpp:47-59`).

#### (2) The table

One table per module holds every data instance of the program, in
`src.datas` order. Member `k` is the `k`th (*decision*; the alternative, one
entry per mutually recursive group, is rejected below). Its attribute entry
is code 0 of idr's attributes, laid out:

    v n, n × s name                    the members, in order
    n × Body
    Body:  v kind (SumKind), [Ctor], a? instance (#idr.instance)
    Ctor:  s name, v role (CtorRole), b byName, a? fn (FlatSymbolRefAttr), [Field]
    Field: v 0, t       a type that holds no data type: its entry
           v 1, v k     member k
           v 2, record  an idr type record, its code then its members
           v 3, record  a builtin type record, likewise

Inside a field's record, each type member is a field again, and each
attribute member is an entry (`a`). A data type inside the table is always a
member (code 1). This layout lives once, in a comment above `DataTable` in
`IdrBytecode.td`. Its two implementations, the C++ reader and the Idris
writer, are checked against each other by the gate.

The four field codes are essential, not a flag. A data type names the table
(1); a type that holds none is shared as an entry (0); a type that holds one
is written in place, as a record of one of the two dialects the handoff's
types come from (2, 3).

How the pinned reader accepts it (*read*):
- **Entries are read lazily, recursively, and once.** An entry is read the
  first time something refers to it, and then kept
  (`BytecodeReader.cpp:1462-1490`). A custom entry is read by its dialect's
  interface (`:1493-1550`).
- **A data type's entry reads the table first.** It reads the table entry
  (`readAttribute<ArrayAttr>`) and only then member `k`. The table refers to
  no data type's entry and not to itself: its `t` fields hold no data type,
  and its `a` refs are an instance and a label's function. So the reads form
  no cycle. In the plain pinned reader a cycle would make the deferral
  worklist retry without end (`:1411-1456`, *read*); the reader we build
  carries `upstream/03-bytecode-deferred-quadratic`, which reports it as
  `cyclic reference to attribute index: N`. An optional reference (`a?`)
  resolves without deferring, so a cycle through one would recurse until
  the stack ends, in both readers (`:928-938`, *conjecture* until reduced
  to upstream alone, e.g. a self-referring LLVM debug-info attribute). A
  well-formed table reaches neither: no table field holds a data type's
  entry or one that holds it.
- **`readTable` makes every member before reading any body.** It calls
  `DataType::get` (`Types.cpp:130-132`) for every member, refusing a
  repeated name. A field of code 1 is then that member, still without its
  body, as `!idr.data<"T">` is inside T's own body in the parser
  (`DataBody.cpp:148-158`).
- **Bodies are set in member order, after all are read.** `setBody` checks
  each (`Types.cpp:199-205`). A body may hold a member whose body is not set
  yet, as the parser sets an inner body before the outer one
  (`DataBody.cpp:211`). `verifyBody` and the type verifiers read field
  kinds, never bodies (`Grades.cpp:253-262`, `Types.cpp:299-317`).
- **A deferral leaves no body set.** If a field's entry is deferred
  (depth 5, `BytecodeReader.cpp:1082, 1114-1140`), the table fails before any
  body is set. The worklist reads the deferred entry, then the table again
  from its start, and `get` returns the same members.
- **`readTable` returns `ArrayAttr` of `TypeAttr` of the members.** That is
  the list of the module's data types, a value MLIR already has. Its entry
  sits in idr's group, and the reader does not compare the two
  (`:1547-1550`).

The alternative is rejected: one entry per mutually recursive group, with
other groups' types as entries. It would need a total SCC algorithm in the
frontend, and two ways for a body to name a data type. It buys nothing,
because the driver reads the whole module (`lib/Driver/Run.cpp:307`,
`parseSourceFile`, not lazy) and the table is read once, at the first data
type.

#### (3) The Idris side

**The generator.** `idris-mlir-tblgen -gen-idris-bytecode -idris-dialect=D
-idris-module=IdrisMLIR.Encoding.M -idris-syntax-module=IdrisMLIR.Syntax.M`
reads a bytecode `.td`: `IdrBytecode.td` for idr, and upstream's
`BuiltinDialectBytecode.td` for builtin. It writes
`compiler/src/IdrisMLIR/Encoding/Idr.idr` and `Encoding/Builtin.idr`, with
fingerprints, through `tools/dialects.sh`. Its `dialects()` gains a fourth
column, the bytecode `.td` or `-`, and its `modules` a third kind,
`bytecode:Encoding`. Per record:
- `<lowerCamel record>Code : Nat` is generated for every record, from its
  place in `elems`.
- `encode<Record>` is generated for each record whose member kinds the
  generator knows, by their parser template, which `WithType` and
  `WithGetter` keep (`BytecodeBase.td:54-63`). Its parameters are the
  record's members, in order. It returns `List Part`, starting `VarInt
  code`. The kinds map like this:

| Member kind | Idris parameter |
| --- | --- |
| VarInt | `Nat` |
| SignedVarInt | `Integer` |
| Bool | `Bool` |
| `readString` | `String` |
| an attribute | `AttrRef` |
| a type | `List Part`: `[TypeAt r]` in an entry, a field in the table |
| `Array<k>`, `List<k>` | `List k` |
| a composite | a tuple of its members |
| `Idr_Enum<E>` | `E`, from the syntax module, written as `<lowerCamel E>Value` |

- Records with any other member (`LocalVar`, a custom parser, `Blob`,
  `KnownWidthAPInt`, …) are left out, with the reason, in the module's
  trailing comment, as `-gen-idris-syntax` leaves types out.

For idr this gives:
- `encodeDataType : AttrRef -> Nat -> List Part`;
- `encodeQType : Quantity -> Permission -> List Part -> List Part`;
- `encodeFnType`, `encodeLazyType`, `encodeBoxType` and `encodeDestType`,
  each `List Part -> List Part`;
- `dataTableCode`, with `DataTable` left out.

For builtin it gives:
- `encodeArrayAttr : List AttrRef -> List Part`;
- `encodeDictionaryAttr : List (AttrRef, AttrRef) -> List Part`;
- `encodeTypeAttr : List Part -> List Part`;
- `encodeFunctionType : List (List Part) -> List (List Part) -> List Part`;
- `encodeRankedTensorType : List Integer -> List Part -> List Part`;
- `encodeMemRefType : List Integer -> List Part -> AttrRef -> List Part`;
- `encodeMemRefTypeWithMemSpace : AttrRef -> List Integer -> List Part ->
  AttrRef -> List Part`.

The type member's encoding is one parameter, so one encoder per record
serves both entries and fields: one layout, from its record.

`-gen-idris-syntax` changes in two ways:
- **Enum values.** It writes `<lowerCamel E>Value : E -> Nat` beside each
  enum, from its cases' values (`quantityValue`, `permissionValue`,
  `sumKindValue`, `ctorRoleValue`, …): the value stays with the enum.
- **The identified type** (`idris-mlir-tblgen.cpp:1590-1650`). Its
  constructor becomes `DataType : (name : String) -> IdrType ty`, and its
  text the name form `!idr.data<"name">`, which only content keys read. The
  body records `IdrSum` and `IdrCtor` stay; they are the table's.
  `idrCtorText` is deleted. A body in a type is then unrepresentable on the
  Idris side.

**The parts.** A new leaf, `compiler/src/IdrisMLIR/MLIR/Parts.idr`, imported
by the generated modules and the writer, verbatim:

    public export record TypeRef where { constructor MkTypeRef; number : Nat }
    public export record AttrRef where { constructor MkAttrRef; number : Nat }
    public export
    data Part = VarInt Nat | SignedVarInt Integer | Flag Bool | Str String
              | TypeAt TypeRef | AttrAt AttrRef | OptionalAttrAt (Maybe AttrRef)

Their bytes are `v`, `sv`, `b`, `s`, `t`, `a` and `a?`, as in (1).

**`MLIR/Bytecode.idr`.**
- **Keeps:** `Bytes`, `varint`, sections, the op, region and container
  encoding, and `finish`'s sections.
- **Replaces:** the type and attribute tables keyed by text
  (`:150-177, 216-224`) with tables keyed by entry: dialect number, custom
  or text, and the entry's bytes. A custom entry's bytes are small, since
  what it holds is entry numbers, so numbering is O(log n) per use. The
  offset section flags each entry custom or not (`:374`). A text entry holds
  its text and NUL, as now.
- **Adds:**
  - `newWriter : List (String, IdrSum MlirType) -> IO (Either String Writer)`
    takes the table, numbers its fields, writes its entry, and keeps `name ->
    member` (`SortedMap String Nat`). A repeated name is an internal error.
  - `data Mode = InEntry | InTable`.
  - One function holds the one switch over the natively encoded kinds:
    `native : Writer -> Mode -> MlirType -> W (Maybe (String, List Part,
    Bool))`. It returns the dialect, the record's parts with each child
    written by mode, and whether a member is below.
  - Its callers are `typeNumber`, `field` and `attrNumber`:
    - `typeNumber` writes a data type as `encodeDataType table k` and a
      native kind as its entry; anything else is a text entry.
    - `field` writes a data type as `[VarInt 1, VarInt k]`, a native kind
      with a member below as `VarInt 2` or `3` followed by its parts, and
      anything else as `[VarInt 0, TypeAt (typeNumber t)]`.
    - `attrNumber` writes `ArrayAttr`, `DictionaryAttr` and `TypeAttr` as
      entries, and anything else as text.
  - Recursion is structural, with lists through mutual helpers as
    `typesText` (`MLIR.idr:142-144`), so totality holds.

**`MLIR.idr`.** Its header (`:3-15`) is rewritten. `MlirAttr` gains
`IdentityMap Nat`, a memref's layout at its rank (text `affine_map<(d0) ->
(d0)>`), which a memref's entry refers to.

**`Emit/Index.idr`.**
- **Deletes:** `spelled`, `Fewer`, `fewerAccessible`, `enter`, `spell`,
  `spellCtors` and `spellFields` (`:24-33, 73-121`).
- **Changes:** `typeWith : Ty -> MlirType` and `heldWith : Quantity -> Ty ->
  MlirType` become total and need no `Either`; `DataT d` is `idr (DataType
  d.name)`. `index : Source -> Index` has no `Either` either: its one
  failure was spell's unknown data, and the writer's name lookup is now that
  boundary.
- **Adds:** `table : List (String, IdrSum MlirType)` holds each instance's
  kind, constructors (fields as `heldWith q t`, `False`, the role,
  `Nothing`) and instance.

**The other Emit modules.**
- `Emit/Types.idr` deletes `spelledData`. `mlirType` and `heldType` become
  pure, without `Index`; the call sites in `Emit/Bodies.idr`,
  `Operations.idr`, `Tensors.idr` and `Declarations.idr` change
  mechanically.
- `Emit.idr:68-71` becomes `let ix = index src` and `newWriter ix.table`.
- `Closures.lift` is unchanged. Its content keys now name data types, so
  `.lam.`/`.delay.` hashes change; names identify instances, so keys stay
  one to one (*conjecture*, gated).
- `SyntaxSamples.idr:57-86` passes its data samples' bodies as the table.

#### (4) The gate

1. **Typecheck machine.**
   - `make typecheck`, with the frontend's totality enforced and
     `tools/dialects.sh check typecheck` current, then `make check`.
   - The 385 test programs (`tests/programs`, `accept`, `reject`) on Chez,
     against d1dc847e's frontend: status, stdout, stderr and Core dump
     identical byte for byte. The Core dump is `prog`'s, apart from Emit
     (`Frontend/Program.idr:197`).
2. **The owner's machine (LLVM).**
   - `make build`, then `make test`. Every test program's module is read and
     verified by `idris-mlir` (`lib/Driver/Run.cpp:307`), which is the
     property that the C++ reads every module the frontend writes. `make
     test` also runs `tests/compiler/dialect-syntax`, the samples' module
     (`Makefile:17-21`).
   - `make test-idr`, which includes `tests/idr/syntax/constants.mlir`'s
     bytecode round trip through the C++ writer; then `make test-unit` and
     `make test-mlir-tools`.
   - A one-time migration check, not committed. One `idris-mlir-opt
     --mlir-disable-threading` prints each new module and d1dc847e's, which
     the unchanged parser still reads. The prints must be identical, aliases
     included, after a mapping of `.lam.`/`.delay.` names checked to be one
     to one.
3. **The self compile.** The scratch frontend of S2b's `emit_patch.py`, on
   the typecheck machine, killed past 30 min or 24 GB. Emit finishes.
   Recorded under `bench/profiles/`: emit's time, peak memory, the
   functions, the `.mlirbc`'s bytes and the table entry's bytes. Expected:
   emit linear in the module. The table is about the 0.73 MB of instance
   names (*measured*, the dumped graph) plus the fields (*conjecture*).

#### (5) Write sets

Disjoint. Each writes against the declarations above: `IdrBytecode.td`'s
text, the table's layout, `Parts.idr`, the generated signatures,
`DataType`'s constructor, `newWriter`, and the C++ declarations `static Type
DataType::member(DialectBytecodeReader &, ArrayAttr, uint64_t)`, `static
LogicalResult DataType::readTable(DialectBytecodeReader &, ArrayAttr &)` and
`void idr::detail::addBytecodeInterface(IdrDialect &)`.

- **A, the C++ dialect.**
  - Writes `include/idr/IR/IdrBytecode.td` (new: the text above and the
    layout comment); `IdrTypes.td` (DataType: the two statics in
    `extraClassDeclaration`, and its comment, `:30-43`); `IdrDialect.h`
    (the registration's declaration, beside `addAsmInterface`, `:358`);
    `lib/IR/Bytecode.cpp` (new: the `.inc`, the interface, `readEnum`,
    `FieldReader`, `readTable`, `member`); `lib/IR/Dialect.cpp` (the
    registration call); and a `PINS.md` entry, since the reader reads a
    custom-encoded mutable type that the pinned writer never writes.
  - Inputs: this section. Output: the dialect reads the table and the
    entries.
  - Verified by `make typecheck`'s C++ part, then by gate 2.
- **B, the generator.**
  - Writes `foreign/idr/tools/idris-mlir-tblgen.cpp` (the new
    `-gen-idris-bytecode`; `-gen-idris-syntax`'s identified type; the
    header, `:41-46`); `tools/dialects.sh`; the generated
    `compiler/src/IdrisMLIR/Encoding/{Idr,Builtin}.idr`; and the regenerated
    `Syntax/Idr.idr`.
  - Inputs: `IdrBytecode.td` exactly as above, copied privately until A
    lands; upstream's `BuiltinDialectBytecode.td`. Output: modules with the
    signatures of (3).
  - Verified by `tools/dialects.sh generate typecheck`, then `check`.
- **C, the Idris emit.**
  - Writes `compiler/src/IdrisMLIR/MLIR/Parts.idr` (new),
    `MLIR/Bytecode.idr`, `MLIR.idr`, `Emit.idr`, `Emit/{Index,Types,Bodies,
    Operations,Tensors,Declarations}.idr`, `SyntaxSamples.idr`,
    `compiler/idris-mlir.ipkg` and `compiler/syntax-samples.ipkg` (the
    modules `IdrisMLIR.MLIR.Parts`, `IdrisMLIR.Encoding.Idr` and
    `IdrisMLIR.Encoding.Builtin`).
  - Inputs: B's modules, or their signatures above until they land.
  - Verified by gate 1.
- **D, the CMake hub text.**
  - Writes `include/idr/IR/CMakeLists.txt`: `set(LLVM_TARGET_DEFINITIONS
    IdrBytecode.td)` and `mlir_tablegen(IdrBytecode.cpp.inc -gen-bytecode
    -bytecode-dialect="Idr")`, inside `IdrOpsIncGen`, then restoring
    `IdrOps.td`.
  - Writes `lib/IR/CMakeLists.txt`: `Bytecode.cpp` in `IdrIR`.
  - Lands with A.
- **E, the gate and the record.** Scratch scripts in `/tmp`, the
  `bench/profiles/` record, and this proposal's status line. Gate 1 and 3 on
  the typecheck machine; gate 2 on the owner's machine, after A to D.

Out of S2.1 (*read*, recorded for S3):
- `idris-mlir-opt --emit-bytecode` still writes data types and `#idr.con` as
  text, as now.
- The C++ content keys print every alias a type reaches
  (`ContentNames.cpp:85-106`), O(reachable types) per key on the self
  module.

## 5. Alternatives rejected

- A compiler case for the fork: exempting a trusted library from the
  static-argument rule, the knot rule or the pragma rule. Each is a branch
  by origin, and the subset is deliberate (47f97059); the fork is ours.
- An `assert_total` at each refused site: a trust is stated once
  (AGENTS.md); a site's assertion is a second copy of it.
- Comparing stage 1's module with stage 2's: stage 1's frontend runs on
  Chez, so the comparison makes Chez's meaning a gate (no oracle).
- Measuring S3 on F0's module: it is text in the dialect before the
  cutover, which the pipeline no longer reads.
- Running all of `make self` before S1: an owner's machine cycle to learn
  what the typecheck machine can, since every frontend refusal is decided
  before any MLIR exists (the pipeline cutover's §2.5).
- Breaking the knot with a weak reference or a collector: the heap is
  acyclic by the memory model, which counting rests on.

## 6. Decisions

- D1. S1 runs on the typecheck machine before the owner's build. Reason:
  the frontend runs on Chez and needs no LLVM, which that machine may run
  (the owner, 2026-10-15); only the pipeline's half needs the owner's.
- D2. A refusal is fixed in the code it names, never in the compiler's
  rules. In the fork: a definition is made total where its recursion is
  the fork's own; where it is Idris's theory's (a call of the evaluator or
  the elaborator, or a recursion on what the evaluator returns, as
  `Reify`'s), it rests on the one stated trust, `Idris.Host`'s, extended
  there (its evaluator fields split into a module below `Core.Reflect` if
  an import cycle forces it), never on a new assertion at the site. Which
  of the two each refusal is, S1's list says (*conjecture* until then).
  Reason: R4, and one thing, one representation.
- D3. The pragma actions stop holding the cell: the desugarer's actions
  become first-order data that `IPragma` holds and the processor
  interprets with every cell in hand, as the action is already given
  `Ref DLY` (`TTImp/TTImp.idr:486-489`). Reason: a closure that captures a
  cell is the state the data makes unrepresentable; `TTImp`, below
  `Idris.Syntax`, cannot name `SyntaxInfo` to take it as an argument
  (`compiler/idris/README.md:470-471`). Verified first by review, then by
  S3's verifier.
- D4 (was 0005's D10). The diet and the memory are a record, not a gate,
  unless a stage does not fit the owner's machine or does not finish;
  then the stage the record names is fixed first, where its design is
  (the frontend's memory: 0010; the optimizer and labels: S3, by the
  cutover's §10 rule; LLVM: 0007's split before O3). The frontend's and
  the pipeline's peaks are recorded apart (S1, S3).
- D5 (was 0005's D16). `make self` compares at the default thread count.
  Thread independence is `tests/determinism` on every suite run and one
  record of stage 3 compiling itself at the counts `tests/lib/
  determinism.sh:14` names (1, 3, 5, 13 and a second process), read from
  there. Reason: the counts are one fact, in one place.
- D6. Each stage copies `compiler/src` afresh into `build/self/src` before
  it runs, and stages 2 and 3 compare the TTCs that copy's build holds.
  Reason: `self.sh:31-32` copies once, so stages 2 and 3 load the TTCs
  stage 1 wrote and the native elaborator never runs on the frontend
  (*read*; the fork's up-to-date check reusing them is *recalled* from
  upstream). One path, since locations carry it. Each stage runs stage
  N-1's `idris-mlir-front` alone, then its `idris-mlir` on the `.mlirbc`:
  the driver removes the module when a later step fails (§3.3), and the
  two peaks are D4's. The artifacts compared keep their names.
- D7 (was 0005's D11, restated). The test machinery also builds and runs
  under idris-mlir, and the stock host keeps running it: its process
  creation moves into sh glue and its imports to base. After `make self`;
  the owner is 0001's X3 and N lanes' successors.
- D8. `make self` holds when stage 2 = stage 3 on both targets, recorded
  in HANDOFF.md. This proposal is deleted then.

## 7. Open, for the owner

Nothing. The guard's scope (§3.2(a)) was decided by the owner on
2026-10-15, and S1 runs on the typecheck machine under the owner's
standing permission to build anything but the LLVM project.
