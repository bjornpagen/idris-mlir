<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane ods-types: the type system

*Complete (2026-10-21), at e96bb991 plus the working tree's uncommitted
proposal. No built compiler exists in this checkout: every count is over
the source, with its command. Scope: `IdrTypes.td`, `IdrAttrs.td`, `IdrBase.td`,
`IdrBytecode.td`, the type and type-constraint definitions in
`IdrOwnershipOps.td` and `IdrArrayOps.td`; `lib/IR/{Types,Attrs,Grades,
Lifetimes,TypeGraph,DataBody,ConAttr,TypeLiterals,ValueFacts}.cpp`,
`lib/IR/Layout/`, `lib/IR/Verify/`; their headers.*

## 1. Reading notes

### §0-§4

- §2 brief: 13 types, 10 attributes; types `token, cell, data, box, fn,
  lazy, str, big, nat, world, q, dest`; `data` is mutable, its body held
  once by the program's table; attributes `con, closure, big, #idr.types`;
  type interfaces ValueFacts, Literal. The grade `!idr.q<quantity,
  permission, T, lifetime>`, shorthands `lin` (one, plain), `own` (many,
  own), `excl` (many, excl), checked after every pass (§2, citing
  `IdrTypes.td:270`).
- §3 walls in this subsystem: 98c6315c (`idr-optimize` threads queued on
  the context's write lock: a mutable type's facts read under the
  context's lock), 73bba53f (`idr-defunctionalize` 843 s: the table of
  data types rebuilt per declaration).
- §4: grades in types, verified after every pass, never discardable.

### §5.1 mlir-analysis

- F3 (read): a mutable type's mutation takes one shard's writer lock;
  reads of its mutable part are unsynchronized (caller guarantees no
  concurrent mutation); creating a parametric type or attribute takes a
  shard's writer lock (`StorageUniquer.cpp:160-193`). Anything that
  creates types or attributes on a hot path grows the context for good.
  Bears on: the `data` body, `#idr.types`, and every `q`/`lin`/`own` type
  built by passes (W5).
- W5: every attribute or type created on an analysis's hot path. Mine
  for types built in verifiers and in ValueFacts/Layout queries.
- 5.1.2.7: no attribute or type created on a solver's hot path.

### §5.2 mlir-ods

- D1: a TypeDef's parameters (`EnumParameter`, `ArrayRefParameter`,
  `OptionalParameter`, ...), `genVerifyDecl`, `assemblyFormat`,
  `genMnemonicAlias`; the hand part is the verifier body and custom
  directives.
- D2 (read): `MutableType`: mutate takes one shard's writer lock; reads
  take none, so a body must be complete before threads read it; the
  bytecode writer always writes a mutable type as **text**
  (`BytecodeWriter.cpp:893-900`); mutating a base instance is
  unsupported inside a transient scope.
- D3: properties are the one in-op place a large structure may be
  mutated without the context.
- D4: one `EnumInfo` gives enum class, stringify, symbolize, parser; the
  same record is attribute, property or type parameter.
- D5: type constraints emitted once per file, called from
  `verifyInvariantsImpl`.
- H2 (read): a type's `verify` runs once per unique instance, at
  creation: "a fact checked in a type's verifier costs nothing after
  creation, however many passes run".
- H3: after every pass the pass manager verifies the op the pass ran on,
  recursively; a module pass re-verifies all 70,000 functions.
- H1: verifier parallel only over `IsolatedFromAbove` children.
- M9: grades: quantity and permission as `EnumParameter`s, well-formedness
  in `genVerifyDecl`, `lin`/kin as builders and printer aliases; what
  must be checked after every pass is the *use* (a linear value used
  once, a grade kept across an op): `verifyTrait`/`verifyRegionTrait`.
- M10: the `data` table: upstream reads a mutable body without a lock, so
  98c6315c's lock came from a uniquing or mutating call on a read path
  (W6); a table in an immutable uniqued attribute is rebuilt and
  re-hashed on every change (73bba53f).
- M11: verifying after every pass: nest passes on functions; mark
  analyses preserved; grades in type verifiers where they cannot change.
- M14 / row 21: bytecode encodings via `-gen-bytecode`; a mutable type
  always goes as text.
- Rows 15, 16: a fact a type carries is a TypeDef parameter; a
  classification of types is a `TypeInterface`.
- Design 3: "facts in types, uses in traits, symbols in
  `verifySymbolUses`".
- Q6 (owner): verification after every pass (= ods-Q6).
- W3 (verify bodies), W6 (the data lock), W7 (measure the verifier),
  W8 (bytecode), W10 (`$_op` vs `$_raw_op` in interface bodies) fall
  partly in my subsystem.

### §5.3 llvm

- M8 (5.3.2): 98c6315c is "a fact kept in a uniqued mutable type rather
  than in frozen analysis data"; lld/BOLT freeze or partition data.
- S0: "Grades in types (`!idr.q`) are the same move for linearity" as the
  world token is for IO: a representation that makes a solve unnecessary.
- B3/I3, B4/I4: closed sums of our C++ data visited once (`std::visit`),
  sums of handles as `PointerUnion`. I8: a C++ list mirroring records is
  generated (`EnumAttr`, `!instances`, `GenericTable`). Applies to
  `Grades.cpp`'s tables and switches over `Quantity`/`Permission`.
- I7: per-node state a vector indexed by a dense number (relevant to
  `ValueFacts`, `TypeGraph`).

### §5.4 modular

- 5.4.2.7 / Design 5: "never reads a mutable fact out of a type"; check
  whether the table as an immutable attribute built once plus a per-worker
  front makes 98c6315c unrepresentable; facts read by many threads in
  immutable attributes built once, never in a mutable type.
- 5.4.2.8: `!idr.lin<T>` and the grades survive specialization (Mojo
  erases origins; we must not).
- F16 / Q-M2: Modular verifies after every pass only in development, with
  explicit verifier passes at phase boundaries in production. Q-M2 asks
  whether to split: grade check after every pass always, full structural
  verifier in development and at boundaries.
- W (5.4.4): "every fact read from the mutable `!idr.data` type by many
  threads (design 5)"; "whether release builds verify after every pass
  today".

### §5.5 cxx26

- D1: MLIR interfaces/traits for anything over ops, types and attributes;
  concepts may *read* ODS (`OpT::hasTrait<>()` constexpr), never *list*
  ops. A ladder over our type classes (`isa<LinType, OwnType>`) is a type
  interface or a parameter, not C++.
- D2: closed sums of our own types: `std::variant` plus one `match`; no
  `holds_alternative`/`get_if` validators. Bears on `Layout`'s and
  `ValueFacts`' sums, if variants.
- D4a: a list over IR is generated from ODS (the grade tables, the
  quantity/permission names); D4b: a C++-only list is one constexpr table
  checked by `consteval` against its enum.
- D8: `std::expected<T, Reason>` where the failure is data (a refusal's
  category).
- finding 16: interface method bodies over `$_raw_op` share one callback;
  for type interfaces the same applies.

### §5.6 ecosystem

- D6 (read): IREE's one whole-program answer that later passes rely on is
  written into types once (`!stream.resource` lifetimes), and its author
  regrets the lossy mapping: "the type should hold the answer's own bits,
  not a lossy summary of them". Our grades are already this.
- 5.6.2.1: a solver's domain is the values whose *type leaves its
  question open*, read off the type (a `lin` value is used once; an
  `excl` value is exclusive); the type system makes the other states
  unrepresentable in the solver.
- Design 2: the filter "is not a C++ predicate but the type's own answer:
  a type interface method in ODS (§2's `ValueFacts` is the candidate)".
- Q-E2 (owner): where a summary lives: analysis object or IR (a type, an
  inherent property) verified after every pass.
- W-E2: for each solver, the values it keeps state for against those
  whose type leaves its question open (the type side of it is mine:
  which types answer which question).
- W-E4: any fact in a discardable attribute.

### §5.7 library

- M1: a quantity-1 value is used exactly once, so for linear values the
  IR has static single use: backward ownership analyses over them are
  sparse equation systems. The grade in the type is what gives SSU.
- M6 (recalled from `notes/compile-pipeline/casework-audit.md`): the
  context-lock wall and the per-declaration table rebuild are "a
  mutable, nominal type read while it may change"; an interned
  structural description makes "same type" an integer compare.
- L1 / QL2 (owner): SSI for ownership: every ownership change a new value
  (consume, share, borrow, give, take, enter a linear scope); a case
  region binds its refined scrutinee; quantity-1 keeps single use by type.
  Bears on: whether the type system can say "the refined scrutinee" and
  "the new ownership state" as a type, which grade changes.
- L3: "build, then freeze: interned program tables": the table of data
  types built once at a pass boundary as an immutable interned
  structure; a pass that changes it builds the next version. Costs: "a
  structural type identity where today's is nominal (§5.8)". Made
  unrepresentable: a read racing a write of a program table.
- W (5.7.4): "where a parallel pass reads a mutable type or anything
  under the context's lock; where a program table is rebuilt (L3)".

### §5.8 dialect-design (the guide this lane applies)

- Summary (1): a value's type is the only per-value fact every pass
  keeps; idiomatic form is **one grade attribute inside the type,
  implementing an interface verifiers ask, normalized so the
  unrestricted grade is the bare type** (B6, T1-T4, DS1).
- B1: strict type equality: every regrade is an op; every op accepting
  several grades says so in its operand constraint.
- B2: no SSA values in types (lifetime parameter must be an attribute).
- B5: defaults normalized away at construction (memref identity layout).
- B6: `!ptr.ptr<#space>` with `MemorySpaceAttrInterface::isValidLoad`
  etc.: the qualifier's algebra lives with the qualifier.
- B7: type traits/interfaces classify types; an op's operand constraint
  names the interface.
- B8: mutable types are the exception; LLVM identified structs mutate once;
  "if a concurrent thread initializes the type before the current thread,
  the initialization may return failure"; transient scopes.
- B9: a function pass may read ancestors, not siblings: a type whose body
  lives in a sibling declaration cannot be read by a parallel function
  pass; a body in the type or on an ancestor can.
- B10: verifiers are local; don't follow def-use chains; whole-function
  invariants are passes ("transform-dialect-check-uses").
- E1 (CIRCT): qualifiers as parameters on one base class;
  `RecursiveTypeProperties` computed once in storage so a classification
  is a bit test.
- E2 (CIRCT): normalize a type only when no op's legality depends on the
  difference; "type canonicalization may make illegal operations legal".
- E3: builders may return a simpler type (`!hw.int<32>` -> `i32`).
- F1 (FIR): a qualifier that must hold at every use is a type; illegal
  nestings refused in the type verifier.
- F2 (FIR): effects derived from a type parameter by one helper
  (`addVolatileMemoryEffects`); one cast may change it.
- F6 (CIR): recursive records as `MutableType`, `mutate()` with an
  agreement check, cyclic print/parse guards; name-keyed identity costs.
- G2 (KGEN): de Bruijn indices inside uniqued types; ChrisL's warning
  against one generic attribute with a growing enum.
- G3 (KGEN): no mutable types; nominal structs via symbols.
- T1: grades are types because nothing else survives every pass.
- T2: the grade's algebra (duplicate, discard, write in place, join,
  legal regrades) written once in the grade attribute, every verifier
  and lowering asks it.
- T3: normalize at construction: the unrestricted grade is the bare
  type, never a wrapper (subject to E2's limit).
- T4: make illegal grade combinations unrepresentable: one enum of legal
  grades replaces (quantity, permission); quantity 0 is already
  unrepresentable, the type's quantity has two values left.
- T5: lifetimes are regions first, attributes second, never SSA values;
  "the fourth parameter of `!idr.q` is the place to look".
- T6: a function type carries conventions and effects; B9 is the catch.
- T7: classify types with traits and interfaces and cache recursive
  properties in storage: "`ValueFacts` is the natural home of 'contains
  a linear field', 'contains a reference', 'is trivially copyable', 'has
  a runtime form', computed at construction, not per query".
- T8 / DS3: recursive types: DS3.1 immutable table on the ancestor
  `program` op with types naming an entry by index; DS3.2 identified
  types mutated once (CIR); DS3.3 structural with de Bruijn
  back-references; DS3.4 symbol declarations (rejected by B9).
- O3: a regrade is a cast whose result type is computed
  (`TypesMatchWith`) and whose legality is the grade's.
- DS1.1: `!idr.g<T, #idr.grade>` with `Idr_GradeAttrInterface`
  (`mayDuplicate`, `mayDiscard`, `isUnique`, `join`, `canRegradeTo`),
  builder returns `T` for the unrestricted grade, aliases `lin/own/excl`.
  Lifetime leaves the type if borrows become regions, else stays a
  normalized symbolic attribute.
- DS1.2: one TypeDef per grade (rejected-ish: CIRCT's "two classes ...
  casting bugs"); DS1.3 keep four parameters; DS1.4 SIL form rejected.
- DS4 rows bearing on types: `token` (builtin or named), `data`
  (DS3.1/3.2), `lin.enter`/`lin.use`/`own.adopt`/`own.give`/`share`/
  `borrow` as one regrade cast.
- Owner: DD-Q1 (may `!idr.lin<i64>` normalize to `i64`?), DD-Q6 (borrows
  as regions, or lifetimes as symbolic attributes).
- Wave 2: which (quantity, permission) pairs occur, what the lifetime
  holds, who reads each; what `!idr.token` is; how the grade verifier
  runs (op verifiers or a pass), whether it follows def-use chains, cost;
  how `data`'s mutability is used, when bodies are set, who reads them,
  the lock path behind 98c6315c.

### §5.9 mlton ("facts into types")

- B5: analysis state sized by *types and constructors*: field facts on
  the constructor; a first-order type maps to one shared abstract value.
- C2: MLton spends a new IR type where the representation change is
  large, a checked invariant where the change is an absence.
- C4: SSA2's `Prod` records mutability per field of the object type.
- F6: representation chosen once per type (`TyconRep`, `ConRep` sums).
- G2.7: "Facts written into the IR's types": after closure conversion a
  closure set *is* a datatype; after useless a dead field is *absent*
  from its type; after representation a type *is* its layout.
- H row 98c6315c: MLton's datatype type is `Datatype of Tycon.t`, body in
  `Program.datatypes`, per-pass facts on the tycon's plist; "the facts
  are never inside the type, so no lock guards them". Row 73bba53f: new
  datatypes pushed to a list and emitted once.
- M6: "the MLton form is an immutable type naming the tycon and an
  immutable table op holding the bodies, with each pass building its own
  tycon-indexed table (Design 3)".
- M11: MLton type-checks at IR boundaries, not after each pass; the
  checker is one linear walk; ours should be that cheap at 70,000
  functions (Q-W7).
- Design 1: "the grade verifier is the instance whose values are types
  and whose `coerce` is the grade order".
- Design 3: a fact is written into a type by the pass that proves it;
  nothing else survives between passes; `!idr.data` an immutable type
  naming its tycon, bodies in one immutable table op; per-tycon facts a
  pass-local table indexed by tycon.
- Q-O3 (owner): Design 3. Q-O5 (owner): verify grades after every pass,
  cost as a measured budget.
- Q-W7: what the grade verifier costs per pass; is it one linear walk.

### §5.10 rc

- G1/G2 (read): linearity restricts the future, uniqueness guarantees
  the past; Idris 2's quantity 1 is the future promise only: "a linear
  binder does not imply unique heap ownership". So `lin` (quantity) and
  `excl` (uniqueness) are two different facts; a grade enum that folds
  them must keep both distinct (Brooks' limit).
- B7: Lean's run-time linearity mark is a dynamic assertion of what
  `!idr.excl` states statically; quantity 1 alone does not state it.
- M3: our grades are OSSA's ownership kinds held in types: `own` =
  Owned, borrowed-with-lifetime = Guaranteed, unrestricted = None; the
  grade verifier should be OSSA's rule (one consuming use per path, every
  borrow ends inside its owner), a linear walk per function.
- M4: `excl` makes a run-time uniqueness test constant true.
- M5: quantity 0 no value; quantity 1 makes a `dup` unrepresentable (a
  verifier error); exclusivity is a forward property from allocation
  sites killed by the first `dup` or ω binding.
- R1.1: "signatures in types": each function's parameter and result
  grades (owned/borrowed, exclusive/shared, local/escaping) live in its
  `!idr.q` types; a per-function pass reads a callee's grades from its
  type. Note: "local/escaping" is a third axis (locality, OxCaml's mode).
- R1.4: `is_unique %x` folds to true when `%x` is exclusive by type: the
  type decides and the folder applies it.
- W3: what `idr-rc-grades` writes; whether parameter and result grades
  sit in function types. W5: the grade verifier: OSSA's rule, linear per
  function, reads consumption from declared traits/effects or re-derives
  it in C++. W7: ownership ops vs the field (lane 03 owns the ops; the
  type side of each regrade is mine).

### §5.11 oom

- C2: uniqued types and attributes live in per-thread allocators for the
  context's lifetime, except in a `TransientScope` (single-threaded, no
  IR referring to them). W8: attributes passes create per function or
  per value, and whether a phase could run under a transient scope.
  Bears on: every `!idr.q` and `#idr.types` instance built by passes.
- Note for dialect-design: OOM must not be an effect; `MemAlloc` on a
  constructor stays free of `Crash`.

### §8 questions this lane gives evidence for

DD-Q1 (8.3), DD-Q6 (8.3), Q-O3 (8.3), Q-E2 (8.3), QL2 (8.3), ods-Q6
(8.6), Q-M2 (8.6), Q-O5 (8.6). Related: DD-Q7 (function type), rc-Q2
(exclusivity static).

### §9 decisions in force

D1 P0 first; D2 own solvers allowed, honest; D3, D4 no code until the
plan is approved.

### proposals/0003-facts-once.md (items in this subsystem)

- "A token without its cell": `!idr.token` has no parameters, so the
  program verifier, `Conversion/Fields.cpp`, `Demand.cpp`,
  `ReusesEveryCell.cpp` each walk back to the `idr.take`; make it
  `!idr.token<!idr.box<T>, @C>` inferred by `TakeOp`.
- "The static lifetime in the grade": `ownership::isStatic`
  (`IR/Verify/Uses.cpp`) walks the definition chain (`madeStatic`);
  readers: counting's classes, `Values.cpp`, `Reuses.cpp`,
  `Narrow/Facts.cpp`, the program verifier. Owed: `static` in
  `Idr_Lifetime` (`IdrBase.td`), ordered static <= heap <= frame, written
  once at the op that makes the value. 467fa2f5..ccc9f4e7 tried it and
  were reverted (c4d38e9b) because they graded from where a value came,
  not what it holds.
- "A `dup` of atoms-only data exempted by its producer"
  (`Verify/OwnedOps.cpp`).
- "Data types carry no location": `Declarations::define` errors at
  `UnknownLoc`; the body should hold the declaration's location.
- `TypeGraph(op)` built directly by `Layouts`, `layout::fit` and the
  program verifier after every pass; `verify::recycles` builds a whole
  `Layouts` to compare two sizes. "`Layouts` takes the `AnalysisManager`."
- `closureLabels` walks every value's type on every run though the sums
  are `TypeGraph::declarations()`.
- "A data type's body holds a kind beside its constructors' roles":
  `DataType::Body` is `{kind, ctors, instance}`; `KindRule`, `RoleOnce`,
  `ruleOf`, verifyBody's table of legal (role, kind) pairs
  (`lib/IR/DataBody.cpp`); owed: `Body` as one alternative per kind,
  `DataType::memo()` its typed view, generated `IdrSum` and bytecode
  `TableBody` following it.
- "The owned stage reads upstream's buffer ops by name"
  (`Verify/Program.cpp` `memref::AllocOp`, `Verify/Uses.cpp`
  `memref::LoadOp`); `Role::Carried`, `takesCarried`, `storedBy`.
- `idris-mlir-tblgen` matches a record by name (`Idr_TagParameter`,
  `Idr_AbiCount`): lane 14's, but the records are in `IdrBytecode.td`.
- `holdsLabels(Value)` (`lib/IR/Flow.cpp`) repeating `carriesLabels(Type)`.
- `knownNonEmpty` (`Crashes.cpp`): "put non-emptiness in the type, as
  `!idr.nat` holds non-negativity".
- Status of 0003: queued after self-hosting; P0 supersedes the ordering.

## 2. What the subsystem is

### 2.1 Files and sizes (measured)

`wc -l` over the files of this lane's scope (command: `wc -l` on the list
below, at e96bb991):

| part | files | lines |
| --- | --- | ---: |
| ODS | `IdrTypes.td` 353, `IdrAttrs.td` 380, `IdrBase.td` 359, `IdrBytecode.td` 70, and the type parts of `IdrOwnershipOps.td` (427 total) and `IdrArrayOps.td` (478 total); `IdrInterfaces.td` lines 15-81 (the two type interfaces) | 2,067 (whole files, the op parts lane 03's) |
| the types | `lib/IR/Types.cpp` 352, `DataBody.cpp` 335, `ValueFacts.cpp` 289, `TypeLiterals.cpp` 65 | 1,041 |
| the grades | `Grades.h` 247, `Grades.cpp` 327 | 574 |
| the frame | `Lifetimes.h` 97, `Lifetimes.cpp` 183 | 280 |
| attributes | `Attrs.cpp` 55, `ConAttr.cpp` 282 | 337 |
| type graph and layouts | `TypeGraph.h` 91, `TypeGraph.cpp` 195, `Layout.h` 325, `Layout/{Layouts 251, Components 204, CellInfo 51, Fit 40}.cpp` | 1,157 |
| the verifier | `Verify.h` 217, `Ownership.h` 82, `Verify/{Program 308, Owned 303, OwnedOps 293, OwnedRegions 370, Linearity 156, Uses 168, Knots 139, Attributes 39}.cpp` | 2,075 |
| C++ total | 27 files | 5,464 |

Definitions (*measured*, `grep -n 'Idr_Type<\|AttrDef<\|Idr_Attr<\|Idr_KeyAttr<'`):
12 types (`data`, `box`, `fn`, `lazy`, `str`, `big`, `nat`, `world`, `q`,
`dest` in `IdrTypes.td`; `token`, `cell` in `IdrOwnershipOps.td:33,158`);
11 attribute definitions (`con`, `closure`, `big`, `key_hole`, `key_con`,
`spec_key`, `key_raise`, `instance`, `types`, `refusal` in `IdrAttrs.td`;
`world` memory space in `IdrArrayOps.td:236`) and `RuleAttr`
(`IdrAttrs.td:366`); 9 enums of this lane (`Quantity`, `Permission`,
`Lifetime`, `SumKind`, `CtorRole`, `RuleCategory`, `Rule`, `CheckKind` in
`IdrBase.td`; `Effect`, `CmpPredicate` in `IdrAttrs.td`); 2 type
interfaces (`ValueFactsTypeInterface`, 5 methods, and
`LiteralTypeInterface`, 2, `IdrInterfaces.td:24-81`); 29 type constraints
across the dialect's `.td` files (`grep -rnE 'def Idr_[A-Za-z0-9]*\s*:\s*(Type<|AnyTypeOf|Idr_AtAnyGrade|Idr_BaseListOf)'`).

C++ patterns in the 27 files (*measured*, `xargs grep -c` over the list):
`dyn_cast<` 54, `DenseMap<`/`DenseSet<` 33, `function_ref<` 25, `get_if<`
15, `switch (` 13, `holds_alternative<` 6, multi-type `isa<A, B>` 6,
`std::variant<` 4, `std::visit`/`makeVisitor` 4, `template <` 4, one
`concept` (`Grades.h:210`), `.walk` 9, `TypeSwitch<` 0.

### 2.2 The facts it holds

- **The grade** (*read*): `!idr.q<quantity, permission, value[, lifetime]>`
  (`IdrTypes.td:283-305`), three independent `EnumParameter`s
  (`IdrBase.td:83-108`: `Quantity {One=1, Many=2}`, `Permission {Plain,
  Borrow, Own, Excl}`, `Lifetime {Heap, Frame}`), so 2 x 4 x 2 = 16
  parameter combinations per carrier. In C++ a `Grade` struct of the three
  (`Grades.h:39-48`). Normalized at construction: `graded()` returns the
  carrier itself at (many, plain, heap) and for a type used once by its
  type (`Grades.cpp:28-33`), and `QType::verify` refuses the plain grade, a
  grade of a grade, a grade of a linear-by-type carrier, frame on a carrier
  that reaches no cell, frame with excl, a tensor at any grade but (one,
  plain), and a non-runtime carrier (`Types.cpp:331-352`). So the
  unrestricted grade already is the bare type (T3 of §5.8 holds today).
  Spellings `lin`/`own`/`excl` from one C++ table (`Types.cpp:280-319`)
  wrapping the generated printer (`IdrBase.td:34`).
- **Which grades occur** (*measured*, `grep -rhoE '!idr\.q<[a-z]+, ?[a-z]+'`
  and `'!idr\.(lin|own|excl)<'` over `foreign tests compiler libs`, `.mlir`
  `.idr` `.cpp` `.td`): `own` 679, `lin` 434, `excl` 110, `(many, borrow)`
  349, `(many, own)` 17 (written out, with `frame`), `(many, plain, ...,
  frame)` 13, `(one, own)` 8, `(one, excl)` 2; frame lifetimes 36 in
  `.mlir`. `(one, borrow)` occurs in no fixture but is constructible
  (`view()` keeps the quantity, `Grades.cpp:85-91`). The frontend writes
  exactly one grade, `QType One Plain t Nothing` (`compiler/src/IdrisMLIR/
  Emit/Index.idr:58-59`); every other grade is written by idr-rc in C++.
- **Which carriers `lin` wraps** (*measured*, same grep, `.mlir`):
  `i64` 127, closures of IO 95 + 42 + 14, `!idr.str` 47, `tensor<?xi64>`
  34, data types and boxes about 40. The frontend grades every quantity-1
  binder but the world (`Emit/Monad.idr:80-83`).
- **The data type** (*read*): `!idr.data<"T">`, a `MutableType` identified
  by its name (`IdrTypes.td:29-165`), whose storage holds, once sealed, the
  body (`SumKind`, constructors with a `Role` variant each, the instance),
  an index of tags by name, a tag per single-instance role, and `Held`, the
  facts of what a value holds (`Types.cpp:45-97`). Sealed per group by one
  `mutate` per member (`Types.cpp:199-225`), groups being a parsed table, a
  table read from bytecode, or the outermost `Declarations::define`
  (`Types.cpp:227-266`, `Symbols.h:101-137`). Its text is its name; its
  body is printed once in the program's table (`DataBody.cpp:114-262`).
  Body changes make new types named from content (`DataRemap`,
  `Symbols.h:139-236`).
- **The table** (*read*): `#idr.types<...>` (`IdrAttrs.td:315-358`), an
  immutable uniqued attribute of all members in name order, the
  `types` property of `idr.program` (`IdrOps.td:74-75`); closed under
  containment (`DataBody.cpp:266-298`); remade whole by
  `DataTableAttr::with` once per `Declarations` (`DataBody.cpp:327-335`,
  `Types.cpp:268`, `Func.cpp:47`).
- **What a value holds** (*read*): `ValueFactsTypeInterface`'s five
  questions (`IdrInterfaces.td:24-64`), answered by 55 hand-written
  one-line methods for the dialect's types (`ValueFacts.cpp:129-199`,
  `OpsOwnership.cpp:79-83`), external models for 13 builtin types
  (`ValueFacts.cpp:83-99`), and for a data type from `Held`, solved once at
  sealing by an SCC pass over the group (`ValueFacts.cpp:210-280`).
- **Constants** (*read*): `#idr.con` held as a canonical run of cells
  (`IdrAttrs.td:50-140`, `ConAttr.cpp`); `#idr.big` at its fewest bits
  (`Attrs.cpp:19-24`).
- **Layouts** (*read*): `Layouts` (`Layout.h:253-307`), an analysis built
  from a `TypeGraph`: per sum a `SumLayout`, per boxed data type a
  `BoxLayout`, sizes measured with the module's `DataLayout`
  (`Layouts.cpp:41-104`); `layout::fit` boxes every type that contains
  itself in place, by one `DataRemap` (`Fit.cpp:24-38`).
- **The type graph** (*read*): containment among data types and arrays
  (`TypeGraph.h:44-87`), built by walking every op, its attribute
  dictionary, its result and block-argument types, then the bodies
  (`TypeGraph.cpp:57-111`).
- **The rules of the frame** (*read*): `lifetimes::edgesOf` reads each op's
  flow edges into `Carries | Fills | Passes | Escape` (`Lifetimes.h:41-93`,
  `Lifetimes.cpp:68-129`).

### 2.3 The verifier that checks grades after every pass

*Read*: there are two verifiers, by MLIR's region verifiers.
- **The program's** (`ProgramOp::verify`, `Func.cpp:56-90`, and
  `ProgramOp::verifyRegions` -> `verify::program`, `Func.cpp:105-120`,
  `Program.cpp:253-298`), on one thread. Each run: one walk of every op of
  the program reading `op->getAttrDictionary()` and every result and block
  argument type (`Func.cpp:73-85`); `effectsCovered`, a `bodyEffect` walk
  and a call walk of every function (`Program.cpp:61-72`,
  `Func.cpp:189-202`); a `TypeGraph` built directly, another walk of every
  op with its attribute dictionary (`Program.cpp:266`,
  `TypeGraph.cpp:79-87`); the memo, label and self-containment rules over
  its data types; and in the owned stage a walk for `idr.cell.recycle` and
  a whole `Layouts`, a third `TypeGraph` walk (`Program.cpp:99-118`).
- **Each function's** (`FuncOp::verifyRegions` -> `verify::function`,
  `Func.cpp:179`, `Program.cpp:300-308`), in parallel over functions
  (`IsolatedFromAbove`, `IdrOps.td:110`): `stageRules` (a walk, with
  `namesLabels` type walks and `isStatic` definition-chain walks per value,
  `Program.cpp:171-249`), `verifyFlow` (a walk before defunctionalization,
  `Flow.cpp:339-351`), `linearity` (a numbering walk and per-linear-value
  use walks, `Linearity.cpp:141-156`), `lifetimes` (a walk,
  `Lifetimes.cpp:136-183`), and in the owned stage `owned`, a walk keeping
  per-value maps (`Verify.h:103-212`, `Owned.cpp`, `OwnedOps.cpp`,
  `OwnedRegions.cpp`).

Each of the grade's three halves has its own whole-function checker:
quantity by `linearity`, permission by `owned`, lifetime by `lifetimes`.
The grade's *well-formedness* is `QType::verify`, which at the pin runs at
every `getChecked` call and, in an assertions build, at every `get` call
(`StorageUniquerSupport.h:176-182, 203-210`), never in a release `get`.

When it runs (*read*): the driver never calls `enableVerifier`
(`grep -rn 'enableVerifier\|verifyPasses' lib tools`: nothing), so the
pass manager's default, verification on (`Pass.cpp:1023, 1028`), holds in
every build. After a pass on the program the program is verified
recursively; after an adaptor of nested function passes it is verified
non-recursively (`Pass.cpp:621-642`), which skips the functions but still
runs `ProgramOp::verify` and `verifyRegionInvariants`
(`Verifier.cpp:355-381`), so **the program's serial O(module) walks run
after every pass and every adaptor**. Program-anchored `addPass` calls in
the pipeline: 37 (*measured*, `grep -c 'program.addPass\|lowered.addPass\|pm.addPass' lib/Transforms/Pipeline.cpp`),
about 19 of them before lowering, where idr functions exist.

### 2.4 Data structures and state (read)

- Per data type: `DataTypeStorage` (`Types.cpp:45-97`): the body, `byName`,
  `roleTags[6]`, `Held`, `defined`. Never freed (context lifetime).
- Per program table version: one `DataTableAttr` of n pointers, uniqued in
  the context; a new one per `Declarations` end and per remap.
- Per `TypeGraph`: `DenseMap<Type, unsigned>`, two `DenseSet<DataType>`, a
  `SmallVector` of successors per node, a `SmallVector` of in-place
  successors per node, and the SCCs (`TypeGraph.h:77-86`).
- Per `Layouts`: `DenseMap<DataType, unique_ptr<SumLayout>>`,
  `DenseMap<Type, pair<unsigned,unsigned>>`, `DenseMap<DataType,
  BoxLayout>` (`Layout.h:298-306`).
- Per owned verify of a function: `DenseMap<Value, Role>`,
  `DenseMap<Value, Slot>`, `DenseMap<Value, unsigned> written`, an undo log
  (`Verify.h:202-211`).
- Per linearity verify: `DenseMap<Operation *, unsigned>` places
  (`Linearity.cpp:42-66`), and per linear value a `DenseSet` of holders and
  a `DenseMap<Block *, ...>` (`Linearity.cpp:133-136`).

### 2.5 Who reads it (measured)

Call sites outside their definitions (`grep -rnE "(idr::|[^A-Za-z_.>:])f\("
lib tools unittests --include='*.cpp'`, `Grades.cpp` and `ValueFacts.cpp`
excluded): `unrestricted` 100, `dataTypeOf` 47, `isOwned` 31,
`holdsReferences` 26, `heldAs` 24, `sourceOf` 20, `isExclusive` 16,
`throughLinear` 14, `quantityOf` 13, `owned` 13, `lifetimeOf` 13,
`gradeOf` 13, `fieldType` 12. Direct uses of the grade's enums outside
`Grades.{h,cpp}`: 47 lines in 21 files (`grep -rnE 'Permission::|Quantity::|Lifetime::'`);
`QType` named in 2 C++ places outside the type files. The grade is
encapsulated: its algebra is the free functions of `Grades.h`.

Body reads (`grep -rnoE '\.(getCtors|getCtor|isMemo|isClosures|isAtom|getTags|getRunningTag|getForcedTag|getConsTag|getNilTag|getListElement)\('`,
`Types.cpp` and `DataBody.cpp` excluded): 147 in 57 files, among them two
ODS type constraints (`IdrBase.td:339-342`, `IdrClosureOps.td:169`) and
the verifiers of `CellType` (`OpsOwnership.cpp:63-75`) and `ConAttr`
(`ConAttr.cpp:104-131, 211-231`), none of which has an op in hand. `isMemo()`
18 readers, `isClosures()` 11, `std::get_if<role::Label>` 18.

### 2.6 Threading (read)

A sealed data type is read by every thread with no lock
(`IdrTypes.td:36-38`, `Types.cpp:37-44`); sealing takes one uniquer shard's
writer lock per member (`StorageUniquer.cpp:195-206`, §5.2 D2). `TypeGraph`
and `Layouts` are immutable once built and passes read them from the
`AnalysisManager` (`TypeGraph.h:5-9`, `Layout.h:244-252`), but the program
verifier and `layout::fit` build their own (`Program.cpp:104, 266`,
`Fit.cpp:25`). The function verifiers run in parallel and keep nothing
beyond one verify (`Verify.h:10-14`). Type queries in verifiers create or
look up types (`view`, `atQuantity`, `atPermission` inside `TypesMatchWith`,
`IdrOwnershipOps.td:101-102, 359-360, 375-376, 406-407, 418-419`): a
thread-local cache hit, a shard reader lock on a miss (§5.1 F3).

## 3. Reconciliation with the proposal

### 3.1 Wave-1 findings, against our code

| finding | verdict | evidence |
| --- | --- | --- |
| §5.1 F3, §5.2 D2: a mutable type's reads take no lock; its mutation takes a shard's writer lock | **holds** | Since 98c6315c a data type's facts are fields written once at sealing and read with no lock (`Types.cpp:57-79, 122-168`, `ValueFacts.cpp:282-289`); types are made only by program passes (`Declarations` users: `Defunctionalize/Declare.cpp`, `Tail/Frames.cpp`, `Tail/FramesTypes.cpp`, and `DataRemap` in deduplicate, fit, bufferize: all `program.addPass`, `Pipeline.cpp`). |
| §5.2 M10: the 98c6315c lock was a uniquing or mutating call on a read path | **holds** | 98c6315c's message: "every holdsReferences and holdsWorld of a data type read its facts through the uniquer's mutate", a lazy fixpoint kept on first question. The read path no longer mutates. |
| §5.2 M10, §5.7 L3: a table in an immutable attribute is rebuilt on every change (73bba53f) | **holds in part** | 73bba53f batched declarations; the table is still remade whole once per `Declarations` end and per remap (`DataBody.cpp:315-335`, `Types.cpp:268`), each version a new uniqued attribute of n members that the context never frees, and in an assertions build every `get` re-verifies the whole table (`DataBody.cpp:266-298`, `StorageUniquerSupport.h:176-182`; 73bba53f: "the dev build verifies every member of each remake"). |
| §5.2 H2: a type's verify runs once per unique instance | **refuted in part** | At the pin `getChecked` runs `verifyInvariants` on every call and `get` runs it on every call in an assertions build (`StorageUniquerSupport.h:176-182, 203-210`); a release `get` never runs it. So `QType::verify` (`Types.cpp:331-352`) runs at every `graded()` (`Grades.cpp:28-33`) in a dev build, and at every parse and bytecode read in any build (`Types.cpp:298`, `IdrBytecode.td:40`). "Free after creation" holds only for release `get`. |
| §5.2 H3, M11: a module pass re-verifies all 70,000 functions | **holds, and worse** | Beyond the recursive verify after a program pass, the non-recursive verify after every function adaptor (`Pass.cpp:621-642`) still runs `ProgramOp::verify` and `verifyRegions` (`Verifier.cpp:355-381`), whose walks cover every function on one thread (`Func.cpp:73-85`, `Program.cpp:61-72, 99-118, 266`). |
| §5.2 H5: symbol checks in `verify()` are linear scans | **holds, once per verify** | `ProgramOp::verifyRegions` finds the root by `SymbolTable::lookupSymbolIn` (`Func.cpp:106`), a scan of the program's block (`SymbolTable.cpp:364-376`): O(F) per verify, not per op. |
| §5.2 M9: grades as `EnumParameter`s with `genVerifyDecl`, spellings as builders and aliases, use checks as traits | **holds in part** | Parameters and `genVerifyDecl` are used (`IdrTypes.td:286-291`); the spellings are a hand table around the generated printer, not aliases or a generated list (`Types.cpp:280-319`, `IdrBase.td:34`); the use checks are whole-function walks that follow def-use chains (`Linearity.cpp:73-89`, `Uses.cpp:82-127`, `Owned.cpp:136-162`), which no op-local `verifyTrait` can express (§5.8 B10). |
| §5.2 M14, row 21: our types and attributes go into bytecode as text unless encoded | **holds** | Records exist for `q`, `fn`, `lazy`, `box`, `dest` and the table (`IdrBytecode.td:38-68`); `cell`, `token`, `str`, `big`, `nat`, `world`, `#idr.con`, `#idr.big`, `#idr.closure`, `#idr.instance`, the keys, `#idr.refusal` and `#idr.world` go as text (the C++ fallback `Bytecode.cpp:44-60`; the frontend's `AsText`, `compiler/src/IdrisMLIR/MLIR/Bytecode.idr:404`). The data type's text is its name only (`DataBody.cpp:119-123`), so its "mutable type as text" cost is bounded. |
| §5.3 S0: grades in types make a solve unnecessary | **holds in part** | The frontend writes quantity only (`Emit/Index.idr:58-59`); permission and lifetime are written by idr-rc after solves (lanes 07, 08). Quantity is read off the type by the linearity verifier and by `consumes()` (`IdrDialect.h:101-108`); exclusivity, once written, is read off the type (`isExclusive`, 16 call sites). |
| §5.4 Design 5, 5.4.2.7: facts many threads read live in immutable attributes, never a mutable type | **holds in part** | The facts live in a type that is mutated once and immutable after (`Types.cpp:57-79`); no thread reads it before sealing. Design 5's goal (98c6315c unrepresentable) is met by sealing; its means (no mutable type) is not. |
| §5.6 D6, 5.6.2.1: the type holds the answer's own bits; a solver's domain is the values whose type leaves the question open | **holds** | Our grade holds its bits directly (no lossy mapping): quantity, permission, lifetime (`Grades.h:39-48`); the filter "does this value need counting" is the type's own answer, `isCounted` (`IdrInterfaces.td:48-53`). |
| §5.6 Design 2: the filter is a type interface method (ValueFacts the candidate) | **holds** | `ValueFactsTypeInterface` already is that interface; its 55 answers are hand-written per type (`ValueFacts.cpp:129-199`), issue T41. |
| §5.7 M6: the context-lock wall and the table rebuild are a mutable nominal type read while it may change | **refuted in part** | Since 98c6315c no type is read while it may change: a reader meets only sealed types, and `ProgramOp::verify` refuses a name alone (`Func.cpp:62-89`). The nominal identity remains (DataRemap's content names). |
| §5.8 T1-T3: the grade in the type; the bare type for the unrestricted grade | **holds** | `graded` and `QType::verify` (`Grades.cpp:28-33`, `Types.cpp:334-335`). |
| §5.8 T2, DS1.1: one grade attribute with an interface verifiers ask | **not yet**: the algebra is in one place, as free functions | `Grades.h:56-128` holds the whole algebra (owned, view, atQuantity, exclusive, shared, forgets, fitsIn, joined, times); ODS constraints call it through `CPred` (`IdrTypes.td:308, 341`; `IdrOwnershipOps.td:42-56, 137-139, 175-180`). There is no grade attribute, so no op or table can hold a grade as a value. |
| §5.8 T4: only some (quantity, permission) pairs are meaningful, so one enum of legal grades | **refuted in part** | Six pairs occur in fixtures and a seventh is constructible (2.2): quantity is Idris's, permission counting's, and `(one, own)`, `(one, excl)`, `(many, borrow)` are all legal (`fieldType`, `Grades.cpp:253-260`; `view`, `:85-91`). The illegal states are carrier-relative (`Types.cpp:341-350`) and stage-relative (`Program.cpp:222-228`), not a product of the two halves. The limit (Brooks) applies: the halves are two facts. |
| §5.8 T5: the fourth parameter of `!idr.q` | **it is not a borrow lifetime** | `Lifetime` is locality, heap or frame, for stack cells (`IdrBase.td:96-108`, `Lifetimes.h:3-28`), OxCaml's locality mode (§5.10 G4); a borrow is `Permission::Borrow` with no scope in its type, its owner recovered per verify by walking definitions (`Uses.cpp:93-127`, `Owned.cpp:136-162`). |
| §5.8 T7: cache recursive properties in the type's storage | **holds for data types, not for the rest** | `Held` (references, world) is solved at sealing (`ValueFacts.cpp:210-280`); "names a closure or suspension" (`Program.cpp:43-51`), "holds no component" (`Components.cpp:103-135`), "reaches only atoms" (`Uses.cpp:137-153`) are recomputed per query. |
| §5.8 B9, DS3.1: a body on an ancestor op is readable from a function pass; a table on the program with types naming an entry by index | **holds for passes, refuted for type-level readers** | 147 body reads in 57 files (2.5) include ODS type constraints and type and attribute verifiers that have no op in hand (`IdrBase.td:339-342`, `IdrClosureOps.td:169`, `OpsOwnership.cpp:63-75`, `ConAttr.cpp:104-131`): under DS3.1 none of them can read a body. |
| §5.8 B10: verifiers are local and do not follow def-use chains | **refuted by our code** | `linearity`, `owned`, `stageRules` follow uses and definitions (`Linearity.cpp:73-89`, `Uses.cpp:82-127`, `Program.cpp:148-177`). |
| §5.9 M6, Design 3: an immutable type naming a tycon, bodies in one immutable table op | **holds in part** | Bodies are in one table (b9d4d592) and types are immutable once sealed; the type is a mutable storage sealed once, not a reference into the table. |
| §5.9 G2.7: facts written into types by the pass that proves them | **holds for grades and cells** | Quantity (frontend), permission, lifetime (idr-rc), a cell's constructor and lifetime (`IdrOwnershipOps.td:166-167`), naturals' non-negativity (`IdrTypes.td:238-249`); **not** for the static lifetime (0003, `Uses.cpp:82-84`), a token's cell (`IdrOwnershipOps.td:33-36`, `Program.cpp:106`), a constant's atoms-only reach (`Uses.cpp:165-168`). |
| §5.10 M3: grades are OSSA's ownership kinds, consuming traits its lifetime-ending bit; the verifier should be OSSA's rule, a linear walk | **holds in part** | `OwnedWalk` is OSSA's rule (`Verify.h:74-77`, `Owned.cpp:3-17`); "consumes" is re-derived from flow edges in C++ (`useOf`, `Uses.cpp:26-28`; `consumes`, `IdrDialect.h:101-108`), not read from declared `MemFree` effects; the walk keeps per-value maps and walks owners per use (`Owned.cpp:136-162`): linear per function in values only if owner chains are short. |
| §5.10 R1.1: signatures in types | **holds** | Parameter and result grades are the `function_type` of `idr.func` (`IdrOps.td:158`), read from the callee's signature by `consumes` (`IdrDialect.h:101-108`). |
| §5.11 C2: transient scopes free uniqued storage | **unused** | No use in `foreign/idr` (`grep -rn TransientScope`). |

### 3.2 Wave-2 questions in this subsystem, answered

- **§5.1 W5** (attributes or types created on a hot path), *read*:
  (a) `op->getAttrDictionary()` on every op of the program, twice or three
  times per verify (`Func.cpp:74`, `TypeGraph.cpp:80` via `Program.cpp:266`
  and `Layouts.cpp:67`): at the pin it builds a `NamedAttrList` and uniques
  a `DictionaryAttr` for any op with properties (`Operation.cpp:292-299`),
  which every op with an inherent attribute has (§5.2 D3); serial, after every pass
  and adaptor. (b) `ConAttr::getField(spine)` and `getFields()` on a run
  build a new uniqued `#idr.con` per call (`ConAttr.cpp:188-206`).
  (c) Every grade function builds its result with `QType::get`
  (`Grades.cpp:28-33`), including inside verifiers' `TypesMatchWith`
  (`IdrOwnershipOps.td:101-102, 359-360, 375-376, 406-407, 418-419`).
  (d) `DataTableAttr::with` per `Declarations` (`DataBody.cpp:327-335`).
  (e) `Layouts::sizeOf`/`alignmentOf` construct a `DataLayout` per miss
  (`Layouts.cpp:118-128`). The keys of specialization (`IdrAttrs.td:221-256`)
  are lane 09's.
- **§5.1 W3** (per-region interface queries), *read*: `isRepetitiveRegion`
  per terminator that forwards a frame value (`Lifetimes.cpp:50-55`) and
  per region op with a linear use whose regions are not alternatives
  (`Linearity.cpp:126`); `alternatives()` asks `getSuccessorRegions` of
  every region (`Linearity.cpp:27-33`) and is recomputed at each `count`
  of each linear value (`Linearity.cpp:121-122`): O(N) per linear value per
  match of N cases.
- **§5.2 W3** (hand `verify`), *read*: the type and attribute verifiers
  `QType::verify`, `CellType::verify`, `ConAttr::verify`, `BigAttr::verify`,
  `DataTableAttr::verify` are genVerifyDecl bodies, the right mechanism
  (§5.2 row 15); the region verifiers `verify::program` and
  `verify::function` hold everything else (2.3), including one symbol
  lookup (`Func.cpp:106`) and two whole-program walks of ours per verify
  (`Func.cpp:73-85`, `Program.cpp:266`).
- **§5.2 W6**: the call was `mutate`, on the read path (98c6315c). The body
  is complete before threads read it: sealed by a program pass, every
  accessor asserts `isDefined` (`Types.cpp:124-149`), and a name alone is
  refused before any op is verified (`Func.cpp:62-89`).
- **§5.2 W7**: no built compiler in this checkout; the structure that a
  measurement would time is 2.3. Lane 13 owns the measurement.
- **§5.2 W8**: yes: the frontend writes bytecode (08647d2e) and the driver
  reads it; see 3.1, row M14.
- **§5.2 W10**: the type interfaces' methods have no bodies; every type
  declares them (`IdrTypes.td:18`), so 12 models with 5 methods each; the
  builtin models are two templates (`ValueFacts.cpp:26-46`).
- **§5.3** (switches on our enums in more than one place; variants), *read*:
  one switch each over `Permission` (`Grades.cpp:56`), `Quantity`
  (`:144`), `SumKind` (`DataBody.cpp:38-53`), `CmpPredicate`
  (`Layouts.cpp:235-249`), `Escape` (`Lifetimes.cpp:21-35`); none repeated.
  Variants: `Role` (`IdrDialect.h:164`), `Source` (`Grades.h:173`), `Edge`
  (`Lifetimes.h:86`), `DescriptorField` (`Layout.h:192`), `Slot`
  (`Verify.h:125`); `get_if` chains on `Role` in 18 sites across lanes,
  on `Source` in 5, on `FlowPoint` in 6 of this lane's.
- **§5.4** ("every fact read from the mutable `!idr.data` by many
  threads"; "whether release builds verify after every pass"): kind,
  constructors, tags, roles, `Held` and instance, each a field written at
  sealing (`Types.cpp:84-96`); and yes, every build verifies after every
  pass (2.3).
- **§5.6 W-E2** (type side): the type answers "counted?" (`isCounted`),
  "exclusive?" (`excl`), "used once?" (`quantityOf`); a value whose type
  is not counted needs no ownership state. The counts at stage 1 need a
  build.
- **§5.6 W-E4**: one discardable attribute, `idr.refusals` on the module,
  a report to the driver that no pass reads (`IdrBase.td:68-70`,
  `Verify/Attributes.cpp:20-32`); every other `idr.*` attribute on an op or
  an argument is refused (`Attributes.cpp:20-39`).
- **§5.7** ("where a parallel pass reads a mutable type or anything under
  the context's lock; where a program table is rebuilt"): no read under a
  lock since 98c6315c; the table is rebuilt per `Declarations` and per
  remap, and `TypeGraph` and `Layouts` per program verify (3.1).
- **§5.8 wave 2**:
  *Pairs and readers*: 2.2 and 2.5. *What `!idr.token` is*: a
  parameterless type, "the memory of a cell whose fields idr.take moved
  out, or null" (`IdrOwnershipOps.td:33-36`), always owned (`:137-139`);
  the program verifier requires a recycle's token to be a take's result
  (`Program.cpp:106-108`), so it behaves as a "came from that op" link, but
  the builtin `token` takes no parameters, and 0003 asks for
  `!idr.token<!idr.box<T>, @C>`. *How the grade verifier runs*: region
  verifiers, following def-use chains, cost structure 2.3. *How `data`'s
  mutability is used*: sealed once per group, 3.1.
- **§5.9 Q-W7**: not one linear walk: per function four or five walks with
  per-value chain walks inside them (`Uses.cpp:82-84`, `Program.cpp:43-51`,
  `Owned.cpp:136-162`), and the program's serial walks (2.3); the cost
  needs a build.
- **§5.10 W3** (type side): parameter grades are in function types
  (3.1, R1.1). **W5**: OSSA's rule, re-deriving consumption from flow
  edges in C++ (3.1, M3).
- **§5.10 W7** (type side of the ownership ops), *read*: `idr.share` is
  uniqueness logic's one-way forgetting in the type algebra (`excl` to
  `own`, `shared`, `Grades.cpp:109-111`), and may raise heap to frame
  (`forgets`, `:113-116`); `idr.lin.enter` and `idr.lin.use` change only the
  quantity (`atQuantity`, `IdrOwnershipOps.td:406-407, 418-419`) and are
  chosen between by `heldAs` (`Grades.cpp:262-268`): one regrade in two
  ops; `idr.own.adopt` (plain memref to owned, `owned()`) and `idr.own.give`
  (owned to plain, quantity kept, `atPermission(Plain)`) are inverse
  permission changes on different carriers (`IdrOwnershipOps.td:359-360,
  375-376`). Lane 03 owns the ops.
- **§5.6 W-E7** (per-function state a dense number would replace), *read*:
  the owned walk's `DenseMap<Value, Role>`, `DenseMap<Value, Slot>`,
  `DenseMap<Value, unsigned>` (`Verify.h:202-211`) and linearity's
  `DenseMap<Operation *, unsigned>` (`Linearity.cpp:64`): each keyed by a
  value or op of one function, per verify (T67, T70).
- **§5.11 W8**: 3.2, §5.1 W5 above; no phase runs under a transient scope.

## 4. Issues

Categories as in `audits/p0/README.md`. "Lane NN" names the lane whose
document owns the disposition where this lane only reports the type side.
All entries *read* unless marked.

### 4.1 ODS: types, attributes, enums, constraints

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| T01 | `IdrTypes.td:283-305`, `IdrBase.td:83-108`, `Grades.h:39-48` | state | The grade is three independent enum parameters, 16 combinations per carrier; `QType::verify` refuses three grade-only combinations and the rest by carrier (`Types.cpp:331-352`). No grade is a value of its own: no property or table can hold one. | §5 C1: one `#idr.grade` attribute parameter, its grade-only rules in its own verifier (once per grade), carrier rules in `QType::verify`. |
| T02 | `Types.cpp:280-319`, `IdrBase.td:34` | list | The spellings `lin`/`own`/`excl` are a C++ table around the generated printer (`useDefaultTypePrinterParser = 0`); `(many, borrow)`, the second most common grade (349 occurrences, 2.2), has none. The Idris side spells grades from the generated enums only. | Spellings as ODS records (one per named grade), read by the C++ printer and parser and by idris-mlir-tblgen (lane 14); add `borrow`. |
| T03 | `IdrTypes.td:278-281` | dead | `class Idr_LifetimeParam` used once, by `def Idr_LifetimeParameter`. | Fold into one def (or into the grade attribute, C1). |
| T04 | `IdrTypes.td:253, 311`, `IdrArrayOps.td:251-254` | dead | `Idr_BigOrNat`, `Idr_SumType`, `Idr_ArrayType`: no op, tool or Idris file uses them (*measured*: `grep -rnw` over `include/idr/IR/*.td`, `tools/`, `compiler/`, `tests/`). | Delete; `Grades.h:238`'s comment names `isArray` instead. |
| T05 | `IdrTypes.td:48-165`, `Types.cpp:45-97, 199-225` | upstream / state | `!idr.data` is a `MutableType` sealed once per group (98c6315c); storage lives for the context; sealing takes a shard writer lock per member; mutation is unsupported in a transient scope (§5.2 D2). Nominal identity makes every body change a new type with a content name (`Symbols.h:139-236`). | Owner's DS3 choice (Q-O3, §6). Evidence: DS3.1 breaks 147 type-level body reads (2.5); DS3.2 is what we have; DS3.3 unmeasured. |
| T06 | `IdrTypes.td:63-67, 94-100`, `Types.cpp:94, 161-166`, `DataBody.cpp:29-108` | state / ladder | A body is `{kind, ctors, instance}` with a `Role` per constructor; the legal (kind, role) pairs are a hand table (`KindRule`, `RoleOnce`, `ruleOf`) checked at sealing; `getRunningTag`/`getForcedTag`/`getNilTag`/`getConsTag` assert a precondition "asked of a sum of another kind, it is the caller's error". (0003, "A data type's body holds a kind beside its constructors' roles".) | §5 C4: the body as one alternative per kind, typed views (`list()`, `closures()`, `memo()`); delete `KindRule`, `RoleOnce`, `ruleOf`, `roleTags`, the role asserts. |
| T07 | `IdrTypes.td:88-89` | ladder | `isMemo()` (18 readers) and `isClosures()` (11) are tests of the kind tag across passes (*measured*, `grep -rnF`). | Typed views (C4): `if (auto memo = data.memo())` binds the memo body. |
| T08 | `IdrBase.td:121-127`, `Demand.cpp:56` | state | `SumKind::InPlace` is read by one pass (Demand) and has the same rules as `Plain` (`DataBody.cpp:40-42`): a property of a plain sum spelled as a kind. | Ask lanes 08/11 whether in-place-ness is a kind (its own body alternative) or a fact of the registry; either way one place (C4). |
| T09 | `IdrDialect.h:152-177`; 18 `std::get_if<role::Label>` sites (*measured*, e.g. `Captures.cpp:17`, `Inline.cpp:106`, `Forces.cpp:62`, `Keys.cpp:119`, `Converter.cpp:54`) | cpp | A `Role` variant read by `get_if` chains, and two `std::get<role::Label>` that abort on the wrong alternative (`Converter.cpp:54`, `Patterns.cpp:128`). | C4: a label exists only in a closure or memo body, read as `Label{fn, byName}` by tag; no `get_if` outside one match. |
| T10 | `IdrBytecode.td:57-60`, `IdrDialect.h:198-219`, `Bytecode.cpp:107-121` | state | Bytecode's `TableCtor` is a product (role, label, by_name) where label and by_name are "none and 0 for every other role", re-checked by the reader: a flag product where a sum belongs (BytecodeBase has no sum composite). | C4: the row follows the body's kind (labels a list of their own, present only for closure and memo kinds); the reader builds the alternative by kind once. |
| T11 | `IdrBytecode.td:38-68` | upstream | 5 of 12 types and 1 of 11 attributes have records; `#idr.con`, `#idr.big`, `#idr.closure`, `#idr.instance`, `#idr.refusal`, `#idr.world`, the keys, `!idr.cell`, `!idr.token`, `!idr.str`, `!idr.big`, `!idr.nat`, `!idr.world` go as text, parsed back by the text parser on the 75 MB handoff (08647d2e). | C8: records for every non-mutable type and attribute (row 21); the data type stays its name. Measure the text share first (§8). |
| T12 | `IdrOwnershipOps.td:33-36`, `Program.cpp:106-108`, `Demand.cpp:66`, `ReusesEveryCell.cpp:21`, `Conversion/Fields.cpp:37` | rederivation | `!idr.token` names no cell, so four readers walk back to the `idr.take`, and the program verifier refuses a token through a block argument: a representation limit acting as a refusal (0003). | C3: `!idr.token<!idr.box<T>, @C>`, inferred by `TakeOp`; delete the walks and the refusal. |
| T13 | `IdrOwnershipOps.td:158-170`, `OpsOwnership.cpp:32-60` | ods | `!idr.cell` has a hand parser and printer whose only custom part is the constructor by name, which `custom<CtorRef>` already reads for ops (`Symbols.h:52-54`). | A declarative `assemblyFormat` with `custom<CtorRef>(ref($box), $tag)` and an optional lifetime. |
| T14 | `IdrOwnershipOps.td:175-180`, `:192, 210-211, 231` | rederivation | `Idr_HeapCell`/`Idr_FrameCell` tie a cell type's lifetime parameter to the op that makes it, beside the op's `MemAlloc` resource (`DefaultResource` or `AutomaticAllocationScopeResource`): one fact (heap or frame) said twice per op. | §5.8 O2: one `Idr_CellAllocOp<mnemonic, Resource, Lifetime>` class whose parameter sets both (lane 03 owns the ops). |
| T15 | `IdrOwnershipOps.td:42-56, 137-139`, `IdrTypes.td:308-309, 323-342` | ods | The grade's type constraints are `CPred`s calling the grade functions (`isOwned`, `isLinear`, `gradeOf(...).permission`, `unrestricted`); the grade's questions are asked through C++ strings in ODS. | C1: constraints over the grade attribute (`Idr_GradeIs<"isOwned">`-style predicates on the attribute's methods), generated once. |
| T16 | `IdrBase.td:339-342`, `IdrClosureOps.td:169` | ods | `Idr_BaseListOf` and `Idr_MemoCell` read the body's kind through `dataTypeOf($_self).getKind()` / `.isMemo()`. | C4 views (`list()`, `memo()`); stays a type-level read, which DS3.1 would forbid (T05). |
| T17 | `IdrAttrs.td:200-209`, `IdrOps.td:143-152, 162-163`, `Func.cpp:250-256` | rederivation (lane 02) | `Idr_Effect {io, crash, diverge}` is a bit enum on `idr.func` and `idr.call`, and a table maps each bit to MLIR effect instances: two representations of what a call may do. | Lane 02 (one effects model); evidence for Q-E2 and DD-Q7 (§6). |
| T18 | `IdrAttrs.td:295-300`, `Types.cpp:60-61, 88` | attribute (keep) | A data type's `#idr.instance` takes part in body equality but no pass reads it (`IdrAttrs.td:267-268`; readers: printing, bytecode, `DataRemap.cpp:304`). | Keep (0003 §1: information for humans, low risk); it stays in the body sum (C4). |
| T19 | `IdrBase.td:68-70`, `Verify/Attributes.cpp:20-39` | attribute (keep) | The one discardable attribute, `idr.refusals`, is the frontend's report; every other `idr.*` attribute is refused. | Keep: this makes discardable facts unrepresentable (W-E4). |
| T20 | `IdrAttrs.td:221-256`, `Consumer.cpp:173` | state (lane 09) | Specialization keys are uniqued attributes created per request, kept in the context for good; `KeyRaiseAttr` has one constructor site (`Consumer.cpp:173`) and is one alternative of the specializer's `Key` variant (`Specialize.h:62`). | Lane 09; candidates for a pass-local interned table instead of context attributes (§5.11 C2). |
| T21 | `IdrBase.td:162-238` | list (keep) | Rules with categories as ODS records read by C++ and Idris (`Attrs.cpp:9-12`). | Keep: the generated-table form §5.3 I8 asks for. |
| T22 | `IdrTypes.td:316-319` | ods (keep) | `Idr_SInt` and `Idr_UInt` are the same type set with two ABI words for idris-mlir-tblgen. | Keep while ops take a signedness (DD-Q4); one record each. |

### 4.2 C++: the types and the table

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| T23 | `Types.cpp:227-266`, `Symbols.h:101-137` | state | `Declarations::define` keeps a nesting counter and pending copies of every body's fields until the outermost define returns, then seals the group and, at destruction, remakes the program's table (`Types.cpp:268`). | Keep the group seal (essential: a group's bodies hold one another); with C4 the pending copies become the body alternatives themselves. |
| T24 | `DataBody.cpp:327-335, 315-325`, `Func.cpp:47` | rederivation | The table is remade whole (sort, unique, re-unique) once per `Declarations` end and per remap; each version stays in the context. | Measure the count of versions per pipeline; if material, the table becomes an op holding members as properties or a symbol-table-like op (§5.2 D3), else keep. |
| T25 | `DataBody.cpp:266-298` | rederivation | `DataTableAttr::verify` walks every member's fields at every `get` of the table in an assertions build and at every `getChecked` (`StorageUniquerSupport.h:176-182`). | Keep the closure rule; check it once per table made (in `with`/`replaced` over the added members only). |
| T26 | `Types.cpp:170-195` | essential | `replaceLabels` aborts if a label is renamed in place: upstream's symbol rename walks into types. | Keep (essential while labels are symbol uses inside a type); comment states why. |
| T27 | `DataRemap.cpp:30-85` (`describe`), QType case `:43-48` | list / bug | A hand `TypeSwitch` restates every type's syntax for content keys; its `QType` case drops the lifetime, so two shapes that differ only in a field's lifetime get one key. Latent: no remap runs after idr-rc-stack today (remaps: deduplicate, defunctionalize, fit, bufferize; `Pipeline.cpp`). Since b9d4d592 MLIR's printer writes a data type as its name, the same short key. | C9: delete `describe`; the key is the shape's canonical printing (`canonicalText`, `Symbols.h:262-264`). |
| T28 | `ValueFacts.cpp:129-199`, `OpsOwnership.cpp:79-83` | list / ods | 55 one-line answers of `ValueFactsTypeInterface` for the dialect's types, constants per type except data types and grades. | C6: per-type ODS fields generate the answers; the Idris side reads the same fields. |
| T29 | `ValueFacts.cpp:83-99` | list | External models attached to 13 builtin types, among them types no value of ours may have by `isFieldType` (`Grades.cpp:300-309`): f16, bf16, f80, f128, unranked memref and tensor. | Derive the attached set and `isFieldType` from one list (C6); attach what a value may have. |
| T30 | `ValueFacts.cpp:210-280` | upstream / cpp | `solveHeld` runs the hand SCC utility (`idr::components`, `Support/Scc.h`) twice per group and recurses through a `std::function`. | `llvm::scc_iterator` over a `GraphTraits` of the group (lane 05 owns `Scc.cpp`); a recursive lambda with deducing `this` (§5.5 D5). |
| T31 | `Grades.cpp:300-327` | list / ods | `isFieldType`, `isArray`, `isValueArray`, `isElementType`: hand predicates over builtin types, with the integer widths `{8, 16, 32, 64}` written in C++ (`:305`). | A classification of types (§5.8 B7): a method of the value-facts interface (`isField`) with the builtin models (C6). |
| T32 | `ConAttr.cpp:188-206` | state (W5) | `getField(spine)` and `getFields()` on a run build and unique a new `#idr.con` per call. | C11: a run view that reads the cells; no attribute made on a read. |
| T33 | `TypeLiterals.cpp:54-65` | keep | Printer names per type (`getAsmName`), a grade taking its carrier's. | Keep (§5.2 G2 row 20). |

### 4.3 C++: grades, sources and the frame

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| T34 | `Grades.cpp:21-157`, `Grades.h:56-128` | ods | The grade's algebra as free functions over `mlir::Type`, each rebuilding a `QType` with `get` (a uniquer lookup; verify in assertions builds). Encapsulated: 47 direct enum uses in 21 files outside it (*measured*). | C1: methods of the grade attribute; the type functions become thin wrappers `graded(type, grade.f())`. |
| T35 | `Grades.cpp:137-141` | cpp | `fitsIn` and `joined` spell the lifetime order by hand (heap below frame); 0003 owes `static` below heap. | C2: the enum's values in the lifetime order; `fitsIn` is `<=`, `joined` is `max`. |
| T36 | `Grades.cpp:143-151` | cpp | `times` is a switch over `Quantity`; with `One < Many` it is `max`. | C1/C2: the coordinate; delete the switch. |
| T37 | `Grades.cpp:55-65` | list | `holdsOwn`: a switch saying which permissions hold a reference. | An ODS field per permission case (C1). |
| T38 | `Grades.cpp:80-91`, `Program.cpp:222-228` | state | `Permission::Plain` means "nothing decided" before idr-rc and "holds no reference" after; which one is read from the program's stage. | New owner question NQ3 (§6): split the two meanings or keep them stage-relative. |
| T39 | `Grades.cpp:118-122` | ladder | `lifetimeOf` asks `dyn_cast<CellType>` first: the lifetime lives in two parameters (the grade's and the cell's). | C1: a cell's lifetime is the grade attribute's locality half (`!idr.cell<..., #grade>`) or stays a cell parameter, read through one accessor. |
| T40 | `Grades.cpp:164-190` | rederivation | `linearPositions`/`throughLinear` walk up `lin.enter`/`lin.use` chains per query (14 callers). Essential in part: RC identity follows a value through regrades (§5.10 C2). | One forwarding interface (lane 02, §5.8 O3) answers it per op; `definitionChain` stays the one walk. |
| T41 | `Grades.h:164-174`, `Grades.cpp:197-218`; get_if at `Grades.cpp:225`, `Uses.cpp:41, 95, 119`, `Owned.cpp:177` | ladder / cpp | `sourceOf` dispatches on `hasTrait<SameValue>`, `dyn_cast<FieldOp>`, `MatchOpInterface`, and its `Source` variant is read by `get_if` chains. | The forwarding interface (lane 02) answers `sourceOf` per op; one exhaustive match over `Source` (§5.5 D2). |
| T42 | `Grades.cpp:233-251` | ladder | `fieldReadOnce` names `FieldOp` and `ResultCarriesOperand`. | Lanes 04/07; the forwarding interface. |
| T43 | `Grades.cpp:262-268` | ods (lane 03) | `heldAs` picks `LinEnterOp` or `LinUseOp` by quantity: two ops that are one regrade with a computed result type (§5.8 DS4, O3). | Evidence for one regrade op (lane 03). |
| T44 | `Lifetimes.cpp:50-55` | upstream | `endsRepeatedRun` calls `isRepetitiveRegion` per terminator that forwards a frame value: O(N) per call (§5.1 C2), O(N^2) over a match of N frame-yielding cases. | Ask once per region op (`verify::alternatives`, cached), or the match overrides `isRepetitiveRegion` (lane 03, §5.1 C4). |
| T45 | `Lifetimes.cpp:59-66` | rederivation (lane 10) | `loopsInFrame` re-asks `isSelfCall` and tail position per op with a frame operand. | Lane 10: tail position as a fact of the call (a property written by the tail pass). |
| T46 | `Lifetimes.cpp:68-129` | ladder | `edgesOf` reads flow edges by `get_if<Flow>`, `get_if<Parameter>`, `holds_alternative<Result>`, `holds_alternative<Part>`, and names `CallOp` and `CellInitOp`. | One match over `FlowPoint` (lane 02 owns the flow types); `Fills`/`Passes` from the flow interface's target kinds. |
| T47 | `Lifetimes.h:92-93` | cpp | `edgesOf` takes a `function_ref` called per edge inside the verifier. | A template callable (§5.3 I5) or a returned range. |

### 4.4 C++: the type graph and layouts

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| T48 | `TypeGraph.cpp:57-111` | rederivation / state (W5) | Built by walking every op, its `getAttrDictionary()` (a uniqued dictionary per op with properties, `Operation.cpp:292-299`), result and block-argument types; then the bodies. | C10: built from the table's members alone (knots and self-containment need only bodies); per-value "held in place" facts move to the function verifier (C7). |
| T49 | `Program.cpp:266`, `Layouts.cpp:67`, `Fit.cpp:25`, `Defunctionalize/Pass.cpp:152` | rederivation | `TypeGraph` built outside the `AnalysisManager` four times, two of them per program verify (0003, "Analyses dropped and rebuilt"). | C10: only through `getAnalysis`; never in a verifier. |
| T50 | `TypeGraph.cpp:110, 185`, `Components.cpp:166-167` | upstream (lane 05) | The hand SCC utility, three uses. | `scc_iterator` over `GraphTraits` (lane 05). |
| T51 | `TypeGraph.h:77-86` | state | Adjacency as a `SmallVector` per node, a `DenseMap<Type, unsigned>` index, two `DenseSet`s. | The solver layer's CSR graph if lane 05 adopts one (§5.3 S1); small at the table's size (6,988 types at stage 1's defunctionalization, 73bba53f). |
| T52 | `Layouts.cpp:41-104` | rederivation | `Layouts` builds its own `TypeGraph` and lays out only data types some value holds boxed (`graph.boxed`), so it needs the value walk. | C10: lay out every member of the table (its box cells and its sum), a pure function of the body and the target; no value walk. |
| T53 | `Layouts.cpp:118-128` | state (W5) | A miss in `measures` builds a `DataLayout` (`DataLayout::closest`) per query. | Measure every component at construction (already the intent, `Layouts.cpp:56-58`); make a miss unreachable by construction. |
| T54 | `Components.cpp:103-135, 181` | rederivation / state | `holdsNoComponent` recurses with a fresh `DenseSet` per query, at every `components()` call. | C5: a `Held::NoComponent` bit solved at sealing; constant answers for the other types. |
| T55 | `Components.cpp:180-202` | ladder | `components` dispatches with `isa<RankedTensorType, MemRefType>`, `isa<BigType, NatType>`, `isa<DestType, CellType>`. | A value-facts method (`runtimeShape`) per type (C6), or one exhaustive `TypeSwitch` with `DefaultUnreachable` (§5.3 I2). |
| T56 | `Layouts.cpp:235-249` | list (lane 12) | `signedPredicate` maps `CmpPredicate` to `arith` predicates by hand. | An ODS field per case (lane 12). |
| T57 | `Layout.h:186-214`, `Components.cpp:124-127` | cpp | `DescriptorField = std::variant<Fixed, Carried>` read by `holds_alternative`. | `std::optional<int64_t>` named, or one match (§5.5 D2). Minor. |
| T58 | `Fit.cpp:24-38` | rederivation | Boxes are decided after the frontend, by a whole-program `DataRemap` (the frontend emits every type in place). | NQ2 (§6): the frontend emits the boxes, the table refuses an in-place cycle once, `fit` and its remap go. |

### 4.5 The verifier

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| T59 | `Func.cpp:56-90` | rederivation / state (W5) | `ProgramOp::verify` walks every op of the program, `getAttrDictionary()` per op, at every verify, to refuse a data type the table does not declare: a name alone is representable. | C7(a): refuse a name the table has not sealed at the parser and the bytecode reader (the boundary); delete the walk. |
| T60 | `Program.cpp:61-72`, `Func.cpp:189-202` | rederivation | `effectsCovered`: two walks of every function, serial, per verify. | C7(a): in `FuncOp::verifyRegions`, per function, in parallel; a call covering its callee is the call's symbol-use check (lane 03). |
| T61 | `Program.cpp:99-118` | rederivation | `recycles`: a walk for every recycle and a whole `Layouts` (a third `TypeGraph`) per verify in the owned stage. | C3 + C7: typed token; the size rule per function, or in the pass that pairs cells (lanes 07, 08). |
| T62 | `Program.cpp:266-294` | rederivation | Memo-held-in-place, labels-in-bodies and self-containment rules recomputed per verify from a fresh `TypeGraph`. | C5 + C7: labels and memo-in-place as type bits tested per value in the function verifier; self-containment once per table (NQ2). |
| T63 | `Program.cpp:43-51, 211-249` | rederivation | `namesLabels` walks a value's type per value per verify. | C5: `Held::Labels`, a bit; one fact with 0003's `holdsLabels(Value)`/`carriesLabels(Type)`. |
| T64 | `Program.cpp:171-177`, `Uses.cpp:74-84` | rederivation | `plainReference` calls `isStatic` (a definition-chain walk) and `upstreamHolds` (a use walk) per value per verify. | C2: static in the grade (0003); the upstream exemption becomes the typed boundary ops (0003's `idr.own.load/store/alloc`, lane 08). |
| T65 | `Program.cpp:185-202` | ladder | `opRules` names `linalg::LinalgOp` and `memref::AllocOp`. | Lane 03/12: the buffer's identity layout and alignment as a type constraint on the owned stage's buffers. |
| T66 | `Program.cpp:81-92` | rederivation | `target()` re-checks the pointer size against the runtime's word at every verify. | Once, in idr-target (lane 13); all four targets are 64-bit (AGENTS.md), so no per-target case here. |
| T67 | `Linearity.cpp:42-66, 133-136` | state | Per verify per function a `DenseMap<Operation *, unsigned>` of places, and per linear value a `DenseSet` and a `DenseMap<Block *, ...>`. | C7(b): one fused walk numbering ops once for all rules; vectors indexed by the number. |
| T68 | `Linearity.cpp:114-131`, `:27-33` | rederivation | `alternatives(branch)` asks every region's successors and is recomputed for every linear value counted inside the op: O(N) per value on a match. | Cache per region op for the walk (C7(b)), or the match answers it in O(1) (lane 03, §5.1 C4). |
| T69 | `Linearity.cpp:150-151` | essential / evidence | Constants of quantity one are exempt from the use count (folding repeats them). | Keep; evidence for DD-Q1 (§6). |
| T70 | `Verify.h:92-212`, `Owned.cpp:94-114` | state | The owned walk keeps a role, a slot and a write epoch per value and an undo log per function per verify; `Role::Carried` exists for the boundary with upstream's buffer ops. | C7(c): keep as OSSA's checker (NQ1 decides where it runs); `Carried` goes with 0003's typed boundary ops (lane 08). |
| T71 | `Owned.cpp:136-162`, `OwnedRegions.cpp:260-317` | rederivation | `deadness` and `ownersAcross` walk a view's owners per use. | Owner chains numbered once per walk (C7(b)); with QL2's SSI each view names its owner once. |
| T72 | `OwnedOps.cpp:32-34, 106, 111-139, 198-200` | ladder | The walk names `ConOp`, `DupOp`, `CellInitOp`, `ShareOp`, `OwnAdoptOp`, `OwnGiveOp` and `isa<BoxType, DataType>`. | Interfaces for "builds a constructor from fields" (the `BuildsValue` trait plus a fields accessor) and the boundary ops (lanes 02/03). |
| T73 | `OwnedOps.cpp:225-251` | rederivation | `declaresSource` re-derives, per owned value per verify, where its reference comes from, from flow edges. | `Res<..., [MemAlloc]>` and the flow interface declare it per result (lane 02); the walk reads the declaration. |
| T74 | `Uses.cpp:26-28`, `IdrDialect.h:101-108` | rederivation (lane 02) | "Consumes" is read from flow edges in C++, not from declared effects on the operand (§5.10 M3, §5.8 EF3). | Lane 02: `MemFree` on consumed operands; the walk reads effects. |
| T75 | `Uses.cpp:104-109` | ladder | `readFrom` names `memref::LoadOp` (0003, "The owned stage reads upstream's buffer ops by name"). | Lane 08: typed boundary ops. |
| T76 | `Uses.cpp:137-168`, `OwnedOps.cpp:113, 129` | rederivation | "A constant reaches only atoms" recomputed per dup per verify (0003, "A dup of atoms-only data exempted by its producer"). | The producing `idr.dup`'s `excl` result type already says it (`IdrOwnershipOps.td:69-72`); the verifier trusts the type at construction (the dup's own verifier) and the walk reads the grade. |
| T77 | `Knots.cpp:81-121` | rederivation | The knot refusal guesses a location from two program walks: a body has no location (0003, "Data types carry no location"). | The body carries its declaration's location (C4). |
| T78 | `OwnedRegions.cpp:173-177`, `Linearity.cpp:30` | upstream | `getSuccessorRegions(region)` per region per walk of a region op. | As T68. |

### 4.6 The Idris side

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| T79 | `compiler/src/IdrisMLIR/Emit/Monad.idr:80-83` | idris | `linear : Quantity -> Ty -> Bool` restates C++'s "a type used once by its type takes no grade" for the world only (`Grades.cpp:28-33`): one fact in two languages, and a Boolean. | C6/C12: the rule generated from the ODS facts; a view `Holding q t` (`ByType`, `Graded`, `Unrestricted`) the emitter matches on. |
| T80 | `compiler/src/IdrisMLIR/Emit/Bodies.idr:340-343` | idris | Linearity tested by matching the representation `Idr (QType One _ _ _) _`. | C12: a generated `quantityOf : MlirType -> Quantity`, or the view of T79. |
| T81 | `compiler/src/IdrisMLIR/Syntax/Idr.idr:492` (generated), `MLIR/Bytecode.idr:421-422` | idris (lane 14) | `QType : Quantity -> Permission -> ty -> Maybe Lifetime -> IdrType ty`: `(Many, Plain, _)` representable, heap spelled two ways (`Nothing`, `Just Heap`, joined by `maybe Lifetime.Heap id l`). | C12: the generator writes a defaulted parameter as a value, and the grade as C1's record; lane 14 owns the generator. |

### 4.7 Callbacks, dead definitions, budgets, per-target cases, hand effects

| ID | file:line | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| T82 | `TypeGraph.h:34-36`, `TypeGraph.cpp:40-55` | cpp / ladder | `forEachNamed` hands a closed three-case answer (a data type with in-place-ness, an array, a leaf) to three `function_ref`s per call, on the hot paths of sealing, the type graph and layouts (`ValueFacts.cpp:241-248`, `TypeGraph.cpp:126-140`, `Components.cpp:81-93`). | Return the step as one sum (`Named = Data{type, inPlace} \| Array{memref} \| Leaf{type}`) matched once by each caller, or a template visitor (§5.3 I5, §5.5 D2). |
| T83 | `Grades.h:65-66`, `Grades.cpp:42` | dead | `idr::world(MLIRContext *)` has no caller (*measured*, `grep -rnE '(^\|[^A-Za-z_:.])world\('`). | Delete. |
| T84 | `Grades.h:141-142`, `IdrAttrs.td:112` | cpp (keep) | `definitionChain`'s step and `ConAttr::walkFields`' visitor are `function_ref`s on cold or per-query paths (§5.3 B5: a traversal compiled once). | Keep. |
| T85 | `Types.cpp:136-138, 199-200`, `Symbols.h:119-121` | cpp (keep) | `seal`, `solveHeld` and `define` take `function_ref` diagnostics and body builders, called once per type. | Keep. |
| T86 | `Layout.h:36-44`, `Layouts.cpp:82-101, 159-190`, `Components.cpp:40` | budget (keep) | The header's object-slot and tag fields are limits lifted by representations (a count word, a group word, a boxed element), never a refusal (`Layout.h:8-12`); a sum's tag is 8, 16 or 32 bits by its constructor count. | Keep: AGENTS.md's "a limit is lifted by a representation". |
| T87 | `IdrDialect.h:263-268` | budget (lane 04) | `constantBytes`, the most static data a fold may make; a larger result stays a run-time computation, never a failure. | Lane 04; it costs size and speed only. |
| T88 | `Asm.cpp:51-54` | budget (keep) | `aliasFrom = 256`: a printer policy that bounds text, not meaning. | Keep. |
| T89 | `Linearity.cpp:126-127` | essential | A use in a region that may run again counts as two: a saturation of the count at "more than once", not a budget. | Keep. |
| T90 | the 27 files | per-target | No per-target case (*measured*: `grep -niE 'aarch64\|arm64\|x86\|darwin\|apple\|linux\|elf\|glibc\|page'` over the files: none in code). Sizes come from the module's data layout (`Layouts.cpp:33-37`); the one host constant, the runtime's word (`Program.cpp:81-92`), is 8 bytes on all four targets. | Keep; T66 moves the word check to idr-target. |
| T91 | `IdrOwnershipOps.td:373-382` | ods (lane 03) | `idr.own.give` declares `MemoryEffectsOpInterface` by hand beside `TypesMatchWith`: the one hand `getEffects` among the ops whose types this lane defines. | Lane 02/03: declare it, or it goes with 0003's typed boundary ops. |

## 5. Target design

What the type system becomes under §5.8's guide (one grade attribute in
the type, asked by verifiers, the bare type for the unrestricted grade)
and §5.9's "facts into types", corrected where our code refutes a wave-1
premise (3.1). Every change is a hard cutover; nothing below keeps an old
form beside a new one. Ranked by leverage; the order of work is 5.13.

### 5.1 C7: the verifier that runs after every pass, local and parallel

*Representation.* The program's verifier does O(table) work and never
walks a function; each function's verifier does one walk.
- (a) **Program level.** A data type name the table has not sealed is
  refused where it is read: `DataType::parse` (`DataBody.cpp:125-135`) and
  the bytecode reader refuse a name with no body, which the table, printed
  before the region (`IdrOps.td:77-80`, *read*) and, in bytecode, read with
  the program's properties before its region's ops (*conjecture*, to check
  against the reader's lazy materialization of entries), has sealed
  already. `ProgramOp::verify`'s walk goes (`Func.cpp:62-89`).
  Effects coverage moves into `FuncOp::verifyRegions` (it reads the
  function and its calls' properties); "a call's effects contain its
  callee's" is the call's `verifySymbolUses` (lane 03). The `TypeGraph` and
  `Layouts` builds leave the verifier (`Program.cpp:104, 266`): labels past
  the higher stage and memo-in-place become per-value bit tests (C5) in the
  function verifier; self-containment is checked once per table (C10,
  NQ2); the recycle size rule follows C3.
- (b) **Function level.** `stageRules`, `linearity`, `lifetimes` and, in the
  owned stage, `owned` share one pre-order walk that numbers ops and
  values once; each region op's alternatives are computed once per walk
  (T68, T78); `isRepetitiveRegion` is asked once per region op (T44).
- (c) **The owned rule** stays OSSA's checker (§5.10 M3), reading
  consumption from declared effects once lane 02 declares them (T74); where
  it runs is NQ1.

*Deletes.* `ProgramOp::verify`'s walk; `effectsCovered`'s program walk;
the program verifier's `TypeGraph` and `Layouts`; `namesLabels`; three of
the four per-function walks; the per-value maps of `Linearity.cpp`.

*One line.* Check moved to a boundary: an undeclared data type is refused
at the parser and the reader; branch deleted: three serial whole-program
walks per verify, run today after every pass and every adaptor (2.3).

*Depends on* lane 03 (call effects in `verifySymbolUses`, match
overrides), lane 13 (the measurement and the pipeline's nesting), C3, C5.

### 5.2 C5: recursive type properties computed once, at construction

*Representation.* `Held` grows from `{References, World}` to
`{References, World, Labels, NoComponent}`, solved at sealing for data
types by the same SCC pass (`ValueFacts.cpp:210-280`) and constant for the
others (`FnType`, `LazyType` name labels; `WorldType` and component-free
sums hold no component). A query is a bit test.

*Deletes.* `namesLabels` (`Program.cpp:43-51`), `holdsNoComponent` and its
per-query `DenseSet` (`Components.cpp:103-135`), 0003's
`holdsLabels(Value)` beside `carriesLabels(Type)` (`lib/IR/Flow.cpp`,
`Analysis/Labels.h`; lane 06 owns the readers).

*One line.* One fact, one place: what a type reaches is solved when the
type is made, never per value per pass (§5.8 T7, FIRRTL's
`RecursiveTypeProperties`).

### 5.3 C3: the token names its cell

*Representation.* `!idr.token<!idr.box<T>, @C>` (0003), inferred by
`idr.take`'s `InferTypeOpInterface` (`IdrOwnershipOps.td:304`), as the
cell type is (`:158-170`).

*Deletes.* The four walks back to the take (T12), the refusal of a token
through a block argument (`Program.cpp:107-108`), `Conversion/Fields.cpp`'s
pairing (lane 12).

*One line.* State made unrepresentable: a token whose cell no type says;
the representation-limit refusal goes.

*Depends on* lanes 07, 08 (Reuses, counting), 12 (lowering).

### 5.4 C2: the lifetime as an ordered coordinate, with `static`

*Representation.* `Lifetime {Static = 0, Heap = 1, Frame = 2}` (0003's
owed order static <= heap <= frame); `fitsIn` is `<=` and `joined` is
`max` (T35); the grade is written once at the op that makes a value, from
what the value holds (the reason c4d38e9b reverted the first attempt).

*Deletes.* `ownership::isStatic` and every caller's static branch
(`Uses.cpp:74-84`, `Program.cpp:176`; counting's `Class::Phantom`,
`Constant`, `StaticRead`: lane 08), the hand order in `Grades.cpp:137-141`.

*One line.* Coordinate: the order of lifetimes is the order of the
enum's values, so the special case "static data is no count" is the rule
"a lifetime below heap"; branch deleted: every definition-chain search for
static data.

*Depends on* lane 08 (who writes it), lane 12 (`StaticData`), lane 14
(the Idris syntax).

### 5.5 C4: a data type's body as one alternative per kind

*Representation.* `DataType::Body` becomes a sum: plain constructors
(name, fields); base list (nil, cons with element); closures (labels, each
name, function, captures); memo (labels with `byName`, `running`,
`forced`). `DataType::list()`, `closures()`, `memo()` return the typed
alternative or nothing; a plain sum has no role at all. The body carries
its declaration's location (0003). Bytecode rows follow the kind (T10).

*Deletes.* `KindRule`, `RoleOnce`, `ruleOf` and the role checks of
`verifyBody` (`DataBody.cpp:29-92`); `roleTags` (`Types.cpp:94`); the
precondition asserts of `roleTag` (`Types.cpp:161-166`); the `Role`
variant and its 18 `get_if` sites (T09); `isMemo()`/`isClosures()` as tag
tests (T07); the bytecode row's flag product and its re-check
(`Bytecode.cpp:107-121`); the knot refusal's location guess (T77).

*One line.* State made unrepresentable: a label in a plain sum, a by-name
label outside a memo, a list without its cons; branch deleted: the table
of legal (kind, role) pairs and every role precondition.

*Depends on* lane 06 (defunctionalization makes closure and memo sums),
lane 14 (`IdrSum`, `TableBody`, the generated syntax), lane 15 (the
frontend's table).

### 5.6 C6: what a value holds, declared in ODS

*Representation.* Each `Idr_Type` takes its constant facts as TableGen
fields (references, world, linear by type, counted, cell pointer, field
type) from which the interface's answers are generated; the data type and
the grade keep code (body-dependent, delegating). The builtin models and
`isFieldType` read one list (T29, T31). idris-mlir-tblgen writes the same
facts into the Idris side.

*Deletes.* The 55 hand answers (T28); the frontend's `linear` rule's world
case (T79); the hand width list in `isFieldType` (`Grades.cpp:305`).

*One line.* One fact, one place: "the world is used once by its type"
read by C++ and Idris from one record; branch deleted: the 55 bodies.

### 5.7 C1: the grade as one attribute inside the type

*Representation.* `#idr.grade<quantity, permission, lifetime>`, one
`AttrDef` with three `EnumParameter`s and `genVerifyDecl` holding the
grade-only rules (the unrestricted grade is no grade; excl is never
frame); `!idr.q<T, #grade>` keeps the carrier rules (`grade.isValidFor`:
frame only where a cell of the frame is reachable, a tensor only linear,
a runtime carrier). The algebra is the attribute's methods
(`holdsReference`, `owned`, `view`, `atQuantity`, `shared`, `forgets`,
`fitsIn`, `join`, `times`); the type-level functions of `Grades.h` become
one-line wrappers. Spellings are ODS records (`lin`, `own`, `excl`, and a
new `borrow`, T02). The bare carrier stays the unrestricted grade (§5.8
T3, already true).

Two deviations from §5.8 DS1.1, each by our evidence: (i) no enum of
legal grades: quantity and permission are two facts, and six of their
pairs occur (3.1, T4 row); (ii) no attribute *interface*: the grade set is
closed, and the skill forbids "an interface where the type already fixes
the implementation"; one attribute class with methods is enough (NQ4).

*Deletes.* `struct Grade` and `hash_value` (`Grades.h:39-54`); the
spelling table and the wrapping printer and parser (`Types.cpp:280-319`);
`holdsOwn`'s switch (T37); `times`'s switch (T36).

*One line.* State made unrepresentable: a grade value that is the
unrestricted grade or exclusive in the frame, checked once per grade (at most 13
today, 21 with C2's static), not per type; branch deleted: the hand spelling table.

*Depends on* lane 14 (generated Idris syntax and encoders), lane 03 (ops'
constraints), lane 08 (the grade's writers).

### 5.8 C10: the type graph and layouts from the table, through the analysis manager

*Representation.* `TypeGraph` is built from the table's members alone
(knots and self-containment need only bodies, `Knots.cpp:3-22`,
`TypeGraph.cpp:179-195`); `Layouts` lays out every member (sum and box
cells), a pure function of the body and the module's target; both reached
only through `getAnalysis` (0003, "Layouts takes the AnalysisManager").

*Deletes.* The value walk with `getAttrDictionary()` (`TypeGraph.cpp:57-87`);
`heldBoxed`/`heldInPlace` (`TypeGraph.h:80`); the four direct builds
(T49); the `DataLayout` per miss (T53).

*One line.* Branch deleted: a whole-program walk that materializes every
op's properties as a dictionary, run up to three times per verify.

### 5.9 C9: content keys from MLIR's printer

*Representation.* `DataRemap`'s key of a remade type is the canonical
printing of its shape (`canonicalText`), which writes a data type as its
name since b9d4d592.

*Deletes.* `describe` (`DataRemap.cpp:30-85`) and its dropped lifetime.

*One line.* One fact, one place: the type syntax printed once, by MLIR;
the drifted copy goes.

### 5.10 C8: every non-mutable type and attribute in bytecode

*Representation.* `IdrBytecode.td` records for `!idr.cell`, `!idr.token`
(after C3), the parameterless types, `#idr.con` (data type, tag, cells,
spine), `#idr.big`, `#idr.closure`, `#idr.instance`, `#idr.refusal`,
`#idr.world` and `#idr.grade` (C1); generated C++ reader and Idris
encoders (lane 14). The data type stays its name, its body in the table.

*Deletes.* The text fallback for these entries and its parse at the
handoff.

*One line.* Branch deleted: the text parser on the bytecode path for
constants. Measurement first (§8, M4).

### 5.11 C11: no attribute made on a read

*Representation.* A run of `#idr.con` is read through a view of its
cells (`walkFields` is already one, `ConAttr.cpp:182-186`); `getField` on
the spine returns the view, never a new attribute.

*Deletes.* `getFields()` on runs; the uniquing in `getField`
(`ConAttr.cpp:188-206`).

*One line.* State made unrepresentable: a read that grows the context.

### 5.12 C12: the Idris side's grades, typed

*Representation.* The generated `QType` follows C1 (a grade record, a
defaulted lifetime as a value, not `Maybe`); the emitter decides a
binder's holding by a view (`ByType | Graded | Unrestricted`) generated
from C6's facts, and reads quantity through a generated `quantityOf`
instead of matching on `QType One _ _ _`. Both hosts compile it (no
dependent field, no growth: plain enums and a view).

*Deletes.* `linear` (`Emit/Monad.idr:80-83`), the match in
`Emit/Bodies.idr:340-343`, the `maybe Lifetime.Heap id l` default
(`MLIR/Bytecode.idr:422`).

*One line.* State made unrepresentable: `(Many, Plain)` as a grade and
two spellings of heap on the Idris side; branch deleted: the frontend's
copy of "used once by its type".

### 5.13 Order and dependencies

1. C9 (independent; removes a latent wrong key).
2. C5 and C6 (facts at construction; no reader changes meaning).
3. C10 (analyses from the table), then C7 (the verifier), which needs C5
   for its per-value bit tests and lane 03 for call effects.
4. C3 and C2 with lanes 07, 08, 12 (they change what counting writes).
5. C4 with lanes 06, 14, 15 (the body's shape on both sides).
6. C1, then C12 and C8 with lane 14 (records settle after C1, C3, C4).
7. C11 any time.

## 6. Evidence for the owner's questions

No answers: what our code says, by question.

**DD-Q1 (may `!idr.lin<i64>` normalize to `i64`?).**
- The frontend grades every quantity-1 binder but the world, words
  included (`Emit/Monad.idr:80-83`, `Emit/Index.idr:58-59`); `!idr.lin<i64>`
  is the most common `lin` in fixtures, 127 of 434 (*measured*, 2.2).
- What reads quantity one of a word: the linearity verifier collects every
  quantity-one value, words included (`Linearity.cpp:45-48`) and counts its
  uses on every path; `lin.enter`/`lin.use` carry a `MemAlloc` on
  `LinResource` so CSE never merges two entries of one value
  (`IdrOwnershipOps.td:388-399, 410, 422`); the quantities-kept contract
  keys binders by location and compares quantities across passes
  (`Expect/Quantities.cpp:3-19`, lane 19). Counting never reads it: a word
  holds no reference (`ValueFacts.cpp:26-33`).
- The verifier already exempts constants of quantity one
  (`Linearity.cpp:144-151`): a folded constant repeats however the program
  was written.
- The normalization the question asks for exists for one case: (many,
  plain) is the bare type (`Grades.cpp:28-33`, `Types.cpp:334-335`), and so
  is every type used once by its type (world, destination, cell).
- AGENTS.md: "No pass may drop what Idris proved: multiplicities ...
  Quantity 1 is a type, `!idr.lin<T>`, which every transformation must keep
  and the verifier checks after every pass." A normalization at the type's
  construction is no pass, but after it no verifier sees a word's
  quantity.

**DD-Q6 (borrows as regions, or lifetimes in types).**
- Today neither. The type's "lifetime" is locality, heap or frame, for
  stack cells (`IdrBase.td:96-108`, `Lifetimes.h:3-28`); 0003 owes `static`
  as a third point (C2). It names no owner.
- A borrow is `Permission::Borrow` (`IdrBase.td:89-94`), made by the pure
  `idr.borrow` (`IdrOwnershipOps.td:93-107`) or read from a field, a case
  argument or a borrowed parameter. Its scope is the owned rule: "a view
  lives only while its owner holds its reference" (`IdrOwnershipOps.td:93-97`),
  checked by walking each view's owners per use (`Owned.cpp:136-162`,
  `OwnedRegions.cpp:260-317`) and recovering what a value was read from by
  definition chains (`Uses.cpp:93-127`).
- Views read out of memory that may be written (a memo cell's captures, a
  buffer's element) die at the memory's next write, tracked by a write
  epoch per place (`Owned.cpp:164-208`): a scope a region could not state.
- Borrowed parameters are the callee's views, kept alive by the caller
  (`Owned.cpp:44-57`); their grade is in the function type (3.1, R1.1).

**Q-O3 (facts into types; an immutable `!idr.data` naming a tycon, bodies
in one table op).**
- In types today: quantity, permission, lifetime of every value
  (`IdrTypes.td:283-305`); a cell's constructor and lifetime
  (`IdrOwnershipOps.td:166-167`); a natural's non-negativity
  (`IdrTypes.td:238-249`); a sum's constructors, roles and labels in its
  body (`IdrTypes.td:29-47`).
- Recomputed instead: static data (`Uses.cpp:82-84`), a token's cell
  (`Program.cpp:106`), a constant's atoms-only reach (`Uses.cpp:165-168`),
  what a type reaches beyond `Held` (`Program.cpp:43-51`,
  `Components.cpp:103-135`).
- The data type: an identified type sealed once (98c6315c), its body
  written once per program in the table (b9d4d592), the table an immutable
  attribute property of `idr.program` (`IdrOps.td:74-75`). Reads take no
  lock. Remaining costs: nominal identity remade by content names on every
  body change (`Symbols.h:139-236`), storage never freed, a "name alone"
  state the parser can make and the program verifier hunts for
  (`Func.cpp:62-89`).
- Who reads bodies: 147 calls in 57 files (*measured*, 2.5), among them ODS
  type constraints and type and attribute verifiers with no op in hand
  (`IdrBase.td:339-342`, `IdrClosureOps.td:169`, `OpsOwnership.cpp:63-75`,
  `ConAttr.cpp:104-131`): a type naming an entry of an ancestor's table
  (DS3.1, §5.9 Design 3's "immutable type naming the tycon") leaves those
  without a body to read.
- Types are made only by program passes (3.1), so no function pass ever
  meets a type being made.

**Q-E2 (where a summary lives).**
- Two summaries already live in IR, verified after every pass: a function's
  effects, an inherent property of `idr.func` and of each `idr.call`
  (`IdrOps.td:143-152, 162-163`), written by one writer for a function and
  its calls together (`Func.cpp:225-230`), checked by `effectsCovered`
  (`Program.cpp:53-72`); and a function's parameter and result grades, its
  `function_type` (`IdrOps.td:158`), read by callers from the callee's
  signature (`IdrDialect.h:101-108`).
- What the first costs: two walks of every function per program verify,
  serial (2.3), which C7 moves into each function's verifier.
- `total` is a third (what Idris proved, `IdrOps.td:131-138`), cleared by
  `absorb` when a body takes in a callee without it (`IdrOps.td:181`).

**QL2 (static single information: every ownership change a new value;
case regions bind the refined scrutinee).**
- Every ownership op of `IdrOwnershipOps.td` defines a new value: `borrow`,
  `share`, `dup`, `lin.enter`, `lin.use`, `own.adopt`, `own.give` give
  results; `take` and `unpack` give the fields and a token; `cell.init`
  gives the box. A grade change is a new SSA value with a new type (§5.8
  B1), so ownership facts of these ops are per value already.
- Case regions bind the constructor's fields as block arguments
  (`Grades.cpp:213-216`), at `fieldType`'s grade (`:253-260`); the default
  region binds the scrutinee again, unrefined (`:211-212`). No type says
  "this value is constructor C" except a cell's (`!idr.cell<box, @C>`).
- What the owned walk still keeps per program point: references per value
  along the path and the undo log (`Verify.h:202-211`), and write epochs of
  memory (`Owned.cpp:191-208`). The epochs are per place, for memory that is
  written: essential to memory, not to values.

**ods-Q6, Q-M2, Q-O5 (verification after every pass at 70,000
functions).**
- Every build verifies after every pass (2.3): the driver never disables
  it.
- The program's verifier runs after every program pass and every adaptor
  of function passes, on one thread, and walks every function three to six
  times, materializing every op's properties as a uniqued dictionary two
  or three times (2.3, 3.2 W5).
- Each function's verifier runs in parallel over functions with four or
  five walks, per-value chain walks inside them, and quadratic-prone
  queries on wide matches (T44, T68).
- The grade's well-formedness costs nothing in a release build after the
  type exists (`StorageUniquerSupport.h:176-182`); the use rules are the
  cost.
- Program-anchored passes: 37 `addPass` calls in the pipeline, about 19
  before lowering (*measured*, `Pipeline.cpp`); one function-anchored
  `addNestedPass` and a few nested pipelines.
- No measurement exists in this checkout (lane 13, §8 M1).

### New questions for the owner

- **NQ1 (ods-types). Where the owned rule runs.** OSSA's checker follows
  def-use chains, which MLIR's verifier doctrine keeps out of op verifiers
  (§5.8 B10). Keep it in `idr.func`'s region verifier (after every pass,
  parallel, as today), or make it a check pass that the pipeline's
  instrumentation runs after every pass (the transform dialect's
  `check-uses` shape), with the region verifier keeping only local rules?
- **NQ2 (ods-types). Who decides the boxes.** The frontend emits every
  type in place and `layout::fit` boxes the cycles by a whole-program remap
  at defunctionalization (`Fit.cpp`, `Layout.h:224-233`). Should the
  frontend emit the boxes (it holds the whole table), so a table is never
  cyclic in place, `DataTableAttr::verify` refuses a cycle once per table,
  and `fit` with its remap goes?
- **NQ3 (ods-types). Plain before and after counting.** `Permission::Plain`
  means "nothing decided" before idr-rc and "holds no reference" after;
  the program's stage says which (`Grades.cpp:80-91`, `Program.cpp:222-228`).
  Two cases of the permission (one only before counting), or one case read
  by stage?
- **NQ4 (ods-types). A closed grade set without an interface.** §5.8 DS1.1
  proposes a grade attribute *interface*; our grades are one closed set,
  and the representation-first skill forbids an interface where the type
  fixes the implementation. One grade attribute with methods (C1): agreed?

## 7. Deletion list

By file and symbol, each with the change that makes it dead (5.x).

- `include/idr/IR/IdrTypes.td`: `Idr_BigOrNat` (T04), `Idr_SumType` (T04),
  `class Idr_LifetimeParam` (T03, C1); `Idr_DataType::Body`'s `kind`/role
  form, `getRunningTag`, `getForcedTag`, `getNilTag`, `getConsTag`,
  `roleTag`, `isMemo`, `isClosures` as tag tests (C4); `Idr_QType`'s three
  enum parameters and its `Grade` builder (C1).
- `include/idr/IR/IdrArrayOps.td`: `Idr_ArrayType` (T04).
- `include/idr/IR/IdrBase.td`: `Idr_CtorRole` and the body-kind/role cross
  product (C4; the kinds stay as the body's alternatives);
  `Idr_Lifetime`'s two-point form (C2, three points in order).
- `include/idr/IR/IdrBytecode.td`: `QType`'s three-enum record (C1);
  `TableCtor`'s `label`/`by_name` beside `role` (C4); the text fallback for
  the entries C8 encodes.
- `include/idr/IR/IdrOwnershipOps.td`: parameterless `Idr_TokenType` (C3);
  `CellType`'s `hasCustomAssemblyFormat` (T13).
- `include/idr/IR/IdrDialect.h`: `namespace role`, `Role`, `kindOf`,
  `emptyRole` (C4); `TableCtor`'s label fields (C4).
- `include/idr/IR/Grades.h`: `struct Grade`, `hash_value(Grade)` (C1).
- `lib/IR/Types.cpp`: `overs`, the custom `parseType`/`printType` wrapper
  (C1, generated spellings); `DataTypeStorage::roleTags` (C4).
- `lib/IR/DataBody.cpp`: `RoleOnce`, `KindRule`, `ruleOf`, the role checks
  of `verifyBody` (C4).
- `lib/IR/ValueFacts.cpp`: the 55 constant answers of the dialect's types
  (C6); `ScalarFacts`/`ArrayFacts` attachments to types no value may have
  (T29).
- `lib/IR/OpsOwnership.cpp`: `CellType::parse`/`print` (T13); the five
  constant answers of `CellType` (C6).
- `lib/IR/Grades.cpp`: `holdsOwn` (C1), the `times` switch (C1/C2), the hand
  order of `fitsIn`/`joined` (C2), `isFieldType`'s width list (C6).
- `lib/IR/ConAttr.cpp`: `getFields()` on runs and the uniquing in
  `getField` on the spine (C11).
- `lib/IR/DataRemap.cpp`: `describe` (C9).
- `lib/IR/TypeGraph.cpp`: the value walk and `getAttrDictionary()` calls
  (`:57-87`), `heldBoxed`, `heldInPlace`, `boxed`, `inlined` (C10).
- `lib/IR/Layout/Layouts.cpp`: its own `TypeGraph`; the `DataLayout`
  fallback in `sizeOf`/`alignmentOf` (C10).
- `lib/IR/Layout/Components.cpp`: `holdsNone`, `holdsNoComponent` as a walk
  (C5).
- `lib/IR/Layout/Fit.cpp`: all of it, if NQ2 is ruled so.
- `lib/IR/Func/Func.cpp`: `ProgramOp::verify`'s walk (`:62-89`) (C7a).
- `lib/IR/Verify/Program.cpp`: `namesLabels` (C5), `effectsCovered`'s
  program walk (C7a), `recycles` (C3, C7a), the `TypeGraph` in
  `verify::program` and the rules it serves there (C7a, C10),
  `plainReference`'s `isStatic` exemption (C2).
- `lib/IR/Verify/Uses.cpp`: `madeStatic`, `isStatic` (C2, with lane 08);
  `onlyAtoms`, `reachesOnlyAtoms` re-derivation in the verifier (T76).
- `lib/IR/Verify/Linearity.cpp`: `Numbering`, the per-value maps of
  `LinearUses` (C7b).
- `lib/IR/Verify/OwnedOps.cpp`: the `excl`-dup re-derivation (T76); with
  lane 08's typed boundary ops, `takesCarried` and `Role::Carried`.
- `lib/Transforms/Demand/Demand.cpp:66`, `lib/Transforms/Expect/ReusesEveryCell.cpp:21`,
  `lib/Conversion/Fields.cpp:37`: the walks from a token to its take (C3;
  their lanes delete them).
- `compiler/src/IdrisMLIR/Emit/Monad.idr`: `linear` (C12);
  `Emit/Bodies.idr:340-343`'s `QType` match (C12); `MLIR/Bytecode.idr:422`'s
  `maybe Lifetime.Heap id l` (C12, lane 14's generator).

## 8. Risks, unknowns, measurements needed

**Risks.**
- R1. The static lifetime was cut over once and reverted (c4d38e9b): it
  graded a value static by where it came from, not by what it holds. C2
  must write it from what the value holds, at the op that makes it, with
  lane 08.
- R2. C7(a)'s boundary check assumes the bytecode reader materializes the
  program's table before any type naming a member (*conjecture*). If it
  does not, the name-alone state stays representable and a cheaper check
  (one walk of value types, no attribute dictionaries) replaces the
  current one.
- R3. DS3 is the owner's (Q-O3). A move to types naming entries of an
  ancestor's table would strand 147 type-level body reads (2.5); a move to
  structural recursive types (DS3.3) is unmeasured at 6,988 types and has
  no upstream precedent (§5.8 DS3.3).
- R4. C1 touches every grade reader, but the algebra is encapsulated (47
  direct enum uses, 2 `QType` names outside the type files); the risk is
  the generated Idris syntax and encoders changing with it (lane 14).
- R5. Fusing the function verifier's walks (C7b) changes which error a
  broken module reports first; fixtures that check messages of two rules on
  one module may need their expectation re-stated as a property (lane 19).
- R6. DD-Q1: if words lose their grade, the linearity verifier and the
  quantities-kept contract lose coverage of quantity on words; if they keep
  it, every word binder carries a `lin.enter`/`lin.use` pair that CSE never
  merges.

**Unknowns.**
- U1. How often the table is remade per pipeline run (T24).
- U2. How many distinct dictionaries the program verifier's
  `getAttrDictionary` calls unique per run (W5), and their memory.
- U3. Whether any value ever holds a frame grade in a body field (T27's
  latent key collision): no remap runs after idr-rc-stack today.

**Measurements needed** (none can run in this checkout: no built
compiler).
- M1. The stage-1 pipeline with and without verification after each pass,
  split into program-verifier and function-verifier time (lane 13; §5.2 W7,
  §5.9 Q-W7).
- M2. Per pass, the count of `QType::get` calls and of uniquer misses (C1).
- M3. The count of values per carrier and grade at stage 1: words at `lin`,
  counted values, values whose type answers the solver's question (§5.6
  W-E2).
- M4. The share of the 75 MB handoff that is text entries (`#idr.con`
  above all) and their parse time (C8, §5.2 W8).
- M5. The largest match's case count against `isRepetitiveRegion` and
  `alternatives` calls in `lifetimes` and `linearity` (T44, T68).

## 9. Sources read

- `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md`;
  `proposals/0000-mlir-native.md` (whole, lines 1-11,141, in order);
  `proposals/0003-facts-once.md` (whole); `audits/p0/README.md` (whole).
- ODS: `foreign/idr/include/idr/IR/IdrTypes.td`, `IdrAttrs.td`,
  `IdrBase.td`, `IdrBytecode.td`, `IdrOwnershipOps.td` (whole),
  `IdrArrayOps.td` (1-100, 225-314), `IdrInterfaces.td` (1-110),
  `IdrOps.td` (52-188).
- C++ (whole): `lib/IR/Types.cpp`, `Attrs.cpp`, `Grades.cpp`,
  `Lifetimes.cpp`, `TypeGraph.cpp`, `DataBody.cpp`, `ConAttr.cpp`,
  `TypeLiterals.cpp`, `ValueFacts.cpp`, `Layout/{Layouts,Components,
  CellInfo,Fit}.cpp`, `Verify/{Program,Owned,OwnedOps,OwnedRegions,
  Linearity,Uses,Knots,Attributes}.cpp`, `Bytecode.cpp`, `Asm.cpp`;
  headers `Grades.h`, `Lifetimes.h`, `TypeGraph.h`, `Layout.h`, `Verify.h`,
  `Ownership.h`, `Symbols.h`, `IdrDialect.h` (100-333).
- C++ (parts): `lib/IR/Func/Func.cpp` (1-265), `lib/IR/DataRemap.cpp`
  (1-120), `lib/IR/OpsOwnership.cpp` (1-83), `lib/IR/Flow.cpp` (164-200,
  339-351), `lib/Transforms/Expect/Quantities.cpp` (1-60),
  `lib/Transforms/Pipeline.cpp` (the pass list).
- Idris: `compiler/src/IdrisMLIR/Emit/Index.idr` (30-80),
  `Emit/Monad.idr` (60-90), `Emit/Bodies.idr` (330-350),
  `Syntax/Idr.idr` (1-30, 110-160, 476-497), `Encoding/Idr.idr` (1-60),
  `MLIR/Bytecode.idr` (by grep), `SyntaxSamples.idr` (by grep).
- Pinned MLIR: `lib/IR/Operation.cpp:285-305`,
  `include/mlir/IR/StorageUniquerSupport.h:170-215`,
  `lib/IR/SymbolTable.cpp:364-397`, `lib/Pass/Pass.cpp:615-645, 1023-1028`,
  `include/mlir/Pass/PassManager.h` (by grep),
  `lib/IR/Verifier.cpp:330-410`.
- History: `git log --oneline` over this lane's paths (29 commits);
  `git show` of 98c6315c, 73bba53f, b9d4d592 (messages and stats),
  c4d38e9b, da66bd95, 3d279eb9 (messages).
- Measurements: the `grep`/`wc` commands given beside each count in
  sections 2 to 4, run at e96bb991 with the working tree's uncommitted
  proposal.
