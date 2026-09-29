# cpp-modern (b): the conversion worklist, file by file

Side file of `cpp-modern.md`. Every C++ file of idris-mlir, with what it
becomes: the zone and module it moves to, the `std::variant`s to introduce
(with their alternative types), the `std::expected` paths, the concepts and
constrained templates, and what blocks `noexcept`. Line numbers are
`/home/user/idris-mlir` at d8b70eb.

Read section 0 first: it defines the shared types that many files use, so
that each row can name them instead of repeating them.

---

## 0. Conventions and shared types

### 0.1 Columns

- **Zone**: `S` = a module in `src/` (dialect code), `G` = glue in
  `foreign/idr/` (TableGen hooks, pass bases, MLIR base classes, `main`),
  `U` = `unsafe/` (fork, mmap, signals, pthreads, raw JIT memory),
  `R` = `runtime/`.
- **noexcept blockers**: `TG n` = n hooks whose declaration TableGen
  writes (exempt by name, `cpp-modern-lint.md` section 2); `FT n` = n
  lambdas handed to an MLIR API that deduces them through
  `llvm::function_traits` (`walk`, `TypeSwitch`, `Attribute::walk`,
  `TypeConverter::addConversion`), which become calls of
  `support::walk`/`support::type_switch`/`support::walk_attrs`. Everything
  else takes `noexcept` with no obstacle. The counts come from the full lint
  run (`cpp-modern-lint.md` section 8).
- Every file also gets, without further mention: `noexcept` on every
  function and lambda, trailing return types, `snake_case` for our own
  names, the three comment forms (`//` narration becomes a `/** */` block on
  the declaration or a better name; closers and banners go), `.clang-format`.

### 0.2 The variant rule, as applied here

The user's rule: every closed set of alternatives is a `std::variant`. The
audit applies it to six shapes, and names the shape in each row:

| Shape | Example today | Becomes |
|---|---|---|
| **tag + payload** (a kind field, and fields meaningful for some kinds only) | `Abstract{Kind kind; unsigned param}` | `std::variant<Top, Same{param}, Smaller{param}>` |
| **null-as-case** (a null handle or pointer that means something other than absence) | `Escapes::Flow = std::optional<...>`, nullopt = "escapes" | a variant with the named alternative |
| **null-as-absence** | `CtorOp lookupCtor(...)` returns null | `std::optional<CtorOp>` (optional is the variant with `nullopt`, `AGENTS.md:627-637`) |
| **bool selector** (a bool parameter or member that picks behaviour) | `Runtime(..., bool jitMode)` | a variant of the modes, each carrying its data |
| **parallel arrays** (vectors indexed together) | `SumLayout::slots` + `counted` | one vector of a product whose field is the alternative |
| **isa-chain over our own closed set** (`dyn_cast` chains over idr types, attributes or ops) | `Layouts::components` | `support::classify<Ts...>(x)` then a visitor struct |
| **enum switched to select behaviour** | `BindingTime` + `switch` in `count`, `nameOf` | a variant of empty structs (alternatives gain their data when they have any), visited |

Not variants: an enum that is only compared or used as a key; an enum ODS
generates (it stays, and C++ switches on it only in the one function that
lifts it into a variant); a product of independent facts, which is a
product (a struct of enums, or a set).

### 0.3 Shared types (defined once, used by many rows)

In the `support` module (`foreign/idr/support/`, glue for the lint's
lambda rule only; prototypes tested in `snip/support.cc`,
`snip/classify.cc`, `snip/fnpat.cc`):

- `support::classify<Ts...>(From) -> std::variant<Ts..., Other<From>>`:
  MLIR's open `isa` world into a closed sum.
- `support::walk<Op>(Operation&, F) requires std::is_nothrow_invocable_v<F&, Op>`,
  `support::type_switch`, `support::walk_attrs<A>(Attribute, F)`: the only
  lambdas MLIR sees.
- `support::Box<T>`: value-semantic heap box until libc++ ships
  `std::indirect` (`PIN(libcxx-no-indirect)`).
- `support::invariant(bool)`: the fail-stop helper (`PIN(clang-contracts)`,
  cpp-starter's `unsafe/net.internal.h:76-81`); it replaces `assert` and
  `llvm::report_fatal_error`.
- `support::Error = std::variant<Rejected, Internal>` with
  `Rejected{Reason reason; ...}`, `Reason` a variant of the C++ side's
  rejections (`Budget{BudgetKind kind; std::uint64_t limit}`, where
  `BudgetKind` is `SimplifyRounds` (`Simplify.cc:97`) or `ClonesPerOwner`
  (`Clones.cc:89`); `RuntimeMember{...}` (`idris-mlir-cc.cc:252`)), and
  `Internal{std::string what}`. `support::render(Location, Error const&)`
  is the one place that writes the text `unsupported (...)` or
  `internal error: ...`; `support::to_logical(expected<T, Error>, Location)`
  is the one adapter to `LogicalResult`. The tool classifies by the variant
  (via diagnostic metadata, mlir-idioms.md section 3), not by matching
  `"unsupported ("` in the text (`idris-mlir-cc.cc:371-378`).
- `support::FnConversion<Op, auto Fn>`: the one conversion-pattern class;
  rewrite patterns are `RewritePatternSet::add(fn)` (MLIR's `FnPattern`,
  `PatternMatch.h:910-929`).
- `support::references(func::FuncOp, SymbolTable&) -> SmallVector<Reference>`
  with `Reference = std::variant<Calls{func::CallOp}, Closes{ClosureOp},
  Names{ClosureAttr}>` and the target: one definition of "the functions a
  function refers to". Today it is written six times, with small
  differences: `BindingTimes.cc:25-43` (`forEachReference`),
  `Inline.cc:56-83`, `Borrow.cc:78-90`, `Stack/Recursion.cc:33-47`,
  `LoopBreakers.cc:60-67`, `Facts/Infer/Infer.cc:31-58`.
- `support::definer(Value) -> std::optional<Operation&>` and
  `support::only_user(Value) -> std::optional<Operation&>`: `getDefiningOp()`
  and the one-use idiom without null pointers (14 `getDefiningOp()` sites,
  `Raise.cc:159`).

In `facts` (the module `idr.facts` becomes):

- `facts::Effects`: one representation of "what running code may do". Today
  it is two: the C++ struct of three bools (`Facts/Effects.cppm:9-17`) and
  the ODS bit enum `idr::Effect` (`io | crash`) that `Record.cc:10-15` and
  `Of.cc:16-19` translate between. A set of independent atoms is a set, not
  a sum: `Effects` becomes the ODS bit enum extended with `diverges`
  (today `partial`), and `Of.cc`/`Record.cc` shrink to reading and writing
  it.
- `facts::Termination = std::variant<Total, Partial>`: today
  `Evaluation::total` (`Evaluation.cppm:17`) and `Outcome`'s budget choice
  (`Eval.cc:91`).

In `layout` (today `Lower/Layout.h`), shared by `lower`, `ownership`,
`stack`, `eval`:

- `layout::Representation = std::variant<Nothing, Pointer, BigWord,
  Unboxed{SumLayout const&}, Scalar{Type}>`, from one
  `representation(Type)`. Today the same isa-chain is written four times:
  `Layouts::components` (`Layout.cc:99-112`), `Layouts::counted`
  (`Layout.cc:114-129`), `ownership::Counting::counted`
  (`Counting.cc:9-38`), and `Reifier::value` (`Reify.cc:59-115`); a fifth
  partial copy is `Runtime::constant` (`Runtime.cc:295-306`).
- `layout::Component{Type type; Counting counting}` with
  `Counting = std::variant<Counted, Plain>`: today the parallel
  `SmallVector<Type>` + `SmallVector<bool>` pairs.

---

## 1. `include/idr` and `lib/Support`

| File | Lines | Zone | Conversions |
|---|---|---|---|
| `include/idr/Idr.h` | 199 | G (resources, traits) / S (`known_non_zero`, `quantity_of`, `unrestricted`, `through_linear`, `read_once`, the lookups) | **Resources** (`CrashResource`… 30-52) inherit MLIR's `Resource::Base`: glue; `getName() const final` gains `noexcept`. **`CallsRuntime::getHelper`** (61-78): function-local `static const std::string` → a `constexpr` name computed from `getOperationName()` (`constexpr std::string` works, `snip/constexpr_string.cc`), stored as a `static constexpr` array. **`MayCrash<bool Allocates>`** (93-121): bool selector → `enum class Allocation { None, Result }`. **null-as-absence**: `getSumName` → `std::optional<FlatSymbolRefAttr>`; `lookupData` → `std::optional<DataOp>`; both `lookupCtor` → `std::optional<CtorOp>`. `Quantity` stays an enum (compared, not switched to select); `quantity_of` is itself an isa-chain (`Dialect.cc:138-142`) → `classify<ErasedType, LinType, WorldType>`. Blockers: FT 2 |
| `include/idr/Passes.h` | 14 | S (`passes`) | `simplifyRound(unsigned, unsigned)`: the second parameter is unused (`Simplify.cc:207`) → drop it; one `Options` aggregate |
| `include/idr/Target.h` | 19 | S (`target`) | mechanical |
| `lib/Support/Actions.h` | 59 | G | Three identical `ActionImpl` structs (20-42): glue by nature (MLIR base, TypeID macro). **`perform<A>(Operation*, function_ref<void()>) -> bool`** (46-57) → `perform<A>(Operation&, std::invocable auto&&) noexcept -> Performed` with `enum class Performed { Ran, Skipped }`. Blockers: the lambda to `executeAction` takes `function_ref` (fine) |
| `lib/Support/EnableStatistics.h` | 10 | G | stays: `PIN(llvm-force-enable-stats)` force-include |
| `lib/Support/PatternCounts.{h,cc}` | 31+35 | G | inherits `RewriterBase::Listener`; `nameOf` (`.cc:13-18`) returns `(any op)` for a null root: `std::optional<OperationName>` already, fine |
| `lib/Support/PipelineStatistics.{h,cc}` | 57+38 | G | `std::vector<std::unique_ptr<Entry>>` + `StringMap<Entry*>` (`.h:53-54`) for stable addresses → `std::deque<Entry>` + `StringMap<std::size_t>`; the non-copying copy constructor (`.h:26`) is forced (the pass manager clones passes): keep with a doc block. Sources stay `Pass::Statistic const*` (MLIR hands them out) |
| `lib/Registration.cc` | 43 | G | `static const StringRef steps[]` (16-30): function-local static C array → namespace-scope `constexpr std::array<std::string_view, 9>`. `llvm::report_fatal_error` (41) → `support::invariant`. The lambda to `PassPipelineRegistration` (a `std::function`) takes `noexcept` |

## 2. `facts` (today `lib/Facts`, module `idr.facts`, 25 files)

cpp-starter's shape (`AGENTS.md:419-446`): one module `facts`, primary
interface `facts.cc` (only `export import`s), partitions of 50-300 lines
with their definitions: `facts:effects`, `facts:functions`,
`facts:closures`, `facts:moves`, `facts:evaluation`, `facts:infer`. The 17
one-function implementation units fold into their partitions: 7 files where
there are 25.

| File (today) | Lines | Conversions |
|---|---|---|
| `Facts.cppm` | 13 | → `src/facts/facts.cc`, undotted name |
| `Effects.cppm`, `Effects/Effects.cc` | 19+17 | struct of bools → the ODS `Effect` set (0.3); `all()`, `none()`, `operator|=` become the enum's own operators |
| `Functions.cppm` + 6 units | 38+106 | `of(FuncOp)` takes a possibly null function (`Of.cc:13`) → `of(std::optional<func::FuncOp>)`; `inherit`'s labels "a null label, one not known, may do anything" (`Functions.cppm:20-25`) → `std::span<Label const>` with `Label = std::variant<Known{func::FuncOp}, Unknown>`. `"idr.total"`, `"idr.effects"`, `"idr.library"` string literals (`Inherit.cc:16-18`, `IsLibrary.cc:9`, `Of.cc:15-16`, `Record.cc:15`) → ODS `discardableAttrs` helpers (`DialectBase.td:40`; section 12). `holdsWorld` (`MayHoldWorld.cc:11-22`) and `holdsClosure` (`MayHoldClosure.cc:11-24`) are one walk with two predicates → `any_field(Operation&, Type, std::predicate<Type> auto)` |
| `Closures.cppm` + 3 units | 26+114 | `closureLabel` returns a null `StringAttr` (`ClosureLabel.cc:12`) → `std::optional<StringAttr>`. `passed` (`Passed.cc:34-70`): an isa-chain over `ClosureOp`, `LinEnterOp`, `LinUseOp`, `ConOp`, constants → `classify` + a visitor struct whose alternatives return `Step = std::variant<Holds{Effects}, Follow{SmallVector<Value>}, Anything>` |
| `Moves.cppm` + 4 units | 35+79 | `only(Operation*, function_ref<bool(Effects const&)>)` (`Moves.cppm:33`, `Only.cc:46-51`) → template `only(Operation&, std::predicate<Effects const&> auto)`, defined in the partition. `own()` (`Only.cc:16-42`): isa-chain over `PerformsIO` trait, `func::CallOp`, `MayCrashOpInterface`, `MayLoopOp`, `ub::UnreachableOp`, recursive effects, `MemoryEffectOpInterface` → `classify` into `OpEffect = std::variant<Io, Call{func::CallOp}, MayCrash{...}, MayLoop, Unreachable, Nested, Declared{SmallVector<EffectInstance>}, Unknown>`. Blockers: FT 5 (walks) |
| `Evaluation.cppm`, `CanEvaluate.cc` | 21+59 | `Evaluation{callee, args, bool total}` → `total` is `Termination` (0.3). `canEvaluate` returns `std::optional<Evaluation>` whose `nullopt` has six causes (`CanEvaluate.cc:23-56`) → `std::expected<Evaluation, NotEvaluable>` with `NotEvaluable = std::variant<NotACall, OperandNotConstant, CalleeMissing, CalleePerformsIo, ...>`, so idr-eval's remarks can say why; the callee from `symbols.lookup` may be null (45) → `std::optional`. The `runs` predicate (15) takes a null function |
| `Infer.cppm`, `Infer/Infer.cc` | 31+106 | returns `SmallVector<pair<FuncOp, Effects>>` → `SmallVector<Inferred{func::FuncOp fn; Effects effects}>`. `local()`'s isa-chain (41-57) → `support::references` (0.3) plus a `MayCrash` test. The `worlds` cache `DenseMap<Type, bool>` (89-96) → `DenseMap<Type, Holds>` with `enum class Holds { World, Nothing }`. Blockers: FT 3 |
| `Pass.cc` | 24 | G: the `idr-effects` pass base, one call into `facts::infer` |

## 3. `layout` (today `Lower/Layout.{h,cc}`)

| File | Lines | Conversions |
|---|---|---|
| `Lower/Layout.h` | 125 | **tag + payload**: `CellKind` + `cellInfo(tag, objs, kind)` (19-23), where `tag` is a constructor tag, a closure label or an ASCII flag depending on the kind → `CellInfo = std::variant<BoxInfo{ctor_tag, objs}, ClosureInfo{label, objs}, StringInfo{Ascii}, BignumInfo>`, whose one `encode(CellInfo) -> std::expected<std::uint32_t, LayoutError>` checks every field against its bit width (16 bits of tag, 8 of objs: the packing bug review-external found). **null-as-absence**: `SumLayout::tag` is "null when the type has at most one constructor" (30) → `std::optional<IntegerType>`; `offset()` (37) follows. **parallel arrays**: `slots` + `counted` (31-32) → `SmallVector<layout::Component>` (0.3). `Cell::order` pairs → `struct Place{unsigned field, component;}`. `Layouts::components`/`counted` (87-90) → `representation(Type)` and `components(Type) -> SmallVector<Component>` (0.3). `labelId` returns 0 for an unknown label (`Layout.cc:52-54`, `DenseMap::lookup`) → `std::optional<LabelId>` at the lookup, `invariant` where the verifier guarantees it. `unique_ptr` members for stable references (116-122): keep (dynamic stable ownership, `AGENTS.md:752-753`) or `std::deque`; not shared |
| `Lower/Layout.cc` | 191 | `sum()` (56-97) dereferences `lookupSymbol<DataOp>` without a check → `invariant`. The slot-assignment loop (74-89) is an index loop over two vectors → one `find_if` over `Component`s. Blockers: FT 2 (`module.walk`, `getAttrDictionary().walk`) |

## 4. `ownership` (today `lib/Ownership`)

| File | Lines | Conversions |
|---|---|---|
| `Ownership.h` | 104 | `readFrom` returns null for any other value (58) → `std::optional<Value>`, or better `ReadFrom = std::variant<Field{FieldOp}, CaseArgument{MatchOp}, NotRead>`. `callee` returns null (75) → `std::optional<func::FuncOp>`. `Use` (71) stays an enum (compared). `insertResetReuse` returns `pair<unsigned, unsigned>` (87) → `ReuseCounts{resets, reuses}`; `insertCounts` returns `FailureOr<pair<...>>` (96) → `std::expected<CountStats{incs, decs}, support::Error>`. `stageAttr`/`ownedStage` string constants (31-34) → a typed stage attribute (mlir-idioms.md 3.1 argues for an op; the C++ side is the ODS helper either way) |
| `Counting.cc` | 102 | **isa-chain**: `Counting::counted` (9-38) → `layout::representation` (0.3); its own `datas`/`sums` caches then go. `useOf` (85-100): an isa list over our ops that decides consume vs borrow → an op interface method `OwnershipOpInterface::use_of(OpOperand&)` in ODS, so the fact sits on the op (mlir-idioms spirit); until then a `classify` + visitor. `usedAfter`, `isStatic`: null-walking loops (`for (; value; value = readFrom(value))`, 52) become loops over `ReadFrom` |
| `Borrow.cc` | 198 | **parallel arrays**: `owned: DenseMap<FuncOp, SmallVector<bool>>` (185) → `SmallVector<Param>` with `Param = std::variant<Borrowed, Owned>` (a two-point lattice). `bool fixed` (50) → `enum class Callers { Seen, Unseen }`. `func::FuncOp current` as mutable null state (187) → a parameter of `collect`. `bool changed` fixpoint flag → `ChangeResult`. `inTailPosition` (142-153) duplicates `stack::in_tail_position` (`Stack/Tail.cc:9-16`) with one extra condition → one function in `facts` or `stack`. `findCycles` → `support::references`. Blockers: FT 3 |
| `Counts.cc` | 290 | **tag + payload**: `enum class Class { Untracked, Static, Borrowed, Owned }` (34) switched in `plan` (141-159), where an owned *field* is a sub-case decided by `readFrom` again (152) → `Class = std::variant<Untracked, Static, Borrowed, Owned{Origin}>` with `Origin = std::variant<Defined, FieldOf{Value}>`. **null-as-case**: `Operation *def`/`after` "or at its start when null" (141, 161, 196, 208) → `Position = std::variant<BlockStart, After{Operation&}>`. `bool keep` parameter (208) → `enum class AtEnd { Consumed, Kept }`. `usersIn` duplicates `ResetReuse.cc:86-96` → one function. `usesBy` returns a pair (186) → `UseCount{consumes, borrows}`. `FailureOr<pair>` (44) → `std::expected<CountStats, support::Error>`. Blockers: FT 4 |
| `Ops.cc` | 89 | G: 8 TableGen hooks. `ctorOf` returns null after emitting (12-29) → `std::expected<CtorOp, Emitted>` (where `Emitted` records that the diagnostic is out). `TakeOp::getToken` returns a null `Value` for a sum (68-70): an ODS `extraClassDeclaration` method → `std::optional<Value>`, declared `noexcept` in the `.td`. The `idr.stage == "owned"` string test (31-38) → typed attribute |
| `Rc.cc` | 54 | G: pass base; options `reuse`, `borrow` are TableGen pass options (bools forced by the option API); lift them once into `RcOptions{Reuse, Borrow}` enums for the module call |
| `ResetReuse.cc` | 184 | **null-as-case**: `Operation *after` "from its start when null" (86, 100) → `Position` (above). `fits(size, block, at, SmallVectorImpl<ConOp>& found) -> bool` (120-140): bool + out-parameter → `std::optional<SmallVector<ConOp>>` or a `SmallVector` that is empty when nothing fits. `reuseAt(..., function_ref<Value()> token)` (155) → `std::invocable auto`. `"idr.stack"` string (74, 123) → ODS helper. `pair<unsigned, unsigned>` → `ReuseCounts`. Blockers: FT 2 |
| `Take.cc` | 25 | mechanical |
| `Verify.cc` | 421 | **null-as-case**, the worst of the tree: `held: DenseMap<Value,int>` + `owners: DenseMap<Value,Value>` where a null owner means "borrowed parameter" (36-38, 94-99) → one `DenseMap<Value, Holding>` with `Holding = std::variant<Owned{int references}, BorrowedFrom{Value owner}, BorrowedParameter>`. `define(value, refs, Value owner = Value(), bool borrowed = false)` (56-60): default arguments and a bool → three functions, or `define(Value, Holding)`. **bool result as case**: `FailureOr<bool> walk` "whether its end is reached" (147) → `std::expected<Reach, Violation>` with `enum class Reach { End, Unreachable }`. `slotOwner` returns null for an owned slot (228-233), `loops` stores null entries (394) → `SmallVector<Slot>` with `Slot = std::variant<OwnedSlot, BorrowedSlot{Value owner}>`. `slotType(slot, value, bool after)` (351) → `enum class LoopRegion { Before, After }`. **isa-chain**: `walkRegions` (253-261) → `classify<MatchOp, MatchLitOp, scf::WhileOp>`. The `alive` loop bound 1024 (88) is a magic number: follow `Holding` until `Owned`/`BorrowedParameter`, the chain is finite by construction. Errors: `fail(op, value, text)` emits at once → `Violation{Operation&, Value, ViolationKind}` rendered once, so tests can name the kind. `function_ref<Layouts&()>` (27) → a lazily filled `std::optional<Layouts>` member |

## 5. `stack` (today `lib/Stack`)

| File | Lines | Conversions |
|---|---|---|
| `Cell.h`, `Cell.cc` | 23+33 | `cell()` returns a null `Value` when unmarked or in JIT mode (`.h:19`, `.cc:13-14`) → `std::optional<Value>`, and the JIT test goes into `lower::Mode` (section 7) |
| `Escape.h` | 95 | **null-as-case**: `using Flow = std::optional<SmallVector<Node, 2>>`, nullopt = "escapes" (79) → `Flow = std::variant<Escapes, Forwards{SmallVector<Node, 2>}>` (a read is `Forwards{}`). `Node = std::pair<Value, Mode>` (64) → `struct Node{Value value; Mode mode;}` with its `DenseMapInfo`. `Frame::repeating` empty for "the function's parameters" (72-75) → `Frame = std::variant<ParameterSummary{FuncOp}, ConFrame{FuncOp, span<Operation* const>}>` |
| `Escape.cc` | 201 | `repeating()` returns `std::optional<SmallVector<Operation*>>` where nullopt means "counts nowhere: escapes" (36-52) → `std::variant<Counted{SmallVector<...>}, Uncounted>`. `flow`'s `TypeSwitch` (169-198) → `support::type_switch` with a visitor struct. `constexpr std::nullopt_t lost` (19) goes with `Flow`. Blockers: FT 8 |
| `Pass.cc` | 67 | G: pass base. The `"idr.stack"` mark → ODS helper; the budget constants stay `constexpr` |
| `Recursion.{h,cc}` | 18+59 | `DenseSet<Operation*>` → `DenseSet<func::FuncOp>`; the call walk → `support::references`. Blockers: FT 1 |
| `Tail.{h,cc}` | 14+18 | one `in_tail_position` for the whole tree (with `Borrow.cc:142-153`) |

## 6. `specialize` (today `lib/Specialize`)

| File | Lines | Conversions |
|---|---|---|
| `BindingTimes.h` | 61 | `BindingTime` enum switched in `nameOf` (`.cc:174-188`) and `count` (`Specialize.cc:139-156`) → `BindingTime = std::variant<Free, Fixed, Decreasing, Bounded, Other>`, each alternative with a `static constexpr std::string_view name` (no string table), statistics indexed by `index()`. `of()` returns `std::optional` for "a function made after the analysis" (52-53): fine as absence; `ReportBindingTimes` dereferences it unchecked (`Pass.cc:88`) → `invariant` or skip |
| `BindingTimes.cc` | 225 | **tag + payload**: `Abstract{Kind kind; unsigned param}`, `param` meaningless for `Top` (46-56) → `std::variant<Top, Same{unsigned param}, Smaller{unsigned param}>`. **parallel arrays of bools**: `same`, `smaller`, `other` (167) → `SmallVector<BindingTime>` starting at a bottom and joined per observation (the result computation at 76-83 becomes the lattice join). **`reinterpret_cast` to build a string key** (91-97) → a hashable `VisitKey{Operation*, SmallVector<Abstract>}` with `DenseMapInfo`. The `auto &self` recursive lambda (104-131) → deducing `this`. `forEachReference(..., function_ref)` (25-43) → `support::references`. Blockers: FT 4 |
| `Clones.h` | 82 | `lookup`/`specialization` return `Clone const*` (39, 43) → `std::optional<Clone const&>`. The key is `Attribute` that is a `SpecKeyAttr`, `KeyApplyAttr` or `KeyApplyFieldAttr` (tested by `isa` in `Clones.cc:49,76` and `Dialect.cc:474`) → `CloneKey = std::variant<SpecKeyAttr, KeyApplyAttr, KeyApplyFieldAttr>`. `copy(..., StringRef kind, ...)` string-as-enum (54; values `"spec"`, `"raise"`, `Clones.cc:18`) → `enum class CloneKind { Spec, Raise }`. `parameterAttrs(..., DictionaryAttr from = {})` default argument (79-80) → two functions. `copy` returns `FailureOr` after emitting the budget error (51-54) → `std::expected<func::FuncOp, support::Error>` with `Budget{ClonesPerOwner, 1024}` |
| `Clones.cc` | 128 | `parseName` returns `optional<pair<StringRef, unsigned>>` (12-22) → `optional<CloneName{owner, number, CloneKind}>`. `assert` (105) → `invariant`. `"idr.origin"` (97) → ODS helper |
| `Pattern.h` | 111 | `Pattern` is already the tree's one variant (`std::variant<Hole, Constant, Con, Closure, Linear>`, 52). `Linear{std::vector<Pattern> value; // Exactly one}` (46-49) → `Linear{support::Box<Pattern> value}`. `isHole()` → `std::holds_alternative`. Out-parameters: `shapeOf(Value, SmallVectorImpl<Value>& leaves)` (67), `renumber(Pattern&, unsigned& next)` (89), `labels(Pattern const&, SmallVectorImpl<...>& out)` (109) → return values (`Shape{Pattern, leaves}`, `Renumbered{Pattern, next}`, `SmallVector<FlatSymbolRefAttr>`) |
| `Pattern.cc` | 261 | The overload set `template <typename... Cases> struct Match : Cases...` (15-17), which cpp-starter forbids by name (`AGENTS.md:1851-1854`), is used by six `std::visit`s (144-258) → one visitor struct per function (`HasStructure`, `Renumber`, `SizeOf`, `KeyOf`, `Rebuild`, `Labels`), each `noexcept`, visited with the member `pattern.node.visit(...)`. `bool constant(Value, Attribute& out)` (21-24) → `std::optional<Attribute>`. **isa-chains**: `constantSize` (31-52), `keyOfConstant` (56-67), `shapeOp` (108-111) → `classify<ConAttr, ClosureAttr, BigAttr>` / `classify<ConOp, ClosureOp, LinEnterOp>`. Blockers: FT 2 |
| `Specializer.h` | 76 | **null-as-case ×3** in `Consumer` (35-43): `enter`/`exit` null together ("only moves the result into a linear position and out again ... or null"), `field` null ("the result itself is applied"), `use` null ("what is applied is not linear") → `Consumer{Passage passage; Target target; Applied applied; ApplyOp apply;}` with `Passage = std::variant<Direct, ThroughLinear{LinEnterOp, LinUseOp}>`, `Target = std::variant<Result, Field{FieldOp}>`, `Applied = std::variant<Plain, LinearUse{LinUseOp}>`. `raise` returns `FailureOr<func::CallOp>` whose success may be a null call ("or null", 56-58) → `std::expected<Raised, support::Error>` with `Raised = std::variant<Replaced{func::CallOp}, NotRaised>` |
| `Raise.cc` | 278 | `keyOf(Consumer, ...)` branches on `c.field` (47-50) → a visitor over `Target`. `labelOf` returns a null `FlatSymbolRefAttr` "when not known" (56-87), and `labels` collects nulls (112-151) that `facts::inherit` reads as "may do anything" (216-226) → `facts::Label` (section 2). `(void)matchPattern(...)` (63, 72) → `std::ignore =`. The `retyped` dispatch `isa<MatchOp>(match) ? ... : ...` (128-129) → `classify<MatchOp, MatchLitOp>`. The lambda given to `perform<RaiseAction>` writes `result` by reference (242-274) → `perform` returns what the transform returns. Blockers: FT 5 |
| `Specialize.cc` | 260 | `specializesOn(BindingTime, bool intoClone, Type)` (55-57) → `enum class Chain { Fresh, InClone }`, derived from `Clone const*` (166) which becomes `std::optional<Clone const&>`. `bool unrolls` (183) → a property of `BindingTime`'s alternative. `count(Statistics&, BindingTime)` switch (139-156) → statistics indexed by the variant. `bool any` (169) fine as a local. `(void)clone.insertArguments(...)` (123, 136) → check the `LogicalResult` (it can fail) and make it `support::invariant`. `perform` lambda writing `result` (215-257) → as above. Blockers: FT 2 |
| `Run.cc` | 45 | `*raised ? *raised : call` (25) → visit `Raised`. `(void)applyPatternsGreedily` (42) → `std::ignore =` on a `LogicalResult` is allowed, but the non-convergence deserves a remark, as `idr-canonicalize` gives one |
| `Pass.cc` | 48 | G: two pass bases; `Statistics` → statistics fields |

## 7. `lower` (today `lib/Lower`, minus `Layout`)

| File | Lines | Conversions |
|---|---|---|
| `Runtime.h` | 118 | **bool selector**: `Runtime(..., bool jitMode)`, `isJit()` (16-20), branched on in `allocate`, `storeHeader`, `crash`, `mayLoop`, `inc`, `dec` (`Runtime.cc:91,102,113,125,175,180`) and by callers (`Counting.cc:31,49`, `Cell.cc:13`) → `Mode = std::variant<Executable, Jit>`, and each method a visit, so a new mode cannot miss a method. **null-as-absence**: `call(..., Type result, ...)` "or nothing when it is null" (22-25) → two functions, `call` and `call_void`, or `std::optional<Type>`. Runtime functions by string name (`"idris_rt_crash"`… across `Runtime.cc`, `Counting.cc`, `Patterns.cc`) and the `noreturn` test by string comparison (`Runtime.cc:69`) → a typed table: `RuntimeFn = std::variant<Crash, EvalCrash, Cell, ArenaAlloc, Inc, Dec, ...>` or an `enum class` indexing a `constexpr std::array<RuntimeDecl>` of name, signature and attributes. `inc`/`dec` take `ArrayRef<bool> counted` (57-60) → `span<Component const>` (0.3). `staticCell`/`global` take `function_ref` (84-98) → `std::invocable<OpBuilder&>` templates |
| `Runtime.cc` | 410 | `describe(Location)` isa-chain over MLIR locations (18-32) → `classify<FileLineColLoc, FusedLoc, NameLoc, CallSiteLoc>`. `constant()` (295-356): an isa-chain over attributes and types (the fifth copy of the representation chain) → `representation(type)` visited, attributes through `classify<StringAttr, BigAttr, IntegerAttr, FloatAttr, ConAttr, ClosureAttr>`. `reinterpret_cast<idris_rt_bignum const*>(word)` (265) → the runtime exports `idris_rt_big_limbs(word, out)`; the cast stays in `runtime/`. `layout.tag ? ... : ...` → `optional` |
| `Pass.cc` | 170 | G: pass base, whose `runOnOperation` becomes one call. **bool selector + null-as-case**: `func::FuncOp root; bool io = false;` meaningful only when `!jit` (72-82) → `Mode = std::variant<Executable{func::FuncOp root; RootKind kind}, Jit>` with `enum class RootKind { Pure, Io }`; `emitMain(..., bool io, ...)` (34) takes `Executable`. `findRoot` returns `FailureOr` after emitting (23-32) → `std::expected<func::FuncOp, support::Error>`. `checkNoClosures` (53-64) → `std::expected<void, support::Error>`. The attribute-stripping walks (146-164) → `support::walk`. Blockers: FT 5 (walks, `addConversion`) |
| `Patterns.h` | 52 | `IdrPattern<OpT>` (39-45): our template deriving MLIR's `OpConversionPattern`, which 13 pattern classes derive again (the 20 `no-own-inheritance` findings of Lower) → every pattern is a `noexcept` function `lower_con(ConOp, Adaptor, ConversionPatternRewriter&, Context const&)`, registered through `support::FnConversion` with `Context{Layouts&, Runtime&}` bound. `buildBox(..., Value cell, ...)` where a null cell means "allocate" (49-50) → `std::optional<Value>` |
| `Patterns.cc` | 454 | 12 pattern classes → functions (above). **optional-bool as three cases**: `std::optional<bool> signedness(OpT)` (298-303) → `std::optional<Signedness>` with `enum class Signedness { Signed, Unsigned }` (or `Signedness = std::variant<Signed, Unsigned, NotApplicable>`). **exact-type allowlist as semantics**: `returnsWord<OpT> = llvm::is_one_of<OpT, ToIntOp, StrToIntOp, BigToIntOp>` (295-296), which cpp-starter forbids (`AGENTS.md:570-591`) → an ODS trait `Idr_ReturnsWord` on those ops and `OpT::template hasTrait<ReturnsWord>()`. `crashCondition` overloads (317-350) → an interface method on the ops that crash, or a `concept HasCrashCondition` (it is already selected by `requires`, 372). `LowerCompare`'s switch on the ODS `CmpPredicate` (405-421) → a `constexpr` mapping table (ODS enum, lifted once). `LowerDivision` uses `op.getIsSigned()` twice (221) → `Signedness`. `layout.tag` null tests (62, 89) → `optional` |
| `Closures.cc` | 73 | 2 pattern classes → functions |
| `Counting.cc` | 146 | 5 pattern classes → functions; `runtime.isJit()` branches (31, 49) → `Mode`. `SmallVector<bool> counted` (116-118) → `Component`s |
| `Matches.cc` | 148 | **isa dispatch after collection**: `lowerMatches` collects `Operation*` then `dyn_cast`/`cast` (133-146) → `SmallVector<std::variant<MatchOp, MatchLitOp>>` and a visitor. `Region *fallback` "or null" (57-59) → `std::optional<Region&>`. `lowerMatchLit`'s `integer || cases == 0` and then `isa<StrType>` (82-115): one classification used twice → `Keys = std::variant<IntegerKeys{IntegerType}, NoKeys, StringKeys, BigKeys>`. `scf::IfOp first, previous` null as "not yet" (106-126) → `std::optional<scf::IfOp>` |
| `Predecessors.cc` | 21 | mechanical; FT 1 |
| `Target.cc` | 29 | mechanical (`llvm::TargetOptions` aggregate) |

## 8. `passes` (today `lib/Passes`)

| File | Lines | Conversions |
|---|---|---|
| `Scc.h` | 61 | `stronglyConnected(ArrayRef<Node>, function_ref<SmallVector<Node>(Node)>)` → `template <class Node, std::invocable<Node> F> requires std::ranges::range<std::invoke_result_t<F, Node>>`, with a `concept GraphNode` (hashable by `DenseMapInfo`, equality). The `auto &self` lambda (30) → deducing `this` |
| `Defunctionalize.cc` | 1139 | **tag + payload**: `Labels{bool unknown; SmallVector<StringAttr> names}` (75-115), with `unknown` the top → `Labels = std::variant<Unknown, Known{SmallVector<StringAttr> sorted}>`; `join`, `mayHold`, `print`, `==` become visitors. **null-as-case ×2**: `using Key = std::pair<idr::FnType, ArrayAttr>`, where a null `FnType` means "holds no closure" and a null `ArrayAttr` means "labels unknown" (409-419) → `Key = std::variant<NoClosure, Closure{FnType type; KnownLabels labels}>` with `KnownLabels = std::variant<Unknown, Known{ArrayAttr}>`; `isEmpty`, `within`, `unknown`, `argument`, `result`, `sinkOf` returning `{}`/`Key()` (411-538) become alternatives. `DenseMap<Key, ...>` then needs `DenseMapInfoVariant.h` (tested; a key is 16 bytes where it was 16 already, a pair). `dataName` (154-160) duplicates `getSumName` and returns null → `getSumName`'s `optional`. `Module::ctor`, `fieldType` return null (178-190) → `std::optional`. `closuresIn(..., function_ref)` (194-209) → constrained template. `assert` (964) → `invariant`. `Sink{Operation *user}` → `Operation&` borrow in an ephemeral product. Banners (`//===---===//`, 67-69 and others) go. Glue: `LabelLattice`, `FieldAnchor`, `FieldLabels`, `LabelAnalysis` derive MLIR's dataflow bases (117-400) → `foreign/idr/defunctionalize/`, each a thin shell over module functions (`Labels` and its operations are module code). Blockers: FT 5 |
| `LoopBreakers.cc` | 91 | `choose` (37-50) keeps three nullable accumulators (`newest`, `first`, `firstOwn`) → one `std::ranges::min(cycle, {}, priority)` with `priority(fn) = std::tuple{Rank, order}` and `enum class Rank { Clone, Own, Library }` (a variant if a rank gains data). `bool marked`, `again` → `ChangeResult`. `refers` → `support::references` |
| `Prune.cc` | 138 | `empty(Block&)` dispatches on the parent op (58-66) → `classify<func::FuncOp>(parent)` (function blocks return poison, the others end unreachable). `live` nullable pointer (124) → `std::optional`. G: pass base |
| `Simplify.cc` | 223 | **`reinterpret_cast` of a pointer's bytes** for hashing (139-144) → `std::bit_cast<std::array<std::uint8_t, sizeof(void*)>>(ptr)` (tested, `snip/clopt.cc`). `parsePassPipeline(step, pm, llvm::errs())` (57) → `std::expected<void, support::Error>`. The budget error text (97-99) → `support::Error{Rejected{Budget{SimplifyRounds, maxRounds}}}`. `simplifyRound`'s unused second parameter (207) goes. G: pass base (`initialize`, `getDependentDialects` are overrides: `noexcept` allowed) |
| `TailLoops.cc` | 183 | `flag(Location, bool)` (77-79) → `enum class Continue { Loop, Exit }`. `payload` (84-105) classifies a block's tail as a self call, a tail match or an exit with a nullable `prev` → `Tail = std::variant<SelfCall{func::CallOp}, TailMatch{Operation&}, Exit>`. `Loop` holds `OpBuilder&` (65-69): an ephemeral product (allowed, `AGENTS.md:807-809`). `std::make_unique<Block>()` then `release()` (141, 162): MLIR takes ownership of the raw pointer; forced by `Region::push_back(Block*)` |

## 9. `eval` (today `lib/Eval`)

| File | Lines | Zone | Conversions |
|---|---|---|---|
| `Child.h` | 65 | S (types) | **tag + payload**: `Run{results; Status status; std::string message}`, where `message` means something for `Crashed` and `Failed` only (28-46) → `Run{SmallVector<Result> results; Outcome outcome;}` with `Outcome = std::variant<Done, Crashed{std::string report}, Exhausted{Exhaustion}, OverBudget, Failed{ChildFailure}>`, `Exhaustion = std::variant<Refused, Killed>`, `ChildFailure = std::variant<NoPipe{int errno_value}, NoFork{int errno_value}, ExitStatus{int}, Signal{int}, Truncated>`: the message is rendered from the alternative, never stored. **parallel arrays**: `runInChild(entries, words, budgets, first, reify)` (60-63) → `span<Call const>` with `Call{Jit::Entry entry; std::size_t words; Budget budget;}`; `reify` `function_ref` → `std::invocable<std::size_t, span<std::uint64_t const>>` |
| `Child.cc` | 243 | U | Fork, mmap, signals, pthreads: quarantine. Mutable globals `guardLow`/`guardHigh` (35-36) and the function-local `static char alternate[1 << 16]` (92) are what a signal handler can reach: record with `/* SAFETY: */` and `PIN(signal-handler-state)`; the alternate stack moves into the reserved mapping (`Stack`). Raw fds (180-205, closed by hand on each path) → cpp-starter's `Fd` RAII class (`unsafe/net.internal.h:83-122`). `reserve()` (38-49) duplicates `idris-mlir-cc.cc:549-570` → one `unsafe` `reserve_stack(Limits) -> std::expected<ReservedStack, int>`. `parse` returns partial results on malformed input (150-171) → `std::expected<SmallVector<Result>, Truncated>`. `char buffer[1 << 16]` (138) → `std::array` |
| `Jit.h`, `Jit.cc` | 35+138 | U | `static std::unique_ptr<Jit> compile(..., std::string &error)` (`Jit.h:25-26`): error string out-parameter plus null → `static auto compile(...) -> std::expected<Jit, JitError>`, `Jit` movable, `JitError = std::variant<NoHost{std::string}, NoMachine{std::string}, Translation, Define{std::string}, Lookup{std::string}>` (the eight exit paths, `.cc:81-134`). `new Jit` (112) goes with it. The `IDRIS_RT_BIND` macro table (32-71) stays quarantine code (addresses of C symbols), `/* SAFETY: */` |
| `Reify.h`, `Reify.cc` | 27+117 | U | Reads JIT memory through `reinterpret_cast` (`Reify.cc:24-26`): quarantine. `value(Type, ArrayRef<uint64_t>& words)` in-out parameter (`Reify.h:16`) → a `WordCursor` passed by reference, or a return of `{Attribute, rest}`. `withTag` returns null (`Reify.cc:28-33`) → `std::optional<CtorOp>`. The type isa-chain (`Reify.cc:59-115`) → `layout::representation` (0.3). `constructor(..., function_ref)` → constrained template |
| `Eval.cc` | 335 | S + G | **bool as case**: `Outcome{results; bool stays}` (72-76) → `Outcome = std::variant<Evaluated{SmallVector<Attribute>}, Stays{StayReason}>`. `Call{Operation *op; ...; const Meter *meter}` pointing at one of two constants (60-83) → `Termination` (0.3) with `meter(Termination) -> Meter`. `Key = std::pair<Attribute, Attribute>` (48) → `CallKey{FlatSymbolRefAttr callee; ArrayAttr args}`. Parallel `words`/`budgets`/`entries` (230-254) → `SmallVector<Call>` (Child.h). `internal(i, why)` (207-210) → `std::expected<void, support::Error>` through the function. `parseAttribute` returns null (283) → checked into `Internal`. The `switch (run.status)` (297-330) → a visitor over `Outcome`. `IdrLowerOptions{/*jit=*/true}` → `Mode`. G: the pass base and `getDependentDialects`. Blockers: FT 3 |

## 10. `expect`, `inline`, `canonicalize`

| File | Lines | Conversions |
|---|---|---|
| `Expect/Expect.h`, `Pass.cc` | 66+76 | `using Check = LogicalResult (*)(ModuleOp, StringRef)` (24) is a plain function pointer: fine (no `std::function_ref` yet). `lookup` via `StringSwitch` with `nullptr` default (`Pass.cc:38-52`) → `constexpr std::array<Property, 10>{{"no-closures", no_closures}, ...}` and `std::ranges::find` → `std::optional<Property const&>`. `named` returns a null function after the error (`Pass.cc:27-32`) → `std::expected<func::FuncOp, Failed>`. `where` (`Pass.cc:22-25`) → `std::optional<func::FuncOp>` of the op's function. `bool failed` accumulation → `std::ranges::fold_left` over results. G: pass base |
| `Expect/Allocation.cc`, `Breakers.cc`, `Clones.cc`, `Closures.cc`, `Counting.cc`, `Facts.cc`, `Folds.cc`, `Output.cc` | 84+44+43+28+49+48+22+25 | each property returns `std::expected<void, Failures>` where `Failures` is the list of places it failed, rendered by the pass; FT 1-2 each (walks). `Facts.cc` parses `expect.facts = "..."` marks: the question names → `enum class Question { Drop, Move, Delay, Evaluate }` |
| `Expect/Quantities.cc` | 102 | `position` returns `optional<pair<unsigned, unsigned>>` → `optional<FilePosition{line, column}>`. `spelled(Quantity)` switch with fallback return (32-43) → the switch without the unreachable fallback (`-Wcovered-switch-default`). `std::map` with a pair key → `llvm::DenseMap`/`std::flat_map` |
| `Inline/Inline.cc` | 158 | `decide`'s walk (`Inline.cc:56-83`) → `support::references`. **A discarded failure**: `(void)parsePassPipeline(pipeline, pm)` in the inliner's default pipeline (`Inline.cc:127-130`) ignores a bad `default-pipeline` option at run time; `getDependentDialects` (145-148) parses it with `succeeded()` and moves on → parse once in `initialize`, fail the pass on error. `static_cast<Inline &>(pass)` (152-154): a static downcast forced by `Inliner`'s `runPipelineHelper` function-pointer API: glue, `PIN(mlir-cxx-api)`. `bool leaf` (55, 107) → locals, fine. `std::function` default pipeline (127) forced by `InlinerConfig::setDefaultPipeline`. G: pass base |
| `Canonicalize/Pass.cc` | 120 | `std::shared_ptr<const FrozenRewritePatternSet>` (85, 117) → a `FrozenRewritePatternSet` member: it is a copyable handle over MLIR's own `shared_ptr` (`FrozenRewritePatternSet.h:34-38,95`). `regionLevel` via `StringSwitch` (38-44): fine (`optional` of an MLIR enum). G: pass base |
| `Dialect/Canonicalize/Calls.cc`, `Matches.cc`, `Merge.cc`, `Sink.cc`, `CaseOfCase.cc`, `Strings.cc` | 31+69+68+121+122+37 | six `OpRewritePattern` classes (`RemoveUnusedCall`, `DropEmptyStringCase`, `MergeIdenticalRegions<Match>`, `SinkIntoRegions<Match>`, `SinkConsumer<Match>`, `PutStrOfEmpty`) → `noexcept` functions registered with `results.add(fn)` (`PatternMatch.h:910-929`; the debug names set in constructors, `CaseOfCase.cc:22-23`, `Sink.cc:85-86`, go through the `add` overload that takes one). `candidate` returns a nullable `Operation*` (`CaseOfCase.cc:43-50`) → `std::optional<Operation&>`. `Operation *value = nullptr` search (`Sink.cc:95-98`) → `std::ranges::find_if` → optional. `getCanonicalizationPatterns` bodies are TableGen hooks (TG 7 in this directory) |
| `Dialect/Canonicalize/Matches.h`, `Meet.cc`, `Apply.cc`, `Field.cc` | 44+32+77+29 | `rebuildMatch(..., ArrayRef<Region*>)` → `span<std::reference_wrapper<Region>>` is heavier than MLIR's own style; keep `Region*` in this template (MLIR hands regions out by pointer) and forbid it in signatures of non-template functions. `feeds` (`Meet.cc`) is an isa list over our ops → an ODS trait `Idr_Feedable` that `canon::feeds` asks. `ApplyOp::canonicalize` (`Apply.cc:43-74`): TableGen hook; its `closureValue` dispatch on `ClosureOp` vs constant → `classify` |

## 11. Glue: `Dialect/`, `Fold/`

| File | Lines | Conversions |
|---|---|---|
| `Dialect/Dialect.cc` | 500 | TG 8 (+ `FnType::parse`/`print`, `LinType::verify`, the inliner interface). **`std::function` for a recursive lambda** (`verifyProgram`, 280-301) → a deducing-`this` lambda. `verifyOperationAttribute` (428-480): an if-chain on attribute-name strings over the ten `idr.*` names → ODS `discardableAttrs` (section 12) and a `constexpr` table of `{name, verifier}`. `LinearUses::secondUse` returns a nullable `Operation*` (353-362) → `std::optional<Operation&>`. `quantity_of`, `unrestricted`, `through_linear`, `read_once`, `is_field_type`, the lookups (120-205): module code (`src/ir`), exported to everything. Blockers: FT 4 |
| `Dialect/Ops.cc` | 919 | TG 43. ODS `extraClassDeclaration` methods (`getCtors`, `getValueType`, `getFieldType`, `isBuildableWith`, `getTakenRegion`): declare `noexcept` in `IdrOps.td`. `getTakenRegion` returns a null `Region*` (616-627, 711-713) → `std::optional<Region&>` (ODS lets us declare it). `idrisDivMod(..., bool isSigned)` (96) → `Signedness`. `printMatch(..., function_ref<void(unsigned)>)` (486) → constrained template. The `DivisionOp` concept (114-120) exists already: the tree's one concept. `knownNonZero`/`knownFinite`/`knownNonEmpty` (20-50) → module code |
| `Fold/Fold.cc` | 366 | TG 32. `Scope` (24-58) owns runtime references in two vectors and releases them in its destructor: an RAII owner over raw C pointers; cpp-starter's form is one RAII value per reference (`Str`, `Big` with `noexcept` moves) collected in the scope, `/* SAFETY: */` at the C calls. `extended(IntegerAttr, bool isSigned)` (68) → `Signedness`. `template <typename Fn> strUnary(...)` unconstrained (102) → `std::invocable<Scope&, idris_rt_str const*>`. `using BigOp = idris_rt_big (*)(...)` fine. The `compared` switch on the ODS `CmpPredicate` (80-100) is shared with `Patterns.cc:405-421` → one `constexpr` table. Blockers: FT 11 (lambdas to `strUnary` are ours; the count comes from lambdas inside hooks) |

## 12. ODS changes the C++ needs

- **`discardableAttrs`** on `Idr_Dialect` (`DialectBase.td:40`; generator
  `mlir-tblgen/DialectGen.cpp:202-235`) for the ten attribute names written
  as string literals today: `idr.total` ×5, `idr.stack` ×5, `idr.origin`
  ×5, `idr.effects` ×3, `idr.library` ×2, `idr.hole` ×2, `idr.clone` ×2,
  `idr.stage`, `idr.program`, `idr.borrowed`. The generated
  `get<Name>AttrHelper()` gives typed `getAttr`/`setAttr`/`isAttrPresent`.
  mlir-idioms.md 3.1-3.2 argues several of these should not be discardable
  attributes at all; the C++ half is valid either way.
- **`noexcept` in `extraClassDeclaration`** for every method we declare
  there, and `std::optional<Region&>`/`std::optional<Value>` returns where
  they return null today.
- **Traits for the exact-type lists**: `Idr_ReturnsWord`
  (`Patterns.cc:295-296`), `Idr_Feedable` (`Meet.cc`), and an ownership
  interface for `useOf` (`Counting.cc:85-100`).

## 13. Tools

| File | Lines | Zone | Conversions |
|---|---|---|---|
| `tools/idris-mlir-cc.cc` | 602 | G (`main`, `cl::opt`) + S (`driver`) + U (large stack) | **13 mutable globals** `cl::opt`/`cl::list` (66-110) → `cl::opt` locals of `main` (an option registers when constructed, so locals built before `ParseCommandLineOptions` parse; tested, `snip/clopt.cc`) and one `Options` aggregate passed to `run(Options const&)`. **strings as enums**: `emitKind` compared to `"obj"`, `"asm"`, `"llvm"`, `"mlir"` (91, 345-348, 472, 513, 520) → `cl::opt<Emit>` with `cl::values` and `enum class Emit { Obj, Asm, Llvm, Mlir }` (LLVM's typed option; the same snippet parses `--emit=asm` into the enum). **bool pair as a closed set**: `checkOnly == !outputPath.empty()` (349-352) → `Output = std::variant<CheckOnly, File{std::string path}>` built once from the options. **bool + errs everywhere**: `dump`, `writeOutput`, `readMembers(..., std::vector<Member>&)` (out-parameter), `prepareMember`, `linkRuntime` (126-300; 12 functions print to `llvm::errs()` and return `false`) → `std::expected<T, ToolError>` with `ToolError = std::variant<Usage{...}, CannotWrite{path, std::error_code}, RuntimeArchive{...}, Internal{...}>` rendered once in `main`, and the pipeline composed with `and_then`. `Verdict{bool rejected}` set by matching `"unsupported ("` in the message text (325-329, 371-378) → the diagnostic's `support::Error` metadata (cpp-starter: "deciding behavior by matching an error's text is forbidden", `AGENTS.md:1408-1410`). `static_cast<llvm::raw_pwrite_stream *>(&os)` (523): a downcast → `writeOutput` hands the callback the `raw_pwrite_stream` it opened. `static_cast<const mlir::PassExecutionAction &>(action)` (433): forced by MLIR's action API (glue). `runOnLargeStack` (549-570) → `unsafe`, shared with `Eval/Child.cc` |
| `tools/idris-mlir-opt.cc`, `idris-mlir-reduce.cc` | 20+20 | G | `main` only; mechanical |

## 14. `runtime/`

The C ABI stays (`PIN(runtime-quarantine)`). Inside, the quarantine profile
and `noexcept`:

| File | Lines | Conversions |
|---|---|---|
| `idris_rt.h` | 361 | `IDRIS_RT_NOEXCEPT` next to `IDRIS_RT_NORETURN` (18-23) on every declaration. `idris_rt_info(tag, objs, kind)` (68-70) packs without range checks, the same bug as `lower::cellInfo`; the checked encoder lives in C++ (`layout::encode`), and the runtime's inline stays for C callers with a `static_assert`-able width table |
| `internal.h` | 68 | `extern bool arenaActive` (14): a mutable global (the runtime is process state by nature: `/* SAFETY: */`). `isInteger(char const*, size_t, size_t& digits) -> bool` (63) → `std::optional<std::size_t>` (`std::span<char const>` in). `newString(..., bool ascii)` (55) → `enum class Ascii { Yes, No }` |
| `eval.cc` | 81 | the meter: `bool metered` + three counters (25-28) → `Meter = std::variant<Unmetered, Metered{ticks, bytes, stack_floor}>`, one global of that type; `reinterpret_cast` of frame addresses (43, 52) stays (quarantine) |
| `rc.cc`, `alloc.cc`, `big.cc`, `strings.cc`, `double.cc`, `numbers.cc`, `io.cc`, `gmp.cc` | 159+74+278+227+169+59+215+44 | `noexcept` on every `extern "C"` definition and helper; the `idris_rt_big` word is a tagged union (odd = small, even = pointer, `big.cc:28-36`) that the C ABI fixes: inside C++, `classify(idris_rt_big) -> std::variant<Small{std::int64_t}, Large{idris_rt_bignum&}>` replaces the `isSmall` tests. `timesPowerOfFive(..., uint64_t& result) -> bool` (`double.cc:30`) → `std::optional<std::uint64_t>`. `bugprone-signed-bitwise` (40 findings) and `reinterpret_cast` (12) are quarantine-legitimate where they touch the ABI; each gets a `/* SAFETY: */` |

## 15. `foreign/idr/bench`

`bench/alloc/shapes.cc` (194 lines) chose the allocator (its README says
so) and selects it with `-DUSE_MI`/`-DUSE_SN`/`-DUSE_LIBC`;
`bench/gate/runtime.{h,cc}` (131+492) is the memory gate's prototype
runtime, superseded by `runtime/`. Neither is in the CMake graph, the
`Makefile` or `tests/` (`grep`), and both violate the mandate throughout
(project preprocessor configuration, `static thread_local`, no
`noexcept`). **Delete both**; git keeps them. If kept, they are the one
exception to the mandate and need a PIN, which no LLVM or MLIR fact would
justify.

## 16. Totals

- Files: 129 C++ files (118 in `foreign/idr`, 11 in `runtime`), 16.0k
  lines, of which 892 are `Mlir.cppm`; plus 3 bench files (section 15).
- Variants: 44 new variant types (listed in the rows above, by the shapes
  of 0.2), replacing tags, null cases, bool selectors, parallel arrays,
  isa-chains over our own closed sets (14 chains collapse into 6
  classifications) and two switched enums; the tree has 1 today
  (`Pattern`). About 27 null returns become `std::optional` (absence).
- `std::expected`: 15 paths (the tool's pipeline, `Jit::compile`,
  `canEvaluate`, the ownership verifier, `insertCounts`, `CloneTable::copy`,
  `raise`, `findRoot`, `checkNoClosures`, `layout::encode`, `Child.cc`'s
  `parse`, the Expect properties, `named`, `ctorOf`,
  `Simplify::buildRound`); the tree has 0 today. One adapter,
  `support::to_logical`, meets MLIR.
- Concepts and constrained templates: the 25 `function_ref` parameters of
  our own functions, `Scc.h`'s graph, `strUnary`, `only`, `any_field`, the
  walk wrappers; the tree has 1 concept today (`DivisionOp`).
- `noexcept` blockers that stay: about 100-120 hooks whose declaration
  TableGen writes (exempt by name; 43 in `Ops.cc`, 32 in `Fold.cc`, 8 in
  `Dialect.cc`, 8 in `Ownership/Ops.cc`, 7 in `Dialect/Canonicalize`, the
  rest in type and attribute hooks), and the lambdas inside `support`'s
  three wrappers. The tree has 0 `noexcept` today.
