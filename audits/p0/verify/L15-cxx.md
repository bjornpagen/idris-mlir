<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L15: the C++, compile-time architecture

*Lane L15 of the P0 verification swarm, written 2026-10-21. HEAD at
start `e96bb991` (21:31Z), at finish `e96bb991`: no anchor moved.*

In scope: D7, D10, D33, D41, D47 and §5.2 of `proposals/0000-mlir-native.md`,
against `audits/p0/design/compile-time-cpp.md` (CTC below),
`audits/p0/design/perf-sources.md` (PS), `audits/p0/wave1/5.5-cxx26.md`
(5.5), lanes 13 and 21, and the code under `foreign/idr/`. Nothing was
built, compiled or run. Grounds: *read* (path:line at HEAD; upstream under
`.toolchain/llvm-project` at `7208ba24`), *measured* (a `grep`/`wc`/`ls`
over the tree, command named), *recalled*, *conjecture*, *decision* (Dn,
Cn). Observation classes: **defect** (confirmed in the source),
**incomplete** (structural incompleteness), **mismatch** (integration
mismatch), **unverified** (behaviour not checked), **simplification**
(optional).

Counts used throughout (*measured* at HEAD over `foreign/idr/{lib,include,tools}`
with `grep -rEn`): 294 C++ units (`find lib tools unittests -name '*.cpp'`);
263 files include `idr/IR/IdrDialect.h`; 46 multi-type `isa<A, B…>`; 94
`function_ref<`; 4 `std::function<`; 84 `std::visit`, 79 `get_if<`, 26
`holds_alternative`; 60 `std::variant<`; 10 `TypeSwitch` lines (4 uses);
10 lines of `virtual` (three classes); 114 `template <`, 5 `concept`, 16
`requires`, 0 `extern template`, 0 `consteval`, 6 `static_assert`; 176
calls of `walk`; 140 maps or sets keyed by `Value`, `Operation *`,
`Block *`, `Region *` or `OpOperand *`, 15 more keyed by `FuncOp`/`CallOp`.

## 1. Verification

### 1.1 D7: templates, concepts, maximal compile-time C++

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| Our C++ is concept-constrained templates by default | holds as the target; far from today | 114 templates against 5 concepts and 16 `requires` (*measured*); the 5 concepts (`Ops.cpp:226, 277`, `Grades.h:210`, `Worklist.h:46, 58`) read constants and list no op | — |
| Callbacks are template parameters; `function_ref` only where an upstream API takes one | holds, with a correction | CTC §6 D6 keeps `ConAttr::walkFields` as "an ODS interface method's parameter, which cannot be a template"; it is not an interface method but an attribute class member declared in `extraClassDeclaration` (`IdrAttrs.td:112`), so it can be a member template. 01 T84/T85's "keep" for cold `function_ref`s is overruled by D7 for every member of ours | defect (CTC) |
| A ladder over our own types is an overload set or one fold over a closed sum | holds, with a correction of scope | of the 46 multi-type `isa` (*read*, each), 25 are over ops or op interfaces, 3 over effect classes, 6 over attributes (open sets: interfaces, ODS facts or the effect API, never concepts), and 12 over types, ours and builtin (`isa<BigType, NatType>` four times: `Narrow/Facts.cpp:23`, `OpsBigs.cpp:42`, `Layout/Components.cpp:197`, `AccumulatorPlan.cpp:172`; `isa<BoxType, DataType>` three times: `Grades.cpp:126`, `Verify/OwnedOps.cpp:128`, `Ownership/Values.cpp:25`). Types are MLIR's open set too: the cure for those 12 is a per-type fact generated from the specification (CTC §2.3(c)), read by a load, not a C++ concept | — |
| Interfaces only where the op set is open; a concept reads ODS facts, never lists ops | holds | no concept lists ops (*read*, the five above); `addRuntimeCalls<GET_OP_LIST>` (`Conversion/RuntimeCalls.cpp:150-169`) and `if constexpr (requires { Abi<OpT>::entry; })` (`:153`) are the right form already | — |
| Every fact knowable when the compiler is built is a constant generated from the one source and checked by `static_assert`/`consteval` | holds, with a correction | since D16 the one source is the Idris specification, and one-source §4.3 deletes C++ re-checks of what Idris proved ("A proof done in Idris is not done again in C++"). D7's "checked by `static_assert`" then means checks whose subject is C++ (a hand function against a generated table, a specialization's existence, a law of hand C++ code), not a re-proof of a generated table. CTC R1-R4 still name TableGen records and `idris-mlir-tblgen` as T0 (`compile-time-cpp.md:69-72, 83-108, 251-322`), superseded by D16 and D51 | mismatch |
| Runtime dispatch survives only where the open op set forces it, each listed | holds, with a correction | CTC §6 lists D1-D13 and misses: the `virtual Node node()` effects.md adds to every resource of ours (`effects.md:733-739`); `TaggedAction::print` (`Actions.h:44-46`, MLIR-required); `StagedPass::runOnProgram` if the CRTP step is refused; the C function pointer of the tools' runner (`Stack.h:47-51, 64-76`); the folder's dispatch on width (§2.8); libc++ hardening's bounds checks (§2.2). §2.10 completes the table | incomplete |
| Each solver instantiated once, explicitly, behind `extern template` | holds, with a correction | 0 `extern template` today (*measured*). CTC instantiates `mark<D, G>` per graph type (`compile-time-cpp.md:1150-1158`); every graph is `Csr<Tag>`, so N tags give N identical copies of one loop. The marking needs no template at all (§2.6) | simplification |
| What templates cost the compiler's own build is measured, never assumed (AGENTS) | holds as a rule; nothing measured | no compile-time baseline exists but a stale `.ninja_log` (13 §2.7, `compile-time-cpp.md:1811-1817`); §2.12 gives the measurements | unverified |
| The design's C++ compiles where the tree is checked | **refuted for one sketch** | `make typecheck` compiles our C++ with the host's compiler (`tools/bootstrap.sh:1126-1160`, `host_cxx=c++` at `:117`), and 5.5 measured the host (Apple clang 21) without expansion statements (5.5 F1, sketch note). CTC's `matchPin` (`compile-time-cpp.md:1219-1230`) would fail that gate on such a host. The design's C++ is the intersection of the pinned clang and the typecheck host (§2.11) | mismatch |
| The recursion idiom: "Recursion without erasure: deducing `this`" (CTC §3.6, 5.5 D5, 21 P-19, 14 T49) | **refuted by D33** where the recursion follows the input | CTC's own example recurses on graph depth (`compile-time-cpp.md:1285-1290`); D33 rules "never recursion on the input's size". §2.9 replaces it | defect (design) |

### 1.2 D10 in the C++ (the compiler's run; the program's run is L02's and L11's)

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| Nothing static is built per function | holds as a target; violated at HEAD | `RetypePattern` per registered op, built, frozen and destroyed per function (`Defunctionalize/Patterns.cpp:282`, called per function from `Pass.cpp:87-104`); the reducer does the same (`tools/idris-mlir-reduce.cpp:61`); PS C2 | defect (HEAD) |
| A fact numbered once is not recomputed per query | holds as a target; two violations the design does not name | (1) the linearity verifier builds a `DenseMap<Operation *, unsigned>` of every op of the function on every verification (`Verify/Linearity.cpp:41-66`), only to sort the uses it reports when a second use is found (`:84-88, 92-101`): the sum it tests does not depend on order, so the success path pays for an error's wording; (2) `verify::alternatives` asks `getSuccessorRegions` into a fresh vector for every region, per linear value, per verification (`Linearity.cpp:27-33, 120`), though "every region returns to the op" is a fact of the op's class (a match, `scf.if`) | defect (HEAD and design) |
| No pointer-keyed map holds per-node state | holds, with the builder exception | CTC R8 allows a `Value`→id map inside a numbering builder, freed with it (`compile-time-cpp.md:131-134`); 140 such declarations at HEAD (*measured*), §1.7 checks those the audits name | — |
| A cost at run time is allowed only for a fact not known until then, and the code that pays it says why | holds; one cost unstated | CTC's `IndexVector::operator[]` keeps libc++'s extensive hardening bounds check (`CMakeLists.txt:326`, DP-75). The bound is not in the type: two scopes of one tag (two functions' local value numberings) share a type and differ in count, so an id of one can index the other's vector. The check is legitimate and must say so (§2.2) | incomplete |
| Assertions | **open** | stage 2, which the shipped compiler links, has `LLVM_ENABLE_ASSERTIONS=ON` (`tools/bootstrap.sh:1022-1031`, 13 DP-57); an `assert` re-tests a fact the code's construction should guarantee. Whether D10 forbids them in the shipped compiler is a question of D10's meaning: §6 OQ-1 | — |

### 1.3 D33: the compiler's own tools keep a small stack

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| "Our C++ is iterative (worklists, never recursion on the input's size)" | **refuted at HEAD**; holds as a target once §2.9 lands | about 55 functions of ours recurse on the input's size (*measured* by a self-call scan over `lib/` and `include/`, each named in §2.9 read where its class was not obvious): region nesting, constant nesting, type nesting, dataflow chains, location chains. Two recurse through a `std::function` (`IR/ValueFacts.cpp:241`, `tools/idris-mlir-tblgen.cpp:261`) | defect (HEAD) |
| MLIR's verifier recurses on nesting | **refuted at the pin** | the op verifier is a worklist (`mlir/lib/IR/Verifier.cpp:412-455`), and so is dominance checking (`:524-556`) | — |
| MLIR's `walk` recurses on nesting | holds | `detail::walk` calls itself per nested op (`mlir/lib/IR/Visitors.cpp:21-32, 40-59`); 176 calls of ours reach it (*measured*) | — |
| "fixed upstream by patch, as `upstream/10-recursive-attribute-parser` already is" | **refuted** | that directory holds `README.md`, `nested.sh`, `submission.md` and no patch (*measured*: `ls`); its README's "Why there is no patch" says the recursion is also in the alias collection, `AttrTypeWalker`, `AttrTypeReplacer` and every dialect's attribute parser, "a change of design across the parser, the printer and the sub-element walks"; `PINS.md:585-607` agrees. Under D25 ("always carry the patch") and D33 that design change is ours to write and carry; it is larger than D33's sentence implies | mismatch |
| "The tools' 64 GiB stack goes with the programs'" | holds, with a correction | today only the main thread runs on the reserved stack (2^36 bytes, `runtime/Start/Runner.cpp:44`; `PINS.md:595` says 2^40, stale); every nested function pass runs on a pool worker with the OS default stack (13 DP-39). A small stack must hold on the workers, which is where nested passes and the parallel verifier recurse | incomplete |
| MLIR's deepest recursion is measured on the stage-1 module and on deep-nesting fixtures (S1) | unverified; measurable | §2.12 M-S1 gives the measurement | unverified |

### 1.4 D41: inline arithmetic, one meaning, a C++ template

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| The meaning is written three times today | holds, with a correction | Euclidean division: the folder (`IR/Ops.cpp:207-223`, `APInt`), the lowering (`Conversion/Scalars.cpp:61-104`, an `arith` expansion), the runtime (`runtime/Big/Arithmetic.cpp:20-33`, `int64_t`). Shifts: twice (`Ops.cpp:256-276`, `Scalars.cpp:115-160`). The scalar-value test: twice (`IR/OpsScalars.cpp:31`, `Scalars.cpp:182-184`). The runtime's copy serves the small path of `Integer`, whose values are 63-bit, not a fixed-width `IntN`: the same Euclidean adjustment, in a domain where the least-word-over-minus-one case cannot arise | — |
| One function generic over a numeric domain (a concept) | holds as a ruling; the concept is unwritten | CTC leaves it to DP-17 ("`ArithDomain` (12 T12)", `compile-time-cpp.md:731-736`); §2.8 writes it | incomplete |
| A generic function written the usual way can be instantiated over an IR builder | **refuted** | `mlir::Value` has `explicit operator bool() const { return impl; }` (`mlir/include/mlir/IR/Value.h:100`), so `if (d.less(r, zero))` compiles with a builder domain and tests whether the comparison's value is non-null: always true. The lowering would silently emit only one adjustment. The concept must make a domain's truth value unbranchable: every choice a `select` (§2.8) | defect (design risk) |
| Over intervals as upstream's `InferIntRangeInterface` | holds; new | no division or shift op infers ranges today (`IdrScalarOps.td:23-90` declare none; only `to_char`, `int_head`, `double_head` do, `:96, 127, 141`); upstream's `intrange::inferDivS`, `inferRemS`, `inferShl`, `evaluatePred` exist (`mlir/include/mlir/Interfaces/Utils/InferIntRangeCommon.h:83-145`), so the interval domain is a thin adapter over them (upstream first) | — |
| Edge cases `static_assert`ed when the compiler is built | holds; can be stronger | widths are i8, i16, i32, i64 only (`IdrTypes.td:312`), so a constexpr 64-bit word serves every width, and the folder needs no `APInt`; the law can be checked exhaustively at 8 bits within clang's 1,048,576-step limit per evaluation (`clang/include/clang/Basic/LangOptions.def:391`) if split per row (§2.8) | simplification |
| "the runtime includes the same header" | holds, with a placement | AGENTS.md: a primitive's one meaning is the runtime's, "which folders call too". The header belongs under `runtime/`, free of LLVM and MLIR; the interval and builder domains live in the compiler | — |

### 1.5 D47: never an `isa<A, B>` ladder, never a concept that lists ops

| claim | verdict | evidence | class |
| --- | --- | --- | --- |
| The skill carries the approved line | holds | `.claude/skills/representation-first/SKILL.md:102-105` | — |
| No concept of ours lists ops | holds | §1.1 | — |
| Every audit disposition agrees | **refuted for two** | 05 ID10 proposes "one `TypeSwitch` with `Default` inside the pass" for `internResult`'s ladder (`05-analyses.md:1165`), and synthesis B §2.9 allows "a `TypeSwitch` inside one pass" (`B-analyses.md:180-181`): `TypeSwitch` is a chain of `dyn_cast`s (5.5 notes, `llvm/include/llvm/ADT/TypeSwitch.h:103, 182`), a ladder by another name. CTC poisons `TypeSwitch` (`compile-time-cpp.md:1948-1950`), which agrees with D47 | mismatch |

### 1.6 §5.2: the C++, as settled

| bullet | verdict | evidence | class |
| --- | --- | --- | --- |
| Decided when the specification is built: ops, families, types and grades, effects, ABI, pipeline, rules, body kinds, causes, clocks; `consteval` checks | holds, with D16's correction (1.1) and D48's | CTC §2.3(c) keeps `MutableType` sealing and "Held bits set when a group is sealed" (`compile-time-cpp.md:521-525`) and a three-case lifetime enum with exhaustive laws (`:509-515`); D48 deletes sealing (facts computed when a type is made) and D39/D40 add lifetime variables, so the constexpr algebra covers the three constants and the variables' order is the region nesting, program data | mismatch |
| Typed dense ids and `IndexVector` | holds | §2.2 | — |
| Compressed rows behind one `Graph` concept, wired into LLVM's algorithms | holds, incomplete | `GraphTraits` needs a `NodeRef` that reaches its graph (an `Id` alone cannot); `scc_iterator` starts from one entry (`llvm/include/llvm/ADT/SCCIterator.h:44-82`), and `Support/Scc.cpp:31-53` adds a root vertex for that reason; the program graph must say how every node is reached (L14's seam, §2.17) | incomplete |
| `Lattice` and `Summary` concepts | holds, incomplete | CTC's budgeted policy has no pessimistic value to write when the budget runs out (§2.5, I-8) | incomplete |
| Direction and every choice a type, never a `bool` | holds | §1.7 lists the `bool`s at HEAD | — |
| One fold over each closed sum (the cliff above eleven) | holds | `_LIBCPP_VARIANT_DISPATCH_COUNT 11` (`libcxx/include/variant:1596-1607`); 189 accessor uses to replace (*measured*) | — |
| Transfer functions and callbacks as constrained template parameters | holds | §2.5 | — |
| Each solver one explicit instantiation behind `extern template` | holds, with I-9's simplification | §2.6 | simplification |
| Nothing static per function; no attribute made on a worker; no pointer-keyed map per node; no per-query recomputation; arenas and per-run interning | holds as a target | §1.2 names two violations the design misses | incomplete |
| A `-ftime-trace` baseline, a precompiled header, explicit instantiation | holds; the header's content is contested | CTC puts `IdrDialect.h` and our vocabulary headers in the PCH (`compile-time-cpp.md:1849-1858`); G DP-74 says "none of ours" (`G-coordinator-decisions.md:595-603`). I-11 selects | mismatch |
| Every surviving runtime dispatch listed and justified | holds, incomplete | §2.10 | incomplete |

### 1.7 The deletions named in the audits, checked at HEAD

| item | audit | at HEAD | deleted by |
| --- | --- | --- | --- |
| `mark(seeds, bool backward)` | 08 C-51 | present, `Transforms/Stack/Stack.cpp:197` | `mark<Backward>` over rows (§2.6) |
| family constants as `bool`s | 03 O-31, O-48 | present: `static constexpr bool quotient, isSigned` (`IdrScalarOps.td:31-34`), `left` in `Idr_ShiftOp`; read by `Ops.cpp:225-232, 276-281` | cases of the specification's enums (CTC §2.3(b)), D41's `Signedness`/`DivPart`/`Way` |
| `StageFacts`, four `bool`s (16 states, 5 valid) | 03 O-61 | present, `include/idr/IR/Func.h:83-91` | an `EnumArray<Stage, …>` printed by `specgen` |
| other `bool` choices | — (found here) | `role::Label::byName` (`IdrDialect.h:158`), `Component::counted` (`IR/Layout.h:85-88`), `factsOf(…, bool shared)` (`Analysis/Inline.cpp:20`), `placeOwned(…, bool keep)` (`Ownership/Placement.cpp:184`), `give(Node &, bool self)` (`SpecializeState.h:33`), `foldCheck(Operation *, bool holds)` (`OpsChecks.cpp:82`), `byNameIs`/`performs`/`provedIs(…, bool wanted)` (`Expect/ByName.cpp:54`, `Does.cpp:48`, `Proved.cpp:18`), `forEachNamed`'s `bool inPlace` (`TypeGraph.h:34`), `idrisDivMod`/`idrisShift`/`foldable`'s `bool left, isSigned` | each a sum or an enum (WU-6); `Loop.cpp:48 flag(Location, bool value)` is the program's boolean constant, essential |
| recursion through `std::function` | 21 P-19, 14 T05/T49, 01 T30 | `Positions::assign` is on origin/main only (101edbc5), not at HEAD; at HEAD: `ValueFacts.cpp:241` (01 T30) and `idris-mlir-tblgen.cpp:261` (14 T05) | §2.9 (a bit computed at type construction; the generator goes with D16/D51) |
| stored `std::function`s | 03 O-85, 06 D-22, 09 OPT-24 | `DataRemap::Leaf` (`Symbols.h:170-171`), `Scheduler::RunPipeline` (`OptimizeScheduler.h:101`) | `DataRemap` goes with D48; the scheduler becomes the pass's own code (09 OPT-24) |
| virtuals of ours | 06 L-5, 09 OPT-22, CTC R11 | `Labels::Statements` (`Analysis/Labels.h:123-126`), `specialize::Schedule` (`Specialize.h:123-138`), `StagedPass::runOnProgram` (`Pipeline.h:44`) | the first two with their lanes' rewrites; the third by CRTP with a carried upstream patch (I-10) |
| `DenseMap<Value, Sharing>`, `DenseSet<Block *> liveBlocks`, `targets`, `callersOf`, `returnsOf` | 07 O-23 to O-26 | present, `include/idr/Analysis/Ownership.h:304-308` | L08's exclusivity on `GatedCsr` (§2.4) |
| `dependents`, `itemsOf` | 07 X-10 | present, `ExclusivityDetail.h:155-156` | as above |
| `liveOf` per function | 07 A-16, 21 P-20 | present, `ExclusivityAnalyses.cpp:315` | a `BitSet` over block ids |
| `onCycle` as `DenseSet<Operation *>` | 05 RC3 | present, `Analysis/Recursion.h:30` | L14's program graph |
| stack inference's ids and adjacency | PS C8 residue | present, `Stack.cpp:262-267` | `Csr` and `mark` (§2.4, §2.6) |
| `CallCycles`' `indices`, `selfCalling` | 05 CC1 | present, `Analysis/CallCycles.h:56-58` | L14 |
| `Scc.h`'s `function_ref` returning a vector per node, its numbering map; `Scc.cpp`'s copied graph | 05 SC1, SC2 | present, `Support/Scc.h:31-52`, `Support/Scc.cpp:31-53` | `Csr` with `GraphTraits` (§2.4) |
| the linearity verifier's numbering and its two maps per value | — (found here) | present, `Linearity.cpp:41-66, 135-136` | I-5 |

## 2. Boundaries

### 2.1 The libraries, and what each may name

The layering is a link dependency, so a rule of it cannot be broken by a
hunk (CTC §3.4's idea, made exact):

| library | holds | links | may not name |
| --- | --- | --- | --- |
| `IdrSupport` (header-only plus `lib/Support/`) | `Id`, `Count`, `IndexVector`, `BitSet`, `Ragged`, `EnumTraits`/`EnumArray`/`EnumSet`, `match`, `depthFirst`, `Interner` | LLVMSupport | MLIR |
| `IdrSolve` | `Csr`, `GatedCsr`, `CsrBuilder`, the marking loops, `summarize`'s definition (`SummarizeImpl.h`), the lattice concepts | IdrSupport, LLVMSupport | MLIR: a solve cannot create an attribute, take a context lock, or keep state keyed by `Value` |
| `runtime/Arith` (header-only) | D41's generic functions and the `Fixed<W>` domain | nothing | LLVM, MLIR |
| `IdrIR` and the passes | extraction (MLIR → arrays, per function, in parallel), the `Numbering` builder, write-back, the effect API, the interval and expansion domains | everything above, MLIR | — |

### 2.2 Dense ids and `IndexVector`

```cpp
// foreign/idr/include/idr/Support/Id.h
namespace idr {
enum class Changed : bool { No, Yes };   // MLIR's ChangeResult is MLIR's; IdrSolve may not name it

// A dense id of the set `Tag` names. Only `Tag::Minter` makes one, so every
// id was numbered by its owner, and only a `Count` from that owner sizes an
// array it indexes.
template <class Tag, std::unsigned_integral Rep = std::uint32_t>
class Id {
  Rep raw;
  constexpr explicit Id(Rep r) : raw(r) {}
  friend typename Tag::Minter;
  template <class> friend class Count;
  template <class> friend class IdRange;
public:
  using tag = Tag;
  using rep = Rep;
  friend constexpr auto operator<=>(Id, Id) = default;
  constexpr Rep index() const { return raw; }   // arrays and GraphTraits::getNumber only
};

// How many ids a minter made: the only size an IndexVector or a BitSet takes.
template <class IdT>
class Count {
  typename IdT::rep n;
  constexpr explicit Count(typename IdT::rep v) : n(v) {}
  friend typename IdT::tag::Minter;
public:
  constexpr typename IdT::rep value() const { return n; }
  constexpr auto ids() const {   // every id, in order: the one way to visit them all
    return std::views::iota(typename IdT::rep{0}, n) |
           std::views::transform([](typename IdT::rep i) { return IdT(i); });
  }
};

// A fact per id. Indexing is libc++'s checked operator[]: the bound is not in
// the type (two scopes numbered under one tag share the type and differ in
// count), so the check is a fact not known until the compiler runs (D10).
template <class IdT, class T>
class IndexVector {
  static_assert(!std::same_as<T, bool>, "a set of ids is a BitSet");
  Count<IdT> count;
  std::vector<T> items;
public:
  explicit IndexVector(Count<IdT> n, const T &init = T{}) : count(n), items(n.value(), init) {}
  Count<IdT> size() const { return count; }
  T &operator[](IdT id) [[clang::lifetimebound]] { return items[id.index()]; }
  const T &operator[](IdT id) const [[clang::lifetimebound]] { return items[id.index()]; }
  template <std::integral I> T &operator[](I) = delete("index by the id its minter made");
  template <std::integral I> const T &operator[](I) const = delete("index by the id its minter made");
};

// A set of ids that only rises: no reset, so a marking over it is monotone
// by its API.
template <class IdT>
class BitSet {
  llvm::BitVector bits;
public:
  explicit BitSet(Count<IdT> n) : bits(n.value()) {}
  bool test(IdT id) const { return bits.test(id.index()); }
  [[nodiscard]] Changed raise(IdT id) {
    if (bits.test(id.index())) return Changed::No;
    bits.set(id.index());
    return Changed::Yes;
  }
};

// A fact per (owner, position) of varying arity: a parameter's bit, a
// field's state. Rows in one array with offsets (CSR), never a vector per owner.
template <class OwnerId, class T>
class Ragged {
  std::vector<std::uint32_t> start;   // count + 1 offsets
  std::vector<T> items;
public:
  std::span<const T> operator[](OwnerId o) const [[clang::lifetimebound]] {
    return {items.data() + start[o.index()], items.data() + start[o.index() + 1]};
  }
};
}  // namespace idr
```

```cpp
// foreign/idr/include/idr/Analysis/Numbering.h (IdrIR: it names MLIR)
// The one place a map keyed by an IR handle exists: while a scope is numbered.
// Ids are minted in pre-order, so under D19 (one block per region until the
// lowering) a definition's id is below every use's, and a forward loop over
// ids is a topological order of the scope's dataflow (§2.9).
template <class Tag, class Key>   // Tag::Minter is Numbering<Tag, Key>
class Numbering {
  llvm::DenseMap<Key, Id<Tag>> index;   // freed with the builder
  std::vector<Key> keys;
public:
  Id<Tag> mint(Key k);                  // the k-th new key gets id k
  Id<Tag> at(Key k) const;              // a use of a numbered value; verified IR has no other
  struct Done { Count<Id<Tag>> count; IndexVector<Id<Tag>, Key> keys; };
  Done finish() &&;                     // the map is gone after this
};
```

`at` has no miss branch: in a verified, isolated function every operand is
defined inside it and before its use, which the verifier proves at the
boundary (the skill: parse at the boundary, once).

### 2.3 Enums and tables

CTC §3.2's `EnumTraits`, `EnumArray`, `EnumSet`, `allOf`, `indexedBy`
stand (`compile-time-cpp.md:956-1015`), with two corrections. The generator
of `EnumTraits` is `specgen` (one-source §6.2), which emits enums dense by
construction ("an enum's position is its number", one-source §4.3), so
CTC's generator refusal of a non-dense `EnumInfo` is moot; `Idr_Quantity`'s
values 1 and 2 (`IdrBase.td:83-84`) become positions 0 and 1. And
`semilattice()` and the other exhaustive law checks run only over hand C++
operators: where the algebra is generated from the specification, Idris
proved it (one-source §4.3, "grade laws ... case-split proofs").

### 2.4 The row-compressed `Graph` concept

```cpp
// foreign/idr/include/idr/Solve/Graph.h
namespace idr {
struct Forward {};
struct Backward {};
template <class D> concept Direction = std::same_as<D, Forward> || std::same_as<D, Backward>;

// A row of a CSR array, read as typed ids. A range, not a span of Id: an Id
// is not a uint32_t to the aliasing rules.
template <class IdT>
class IdRange {
  const std::uint32_t *first, *last;
public:
  struct iterator { const std::uint32_t *at; IdT operator*() const { return IdT(*at); } /* ... */ };
  iterator begin() const; iterator end() const; std::size_t size() const;
};

template <class G>
concept Graph = requires(const G &g, typename G::Node n) {
  requires std::same_as<typename G::Node, Id<typename G::Node::tag, typename G::Node::rep>>;
  { g.size() } -> std::same_as<Count<typename G::Node>>;
  { g.successors(n) } -> std::same_as<IdRange<typename G::Node>>;
  { g.predecessors(n) } -> std::same_as<IdRange<typename G::Node>>;
};

namespace detail {
// The tag shed: what the one marking loop reads.
struct Rows { std::span<const std::uint32_t> start, to; };
}

// The graph of every solver of ours: 4 bytes per edge per direction and 4
// per node per direction (CTC §3.3's 8 + 8, *read*: the arithmetic holds).
template <class Tag>
class Csr {
public:
  using Node = Id<Tag>;
  Count<Node> size() const { return count; }
  IdRange<Node> successors(Node n) const [[clang::lifetimebound]];
  IdRange<Node> predecessors(Node n) const [[clang::lifetimebound]];
  detail::Rows rows(Forward) const { return {succStart, succ}; }
  detail::Rows rows(Backward) const { return {predStart, pred}; }
private:
  friend class CsrBuilder<Tag>;
  Count<Node> count;
  std::vector<std::uint32_t> succStart, predStart, succ, pred;
};

// Edges collected, then laid out by a counting sort on the source: O(V + E),
// no hash, no comparison sort. `finish` consumes the builder, so no edge can
// be added to a built graph (a graph that grows during its solve, the label
// solve's, keeps append-only vectors instead: 06 §3.2, essential).
template <class Tag>
class CsrBuilder {
public:
  explicit CsrBuilder(Count<Id<Tag>> n);
  void edge(Id<Tag> from, Id<Tag> to);
  Csr<Tag> finish() &&;
};

// Exclusivity's gates as data, not a callback. An edge either always carries
// the marking, or carries it once its guard node is marked too: Horn
// propagation, linear in nodes and edges, monotone because a guard is a node
// of a BitSet that only rises.
template <class Tag>
class GatedCsr {
public:
  using Node = Id<Tag>;
  struct Guarded { std::uint32_t to, guard; };   // read through Node accessors
  struct Waiting { std::uint32_t from, to; };
  Count<Node> size() const;
  IdRange<Node> plain(Node from) const [[clang::lifetimebound]];
  std::span<const Guarded> guarded(Node from) const [[clang::lifetimebound]];
  std::span<const Waiting> waitingOn(Node guard) const [[clang::lifetimebound]];   // the same edges, by guard
};
}  // namespace idr

// Upstream's algorithms. NodeRef carries its graph, since an Id alone reaches
// no row; getNumber lets PostOrderIterator index by number
// (llvm/include/llvm/ADT/PostOrderIterator.h:40-51); scc_iterator still keeps
// a DenseMap of visit numbers (SCCIterator.h:75) until CTC's proposed
// upstream/scc-node-numbers patch.
template <class Tag> struct llvm::GraphTraits<const idr::Csr<Tag> *> {
  struct NodeRef { const idr::Csr<Tag> *graph; std::uint32_t node; };
  static unsigned getNumber(NodeRef n) { return n.node; }
  // child_begin / child_end map the successor row to NodeRefs ...
};
```

What the concept cannot say, and who says it: how every node is reached by
an SCC walk that starts at one entry is the program graph's (L14).

### 2.5 `Lattice`, `Summary`, and what may stop a solve

```cpp
// foreign/idr/include/idr/Solve/Lattice.h
namespace idr {
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
template <class L>
concept Bounded = JoinSemilattice<L> && requires { { L::top() } -> std::same_as<L>; };

// A per-function fact a caller reads (a row, a lifetime signature, a borrow mask).
template <class S>
concept Summary = NodeState<S> && FiniteHeight<S>;

// What may stop a solve. Exact: nothing; a refusal or an ordering fact rests
// on the answer, so the lattice's height ends it (CTC's Acceptance, renamed:
// the effect rows are no refusal, yet the verifier holds them equal to their
// derivation, so they may not stop early either). Budgeted: a count in the
// program's units; what is unfinished is written top, so the answer stays sound.
struct Exact {};
struct Budgeted { std::uint64_t steps; };
template <class P> concept Policy = std::same_as<P, Exact> || std::same_as<P, Budgeted>;

struct CalleesFirst {};
struct CallersFirst {};
template <class O> concept Order = std::same_as<O, CalleesFirst> || std::same_as<O, CallersFirst>;

// transfer is const: it reads the graph and the finished summaries and
// mutates nothing, so one SCC level runs on many threads with no lock.
template <class P>
concept SummaryProblem = requires(const P &p, const ProgramGraph &g, FunctionId f,
                                  const IndexVector<FunctionId, typename P::Summary> &done) {
  requires NodeState<typename P::Summary>;
  requires Policy<typename P::Policy>;
  requires (std::same_as<typename P::Policy, Exact> && FiniteHeight<typename P::Summary>) ||
           (std::same_as<typename P::Policy, Budgeted> && Bounded<typename P::Summary>);
  { p.transfer(g, f, done) } -> std::same_as<typename P::Summary>;
};

template <Order O, SummaryProblem P>
IndexVector<FunctionId, typename P::Summary>
summarize(const ProgramGraph &, const P &, llvm::ThreadPoolInterface &);
}  // namespace idr
```

`ThreadPoolInterface &` is the context's pool, passed in (so no second pool
beside it, §5.3 D1), and the solve emits no diagnostic (so
`ParallelDiagnosticHandler`, PS C3, is not entered). A problem's local facts
(a function's own ops projected, read off its IR) are extracted per function
in parallel before the solve and held by `P` in an `IndexVector`; `transfer`
joins them with its callees' summaries. That split is what makes `summarize`
MLIR-free.

### 2.6 One solver instantiation behind `extern template`

The marking needs no template: the tag is shed at the call and the loop is
one ordinary function, compiled once for every graph of the compiler.

```cpp
// foreign/idr/include/idr/Solve/Mark.h
namespace idr {
namespace detail {
llvm::BitVector markRows(Rows rows, std::uint32_t count, std::span<const std::uint32_t> seeds);
llvm::BitVector markGated(const GatedRows &rows, std::uint32_t count, std::span<const std::uint32_t> seeds);
}
template <Direction D, class Tag>
BitSet<Id<Tag>> mark(const Csr<Tag> &g, std::span<const Id<Tag>> seeds);   // inline: shed, call, re-wrap
template <class Tag>
BitSet<Id<Tag>> mark(const GatedCsr<Tag> &g, std::span<const Id<Tag>> seeds);
}
// lib/Solve/Mark.cpp: the two loops, a worklist each; no recursion, no map.
```

The summary solve is a template by necessity (its transfer inlines into
the loop), and is instantiated once per problem:

```cpp
// foreign/idr/include/idr/IR/Effects.h: the effect rows' problem, declared.
namespace idr::effects {
struct RowProblem {
  using Summary = Row;          // EnumSet<Atom>: height = the atom count, so FiniteHeight holds by construction
  using Policy = Exact;
  IndexVector<FunctionId, Row> local;   // each function's own ops, projected; extracted in parallel
  Row transfer(const ProgramGraph &, FunctionId, const IndexVector<FunctionId, Row> &done) const;
};
}
extern template idr::IndexVector<idr::FunctionId, idr::effects::Row>
idr::summarize<idr::CalleesFirst, idr::effects::RowProblem>(
    const idr::ProgramGraph &, const idr::effects::RowProblem &, llvm::ThreadPoolInterface &);

// foreign/idr/lib/IR/Effects/RowSolve.cpp: the only unit that compiles it.
#include "idr/Solve/SummarizeImpl.h"
template idr::IndexVector<idr::FunctionId, idr::effects::Row>
idr::summarize<idr::CalleesFirst, idr::effects::RowProblem>(
    const idr::ProgramGraph &, const idr::effects::RowProblem &, llvm::ThreadPoolInterface &);
```

`SummarizeImpl.h` is included by one unit per problem and by no header.
The row's content (what `transfer` joins, the `total` seed) is L02's.

### 2.7 The effect query API (shape; content L01's and L02's)

D27 to D29 fix the names; CTC §2.3(d) and effects.md §3 use two other
vocabularies (`ResourceId`/`EffectRow` against `Node`/`Nodes`/`EffectSet`,
and the pre-D28 names `Fresh`, `Halt`, `Outside`, `Forge`). One vocabulary:

```cpp
// specgen → foreign/idr/include/idr/IR/Generated/EffectTree.h.inc, from Spec.Effects.
namespace idr::effects {
enum class ResourceId : std::uint8_t {   // upstream's two first, then D28's ten
  Root, Frame, Heap, Contents, Count, MemoState, Identity, IO, RuntimeState, Exit, Crash, Divergence };
enum class Kind : std::uint8_t { Read, Write, Allocate, Free };        // MLIR's four, and nothing more (D27)
enum class Atom : std::uint8_t {                                       // D29's eleven, in its printed order
  IO, RuntimeState, Exit, Crash, Divergence, Count, MemoState, Read, Write, Alloc, Free };
// Two independent facts of an op's declaration, so two enums, never two bools
// and never one five-case sum: idr.match has a typed rule (its scrutinee may
// be a memo sum) and RecursiveMemoryEffects (upstream's inliner needs it),
// effects.md:528-537. "Runs unknown code" is a static row of every effect
// (Idr_RunsUnknown, effects.md:339); a definition (func, program) has no Of<>.
enum class Rules : std::uint8_t { None, Typed };
enum class Bodies : std::uint8_t { Own, Recursive };
using Resources = EnumSet<ResourceId>;
using Row = EnumSet<Atom>;

inline constexpr EnumArray<ResourceId, Resources> ancestorsOrSelf{/* ... */}, descendantsOrSelf{/* ... */};
inline constexpr EnumArray<Kind, EnumArray<ResourceId, Row>> project{/* ... */};
inline constexpr EnumArray<Atom, LLVMFacts> llvmOf{/* ... */};

// What an op may do: per kind, the resources acted on. No `unknown` flag (an
// op that declares nothing is everything()), and no second allocation set:
// the specification's law "an acquisition names its result" (one-source §5)
// leaves no allocation but of the op's own results.
struct EffectSet {
  EnumArray<Kind, Resources> on;
  static constexpr EffectSet everything();
};
template <class OpT> struct Of;          // { static constexpr Rules rules; Bodies bodies; EffectSet may; }
template <class OpT> struct EffectRules; // only where rules == Rules::Typed: a tuple of rule types
}  // namespace idr::effects
```

```cpp
// foreign/idr/include/idr/IR/Effects.h (hand): the one API.
namespace idr::effects {
template <class OpT> concept Declared = OpT::template hasTrait<OpTrait::DeclaredEffects>();   // reads ODS
template <class OpT>
concept StaticEffects = Declared<OpT> && Of<OpT>::rules == Rules::None && Of<OpT>::bodies == Bodies::Own;

// The questions: total functions over a set, constexpr where the set is.
constexpr bool conflicts(EffectSet a, EffectSet b);
constexpr bool deadIfUnused(EffectSet s);
constexpr bool touches(EffectSet s, ResourceId r);   // an effect in r's subtree
constexpr bool on(EffectSet s, ResourceId r);        // an effect on r itself

// The typed path: a constant where the class decides.
template <StaticEffects OpT> consteval EffectSet effectsOf() { return Of<OpT>::may; }
// The instance path: rules applied to the op's types; bodies through the cache.
template <Declared OpT> EffectSet effectsOf(OpT op, RegionEffects &bodies);
// The untyped path: one interface dispatch (ours: EffectFactsOpInterface; others: MemoryEffectOpInterface).
EffectSet effectsOf(mlir::Operation *op, RegionEffects &bodies);

// A region op's bodies, once per op per analysis lifetime: an AnalysisManager
// analysis per function. A reference, never a nullable pointer: there is no
// "uncached" mode to choose.
class RegionEffects { public: explicit RegionEffects(mlir::Operation *function); EffectSet of(mlir::Operation *regionOp); };

template <class Q> concept Question = std::predicate<const Q &, const Effect &>;
enum class Does : std::uint8_t { Computes, Effects, Touches };
template <Question Q> Does classify(mlir::Operation *op, const Q &q, RegionEffects &bodies);

template <class F> concept CallFilter = std::predicate<const F &, CallOp>;
template <CallFilter Skip = NoSkip> Row derive(FuncOp fn, const Skip &skip = {});
}  // namespace idr::effects
```

`Of<OpT>` carries two enums where effects.md has two `bool`s, `exact` and
`recursive` (`effects.md:824-836`), and not the single "five forms, exactly
one per op" of §5.1, which cannot represent `idr.match` (I-2). `derive`
walks the op's nesting with upstream's `walk` (iterative once D33's patch
lands) or the region cache; it never recurses itself.

### 2.8 D41's numeric domain

```cpp
// runtime/Arith/Arith.h: the one meaning of Idris's fixed-width division,
// shifts and character conversion. The runtime, the folder, the range
// inference and the lowering instantiate it. It includes no LLVM and no MLIR.
namespace rt::arith {
enum class Signedness : std::uint8_t { Signed, Unsigned };   // printed by specgen from the specification's cases
enum class DivPart : std::uint8_t { Quotient, Remainder };
enum class Way : std::uint8_t { Left, Right };

// Words in a domain: integers, intervals of them, or IR that computes them.
// A domain's truth value is no C++ bool and converts to none, so generic code
// cannot branch on it: every choice is `select`, whose two arms are computed
// and total. (mlir::Value converts to bool, Value.h:100: an `if` on a
// comparison would test that the IR value exists.)
template <class D>
concept Domain = requires(const D &d, typename D::Word a, typename D::Word b,
                          typename D::Truth p, std::uint64_t k) {
  requires !std::constructible_from<bool, typename D::Truth>;
  { d.width() } -> std::same_as<unsigned>;
  { d.constant(k) } -> std::same_as<typename D::Word>;            // k mod 2^width
  { d.add(a, b) } -> std::same_as<typename D::Word>;              // mod 2^width
  { d.sub(a, b) } -> std::same_as<typename D::Word>;
  { d.bitAnd(a, b) } -> std::same_as<typename D::Word>;
  { d.eq(a, b) } -> std::same_as<typename D::Truth>;
  { d.template less<Signedness::Signed>(a, b) } -> std::same_as<typename D::Truth>;
  { d.template less<Signedness::Unsigned>(a, b) } -> std::same_as<typename D::Truth>;
  { d.both(p, p) } -> std::same_as<typename D::Truth>;
  { d.either(p, p) } -> std::same_as<typename D::Truth>;
  { d.negation(p) } -> std::same_as<typename D::Truth>;
  { d.select(p, a, b) } -> std::same_as<typename D::Word>;
  // Truncating, by a divisor that is neither 0 nor, when signed, -1 under the least word.
  { d.template quotient<Signedness::Signed>(a, b) } -> std::same_as<typename D::Word>;
  { d.template quotient<Signedness::Unsigned>(a, b) } -> std::same_as<typename D::Word>;
  { d.template remainder<Signedness::Signed>(a, b) } -> std::same_as<typename D::Word>;
  { d.template remainder<Signedness::Unsigned>(a, b) } -> std::same_as<typename D::Word>;
  // By an amount below the width.
  { d.shiftLeft(a, b) } -> std::same_as<typename D::Word>;
  { d.template shiftRight<Signedness::Signed>(a, b) } -> std::same_as<typename D::Word>;
  { d.template shiftRight<Signedness::Unsigned>(a, b) } -> std::same_as<typename D::Word>;
};

// Idris's div and mod: Euclidean when signed (the remainder in [0, |b|)),
// the naturals' when unsigned. The guard has refused a zero divisor.
template <Signedness S, DivPart P, Domain D>
constexpr typename D::Word divide(const D &d, typename D::Word a, typename D::Word b) {
  using enum Signedness;
  if constexpr (S == Unsigned) {
    if constexpr (P == DivPart::Quotient) return d.template quotient<Unsigned>(a, b);
    else return d.template remainder<Unsigned>(a, b);
  } else {
    const auto zero = d.constant(0), one = d.constant(1);
    const auto least = d.constant(std::uint64_t{1} << (d.width() - 1));
    // The least word over -1 divides by 1 instead: the least word and 0, the
    // Euclidean pair wrapped to the width.
    const auto by = d.select(d.both(d.eq(a, least), d.eq(b, d.constant(~std::uint64_t{0}))), one, b);
    const auto q = d.template quotient<Signed>(a, by);
    const auto r = d.template remainder<Signed>(a, by);
    const auto behind = d.template less<Signed>(r, zero);   // truncation left a negative remainder
    const auto upward = d.template less<Signed>(zero, by);
    if constexpr (P == DivPart::Quotient)
      return d.select(behind, d.select(upward, d.sub(q, one), d.add(q, one)), q);
    else
      return d.select(behind, d.select(upward, d.add(r, by), d.sub(r, by)), r);
  }
}

// Idris's shifts, total in the amount: masked so no shift is undefined, the
// fill from the width up; a negative signed amount turns the direction (the
// least amount stays negative, a huge count, so it fills).
template <Signedness S, Way W, Domain D>
constexpr typename D::Word shift(const D &d, typename D::Word a, typename D::Word amount) {
  using enum Signedness;
  const auto zero = d.constant(0), width = d.constant(d.width()), mask = d.constant(d.width() - 1);
  auto moved = [&]<Way M>(typename D::Word places) {
    const auto huge = d.negation(d.template less<Unsigned>(places, width));
    const auto masked = d.bitAnd(places, mask);
    if constexpr (M == Way::Left) return d.select(huge, zero, d.shiftLeft(a, masked));
    else {
      const auto fill = S == Signed ? d.template shiftRight<Signed>(a, mask) : zero;
      return d.select(huge, fill, d.template shiftRight<S>(a, masked));
    }
  };
  constexpr Way other = W == Way::Left ? Way::Right : Way::Left;
  if constexpr (S == Unsigned) return moved.template operator()<W>(amount);
  else {
    const auto turned = d.template less<Signed>(amount, zero);
    const auto places = d.select(turned, d.sub(zero, amount), amount);
    return d.select(turned, moved.template operator()<other>(places), moved.template operator()<W>(places));
  }
}

// An integer as a Char: the word already widened to 64 bits as its
// signedness says, itself if a Unicode scalar value, else 0. A negative
// signed word widened is above 0x10FFFF read unsigned, so one test serves both.
template <Domain D>
constexpr typename D::Word toChar(const D &d64, typename D::Word x) {
  using enum Signedness;
  auto atMost = [&](std::uint64_t k) { return d64.negation(d64.template less<Unsigned>(d64.constant(k), x)); };
  const auto low = atMost(0xD7FF);
  const auto high = d64.both(d64.negation(d64.template less<Unsigned>(x, d64.constant(0xE000))), atMost(0x10FFFF));
  return d64.select(d64.either(low, high), x, d64.constant(0));
}

// The integers at a width up to 64, as constants: the runtime, the folder,
// and the laws checked when the compiler is built.
template <unsigned W> requires (W >= 1 && W <= 64)
struct Fixed {
  struct Truth { bool value; };   // read only by Fixed's own select
  using Word = std::uint64_t;     // the low W bits; the rest zero
  static constexpr Word mask = W == 64 ? ~Word{0} : (Word{1} << W) - 1;
  static constexpr std::int64_t signedOf(Word a) {
    return W == 64 ? std::bit_cast<std::int64_t>(a) : std::bit_cast<std::int64_t>(a << (64 - W)) >> (64 - W);
  }
  constexpr unsigned width() const { return W; }
  constexpr Word constant(std::uint64_t k) const { return k & mask; }
  constexpr Word add(Word a, Word b) const { return (a + b) & mask; }
  constexpr Word sub(Word a, Word b) const { return (a - b) & mask; }
  constexpr Word bitAnd(Word a, Word b) const { return a & b; }
  constexpr Truth eq(Word a, Word b) const { return {a == b}; }
  template <Signedness S> constexpr Truth less(Word a, Word b) const {
    return {S == Signedness::Signed ? signedOf(a) < signedOf(b) : a < b};
  }
  constexpr Truth both(Truth p, Truth q) const { return {p.value && q.value}; }
  constexpr Truth either(Truth p, Truth q) const { return {p.value || q.value}; }
  constexpr Truth negation(Truth p) const { return {!p.value}; }
  constexpr Word select(Truth p, Word a, Word b) const { return p.value ? a : b; }
  template <Signedness S> constexpr Word quotient(Word a, Word b) const {
    if constexpr (S == Signedness::Signed) return constant(std::bit_cast<Word>(signedOf(a) / signedOf(b)));
    else return a / b;
  }
  template <Signedness S> constexpr Word remainder(Word a, Word b) const {
    if constexpr (S == Signedness::Signed) return constant(std::bit_cast<Word>(signedOf(a) % signedOf(b)));
    else return a % b;
  }
  constexpr Word shiftLeft(Word a, Word n) const { return (a << n) & mask; }
  template <Signedness S> constexpr Word shiftRight(Word a, Word n) const {
    if constexpr (S == Signedness::Signed) return constant(std::bit_cast<Word>(signedOf(a) >> n));
    else return a >> n;
  }
};
static_assert(Domain<Fixed<8>> && Domain<Fixed<64>>);
}  // namespace rt::arith
```

No undefined behaviour reaches C++'s division: the least-over-minus-one
divisor is replaced before it, and in a constant evaluation undefined
behaviour is a compile error, so the laws below would catch one.

```cpp
// runtime/Arith/Laws.cpp: compiled once; nothing includes it.
using namespace rt::arith;
constexpr Fixed<8> d8;
constexpr std::uint64_t w(int v) { return d8.constant(static_cast<std::uint64_t>(v)); }
static_assert(divide<Signedness::Signed, DivPart::Quotient>(d8, w(-7), w(2)) == w(-4));
static_assert(divide<Signedness::Signed, DivPart::Remainder>(d8, w(-7), w(2)) == w(1));
static_assert(divide<Signedness::Signed, DivPart::Quotient>(d8, w(7), w(-2)) == w(-3));
static_assert(divide<Signedness::Signed, DivPart::Quotient>(d8, w(-7), w(-2)) == w(4));
static_assert(divide<Signedness::Signed, DivPart::Remainder>(d8, w(-7), w(-2)) == w(1));
static_assert(divide<Signedness::Signed, DivPart::Quotient>(d8, w(-128), w(-1)) == w(-128));
static_assert(divide<Signedness::Signed, DivPart::Remainder>(d8, w(-128), w(-1)) == w(0));
static_assert(shift<Signedness::Signed, Way::Right>(d8, w(-128), w(8)) == w(-1));     // the fill
static_assert(shift<Signedness::Signed, Way::Left>(d8, w(2), w(-1)) == w(1));         // turned
static_assert(shift<Signedness::Unsigned, Way::Left>(d8, w(1), w(8)) == w(0));
static_assert(toChar(Fixed<64>{}, 0xD7FF) == 0xD7FF && toChar(Fixed<64>{}, 0xD800) == 0);
static_assert(toChar(Fixed<64>{}, 0x10FFFF) == 0x10FFFF && toChar(Fixed<64>{}, 0x110000) == 0);
// The Euclidean law at every pair of 8-bit words: a == b*q + r (mod 2^8), 0 <= r < |b|.
// One row per dividend, each its own constant evaluation (about 255 divisors x
// two calls, under the 1,048,576-step limit, LangOptions.def:391), instantiated
// in four folds of 64 to stay under the fold's bracket depth (5.5 F19).
template <unsigned A> struct SignedRow { static_assert(signedRowHolds(A)); };
template <unsigned A> struct UnsignedRow { static_assert(unsignedRowHolds(A)); };
// ... sizeof(SignedRow<I>) for I in 0..255, likewise UnsignedRow
```

```cpp
// foreign/idr/include/idr/IR/ArithDomains.h: the compiler's two other domains.
namespace idr::arith {
using rt::arith::Signedness;
// What a range inference knows: upstream's interval functions, so the meaning
// stays the template's and the arithmetic of ranges stays upstream's.
struct Interval {
  struct Truth { std::optional<bool> known; };   // true, false, or either
  using Word = mlir::ConstantIntRanges;
  unsigned bits;
  unsigned width() const { return bits; }
  Word constant(std::uint64_t k) const { return Word::constant(llvm::APInt(bits, k)); }
  Word add(Word a, Word b) const { return mlir::intrange::inferAdd({a, b}); }
  template <Signedness S> Truth less(Word a, Word b) const {
    return {mlir::intrange::evaluatePred(S == Signedness::Signed ? mlir::intrange::CmpPredicate::slt
                                                                  : mlir::intrange::CmpPredicate::ult, a, b)};
  }
  Word select(Truth p, Word a, Word b) const { return p.known ? (*p.known ? a : b) : a.rangeUnion(b); }
  template <Signedness S> Word quotient(Word a, Word b) const {
    return S == Signedness::Signed ? mlir::intrange::inferDivS({a, b}) : mlir::intrange::inferDivU({a, b});
  }
  // remainder: inferRemS/U; shifts: inferShl, inferShrS/U; both/either/negation: Kleene's three values ...
};

// The expansion into arith, at the stage that needs arith (the lowering; 0009's vectorization).
struct Expansion {
  struct Truth { mlir::Value bit; };   // an i1, never read as a C++ bool
  using Word = mlir::Value;
  mlir::OpBuilder &b;
  mlir::Location loc;
  mlir::IntegerType type;
  unsigned width() const { return type.getWidth(); }
  Word constant(std::uint64_t k) const;
  Word select(Truth p, Word x, Word y) const { return mlir::arith::SelectOp::create(b, loc, p.bit, x, y); }
  template <Signedness S> Word quotient(Word x, Word y) const {
    if constexpr (S == Signedness::Signed) return mlir::arith::DivSIOp::create(b, loc, x, y);
    else return mlir::arith::DivUIOp::create(b, loc, x, y);
  }
  // ... each operation one arith op
};
}  // namespace idr::arith
```

The three readers, each one line over the template:
- the folder: `atWidth(type.getWidth(), [&]<unsigned W>(rt::arith::Fixed<W> d) { ... divide<Division<OpT>::sign, Division<OpT>::part>(d, a, b) ... })`,
  where `atWidth` dispatches on the op's type, one of the four widths of
  `Idr_Int` (program data, a four-case switch `specgen` prints from the
  constraint); `x / 1` stays an algebraic fold beside it;
- the range: `setResultRange(getResult(), divide<S, P>(Interval{w}, ranges[0], ranges[1]))`;
- the expansion: `rewriter.replaceOp(op, divide<S, P>(Expansion{rewriter, loc, type}, a, b))`;
- the runtime's small `Integer` path: `divide<Signed, P>(Fixed<64>{}, x, y)`
  (its 63-bit operands never meet the least-over-minus-one case, so the
  select is dead there and folds away).

Which ops the template covers and when they stay ops (D18) is L13's.

### 2.9 No recursion on the input's size (D33)

```cpp
// foreign/idr/include/idr/Support/Nest.h: down a nesting of our own data with
// an explicit stack, which grows on the heap: no input overflows a frame.
namespace idr {
enum class Descend : std::uint8_t { Into, Past };
enum class Visit : std::uint8_t { Enter, Leave };

template <class Node, class Children, class Enter, class Leave>
  requires std::invocable<Children &, Node> &&
           std::same_as<std::invoke_result_t<Enter &, Node>, Descend> && std::invocable<Leave &, Node>
void depthFirst(Node root, Children children, Enter enter, Leave leave) {
  llvm::SmallVector<std::pair<Node, Visit>, 32> stack{{root, Visit::Enter}};
  while (!stack.empty()) {
    auto [node, visit] = stack.pop_back_val();
    if (visit == Visit::Leave) { leave(node); continue; }
    if (enter(node) == Descend::Past) continue;
    stack.push_back({node, Visit::Leave});
    for (Node child : llvm::reverse(children(node))) stack.push_back({child, Visit::Enter});
  }
}
}  // namespace idr
```

The inventory, by what the recursion follows (*read*; found by a self-call
scan, so a recursion through two functions may be missing):

| follows | sites (path: function) | depth grows with | replacement |
| --- | --- | --- | --- |
| tail matches (an `else if` ladder nests one match per branch, D33) | `Tail/TailLoops.cpp`: `forTails`, `reachesTailCall`; `Tail/FramesPlan.cpp`: `framesFrom`; `Tail/Frames.cpp`: `answerTails`; `Tail/Loop.cpp`: `rewriteTail`; `Tail/Trmc.cpp`: `contextsOf`, `rewriteClone`; `Specialize/Raise.cpp`: `push` | branches of a ladder | **none needed**: D30 makes tail position one fact held on each call, so every one of these reads the call's fact instead of finding tails; the recursion is deleted with the deciders |
| region nesting, general | `Ownership/Uses.cpp`: `whereDies`; `Ownership/ExclusivityGraph.cpp`: `scan`; `Ownership/Reuses.cpp`: `visit`, `fits`; `Verify/Linearity.cpp`: `count`; `Canon/CaseOfCase.cpp`: `moves`; `Ownership/Placement.cpp`: `placeOwned`, `placeBorrowed` | nesting depth | upstream's `walk` with `WalkStage` (one pre and one post callback per region), iterative once D33's upstream patch lands; until then nothing of ours stands beside it. Most go whole with their lanes' rewrites (L07's one reverse walk, L08's graph) |
| constant nesting (a run's spine is already iterated: `ConAttr::getRunLength`, `IdrAttrs.td:103`) | `IR/Constants.cpp`: `verifyConstant`; `Analysis/Labels.cpp`: `holds`; `Conversion/StaticData.cpp`: `datum`; `Defunctionalize/Declare.cpp`: `convertConstant`; `Specialize/Patterns.cpp`: `shapeOf`, `rebuild`, `holeTypes`, `countHoles`; `Specialize/Order.cpp`: `oneShape`, `embeds`, `liftPart`; `Specialize/Keys.cpp`: `fill`, `closuresIn` | nesting off the spine | `depthFirst` over the attribute's fields, with the memo the function keeps (`Labels.cpp`'s `known`); `Order.cpp:177` already does one this way ("with no recursion, however deep the constant") |
| type nesting | `IR/ValueFacts.cpp`: `reach` (through a `std::function`); `IR/TypeGraph.cpp`: `forEachNamed`; `IR/DataRemap.cpp`: `describe`; `Verify/Knots.cpp`: `describe`; `Verify/Uses.cpp`: `onlyAtoms`; `Layout/Components.cpp`: `holdsNone`; `Conversion/Frame.cpp`: `mayPoint`; `Conversion/TailPosition.cpp`: `hashOf`, `extract`, `insert`, `isPart`; `Columns/Records.cpp`: `leavesOf`, `reach`, `takeApart`; `Analysis/LabelSites.cpp`: `expand` | a type's depth | a type's recursive facts are bits computed when the type is made (§5.3; D48): uniquing makes a type's parameters before it, so construction order is a topological order and each bit is a load of its parts' bits, no recursion; a mutually recursive group (`#idr.families`) computes its bits once at the group's creation. `describe` (diagnostics) becomes `depthFirst`; `DataRemap` goes with D48 |
| dataflow chains in one function | `Analysis/IdentitiesRebuilds.cpp`: `fill`, `rebuilds`; `Analysis/IdentitiesRecord.cpp`: `intern`; `Analysis/BindingTimes.cpp`: `eval`; `Ownership/Exclusivity.cpp`: `proves`; `Ownership/Borrows.cpp`: `own`; `Tail/AccumulatorPlan.cpp`: `dependsOnSelfCall`; `Inline/Inline.cpp`: `dispatched` | a chain's length | ids in pre-order are topological (§2.2), so a memo filled by recursion is a forward loop over ids; across calls, `summarize` over SCCs (§2.5) |
| location trees | `Defunctionalize/Forces.cpp`: `placesIn`; `Expect/Named.cpp`: `locationNames` | inlining depth | `depthFirst` over a location's children |
| bounded by a constant | `IR/Asm.cpp`: `treeSize` (at most `aliasFrom` = 256 nodes, `:55-63`) | — | stays: its depth is a constant of the code |
| our records, not a program | `tools/idris-mlir-tblgen.cpp` (eight functions and `walk` at `:261`) | — | deleted with the generator (D16, D51) |
| upstream | `detail::walk` (`Visitors.cpp:21-59`), the attribute parser and printer, alias collection, `AttrTypeWalker`, `AttrTypeReplacer` (`upstream/10-recursive-attribute-parser/README.md`) | nesting | D33's upstream patch, carried (D25); its test is `tests/upstream-recursive-attribute-parser` (`PINS.md:604-606`) |

### 2.10 Every runtime dispatch that survives

Dispatch on program data (which alternative a value holds, a type read
off an operand, an id) is not a dispatch on a static fact; it is listed
last. Every row else is either upstream's open set or the machine.

| # | site | why it cannot be compile-time | cost and bound |
| --- | --- | --- | --- |
| D1 | `Operation *` → `OpIndex` through `IndexedOp` (CTC §2.3(a)) | the op set is open to `Operation *`, and `TypeID` is an address (`InterfaceSupport.h:268-283`) | one binary search of the op's interfaces, once per op per walk; every per-op fact after it a load |
| D2 | upstream interfaces on upstream ops (`RegionBranchOpInterface`, `BranchOpInterface`, `CallOpInterface`, `MemoryEffectOpInterface`; `hasTrait<ReturnLike>`) | upstream's facts are in upstream's interfaces | once per op per extraction, never per pair (PS C10) |
| D3 | `Model<ConcreteOp>` calls behind D1 and D2 | MLIR's monomorphization point (5.5 F16) | one indirect call per question |
| D4 | the rewrite and conversion drivers; `TypeConverter`'s `std::function`s; `ConversionTarget` callbacks | upstream's drivers and API | built once per pass at T2 |
| D5 | the pass manager: virtual `runOnOperation`, the adaptor's per-op dispatch, the diagnostic handler's order map | upstream's open pass hierarchy | per op of a nested pass |
| D6 | callbacks MLIR erases: `walk`, `replaceUsesWithIf`, `executeAction` (`Actions.h:52-63`), ODS interface methods taking `function_ref` | upstream's API; an interface method cannot be a template | per element; our lambda inlined into the thunk |
| D7 | context uniquing; `SymbolTable` lookups | MLIR's identity of IR | at T2 for constants; at IR creation |
| D8 | parsing and printing; `cl::opt` parsing; `symbolize<E>` | text at the tool boundary | once per entity read |
| D9 | actions' tags and debug counters compared as strings | upstream's format | off unless asked |
| D10 | the thread pool's `unique_function` tasks | upstream's pool | per task |
| D11 | the LLVM backend, lld, the target machine | upstream's | — |
| D12 | the program at T4: a handle slot's alternative, OS calls, the signal handler, the startup check of CPU and page size, simdutf beyond the baseline, a big word's small-or-pointer test | the input and the machine | once at start, or per value where the value varies |
| D13 | the run's interner and a numbering builder's map (§2.2) | program data hashed once | one hash per datum per run |
| D14 | our resources' identity: `nodeOf(const Resource *)` through a virtual of our resource base (`effects.md:733-771`) | an `EffectInstance` names its resource by pointer, from any dialect: the resource set is open | one virtual call; upstream's two resources by two pointer compares |
| D15 | `TaggedAction::print`, `resolveTypeID` (`Actions.h:36-46`) | MLIR's `ActionImpl` requires the override | when an action is printed |
| D16 | the tools' runner: `idris_rt_run_on_stack(void (*)(void *), void *, ...)` (`Stack.h:47-76`) | the runtime's C ABI takes a function pointer | once per tool run |
| D17 | libc++'s extensive hardening checks (`CMakeLists.txt:326`), `IndexVector`'s bound among them | the bound is not in the type (§2.2) | a compare per access; DP-75 |
| D18 | `StagedPass::runOnProgram`, only if I-10's CRTP is refused | ours, kept by a refusal | one virtual call per pass run |

**Program data, for completeness.** `match` over a variant (a jump table,
§3.5 of CTC); `atWidth` over the op's type (§2.8); `Interval::select` on an
unknown truth (a union); a grade or kind read off a type, then a constexpr
table; an id, an array index.

**Deleted, so not listed:** `Labels::Statements`, `specialize::Schedule`,
`Scheduler::RunPipeline`, `DataRemap::Leaf`, `Scc.h`'s successor callback,
the `TypeSwitch` uses (`DataRemap.cpp:36`, `Symbols.cpp:20`,
`Narrow/Ops.cpp:146`, `Nests.cpp:242`), `std::visit`, every `function_ref`
of ours on a static type.

### 2.11 C++26: what the pin supports, what the typecheck host supports, what the design uses

Pinned clang 24.0.0git at `7208ba24` (*read*: `clang/www/cxx_status.html`,
C++2c table); host column: Apple clang 21 as 5.5 measured it (5.5 F2, F6,
the † rows), since `make typecheck` compiles with the host's compiler
(`tools/bootstrap.sh:1145-1160`).

| feature | paper | pin | host | used for |
| --- | --- | --- | --- | --- |
| concepts, `requires` | P0734R0 | Clang 10 | yes (measured) | every template boundary |
| `consteval`, `if consteval` | P1073R3, P1938R3 | 17, 14 | yes (measured) | validators of C++-subject facts; `effectsOf<OpT>()` |
| user-generated `static_assert` messages | P2741R3 | 17 | *conjecture* yes | laws with generated messages |
| `= delete("reason")` | P2573R2 | 19 | yes (measured) | raw indexing of `IndexVector`, `EnumArray` |
| pack indexing | P2662R3 | 19 | yes (measured) | families' type lists |
| deducing `this` | P0847R7 | 18 | yes (measured) | mixins of ours; **never** recursion (D33) |
| `_` placeholder | P2169R4 | 18 | yes (measured) | unused bindings |
| structured-binding packs | P1061R10 | 21, templated contexts | yes (measured) | field-wise joins of product lattices |
| class-type and enum NTTPs | P0732R2 | 12 | yes | `Fixed<W>`; `divide<S, P>` |
| `constexpr` placement new | P2747R2 | 20 | not measured | not used |
| expansion statements | P1306R5 | 23, partial (no iterating form) | **no** | **not used** while typecheck runs on the host: `match` stays the fold form |
| reflection, annotations | P2996R13, P3394R4 | No | No | not used: the specification is our reflection |
| contracts | P2900R14 | No | No | types first |
| constexpr structured bindings; constexpr exceptions; concept template parameters; trivial unions; erroneous behaviour | P2686R5, P3068R6, P2841R7, P3074R7, P2795R5 | No | No | not used |
| library: `std::expected`, `std::span`, `std::to_underlying`, `std::unreachable`, `std::bit_cast`, `views::iota`/`transform` | — | yes | yes (host libc++) | throughout |
| library: `std::function_ref` | P0792R14 | LLVM 24 libc++ | not in the host's libc++ (*conjecture*) | not used: `llvm::function_ref` at MLIR's APIs |
| clang: `[[clang::lifetimebound]]`, `-Wthread-safety` annotations, `#pragma clang poison` | — | yes | yes (*recalled*) | views (§2.2, §2.4), locks, poisoned identifiers |

The pin moves weekly (D25); a feature joins this design only when both
columns say yes.

### 2.12 The compile-time cost plan: the exact measurements

Every number states its commit, preset, machine, `NCPU`, and that the
compiling clang is stage 2 with assertions (`tools/bootstrap.sh:1022-1031`).
Taken once at the starting commit and again after each work unit (§5).

- **M-C1, clean build.** `rm -rf build/dev && /usr/bin/time -l make build PRESET=dev`
  (macOS; `/usr/bin/time -v` on Linux): user plus system CPU, wall, peak
  memory. The same for `PRESET=release`, with the full-LTO link's time
  read separately from `build/release/.ninja_log`.
- **M-C2, per unit.** From that build's `.ninja_log`: `end − start` per
  object; the twenty slowest units.
- **M-C3, inside each unit.** A preset adding `-ftime-trace
  -ftime-trace-granularity=500` (13 DP-59). From each unit's JSON:
  `Total Source` (headers), `Total Frontend`, `Total InstantiateClass`,
  `Total InstantiateFunction`, `Total CodeGen Function`, `Total Backend`;
  summed per unit and across units; and the twenty costliest templates by
  the summed duration of `InstantiateFunction`/`InstantiateClass` events
  per `args.detail`. The summing is an Idris tool of the harness, never
  Python (AGENTS.md; 13 DP-62).
- **M-C4, fan-out.** `ninja -C build/dev -t deps`, counting the units
  that depend on each generated header (`IdrOps.h.inc` and every
  `Generated/*.h.inc`): a specification change to one family rebuilds
  exactly those.
- **M-C5, an edit.** `touch` one generated header, then
  `ninja -C build/dev -n | grep -c ' -c '` (the compiles a change costs)
  and the timed `ninja`; the same after touching a vocabulary header
  (`Support/Id.h`).
- **M-C6, the precompiled header.** M-C1 and M-C3 with the PCH of I-11,
  `Total Source` against M-C3's.
- **M-C7, size.** `size -m build/dev/foreign/idr/idris-mlir` (macOS) or
  `size -A` (Linux); the `.text` of each solver's instantiating unit.
- **M-C8, the new templates.** From M-C3, the instantiation time summed
  per template name: `match`, `summarize`, `divide`, `shift`, `toChar`,
  `effectsOf`, the `TypedEffects` folds; each against 5.5 F12 and F13's
  per-site figures (3 to 4 ms per `match` site, about 1.6 ms per template
  callback).
- **M-C9, the laws.** `runtime/Arith/Laws.cpp`'s time from `.ninja_log`
  (the exhaustive 8-bit rows).
- **M-C10, the gate's compiler.** `make typecheck`'s wall time, on the
  host compiler it runs.
- **M-S1, stack depth (D33).** S1's deep fixtures (a match nested
  10^3, 10^4 and 10^5 deep; an `else if` ladder of as many branches; a
  constant nested as deep off its spine; a type nested as deep) through
  the whole pipeline, once with today's reserved stack, recording the
  pages of the stack region the run touched (the runner reserves it
  `PROT_NONE` and commits as touched, `runtime/Start/Runner.cpp:61-92`, so
  the touched pages at exit are the depth's high-water mark; `mincore` over
  the region, behind the platform layer), and once on the small stack D33
  sets, where a crash names the recursion that remains.

### 2.13 Constructor provenance

| fact | constructed by | who alone may |
| --- | --- | --- |
| `OpIndex`, its count, `IndexOf<OpT>` | `specgen`, from the specification's op list | `specgen` |
| family constants (`Division<OpT>`, `Shift<OpT>`, `Abi<OpT>`, `Guarded<OpT>`) | `specgen`, from family applications | `specgen` |
| `EnumTraits<E>` for the specification's enums | `specgen` | `specgen`; a C++-only closed set (a solver's phase) writes its own, checked by `indexedBy` |
| `Id<Tag>`, `Count<Id<Tag>>` | `Tag::Minter`: `Numbering` per extraction scope; the program graph's builder for `FunctionId` (L14) | the minter |
| `Csr`, `GatedCsr` | `CsrBuilder::finish() &&` | the builder, consumed |
| a `BitSet`'s bits | `mark` (and the solve that owns it) | `raise` only; nothing lowers a bit |
| `Of<OpT>`, `EffectRules<OpT>`, the projection and LLVM tables | `specgen` from `Spec.Effects` | `specgen` |
| an op instance's `EffectSet` | the `TypedEffects` trait over generated rules and four hand predicates | that trait |
| a function's and a call's `Row` | `derive` (hand C++ over generated tables), written by the one writer | the writer; the verifier re-derives to check |
| D41's meaning | `runtime/Arith/Arith.h` | that header |
| `Interval`, `Expansion` domains | `ArithDomains.h` | that header |
| an `Exclusive` handle (§3) | `asExclusive(Value)`, a parse of the value's type | the parse; exclusivity's write-back (L08) is what makes such a type |
| a reuse `Token` handle (§3) | counting's forward walk, from a drop it turns into a recycle (C1) | that walk (L07) |
| interned keys | `Interner::intern` | the interner |
| pass constants | `initialize`, at T2 | the pass |

### 2.14 Consumers, errors, cleanup

- `mark` and `summarize<Exact>` cannot fail: no `LogicalResult`, no
  budget; their termination is the lattice's height (finite) or the
  graph's size. `summarize<Budgeted>` writes `top()` for every unfinished
  function when its count runs out, and reports success (AGENTS.md: a
  spent budget leaves the program less optimized and never rejects it).
- A `Numbering` is freed by `finish() &&`; after it no map keyed by an IR
  handle remains. An `Interner` lives for the run. Pass constants live as
  long as the pass clones that share them.
- The effect API's failures are none: an op of another dialect that
  declares nothing is `everything()`, a value, not an error.
- D41's template has no failure path: its preconditions (a nonzero
  divisor, a width of 1 to 64) are a guard op's refined result and the
  `Idr_Int` constraint, both checked where they are made.
- A recursion that remains after §2.9 and overflows the small stack is
  the tool's internal error, named by the exhaustion handler
  (`Stack.h:33-41`), never a refusal.

### 2.15 What it deletes

`include/idr/Support/{Scc.h,Worklist.h}` and `lib/Support/Scc.cpp` (the
copied graph, the per-node vectors, `FiniteLattice`'s `bool` join,
`MonotoneWorklist`'s `DenseMap<T, Entry>`); `IR/Ops.cpp:205-294`
(`idrisDivMod`, `idrisShift`, the two concepts and folders, replaced by
one-line folders over the template); `Conversion/Scalars.cpp:57-190`'s
three expansions; `runtime/Big/Arithmetic.cpp:20-33` (`euclidean`);
`IR/OpsScalars.cpp:20-33`'s scalar test; the `bool` family constants in
`IdrScalarOps.td`; `StageFacts`' four `bool`s (`Func.h:83-108`); the
recursive functions of §2.9 (or their recursion); `Verify/Linearity.cpp`'s
`Numbering` and per-value maps; `Stack.cpp:197, 262-267`; CTC's `Gates`
concept and `matchPin`; effects.md's `Node`/`Nodes` vocabulary, `bool
unknown`, `allocOther`, `exact`/`recursive`, `Cache *` nullable parameter;
`StagedPass`'s virtual (I-10). The lanes' rewrites delete the rest of
§1.7.

### 2.16 Essential distinctions that must remain

- Over ops, types and attributes the set is open: interfaces and ODS
  facts. Over our C++ types the set is closed: sums and templates. A
  concept reads an ODS fact; it never lists ops (D47).
- An exact solve and a budgeted one are two types, never a flag.
- A plain edge and a gated edge are two arrays, never a sentinel guard.
- A graph that is frozen (`Csr`) and one that grows during its solve (the
  label solve's append-only vectors) are two shapes (06 §3.2).
- The runtime's header names no LLVM or MLIR; the compiler's domains do.
- Typed and untyped paths of the effect API are two entry points over one
  set, because the op set is open to `Operation *` and closed to `OpT`.

### 2.17 Seams

| with | the declaration both sides write against | state |
| --- | --- | --- |
| L03 (specification, `specgen`) | the generated headers' names and shapes: `EnumTraits<E>`, `OpIndex`, `IndexOf<OpT>`, `Division<OpT>`/`Shift<OpT>` (with `Signedness`, `DivPart`, `Way`), `Of<OpT>` with `Rules` and `Bodies`, `EffectRules<OpT>`, `atWidth`'s four cases, the `Idr_DeclaredEffects` trait | fixed by this file's §2.3, §2.7, §2.8; L03 prints them |
| L01, L02 (effects) | `ResourceId`, `Kind`, `Atom`, `Rules`, `Bodies`, `EffectSet`, `Row`, `RegionEffects`, `derive`, `RowProblem` | names fixed by D27-D29; content theirs. Unfixed, theirs to settle: one-source §5 puts the row in the function type, against D20's "on its op"; §5.1's "five forms, exactly one per op" against `idr.match`'s recursive and typed declaration (I-2) |
| L13 (ops, primitives) | `divide<S, P>`, `shift<S, W>`, `toChar` and the ops each covers | fixed here; the op set theirs |
| L11 (runtime) | `runtime/Arith/Arith.h` and `Laws.cpp` in the runtime's tree; the runtime's typed core (`inc<K>`) | header fixed here |
| L14 (program graph, solver layer) | `Graph`, `Csr`, `CsrBuilder`, `GatedCsr`, `mark`, `summarize`, `SummaryProblem`, `ProgramGraph`'s `FunctionId` minter, how an SCC walk reaches every node | concepts fixed here; the graph's reachability unfixed |
| L08 (exclusivity) | `GatedCsr` and `mark(GatedCsr)`; the "switch" B §2.9 names beside gates | gate shape fixed here; the switch unfixed |
| L07 (counting) | the reuse `Token` handle and the walk API that mints it | proposed here (§3, I-7) |
| L19 (tests) | refusal fixtures for C++ constructions (`clang -fsyntax-only -Xclang -verify` over snippets that must not compile), S1's deep fixtures | named here; theirs to write |

## 3. QTT

**Where quantities are in the C++ today.**
- *Quantity 0* never reaches the C++ as a value: the frontend emits no
  parameter, field or argument for it (AGENTS.md), and the generated
  `Quantity` enum has no zero case (`IdrBase.td:83-84`: One, Many). Under
  D48, index and lifetime variables are quantity-0 parameters of
  `idr.func` and `idr.call`, held as attributes: in C++ an attribute and a
  `Value` are different types, so an erased binder used as a run-time
  operand is unwritable at the builder. Kept; nothing to add.
- *Quantity 1* is a type (`!idr.lin<T>`, and the types linear by
  themselves: a destination, a cell), read per value by `quantityOf(Type)`
  (`Grades.h:125`, 32 readers, *measured*) and checked by the linearity
  verifier after every pass (`Verify/Linearity.cpp:143-160`).
- *ω* is every other value.
- The grade is a C++ struct of three enums (`Grades.h:39-48`), so the C++
  can hold a grade the specification rules illegal (14 G03: the full
  product); with D40's lifetime variables, part of it is no longer an
  enum at all.

**What a quantity proves that the design still pays for.**
1. *The linearity verifier numbers every op of every function on every
   verification* (`Linearity.cpp:41-66`) to order an error's wording, and
   builds two pointer-keyed maps per linear value (`:135-136`). A value
   with one use, outside any region that repeats, is used once on every
   path by construction: no walk is needed. I-5.
2. *Counting keeps state for quantity-1 values.* A linear value's single
   use on each path is its last use: it never needs a dup, and a drop only
   on a path that does not use it. A `Numbering` for counting that mints
   ids only for ω values makes the state sized by the problem (07 D6's
   "state only for values whose type leaves the question open"); the
   algorithm is L07's, the minting rule is this layer's.
3. *Exclusivity is tested where it is typed.* `isExclusive(Type)` returns
   a `bool` (`Grades.h:91`) that callers test and then build from: a
   validator. A parse handle (below) carries the proof to the builder.

**Representations that make a misuse of a quantity unwritable in a C++ pass.**

```cpp
// foreign/idr/include/idr/IR/Quantities.h
namespace idr {
// A value whose type says it owns its whole cell graph alone (!idr.excl).
// Made only by a parse of the type, so a builder that takes one cannot be
// handed a shared value: the exclusive release reads no count (D10) and its
// builder takes this, not a Value.
class Exclusive {
  mlir::Value v;
  explicit Exclusive(mlir::Value v) : v(v) {}
  friend std::optional<Exclusive> asExclusive(mlir::Value);
public:
  mlir::Value value() const { return v; }
};
std::optional<Exclusive> asExclusive(mlir::Value);   // the boundary: once, where the type is read

// A reuse token in counting's forward walk (C1): moved, never copied, so the
// walk cannot recycle one cell into two constructions. It leaves the walk
// exactly three ways: into a recycle, as a join argument across a rejoin
// (D19), or dropped.
class Token {
  mlir::TypedValue<TokenType> v;
public:
  explicit Token(mlir::TypedValue<TokenType> v) : v(v) {}
  Token(Token &&) noexcept;
  Token(const Token &) = delete("a token is used once");
  Token &operator=(const Token &) = delete("a token is used once");
  [[nodiscard]] mlir::Value consume() &&;
};
// The tokens available at a point, by layout; a rejoin takes both sides by value.
struct Available { llvm::SmallVector<std::pair<LayoutId, Token>> tokens; };
Available rejoin(Available &&left, Available &&right, JoinArgs &out);
}  // namespace idr
```

A C++ view outliving what it views is D39's misuse in C++: every
view-returning accessor of the vocabulary carries `[[clang::lifetimebound]]`
(§2.2, §2.4), so `auto row = buildGraph().successors(n);` is a dangling
warning, an error under `-Werror` (`CMakeLists.txt:344-361`).

What these cannot do: MLIR's generic machinery (clone, `OperationState`,
the conversion driver, `Support/Remake.h`'s `remakeOp`) builds ops without
our builders, so the verifier after every pass stays the complete check of
quantity 1; the handles move the error to compile time on our own paths.
The narrower form is selected (I-7); generated builders taking handles
for every quantity-1 operand were weighed and rejected for that reason.

## 4. Improvements

**I-1. Recursion: the iterative forms D33 rules, and the idiom CTC
prescribes withdrawn.** *Coordinator.*
- *Evidence:* §1.3, §2.9; CTC §3.6 (`compile-time-cpp.md:1285-1290`), 5.5
  D5, 21 P-19 prescribe deducing-`this` recursion.
- *Counterexample:* an Idris function whose body is an `if … else if …`
  of 20,000 branches. Under D19 each branch nests one match in the
  previous one's default region; `Tail/Loop.cpp`'s `rewriteTail` and
  `Tail/FramesPlan.cpp`'s `framesFrom` recurse once per level, 20,000
  frames deep (*conjecture*: some 100 to 200 bytes each, 2 to 4 MB). On
  D33's small stack the tool dies with "the stack is exhausted"
  (`Stack.h:57-59`): an internal error on a valid program.
- *Root cause:* the control stack is used as the representation of the
  input's nesting.
- *Correction:* the four replacements of §2.9 (the tail fact read off the
  call, D30; `walk` patched upstream; type bits at construction; ids in
  topological order and `depthFirst`), and D33's upstream patch carried
  with its scope stated: parser, printer, alias collection,
  `AttrTypeWalker`, `AttrTypeReplacer`, `detail::walk`.
- *Deletes:* the recursion of the 55 functions; CTC's `depth` lambda;
  `PIN(mlir-recursion)`'s large stack once upstream's half lands.
- *Discriminated by:* M-S1's fixtures on the small stack: they fail
  before and pass after.

**I-2. One effect vocabulary in C++, and a declaration's two facts as two
enums.** *Coordinator* (the C++); the sum's content is L01's.
- *Evidence:* §2.7; `effects.md:729-836, 997-1031` against
  `compile-time-cpp.md:583-618` and D27-D29; §5.1's "Five forms of
  declaration, exactly one per op" against `effects.md:528-537`, where
  `idr.match` lists both `RecursiveMemoryEffects` and the typed rule
  `Idr_ReadsMemo<"scrutinee">`.
- *Counterexample:* with one five-case `Form`, `idr.match` must be
  `Recursive` or `Typed`. As `Recursive`, its scrutinee's memo read is
  undeclared, and a match may move across the memo write that forces the
  scrutinee; as `Typed`, it loses `RecursiveMemoryEffects`, and upstream's
  known-case inlining refuses it (`lib/Interfaces/ControlFlowInterfaces.cpp:1224-1228`,
  as effects.md reads it). With effects.md's two `bool`s it is
  representable, but as flags (R6).
- *Root cause:* two independent facts of a declaration (whether its own
  effects follow from types; whether its bodies' effects are its own)
  written once as one sum and once as two booleans.
- *Correction:* `Rules { None, Typed }` and `Bodies { Own, Recursive }`;
  "runs unknown code" a static row of every effect, as effects.md already
  declares it; a definition no `Of<>` at all. `EffectSet` without `unknown`
  and `allocOther`; `RegionEffects &` in place of `Cache *`; D28's names.
- *Deletes:* `Node`, `Nodes`, `exact`, `recursive`, `unknown`,
  `allocOther`, the nullable cache parameter; §5.1's "exactly one per op"
  wording, to be corrected with L01.
- *Discriminated by:* the types: `StaticEffects` reads both enums, and an
  op whose specification states both facts gets both, which a test of
  `idr.match`'s effects (a memo write not moved across it, its known case
  inlined) observes.

**I-3. Gates as nodes, not a callback.** *Coordinator.*
- *Evidence:* CTC's `Gates` concept takes `opens(from, to, marked) ->
  bool` with "monotone: open stays open" as a comment
  (`compile-time-cpp.md:1118-1125`); B §2.9 states the gate as a node
  (`B-analyses.md:171-172`).
- *Counterexample:* a gate written `opens = !marked.test(g)` compiles
  under CTC's concept. The marking then depends on the order nodes rise:
  two thread counts, or two orders of one SCC level, give two answers, and
  an exclusivity verdict (a refusal, D24) changes with the schedule.
- *Root cause:* monotonicity is a law of the callback, not a property of
  the data.
- *Correction:* `GatedCsr` (§2.4) and one Horn-propagation loop.
- *Deletes:* the `Gates` concept and every gate callback.
- *Discriminated by:* the type: a guard is an id of a `BitSet` that only
  rises, so a non-monotone gate cannot be written.

**I-4. D41's template unbranchable, in the runtime, over three domains.**
*Coordinator.*
- *Evidence:* §1.4, §2.8; `Value.h:100`.
- *Counterexample:* §1.4's: with a builder domain, `if (d.less(r, zero))`
  takes the first branch for every input, and `idr.divs -7, 2` lowers to
  -3 instead of -4.
- *Root cause:* a domain's truth value converts to `bool`.
- *Correction:* the `Domain` concept requiring a `Truth` that no `bool`
  is constructible from; `divide`, `shift`, `toChar` written over
  `select`; `Fixed<W>` in `runtime/Arith/Arith.h` (no `APInt` in the
  folder); `Interval` over upstream's `intrange`; `Expansion` over
  `arith`; the 8-bit law checked exhaustively.
- *Deletes:* the three copies (§2.15).
- *Discriminated by:* the concept (a domain whose truth converts does not
  satisfy it), and `Laws.cpp`'s `static_assert`s.

**I-5. The linearity verifier on its success path: no numbering, a
quantity's fast path, no recursion.** *Coordinator.*
- *Evidence:* `Verify/Linearity.cpp:41-66, 70-140, 143-160`; 13 §2.3 counts
  up to 26 program verifications and up to 19 re-verifications of every
  function per compile.
- *Counterexample:* a function of 100,000 ops with ten linear values:
  each verification inserts 100,000 entries into a `DenseMap` (about
  16 bytes each plus buckets, *conjecture* a few MB) and frees them, after
  every pass, to sort the uses of a value whose use count is one.
- *Root cause:* the order of an error's wording is computed on the path
  that reports no error.
- *Correction:* sum the uses unordered; number and sort only when the sum
  exceeds one; skip a value with one use whose ancestors up to its home
  region repeat nothing; ask "the regions exclude each other" once per op
  class (a constant of `OpIndex`, or `getRegionInvocationBounds`, which the
  match ops override, `IdrMatchOps.td:29, 84`); walk with `walk`, not
  `count`'s recursion.
- *Deletes:* `Numbering`, `holders`, `byBlock`, `verify::alternatives`'s
  per-query vectors.
- *Discriminated by:* the same errors on today's fixtures (the verifier's
  verdict is unchanged), and the verifier's share of `-mlir-timing` on a
  large module before and after (13 §8 M1's method: a pass's row less its
  `PassExecutionAction` spans).

**I-6. CTC corrected to D16, D48 and the typecheck host.** *Coordinator.*
- *Evidence:* §1.1, §1.6, §2.11; `tools/bootstrap.sh:1126-1160`.
- *Counterexample:* landing CTC's `matchPin` breaks `make typecheck` on a
  host whose clang lacks expansion statements (5.5 F1): every change then
  fails the gate that is the only C++ check on a machine that cannot build
  LLVM.
- *Root cause:* the design was written against the pinned clang, while
  one gate compiles with another.
- *Correction:* T0 is the specification; R1 is one Idris definition; R4's
  cross-record checks are proofs; `static_assert` only on C++-subject
  facts; no feature unless both columns of §2.11 say yes; CTC §2.3(c)'s
  sealing and three-lifetime laws re-based on D48 and D40.
- *Deletes:* CTC §2.2's C++ generator model, `matchPin`, the re-proofs.
- *Discriminated by:* `make typecheck` on the host, green.

**I-7. Quantity handles on our own paths.** *Coordinator.*
- *Evidence:* §3; 9db9813d's 1088 verifier errors came from a field
  read twice after its uses moved (21 P-15).
- *Counterexample:* counting's forward walk meets a rejoin whose two
  arms each hold a token of one layout and passes the left one to both
  the join argument and a recycle after the rejoin: one cell becomes two
  live values, which the verifier catches after the pass at best.
- *Root cause:* a quantity-1 IR value held as a copyable `mlir::Value` in
  the pass.
- *Correction:* `Exclusive` and `Token` (§3); the exclusive release's
  builder takes `Exclusive`.
- *Deletes:* the `isExclusive`-then-build validators on those paths.
- *Discriminated by:* a refusal fixture: a snippet copying a `Token`
  fails to compile with "a token is used once" (`-Xclang -verify`).

**I-8. A budget writes top.** *Coordinator.*
- *Evidence:* CTC's `Optimization{steps}` with no pessimistic value
  (`compile-time-cpp.md:1110-1113, 1139-1141`).
- *Counterexample:* an inline-facts summary solve stops mid-SCC at its
  budget; the members not yet visited keep `bottom`, the optimistic start
  of a solve that grows toward its answer (*conjecture* on that lattice's
  orientation), and a caller acts on a member's summary that its body
  contradicts: a miscompile rather than a less optimized program.
- *Root cause:* stopping is allowed without a sound value to stop at.
- *Correction:* `Budgeted` requires `Bounded` (`top()`), and `summarize`
  writes it for every unfinished function; `Exact` for rows (L02) as for
  refusals.
- *Deletes:* nothing.
- *Discriminated by:* the concept: a budgeted problem without `top()`
  does not compile.

**I-9. The marking compiled once.** *Coordinator; simplification.*
- *Evidence:* CTC instantiates `mark<D, G, Gates>` per graph type with
  `extern template` (`compile-time-cpp.md:1145-1158`).
- *Counterexample:* three markings (stack, borrows, exclusivity) over
  three tags compile three copies of one loop; each new client adds one,
  and identical-code folding is not on every target's linker.
- *Correction:* tags shed at an inline wrapper; `markRows` and
  `markGated` are ordinary functions (§2.6); `extern template` is kept
  for what must inline a transfer (`summarize`).
- *Deletes:* the per-tag instantiations and their `extern` lines.
- *Discriminated by:* M-C7 and M-C8: one symbol for the loop.

**I-10. `StagedPass` as CRTP, the upstream name carried as a patch.**
*Coordinator.*
- *Evidence:* `Pipeline.h:44`'s virtual; CTC's CRTP relies on upstream's
  generated `template <typename DerivedT>` (`mlir/tools/mlir-tblgen/PassGen.cpp:194-200`),
  which no upstream `.td` uses in a `baseClass` (*measured*: no match in
  `mlir/include`).
- *Counterexample:* upstream renames the parameter; our build breaks with
  an error in generated code no reader can trace to a decision.
- *Correction:* a small carried patch documenting `DerivedT` in
  `PassBase.td`'s `baseClass` (with an upstream test and plan, D25), then
  `StagedPass<DerivedT, …>` calls `static_cast<DerivedT &>(*this).runOnProgram`.
- *Deletes:* the last virtual of ours.
- *Discriminated by:* the patch's upstream test; our build.

**I-11. The precompiled header holds upstream's headers and our
generated declarations, not our vocabulary.** *Coordinator.*
- *Evidence:* CTC §7.2 (ours in) against G DP-74 (none of ours); 263
  files include `IdrDialect.h`, which carries `IdrOps.h.inc` (38,361
  lines, 13 §2.7).
- *Counterexample:* with none of ours in it, every unit still parses the
  38,361 lines (the dominant header of ours); with the vocabulary in it,
  an edit to `Support/Id.h` rebuilds the PCH and all 294 units, and a
  missing include of `Id.h` stops being an error.
- *Correction:* PCH = libc++, LLVM ADT, MLIR's `pch.h` set,
  `IdrDialect.h`; the vocabulary headers stay outside. A spec change to
  ops rebuilds every includer of `IdrOps.h.inc` anyway (M-C4), so putting
  it in the PCH widens no rebuild.
- *Deletes:* nothing.
- *Discriminated by:* M-C6 against M-C3, and M-C5 for an edit of `Id.h`.

**I-12. The `bool` choices and the stored callbacks.** *Coordinator.*
- *Evidence:* §1.7.
- *Counterexample:* `StageFacts(true, false, false, true)`: 16
  representable states of which 5 are stages (03 O-61); a construction
  with `closures = true, grades = true` names no stage and no check
  refuses it.
- *Correction:* each to a sum or an enum (WU-6).
- *Deletes:* §1.7's rows.
- *Discriminated by:* the types.

## 5. Work units (draft; none dispatched)

| unit | exclusive write set | outcome | deletes | must not | acceptance |
| --- | --- | --- | --- | --- | --- |
| WU-1 the vocabulary, with its first client | `foreign/idr/include/idr/Support/{Id,Enum,Match,Nest}.h`, `include/idr/Solve/{Graph,Lattice,Mark}.h`, `lib/Solve/Mark.cpp`, `include/idr/Analysis/Numbering.h`, `lib/Transforms/Stack/Stack.cpp` (the first client) | the stack inference on `Csr`, `mark<Backward>`, `BitSet` | `Stack.cpp:197, 262-267`; `Support/Worklist.h` once its users move | land a header with no client; add a map keyed by an IR handle outside `Numbering` | builds and passes on four targets; the stack fixtures unchanged; a snippet indexing an `IndexVector` by an `int` fails with its `delete` message |
| WU-2 recursion | the files of §2.9's region, constant, type, dataflow and location rows not owned by another unit | every listed recursion replaced as its row says | the recursion; `ValueFacts.cpp:241`'s `std::function` | leave a recursion on input size; reverse a ruling | M-S1's fixtures pass on D33's small stack |
| WU-3 D41 | `runtime/Arith/{Arith.h,Laws.cpp}`, `foreign/idr/include/idr/IR/ArithDomains.h`, `lib/IR/Ops.cpp:205-294`, `lib/IR/OpsScalars.cpp:20-60`, `lib/Conversion/Scalars.cpp:57-190`, `runtime/Big/Arithmetic.cpp:15-140` | one meaning, three domains, ranges for division and shifts | §2.15's arithmetic rows | include LLVM or MLIR in the runtime header; branch on a domain truth | `Laws.cpp` builds; programs dividing and shifting at every width give the committed outputs; range inference narrows a division by a constant |
| WU-4 the effect API's C++ | `include/idr/IR/Effects.h`, `lib/IR/Effects/`, `lib/IR/Effects/RowSolve.cpp` | §2.7 over L01/L02's generated tables | `lib/IR/Effects.cpp`'s classifiers; `Analysis/Effects.h`'s readers (with L02) | name a resource outside the generated enum; read an `EffectInstance` list outside the API | the effect fixtures (06 §8 risk 5) unchanged; one symbol for the row solve |
| WU-5 the linearity verifier | `lib/IR/Verify/Linearity.cpp` | I-5 | `Numbering`, the per-value maps, per-query `alternatives` | change a verdict | today's linearity fixtures give the same errors at the same ops |
| WU-6 choices as types | `include/idr/IR/Func.h:65-111`, `include/idr/IR/IdrDialect.h:150-166`, `include/idr/IR/Layout.h:80-95`, `lib/Analysis/Inline.cpp`, `lib/Transforms/Ownership/Placement.cpp:184-250`, `include/idr/Transforms/SpecializeState.h`, `lib/IR/OpsChecks.cpp:59-90`, `lib/Transforms/Expect/{ByName,Does,Proved}.cpp`, `include/idr/IR/TypeGraph.h` | every `bool` of §1.7 a sum or an enum | those `bool`s | turn a predicate's answer into an enum for its own sake (a `test` is a question, not a choice) | builds; suites unchanged |
| WU-7 callbacks and virtuals | `include/idr/Transforms/OptimizeScheduler.h`, `lib/Transforms/Optimize/Optimize.cpp:90-100`, `include/idr/Transforms/Pipeline.h`, `upstream/<id>/llvm-project.patch` (the `DerivedT` patch) with its `PINS.md` entry and test | no `std::function` of ours; no virtual of ours | `RunPipeline`, `runOnProgram`'s virtual | keep a virtual "for now" | builds; the patch's upstream test passes |
| WU-8 the build | `CMakeLists.txt:317-361`, `foreign/idr/CMakeLists.txt`, `foreign/idr/lib/IR/CMakeLists.txt`, `CMakePresets.json`, `tools/bootstrap.sh:255-275` (ccache sloppiness) | the PCH of I-11; `-Wthread-safety`, `-Wcovered-switch-default`, `-Wsuggest-override`, `-Werror=global-constructors` (after 13 DP-49); the poison pragma, one identifier per commit that deletes its last use | the "ccache cannot cache a PCH" premise | add a non-PCH path | M-C1, M-C3, M-C6 recorded; builds on four targets |
| WU-9 the baseline | `harness/` (the Idris summing tool of M-C3) | §2.12's records at the starting commit | `tools/profile.sh:89-101`'s Python (13 DP-62) | Python, a threshold that stops a step | the records exist, each stating its build |
| WU-10 quantity handles | `include/idr/IR/Quantities.h`, the exclusive release's builder hook, counting's walk API (with L07, L08) | `Exclusive` and `Token` | the validators on those paths | generated builders for every quantity-1 operand | a copy of a `Token` fails to compile with its message; counting's suites unchanged |
| WU-11 the effect API's and solver's refusal fixtures | `tests/cxx-refusals/` (with L19) | snippets that must not compile: raw indexing, a `bool` truth domain, a budgeted problem without `top`, a copied token, a non-monotone gate | — | test output text beyond clang's `-verify` expectations | each snippet refused with its message |

## 6. Owner questions

**OQ-1. Does D10 forbid assertions in the shipped compiler?**
D10 bans testing at run time "a fact ... a pass's construction ... already
knows"; an `assert` re-tests exactly such a fact, and the shipped compiler
links an LLVM and MLIR built with assertions (`tools/bootstrap.sh:1022-1031`),
with ABI-breaking checks in every `DenseMap` iterator of ours (PS §1). The
cost is unmeasured (PS U8; the 12× of PS M12 is a debug build, not
assertions alone).
- *(a) One toolchain, assertions off everywhere, ours as types.* Buys
  D10's letter, the shipped binary is the tested one, one recipe. Costs:
  upstream's internal checks no longer run in our tests, so a misuse of
  MLIR's API (an op erased with uses) is a corruption or a later verifier
  failure instead of an abort at the call; our `assert`s each become a
  type, a verifier rule, or nothing.
- *(b) Two stage-2 builds: assertions for tests, none shipped.* Buys
  upstream's checks in tests and D10 in production. Costs: a second LLVM
  build per target in the bootstrap, and the shipped binary is not the
  tested one, close to the verification split by build type §9 rejects.
- *(c) As today.* Buys simplicity and checks in the field. Costs D10's
  letter and the unmeasured speed.

*Recommendation:* (a), with PS U8 measured first so its price is known,
because it alone keeps both D10 and "the shipped binary is the tested
one", and our own invariants belong in types anyway (the skill).
