<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the centralized effect system

Written 2026-10-21 at e96bb991, for P0 to adopt (F DP-04, the owner's
ruling of 2026-10-21: "a new centralized effect system so there's never
downstream disagreement about this ever again ... so it can all be
defined and monomorphized in a single place"). No code is written; nothing
was built. Claims are marked *read* (a path and line, at e96bb991 for our
tree, at 7208ba24 for `.toolchain/llvm-project`), *measured* (the method is
given), *conjecture*, or *decision* (the owner's, as recorded in
`audits/p0/synthesis/F-decisions.md`, cited "F DP-nn").

Citations. "02 §3.7", "02 E22" are `audits/p0/02-ods-effects.md`'s section
and issue IDs (likewise 03, 04, 05, 06, 08, 10, 12, 14, 18, 19, 21). Wave
1's research is cited at its new home: "5.2 A5" is
`audits/p0/wave1/5.2-mlir-ods.md`, finding A5 (line given at first use);
"5.8 EF3" is `audits/p0/wave1/5.8-dialect-design.md`; the question
register is `audits/p0/wave1/questions.md`. Paths without a prefix are
relative to `foreign/idr/`; upstream paths are relative to
`.toolchain/llvm-project/mlir/`.

**Rules this design is held to.** AGENTS.md whole, and in particular its
new bullet (read, AGENTS.md:74-117): "NO FACT KNOWN STATICALLY, RIGHT NOW
OR IN PRINCIPLE, MAY EVER BE PAID FOR AT RUNTIME". The representation-first
skill. F DP-08 (decision): concept-constrained templates for our own C++,
MLIR op interfaces where the op set is open, a concept may read ODS facts
and never list ops. Hard cutover with hard culling.

## 0. In plain words

One TableGen file, `include/idr/IR/IdrEffects.td`, says every effect fact
once: which states exist and which are ordered with which (a resource
tree); what each op does to them, either as plain ODS effects or, for the
fourteen ops whose effects follow from their operands' types, as rules from
a small closed set; what a function's summary may say (each summary bit is
declared on the tree node it stands for); and what LLVM is told. Two
generators read it: upstream's `mlir-tblgen` writes the `getEffects` of
every op with static effects, and `idris-mlir-tblgen` writes the tree's
C++ classes and tables, one compile-time effect constant per op class, the
rule tuples of the typed ops, and the summary's two-way table with
`static_assert`ed checks. One C++ API answers every question (does IO, may
this move past that, is it dead if unused, what does this function do):
typed code reads `OpT::effects()` as a constant, `Operation *` code makes
one interface dispatch, and both run the same functions over one
`EffectSet` value. A function's summary is derived from its ops by one
function and written by one writer; the verifier holds it to that
derivation per function, in parallel, after every pass, and holds every
call to its callee exactly. Everything that reads effects today some other
way is deleted (section 5).

The owner's choices the tree's shape waits on (section 6): whether a dead
crash or divergence may be deleted, and what `exit` is (DP-01); whether the
world value stays (DP-02); whether a crash is ordered with heap writes,
what a summary covers, and whether runtime state is IO (DP-03). Each answer
is a one-line edit of the source. One combination is incoherent under the
ruling itself: a summary of only {io, crash, diverge} (6.4).

## 1. The one source

### 1.1 What it holds, and where

`include/idr/IR/IdrEffects.td`, included by `IdrInterfaces.td` in place of
today's six `Resource` defs (`IdrInterfaces.td:87-92`, read). It holds,
and nothing else in the tree holds:

| # | fact | form | today's carriers it replaces |
| --- | --- | --- | --- |
| S1 | the states, and which are ordered with which | a tree of `Idr_Node` records | six sibling resource structs (`include/idr/IR/IdrDialect.h:58-99`) |
| S2 | the effect kinds | upstream's four (`Read`, `Write`, `Allocate`, `Free`), no new kind | — |
| S3 | named effect bundles | `MemoryEffects<[...]>` defs over the nodes | `Idr_MayCrash` (`IdrInterfaces.td:116-117`), the IO class's list (`IdrIOOps.td:21-23`) |
| S4 | the typed rules | `Idr_When` records (a closed set, one C++ predicate each) and `Idr_Rule` classes | `consumedEffects`, `readsMemoState` (`lib/IR/Effects.cpp:79-105`), the `ConsumesOperands` trait (`Traits.h:84-91`), the hand `getEffects` of `con`, `field`, `tag`, `match`, `own.give`, `call` |
| S5 | each op's effects | on the op's record: ODS effects (static ops) or a rule list (typed ops), never both | the same, plus `PerformsIO`, `ObservableIO`, `MayCrashOpInterface`, `ConsumesOperands` |
| S6 | each op's speculation | upstream's traits, plus typed speculation rules | hand `getSpeculatability` (`lib/IR/OpsCon.cpp:62-67`, `lib/IR/OpsConReads.cpp:26-29`) |
| S7 | the summary's vocabulary | `Idr_Atom` records, each on one node; the property's enum is generated from them | `Idr_Effect` (`IdrAttrs.td:200-209`) and the hand table `rows` (`lib/IR/Func/Func.cpp:250-256`) |
| S8 | the one non-op input of a summary | `total` (Idris's proof) seeds the `diverge` atom | `bodyEffect`'s first line (`lib/IR/Func/Func.cpp:190`) |
| S9 | what LLVM is told | columns on the atoms and nodes | nothing: no fact reaches LLVM today (12 CV-05, CV-14) |

The build-time checks of section 1.10 are part of the source: they run in
`idris-mlir-tblgen` and refuse a source that breaks them.

### 1.2 The resource tree

The pin's resources form a hierarchy (`getParent`, `isDisjointFrom`,
`isAddressable`; `include/mlir/Interfaces/SideEffectInterfaces.h:88-176`,
read). Two resources conflict only when one is an ancestor of the other;
siblings never conflict (`:151-153`, read; 5.2 A8,
`audits/p0/wave1/5.2-mlir-ods.md:143`). CSE already reads disjointness and
addressability (`lib/Transforms/Utils/CSE.cpp:222-228`, read). An effect
that names a value may not be on a non-addressable resource
(`SideEffectInterfaces.h:339-343`, a fatal error, read), and an
addressable resource may not have a non-addressable parent (`:164-173`,
checked only under `EXPENSIVE_CHECKS`, read). ODS cannot declare a parent:
`Resource<name>` names a C++ class (5.2 A3, `5.2-mlir-ods.md:77`). So the
tree is records of ours that subclass upstream's `Resource`, and
`idris-mlir-tblgen` writes the classes.

```tablegen
include "mlir/Interfaces/SideEffectInterfaces.td"

// A state the program's ops act on: the C++ class idris-mlir-tblgen writes
// for it (::idr::effects::<cppName>, its getParent and isAddressable), its
// parent, and whether an effect on it may name a value. It is upstream's
// Resource, so an op says `MemWrite<Idr_IO>` in upstream's own syntax.
class Idr_Node<string cppName, Resource parentNode, bit isAddressable>
    : Resource<"::idr::effects::" # cppName> {
  Resource parent = parentNode;
  bit addressable = isAddressable;
}

// Upstream's DefaultResource (SideEffectInterfaceBase.td:39) is the root:
// any memory, and what an op of another dialect touches through a value.
// Upstream's AutomaticAllocationScopeResource (:41) is a function's frame.
// Both are nodes of the tree as they are; their classes stay upstream's.

// Memory the program holds: cells, boxes, arrays, buffers.
def Idr_Heap    : Idr_Node<"Heap", DefaultResource, 1>;
// A cell's reference count: dup, drop, take, consumption, is_unique.
def Idr_Count   : Idr_Node<"Count", Idr_Heap, 1>;
// A memo cell's state, the one cell that changes while referenced.
def Idr_Memo    : Idr_Node<"MemoState", Idr_Heap, 1>;
// A new value's identity, which no memory holds (a linear value's entry).
def Idr_Fresh   : Idr_Node<"Fresh", DefaultResource, 1>;
// What the program's outside observes. Every IO op reads and writes it,
// so all IO stays in program order (AGENTS.md: "in program order with
// every other effect").
def Idr_IO      : Idr_Node<"IO", DefaultResource, 0>;
// The end of the run: a crash [DP-01: and exit]. [DP-03 ods-Q3 (a): its
// parent is DefaultResource, it is addressable, and Idr_Heap and Idr_IO are
// its children.]
def Idr_Halt    : Idr_Node<"Halt", Idr_IO, 0>;
// A run that may never end. Under Halt, so a crash and a loop that may not
// end stay ordered with each other and with output.
def Idr_Diverge : Idr_Node<"Divergence", Idr_Halt, 0>;
// Runtime state read without IO: the handle table, the C library's error
// text. Every IO op writes its ancestor, so a read of it stays after what
// changes it. [DP-03 eff-Q4 (a): deleted; its readers read Idr_IO.]
def Idr_Runtime : Idr_Node<"RuntimeState", Idr_IO, 0>;
// A forged world's chain (world.new). [DP-02 A: deleted with the world.]
def Idr_Forge   : Idr_Node<"Forge", Idr_IO, 0>;
```

Drawn, under DP-01 A, DP-02 B and DP-03 (b, b, b) (one combination, chosen
only to draw; section 6 gives every other):

```
DefaultResource (upstream root, addressable)
├── Heap                addressable    cells, boxes, arrays, buffers
│   ├── Count           addressable    reference counts
│   └── MemoState       addressable    a memo cell's state
├── AutomaticAllocationScopeResource (upstream, addressable)   frame cells
├── Fresh               addressable    a new value's identity
└── IO                  not addressable   what the outside observes
    ├── Halt            not addressable   a crash ends the run
    │   └── Divergence  not addressable   a run that may never end
    ├── RuntimeState    not addressable   handle table, error text
    └── Forge           not addressable   a forged world's chain
```

Why each node, against the evidence:
- *IO has no disjoint IO children.* 03 (§5.3's table, its `IO.Files`,
  `IO.Clock`, `IO.Process`) splits IO so clock reads move past console
  writes. That reorders IO, which AGENTS.md forbids ("in program order with
  every other effect"); a program that prints and then reads the clock
  measures a different time. Rejected. Read-only *runtime state* is the one
  disjoint child that moves (RuntimeState), because nothing outside sees a
  read of it.
- *Halt under IO.* The runtime's crash flushes standard output, writes its
  message and exits (`runtime/Io/Ending.cpp:64-71`, read via 02 §6, 18
  §2.3), so output before a crash comes first and none comes after it.
  Today ten ops say this by writing `IOResource` beside their own resource
  (02 §2.3, E1); the tree says it once.
- *Divergence under Halt.* A loop that may not end, then a crash: swapped,
  the program crashes instead of hanging. A chain keeps them ordered;
  siblings would not (5.2 A8).
- *Heap a sibling of IO.* Nothing reads program memory after a crash
  (`Ending.cpp:66-71`, 02 §6); today's heap order is an accident of every
  heap effect sitting on the root (02 §6 ods-Q3). This is DP-03's part (a)
  versus (b).
- *Count and MemoState under Heap.* Counts live in cell headers, memo state
  in memo cells: heap memory. Under one parent they conflict with a write
  of "some heap" (an effect on Heap itself, a summary's `writes` atom) and
  not with each other.
- *Fresh.* `lin.enter` and `lin.use` allocate a fresh value so that CSE
  never merges two (`IdrOwnershipOps.td:410, 422`, read). Before counting
  nothing is owned, so no consumption keeps them apart (03 O-29's
  "consumption could replace it" holds only after idr-rc), and merging two
  would put one linear value at two uses. The identity is essential; it is
  a node apart from Heap so "allocates memory" (a Heap-subtree allocation)
  needs no exception for it (today's `isa<LinResource>` exceptions,
  `lib/Transforms/Expect/Allocation.cpp:38`,
  `lib/Transforms/Ownership/Reshape.cpp:302`, read). It is addressable
  because the allocation names its result.
- *The frame* is upstream's `AutomaticAllocationScopeResource`, a child of
  the root (`SideEffectInterfaces.h:198-202`, read), which `cell.stack`
  already uses (`IdrOwnershipOps.td:211`, read).

### 1.3 Effect kinds, and consumption

No kind is invented. Upstream's four are the vocabulary; MLIR's second
interface, `ConditionallySpeculatable`, is the other half of the model
(5.2 A7, `5.2-mlir-ods.md:132`).

**Consumption is `Read` + `Free` on the consumed operand, on `Count`.** The
transform dialect's form (`transform::consumesHandle`,
`lib/Dialect/Transform/Interfaces/TransformInterfaces.cpp:1793-1802`, read:
`Read` and `Free` on each consumed `OpOperand`). It makes a consuming op
never trivially dead and never merged, and leaves a borrow (no effect)
deletable (5.2 M2, `5.2-mlir-ods.md:546`). The resource is `Count`, the
one resource `dup`, `drop`, `take`, consumption and a future `is_unique`
share (08 T7; C §3.10), so an `is_unique` (a `Read` of `Count`) cannot move
past a `dup` (a `Write`) once runtime calls carry effects: Swift's hazard
(5.10 R1.5, `audits/p0/wave1/5.10-rc.md:627`; 12 §1 C4). Today consumption
is a `Free` on `ReferenceResource` without the `Read`
(`lib/IR/Effects.cpp:103`, read) and the counts sit on the root, two
resources for one count (08 §3.1 R1.5).

Consumption is not static per op: it fires only on an owned or exclusive
operand, which exist only from idr-rc on (`lib/IR/Effects.cpp:98`, read;
02 §3.5). What *is* static per op class is which operand positions take
over a reference. Today those positions are recomputed per query by
rebuilding the op's whole flow-edge list (`eachTaken`,
`lib/IR/Effects.cpp:45-75`; 02 E53, E54), which the new AGENTS.md rule
forbids. In the source the positions are declared per op class (the rule's
operand group, 1.6), and only the grade, which the operand's type carries,
is read per op. *Conjecture* that every taking position is static per op
class: today's taking ops take whole operand groups (fields, captures,
arguments, results, the one operand; `IdrInterfaces.td:310-316`,
`lib/IR/Func/Call.cpp:61-72`, read). The cutover's gate checks it (8.3,
G6).

### 1.4 The summary's vocabulary: atoms

A function's summary is a set of *atoms*. Each atom is declared on one
node, with the effects a call holding it declares on that node and what
LLVM is told. The property's enum is generated from the atoms by
upstream's enum generator, so `effects<io, crash>` keeps today's spelling
for today's three bits and the bit-to-resource table `rows` cannot exist
(it is the atoms).

```tablegen
// A location of #llvm.memory_effects (LLVMAttrDefs.td:1069-1072).
class Idr_LLVMLocation<string paramName> { string param = paramName; }
def Idr_ArgMem       : Idr_LLVMLocation<"argMem">;
def Idr_OtherMem     : Idr_LLVMLocation<"other">;
def Idr_Inaccessible : Idr_LLVMLocation<"inaccessibleMem">;
def Idr_ErrnoMem     : Idr_LLVMLocation<"errnoMem">;

// One bit of a summary: the node it stands for; the effects a call that
// holds it declares on that node (an op effect on the node or below it is
// summarized here when its kind is one of these); where LLVM sees it; and
// whether it stops a run from returning (no `willreturn`, no
// `mustprogress` when it is `diverge`).
class Idr_Atom<int index, string spelling, Idr_Node n, list<MemoryEffect> callEffects,
               list<Idr_LLVMLocation> llvmAt, bit endsRun = 0>
    : I32BitEnumAttrCaseBit<spelling, index> {
  Idr_Node node = n;
  list<MemoryEffect> effects = callEffects;
  list<Idr_LLVMLocation> llvm = llvmAt;
  bit stopsReturn = endsRun;
}

def Idr_AtomIO      : Idr_Atom<0, "io", Idr_IO, [MemRead<Idr_IO>, MemWrite<Idr_IO>],
                               [Idr_OtherMem, Idr_Inaccessible, Idr_ErrnoMem]>;
// [DP-01 B: MemRead<Idr_Halt>.]
def Idr_AtomCrash   : Idr_Atom<1, "crash", Idr_Halt, [MemWrite<Idr_Halt>],
                               [Idr_OtherMem, Idr_Inaccessible, Idr_ErrnoMem], 1>;
// [DP-01 B: MemRead<Idr_Diverge>.]
def Idr_AtomDiverge : Idr_Atom<2, "diverge", Idr_Diverge, [MemWrite<Idr_Diverge>], [], 1>;
// [DP-03 eff-Q4 (a): deleted.]
def Idr_AtomRuntime : Idr_Atom<3, "runtime", Idr_Runtime, [MemRead<Idr_Runtime>],
                               [Idr_OtherMem]>;
// [DP-03 eff-Q1 (b) — required under DP-04, 6.4: these four.]
def Idr_AtomReads   : Idr_Atom<4, "reads", Idr_Heap, [MemRead<Idr_Heap>],
                               [Idr_ArgMem, Idr_OtherMem]>;
def Idr_AtomWrites  : Idr_Atom<5, "writes", Idr_Heap, [MemWrite<Idr_Heap>],
                               [Idr_ArgMem, Idr_OtherMem]>;
def Idr_AtomCount   : Idr_Atom<6, "count", Idr_Count, [MemRead<Idr_Count>, MemWrite<Idr_Count>],
                               [Idr_ArgMem, Idr_OtherMem]>;
def Idr_AtomMemo    : Idr_Atom<7, "memo", Idr_Memo, [MemRead<Idr_Memo>, MemWrite<Idr_Memo>],
                               [Idr_ArgMem, Idr_OtherMem]>;

// What a run of a function may do besides computing its results: the
// atoms, generated, so the summary's names are the tree's. idr.func and
// idr.call hold it as `effects` (1.8).
def Idr_Summary : I32BitEnumAttr<"Summary", "what a run of a function may do",
    !listconcat([I32BitEnumAttrCaseNone<"none">], !instances<Idr_Atom>())> {
  let cppNamespace = "::idr::effects";
  let separator = ", ";
  let printBitEnumQuoted = 0;
  let genSpecializedAttr = 0;
}
```

(`!instances` exists in the pinned TableGen: `llvm/lib/TableGen/TGLexer.cpp:683`,
read. The exact list typing of the enum's cases is a sketch.)

**Projection** (the derivation of a summary from op effects, generated as a
table, 2.4): an op's effect of kind *k* on node *r*
- is summarized as the atom on the nearest ancestor-or-self of *r* that has
  atoms, among those whose effects include kind *k*;
- or, if *r* has no such ancestor but has atoms below it (the root), as
  every atom below *r* whose effects include *k*, restricted to atoms on
  addressable nodes when the effect names a value (a non-addressable state
  cannot be reached through a value, 1.2): so an upstream `memref.store`
  on the root with a value becomes `writes`, `count` and `memo`, never
  `io`;
- or, if no atom is above or below *r* (`Fresh`, the frame), is local and
  dropped;
- and `Allocate` and `Free` are never summarized: an allocation is part of
  computing a result (upstream's own reading, 5.2 A6,
  `5.2-mlir-ods.md:113`), and a `Free` is consumption, which the call
  declares on its own operands (its typed rule, 1.6). That a callee frees
  only what it was handed owned is the ownership model's invariant, which
  the owned verifier checks (`lib/IR/Verify/Owned.cpp`, read).

An unknown op (no effect declaration and not `RecursiveMemoryEffects`)
projects to every atom.

### 1.5 Bundles

```tablegen
def Idr_DoesIO       : MemoryEffects<[MemRead<Idr_IO>, MemWrite<Idr_IO>]>;
// [DP-01 B: MemRead<Idr_Halt>, with ConditionallySpeculatable answering
// NotSpeculatable, as arith.divsi is declared (5.2 A7).]
def Idr_MayHalt      : MemoryEffects<[MemWrite<Idr_Halt>]>;
// [DP-01 B: no op lists it; idr.may_loop is deleted.]
def Idr_MayDiverge   : MemoryEffects<[MemWrite<Idr_Diverge>]>;
// [DP-03 eff-Q4 (a): Idr_DoesIO.]
def Idr_ReadsRuntime : MemoryEffects<[MemRead<Idr_Runtime>]>;
// [DP-02 A: deleted.]
def Idr_Forges       : MemoryEffects<[MemWrite<Idr_Forge>]>;

// Everything a function may do, computed from the atoms: what an op that
// runs code no symbol names declares (apply, force), and a function's
// default summary. One list, never a second copy of the atoms.
defvar Idr_AnyEffect = !foldl([]<MemoryEffect>, !instances<Idr_Atom>(), acc, a,
                              !listconcat(acc, a.effects));
def Idr_RunsUnknown  : MemoryEffects<Idr_AnyEffect>;
```

### 1.6 Typed rules

ODS is all or nothing per op: an op that declares effects in ODS and lists
`DeclareOpInterfaceMethods<MemoryEffectsOpInterface>` stops mlir-tblgen
("Unexpected overlap", `tools/mlir-tblgen/OpDefinitionsGen.cpp:1078`, read;
5.2 A5, `5.2-mlir-ods.md:100`). Upstream's precedent for effects that
follow from types is a trait that supplies the whole `getEffects`
(`FunctionalStyleTransformOpTrait`,
`include/mlir/Dialect/Transform/Interfaces/TransformInterfaces.h:1327-1335`,
read; 5.2 row 3, `5.2-mlir-ods.md:655`), and ours already is one
(`Idr_ConsumesOnly`, `IdrInterfaces.td:310-316`; 02 E40). So a typed op
declares *all* its effects as rules, and one C++ trait, `TypedEffects`,
supplies `getEffects` by expanding the rules the generator writes for that
op. No op needs static ODS effects and typed rules at once: the one op that
mixed today's two kinds, `idr.call`, has only derived effects (its summary,
its consumption, its fresh linear results), and `apply`, which runs before
idr-rc, has no owned operand to consume (02 §3.5). So no upstream patch to
mlir-tblgen is needed (7.3). The generator refuses an op that has both
(1.10).

```tablegen
// A condition read off an op's own operand or result types: a closed set,
// each with one C++ predicate (::idr::effects::When<...>, 3.2). Never a
// condition read anywhere else.
class Idr_When;
def Idr_IfOwned       : Idr_When;  // the value's grade is own or excl (Grades.h isOwned)
def Idr_IfMemoSum     : Idr_When;  // the value is a memo sum's (DataType::isMemo)
def Idr_IfCellPointer : Idr_When;  // one pointer to a cell (ValueFactsTypeInterface::isCellPointer)
def Idr_IfLinear      : Idr_When;  // the value is linear (Grades.h isLinear)
def Idr_FromSummary   : Idr_When;  // the op's `effects` property: each atom's call effects

// A rule: these effects on each value of the operand or result group named,
// when the condition holds of that value's type ("" names no value: an
// op-level effect).
class Idr_Rule<list<MemoryEffect> fx, string valueGroup, Idr_When cond> {
  list<MemoryEffect> effects = fx;
  string group = valueGroup;
  Idr_When when = cond;
}
// Speculation: not speculatable when the condition holds of a value of the
// group; otherwise speculatable.
class Idr_NotSpeculatableIf<string valueGroup, Idr_When cond> {
  string group = valueGroup;
  Idr_When when = cond;
}

class Idr_Takes<string g>         : Idr_Rule<[MemRead<Idr_Count>, MemFree<Idr_Count>], g, Idr_IfOwned>;
class Idr_ReadsMemo<string g>     : Idr_Rule<[MemRead<Idr_Memo>], g, Idr_IfMemoSum>;
class Idr_BuildsCell<string g>    : Idr_Rule<[MemAlloc<Idr_Heap>], g, Idr_IfCellPointer>;
class Idr_FreshIfLinear<string g> : Idr_Rule<[MemAlloc<Idr_Fresh>], g, Idr_IfLinear>;
def Idr_Summarized                : Idr_Rule<[], "", Idr_FromSummary>;

// The op base: an op names its typed rules (and typed speculation) here,
// and gets the trait that supplies getEffects (and getSpeculatability)
// from them exactly when it has some. Every op also gets the generated
// facts' trait and interface (2.3).
class Idr_Op<string mnemonic, list<Trait> traits = [],
             list<Idr_Rule> rules = [], list<Idr_NotSpeculatableIf> spec = []>
    : Op<Idr_Dialect, mnemonic, !listconcat(traits, [Idr_DeclaredEffects],
          !if(!empty(rules), [], [MemoryEffectsOpInterface, Idr_TypedEffectsTrait]),
          !if(!empty(spec), [], [ConditionallySpeculatable, Idr_TypedSpeculationTrait]))> {
  list<Idr_Rule> typedEffects = rules;
  list<Idr_NotSpeculatableIf> typedSpeculation = spec;
}
```

The typed ops (02 §3.3 W1 and the `Idr_ConsumesOnly` users,
`IdrInterfaces.td:310-316`; read), fourteen:
`con`, `field`, `tag`, `match`, `closure`, `suspend`, `delay`, `return`,
`yield`, `share`, `unpack`, `nat.to_big`, `own.give`, `call`, and under
ods-Q2's settled reading (F DP-04: "the rules ... are declared in the one
source, so a type-dependent effect no longer forces either a hand trait or
a split") none of them splits. `lin.enter` and `lin.use` are not among
them: their fresh result is unconditional, so it is a static decorator
(02 T3 counted them with the typed ops).

### 1.7 Excerpts, by family

Each excerpt is the source as it would read; `[DP-...]` marks a line one of
the owner's answers edits (section 6).

**IO** (`IdrIOOps.td:19-23` today: `PerformsIO`, `ObservableIO`, the
runtime mark and the IO list, read):

```tablegen
class Idr_IOOp<string mnemonic, list<Trait> traits = [],
               string symbol = "idris_rt_io_" # mnemonic>
    : Idr_Op<"io." # mnemonic, !listconcat(traits, [Idr_DoesIO])> {
  string runtimeSymbol = symbol;  // a field (02 E69), no longer a C++ trait
  bit idrisIO = 1;                // [DP-02 A only; under B the world operand says it]
}
def Idr_PutStrOp : Idr_IOOp<"put_str", [Idr_Primitive]> {
  let arguments = (ins Idr_StrRead:$str, Idr_WorldType:$world);  // [DP-02 A: no $world]
  let results = (outs Idr_WorldType:$next);                       // [DP-02 A: none]
}
```

**Platform** (`IdrPlatformOps.td:282-287, 311-322, 363-374`, read):

```tablegen
// Base's exitWith: IO, and the end of the run. [DP-01 eff-Q2: Idr_MayHalt
// (exit is a halt), or MemWrite<Idr_Exit> on a node of its own under
// Idr_IO, or Idr_MayDiverge (exit is a divergence).] A terminator with no
// successor (03 R4), so "never returns" is structural; the build-time check
// of 1.10 (e) ties it to a run-stopping atom.
def Idr_ExitOp : Idr_IOOp<"exit", [Idr_MayHalt, Terminator]> {
  let arguments = (ins I64:$status, Idr_WorldType:$world);
}
// The C library's text for an error number. [DP-03 eff-Q4 (a): Idr_DoesIO.]
def Idr_StrerrorOp : Idr_Op<"io.strerror", [Idr_ReadsRuntime, Idr_Primitive]> {
  string runtimeSymbol = "idris_rt_io_strerror";
  bit idrisIO = 1;
  let arguments = (ins I64:$code, Idr_WorldType:$world);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc<Idr_Heap>]>:$str, Idr_WorldType:$next);
}
// Base's getString: pure to Idris (`Registry/Primitives.idr:373-375`, read),
// a read of the handle table to MLIR. [DP-03 eff-Q4 (a): MemRead<Idr_IO>.]
def Idr_HandleStringOp : Idr_Op<"handle.string", [Idr_ReadsRuntime, Idr_Primitive]> {
  string runtimeSymbol = "idris_rt_handle_string";
  let arguments = (ins I64:$handle);
  let results = (outs Res<Idr_StrValue, "", [MemAlloc<Idr_Heap>]>:$str);
}
```

**Checks** (`IdrCheckOps.td:19-90`, read):

```tablegen
def Idr_CrashOp : Idr_Op<"crash", [Idr_MayHalt, Terminator]> {   // 03 R4: one terminator
  let arguments = (ins StrAttr:$message);
}
class Idr_CheckOp<string mnemonic, I32EnumAttrCase kind, list<Trait> traits = []>
    : Idr_Op<"check." # mnemonic, !listconcat(traits, [Idr_MayHalt,
        DeclareOpInterfaceMethods<Idr_GuardOpInterface>])> {
  EnumCase checkKind = kind;
}
// Made by idr-tail-loops in loops of functions without `total`.
// [DP-01 B: deleted.]
def Idr_MayLoopOp : Idr_Op<"may_loop", [Idr_MayDiverge]>;
```

**Ownership and cells** (`IdrOwnershipOps.td:74, 89, 192, 211, 230-231,
258, 318, 410, 422`, read; 03 §5.3's table for `drop` and `take`):

```tablegen
def Idr_DupOp  : Idr_OwnedOp<"dup"> {
  let arguments = (ins Arg<Idr_ViewType, "", [MemRead<Idr_Count>, MemWrite<Idr_Count>]>:$value);
}
def Idr_DropOp : Idr_OwnedOp<"drop"> {
  let arguments = (ins Arg<Idr_OwnType, "",
      [MemRead<Idr_Count>, MemWrite<Idr_Count>, MemFree<Idr_Heap>]>:$value);
}
def Idr_TakeOp : Idr_OwnedOp<"take"> {
  let arguments = (ins Arg<Idr_OwnType, "",
      [MemRead<Idr_Heap>, MemWrite<Idr_Count>, MemFree<Idr_Heap>]>:$value, Idr_TagAttr:$tag);
}
// One class, the resource the only difference (5.8 O2, `5.8-dialect-design.md:887`;
// 03 O-25). Stages and full-region bits kept: F DP-04 settles ods-Q5 as
// "declared in the one source like every other" (nothing reads them).
class Idr_CellAllocOp<string mnemonic, Resource where, TypeConstraint cell>
    : Idr_OwnedOp<mnemonic> {
  let results = (outs Res<cell, "", [MemAlloc<where, 0, FullEffect>]>:$cell);
}
def Idr_CellNewOp   : Idr_CellAllocOp<"cell.new", Idr_Heap, Idr_HeapCell>;
def Idr_CellStackOp : Idr_CellAllocOp<"cell.stack", AutomaticAllocationScopeResource, Idr_FrameCell>;
def Idr_LinEnterOp  : Idr_Op<"lin.enter", [/* forwarding, 02 T6 */]> {
  let results = (outs Res<Idr_LinType, "", [MemAlloc<Idr_Fresh>]>:$result);
}
def Idr_ShareOp : Idr_Op<"share", [AlwaysSpeculatable /* , forwarding */],
                         [Idr_Takes<"value">]>;
```

**Data** (`IdrOps.td:283-368`, `IdrMatchOps.td:25-37, 102`; the hand bodies
`lib/IR/OpsCon.cpp:50-67`, `lib/IR/OpsConReads.cpp:26-38, 157-160`,
`lib/IR/OpsMatch.cpp:135-138`; read):

```tablegen
def Idr_ConOp : Idr_Op<"con", [],
    [Idr_Takes<"fields">, Idr_BuildsCell<"result">],
    [Idr_NotSpeculatableIf<"result", Idr_IfCellPointer>,
     Idr_NotSpeculatableIf<"fields", Idr_IfOwned>]>;
def Idr_FieldOp : Idr_Op<"field", [],
    [Idr_ReadsMemo<"value">], [Idr_NotSpeculatableIf<"value", Idr_IfCellPointer>]>;
def Idr_TagOp   : Idr_Op<"tag", [AlwaysSpeculatable], [Idr_ReadsMemo<"value">]>;
// The family (IdrMatchOps.td:25-37) keeps its traits; only idr.match, whose
// scrutinee may be a memo sum, has a rule; idr.match_lit's is a word, so it
// stays exact.
class Idr_MatchOpBase<string mnemonic, Region caseRegion, list<Trait> traits = [],
                      list<Idr_Rule> rules = []>
    : Idr_Op<mnemonic, !listconcat(traits, [RecursiveMemoryEffects, RecursivelySpeculatable,
                                            SingleBlock, Idr_MatchOpInterface]), rules>;
def Idr_MatchOp : Idr_MatchOpBase<"match", MaxSizedRegion<1>, [/* ... */],
                                  [Idr_ReadsMemo<"scrutinee">]>;
```

`RecursiveMemoryEffects` stays on every region op: upstream's known-case
inlining refuses an op without it
(`lib/Interfaces/ControlFlowInterfaces.cpp:1224-1228`, read; 04 C50).

**Closures** (`IdrClosureOps.td:37-215`, read):

```tablegen
def Idr_ClosureOp : Idr_Op<"closure", [AlwaysSpeculatable],
    [Idr_Takes<"captures">, Idr_BuildsCell<"result">]>;   // [DP-31 A: no Idr_BuildsCell]
def Idr_ForceOp : Idr_Op<"force", [Idr_RunsLabelsOpInterface, Idr_RunsUnknown]>;
def Idr_ApplyOp : Idr_Op<"apply", [CallOpInterface, Idr_RunsLabelsOpInterface, Idr_RunsUnknown]>;
def Idr_MemoRunOp : Idr_Op<"memo.run", [RecursiveMemoryEffects, SingleBlock /* ... */]> {
  let arguments = (ins Arg<Idr_MemoCell, "", [MemRead<Idr_Memo>, MemWrite<Idr_Memo>]>:$cell,
                       Idr_TagAttr:$tag);
}
```

`force` today writes Crash, Divergence and IO but reads nothing
(`IdrClosureOps.td:101-103`), so `performsIO(force)` is false and MoveOut
special-cases it (02 E31; 04 C27); `apply` declares nothing, which MLIR
reads as unknown (02 E32). Both become `Idr_RunsUnknown`, the atoms'
"everything".

**Arrays and buffers** (`IdrArrayOps.td:288, 314, 334, 362-428`,
`IdrIOOps.td:138-213`, `lib/IR/OpsArrays.cpp:78-84`, read): every operand
and result decorator that names no resource today names the root
(*measured* below); each names `Idr_Heap` instead, and the two updates' hand
bodies become decorators:

```tablegen
def Idr_ArrayUpdateOp : Idr_ArrayOp<"update", [RecursiveMemoryEffects, SingleBlock,
                                               Idr_UpdateOpInterface]> {
  let arguments = (ins Arg<Idr_ArrayValue, "", [MemRead<Idr_Heap>, MemWrite<Idr_Heap>]>:$array,
                       Variadic<I64>:$indices /* , world under DP-02 B */);
}
def Idr_BufferStoreOp : Idr_BufferAccessOp<"buffer_store", [/* guard marks */]> {
  let arguments = (ins Arg<Idr_ByteBuffer, "", [MemWrite<Idr_Heap>]>:$buffer, I64:$offset,
                       AnyTypeOf<[I8, I16, I32, I64, F64]>:$value /* , world under DP-02 B */);
}
```

*Measured* (TableGen's records: `llvm-tblgen --dump-json -I
.toolchain/llvm-project/mlir/include -I foreign/idr/include
foreign/idr/include/idr/IR/IdrRuntime.td`, read by `python3 -I` scripts in
`/tmp/p0-effects-scripts/`, outside the repository): 51 ops carry a value
effect on the root today: 35 allocate their result only (the `big.*` and
`str.*` builders, `cell.new`, `handle.string`, `io.arg`, `io.get_line`,
`io.strerror`, `nat.from_big`), 5 write an operand (`cell.init`,
`dest.write`, `io.buffer_set_string`, `io.buffer_store`, `io.read_bytes`),
3 read one (`array.get`, `io.buffer_load`, `io.write_bytes`), 3 read and
write one (`array.set`, `dup`, `io.buffer_copy`), 2 read, write and free
one (`drop`, `take`), and `array.new`, `io.buffer_get_string`,
`cell.recycle` one each. Over all 189 ops, by kind and resource: 80
op-level `Write` and 70 op-level `Read` on `IOResource`, 38 value
`Allocate`, 11 value `Write`, 9 value `Read` and 3 value `Free` on the
root, 9 `Write` on `CrashResource`, 2 `Write` on `DivergenceResource`, 2
`Allocate` on `LinResource`, 1 on the frame.

**Calls, functions, returns** (`IdrOps.td:105-240`, read):

```tablegen
def Idr_CallOp : Idr_Op<"call", [CallOpInterface,
        DeclareOpInterfaceMethods<SymbolUserOpInterface> /* , flow, asm names */],
    [Idr_Summarized, Idr_Takes<"args">, Idr_FreshIfLinear<"results">]> {
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$args,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs,
                       Idr_SummaryProp:$effects);
}
def Idr_ReturnOp : Idr_Op<"return", [HasParent<"FuncOp">, ReturnLike, Terminator],
                          [Idr_Takes<"operands">]>;
// A definition, never executed: its effects are its calls'. The build-time
// check of 1.10 (b) exempts an op with FunctionOpInterface or SymbolTable,
// as it exempts idr.program.
def Idr_FuncOp : Idr_Op<"func", [/* ... */ FunctionOpInterface, IsolatedFromAbove]> {
  let arguments = (ins /* ... */ UnitAttr:$total, Idr_SummaryProp:$effects /* ... */);
}
```

**The forged world** (`IdrIOOps.td:220-232`, read): `[DP-02 B]` `world.new`
lists `Idr_Forges`; `[DP-02 A]` it is replaced by a region op
`io.unsafe_run` with `RecursiveMemoryEffects`, whose effects are its body's
where the value is demanded (5.8 DS2.1, `5.8-dialect-design.md:1048`).

### 1.8 The summary property, and its one seed

`idr.func` and `idr.call` hold `effects : Idr_SummaryProp`, a property over
the generated `Summary` enum, default every atom (`Idr_AnyEffect`'s atoms),
printed bare (`effects<io, crash>`) and not at the default, as today
(`IdrOps.td:162-163, 219-220`, read). It is inherent, never discardable
(AGENTS.md). The one input of a summary that is not an op is Idris's proof:
a function without `total` may run its own loops forever, so its summary
holds `diverge` (`lib/IR/Func/Func.cpp:190`, read; 06 §6: "`diverge` is
'not `total`'"; 05 R14: essential). The source names it once:

```tablegen
// A function without Idris's proof of termination may run its own loops
// forever: its summary holds this atom besides its ops'.
def Idr_NotTotal : Idr_SummarySeed<"total", Idr_AtomDiverge>;
```

### 1.9 What LLVM is told

From the same records (12 T2; 0003's owed "function facts lowered"):
- a runtime call (`llvm.call` of an op's runtime function): `memory_effects`
  from the op's effects, each node's effects going to the locations of the
  atom that summarizes it, `ArgMem` for an effect that names an operand;
  `will_return` unless an effect lands on a run-stopping atom; `no_unwind`
  always, since no unwinding exists in the language (a crash is `_exit`,
  `runtime/Io/Ending.cpp:66-71`; *conjecture* that no runtime function lets
  a C++ exception out, which the audit of 4.4 confirms); `noreturn` for a no-successor terminator's
  function, as today (12 CV-15);
- a function: `memory_effects` from its summary's atoms (value-less, so a
  heap atom goes to both `argMem` and `other`), `will_return` unless the
  summary holds a run-stopping atom, `no_unwind` always, and
  `mustprogress` (through `passthrough`: the LLVM dialect has no
  `mustprogress` function attribute at the pin; only a loop annotation's
  `mustProgress`, `include/mlir/Dialect/LLVMIR/LLVMAttrDefs.td:314`, read)
  unless the summary holds `diverge`. That is DP-01's option C for free:
  LLVM deletes an effect-free endless loop only where Idris proved there is
  none (12 §6).

The locations per atom are *conjecture* to be checked by the runtime audit
(4.4): the IO atoms name `other` because the runtime's buffers become
module globals once its bitcode is linked in (lane 13's prepared bitcode),
so `inaccessibleMem` alone would be false after linking; they name
`inaccessibleMem` and `errnoMem` too because the runtime calls the C
library.

### 1.10 What the source refuses at build time

`idris-mlir-tblgen` checks, over the records, before anything is
generated (each is a fatal TableGen error naming the record; lane 14 TD1's
"one fixture per refusal" covers them):
- (a) an `idr` op that lists `DeclareOpInterfaceMethods<MemoryEffectsOpInterface>`
  or `ConditionallySpeculatable` methods by hand: an effect is declared,
  never written;
- (b) an `idr` op that declares nothing: no ODS effect, no rule, not
  `Pure`/`NoMemoryEffect`, not `RecursiveMemoryEffects`, unless it is a
  definition (`FunctionOpInterface`, `SymbolTable`). Today `apply` is such
  an op (02 §2.2);
- (c) an op with both ODS effects and rules;
- (d) an effect that names a value on a non-addressable node (upstream
  aborts at run time, `SideEffectInterfaces.h:339-343`; we refuse at build),
  and an addressable node under a non-addressable one (`:164-173`);
- (e) a no-successor terminator (other than upstream's `ub.unreachable`)
  without an effect on a run-stopping atom's node;
- (f) coverage: every kind any op declares on a node is among the effects
  of the atom that summarizes that node (so the summary never drops a
  kind), and only `Allocate` lands on `Fresh` or the frame;
- (g) every rule's group names an operand or result group of its op, as
  `Idr_Guarded` already requires of its operand names (`IdrBase.td:295-308`,
  read);
- (h) under DP-03 eff-Q4 (b): no op writes `RuntimeState` without writing
  `IO`, so every change of runtime state is IO.

## 2. Everything generated from it, and where it goes

| artifact | generator | output | read by |
| --- | --- | --- | --- |
| `getEffects` of every op whose class decides its effects (175 of 189; `func` and `program`, definitions, have none) | `mlir-tblgen -gen-op-defs` (upstream, unchanged) | `IdrOps.cpp.inc` | MLIR's interface; the API's instance path |
| `getEffects` and `getSpeculatability` of the 14 typed ops | one hand C++ trait, `TypedEffects`, over the generated rule tuples | `Traits.h` (the trait), `EffectFacts.h.inc` (the tuples) | the same |
| the tree: `Node` enum, resource classes, constexpr tables (parent, ancestors, descendants, addressable, summarizing atom, locations, names) | `idris-mlir-tblgen -gen-effect-tree` (new) | `include/idr/IR/EffectTree.h.inc` | the API, the lowering |
| `Summary` enum, `stringify`/`symbolize`, the property's print form | `mlir-tblgen -gen-enum-decls/defs` over `Idr_Summary` (upstream) | `IdrEnums.h.inc` | func and call, idr-expect's `effects` argument |
| one constant per op class, `Of<OpT>` (its effect set, exact or upper bound, recursion, speculation class), and `EffectRules<OpT>` | `idris-mlir-tblgen -gen-effect-facts` (new) | `include/idr/IR/EffectFacts.h.inc` | `OpT::effects()`, the API, the lowering, idr-expect |
| the projection table and the two-way checks | `-gen-effect-tree` | `EffectTree.h.inc`, `static_assert`s in it | the API, the writer, the verifier |
| LLVM attributes of a runtime call | computed `constexpr` from `Of<OpT>` and the tree tables in the lowering | none | `Runtime::call` (12 T1, T2) |
| LLVM attributes of a function | computed from the summary in the lowering | none | the lowering's function step |
| C prototypes' `noreturn` | `-gen-runtime-abi-decls`, from the terminator fact | `idris_rt_ops.h` | the runtime |
| the Idris side's IO primitives | `-gen-idris-dialect`, from the world constraint or the `idrisIO` field | `compiler/src/IdrisMLIR/Dialect/Idr.idr` | the frontend |

Every new backend reads ODS through `mlir::tblgen::Operator` and
`mlir::tblgen::SideEffect` (`include/mlir/TableGen/SideEffects.h:24-36`,
read), the same wrappers mlir-tblgen's own effect generator iterates
(`OpDefinitionsGen.cpp:3499-3616`, read), so the constant and the generated
`getEffects` are two readings of one set of records (5.2 F2, M12;
`5.2-mlir-ods.md`). One gap: an ODS effect keeps only its resource's C++
class name, as a string (`string resource = resourceReference.name;`,
`include/mlir/Interfaces/SideEffectInterfaceBase.td:165-181`, read;
`tblgen::SideEffect::getResource()` returns that string,
`include/mlir/TableGen/SideEffects.h:36`, read), so a backend cannot reach
the `Idr_Node` record an effect names. Resolving the string back to a
record is a string standing for a thing (the skill; 14 T06 counts twenty
such compares in the backend today). The fix is upstream's: patch U4 (7.2)
keeps the record beside the name. Until the pin moves past it, the patch
is carried; there is no string lookup of ours.

### 2.1 The tree in C++

```cpp
// EffectTree.h.inc, generated by idris-mlir-tblgen -gen-effect-tree. Do not edit.
namespace idr::effects {

enum class Node : std::uint8_t { Root, Frame, Heap, Count, MemoState, Fresh, IO, Halt,
                                 Divergence, RuntimeState, Forge };
inline constexpr unsigned numNodes = 11;

// The base of our nodes: upstream's Resource, and which Node it is.
class NodeResource : public mlir::SideEffects::Resource {
public:
  virtual Node node() const = 0;
protected:
  explicit NodeResource(mlir::TypeID id) : Resource(id) {}
};

// Each of our nodes: its parent and addressability, as the source says.
struct IO : mlir::SideEffects::Resource::Base<IO, NodeResource> {
  Node node() const final { return Node::IO; }
  llvm::StringRef getName() const final { return "idr.io"; }
  mlir::SideEffects::Resource *getParent() const final {
    return mlir::SideEffects::DefaultResource::get();
  }
  bool isAddressable() const final { return false; }
};
struct Halt : mlir::SideEffects::Resource::Base<Halt, NodeResource> {
  Node node() const final { return Node::Halt; }
  llvm::StringRef getName() const final { return "idr.halt"; }
  mlir::SideEffects::Resource *getParent() const final { return IO::get(); }
  bool isAddressable() const final { return false; }
};
// ... one per node of ours.

// The tree as constants, indexed by Node.
inline constexpr std::array<Node, numNodes> parent = {/* ... */};
inline constexpr std::array<Nodes, numNodes> ancestorsOrSelf = {/* ... */};
inline constexpr std::array<Nodes, numNodes> descendantsOrSelf = {/* ... */};
inline constexpr std::array<bool, numNodes> addressable = {/* ... */};

// The Node of a resource an effect names: ours carry it; upstream's two
// adopted nodes are compared; any other resource is the root (anything).
Node nodeOf(const mlir::SideEffects::Resource *resource);

} // namespace idr::effects
```

`nodeOf` is one virtual call for our nodes (upstream's `Base<Derived,
BaseResource>` takes a parent class, as `AutomaticAllocationScopeResource`
does, `SideEffectInterfaces.h:198-202`, read) and two pointer compares for
upstream's. Resources stay function-local static singletons
(`SideEffectInterfaces.h:100-104`, read), so nothing is allocated and
nothing locks.

### 2.2 Each op's `getEffects`

- *Static ops:* mlir-tblgen, one `effects.emplace_back(...)` per
  declaration (`OpDefinitionsGen.cpp:3559-3616`, read). No hand body
  remains: the 9 today (`memo.run`, `array.update`, `element.update`,
  `match`, `field`, `tag`, `con`, `own.give`, `call`; 03 W1) and the one
  trait body (`ConsumesOperands`, `Traits.h:84-91`) become decorators or
  rules; `VectorizeLanesOp` (`lib/Target/Schedules.cpp:303-308`) lists
  upstream's `FunctionalStyleTransformOpTrait` (02 E51); `NeverRuns`
  (`lib/IR/FlowOps.cpp:344-346`) goes with the `ub.unreachable` patch
  (7.2).
- *Typed ops:* the generator writes each op's rules as types, as it writes
  `Guarded<Op>` for the guards today (`include/idr/IR/Traits.h:132-144`,
  read), and the trait expands them at compile time. Positions are ODS
  operand indices resolved by the generator; nothing is looked up per
  query.

```cpp
// EffectFacts.h.inc (generated):
template <> struct EffectRules<idr::ConOp> {
  using type = std::tuple<Rule<IfOwned, Operands<0>, Read<Node::Count>, Free<Node::Count>>,
                          Rule<IfCellPointer, Results<0>, Allocate<Node::Heap>>>;
  using speculation = std::tuple<NotSpeculatableIf<IfCellPointer, Results<0>>,
                                 NotSpeculatableIf<IfOwned, Operands<0>>>;
};

// Traits.h (the one hand getEffects of the dialect):
template <class ConcreteOp>
class TypedEffects : public mlir::OpTrait::TraitBase<ConcreteOp, TypedEffects> {
public:
  void getEffects(llvm::SmallVectorImpl<mlir::MemoryEffects::EffectInstance> &effects) {
    std::apply([&](auto... rule) { (rule.emit(this->getOperation(), effects), ...); },
               typename EffectRules<ConcreteOp>::type{});
  }
};
```

`Rule<When, Position, Effects...>::emit` loops over the position's values,
asks `When::holds(value.getType())` (or, for `FromSummary`, reads the
property), and emplaces each effect on the value; one hand-written
predicate per type condition, four in all.

### 2.3 Compile-time constants per op class

```cpp
// EffectFacts.h.inc (generated), for every idr op class:
template <> struct Of<idr::PutStrOp> {
  static constexpr EffectSet may{.read = {Node::IO}, .write = {Node::IO}};
  static constexpr bool exact = true;       // no typed rule
  static constexpr bool recursive = false;  // not RecursiveMemoryEffects
  static constexpr Speculation speculation = Speculation::Never;
};
template <> struct Of<idr::ConOp> {
  static constexpr EffectSet may{.read = {Node::Count}, .free = {Node::Count},
                                 .allocResult = {Node::Heap}};  // every rule's effects
  static constexpr bool exact = false;      // which rule fires is the instance's types'
  static constexpr bool recursive = false;
  static constexpr Speculation speculation = Speculation::Typed;
};
```

Typed code reads the fact on the op class, as the task asks (`OpT::...`):
the trait every `Idr_Op` lists (`Idr_DeclaredEffects`) gives

```cpp
template <class ConcreteOp>
class DeclaredEffects : public mlir::OpTrait::TraitBase<ConcreteOp, DeclaredEffects> {
public:
  static constexpr EffectSet effects() { return Of<ConcreteOp>::may; }
  static constexpr bool exactEffects() { return Of<ConcreteOp>::exact; }
};
```

and an op interface, the one way `Operation *` code reaches the constant
without building an instance list (the new AGENTS.md rule: the set of a
static op is known when the compiler is built, so it is returned, not
rebuilt per query; the op set is open to `Operation *`, so an interface is
the sanctioned dispatch, F DP-08):

```tablegen
def Idr_EffectFactsOpInterface : OpInterface<"EffectFactsOpInterface"> {
  let cppNamespace = "::idr::effects";
  let methods = [
    InterfaceMethod<"The op's own effects as one set: its class's constant, or its rules applied "
                    "to its types; the bodies of a RecursiveMemoryEffects op are not in it.",
                    "::idr::effects::EffectSet", "getEffectSet", (ins),
                    [{ return ::idr::effects::ownSet<ConcreteOp>($_op); }]>];
}
def Idr_DeclaredEffects : TraitList<[Idr_EffectFactsOpInterface,
                                     NativeOpTrait<"DeclaredEffects">]>;
```

`ownSet<OpT>` returns `Of<OpT>::may` when `Of<OpT>::exact`, and otherwise
folds the rules into masks directly, emplacing nothing.

Every one of the 119 runtime ops is exact (*measured*, 4.4: none has a
typed rule), so every runtime call's LLVM attributes are compile-time
constants.

### 2.4 The summary's derivation table and its two-way check

Generated into `EffectTree.h.inc`:
- `project[kind][node][namesValue] -> Summary` (1.4's rule, as a table);
- `callEffects[atom]`, the effects a call holding the atom declares
  (from `Idr_Atom.effects`);
- `static_assert`s, evaluated when the compiler is built:
  - *round trip:* for every atom *a*, projecting `callEffects[a]` gives
    exactly *a*;
  - *never less:* for every kind and node with an atom above or below,
    each atom it projects to sits on an ancestor-or-self (or a descendant,
    for the root's case) and carries the kind; since an effect on an
    ancestor conflicts with everything an effect on its descendant
    conflicts with (1.2), a call's declared effects conflict with
    everything its callee's ops conflict with;
  - *the seed:* `Idr_NotTotal`'s atom stops a run from returning.

1.10 (f) checks the other direction, over the op records: no op declares a
kind on a node that its summarizing atom does not carry.

### 2.5 The lowering's LLVM attributes

```cpp
// Computed when the compiler is built, for every runtime op class.
template <class OpT>
  requires StaticEffects<OpT>
consteval LLVMCallFacts llvmFactsOf() { return llvmFacts(OpT::effects()); }
```

`Runtime::call<OpT>` (12 T1) writes `memory_effects`, `will_return` and
`no_unwind` from it; the function step writes the function's attributes
from its summary property (the summary, not a walk of its ops: the new
rule's "the function summary is derived once and verified, never re-walked
by readers"). The attributes reach LLVM at translation whatever MLIR does
with them. For MLIR's own canonicalize and CSE after the lowering
(`Pipeline.cpp:167-168, 181-182`, read via 12 §3.1) to read them,
`llvm.call` must implement `MemoryEffectOpInterface`, which it does not at
the pin (`include/mlir/Dialect/LLVMIR/LLVMOps.td:821-826`, read: its
interfaces are `FastmathFlagsInterface`, `CallOpInterface`,
`SymbolUserOpInterface`); that is upstream patch U1 (7.2).

Where the function attributes are written is lane 12's (its phase 0
rebuilds `idr.func` as `func.func` and drops its facts, 12 CV-05): if the
lowering goes through `func.func`, a discardable `llvm.*` attribute would
carry a fact between two passes, which AGENTS.md forbids; the facts must be
written on `llvm.func`'s inherent attributes (`memory_effects`,
`will_return`, `no_unwind`, `passthrough`, `LLVMOps.td:2126-2148`, read) by
the step that makes it. A dependency on lane 12, not a choice of this
design.

### 2.6 The Idris side's view

What the Idris side knows of effects today is one fact: which primitives
are IO, read off `PerformsIO` (`tools/idris-mlir-tblgen.cpp:1481`, read),
with the result shape read off the world operands (`:1445-1458`, read); it
reads no `SideEffect` (14 §2, W5: "It reads no effect"). `PerformsIO` is
exactly "takes or gives a world" (80 = 80 ops, 02 F1, *measured* by lane
02). Two facts are in play, and they are different facts (the skill's
Brooks limit):
- *Idris's sequencing:* whether the primitive is in `IO` in Idris's type,
  so the frontend threads it. `handle.string` is pure to Idris
  (`compiler/src/IdrisMLIR/Registry/Primitives.idr:373-375`, read) yet
  reads runtime state; `io.strerror` is IO to Idris yet, under DP-03
  eff-Q4 (b), only reads runtime state.
- *MLIR's ordering:* the op's effects.

So the generated boundary carries Idris's fact and no effect: under DP-02
B, `IOPrim` is "has a world operand or result", which the generator already
reads (02 E9); under DP-02 A, it is the family's `bit idrisIO` (1.7), set
once on the IO family classes. Nothing on the Idris side restates an
effect, and nothing would gain from one (14 §1: "none today, as far as the
emitter reads"). `Emit/Monad.idr:81`'s hand copy of "the world is linear by
its type" (14 E01) goes with DP-02 A, or becomes a generated fact under B
(lane 14 TD5). The `IOPrim` sum is unchanged in content under B (02 §8).

### 2.7 idr-expect's properties

Every property that reads an effect is restated as a call to the API
(names and argument shapes kept, as T-Q3 leaves open; 19 C1):

| property (`lib/Transforms/Expect/Lookup.cpp`) | today's reading (read) | over the API |
| --- | --- | --- |
| `crash-sites` (:193) | `NoReturn` ∪ `GuardOpInterface` ∪ an LLVM `noreturn` call (`CrashSites.cpp:24-37`) | ops whose `Of<OpT>::may` touches `Halt`, the set computed at compile time over `GET_OP_LIST`; at the LLVM level, the `noreturn` the lowering wrote from the same constant |
| `computes-nothing` (:230) | `GuardOpInterface`, `ub.unreachable`, `NoReturn`, terminators (`ComputesNothing.cpp:26`) | `atMostHalts(op)`: every effect on `Halt`'s subtree or an own-result allocation |
| `no-heap-allocation` (:34) | `Allocate` but `LinResource` and the frame, plus `isa<ClosureOp>`, `isa<SuspendOp>` (`Allocation.cpp:28-41`) | an `Allocate` in `Heap`'s subtree (a tree fact; the closure cases go under DP-31 B) |
| `reads-nothing`, `writes-nothing` (:221-222) | `Read`/`Write` but on the frame (`Memory.cpp:44-60`) | no `Read`/`Write` in `Heap`'s subtree |
| `counts-nothing` (:56) | `isa<DupOp, DropOp>` (19 E7) | no effect on `Count` |
| `builds`, `builds-nothing` (:127) | `BuildsValue` (`Does.cpp:33-34`) | an `Allocate` on `Heap` of the op's own result (DP-31 B), else the trait stays test-only (02 E45) |
| `crashes-before-output` (:164) | `orderOf`'s hand bits (`Placement.cpp:78-92`) | `of(op)` against `IO` and `Halt` |
| `effects` (:226) | the `Effect` bits (`SolvedEffects.cpp:29-33`, `Arguments.cpp:295-298`) | the `Summary` atoms, parsed by the generated `symbolizeSummary` |
| `folded` (:82) | `isMemoryEffectFree` (`Folded.cpp:32`) | the same upstream query, through the API |
| `test-idr-facts` | `onlyAllocates`, `performsIO` (`Facts.cpp:38-41`) | deleted with the old classifiers (19 E19) |
| contracts `effects-not-widened`, `crash-sites-not-added` | `Effect` bits, `writeEffects` (`Contracts.cpp:164-246`) | the summary and the API |

### 2.8 Nothing else may restate an effect

The rule P0 records: an effect fact is declared in `IdrEffects.td` or on an
op's record and read through `idr::effects::` (section 3); no other C++ or
Idris names a resource, reads an `EffectInstance` list, or maps between
bits and resources. What enforces it:
- the representation: our resources exist only as generated classes and
  the `Node` enum, the summary only as the generated `Summary`; deleting
  today's six structs and `Effect` breaks every old reader at compile time
  (the cutover cannot leave one behind);
- 1.10's refusals, so no op can write its effects by hand;
- review: a handoff that reads effects outside the API is sent back (the
  skill's "a hunk that adds control flow and names none of these").

## 3. The one C++ query API

`include/idr/IR/Effects.h` and `lib/IR/Effects/`, replacing
`include/idr/IR/Flow.h:81-111`, `include/idr/IR/Func.h:30-59`,
`include/idr/Analysis/Effects.h` and `lib/IR/Effects.cpp`.

### 3.1 The values

```cpp
namespace idr::effects {

// A set of nodes: one bit each (11 today; never more than 16).
class Nodes {
public:
  constexpr Nodes() = default;
  constexpr Nodes(std::initializer_list<Node>);
  constexpr bool any() const;
  constexpr Nodes operator|(Nodes) const;
  constexpr Nodes operator&(Nodes) const;
  constexpr Nodes up() const;    // every ancestor-or-self of a member
  constexpr Nodes down() const;  // every descendant-or-self of a member
private:
  std::uint16_t bits = 0;
};

// What an op, or everything in it, may do, without the values: per kind,
// the nodes acted on. Two sets conflict when a write or free in one lands
// on an ancestor-or-self or descendant-or-self of anything in the other.
struct EffectSet {
  Nodes read, write, free, allocResult, allocOther;
  bool unknown = false;   // an op of another dialect that declares nothing

  static constexpr EffectSet everything();
  constexpr EffectSet operator|(EffectSet) const;
  constexpr bool conflicts(EffectSet other) const;
  constexpr bool deadIfUnused() const;    // upstream's wouldOpBeTriviallyDead, as a set
  constexpr bool onlyAllocates() const;   // dead if unused, and reads nothing
  constexpr bool touches(Node) const;     // an effect in the node's subtree
  constexpr bool on(Node) const;          // an effect on the node itself
};

// One effect with its value, for the questions that ask about one value.
struct Effect {
  Kind kind;
  Node node;
  mlir::Value value;  // null for an op-level effect
};

// What a run of a function may do: the generated atom enum.
using Summary = ::idr::effects::Summary;

} // namespace idr::effects
```

### 3.2 Concepts, and the typed path

```cpp
// An op class with generated effect facts: every idr op, read off its
// trait (an ODS fact), never a list of ops.
template <class OpT>
concept Declared = OpT::template hasTrait<OpTrait::DeclaredEffects>();

// One whose effects are its class's alone: no typed rule, no body.
template <class OpT>
concept StaticEffects = Declared<OpT> && Of<OpT>::exact && !Of<OpT>::recursive;

// A type condition of a typed rule (one of Idr_When's four).
template <class W>
concept When = requires(mlir::Type type) { { W::holds(type) } -> std::same_as<bool>; };

// A question about single effects, for the one classifier (3.5).
template <class Q>
concept Question = std::predicate<const Q &, const Effect &>;

// A filter on calls, for the summary solve's SCCs (3.6).
template <class F>
concept CallFilter = std::predicate<const F &, CallOp>;

// The typed path: a constant where the class decides, the instance's
// rules where its types do, the body where it has one.
template <Declared OpT>
EffectSet of(OpT op, Cache *cache = nullptr) {
  if constexpr (StaticEffects<OpT>)
    return OpT::effects();
  else
    return detail::ofInstance(op.getOperation(), cache);
}
template <StaticEffects OpT> consteval bool deadIfUnused() { return OpT::effects().deadIfUnused(); }
template <StaticEffects OpT> consteval bool performsIO() { return OpT::effects().on(Node::IO); }
```

A rewrite pattern over a typed op asks `if constexpr
(effects::deadIfUnused<OpT>())` and the branch vanishes from every
instantiation the class decides; the folds over `GET_OP_LIST` the
lowering already uses (`lib/Conversion/RuntimeCalls.cpp:146-165`, read;
02 §3.3 B4) read the same constants.

### 3.3 The untyped path

```cpp
// The op's own set, and its bodies' for a RecursiveMemoryEffects op. One
// dispatch: our ops answer through EffectFactsOpInterface (a constant, or
// their rules); an op of another dialect through MemoryEffectOpInterface,
// its instances folded into a set; an op with neither, and no recursion,
// is everything. A body's set is computed once per op and kept in `cache`
// for as long as the analysis that owns it lives (3.7).
EffectSet of(mlir::Operation *op, Cache *cache = nullptr);

// Each effect with its value, own and nested as above: the questions that
// ask about one value (3.4) read this, never a set.
template <std::invocable<const Effect &> F>
void forEach(mlir::Operation *op, F &&visit);

// The pass-scoped cache of region ops' sets, an AnalysisManager analysis
// per function, invalidated by the pass manager like any other.
class Cache {
public:
  explicit Cache(mlir::Operation *function);
  EffectSet of(mlir::Operation *regionOp);
};
```

### 3.4 The questions

Every question is one function over `EffectSet` (or over `forEach` for a
value); the typed and untyped paths only differ in how the set is had.

| question | API | today, deleted or rewritten (read) |
| --- | --- | --- |
| does it perform IO | `of(op).on(Node::IO)` | `performsIO` (`lib/IR/Effects.cpp:137-142`, keyed on a `Read` of `IOResource`) |
| is it ordered with output | `of(op).touches(Node::IO)` | `orderOf` (`Expect/Placement.cpp:78-92`), `mayRunAt`'s `isa<IOResource>` (`lib/IR/Effects.cpp:173`) |
| may it crash; may it not end | `touches(Node::Halt)`; `touches(Node::Divergence)` | `isa<MayCrashOpInterface>` (`Func.cpp:194`, `Forms.cpp:52`), `NoReturn ∪ Guard` (`CrashSites.cpp:28`) |
| at most a crash | `atMostHalts(op)` | `atMostCrashes` (`Forms.cpp:46-63`) |
| dead if unused | `deadIfUnused(op)`, which for an op not ours is upstream's `wouldOpBeTriviallyDead` | — (upstream's stays the one reading) |
| only computes | `of(op).onlyAllocates()` | `onlyAllocates` (`lib/IR/Effects.cpp:129-133`) |
| may A move past B | `!of(a).conflicts(of(b))`, and no write or free by B of a value A reads | `mayRunAt` (`lib/IR/Effects.cpp:161-184`), `Reshape::movable` (`Reshape.cpp:291-306`) |
| does it write this value | `writes(op, value)` over `forEach` | `Placement::writes` (`Ownership/Placement.cpp:152-161`), `OwnedWalk::writes` (`Verify/Owned.cpp:191-210`), `storedBy` (`Verify/Uses.cpp:52-65`) |
| does it allocate this result | `allocates(op, value)` | `hasEffect<Allocate>(op, value)` (`Verify/Owned.cpp:107`, `Verify/OwnedOps.cpp:226`) |
| does it consume this operand | `consumes(operand)`: a `Free` on `Count` on it | `consumes` (`lib/IR/Effects.cpp:86-90`, rebuilding flow edges per operand), four other readings (08 §2.6) |
| what does a call or function do | `call.getEffects()`, `fn.getEffects()` (the property) | the `Effect` bits read directly (02 §2.5's readers) |
| does a label's run observe the outside | `summary` holds `io` | `observableRuns` (`Analysis/Effects.cpp:49-96`) via `ObservableIO` |

### 3.5 The one classifier

Today there are two: `classify` (`lib/IR/Effects.cpp:113-127`, a
`function_ref` predicate over `getEffectsRecursively`) and MoveOut's own
`Does`, `doesOf` and walk (`lib/IR/Canon/MoveOut.cpp:59-101`), which
disagree on `ub.unreachable` and special-case `force` (02 E34, E35; 04 C26,
C27). One remains:

```cpp
enum class Does : std::uint8_t { Computes, Effects, Touches };  // ordered: a step past the one before

// What `op`, with everything in it, does toward the asker's question:
// Touches when an effect answers the question (or nothing is known),
// Effects when it has any effect but an allocation of its own results,
// Computes otherwise. Region ops' sets come from `cache`.
template <Question Q>
Does classify(mlir::Operation *op, const Q &touches, Cache *cache = nullptr);
```

MoveOut's question is one instance (`[&](const Effect &e) { return
e.value && unrestricted(e.value.getType()) == array; }`, together with
`touches(Node::IO)` on the set); its `ub.unreachable` case goes with the
upstream patch U2 and its `isa<ForceOp>` with `force`'s declared
`Idr_RunsUnknown` (1.7). `onlyAllocates` and `performsIO` are set
questions, not instances of `classify`.

### 3.6 Derive, project, write

```cpp
// The one derivation of a function's summary: the projection of every op's
// own effects, at every depth (into the bodies of RecursiveMemoryEffects
// ops), each call by the summary it holds, and the seed (`total`). The
// solve passes a filter that leaves out calls of its SCC's members; the
// verifier passes none.
template <CallFilter Skip = NoSkip>
Summary derive(FuncOp fn, const Skip &skip = {});

// What an effect set is to a summary: the generated table.
constexpr Summary project(EffectSet set);

// The one writer: each function's summary, and every call's, from derive,
// over the program graph's SCCs callees first (05 T5.1, T5.3), starting
// from `changed` and moving to callers only while a summary changes.
void write(ProgramGraph &graph, llvm::ArrayRef<FuncOp> changed);
```

`derive` never asks `isa<CallOp>`: a call's own set is its summary's call
effects (its `Idr_Summarized` rule), which project back to the summary
(2.4's round trip); consumption and fresh results project to nothing
(1.4). Before defunctionalization, the solve that decides `by_name` (F
DP-50, 06 T3) instantiates `derive` with a filter that treats a label
runner as calls of the labels the label solve gives it, instead of its
declared `Idr_RunsUnknown`; defunctionalization then replaces each runner
by a dispatch of those calls, after which the plain derivation gives the
same summaries. That refinement lives in the solver, never in an op's
effects.

### 3.7 What is genuinely dynamic, and why (the new AGENTS.md rule)

Every effect fact not in this table is a compile-time constant: the tree,
the atoms, the projection and LLVM tables, and the effects of every op
whose class decides them (175 of 189 classes, all 119 runtime ops). Each
dynamic fact below says why it is not static, and what it costs.

| fact | why it is not static | carrier and cost |
| --- | --- | --- |
| which typed rule fires on a `con`, `field`, `tag`, `match`, `closure`/`suspend`/`delay`, consuming op, `call` | it depends on the instance's operand and result types (a box or a sum, owned or not, a memo sum, linear), fixed when the op is built | the types carry it: one `When::holds` per rule per value, a TypeID compare or a bit the type computed at construction (01 C5's recursive facts); positions are generated indices, so nothing is rebuilt (today's flow-edge rebuild per query, 02 E53-E54, goes) |
| a call's effects | they are its callee's summary, which changes as the callee's body changes | the call's `effects` property: read in O(1); written by the one writer; verified equal to the callee's (4.1 V2) |
| a function's summary | its body is IR that passes rewrite | the `effects` property: derived once per change by the writer, read in O(1) by every reader, re-derived only by the verifier to check it (AGENTS.md's verified property) |
| a region op's effects (`match`, `match_lit`, `memo.run`, `tabulate`, `tabulate_io`, `fold_last`, `scan_last`, `array.update`, `element.update`; 02 §2.2) | their bodies are IR that passes rewrite; and the trait that makes them their bodies' is load-bearing for upstream's inliner (04 C50) | our readers: computed once per op per analysis lifetime (`Cache`, 3.3; 5.6 E3's Flang cache, `AliasAnalysisRecursiveEffectsCache`). Upstream's own walkers (DCE pays only for an unused match, `isOpTriviallyDead` checks uses first, 04 D3; CSE asks `isMemoryEffectFree` of each candidate, `lib/Transforms/Utils/CSE.cpp:264`) stay upstream's; measured (8.4 M5) before U3 (7.2) |
| an op of another dialect | the op set is open to `Operation *` code, and upstream declares it | one `MemoryEffectOpInterface` dispatch (the sanctioned dynamic dispatch, F DP-08) |
| a value-level question (does this op write this value) | which operand is asked is the caller's | the op's instance list, positions static |
| a `GuardedOp`'s speculatability | whether the guarded operand comes from the same guard is the IR's def-use | unchanged (`Traits.h:178-198`) |
| may A move past B | positions in a block | the two cached sets |

And in the compiled program: no effect fact is tested at run time, and the
facts reach LLVM (1.9, 2.5), so a pure runtime call is merged, hoisted and
deleted by LLVM instead of being paid for at every call; today none is (12
CV-05, CV-14), which the new rule forbids.

## 4. The verifier

### 4.1 The rule that makes disagreement impossible

- **V0, before the first solve.** The program's stage records whether
  summaries are solved (a stage fact, the one place the pipeline's phase
  is held, `stageFacts`, `lib/IR/Func/Func.cpp:107`, read). Before, every
  function and call holds the default exactly (the frontend writes none,
  `IdrOps.td:143-150`, read).
- **V1, per function, after every pass, in parallel.** In
  `FuncOp::verifyRegions` (run after the body's ops, in parallel over
  isolated functions, upstream `lib/IR/Verifier.cpp:357-371` via 5.2 H1):
  `derive(fn) ⊆ fn.getEffects()`. A summary never says less than its ops.
- **V2, per call.** In `CallOp::verifySymbolUses`, once per program
  verification from the shared `SymbolTableCollection`
  (`lib/IR/Func/Call.cpp:29-59`, read; 5.2 H5): `call.getEffects() ==
  callee.getEffects()`, equality where today is containment (`:54`). The
  call's property is a cache of one source (5.8 DS2.1's mechanism, today's
  code: 02 §3.5) and only the one writer writes either.
- **V3, the writer's postcondition.** Right after `write`, every summary it
  wrote equals `derive` of its function, asserted; `--idr-contracts`
  (test-only, T-Q4) checks equality after every pass, as a measurement of
  how stale summaries become between writes.
- **V4, at the boundary.** The pipeline runs the writer as the last step
  before the lowering reads summaries, so what LLVM is told equals the
  derivation (no fact the compiler had is thrown away at the boundary, the
  new rule).
- **V5, at build time.** Every op's effects come from the source (1.10).

Together: no reader can see a summary that says less than the ops it
stands for (V1, V2: by induction over the call graph, a call's effects
contain everything its callee's ops do), every reader of a function or a
call reads the same value (V2: one writer), and there is exactly one
derivation (`derive`), which only the writer and the verifier run.

**Where this refines the ruling's wording.** F DP-04 records "a verifier
rule checks that a function's summary equals the derivation from its ops".
V1 is containment after every pass and equality at every write (V3, V4),
for three reasons the owner should see and may overrule:
1. Upstream passes the pipeline runs delete ops that carry effects:
   canonicalize's known-case inlining deletes a match's other regions,
   crashes included (`ControlFlowInterfaces.cpp:1224-1240`, read), and our
   guards fold away inside it; CSE erases trivially dead ops, reads among
   them (`lib/Transforms/Utils/CSE.cpp:303`, read). Neither can call our
   writer.
2. A pass nested on functions may not touch its callers' calls (5.8 B9,
   `5.8-dialect-design.md:264`), so it cannot keep V2 if it changes its
   own summary. So nested passes never write a summary; the writer does,
   at program level.
3. A pass that adds effects (counting adds `count`) would, if it wrote its
   own summary from a nested pass, let a sibling running in parallel read
   a call that says too little. Under V1 such a pass fails verification
   instead, so it must write at program level (or the stage transition
   writes the atom everywhere first and the writer tightens it after).

Equality after literally every pass needs the writer after every pass
that may change a function's effects. The design provides that too: the
pipeline (one TableGen list, drv-Q2) marks each pass that may change
effects, and inserts the writer after it. Its cost is one parallel derive
per function and one serial join over the SCCs per insertion (8.4 M2).
With the writer inserted everywhere, V1 can be tightened to equality
outright; the choice is the owner's (6.8), and nothing else in the design
changes.

### 4.2 Effects only from the source

By construction, not by a run-time check: 1.10 refuses a hand
`getEffects`, an undeclared op, a mixed op, a value on a non-addressable
node, an unaccounted terminator and an uncovered kind; the typed ops'
effects are emitted only by the generated rules, whose union is
`Of<OpT>::may`, so no dynamic effect can fall outside the class's bound;
and the summary's tables are `static_assert`ed (2.4). Nothing here costs
the compiler anything when it runs.

### 4.3 Cost

V1 is one walk per function, one `getEffectSet` per op (a constant for
static ops), in parallel; it replaces `effectsCovered`, which walks every
function twice per program verification on one thread
(`lib/IR/Verify/Program.cpp:53-71`, read; 02 E29), and reads a call's
property where `bodyEffect` read four other facts. V2 is a compare per
call, linear with the shared symbol table. Measured in 8.4 (M2).

### 4.4 The audit of the 119 runtime ops

*Measured* (the records, method as in 1.7), the 119 ops tied to a runtime
symbol, by what they declare:

| group | ops | declared today |
| --- | ---: | --- |
| the IO family (`Idr_IOOp`, platform ops, `io.exit` among them) | 67 | `Read`+`Write` of `IOResource`, `PerformsIO`, `ObservableIO` |
| words, bigs, strings, `handle.is_null` | 46 | no op-level effect: `Pure`, `NoMemoryEffect` with a guard, or only an allocation of the result |
| buffer accessors that call the runtime (`io.buffer_copy`, `_get_string`, `_set_string`) | 3 | value effects on the buffers, `PerformsIO`, no `IOResource` |
| `crash_str` | 1 | `Write` of `CrashResource` and `IOResource` |
| `handle.string` | 1 | `Read` of `IOResource`, no world |
| `io.strerror` | 1 | `Read`+`Write` of `IOResource`, not `ObservableIO` |

No audit of these against the runtime exists (lane 18 checks no declared
effect against its function, its oom-1 row being its one per-op check; 02
§8 names the gap as the risk). It matters
once the heap is apart from IO (CSE then moves heap reads across output)
and once calls carry LLVM attributes (LLVM then reorders and deletes
runtime calls): an under-declared effect becomes a miscompile that today's
coarse model hides. The plan, before the cutover enables either:
1. **A mechanical lower bound.** Build the runtime as the bitcode the
   pipeline links (lane 13's prepared bitcode), run LLVM's own
   attribute inference on it (`opt -passes=function-attrs`), and read each
   `idris_rt_*` function's inferred `memory(...)`, `willreturn`,
   `nounwind`, `noreturn`. LLVM's inference over-approximates what the code
   may do, so for each op compare it with what 1.9 derives from the op's
   declared effects: an inferred write the declaration lacks is an
   under-declaration, to fix; a declared effect LLVM shows absent is a lost
   optimization, to review. Writes to the allocator's own state are
   expected for an op that allocates its result and are listed apart
   (snmalloc's globals, `runtime/Cells.cpp:85-87`, via 18 §2.3).
   *Conjecture* that the inference is precise enough to be useful on the
   46 pure ops and coarse on the IO family (libc calls are opaque).
2. **A review of meaning, family by family,** by the runtime lane (18),
   against each function's documented meaning (AGENTS.md: the runtime's
   documented semantics are a primitive's meaning). Which node each family
   touches, for example: clock readings read and write `IO` (time moves, so
   two readings must never merge; a `Read` alone would let CSE merge them);
   `io.arg` and `io.arg_count` read nothing that changes (argv is fixed,
   `runtime/Start/Entry.cpp:21-22`, via 18 §2.3), so they may be pure in
   MLIR while staying IO to Idris; `io.errno`, `io.env_get`,
   `handle.string`, `io.strerror` are candidates for `RuntimeState` under
   eff-Q4 (b); the big and string functions must touch nothing but their
   operands and their result (to confirm); `put_*` read their operand's
   bytes (an `ArgMem` read).
3. **Output.** Every finding is an edit of the op's record in the one
   source, never a second table. Step 1 becomes a test,
   `tests/runtime-effects`, generated from the records (each runtime symbol
   with the attributes the source implies, against LLVM's inference), run
   on all four targets, since the platform layer differs by target
   (`runtime/Posix/`, `runtime/Io/`; AGENTS.md's four targets).

## 5. What it deletes

Every current reading of effects in the tree: lane 02's inventory (02 §2.4,
§2.5, §7) and this design's own grep at e96bb991 (`grep -rnE
'getEffects\b|getEffectsRecursively|EffectInstance|IOResource|CrashResource|DivergenceResource|LinResource|ReferenceResource|MemoStateResource|DefaultResource|hasEffect<|isMemoryEffectFree|isPure\(|wouldOpBeTriviallyDead|isOpTriviallyDead|isSpeculatable|Effect::(io|crash|diverge|none)|anyEffect|bodyEffect|componentEffects|writeEffects|effectInstances|classify\(|onlyAllocates|performsIO|mayRunAt|consumedEffects|readsMemoState|observableRuns|PerformsIO|ObservableIO|MayCrash|NoReturn|CallsRuntime|holdsWorld|WorldNewOp'
lib include tools unittests`, every hit read). "Deleted" means gone with
nothing in its place but the source; "API" means rewritten to call section
3's functions, its own reading of effects gone.

### 5.1 TableGen

| where (read) | what | disposition |
| --- | --- | --- |
| `IdrInterfaces.td:87-92` | six sibling `Resource` defs | deleted; the tree (1.2) |
| `IdrInterfaces.td:103-117` | `Idr_MayCrashOpInterface`, `Idr_MayCrash` (crash and IO double write) | deleted; `Idr_MayHalt` |
| `IdrInterfaces.td:292-308` | `Idr_PerformsIO`, `Idr_ObservableIO` | deleted; IO is `Idr_DoesIO`, "observable" is `on(Node::IO)`, Idris's sequencing is the world operand or `idrisIO` |
| `IdrInterfaces.td:310-316` | `Idr_ConsumesOperands`, `Idr_ConsumesOnly` | deleted; `Idr_Takes` rules, `AlwaysSpeculatable` listed by the ops that have it |
| `IdrInterfaces.td:318-320`, `IdrBase.td:265-275` | `Idr_Primitive`, `Idr_Runtime` as C++-backed traits | record fields (02 E69, E70); not effects, culled with the marker classes |
| `IdrBase.td:282-287` | `Idr_TakesReference` | deleted; a `Write` on `Count` of the operand (02 E59) |
| `IdrBase.td:289-293` | `Idr_BuildsValue` | deleted under DP-31 B (an `Allocate` on `Heap` of the result); else test-only (02 E45) |
| `IdrAttrs.td:186-209` | `Idr_Effect` bits | deleted; `Idr_Summary` generated from the atoms |
| `IdrCheckOps.td:19, 22, 30-31, 37-39, 75, 88-90` | `Idr_NoReturn` (a terminator under 03 R4), `Idr_MayCrash` on crash, `crash_str`, guards, `nat.to_extent` (`IdrArrayOps.td:441`), the `getCrashCause` definitions | `Idr_MayHalt`; `getCrashCause` deleted (02 E15-E17), the op's own `getCause` stays |
| `IdrCheckOps.td:46-47` | `may_loop`'s two writes | `Idr_MayDiverge` [DP-01 A]; the op deleted [B] |
| `IdrClosureOps.td:37, 54, 72` | `closure`, `suspend`, `delay`: `Idr_ConsumesOnly` | rules (`Idr_Takes`, `Idr_BuildsCell` under DP-31 B) |
| `IdrClosureOps.td:101-103, 124-158` | `force`'s three writes; `apply`'s nothing | `Idr_RunsUnknown` on both |
| `IdrClosureOps.td:189-191`, `IdrArrayOps.td:362-363, 401-403` | `DeclareOpInterfaceMethods<MemoryEffectsOpInterface>` on `memo.run` and the updates | `Arg` decorators (02 E49, E50) |
| `IdrOps.td:212, 242, 285-287, 329-330, 359-360`, `IdrMatchOps.td:102, 163`, `IdrOwnershipOps.td:118, 329, 374`, `IdrBigOps.td:172` | hand effects or `ConsumesOnly` on `call`, `return`, `con`, `field`, `tag`, `match`, `yield`, `share`, `unpack`, `own.give`, `nat.to_big` | rules |
| `IdrOps.td:162-163, 219-220` | the `effects` property over `Idr_Effect` | over `Idr_Summary` |
| `IdrOwnershipOps.td:74, 89, 318` | `dup`, `drop`, `take` on the root | `Count`, `Heap` (1.7) |
| `IdrOwnershipOps.td:410, 422` | `MemAlloc<Idr_LinResource>` | `MemAlloc<Idr_Fresh>` |
| `IdrOwnershipOps.td:192, 211, 230-231, 258`, `IdrOps.td:377` | cells and `dest.write` on the root | `Heap` (stages kept, F DP-04) |
| `IdrIOOps.td:21-23, 147, 227-228`, `IdrArrayOps.td:119, 272`, `IdrStringOps.td:84-85`, `IdrPlatformOps.td:313-315, 367` | `PerformsIO`, `ObservableIO`, `IOResource` | `Idr_DoesIO`, `Idr_ReadsRuntime`, `Idr_Forges`, by the owner's answers |
| the 51 ops of 1.7's measurement | value effects that name no resource (the root) | `Idr_Heap` named |

### 5.2 C++ declarations

| where (read) | what | disposition |
| --- | --- | --- |
| `include/idr/IR/IdrDialect.h:52-56` | `anyEffect` | deleted; the property's generated default |
| `include/idr/IR/IdrDialect.h:58-99` | six resource structs, `readsMemoState` | deleted; generated classes; the `Idr_IfMemoSum` predicate |
| `include/idr/IR/IdrDialect.h:101-108` | `consumes(OpOperand &, const SymbolTable *)`, two modes | API `consumes(operand)`, one mode; the placement mode goes with the call's conventions (08 T6, F DP-38) |
| `include/idr/IR/Traits.h:23-26, 31-80, 82-91, 114-123` | `consumedEffects`; `CallsRuntime`, `NoReturn`, `PerformsIO`, `ObservableIO`, `Primitive`; `ConsumesOperands`; `TakesReference`, `BuildsValue` | deleted (`NoReturn` by lane 03's terminator); `DeclaredEffects`, `TypedEffects`, `TypedSpeculation` added |
| `include/idr/IR/Flow.h:81-111` | `Does`, `classify`, `onlyAllocates`, `performsIO`, `mayRunAt` | API |
| `include/idr/IR/Func.h:30-59` | `bodyEffect`, `componentEffects`, `writeEffects`, `effectInstances` | API `derive`, `write`; `effectInstances` deleted (the atoms' call effects) |
| `include/idr/Analysis/Effects.h` (whole) | `solveEffects`, `observableRuns`, `LabelsRun` | the writer; `observableRuns` with F DP-50 |
| `include/idr/IR/Verify.h:44` | the rule's comment | rewritten |

### 5.3 The IR library

| where (read) | what | disposition |
| --- | --- | --- |
| `lib/IR/Effects.cpp:1-184` | flow-based consumption, `readsMemoState`, `consumedEffects`, `classify`, `onlyAllocates`, `performsIO`, `sourcesOf`, `mayRunAt` | deleted; `lib/IR/Effects/` implements section 3 |
| `lib/IR/Func/Func.cpp:185-265` | `bodyEffect` (world parameters, `MayCrashOpInterface`, `WorldNewOp`, `RunsLabelsOpInterface`), `componentEffects`, `writeEffects`, `Row`, `rows`, `effectInstances` | deleted; `derive`, `write`, the generated tables |
| `lib/IR/Func/Call.cpp:52-57, 61-72` | containment check; hand `getEffects` (bits, consumption, `LinResource`) | V2 equality; the rules |
| `lib/IR/Verify/Program.cpp:53-71` | `effectsCovered` | deleted; V1 |
| `lib/IR/OpsCon.cpp:50-67`, `lib/IR/OpsConReads.cpp:26-38, 157-160`, `lib/IR/OpsMatch.cpp:135-138`, `lib/IR/OpsOwnership.cpp:232-235`, `lib/IR/OpsClosures.cpp:258-265`, `lib/IR/OpsArrays.cpp:78-84, 185-188, 229-232` | hand `getEffects` and `getSpeculatability` | deleted |
| `lib/IR/OpsArrays.cpp:242`, `lib/IR/Crashes.cpp:45` | `getCrashCause` | deleted (`Conversion/Bigs.cpp:44` calls the op's cause accessor) |
| `lib/IR/FlowOps.cpp:344-346, 365` | `NeverRuns` on `ub.unreachable` | deleted with U2 |
| `lib/IR/Canon/MoveOut.cpp:55-113` | second `Does`, `doesOf`, `usesWorld` | `classify<Q>`; `usesWorld` with DP-02 |
| `lib/IR/Canon/Sink.cpp:71-79, 223`, `lib/IR/Canon/CaseOfCase.cpp:78, 117, 126`, `lib/IR/Canon/Force.cpp:45` | `onlyAllocates`, `performsIO` per op between | API, cached sets |
| `lib/IR/Tail.cpp:274` | `mayRunAt` | API |
| `lib/IR/Verify/Uses.cpp:52-78`, `lib/IR/Verify/Owned.cpp:106-107, 183, 191-210`, `lib/IR/Verify/OwnedOps.cpp:226, 240` | instance-list and trait readings | API value questions |

### 5.4 Analyses, transforms, conversion, tools

| where (read) | what | disposition |
| --- | --- | --- |
| `lib/Analysis/Effects.cpp:36-96` | the bits solve, `observableRuns` (`hasTrait<ObservableIO>`) | the writer; F DP-50 |
| `lib/Analysis/IdentitiesRecord.cpp:160, 308, 314` | `returns = !diverge`; `onlyAllocates` | API (a call returns unless its summary stops returns: `exit` included) |
| `lib/Transforms/Effects/Effects.cpp:28-41` | the pass and its statistics | the writer's pass (it preserves the program graph, 05 EF12) |
| `lib/Transforms/Optimize/Component.cpp:73-81, 213-215`, `Optimize/Waves.cpp:285-292` | `writeCallEffects`, `componentEffects`, `setEffects` | the writer |
| `lib/Transforms/Specialize/Raise.cpp:111`, `Specialize/Specialization.cpp:36`, `Tail/Frames.cpp:320`, `Tail/FramesPlan.cpp:158` | `setEffects(anyEffect)` on clones, a copied summary, a compare | a clone takes its source's summary (its body does no more than its source's), so V1 and V2 hold with no solve; anything else goes through the writer |
| `lib/Transforms/Specialize/Consumer.cpp:48, 59-62` | world argument test; bits | API; the world test with DP-02 |
| `lib/Transforms/Ownership/Reshape.cpp:291-306`, `Ownership/Placement.cpp:152-161` | resource `TypeID` compares; `writes` | API |
| `lib/Transforms/Bufferize/Bufferize.cpp:193` | `onlyAllocates` | API |
| `lib/Transforms/StructureLoops/Forms.cpp:40-63` | `atMostCrashes` | API `atMostHalts` |
| `lib/Transforms/Defunctionalize/Pass.cpp:110-115` | `observableRuns` with `LabelsRun` | the refined solve (3.6), F DP-50 |
| `lib/Transforms/Contracts/Contracts.cpp:164-246` | bits, `writeEffects` | API, the writer |
| `lib/Transforms/Expect/Facts.cpp:38-41`, `Placement.cpp:78-92, 117`, `Allocation.cpp:28-41`, `Memory.cpp:44-60`, `CrashSites.cpp:24-37`, `ComputesNothing.cpp:21-35`, `Does.cpp:33-34`, `SolvedEffects.cpp:29-33`, `Arguments.cpp:295-298`, `Folded.cpp:32` | the properties of 2.7 | API (Facts deleted) |
| `lib/Transforms/Tail/TailLoops.cpp:150`, `Tail/WhileDo.cpp:199, 301`, `Tail/AccumulatorPlan.cpp:140`, `Tail/Accumulate.cpp:113`, `Narrow/Widths.cpp:48`, `Effects/Constants.cpp:149`, `Conversion/TailPosition.cpp:204` | upstream's `isMemoryEffectFree`, `isSpeculatable`, `wouldOpBeTriviallyDead`, `isOpTriviallyDead` | kept as upstream's readings (they read the declared effects); region ops' answers through the cache where hot |
| `lib/Transforms/Tail/Loop.cpp:133`, `Tail/WhileDo.cpp:282`, `Conversion/Scalars.cpp:48-58` | `may_loop` made and lowered | DP-01 A kept; B deleted |
| `lib/Conversion/Scalars.cpp:39-46` | `world.new` lowered | DP-02 |
| `lib/Conversion/Runtime.cpp:87, 130, 140-150`, `RuntimeCalls.cpp:81` | `noreturn` only; no other attribute | 2.5's constants |
| `lib/Conversion/FuncToFunc.cpp:3-5, 35-45` | function facts dropped | 2.5 (lane 12) |
| `lib/Target/Schedules.cpp:303-308` | hand transform effects | `FunctionalStyleTransformOpTrait` |
| `tools/idris-mlir-tblgen.cpp:950, 1481, 1596, 2307, 2878` | traits read by C++ name (`NoReturn`, `PerformsIO`, `Primitive`, the runtime mark) | the terminator fact, the world constraint or `idrisIO`, record fields; the new backends added |

### 5.5 Idris side and tests

| where (read) | what | disposition |
| --- | --- | --- |
| `compiler/src/IdrisMLIR/Dialect/Idr.idr:1222, 1413-1517` | `IOPrim`, `ioResult`, generated from `PerformsIO` | regenerated from 2.6's fact; same content under DP-02 B |
| `compiler/src/IdrisMLIR/Emit/Monad.idr:81`, `Emit/Operations.idr:338-356` | the world's linearity by hand; the IO op's world plumbing | DP-02 (lane 14) |
| `unittests/Verify.cpp:33`, `unittests/Identities.cpp:39, 70, 76` | `Effect::none`, `effects<...>` text | the atoms (spelling unchanged for `none`, `diverge`) |
| `tests/effects-*` (16), `tests/func-call-effects{,-contain,-cse}`, `tests/expect-solved-effects`, `tests/expect-crash-sites`, `tests/contracts-crash-sites`, `tests/expect-memory` | fixtures and properties over today's bits and readings | rewritten by lane 19's plan (19 T5: trace-invariance programs replace the 84 `facts:` remarks); summary text changes only where new atoms appear |

### 5.6 The skill's lines, per obligation

- *Made unrepresentable:* a crash unordered with output, and the second
  write that said it (the tree, 1.2); a summary bit that names no state, or
  a bit-to-resource table that drifts (the atoms are the bits, 1.4); a hand
  `getEffects` and an op that declares nothing (1.10); a call that runs a
  label and declares less than "everything" (`Idr_RunsUnknown`, computed
  from the atoms); a builder that allocates and says it does not, under
  DP-31 B (`Idr_BuildsCell`).
- *Check moved to a boundary:* "a summary covers its body" from a serial
  whole-program walk to each function's region verifier (V1); "a call
  holds its callee's effects" from containment to equality at the symbol
  verifier (V2); every effect declaration's well-formedness from run time
  (upstream's fatal error on a value on a non-addressable resource) to
  TableGen time (1.10 d); the summary's coverage to `static_assert`s (2.4).
- *Branch deleted:* the four readings of "does IO" (02 §3.1), the three
  of "may crash" (02 F5), the five of "is this operand consumed" (08 §2.6),
  the second classifier (3.5), `bodyEffect`'s four special cases, the
  `isa<LinResource>` and frame exceptions (now tree facts), the flow-edge
  rebuild on every effect query (static positions, 1.3).
- *Essential, kept:* the typed rules (the problem has ops whose effects
  their types decide; ods-Q2 settled by F DP-04); the `total` seed (Idris's
  proof is the one non-op input); region ops' effects (their bodies are
  rewritten IR); Idris's sequencing beside MLIR's effects (two facts,
  2.6); the frame and `Fresh` as nodes apart from `Heap` (an identity and a
  frame are not heap memory).

## 6. The owner's open choices, as parameters

Each answer is an edit of `IdrEffects.td` (and of the op lines marked
`[DP-...]` in 1.7); nothing else in sections 2 to 5 changes with it. The
design works under every combination except those 6.4 names.

### 6.1 DP-01: a dead crash, a dead divergence, and `exit`

- **A. Kept** (today). `Idr_MayHalt = MemWrite<Idr_Halt>`,
  `Idr_MayDiverge = MemWrite<Idr_Diverge>`, `may_loop` stays, atoms
  `crash`, `diverge` carry `MemWrite`. Two identical guards are not merged
  by CSE (04 C55's hand fold stays).
- **B. Deletable when dead** (upstream's model, 5.2 A7). Edit:
  `Idr_MayHalt = MemRead<Idr_Halt>` and the crash family lists
  `ConditionallySpeculatable` answering `NotSpeculatable`; atoms `crash`
  and `diverge` carry `MemRead`; `Idr_MayDiverge` and `may_loop` deleted
  (`Tail/Loop.cpp:133`, `Tail/WhileDo.cpp:282`, `Conversion/Scalars.cpp:48-58`).
  A `Read` on `Halt` is upstream's exact statement of what B means: an
  unused guard is trivially dead (only reads, 5.2 A6), it still conflicts
  with every IO write (an ancestor), so a live crash stays in order with
  output, and two equal guards merge under CSE (no write between them on
  the same subtree), so `checkedBefore` goes (04 C55). What the owner
  should know: under B two different guards may swap (reads never
  conflict), so which crash message a program prints when two would fire
  is unspecified, GHC's "imprecise exceptions"; and a call whose summary
  holds only `crash` or `diverge` reads becomes deletable when unused.
- **C. Crash kept, divergence deletable only where proved.** Not a
  separate configuration: it is A plus `mustprogress` on every function
  whose summary lacks `diverge`, which 1.9 derives under every answer.
- **`exit` (eff-Q2).** It is IO under every answer (`exitWith` is in IO;
  `Idr_DoesIO`), so it is never deletable. Its second effect is the
  choice: (i) a halt: `Idr_MayHalt` (crash-sites counts it, as today's
  `NoReturn` count does, 19 E14); (ii) its own node: `def Idr_Exit :
  Idr_Node<"Exit", Idr_IO, 0>;` and an atom `exit` with `stopsReturn = 1`
  (crash-sites then excludes it); (iii) a divergence: `Idr_MayDiverge`
  (loses `mustprogress` on every function that may exit, a lost
  optimization, never unsound). Every option makes a function that may
  exit lose `will_return` (02 §3.7's latent case).

### 6.2 DP-02: the world

- **B. Kept.** `Idr_Forge` and `Idr_Forges` stay; world operands stay on
  the ops that have them. The world orders, it is never an effect source:
  IO ops declare `Idr_DoesIO`, buffers and arrays their value effects, as
  the source says. Idris's sequencing is the world constraint (2.6).
- **A. Effects only.** Edit: delete `Idr_Forge`, `Idr_Forges`, the world
  type and every `Idr_WorldType` operand and result (44 definitions, 03
  §2); add `bit idrisIO` to the IO families; `world.new` becomes
  `io.unsafe_run` (`RecursiveMemoryEffects`); `tabulate_io` and
  `element.update` merge into `tabulate` and `array.update` (03 O-43).
  MoveOut's next-IO search becomes a walk over cached sets (02 §8's
  quadratic risk; 8.4 M5).
- **C. The builtin `token`.** Ruled out by every lane (5.8 B11,
  `5.8-dialect-design.md:285`); nothing to edit.

### 6.3 DP-03: what is ordered with what

- **ods-Q3, a crash and the heap.** (b) ordered with IO only: `Idr_Halt`
  under `Idr_IO`, `Idr_Heap` under the root (1.2). (a) ordered with both:
  ```tablegen
  def Idr_Halt    : Idr_Node<"Halt", DefaultResource, 1>;  // addressable: Heap is under it
  def Idr_Heap    : Idr_Node<"Heap", Idr_Halt, 1>;
  def Idr_IO      : Idr_Node<"IO", Idr_Halt, 0>;
  def Idr_Diverge : Idr_Node<"Divergence", Idr_IO, 0>;
  ```
  A crash then conflicts with every heap and IO effect, heap and IO stay
  disjoint (CSE still moves heap reads across output), and every `dup` and
  `drop` conflicts with every guard, so counting cannot move one past a
  guard (a cost to counting's placement, 08 T3; *conjecture* how much).
- **eff-Q1, what a summary covers.** (b) every state a caller must order
  with: the atoms `reads`, `writes`, `count`, `memo` (1.4). (a) only
  `io`, `crash`, `diverge`: delete those four atoms; see 6.4.
- **eff-Q4, runtime state.** (b) a state ordered only with what changes
  it: `Idr_Runtime`, `Idr_AtomRuntime`, `Idr_ReadsRuntime` (1.2, 1.4,
  1.5), and 1.10 (h). (a) IO: delete the three; `handle.string` reads
  `Idr_IO`, `io.strerror` lists `Idr_DoesIO`.

### 6.4 Incoherent combinations

1. **eff-Q1 (a) is incoherent with the ruling's derived summary**, except
   in one narrow form. A summary derived from ops (F DP-04) must carry
   every effect a caller can be ordered with, and four op families write
   state a caller can reach without any IO: `memo.run` writes memo state
   (`lib/IR/OpsClosures.cpp:263-264`), `dup` and `drop` write counts of
   borrowed arguments after counting (`IdrOwnershipOps.td:74, 89`), and
   arrays and buffers are written in place (`IdrArrayOps.td:334`,
   `IdrIOOps.td:167, 183, 197`); read. Without their atoms, a caller's
   `tag` of a memo cell, `is_unique` of a cell, or array read can move or
   merge across the call: 02 §3.7's third case, and A B3. The narrow form:
   under DP-02 B the world chain orders the world-threaded array and
   buffer ops by data dependence (an array read after the call takes the
   call's world), so `reads` and `writes` could be dropped; `count` and
   `memo` never can (neither op takes a world). So: eff-Q1 (a) is coherent
   only as "(a) plus `count` and `memo`, under DP-02 B"; under DP-02 A it
   must be (b) whole.
2. **DP-02 B with effects derived from the world by a rule** (5.8 DS2.2
   read literally: "an op with a world operand writes `World`") is
   incoherent with eff-Q4 (b) (`io.strerror` takes a world and only reads
   runtime state) and with the ten world-threaded memory ops, which would
   gain `IO` (02 E14). The design therefore never derives effects from the
   world (6.2 B); the rule could be written (`Idr_When` admits an
   `Idr_IfWorld`) but only with eff-Q4 (a) and the buffer ops ordered as
   IO.
3. **ods-Q3 (a) requires `Halt` addressable**, since an addressable node
   (`Heap`) may not sit under a non-addressable one
   (`SideEffectInterfaces.h:164-173`); with that, coherent under every
   other answer, DP-01 B included (a `Read` of `Halt` conflicts with
   writes below it).
4. Every other combination is coherent: DP-01 B with any `exit` option
   (exit's IO keeps it alive), DP-31 either way (a merged `delay` shares
   one cell, and a `by_name` label reruns at each force, so effects still
   happen where the value is demanded, AGENTS.md), eff-Q4 (b) with either
   tree.

### 6.5 DP-31: a closure's allocation

(A) as today: `closure`, `suspend`, `delay` have no `Idr_BuildsCell`; CSE
may merge two. (B) they list `Idr_BuildsCell<"result">`, as `con` does;
`BuildsValue` and `Allocation.cpp`'s closure cases go.

### 6.6 ods-Q5 (settled)

F DP-04: stages and full-region bits are declared in the source like every
other fact; nothing reads them, and nothing generated does. Kept on
`cell.new`, `cell.stack`, `cell.recycle` (1.7).

### 6.7 DP-50 (the coordinator's)

Where the writer first runs (folded into defunctionalization's decision,
or a pass after the conversion) changes nothing here: the writer, `derive`
and its label-refined filter are the same functions either way (3.6).

### 6.8 One choice this design adds

V1 as containment with equality at every write (the design), or equality
after every pass with the writer inserted after every pass that may change
effects (4.1). Both are sound and both keep one writer; the second costs a
program-level writer run per such pass.

## 7. Upstream

### 7.1 Who reads the declared effects

| upstream reader | reads | in our pipeline (read) |
| --- | --- | --- |
| greedy driver's DCE, region DCE | `wouldOpBeTriviallyDead`, `isOpTriviallyDead` | every canonicalize (`Pipeline.cpp:28-32`; 5.1 D2, `audits/p0/wave1/5.1-mlir-analysis.md:378`) |
| CSE | `isMemoryEffectFree`; for read-only ops, resource disjointness and addressability (`lib/Transforms/Utils/CSE.cpp:222-228, 264`); erases trivially dead ops (`:303`) | twice on `idr.func` (`Pipeline.cpp:92-94, 115-117`), and after the lowering |
| known-case inlining (`InlineRegionBranchOp`) | requires `HasRecursiveMemoryEffects` (`lib/Interfaces/ControlFlowInterfaces.cpp:1224-1228`) | canonicalize on every match (04 C50) |
| SCCP's cleanup | `wouldOpBeTriviallyDead` | idr-constants (`Effects/Constants.cpp:149`) |
| LICM, control-flow sink | `isPure`, `isMemoryEffectFree` | not run on `idr` ops (our sinking is `Canon/Sink.cpp`, 02 §3.2); after structure loops, on `scf`/`linalg` |
| inliner pass | `isMemoryEffectFree` of a non-symbol callable | not run (our optimizer inlines) |
| local alias analysis | non-addressable never aliases (`LocalAliasAnalysis.cpp:530`) | if a pass uses it |
| bufferization | `Allocate`/`Free` on values | one-shot bufferization of arrays |
| LLVM (after translation) | call and function attributes | every program, once 2.5 lands |

What the tree buys there (*conjecture* until 8.4 M4): CSE merges a heap
read across output and crashes, and a memo read across output; DCE deletes
dead guards and loops under DP-01 B; LLVM merges, hoists and deletes pure
runtime calls.

`RecursiveMemoryEffects` stays on every region op (04 C50): replacing it
by explicit effects would switch off known-case inlining unless upstream
relaxed its precondition, and the precondition is right (folding an op away
must lose no effect of the op's own). No patch.

### 7.2 Patches the design needs

Each per AGENTS.md: `upstream/<NN>-<bug>/` with `README.md` (symptom,
reproducer, cause, patch, when it goes, `## Upstreaming plan`),
`llvm.patch` applied by `tools/bootstrap.sh`, `submission.md`, a
`tests/upstream-<bug>` check and a `PINS.md` entry, landed in the same
change (upstream/README.md:15-46, read).

- **U1. `llvm.call` implements `MemoryEffectOpInterface` from
  `memory_effects`** (12 T2, CV-14). Today it implements none
  (`LLVMOps.td:821-826`, read), so MLIR's passes after the lowering see
  every runtime call as unknown, whatever attributes it carries. The
  patch: when `memory_effects` is present *and* `will_return` and
  `no_unwind` are set, report a `Read`/`Write` per location's ModRef on
  `DefaultResource` (no value), none for `none`; otherwise report `Read`
  and `Write` on `DefaultResource`, as `LLVM::InlineAsmOp::getEffects` does
  for an op with side effects (`lib/Dialect/LLVMIR/IR/LLVMDialect.cpp:4368-4374`,
  read). Requiring `will_return` keeps MLIR's DCE (which deletes an
  effect-free op even if it may not return, 5.2 A7) from deleting a call
  LLVM itself would keep (LLVM deletes a call only if it will return).
  Upstream test: a new `mlir/test/Dialect/LLVMIR/call-memory-effects.mlir`
  (canonicalize and CSE: two calls with `memory_effects` all `none`,
  `will_return`, `no_unwind` merge, an unused one goes; a call without the
  attribute stays). Ours: `tests/upstream-llvm-call-memory-effects`.
  Status: to write; not sent. Receptiveness unknown (12 §8).
  Needed only for MLIR's cleanups after the lowering; the attributes reach
  LLVM without it.
- **U2. `ub.unreachable` declares no memory effects** (02 T8, E67). Today it
  is `[Terminator]` only (`include/mlir/Dialect/UB/IR/UBOps.td:73`, read),
  so `getEffectsRecursively` of a region ending in it has no answer and
  every reader takes the region op for "anything"; we work around it with
  an external model (`lib/IR/FlowOps.cpp:344-346`) and MoveOut's case
  (`lib/IR/Canon/MoveOut.cpp:85-86`), which AGENTS.md forbids. The patch:
  `NoMemoryEffect` on `UB_UnreachableOp` (it never executes; LLVM's
  `unreachable` has no side effects). Upstream test:
  `mlir/test/IR/test-side-effects.mlir`'s pass prints its effects (none),
  and a `RecursiveMemoryEffects` test op holding only `ub.unreachable` is
  memory-effect free. Ours: `tests/upstream-ub-unreachable-effects`.
  Independent of everything else here; may land first.
- **U4. An ODS effect keeps its resource's record.** `SideEffect` stores
  only `resourceReference.name` (`include/mlir/Interfaces/SideEffectInterfaceBase.td:165-181`,
  read), so a TableGen backend learns a resource's C++ name and loses the
  record (its fields, its parent). The patch: `Resource resourceDef =
  resourceReference;` in `SideEffect`, and `const llvm::Record
  &getResourceDef() const` on `mlir::tblgen::SideEffect`
  (`include/mlir/TableGen/SideEffects.h:24-36`); nothing upstream changes
  behaviour. Upstream test: a `mlir-tblgen` test under
  `mlir/test/mlir-tblgen/` whose backend prints each effect's resource
  record (or a unit test of the wrapper). Ours:
  `tests/upstream-side-effect-resource-record` (the generator resolves every
  effect of the dialect to an `Idr_Node`). Status: to write; not sent;
  likely uncontroversial (*conjecture*).
- **U3, conditional. Memoize recursive effects within one CSE run.** Only
  if 8.4 M5 shows upstream's walks of match bodies hot at stage 1 (CSE asks
  `isMemoryEffectFree` of each candidate, and a nested match is walked
  again from each enclosing one). Upstream already names the need ("we
  should introduce some caching", `LocalAliasAnalysis.cpp:488-492`, via
  5.1 D3); Flang's pass-scoped cache is the model (5.6 E3). Plan written
  only when measured.

### 7.3 Patches the design does not need, and why

- mlir-tblgen's all-or-nothing `getEffects` (5.2 A5): no op mixes static
  and typed effects (1.6).
- A `mustprogress` function attribute in the LLVM dialect: `passthrough`
  carries it.
- Resource parents in ODS: our generator writes the classes from our
  records; upstream's syntax names them unchanged (U4 only lets the
  generator see which record an effect names).
- Readers of effect stages and full-region bits: nothing needs them (6.6).

## 8. Landing

### 8.1 Before the cutover

- **A green start.** e96bb991 (470/480), not origin/main after 101edbc5
  (21 §5.5); the invariant set below must pass there.
- **The owner's answers** to DP-01, DP-02, DP-03 (and the coordinator's to
  DP-31), since they fix the tree (F DP-04: "the tree's shape waits on
  DP-01 to DP-03").
- **U2** and **U4** (independent; U4 before the new backends).
- **The runtime audit** (4.4) and its fixes to the op records: the tree
  and the LLVM attributes turn any under-declared runtime effect into a
  miscompile, so the audit precedes both.
- **A record** of the measurements in 8.4 at the starting commit.

### 8.2 What lands together, and the order inside it

One hard cutover. These cannot land apart (02 §5's order item 3, §8: "T1
and T2 land together or not at all"): the tree without the derived summary
over memory hides a callee's buffer, array, count and memo writes across
calls, which today's root resource masks.

The cutover contains, in the order it is written and built:
1. `IdrEffects.td` (tree, kinds, atoms, bundles, rules, seed, LLVM
   columns) and the two new backends with 1.10's refusals; the generated
   `EffectTree.h.inc`, `EffectFacts.h.inc` and their `static_assert`s.
2. Every op re-declared onto the tree (5.1), the hand bodies and marker
   traits deleted; `TypedEffects`, `TypedSpeculation`, `DeclaredEffects`
   and the interface added. Deleting today's resource structs and `Effect`
   makes every old reader a compile error from here on.
3. The summary property over `Summary`; `derive`, `project`, `write`;
   V0-V2 in the verifiers; the writer in idr-effects, idr-optimize and
   the pipeline's insertion points (4.1, V4).
4. The API (section 3) and every reader of 5.3-5.4 rewritten to it.
5. The lowering's attributes (2.5).
6. The generator's Idris output (2.6) and, under DP-02 A, the frontend's
   world removal in the same commit (14 §6 Q3).
7. The tests: idr-expect's properties over the API (2.7), the fixtures
   (19 T5), the new tests below.

U1 lands after, alone: it only lets MLIR's post-lowering passes read what
step 5 already writes.

### 8.3 The gates

- **G1, the invariant oracle** (T-Q1, 19 C3): the program tests (234, 907
  cases), the rejects with their neighbours, the 144 semantics runs, the
  benchmarks' outputs and the fuzz seeds pass unchanged; no step's
  correctness rests on a test the step rewrote.
- **G2, the effects fixtures:** the 16 `effects-*` tests,
  `func-call-effects{,-contain,-cse}`, `expect-solved-effects`,
  `expect-crash-sites`, `contracts-crash-sites`, `expect-memory`,
  `effects-memo-label` and `defunc-memo-by-name` (whose `by_name` must
  stay where `observableRuns` puts it, 06 risk 5), restated by lane 19;
  summary text changes only by new atoms.
- **G3, three new program tests,** one per case of 02 §3.7, each a program
  whose output is its specification: a string handle read in a helper
  that is not inlined and freed after; a function that always exits (its
  `will_return`); a memo cell read before and after a call that forces it.
  (*Conjecture* that the first and third fail today, 02 §8.)
- **G4, the generator's refusals:** one planted `.td` fixture per check of
  1.10 (lane 14 TD1).
- **G5, `tests/runtime-effects`** (4.4) on all four targets.
- **G6, the taking positions:** before `eachTaken` is deleted, a run over
  the test corpus that compares, per op, the operands the generated
  `Idr_Takes` rules name with those today's flow edges take; equal on every
  op, or the rule set is wrong (1.3's conjecture).
- **G7, AGENTS.md's checks:** `make check`, `make build`, `make test`,
  `make test-idr`, `make test-unit`, `make test-mlir-tools`, each on the
  four targets.

### 8.4 The measurements

On the suites and on the stage-1 module, release build, assertions stated
(drv-Q1), before and after:
- **M1.** `getEffects` calls per pass and their time; the flow-edge
  rebuilds that consuming ops pay today (02 E53, E54), which go to zero.
- **M2.** The verifier: V1 per function against `effectsCovered`'s two
  serial walks (02 E29); and the writer's cost per insertion point (4.1,
  6.8).
- **M3.** Functions whose derived summary differs from today's
  `bodyEffect` rule: the size of the behaviour change, and how many gain
  `count` after counting.
- **M4.** CSE merges and DCE deletions with the tree and without (the gain
  7.1 claims).
- **M5.** Time in recursive effect walks per pass, ours (with the cache)
  and upstream's (deciding U3), with the number and case counts of
  `RecursiveMemoryEffects` ops (5.1 W4).
- **M6.** Compile time of the generated rule tuples, constants and
  interface models (`-ftime-trace`, 5.5 D6.2): 189 small models and 14
  rule expansions.
- **M7.** The benchmarks' run time and size with the LLVM attributes, and
  how many runtime calls LLVM deletes or merges.
- **M8.** Stage-1 footprint unchanged within noise (the API keeps no state
  beyond a pass-scoped cache).

## 9. Sources read

**In full:** `.claude/skills/representation-first/SKILL.md`; `AGENTS.md`
(including the new rule, :74-117); `proposals/0000-mlir-native.md` §0-§4,
§8, §9 and the parts the task names (§5.2 whole, §5.8 C and Effects and
DS2 and DS4, §5.1 D, §5.10 G5, M3, R1), now at `audits/p0/wave1/`;
`audits/p0/02-ods-effects.md`; `audits/p0/synthesis/A-dialect.md`,
`C-memory-backend.md`; `B-analyses.md` §1, §2, §5;
`audits/p0/synthesis/F-decisions.md` §1, DP-01 to DP-04, DP-08, DP-31,
DP-38, DP-50.

**The effects parts of** 03, 04, 05, 06, 08, 10, 12, 14, 18, 19, 21 (each
grepped for effect, resource, PerformsIO, world, getEffects, Crash,
Divergence, MemoState and their kin, every hit read in context, by four
read-only helpers whose reports this design cites by the lanes' own IDs).

**Our code:** `include/idr/IR/IdrInterfaces.td` (whole), `IdrBase.td:225-359`,
`IdrAttrs.td:180-215`, `IdrDialect.h:40-140`, `Traits.h` (whole),
`IdrIOOps.td:1-60, 130-232`, `IdrCheckOps.td:1-110`,
`IdrPlatformOps.td:1-62, 270-385`, `IdrClosureOps.td:85-215`,
`IdrOwnershipOps.td:56-96, 180-262, 395-427`, `IdrOps.td:105-240`, every
effect declaration in `include/idr/IR/*.td` (by grep);
`lib/IR/Effects.cpp`, `lib/IR/Func/Func.cpp`, `lib/IR/Func/Call.cpp`
(whole); `lib/Analysis/Effects.cpp`, `lib/Transforms/Effects/Effects.cpp:20-43`,
`lib/IR/Verify/Program.cpp:48-72`, `lib/IR/Canon/MoveOut.cpp:55-115`,
`lib/Transforms/StructureLoops/Forms.cpp:40-64`,
`lib/Transforms/Expect/{Placement.cpp:74-93, Memory.cpp:44-60, Allocation.cpp:22-42, Facts.cpp:30-44, CrashSites.cpp:15-46, ComputesNothing.cpp:15-40, Does.cpp:121-130}`,
`lib/Transforms/Ownership/{Reshape.cpp:284-306, Placement.cpp:148-162}`,
`lib/IR/Verify/{Uses.cpp:48-80, Owned.cpp:100-110, 178-212}`,
`lib/Transforms/Specialize/Consumer.cpp:40-66`, `lib/IR/Tail.cpp:262-280`,
`lib/IR/Canon/{Sink.cpp:60-84, Force.cpp:38-48}`,
`lib/Transforms/Bufferize/Bufferize.cpp:188-196`,
`lib/Analysis/IdentitiesRecord.cpp:300-318`,
`lib/Transforms/Optimize/{Component.cpp:70-82, 208-218, Waves.cpp:280-292}`,
`lib/Transforms/Effects/Constants.cpp:140-152`, `lib/IR/OpsCon.cpp:40-68`,
`lib/IR/OpsConReads.cpp:20-40`, `lib/IR/OpsOwnership.cpp:225-236`;
`tools/idris-mlir-tblgen.cpp:1-60, 270-290, 1395-1500, 2748-3010`;
`compiler/src/IdrisMLIR/Dialect/Idr.idr:1405-1520` and the Idris side by
grep; the readers listed in section 5, by grep, each hit read.

**Upstream** (`.toolchain/llvm-project/mlir`):
`include/mlir/Interfaces/SideEffectInterfaces.h:70-210, 330-350, 470-560`;
`include/mlir/Interfaces/SideEffectInterfaceBase.td:25-41, 150-195`;
`tools/mlir-tblgen/OpDefinitionsGen.cpp:3499-3616`, `:1078`;
`include/mlir/TableGen/SideEffects.h:24-36`;
`include/mlir/Dialect/Transform/Interfaces/TransformInterfaces.h:1276-1335`,
`lib/Dialect/Transform/Interfaces/TransformInterfaces.cpp:1793-1821`;
`lib/Interfaces/ControlFlowInterfaces.cpp:1220-1240`;
`include/mlir/Dialect/LLVMIR/LLVMOps.td:821-880, 2110-2160`,
`LLVMAttrDefs.td:1069-1080`, `lib/Dialect/LLVMIR/IR/LLVMDialect.cpp:4360-4380`;
`include/mlir/Dialect/UB/IR/UBOps.td:73-88`;
`lib/Transforms/Utils/CSE.cpp` (by grep, :222-228, 264, 303);
`llvm/lib/TableGen/TGLexer.cpp:683`.

**Measured:** the records dumped with `.toolchain/build/tblgen/bin/llvm-tblgen
--dump-json` (1.7) and read by `python3 -I` scripts in
`/tmp/p0-effects-scripts/` (`rt_effects.py`: the 119 runtime ops by
declared effects; `defaults.py` and an inline script: effects by kind and
resource, and the 51 ops on the root); the reader inventory by the grep of
section 5.
