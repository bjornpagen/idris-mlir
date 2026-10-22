<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: compile-time C++

*Written 2026-10-21 by P0's compile-time C++ design agent. It is a
design for the owner and the coordinator: it decides what the owner has
already ruled, and marks every other choice as a proposal.*

**The rulings this design answers to** (2026-10-21, quoted from
synthesis F DP-04 and DP-08, AGENTS.md, and the owner's words as the
coordinator relayed them):
- "heavy use of templates and concepts" (stressed);
- "we should push on this maximally insane compile time c++
  requirement. I will not accept any plan that does anything less than
  this";
- one centralized effect system, "defined and monomorphized in a single
  place" (DP-04);
- every change is a hard cutover that culls the old code;
- upstream MLIR first;
- AGENTS.md's new rule: "NO FACT KNOWN STATICALLY, RIGHT NOW OR IN
  PRINCIPLE, MAY EVER BE PAID FOR AT RUNTIME". This holds both when the
  compiler runs and when a compiled program runs.

The line between interfaces and concepts is settled (DP-08). MLIR's
interfaces, traits and rooted patterns handle anything over ops, types
and attributes. Concept-constrained templates handle our own C++. A
concept may read an ODS fact but may never list ops.

**What this document decides.** Where each static fact lives, how it
reaches C++, how C++ dispatches on it, and what is left at run time and
why. It does not decide:
- what the effects mean. That is DP-01 to DP-03, and the design agent
  writing `audits/p0/design/effects.md`. That file did not exist when
  this was written, so §2.3(d) sets out the slots it fills.
- the solvers' algorithms (synthesis B);
- the op set (synthesis A).

The other design input, `audits/p0/design/perf-sources.md`, is folded
in: its causes C1 to C14 in §5 and its rules R1 to R13 in §5.3.

## 0. Grounds and citations

- *Read*: a `path:line` (ours at e96bb991 unless marked `main:`, which
  is origin/main at 1e1907ab; upstream under `.toolchain/llvm-project`
  at 7208ba24). *Measured*: a count with its command, or a record.
  *Conjecture*: everything else. No build was run for this document.
- Every C++ feature used here is present in the pinned clang (24.0.0git)
  and libc++. The citation for each is the wave-1 feature matrix,
  `audits/p0/wave1/5.5-cxx26.md` §B, or `clang/www/cxx_status.html` for
  features that matrix does not list. "Compiles in principle" means a
  sketch uses only such features. None of the sketches was compiled. A
  sketch marked *pin-only* uses a feature that the pinned clang has but
  the host clang 5.5 measured with lacks.
- Short forms used throughout:
  - `5.5 F12`: wave-1 lane 5.5 (`audits/p0/wave1/5.5-cxx26.md`), finding
    12. `5.3 B7` and `5.2 row 12` work the same way.
  - `08 C-51`: issue C-51 of `audits/p0/08-counting.md`.
  - `12 T1`: lane 12's target-design item T1.
  - `A §2.7`: synthesis A.
  - `DP-73`: decision point 73 in synthesis F.
  - `PS C2`, `PS R5`: `audits/p0/design/perf-sources.md`.
  - `flame`: `origin/main:audits/flamegraph-2026-10-21.md`.

## 1. The principle

### 1.1 Five times, and what each may decide

| time | what exists | decides | checked by | may never decide |
| --- | --- | --- | --- | --- |
| **T0, TableGen** | the records | every closed set (ops, families, enums, resources, rules, endings, passes, steps); every relation between records (op to runtime function, op to stages, op to effects, pass to stage chain, rule to category) | TableGen `assert` for a fact inside one record; the generator's typed model (`PrintFatalError` naming both records) for a fact across records | anything about a program |
| **T1, building the compiler** | the generated headers and our templates | the layout of every table (an array indexed by a dense generated enum); every derived closure (resource ancestors, the conflict matrix, the grade algebra's laws); the code that runs for each case of every closed set (templates, concepts, `match`); one instantiation per solver | `static_assert` over `consteval` validators, with generated messages (P2741R3, Clang 17); concepts at every template boundary; `-Wswitch` exhaustiveness on generated enums | anything a context or a program holds |
| **T2, pass construction** (MLIR's `Pass::initialize`, `mlir/include/mlir/Pass/Pass.h:183-191`) | a context with its dialects loaded | what MLIR can only make inside a context: frozen pattern sets, conversion targets, type converters, the attributes and types a pass writes that do not depend on the program | a failing `initialize` stops the pipeline (`mlir/lib/Pass/Pass.cpp:482-516`) | anything per function or per op |
| **T3, the compiler running** | the program | facts about the program: numberings, graphs, solutions, the IR it writes | the verifier after every pass | a static fact: computed again, looked up, string-compared, hash-looked-up or rebuilt |
| **T4, the compiled program running** | the program's input | only what was unknown when the compiler ran | nothing; the compiler decided everything else | anything the compiler knew: a grade, a component kind, staticness, a crash site and its cause, a key set, an element size, the target's CPU baseline |

T3 is T4's build. Every fact the compiler holds about a program, it
compiles into that program as a constant: a specialized entry point, a
folded test, a constant operand. The compiler applies the same rule to
the program that its own build applies to it.

### 1.2 The rules

- **R1. One record.** Every static fact has exactly one TableGen record.
  C++ in the compiler, C++ in the runtime, the Idris side and the tests'
  tables are all generated views of it (AGENTS.md: "Generate the second
  copy from the first, or delete it").
- **R2. A closed set is a generated enum, dense from zero.** Its count
  is generated beside it, never a `Count` enumerator: a sentinel is a
  value of the type that names no member. Every table over the set is
  an `EnumArray` indexed by it, and is checked complete at T1. The
  generator refuses an `EnumInfo` whose case values are not 0 to n−1.
  `Idr_Quantity` is 1 and 2 today (*read*:
  `foreign/idr/include/idr/IR/IdrBase.td:83-84`).
- **R3. A static fact is found by indexing, never by searching.** It is
  never a search, a hash or a string comparison.
  - SearchableTables emits a direct index when the key is dense and
    integral, and a binary search otherwise (*read*:
    `llvm/utils/TableGen/SearchableTableEmitter.cpp:9-12`).
  - Every key here is a dense generated enum, so every lookup is the
    direct case.
- **R4. A fact is checked where it first exists.**
  - A fact inside one record: by `assert` at T0.
  - A fact across records: by the generator at T0.
  - A fact that needs a C++ type (a signature, a law, the order of an
    index): by `static_assert` at T1.
  - Validation at T1 stays linear. A check of O(n²) or worse runs at T0,
    since constexpr evaluation is capped at 1,048,576 steps (*read*:
    `clang/include/clang/Basic/LangOptions.def:391`).
  - A check repeated at a later time is deleted.
- **R5. Dispatch over `Operation *` happens once per op per walk, through
  MLIR, then the code is typed.**
  - MLIR's mechanism is an interface, a trait or a rooted pattern.
  - Below that dispatch the code is typed: `Model<ConcreteOp>`,
    `OpRewritePattern<OpT>`, `Family<OpT>`.
  - Over our own types, run-time dispatch happens only on program data:
    which alternative a value holds. The code for each alternative is
    chosen at T1.
- **R6. Every choice is a type or an enum case, never a `bool`.**
  - Directions are types: `Forward`, `Backward`.
  - Family constants are enum cases: `Signedness::Signed`,
    `DivPart::Quotient`.
  - A solver's budget policy is a type.
  - Today there is `mark(seeds, bool backward)` (08 C-51), and the
    family constants are `static constexpr bool quotient, isSigned,
    left` (*read*: `foreign/idr/include/idr/IR/IdrScalarOps.td:23-36`,
    `lib/IR/Ops.cpp:225-232`).
- **R7. A callback is a template parameter constrained by a concept.**
  `function_ref` stays only where an MLIR or LLVM API takes one; §6
  lists each such site.
- **R8. An id is typed and dense, minted only by its owner, and it is
  the only index of its state.**
  - Indexing by a raw integer is `= delete("...")` (P2573R2, Clang 19).
  - A map keyed by `Value *`, `Operation *` or `Block *` exists only
    inside a builder that is numbering, and is freed with it.
- **R9. A name is printed text, never an identity.** No string
  comparison and no string-keyed map exists below the parser and the
  printer. This holds in the generator too: it classifies records by
  their TableGen class, not by C++ spelling (14 T06; 20 §4.3, the
  `getName() == "Idr_` probe).
- **R10. A pass makes what does not depend on the program once, at T2.**
  - That means everything a pass makes in the context that does not
    depend on the program.
  - Nothing static is built per function or per op (PS C2; flame,
    finding 1).
  - No worker creates an attribute or a type (PS R3).
- **R11. No virtual function of ours except an override MLIR requires.**
  - Today: `Labels::Statements` (06 L-5); `specialize::Schedule` (09
    OPT-22); `StagedPass::runOnProgram` (*read*:
    `foreign/idr/include/idr/Transforms/Pipeline.h:44`).
  - §4.9 removes the last of these.
- **R12. A solver keeps one value per node: fixed-size and trivially
  copyable.** A set-valued fact is a graph and a marking, never a
  lattice element (b8301ebe; PS C8).
- **R13. Monomorphized, instantiated once.** Every solver template has
  one explicit instantiation in its client's unit, with `extern
  template` everywhere else (DP-08: Q-llvm-1).
- **R14. A budget's existence is a type.**
  - An analysis a refusal rests on takes the `Acceptance` policy, which
    has no budget field.
  - An optimization takes `Optimization{Steps}`, a count in the
    program's units.
  - So "a spent budget refuses a program" cannot be written (AGENTS.md;
    B §2.6).

### 1.3 What is never decided at run time

**When the compiler runs**, none of these is decided:
- which family an op belongs to, and that family's constants;
- whether an op calls the runtime, and with what signature;
- an op's static effects, every derived relation between resources, and
  every rule by which an effect follows from a type (the operand's type
  is program data; the rule is not);
- the stages an op is legal at;
- a pass's stage contract, position, nesting, role, action tags and
  statistics;
- a rule's category and scope;
- an ending's status and text;
- a guard's operand indices, and a crash cause's message;
- a data-body kind's roles;
- an ABI kind's C type, LLVM type and passing rule;
- a lattice's height, laws and direction;
- the code that handles an alternative;
- every name.

**When a compiled program runs**, none of these is decided:
- the grade of a value: an exclusive value is unique without a test, a
  frame value is never unique, and a static value is never counted;
- the kind of a component word: a cell is not tested for NULL, and a
  non-big word is not tested for the odd bit;
- which fields of a cell move;
- where a crash happens, why, and its status;
- the element size of a copy;
- a match's key set (sorted at compile time);
- which CPU features the target's baseline guarantees.

What may be decided at T3:
- which registered op an `Operation *` is, once per op per walk;
- facts about the program;
- the identities a context hands out: TypeID addresses, and the
  pointers of uniqued attributes and types.

What may be decided at T4: the program's input, the machine (page size,
CPU features beyond the baseline, the address space), and the program's
data.

### 1.4 What cannot be compile-time, and why

- **`TypeID` is an address assigned at run time** (MLIR's design, so
  that types stay unique across shared objects). So no constexpr table
  can be keyed by it.
  - Mapping an `Operation *` to our dense op index costs one interface
    lookup: a binary search of the op's interfaces, sorted by TypeID
    (*read*: `mlir/include/mlir/Support/InterfaceSupport.h:268-283`).
  - No constexpr perfect hash over TypeIDs exists.
- **The identity of attributes and types is context uniquing.** A hash,
  and a shard lock on creation (*read*: PS C4,
  `mlir/lib/Support/StorageUniquer.cpp:160-206`). Any attribute or type
  the compiler writes is made at run time. This design confines that to
  T2 and to IR the program genuinely needs.
- **MLIR builds its own run-time structures**, and they cannot move:
  - interface maps, at registration;
  - pattern indices, at freeze (*read*:
    `mlir/lib/Rewrite/FrozenRewritePatternSet.cpp:63-141`);
  - the pass manager's schedule and its clones (*read*:
    `mlir/lib/Pass/Pass.cpp:927-931`);
  - dialect registration.
- **The program.** Its call graph, data bodies, numbering and values are
  T3 facts. For T4 they are compile-time facts.
- **Upstream code we call** dispatches as upstream wrote it: the greedy
  driver, the conversion driver, CSE, bufferization, the LLVM backend.
- **The machine a program runs on.** Its page size and its CPU beyond the
  target's baseline are checked once at startup (AGENTS.md permits cpuid
  in the target's startup check, and nowhere else).

## 2. The one source and its generators

### 2.1 Who generates what

**Upstream `mlir-tblgen`** generates everything it already can, unchanged:
- op, type, attribute and enum declarations and definitions;
- interfaces and the dialect;
- bytecode (`-gen-bytecode`);
- passes (`-gen-pass-decls`, with `GEN_PASS_REGISTRATION`);
- DRR patterns.

It also gains `-op-shard-count`, so the op definitions compile in
parallel (*read*:
`mlir/tools/mlir-tblgen/OpGenHelpers.cpp:34-35, 91-100`; the CMake side
is `add_sharded_ops`, `mlir/cmake/modules/AddMLIR.cmake:159`; §7.3).

**Ours: `idris-mlir-tblgen`**, rebuilt as a typed model (§2.2), generates
the rest:
- the Idris mirror;
- every table that spans records (§2.3);
- the runtime's C ABI and its typed instantiations;
- the pipeline;
- the tests' tables.

It is ours rather than upstream's for three reasons:
1. **Upstream emits per entity.** Its generators emit C++ for one entity
   at a time (an op class, an enum). None emits a table across records
   for a reader outside the entity, and none emits Idris. The generator
   says as much about itself (*read*:
   `foreign/idr/tools/idris-mlir-tblgen.cpp:1-58`). So does lane 14
   (14 §3.1).
2. **Upstream's generators are not a library.**
   - `MLIRTblgenLib` is the driver alone at the pin (14 §3.1; D §3.11).
   - So "one tool" (Q-llvm-5, DP-69) means two binaries over one set of
     records: ours on `MlirTblgenMain`, and upstream's `mlir-tblgen`.
     That is two readers of one record, not two copies of a fact.
   - Today's generator already has eleven `GenRegistration`s (*read*:
     `idris-mlir-tblgen.cpp:3221-3251`) and `main` is `MlirTblgenMain`
     (`:3255`).
3. **SearchableTables is a model, not a dependency.**
   - Its emitter is built into `llvm-tblgen` (5.3 E2).
   - Our generator's header says the installed toolchain provides
     `mlir-tblgen`, not `llvm-tblgen` (*read*: `idris-mlir-tblgen.cpp:44-48`).
     An `llvm-tblgen` exists only as a build artifact (*measured*:
     `find .toolchain -name llvm-tblgen` finds
     `.toolchain/build/tblgen/bin/llvm-tblgen`).
   - Our keys are dense enums, so the table we need is SearchableTables'
     simplest case.

### 2.2 The generator itself, under the same rules

The generator runs at T0, but its own C++ follows §1.2:
- **Parse once into a typed model** (14 TD1; Modular's
  `driver-tblgen`, 5.4 F18).
  - A `Model` is built from the `RecordKeeper` through the wrappers:
    `Operator`, `EnumInfo`, `AttrOrTypeDef`, `SideEffect`, `Pass`.
  - Every cross-record invariant is checked once, in `Model::validate`,
    with a `PrintFatalError` that names the records involved.
  - Each generator is a function of `(const Model &, raw_ostream &)`.
    Today `read` runs once per generator (14 T39).
- **Classify records by TableGen class, never by name or spelling.** It
  reads traits through `Operator::getTraits()`, not a raw walk (14 T05),
  and optionality through `isOptional()` (14 T32). These go:
  - the C++ class-name strings `"::idr::NoReturn"` and
    `"::idr::PerformsIO"` (14 T06);
  - the storage-type spellings (14 T10, T33);
  - `Idr_TagParameter` matched by name (14 T34);
  - the `"predicate"` attribute rule (14 T15).
- **No fact lives inside the generator.**
  - The ABI kind rows are hand-written C++ today: `OperandKind` and
    `ResultKind`, with their spellings and C patterns (*read*:
    `idris-mlir-tblgen.cpp:716-780`). A string search maps a record's
    `abiKind` string back to them (`:790`, `kindSpelled`).
  - They become records (02 E72; 12 CV-54; 14 T12, T13). A misspelt
    kind is then an undefined record, which TableGen itself refuses.
- **The Idris output is a typed expression tree, printed once** (14 TD9,
  T04). Neither `formatv` templates with `{0}` holes nor a `char` arity
  (14 T11) survive; arity becomes `enum class Arity { Single, Optional,
  Variadic }`.
- **Templates and sums in place of erasure.**
  - `std::function` (14 T49) becomes a template or a deducing-`this`
    lambda.
  - `get_if` validators over `Written<T>` (14 T31) become one `match`,
    or `std::expected`.
  - Parallel vectors become one struct (14 T21).
- **Its errors are tested.** Each refusal gets a fixture: a bad record
  that must fail with the error that names it (5.4 F18). That is a test
  of behaviour (the build fails, and says why), not of output text.

```cpp
// tools/idris-mlir-tblgen/Model.h (sketch): the records, read once, typed.
namespace idr::tblgen {
enum class Arity : std::uint8_t { Single, Optional, Variadic };

struct OpRecord {
  const mlir::tblgen::Operator *op;   // the wrapper owns the reading
  std::uint16_t index;                // dense, in record order: OpIndex's value
  llvm::SmallVector<const llvm::Record *, 2> families;  // classified by isSubClassOf
  EffectRow effects;                  // from SideEffect decorators and the effect records
  StageSet stages;                    // from the family's `stages` field
};

struct Model {
  std::vector<OpRecord> ops;               // OpIndex order
  std::vector<EnumRecord> enums;           // dense-from-zero, checked in validate()
  std::vector<ResourceRecord> resources;   // parents before children, checked
  std::vector<StepRecord> pipeline;        // the stage chain, checked
  static Model read(const llvm::RecordKeeper &);   // PrintFatalError on any bad record
};

// One emitter per view. Each reads the model; none reads a record.
template <class View>
concept Emitter = requires(const Model &m, llvm::raw_ostream &os) {
  { View::emit(m, os) } -> std::same_as<void>;
};
}  // namespace idr::tblgen
```

### 2.3 The fact families

Each family is described the same way: its record schema, what is
generated from it, the validators, what it deletes, and which generator
emits it.

#### (a) Op identity: `OpIndex`

One dense enum over the dialect's ops, and one interface that turns an
`Operation *` into it. Every per-op table of every subsystem (stages,
effects, forwarding, family membership) is an `EnumArray<OpIndex, ...>`.

The one dispatch per op (R5) then costs one interface lookup. Before,
each fact was its own `hasTrait<T>()` (a virtual call, then a chain of
TypeID compares: 5.3 B1) or its own interface lookup.

```tablegen
// IdrBase.td: listed once, in Idr_Op's base traits, so every idr op has it.
def Idr_IndexedOp : OpInterface<"IndexedOp"> {
  let cppNamespace = "::idr";
  let methods = [StaticInterfaceMethod<
      "the op's dense index, every per-op table's key",
      "::idr::OpIndex", "opIndex", (ins), [{}],
      /*defaultImplementation=*/[{ return ::idr::indexOf<ConcreteOp>; }]>];
}
```

```cpp
// IdrOpIndex.inc: generated by idris-mlir-tblgen -gen-op-index, after the op classes.
namespace idr {
enum class OpIndex : std::uint16_t { ArrayGetOp, ArraySetOp, /* ... one per op, record order */ };
template <> struct EnumTraits<OpIndex> {
  static constexpr std::size_t count = 189;   // lanes 01-03 count 189 at e96bb991
  static constexpr llvm::StringLiteral names[] = {"idr.array.get", "idr.array.set", /* ... */};
};
template <class OpT> struct IndexOf;          // no primary definition
template <> struct IndexOf<ArrayGetOp> : std::integral_constant<OpIndex, OpIndex::ArrayGetOp> {};
// ...
template <class OpT> inline constexpr OpIndex indexOf = IndexOf<OpT>::value;  // an op of another
}                                                                              // dialect: no such member
```

The interface is MLIR's mechanism (row 11 of the 5.2 recipe), used for
data rather than behaviour. Upstream ops our passes read get the same
interface through external models (`attachInterface`, *read*:
`mlir/include/mlir/IR/OpDefinition.h:1774-1782`). Those models are
generated from a record list that names upstream's own op records, for
example `Idr_Admitted<Arith_AddIOp, [IdrStageFirst, ...]>`. The
generator gets the C++ class from the record, so that list contains no
strings.

The list exists anyway, because stage legality must name the upstream
ops (03 O-1; DP-47). An op with no index is outside the admitted set.
That case is essential, because the op set is open: such ops are
answered by upstream's interfaces (§6, D2).

#### (b) Op families and their constants

A family is a TableGen class whose members come from a list (03 R1;
5.2 row 23). Its parameters are enum records, never bits (R6).

The generator emits one specialization of a class template per member.
That specialization is the only carrier of every per-op constant:
- the runtime function `Abi<OpT>` exists today (*read*:
  `build/typecheck/.../IdrRuntimeAbi.inc`);
- so do the guards `Guarded<OpT>` (*read*: `IdrGuards.inc`) and the word
  op `BigToWord<OpT>` (*read*: `IdrBigToWord.inc`);
- `Division<OpT>` and `Shift<OpT>` are new;
- the rest of 03 §5.3's families follow the same pattern.

A concept tests whether the specialization exists. The concept reads
ODS and lists no op.

```tablegen
// IdrBase.td: a constant is a case, never a bit.
class Idr_Case<string enumName, string caseName> {
  string cpp = "::idr::" # enumName # "::" # caseName;
}
def Idr_Signed    : Idr_Case<"Signedness", "Signed">;
def Idr_Unsigned  : Idr_Case<"Signedness", "Unsigned">;
def Idr_Quotient  : Idr_Case<"DivPart", "Quotient">;
def Idr_Remainder : Idr_Case<"DivPart", "Remainder">;

// IdrScalarOps.td: one family, its members from one list. Which ops the family
// keeps (divu/modu to arith, ops-Q3) is lane 03's; the shape is the point.
class Idr_DivisionRow<string m, string c, Idr_Case p, Idr_Case s> {
  string mnemonic = m;  string cppClass = c;  Idr_Case part = p;  Idr_Case sign = s;
}
defvar Idr_DivisionRows = [
  Idr_DivisionRow<"divs", "DivSOp", Idr_Quotient,  Idr_Signed>,
  Idr_DivisionRow<"divu", "DivUOp", Idr_Quotient,  Idr_Unsigned>,
  Idr_DivisionRow<"mods", "ModSOp", Idr_Remainder, Idr_Signed>,
  Idr_DivisionRow<"modu", "ModUOp", Idr_Remainder, Idr_Unsigned>];
class Idr_DivisionOp<Idr_DivisionRow r>
    : Idr_Op<r.mnemonic, [SameOperandsAndResultType, NoMemoryEffect,
                          Idr_Guarded<["rhs"], Idr_Nonzero>, Idr_GuardedOp,
                          ConditionallySpeculatable]>,
      Idr_Member<Idr_Division, [r.part, r.sign]> {
  let arguments = (ins Idr_Int:$lhs, Idr_Int:$rhs);
  let results = (outs Idr_Int:$result);
  let hasFolder = 1;
}
foreach r = Idr_DivisionRows in
  def Idr_ # r.cppClass : Idr_DivisionOp<r>;
```

```cpp
// IdrFamilies.inc: generated, included only by the units that read a family.
namespace idr {
template <class OpT> struct Division;   // members only
template <> struct Division<DivSOp> {
  static constexpr DivPart part = DivPart::Quotient;
  static constexpr Signedness sign = Signedness::Signed;
};
// ...
}  // namespace idr

// idr/IR/Families.h: hand-written; reads the generated specializations, lists no op.
template <class OpT>
concept DivisionOp = requires { Division<OpT>::part; Division<OpT>::sign; };

template <DivisionOp OpT>
mlir::OpFoldResult foldDivision(OpT op, typename OpT::FoldAdaptor adaptor) {
  if (!Guarded<OpT>::holds(adaptor)) return {};
  // ...
  if constexpr (Division<OpT>::part == DivPart::Quotient) { /* the quotient */ }
  else { /* the remainder */ }
}
```

**Why a specialization, not a member injected into the op class.** 12 T1
and 03 M7 would inject `static constexpr runtimeEntry` through a trait's
`extraConcreteClassDeclaration` (*read*: `mlir/include/mlir/IR/Traits.td:35-44`).
A specialization is the better carrier for four reasons:
- it works the same way for upstream ops;
- it keeps per-op data out of `IdrOps.h.inc`, which is 38,361 lines and
  parsed by 260 units (*measured*, 13 §2.7; §7);
- the specialization is itself the family's membership, so membership
  and constants cannot disagree;
- it is the carrier that already exists.

This settles A §3, item 7, as one carrier, `Abi<OpT>`. The empty C++
trait `CallsRuntime` goes (02 T7).

**Deleted:**
- the `bool` constants (03 O-31, O-48);
- the hand lists of family members (12 CV-37, *read*:
  `Conversion/Scalars.cpp:199-205`);
- the `isa<A, B, C>` ladders that restate a family (05 ID10; 11 I-NA2;
  04 C43).

#### (c) Types and grades

- **Enums.** `Quantity`, `Permission` and `Lifetime` stay ODS
  `EnumInfo`s, renumbered dense from zero (R2). The lifetime order
  `Static < Heap < Frame` is the order of the records (08 T1; 01 C2).
- **The algebra is `constexpr` over that order** (01 C1, C2, T35-T37):
  - `fitsIn` is `<=`, and `joined` and `times` are `max`.
  - Their laws are checked exhaustively at T1. Each component is small:
    2 quantities, 4 permissions, 3 lifetimes.
  - This deletes the out-of-line `fitsIn`, `joined` and `times` (*read*:
    `foreign/idr/include/idr/IR/Grades.h:115-120`), the `holdsOwn`
    switch (01 T37) and the `times` switch (01 T36).
- **Per-type facts come from ODS fields on each type record** (01 C6),
  generated into the `ValueFacts` answers and into the Idris side. This
  deletes the 55 hand answers (01 T28), the hand list of attached
  builtin types (01 T29), and the hand-written widths `{8, 16, 32, 64}`
  (01 T31).
- **Recursive facts are bits in the storage.** `Held` (labels, holds no
  component, references, world) is set when a group is sealed
  (01 C5; PS R7). A query is a load and a mask. This deletes
  `holdsNoComponent`'s fresh set per query (01 T54) and `Carriers::of`'s
  recomputation per edge (PS C4, residue).
- **Data bodies: one generated view per kind** (01 C4; 14 TD8):

```tablegen
class Idr_Role<string n> { string name = n; }
class Idr_BodyKind<string n, list<Idr_Role> roles> { string name = n; list<Idr_Role> legal = roles; }
def Idr_PlainBody   : Idr_BodyKind<"Plain",    [Idr_RolePlain]>;
def Idr_ListBody    : Idr_BodyKind<"List",     [Idr_RoleNil, Idr_RoleCons]>;
def Idr_ClosureBody : Idr_BodyKind<"Closures", [Idr_RoleLabel]>;
def Idr_MemoBody    : Idr_BodyKind<"Memo",     [Idr_RoleLabel, Idr_RoleRunning, Idr_RoleForced]>;
```

  These generate `using BodyView = std::variant<PlainView, ListView,
  ClosuresView, MemoView>`, where each view has accessors only for its
  own legal roles, and the Idris body type alongside it. An illegal pair
  of kind and role cannot be written. So these go:
  - the table of legal pairs (`KindRule`, `RoleOnce`, `ruleOf`; 01 T06);
  - the 18 `get_if<role::Label>` sites (01 T09);
  - the two `std::get<role::Label>` calls that abort (*read*:
    `Converter.cpp:54`, `Patterns.cpp:128`).

  Whether `InPlace` is a body kind is lane 08's and lane 11's question
  (01 T08).
- **Spellings** (`lin`, `own`, `excl`, and the missing `borrow`) become
  case fields of the grade's records (01 T02).

#### (d) Effects: the hosting for `effects.md`

DP-04 rules a single source: the resource tree, each op's effects, the
rules by which effects follow from types, consumption, the bits of the
function summary, and the mapping to LLVM. Every consumer is generated
or monomorphized from it. One concept-constrained query API answers
every question, and a verifier rule checks each function's summary
against the derivation from its ops.

This section gives the effect design its slots; it does not restate the
semantics (DP-01 to DP-03 decide the tree's shape). There are seven
slots:

1. **Resources: records in topological order.** A resource is declared
   after its parent, so "parent precedes child" is checkable and the
   ancestor closure is a single forward pass.

```tablegen
// IdrEffects.td (shape only; the tree is DP-01..DP-03's, the names effects.md's).
class Idr_Resource<string cpp, bit isAddressable> {
  string cppClass = cpp;  bit addressable = isAddressable;
}
class Idr_Under<Idr_Resource p> { Idr_Resource parent = p; }   // a record must exist to be named
def Idr_Heap    : Idr_Resource<"::idr::Heap", 1>;                     // under upstream's root
def Idr_Count   : Idr_Resource<"::idr::Count", 1>, Idr_Under<Idr_Heap>;
def Idr_Outside : Idr_Resource<"::idr::Outside", 0>;
```

2. **Generated: the resource enum, its tree and its closures**, with
   their checks:

```cpp
// IdrEffects.inc (generated): the one place the tree is C++.
namespace idr::effects {
enum class ResourceId : std::uint8_t { Heap, Count, MemoState, Fresh, Outside, Halt, /* ... */ };
// nullopt: the parent is upstream's DefaultResource (essential: the root is not ours)
inline constexpr EnumArray<ResourceId, std::optional<ResourceId>> parentOf{/* ... */};
inline constexpr EnumArray<ResourceId, EnumSet<ResourceId>> ancestorsOf = closeAncestors(parentOf);
inline constexpr EnumArray<ResourceId, EnumSet<ResourceId>> conflictsWith = closeConflicts(parentOf);
static_assert(parentsPrecede(parentOf), "a resource is declared before its parent");
static_assert(symmetric(conflictsWith));
}
```

   A query of the form "does A conflict with B" becomes a mask `&`. The
   parent-chain walk per query goes (5.2 row 6, "a parent-chain walk").

3. **Each op's static row:** `EnumArray<OpIndex, EffectRow>`, with
   `struct EffectRow { EnumSet<ResourceId> read, write, alloc, free; }`.
   - The generator derives it from the op's `SideEffect` decorators and
     the effect records it lists, through `mlir::tblgen::SideEffect`
     (*read*: `mlir/include/mlir/TableGen/SideEffects.h:24-53`).
   - Upstream passes keep reading ODS `MemoryEffects`.
   - Both are generated from the same records, so they cannot disagree
     (R1). Today the generator "reads no effects" (`02-ods-effects.md`, lines 1338-1339).

4. **Rules for effects that follow from types: a tuple of rule types per
   op**, the shape `Guarded<Op>` already has.

```cpp
template <class OpT> struct TypedEffects;   // generated for each op whose effects follow from types
template <> struct TypedEffects<ConOp> {
  using Rules = std::tuple<AllocWhenResultIs<BoxType, ResourceId::Heap>>;   // illustrative
};
// The one trait (02 T3) folds the tuple at T1: straight-line code per op that reads the
// operand types (program data) and emits the effects the rules name. Nothing interprets
// a rule table at run time.
```

   This deletes the eight hand `getEffects` bodies (02 T3) and
   `Allocation`'s ladder of exceptions (02 E44).

5. **The query API, monomorphized per question:**

```cpp
// idr/IR/Effects.h (hand): the one query API.
template <class Q>
concept EffectQuestion = requires(const Q &q, const EffectRow &row) {
  { q(row) } -> std::same_as<bool>;
};
template <EffectQuestion Q> bool ask(mlir::Operation *op, const Q &q);   // one IndexedOp lookup, then
                                                                         // the row (and the typed rules)
template <class OpT, EffectQuestion Q> consteval bool askStatic(const Q &q) {  // a typed op: a constant
  return q(staticEffects[indexOf<OpT>]);
}
```

   This deletes:
   - the four representations of "does IO" (02 §3.1);
   - `PerformsIO` (02 E7) and `ObservableIO` (02 E10);
   - `MayCrashOpInterface` (02 E15, E16, E20);
   - the classifier's `function_ref` (02 E37);
   - MoveOut's second classifier (04 C26; 02 E34).

6. **The function summary.** The bits are generated from the resource
   records (02 T2), with the two-way table generated too. The verifier
   rule ("summary equals the join of the ops' rows and the callees'
   summaries") runs per function, in parallel (02 E29; 01 T60). This
   deletes the hand bit-to-resource table, its three hand reverses
   (*read*: `IR/Func/Func.cpp:232-266`; 02 E23-E25), and `bodyEffect`'s
   ladder (02 E22; 03 O-65).

7. **The LLVM mapping.** `EnumArray<ResourceId, LLVMLocation>` (argument
   memory, inaccessible memory, other) is generated. The lowering writes
   `llvm.memory` and `will_return`/`no_unwind` from it in one rule
   (12 T2). This needs an upstream patch, because `llvm.call` implements
   no `MemoryEffectOpInterface` at the pin (12 §3.1). It also needs
   DP-01's answer on `exit` before `willreturn` is lowered (A §4, B2).

"Monomorphized in a single place": everything above is one generated
header, `IdrEffects.inc`, plus one hand-written header,
`idr/IR/Effects.h`. Every reader of an effect includes them, and nothing
else states an effect.

#### (e) The runtime ABI, and the typed runtime core

The generator does part of this already. Each op's `Idr_Runtime<"sym">`
mark and each `Idr_RuntimeFunction` record produce three things (*read*:
`idris-mlir-tblgen.cpp:2750-2995`, `IdrRuntime.td:1-98`):
- `idris_rt_ops.h`, which the runtime includes, so a definition that
  disagrees with its record does not compile;
- `Abi<Op>` rows;
- `helper::` constants.

What moves on:
- **ABI kinds become records** (§2.2). Each kind's record also carries
  its LLVM type and passing rule, so the lowering's four switches over
  the kinds go (12 CV-13, T1).
- **The nine hand-written native prototypes** in `idris_rt.h:306-317`
  and the prose encodings of handles and `OSClock` become records too
  (18 T-ABI2; R-ABI-5, R-ABI-6).
- **The cell's kind and info word: one typed enum and one header-only
  view**, shared by compiler and runtime (18 T-ABI1; R-ABI-2, R-ABI-3).
  This deletes `CellInfo.cpp`'s second packing.
- **The runtime's C entry points are explicit instantiations of a typed
  core** (C §2's table; 18 T-RC2, T-CPP1). Their declarations are
  generated from the same records. A test that the operand's kind makes
  unnecessary is not present in that kind's instantiation. That is the
  new AGENTS.md rule at T4:

```cpp
// runtime/Rc/Rc.h (hand): the typed core.
namespace rt {
enum class Component : std::uint8_t { Cell, MaybeCell, Big };   // generated from IdrRuntime.td
template <Component K> struct Word { void *raw; };
template <Component K> [[gnu::always_inline]] inline void inc(Word<K> w) {
  if constexpr (K == Component::MaybeCell) { if (!w.raw) return; }        // only where the type allows null
  if constexpr (K == Component::Big) { if (isSmall(w.raw)) return; }       // only where a word may be small
  bump(header(w.raw));
}
}  // namespace rt
```

```tablegen
// IdrRuntime.td: one record per instantiation, from one list.
class Idr_RuntimeInstance<string sym, string tmpl, Idr_ComponentKind k>
    : Idr_RuntimeFunction<sym, (ins Idr_CCell:$o), Idr_CVoid, "..."> {
  string instantiates = tmpl;  Idr_ComponentKind kind = k;
}
foreach k = [Idr_KindCell, Idr_KindMaybeCell, Idr_KindBig] in {
  def Idr_RtInc_ # k.name : Idr_RuntimeInstance<"idris_rt_inc_" # k.suffix, "::rt::inc", k>;
  def Idr_RtDec_ # k.name : Idr_RuntimeInstance<"idris_rt_dec_" # k.suffix, "::rt::dec", k>;
}
```

```cpp
// runtime/Generated/Instances.cpp (generated): each C name is its instantiation.
extern "C" void idris_rt_inc_cell(void *o)  { rt::inc<rt::Component::Cell>({o}); }
extern "C" void idris_rt_inc_maybe(void *o) { rt::inc<rt::Component::MaybeCell>({o}); }
extern "C" void idris_rt_inc_big(void *o)   { rt::inc<rt::Component::Big>({o}); }
```

  The other entry points follow the same pattern:
  - `inc_slots`/`dec_slots` count one run of slots (18 T-RC5; 12 T4).
    This deletes the 4,472 increments and 4,472 decrements in one test
    function (18 R-RC-4; 12 CV-19).
  - `free_exclusive` releases a cell with no count read (18 T-RC4;
    12 CV-32).
  - `is_unique` tests the count alone (18 R-RC-3). The compiler folds
    the test away entirely on `!idr.excl` (08 T8) and on frame values.
- **The scalar primitives' one meaning is DP-17's to decide.** One
  option is the runtime's typed template, which the folder calls through
  its instantiation (18 T-BG1). The other is a template over a value
  domain, `ArithDomain` (12 T12), which AGENTS.md permits only once it
  is amended. Either way, the template, not a third hand copy, is the
  one definition (12 CV-39; 03 O-47; 18 R-BG-1).

#### (f) The pass pipeline and its stage chain

This follows 13 T2 (DP-47; drv-Q2). The pipeline is a TableGen list of
steps beside `Passes.td`. Each step names a pass record and its reason.
A pass record is ours, or upstream's from `mlir/Transforms/Passes.td`
and its kin. A nest is a step whose anchor groups its body.

```tablegen
// IdrPipeline.td
class IdrStepBase;
class IdrRun<PassBase p, string why> : IdrStepBase { PassBase pass = p; string reason = why; }
class IdrConfigured<PassBase p, string make, string why> : IdrRun<p, why> {
  string constructor = make;   // a C++ function returning the configured pass (04 T3's one canonicalizer)
}
class IdrNest<string anchor, list<IdrStepBase> steps> : IdrStepBase {
  string anchorOp = anchor;  list<IdrStepBase> body = steps;
}
def IdrPipeline {
  list<IdrStepBase> steps = [
    IdrRun<IdrDeduplicate, "of each class of identical functions the rest sees one">,
    IdrRun<IdrDefunctionalize, "every later pass is first-order; the call graph sees every call">,
    // ...
    IdrNest<"::idr::FuncOp", [
      IdrConfigured<Canonicalizer, "::idr::canonicalizer", "folds what the columns conversion leaves">,
      IdrRun<CSE, "">]>,
    // ...
  ];
}
```

The generator walks the steps carrying the current stage. It refuses at
T0 a broken chain, a function pass placed at program level, or the
reverse, naming the step. That is a check across records, so it runs at
T0 (R4).

From the same list it generates:
- `buildPipeline`'s body as straight-line constructor calls. That
  deletes `Pipeline.cpp:61-197`'s statements; their comments become the
  reasons.
- the textual pipeline and the tests' table, which replaces
  `IdrPassStages.txt` and the awk reconstruction (13 DP-01; 19 S7);
- `--idr-pipeline=from:/to:` over a generated `PassId` enum (19 C2);
- the registration of every upstream pass it names. That deletes the
  hand list with its dead `remove-dead-values` and missing canonicalizer
  (13 DP-16).

**The kind of a pass becomes a type** (13 T1: decide, apply,
restructure). The `IdrPass` record gains a `kind` field, and `baseClass`
is computed from it. The stages are already template parameters of
`StagedPass` (*read*: `Pipeline.h:30-77`; 13 DP-15 calls it right).

The last virtual of ours, `runOnProgram`, goes as well:
- upstream's pass generator emits `baseClass` inside `template
  <typename DerivedT>` (*read*:
  `mlir/tools/mlir-tblgen/PassGen.cpp:194-200`);
- so `baseClass = "::idr::StagedPass<DerivedT, ...>"` makes `StagedPass`
  a CRTP base that calls `static_cast<DerivedT &>(*this).runOnProgram(p)`.

This relies on the name of a template parameter in upstream's generated
code, not on an API. If the owner judges that too fragile, the one
virtual stays (DP-15's "keep").

**Action tags** become fields of the pass's record. They are generated
into the `TaggedAction` classes and into the tests' list (13 DP-53;
19 S14). That deletes the 26 hand string literals.

#### (g) Refusal rules, their categories and scope

`Idr_Rule` already carries its category as a case field. The generator
emits the tests' list and a `categoryOf` switch (*read*:
`idris-mlir-tblgen.cpp:3108-3172`; 01 T21 calls this the right form).

What changes:
- the switch becomes an `EnumArray<Rule, RuleCategory>`;
- a rule gains a `scope` field, generated to Idris too. That deletes
  `Profile.outsideLanguage`, the hand list restating the rules
  (16 G5, FC-78).

A further option is that a refusal carries a typed payload per rule: the
site, and the value whose set is unbounded (AGENTS.md: the refusal
"names the site and the value"). The payload would come from the rule's
record, as `std::expected<T, Refusal>` (5.5 D8). That is *conjecture*;
it waits on lane 15's `ft-Q5`.

#### (h) Endings and crash causes

**Endings: one record set.** It generates:
- the runtime's `rt::end::Ending` variant (18 T-END1);
- the table of statuses and texts, indexed by the variant's index and
  checked at T1;
- the harness's Idris `Ending` (19 C4);
- the compiler's crash-site lowering, with `Cause` as a generated enum
  (12 T9; 03 O-80).

The statuses themselves are DP-18's. A status known for a crash site is
then compiled in, rather than "status 1 and a text the harness parses
back from stderr" (AGENTS.md's new rule, the endings example).

**Crash causes.** Today they are a string literal per op, a `StrAttr`
per guard and a message per site (03 O-80). They become one generated
`CrashCause` enum and its message table. `idr.crash` keeps its message:
it is the program's text.

#### (i) Clock kinds and file times (handle encodings: (e))

**Clocks.** `io.clock <kind>` becomes one op with a generated
`ClockKind` property (03 §5.3; DD-Q5; DP-42), calling one runtime
function that takes the kind. The runtime's `readClock(Clock)` already
exists (*read*: 18 §3.1). `Clock` becomes a generated C23 typed enum,
read by compiler, runtime and Idris (18 T-IO3). The switch from `Clock`
to `clockid_t` becomes a `constexpr` array checked at T1 (18 R-PL-6).

**File times** become one op with six results: a merge in the frontend
or in canonicalization (14 §6 DD-Q5).

#### (j) Everything else the tests or tools spell by hand

- **idr-expect's properties.** One record per property generates the
  declarations, the dispatch table and the coverage list (19 C1, E1).
  That deletes `Expect.h:146-230`, `Lookup.cpp`'s table, and the `sed`
  the coverage test runs.
- **`CmpPredicate`.** Case fields give its arith predicates, generated
  to C++ and Idris (14 TD5, E14). That deletes `Layouts.cpp:235-249` and
  `Emit/Operations.idr:176-194`.
- **The driver's print actions** become one table (13 DP-19).
- **The harness's primitive list and domains** come from the guard
  records (19 G6).
- **Bytecode codes** are already records (`IdrBytecode.td`; 01 C8 adds
  every non-mutable type and attribute, which deletes the copied format
  parser, 14 TD2).
- **Stack budgets** move to `Passes.td`'s records (08 C-09, T14).

#### (k) Target facts

AGENTS.md puts the target in one place: CMakeLists.txt's target entry.
That entry configures one header of `inline constexpr` typed values:
page size, user address bits, the triple, and the baseline CPU's
features. The header replaces macros, and it replaces the X-macro
expanded three times in the runtime and once in the compiler (18 R-PL-5,
R-STK-5; T-PL2; 12 CV-47). The one exception: `__builtin_cpu_supports`
needs a string literal, so an expansion stays there, and only there
(18 R-PL-5, essential).

## 3. The C++ vocabulary

A small set of headers, used by every subsystem. All are templates with
concepts at their boundaries. Each lands with its first client: a header
with no client is not landed (hard cutover).

### 3.1 `idr/Support/Id.h`: typed dense ids

```cpp
namespace idr {
template <class IdT> using RepOf = decltype(std::declval<IdT>().index());

// A dense id. Only `Tag::Minter` makes one, so every id names something its minter numbered.
template <class Tag, std::unsigned_integral Rep = std::uint32_t>
class Id {
  Rep raw;
  constexpr explicit Id(Rep r) : raw(r) {}
  friend typename Tag::Minter;
  template <class> friend class Count;
public:
  using tag = Tag;
  friend constexpr auto operator<=>(Id, Id) = default;
  constexpr Rep index() const { return raw; }    // for arrays and GraphTraits::getNumber only
};

// How many ids a minter made: the only size an IndexVector or a BitSet takes.
template <class IdT>
class Count {
  RepOf<IdT> n;
  constexpr explicit Count(RepOf<IdT> v) : n(v) {}
  friend typename IdT::tag::Minter;
public:
  constexpr RepOf<IdT> value() const { return n; }
  auto ids() const;                              // 0..n-1 as IdT, the one way to visit every id
};

template <class IdT, class T>
class IndexVector {
  static_assert(!std::is_same_v<T, bool>, "a set of ids is a BitSet");
  std::vector<T> items;
public:
  explicit IndexVector(Count<IdT> n, const T &init = T{}) : items(n.value(), init) {}
  T &operator[](IdT id) { return items[id.index()]; }
  const T &operator[](IdT id) const { return items[id.index()]; }
  template <std::integral I>
  T &operator[](I) = delete("index by the id its minter made, not a raw integer");
};

template <class IdT>
class BitSet {
  llvm::BitVector bits;
public:
  explicit BitSet(Count<IdT> n) : bits(n.value()) {}
  bool test(IdT id) const { return bits.test(id.index()); }
  bool raise(IdT id);                            // whether it rose: the marking's one question
};

// A fact per (owner, position) of varying arity: a parameter's bit, a field's state.
template <class OwnerId, class T>
class Ragged {
  std::vector<std::uint32_t> start;              // CSR offsets by owner
  std::vector<T> items;
public:
  std::span<const T> operator[](OwnerId o) const;
};
}  // namespace idr
```

These delete:
- `DenseMap<Value, ...>`, `DenseMap<FuncOp, ...>` and `DenseSet<Block *>`
  as solver state. Lane 07 counts them: O-23 to O-26, X-10, A-16. So
  does 05 RC3.
- the six separately minted numberings (05 §2.6; B §3.2);
- every "lookup that can miss": 06 L-7; 07 O-16, O-20; 09 OPT-31.

### 3.2 `idr/Support/Enum.h`: generated enums and their tables

```cpp
namespace idr {
template <class E> struct EnumTraits;   // specialized by the generator for every enum it emits

template <class E>
concept Enumerated = std::is_scoped_enum_v<E> && requires {
  { EnumTraits<E>::count } -> std::convertible_to<std::size_t>;
  { EnumTraits<E>::names[0] } -> std::convertible_to<llvm::StringLiteral>;
};

template <Enumerated E, class T>
struct EnumArray {
  std::array<T, EnumTraits<E>::count> items;
  constexpr const T &operator[](E e) const { return items[std::to_underlying(e)]; }
  template <std::integral I> const T &operator[](I) const = delete("index by the enum");
};

template <Enumerated E>
class EnumSet {
  static_assert(EnumTraits<E>::count <= 64);
  std::uint64_t bits = 0;
  static constexpr std::uint64_t bit(E e) { return std::uint64_t{1} << std::to_underlying(e); }
public:
  constexpr EnumSet() = default;
  constexpr EnumSet(std::initializer_list<E> es) { for (E e : es) bits |= bit(e); }
  constexpr bool contains(E e) const { return (bits & bit(e)) != 0; }
  constexpr EnumSet operator|(EnumSet o) const { EnumSet r; r.bits = bits | o.bits; return r; }
  constexpr EnumSet operator&(EnumSet o) const { EnumSet r; r.bits = bits & o.bits; return r; }
  constexpr bool empty() const { return bits == 0; }
  friend constexpr bool operator==(EnumSet, EnumSet) = default;
};

template <Enumerated E> consteval auto allOf() {
  std::array<E, EnumTraits<E>::count> out{};
  for (std::size_t i = 0; i < out.size(); ++i) out[i] = static_cast<E>(i);
  return out;
}

// The validator every generated table passes: one row per case, in the case's order.
template <Enumerated E, class Row, std::size_t N>
consteval bool indexedBy(const std::array<Row, N> &rows) {
  if (N != EnumTraits<E>::count) return false;
  for (std::size_t i = 0; i < N; ++i)
    if (std::to_underlying(rows[i].key) != i) return false;
  return true;
}

// A finite algebra's laws, checked over every element at T1.
template <Enumerated E, E (*op)(E, E)>
consteval bool semilattice() {
  for (E a : allOf<E>())
    for (E b : allOf<E>()) {
      if (op(a, b) != op(b, a) || op(a, a) != a) return false;
      for (E c : allOf<E>()) if (op(op(a, b), c) != op(a, op(b, c))) return false;
    }
  return true;
}
}  // namespace idr
```

`EnumSet` replaces the hand bit set in `Carriers` (02 E61), and the
grade's `Stage`-decoded booleans: `StageFacts` today is four `bool`s, 16
states of which 5 are valid (03 O-61). It becomes `EnumArray<Stage,
StageFacts>`, generated from the `Idr_Stage` records.

### 3.3 `idr/Support/Graph.h`: compressed rows behind a concept

```cpp
namespace idr {
struct Forward {};
struct Backward {};
template <class D> concept Direction = std::same_as<D, Forward> || std::same_as<D, Backward>;

template <class G>
concept Graph = requires(const G &g, typename G::Node n) {
  { g.size() } -> std::same_as<Count<typename G::Node>>;
  { g.successors(n) } -> std::same_as<std::span<const typename G::Node>>;
  { g.predecessors(n) } -> std::same_as<std::span<const typename G::Node>>;
};

template <Direction D, Graph G>
std::span<const typename G::Node> edges(const G &g, typename G::Node n) {
  if constexpr (std::same_as<D, Forward>) return g.successors(n);
  else return g.predecessors(n);
}

// The one graph type: 8 bytes per edge both ways plus 8 per node (5.3 S1's memory).
template <class Tag>
class Csr {
public:
  using Node = Id<Tag>;
  Count<Node> size() const { return count; }
  std::span<const Node> successors(Node n) const { return row(succStart, succ, n); }
  std::span<const Node> predecessors(Node n) const { return row(predStart, pred, n); }
private:
  friend class CsrBuilder<Tag>;   // the builder sorts once; nothing else hashes
  static std::span<const Node> row(const std::vector<std::uint32_t> &start,
                                   const std::vector<Node> &to, Node n) {
    return {to.data() + start[n.index()], to.data() + start[n.index() + 1]};
  }
  Count<Node> count;
  std::vector<std::uint32_t> succStart, predStart;
  std::vector<Node> succ, pred;
};
}  // namespace idr

// So scc_iterator, post_order and GenericDomTree accept it (5.3 B8). getNumber and
// getMaxNumber let PostOrderIterator index by number
// (llvm/include/llvm/ADT/PostOrderIterator.h:40-51).
template <class Tag> struct llvm::GraphTraits<const idr::Csr<Tag> *>;
```

**The upstream gap.** At the pin, `scc_iterator` keeps a
`DenseMap<NodeRef, unsigned>` of visit numbers whatever the graph offers
(*read*: `llvm/include/llvm/ADT/SCCIterator.h:46-80`). `PostOrderIterator`
does index by `getNumber` when `GraphHasNodeNumbers` holds. One map per
solve is within 5.3 B7's line ("one per solve: fine"). Even so, a hash
keyed by a dense number is a missing index.

So this design proposes `upstream/scc-node-numbers/llvm.patch`, which
makes `scc_iterator` index by number the way `PostOrderIterator` does.
Per AGENTS.md it would come with a report, a reproducer, a test, a
`PINS.md` entry and a plan to send it (*conjecture* that upstream takes
it). Until it lands, the map stays.

This deletes:
- `Support/Scc.cpp`'s three copies of the graph, its `function_ref`
  returning a heap vector per node, and its numbering map (05 SC1-SC3);
- the ten hand-built `SmallVector<SmallVector<unsigned>>` graphs
  (05 SC3);
- the private graphs of exclusivity, the stack and the label solve
  (07 X-10; 08 C-50; 06 L-9; PS C8, C10 residues).

### 3.4 `idr/Support/Lattice.h` and `idr/Solve/*.h`: the solver layer's types

```cpp
namespace idr {
enum class Changed : bool { No, Yes };

template <class L>
concept JoinSemilattice = std::regular<L> && requires(L &a, const L &b) {
  { L::bottom() } -> std::same_as<L>;
  { a.join(b) } -> std::same_as<Changed>;
};

// What a solver keeps per node: a value, never a container (R12; b8301ebe).
template <class L>
concept NodeState = JoinSemilattice<L> && std::is_trivially_copyable_v<L> && (sizeof(L) <= 16);

template <class L>
concept FiniteHeight = JoinSemilattice<L> && requires { { L::height } -> std::convertible_to<unsigned>; };

// R14: a budget's existence is a type.
struct Acceptance {};                                // no field: a refusal rests on it
struct Optimization { std::uint64_t steps; };        // in the program's units (ops, rewrites)
template <class P> concept Policy = std::same_as<P, Acceptance> || std::same_as<P, Optimization>;

template <Direction D, Graph G>
BitSet<typename G::Node> mark(const G &g, std::span<const typename G::Node> seeds);

template <class X, class G>
concept Gates = Graph<G> &&
    requires(const X &x, typename G::Node from, typename G::Node to,
             const BitSet<typename G::Node> &marked) {
      { x.opens(from, to, marked) } -> std::same_as<bool>;   // monotone: open stays open
    };
template <Direction D, Graph G, Gates<G> X>
BitSet<typename G::Node> mark(const G &g, std::span<const typename G::Node> seeds, const X &gates);

struct CalleesFirst {};
struct CallersFirst {};
template <class O> concept Order = std::same_as<O, CalleesFirst> || std::same_as<O, CallersFirst>;

template <class P>
concept SummaryProblem = requires(P &p, const ProgramGraph &g, FunctionId f,
                                  const IndexVector<FunctionId, typename P::Summary> &done) {
  requires NodeState<typename P::Summary>;
  requires Policy<typename P::Policy>;
  { p.transfer(g, f, done) } -> std::same_as<typename P::Summary>;
};

template <Order O, SummaryProblem P>
  requires (!std::same_as<typename P::Policy, Acceptance> || FiniteHeight<typename P::Summary>)
IndexVector<FunctionId, typename P::Summary> summarize(llvm::ThreadPoolInterface &, const ProgramGraph &, P &);   // no context (below)
}  // namespace idr
```

**One instantiation per client.** The definitions live in
`idr/Solve/MarkImpl.h` and `SummarizeImpl.h`. Only the unit that
instantiates includes them; every other unit sees declarations and an
`extern template` (R13; 5.5 D3):

```cpp
// idr/Analysis/Ownership/Exclusivity.h
extern template BitSet<ExclNode> mark<Forward, ExclGraph, ExclGates>(
    const ExclGraph &, std::span<const ExclNode>, const ExclGates &);
// lib/Analysis/Ownership/ExclusivityMark.cpp: the only unit that compiles the marking for it
#include "idr/Solve/MarkImpl.h"
template BitSet<ExclNode> mark<Forward, ExclGraph, ExclGates>(
    const ExclGraph &, std::span<const ExclNode>, const ExclGates &);
```

**The solve is MLIR-free by link dependency.** This is a design rule,
and *conjecture* that it holds for every solver:
- The solver layer is a library target, `IdrSolve`, that links
  LLVMSupport and nothing of MLIR.
- Extraction (shape G, B §2.3) reads IR per function, in parallel, into
  arrays. The solve is pure C++ over those arrays. Writing back is an
  apply pass.
- So a solve cannot create an attribute or take a context lock, because
  it cannot name the context.

This is PS R3's `Materializer` taken one step further: the type system
removes the context from the solve altogether, rather than only removing
creation from workers. The summary schedule needs the context's pool
(`mlir::parallelForEach`, 5.3 D1). It receives that pool as a
`ThreadPoolInterface &`, not the context.

### 3.5 `idr/Support/Match.h`: the one fold over a closed sum

**The choice.** One `match` everywhere, and `std::visit` not used. This
is DP-73's option B, and the coordinator's to confirm. The measurement
behind it is 5.5 F12 (*measured (host)*: 300 sites, an eight-lambda
overload set, `-O2`, against the pinned libc++):

| dispatch over K types, 300 sites | user s | object size |
| --- | ---: | ---: |
| `std::visit`, K = 11 | 2.10 | 65 KB |
| `std::visit`, K = 16 | 11.3 | 3,042 KB |
| fold `match`, K = 16 | 2.02 | 68 KB |
| at `-O0`, K = 16: `std::visit` / fold `match` | 6.25 / 1.23 | 15,372 / 1,736 KB |

- **The cliff.** The pinned libc++ dispatches `visit` with a `switch` up
  to 11 alternatives, and through a matrix of function pointers above
  that (*read*: `libcxx/include/variant:1596-1640`).
- **What `match` buys.** It compiles to one bounds check and a jump
  table at any size (*measured (host)*, its assembly). It also rejects a
  missing alternative at compile time.
- **Why one form.** One dispatch form for the tree removes the question
  "how many alternatives does this variant have" from every review.

```cpp
namespace idr {
template <class... Fs> struct Cases : Fs... { using Fs::operator()...; };

// The fold form: compiled and measured by 5.5 (host).
template <class V, class... Fs>
constexpr decltype(auto) match(V &&v, Fs &&...fs) {
  Cases<std::decay_t<Fs>...> cases{std::forward<Fs>(fs)...};
  using R = decltype(cases(std::get<0>(std::forward<V>(v))));
  return [&]<std::size_t... I>(std::index_sequence<I...>) -> R {
    if constexpr (std::is_void_v<R>) {
      (void)((v.index() == I ? (cases(*std::get_if<I>(&v)), true) : false) || ...);
    } else {
      std::optional<R> r;
      (void)((v.index() == I ? (r.emplace(cases(*std::get_if<I>(&v))), true) : false) || ...);
      return *std::move(r);
    }
  }(std::make_index_sequence<std::variant_size_v<std::remove_cvref_t<V>>>{});
}

// pin-only: the enumerating expansion statement (P1306R5, Clang 23 partial: enumerating
// and destructuring forms work, iterating does not; 5.5 F1). Drops the optional.
// Not compiled: the host clang has no `template for`.
template <class V, class... Fs>
constexpr decltype(auto) matchPin(V &&v, Fs &&...fs) {
  Cases<std::decay_t<Fs>...> cases{std::forward<Fs>(fs)...};
  return [&]<std::size_t... I>(std::index_sequence<I...>) -> decltype(auto) {
    template for (constexpr std::size_t i : {I...})
      if (v.index() == i) return cases(*std::get_if<i>(&v));
    std::unreachable();
  }(std::make_index_sequence<std::variant_size_v<std::remove_cvref_t<V>>>{});
}
}  // namespace idr
```

**How each kind of sum is represented:**
- A sum of our own data (a plan, an answer, an ending) is a
  `std::variant` read by `match`.
- A sum of handles (an op, a value, a block) is a `PointerUnion`, which
  is 8 bytes and keeps `isa` (5.3 B4, I4).
- A per-node kind inside a solver is an `EnumArray`, or an enum array in
  struct-of-arrays layout, with the payloads in side vectors indexed by
  id. A variant per node is never solver state (§5).

**What it deletes.** The tree had 192 `visit`/`get_if`/`holds_alternative`
uses and 60 variants at e96bb991 (*measured*, wave1/00-brief §2). Every
`get_if` and `holds_alternative` outside `match` goes, by lane:
- lane 01: T09, T41, T46, T57;
- lane 06: C-2, D-24;
- lane 07: R-05, X-02, E-04;
- lane 08: C-70;
- lane 09: OPT-13;
- lane 10: H-14, IT-4, TPo-1;
- lane 11: I-CV6;
- lane 13: DP-30, DP-46;
- lane 05: ID13, RT3.

The local `Visit` overload sets go (10 A-4), as does `llvm::makeVisitor`
in the generator (`idris-mlir-tblgen.cpp:3036-3045`).

### 3.6 Callbacks are templates

Every callback threaded through code that knows its static type becomes
a template parameter with a concept:
- 05 SC2, EF4, ID1, IN5, CO2;
- 06 D-10, C-3;
- 07 O-08, X-03;
- 08's `whereDies` and `edgesOf`;
- 09 OPT-08;
- 10 H-1 (which returns its blocks);
- 11 I-SL14, I-SL24;
- 12 CV-42;
- 01 T47 and T82 (`forEachNamed`'s three callbacks become one `Named`
  sum).

The stored `std::function`s go too: 03 O-85 and 06 D-22 (`DataRemap`'s
leaf); 21 P-19 (`Positions`); 09 OPT-24.

```cpp
template <class F, class... Args>
concept Visitor = std::invocable<F &, Args...>;

// Before: llvm::function_ref<llvm::SmallVector<Node>(Node)> successors (05 SC2), a heap
// vector per node. After: the caller hands a Graph; there is nothing to call back.
template <Graph G> std::vector<std::vector<typename G::Node>> components(const G &);

// Recursion without erasure (5.5 D5): deducing `this`.
auto depth = [&](this auto self, Node n) -> unsigned {
  unsigned d = 0;
  for (Node s : g.successors(n)) d = std::max(d, 1 + self(s));
  return d;
};
```

**The cost.** A template callback costs 2 to 3 times a `function_ref`
to compile: 2.6 ms against 1.0 ms per site (*measured (host)*, 5.5 F13).
At our size that is seconds, and the design pays it. The sites where
MLIR takes a `function_ref` (`walk`, `replaceUsesWithIf`, interface
methods declared with one) stay as upstream wrote them; §6 lists them,
under D6.

**Cold callbacks.** Lanes 01 and 03 propose keeping several cold
`function_ref`s (01 T84, T85; 03 §4 L621). Under the ruling they become
templates. Where a callback is an ODS interface method's parameter,
which cannot be a template, it stays and is listed in §6.

### 3.7 Rooted patterns only

```cpp
// idr/IR/Patterns.h: every pattern of ours derives from one of these two.
template <class OpT>
  requires std::derived_from<OpT, mlir::OpState>
struct IdrPattern : mlir::OpRewritePattern<OpT> { using mlir::OpRewritePattern<OpT>::OpRewritePattern; };

template <class Iface>
  requires std::derived_from<Iface, mlir::OpInterface<Iface, typename Iface::Concept>>   // illustrative
struct IdrInterfacePattern : mlir::OpInterfaceRewritePattern<Iface> {
  using mlir::OpInterfaceRewritePattern<Iface>::OpInterfaceRewritePattern;
};

// A set over several ops is a pack generated from ODS, as addNarrowWords already is
// (lib/Transforms/Narrow/Ops.cpp:217-228; PS R1).
template <class... Ops> void addRooted(mlir::RewritePatternSet &set, mlir::MLIRContext *ctx);
```

Upstream already files interface- and trait-rooted patterns per op at
freeze (*read*: `mlir/lib/Rewrite/FrozenRewritePatternSet.cpp:124-141`;
5.5 F18). So no generated list of patterns per op indexes any better.

These go:
- `MatchAnyOpTypeTag`, already gone (7987388b);
- `getRegisteredOperations()` inside a populate function (PS C2): the
  retype becomes a walk over the ops the plan names (06 T1);
- roots spelled as op-name strings (04 C19);
- the "handled" list of nine names (06 D-4; 04 C65).

### 3.8 Arenas, run-local interning, and constants made at T2

```cpp
// idr/Support/Interner.h: program data hashed once, per run, outside the context.
template <class T, class Hash = llvm::DenseMapInfo<T>>
class Interner {
  llvm::SpecificBumpPtrAllocator<T> arena;
  llvm::DenseMap<T, Id<Interner>, Hash> index;   // essential: it hashes program data
  std::vector<const T *> items;
public:
  using Minter = Interner;
  Id<Interner> intern(const T &);
  const T &operator[](Id<Interner>) const;
};

// idr/Support/PassConstants.h: what a pass makes once, at T2 (R10).
template <class Constants>
struct WithConstants {
  std::shared_ptr<const Constants> constants;    // shared by the clones the adaptor makes
  mlir::LogicalResult build(mlir::MLIRContext *ctx) {
    constants = std::make_shared<const Constants>(ctx);
    return mlir::success();
  }
};
```

Pass clones are copies made after `initialize` (*read*:
`mlir/lib/Pass/Pass.cpp:482-516, 927-931`). A
`FrozenRewritePatternSet` shares its implementation through a
`shared_ptr` (*read*:
`mlir/include/mlir/Rewrite/FrozenRewritePatternSet.h:91-95`). So
constants built once are shared by every worker for free.

Interning replaces:
- specialization keys kept in the context forever (09 T3, OPT-64; 01 T20);
- dedup's dictionaries built per op and per comparison (06 U-9 to U-11);
- the `#idr.con` built per run read (01 T32), and the `StringAttr`
  uniqued per big operand (04 C41);
- the `FlatSymbolRefAttr` uniqued per return-flow query (02 E64), and
  the dictionary per op per verify (01 T48, T59).

### 3.9 Profile zones with compile-time identity

A zone's name is a `constexpr` string literal, and its subsystem a
generated enum. Today `IDR_ZONE_IN(name, subsystem)` throws the subsystem
away: a Tracy leftover (*read*:
`foreign/idr/include/idr/Support/Profile.h:73-79`; 13 DP-48).

The sink is 13 T4's one trace: MLIR's actions, observed into LLVM's time
trace. Which backend records it (LLVM's time trace, or Tracy, which the
owner asked for on 2026-10-12) is the owner's call. The zone's identity
is compile-time either way. Tracing compiled out by a `constexpr` level
in the type is Modular's form (5.4 F19).

## 4. Subsystem by subsystem

Each subsystem is described by what becomes a compile-time constant,
what is monomorphized, and which run-time dispatch remains and why.

### 4.1 Dialect, effects and canonicalization (lanes 01-04)

**Compile-time:**
- `OpIndex`, and every per-op table: stages (03 O-1, O-61), forwarding
  kind (02 T6; E57, E58, E79), family membership.
- Family constants as enum cases (03 R1, O-31, O-48).
- The grade algebra and its laws (01 C1, C2, T35-T37).
- Per-type facts from ODS fields (01 C6, T28, T29, T31).
- Body kinds as generated views (01 C4, T06, T07, T09, T10).
- Spellings as records (01 T02).
- `CmpPredicate`'s case fields (01 T56).
- The `CrashCause` enum (03 O-80).
- The effect tables of §2.3(d) (02 T1-T7).
- The canonicalizer's configuration, once (04 C59, T3).

**Monomorphized:**
- One generic runtime fold, a template over the C signature read off
  `Abi<OpT>` and supplied by a `foldTrait` (04 T1, C40). It deletes 37
  folder bodies, and `strUnary`, `strBinary`, `bigUnary`, `bigBinary`
  and `strAtOffset`.
- `Idr_FoldsToConstant<Attr>` for `con`, `closure` and `suspend`
  (04 C05).
- `classify<Question>` (02 T5).
- `TypedEffects<OpT>` (§2.3(d), slot 4).
- `Model<ConcreteOp>` bodies that need no concrete op move to `$_raw_op`,
  shared, which saves per-op copies (5.5 F16; 02 E75).

**Runtime dispatch left:**
- An op's row: one `IndexedOp` lookup per op per walk (§6, D1). It
  replaces `hasTrait` calls such as `SameValue`, `ResultCarriesOperand`
  and `BuildsValue`, which become row bits or forwarding kinds.
- Upstream passes reading `MemoryEffectOpInterface` (D2).
- The match's region interfaces. They answer each query in O(1) once
  `getPredecessors` and `getPredecessorValues` are overridden (03 O-13).
- Type-dependent effects reading their operand's type. That type is
  program data: essential.

**The verifier:** per function and in parallel, numbering once (01 C7;
13 T3).

### 4.2 The solver layer (lanes 05, 06, 07, 09)

**Compile-time:** Each solver's graph type, lattice, direction, order,
policy and gates are template arguments, checked by the concepts of
§3.4. Whether an analysis is an `Acceptance` or an `Optimization` is
written in its type. B6 asks for the exact list of acceptance analyses:
exclusivity, knots, the label solve, defunctionalization, the growth
check, the reachability walk (B §5 B6; D §3.11). The list becomes the
set of instantiations with `Acceptance`.

**Monomorphized:**
- `ProgramGraph` (05 T5.1): `FunctionId`, callees and callers as CSR
  rows, SCCs as id ranges, a self-edge bit, preserved by name (05 T5.10).
  It deletes `CallCycles` (05 CC1-CC5), `Recursion` (RC2, RC3), the
  caller-only `SymbolUserMap`s (EF2, EF9; 09 OPT-45) and the name maps
  (05 R9).
- `mark<D>` and `mark<D, Gates>`:
  - the stack inference instantiates it first (08 T9, C-50, C-51);
  - borrows second (07 D3, B-01: off `DataFlowSolver`);
  - exclusivity third (07 D2, X-08, A-07, A-12; PS C10 residue).
- `summarize<CalleesFirst|CallersFirst>`: effects (05 T5.3), identities,
  inline facts and signature demand (09 T5).
- The label solve on dense ids (06 T2). Its arrays are append-only,
  because its graph grows during the solve (06 §3.2). That is essential,
  and why its state is append-only vectors rather than a frozen CSR. It
  deletes the virtual `Statements` (06 L-5), the hashed point variant
  (L-3), the pointer maps (L-6) and the per-wave graph (L-9).
- The optimizer's sums:
  - phase `Waiting | Parked | Done | Final` (09 T2, OPT-17);
  - node kind (T4, OPT-18) and verdict (OPT-04);
  - key patterns as a closed sum in a run arena (T3, OPT-60, OPT-64).
  These delete `specialize::Schedule`'s virtuals (OPT-22) and the
  string-keyed reader API (OPT-21). Component merges go through
  `IntEqClasses` (09 T1).

**Runtime dispatch left:**
- Extraction asks each op once, through `IndexedOp` or upstream's
  `RegionBranchOpInterface`, `BranchOpInterface` and `CallOpInterface`
  (B §2.8). It never asks per pair (PS C10).
- The optimizer inserts nodes and merges SCCs while it solves (09 §3.1;
  B §3.6). That set is dynamic, which is essential, and it is the one
  dynamic client of the static spine (Q-AN2).

### 4.3 Counting (lane 08)

**Compile-time:**
- `enum class Class` goes: the class is the grade, and the grade is
  `constexpr` over the type's parameters (08 T2; C-04, C-05, C-17, C-22,
  C-24).
- Consumption is the effect rows' `free` set (08 T7; C-19, C-25, C-67,
  C-80).
- The specialization key is a typed `(FunctionId, mask)` (08 T12, C-63).
- The stack budgets come from records (08 C-09).

**Monomorphized:**
- `template <LiveSet S> void place(FuncOp, S &)`: one reverse walk, where
  `S` (a bit vector or a sparse set) is chosen at the instantiation
  (08 T3).
- `Consuming<OpT>` reads `staticEffects[indexOf<OpT>].free` in typed
  code.

**T4: the compiled program.**
- `idr.is_unique` folds to true on `!idr.excl` and to false on frame
  values (08 T8; C-76; 12 CV-30).
- Drop specialization and reuse are IR, so the shared arm is
  canonicalized away.
- The lowering decides nothing (12 T3, T4).

AGENTS.md's examples of a "uniqueness test on values typed exclusive" go
in that step.

**Runtime dispatch left:** the region interfaces during the reverse
walk.

### 4.4 Tail calls, frames and returned arguments (lane 10)

**Compile-time:**
- Tail position is either a call property, a generated enum lowered to
  `llvm.call`'s `tail_call_kind` (10 D1b), or one cached table per
  function (10 D1a). DP-38 decides which.
- `TailEnd` is read through `ReturnLike` (10 D5). That deletes the five
  `isa<ReturnOp, YieldOp>` (IT-2, Fr-2, Tr-4, A-2, L-2; 03 O-92) and
  passesOnPrevious's restatements (FP-3, Fr-3).
- The frame tag is stored when the stack is declared (10 D2, Fr-5).

**Monomorphized, through `match`:**
- `Answer = OneResult | AnswerSum` (H-11, H-12, FT-1);
- `Site = CallSite | DispatchSite` (H-9, Fr-6);
- `TailCall | AddedTail` (H-6, D7);
- `WhileDoLoop | GeneralLoop` (TL-4, D8).

**Deleted:**
- the whole-module `Returned` solve (R-1 to R-5), replaced by a carried
  fact or a per-function summary (10 D3; DP-38);
- `[[maybe_unused]] LogicalResult` with an `assert` (R-2), and the
  `(void)` results of interface calls (Tr-7, A-5, Fr-14, PT-1);
- serial planning: it moves under the pass manager (Fr-18, Tr-6, A-6).

**Runtime dispatch left:** the ops `ReturnLike` and the region
interfaces answer for.

### 4.5 Arrays (lane 11)

**Compile-time:**
- `Form`'s lowering and statistic become one `EnumArray<Form, ...>`
  checked at T1 (11 I-SL1, C1).
- `Idr_Iteration` is spelled as upstream's `IteratorType`, plus
  `Ordered` (I-SL18, C3).
- The word/big conversions are fields of the `BigToWord` record (I-NA9),
  and the narrowed ops one generated type list (I-NA8).

**Monomorphized:**
- `lowerInterchange<OpT>` and `folded<OpT>`, with `if constexpr` on the
  family constant (I-SL17).
- `Bind`, `Yield` and `cellDim` become template parameters (I-SL14,
  I-SL24).
- One bufferization model template over `RegionBranchOpInterface` ops
  (I-BU13, C6).
- `Element = InPlace | Boxed`, read by `match` (I-CV5, C9).

**Deleted:**
- the hand ladder of nine combining ops, for upstream's `matchReduction`
  and `getCombinerOpKind` (I-SL7);
- per-op pattern instantiations, which become interface roots (I-CO8,
  C7).

**Runtime dispatch left:** bufferization's model calls, which are
upstream's.

### 4.6 Lowering (lane 12)

**Compile-time:**
- `Abi<OpT>` carries the entry, the C function and, once the kind
  records are in, each kind's LLVM type and passing rule (12 T1; CV-13,
  CV-54).
- `concept RuntimeOp = requires { Abi<OpT>::entry; }` names the filter
  that is anonymous today (CV-23).
- Families come from `GET_OP_LIST`, filtered by concepts on the family
  enums (CV-37).
- `Representation = Boxed | Unboxed` (T5, CV-26).
- Typed content keys (CV-44).
- The function's facts and the call's effects come from §2.3(d)'s LLVM
  mapping (T2, CV-05).
- Crash sites are data: a `CrashCause` and the site (T9).
- Mangling has a fixed prefix (T7, CV-07).

**Monomorphized:** `LowerRuntimeCall<OpT>`, as today's
`addRuntimeCalls<GET_OP_LIST>` already is (*read*:
`lib/Conversion/RuntimeCalls.cpp:150-169`).

**T2:** The type converter and conversion target are built once. Every
runtime function in the generated table is declared up front (T6,
CV-48). `idr-lower` runs under the pass manager rather than a scheduler
of ours (T6, CV-02; DP-61).

**T4:**
- string and big literal matches become a binary search over keys sorted
  at compile time (CV-09);
- the counts become `inc_slots` runs (T4, CV-19);
- an exclusive release reads no count (CV-32);
- static data is known from the grade (CV-20).

**Runtime dispatch left:** the conversion driver and its `TypeConverter`
callbacks, both upstream's (§6, D4).

### 4.7 The runtime (lane 18)

**Compile-time:**
- the component kinds;
- the typed core and its generated instantiations (§2.3(e));
- the ending table (§2.3(h));
- the clock table (§2.3(i));
- the CPU features from the target entry (18 T-PL2);
- the snmalloc failure continuation as a template argument (T-AL1),
  which deletes the null tests after allocation.

**Sums read by `match`:** the handle `Slot` (T-IO1; R-IO-1 to R-IO-4),
`Read` (R-IO-4) and `Numeral` (T-NU1, R-NU-1).

**Platform errors** become `std::expected<T, Errno>` (T-PL1, R-PL-1).

**Concepts on every template:** `eachSlot` and `binary<Op>` (T-CPP1;
R-RC-6, R-BG-2).

**T4, removing what the compiler knew:**
- the NULL and odd-bit tests in every `inc`/`dec` (R-RC-1);
- the stack-bit test in `is_unique` (R-RC-3);
- the header reads in `memref_copy`, replaced by constant sizes (T-AL5,
  R-AL-7);
- `persist_held` after every force, now only on static memo cells
  (R-RC-8);
- the shipped live-cell counter and the read of `IDRIS_RT_LIVE`, now in
  the checked runtime only (T-AL4; R-AL-5, R-IO-10; DP-81).

**Runtime dispatch left:**
- the handle slot's alternative (program data);
- OS calls through the platform layer, with per-target units chosen at
  build time (18 T-PL4);
- the signal handler;
- the startup check of the CPU and the page size (the machine; AGENTS.md
  allows it);
- the big word's small-or-pointer test where narrowing did not prove
  small: essential, because a `Big`'s representation varies by value.

### 4.8 The generator and the Idris side's tables (lanes 14-17, 19)

§2.2 covers the generator.

**What the Idris side gains from the same records:**
- the stage-scoped builders (14 TD6, T22): 125 of 191 builders are unused
  today;
- `Op n`, `Fin n` and `Vect` arities (TD3, TD4, T20, T26, T29);
- rule scope (16 G5);
- endings (19 C4);
- crash causes and clock kinds (03 §5.4);
- the harness's primitive list (19 G6);
- `CmpPredicate`'s fields (14 TD5);
- body kinds (14 TD8, T37).

Every one of these stays inside the subset both hosts compile (D §6).

**Fingerprints.** The fingerprint of each generated module covers the
records and the output only (14 T50). Whether the modules stay checked
in is DP-71.

### 4.9 Driver and pipeline (lane 13)

**Compile-time:**
- the pipeline (§2.3(f));
- decide/apply/restructure as types (13 T1);
- action tags and statistics in records (DP-53);
- print actions as a table (DP-19);
- `cl::opt` globals and `llvmZones` read into the invocation, with no
  static constructor (DP-49), enforced by `-Werror=global-constructors`
  (§7.6).

**Monomorphized:** `StagedPass<DerivedT, Anchor, Requires, Sets>` with
no virtual (§2.3(f), if accepted).

**T2:**
- `getDependentDialects` on the built pipeline replaces the hand dialect
  list (13 DP-17);
- one trace observer (13 T4);
- one pool on reserved stacks (13 T6; DP-62).

**Runtime dispatch left:** the pass manager's (§6, D5).

## 5. Performance at run time, from the record

### 5.1 When the compiler runs

Each measured cause, and the rule of this design that makes it
unrepresentable. Causes are PS C1 to C14; numbers are PS §1's.

| cause | the number | rule | how the design makes it unrepresentable |
| --- | --- | --- | --- |
| PS C1, any-op patterns (3a96c407, 7987388b) | 75 M attempts each in 31 min (M1) | R5; PS R1 | §3.7: our pattern bases accept only an op class or an interface; `MatchAnyOpTypeTag` is poisoned (§7.6) |
| PS C2, a static pattern set built, frozen and legalized per function | 70 % of test-idr's on-CPU (M9; flame finding 1) | R10; PS R2 | patterns and the conversion target are made at T2 in `PassConstants`; the retype is a walk over planned ops, not R patterns per function (06 T1, D-3) |
| PS C3, global locks per element and per hook | "a fifth" of the reduced corpus (M10) | PS R3, R4 | the solve has no context (§3.4); constants at T2; interning per run (§3.8); per-function work as nested passes, chunked; one trace observer (13 T4) instead of a mutex and a map per thread (13 DP-50) |
| PS C4, mutable type facts read through `mutate` (98c6315c) | half of a ten-minute window (M14) | PS R7 | facts are bits set at sealing (01 C5); `Carriers::of` is a load |
| PS C5, a table remade per insert (73bba53f) | 843 s (M15) | PS R8 | tables only from a complete list (`Declarations`, generalized); the API has no single-insert `with` |
| PS C6, identity by printed text (b9d4d592) | half an hour (M16) | R9 | ids, structural hashes in the run's interner |
| PS C7, `DataFlowSolver`'s state per value (ffa91113, 16005000) | 627 GB, 52 GB (M6, M3) | R8, R12; PS R5, R6 | the solve's state is `IndexVector`/`BitSet` over ids; no `DenseMap<Value, L>` can be a solve's state, since `IdrSolve` cannot name `Value` |
| PS C8, a fact per (value, cell) copied along edges (b8301ebe) | 47 GB (M4) | R12 | `NodeState` requires a trivially copyable value of at most 16 bytes; a `BitVector` per node does not satisfy the concept |
| PS C9, IR cloned per (member, answer) (16005000) | 336 s, 43 GB (M2) | PS R6 | the plan is data decided first (10 D2), cloned once per member |
| PS C10, an interface query per (successor, terminator) (e96bb991) | did not finish (M7) | B §2.8; PS R6 | the extractor visits each op once and writes edges; the builder API has no "ask a pair" |
| PS C11, IR order recomputed per query (101edbc5) | half of grades in `findAncestorOpInBlock`, a quarter in renumbering (M8) | PS R5 | one frozen numbering per function, an analysis invalidated at phase boundaries; no incremental `forget` (0be4e660's lesson: a block is a coordinate); or no position queries at all (08 T3). DP-06 decides `Positions` |
| PS C12, many-region ops revisited after each change | O(N²) (M18) | upstream patches 62, 63 | kept upstream-first |
| PS C13, asking by mutating or cloning | a hang; then a clone per probe (M17) | PS R10 | folders as functions over attributes (04 T1); `meets` declared per op (04 T2), so no clone per probe (04 C12) |
| PS C14, backend, startup, harness | 34 %, 1-2 %, 13 % of suites (M11) | none | outside the passes; recorded, not designed for |

Two smaller observations from the record:
- **The driver's `std::visit`.** It shows 5.0 % self in the program
  suite, over two alternatives, which take the `switch` path (flame,
  corpus C). `sample` folds inlined work into "self" (flame §Method), so
  the cost is the driver's inlined work, not the dispatch (*conjecture*).
  It becomes a `match` over the module's first op (13 DP-25).
- **Assertions and epoch checks** in the toolchain's MLIR (PS R13) cost
  inside every `DenseMap` iterator of ours. They cannot touch an
  `IndexVector`. Whether production links an MLIR without assertions is
  DP-07's and drv-Q1's.

### 5.2 When a compiled program runs

AGENTS.md's new rule, applied to T4. Each line is a fact the compiler
held that the program pays for today, and where it goes:

| paid by the program today | known to the compiler as | where it goes |
| --- | --- | --- |
| a uniqueness test on a value typed exclusive (08 C-76; 12 CV-30) | `!idr.excl` | `idr.is_unique` folds (08 T8) |
| the count read on an exclusive drop (12 CV-32) | `!idr.excl` | `free_exclusive` (18 T-RC4) |
| NULL and odd-bit tests in every `inc`/`dec` (18 R-RC-1) | the component's kind | `inc<K>` instantiations (§2.3(e)) |
| the stack bit tested in `is_unique` (18 R-RC-3) | a frame value's grade | folds to false; the runtime tests the count alone |
| 4,472 + 4,472 calls in one function (18 R-RC-4; 12 CV-19) | contiguous runs of fields | `inc_slots`/`dec_slots` (18 T-RC5) |
| `persist_held` after every force (18 R-RC-8) | the memo cell's staticness | called only on static cells |
| element bytes read from the header in `memref_copy` (18 R-AL-7) | the element type | constant operands (18 T-AL5) |
| every crash is status 1 with a text (18 R-ABI-4) | the site and its cause | `Ending` and `CrashCause` compiled in (§2.3(h); DP-18) |
| a live-cell count in every shipped program (18 R-AL-5, R-IO-10) | a test's need, not the program's | the checked runtime only (DP-81) |
| a literal match as a linear chain (12 CV-09) | the sorted key set | binary search over constant keys |
| simdutf re-testing the CPU by feature strings (18 R-PL-3) | the target's baseline features | a `constexpr` table from the target entry; static choice where the baseline guarantees the feature (18 T-PL2) |
| effects dropped at lowering, so LLVM re-infers weaker facts (12 CV-05) | the effect rows and summary | `llvm.memory`, `nounwind`, `willreturn`/`mustprogress` by one rule (12 T2) |

### 5.3 perf-sources' rules, folded

| PS rule | where it lives here |
| --- | --- |
| R1, every root set is a compile-time list | §3.7; R5 |
| R2, frozen once per process; units receive data | R10; §3.8 `PassConstants` |
| R3, no context mutation or synchronized read on a worker; a `Materializer` | §3.4: the solve cannot name the context; for extraction and apply passes, the context is reached only through T2 constants and a serial materialization step; interning per run (§3.8) |
| R4, chunked parallelism, nothing per element on the hot path | the decide/apply/restructure shape under the pass manager (13 T1); chunking is the pass manager's |
| R5, dense ids per scope as the coordinates | §3.1; one numbering analysis per function shared with the verifier (07 D5; 21 P-2), frozen per phase |
| R6, state as arrays by id; pairs only as sparse edges | §3.1, §3.3; R12 |
| R7, type and op-kind facts are constants read by a load | §2.3(a)-(c); `IndexedOp`; `Held` bits |
| R8, a growing table built once per phase | `Declarations` generalized; R2 |
| R9, identity is never text | R9 |
| R10, a question allocates and mutates nothing | 04 T1, T2; R10 |
| R11, one solver layer, each unit an action | §3.4; each per-function and per-SCC unit a `TaggedAction`, its tag generated (§2.3(f)) |
| R12, no type erasure on a hot path over a closed set | R7; §3.5, §3.6 |
| R13, builds state their assertions | §7.1; DP-07 |

**What the design avoids allocating:**
- a `std::function`, a virtual call or a `variant` per node, anywhere in
  our hot loops;
- a hash map per node or keyed by a static fact;
- any allocation in a solve beyond its arrays. A graph costs 8 bytes per
  edge in each direction, plus 8 bytes per node. At N = 10⁷ and
  E = 3·10⁷ with an 8-byte state that is about 400 MB. The framework's
  state at the same N is about 20 GB (*conjecture*, arithmetic; 5.3 S1).

## 6. Every surviving runtime dispatch

Every place where the design still dispatches at run time on something
other than program data, and why each is essential. Dispatch on program
data (which alternative a value is, a grade read from a type, a data
body) is not a dispatch on a static fact, and is listed once, at the
end.

| # | site | what dispatches | why it is essential | its cost, and its bound |
| --- | --- | --- | --- | --- |
| D1 | `Operation *` → `OpIndex` (§2.3(a)) | an interface lookup: a binary search of the op's sorted (TypeID, Concept) list, then one indirect call | the op set is open to C++ and TypeIDs are run-time addresses (§1.4) | ~log₂(interfaces) compares, once per op per walk; every per-op fact after it is an array load |
| D2 | upstream interfaces on upstream ops our extractors read: `RegionBranchOpInterface`, `BranchOpInterface`, `CallOpInterface`; `ReturnLike` and `IsTerminator` via `hasTrait`; `MemoryEffectOpInterface` on ops with no index | interface lookups and `Model` calls; `hasTrait` is one virtual call and a chain of TypeID compares (5.3 B1) | upstream's facts live in upstream's interfaces | once per op per extraction (B §2.8); overriding the match's methods makes each answer O(1) (03 O-13) |
| D3 | `Model<ConcreteOp>` calls inside D1 and D2 | indirect calls through the interface's concept | MLIR's monomorphization point (5.5 F16): the code behind the call is typed | one call per question |
| D4 | the rewrite and conversion drivers | `FrozenRewritePatternSet`'s lists per `OperationName`, built at freeze (`FrozenRewritePatternSet.cpp:63-141`); the applicator's cost model; the greedy worklist; `ConversionTarget` legality callbacks; `TypeConverter`'s conversions as `std::function`s | upstream's drivers; `TypeConverter` takes `std::function` by API | built once per pass at T2 (R10); rooted patterns only (§3.7) |
| D5 | the pass manager | virtual `runOnOperation`; the op-to-op adaptor's per-op dispatch to cloned managers (`Pass.cpp:985-1010`); `ParallelDiagnosticHandler`'s order-id map per element (PS C3) | upstream's open pass hierarchy and scheduler | per op of a nested pass; the order-id map is an upstream cost under a recursive mutex (`Diagnostics.cpp:1052-1062`), a candidate patch (*conjecture*) |
| D6 | callbacks MLIR erases: `walk`, `replaceUsesWithIf`, `getUsers` filters; ODS interface methods taking `function_ref` (01 T84: `ConAttr::walkFields`) | an indirect call per element | upstream's API (`Visitors.h:275-347`); an interface method cannot be a template | per element visited; our lambda is inlined into the thunk |
| D7 | context uniquing | attribute and type `get` (a hash and a shard lock), `StringAttr` interning, `SymbolTable` lookups by `StringAttr` | MLIR's identity of IR (§1.4) | at T2 for constants; at IR creation; hot-path symbol lookups replaced by `FunctionId` (05 T5.1); what remains is the parser, `verifySymbolUses` and the lowering's new LLVM functions |
| D8 | parsing and printing | mnemonic → `OperationName` (a hash); `symbolize<E>(StringRef)` (generated); bytecode dispatch by code (a generated switch) | text and bytecode at the tool boundary | once per entity read |
| D9 | actions and debug counters | `-mlir-debug-counter` and `--log-actions-tags` compare tags as strings | test instrumentation, upstream's | off unless asked; tags generated (§2.3(f)) |
| D10 | the thread pool | `unique_function` tasks | upstream's pool (5.3 D1) | per task |
| D11 | the LLVM backend, lld, the target machine | upstream's | the compiler's back end | — |
| D12 | the program at T4: the handle slot's alternative, OS calls, the signal handler, the startup checks of CPU and page size, simdutf's choice for features beyond the baseline, a big word's small-or-pointer test | data, the machine | the program's input and the machine are T4 facts | once at startup, or per value where the value varies |
| D13 | hash maps keyed by program data | the run's interner (keys, structural digests); a numbering builder's `Value` → id map, freed when its arrays are built | program data hashed once | one hash per datum per run |

**Dispatch on program data, listed for completeness.** A `match` over a
variant, which is a jump table (§3.5). A grade or kind read from an
operand's type, then a `constexpr` table (§2.3(d), slot 4). A data body's
view, a `match` (§2.3(c)). A function's id, an array index.

**The three hardest.** These three cannot be removed:
1. **D1 and D2 together: dispatch over the open op set.** Every walk pays
   one interface lookup per op, because the op set is open to C++ and
   TypeIDs are addresses. The design concentrates all of its per-op
   facts behind that one lookup.
2. **D4: upstream's rewrite and conversion drivers.** Their pattern
   indices are built at run time, and `TypeConverter` keeps its
   conversions in `std::function`s. The design builds them once (T2)
   and roots every pattern, but cannot make them compile-time without
   replacing upstream's drivers, which "upstream first" forbids.
3. **D7: context uniquing and symbol tables.** Every attribute, type and
   symbol name is hash-consed under a lock at run time. The design
   moves every program-independent one to T2, and the solve away from
   the context, but every piece of IR the compiler writes still pays it.

## 7. The cost of compiling the compiler

### 7.1 The baseline that must exist first

There is none today (*read*: 13 §2.7, DP-59). The only record is a stale
`.ninja_log` of the typecheck build: host clang, Debug, 2026-10-12 to
10-18. Its 353 objects averaged 7.26 s of wall time each, with
`Driver/Run.cpp` at 40.1 s and `Transforms/Pipeline.cpp` at 19.9 s. That
was measured under parallel load with some ccache hits, so it is an
indication only.

The build's shape (*measured*: 13 §2.7, this document):
- 294 C++ units under `lib`, `tools` and `unittests`;
- 228 of them include `mlir/` directly;
- 260 include `idr/IR/IdrDialect.h`. That header includes 20 MLIR
  headers (03 O-98) and the generated `IdrOps.h.inc`, which is 38,361
  lines and 2.0 MB (*measured*:
  `build/typecheck/.../IdrOps.h.inc`, dated 2026-10-18).
- `IdrOps.cpp.inc` is 59,654 lines, compiled as one unit with
  `GET_OP_CLASSES` (*read*: `lib/IR/Ops.cpp:301`).
- MLIR's core headers preprocess to 141,000 lines. One unit of them
  costs 1.54 s at `-O0`, and 0.43 s with a precompiled header
  (*measured (host)*, 5.5 F11).
- By arithmetic, headers alone take about 7.5 CPU-minutes per clean
  build, and about 2.1 minutes with a PCH (13 DP-55).

The compiling clang is stage 2, with assertions on (13 DP-57). Every
compile-time number states it.

**Step 0 records**, at one commit (main is green at 1e1907ab, 470/480):
- a `-ftime-trace` preset (13 DP-59);
- clean-build CPU time and wall time;
- the 20 slowest units;
- the 20 costliest templates and instantiations, summed over units from
  the traces;
- header parse time against code generation per unit.

That record is P0's compile-time baseline. Each later step leaves the
same record.

### 7.2 Precompiled headers

One PCH on `IdrIR`, reused by every target of ours through
`target_precompile_headers(REUSE_FROM)` (DP-74; 13 DP-55). Its contents,
in order:
1. libc++: `<variant>`, `<span>`, `<array>`, `<optional>`, `<expected>`,
   `<ranges>`;
2. LLVM's ADT;
3. MLIR's `mlir/IR/pch.h` set, plus `Pass` and `Interfaces`;
4. `IdrDialect.h`, with its generated declarations;
5. the vocabulary headers of §3;
6. last, the poison pragma (§7.6).

**ccache.** The premise against a PCH ("ccache cannot cache one",
`CMakeLists.txt:40-41`, `tools/bootstrap.sh:265-273`) is refuted. LLVM
passes `-Xclang -fno-pch-timestamp` for exactly this
(`llvm/cmake/modules/HandleLLVMOptions.cmake:1458-1466`; 5.5 D6). Our
ccache sloppiness gains `pch_defines,time_macros` (13 §6 cxx-Q3;
recalled from ccache's documentation).

**Macros.** A PCH fixes the macros every unit sees, so libc++'s
hardening mode must be the same for every unit of a target. It already
is: one flag in `CMAKE_CXX_FLAGS` (*read*: `CMakeLists.txt:326`). DP-75
decides the mode.

**Risks** (5.5 D6): a PCH hides missing includes, and names can collide.

**Expected gain.** About 7.5 → 2.1 CPU-minutes of headers (*conjecture*:
arithmetic on 5.5 F11). LLVM's own RFC measured about 3× on the front
end (5.5 F15).

### 7.3 Op definitions in parallel

`add_sharded_ops` and `-op-shard-count` split `IdrOps.cpp.inc` across N
units (*read*: `AddMLIR.cmake:159`, `OpGenHelpers.cpp:91-100`). Then no
single unit compiles 59,654 lines of op definitions.

Splitting declarations by family (`-op-include-regex`, *read*:
`OpGenHelpers.cpp:27-31`; 03 O-98) is rejected. The PCH already
amortizes `IdrOps.h.inc`, and a per-family split would fight it.

### 7.4 Templates: what they cost, and how it is paid

- **The cliff.** `std::visit` is not used (§3.5). The fold `match` costs
  3 to 4 ms per site more than a `dyn_cast` ladder (*measured (host)*,
  5.5 F12). At about 200 sites that is under a second.
- **Callbacks.** Templates cost about 1.6 ms more per site than a
  `function_ref` (5.5 F13). At about 100 sites that is a fraction of a
  second.
- **Solvers.** Each is instantiated once, behind `extern template`, its
  definitions in `*Impl.h` headers included by one unit each (§3.4).
  There are about 15 to 20 such instantiations (5.3 S1). Each costs
  seconds at most (*conjecture*), paid once, in parallel.
- **Generated specializations** (`Abi`, `Guarded`, `Division`,
  `TypedEffects`, `IndexOf`) are tiny structs. Their headers are
  included only by their readers, never by `IdrDialect.h`.
- **Interface models.** MLIR already instantiates one `Model` per op and
  interface, and pays that today. `IndexedOp` adds one model per op. Its
  body uses only `ConcreteOp`'s index, a constant, so it inlines to a
  load. Bodies that need no concrete op move to `$_raw_op` (5.5 F16).

### 7.5 Depth and step limits at the pin

- **Template recursion: none.** Type lists use pack indexing (P2662R3,
  Clang 19) and folds. The instantiation depth limit of 1,024 (*read*:
  `LangOptions.def:387`) is never approached.
- **Fold expressions** count against the bracket depth.
  - The pin's cc1 default is 2,048 (*read*:
    `clang/include/clang/Options/Options.td:9036`). `LangOptions.def:395`
    initializes the field to 256, which is the value 5.5 F19 cites; the
    cc1 marshalling default is what applies when no flag is given
    (*conjecture* on that precedence).
  - Either way, no fold in this design spans a generated list. Lists of
    189 ops expand through `initializer_list` or generated arrays, as
    MLIR's `addOperations` does (*read*:
    `mlir/include/mlir/IR/Dialect.h:277-284`).
- **constexpr evaluation** is capped at 1,048,576 steps and a call depth
  of 512 (*read*: `LangOptions.def:389-391`).
  - The validators at T1 are linear: order and completeness of a
    189-row table.
  - Exhaustive law checks run per component: 2³, 4³ and 3³ cases.
  - Checks of O(n²) or worse run in the generator at T0 (R4).

### 7.6 Enforcement the compiler does for us

- **Warnings, added** (13 DP-58; 5.4 design 8):
  - `-Wcovered-switch-default`, with `-Wswitch` already in `-Wall`;
  - `-Werror=global-constructors`, after `cl::opt` and `llvmZones` move
    into the invocation (13 DP-49);
  - `-Wthread-safety`, with `GUARDED_BY` on the locked members;
  - `-Wsuggest-override`.
  With `-Werror` (*read*: `CMakeLists.txt:344-361`), these hold the
  generated exhaustive switches, the ban on static constructors, and our
  few locks.
- **Poisoned identifiers.** `#pragma clang poison` makes any later use
  of an identifier an error. The PCH's last line poisons the identifiers
  this design removes:
  - `MatchAnyOpTypeTag`;
  - `holds_alternative`;
  - `get_if` (used inside `match` only, and `match` is parsed before the
    pragma);
  - `TypeSwitch`, once its four uses go (*read*: `DataRemap.cpp:36`,
    `Symbols.cpp:20`, `Narrow/Ops.cpp:146`, `Nests.cpp:242`; deleted by
    01 C9, 03 O-83, 11 I-NA8 and C3).

  Poisoning is lexical, so headers parsed before the pragma are
  unaffected.

  It is *conjecture* that no upstream header a unit includes after the
  PCH uses a poisoned identifier. The first build answers that, and any
  header that does joins the PCH. `std::visit` cannot be poisoned,
  because `visit` is a common identifier; it stays a review rule. Each
  identifier is poisoned in the same commit that deletes its last use.
  The cutover then locks the door behind it.
- **`= delete("reason")`** on raw indexing (§3.1, §3.2), with a message
  saying why.

### 7.7 What is measured, and when

Every landing step of §8 leaves the compile-time record of §7.1 next to
its stage-1 record. A step that raises clean-build CPU time names the
cause in its commit message: the template, the header or the unit. The
threshold that would stop a step is the owner's to set. This design
proposes none, because a cost is recorded, not refused.

**Rejected, as in 5.5:**
- C++20 modules and `import std`. Clang defines `__cpp_modules` as 1,
  libc++'s `std` module is experimental, and macros do not cross an
  import (5.5 F14). Modules were also tried here and taken out
  (4cfce768, then 1e1a3827; 13 §6).
- Unity builds, which merge anonymous namespaces and hide missing
  includes (5.5 D6).

**Estimate for a tree of about 60,000 lines** (*conjecture*): headers
are about 2 CPU-minutes with a PCH, templates add seconds, sharded op
definitions remove the longest single unit, and a clean build at the
machine's width is dominated by the link and by LTO in release.

## 8. Landing

The order, as hard cutovers. Each step deletes what it replaces in the
same commit; the deletions are the lanes' §7 lists. Each step passes:
- **the gate:** E2's: build, five suites, the invariant set (19 C3), and
  a stage-1 record (DP-22, DP-07);
- the compile-time record of §7.1;
- byte-identical generated outputs wherever the representation did not
  change;
- the step's own measurement.

1. **Measure.** The `-ftime-trace` preset and the baseline record (§7.1;
   13 DP-59), on a green tree.
2. **Build.** The PCH (DP-74), sharded op definitions, ccache
   sloppiness, the new warnings, and `cl::opt` and `llvmZones` moved into
   the invocation (13 DP-49). There is no non-PCH path to keep.
3. **The generator's typed model** (14 TD1, TD9), with ABI kinds as
   records (02 E72; 12 CV-54) and the generator's error fixtures. Gate:
   every generated file byte-identical.
4. **Enums and tables**, with their first clients:
   - `Enum.h`, `EnumTraits`, and renumbering dense from zero;
   - rule categories and scope (16 G5, deleting `Profile.outsideLanguage`);
   - `CmpPredicate`'s fields (14 TD5, deleting `Layouts.cpp:235-249` and
     `Emit/Operations.idr:176-194`);
   - print actions (13 DP-19) and `Form` (11 I-SL1).
5. **The pipeline as records** (13 T2), with the tests' pass table
   (19 C2), generated registration, action tags (13 DP-53), and
   `StagedPass` as CRTP (if accepted). Gate: the generated pipeline
   equals today's `--dump-pass-pipeline` text (13 §5, order 3).
6. **`OpIndex` and families as specializations**, landing with
   cluster A's families-from-lists (03 R1; 12 T1; 04 T1; 11 I-NA9) and
   stage legality per op (03 O-1, O-61; DP-47). The generic runtime fold
   replaces the 37 folder bodies.
7. **The effect system** (§2.3(d)), after DP-01 to DP-03:
   - the generated tree, rows, rules and summary;
   - the verifier rule;
   - the LLVM mapping, with its upstream patch.
   It deletes everything 02 T1 to T7 lists. Gate: the 16 `effects-*`
   fixtures (06 §8, risk 5).
8. **The solver layer.**
   - `Id.h`, `Graph.h`, `Lattice.h` and `Solve`, with the stack
     inference as first client (08 T9);
   - then `ProgramGraph` (05 T5.1), replacing `CallCycles`, `Recursion`
     and `Scc.cpp`;
   - then borrows (07 D3) and exclusivity (07 D2), with lane 07's corpus
     comparison before the old solve goes (B §7);
   - then the label solve (06 T2) and the optimizer (09 T1-T4).
   Each solver has its own instantiating unit, and each unit is an
   action. Gate: per-solver footprint, and one thread against many
   (Q-llvm-6).
9. **Counting, tail, arrays and lowering**, in the order lanes 08, 11,
   10 and 12 give (13 §5, order 4):
   - `place<LiveSet>` and the folding `is_unique`;
   - `TailEnd` and the plan sums;
   - `Form` and `Element`;
   - `Representation` and crash sites as data.
10. **The runtime's typed core and its generated instantiations** (18
    T-RC2, T-RC4, T-RC5, T-ABI1, T-ABI2, T-PL1, T-PL2, T-IO1, T-NU1),
    with `Ending` and the harness's one ending (18 T-END1; 19 C4),
    landing before any step that rewrites fixtures (C §6, step 2.5).
11. **The poison pragma**, one identifier per commit, each in the commit
    that deletes its last use (§7.6). Then a hard cleanup.

**Dependencies on decisions (the owner's and the coordinator's):**
- **Steps 1 to 5 need none.**
- Step 6 waits on the op redesign's families (A §6).
- Step 7 waits on DP-01 to DP-03.
- Step 8 waits on DP-53, plus DP-06 (`Positions`) for counting's queries.
- Step 10's statuses wait on DP-18, and its count encoding on DP-59.

The coordinator decides DP-73 (`match` against `std::visit`), DP-74 (the
PCH) and DP-75 (hardening).

## 9. What the pin blocks, and the workaround

| wanted | at the pin | instead |
| --- | --- | --- |
| static reflection (P2996): enum names, member lists, generated aggregates | No: a cc1-only `-freflection`, `^^` of builtin types only (5.5 F1) | TableGen is our reflection: every list is generated (§2); nothing waits for P2996 (5.5 D9) |
| iterating expansion statements over a `constexpr` range | No: "iterating expansion statements are not yet supported" (5.5 F1) | the enumerating form over a pack (`{I...}`), or an `index_sequence` fold (§3.5) |
| concept template parameters (P2841) | No | a predicate class template where a type list is filtered by a concept |
| constexpr structured bindings (P2686) | No | named members |
| contracts (P2900) | No | types first; `assert` where a precondition is not yet a type |
| exceptions in constant evaluation (P3068) | No | `static_assert` with a generated message (P2741R3, Clang 17) |
| `std::inplace_vector`, `move_only_function`, `std::execution`, `std::generator` | No (5.5 F5) | `llvm::SmallVector`, `llvm::unique_function`, MLIR's pool |
| C++20 modules with MLIR | not usable (5.5 F14) | the PCH (§7.2) |
| `scc_iterator` indexing by node number | an upstream gap, not a clang one (§3.3) | the proposed upstream patch; the map until it lands |
| effects on `llvm.call` | upstream has no `MemoryEffectOpInterface` on it (12 §3.1) | an upstream patch, for §2.3(d) slot 7 |

## 10. Sources read

- `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md`
  (with the new rule); the owner's preferences as held in this
  workspace's memory.
- `proposals/0000-mlir-native.md` §0-§4, §5.2 (the recipe table),
  §5.3 (whole), §5.4 (F3, F13, F18, F19, design 1, design 8, design 9,
  notes), §5.5 (whole), §8, §9, as first read; the same text now under
  `audits/p0/wave1/` (`00-brief.md`, `5.2-mlir-ods.md`, `5.3-llvm.md`,
  `5.4-modular.md`, `5.5-cxx26.md`, `questions.md`).
- `audits/p0/synthesis/A-dialect.md`, `B-analyses.md`,
  `C-memory-backend.md`, `D-idris-side.md`, `E-process.md` (whole);
  `F-decisions.md` (§1, DP-04, DP-08, DP-47, DP-53, DP-69 to DP-75).
- `audits/p0/01` to `21`: §4 rows tagged cpp, ladder, list, state and
  rederivation, and every §5 code sketch. These were extracted
  exhaustively by four read-only helpers and spot-checked against the
  documents. Also 13's build and compile-time passages (§1, §2.1, §2.2,
  §2.7, §3.1, §5 T2, T7, §6, §8).
- `audits/p0/design/perf-sources.md` (whole).
- `git show origin/main:audits/flamegraph-2026-10-21.md` (whole); the
  messages of 101edbc5, 0be4e660, e96bb991, ffa91113, b8301ebe,
  98c6315c, 3a96c407, 7987388b, 73bba53f; `git log e96bb991..origin/main`.
- Ours: `foreign/idr/tools/idris-mlir-tblgen.cpp` (header, outline,
  `:706-800`, `:2749-3255`); `include/idr/IR/IdrRuntime.td`;
  `IdrBase.td:83-124, 255-300`; `IdrScalarOps.td:15-70`;
  `include/idr/IR/CMakeLists.txt`; `include/idr/Transforms/Passes.td:1-80`;
  `lib/Transforms/Pipeline.cpp`; `include/idr/Transforms/Pipeline.h`;
  `lib/Conversion/RuntimeCalls.cpp:90-185`; `include/idr/IR/Fold.h:30-60`;
  `include/idr/IR/Traits.h:120-160`; `lib/IR/Ops.cpp:215-300`;
  `include/idr/IR/Grades.h`; `include/idr/Support/{Profile,Actions,Worklist,Scc}.h`;
  the generated `build/typecheck/foreign/idr/include/idr/IR/{IdrGuards,IdrRuleCategories,IdrRuntimeAbi,IdrTable.h}.inc`
  and the sizes of `IdrOps.{h,cpp}.inc` (stale, 2026-10-18);
  `CMakeLists.txt:300-361`; counts of `virtual`, `std::function`,
  `TypeSwitch` and units (grep, find).
- Upstream at the pin: `mlir/include/mlir/Pass/Pass.h:180-200`;
  `mlir/lib/Pass/Pass.cpp:482-520, 920-935`;
  `mlir/include/mlir/Rewrite/FrozenRewritePatternSet.h:91-95`;
  `mlir/include/mlir/IR/PatternMatch.h:159, 348`;
  `mlir/include/mlir/Support/InterfaceSupport.h:200-285`;
  `mlir/include/mlir/IR/OpDefinition.h:1716, 1774-1782`;
  `mlir/include/mlir/IR/Traits.td:25-50`; `mlir/include/mlir/IR/OpBase.td:30-50`;
  `mlir/include/mlir/TableGen/SideEffects.h:24-53`;
  `mlir/tools/mlir-tblgen/OpGenHelpers.cpp:27-100`;
  `mlir/tools/mlir-tblgen/PassGen.cpp:194-339`;
  `mlir/cmake/modules/AddMLIR.cmake:159`;
  `llvm/utils/TableGen/SearchableTableEmitter.cpp:1-20, 356-380, 860-878`;
  `llvm/include/llvm/TableGen/SearchableTable.td`;
  `llvm/include/llvm/ADT/SCCIterator.h:40-100`;
  `llvm/include/llvm/ADT/GraphTraits.h:75-106`;
  `llvm/include/llvm/ADT/PostOrderIterator.h:40-51`;
  `clang/www/cxx_status.html` (C++2c rows; P2741R3, P2738R1, P2747R2,
  P2686R5, P3068R6); `clang/include/clang/Basic/LangOptions.def:385-397`;
  `clang/include/clang/Options/Options.td:2295-2299, 4731, 9036`;
  `clang/test/SemaCXX/fold_expr_expansion_limit.cpp`.
- Commands: `git show`, `git log`, `git diff` (read only); `grep`,
  `find`, `wc`. Nothing was built or run.
