# How idris-mlir uses MLIR, read against MLIR's own documentation

Stream: mlir-idioms. Read: the pinned `.toolchain/llvm-project/mlir/docs`
(the same llvmorg-23.1.2 text as `sources/docs/mlir`): LangRef, Dialects/Builtin, LLVM,
MemRef, Transform, IRDL, DefiningDialects/*, Interfaces, Traits, Tokens,
Canonicalization, PatternRewriter, DialectConversion, DataLayout,
Diagnostics, PassManagement, ActionTracing, PDLL, DeclarativeRewrites,
Bufferization, OwnershipBasedBufferDeallocation, SymbolsAndSymbolTables,
Rationale/{Rationale,SideEffectsAndSpeculation}, Tutorials/DataFlowAnalysis.
Where the docs are thin I read the headers and sources: `SideEffectInterfaces.h`,
`SideEffectInterfaceBase.td`, `IntegerRangeAnalysis.cpp`, `Verifier.cpp`,
`SymbolTable.cpp`, `LLVMTranslationInterface.h`, `ModuleTranslation.cpp`,
`FuncToLLVM.cpp`, `LLVMOps.td`, `LLVMDialect.td`, and
`BufferViewFlowOpInterface.td`. Then I read our side: `foreign/idr/include/idr/*`, `lib/Dialect`,
`Ownership`, `Stack`, `Lower`, `Facts`, `Passes`, `Registration.cc`,
`Canonicalize`, and `tools/idris-mlir-cc.cc`.

Experiments: the built `build/dev/foreign/idr/idris-mlir-opt`, in
`$SCRATCH/research/mlir-idioms/`, under the shared lock (inputs quoted below).

There is a companion sketch, `findings/mlir-ownership-types.md`, on typing the
owned stage.

## The questions

1. Is each point of the outside review right, and what is the idiomatic MLIR fix?
2. Which MLIR mechanisms do we reimplement by hand, or not use when we should?
3. Where is our use of MLIR fragile, and which representation would make the
   bad state unrepresentable?
4. What in the dialect does not carry weight (it is dead, decorative, or accepted
   without meaning), and where do we flatten Idris's richness too early? (This is
   the coordinator's addendum, from `principle-representation.md`.)
5. What does MLIR offer for the rich-data optimizations: ranges, uniqueness,
   noalias, range and nonnull?

---

## 1. The outside review, point by point

### 1.1 A dead ctor attribute that verifies: agree, and it is wider than `quantities`

Evidence:
- `tests/idr/rc/loops.mlir:16-17` and `tests/idr/stack/expect.mlir:16-17` carry
  `{quantities = ...}`, and nothing reads it.
- The mechanism is general. The verifier asks a dialect about a discardable
  attribute only when the attribute's name has a dialect prefix: the loop at
  `mlir/lib/IR/Verifier.cpp:300-308` runs `attr.getNameDialect()` and then
  `verifyOperationAttribute`. An unprefixed name reaches no one.
- LangRef ("Attributes", `docs/LangRef.md:808-823`) says that discardable
  attributes *must* have dialect-prefixed names. Only `builtin.module` enforces
  that rule (`lib/IR/BuiltinDialect.cpp:168`).
- Experiment (`junk.mlir`): all of these verify and round-trip:
  - `idr.ctor @N tag 0 () {anything = "goes", quantities = []}`;
  - `idr.tag %0 {nonsense = 1 : i64}`;
  - `func.func @root() ... attributes {junk}`.
- Only `module attributes {whatever = 3}` is rejected, by the builtin rule.

The idiomatic fix is the builtin module's own rule, applied to the program:
- `verifyProgram` (`lib/Dialect/Dialect.cc:214`) already walks every op of an
  `idr.program`. It should reject any discardable attribute whose name has no
  prefix of a loaded dialect, and any `idr.*` name the dialect does not define.
  One rule covers every op, `func.func` included.
- A per-op verifier would miss the upstream ops we use.
- The same rule also catches the stale comment in `lib/Lower/Pass.cc:149-150`.
  It says calls carry `idr.spec_caller` and `idr.spec_stopped`, but neither
  attribute exists any more: `verifyOperationAttribute` would reject both
  (`Dialect.cc:478`), and nothing sets them.

### 1.2 Unchecked bit packing in the cell header: agree, and it is reproduced

Evidence:
- `lib/Lower/Layout.h:21-23` computes `tag | objs << 16 | kind << 24` with no
  range check. `Layout.cc:159` does `++cell.objs` with no bound.
- `labelId` (`Layout.cc:52-54`) returns an unbounded module-wide count that
  is used as a 16-bit tag.
- Experiment (`fat.mlir`): a box constructor with 256 `!idr.str` fields, run
  through `--idr-lower`, calls `idris_rt_cell(..., 16777216)`, which is `1 << 24`.
  The runtime (`runtime/idris_rt.h:76-77`) reads that as objs = 0 and
  kind = 1 (a closure). The cell's fields are never released, and a free reads
  the object slots at the closure offset (`rc.cc:76`). Nothing fails at compile
  time.
- There are two sources of truth for the packing: `cellInfo` with `CellKind`
  (`Layout.h:19-23`) and `idris_rt_info` with `IDRIS_RT_KIND_*`
  (`idris_rt.h:72-77`).
- The runtime also reuses the 16 tag bits for its free list (`rc.cc:44-50`),
  so the tag's width has two constraints behind it.

Idiomatic fix (fix the representation, not the use):
- The tag of a box constructor is its index in its data declaration. Since
  `DataOp::verify` forces `tag == index` (`Ops.cc:164-176`), the bound belongs
  on the declaration: `DataOp::verify` rejects a box with more than 65536
  constructors, with an `unsupported` error.
- `Layouts` returns `FailureOr<const Cell &>`. A `Cell` exists only once
  `objs <= 255` holds. The label table is likewise a `FailureOr` (at most 65536
  labels).
- The header word is a value type, say `CellInfo`, whose only constructor is
  `static FailureOr<CellInfo> make(tag, objs, kind)`. `storeHeader`,
  `allocate` and `staticCell` take a `CellInfo`, never a `uint32_t`, so an
  unchecked word can no longer be passed.
- `make` computes the word with the runtime's `idris_rt_info`, which
  `Lower/Runtime.cc` already includes. That leaves one packing, not two.
- MLIR's equivalent for an attribute is `genVerifyDecl` with `getChecked`
  (`docs/DefiningDialects/AttributesAndTypes.md` "Verification", 966-981). If
  the info word were ever printed in IR (a `#idr.cell_info<tag, objs, kind>`),
  that is the mechanism to use.

The test hole: agree, and it is not an MLIR matter.

### 1.3 One dialect, two semantics switched by `idr.stage`: agree, but a dialect split alone does not fix it; types do

The current state:
- `Ownership/Ops.cc:31-45`: `idr.inc`, `dec`, `reset`, `reuse` and `take`
  verify by walking up to the module and reading a string attribute.
- `Dialect.cc:437-442`: the stage's rule is a *module attribute verifier*.
  MLIR runs it before the module's ops are verified
  (`docs/DefiningDialects/Operations.md` "Verification Ordering", 687-708). So
  `Ownership/Verify.cc:7-8` must "assume no op is well formed", and it is a
  whole-module, path-by-path interpretation run after every pass.
- `Rc.cc:24` refuses a module that is already owned.
- `idr-lower` lowers both stages (the JIT path, `Lower/Counting.cc:3-4`).
- `LinearUses::count` special-cases `IncOp` (`Dialect.cc:373-376`): a linear
  value used by `idr.inc` is not consumed.
- `idr.stage` is a `StringAttr` with exactly one legal value, `"owned"`
  (`Dialect.cc:438-440`), so its value carries nothing and only its presence
  counts.
- Correctness after `idr-rc` also depends on pass order: the pipeline runs no
  stage-ignorant pass between `idr-rc` and `idr-lower` (`Registration.cc:24-27`).
  The review overstates one part: "every pass has to know its stage" is not
  quite true. Generic passes are held back by the memory effects of `inc`/`dec`
  and by re-verification. The coupling is real all the same.

Three designs compared:

| | stage attribute (today) | a pure dialect plus an rc dialect, legality-driven | stage in the **types** (bufferization's way) |
|---|---|---|---|
| can an rc op appear before rc? | the op's verifier walks to the module | yes, unless a verifier checks. `ConversionTarget` legality holds only *during* a conversion (DialectConversion.md "Conversion Target") | no: the op's operand types do not exist before rc, and ODS rejects it locally |
| what checks the invariant | a module-attribute verifier, before the ops, on the whole program | the same, plus pass-level `addIllegalDialect` in `idr-lower`'s JIT target | op verifiers (local), plus a linearity check on one type |
| what JIT lowering gets | runtime `if (jit)` branches | `addIllegalDialect<rc>` with no patterns: an rc op fails to legalize | the same as the split |
| cost | none | new dialect, move ops | new types, rewrite `Counts`/`Verify`/lowering |

Bufferization is MLIR's own precedent:
- The value world (`tensor`) and the buffer world (`memref`) are different
  *types*. One-Shot Bufferize converts between them (Bufferization.md,
  Overview and "What is One-Shot Bufferize?").
- The deallocation pipeline states the stage as a type rule: "from this point
  onwards no tensor values are allowed" (OwnershipBasedBufferDeallocation.md,
  the pipeline diagram).
- Ownership itself is not in the types. It "materializes as an `i1` SSA value"
  per buffer, with a lattice uninitialized < unique(X) < unknown ("Ownerships").
- The pass inserts `bufferization.dealloc` unconditionally at each block end.
  Canonicalization and `buffer-deallocation-simplification` fold it, with
  alias analysis ("Buffer Deallocation Simplification Pass").
- Function boundaries use a fixed ABI: arguments are never owned, results
  always are ("Function boundary ABI").
- Unknown region ops are rejected unless they implement
  `RegionBranchOpInterface` ("Limitations").

How ours differs:
- Lean-style static counts with interprocedural borrow inference (Borrow.cc).
  This is stronger than bufferization's fixed ABI.
- A runtime uniqueness test at every reset (`Runtime.cc` `exclusive`, used by
  `LowerTake`/`idris_rt_reset`), with no SSA form for "known unique". That is
  weaker than bufferization's foldable ownership indicator.

What I would do (the fuller sketch is in `mlir-ownership-types.md`):
- Make the stage a type. After rc, a value that holds a reference is
  `!idr.own<T>` when owned and plain `T` when borrowed.
- `idr.inc` becomes `%b = idr.dup %a : ... -> !idr.own<T>`, a new SSA value.
  `idr.dec` consumes an `!idr.own<T>`.
- "Consumed exactly once on every path" is then the linearity rule the
  dialect already checks for `!idr.lin`, with "at most" tightened to
  "exactly". It is a local SSA rule and needs no path interpreter.
  `idr.stage`, `inOwnedStage` and the `IncOp` special case disappear.
- Borrowedness becomes part of the function type, so `idr.borrowed` stops
  being a discardable argument attribute.
- Uniqueness becomes bufferization's indicator: an `i1` SSA value, `true` at a
  fresh `idr.con`. `idr.reset`'s runtime test consumes it, and folding removes
  the test where it is known. `idr-specialize` already clones on constant
  arguments, so a callee passed `true` gets a clone without the test. This is
  conjecture and has not been tried.
- A dialect split can come on top of this, for pass anchoring and JIT
  legality. Alone it is not enough: legality is a property of a conversion,
  not of the IR.

### 1.4 Untyped constant attributes and the `NoneType` self type: agree

Evidence:
- `IdrOps.td:107-115`: every `Idr_Attr` declares `TypedAttrInterface` and an
  `AttributeSelfTypeParameter`, but builders pin it to `NoneType`
  (`:123,135,146,156`).
- `ConstantOp::parse` reads `#idr.con<...> : T`, moves `T` to the result, then
  stores `untyped(value)`, a rebuilt attribute without it (`Ops.cc:197-208,
  229-240`).
- `isBuildableWith` actively rejects a typed one (`Ops.cc:215`).
- So the attribute claims `TypedAttrInterface` and always answers `none`.
  Every consumer supplies the type from context: `verifyConstant` passes
  field types down (`Ops.cc:264-318`), and `materializeConstant` passes the
  result type.
- The docs describe the self-type parameter as *the* way to carry the type
  (`AttributesAndTypes.md` "Attribute Self Type Parameter", 748-785). We use it
  to throw the type away.

Idiomatic fix:
- `#idr.big` and `#idr.erased` have one possible type each. They should
  implement `TypedAttrInterface::getType()` returning `!idr.big` and
  `!idr.erased`, with no parameter at all.
- `#idr.con` and `#idr.closure` should *store* their type. Nested fields and
  captures are then typed attributes too, so `verifyConstant` compares types
  instead of re-deriving them through symbol lookups (`Ops.cc:289-315`).
- `idr.constant` then looks like `arith.constant`: `$value attr-dict`, with the
  result type inferred from the attribute (`InferTypeOpInterface` or
  `AllTypesMatch`). The custom parser and printer and `untyped()` go away, and
  `isBuildableWith` becomes `cast<TypedAttr>(value).getType() == type` plus a
  kind check.
- Cost: bigger text. An `OpAsmDialectInterface::getAlias` for types keeps it
  readable.

### 1.5 Symbol-ref nominal types (`!idr.box<@L>`): disagree that this is "standard"; it fights MLIR's symbol machinery

The review says LLVM named structs do the same. They do not:
- LLVM's identified structs are *types uniqued by name that carry their body*
  (`docs/Dialects/LLVM.md:360-406`, set once through a mutable storage, as
  `AttributesAndTypes.md` "Mutable attributes and types", 1071+, describes).
  They are not references into a symbol table.
- Ours are references, and MLIR does not see references inside value types.
  `walkSymbolRefs` walks only an op's attribute dictionary
  (`lib/IR/SymbolTable.cpp:559-569`). A `!idr.data<@P>` on a result or block
  argument is invisible to `getSymbolUses`, `replaceAllSymbolUses` and
  `symbol-dce`.
- Experiment (`dce4.mlir`): make `idr.data @P` private and use it only as a
  `ub.poison : !idr.data<@P>` result. `--symbol-dce` deletes the declaration,
  and our verifier then fails with "uses an undeclared data type @P".
  - Today the declarations are public, so this never fires.
  - But then `symbol-dce` never collects a dead declaration either, and
    specialization and defunctionalization make new ones every round.
  - `verifyProgram` walks every type by hand (`Dialect.cc:237-274`) precisely
    because the symbol verifier cannot.
- Every question about a type is a linear scan. `SymbolTable::lookupSymbolIn`
  loops over the module body (`SymbolTable.cpp:397-399`).
  - 46 lookups in `lib/` do not go through a `SymbolTableCollection`.
  - They include hot folders: `TagOp::fold` and `TagOp::inferResultRanges`
    (`Ops.cc:432-446`), plus `FieldOp` and `MatchOp` lookups, and
    `mayHoldClosure` and `closureLabel` in Facts.
  - With `clone-limit=4096` the module has thousands of top-level symbols, and
    every tag fold scans them. The cost is conjecture; it is unmeasured.
- The kind is stated twice. `!idr.box` versus `!idr.data` in the type and the
  `box` unit attribute on `idr.data` must agree, and `verifyProgram` checks
  that they do (`Dialect.cc:245-250`). The representation admits the
  inconsistent state.

Idiomatic fix, in order of ambition:
1. Minimum: one `DataDecls` analysis (PassManagement.md "Analysis Management":
   `getAnalysis<>`, `markAnalysesPreserved`), a `DenseMap` from name to decl,
   ctor list and tag. Every pass and `Layouts` query it. For folders, which
   cannot reach analyses, put in the type only what they need; see 2.
2. Idiomatic: identified recursive types, as the LLVM dialect has.
   `!idr.data<"L", box, [N: (), C: (i64, !idr.data<"L">)]>` is the
   declaration. Folders and interfaces read the constructors off the type at
   O(1). The `box` flag, the tag, the symbol walk in `verifyProgram` and all
   46 lookups disappear.
   - Cost: the mutable storage is hand-written C++ (TableGen cannot declare
     mutable parameters yet), the printer must handle cycles
     (`AsmPrinter::tryStartCyclicPrint`), and Emit prints the bodies (aliases
     keep it readable). The JIT child forks, which is fine.
   - I would go here. It is the one change that removes a whole class of
     lookups and consistency rules.

### 1.6 Stripping `idr.*` attributes by prefix before translation: agree it is a smell, disagree with the proposed fix

The comment says "LLVM's translation refuses attributes of a dialect it cannot
translate" (`Lower/Pass.cc:144-145`). For op attributes that is not what the
pin does:
- `LLVMTranslationInterface::amendOperation` returns success when no
  interface is registered (`LLVMTranslationInterface.h:56-65`).
- For parameter attributes it only warns (`:78-80`).

What really forces the strip is *our own verifier*:
- `convert-func-to-llvm` copies every discardable function attribute (except
  three) onto `llvm.func` (`FuncToLLVM.cpp:72-79`), and argument attributes
  1:1 (`:396-421`).
- Our `verifyOperationAttribute` then rejects them. Experiment (`strip.mlir`,
  `strip2.mlir`): "'llvm.func' op expects idr.total as a unit attribute of a
  function".

A translation interface that ignores `idr.*` would therefore treat the wrong
layer. The idiomatic answer: every `idr` fact is either *consumed* by the
conversion, turned into what it means at LLVM's level, or it is the inherent
property of an op that disappears.
- `idr.total` on a function that cannot crash would become `will_return`.
- Cell pointers would get `llvm.nonnull`, `llvm.align`, `llvm.dereferenceable`
  (section 5).
- `idr.program` and `idr.stage` go away with 1.3 and 3.1.

Then an `idr.*` attribute that is still present after `idr-lower` means a
lowering forgot a fact, and the verifier should report it, not strip it
silently.

---

## 2. MLIR mechanisms we reimplement by hand, or leave unused

| We do by hand | MLIR has | Evidence | Weight |
|---|---|---|---|
| per-op "what happens to this operand" in 7 isa-chains | an op interface, or a custom **effect interface** with ODS operand decorators (`EffectOpInterfaceBase`, `SideEffect`: `SideEffectInterfaceBase.td:48,162`); bufferization's precedent `BufferViewFlowOpInterface` (dependencies operand → result or region argument) and `BufferizableOpInterface` (read, write, aliasing results: Bufferization.md "Extending One-Shot Bufferize") | `Ownership/Counting.cc:40-49` (readFrom), `:85-100` (useOf), `Borrow.cc:158-178`, `Stack/Escape.cc:169-200`, `Facts/Moves/Only.cc:16-41`, `Facts/Closures/Passed.cc`, `Dialect.cc:149-171` (throughLinear/readOnce) | high |
| fixpoints: borrow inference re-walks every function until nothing changes (`Borrow.cc:57-61`); escape summaries (`Escape.cc:81-94`); effects (`Infer.cc:78-90`); binding times | the DataFlow framework: sparse *backward* interprocedural analyses (`AbstractSparseBackwardDataFlowAnalysis`, which LivenessAnalysis and remove-dead-values use), `DataFlowConfig().setInterprocedural(true)`; `CallGraph` + `llvm::scc_iterator` for bottom-up SCC order | Defunctionalize already does it right (`Passes/Defunctionalize.cc:117-400`, a custom lattice anchor); the others do not | medium: correctness today, uniformity tomorrow |
| a fixed list of region ops per analysis: `isa<MatchOp, MatchLitOp, scf::WhileOp>` | `RegionBranchOpInterface`, which our matches implement fully (`Ops.cc:717-783`) | `Ownership/Verify.cc:253-261`, `Counts.cc:63-75`, `Escape.cc:36-51` | medium |
| `Tarjan` in `Passes/Scc.h` | `llvm::scc_iterator` over a `GraphTraits` adapter | 60 lines | low |
| two effect systems: MLIR `MemoryEffects` with idr resources, *and* `facts::Effects{io,crash,partial}` computed by `own()` with its own isa chain | one: effects on resources, read by resource. See 3.4 | `Facts/Moves/Only.cc`, `Idr.h:30-52` | medium |
| `RemoveUnusedCall`, a dialect canonicalizer, because `func.call` has no effects | an **external model** of `MemoryEffectOpInterface` on `func::CallOp` (Interfaces.md "External Models"), from the callee's `idr.effects`, so that DCE, CSE and LICM treat pure total calls as pure. The caveat: the effect depends on a symbol lookup and on a cache attribute that must never under-state. The alternative is an `idr.call` of our own | `Dialect/Canonicalize/Calls.cc` | medium: CSE and LICM of pure calls is a real gain (conjecture) |
| `idr-canonicalize`, a copy of `Canonicalizer.cpp`, only to count patterns | `createCanonicalizerPass(GreedyRewriteConfig{listener})` takes the same config and listener; `ApplyPatternAction` exists for tracing (`PatternApplicator.h:30`) | `Canonicalize/Pass.cc` (120 lines) | low |
| rejection recognized by the text prefix `"unsupported ("` | diagnostic **metadata** (Diagnostics.md "Metadata", `Diagnostics.h:288-289`): attach `#idr.rule<...>` to the error, and the handler reads it | `idris-mlir-cc.cc:371-378`; C++ sites `Specialize/Clones.cc:89`, `Passes/Simplify.cc:97` | low; makes the reason typed |
| `InferIntRangeInterface` implemented on 5 ops, consumed by nothing | `int-range-optimizations`, `arith-unsigned-when-equivalent`, `arith-int-range-narrowing` (Arith `Passes.td:31-72`) | see 5.1: it works once run | high value, low cost |
| a `ConfinedAttr`-able bound checked in C++ or nowhere | `ConfinedAttr<I64Attr, [IntNonNegative, IntMaxValue<N>]>` (Operations.md "Confining attributes", 295-343) | `idr.field` index, a box's constructor count | low |
| `!idr.token`, whose producer is checked by `getDefiningOp` in the verifier | the builtin **`token` type** (LangRef "Token Type" 750-776, `docs/Tokens.md`): "you can always walk back from a use and say this token came from that specific op"; ODS adds `TokenProducerTrait` and `TokenConsumerTrait`; tokens cannot be forwarded | `Ownership/Verify.cc:237-251` reads `made->getAttrOfType<SymbolRefAttr>("ctor")` by string name | medium: the check becomes structural |
| `idr.stack`'s slot built in the entry block, with the loop-iteration rule in the escape analysis | `AutomaticAllocationScopeResource`, the `AutomaticAllocationScope` trait, and `memref.alloca_scope` (`MemRefOps.td:422`) delimit an alloca's lifetime structurally | `Stack/Cell.cc`, `Escape.h:31-39` | medium (3.3) |

Already idiomatic, keep:
- **Actions and debug counters**: `Support/Actions.h`, and `--no-eval` as an
  action handler (`idris-mlir-cc.cc:424-438`).
- **Remarks, statistics and timing.**
- **`verifySymbolUses`** for symbol checks.
- **`RegionBranchOpInterface`** on matches, with `getEntrySuccessorRegions` and
  `getRegionInvocationBounds`, which SCCP and DeadCodeAnalysis use.
- **The sparse dataflow in defunctionalization.**
- **`replaceOpWithMultiple` 1:N conversion.**
- **`ConstantLike` with `materializeConstant`.**
- **DRR for the 8 output-fusion patterns.** PDLL (PDLL.md "Why build a new
  language...") would buy nothing at this size. The one improvement is to
  replace the `CPred` type checks (`Canonicalize.td:10-13`) with ODS type
  constraints on the matched operand.
- The **Transform dialect** and **IRDL** have no role here. We have no
  schedules to script, and our dialect is static ODS.

---

## 3. Fragile or non-idiomatic places, and the representation that removes them

**3.1 Whole-program invariants hang off discardable module attributes.**
- `idr.program`, a unit attribute that exists to trigger `verifyProgram`, and
  `idr.stage` both run their verifier before the ops
  (Operations.md "Verification Ordering").
- They are re-run on the whole module after every pass. The verifiers have to
  be defensive: `Verify.cc:7-8`, and `Counting.cc:27-29`, "the provisional
  answer only guards a module the verifier has yet to reject".
- The MLIR home for "check the body after its ops are verified" is a
  `hasRegionVerifier` (or `verifyRegionTrait`) on an op we own. That is either
  a container op (`spirv.module` restricts its body the same way) or an
  `idr.func`. With 1.3's types, most of the stage rule becomes local op
  verification anyway.

**3.2 The stack mark changes an op's meaning through a discardable attribute.**
- `ConOp::getEffects` picks its resource from `hasAttr("idr.stack")`
  (`Ops.cc:334-342`). `ResetReuse.cc:74,123` and `Stack/Cell.cc:13` read the
  same string.
- A pattern that rebuilds an `idr.con` drops the mark. That is safe today
  (heap instead of stack).
- The mark's soundness also depends on no later pass inlining or duplicating
  the con into a loop or another frame. The escape analysis bakes in
  `idr-tail-loops`' future behaviour (`Escape.h:31-39`). That is pass-order
  coupling held in an attribute.
- Representation: placement as IR, the way `memref.alloca` and `memref.alloc`
  are two ops. A `%slot = idr.frame_cell @T::@C` in the entry block (the
  resource `AutomaticAllocationScopeResource`), and `idr.con ... in %slot`.
  The slot is then a value that passes can see and must respect.

**3.3 Linearity has two encodings and two special cases.**
- The world is linear "by its own rule" (`quantityOf`, `Dialect.cc:138-142`;
  `LinType::verify` forbids `!idr.lin<!idr.world>`).
- A closure that captures a linear value is checked by a special rule in
  `ClosureOp::verify` (`Ops.cc:794-809`): "its one use must apply it or enter
  it into a linear type". The representation fix is that such an
  `idr.closure` *returns* `!idr.lin<!idr.fn<...>>`. The generic linearity
  check then covers it, and the special case goes.

**3.4 The effect resources say less than they could.**
- Every writer of `CrashResource` or `DivergenceResource` also writes
  `IOResource` (`Idr.h:97-108`, `IdrOps.td:444-446`). Nothing reads the first
  two.
- The pinned MLIR has a resource hierarchy: `getParent`, `isSubresourceOf`,
  `isDisjointFrom` and `isAddressable` (Rationale/SideEffectsAndSpeculation.md
  "Resource hierarchy and scope"; `SideEffectInterfaces.h:131-153`).
- Declare Crash and Divergence as children of IO, and every op writes one
  resource. `LinResource` should be non-addressable. Today its parent is
  `DefaultResource`, so a `lin.enter` looks like a heap allocation to every
  analysis.
- Then `facts::own()` can read IO, crash and partial off the effects by
  resource. The `PerformsIO` trait and the isa chain in `Moves/Only.cc` go
  away.

**3.5 Types are recognised by dialect namespace string** in the lowering's
converter (`Lower/Pass.cc:102`). Use `isa<...>` over our types, or a type
interface (`RuntimeLayoutTypeInterface`: components and counted) implemented
by each idr type. `Layouts::components` and `counted` are exactly that
interface's methods.

**3.6 The runtime-call lowering keeps a hand list of 35 ops**
(`Lower/Patterns.cc:444-451`) next to the `Idr_CallsRuntime` trait that marks
them. The declared `RuntimeCallOpInterface` (`IdrOps.td:206-213`) is never
queried. One `OpInterfaceConversionPattern<RuntimeCallOpInterface>` makes the
interface load-bearing and the list disappears.

**3.7 `idr.match`'s default region is positional.** "Region i < cases.size()
is case i; one more is the default" (`IdrOps.td:345`) is checked by a count in
the verifier (`Ops.cc:573`). `scf.index_switch`, which the comment cites,
declares `$defaultRegion` separately from `VariadicRegion $caseRegions`. The
case list could also be a typed array (`FlatSymbolRefArrayAttr`) instead of
`ArrayAttr` with an `isa` loop (`Ops.cc:576-581`).

---

## 4. What carries no weight (the coordinator's addendum)

**Dead:**
- `quantities` on `idr.ctor` (1.1).
- The comment naming `idr.spec_caller` and `idr.spec_stopped`
  (`Lower/Pass.cc:149-150`).
- The JIT branches of `LowerReset`, `LowerInc` and `LowerDec`
  (`Lower/Counting.cc`). `idr-eval` runs only inside `idr-simplify`, before
  `idr-rc`, so owned ops never reach JIT lowering. They are defensive at best.

**Decorative (declared, never consumed):**
- `RuntimeCallOpInterface` (3.6).
- The `NoneType` self-type parameter on all four constant attributes (1.4).
- `CrashResource` and `DivergenceResource` as distinct resources (3.4).
- `InferIntRangeInterface` on `idr.tag`, `to_char`, `str.length`,
  `double_head` and `int_head`. No pass in the pipeline reads ranges; `sccp`
  does not (5.1).
- `ApplyOp`'s `arg_attrs` and `res_attrs`. `CallOpInterface` mandates them;
  nothing sets them. That is acceptable.

**Redundant, with a verifier rule to keep the copies consistent** (the
representation admits a bad state):
- `idr.ctor`'s `tag`: `DataOp::verify` forces it to equal the constructor's
  index (`Ops.cc:164-176`). Drop the attribute and derive it.
- `idr.data`'s `box` flag against `!idr.box` or `!idr.data` in every use
  (`Dialect.cc:245-250`).
- `idr.stage = "owned"`: a string with one legal value.
- `PerformsIO` against `MemRead/MemWrite<IOResource>` on the same ops
  (`IdrOps.td:805-808`).
- Two copies of the cell header packing (1.2).

**Accepted without meaning:**
- Any unprefixed discardable attribute on any op but the module (1.1).
- `AnySignlessInteger` on `idr.div`, `mod`, `to_char`, `put_int` and
  `match_lit`. Experiment (`odd.mlir`): `idr.div signed %a, %b : i7`
  verifies. No Idris type is `i7`, and constructor fields are restricted to
  8, 16, 32 and 64 (`isFieldType`, `Dialect.cc:121-128`), but op operands are
  not. Use `Idr_Int` (`IdrOps.td:101`) everywhere.
- `idr.constant`'s `AnyAttr:$value`, narrowed only in C++.

**Load-bearing, confirmed:**
- **Types:** data, box, fn, erased, str, big, world, lin, token.
- **Constant attributes:** con, closure, big, erased.
- **Enums:** `CmpPredicate` and the effect enum.
- **`MayCrashOpInterface`**, read by Facts.
- **`LinResource`**: it stops CSE from merging two linear entries, and
  `Expect/Allocation.cc` reads it.
- **`idr.data closures`**, read by Facts.
- **Specialization keys and `#idr.clone`**: caches whose loss is safe. The
  self-reference in `#idr.clone` is a deliberate barrier against SCCP and DCE
  (`IdrOps.td:1008-1013`).
- **`idr.effects` and `idr.total`**: absent means "may do anything", so
  dropping one is safe but pessimizes.

---

## 5. Richness flattened too early

Each of these is a place where Idris knows more than the IR keeps.

1. **Nat-like types, `Fin n` included, become `BigT`, identical to `Integer`**
   (`compiler/src/IdrisMLIR/Frontend/Translate/Types.idr:207-265`, `Types.idr:104`;
   `IdrOps.td:79-81` "an Integer, or a Nat-like value").
   - Non-negativity is lost.
   - For `Fin k` with `k` static after monomorphisation, so is the bound `k`.
     A `Fin 5` could be an `i8` in `[0,5)`, not a GMP-backed big.
   - Representation: `!idr.nat` (non-negative big), and bounded integers for
     `Fin` with a static bound. This is conjecture about frequency.
2. **`Char` becomes `i32`** (`Emit/Types.idr:20`). Its range
   `[0, 0x10FFFF] \ surrogates` survives only when a `to_char` produced it.
3. **Erased values become one constant, `#idr.erased`.** A quantity-0 index
   (`Vect n`'s `n`, `Fin n`'s `n`) is gone as a value. It could survive as a
   ghost SSA value: compile-time only, deleted by the lowering, and usable by
   range and bounds reasoning. AGENTS.md says "erased does not mean constant";
   the dialect makes every erased value one `ConstantLike` constant. This is an
   open question, not a claim.
4. **Idris's size-change graphs reach the frontend and stop there.**
   `Frontend/Translate/Recursion.idr` reads them only to reject polymorphic
   recursion. MLIR re-derives "decreasing" parameters by abstract
   interpretation (`Specialize/BindingTimes.h`). Carrying Idris's proved
   measure would make the specializer's decreasing class a fact, not a guess.
   It has to survive specialization, so it must be re-checked or re-derived
   after clones. Conjecture on gain.
5. **Function-level facts are discardable attributes on `func.func`**:
   `idr.total`, `idr.effects`, `idr.borrowed`. The closure type `!idr.fn`
   carries neither totality nor effects. So applying an unknown closure is
   always "may do anything", even when every Idris function of that type is
   total and pure. Putting effects and totality in `!idr.fn` would let
   `canMoveAcross` and `canEvaluate` judge an apply by its type.
6. **`Lazy` and `Inf` are `!idr.fn<() -> (a)>`** (`IdrOps.td:60`,
   `Emit/Types.idr:32`). Delay and codata are indistinguishable from a
   nullary closure. Whether that loses optimizations (memoization,
   productivity) is an open question.

---

## 6. What MLIR offers for the rich-data optimizations

### 6.1 IntegerRangeAnalysis (Int, Nat, Fin, Char)

- Experiment (`range2.mlir`, a function reached from the root).
  `--int-range-optimizations` folds these to `true`:
  - `idr.tag %l : !idr.box<@L>`, then `cmpi ult, %t, 2`;
  - `idr.to_char`, then `cmpi slt, %ch, 0x110000`.

  Our interface implementations work. They are just never run.
- Upstream seeds ranges for *region arguments* through the op's
  `InferIntRangeInterface` (`IntegerRangeAnalysis.cpp:115-147`). Two
  consequences follow.
  - `idr.match` can give the integer fields a case binds a range, once
    fields have ranged types.
  - If `idr.match_lit`'s default region received the refined scrutinee as a
    block argument (the value is known to differ from the case keys), the
    analysis could use it. Today it cannot: IntegerRangeAnalysis is not
    path-sensitive.
- `IntegerRangeAnalysis::setToEntryState` is an override
  (`IntegerRangeAnalysis.h:74`). A subclass can seed function parameters from
  their types (the `Fin` and `Char` of section 5).
  `populateIntRangeOptimizationsPatterns(patterns, solver)` takes our solver,
  so we can reuse upstream's rewrites with our seeding.
- Action: add `int-range-optimizations` and `arith-unsigned-when-equivalent`
  to the simplify round. Before that, fix `TagOp::inferResultRanges`' linear
  symbol lookup (1.5).

### 6.2 Ownership and uniqueness: what to take from bufferization

See 1.3 and `mlir-ownership-types.md`. In short:
- Ownership and uniqueness as SSA values that fold.
- Conservative insertion, then simplification patterns: `dup`/`drop`
  cancellation and drop of a fresh constructor. Bufferization does this with
  `bufferization.dealloc`. We currently compute the exact placement in one
  pass, and nothing simplifies `inc`/`dec` afterwards, since they are memory
  effects no generic pass touches.
- Interfaces for per-op aliasing (`BufferViewFlowOpInterface`), not isa
  chains.
- Destination-passing style (Bufferization.md) is what `idr.reuse %token` is.
  One-Shot's static in-place decision uses SSA use-def plus alias sets. Our
  equivalent is "dead after the match" plus "unique". The second half is the
  runtime test that section 1.3's indicator could fold.

### 6.3 LLVM attributes and metadata: none are emitted today

- Grepping `lib/Lower` for noalias, nonnull, range, tbaa, invariant,
  dereferenceable or alias scopes finds nothing. The only function attribute
  set is `noreturn` on the crash helpers (`Runtime.cc:67-70`).
- The pinned LLVM dialect has what we need:
  - argument and result attributes (`LLVMDialect.td:42-70`): `llvm.noalias`,
    `llvm.nonnull`, `llvm.dereferenceable`, `llvm.align`, `llvm.noundef`,
    `llvm.range`, `llvm.nocapture`, `llvm.readonly`;
  - on `llvm.func` and `llvm.call`: `memory_effects`, `will_return`,
    `no_unwind` (`LLVMOps.td:860-861, 2043-2064`);
  - on loads and stores: `invariant`, `invariantGroup`, `dereferenceable`,
    `alias_scopes`, `noalias_scopes` and `tbaa` (`LLVMOps.td:381-390`,
    `LLVMOpBase.td:269-272`).
- Mind these when setting them:
  - `func-to-llvm` carries argument attributes over only when an argument
    maps 1:1 (`FuncToLLVM.cpp:407-418`). Unboxed sums map 1:N, so set the
    attributes on each flattened component inside `idr-lower`, after the
    signature conversion.
  - `idr-prune` passes `ub.poison` for parameters a function never reads, so
    `llvm.noundef` would turn those calls into UB. Only non-poison positions
    qualify.
- Candidates, in decreasing confidence:
  - **`nonnull`, `align 8` and `dereferenceable(8)` on every `!idr.box` or
    closure pointer**, parameter or result. A box is never null: static data
    or a live cell. A *counted slot* of an unboxed sum may be null, so not
    there. This lets LLVM speculate header loads. The gain is conjecture.
  - **`llvm.range` on `i32` Char and tag values** at function boundaries.
  - **`will_return`** on functions that are total and cannot crash. A crash
    calls a `noreturn` function, which `will_return` would make UB, so only
    ¬crash qualifies.
  - **`invariant.group` on field loads and initializing stores, with
    `llvm.intr.launder.invariant.group` on the token at `idr.reuse`.** This is
    exactly C++'s placement-new discipline: Idris cells are immutable while
    referenced, and reuse is re-construction in the same storage. It would let
    GVN reuse field loads across opaque calls (`idris_rt_dec`, for instance).
    Conjecture: sound on paper, needs a benchmark.
  - **`noalias` on a parameter** that is both linear and proved unique
    (after 6.2). **TBAA** separating header words from fields only pays off
    if the runtime's inlined counting code shares our TBAA root (clang emits
    its own). Unverified, and low confidence.

---

## What it means for idris-mlir, ordered by value over cost

1. The program-wide attribute rule (1.1). Delete `quantities`, `idr.ctor`'s
   `tag` and the `box` flag (after 1.5).
2. A checked `CellInfo`, `FailureOr` layouts, and one packing (1.2).
3. Run `int-range-optimizations` in the simplify round (6.1). Then emit
   `nonnull`, `align`, `dereferenceable` and `range` in `idr-lower` (6.3).
4. Typed constant attributes (1.4).
5. One ownership and flow interface (or custom effect interface) that
   replaces the seven isa chains (section 2). The builtin `token` for reuse
   tokens.
6. The resource hierarchy (3.4). One effect system.
7. Identified recursive types in place of symbol-ref types (1.5). This is
   large; the stopgap is a `DataDecls` analysis.
8. The owned stage as types, `dup` and `drop`, and a uniqueness indicator
   (1.3, `mlir-ownership-types.md`). This is the largest item and the one that
   serves the project's aim, statically guaranteed in-place reuse, most
   directly.
9. Richness items 5.1 to 5.5 on the Idris side, each behind a measurement.

## Open questions

- Would identified types survive `idr-eval`'s fork-and-JIT and Emit's text
  contract without pain? Emit would have to print type bodies once with
  aliases.
- The cost of `verifyOwned` and `verifyProgram` per pass on the largest
  bench module. Unmeasured; `--timing` would show it.
- Is `invariant.group` sound with the runtime's free list? The free list
  writes only header words (`rc.cc:44-50`), and our field stores go through
  our lowering. It looks sound; it needs a test.
- Do MLIR's `remove-dead-values` and `sccp` treat an external-model effect on
  `func.call` as the docs promise? Worth a reduced test before relying on it.
