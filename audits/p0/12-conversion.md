<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane `conversion`: the lowering to func, memref and LLVM

Scope: `foreign/idr/lib/Conversion/` (except TailCalls, TailCallPlan,
TailPosition, ReturnRegisters: lane 10; Arrays, Elements, Memrefs,
Descriptors, Buffers: lane 11) and `foreign/idr/include/idr/Conversion/`.
Measured at e96bb991 unless said otherwise. Nothing here is built; every
count is over the source, with its command.

## 1. Reading notes

What in the proposal bears on the lowering, by section and finding ID
(*read*, proposal at the working tree of 2026-10-21).

**§1-§4 (directives, brief, history, bar).**
- §1: culling polymorphic ladders and callback plumbing is a named
  directive; the lowering is where the `idr` dialect's op set meets one
  pattern per op, so every ladder of ours over op kinds shows up here.
- §2 brief: `lib/Conversion` is 5,034 lines; the pipeline's tail is
  "narrow, lower to func/memref/vector, entry, the vectorization schedule,
  linalg to loops, upstream's lowering to LLVM, tail calls". `Idr_Runtime<"symbol">`
  ties a primitive op to the runtime function that is its one meaning.
- §3: every design must fit the stage-1 module (70,000 functions, matches
  of tens of thousands of cases). The lowering of a match of N cases is
  where a per-case cost (a block per case, a `cf.switch` of N, a static
  table per constructor) becomes visible.
- §4: order of preference upstream, upstream patched, our solver;
  "declare, don't write"; "no polymorphic ladders ... a callback threaded
  through code that knows its static type is a template or a concept not
  yet written".

**§5.1 mlir-analysis.** Little is analysis-heavy in the lowering, but:
- D2: the greedy driver's DCE and CSE read effects; the lowering's
  output (`func`, `memref`, `llvm`) is re-canonicalized upstream, so
  runtime calls we emit as `func.call`/`llvm.call` have unknown effects
  unless declared (bears on `Runtime.cpp`'s call emission).
- F3: no attribute or type created on a hot path; the lowering creates
  `StringAttr` symbol names per runtime call and per static datum
  (bears on `StaticNames`, `Mangle`).
- C1-C4: a match of N cases lowered through `RegionBranchOpInterface`
  per region is O(N^2); our lowering of `idr.match` must enumerate
  edges once per op.
- G3: ownership-based deallocation emits *runtime conditions* where
  static knowledge runs out and simplifies them later: the model for
  rc-Q2's run-time uniqueness test and for `LowerTake`'s branch.

**§5.2 mlir-ods.**
- A1-A6, row 1-3: effects declared in ODS; a runtime call's effects
  come from the op it lowers, which the lowering throws away when it
  emits a bare `func.call` (to be checked in `Runtime.cpp`).
- A9: consumption = `Read`+`Free` on the operand (transform dialect);
  bears on how `drop`/`take` lower.
- E1: pattern roots decide cost; a `MatchAnyOpTypeTag` pattern in a
  conversion is visited on every op. Check every pattern in our
  conversion for its root.
- E6: one-shot dialect conversion (`allowPatternRollback = false`):
  no rollback state, fatal on a pattern that fails after modifying IR.
  Directly applicable to our conversion driver (to be checked which
  mode and which driver we use).
- M7, row 12, sketch at 5.2.3: `Idr_Runtime<"symbol">` becomes a
  `NativeOpTrait` injecting `static constexpr StringLiteral
  getRuntimeSymbol()`, read by an interface `RuntimeFunction`'s
  `StaticInterfaceMethod`, and **"the one lowering of every primitive to
  its runtime call is then a single `OpInterfaceRewritePattern<RuntimeFunction>`"**.
  This is the central claim for `Runtime*.cpp` and is reconciled in §3.
- M8, row 23: op families from lists (platform ops, per-signedness word
  ops, conversions), each carrying its runtime symbol; the lowering
  then has no per-family pattern.
- M13: DRR yes, PDLL no; DRR generates op-rooted native patterns. A
  lowering of `idr.X` to `arith.Y` one to one is a DRR candidate.
- Design 2 (rooted rewriting): "lowering to runtime calls on the walk
  driver"; the greedy driver only for canonicalization.
- F3 (llvm intrinsics): a per-op translation carried as a record field
  (`llvmBuilder`) generates a `dyn_cast` chain; the proposal prefers an
  interface-rooted pattern.

**§5.3 llvm.**
- B2, I2: "a per-pass table over ops is a `TypeSwitch` with
  `DefaultUnreachable`", never an `if`/`else if` chain of `dyn_cast`.
  A lowering is the canonical place where "the ops this translation
  knows" is a per-pass table; but a classification more than one pass
  reads is still a trait or interface. Applies to every op-kind ladder
  in `Conversion/`.
- B3, I3: `get_if`/`holds_alternative` chains become one `std::visit`
  over an overload set; bears on any variant in the runtime-call layer
  (e.g. a call's argument kinds) and in static data.
- B4, I4: sums of handles are `PointerUnion`.
- B5, I5: a hot callback is a template, a cold one `function_ref`; a
  callback into code that knows its static type is a template. Bears
  on every `function_ref` in `Conversion/` (counted in §2 below).
- B6: `zip_equal`, `enumerate` replace parallel lists matched by
  position (e.g. operand lists and converted types).
- E1, E2, I8: a C++ list mirroring records is generated
  (`!instances`, `GenericTable`, our backend). The runtime symbol table
  and any op-to-runtime list are I8's case.
- M10: switches on our enums in several places are generated.

**§5.4 modular.**
- F9: Modular uses `DialectConversion.h` in 6 files: upstream
  conversion is the norm for a large MLIR compiler's lowering.
- F12: 15 `Arg`/`Res` effects, `pop.aligned_alloc` with
  `Res<..., [MemAlloc]>` and `aligned_free` with `Arg<..., [MemFree]>`
  (§5.4.5 note to §5.8): the shape our cell allocation and free should
  take at the level just above the runtime call.
- F17 (not to take): two implementations behind an option; facts in
  discardable attributes. Checked in our lowering (§4).
- Design 7: answers that carry what was learned (`TriResult`) rather
  than a `bool` plus a side output; bears on the lowering's helpers that
  return `bool`/`LogicalResult` with a fact discarded.

**§5.5 cxx26.**
- D1 (rank 1): dispatch once where the set is open (an interface, a
  trait, a rooted pattern), then typed code below it. Its own example is
  a *lowering*: `Idr_ConsumeLowering`, an interface whose
  `defaultImplementation` calls `::idr::lowerConsume($_op, rewriter)`, a
  template constrained by `ConsumingOp` reading the ODS trait. "Never a
  C++ concept or an `isa<A, B, C>` that lists op classes."
- D2: closed sums via one `match`; `holds_alternative`/`get_if` banned
  outside `match`. Finding 12: `std::visit` over more than 11
  alternatives goes through a function-pointer matrix.
- D4a: "An op's runtime symbol (`Idr_Runtime<"symbol">`), its refusal
  category, its effect row: each is emitted to C++ and to Idris from the
  one record, never typed into a C++ `switch`." D4b: a C++-only list is
  one `constexpr` table checked by `consteval`.
- D8: `LogicalResult`/`FailureOr` at MLIR boundaries; `llvm::zip_equal`
  rather than `zip` (which truncates silently, "a check thrown away").
- Finding 18: interface- and trait-rooted patterns are indexed per op at
  freeze; a hand list of per-op patterns buys nothing over
  `OpInterfaceRewritePattern`.

**§5.6 ecosystem.**
- F2: **ClangIR generates its LLVM lowering from ODS fields**
  (`hasLLVMLowering`, `llvmOp`, `extraLLVMLoweringPatternDecl`) through
  a backend (`CIRLoweringEmitter.cpp`) that emits one pattern per op and
  the registration list. "The fact 'this op lowers to that LLVM op' is
  one ODS field." Direct precedent for generating our one-to-one
  lowerings (scalar, word, check, platform) and the pattern list.
- E4 / 5.6.5 note to §5.2: HLFIR's 24 hand `getEffects` because effects
  depend on operand types: a case the redesign should make
  unrepresentable.
- Item 9: queries on a big region op answered once per op (bears on
  how `idr.match` lowers: one switch built per op, not per case).
- D6: an analysis answer written into a type once; "the type should
  hold the answer's own bits, not a lossy summary" (bears on how
  counting's answers reach `LowerTake` and the cell lowering).

**§5.7 library.** B4: Bhat and Grosser lower Lean's lambda-rc through
MLIR with case alternatives as regions; the shape of our match lowering.
B3: no whole-module use-def chains; symbol references (runtime symbols,
static data names) are the interprocedural relation. M11: rooted
patterns are an index; an any-op pattern is a full scan.

**§5.8 dialect-design (read most carefully).**
- O4: "A lower form is another op, often of another dialect, never a
  flag on the high one ... our ops that exist only before or only after a
  pass are legal or illegal through `ConversionTarget`, not through
  attributes." Directly the lowering's contract.
- O5: "compose before fusing": `io.put_sint %x` is `io.write
  (str.show_sint %x)`, **fused at lowering when the runtime has a faster
  entry point**. Puts a fusion decision into the lowering.
- O2/C3: `cell.new`/`cell.stack` as one `AllocLikeOp`-style class
  parameterized by the resource; the lowering then has one pattern
  family for allocation, the resource deciding heap call or `alloca`.
- C6: `cf.assert` writes the default resource; `ub.unreachable` is a
  terminator with no effect. DS4: `check.nonzero/in_bounds/nonempty/
  finite/range` become `arith.cmpi`/`cmpf` plus one `idr.check %cond,
  <reason>` (cf.assert's shape with a reason enum); `check.crash`/
  `crash_str` become one terminator `idr.crash`. Our check lowering
  (`Checks.cpp`) is the place this lands.
- DS4 word ops: `divs/divu/mods/modu/shrs/shru` become `arith.*` where
  the runtime's meaning agrees on every input it defines, with Idris's
  edge cases as `idr.check` or `arith.select`; `shls`/`shlu` one op.
  Our `Scalars.cpp`/`Words.cpp` hold today's per-op lowering (checked
  in §3).
- DS4: six stat-time ops to one `io.file.stat` with several results;
  eight clock ops to one `io.clock <kind>`; `put_*` to `str.show_*`
  plus `io.write`. Each shrinks the runtime-call layer's table.
- DS4: `match_lit` on words to `scf.index_switch` or `cf.switch`;
  `func`/`call`/`return` to `func.*` unless `!idr.fn` carries
  conventions and effects. `Idr_Runtime<"symbol">` kept: "it is the op's
  one meaning"; `Primitive` implied by it.
- DS1: the grade becomes `!idr.g<T, #grade>`, unrestricted = `T`; the
  lowering's type converter then strips one wrapper kind, not four
  parameters.
- DS2: no world value after the frontend; the lowering then has no world
  operand to drop.
- DS3: the data table as an immutable attribute on `program`, types
  naming entries by index; our layout and static-data code reads it.
- **DD-Q5 (mine, evidence in §6):** "May one op with an enum
  (`io.clock <kind>`, `idr.check <reason>`) map to several runtime
  functions, selected by a table generated from ODS, where
  `Idr_Runtime<"symbol">` ties one op to one function today?"
- W-items for wave 2 bearing on me: "which word ops differ from `arith`
  on inputs the runtime defines ... why `shls` and `shlu` are two ops";
  "every op with a `UnitAttr`, an optional operand or an enum, and
  whether it changes effects" (for ops the lowering reads).

**§5.9 mlton.**
- F6: representation chosen once per program, **per type**, as sums
  (`TyconRep = One | Objptrs | Small | SmallAndBox | ...`, `ConRep =
  ShiftAndTag | Tag | Tuple`) whose constructors carry only what that
  representation needs; the translation asks it through a record of
  functions (`genCase`, `object`, `select`, `update`, `toRtype`).
  RSSA's `Switch` is a flat sorted vector of `(WordX, Label)`. This is
  the model our layout-driven lowering (`Fields`, `Matches`, cells)
  should be checked against: is the representation decided once per
  type and asked, or rederived per op?
- Design 2 / M3: after defunctionalization a match is a terminator with
  produced successor operands (`BranchOpInterface`); "a case's
  successors are its operand list". Our lowering is where `idr.match`
  becomes `cf.switch` today (checked in §3); if Design 2 is taken, the
  match lowering moves up the pipeline.
- G2.7: facts written into the IR's types; "after representation a type
  *is* its layout". The lowering's type converter is where a data type
  becomes its layout.
- E2/E3: one linear normalizer rather than a rewrite driver; bears on
  our lowering's use of greedy drivers vs conversion vs walks.

**§5.10 rc.** (read most carefully)
- A3/A4: drop specialization emits `drop-special(y, unique: drop
  children; free(y), shared: dup children used; decref(y))`; drop-guided
  reuse turns a drop into `if is_unique(y) then (drop children; token :=
  &y) else (dup used children; decref(y))`. This is the shape
  `LowerTake` (Counting.cpp) must be compared with.
- A9: Koka's fast path is one signed compare: 0 unique, positive more
  same-thread refs, negative thread-shared/sticky; `drop` tests `rc <=
  0` for both slow cases. A10: `dropn` with the scan count known
  statically; stackless free. B6: Lean's "unique = 1" costs a second
  compare. Our runtime calls emitted by the lowering (count test, free)
  are compared in §3 (the runtime itself is lane 18's).
- A11 (counterexample): Koka's counting ops are untyped externals found
  by name comparison. Checked against how our lowering finds runtime
  functions (by string?) in §4.
- B5: Lean's `expandResetReuse` splits hot and cold paths *in IR*
  (unique path: projections need no `inc`; unchanged field writes
  skipped). Bears on the wide take-apart.
- C4: the uniqueness test is an ordering hazard; `is_unique` must not
  move across a retain. Effects on the count resource must stay on the
  lowered calls, or upstream passes after the lowering may reorder.
- M4: an exclusive operand makes the uniqueness test constant true.
- **R1.4 (bears on rc-Q2):** "`is_unique %x` is an op whose folder
  returns true when `%x` is exclusive by type; drop specialization and
  drop-reuse emit `scf.if` on it ... where it was not [proved], the test
  stays and costs one compare. No pass special-cases the static case:
  the type decides and the folder applies it." R1.5: `dup`/`drop` write
  the count resource, `is_unique` reads it.
- R4: Koka's header without the atomic half; a drop of an exclusive
  cell frees without reading the count.
- **rc-Q2 (§5.10.4 Q2, evidence in §6):** "How much exclusivity is
  static ... is a run-time uniqueness test an acceptable fallback where
  the proof fails?"
- W6 (runtime header) is lane 18's; W8 (counting on regions or CFG) is
  lane 08's; this lane gives the lowering's side of both.

**§5.11 oom.**
- K6/B2: stack probes as `probe-stack="inline-asm"` and
  `stack-probe-size` = the target's page size, from the target's entry.
  oom wave-2 question 4: "Whether lowering sets `probe-stack`" (answered
  in §3).
- B1: allocation failure is one named crash in the allocator's types;
  "every null test after an allocation" goes. Checked: does the lowering
  emit a null test after a cell allocation (§3)?
- 5.11.5 note to §5.8: `MemAlloc` on a constructor must stay free of
  `Crash`, or nothing allocating is pure. Bears on the effects the
  lowering's allocation calls carry.
- oom wave-2 question 6: array byte size overflow (lane 11's).
- oom wave-2 question 8: attributes created per function or per value
  (the lowering creates symbol and static-data attributes; §2 below).

**§6-§9.** §6: twenty lanes, documents in `audits/p0/`. §7 not written.
§8 groups the owner's questions; mine are **DD-Q5** (§8.3) and **rc-Q2**
(§8.5). Related ones the lowering has evidence for: ods-Q1/DD-Q2 (a dead
crash; the check lowering), ods-Q3 (crash ordering), DD-Q3 (the world;
the lowering drops world operands), DD-Q4 (signedness; the word
lowering), DD-Q7 (`idr.func` vs `func.func`; the lowering converts one to
the other), Q-O1 (structured match; the lowering makes the CFG), ods-Q4
(DRR for one-to-one lowerings), Q-llvm-5 (one tblgen tool; the runtime
symbol table), oom-4 (stack probes), cxx-Q1 (interfaces vs concepts in a
lowering). §9: D1-D4 (P0 first; our own solvers allowed; wave 1 outside
our code; no code before the plan).

**Proposal 0003 (each fact once), items in the lowering** (*read*,
`proposals/0003-facts-once.md`):
- "A token without its cell": `!idr.token` has no parameters, so
  `Conversion/Fields.cpp` (among four) walks back to the `idr.take`;
  "`Fields` silently stores every field again" when the token reaches its
  recycle through a block argument. Fix: `!idr.token<!idr.box<T>, @C>`
  inferred by `TakeOp`; "delete the four walks and all of `Fields`'
  pairing". (0003:178-185)
- "Two upward walks without `definitionChain`'s cycle guard":
  `Conversion/Fields.cpp` `moved`. (0003:269-271)
- `StaticData::isStatic` in `Conversion/` is "the lowering's question of
  a global's component", distinct from `ownership::isStatic`. (0003:244-245)
- "Function facts not lowered": `effects` and `total` reach no LLVM
  attribute; map them in `LowerFunc` (`willreturn`, `mustprogress`,
  `nounwind`, `memory`). (0003:330-332)
- "`idr.crash_str` drops its site; lower it through `Runtime::crash`."
  (0003:336)
- "No stack probes against the 1 MiB guard: set
  `"probe-stack"="inline-asm"` on program functions." (0003:340-341)
- "Emitted code decodes the small word by hand": `Conversion/Bigs.cpp`
  (`lowBit`, the shift in `LowerNatToExtent`) and `Conversion/Words.cpp`
  (`groupBase`); owed: `idris_rt_word_is_small`/`idris_rt_small_value`
  called instead. (0003:412-417)
- "One target machine recipe" (DLTI spec written once by idr-target):
  bears on any target fact the lowering reads. (0003:317-329)

## 2. What the subsystem is

**Files and sizes** (*measured*: `wc -l` over the list below, kept in
`/tmp/conv-files.txt`): 23 `.cpp` and 13 `.h`, **4,212 lines**, of
`lib/Conversion`'s 6,158 (`wc -l lib/Conversion/* include/idr/Conversion/*`).

| file | lines | holds |
| --- | ---: | --- |
| `Lower.cpp` | 267 | `idr-lower`: phase 0 (FuncToFunc), then per run of functions a `Worker` (Runtime, TypeConverter, ConversionTarget, frozen patterns), phase 1 (walk driver) and phase 2 (one-shot `applyFullConversion`), then `Runtime::merge`; `LowerNoRuntimeForm` (trait-rooted) |
| `FuncToFunc.cpp/.h` | 142 | phase 0: `idr.func/call/return` to `func.*` under mangled names, one `AttrTypeReplacer` pass, facts dropped |
| `Mangle.cpp/.h` | 67 | `mangle`: injective escape to `[A-Za-z0-9_.$]` |
| `Matches.cpp/.h` | 212 | phase 1: `idr.match` to `idr.tag` + `scf.index_switch`; `idr.match_lit` to `index_switch` (integers) or an `scf.if` chain of `str.cmp`/`big.cmp` |
| `Facts.cpp/.h` | 140 | signature conversion of `func.func` writing `nonnull`/`align`/`dereferenceable` on cell pointers and `range` on a sum's tag |
| `Runtime.cpp/.h` | 477 | the call layer: `runtimeDeclaration`, `Runtime::call` (two forms), crash/crashIf/mayLoop, inc/dec, `merge` |
| `RuntimeCalls.cpp` | 172 | `LowerRuntimeCall<OpT>` for every op whose generated `Abi<OpT>::entry` exists (GET_OP_LIST + `requires`); result kinds Wrapped/Order/range |
| `RuntimeCells.cpp` | 105 | cell header and slot reads and writes, `allocate`, `loadTag`, `exclusive` (`idris_rt_is_unique`) |
| `Cells.cpp` | 342 | cell.new/stack/recycle/init, con, unpack, tag, field, constant, dest.write, poison, select |
| `Counting.cpp` | 126 | dup, drop, **`LowerTake`** |
| `Fields.cpp/.h` | 114 | pre-walk of every `cell.init` before conversion: same-constructor recycles and kept fields |
| `MemoCells.cpp` | 117 | `memo.run`: captures out, Running, region, value in, Forced, `idris_rt_persist_held` |
| `Checks.cpp` | 139 | `LowerCheck<OpT>` per guard op (GET_OP_LIST + `hasTrait<GuardOpInterface::Trait>`), a `fails` overload per guard |
| `Scalars.cpp` | 208 | crash, world.new, may_loop, Euclidean division, total shifts, to_char |
| `Bigs.cpp` | 61 | `nat.to_extent` (hand-decoded small word) |
| `Strings.cpp` | 166 | `str.pack`/`str.concat` (two list walks), `io.put_list` |
| `Words.cpp/.h` | 153 | pointer type, constants, `at`, alignments, `groupBase` (hand-decoded group word), `nullComponent`, `references`, unboxed sums |
| `StaticData.cpp/.h`, `StaticBytes.cpp`, `StaticNames.cpp` | 638 | content-named globals: strings, bigs, boxes (spine runs), memo cells, crash messages, constant arrays, `nothing` |
| `Entry.cpp` | 188 | `idr-entry`: takes the program apart into the module, `@__idr$entry$body`, `@main`, CPU feature bits |
| `Frame.cpp/.h`, `PassThroughMemory.cpp/.h` | 241 | helpers of lane 10's tail-call lowering (only `TailCallPlan.cpp`, `TailCalls.cpp` use them; *read*, grep) |
| `IdrPattern.h`, `Patterns.h`, `Passes.h` | 137 | the pattern base (layouts + runtime), the eleven `populate*` entry points, pass decls |

**Facts the subsystem holds or derives** (*read*):
- *The runtime ABI* is generated, not held: `Idr_Runtime<"sym">`
  (`IdrBase.td:272-275`, a `NativeOpTrait<"CallsRuntime">` with a `symbol`
  field) and `Idr_RuntimeFunction` records (`IdrRuntime.td:54-108`) feed
  `idris-mlir-tblgen -gen-runtime-abi-defs/-decls`
  (`tools/idris-mlir-tblgen.cpp:2753-3000`), which writes `Abi<Op>::entry`,
  `helper::<name>` and the C prototypes the runtime compiles against. The
  lowering reads `Abi<OpT>` at compile time (`RuntimeCalls.cpp:149-170`).
  *Measured*: 45 `Idr_Runtime<` mentions in `include/idr/IR/*.td` (families
  expand them); 119 `Abi<` specializations and 15 helpers in the last
  generated table (`build/typecheck/.../IdrRuntimeAbi.inc`, dated
  2026-10-18, so stale by `persistHeld`).
- *Layouts* (lane 01's `Layouts`, `getAnalysis<Layouts>()`,
  `Lower.cpp:251`): every type's components, each sum's and box's layout,
  every cell's slots, own words, info word, size. The type converter is
  one 1:N rule over them (`Lower.cpp:104-111`).
- *Rederived in the lowering*: same-constructor recycle and kept fields
  (`Fields.cpp:32-49`, from the IR before conversion); "this field dies
  here" (`Counting.cpp:74-76`, from the field's one use); whether a
  component is static data (`StaticData.cpp:62-65`, from the defining LLVM
  op); the small-word and group-word encodings (`Bigs.cpp:26-47`,
  `Words.cpp:30-33`); the CPU feature bits (`Entry.cpp:72-88`, a fresh
  `TargetMachine`); per-parameter LLVM facts (`Facts.cpp:44-61`, per type
  per signature).
- *Dropped*: every `idr.func` fact (`FuncToFunc.cpp:3-5`, "A function's
  other facts were for the passes that are over"); every op's declared
  effects (no `memory_effects`, `will_return`, `no_unwind` on any call:
  *measured*, `grep -rn "memory_effects\|will_return\|no_unwind" lib include`
  finds nothing); `idr.crash_str`'s location (it goes through the generic
  runtime call, `IdrCheckOps.td:30`).

**State and threading** (*read*). `idr-lower` is a `ModuleOp` pass
(`Passes.td:724`) that does its own parallelism: phase 0 serial; then the
program's functions cut by count into `min(threads, functions)` runs
(`Lower.cpp:215-229`), each run a `Worker` with its own `Runtime`
(its own `LLVMTypeConverter` with no data layout analysis, a scratch
`ModuleOp` of static data, a `StringMap` of globals, a `DenseMap` of
boxes, a `SmallPtrSet` of runtime functions called) and its own frozen
pattern set; `failableParallelForEach` on the context's pool (§5.3 D1's
right pool); then `Runtime::merge` serially sorts declarations by symbol
and globals by name into the program. Shared read-only across workers:
`Layouts`, `Fields`, the constant arrays, the data layout options. No
mutex, no atomic (*measured*: grep). Per-node containers: none; every
map is one per pass or per worker (Fields' two maps keyed by
`Operation *`, StaticData's two maps, FuncToFunc's `Renames`, Frame's
`DenseSet<Value>` per function).

**Who reads its results.** The module after `idr-entry`: the
vectorization schedule, `idr-narrow-lanes`, linalg-to-loops, canonicalize
and CSE on `func.func`, `idr-returned-arguments`, scf-to-cf,
convert-to-llvm, `idr-tail-calls` (`lib/Transforms/Pipeline.cpp:140-196`).

**Measured counts over the 36 files** (`xargs cat < /tmp/conv-files.txt |
grep -c <token>`): `isa<` 14, `dyn_cast` 17, `cast<` 61, `std::variant<` 1
(visited once, exhaustively, `StaticData.cpp:179, 212-221`), `function_ref<`
5, `switch (` 5, `TypeSwitch` 0, `template <` 11, `requires`/`concept` 1,
`hasTrait<` 3, `getEffects`/`MemoryEffects` 0, `DenseMap`/`DenseSet`/`StringMap`
13, walks 3, `if constexpr` 10, patterns (`struct Lower*`) 35,
`internal error` 8, `std::string` 18.

## 3. Reconciliation with the proposal

### 3.1 Findings and designs

| finding | verdict | our code |
| --- | --- | --- |
| §5.2 E6, one-shot conversion | **holds, already adopted** | `Lower.cpp:180-187`: `allowPatternRollback = false`, `foldingMode = Never` (dbb34b31: a fold read an LLVM value as its own type without rollback). |
| §5.2 E3, the walk driver for one-shot rewrites | **holds, already adopted** | phase 0 (`FuncToFunc.cpp:109-112`) and phase 1 (`Lower.cpp:179`) are `walkAndApplyPatterns`. |
| §5.2 E1, M6, pattern roots | **holds** | every pattern is op-rooted; one is trait-rooted (`LowerNoRuntimeForm`, `Lower.cpp:69-76`); no `MatchAnyOpTypeTag` (*measured*, grep). Upstream's memref patterns are filtered by root name (`Lower.cpp:161-167`), a second mechanism beside `ownLowering`'s benefit (`IdrPattern.h:20`, used in `Memrefs.cpp:169`). |
| §5.2 M7, row 12, "one `OpInterfaceRewritePattern<RuntimeFunction>`" | **holds in part** | The fact is already single-source: the `Idr_Runtime` record generates the C prototypes, the `Abi<Op>` table and the Idris side (`IdrBase.td:265-275`, `tools/idris-mlir-tblgen.cpp:2753-3000`), and `idris-mlir-tblgen` refuses a symbol declared twice (`:2868-2875`). The lowering is one template instantiated per op over `GET_OP_LIST`, filtered by `requires { Abi<OpT>::entry }` (`RuntimeCalls.cpp:149-170`): op-rooted patterns, indexed per op at freeze exactly as an interface-rooted one would be (§5.5 finding 18), with the typed adaptor an interface pattern loses. What does not hold: the symbol lives in a table keyed by op class, beside the op, and the C++ trait `CallsRuntime` carries nothing and is read by nothing (`Traits.h:31-40`; *measured*: no `hasTrait<CallsRuntime>`). Disposition in §5 (T1). |
| §5.2 M8, row 23, families from lists | **holds in part** | Scalar families are ODS classes whose `static constexpr bool isSigned/quotient/left` the lowering reads (`IdrScalarOps.td:31-34, 67-70, 101-102`; `Scalars.cpp:75, 93, 138, 148, 152, 174`), D1's shape. The pattern list repeats the family by hand (`Scalars.cpp:201-205`). |
| §5.2 A1-A6, effects | **holds; the lowering drops them** | No call the lowering makes carries the op's declared effects: no `memory_effects`, `will_return`, `no_unwind` anywhere (*measured*). `llvm.call` at the pin does not implement `MemoryEffectOpInterface` (*read*: `mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td:821-826, 877-879`; `LLVMDialect.cpp` defines `getEffects` only for load, store, inline asm), so even with the attribute set, the canonicalize and CSE after the lowering (`Pipeline.cpp:167-168, 181-182`) see every runtime call as unknown. |
| §5.2 M13, DRR | **does not reach phase 2** (*conjecture*) | DRR writes `RewritePattern`s; phase 2 needs `OpConversionPattern` with a 1:N adaptor (`IdrPattern.h:24-31`). The one-to-one lowerings (`world.new`, `may_loop`, `crash`, `Scalars.cpp:28-56`) are too few to matter. |
| §5.8 O4, lower forms by `ConversionTarget` | **holds** | `Lower.cpp:115-138`: `idr` and `memref` illegal, the target dialects legal, `memref.load/store`, linalg, poison, select, `func.*` dynamically legal. |
| §5.8 DS4, word ops to `arith` | **holds for unsigned division, refuted for the rest** | `divu`/`modu` lower to `arith.divui`/`remui` exactly, the guard before them (`Scalars.cpp:75-77`). `divs`/`mods` are Euclidean (`IdrScalarOps.td:20-22`; `Scalars.cpp:78-104`), not arith's truncating division. Every shift is defined for every amount where arith's are poison from the width up (`IdrScalarOps.td:55-60`; `Scalars.cpp:110-160`). |
| §5.8 DS4, guards to `arith.cmpi` plus one `idr.check <reason>` | **holds** | Each guard already lowers to a comparison and one `idris_rt_crash` (`Checks.cpp:43-115`); two guards hold two operand kinds in one op (`CheckNonzero`: an integer or a big, `Checks.cpp:46-50`; `CheckInBounds`: a string or an array, `Checks.cpp:59-63`), which is the flag DS4 removes. |
| §5.8 DS4, `match_lit` on words to `scf.index_switch` | **holds** | That is what phase 1 emits (`Matches.cpp:115-131`). Emitted directly (DS4), the integer arm here goes. |
| §5.8 DS4, `func`/`call`/`return` to `func.*` | **holds; facts lost** | Phase 0 (`FuncToFunc.cpp:31-66`); "the facts of `idr.func` are not copied" (`Passes.td:731-732`). |
| §5.8 O5, fuse at the lowering | **not done in the lowering** | No lowering fuses; `io.put_list` is a fused op at the idr level with a canonicalizer (`IdrStringOps.td:84-91`). |
| §5.8 C6, an abort is a write | **holds** | `idris_rt_crash` is a cold `noreturn` call with no effect attribute, so unknown (`Runtime.cpp:189-196`), ordered after everything. |
| §5.8 O2/C3, `cell.new`/`cell.stack` one class by resource | **holds in the lowering's shape** | Two patterns, one heap call, one entry-block `llvm.alloca` with the stack mark (`Cells.cpp:66-103`); one class parameterized by resource would make them one pattern with one branch on the resource, which is essential (heap call vs frame slot). |
| §5.9 F6, representation per type asked through a record of functions | **holds in part** | `Layouts` decides each data type's representation once (lane 01), but con, tag and field each branch on `isBoxed` again (`Cells.cpp:188, 226, 249`). |
| §5.9 Design 2, `case` as a terminator | **the lowering already makes the CFG** | `scf.index_switch` here, `cf.switch` at scf-to-cf (`Pipeline.cpp:186`); Design 2 moves the change up the pipeline (Q-O1). |
| §5.10 A3, A4, drop specialization and drop-guided reuse | **holds in shape** | `LowerTake` is Perceus's drop-special at a take: unique, the dying fields dropped and the cell the token; shared, the moving fields incremented, the cell decremented, the token null (`Counting.cpp:86-107`). Dup/drop fusion of a dying field is done here by peeking at the field's one use and erasing it (`Counting.cpp:74-76, 108-110`), where Koka does it in Parc. |
| §5.10 A7, reuse specialization | **holds, as a side table** | `Fields::kept` (`Fields.cpp:32-58`, cfca1a06 cites Lean's ExpandResetReuse and Perceus). |
| §5.10 A10, `dropn` with the scan count known | **refuted** | one `idris_rt_inc`/`idris_rt_dec` call per counted component (`Runtime.cpp:285-297`); the wide take-apart is 4,472 of each in one function (`audits/bugs.md:43-53`). |
| §5.10 B5, hot and cold paths in IR | **holds** | `scf.if` on `idris_rt_is_unique` (`Counting.cpp:94-106`), on the token's null (`Cells.cpp:128-140`). |
| §5.10 M4, an exclusive operand needs no test | **holds** | `isExclusive` skips both tests (`Counting.cpp:91-92`, `Cells.cpp:123-127`). |
| §5.10 R1.4, the test as a folding op | **refuted as today's shape** | the static and the dynamic case are two C++ branches in two patterns, not one op that folds. |
| §5.10 R4, an exclusive drop reads no count | **refuted** | `LowerDrop` has no exclusive case; it calls `idris_rt_dec`, which reads the count (`Counting.cpp:42-55`; `runtime/Rc/Rc.h:86-95`). |
| §5.10 C4, the uniqueness test's ordering | **holds by unknown effects** | every lowered runtime call has unknown effects until LTO inlines it, so nothing reorders across `idris_rt_is_unique`; correct, and maximally conservative. |
| §5.11 K6/B2, stack probes | **refuted: none set** | *measured*: `grep -rn "probe-stack" lib include` finds nothing (0003's target item, `proposals/0003-facts-once.md:340-341`). |
| §5.11 B1, no null test after an allocation | **holds** | `Runtime::allocate` tests nothing (`RuntimeCells.cpp:33-38`). |
| §5.1 C1-C4, a match queried per op | **holds** | phase 1 walks a match's regions once; `knownTag` is O(1) (`Matches.cpp:82-101`; `lib/IR/OpsMatch.cpp:153-157`). No `getPredecessors`, `getSuccessorRegions`, `isRepetitiveRegion` in the subsystem (*measured*, grep). |
| §5.1 F2, W6, function passes under the pass manager | **refuted** | `idr-lower` is a `ModuleOp` pass with its own `failableParallelForEach` over runs of functions cut by count (`Lower.cpp:212-229`). |
| §5.1 F3, attributes on a hot path | **holds as a risk** | workers create `StringAttr`s (one crash message per site: `Runtime.cpp:42-50, 189-196`; `StaticBytes.cpp:30-39`), `DictionaryAttr`/`ConstantRangeAttr` per ranged call (`RuntimeCalls.cpp:112-116`) and literal struct types per static cell (`StaticData.cpp:202`), all through the context's uniquer from parallel threads (98c6315c's lock, §3). Unmeasured. |
| §5.3 B2, I2, a per-pass table is a `TypeSwitch` | **holds** | `StaticData::datum` is a `dyn_cast` ladder over attribute kinds (`StaticData.cpp:78-120`), a per-pass table. |
| §5.3 E2, I8, generated tables | **holds for the ABI; four switches remain** | `appendParameter`, `resultType`, `Runtime::call` and `givenRange` switch on the generated kinds (`Runtime.cpp:54-104, 157-185`; `RuntimeCalls.cpp:61-90`). |
| §5.5 D1, dispatch once then typed code | **holds** | `addRuntimeCalls` and `addChecks` read ODS at compile time and list no op (`RuntimeCalls.cpp:149-157`, `Checks.cpp:117-125`): the concept-reads-ODS line of cxx-Q1, already practised. |
| §5.5 D2, one exhaustive visit | **holds** | the subsystem's one variant (`StaticData.cpp:173-180`) is visited once with `makeVisitor` (`:212-221`). |
| §5.5 D8, `zip_equal` | **holds** | `Runtime.cpp:157`, `RuntimeCells.cpp:83`, `Words.cpp:54, 67, 71`, `MemoCells.cpp:66`, `Matches.cpp:98`. |
| §5.6 F2, the lowering generated from ODS | **holds for runtime calls** | the table is generated; cells, matches and counting are essential custom lowerings. |
| 0003, "a token without its cell" | **holds** | `Fields.cpp:34-38` finds the take only as the token's direct definer; a token through a block argument or a regrade gets no mask and every field is stored again (correct, slower). |
| 0003, `moved` without a cycle guard | **holds weakly** | `Fields.cpp:17-28` climbs operands of `ResultCarriesOperand` ops; SSA dominance bounds it in a CFG region, as its comment says. |
| 0003, function facts, `crash_str`'s site, stack probes, the small word by hand, one target machine | **all hold** | `FuncToFunc.cpp:3-5`; `IdrCheckOps.td:30` through `LowerRuntimeCall`; *measured* no probes; `Bigs.cpp:26-47`, `Words.cpp:30-33`; `Entry.cpp:77-78` builds its own machine by `LLVM::detail::getTargetMachine`, not `idr::target::machine` (`include/idr/Target/Target.h:75`). |

### 3.2 Wave-2 questions answered (those that fall here)

- **§5.1 W3** (per-region interface queries): none in the subsystem (*measured*).
- **§5.1 W5** (attributes created on a hot path): yes, from parallel workers; see F3 above. Each crash site makes a unique message, so a `StringAttr` and a global per site (`Runtime.cpp:42-50`).
- **§5.1 W6** (passes anchored on functions): `idr-lower` and `idr-entry` are `ModuleOp` passes (`Passes.td:724, 760`); phase 1 and 2 are per function but scheduled by hand.
- **§5.2 W1** (hand `getEffects`): none here. **W2** (`MatchAnyOpTypeTag`): none. **W3** (`verify()`): none here. **W4** (`isa` over ops): `Frame.cpp:46` (seven LLVM ops), `FuncToFunc.cpp:77`, `Matches.cpp:31`, `Counting.cpp:76`.
- **§5.3** worklists: one, `OnceWorklist<Value>` in `Frame.cpp:30-51`. Maps: all one per pass or worker (§2). `function_ref`: five, all cold builders (`StaticData.h:123, 148`; `StaticData.cpp:163, 237`; `Strings.cpp:41`); the callee is local and knows the callable, so each is I5's template case at no hot-path cost. Variants: one, exhaustive. Mutex/atomic: none; one `failableParallelForEach` on the context's pool. Switches: five, four over the generated ABI kinds, one over `RootKind` (`Entry.cpp:146-153`, two essential cases).
- **§5.4** "every option that selects between two implementations": none here. "Hand `getEffects` because an attribute changes an op": none here.
- **§5.5** `isa` over ops vs types: over ops as in §5.2 W4; over types `Checks.cpp:47, 61`, `Counting.cpp:47`, `Facts.cpp:47`, `Frame.cpp:19-23`, `Lower.cpp:106, 126`, `Matches.cpp:115, 147`, `Runtime.cpp:293`, `Strings.cpp:143`, `Words.cpp:47`; over attributes `StaticData.cpp:85-103`, `StaticBytes.cpp:43, 79, 81`. Templates: 11, constrained only by `requires { Abi<OpT>::entry }` (`RuntimeCalls.cpp:153`) and a constexpr trait filter (`Checks.cpp:121`); each over op classes, each a concept reading ODS waiting to be named. CRTP mixins: none. Hand lists restating ODS: `Scalars.cpp:201-205` (the families), the eleven `populate*` calls (`Lower.cpp:146-156`). C++-only lists: the four ABI-kind switches.
- **§5.6 W-E4** (facts in discardable attributes): none here; the LLVM argument and result attributes the lowering writes are LLVM's inherent ones. **W-E5** (budgets): none here; the inlining budget the wide take-apart trips is lane 13's (`audits/bugs.md:49-52`). **W-E6** (queries walking a match): none.
- **§5.7** unrooted patterns: none.
- **§5.8** "which word ops differ from `arith` ... and why `shls` and `shlu` are two ops": `divu`/`modu` agree with `arith.divui`/`remui` on every input the guard admits; `divs`/`mods` are Euclidean and give the wrapped `MIN / -1` (`Scalars.cpp:78-104`); every shift is defined at and past the width; `shls` reads a negative amount as a right shift and `shlu` an amount as unsigned (`IdrScalarOps.td:55-60`; `Scalars.cpp:148-157`): a different computation, so two ops by B3's line. Ops whose operand *type* changes their meaning, which the lowering branches on: `check.nonzero`, `check.in_bounds`, `match_lit`, `io.put_list`, `drop` (of a token vs a value).
- **§5.9 Q-W3** (a 30,000-arm match): phase 1 makes one `scf.index_switch` of 30,000 regions with one `idr.field` per bound field per case (`Matches.cpp:53-63, 96-101`), linear; scf-to-cf makes one `cf.switch`. **Q-W4**: the lowering itself reads the region structure, once.
- **§5.10 W8** (counting on regions or a CFG): the takes lower inside `scf.index_switch` regions, after phase 1 (`Lower.cpp:176-187`).
- **§5.11 wave-2 4** (does the lowering set `probe-stack`): no. **8** (attributes per function or value): crash messages per site, content names per static datum, range dictionaries per ranged call.

## 4. Issues

All *read* at the cited lines unless marked. "T*n*" names the target
design of §5 that disposes of the issue; another lane's document is cited
where the fix is theirs.

| ID | file:line | category | what | disposition |
| --- | --- | --- | --- | --- |
| CV-01 | `Lower.cpp:245-262`; `Passes.td:724` | upstream | `idr-lower` is a `ModuleOp` pass that schedules its functions itself (`failableParallelForEach`, `Lower.cpp:212-229`): the pass manager's per-function verification, timing, crash reproducer and dynamic claiming are bypassed (§5.1 F2, W6). | T6: phases 1-2 a pass nested on the functions; declarations and static data made outside it. |
| CV-02 | `Lower.cpp:215-224` | state | Runs cut by function *count*, not cost: a run holding a 30,000-case match lowers alone while the others idle (BOLT's `SP_CONSTANT`, §5.3 D3). The static cut is not needed for determinism: names are content-made and merge sorts (`Runtime.cpp:256-278`). | T6 (dynamic claiming by the pass manager). |
| CV-03 | `Lower.cpp:157-167`; `IdrPattern.h:17-20` | upstream | Upstream's `memref.global`/`get_global` patterns removed from the set by root name, while elsewhere our own lowering wins by benefit (`ownLowering`, `Memrefs.cpp:169`): two mechanisms for "ours first". | Give `LowerGetGlobal` (lane 11's `Arrays.cpp:92`) `ownLowering`; delete the filter loop. |
| CV-04 | `Lower.cpp:146-156`; `Patterns.h:19-80` | list | Eleven `populate*` entry points, called in a hand order. | Keep as files; the list shrinks with T3, T4, T5 (each deletes a family). |
| CV-05 | `FuncToFunc.cpp:3-5, 35-45`; `Passes.td:731-732` | rederivation | Every `idr.func` fact (effects, `total`) is dropped; LLVM re-infers weaker ones (0003:330-332). | T2: `LowerFunc` writes `llvm.memory`, `nounwind`, `willreturn`/`mustprogress` from the function's facts, by one rule. |
| CV-06 | `FuncToFunc.cpp:70-114` | upstream | Phase 0 renames every function and rebuilds `idr.func/call/return` as `func.*`, serially. | Goes if `func.func` is emitted from the start (DD-Q7); else stays as the one rename. |
| CV-07 | `FuncToFunc.cpp:73-88`; `Runtime.cpp:249-267`; `Entry.cpp:107-113` | state | Three collision checks for one coordinate: a mangled function name meeting another program symbol (an internal error), a runtime C name meeting a program symbol (refused), `main` meeting a program function (renamed). Each exists because `mangle` is the identity on C identifiers (`Mangle.h:15-22`). | T7: every program function mangles under a prefix no C identifier of the runtime and no `main` has; the three branches go. |
| CV-08 | `Matches.cpp:108-131, 147-149` | ladder | `match_lit` is three ops in one by scrutinee type: an integer (`index_switch`), a string or a big (`isa<StrType>` chooses `str.cmp` or `big.cmp`). | Integer literal matches emitted as `scf.index_switch` (§5.8 DS4, lanes 03/15); string and big literal matches one op over an order (the cmp op is the parameter). |
| CV-09 | `Matches.cpp:132-163` | ladder | A string or big literal match lowers to a linear `scf.if` chain: up to N runtime comparisons per dispatch (an emitted ladder). | The cmp ops give a three-way order (`ResultKind::Order`): a sorted binary search, log N; small bigs a switch on the word. |
| CV-10 | `Matches.cpp:22-40` | state | A region ending in `ub.unreachable` after a crash yields poison, because `scf.index_switch` regions must yield. | Essential under scf; goes with Q-O1 (a `case` terminator keeps the unreachable). |
| CV-11 | `Matches.cpp:42-49, 91-92` | cpp | `Arm{region, optional<Tag>}` holds three kinds (a case, a default, a literal case) as an optional, dereferenced unchecked at `:92`. | A closed sum `Case{Tag} \| Default \| Literal`. |
| CV-12 | `Facts.cpp:41-61, 88-92` | rederivation | A component's LLVM facts (`nonnull`, `align`, `dereferenceable`, `range`) are derived per type at each signature; loads from cells (`LowerField`, `Cells.cpp:249-253`) and call results carry none. | T8: `layout::Component` carries its facts once (lane 01); signatures, call results and loads write them. |
| CV-13 | `Runtime.cpp:54-104, 152-187`; `RuntimeCalls.cpp:61-90` | list | Four switches over the generated `OperandKind`/`ResultKind`: the LLVM type, the passing rule (World nothing, Signed/Unsigned extended), the result type, the stated range. | T1: the generated rows carry the LLVM type and the passing rule (§5.5 D4a); the switches go. |
| CV-14 | `Runtime.cpp:142-150` | ods | A runtime call carries none of its op's declared effects: no `memory_effects`, `will_return`, `no_unwind` (*measured*: none in the tree). | T2: `Runtime::call(op, …)` maps the op's effects once; plus an upstream patch so `llvm.call` reports `memory_effects` to `MemoryEffectOpInterface` (*read*: it implements none at the pin). |
| CV-15 | `Runtime.cpp:117-133, 140-149` | state | `noreturn` set on the declaration and again at every call. | Essential: linking the runtime replaces declarations' attributes (`Runtime.cpp:140-141`). Keep. |
| CV-16 | `Runtime.cpp:39-50, 189-196`; `StaticBytes.cpp:30-39`; `Checks.cpp:101-110` | attribute | Every crash site writes its own message global with `file:line:col` baked into the text: a unique `StringAttr`, digest and global per site, created from parallel workers (§5.1 F3). | T9: `idris_rt_crash_at(cause, file, line, col)`; cause and file globals shared, line and column immediates. |
| CV-17 | `IdrCheckOps.td:30`; `RuntimeCalls.cpp:127-147` | rederivation | `idr.crash_str` lowers through the generic call and loses its site (0003:336). | T9: the same entry with the string as cause. |
| CV-18 | `Runtime.cpp:205-210` | state | `may_loop` becomes `llvm.sideeffect`, kept defensively: nothing sets `mustprogress` today, so LLVM would keep the loop anyway. | Keep; essential once T2 marks total functions `mustprogress` (DD-Q2's evidence, §6). |
| CV-19 | `Runtime.cpp:285-297`; `Counting.cpp:27-37, 81-106` | state | One `idris_rt_inc`/`idris_rt_dec` call per counted component; the wide take-apart is 4,472 of each in one function (`audits/bugs.md:43-53`). | T4: a cell's object slots as a half-open range; one call per contiguous run (`idris_rt_inc_slots(cell, first, count)`). |
| CV-20 | `StaticData.cpp:62-65`; `Runtime.cpp:287-289` | rederivation | Whether a component is static data is re-derived from its defining LLVM op; a static value through a select or block argument loses it (an extra no-op call, `runtime/Rc/Rc.h:79-84`). | The value-level case goes with 0003's static lifetime in the grade (a static `dup`/`drop` deleted before the lowering, lane 08); the component-level check goes too: the runtime's count test already skips a persistent cell. Measure the calls. |
| CV-21 | `Runtime.h:49-174` | cpp | `Runtime` is one class of six roles (ABI calls, crashes, cell reads and writes, counting, static data, merge), passed to every pattern. | Split by role as T1, T4, T6 leave them; each pattern takes the part it uses. |
| CV-22 | `RuntimeCalls.cpp:133-143`; `Runtime.cpp:57-58, 160-161`; `Scalars.cpp:38-46`; `Strings.cpp:151-152`; `StaticData.cpp:82-83`; `Facts.cpp:80-81` | state | Seven special cases for a world that converts to nothing. | Goes with DS2.1 (no world after the frontend, DD-Q3); essential while the world is a value. |
| CV-23 | `RuntimeCalls.cpp:149-157` | cpp | The op filter is an unnamed `requires` in a lambda over `GET_OP_LIST`. | A named concept (`RuntimeOp`) reading the op's own entry (T1). |
| CV-24 | `RuntimeCells.cpp:54-70`; `Words.cpp:40-45` | rederivation | `groupBase` decodes the group word as a small Integer by hand (0003:412-417). | T10: the runtime's encoding called through the table, inlined by LTO. |
| CV-25 | `Bigs.cpp:26-47` | rederivation | `nat.to_extent` decodes the small word by hand (`lowBit`, the shift). | T10. |
| CV-26 | `Cells.cpp:181-198, 219-259` | ladder | `con`, `tag` and `field` each branch on `isBoxed` again: the representation `Layouts` chose per type is re-asked per op (§5.9 F6). | T5: one representation sum per data type (`Boxed{BoxLayout} \| Unboxed{SumLayout}`) matched once, or split ops (lane 03). |
| CV-27 | `Cells.cpp:183-194` | ods | A boxed `con` is lowered as an atom with its fields ignored; that it is an atom rests on a whole-program walk of the owned verifier (`lib/IR/Verify/OwnedOps.cpp:29-33`). | T5: an atom is its own op (or a constant); a boxed `con` with fields unrepresentable past idr-rc (lane 03). |
| CV-28 | `Cells.cpp:105-173`; `Fields.h:20-50`; `Fields.cpp:32-58` | rederivation | Recycle and init ask a side table, keyed by `Operation *`, built by a pre-walk before conversion, for facts the conversion loses (same constructor; kept fields) (cfca1a06). | T3: the token's type carries its constructor (0003:178-185); kept fields are IR (`cell.update` of only the changed fields), made by idr-rc where reuse is decided. `Fields` goes. |
| CV-29 | `Fields.cpp:17-28, 34-38` | rederivation | `moved` climbs regrades; the take is found only as the token's direct definer, so a token through a block argument stores every field again (0003). | Goes with CV-28. |
| CV-30 | `Cells.cpp:123-140`; `Counting.cpp:91-107` | ladder | The static and the dynamic case of uniqueness are C++ branches in two patterns. | T4: `idr.is_unique` (and the token's null test) as ops that fold on an exclusive type (§5.10 R1.4), made above the lowering; the lowering lowers the op. |
| CV-31 | `Counting.cpp:42-55` | ods | `drop` means two things by operand type (`isa<TokenType>`): free an emptied cell, or give up a reference. | Split: `idr.token.free` (lane 03). |
| CV-32 | `Counting.cpp:42-55` | rederivation | An exclusive drop still calls `idris_rt_dec`, which reads the count (§5.10 R4). | T4: an exclusive drop is the release with no count read (a runtime entry for it). |
| CV-33 | `Counting.cpp:74-76, 108-110` | rederivation | Dup/drop fusion of a dying field is found by peeking at the field's one use, and the pattern erases that `idr.drop`, an op it did not match. | T4: the take states which fields it gives; a field not given dies with the box (lane 08 places it). |
| CV-34 | `MemoCells.cpp:38-45, 95-98` | state | Stack mark kept by a run-time load-and-or; `persistHeld` called after every force. | Essential: one dispatch forces static, counted and frame cells alike (`MemoCells.cpp:95-97`). Keep. |
| CV-35 | `MemoCells.cpp:73-82` | upstream | A capture of no component must be skipped, since an empty `remapInput` reads as a remapped position. | An upstream API sharp edge; report or document upstream; keep the skip until then. |
| CV-36 | `Checks.cpp:43-52, 57-66` | ods | Two guards hold two operand kinds each (an integer or a big; a string or an array), branched by `isa`. | T11: `idr.check %cond, <reason>` with the condition built by `arith`/`idr` ops (§5.8 DS4); the five guard ops and the `fails` overloads go. |
| CV-37 | `Scalars.cpp:199-205` | list | The ten family members listed by hand. | `GET_OP_LIST` with concepts on `isSigned`/`quotient`/`left`, as `Checks.cpp` does. |
| CV-38 | `Scalars.cpp:58-108` (unsigned arm); `IdrScalarOps.td:42-53` | upstream | `divu`/`modu` are `arith.divui`/`remui` after their guard. | Emitted as `arith` (DS4); the two ops and the arm go (lanes 03/15). |
| CV-39 | `Scalars.cpp:58-192`; `lib/IR/Ops.cpp:200-293`; `lib/IR/OpsScalars.cpp:31`; `runtime/Big/Arithmetic.cpp:17-25` | rederivation | Euclidean division, total shifts and the scalar-value test are written twice in C++ (folder on `APInt`, lowering as `arith`), division a third time in the runtime: one meaning, three copies, against AGENTS.md's "its one meaning is the runtime's, which folders call too". | T12: one definition per primitive over a value domain, instantiated for folding and for lowering (or the runtime's, if vectorization allows: new owner question, §6). |
| CV-40 | `Strings.cpp:86-128` | ladder | `is_same_v<OpT, StrPackOp>` picks the per-element functions in two places. | The per-element functions as ODS fields of the builder family (`Idr_ListBuilder<…>`), read as `OpT::…`. |
| CV-41 | `Strings.cpp:135-155` | ods | `io.put_list` is one op over two element types, picking `put_str` or `put_char` by `isa<StrType>`, where building is two ops. | Two ops, as pack and concat (lane 03). |
| CV-42 | `Strings.cpp:41-74` | cpp | `Step` is a `function_ref` into a local walk whose callers know the callable. | A template (§5.3 I5); cold, low priority. |
| CV-43 | `StaticData.cpp:78-120` | ladder | `datum` is a `dyn_cast` ladder over attribute kinds. | `TypeSwitch` with `DefaultUnreachable` (§5.3 I2). |
| CV-44 | `StaticData.h:96-109`; `StaticData.cpp:34-43, 224-226`; `StaticNames.cpp:28-33` | cpp | Content keys are strings concatenated from digests, symbol names, punctuation and the constructor's printed name, then hashed. | A typed key: combined 128-bit digests, the constructor by tag; no text built. |
| CV-45 | `StaticBytes.cpp:94-170` vs `StaticData.cpp:162-234` | rederivation | Two ways to lay out static data: box cells as packed structs from `layout::Cell`; strings, bigs, arrays and `nothing` as natural-alignment structs that rely on the data layout matching the runtime's C structs. | One static-cell builder from layouts for every kind (lane 01 gives strings, bignums and arrays a `layout::Cell`). |
| CV-46 | `StaticBytes.cpp:125-157` | rederivation | A large big's limbs are read by `reinterpret_cast` past `idris_rt_bignum` (`number + 1`): the runtime's memory layout restated. | An accessor in `idris_rt.h` (lane 18). |
| CV-47 | `Entry.cpp:67-88` | rederivation | The CPU feature bits are re-derived each compilation from a fresh `TargetMachine` with default options (0003:317-329), though the CPU is the build's target entry. | Written once by idr-target or the target entry (lane 13); `requiredCpuFeatures` goes. |
| CV-48 | `Entry.cpp:123-134` | state | idr-entry declares two runtime functions "where the module declares none". | Goes with T6's up-front declarations. |
| CV-49 | `Entry.cpp:114-116` | cpp | `*rootKind(...)` dereferences an optional the lowered verifier made total. | Parse once: the program's root kind a property of the program op (lane 03/13). |
| CV-50 | `Frame.cpp:46-49` | ladder | Seven LLVM ops listed as pointer-forwarding. | Lane 10's (`10-tail.md`): the helper serves only `TailCallPlan.cpp`. |
| CV-51 | `PassThroughMemory.cpp:61-71` | state | The call's next op taken to be its return (0003's "types that could carry the fact"). | Lane 10's. |
| CV-52 | `IdrBase.td:272-275`; `include/idr/IR/Traits.h:31-40` | dead | The C++ trait `CallsRuntime` holds nothing and is read by nothing (*measured*). | T1: the trait carries the op's entry. |
| CV-53 | `tools/idris-mlir-tblgen.cpp:2805-2836` | ods | `opFunctionOf` refuses an attribute other than `predicate`, a property, and an operand admitting two kinds: one op, one function, enforced at build time. | Evidence for DD-Q5 (§6); extend only if the owner says so. |
| CV-54 | `tools/idris-mlir-tblgen.cpp:2838-2864`; `IdrRuntime.td:20-28` | list | Helper records read as raw `Record` fields; a C type's kind is a string checked against rows by spelling (`kindSpelled`). | Lane 14's (Q-llvm-5): the kind a def, read through the wrappers. |
| CV-55 | `Lower.cpp:251-255`; `lib/IR/Layout/Layouts.cpp:118-128` | state | Workers call `Layouts::sizeOf` (`StaticData.cpp:187`), which on a miss asks the module's `DataLayout`, whose caches `Lower.cpp:252-253` says no worker may fill (*conjecture*: a latent race if a component type was not measured). | Lane 01: `measures` complete by construction, the fallback a fatal internal error. |
| CV-56 | `Counting.cpp:33, 51, 84`; `Cells.cpp:304`; `Words.cpp:52-58` | rederivation | A type's counted mask is recomputed from `layouts.components(type)` at every dup, drop, take and poison. | Cached per type by `Layouts` (T8). |

**No issue found** (*read*): no hand `verify` or `getEffects`, no
`MatchAnyOpTypeTag`, no budget or round count, no per-target case (*measured*:
grep for target names over the 36 files finds none), no discardable
attribute holding a fact. Kept as right: the `nothing` cell (a null
object, `Cells.cpp:285-311`, `StaticBytes.cpp:159-170`); content names for
static data (deterministic across workers, `StaticData.h:3-11`); the
1:N type converter (`Lower.cpp:103-111`); `LowerCellStack`'s use of
`AutomaticAllocationScope` (`Cells.cpp:93-98`); the generated runtime ABI.

## 5. Target design

The lowering keeps what is already upstream's grain (one-shot dialect
conversion, the walk driver, a 1:N type converter over layouts, op-rooted
typed patterns generated from ODS) and loses what it rederives. Each
change: representation, what it deletes, the one line.

**T1. The runtime entry on the op.** `Idr_Runtime<"sym">` keeps its
record; the C++ trait it names (`CallsRuntime`, today empty) gets the
entry through `extraOpDeclaration`: `static constexpr runtime::Function
runtimeEntry`, written by `idris-mlir-tblgen` from the same record (§5.2
M7's sketch), so `Abi<Op>` and the trait are one carrier and folders read
`OpT::runtimeFunction`. The generated `OperandKind`/`ResultKind` rows also
carry each kind's LLVM type and passing rule (omit, as is, sign- or
zero-extend; wrap or order the result), so the four switches go. The
lowering's filter becomes a named concept, `template <class OpT> concept
RuntimeOp = requires { OpT::runtimeEntry; };`. No
`OpInterfaceRewritePattern`: an interface would erase the typed adaptor
the per-op template keeps, and costs the same index at freeze (§5.5
finding 18). Deletes CV-13, CV-23, CV-52. *Branch deleted: four switches
over the ABI's kinds; a dead trait becomes the one carrier.* Lanes 02, 14.

**T2. Declared effects reach LLVM, once.** One function maps an op's
declared effects (its `MemoryEffectOpInterface`, its speculatability) to
`LLVM::MemoryEffectsAttr`, `will_return` and `no_unwind` on the call
`Runtime::call(op, …)` makes; the same rule maps a function's facts onto
`func.func` in `LowerFunc` (`llvm.memory`, `nounwind`, `willreturn`,
`mustprogress` for a total function). Upstream patch (`upstream/<bug>/`):
`LLVM::CallOp` implements `MemoryEffectOpInterface` from `memory_effects`
when present, so the canonicalize and CSE after the lowering
(`Pipeline.cpp:167-168, 181-182`) merge and delete pure runtime calls.
Deletes CV-05, CV-14; makes CV-18 essential. *Check moved to a boundary:
the effect declared once in ODS is read once at the call; nothing
re-infers it.* Depends on lane 02's resource tree.

**T3. Reuse is IR, not a side table.** The token's type names its
constructor (0003:178-185); a recycle of the same constructor is a type
equality at `LowerCellRecycle`. idr-rc, where reuse is decided, emits
`idr.cell.update %token {changed fields}` for an exclusive same-constructor
reuse (Koka's reuse specialization, §5.10 A7) and `idr.cell.init`
otherwise. Deletes `Fields.cpp/.h`, the pre-walk, `moved`, CV-28, CV-29.
*State made unrepresentable: a kept field the lowering must rediscover; a
recycle whose constructor is unknown.* Lanes 08, 03, 01.

**T4. Counting's last step above the lowering; counts by runs.**
`idr.is_unique %box` is an op reading the count resource whose folder
answers true on `!idr.excl` (§5.10 R1.4); the token's null test likewise.
The take-apart is expanded where counting places it (lane 08) into the
test, the field reads, the moves and the counts, Lean's
expand-reset-reuse in our IR (§5.10 B5), and the take states which fields
it gives, so a dying field's dup and drop are never written (CV-33). The
lowering then lowers ops only: `is_unique` to the call; a cell's object
slots are a half-open range in `layout::Cell` (lane 01), each field's a
sub-range, so incrementing the moving fields is one
`idris_rt_inc_slots(cell, first, count)` per contiguous run (CV-19); an
exclusive drop is the release with no count read (CV-32). Deletes
`LowerTake` and both static/dynamic branches (CV-30). *Branch deleted:
the static case special-cased in two patterns; state made unrepresentable:
a per-field call for a run of slots.* Lanes 08, 18, 01.

**T5. A data type's representation dispatched once.** The owned stage
already makes every box with fields a cell; what remains is split where
idr-rc makes cells explicit: an atom is its own op (or the constant it
lowers to), and a box's tag and field reads are ops of their own beside an
unboxed sum's. If lane 03 keeps one op, `Layouts` returns a closed sum
`Boxed{const BoxLayout &} | Unboxed{const SumLayout &}` matched once per
pattern (MLton's `TyconRep`, §5.9 F6). Deletes CV-26, CV-27. *Branch
deleted: `isBoxed` in three patterns; state made unrepresentable: a boxed
`con` with fields past idr-rc.*

**T6. `idr-lower` under the pass manager.** (1) Before the lowering, a
program pass declares every function of the generated table once (some
135 declarations); symbol DCE drops the unused later. (2) A program pass
materializes every constant that is static data (strings, bigs, boxes,
memo cells, constant arrays, `nothing`, crash causes) as a content-named
global, and the constants as references to it. (3) Phases 1 and 2 are one
pass nested module → `idr.program` → `func.func`, each instance with its
own converter and patterns (`initialize`), writing nothing outside its
function. Deletes the `Worker`, the count-cut runs, `Runtime::merge`,
`StaticData`'s scratch modules and collision merge, the `called` set,
idr-entry's `declared` (CV-01, CV-02, CV-48). *Check moved to a boundary:
every symbol exists before a function is converted, so no function
writes outside itself; branch deleted: the merge.* Depends on T5 and T9
(each static datum enumerable from ops) and lane 13. Owner question NQ2.

**T7. One coordinate for symbols.** Every program function mangles
under a prefix no C identifier has (a dot or `$` first), so no program
symbol is a runtime symbol or `main`. Deletes the three collision
branches (CV-07). *Coordinate change: three branches deleted.* NQ5.

**T8. Component facts in the layout.** `layout::Component` carries its
LLVM facts and its counted bit, computed once per type and cached by
`Layouts` (lane 01); signatures and call results write them. Deletes
CV-12, CV-56. *Fact held once: per type, not per signature or per op.*

**T9. A crash site is data.** `idris_rt_crash_at(cause, len, file,
file_len, line, column)` (one `Idr_RuntimeFunction` record); one global
per cause and per file, the line and column immediates; `crash_str`
passes its string as the cause and gets its site. Deletes `crashMessage`'s
per-site text (CV-16, CV-17). *State made unrepresentable: a unique global
and attribute per crash site.* Lane 18. NQ4.

**T10. Encodings called, not restated.** The runtime's small-word
predicate and value are helper records called by `nat.to_extent` and
`loadTag`, inlined by LTO as every runtime call is (1c38fff5). Deletes
`lowBit`, the shift, `groupBase`'s decode (CV-24, CV-25). *Fact generated
from its one source.* Lane 18.

**T11. One guard op.** `idr.check %cond, <kind>` over the existing
`Idr_CheckKind` enum (`IdrBase.td:250-259`); the condition is built at
emission by `arith` (and `idr.str.length` for strings), which `arith`
folds. On the Idris side the guard's condition is built by a function
indexed by the guard's kind and operand type (`Check Nonzero Int`, `Check
InBounds Str`), so a guard over the wrong kind of operand does not
typecheck (lanes 14, 15). Deletes the five guard ops' patterns and `fails`
(CV-36). *Branch deleted: the operand-kind `isa` in two guards; five ops
one.*

**T12. One meaning per scalar primitive.** Euclidean division, the total
shifts and the scalar-value test are written once, as templates over a
value domain constrained by a concept (`ArithDomain`: compare, select,
add, sub, divsi, remsi, shifts), instantiated with an `APInt` domain for
the folder and an `arith`-building domain for the lowering, and checked
against the runtime's small-big division in one test. Deletes
`idrisDivMod`, `idrisShift`, the scalar test in `OpsScalars.cpp:31` and
the hand expansions in `Scalars.cpp` (CV-39). *Fact held three times, one
definition.* AGENTS.md says a primitive's one meaning is the runtime's:
NQ1 asks whether vectorization (an `arith` body inside a linalg op,
*conjecture*) justifies a shared template instead.

**Also:** CV-08/09/11 (integer literal matches emitted as
`scf.index_switch`; string and big literal matches a binary search on the
order; `Arm` a sum); CV-31/41 (split `drop` of a token, split
`put_list`); CV-40 (builder functions as ODS fields); CV-43/44
(`TypeSwitch` for constants; typed content keys); CV-45/46 (one static
cell builder; a limb accessor); CV-03, CV-37, CV-38, CV-42, CV-49 as their
rows say.

**Order inside the subsystem.** T1, T7, T9, T10, T12 are local and go
first. T2 waits for lane 02's resource tree. T5 and T11 follow lane 03's
op set. T3 and T4 follow lane 08's counting. T6 last: it needs every
static datum enumerable from ops (T5, T9) and the pipeline's nesting
(lane 13). Lanes 10 (CV-50, CV-51) and 11 (the memref and array
patterns this pass hosts) cut over with T6.

## 6. Evidence for the owner's questions

No answers: what our code says, by ID.

**DD-Q5 (one op, several runtime functions).**
- Today one op names one function, and the generator makes anything else
  a build error: `opFunctionOf` refuses an attribute other than the
  comparison's `predicate`, any property, a variadic operand, and an
  operand admitting two ABI kinds (`tools/idris-mlir-tblgen.cpp:2805-2836`);
  `runtimeAbi` refuses a symbol two records declare (`:2868-2875`). The
  lowering reads one `Abi<OpT>::entry` per op (`RuntimeCalls.cpp:127-157`).
- `idr.check <reason>` would map to one function, not several: each guard
  lowers to inline comparisons and the one `idris_rt_crash`
  (`Checks.cpp:43-115`); only the string guards call another function,
  `str.length`'s (`Checks.cpp:63, 71-72`), which is a condition's, not
  the check's.
- The clocks: six reading ops (`IdrPlatformOps.td:330-335`), each its own
  symbol; the C call beneath them takes the clock as an argument
  (*recalled*: `clock_gettime`), so `io.clock <kind>` could be one op
  calling one function with the kind's value as an `Int32` parameter, if
  `opFunctionOf` admitted an enum argument passed as a constant; no table
  of several functions is needed for them. Two of the six are "never
  valid" (`:334-335`), constants needing no call at all.
- The seven file-time ops (`IdrPlatformOps.td:138-151`) read one `stat`;
  §5.8's "one op, several results" would be one function with several
  results, which the ABI's one-result `ResultKind` cannot express today.
- A generated per-op selection table would be a second dispatch beside
  `Abi<Op>`; the lowering has none today.

**rc-Q2 (how much exclusivity is static; is a run-time test an
acceptable fallback).**
- R1's fallback is today's code: a take of a value not graded exclusive
  tests `idris_rt_is_unique` (`Counting.cpp:86-107`); a recycle of a
  non-exclusive token tests it for null (`Cells.cpp:128-140`). An
  exclusive operand skips both (`Counting.cpp:91`, `Cells.cpp:123`).
- R2 is already built, inside idr-rc: idr-rc-exclusive "decides the keys
  of grade specialization ... Each key gets one copy, made once and named
  from its key" (`Passes.td:591-603`), so the pipeline-order cost R2
  names (grades needed at idr-optimize) does not arise: specialization by
  grade runs where the grades are.
- The test changes speed, never meaning, in today's code: both arms give
  the take's fields with one reference each and leave the box's reference
  consumed; only the token differs (the cell, or null, which the recycle
  then answers with a fresh cell) (`Counting.cpp:57-64, 86-107`;
  `Cells.cpp:105-145`).
- The runtime's test is `count == 1 && !stack` (`runtime/Rc/Rc.h:49-53`),
  Lean's encoding (§5.10 B6), a call the lowering emits and LTO inlines.
- Missing: the folding op (CV-30), the exclusive drop with no count read
  (CV-32), per-run counts (CV-19). Measurement owed: how many tests the
  stage-1 module keeps after idr-rc-exclusive (its `numExclusive`
  statistic, `Passes.td:606-608`, against the takes and recycles emitted).

**Others the lowering bears on.**
- **ods-Q1, DD-Q2 (a dead crash or divergence).** `may_loop` lowers to
  `llvm.sideeffect`, which LLVM keeps (`Runtime.cpp:205-210`); a crash to
  a cold `noreturn` call with unknown effects (`Runtime.cpp:189-196`).
  Nothing marks a function `mustprogress` (*measured*), so after the
  lowering neither is deletable today. T2 would mark total functions
  `mustprogress`, which lets LLVM delete an effect-free endless loop only
  where Idris proved there is none.
- **ods-Q3 (crash ordering).** The lowered crash is an unknown call,
  ordered with every unknown call and memory access; a resource tree
  reaches LLVM only through T2's mapping.
- **DD-Q3 (the world).** Seven special cases exist because the world
  lowers to nothing (CV-22); the ABI has a `World` kind for it
  (generated `OperandKind::World`).
- **DD-Q4 (signedness).** The lowering is arith's school already:
  signless integers, the sign on the op (`Scalars.cpp`), and the ABI
  extends an operand by its constraint's word (`Runtime.cpp:162-173`).
- **DD-Q7 (our own function op).** Phase 0 exists to rebuild `idr.func`
  as `func.func`, and drops its facts (CV-05, CV-06).
- **Q-O1 (structured match).** Phase 1 turns a match into
  `scf.index_switch`, upstream's scf-to-cf into `cf.switch`; the only
  artifact of the structured form here is the poison yield after a crash
  (CV-10). Under Design 2 phase 1 goes.
- **oom-4 (stack probes).** None set (*measured*); `LowerFunc` or
  idr-target (lane 13) is where the attribute and the target's page size
  meet.
- **cxx-Q1 (interfaces and concepts).** The lowering practises the
  proposed line: generated op lists filtered at compile time by what ODS
  says (`RuntimeCalls.cpp:149-157`, `Checks.cpp:117-125`, the families'
  static members), typed code below, no op listed in C++.
- **ods-Q4 (DRR).** Phase 2 needs 1:N conversion patterns, which DRR does
  not write (*conjecture*, CV-row M13 in §3).
- **Q-llvm-5 (one TableGen tool).** The runtime-ABI backend reads ops
  through `mlir::tblgen::Operator` but marks and helpers as raw records,
  and a C type's kind by its spelling (CV-54).
- **Q-O3, Q-E2 (facts into types).** The lowering's rederivations are
  each a fact a type or an op could hold: the token's constructor (CV-28),
  static data (CV-20), which fields a take gives (CV-33), the uniqueness
  test's answer (CV-30).

**New questions for the owner.**
- **NQ1 (CV-39, T12).** Euclidean division, the total shifts and the
  scalar-value test are written in C++ twice (folder, lowering) and
  division a third time in the runtime; none is a runtime primitive, so
  AGENTS.md's "its one meaning is the runtime's, which folders call too"
  is not kept for them. Make each a runtime function (a call in what the
  vectorization schedule sees, *conjecture*), or allow one C++ template
  instantiated for folding and for lowering as the one meaning?
- **NQ2 (T6).** Putting `idr-lower` under the pass manager needs every
  runtime function declared and every static datum materialized before
  the function pass. Accept those two program passes, or keep the
  worker-and-merge scheduler as an honest scheduler of ours (and say so
  in its header)?
- **NQ3 (T4).** Is the take's expansion (the test, the moves, the counts)
  counting's last step at the idr level, leaving the lowering only
  primitive ops, or does it stay the lowering's?
- **NQ4 (T9).** May a crash site reach the runtime as (cause, file, line,
  column), an ABI change, instead of one message string per site?
- **NQ5 (T7).** May the mangling prefix every program symbol, so that no
  program symbol can be a runtime symbol or `main`?

## 7. Deletion list

By file and symbol, each with the design that deletes it.
- `include/idr/Conversion/Fields.h`, `lib/Conversion/Fields.cpp` whole:
  `Fields`, `sameConstructor`, `kept`, `moved` (T3).
- `lib/Conversion/Counting.cpp`: `LowerTake` (T4: its expansion moves to
  counting); `LowerDrop`'s token arm (CV-31, the op split).
- `lib/Conversion/Cells.cpp`: `LowerCellRecycle`'s exclusive branch and
  `fields` member, `LowerCellInit`'s `kept` read (T3, T4); `LowerCon`'s
  boxed arm, `LowerTag`'s and `LowerField`'s `isBoxed` arms (T5).
- `lib/Conversion/Lower.cpp`: `Worker`, the runs and
  `failableParallelForEach`, `lowerProgram`'s merge call, the root-name
  filter of upstream's memref patterns (T6, CV-03).
- `lib/Conversion/Runtime.cpp`/`Runtime.h`: `appendParameter`,
  `resultType`, the switch in `Runtime::call(op, …)` (T1); `merge`, the
  `called` set (T6); `crashMessage` (T9); `countEach`'s `isStatic` test
  (CV-20).
- `lib/Conversion/RuntimeCalls.cpp`: `givenRange`'s switch (T1); the
  world arm of `LowerRuntimeCall` (with DS2).
- `include/idr/Conversion/StaticData.h`, `StaticData.cpp`,
  `StaticBytes.cpp`, `StaticNames.cpp`: the per-worker scratch module,
  `written()`, `collided()`, `Written` (T6); string keys (CV-44); the
  natural-alignment builders for strings, bigs, arrays and `nothing`
  (CV-45); `isStatic` (CV-20).
- `lib/Conversion/Bigs.cpp`: `lowBit` and the hand decode (T10).
- `lib/Conversion/Words.cpp`/`Words.h`: `groupBase` (T10).
- `lib/Conversion/Checks.cpp`: every `fails` overload and `LowerCheck`'s
  per-op instantiation, replaced by one `idr.check` pattern (T11).
- `lib/Conversion/Scalars.cpp`: the hand expansions of `LowerDivision`,
  `LowerShift`, `LowerToChar` (T12); the unsigned division arm (CV-38);
  `LowerWorldNew` (with DS2); the hand family list (CV-37).
- `lib/IR/Ops.cpp:200-293` (`idrisDivMod`, `idrisShift`) and
  `lib/IR/OpsScalars.cpp:31`'s scalar test (T12; lanes 03/04 hold the
  files).
- `lib/Conversion/FuncToFunc.cpp`: the `kept` collision check (T7); the
  whole phase if `func.func` is emitted (DD-Q7).
- `lib/Conversion/Entry.cpp`: `requiredCpuFeatures` (CV-47, lane 13);
  the `main` rename (T7); the `declared` lambda (T6).
- `lib/Conversion/Matches.cpp`: `lowerMatchLit`'s integer arm (CV-08);
  the optional in `Arm` (CV-11); the linear chain (CV-09).
- `lib/Conversion/Strings.cpp`: the `is_same_v` selections (CV-40);
  `LowerPutList`'s element-type choice (CV-41).
- `include/idr/IR/Traits.h:31-40`: `CallsRuntime` as an empty trait (T1:
  it gets the entry); `IdrRuntimeAbi.inc`'s `Abi<Op>` table, merged into
  the trait (T1).

## 8. Risks, unknowns, measurements needed

- **T6's static-data pre-pass must see every datum the lowering makes.**
  Today some are born in the conversion: a crash message per guard, the
  `nothing` of a poison cell pointer, an atom from a boxed `con`
  (`Cells.cpp:188-193, 298-301`; `Runtime.cpp:189-196`). Without T5 and
  T9 the pre-pass needs a ladder over those ops; with them each is an op's
  fact. If that fails, NQ2's other branch (the scheduler kept, named) is
  the fallback.
- **T4 moves work into counting** (lane 08): the take's expansion in idr
  ops must keep the verifier's rules (every reference consumed once) on
  the unique arm, where fields move without a count. Lean's
  expand-reset-reuse and Koka's Parc show it can be stated; our verifier
  has to state it.
- **T2's upstream patch** changes `llvm.call`'s effects for every user
  upstream; a call without `memory_effects` must stay unknown. Upstream
  receptiveness *unknown*.
- **Vectorization and T12** (*conjecture*): whether linalg bodies ever
  hold `divs`, shifts or `to_char` when the vectorization schedule runs;
  lane 11 knows. It decides NQ1.
- **Context contention from workers** (§5.1 F3, CV-16): unmeasured. A
  Tracy run of idr-lower on the stage-1 module, with the uniquer's lock
  wait, is the measurement; T9 and T6 remove most of the attributes made.
- **Load balance** (CV-02): the largest function's share of idr-lower's
  time on the stage-1 module, today, against the per-run average.
- **The wide take-apart after T4**: LLVM's time on records-past-the-cell
  with per-run counts, against the 11 s with the inlining budget
  (`audits/bugs.md:49-52`).
- **`Layouts::sizeOf`'s fallback from workers** (CV-55): whether any
  component type reaches it unmeasured; a fatal error there would show it.
- **Counts this lane could not run** (no built compiler): the stage-1
  module's number of crash sites, static data globals, runtime calls by
  symbol, takes, recycles and the share of them graded exclusive. Each is
  one statistic or one grep over the lowered module.
- **The generated ABI table read here is stale** (2026-10-18; it lacks
  `persistHeld`), so the 119 and 15 counts are approximate.

## 9. Sources read

- `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md`
  (whole); `proposals/0000-mlir-native.md` (whole, §0-§9, every lane's
  section); `proposals/0003-facts-once.md` (whole); `audits/p0/README.md`
  (whole); `audits/bugs.md:1-120`.
- The subsystem, whole, line by line: `lib/Conversion/{Bigs, Cells,
  Checks, Counting, Entry, Facts, Fields, Frame, FuncToFunc, Lower,
  Mangle, Matches, MemoCells, PassThroughMemory, Runtime, RuntimeCalls,
  RuntimeCells, Scalars, StaticBytes, StaticData, StaticNames, Strings,
  Words}.cpp`; `include/idr/Conversion/{Facts, Fields, Frame, FuncToFunc,
  IdrPattern, Mangle, Matches, Passes, PassThroughMemory, Patterns,
  Runtime, StaticData, Words}.h`.
- Beside it, the parts cited: `include/idr/IR/IdrBase.td:230-359`;
  `include/idr/IR/IdrRuntime.td` (whole); `include/idr/IR/IdrScalarOps.td:15-155`;
  `include/idr/IR/IdrCheckOps.td:22-50`; `include/idr/IR/IdrStringOps.td:60-91`;
  `include/idr/IR/IdrPlatformOps.td:138-151, 328-347`;
  `include/idr/IR/IdrIOOps.td:227-232`; `include/idr/IR/IdrInterfaces.td:274-290, 324-337`;
  `include/idr/IR/Traits.h:25-50`; `include/idr/IR/Symbols.h:236-326`;
  `include/idr/IR/Layout.h:85-100, 253-306`; `lib/IR/Layout/Layouts.cpp:106-141`;
  `lib/IR/OpsMatch.cpp:140-180`; `lib/IR/OpsOwnership.cpp:18-35`;
  `lib/IR/Verify/OwnedOps.cpp:20-40`; `lib/IR/Ops.cpp:200-300`;
  `lib/IR/OpsScalars.cpp:31`; `include/idr/Transforms/Passes.td:33-94,
  520-610, 700-780`; `lib/Transforms/Pipeline.cpp` (the tail, grep);
  `include/idr/Target/Target.h:75`;
  `tools/idris-mlir-tblgen.cpp:2700-3000`;
  `build/typecheck/foreign/idr/include/idr/IR/IdrRuntimeAbi.inc` (head,
  helpers, count); `runtime/idris_rt.h:55-120`; `runtime/Rc/Counting.cpp:30-80`;
  `runtime/Rc/Rc.h:40-130`; `runtime/Big/Arithmetic.cpp:17-25` (grep).
- Pinned MLIR: `mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td:815-880`,
  `LLVMOpBase.td:264-273`; `mlir/lib/Dialect/LLVMIR/IR/LLVMDialect.cpp`
  (grep for `getEffects`).
- Other lanes' documents, for overlap only: `audits/p0/08-counting.md`,
  `10-tail.md`, `18-runtime.md` (grep).
- History: `git log` of the subsystem (18 commits; `--follow` for
  `Lower.cpp`, `Counting.cpp`); `git show` of c4d38e9b, fc1a5daa,
  1c38fff5, da66bd95, 651164af, dbb34b31, 8bc44685, cfca1a06, 595ed341.
- Measurements: the token counts of §2 (`xargs cat < /tmp/conv-files.txt
  | grep -c`); `wc -l`; greps for `probe-stack`, `memory_effects`,
  `will_return`, `no_unwind`, `hasTrait<CallsRuntime>`, target names,
  `getPredecessors`/`getSuccessorRegions` over `foreign/idr`.
