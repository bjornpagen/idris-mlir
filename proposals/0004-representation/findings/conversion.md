<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Representation survey: conversion

Area: `foreign/idr/include/idr/Conversion/` and `foreign/idr/lib/Conversion/`
(all 31 `.cpp` and the 18 headers, read whole), with the types they consume
(`include/idr/IR/Layout.h`, `lib/IR/Layout/*`, `lib/IR/Verify/Program.cpp`,
the generated `IdrRuntimeAbi.inc` and its generator in
`tools/idris-mlir-tblgen.cpp`, `runtime/idris_rt.h`, `runtime/Rc/Rc.h`,
`lib/Analysis/Tail.cpp`, `lib/Transforms/Pipeline.cpp`). Paths below are
relative to `foreign/idr/` unless they start with `runtime/`, `tests/` or
`proposals/`.

## The area as it stands

The lowering is three passes. idr-lower renames the program's functions
(phase 0, a serial walk, `mangle`), lowers matches to scf (phase 1, the walk
driver), then converts each function on a worker of its own (phase 2, a
one-to-N dialect conversion whose type converter is `Layouts::components`,
meeting upstream's `LLVMTypeConverter` through materializations so upstream's
memref patterns work on descriptors), and merges what the workers wrote
(runtime declarations, static data, `@__idr_release_cafs`) and the LLVM facts
at function boundaries. idr-entry takes the lowered program apart and builds
`@main`. idr-tail-calls plans over the final LLVM dialect (a path interpreter
for tail position, a frame-escape walk, LLVM's own answer on return
registers) and rewrites each function in parallel. The earlier waves already
made the op-calling runtime ABI generated from ODS (0007 D9), built the
lowering options once (B4), fixed element alignment (B8), keyed static names
on raw content (B17), dropped the greedy driver's count (B18), made a force a
call with `idr.memo.enter`/`settle` (D2), added the `lowered` stage (D3) and
kept Facts' non-null test (D8); none of that is re-found here. The framework
use is mostly right: one-to-N conversion, two converters with
materializations, upstream's `MemRefDescriptor`, generic registration of
guards and runtime ops over `GET_OP_LIST`. The accidental casework sits where
one fact has two homes: the runtime's C prototypes (generated for op
functions, typed by hand at every other call), the ABI's kinds (one enum for
operand and result positions), the layout's self-description (prefix words
restated by two writers, facts decoded back out of a packed info word, a
counted list parallel to the components), the descriptor's free fields
(decided by four walks with two different tests), the tail plan (per-caller
copies of per-callee facts), and the static data walked twice, once to name
it and once to write it. No per-target casework was found: the target is read
from the module's data layout, from `#llvm.target` (ReturnRegisters asks
LLVM's call lowering), and from the target entry's feature list
(`runtime/cpu_features.h`).

## Findings, ranked (branches removed against risk)

### conversion-1: one runtime ABI kind for two positions, and the variant found by a search

| Field | Content |
|---|---|
| ID | conversion-1 |
| Evidence | Generated `idr::runtime::Kind` (`build/typecheck/.../IdrRuntimeAbi.inc:24-50`, from `tools/idris-mlir-tblgen.cpp:916-948` `Word`/`WordInfo`) holds operand-only kinds (World, Signed, Unsigned, Buffer), result-only kinds (Void, Wrapped, Order) and shared ones in one enum, and `Function` holds `bool noreturn` beside `Kind result`. Every consumer switch carries arms for the other position: `lib/Conversion/Runtime.cpp:68-91` `takes` (Void arm, `llvm_unreachable` at 90); `:94-117` `resultType` (World/Signed/Unsigned/Buffer arms 110-114, `llvm_unreachable` 116); `:145-189` `Runtime::call` (Void arm, `llvm_unreachable` 182); `lib/Conversion/RuntimeCalls.cpp:54-85` `givenRange` (World/Signed/Unsigned/Buffer arms, `llvm_unreachable` 84). The variant of an op with an operand of several kinds is found by a linear search with an assert: `Runtime.cpp:121-130` `functionTaking` (`assert` 128), fed by `include/idr/Conversion/Runtime.h:39-55` (`std::optional<bool> isSigned`). The generator guards the same states with fatal errors (`idris-mlir-tblgen.cpp:2237-2261`: several result kinds, more than one value, Order without predicate, noreturn with a value) and answers both positions through one `wordsOf(type, bool result, ...)` (`:2159-2195`). Count: 4 `llvm_unreachable`, 1 assert, about 10 dead arms, one 12-arm predicate (`takes`) that exists only for the search. |
| Counterexample | `Function{operands = {Kind::Void}, result = Kind::Buffer, noreturn = true}` is a value of the generated type; each switch above handles it with an unreachable arm. An op whose integer operand reaches `functionTaking` with `isSigned` empty matches no function and dereferences `end()` in a release build; only a generator check elsewhere keeps it from happening. |
| Root cause | The kind of a C parameter and the kind of a C result are one type, and "does not return" is a flag beside the result instead of a result; the variant an op calls is not part of the table, so the lowering rediscovers it. |
| Correction | The generator emits two enums, `runtime::Operand {World, Int32, Int64, Double, Signed, Unsigned, Str, Big, Buffer}` and `runtime::Result {Void, NoReturn, Int32, Int64, Double, Wrapped, Order, Str, Big}`, `Function{symbol, span<const Operand>, Result}`, and per op with a several-kinds operand a generated `Abi<Op>::of(Op)` that picks the variant from the operand's type and `is_signed` (the rule the generator already uses to name `_f64`, `_s`, `_u`). `wordsOf` splits into `operandKinds` and `resultKind`. |
| Deletion | `takes`, `functionTaking` and its assert, the `isSigned` optional in `runtimeFunctionOf`; the Void arm and `llvm_unreachable` in `Runtime::call` and `takes`; the four operand-only arms and the `llvm_unreachable` in `resultType` and `givenRange`; `Function::noreturn` and `Callee::noreturn` (now `Result::NoReturn`); the generator's `result` flag and its noreturn-with-value and several-results fatal errors, which the types no longer admit. |
| Consumers | `tools/idris-mlir-tblgen.cpp`; generated `IdrRuntimeAbi.inc`, `idris_rt_ops.h`; `include/idr/Conversion/Runtime.h`; `lib/Conversion/Runtime.cpp`; `lib/Conversion/RuntimeCalls.cpp`. The folders (`include/idr/IR/Fold.h`) read only the typed pointers and are untouched. |
| Discriminator | A `switch` over `Operand` with a `Void` case, or over `Result` with a `Buffer` case, does not compile; `Abi<StrShowOp>::of` on an `i32` operand with `is_signed = false` returns `idris_rt_str_show_u` by construction (a googletest box can enumerate every op's variants against the old search before the search is deleted). Lowered LLVM is identical on `tests/idr/lower/{io,big-fast-path,nat,buffer}.mlir`. |
| Verification here | `make typecheck` builds `idris-mlir-tblgen`, regenerates both files and compiles the C++; the runtime builds with host clang against the regenerated `idris_rt_ops.h`. The lowering's output is the owner's build. |
| Size and risk | About 60 lines and 16 branches go. Low risk: generated code plus two files, no layout or symbol changes. Essential and kept: Buffer's three C arguments and the sign or zero extension, which are what the kinds mean. 0002 §9's owed `crashes` flag (crash-sites against `MayCrash`) belongs in the same generated `Result`/op record. |
| Insight | 4 (illegal states), 6, 7 |

### conversion-2: every other runtime function is typed by hand at each call, and checked after the fact

| Field | Content |
|---|---|
| ID | conversion-2 |
| Evidence | Only op functions come from the table. Nineteen runtime functions are named as strings and typed from their arguments at each call: `RuntimeCells.cpp:27` (`idris_rt_cell`), `:99` (`idris_rt_is_unique`, an `i1`), `Arrays.cpp:45` (`idris_rt_array_new`), `Counting.cpp:47` and `Elements.cpp:78` (`idris_rt_free_cell`), `Memrefs.cpp:128` (`idris_rt_memref_copy`), `Strings.cpp:79,112,115,122,142-143`, `Checks.cpp:58,65`, `Runtime.cpp:224` (`idris_rt_crash`, `/*noreturn=*/true` by hand), `:243,247` (`inc`/`dec`), `:323-325,370-372` (`caf_release`, typed by hand and called around `callOp`), `Entry.cpp:83-91,122-126` (`main_return`, `start`, a second declaring helper). Five of them are op functions the table already types: `idris_rt_str_length`, `str_bytes_length`, `io_put_str`, `io_put_char` by hand, and `Strings.cpp:105` takes `Abi<StrScalarBytesOp>`'s symbol but types it by hand. Because the type is inferred per call, `Runtime::callOp` (`Runtime.cpp:198-215`) records the first type and sets `mistyped` on a second; `merge` checks again across workers (`:294-301`); both report "called as X and as Y". `declaration` (`:267-284`) guesses `zeroext` from an LLVM width below 32 because the C type is not known. `call`/`perform` (`Runtime.h:70-75`) split on whether there is a result. 0002 §9 owes "the `StringMap`s in `Conversion/Runtime.cpp`". |
| Counterexample | `idris_rt_cell`'s C prototype (`runtime/idris_rt.h:235`) changes its `size_t` to `uint32_t`: nothing in the compiler notices, every call still passes an `i64`, and the program links a call of the wrong type. A narrow signed C parameter would be declared `zeroext` by the width guess. Two sites typing one function differently become an internal error only when both appear in one module. |
| Root cause | The runtime's prototypes for functions no op calls exist only in the hand-written C header; the lowering restates each at its call sites. |
| Correction | Declare every runtime function the lowering calls in TableGen beside `Idr_Runtime` (a record class `Idr_RuntimeFunction<symbol, operands, result>` using conversion-1's kinds, with kinds for a cell pointer, `bool`, `size_t` and `uint32_t` added), generate their prototypes into `idris_rt_ops.h` as 0007 D9 did for op functions (the runtime then fails to compile on a mismatch), and give the lowering one call path, `Runtime::call(b, loc, const runtime::Function &, ValueRange)`, whose declaration type comes from the table. `called` becomes a set of table entries. |
| Deletion | `Callee`, `mistyped`, both "called as X and as Y" internal errors (`Runtime.cpp:203-207`, `:296-300`), the width-guessed `zeroext` (`:271-280`, now from the C kind), `perform` and the string-typed `call`, the hand `require` of `caf_release`, Entry's `runtimeFunction` helper and its two hand types, the hand-written prototypes in `runtime/idris_rt.h` for the generated functions, and the hand types at the 19 call sites. |
| Consumers | `include/idr/IR/IdrBase.td` (or a new `IdrRuntime.td`), `tools/idris-mlir-tblgen.cpp`, generated headers, `runtime/idris_rt.h` and the runtime definitions it declares, `include/idr/Conversion/Runtime.h`, `lib/Conversion/{Runtime,RuntimeCells,Arrays,Counting,Elements,Checks,Memrefs,Strings,Entry}.cpp`. |
| Discriminator | The runtime does not compile when a definition disagrees with the generated prototype (as D9 made true for op functions); a call site passing the wrong argument type fails the assertion in `Runtime::call` instead of producing a second declaration type. Lowered declarations are identical on `tests/idr/lower/{entry,io,counting,static-thunk}.mlir`. |
| Verification here | `make typecheck` (generator, C++); the runtime and `tests/toolchain/runtime-api` build with host clang. Behaviour is the owner's build. |
| Size and risk | About 45 lines and 8 guards go, 19 call sites simplify. Low to medium risk: the runtime header and generator change together. Essential and kept: `idris_rt_crash`'s `cold` at its call, and `idris_rt_array_new`'s `noalias` result, which could become table data too. |
| Insight | 6, 7, 16-limit noted (the C header stays the definition's home, generated) |

### conversion-3: a memref descriptor's free fields decided by four walks with two different tests

| Field | Content |
|---|---|
| ID | conversion-3 |
| Evidence | `lib/Conversion/Descriptors.cpp:35-48` (`Strided`, `stridedOf`: non-identity means strided, `getStridesAndOffset`'s failure ignored with `(void)`), `unpack` `:94-112` (branches at 102, 105-109; `assert` at 110 that the walk used every component), `pack` `:114-129` (121, 125), `componentsOf` `:145-167` (153, 161); and `lib/IR/Layout/Components.cpp:99-107` `descriptorWords`, which counts the same fields but tests `dyn_cast<StridedLayoutAttr>` instead. Seven `strided` branches in four walks over one fact. |
| Counterexample | A memref with a non-identity `AffineMapAttr` layout (what `memref.transpose` gives) is strided to `stridedOf` and not to `descriptorWords`: `Layouts::components` gives it no stride words, `unpack` reads strides from components that are not there, and the assert at `:110` is the only thing between that and reading past the range. A layout `getStridesAndOffset` rejects leaves `strides` empty and builds a descriptor without strides. |
| Root cause | Which descriptor fields a value carries (fixed, carried as a component, or derived row-major from the sizes) is not a value; each walk re-decides it from the type. |
| Correction | One plan per memref type, `layout::DescriptorFields` in `Layout.h`: the offset, each size and each stride as `Fixed(n)`, `Carried`, or `Derived` (an identity layout's strides), made once from the type, with a non-strided layout refused where the program's verifier holds buffer layouts. `Layouts::components` counts its `Carried` fields; `unpack`, `pack` and `componentsOf` iterate it. |
| Deletion | `Strided`, `stridedOf`, the seven branches, the assert at `:110`, and `descriptorWords`' own test. |
| Consumers | `include/idr/IR/Layout.h`, `lib/IR/Layout/Components.cpp`, `include/idr/Conversion/Arrays.h`, `lib/Conversion/Descriptors.cpp`, `lib/IR/Verify/Program.cpp` (the layout rule). |
| Discriminator | A fixture with a `memref.transpose` result reaching idr-lower: today the walks disagree (assert, or a wrong descriptor in release); after, the verifier refuses the layout or every walk agrees by construction. `tests/idr/lower/{arrays,value-buffers}.mlir` lower identically. |
| Verification here | `make typecheck`. |
| Size and risk | About 30 lines and 7 branches go, plus one latent disagreement. Low risk. Essential and kept: that an identity layout's strides are derived, not carried (it saves registers), now one case of the plan. |
| Insight | 11, 12, 6 |

### conversion-4: a cell's own words are restated by two writers, and its kind and object count decoded from a packed word

| Field | Content |
|---|---|
| ID | conversion-4 |
| Evidence | The prefix of a cell (header count and info, the count word, the group word) is written twice: dynamically in `RuntimeCells.cpp:32-50` (`storeHeader` with count `1` at offset 0, `storeCellWords` with `if (cell.countWord())` at 42 and `if (cell.group)` at 45) and statically in `StaticData.cpp:249-266` (`{i32 0, i32 info}`, the same two branches at 257 and 263). The header is a literal again at `StaticData.cpp:114,128` (arrays), `:308,317` (strings), `:351,361` (bigs); the info word's offset is the literal `4` at `RuntimeCells.cpp:70,75`; `Facts.cpp:30-34` writes `align 8` and `dereferenceable(8)` as literals. The group, one offset for the whole sum, is reachable only through a constructor's cell, so `RuntimeCells.cpp:60-61` guards `data.getCtors().empty()`. What `Layouts::cellOf` knew is decoded back out of `CellInfo`: `StaticData.cpp:193-195` `isMemoCell` (`idris_rt_info_kind`), used by `StaticNames.cpp:116-118`; `Memrefs.cpp:118` (`idris_rt_info_objs(element.info.word()) == 0`). Six branches, seven literal restatements, two decodes. |
| Counterexample | A memo cell's `layout::Cell` carries no `memo`; a sum with no constructors has a group nobody can ask for; the static and dynamic writers agree on where the count word goes only because both write `sizeof(idris_rt_header)` by hand. |
| Root cause | `layout::Cell` describes its fields' slots but not itself: its prefix is a bool and an optional the writers interpret, its kind and object count live only inside the packed `CellInfo`, and the group, a fact of the sum, is stored per cell. |
| Correction | `Layouts::cellOf` records the prefix as data, `SmallVector<layout::OwnWord{Slot slot; int64_t value}>` (info at `offsetof(idris_rt_header, info)`, the count word, the group word with its value), the count's slot from `offsetof(idris_rt_header, count)`; `CellInfo` exposes typed `kind()` and `objects()`; `Layouts` gives the group slot per sum (`Layouts::group(DataType)`). The static writer emits the prefix's words as members, the dynamic one stores them; Facts reads the header's size and the cell alignment from the same constants. |
| Deletion | The two `countWord` and two `group` branches, the empty-constructors guard, `isMemoCell` and the objs decode, `groupWord` in `Words.cpp` (the layout computes the value), the literal offsets and the four hand-written static headers (one helper over the header constants). |
| Consumers | `include/idr/IR/Layout.h`, `lib/IR/Layout/{Layouts,CellInfo}.cpp`, `lib/Conversion/{RuntimeCells,StaticData,StaticNames,MemoCells,Memrefs,Facts,Words}.cpp`, `include/idr/Conversion/{Runtime,Words}.h`. |
| Discriminator | Lowered LLVM and static globals identical on `tests/idr/lower/{box,static-thunk,layout,force-by-name,arrays}.mlir`; a googletest box (`make test-unit`) builds each cell of a grouped and a wide sum and checks the static and dynamic prefixes word for word against `idris_rt_info_*` and `offsetof`. |
| Verification here | `make typecheck`; the box links MLIR and is the owner's. |
| Size and risk | About 25 lines and 6 branches go. Low risk (a refactor). Essential and kept: the stack mark kept across a memo cell's states (`MemoCells.cpp:39-42`), and count 1 against count 0 (heap against static), passed as the one parameter. |
| Insight | 6, 8, 4 |

### conversion-5: poison of a cell pointer is null, so Facts runs an analysis to withhold the pointer facts

| Field | Content |
|---|---|
| ID | conversion-5 |
| Evidence | `Cells.cpp:152-168` lowers poison's counted components to null. Because a null that is `dereferenceable` is undefined behaviour, `Facts` walks the whole program before phase 0 (`Facts.cpp:65-94`: an `isa` ladder over `idr::CallOp`, `ConOp`, `ReuseOp`, a role test for memo labels at 69-72, `if (!callee)`, the poison test at 91) to collect every (function, parameter) some call passes poison, keyed by recomputed mangled names (`:67,74,89`), and `componentFacts` takes `bool mayBeNull` (`:39-46`, lookup at 105). `include/idr/Conversion/Facts.h:24-35,49-52`. Seven branches, a program walk and the reason Facts must run before phase 0. |
| Counterexample | One call that passes poison for a box parameter (what idr-tail-loops forwards on the path it does not take) strips `nonnull align 8 dereferenceable(8)` from that parameter for every caller. A memo label's capture stored as poison reaches its function through the dispatch, so the analysis has to model label constructors too. |
| Root cause | Absence of a cell is represented by null, a value outside the type "pointer to a cell" (Hoare's null), so every fact about cell pointers needs a proof that no null reaches it. |
| Correction | A null object: poison of a cell-pointer component lowers to the address of one persistent static cell, `nothing` (a header of count 0, a box's info with no object slots), written once by `StaticData`. Counting already ignores it (count 0 is persistent in `runtime/Rc/Rc.h:31,63-78`, and `StaticData::isStatic` skips the address at the call). Other counted components (a big's word, a sum's slot, an array's cell) keep the runtime's empty value. Facts then reads each function's idr signature after phase 0 from the `func.func`, keyed by the op. |
| Deletion | `Facts::poisoned`, the constructor's walk, `labelFunction`, `mayBeNull`, the mangling in Facts, and the ordering constraint that builds Facts before phase 0 (`Lower.cpp:180`). |
| Consumers | `lib/Conversion/{Cells,StaticData,Facts,Lower}.cpp`, `include/idr/Conversion/{Facts,StaticData}.h`, `tests/idr/lower/llvm-facts.mlir` (kept as a text contract by 0002 R2). |
| Discriminator | `llvm-facts.mlir` gains a function whose parameter one caller passes poison: before, no `llvm.nonnull` on it; after, the three facts. An e2e program whose tail loop forwards poison runs with `idris_rt_live_cells` back at its start. |
| Verification here | `make typecheck`. |
| Size and risk | About 40 lines and 7 branches go; one static global is added. Medium risk: lowered code changes (an address where a null was), and a field read of `nothing` on a dead path must stay dead, which it is by poison's meaning. |
| Insight | 8 (null object), 5 |

### conversion-6: the components of a value and whether each is counted, as two parallel lists

| Field | Content |
|---|---|
| ID | conversion-6 |
| Evidence | `Runtime::inc`/`dec` take `ValueRange components` and `ArrayRef<bool> counted` matched by position (`Runtime.h:157-160`, `Runtime.cpp:377-387` `zip_equal`), at 13 call sites (`Arrays.cpp:134,148,150,181`; `Counting.cpp:33,49,157,175`; `Elements.cpp:55,57-59,80,81`; `Cells.cpp:161-164`). A lone cell is the literal `{true}` three times. `LowerTake` keeps four parallel vectors (`Counting.cpp:150-158`: `moving`, `dying`, `movingCounted`, `dyingCounted`). Upstream of them, `Layouts::components` and `Layouts::counted` are two walks over one six-way type split (`lib/IR/Layout/Components.cpp:127-170`), `SumLayout` holds `slots` and `counted` side by side (`Layout.h:145-146`), and `cellOf` a `countedness` list beside the slots (`lib/IR/Layout/Layouts.cpp:170-177`). |
| Counterexample | A `counted` list one shorter than its components fails only at `zip_equal`'s assert; the `{true}` sites restate a fact `Layouts` holds and would not follow a change to how a cell pointer is counted. |
| Root cause | A component's type and its countedness are one fact held as two lists. |
| Correction | 0020 N1 as designed there (`proposals/0020-niche-sums.md` §5, N1): `layout::Component{Type type; bool counted; ...}`, `Layouts::components` returns them, `Layouts::counted` and `countedOf` are deleted. On this side, `Runtime::inc`/`dec` take only the references, `ValueRange`, selected once from a value's components by its `Component`s, so a lone cell is just the cell. |
| Deletion | `Layouts::counted`, `layout::countedOf`, `SumLayout::counted`, `cellOf`'s `countedness`, the `ArrayRef<bool>` parameter, the three `{true}`, `LowerTake`'s two bool vectors, `LowerPoison`'s second list. |
| Consumers | `include/idr/IR/Layout.h`, `lib/IR/Layout/{Components,Layouts}.cpp`, `lib/IR/Verify/Program.cpp`, `include/idr/Conversion/Runtime.h`, `lib/Conversion/{Runtime,Counting,Elements,Arrays,Cells,Facts}.cpp`. |
| Discriminator | 0020 N1's own: executables byte-identical to the parent (a refactor); the `Niches` box when N2 follows. |
| Verification here | `make typecheck`. |
| Size and risk | About 50 lines across IR and conversion, 13 call sites simplified. Low risk. N1 is queued AFTER-SELF; doing it in this wave pulls it forward with no layout change. |
| Insight | 4, 6 (parallel lists) |

### conversion-7: the tail-call plan copies per-callee facts into per-caller lists, beside flags that admit invalid combinations

| Field | Content |
|---|---|
| ID | conversion-7 |
| Evidence | `include/idr/Conversion/TailCallPlan.h:42-59`: `Function{bool tail; tailCalls; tailccCalls; bool resultInMemory; throughSlot}`. `tailccCalls` is the caller's list of calls whose callee has `tail`, and `throughSlot` its list of calls whose callee has `resultInMemory`, both computed by a last loop over every function (`TailCallPlan.cpp:199-218`, with `reach(fn, {})` and `forEachCallKept`, `:69-80`) although `place` erases the unreachable blocks itself before it uses them (`TailCalls.cpp:106`). `tail` and `inMemory` are kept again as `ByName` maps (`:146-156`, `:184-197`). The rewrite reads the lists (`TailCalls.cpp:93-96,107-112`). Three branches in the last loop, two flags whose combination is partly invalid, two derived lists. |
| Counterexample | `Function{tail = false, resultInMemory = true}` and `Function{tail = false, tailCalls = {c}}` are representable (make() never builds them, place() would apply them); a caller's `tailccCalls` can name a call to a function whose own entry says `tail = false`. |
| Root cause | A function's convention (C, tail, tail with the result through memory) is one three-valued fact held as two bools, and its consequences for each call site are stored with the caller instead of read from the callee. |
| Correction | `enum class Convention {C, Tail, TailThroughMemory}` per function, in one read-only map by symbol, plus each function's planned `tailCalls`. `place` sets a call's convention and its slot from its callee's `Convention` after it has erased what the entry no longer reaches, skipping its own planned calls. |
| Deletion | `tailccCalls`, `throughSlot`, `Function::tail`, `Function::resultInMemory`, the last loop of `make`, `forEachCallKept`, the `reach(fn, {})` calls, the `inMemory` map. `reach(fn, planned)` stays: it drops a planned call an earlier one makes unreachable, which decides who is on a tail call. |
| Consumers | `include/idr/Conversion/TailCallPlan.h`, `lib/Conversion/{TailCallPlan,TailCalls,PassThroughMemory}.cpp`. |
| Discriminator | `tests/idr/tail-calls/*` and idr-expect's `constant-stack`/`tail-calls` properties hold unchanged, and the pass's statistics (`numTailCalls`, `numInMemory`, `numFrameBound`) are equal on the fixtures. |
| Verification here | `make typecheck`. |
| Size and risk | About 35 lines and 5 branches go. Low to medium risk (the rewrite's order matters: conventions before slots, slots after erasure). Essential and kept: see "kept" on the two tail-position analyses. |
| Insight | 4, 6 |

### conversion-8: idr-entry re-checks the lowered stage, and the root's kind is decided twice by two rules

| Field | Content |
|---|---|
| ID | conversion-8 |
| Evidence | `lib/IR/Verify/Program.cpp:53-63` admits a root `() -> i64` or `(!idr.world) -> (...)`, any results. idr-entry decides the kind again from the lowered type (`lib/Conversion/Entry.cpp:111-115`: `status` when the lowered root is `() -> i64`, internal error unless `() -> ()`), re-checks that the root is a lowered function (`:40-44`), which the lowered stage's verifier already holds (`Program.cpp:258-266`), and looks up `@__idr_release_cafs` by a string literal with an internal error (`:127-130`) that `Runtime::merge` makes from its own literal (`Runtime.cpp:362`). Three internal errors and one second rule. |
| Counterexample | A root `(!idr.world) -> (!idr.world, i64)` verifies; it lowers to `() -> i64`, and idr-entry takes it for an exit-status root: the program's status becomes the IO action's result, with no error. A root returning `(!idr.world, !idr.str)` reaches idr-entry's internal error instead of the verifier. |
| Root cause | The root's kind is a fact of the program decided by a predicate that returns a bool, so the entry re-derives it from a lowered shape; the lowered stage states only one of the facts idr-entry relies on. |
| Correction | `enum class RootKind {Status, IO}` returned by one `rootKind(FunctionType)` in `lib/IR` that admits exactly `() -> i64` and `(!idr.world) -> !idr.world`; the lowered stage's verifier holds the lowered forms (`() -> i64` or `() -> ()`) and the presence of `@__idr_release_cafs`, named by one constant both passes read. idr-entry reads the kind and builds `@main`. |
| Deletion | Entry's three internal errors (`:40-44`, `:111-115`, `:127-130`), the second `status` predicate, the two literals of the release function's name. `@main`'s own collision check stays (a C name). |
| Consumers | `lib/IR/Verify/Program.cpp`, an IR header for `RootKind` and the name, `lib/Conversion/{Entry,Runtime}.cpp`, `tests/idr/verify/` (a new refusal fixture), `tests/idr/lower/entry.mlir`. |
| Discriminator | The IO root with an `i64` result is refused by the verifier, before any pass; today it verifies and silently changes the exit status. |
| Verification here | `make typecheck`. |
| Size and risk | About 15 lines and 3 internal errors go; one latent wrong program is ruled out. Low risk. |
| Insight | 6, 4 |

### conversion-9: a static datum is walked twice, once to name it and once to write it

| Field | Content |
|---|---|
| ID | conversion-9 |
| Evidence | Naming: `StaticNames.cpp:49-66` `fieldKey` (world, string, scalar, in-place sum, box), `:74-90` `boxName` (run or not), `:93-113` `runNames`. Writing: `StaticData.cpp:60-75` `constant` (the same ladder), `:147-159` `box` (run or not), `:165-190` `run`. The run cell's spine re-indexing `i < spine ? i : i - 1` is written in both (`StaticNames.cpp:107`, `StaticData.cpp:185`); each ladder ends in `cast<ConAttr>` that assumes the other cases were handled (`StaticNames.cpp:57`, `StaticData.cpp:71`). |
| Counterexample | A new constant attribute kind added to `constant` but not to `fieldKey` asserts in `cast<ConAttr>` the first time a box holds one. |
| Root cause | A static datum's key and its components are produced by two walks; nothing holds "a datum" as one value. The run cell's fields without the spine is a coordinate every reader re-indexes (`ConAttr` offers `getField` for the first cell only). |
| Correction | One recursive `StaticData::datum(Attribute, Type) -> Datum{std::string key; components}` with the ladder once: a box's children are written first and keyed by their names, so the parent's name follows from them and the global is written if absent. A `ConAttr::runField(cell, index)` accessor in IR gives a run cell's field in field coordinates. |
| Deletion | `fieldKey`, `boxName`, `runNames`, `boxNames`, one of the two ladders, both spine re-indexings. |
| Consumers | `lib/Conversion/{StaticData,StaticNames}.cpp`, `include/idr/Conversion/StaticData.h`, `include/idr/IR/` (ConAttr declaration), `lib/IR/ConAttr.cpp`. |
| Discriminator | Static global names and contents identical on `tests/idr/lower/{constants,static-thunk,linear-constant}.mlir` (the key text is unchanged); a long constant list still writes with constant stack. |
| Verification here | `make typecheck`. |
| Size and risk | About 40 lines and one duplicated four-case ladder go. Low to medium risk (names must stay byte-identical). |
| Insight | 6 (one fact, one place), 11 |

### conversion-10: a string or big literal match with no case is special-cased because the chain has no first link

| Field | Content |
|---|---|
| ID | conversion-10 |
| Evidence | `lib/Conversion/Matches.cpp:103-125`: `if (integer \|\| cases == 0)` sends a caseless string or big match through the integer switch with a made-up index 0 (`:106-107`); `:129-154` threads `first` and `previous` with `if (previous)` twice. Four branches. |
| Counterexample | `idr.match_lit` on a string with only a default lowers to an `scf.index_switch` on the constant 0. |
| Root cause | The comparison chain starts at the match's own position, so its first link differs from the others and the empty chain has nowhere to start. |
| Correction | A sentinel: the chain is built inside one `scf.execute_region` made at the match, every link (the first included) yields its `scf.if`'s results into the block before it, and the empty chain is the default's body alone; canonicalization and scf-to-cf inline the region. |
| Deletion | The `cases == 0` disjunct, `if (!integer)`, both `if (previous)`, and `first`. |
| Consumers | `lib/Conversion/Matches.cpp`, `tests/idr/lower/match-lit.mlir`. |
| Discriminator | A caseless string match lowers with no `scf.index_switch`; `match-lit.mlir`'s programs return the same results. |
| Verification here | `make typecheck`. |
| Size and risk | About 10 lines and 4 branches. Low risk. Essential and kept: integer keys through `scf.index_switch`, string and big keys through comparisons. |
| Insight | 8 (sentinel), 11 |

### conversion-11: the crash message finds its source location by a hand walk that the report does with MLIR's

| Field | Content |
|---|---|
| ID | conversion-11 |
| Evidence | `lib/Conversion/Runtime.cpp:40-55` `describe`: an `isa` ladder over `FileLineColRange`, `FusedLoc`, `NameLoc`, `CallSiteLoc` (callee only). `lib/Driver/Outcome.cpp:75` and `lib/IR/Verify/Knots.cpp:39` use `Location::findInstanceOf<FileLineColRange>()`, upstream's pre-order walk. |
| Counterexample | `callsite(unknown at "M.idr":3:1)`: the crash message says no place (`describe` follows only the callee), the `--report` line names `M.idr:3`. |
| Root cause | "Where in the source is this location" is defined twice. |
| Correction | `describe` is `loc->findInstanceOf<FileLineColRange>()`, formatted. |
| Deletion | The four-arm ladder and its recursion. |
| Consumers | `lib/Conversion/Runtime.cpp`, `tests/idr/lower/crash.mlir`. |
| Discriminator | A crash at a call-site location whose callee is unknown names the caller's file and line. |
| Verification here | `make typecheck`. |
| Size and risk | About 15 lines, 4 branches. Low risk. |
| Insight | 7, 13 (the mechanism MLIR already has) |

### conversion-12: the small Integer word, 2v+1, is restated at seven sites

| Field | Content |
|---|---|
| ID | conversion-12 |
| Evidence | `lib/Conversion/Bigs.cpp:25-28,36-39,53-58` (low bit, `shl 1 \| 1`, `shr 1`), `Words.cpp:30-37` (`groupWord`: `*2+1`; `groupBase`: `>>1`), `RuntimeCalls.cpp:69-70` (`2lo+1`, `2hi+2`), `StaticData.cpp:338` (`word & 1`), `Checks.cpp:43-45` (the big zero is the word 1); `runtime/Rc/Rc.h:23-26` has its own. `runtime/idris_rt.h:151-162` exports the bounds (0002 F22) but states the encoding only in prose. Bigs.cpp's own header says the tagged arithmetic "exists once and is inlined" from the runtime, which two of its own patterns contradict. |
| Counterexample | A change of the small word's encoding (0018's work on word shapes is the likeliest source) must be found by hand at seven compiler sites; a missed one miscompiles silently (a wrong `range` on a call, a wrong static big, a wrong nonzero guard). |
| Root cause | The runtime exports the small range, not the encoding. |
| Correction | `runtime/idris_rt.h` exports the encoding as constexpr functions beside `idris_rt_info` (`idris_rt_small_word`, `idris_rt_word_is_small`, `idris_rt_small_value`); compile-time sites call them; `BigSmallOp` and `NatToExtentOp`'s test call the runtime's inline functions through `Idr_Runtime` marks, as every other big op does, and LTO inlines them. |
| Deletion | `lowBit`, `LowerBigSmall`, the arithmetic in `LowerNatToExtent`, `groupBase`'s and `groupWord`'s arithmetic, the literals in `givenRange`, `StaticData::big` and `CheckNonzero`, and Rc.h's copy. |
| Consumers | `runtime/idris_rt.h`, `runtime/Rc/Rc.h`, `runtime/Big/*`, `include/idr/IR/IdrBigOps.td`, `lib/Conversion/{Bigs,Words,RuntimeCalls,StaticData,Checks}.cpp`, `include/idr/Conversion/Words.h`. |
| Discriminator | A googletest box checks `groupWord`, `givenRange` and the static big against the runtime's constexpr functions over every small value within 2 of 0 or of ±2^k (0002 §4.5's box); `tests/idr/lower/{nat,big-fast-path}.mlir` lower to calls LTO inlines to the same code. |
| Verification here | `make typecheck`; the runtime and its property programs build and run with host clang. |
| Size and risk | No branch, seven restatements, about 35 lines. Low risk. |
| Insight | 6 (one fact, one place) |

### conversion-13: ops with no runtime form are listed by hand in four populate functions

| Field | Content |
|---|---|
| ID | conversion-13 |
| Evidence | `LowerAsItself` is registered for `LinEnterOp`, `LinUseOp` (`Cells.cpp:216`), `BorrowOp`, `ShareOp`, `OwnAdoptOp`, `OwnGiveOp` (`Counting.cpp:196-197`), `TieShapeOp` (`Memrefs.cpp:144`), `NatToBigOp` (`Bigs.cpp:71`). Four of them carry `Idr_ResultCarriesOperand` (`include/idr/IR/IdrOwnershipOps.td:93,108,237,251`), which the lowering does not read; guards and runtime ops are already registered generically over `GET_OP_LIST` (`Checks.cpp:110-130`, `RuntimeCalls.cpp:141-162`). |
| Counterexample | A new grade-changing op with `Idr_ResultCarriesOperand` fails to legalize until someone adds it to one of four lists; nothing ties the trait to the lists. |
| Root cause | "Lowers to its operand's components" is a property of the op held only as list entries in the lowering. |
| Correction | An ODS trait `Idr_NoRuntimeForm` on those eight ops, and one generic registration of `LowerAsItself` for every op that has it, as Checks and RuntimeCalls do. |
| Deletion | The four hand lists. |
| Consumers | `include/idr/IR/IdrInterfaces.td`, `include/idr/IR/IdrDialect.h`, the ops' `.td` files, `lib/Conversion/{Cells,Counting,Memrefs,Bigs}.cpp`, `include/idr/Conversion/IdrPattern.h`; the coordinator regenerates the dialect modules if the trait reaches them. |
| Discriminator | Removing an op from the trait makes idr-lower fail to legalize it on its fixture; adding the trait to a new op lowers it with no lowering change. |
| Verification here | `make typecheck`. |
| Size and risk | Four lists, about 10 lines. Low risk. |
| Insight | 7 |

### conversion-14: a buffer's alignment and layout are checked in two lowering patterns instead of once at the stage

| Field | Content |
|---|---|
| ID | conversion-14 |
| Evidence | `StaticData.cpp:77-92` (`ConstantArray::of`: alignment above a word is an internal error) and `Arrays.cpp:61-67` (`LowerAlloc`: a non-identity layout and an alignment above a word are internal errors); `tests/idr/lower/internal-errors.mlir` exercises one. The comment there says bufferization never asks for more. |
| Counterexample | `memref.alloc {alignment = 64}` verifies, survives every pass, and is refused as an internal error in the middle of idr-lower's parallel conversion. |
| Root cause | A rule of the owned stage (a buffer is a runtime cell: identity layout, at most word-aligned) is held as two pattern-time checks. |
| Correction | The owned stage's verifier (`lib/IR/Verify/Program.cpp`, beside its data-layout rule) holds it for every `memref.alloc` and `memref.global` of the program. `ConstantArray::of` keeps parsing what makes a global a constant array (constant, elements, words). |
| Deletion | Two internal errors in `LowerAlloc`, the alignment branch in `ConstantArray::of`. |
| Consumers | `lib/IR/Verify/Program.cpp`, `lib/Conversion/{Arrays,StaticData}.cpp`, `tests/idr/lower/internal-errors.mlir` (its second case moves to `tests/idr/verify/`). |
| Discriminator | The over-aligned allocation is refused by the verifier before any pass. |
| Verification here | `make typecheck`. |
| Size and risk | About 10 lines, 3 checks. Low risk. |
| Insight | 6 |

### conversion-15: the lowering's own symbols share the program's namespace, and collisions are checked rather than excluded

| Field | Content |
|---|---|
| ID | conversion-15 |
| Evidence | Reserved names are literals in four files: `StaticNames.cpp:27` (`"__idr"`), `lib/Target/Partition.cpp:53` (`"__idr."`), `Runtime.cpp:362` and `Entry.cpp:127` (`"__idr_release_cafs"`), `Entry.cpp:134` (`"__idr_main"`). `mangle` keeps `[A-Za-z0-9_.]` (`Mangle.cpp:19`), so a program symbol can spell any of them; `Runtime::merge` checks with two internal errors (`Runtime.cpp:333-338`, `:363-365`). |
| Counterexample | An idr symbol `__idr.box.0123456789abcdef` mangles to itself and collides with a static datum; the merge reports an internal error. |
| Root cause | No coordinate separates compiler-made names from mangled program names. |
| Correction | One constructor of reserved names in `include/idr/IR/Symbols.h` whose first `$` is followed by a letter (`__idr$box$<hex>`): `mangle` writes `$` only to open an escape followed by a digit, so no mangled name can equal one, and no C name has a `$` in the runtime. Static data, the release function, the entry body and Partition's cross-bin names use it. |
| Deletion | The two collision internal errors in `merge`, the four literals. |
| Consumers | `include/idr/IR/Symbols.h`, `lib/IR/Symbols.cpp`, `lib/Conversion/{StaticNames,Runtime,Entry}.cpp`, `include/idr/Conversion/Mangle.h` (its doc states the property), `lib/Target/Partition.cpp`, `tests/idr/lower/{entry,static-thunk,io,value-buffers}.mlir`, `runtime/idris_rt.h` (a comment). |
| Discriminator | A googletest box: `mangle` of every string over a small alphabet including `$` and digits never equals a reserved name. |
| Verification here | `make typecheck`. |
| Size and risk | About 12 lines, 2 internal errors. Low risk; symbol names change, so fixtures that name them change. |
| Insight | 11, 12 |

## Judged essential, and kept

- **Boxed against in place** in `LowerCon`, `LowerTag`, `LowerField`, `LowerTake` (`Cells.cpp:66,93,116`, `Counting.cpp:131`): two representations of a data value, one switch per op. Splitting each into two patterns would move the `if`, not remove it. 0020 adds niches inside `SumLayout`, not a third branch here.
- **An element in place or boxed** (`Elements.cpp`, four functions × two cases). The two cases are the problem's. `layout::Element` as a variant (so `slots` would not mean two things) is IR's to decide and removes no branch.
- **Tail position at two IR levels.** `idr::tail::inTailPosition` (`lib/Analysis/Tail.cpp`) serves idr-tail-loops, borrows and idr-stack; `TailPaths` (`TailPosition.cpp`) decides `musttail` on the final CFG, where scf-to-cf has put branches between a call and its return. No MLIR mechanism carries a call's tail-ness from `func.call` to `llvm.call` except a discardable attribute, which AGENTS.md forbids, and `musttail` must be adjacent to its return, which only the final CFG shows. `Frame` is the safety net for what the two disagree on.
- **`Frame`'s `isa` list** of pointer-carrying LLVM ops (`Frame.cpp:46-49`): upstream's `LocalAliasAnalysis` follows neither loads of pointers nor `insertvalue`/`extractvalue`, and LLVM's capture tracking is not on the LLVM dialect.
- **`Fields`' side table** (`Fields.cpp`): the conversion replaces a take before its reuse is converted, so the identity of their fields is read once before the boundary. Its optional (another constructor, or the same one with a mask) is a two-case sum.
- **Content-name collision checks** per worker and at the merge (`Runtime.cpp:308-317`): names are 64 bits of a 128-bit digest by design (`Symbols.h`, ContentNames: "never a merge and never a longer name").
- **`ConstantArray::of`**: a parser at the boundary, done right (conversion-14 moves only its alignment rule).
- **`unrestricted()` before type switches**: the grade carries exclusivity the lowering reads (`isExclusive` in `LowerReuse`, `LowerTake`), so the wrapper cannot be stripped before phase 2.
- **Signed and unsigned arms** in `LowerDivision`, `LowerShift`, `LowerToChar`: Idris's two semantics; arith itself splits them into ops.
- **Ops polymorphic over two operand kinds**: `MatchLitOp` (integer against string or big), `CheckInBoundsOp` (string or array), `CheckNonzeroOp` (integer or big): one switch each, on what ODS admits.
- **`LowerDrop`'s token branch**: freeing an emptied cell is not a count.
- **`countEach`'s `inttoptr`** for a big's word: a big is an `i64` by design (arithmetic on small words, raw addresses for the prefetcher).
- **Per-worker `Runtime`, converter, target and patterns** (`Lower.cpp:68-155`): parallel conversion with no shared writes; the merge orders the result.
- **Phase 0 as a serial walk** rather than conversion patterns: renaming writes the shared symbol table, and phase 2 runs per function in parallel.
- **`ReturnRegisters`** asks the target's own call lowering; no per-target casework.
- **`StaticData::pack`'s `insertvalue` chain**: members include addresses of globals, which no LLVM constant attribute holds.
- **`TailCallPlan::of`'s static `nothing`**: already a null object.
- **Two converters** (components and descriptors) with materializations: 0007's decision that memrefs inside a function lower through upstream's patterns on a descriptor built at the use.

Minor, below the bar of a finding (one line each, for whichever lane touches the file):
- A dialect is identified by comparing its namespace string (`Lower.cpp:93`, `Descriptors.cpp:192`); `isa<IdrDialect>(type.getDialect())` says it.
- The index materialization lambda is written twice (`Descriptors.cpp:216-221`, `:227-232`).
- Upstream's `memref.get_global` and `memref.global` patterns are filtered out by root kind (`Lower.cpp:147-153`) while every other override wins by `ownLowering`'s benefit; one mechanism would do.
- `tests/idr/lower/cpu-features-x86-64.mlir` has no arm64 counterpart (tests' area: a first-class target's feature list goes untested there).
