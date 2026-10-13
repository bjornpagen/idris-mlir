# U02 — idr.func, idr.call, idr.return and the verifiers at the level the pass ran

Mandatory findings: F-pass-2 F-pass-3 F-pass-13 F-fact-1 F-fact-2

## Permitted outcome

1. **The three ops behind C1.2's ODS.** Every line of C++ `idr.func`,
   `idr.call` and `idr.return` need: the parser and printer of `idr.func`
   through `function_interface_impl`; `idr.func`'s verifier (the clone
   fact's shape) and region verifier; `idr.call`'s `verifySymbolUses`
   (callee, types, effects containment), `getEffects` (from its own
   `effects`, no lookup) and `consumesOperand` (from the operand's
   type); `idr.return`'s verifier. Every fact of a function or a call is
   read and written through the generated accessors (C2.2). Mandatory.
2. **The inliner interface, mirroring func's.** `IdrInlinerInterface`
   allows every call, region and op, and implements both
   `handleTerminator` forms for `idr.return`: values replaced for a
   single block, a `cf.br` for a block destination. What is inlined is
   what is inlined today (F-pass-13). Mandatory.
3. **The function verifier.** `FuncOp::verifyRegions` owns the rules of
   one function: every value of quantity one used once on every path,
   with one numbering of the body however many linear values it has
   (F-pass-3), and the owned stage's counting when the function's own
   grades put it in that stage (C4). It runs in parallel per function,
   opens no symbol table, and resolves each declaration it needs at most
   once per verify. Mandatory.
4. **The module verifier reduced.** The `idr.program` verifier keeps one
   root, every data type declared and of its kind, containment acyclic
   (`TypeGraph::containsItself`) and no array that can reach itself
   (`TypeGraph::knots`), from one `TypeGraph` it constructs. It walks no
   function for linearity, counts no reference, and polices no attribute
   dictionary (F-pass-2, F-fact-2). Mandatory.
5. **The dialect's attribute hooks.** `IdrDialect::verifyOperationAttribute`
   knows `idr.program` and `idr.stack` and refuses any other `idr.*`
   name; `verifyRegionArgAttribute` refuses every `idr.*` argument
   attribute. Attributes outside the `idr.` prefix are not policed
   (F-fact-2). Mandatory.
6. **The owned stage's vocabulary.** `INC/IR/Ownership.h` declares what
   the owned walk and the ownership passes share, defined once in
   `IDR/IR/Verify/Uses.cpp` (C2.0). Mandatory.
7. **The deletions.** `IDR/Verify`, `IDR/Dialect/Verify` and
   `IDR/Ownership/Verify.cppm` go, with the definition of the trait that
   polices every op's attribute dictionary. Mandatory.
8. **Consumer adaptations named, not written.** U01's
   `IdrDialect::initialize` calls `idr::addInlinerInterface`; U03's
   `idr-effects` writes `effects` on functions and calls with
   `setEffectsAttr`; U05's clone callback and U04's contify call
   `FuncOp::absorb`; U08, U11 and U15 include `INC/IR/Ownership.h`;
   U10's phase 0 reads the facts through the accessors. None of those
   files is written here.

## Owner / exclusive writes

- `IDR/IR/Func` (new): `Func.cpp`, `Call.cpp`, `Inliner.cpp`.
- `IDR/IR/Verify` (new): `Attributes.cpp`, `Program.cpp`, `Knots.cpp`,
  `Linearity.cpp`, `Owned.cpp`, `OwnedRegions.cpp`, `OwnedLoops.cpp`,
  `Uses.cpp`.
- `INC/IR/Func.h`, `INC/IR/Verify.h`, `INC/IR/Ownership.h` (new).
- `IDR/Verify` (deleted whole: `Cycles.cppm`, `Linearity.cppm`,
  `Program.cppm`, `Verify.cppm`, `CMakeLists.txt`).
- `IDR/Dialect/Verify` (deleted whole: `Attributes.cc`,
  `DiscardableAttrs.cc`).
- `IDR/Ownership/Verify.cppm` (deleted).

**Excluded:**

- `INC/IR/IdrOps.td`, `IDR/IR/CMakeLists.txt`, `IDR/Dialect/CMakeLists.txt`,
  `IDR/Ownership/CMakeLists.txt`: the coordinator's.
- `INC/IR/IdrDialect.h`, `INC/IR/Grades.h`, `INC/IR/Symbols.h`,
  `IDR/IR/Dialect.cpp`, `IDR/IR/Asm.cpp`: U01's. The dialect's
  `initialize`, `consumes` and `consumedEffects`, the grade helpers,
  `declarationOf` and the other symbol helpers, and
  `CallOp::getAsmResultNames` live there.
- `INC/IR/TypeGraph.h`, `IDR/IR/TypeGraph.cpp`, `INC/Support/Scc.h`,
  `IDR/Support/Scc.cpp`: U03's. The module verifier constructs the
  class.
- `INC/IR/Layout.h`, `IDR/IR/Layout`: U10's. The owned walk constructs
  `Layouts`.
- `IDR/Ownership/Checker.cppm`, `References.cppm`, `Loops.cppm`,
  `InOwnedStage.cppm`, `Counting.cppm`, `UseOf.cppm`, `IsStatic.cppm`,
  `ReadFrom.cppm`, `ReachesOnlyAtoms.cppm`, `ArrayLoop.cppm`: U08
  deletes them. Their logic is re-housed here (decisions 7 and 8); the
  files are not touched.
- `INC/Analysis/Ownership.h`: U08's (`usersIn`, `usedAfter`,
  `whereDies`, `followed`, `onlyReads`, `Counted`).
- `IDR/Facts/CallEffects.cc`, `IDR/Facts/Passed.cppm`, `IDR/Facts/Of.cppm`:
  U03 deletes them. The bits-to-resources mapping comes here; what the
  closures passed may do is `idr-effects`' to compute (U03).
- `IDR/Ops/Inliner.cppm`: U01 deletes it. `Inliner.cpp` takes its logic.
- `IDR/Dialect/Effects/Consumed.cc`: U01's (`consumes`).
- `IDR/Transforms/Inline`: U05's (the MLton rule, the clone callback,
  the pipeline runner and its marks).
- `IDR/Conversion`: U10's. Phase 0 is stated here as an interface only.
- `T/idr`: U21's. This lane fixes the messages U21 states.

## Read first

- `contracts.md` C0, C1.1, C1.2 (the Functions block, verbatim), C1.3,
  C2.0 (the rule for code called without a table; `INC/IR/Ownership.h`),
  C2.1 (`TypeGraph`, `Layouts` and its paragraph), C2.2, C2.5, C3.3, C4,
  C6.5, C7.1, C9.1, C10 (R01, R04, R05, R07, R08, R11, R13, R22, R29,
  R32, R35, R37, R44), C11.
- `findings.md` F-pass-2, F-pass-3, F-pass-13, F-fact-1, F-fact-2;
  F-state-1 and F-state-2 for why no lookup goes through a chain kept
  outside the IR.
- The module rules: `IDR/Verify/Program.cppm:16-21` (why they run before
  the ops inside are verified), `:23-39` (the root), `:41-66` (the
  attribute walk, deleted), `:68-116` (every type names a declaration of
  its kind), `:118-145` (the containment search, replaced by
  `containsItself`; the message at `:127-128`), `:146-150` (the calls to
  the cycle check and to linearity).
- Linearity: `IDR/Verify/Linearity.cppm:12-20` (which regions exclude
  each other), `:22-96` (`LinearUses`; the per-value numbering at
  `:40-50`), `:104-131` (the walk; the constant exemption at `:112`,
  the messages at `:115-117`).
- The knots: `IDR/Verify/Cycles.cppm:130-134` (`inSource`), `:136-149`
  (`describe`), `:155-215` (the report, which stays here; the graph at
  `:31-128` is U03's `TypeGraph`).
- The dialect's hooks: `IDR/Dialect/Verify/Attributes.cc:28-75` (the
  table; `idr.program` at `:36-44`, `idr.stack` at `:57-63`, the clone
  rule at `:66-74`), `:79-84`, `:86-96`;
  `IDR/Dialect/Verify/DiscardableAttrs.cc:21-38`.
- The owned stage: `IDR/Ownership/Verify.cppm:28-53`;
  `IDR/Ownership/InOwnedStage.cppm:11-29`;
  `IDR/Ownership/Checker.cppm:21-35`, `:40-60`, `:62-151` (the stack
  mark read by string at `:85`), `:155-167`, `:169-189` (the take's
  `ctor` read by string at `:173`, the lookups at `:176-177`, the
  layouts at `:180-183`), `:191-210`, `:218-244`, `:249-295`;
  `IDR/Ownership/References.cppm:16-154`; `IDR/Ownership/Loops.cppm:15-188`;
  `IDR/Ownership/Counting.cppm:14-41`; `IDR/Ownership/UseOf.cppm:11-24`;
  `IDR/Ownership/IsStatic.cppm:13-20`; `IDR/Ownership/ReadFrom.cppm:11-23`;
  `IDR/Ownership/ReachesOnlyAtoms.cppm:14-56` (the per-constant scan at
  `:27-29`); `IDR/Ownership/ArrayLoop.cppm:12-25`.
- The call: `IDR/Facts/CallEffects.cc:1-26` (why a call answers the
  interface), `:46-60` (the bits mapped to the resources, the results'
  allocation); `IDR/Facts/Of.cppm:14-24` (absent or external means
  anything); `IDR/Facts/Infer.cppm:38-43` (a call is judged by what it
  is passed too, which the call's `effects` now carries);
  `IDR/Dialect/Effects/Consumed.cc:19-28` (the per-call lookup that
  `consumesOperand` replaces).
- The clone fact: `IDR/Specialize/Clones.cppm:110-116` (the holes of a
  key, by a walk of its patterns); `INC/IdrOps.td:2124-2178` (the key
  attributes and `Idr_CloneAttr`).
- The inliner: `IDR/Ops/Inliner.cppm:13-27`,
  `IDR/Dialect/Dialect/Initialize.cc:114-120`, `IDR/Inline/Pass.cc:60-71`
  (how the inliner asks about legality and profitability);
  `PINS.md:285-310` (`inline-unreachable`: what the carried patch
  decides for a callee ending in `ub.unreachable`).
- The ODS today: `INC/IdrOps.td:20-84` (the dialect; its list of
  discardable attributes at `:64-78`), `:429-439` (`Idr_Effect`, a bit
  enum), `:453-464` (the policing trait and the op base; `:457-462` on
  what `verify` may read), `:499-526` (`Idr_Consumes`), `:544-571`
  (`idr.data`), `:785-793` (`idr.yield`'s parents).
- The stage's readers outside the verifier: `IDR/Narrow/Words.cppm:43`,
  `IDR/Ownership/Rc.cppm:72`.
- A body that ends without a return: `IDR/Tail/WhileDo.cppm:283-288`.
- Fixtures: `T/idr/verify/{module,data,cycle,linear,attributes,function}.mlir`,
  `T/idr/ownership/owned-stage.mlir`, `T/idr/canon/unused-call.mlir`.
- MLIR, snapshotted: `sources/code/mlir/include/mlir/Interfaces/FunctionInterfaces.td:24-53`
  (what the op must provide; `CallableOpInterface` is a base at
  `:24-26`), `:80-112` (`verifyBody`), `:148-163` (the shared
  `isExternal`), `:594` (the trait's verify);
  `sources/code/mlir/include/mlir/Interfaces/CallInterfaces.td:73-169`
  (`CallOpInterface`; `:149-159` on the table that spares an O(N) scan),
  `:173-203`; `sources/docs/mlir/docs/DefiningDialects/Assembly.md:139-164`
  (the default dialect, as `func.func` declares it);
  `sources/docs/mlir/docs/SymbolsAndSymbolTables.md:153-155`, `:179-182`;
  `sources/docs/mlir/docs/DefiningDialects/Operations.md:703-724` (the
  order of verification).
- MLIR, in the pinned tree (`.toolchain/llvm-project/mlir`):
  `include/mlir/Interfaces/FunctionImplementation.h` (`parseFunctionOp`,
  `printFunctionOp`); `lib/Dialect/Func/IR/FuncOps.cpp` (`FuncOp::parse`,
  `FuncOp::print`, `CallOp::verifySymbolUses`, `ReturnOp::verify`);
  `lib/Dialect/Func/Extensions/InlinerExtension.cpp` (both
  `handleTerminator` forms, which `Inliner.cpp` mirrors);
  `include/mlir/Transforms/InliningUtils.h` (`DialectInlinerInterface`);
  `lib/IR/SymbolTable.cpp` (`lookupSymbolIn`, and the `SymbolTable`
  trait's region verifier that runs every `verifySymbolUses` with one
  collection); `lib/IR/Verifier.cpp` (the parallel verification of
  isolated ops); `lib/Pass/Pass.cpp` (`OpToOpPassAdaptor`: the verifier
  runs on the op the pass ran on).

## Fixed decisions

1. **Units.** `IDR/IR/Func/Func.cpp`: `idr.func`'s `parse`, `print`,
   `verify` and `verifyRegions`. `IDR/IR/Func/Call.cpp`: `idr.call`'s
   `verifySymbolUses`, `getEffects` and `consumesOperand`; `idr.return`'s
   `verify`. `IDR/IR/Func/Inliner.cpp`: the dialect's inliner interface
   and `addInlinerInterface`. `IDR/IR/Verify/Attributes.cpp`:
   `verifyOperationAttribute`, `verifyRegionArgAttribute`.
   `IDR/IR/Verify/Program.cpp`: the module's rules.
   `IDR/IR/Verify/Knots.cpp`: the report of a cycle through an array.
   `IDR/IR/Verify/Linearity.cpp`: the numbering and the per-value count.
   `IDR/IR/Verify/Owned.cpp`: the owned-stage entry, the walk's state,
   its declaration memo and its visit of one op.
   `IDR/IR/Verify/OwnedRegions.cpp`: the walk of a match, an `scf.if`
   and an array loop. `IDR/IR/Verify/OwnedLoops.cpp`: the walk of the
   `scf.while` and `scf.for` that `idr-tail-loops` makes.
   `IDR/IR/Verify/Uses.cpp`: the definitions of `INC/IR/Ownership.h`.
   Every unit includes `idr/IR/IdrDialect.h` first among ours, then the
   `idr/IR/` headers it names (`Func.h`, `Verify.h`, `Ownership.h`,
   `Grades.h`, `Symbols.h`, `TypeGraph.h`, `Layout.h`), then its MLIR
   and LLVM headers by name. Each is at or under 400 lines.
2. **Headers.**
   - `INC/IR/Func.h` declares `void idr::addInlinerInterface(IdrDialect &)`.
   - `INC/IR/Ownership.h` declares, in `idr::ownership`, exactly C2.0's
     list: `enum class Use { Consume, Borrow };`,
     `Use useOf(mlir::OpOperand &, mlir::SymbolTable *symbols = nullptr)`,
     `bool isStatic(mlir::Value)`, `mlir::Value readFrom(mlir::Value)`,
     `bool reachesOnlyAtoms(mlir::Value, llvm::function_ref<DataOp(mlir::Type)>)`,
     `bool isArrayLoop(mlir::Operation *)`, `bool inOwnedStage(FuncOp)`.
     It includes `idr/IR/IdrDialect.h` and nothing of `IdrAnalysis`.
   - `INC/IR/Verify.h`, the area header of `IdrIR`'s verifier, declares
     in `idr::verify`: `LogicalResult program(ModuleOp)`;
     `LogicalResult knots(ModuleOp, const TypeGraph &)`; the class
     `Numbering` (decision 5); `bool definesOwned(Operation *)` (an op
     with an owned or exclusive result, or a region whose block has
     such an argument), the one predicate the stage is decided by;
     `LogicalResult linearity(const Numbering &)`;
     `LogicalResult owned(FuncOp)`; and the class `OwnedWalk` (the state
     of the walk, its memo and its primitives, whose methods three units
     define). `OwnedWalk` is library-internal to `IdrIR` and lives in the
     area header because three units define it.
3. **`idr.func`'s text.** `parse` calls
   `function_interface_impl::parseFunctionOp` with variadic off, a
   `buildFuncType` that returns `FunctionType::get(inputs, results)`, and
   the generated `getFunctionTypeAttrName`, `getArgAttrsAttrName`,
   `getResAttrsAttrName`; `print` calls `printFunctionOp` with the same
   names. The facts print as the remaining inherent attributes inside
   `attributes {…}`: `total`, `break_last`, `no_inline`,
   `effects = #idr.effects<io>`,
   `instance = #idr.instance<"Prelude.f", ["Prelude.Types.Nat"]>`,
   `clone = #idr.clone<…>`, as `func.func` prints its own. The body's ops
   print without the `idr.` prefix: `getDefaultDialect` is defined once,
   in the ODS's `extraClassDeclaration`, and `OpAsmOpInterface` is listed
   plainly (C1.2). Nothing else is custom.
4. **When each rule runs.** `FuncOp::verify` runs with the op's own
   verification and reads only the op's attributes and type.
   `verifyRegions` runs after the body's ops are verified
   (Operations.md:714-724), so the function rules may rely on what the
   ops' verifiers established: a match's regions and yields, a
   `lin.enter`'s types. The module rules run in the module's first
   phase, from the dialect's attribute hook, before the ops inside are
   verified, and assume nothing of them, as today (Program.cppm:16-21).
   MLIR's pass manager verifies the op a pass ran on: a function pass is
   followed by the verifiers of its function alone, a module pass by the
   module's hook and, through MLIR's recursion, every function's
   verifiers (C4). `verifySymbolUses` of a call runs when the module is
   verified, from the `SymbolTable` trait's region verifier with one
   `SymbolTableCollection` for every user, as `func.call`'s does today;
   a function pass's verify does not run it.
5. **Linearity, linear.** `Numbering` is built by one pre-order walk of
   the body, which does three things: it gives every operation an index
   in a `llvm::DenseMap<Operation *, unsigned>`, it collects every value
   of quantity one (the arguments of every block, the results of every
   op) in walk order, and it records whether `definesOwned` holds for the
   function or any op in it. Then, per linear value, today's holder
   collection (Linearity.cppm:28-39) runs unchanged, `top` is sorted by
   the shared index instead of a map built for the value (`:40-50` go),
   and today's `count` (`:65-90`) and `secondUse` (`:54-62`) run on it.
   Pre-order numbers the ops of one region in block order, so the sort is
   the same. The constant exemption (`:112`) and the two messages
   (`:115-117`) are unchanged: `uses a world that is already used on the
   same path`, `uses a linear value that is already used on the same
   path`. The verifier does not call `isBeforeInBlock`: it writes
   nothing, not even a block's order cache, which other threads'
   verifiers read. Cost: one map of the body plus, per linear value, its
   holders. A body of several blocks (only after the inliner takes in a
   callee ending in `ub.unreachable`, until `canonicalize` erases the
   unreachable block, C1.2) is counted as today's `count(Region &)`
   counts one (`:22-25`, `:65-71`).
6. **The owned stage, per function.** A function is in the owned stage
   when any value of it has the grade own or excl (`isOwned`): an entry
   argument, an argument of a nested block, or a result. `Numbering`
   records it from the walk of decision 5; `inOwnedStage(FuncOp)` in
   `Uses.cpp` answers the same question for the passes, by one walk with
   `definesOwned` interrupted at the first hit (InOwnedStage.cppm:16-29
   over one function). An external function has no rules. The module is
   not consulted (C4). A module-level stage question is an `any_of` over
   the module's functions, written where it is asked (U08, U11), not
   here. The residual this accepts: a pass that strips every owned grade
   from a function whose signature carries none leaves a function in the
   pre-stage shape, which the pre-stage rules accept; a stripped
   signature is caught at its callers by decision 9's type check.
7. **The owned walk.** `OwnedWalk` is today's `References`
   (References.cppm:16-154), `Loops` (Loops.cppm:15-188) and `Checker`
   (Checker.cppm:21-298) with their meaning unchanged and these
   retargets:
   - `func::FuncOp` becomes `FuncOp` and `func::ReturnOp` becomes
     `ReturnOp` (Checker.cppm:26, `:52`);
   - `op.hasAttr("idr.stack")` (`:85`) becomes
     `IdrDialect::StackAttrHelper(...).isAttrPresent(op)` (the spelling
     the generated helper gives at the pin);
   - the take's `ctor` read by string (`:173`) becomes
     `cast<TakeOp>(made).getCtorAttr()`;
   - `Counting` (Counting.cppm:18-41) and its `SymbolTableCollection`
     go. `OwnedWalk` holds, for one run of `owned(FuncOp)`, two maps:
     `llvm::DenseMap<Type, DataOp> declarations`, filled by a member
     `DataOp declaration(Type)` that calls `declarationOf(fn, type)` once
     per distinct type, and `llvm::DenseMap<Type, bool> counted`, filled
     by `holdsReferences(type, [&](Type t) { return declaration(t); })`
     once per distinct type. Every declaration the walk needs comes from
     `declaration`: an unboxed sum's for `isView`, a constant
     constructor's in `reachesOnlyAtoms` (decision 8), a take's and a
     reuse's, whose constructor is then
     `lookupCtor(declaration(DataType of the root), leaf name)`. So each
     distinct declaration is scanned for at most once per verify of the
     function, and a function that asks about no sum, no constant
     constructor and no reuse scans nothing;
   - `Layouts` is constructed at most once per verify, lazily at the
     first `idr.reuse` the walk meets, as
     `Layouts(fn->getParentOfType<ModuleOp>())` (C2.1). When
     `!valid()`, the reuse rule fails; the constructor has already
     reported each cell with today's `unsupported (layout)` text. The
     size check is today's (Checker.cppm:184-188): `builds a cell of N
     bytes in the M-byte cell of @X::@C`.
   The walk builds no `SymbolTable` and no `SymbolTableCollection`, and
   calls `useOf` without a table. The `1024` depth guards
   (References.cppm:94, Loops.cppm:126) keep their values and comments.
   The walk starts at the entry block (Checker.cppm:26-35); a return
   ends a path. Its messages are today's, each through `emitOpError` at
   the op that breaks the rule, with the note `the value is defined
   here` where today attaches one (References.cppm:110-114).
8. **The shared vocabulary.** `Uses.cpp` defines `INC/IR/Ownership.h`:
   - `useOf` as UseOf.cppm:20-24: a force consumes when its operand is
     owned; every other use is `consumes(operand, symbols)` (U01), the
     table passed through, which only `idr-rc` and `idr-rc-place` give;
   - `isStatic` (IsStatic.cppm:14-20) and `readFrom` (ReadFrom.cppm:13-23);
   - `reachesOnlyAtoms` as ReachesOnlyAtoms.cppm:21-56, the declaration
     of a constant constructor asked of the caller's resolver with
     `DataType::get(ctx, FlatSymbolRefAttr::get(root))` of the
     constructor's root reference (the declaration depends on the name
     alone, box or not); the verifier passes its memo, U08 a lookup
     through the `SymbolTable` analysis it holds;
   - `isArrayLoop` as ArrayLoop.cppm:18-25;
   - `inOwnedStage(FuncOp)` as decision 6.
   They live in `IdrIR` because the verifier is there; `IdrNarrow` and
   `IdrExpect` include the header and link `IdrIR` only.
9. **`idr.call`'s symbol uses.** `verifySymbolUses(SymbolTableCollection &symbols)`
   resolves `symbols.lookupNearestSymbolFrom<FuncOp>(*this, getCalleeAttr())`,
   then checks, each through `emitOpError`, in this order:
   - `calls @f, which the module does not define as an idr.func`;
   - `passes N arguments to @f, which takes M`;
   - `passes 'T' as argument i of @f, which takes 'U'`, each type by
     equality, so every operand's type is its parameter's (which
     `consumesOperand` relies on);
   - `expects N results from @f, which returns M`;
   - `expects 'T' as result i of @f, which returns 'U'`;
   - when the call's `getEffectsAttr()` is present: the callee's bits
     are its `getEffectsAttr()` value, or io, crash and diverge when it
     has none or is external (Of.cppm:16-24); the call must contain them
     (`bitEnumContainsAll`), else `carries effects <call>, but @f may do
     <callee>`, each printed as `#idr.effects<…>` prints it. Since no
     writer stores the full set, a present call effects never contains a
     callee that may do anything.
   The lookup is O(1) in the collection MLIR shares across every user of
   the module's verify.
10. **`idr.call`'s effects.** `getEffects` reads only the op:
    - its bits are `getEffectsAttr()`'s value, or io, crash and diverge
      when the attribute is absent;
    - the bits map to the resources as CallEffects.cc:46-55 maps them
      (io a read and a write of `IOResource`; crash a write of
      `CrashResource`; diverge a write of `DivergenceResource`; either
      without io also a write of `IOResource`);
    - then `consumedEffects(getOperation(), effects)` (U01);
    - then one `Allocate` on `LinResource` per result whose
      `unrestricted` type is not an integer, index or float and not a
      world (CallEffects.cc:56-60 without the erased case).
    It resolves no symbol, scans nothing and computes no fact: what the
    closures passed may do is already in the call's bits, written by
    `idr-effects` (U03), which keeps the rule of Infer.cppm:38-43. Every
    query is O(operands + results), so canonicalize, CSE and
    `remove-dead-values` ask it freely, from any thread.
11. **`idr.return`'s verifier.** The parent is an `idr.func`
    (`HasParent`); `idr.return` ends a block of its body. `verify` checks
    the operand count and types against the parent's `getResultTypes()`.
    Messages: `returns N values, but @f returns M`; `returns 'T' as
    result i, but @f returns 'U'`.
12. **The inliner interface.** `struct IdrInlinerInterface : DialectInlinerInterface`
    in `Inliner.cpp`, mirroring func's interface at the pin:
    - `isLegalToInline(Operation *call, Operation *callable, bool)` is
      true;
    - `isLegalToInline(Region *, Region *, bool, IRMapping &)` is true;
    - `isLegalToInline(Operation *, Region *, bool, IRMapping &)` is
      true, as today (Inliner.cppm:16-19);
    - `handleTerminator(Operation *op, ValueRange valuesToRepl)`
      replaces each value with the matching operand of the `idr.return`,
      which the inliner then erases;
    - `handleTerminator(Operation *op, Block *newDest)` replaces the
      `idr.return` with a `cf.br` to `newDest` carrying its operands,
      built with an `OpBuilder` at the return, then erases the return.
    The interface decides nothing about `no_inline` or profitability
    (U05's `InlineDecisions`). A callee ending in `ub.unreachable` is
    decided by the carried patch of `PINS.md` `inline-unreachable`
    (inlined into a function body, left a call in a region that must stay
    one block), exactly as for `func.func` today. `addInlinerInterface`
    does `dialect.addInterfaces<IdrInlinerInterface>()`
    (Inliner.cppm:27), and U01's `initialize` calls it. The dialect's
    `dependentDialects` include `cf` (C1.2), so the `cf.br` is legal.
13. **The module verifier.** `program(ModuleOp)`:
    - the root: Program.cppm:23-39 over `FuncOp` (`expects exactly one
      public function (the root), found N`; `is the root, so its type
      must be () -> i64 or (!idr.world) -> (...), not …`);
    - every `!idr.data` and `!idr.box` names a declaration of its kind:
      `:68-116` unchanged, `datas` built once, one `AttrTypeWalker`
      whose cache visits each type and attribute once (`uses an
      undeclared data type @X`; `uses '!idr.data<@X>', but @X is declared
      box, so its values are !idr.box`, and the unboxed counterpart);
    - one `idr::TypeGraph graph(module)` (`INC/IR/TypeGraph.h`),
      constructed directly: if `graph.containsItself()` is not empty, its
      first declaration (module order) is reported with `contains itself
      through unboxed sums; a recursive type must be declared box`
      (`:127-128`), one error per module as today; then
      `knots(module, graph)`.
    `Knots.cpp` is Cycles.cppm:155-215 over `graph.knots()`,
    `graph.cycle`, `graph.type`, `graph.isArray` and
    `graph.declaration`: each knot reported at the first `idr.array.new`
    in the program's own code, else at a declaration on the cycle, else
    at the module, with `unsupported (cycle): an <array> can hold a
    reference to itself through <T> -> … -> <T>`. `inSource` tests
    `loc->findInstanceOf<FileLineColRange>()` (C6.5), so a location
    with a `NameLoc` around its range still counts as source. The
    module walk for `idr.array.new` runs only when there is a knot.
    Nothing walks the module for attributes, linearity or references.
14. **Phase 0's interface (U10).** `idr-lower` reads a function with the
    generated accessors only: `getSymNameAttr`, `getFunctionType`,
    `getSymVisibilityAttr`, `getArgAttrsAttr`, `getResAttrsAttr`,
    `getTotal`, `getBreakLast`, `getNoInline`, `getEffectsAttr`,
    `getInstanceAttr`, `getCloneAttr`, and moves `getBody()` into the
    `func.func` it builds; an `idr.call` gives `getCalleeAttr`, `getArgs`,
    `getArgAttrsAttr`, `getResAttrsAttr`, and its `effects` is dropped
    (C2.5); an `idr.return` gives its operands. Nothing in this lane's
    headers is for it, and no verifier of this lane runs on a
    `func.func`.
15. **The clone fact.** `FuncOp::verify` (the ODS's `hasVerifier`), when
    `getCloneAttr()` is present, refuses with `expects clone to name the
    function and its key` (today's text at Attributes.cc:72, renamed)
    a clone whose `getFunction()` is not `getSymNameAttr()` or whose key
    is not a `SpecKeyAttr`, `KeyApplyAttr` or `KeyApplyFieldAttr`; and,
    for a `SpecKeyAttr`, refuses with `has a clone key with N holes, but
    takes M parameters` when the count of `KeyHoleAttr` in its patterns
    (one `walk` per pattern, as Clones.cppm:110-116) is not the number
    of the function's parameters. It reads no other function.
16. **Consumption by grade.** `CallOp::consumesOperand(unsigned index)`
    returns `isOwned(getOperand(index).getType())`. Decision 9 makes the
    operand's type the callee's parameter type, so this is the callee's
    grade without a lookup (Consumed.cc:24-28 did one per call).
    `idr-rc` and `idr-rc-place`, which ask before the operands are
    retyped, pass their table to `consumes` (U01, R08); this method is
    the tableless answer.
17. **Parallelism and cost.** The parallel unit is one `idr.func`: it is
    `IsolatedFromAbove`, so MLIR's verifier runs `verify` and
    `verifyRegions` of each function on the context's thread pool. What a
    function's verify reads is the function, its own attributes, the
    module's top-level declarations through `declarationOf` (read-only
    scans, at most one per distinct type, decision 7) and, for a function
    with a reuse, one `Layouts`. It writes nothing outside its own
    locals: no block order cache, no shared collection, no memo that
    outlives the call. `verifySymbolUses` runs serially, once per module
    verify, O(1) per call. The module hook constructs one `TypeGraph`
    per module verify; no analysis manager is involved, so the verifier
    has no preservation obligation and keeps none. The walks this lane
    removes: the attribute walk of every op (Program.cppm:41-66), the
    dictionary check every idr op ran (DiscardableAttrs.cc:21-38), the
    module-wide linearity loop (Program.cppm:146-150), the per-value
    numbering of the home region (Linearity.cppm:40-50), the serial owned
    walk of every function with a fresh symbol table from the module hook
    (Ownership/Verify.cppm:28-53, Attributes.cc:43), the second
    containment search (Program.cppm:118-145), and the per-query module
    scans of a call's effects and consumption (CallEffects.cc:43-45,
    Consumed.cc:24-28).

## Inputs

- C1.2's Functions block: `Idr_FuncOp` with `hasVerifier`,
  `hasRegionVerifier`, `getDefaultDialect`, `absorb` and its accessors
  (`getTotal`, `setTotal`, `getBreakLast`, `getNoInline`,
  `getEffectsAttr`, `setEffectsAttr`, `getInstanceAttr`, `getCloneAttr`,
  `getBody`, `isExternal`, `getArgumentTypes`, `getResultTypes`);
  `Idr_CallOp` with `getCalleeAttr`, `getArgs`, `getArgOperands`, the
  generated `arg_attrs`, `res_attrs` and `effects` accessors, and the
  declared `SymbolUserOpInterface`, `MemoryEffectsOpInterface` and
  `Idr_ConsumingOpInterface` (`consumesOperand`); `Idr_ReturnOp`;
  `Idr_InstanceAttr`, `Idr_EffectAttr`, `Idr_CloneAttr` and the key
  attributes; the dialect's `discardableAttrs` (`program`, `stack`) and
  `dependentDialects` (`arith`, `cf`, `ub`, LLVM).
- `idr::TypeGraph` (C2.1, `INC/IR/TypeGraph.h`, `IdrIR`): the
  `(Operation *)` constructor, `containsItself`, `knots`, `cycle`,
  `type`, `isArray`, `declaration`.
- `idr::Layouts` (C2.1, `INC/IR/Layout.h`, `IdrIR`): `explicit
  Layouts(mlir::Operation *)`, `valid()`, `box`.
- From U01, by C2.0's names: `consumes(OpOperand &, SymbolTable * = nullptr)`,
  `consumedEffects`, `IdrDialect::ProgramAttrHelper`, `StackAttrHelper`,
  `IOResource`, `CrashResource`, `DivergenceResource`, `LinResource`
  (`INC/IR/IdrDialect.h`); `quantityOf`, `unrestricted`, `isWorld`,
  `isOwned`, `isExclusive` (`INC/IR/Grades.h`); `declarationOf`,
  `lookupCtor(DataOp, StringRef)`, `holdsReferences(Type,
  function_ref<DataOp(Type)>)`, `isMemo` (`INC/IR/Symbols.h`).
- The writers that keep a call's `effects` valid (C2.2): `idr-effects`
  (U03) writes it on every call from its callee's and the closures
  passed; a pass that rebuilds a call of the same callee keeps it; a
  pass that makes a call or changes its callee gives the old call's
  effects only when they contain the new callee's.
- MLIR: `function_interface_impl::parseFunctionOp` and `printFunctionOp`;
  `SymbolTableCollection`; `DialectInlinerInterface`; `cf::BranchOp`;
  `AttrTypeWalker`; `MemoryEffects`; `bitEnumContainsAll` from the
  generated enum.

## Outputs

- `INC/IR/Func.h`: `idr::addInlinerInterface(IdrDialect &)`, consumed
  by U01's `IdrDialect::initialize`.
- `INC/IR/Ownership.h`: `idr::ownership::{Use, useOf, isStatic,
  readFrom, reachesOnlyAtoms, isArrayLoop, inOwnedStage}`, consumed by
  U08 (`IdrOwnership`, `IdrAnalysis`), U11 (`isStatic`,
  `inOwnedStage`) and U15 (`readFrom`).
- `INC/IR/Verify.h`: `idr::verify::{program, knots, Numbering,
  definesOwned, linearity, owned, OwnedWalk}`, consumed within `IdrIR`
  by `Func.cpp` and `Attributes.cpp`.
- The ops' C++: `FuncOp::parse`, `print`, `verify`, `verifyRegions`;
  `CallOp::verifySymbolUses`, `getEffects`, `consumesOperand`;
  `ReturnOp::verify`; `IdrDialect::verifyOperationAttribute`,
  `verifyRegionArgAttribute`.
- The messages of decisions 5, 7, 9, 11, 13 and 15, for U21.
- The unit list of decision 1, for the coordinator's `IDR/IR/CMakeLists.txt`
  (`IdrIR`).

## Implement

- **`Func.cpp`.** `parse` and `print` as decision 3. `verify` as
  decision 15. `verifyRegions`: `if (isExternal()) return success();`
  then one `verify::Numbering numbering(*this)`, then
  `verify::linearity(numbering)`, then, only when `numbering.owned()`,
  `verify::owned(*this)`. The interface's `verifyBody`
  (FunctionInterfaces.td:80-112) already matched the entry block to the
  type; nothing is repeated.
- **`Call.cpp`.** `verifySymbolUses` as decision 9, `getEffects` as
  decision 10, `consumesOperand` as decision 16, `ReturnOp::verify` as
  decision 11. No file-local lookup helper: nothing here reaches the
  module but the collection `verifySymbolUses` is given.
- **`Inliner.cpp`.** Decision 12. The MLton rule, the iteration bound,
  the clone callback and the pipeline runner are U05's.
- **`Attributes.cpp`.** `verifyOperationAttribute`: `idr.program`
  (`ProgramAttrHelper`'s name) on a `ModuleOp` as a unit attribute runs
  `verify::program`, else `expects idr.program as a unit attribute of
  the module`; `idr.stack` is Attributes.cc:57-63 (`expects idr.stack as
  a unit attribute of an idr.con of a box`); any other `idr.*` name is
  `has an unknown idr attribute <name>` (`:83`). `verifyRegionArgAttribute`
  refuses every name it is asked about with `has an unknown idr argument
  attribute <name>` (`:95`); `idr.hole` is no longer accepted. The table
  of `:32-75` goes; two `if`s replace it.
- **`Program.cpp`.** Decision 13's rules, with `datas` built once
  (Program.cppm:68-70) and the type walk as `:72-116`. The containment
  verdict comes from the graph.
- **`Knots.cpp`.** `inSource` and `describe` (Cycles.cppm:130-149) and
  `knots(ModuleOp, const TypeGraph &)` as `:155-215`.
- **`Linearity.cpp`.** `exclusiveRegions` (Linearity.cppm:14-20), the
  `Numbering` constructor (the one walk), `LinearUses` taking the
  numbering by reference, `linearity(const Numbering &)` iterating the
  numbering's linear values in walk order.
- **`Owned.cpp`.** `owned(FuncOp)`: constructs `OwnedWalk` with the
  function and its lazy `Layouts`, runs `check` (Checker.cppm:26-35);
  `OwnedWalk`'s state, `declaration`, `counted`, `tracked`
  (References.cppm:23-148 with the memo of decision 7), `visit`
  (Checker.cppm:62-151), `useKind` (`:155-167`), `fits` (`:169-189`).
- **`OwnedRegions.cpp`.** `walkRegions`, `walkMatch`, `walkArrayLoop`
  (Checker.cppm:191-295), and `walk(Block &)` (`:40-60`) with
  `ReturnOp` as the end of a path.
- **`OwnedLoops.cpp`.** Loops.cppm:21-188: `slotOwner`, `passOn`,
  `walkLoop`, the view owner's search, `walkFor`.
- **`Uses.cpp`.** Decision 8, and `verify::definesOwned`.
- **Failure paths.** Every rule reports through `emitOpError` at the op
  that breaks it. A verifier never asserts on a lookup that fails: a
  missing declaration is a diagnostic in the module rules and a
  `calls @f, which the module does not define as an idr.func` in a
  call's; in the owned walk a declaration that cannot be found answers
  as today's `lookupCtor` failures do (Checker.cppm:178-179: nothing to
  compare, success), and the module rules report it.

## Delete

- `IDR/Verify/Cycles.cppm`, `Linearity.cppm`, `Program.cppm`,
  `Verify.cppm`, `CMakeLists.txt`, and the library `idr_verify`.
- `IDR/Dialect/Verify/Attributes.cc`, `DiscardableAttrs.cc`. The latter
  defined `verifyDiscardableAttrs`, the body of the
  `Idr_KnownAttributes` trait (F-fact-2); the coordinator removes the
  trait from the ODS and U01's header declares neither. Its
  `kOutsideDialects` list goes with it: an attribute of no dialect,
  `expect.facts` included, is accepted by MLIR and read by `idr-expect`.
- `IDR/Ownership/Verify.cppm`: `verifyOwned(ModuleOp)`, its
  `SymbolScope` (`:37`), its `SymbolTable` (`:36`) and its loop over the
  module's functions.
- In the module verifier: the attribute walk (Program.cppm:41-66), the
  containment search (`:118-145`), the linearity loop (`:146-150`), the
  call of the owned-stage check from the attribute hook
  (Attributes.cc:43), the rows for the facts as discardable attributes
  (`:45-54`, `:64-74`), and the per-value numbering
  (Linearity.cppm:40-50).
- `verifyRegionArgAttribute`'s acceptance of `idr.hole`
  (Attributes.cc:91-94) and every use of `HoleAttrHelper` here.
- The `Counting` class (Counting.cppm:18-41) as the verifier used it,
  with its `SymbolTableCollection`; the `idr.stack` read by string
  (Checker.cppm:85) and the `ctor` read by string (`:173`).
- Lookups through the chains kept outside the IR: `SymbolScope` in
  `Verify.cppm:37`, `lookupSymbol` in `ReachesOnlyAtoms.cppm:29` and in
  `CallEffects.cc:43`, and `HoldMemo` behind `mayHoldClosure` in
  `Passed.cppm:57`. Neither the verifier nor any hook of the ops opens or
  reads one.
- Logic re-housed here whose files their owners delete:
  `IDR/Facts/CallEffects.cc` (U03), `IDR/Ops/Inliner.cppm` (U01),
  `IDR/Ownership/Checker.cppm`, `References.cppm`, `Loops.cppm`,
  `InOwnedStage.cppm`, `Counting.cppm`, `UseOf.cppm`, `IsStatic.cppm`,
  `ReadFrom.cppm`, `ReachesOnlyAtoms.cppm`, `ArrayLoop.cppm` (U08).

## NOT TO DO

- Do not edit `INC/IR/IdrOps.td` or any `CMakeLists.txt`
  (coordinator); the ODS of C1.2 is used as if it had landed.
- Do not cache a symbol table, a declaration or a type answer anywhere
  but in the locals of one verify: no `thread_local`, no `static`
  object, no `std::atomic`, no member of the dialect or of an op (C2.0).
- Do not resolve the callee or any sibling `idr.func` in `getEffects`,
  `consumesOperand`, `ReturnOp::verify`, `FuncOp::verify` or
  `verifyRegions` (C2.0). The callee is read only in `verifySymbolUses`,
  through the collection it is given.
- Do not compute what a call or a function may do: `idr-effects` (U03)
  writes it; `getEffects` and the containment check read it. Do not
  write `Effects`, `Holds`, `TypeGraph`, `Scc` or `idr-effects` (U03).
- Do not define `CallOp::getAsmResultNames`, an alias or a name helper
  (U01, `IDR/IR/Asm.cpp`, C7.1).
- Do not write `idr-rc`, `idr-rc-place`, `Borrows`, `Reuses` or
  `Exclusivity` (U08). `Uses.cpp` holds the declarations of
  `INC/IR/Ownership.h` and nothing of placement; `usersIn`, `usedAfter`,
  `whereDies`, `followed`, `onlyReads` and `Counted` stay U08's.
- Do not write `InlineDecisions`, the clone callback, the marks or the
  pipeline runner (U05), and do not decide `no_inline` or profitability
  in the interface.
- Do not add `SymbolUserOpInterface` to `idr.func`, and do not move the
  owned walk's declaration half into a `verifySymbolUses` (C4 keeps it in
  `verifyRegions`).
- Do not keep any module-wide rule for linearity or references, and do
  not read the module from `verifyRegions` to decide the stage.
- Do not write or edit a fixture (U21); state the messages.
- Do not add a limit, budget or depth; the two `1024` guards keep their
  values and comments.
- Do not touch the Idris side (U18, U19, U20), `IDR/Conversion` (U10) or
  `INC/IR/Layout.h` (U10).

## Stop and return

Done when the eleven units of decision 1 and the three headers exist,
the three owned deletions are made, no `.cppm` remains under
`IDR/Verify`, `IDR/Dialect/Verify` or at `IDR/Ownership/Verify.cppm`,
and no unit of this lane names `func::FuncOp`, `func::CallOp`,
`func::ReturnOp`, or reads a fact with `hasAttr`, `getAttr` or
`getAttrOfType` by string. Return the changed paths against outcomes 1
to 7, the unit list, the messages, `Verification: NotRun (swarm
policy)`, and as seams without stopping:

- the members of `TypeGraph` and `Layouts` the verifier read, by their
  spelling in the headers;
- each upstream signature confirmed at the pin (`parseFunctionOp`,
  `printFunctionOp`, both `handleTerminator` forms, the
  `StackAttrHelper` presence test, `bitEnumContainsAll`, the verifier's
  parallel loop over isolated ops), with any difference from this text
  (C0: the pinned header is right; report, never patch);
- that a module whose `Layouts` is not valid and that holds reuses in
  several functions has the layout errors reported once per such
  function, from parallel verifies, in the pool's order; only a fixture
  reaches it, since every pass that asks for `Layouts` fails first;
- E1.

## Acceptance

Each is a U21 fixture under `T/idr/func/` or `T/idr/verify/`; the
property is what `idris-mlir-opt -verify-diagnostics` or `FileCheck`
observes.

- **`T/idr/func/world-twice`.** An `idr.func` that uses a world twice on
  one path is refused at the second use with `uses a world that is
  already used on the same path`; one that uses it once in each region
  of a match passes.
- **`T/idr/func/linear-twice`.** Today's `T/idr/verify/linear.mlir`
  cases on `idr.func`, `idr.call` and `idr.return`: `uses a linear value
  that is already used on the same path` at `:46` and `:68`; the
  accepted cases accepted.
- **`T/idr/func/owned-not-consumed`.** Today's `T/idr/ownership/owned-stage.mlir:24-36`
  on `idr.func`: `returns while a value still holds a reference` with the
  note `the value is defined here`; and a second function in the same
  module with no owned value and a plain constructor passes, since the
  stage is the function's. Owned-stage fixtures keep an `idr.reuse`
  round trip.
- **`T/idr/func/call-type`.** A call of `@f : (!idr.str) -> i64` as
  `(i64) -> i64` is refused with `passes 'i64' as argument 0 of @f,
  which takes '!idr.str'`; a wrong count with `passes 2 arguments to @f,
  which takes 1`; a wrong result with `expects 'i64' as result 0 of @f,
  which returns '!idr.str'`; a wrong result count with `expects 2
  results from @f, which returns 1`; a callee the module lacks with
  `calls @g, which the module does not define as an idr.func`. A return
  of the wrong shape is refused with `returns 2 values, but @f returns
  1` or `returns 'i64' as result 0, but @f returns '!idr.str'`.
- **`T/idr/func/call-effects`.** A call carrying
  `{effects = #idr.effects<io>}` of a callee with
  `effects = #idr.effects<io, crash>` is refused with `carries effects
  #idr.effects<io>, but @f may do #idr.effects<io, crash>`; one of a
  callee without `effects` is refused the same way; one that contains
  its callee's passes; `--idr-effects` writes the call's attribute; a
  call without one stays under `--canonicalize`.
- **`T/idr/func/clone-shape`.** A clone whose function is not itself is
  refused with `expects clone to name the function and its key`; a
  `spec_key` with two holes on a function of one parameter with `has a
  clone key with 2 holes, but takes 1 parameters`.
- **`T/idr/func/facts-roundtrip`.** `idr.func private @f(%x: i64) -> i64
  attributes {total, no_inline, effects = #idr.effects<io, crash>,
  instance = #idr.instance<"Prelude.f", ["Prelude.Types.Nat"]>,
  clone = #idr.clone<@f, …>}` prints and parses to the same text; the
  body prints `call` and `return` without a prefix; `total = 1 : i64` is
  refused by the ODS constraint; no `idr.total`, `idr.effects`,
  `idr.break_last`, `idr.clone` or `idr.hole` appears in any fixture
  (C9.1).
- **`T/idr/func/inline`.** Under `--idr-inline`, a call of a one-block
  callee is replaced by its body, the call's results by the return's
  operands, and no `idr.return` remains from the callee; a callee ending
  in `ub.unreachable` is inlined into a function body and left a call
  inside a match region.
- **`T/idr/verify/module`.** Today's root rules with today's text on
  `idr.func`.
- **`T/idr/verify/data`.** `uses an undeclared data type @X`; `uses
  '!idr.data<@X>', but @X is declared box, so its values are !idr.box`.
- **`T/idr/verify/cycle`.** `unsupported (cycle): an array of Node can
  hold a reference to itself through Node -> array of Node -> Node`
  (today's `:23`) at the first `idr.array.new` in the program's code;
  `contains itself through unboxed sums; a recursive type must be
  declared box` once, at the first declaration on the cycle.
- **`T/idr/verify/attributes`, `T/idr/verify/function`.** The cases that
  tested the attribute policing go; what stays: `has an unknown idr
  attribute "idr.nonsense"` for an unknown `idr.*` discardable
  attribute on any op, `has an unknown idr argument attribute
  "idr.hole"` on a parameter, `expects idr.program as a unit attribute
  of the module`, `expects idr.stack as a unit attribute of an idr.con
  of a box`; an argument attribute outside the prefix (`sample.x`) is
  accepted.
- **`T/idr/canon/unused-call`.** Under `--idr-effects --canonicalize`:
  an unused call of a callee marked `total` with `effects =
  #idr.effects<none>` goes; a call that is given a closure whose label
  may crash stays (today's `:1-3`, `:23-24`), because `idr-effects`
  wrote crash on the call.
- **Source conditions.** `grep -rn 'func::FuncOp\|func::CallOp\|func::ReturnOp\|hasAttr("idr\.\|getAttr("idr\.\|getAttrOfType<[A-Za-z]*>("\|thread_local\|std::atomic' IDR/IR/Func IDR/IR/Verify`
  prints nothing; `grep -n 'lookupNearestSymbolFrom\|lookupSymbolIn\|declarationOf\|constructorOf' IDR/IR/Func/Call.cpp`
  prints only the collection's lookup in `verifySymbolUses`; no
  `SymbolTable` or `SymbolTableCollection` is constructed under
  `IDR/IR/Verify`; every unit of this lane is at or under 400 lines; no
  `.cppm` remains in the deleted areas.
- **Review conditions.** `Linearity.cpp` builds one numbering per body:
  no map of operations is constructed inside the per-value loop.
  `OwnedWalk` calls `declarationOf` only from `declaration`, behind its
  map, and constructs `Layouts` at most once.
- **Tempting partials, rejected.** Keeping the module-level linearity
  loop beside the function rule (two homes for one rule; F-pass-2).
  Reading the module from `verifyRegions` to decide the stage (C4).
  Looking the callee up in `getEffects` "for precision" (C2.0; the call's
  own `effects` is the answer). Accepting `idr.hole` for old fixtures
  (R04).

## Escalate if

- **E1. The type rule is the module verify's last walk of every op.**
  C4 keeps "every data type declared and of its kind" in the module
  verifier, and decision 13 writes it there: a serial walk of every op's
  attribute dictionary, results and block arguments
  (Program.cppm:99-116), run by the module hook after every module
  pass, before the parallel function verifies start. The
  `AttrTypeWalker` visits each distinct type once, but the op walk is
  O(module) per module verify, after every module pass of the round.
  No ruling settles where it runs. Report its share of the
  `VerifierPass` rows (R47 records them) and the split that would make
  it parallel: the module keeps the declarations' field types and the
  signatures; each `idr.func`'s `verifyRegions` checks the types inside
  its body against the declaration memo of decision 7, with today's
  messages at the same ops. This lane does not make that move.
