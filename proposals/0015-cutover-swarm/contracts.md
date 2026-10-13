# Contracts: the cutover

Every declaration a lane consumes is fixed here by name and shape. Lanes
write against this text from the first minute; the owner named in
`ownership.json` writes the file. A conflict between this file and the
live tree goes to the coordinator, who edits this file and re-dispatches
the lane. No lane resolves it.

Path roots, as `ownership.json` spells them:

- `FI` is `foreign/idr`;
- `INC` is `foreign/idr/include/idr`;
- `IDR` is `foreign/idr/lib`;
- `CS` is `compiler/src/IdrisMLIR`;
- `RT` is `runtime`;
- `T` is `tests`.

The evidence is `findings.md`, read at 25890d32. The design is
`../0014-get-back-on-track.md`; where this file is more specific, this
file is the decision. The rulings R01 to R48 (C10) are applied in the
sections they name; a lane cites a ruling by its number.

## C0. What does not change

- **The semantics.** Every program prints, exits and crashes exactly as
  before: the same bytes, the same status, the same crash message. The
  702-program corpus is byte-identical after integration, except
  programs refused for an erased value in a runtime position (C6.1),
  which the qualification lists.
- **The grades of one and of ownership.** `!idr.lin<T>`, `!idr.world`,
  `!idr.own<T>`, `!idr.excl<T>` and `!idr.q<quantity, permission, T>`
  stay types, and every pass keeps them. The quantity `zero` goes (C6.1).
- **The verifier after every pass.** No code gives `enableVerifier` or
  `verifyPasses` anything but true; no command sets `-verify-each` off.
  What changes is the level the verifier runs at (C4).
- **The runtime ABI.** `RT/idris_rt.h` is unchanged. Nothing in `RT/`
  changes in this packet.
- **The targets.** x86_64 Linux and arm64 macOS; nothing assumes either.
- **The unit size.** Every `.cpp`, `.h` or `.cc` under `FI` stays at 400
  lines or fewer unless `T/spec/file-size/allowed` lists it; a unit that
  grows past 400 is split in the same lane.
- **The pin.** Upstream signatures this packet recalls are confirmed at
  the pin by the lane that uses them; the pinned header is right, and a
  difference is reported, never patched.
- **Comments say why**, in the surrounding code's density; they cite no
  document, finding or contract.

**No compatibility is owed** (owner, 2026-10-12): the handoff text, the
dumps, every test fixture, the pass names, the tool options and the
module layout change at once. Nothing is kept for an old reader.

## C1. The hubs the coordinator writes at dispatch

### C1.1 The layout

`FI` is an in-tree MLIR dialect in upstream's layout. No C++20 module,
no partition, no `import`: headers and `.cpp`.

| Today | After | Library target |
| --- | --- | --- |
| `INC/IdrOps.td`, `INC/IdrPlatformOps.td` | `INC/IR/IdrOps.td`, `INC/IR/IdrPlatformOps.td` | `IdrOpsIncGen` |
| `INC/Passes.td` | `INC/Transforms/Passes.td` | `IdrPassesIncGen` |
| `INC/Idr.h`, `IDR/Dialect/Dialect.cppm`, `IDR/Mlir.cppm` | `INC/IR/IdrDialect.h` (the one header of the dialect: enums, attrs, types, interfaces, traits, ops), `INC/IR/Grades.h`, `INC/IR/Symbols.h`, `INC/IR/Ranges.h` | `IdrIR` |
| `IDR/Dialect/{Ops,Types,Attrs,Grades,Effects,Crashes,Canonicalize,Dialect,Symbols}`, `IDR/Ops`, `IDR/Ranges`, `IDR/Sharing` | `IDR/IR/*.cpp` | `IdrIR` |
| `IDR/Dialect/Canonicalize.td` | `IDR/IR/Canon/Canonicalize.td` (U17) | `IdrIR` (`IdrCanonicalizeIncGen`) |
| `IDR/Dialect/Verify`, `IDR/Verify`, `IDR/Ownership/Verify.cppm` | `IDR/IR/Func/*.cpp`, `IDR/IR/Verify/*.cpp`, `INC/IR/Func.h`, `INC/IR/Verify.h` | `IdrIR` |
| `IDR/Ownership/{Ops.cc,OpChecks.cppm}` | `IDR/IR/OpsOwnership.cpp` (U01) | `IdrIR` |
| `IDR/Ownership/{Checker,References,Loops,UseOf,IsStatic,ReadFrom,ReachesOnlyAtoms,InOwnedStage}.cppm` | `IDR/IR/Verify/*.cpp`, `INC/IR/Ownership.h` (U02) | `IdrIR` |
| `TypeGraph` (`IDR/Verify/Cycles.cppm:31`) | `IDR/IR/TypeGraph.cpp`, `INC/IR/TypeGraph.h` (U03) | `IdrIR` |
| `IDR/Canon` | `IDR/IR/Canon/*.cpp`, `INC/IR/Canon.h` | `IdrIR` |
| `IDR/Fold` | `IDR/IR/Fold/*.cpp`, `INC/IR/Fold.h` | `IdrIR` |
| `IDR/Layout` | `IDR/IR/Layout/*.cpp`, `INC/IR/Layout.h` | `IdrIR` |
| `IDR/Graph` | `References.cppm` to `IDR/Analysis/References.cpp`, `INC/Analysis/References.h` (IdrAnalysis, U03); `Scc.cppm` to `IDR/Support/Scc.cpp`, `INC/Support/Scc.h` (IdrSupport, U03); `InTailPosition`, `InTailPositionModuloConstructor`, `PassesOnPrevious`, `IsSelfCall`, `ModuloAt` to `IDR/Analysis/Tail.cpp`, `INC/Analysis/Tail.h` (IdrAnalysis, U09); `SymbolUses` goes (`mlir::SymbolUserMap`); `FieldsOf` to a static of `IdrTail`; `Trips` to `INC/Transforms/Narrow.h` (U11); `RefersTo` goes (`References`) | `IdrAnalysis`, `IdrSupport` |
| `IDR/Facts` (but `Pass.cc`) | `IDR/Analysis/{Effects,Holds}.cpp`, `INC/Analysis/{Effects,Holds}.h` (U03); what an op answers goes with the op (`CallOp::getEffects`, U02; `FuncOp::absorb`, C1.2) | `IdrAnalysis` |
| the analyses of each pass (C2.1's first table) | `IDR/Analysis/<Name>.cpp`, or the directory `IDR/Analysis/<Name>/` where one is split, `INC/Analysis/<Name>.h` | `IdrAnalysis` |
| `IDR/Narrow/Naturals.cppm` (the seeded solver) | `IDR/Analysis/Ranges.cpp`, `INC/Analysis/Ranges.h` (U11) | `IdrAnalysis` |
| `IDR/Simplify`, `IDR/Canonicalize` | `IDR/Transforms/Simplify/*.cpp`, `INC/Transforms/Simplify.h` | `IdrSimplify` |
| `IDR/Inline`; `ForceOfOneConstant` and `ForceAtCapture` (`IDR/Dialect/Ops/Lazy.cc:96`, `:170`) | `IDR/Transforms/Inline/*.cpp`, `INC/Transforms/Inline.h` | `IdrInline` |
| `IDR/Specialize` | `IDR/Transforms/Specialize/*.cpp`, `INC/Transforms/Specialize.h` | `IdrSpecialize` |
| `IDR/Defunctionalize` | `IDR/Transforms/Defunctionalize/*.cpp`, `INC/Transforms/Defunctionalize.h` | `IdrDefunctionalize` |
| `IDR/Ownership` (but the files of the `IdrIR` rows above) | `IDR/Transforms/Ownership/*.cpp`, `INC/Transforms/Ownership.h`; the analyses in `IDR/Analysis/Ownership/{Values,Uses,Borrows,Reuses,Exclusivity}.cpp`, `INC/Analysis/Ownership.h` (U08) | `IdrOwnership`, `IdrAnalysis` |
| `IDR/Tail` | `IDR/Transforms/Tail/*.cpp`, `INC/Transforms/Tail.h` (which holds `Returned`) | `IdrTail` |
| `IDR/Narrow` | `IDR/Transforms/Narrow/*.cpp`, `INC/Transforms/Narrow.h` | `IdrNarrow` |
| `IDR/InBounds` | `IDR/Transforms/InBounds/*.cpp`, `INC/Transforms/InBounds.h` (which holds `Lengths`) | `IdrInBounds` |
| `IDR/Stack`, `IDR/Identity`, `IDR/Isolate`, `IDR/Demand` | `IDR/Transforms/{Stack,Identity,Isolate,Demand}/*.cpp`, `INC/Transforms/{Stack,Identity,Isolate,Demand}.h` | `IdrSmallPasses` |
| `IDR/Vectorize` | `IDR/Transforms/Vectorize/*.cpp`, `INC/Transforms/Vectorize.h` | `IdrVectorize` |
| `IDR/Expect` | `IDR/Transforms/Expect/*.cpp`, `INC/Transforms/Expect.h` | `IdrExpect` |
| `IDR/Facts/Pass.cc` (idr-effects) | `IDR/Transforms/Effects/*.cpp`, `INC/Transforms/Effects.h` | `IdrEffects` |
| `IDR/Lower`, `IDR/Target` | `IDR/Conversion/*.cpp`, `INC/Conversion/*.h` (`TailCallPlan.h` among them), `IDR/Target/*.cpp`, `INC/Target/Target.h` | `IdrConversion`, `IdrTarget` |
| `IDR/Dialect/Registration/{PipelineSteps,RegisterIdrPipeline}.cc` | `IDR/Transforms/Pipeline.cpp`, `INC/Transforms/Pipeline.h` | `IdrPipeline`, declared in `IDR/Transforms/CMakeLists.txt` |
| `IDR/Support` | `IDR/Support/*.cpp`, `INC/Support/*.h` | `IdrSupport` |
| `IDR/Driver` | `IDR/Driver/*.cpp`, `INC/Driver/*.h` | `IdrDriver` |
| `IDR/TracySampling.h` | `INC/Support/ProfileSampling.h` | `IdrSupport` |

Rules of the layout:

- **Headers.** Every public declaration is in one header under `INC`,
  in namespace `idr` or `idr::<area>`. A library's units share
  declarations through its one area header (`INC/Transforms/<Area>.h`,
  `INC/Conversion/*.h`, the `INC/IR` headers for `IdrIR`'s areas), which
  may declare library-internal classes in the area's namespace. A class
  private to one analysis whose `.cpp` is split may be nested in the
  public class in its header. No header sits beside a `.cpp`. Private
  helpers are `static` or in an anonymous namespace in their `.cpp`.
- **Pass declarations.** No header defines `GEN_PASS_DECL` or
  `GEN_PASS_REGISTRATION` bare: each area header includes
  `idr/Transforms/Passes.h.inc` with `GEN_PASS_DECL_<its passes>`,
  `INC/Transforms/Pipeline.h` with `GEN_PASS_REGISTRATION`, and
  `IdrDialect.h` with neither.
- **The dialect's registration.** `IdrDialect::initialize` (U01) adds the
  dialect's types, attributes and ops, `idr::addInlinerInterface` (U02)
  and the asm interface. `registerIdr` and `registerCallEffects` go; the
  driver and the tools insert `idr::IdrDialect` themselves (C5).
- **Actions.** `INC/Support/Actions.h` (U14):
  `idr::support::TaggedAction<Derived>`, `printTag`,
  `perform<A>(Operation *, function_ref<void()>) -> bool`. The two
  actions of specialization (`idr-raise`, `idr-specialize-clone`) are
  U06's, in `INC/Transforms/Specialize.h`.
- **Includes.** Every `.cpp` that names a symbol of the dialect includes
  `idr/IR/IdrDialect.h` first among ours, then its area's `idr/`
  headers, then the MLIR and LLVM headers it uses, by name. A unit that
  names nothing of the dialect (`IdrSupport`, most of `IdrDriver`) does
  not include it. Nothing includes a header for its transitive effect.
- **Links.** A library links exactly the libraries whose headers it
  includes and the libraries that define the generated pass constructors
  it declares from `idr/Transforms/Passes.h.inc` (U04's `Round.cpp`).
  `IdrSupport` includes no header of the dialect, so `IdrIR` may link it.
- **CMake.** Each library is one `add_mlir_library`
  (`add_mlir_dialect_library` for `IdrIR`). Every list is the
  **coordinator's**, filled from the unit lists each lane reports:
  - `INC/IR/CMakeLists.txt`: the generated `IdrEnums`, `IdrAttrs`,
    `IdrDialect`, `IdrInterfaces`, `IdrTypes` and `IdrOps`, as `.h.inc`
    and `.cpp.inc` under `include/idr/IR` (`IdrOpsIncGen`);
  - `IDR/IR/CMakeLists.txt`: `IdrIR` from every `.cpp` under `IDR/IR`; a
    PUBLIC link of `idris_rt` with `runtime/` on its interface include
    path; `IDRIS_MLIR_TARGET_TRIPLE` as `FI/CMakeLists.txt:61` defines
    it; dependencies on `IdrOpsIncGen` and on `IdrCanonicalizeIncGen`,
    the `mlir_tablegen(IdrCanonicalize.inc -gen-rewriters)` rule over
    `IDR/IR/Canon/Canonicalize.td` (U17); a link of `IdrSupport` for
    `Scc`;
  - `IDR/Analysis/CMakeLists.txt`: `IdrAnalysis` from every `.cpp` under
    `IDR/Analysis`, subdirectories included;
  - `IDR/Transforms/CMakeLists.txt`: one library per area subdirectory,
    and `IdrPipeline` from `Pipeline.cpp`; `IdrVectorize` depends on
    `IdrPassesIncGen` and links `IdrIR`;
  - `IDR/Support/CMakeLists.txt`: `IdrSupport`;
  - `IDR/Target/CMakeLists.txt`: `IdrTarget`, keeping
    `IDRIS_MLIR_TARGET_TRIPLE` and `IDRIS_MLIR_TARGET_CPU`;
  - `IDR/CMakeLists.txt`: `IdrConversion`; `IdrDriver` with the four
    definitions of `FI/CMakeLists.txt:316-321` plus the triple and the
    CPU, and `idr/TargetEntry.h`, `idris_rt.h` and `cpu_features.h` on
    its include path.

  No other `CMakeLists.txt` exists under `IDR`: none under
  `IDR/Transforms/<Area>` or `IDR/Analysis/<x>`. An old area's
  `CMakeLists.txt` is deleted by the lane that deletes the area:

  | Lane | Deletes the `CMakeLists.txt` of |
  | --- | --- |
  | U01 | `IDR/Ops`, `IDR/Ranges`, `IDR/Sharing` |
  | U02 | `IDR/Verify` |
  | U03 | `IDR/Graph`, `IDR/Facts` |
  | U04 | `IDR/Simplify`, `IDR/Canonicalize` |
  | U05 | `IDR/Inline` |
  | U06 | `IDR/Specialize` |
  | U07 | `IDR/Defunctionalize` |
  | U09 | `IDR/Tail` |
  | U10 | `IDR/Lower`, `IDR/Layout` |
  | U11 | `IDR/Narrow` |
  | U12 | `IDR/InBounds` |
  | U13 | `IDR/Stack`, `IDR/Identity`, `IDR/Isolate`, `IDR/Demand` |
  | U14 | `IDR/Driver` |
  | U15 | `IDR/Expect` |
  | U16 | `IDR/Fold`, `IDR/Vectorize` |
  | U17 | `IDR/Canon` |
  | coordinator | `IDR/Dialect`, `IDR/Ownership` (each emptied by several lanes) |

- **Unit size.** 400 lines per `.cpp`, `.h` and `.cc`.
- **State.** Nothing under `FI` is `thread_local`, `static` mutable or
  `std::atomic`, except three: the dialect's `foldLeak` counter (kept,
  C1.2), the command-line option objects (`cl::opt`, `cl::list`) of the
  driver and the tools, and a `TaggedAction`'s function-local
  `SelfOwningTypeID`, a constant identity (C2.0).

### C1.2 `INC/IR/IdrOps.td`: what the coordinator adds and removes

**Removed.** From the dialect's `discardableAttrs` list every entry but
`program` and `stack` (it becomes
`let discardableAttrs = (ins "::mlir::UnitAttr":$program, "::mlir::UnitAttr":$stack);`),
and `Idr_KnownAttributes` with `verifyDiscardableAttrs`, the quantity
`Zero` of `Idr_Quantity`, `Idr_ErasedAttr`, and the dialect's
`extraClassDeclaration` members for published scopes and memos
(`publishedScopes`, `publishedScopeOwner`, `publishedMemos`,
`publishedMemoOwner`). `foldLeak` stays.

**The dialect's dependencies.** `dependentDialects` become `arith`,
`cf`, `ub` and `LLVM`: no idr op or pattern makes a `func` op, and the
inliner's block form of `idr.return` makes a `cf.br` (C3.3).

**Added, under a new section "Functions".**

```tablegen
// The function of a monomorphic program, and what is known of it: what
// Idris proved (total), what the passes find (effects, no_inline,
// break_last) and what it is an instance or a clone of. Each is inherent,
// so no pass drops one without changing the op, and every reader uses the
// generated accessor. Its region verifier owns the rules of one function:
// every linear value used once on every path, and the owned stage's
// counting; its verifier checks the clone fact's shape.
// effects absent means the function may do anything; no writer stores the
// full set io, crash, diverge: it removes the attribute.
def Idr_FuncOp : Idr_Op<"func", [AffineScope, AutomaticAllocationScope,
    FunctionOpInterface, IsolatedFromAbove, OpAsmOpInterface]> {
  let summary = "a function of the program, with the facts known of it";
  let arguments = (ins SymbolNameAttr:$sym_name,
                       TypeAttrOf<FunctionType>:$function_type,
                       OptionalAttr<StrAttr>:$sym_visibility,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs,
                       UnitAttr:$total, UnitAttr:$break_last, UnitAttr:$no_inline,
                       OptionalAttr<Idr_EffectAttr>:$effects,
                       OptionalAttr<Idr_InstanceAttr>:$instance,
                       OptionalAttr<Idr_CloneAttr>:$clone);
  let regions = (region AnyRegion:$body);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let extraClassDeclaration = [{
    static StringRef getDefaultDialect() { return "idr"; }
    ::mlir::Region *getCallableRegion() { return isExternal() ? nullptr : &getBody(); }
    ::llvm::ArrayRef<::mlir::Type> getArgumentTypes() { return getFunctionType().getInputs(); }
    ::llvm::ArrayRef<::mlir::Type> getResultTypes() { return getFunctionType().getResults(); }
    ::mlir::Type cloneTypeWith(::mlir::TypeRange inputs, ::mlir::TypeRange results) {
      return ::mlir::FunctionType::get(getContext(), inputs, results);
    }
    bool isExternal() { return getBody().empty(); }
    // A body that takes in a callee without Idris's proof of termination
    // loses its own: what inlining and contification record.
    void absorb(FuncOp callee) { if (!callee || !callee.getTotal()) setTotal(false); }
  }];
}

// A call of a function by name. What it may do is its own effects: the
// callee's, joined with what the closures it is given may do when applied,
// written by idr-effects each round; a call without one may do anything.
// The callee's effects is the authority: verifySymbolUses refuses a call
// whose effects does not contain its callee's. It takes over an argument
// the callee's parameter owns: consumesOperand reads the operand's type,
// which verifySymbolUses makes the parameter's.
def Idr_CallOp : Idr_Op<"call", [CallOpInterface,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<Idr_ConsumingOpInterface, ["consumesOperand"]>]> {
  let summary = "a call of a function by name";
  let arguments = (ins FlatSymbolRefAttr:$callee, Variadic<AnyType>:$args,
                       OptionalAttr<DictArrayAttr>:$arg_attrs,
                       OptionalAttr<DictArrayAttr>:$res_attrs,
                       OptionalAttr<Idr_EffectAttr>:$effects);
  let results = (outs Variadic<AnyType>:$results);
  let assemblyFormat = [{
    $callee `(` $args `)` attr-dict `:` functional-type($args, $results)
  }];
  let extraClassDeclaration = [{
    ::mlir::CallInterfaceCallable getCallableForCallee() { return getCalleeAttr(); }
    void setCalleeFromCallable(::mlir::CallInterfaceCallable callee) {
      setCalleeAttr(::llvm::cast<::mlir::FlatSymbolRefAttr>(::llvm::cast<::mlir::SymbolRefAttr>(callee)));
    }
    ::mlir::Operation::operand_range getArgOperands() { return getArgs(); }
    ::mlir::MutableOperandRange getArgOperandsMutable() { return getArgsMutable(); }
  }];
}

def Idr_ReturnOp : Idr_Op<"return", [Idr_ConsumesOnly<"0">, HasParent<"FuncOp">,
    ReturnLike, Terminator]> {
  let summary = "returns from a function";
  let arguments = (ins Variadic<AnyType>:$operands);
  let assemblyFormat = "attr-dict ($operands^ `:` type($operands))?";
  let hasVerifier = 1;
}
```

`idr.func`'s body holds several blocks only after the inliner takes in
a callee that ends in `ub.unreachable`, until `canonicalize` erases the
unreachable block; `idr.return` ends a block of the body. A pass that
lists the returns of a function reads the terminators of the body's
blocks.

```tablegen
// What a function or a data declaration is an instance of, as the frontend
// decided it: the Idris definition and the compile-time values it was
// instantiated at (types, implementations, shapes), each the
// alpha-normalized text the frontend prints. Names, not symbol uses, as
// the specialization keys are: an instance keeps no function alive, refers
// to none and follows no rename. The readable symbol is this key printed;
// no pass reads it.
def Idr_InstanceAttr : AttrDef<Idr_Dialect, "Instance"> {
  let mnemonic = "instance";
  let summary = "the Idris definition and arguments a function or data type is an instance of";
  let parameters = (ins "::mlir::StringAttr":$origin, "::mlir::ArrayAttr":$arguments);
  let assemblyFormat = "`<` $origin `,` $arguments `>`";
  let genVerifyDecl = 1;
}
```

It prints `#idr.instance<"Prelude.Show.show", ["Prelude.Types.Nat"]>`.
Its verifier checks that every argument is a `StringAttr` (U01,
`IDR/IR/Attrs.cpp`). No symbol reference is anywhere in it, so it is no
symbol use to `symbol-dce`, `remove-dead-values`, `getSymbolUses`,
`SymbolUserMap` or `References`.

`Idr_CloneAttr` is unchanged and moves from `discardableAttrs` to the
`clone` argument above. `Idr_EffectAttr` is unchanged; it is the
`effects` of `idr.func` and of `idr.call`.

**Added to existing ops.**

- `Idr_DataOp` gains `OptionalAttr<Idr_InstanceAttr>:$instance` and
  prints it as ``(`instance` $instance^)?`` after `labels`.
  `Idr_DataOp`'s verifier refuses a box with more constructors than the
  runtime's tag limit (`IDRIS_RT_TAG_LIMIT`, `RT/idris_rt.h:106`), with
  today's `unsupported (layout)` text, at parse (U01).
- `OpAsmOpInterface` with `getAsmResultNames` is declared on
  `Idr_ConstantOp`, `Idr_ConOp`, `Idr_ClosureOp`, `Idr_SuspendOp`,
  `Idr_LambdaOp`, `Idr_DelayOp`, `Idr_LinEnterOp`, `Idr_ForceOp`,
  `Idr_ApplyOp` and `Idr_CallOp`; `getAsmBlockArgumentNames` on
  `Idr_MatchOp` suggests `f0`, `f1`, ... and reads no declaration. The names
  are C7.1's.
- `Idr_QType` is unchanged but for its traits (below); the spellings
  table stays and loses `!idr.erased`.
- `DeclareTypeInterfaceMethods<OpAsmTypeInterface, ["getAsmName"]>` is
  declared on `Idr_WorldCarrier` (`w`), `Idr_StrType` (`s`),
  `Idr_BigType` (`n`), `Idr_NatType` (`n`), `Idr_FnType` (`f`),
  `Idr_LazyType` (`lazy`), `Idr_TokenType` (`tok`) and `Idr_QType`,
  whose `getAsmName` forwards to its carrier's.
- `DeclareOpInterfaceMethods<SymbolUserOpInterface>` on `Idr_ForceOp`,
  `Idr_StrPackOp`, `Idr_StrConcatOp` and `Idr_PutListOp`: their
  declaration checks are symbol-use rules (C4). Their `verify()` keeps
  what the op's own types say.
- `Idr_ForceOp` gains `hasFolder`; `Idr_DelayOp` gains
  `hasCanonicalizer`. The fold returns the yielded value of an evaluated
  delay when the types are equal; the canonicalization moves a body that
  is only constants and `idr.con` of non-linear values from above out
  before the delay (C2.4). `ForceOp::getCanonicalizationPatterns`
  registers `ForceOfOneUse` and `ForceInOneCase` only (C3.3).
- `Idr_YieldOp`'s `ParentOneOf` is unchanged. `Idr_DestWriteOp`,
  `Idr_DropOp` and the other ownership ops are unchanged.

### C1.3 `INC/Transforms/Passes.td`: the passes and their anchors

Every pass keeps its name where its meaning is kept. The anchor column
is the contract: a `FuncOp` pass runs under a nested pass manager and may
touch nothing outside its function (C2.0).

| Pass | Anchor | Notes |
| --- | --- | --- |
| `idr-isolate` | `ModuleOp` | outlines every `idr.lambda` and every `idr.delay` but an evaluated one; plan, then rewrite (C2.0) |
| `idr-contify` | `ModuleOp` | unchanged in meaning; the function a callee is contified into calls `absorb` (C1.2) |
| `idr-simplify` | `ModuleOp` | C3 |
| `idr-effects` | `ModuleOp` | writes `effects` on every `idr.func` from the `Effects` analysis and on every `idr.call` from its callee's and the closures it is passed |
| `idr-loop-breakers` | `ModuleOp` | writes `no_inline` from `References` |
| `idr-round-facts` | `ModuleOp` | computes `SymbolTable`, `Holds`, `Identities`, `CloneTable` and `BindingTimes` for the round's function step; rewrites nothing; preserves everything |
| `idr-identity` | `::idr::FuncOp` | reads `Identities` through the parent (`idr-round-facts`) |
| `idr-redirect` | `::idr::FuncOp` | new: a call whose key the `CloneTable` holds calls the clone (the redirect half of today's specialization); reads `CloneTable`, `BindingTimes` and `Holds` through the parent (`idr-round-facts`) and no sibling op |
| `idr-inline` | `ModuleOp` | the force preparation, then upstream `Inliner` with the MLton rule; `canonicalize,cse` only on a function an iteration inlined into (C3.3) |
| `idr-specialize` | `ModuleOp` | raising and cloning; redirects the calls it rewrites in the same run; plan, then rewrite (C2.0); writes a new clone's first facts |
| `idr-defunctionalize` | `ModuleOp` | C2.4 |
| `idr-stack` | `ModuleOp` | marks from the `Escapes` analysis; plan, then rewrite (C2.0) |
| `idr-accumulate` | `ModuleOp` | inserts the accumulator clones; plan, then rewrite |
| `idr-rc` | `ModuleOp` | owned grades from `Borrows` into signatures; runs `idr.func(idr-rc-place)`; excl grades from `Exclusivity` into signatures and call results; runs `idr.func(idr-rc-commit)`; erases unused originals; options `reuse`, `sink` |
| `idr-demand` | `ModuleOp` | option `in-place` |
| `idr-trmc` | `ModuleOp` | inserts the destination clones; plan, then rewrite |
| `idr-tail-loops` | `::idr::FuncOp` | declarations by `declarationOf`; plan, then rewrite (C2.0) |
| `idr-narrow` | `ModuleOp` | the `Ranges` analysis; versions loops; the word rewrite nested per function (`idr-narrow-words`); upstream's range passes replace nothing here |
| `idr-in-bounds` | `ModuleOp` | `Lengths` over `Ranges`; the proofs nested per function (`idr-in-bounds-prove`); `ValueBoundsConstraintSet` replaces nothing |
| `idr-lower` | `ModuleOp` | phase 0 (C2.5), then today's two phases |
| `idr-entry` | `ModuleOp` | |
| `idr-vectorize`, `idr-narrow-lanes` | `::mlir::func::FuncOp` | after lowering, functions are `func.func` |
| `idr-returned-arguments` | `ModuleOp` | the `Returned` analysis; its rewrite nested over `func.func` (`idr-returned-arguments-drop`) |
| `idr-tail-calls` | `ModuleOp` | the `TailCallPlan` analysis; its rewrite nested over `llvm.func` (`idr-tail-calls-place`) |
| `idr-expect` | `ModuleOp` | the test API |
| `idr-binding-times` | `ModuleOp` | the report |
| `idr-target` | `ModuleOp` | first in the driver's manager (C1.4) |

**Nested, unregistered passes.** These run only through their module
pass's `runPipeline`. Each is a `PassWrapper` with a `getArgument()` of
the listed name (for timing and remarks), constructed with its options
by the module pass, declared in no `.td`, registered nowhere, not
addressable by `--without`, and declaring no statistic.

| Pass | Anchor | Run by | Reads |
| --- | --- | --- | --- |
| `idr-rc-place` | `::idr::FuncOp` | `idr-rc` | `SymbolTable` and, with `reuse`, `Reuses` |
| `idr-rc-commit` | `::idr::FuncOp` | `idr-rc` | `SymbolTable`, `Exclusivity` |
| `idr-narrow-words` | `::idr::FuncOp` | `idr-narrow` | `Ranges` |
| `idr-in-bounds-prove` | `::idr::FuncOp` | `idr-in-bounds` | `Lengths`, `SymbolTable` |
| `idr-returned-arguments-drop` | `::mlir::func::FuncOp` | `idr-returned-arguments` | `Returned` |
| `idr-tail-calls-place` | `::mlir::LLVM::LLVMFuncOp` | `idr-tail-calls` | `TailCallPlan` |

The module pass keeps the statistics and counts what it reports:
`idr-rc` counts takes, reuses, dups and drops in one walk after its
nested runs; `idr-in-bounds` counts guards before and after;
`idr-narrow` keeps `versioned` only. The round's passes, which the
composite runs through `runPipeline`, keep their statistics, which
`idr-simplify`'s statistics remark reports (C3.1).

Deleted passes: `idr-canonicalize`; the round uses upstream
`canonicalize` (C3.2).

`INC/Transforms/Passes.td` declares no `let constructor`; every pass is
built by its generated constructor, with its options struct. `idr-rc`
keeps the options `reuse` and `sink`, `idr-demand` `in-place`.
`Passes.td` declares `IdrRoundFacts` and no `IdrCanonicalize`,
`IdrRcPlace` or `IdrRcCommit`; the rest of its text is R40's.

### C1.4 The pipeline (`IDR/Transforms/Pipeline.cpp`, U14)

One `PassManager`, built by constructors, never from text. The order is
today's (`IDR/Dialect/Registration/PipelineSteps.cc`), with these
changes:

```text
idr-isolate
idr-contify
idr-simplify                       -- the round, C3
idr-defunctionalize
idr.func(canonicalize)
idr-stack
idr-accumulate
idr-rc                             -- runs idr.func(idr-rc-place) and idr.func(idr-rc-commit) itself
idr-demand
idr-trmc
idr.func(idr-tail-loops)
idr-narrow                         -- runs its word rewrite nested
idr-in-bounds                      -- runs its proofs nested
idr-lower
idr-entry
func.func(idr-vectorize, idr-narrow-lanes, convert-linalg-to-loops, canonicalize, cse)
idr-returned-arguments             -- runs its rewrite nested over func.func
func.func(canonicalize, cse, convert-vector-to-scf, expand-strided-metadata, lower-affine, convert-scf-to-cf)
convert-vector-to-llvm
convert-to-llvm
reconcile-unrealized-casts
idr-tail-calls                     -- runs its rewrite nested over llvm.func
```

The nested managers are `pm.nest<idr::FuncOp>()` before lowering and
`pm.nest<func::FuncOp>()` after it; the `llvm.func` nest is inside
`idr-tail-calls`. The five anchorless upstream lowering passes
(`convert-linalg-to-loops`, `convert-vector-to-scf`,
`expand-strided-metadata`, `lower-affine`, `convert-scf-to-cf`) run per
function; one that declares a module anchor at the pin stays on the
module and U14 reports it.

The driver's one manager runs `idr-target` first, then this pipeline;
`--idr-pipeline` is this pipeline without `idr-target`. `--without`
names top-level steps (and the options `reuse`, `sink`, `in-place`); the
round's passes and the nested passes of C1.3 are not named by it.
`--dump-dir` writes after each top-level pass, a top-level pass being
one added to the driver's manager itself: passes run through
`runPipeline` and nested managers' passes do not dump, and the depth is
counted with `runBeforePipeline` and `runAfterPipeline`. A nested
group's dump is named after the first pass it ran, numbered from 01
with two digits and no gap, and a group that ran nothing writes no
file. Dumps print with
`OpPrintingFlags().enableDebugInfo().printNameLocAsPrefix()` and
aliases. Every pass uses its generated constructor (no
`let constructor`). The loop's instrumentation is always added (C5);
the profile instrumentation is always called; it adds nothing without
`TRACY_ENABLE` (C8.1).

### C1.5 CMake, presets, pins

- `FI/CMakeLists.txt`: `add_subdirectory` of `include/idr` and `lib`;
  the tools. `INC/IR/CMakeLists.txt` runs TableGen over
  `INC/IR/IdrOps.td` (C1.1); `INC/Transforms/CMakeLists.txt` runs it
  over `INC/Transforms/Passes.td` into
  `include/idr/Transforms/Passes.h.inc` (`IdrPassesIncGen`).
  `IDR/CMakeLists.txt` adds the area directories. The libraries are
  declared in the coordinator's lists of C1.1, from the unit lists the
  lanes report.
- The language profile: `-fno-exceptions -fno-rtti -Werror`, C++26,
  `-ffp-contract=off`, as today. The hardening flags
  (`-fsanitize=undefined -fsanitize-trap=all -ftrivial-auto-var-init=zero
  -fstack-protector-strong -fzero-call-used-regs=used-gpr
  -fno-delete-null-pointer-checks -fno-strict-aliasing
  -fstrict-flex-arrays=3`) move to the `hardened` preset.
- Presets (`CMakePresets.json`): `dev` (Debug), `release` (Release,
  `-flto=full`, `-ffunction-sections -fdata-sections`), `hardened`
  (Release plus the flags above), `profile` (Release plus
  `IDRIS_MLIR_PROFILE=ON`, `-fno-omit-frame-pointer`, `-g1`, and the
  option `IDRIS_MLIR_PROFILE_MEMORY`, default `OFF`, C8.2), `lint`
  (Debug under the stage-2 clang-tidy). `make build` builds `dev` as
  today; `make build PRESET=release` the others.
- ccache: `make build` launches every compile through the bootstrap's
  ccache when the host has one (`CMAKE_CXX_COMPILER_LAUNCHER`), as the
  toolchain's builds do. No precompiled header.
- `third_party/tracy`: a submodule pinned to the current release at
  launch (the coordinator records the tag and commit in
  `toolchain.lock.json` and `PINS.md`); `IDRIS_MLIR_TRACY_DIR` and the
  sibling-directory lookup go. The `idr_tracy` library is built only
  with `IDRIS_MLIR_PROFILE=ON`; every other preset compiles
  `tracy/Tracy.hpp` with `TRACY_ENABLE` undefined, so the zones cost
  nothing.

### C1.6 `CS/Ids.idr`: the instance key on the Idris side

```idris
||| What a function or data instance is an instance of: the definition and
||| the compile-time values it was instantiated at, each the
||| alpha-normalized text the frontend prints. Emit writes it as
||| #idr.instance and derives the symbol's readable name from it; nothing
||| else reads the name.
public export
record InstanceKey where
  constructor MkInstanceKey
  origin : String            -- the definition's printed full name
  arguments : List String    -- each compile-time argument, alpha-normalized text
```

`origin` is the definition's printed full name (C6.3); a type, an
implementation and a shape are all printed text. There is no
`InstanceArg`, so `Ids.idr`, which `Types.idr` imports
(`CS/Types.idr:11`), needs nothing of `Types.idr`. The root's key is
`MkInstanceKey "$idris-mlir.root" []`.

`Term.idr`'s `TFn` and `Data` records gain `key : InstanceKey` and lose
`idrisName`; `TFn.params` is `Vect arity (Shown, Binder)`; `Let`,
`CaseNat`, `Lam` and `MkAlt` carry the binder's name as a `Shown` (U18
writes the records, U19 fills them); `showSource` prints the readable
key. The coordinator writes `Ids.idr`.

### C1.7 Generated Idris

`CS/Dialect/*.idr` and `CS/Syntax/*.idr` are regenerated by the
coordinator with `tools/dialects.sh generate` at integration, from the
ODS above and U20's generator. Lanes write against the names the
generator gives today plus these, which are the generator's signatures:

- `Idr.funcOp` with the implicits `symVisibility`, `argAttrs`,
  `resAttrs`, `total'`, `breakLast`, `noInline`, `effects`, `instance`,
  `clone`, then `symName`, `functionType`, `body`;
- `Idr.callOp` with the implicits `argAttrs`, `resAttrs` and `effects`,
  then `callee`, `args`, `results`;
- `Idr.returnOp` with `operands`;
- `Idr.dataOp`, which gains `instance`;
- the syntax constructor
  `InstanceAttr : (origin : String) -> (arguments : List at) -> IdrAttr ty at`,
  the arguments string attributes;
- `Quantity = One | Many`;
- in every generated `CS/Dialect/<Name>.idr`,
  `export printOp : Op -> Maybe String`: the op's full name and its
  format's text up to its region directives, which must all be last;
  `Nothing` (generic form) for an op with `hasCustomAssemblyFormat`, a
  `custom<...>`, `oilist` or `ref` directive, or a region not last in its
  format. The generator's trailer lists those ops by name with the
  reason, and is the list of generic ops. A format inside the subset
  that MLIR's parser refuses on a sample leaves the subset (the
  generator lists it generic).

The generator calls `CS/MLIR.idr`'s attribute-dictionary writer, which
U18 exports, instead of repeating it.

## C2. One representation per fact

### C2.0 The pass rules

Every pass obeys MLIR's rules (`PassManagement.md`, "Operation Pass"):
no state across runs, no global mutable state, copy-constructible, and a
`FuncOp` pass touches only its function. Concretely:

- No pass constructs a `SymbolTable` for lookups. A module pass takes
  `getAnalysis<SymbolTable>()`; a function pass takes
  `getCachedParentAnalysis<SymbolTable>()` and fails its pass with an
  internal error if it is absent. A pass or analysis that needs the
  users of every symbol builds one `mlir::SymbolUserMap` over a
  `SymbolTableCollection` local to that run, the only symbol table it
  builds (U04's contify, U08's erase of originals, U09's `Returned`,
  U10's `TailCallPlan`, U12's `Lengths`).
- Code MLIR calls with no table in hand (fold, `getEffects`,
  `inferResultRanges`, a canonicalization pattern, a printer hook, a
  plain verify) resolves no sibling `idr.func`: a callee's fact it needs
  is written onto the call by a module step. It reads a declaration only
  through `declarationOf` or `constructorOf`, and only where the scan
  runs at most once per op it rewrites or on ops that exist after
  `idr-defunctionalize` or `idr-tail-loops`. A verifier rule that needs
  a declaration is `verifySymbolUses`. While a nested manager runs, no
  pass writes a declaration or another function's signature or facts,
  and no pass of the round's function step or of the inliner's
  component pipeline writes its own function's signature. No
  canonicalization pattern creates, erases or renames a symbol.
  `ApplyOp::canonicalize` keeps its constant branch, resolving the
  callee's signature with `SymbolTable::lookupNearestSymbolFrom<FuncOp>`
  under these rules.
- The helpers every lane shares are fixed by name and signature:
  - `INC/IR/Symbols.h` (U01), the one home of symbol lookup:
    `getSumName(Type)`; `lookupData(SymbolTable &, Type)` and
    `lookupCtor(SymbolTable &, SymbolRefAttr)`, O(1) from the table a
    pass or analysis holds; `lookupData(SymbolTableCollection &,
    Operation *from, Type)` for a `verifySymbolUses`;
    `lookupCtor(DataOp, StringRef)`; `declarationOf(Operation *from,
    Type)` and `constructorOf(Operation *from, SymbolRefAttr)`, the scans
    of the rule above (`SymbolTable::lookupNearestSymbolFrom<DataOp>`;
    nothing opened, published or remembered); `listCons(Operation *op,
    DataOp, Type list, Type element)`; `holdsReferences(Type,
    function_ref<DataOp(Type)>)`; `Elimination` and
    `eliminationAt(OpOperand &)`; `isMemo(DataOp)`;
  - `INC/IR/Grades.h` (U01): the grade helpers of U01's part,
    `arrayRoot` and `isRank1Array` included;
  - `INC/IR/IdrDialect.h` (U01): `bool consumes(mlir::OpOperand &,
    mlir::SymbolTable *symbols = nullptr)`, `consumedEffects`,
    `ioEffects`, `onlyAllocates`, `performsIO`, the traits,
    `knownNonZero`, `knownFinite`, `knownNonEmpty`, `CheckKind`,
    `checkHolds`, `checkSpeculatability`, `writtenInPieces`,
    `memoRunning`, `memoForced` and `constantBytes`;
  - `INC/IR/Ranges.h` (U01): `idr::ranges` (`smallMin`, `smallMax`,
    `Bounds`, `bounded`, `natural`, `boundsOf`, `add`, `sub`, `mul`,
    `ofInteger`, `rangeOf`, `nonNegative`);
  - `INC/IR/Ownership.h` (U02, `idr::ownership`): `enum class Use`,
    `Use useOf(OpOperand &, SymbolTable *symbols = nullptr)` (a force
    consumes when its operand is owned; every other use is
    `consumes(operand, symbols)`), `isStatic(Value)`, `readFrom(Value)`,
    `reachesOnlyAtoms(Value, llvm::function_ref<DataOp(Type)>)`,
    `isArrayLoop`, `inOwnedStage(FuncOp)`, defined in
    `IDR/IR/Verify/Uses.cpp`. U08 keeps `usersIn`, `usedAfter`,
    `whereDies`, `followed`, `onlyReads` and `Counted` in
    `INC/Analysis/Ownership.h`. A module-level stage question is an
    `any_of` over the module's functions, inline where it is asked.
- No `thread_local`, no `std::atomic`, no `static` mutable object, no
  cache on a pass instance. `SymbolScope`, `HoldMemo`, `SymbolsHeld`,
  the effects pass's `inferred` and the dialect's published chains are
  deleted (U01, U02, U03, U04). The three exceptions are C1.1's: the
  dialect's `foldLeak` counter, the `cl::opt` and `cl::list` objects of
  the driver and the tools, and a `TaggedAction`'s function-local
  `SelfOwningTypeID`.
- A pass that rewrote nothing calls `markAllAnalysesPreserved()`; one
  that rewrote and knows which analyses still hold calls
  `markAnalysesPreserved<…>()` (C2.1's obligations). No pass hashes the
  module to find out whether it changed anything.
- A nested manager and every `runPipeline` preserve no module analysis;
  after one, every module analysis is gone. A module pass holds no
  analysis reference across `runPipeline`; an analysis a nested pass
  reads is computed immediately before the nest and preserved by that
  step; a function pass that finds one absent fails with an internal
  error.
- A rewrite goes through a rewriter and never mutates the IR a walk is
  walking. Many independent local sites with no fixpoint: a pattern
  under `walkAndApplyPatterns`. A fixpoint: the greedy driver, which is
  also the choice where `walkAndApplyPatterns` refuses a pattern that
  erases or inserts beside the matched op. A decision taken once on the
  IR as it stands, from an analysis or a walk that collects, is a plan
  applied afterwards through an `IRRewriter` on exactly the collected
  sites: `idr-specialize` (symbols from calls), `idr-accumulate`,
  `idr-trmc` and `idr-tail-loops` (a clone or a loop built from a body),
  `idr-in-bounds`' proofs (each judged on the function as it was, erased
  together after), `idr-isolate` (innermost first), `idr-stack` (marks),
  `idr-rc`'s signatures and `shareTainted`, `idr-vectorize` (tiles),
  `idr-effects` and `idr-loop-breakers` (facts). Upstream transform
  utilities (`moveLoopInvariantCode`, `upliftWhileToForLoop`,
  `tileUsingSCF`, the linalg vectorizer) may be called directly on
  collected ops. A function pass changes only its own function and the
  ops in it; it may read its ancestors' attributes (the module's
  `#llvm.target`, its data layout); it may build, analyse and erase IR
  in a detached module it creates and owns (`idr-narrow-lanes`' trial
  copy).
- A function pass emits a remark only as a diagnostic the pass manager
  orders; no remark streamer is open while a nested manager runs; a
  remark names its site by location.

### C2.1 The analyses

Each is a class with the constructor `(Operation *, AnalysisManager &)`
or `(Operation *)`, an `isInvalidated(const AnalysisManager::PreservedAnalyses &)`,
and one header (the column, relative to `INC`). None mutates IR.

| Class | Header | Owner | Computes | Reads | Invalidated unless preserved |
| --- | --- | --- | --- | --- | --- |
| `idr::References` | `Analysis/References.h` | U03 | per `idr.func` in walk order the `Site{target, at}` of each `idr.call`, `idr.closure`, `idr.suspend`, closure constant and constructor of a sum of closures naming a function; `functions()`, `of(fn)`, `hasCall(fn)` (any `CallOpInterface`, `idr.apply` included), `callsUnknown(fn)`, `ops(fn)`, `components()` (callees first), `isRecursive(fn)` | `SymbolTable` | `References`, `SymbolTable` |
| `idr::Effects` | `Analysis/Effects.h` | U03 | per function io, crash, diverge (`of`), `takesWorld`, `passed(Value)`, `static declared(FuncOp)`, `anyEffect` | `References`, `Holds`, `SymbolTable` | `Effects`, `References`, `Holds`, `SymbolTable` |
| `idr::Holds` | `Analysis/Holds.h` | U03 | `mayHoldWorld(Type)`, `mayHoldClosure(Type)`, stopping at an array as today | `TypeGraph` | `Holds`, `TypeGraph` |
| `idr::TypeGraph` | `IR/TypeGraph.h` (IdrIR) | U03 | containment among declarations and arrays: `size`, `node`, `type`, `isArray`, `declaration`, `successors`, `components`, `knots`, `cycle`, and `containsItself()`, each declaration on a cycle whose edges join unboxed declarations only, in module order | none | `TypeGraph` |
| `idr::InlineDecisions` | `Analysis/Inline.h` | U05 | the MLton rule | `References` | `InlineDecisions`, `References` |
| `idr::CloneTable` | `Analysis/Specialize.h` | U06 | the clone table from the clone facts and the signatures (the hole of a parameter is its position; `arg_attrs` is not read), with `Clone { FuncOp fn; Attribute key; FlatSymbolRefAttr name; FunctionType type; std::optional<idr::Effect> effects; }` | `SymbolTable` | `CloneTable`, `SymbolTable` |
| `idr::BindingTimes` | `Analysis/Specialize.h` | U06 | today's binding times | `References`, `CloneTable`, `SymbolTable` | `BindingTimes`, `References`, `CloneTable`, `SymbolTable` |
| `idr::Labels` | `Analysis/Labels.h` | U07 | the label lattice on a `DataFlowSolver` | `SymbolTable` | `Labels`, `SymbolTable` |
| `idr::Borrows` | `Analysis/Ownership.h` | U08 | borrow inference | `Reuses`, `SymbolTable` | `Borrows`, `Reuses`, `SymbolTable` |
| `idr::Reuses` | `Analysis/Ownership.h` | U08 | where each function's dead boxes are taken apart and which constructors get their cells | `SymbolTable`, `Layouts` | `Reuses`, `SymbolTable`, `Layouts` |
| `idr::Exclusivity` | `Analysis/Ownership.h` | U08 | exclusivity on the solver (`failed()`) | none | `Exclusivity` |
| `idr::Escapes` | `Analysis/Escapes.h` | U13 | which boxes may outlive their frame, as a sparse backward analysis on the solver, with the baseline analyses when the pinned backward base needs liveness | `SymbolTable` | `Escapes`, `SymbolTable` |
| `idr::Identities` | `Analysis/Identities.h` | U13 | the functions that give back an argument (the greatest fixpoint) | `SymbolTable` | `Identities`, `SymbolTable` |
| `idr::Ranges` | `Analysis/Ranges.h` | U11 | one interprocedural `DataFlowSolver` with `NaturalRanges` (a `!idr.nat` seeded at `[0, INT64_MAX]`, the type as written, as today); `valid()`, `counted`, `rangeOf(Value)`, `solver()` | none | `Ranges` |
| `idr::Layouts` | `IR/Layout.h` (IdrIR) | U10 | the layouts of cells; `valid()` after its constructor reported each cell that cannot be built | none | `Layouts` |

Library-private analyses, declared in their library's area header:

| Class | Header | Owner | Computes | Reads | Invalidated unless preserved |
| --- | --- | --- | --- | --- | --- |
| `idr::inbounds::Lengths` | `Transforms/InBounds.h` | U12 | which integers are lengths of which arrays, across calls | `Ranges`, `SymbolTable` | `Lengths`, `Ranges`, `SymbolTable` |
| `idr::tail::Returned` | `Transforms/Tail.h` | U09 | per eligible `func.func`, by name, the lattice value of each result and the original result types | `SymbolTable` | `Returned`, `SymbolTable` |
| `idr::conversion::TailCallPlan` | `Conversion/TailCallPlan.h` | U10 | per function: the internal functions from one `SymbolUserMap`, the candidates in tail position, the cycles from `mlir::CallGraph` through `llvm::scc_iterator`, the `tailcc` set, the planned tail calls, what goes through memory | none | `TailCallPlan` |

**Invalidation.** Every `isInvalidated` returns true unless the analysis
and every analysis it reads are preserved; none special-cases itself.

**Obligations.** A module pass that changes no `idr.data` or `idr.ctor`
marks `Holds`, `TypeGraph` and `Layouts` preserved; one that inserts or
erases symbols only through the `SymbolTable` analysis, or none, marks
`SymbolTable` preserved. `CloneTable` is claimed only by a pass that
adds, erases and retypes no `idr.func` and writes no effects, and by
`idr-specialize`, which enters every clone it inserts in the table it
holds. `idr-effects` and `idr-loop-breakers`, which write only
attributes of `idr.func` and `idr.call`, also mark `References` and
`Effects`; `idr-round-facts` marks everything. Per pass:

- `idr-isolate`, `idr-contify`, `idr-inline`, `idr-stack`, `idr-rc`,
  `idr-demand`, `idr-narrow`, `idr-in-bounds`, `idr-entry`: `Holds`,
  `TypeGraph`, `Layouts`, and `SymbolTable` where true;
- `idr-specialize`, `idr-accumulate`, `idr-trmc`: those and
  `SymbolTable`, and `CloneTable` for `idr-specialize`; an
  `idr-accumulate` or `idr-trmc` run that clones nothing marks
  everything;
- `idr-defunctionalize`, `idr-lower`: none.

An analysis may be recomputed within a round, but not after a step that
preserved it.

**Construction.** An analysis whose per-function part depends only on
that function's body, the symbol table, declarations and other analyses
computes those parts with `mlir::parallelForEach` over
`module.getOps<idr::FuncOp>()` into one slot per function in module
order, then merges and runs its fixpoint serially in that order. A
per-function part inserts into no shared container and emits no
diagnostic: a failure is recorded in its slot and reported by the
merge. `References`, `Effects` (its local bits), `Identities` (its
record), `BindingTimes` (its call collection) and `Reuses` do so;
`Escapes`, `Lengths` and `Borrows` do where their per-function part
separates, and a lane that cannot separate keeps it serial and says why
in its handoff. Through the analysis manager, analyses are constructed
only by module passes, on the pass thread; the module verifier
constructs `TypeGraph` and the owned walk `Layouts` directly (C4).

A function pass reads a module analysis with
`getCachedParentAnalysis<T>()`; a module step computes it with
`getAnalysis<T>()`. The names above are the only spellings.

The strongly connected components of any graph of ours come from
`idr::components` or `idr::stronglyConnected` (`INC/Support/Scc.h`):
`llvm::SmallVector<llvm::SmallVector<unsigned>> idr::components(llvm::ArrayRef<llvm::SmallVector<unsigned>> successors)`
and
`template <typename Node> llvm::SmallVector<llvm::SmallVector<Node>> idr::stronglyConnected(llvm::ArrayRef<Node>, llvm::function_ref<llvm::SmallVector<Node>(Node)>)`,
callees first, the order depending only on node and successor order. No
unit specializes `llvm::GraphTraits` or calls `llvm::scc_begin` but over
upstream's graph types (`mlir::CallGraph` in `TailCallPlan`).

`Layouts` has the constructor `explicit Layouts(mlir::Operation *)`, is
eager and immutable after construction (it is read from several
threads), and every pass that asks for it fails its pass when
`!valid()`, with today's `unsupported (layout)` text for each cell.
`INC/IR/Layout.h` publishes `idr::Layouts` (`box`, `element`, `sizeOf`,
`alignmentOf`, `isMemo`, `getModule`) and `idr::layout::{mostObjects,
tagMask, CellInfo, Slot, Cell, Element, SumLayout, Components, boxable,
Holders (with overflows), fit}`; `unsigned
idr::layout::fit(mlir::ModuleOp)` is the one call U07 makes.
`INC/Target/Target.h` publishes `idr::target::{targetOptions, machine,
optimize, vectorBits}`, with `unsigned vectorBits(mlir::ModuleOp)` read
by U16 from the parent module.

### C2.2 The facts of a function

`total`, `break_last`, `no_inline`, `effects`, `instance` and `clone`
are the inherent attributes of `idr.func` (C1.2). `idr.call`'s
`effects` is inherent too, written by `idr-effects`, read through
`getEffectsAttr()`; a pass that changes a call's callee keeps it only
while it contains the new callee's. A pass that rebuilds a call of the
same callee keeps it; a pass that makes a call or changes its callee
(`idr-specialize`, `idr-redirect`, the apply canonicalization,
`ForceOfOneUse`, `ForceInOneCase`, the force preparation) gives the new
call the old call's effects when they contain the new callee's, and
none otherwise. Every fact is read and written through the generated
accessors (`getTotal()`, `setEffectsAttr`, …) and nowhere else: no
`hasAttr("idr.…")`, no `getAttr("…")`.

The `idr.stack` mark on an `idr.con` stays a discardable attribute,
written by `idr-stack` (U13) and read only through
`IdrDialect::StackAttrHelper`: by `ConOp::getEffects` (U01), the owned
walk (U02), `Reuses` and `Exclusivity` (U08), the stack-cell lowering
(U10) and no-heap-allocation (U15).

A call takes an argument over when the callee's parameter is owned:
`consumes(OpOperand &, SymbolTable * = nullptr)` (U01) reads the
callee's grade through the table when one is given (`idr-rc` and
`idr-rc-place`), and otherwise `idr.call`'s `consumesOperand`, which
reads the operand's type.

A pass that creates an `idr.func` gives it its first facts through the
accessors (`idr-specialize`, `idr-inline`'s force preparation,
`idr-isolate`, `idr-accumulate`, `idr-trmc`, `idr-rc`'s copies);
`idr-effects` rewrites effects each round; no writer stores the full
set. A copy made for a pass's own purpose drops `clone`. `idr.func`'s
verifier checks the clone fact: its function is the op itself and its
key fits the signature. A clone keeps its origin's `instance` and
location.

### C2.3 Symbols

An `idr.func` and an `idr.data` are named by the readable, quoted
symbol the frontend derives from the key (C6.3). No key, owner, count,
kind or identity is read from a symbol; the printer's names and aliases
read a symbol's characters to shorten it for the reader and decide
nothing. `idr-lower`'s phase 0 mangles each program function symbol
(the `func.func` name, the `func.call` callee, the `Facts` key, a memo
label's function) into `[A-Za-z0-9_.$]` with `$<code point>$`, the
injective scheme of today's `mangle` (`CS/MLIR/Text.idr:20-26`), moved
(U10); static data, runtime and entry names are already in the alphabet
and are not passed through it; after phase 0 every program symbol is
mangled. The driver's runtime-name check compares the names the LLVM
module carries and calls no mangler; U18 deletes the frontend's
`mangle`.

### C2.4 Defunctionalization through dialect conversion

The rewrite of `!idr.fn` and `!idr.lazy` slots into sums is a
`ConversionTarget` and a `TypeConverter`
(`sources/docs/mlir/docs/DialectConversion.md`). The keys are decided
from `Labels` by the key decision `Slots`, a value the pass builds from
`Labels` and the `SymbolTable`, in `IdrDefunctionalize`. The converter
maps each keyed slot (a value, a function's argument or result, a
constructor field, an array element) to its key's sum through a value
conversion tried first, and keeps grades and retypes array elements
through a type conversion that returns nothing for a bare `!idr.fn` or
`!idr.lazy` carrier. Signatures convert through `FuncSignaturePattern`,
the body of upstream's function-interface pattern with result types from
the slot table (a result's key is the function's, not the type's), not
`populateFunctionOpInterfaceTypeConversionPattern`.
`populateCallOpTypeConversionPattern` and
`populateReturnOpTypeConversionPattern` are the lane's slot-keyed
patterns for `idr.call` (keeping its effects, C2.2) and `idr.return`,
declared in `INC/Transforms/Defunctionalize.h`. `idr.closure` and
`idr.suspend` become `idr.con`, `idr.apply` `idr.match`, `idr.force` a
force of the memo sum (the switch on its state stays `idr-lower`'s);
`idr.constant`, `idr.ctor`'s field types and every other op convert
through patterns, the last generic. `Moves.cppm`'s coercions are the
converter's target materializations. The pass runs one
`applyFullConversion` on the module with rollback, folding off and
materializations built; then `markByName` and `layout::fit` (C2.1). A
slot kind the framework cannot express is reported with its op and
fixture, never kept as a hand walk.

An `idr.delay` whose body is one `idr.yield` of a value from above is
the evaluated suspension: `idr-isolate` leaves it, `Labels` gives it no
label, the conversion makes it `idr.con` of the memo sum's forced
constructor, and `idr.force` of it folds to the value.

### C2.5 `idr.func` to `func.func`

`idr-lower` begins with phase 0: every `idr.func` becomes a `func.func`
of the same type and visibility under its mangled name (C2.3),
`idr.call` a `func.call`, `idr.return` a `func.return`, after
`IDR/Conversion/Facts.cpp` has read the facts it hands LLVM (the
argument and result attributes). `idr.call`'s `effects` is dropped. From
phase 1 on, the lowering is today's. No fact of `idr.func` survives
phase 0 as an attribute; what LLVM needs is already on the `func.func`.
`tailcc` is `idr-tail-calls`' decision, on `llvm.func`.

## C3. The simplify loop

### C3.1 The loop

`idr-simplify` is upstream's `CompositeFixedPointPass` over the round,
built by `createCompositeFixedPointPass("IdrSimplifyRound", round,
maxRounds, ConvergenceFailureAction::Silent)`. The loop's
instrumentation, `idr::createSimplifyInstrumentation()`, is added by the
manager's owner (C5), and `idr-simplify` fails with its internal error
under a manager without it. The instrumentation picks the round's
pipelines by the composite's pointer identity (falling back to the
display name `IdrSimplifyRound` if the pin passes another `parentPass`),
counts rounds, and emits today's remarks (`round N …`,
`fixpoint: round N changed nothing`) and the statistics remark: the
deltas per pass instance, sorted by name, as `<pass>.<statistic>`. A
loop that ran past `max-rounds` is `unsupported (compile-time budget)`,
as today. The fingerprint is upstream's, one per round; the per-pass
fingerprints, `SymbolsHeld`, `holdsSymbols`, `OpenRound`, `CloseRound`
and `PipelineStatistics` are deleted. The carried sccp patch
(`upstream/02-composite-fixed-point-sccp`, `PINS.md`
`simplify-structural-fixpoint`) is what lets the composite converge; it
stays carried. The instrumentation also emits `IDR_FRAME("round")` and
the plots functions, clones and ops after each round; the walk that
counts ops is an argument of the macro and runs only in the profile
build.

### C3.2 The round

```text
idr-effects                                   -- module: Effects -> facts on functions and calls
idr-loop-breakers                             -- module: References -> no_inline
idr-round-facts                               -- module: the analyses the function step reads
idr.func(idr-identity, canonicalize, cse, idr-redirect)
idr-inline                                    -- module: force preparation, upstream Inliner, component pipeline (C3.3)
idr-specialize                                -- module: raise, clone, redirect what it rewrites
sccp
int-range-optimizations
remove-dead-values{canonicalize=false}
symbol-dce
```

`canonicalize` is upstream's pass with the default configuration; the
dialect's patterns are registered on the ops. The counts of rewrites per
pattern (`IDR/Support/Counts.cppm`) go; upstream's `-mlir-pass-statistics` and the
loop's statistics remark report what a round did. `canonicalize` also
runs inside `idr-inline`'s component pipeline, over a call graph taken
before it; no pattern of the dialect creates, erases or renames a
symbol.

`idr-redirect` reads no sibling op: a clone's symbol, function type and
effects come from its `Clone` record; the raise pattern's effects
condition reads the call's own effects and its takes-a-world test reads
the call's operand types through `Holds`; the redirected call takes the
old call's effects when they contain the clone's recorded effects.
`--mlir-debug-counter` on the redirect actions needs
`--mlir-disable-threading`.

### C3.3 The inliner

`idr-inline` first applies, to the module, `ForceAtCapture` then
`ForceOfOneConstant` (`IDR/Transforms/Inline/Prepare.cpp`, declared in
`INC/Transforms/Inline.h`) through the greedy driver with its changed
flag, over the `SymbolTable` and `References` analyses, and clears the
analysis manager when either changed anything; neither is a
canonicalization pattern. `ForceAtCapture`'s new function is inserted
through the `SymbolTable` analysis, named `<wrapper>.capture<n>` (C6.3),
with `total` and `effects` copied from the callee whose body it copies
and no `instance`.

It then runs `mlir::Inliner` with `InlinerConfig`: the MLton rule of
`InlineDecisions` as profitability; `maxInliningIterations` unbounded;
the default pipeline `canonicalize,cse`; a clone callback that calls
`absorb(callee)` on the function inlined into and marks it; a pipeline
runner that runs the pipeline on a callable only when it is marked, and
clears the mark. The marks are one `DenseMap` filled with every
`idr.func` before the inliner starts, written by the callback on the
pass thread and cleared by the runner on its own entry; parallel runners
insert nothing. A component's first optimization runs no pipeline, so
the round's parallel function step stays its one canonicalization, and
a do block still unfolds in one round. The dialect's inliner interface
(U02, `IDR/IR/Func/Inliner.cpp`) mirrors func's: both `handleTerminator`
forms for `idr.return` (a `cf.br` for a block), every op and region
legal; `PINS.md` `inline-unreachable` decides a callee ending in
`ub.unreachable`. No upstream patch.

## C4. Verification at the level the pass ran

- `idr.func`'s `verifyRegions` owns the per-function rules: every
  value of quantity one used once on every path (today's
  `Linearity.cppm`, made linear: one numbering of the body's operations,
  then every linear value's uses counted against it), and the owned
  stage's counting (today's `Ownership/Verify.cppm` and
  `Checker.cppm`'s walk) when the function's grades are in that stage.
  The owned walk resolves each declaration it needs at most once per
  verify of the function, by `declarationOf` memoized per type, builds
  no symbol table, and constructs `Layouts` at most once per verify, for
  a function holding an `idr.reuse`; it fails its reuse rule when
  `Layouts` is not `valid()`. Its shared vocabulary is
  `INC/IR/Ownership.h` (U02). It runs in parallel per function. Its cost
  is recorded at integration (C10, R47); if the `VerifierPass` rows
  after `idr-rc` dominate, the owner's next step is the
  declaration-dependent half of the walk as `idr.func`'s
  `verifySymbolUses`.
- `FuncOp::verify` (U02) checks the clone fact: its function names the
  op itself, its key is a `SpecKey`, `KeyApply` or `KeyApplyField`, and
  a `SpecKey` has as many holes as the function has parameters.
- The module's `idr.program` attribute verifier keeps the module-level
  rules: one root, every data type declared and of its kind, containment
  acyclic (`TypeGraph::containsItself`), no array that can reach itself
  (`TypeGraph::knots`). It constructs `TypeGraph` directly and no longer
  calls per-function rules.
- A rule that needs a declaration or a callee is a `verifySymbolUses`
  rule, run once per module verify with one shared
  `SymbolTableCollection`: `idr.call`'s callee, its types (each
  operand's type is its parameter's) and its effects, refused with
  `carries effects <call>, but @f may do <callee>` when present and not
  containing its callee's (a callee without effects may do everything);
  and the declaration checks of `Idr_ForceOp` (its memo-sum branch),
  `Idr_StrPackOp`, `Idr_StrConcatOp` and `Idr_PutListOp` (U01).
- Nothing turns the verifier off. A function pass is followed by the
  verifier of its function; a module pass by the module's, which runs
  the function verifiers too, as MLIR does.
- `verifyDiscardableAttrs` and `Idr_KnownAttributes` are deleted: the
  only discardable `idr.*` attributes left are `idr.program` on the
  module and `idr.stack` on an `idr.con` of a box, each verified by the
  dialect's `verifyOperationAttribute` (U02), which refuses any other
  `idr.*` name. `verifyRegionArgAttribute` refuses every `idr.*`
  argument attribute. Attributes outside the `idr.` prefix are not
  policed.

## C5. The driver

- One `PassManager` per compilation: `idr-target`, then C1.4's
  pipeline. `applyPassManagerCLOptions`, `enableTiming` with the
  compilation's root timer, statistics when `--stats`, the loop's
  instrumentation (`idr::createSimplifyInstrumentation()`), always, in
  idris-mlir and in idris-mlir-opt through `MlirOptMainConfig`'s pass
  pipeline setup hook, the dump instrumentation when `--dump-dir`, and
  the profile instrumentation, always called; it adds nothing without
  `TRACY_ENABLE`.
- `idris-mlir-opt` is `MlirOptMain` with the idr dialect and passes
  registered and `--idr-pipeline` registered as a pass pipeline (C1.4).
- The handoff is read as text; the driver already accepts a `.mlirbc`
  input (`IDR/Driver/Artifacts.cppm:19`, `IDR/Driver/Options.cppm:20`);
  nothing in this packet writes bytecode.
- `Driver` is plain headers and `.cpp` under `IDR/Driver`; `Options`,
  `Artifacts`, `Report` and the runtime preparation keep their names.
- The driver and the tools insert `idr::IdrDialect` into their
  registries.

## C6. The handoff: the frontend emits what it decided

### C6.1 No quantity zero

The frontend emits no value, parameter, field, argument, capture or
constant of quantity zero. A parameter Idris erased is not a parameter;
a field Idris erased is not a field; an argument at an erased position
is not passed; a lambda's erased binder is not a parameter of its
`!idr.fn` type. `ErasedT`, `Gone`, `Erased` and `erasedValue` leave
`CS/Types.idr`, `CS/Term.idr` and `CS/Emit`. Where a position cannot be
dropped, Translate (U19) rejects the term with `unsupported (type)`,
naming the term and its head (`<term> in a runtime position: an
argument of <head>, whose type is not known here`); no erased value
reaches Emit. A `FunT` of an erased binder is its result type; no `Lam`
binds one.

The frontend has one quantity type, the generated `Quantity`; `Use` goes
with `Gone`, and `Binder` is a record of a quantity and a type
(`record Binder where constructor MkBinder; quantity : Quantity;
type : Ty`). `binderType` is `QType q Plain t` when `q` is `One` and `t`
is not the world, else the carrier. The registry's Idris multiplicity
is its own three-valued type (erased, linear, unrestricted).

### C6.2 No newtype

A data type with one constructor and exactly one runtime field is not
declared: a value of it is the field's value, its constructor is the
identity, and a match on it binds the field. The frontend decides this
in `Translate/Types.idr` (`dataInstance`) and `Emit` never sees the
type (U19 decides, U18 has nothing to emit).

### C6.3 Names

A symbol is the key printed: the origin, then `[` the arguments joined
by `, ` `]` when there are any. The origin is Idris's printed full name,
except that a `DN` prints its inner name and a case, with or nested
block is `<parent origin>.case<k>`, `.with<k>` or `.<nested>`, `k` by
position in the parent, not by Idris's global counter. A `'n` suffix
marks a second identity whose key prints alike, from one counter over
`idr.data` and `idr.func` symbols in `Source` order. The root is
`$idris-mlir.root`. No `$<digits>$` escape: `symbol` quotes a name that
is not a bare identifier. The key itself is `#idr.instance` (C1.2) on the
`idr.func` and the `idr.data`.

A function a pass derives is named `<parent>.<kind><n>` for kinds made
several times per parent (`lam` and `delay` by `idr-isolate`, `spec`
and `raise` by `idr-specialize`, `capture` by `idr-inline`'s force
preparation), `n` the parent's count of that kind plus one, and
`<parent>.<kind>` for kinds made once (`acc` by `idr-accumulate`,
`trmc` by `idr-trmc`, `excl` by `idr-rc`). Every name goes through
`SymbolTable::insert`, which renames a collision; nothing reads a name
back.

### C6.4 Methods and arity

A call of an interface method whose implementation the instance fixes
is emitted as `idr.call` of the implementation's method function,
saturated, never as an `idr.apply` of a shim's result. A definition is
emitted at its syntactic arity; a call with that many arguments is one
`idr.call`; fewer build one closure per missing parameter, as the
result's curried type requires; more apply the result. `Lam` stays
unary, and Emit writes one `idr.lambda` per `Lam`. Every Delay is
emitted as `idr.delay`; one whose body yields a value from above is the
evaluated suspension, which the dialect handles (C2.4). A case
alternative set that covers every constructor of the scrutinee's data
has no default region.

### C6.5 Locations

Every op carries the span of the term it came from, as
`loc("file":l:c to l2:c2)` (`FileLineColRange`), or `loc(unknown)` only
for code with no source. A value bound by an Idris binder (a parameter,
a `let`, a pattern variable, a lambda's parameter) carries
`loc("name"("file":l:c to l2:c2))` (`NameLoc`), so the printer names
the SSA value after the Idris variable. Library code keeps the
`fused<"library">[…]` wrapper. Every C++ reader of a source position
takes `FileLineColRange` and reads its start: the crash message (U10),
so crash messages stay byte-identical; the knot report (U02);
quantities-kept (U15), which keys a binder by its location with every
`NameLoc` removed.

### C6.6 The ops

`idr.func`, `idr.call` and `idr.return` replace `func.func`, `func.call`
and `func.return` in the emitted module. The frontend writes no
`effects` on an `idr.call` (C2.2). Everything else Emit writes is
unchanged in meaning.

### C6.7 Emission

Emit writes the module to a handle, top-level op by top-level op,
through a temporary file renamed on success; no String of the whole
module exists. `emit : File -> Source -> IO (Either String ())` writes
the module op's head, each data declaration and each function's
statement pieces joined per statement, then the module's tail and
location (U18, `CS/Emit.idr`, `CS/MLIR.idr`). `CS/Frontend/Program.idr`
(U19) opens `<mlirPath>.tmp`, calls `emit`, and renames on `Right`; a
`Left` leaves no module behind. The frontend's `--timing` phases are
`checks`, `reachable`, `translate` and `emit`. The Core dump keeps its
shape.

## C7. Readability

### C7.1 Names the printer suggests

| Op or type | Suggested SSA name |
| --- | --- |
| `idr.constant` | `str` for a string, `big` for a big, `nat` for a natural, `clo` for a closure constant, `thunk` for a suspension constant, the constructor's name in lower case for a constructor constant (`nil`, `just`) |
| `idr.con` | the constructor's name in lower case |
| `idr.closure`, `idr.lambda` | `clo`, `lam` |
| `idr.suspend`, `idr.delay` | `thunk` |
| `idr.lin.enter` | `lin` |
| `idr.force`, `idr.apply`, `idr.call` | `forced`, `applied`; for `call`, the symbol's text before its first `[`, after its last `.`, in lower case |
| a value of `!idr.world` | `w` |
| `!idr.str`, `!idr.big`, `!idr.nat`, `!idr.fn`, `!idr.lazy`, `!idr.token` | `s`, `n`, `n`, `f`, `lazy`, `tok` |
| a graded value (`!idr.q` and its spellings) | its carrier's name |
| a match case's arguments | the Idris pattern variable's name, from its `NameLoc` (C6.5); else `f0`, `f1`, … |

Under `idr.func`, the `idr.` prefix is elided (`getDefaultDialect`).
The names and the aliases of C7.2 come from one helper in
`IDR/IR/Asm.cpp` (U01); `CallOp::getAsmResultNames` is U01's, in that
file.

### C7.2 Aliases

`OpAsmDialectInterface::getAlias(Type)` on `!idr.data<@X>` and
`!idr.box<@X>` returns a `FinalAlias` from X's text: split at `[`, `]`,
`,` and spaces, keep each nonempty piece's text after its last `.`,
join with `_` (`Prelude.Types.List[Prelude.Types.Nat]` is `List_Nat`);
MLIR sanitizes and numbers collisions. The existing alias for large
constants stays. Every dump and every `idris-mlir-opt` output is
printed with aliases.

### C7.3 The handoff's text

The dumps, printed by MLIR with aliases, names and the elided prefix,
are the readability target. Emit writes each op through the generated
`printOp` of its dialect, which gives its declarative head up to its
regions, appends the regions and the location, and writes the generic
form where `printOp` gives none (the generator's trailer lists those
ops and why; `idr.constant`, `idr.match`, `idr.match_lit`,
`idr.array.generate`, `idr.array.fold` and `idr.func` are among them).
Mixed forms are legal MLIR text. `T/compiler/handoff-round-trip` checks
the emitted module; `T/compiler/dialect-syntax` checks the printer
against the generic form (R46).

## C8. Profiling with Tracy

### C8.1 The one layer

`INC/Support/Profile.h` is the only header that includes
`tracy/Tracy.hpp`. It defines:

```cpp
namespace idr::profile {
enum class Subsystem { Driver, Parse, Round, Analysis, Pass, Conversion, LLVM, Link };
constexpr uint32_t color(Subsystem);     // one fixed colour per subsystem
}
#define IDR_ZONE(name)             ZoneScopedN(name)
#define IDR_ZONE_IN(name, sub)     ZoneScopedNC(name, ::idr::profile::color(::idr::profile::Subsystem::sub))
#define IDR_FRAME(name)            FrameMarkNamed(name)
#define IDR_PLOT(name, value)      TracyPlot(name, static_cast<int64_t>(value))
#define IDR_MESSAGE(literal)       TracyMessageL(literal)
namespace idr::profile {
// Zones for every pass and every analysis the manager runs, named by the
// pass or analysis and coloured Pass or Analysis.
void addInstrumentation(mlir::PassManager &pm);
}
```

Every macro expands to nothing unless `TRACY_ENABLE` is defined, which
only the profile preset does. `addInstrumentation` is defined in every
build and adds nothing without `TRACY_ENABLE`; with it, it registers a
`PassInstrumentation` holding a mutex and two maps from
`(Pass *, Operation *)` and `(TypeID, Operation *)` to a Tracy zone
context, begun in the before-hooks and ended in the after-hooks (and
`runAfterPassFailed`) with Tracy's C API and an allocated source
location named after the pass or analysis, on the thread MLIR calls
them on. Macro zones have literal names; no zone of ours allocates: the
pass and analysis zones' source locations are allocated and owned by
Tracy. No `thread_local`, no `std::atomic`. The `.cpp` is
`IDR/Support/Profile.cpp`.

### C8.2 Where the zones are

- The driver: one zone per phase named as `-mlir-timing` names it
  (`frontend`, `parse`, each top-level pass through the
  instrumentation, `translate`, `link runtime`, `optimize`, `codegen`,
  `link`), `IDR_FRAME("compile")` at the end of each compilation.
- The passes and analyses: through `addInstrumentation`, once, nested
  and dynamic pipelines' passes included; no pass adds a zone of its
  own for its whole run. The round's frame mark and plots are the
  loop's instrumentation's (C3.1).
- Inside a pass, a zone only around a stage a worker would want to see
  apart (an analysis's fixpoint, a conversion's phase), with a literal
  name; at most a handful per library.
- Memory: `IDR/Support/ProfileAlloc.cpp` defines the global
  `operator new` and `operator delete` with `TracyAlloc`/`TracyFree`
  when `TRACY_ENABLE` and `IDRIS_MLIR_PROFILE_MEMORY=ON` (an option of
  the profile preset, default `OFF`), linked into the three tools only
  then.
- Capture: `tools/profile.sh <idris-mlir arguments>` builds the profile
  preset if needed (with `--memory`, a separate build with
  `IDRIS_MLIR_PROFILE_MEMORY=ON`), starts `tracy-capture` from the
  Tracy submodule's `capture` tool on localhost, runs the compile with
  `TRACY_NO_EXIT=1`, and saves
  `bench/profiles/<date>-<commit>-<name>.tracy` (`bench/profiles/` is
  gitignored but for its README).
- The runtime is not instrumented in this packet (NOT TO DO for U23).

### C8.3 What `-mlir-timing` keeps

The timing instrumentation stays the cheap always-on report; Tracy is
the timeline. Both read the same pass names.

## C9. Tests

### C9.1 The dialect suite (`T/idr`, U21)

- Every fixture spells functions as `idr.func`, calls as `idr.call`
  (or `call` under an `idr.func`) and returns as `idr.return`; after
  lowering, `func.func`, with mangled symbols (C2.3).
- No fixture mentions `!idr.erased` or `#idr.erased`, nor writes
  `idr.effects`, `idr.total`, `idr.break_last`, `idr.clone` or
  `idr.hole` as discardable attributes: the facts are written as
  `idr.func`'s own (`attributes {total, effects = #idr.effects<io>,
  instance = #idr.instance<"Prelude.f", ["Prelude.Types.Nat"]>}`). The
  only discardable `idr.*` attributes are `idr.program` and
  `idr.stack`.
- A fixture that states a call's effects runs `--idr-effects` first or
  writes `{effects = #idr.effects<...>}` on the call;
  `T/idr/func/call-effects` states the containment rule.
- A fixture of a pass of the round's function step runs
  `idr-round-facts` before its nest:
  `builtin.module(idr-round-facts, idr.func(idr-redirect))`.
- New fixtures: `T/idr/func/` (the function verifier: a world used
  twice, a linear value used twice, an owned value not consumed, a call
  whose type does not match its callee, the call-effects rule, a clone
  fact that does not fit its function, facts round-tripping, a callee
  ending in `ub.unreachable` inlined into a function body);
  `T/idr/asm/` (aliases printed for data and box types, result names,
  the elided prefix, `--mlir-use-nameloc-as-prefix`).
- `T/idr/obs/stats.mlir` checks the statistics remark of the loop's
  instrumentation (C3.1).
- `T/idr/pipeline/*` and `T/idr/e2e/*` state the round's remarks by
  their names (`round 1 changed nothing`), unchanged.

### C9.2 The program suites (U22)

- `T/lib/properties.sh`: `quantities_kept` reads `idr.func` signatures
  and keys a binder by its location; `simplify_idempotent` is
  unchanged; the second compilation (`no-eval`) is deleted and every
  `expected` loses its `no-eval` lines.
- New: `T/compiler/handoff-readable` (the emitted module holds no
  `$<digits>$` in a symbol, no `!idr.erased`, no `func.func`, and every
  `idr.func` has a location and an `instance`), and
  `T/compiler/handoff-round-trip` (the emitted text parses, prints and
  parses again to the same bytes).
- `T/compiler/dialect-syntax`: syntax-samples writes its module
  declarative and generic; `--mlir-print-op-generic` of the two is
  byte-identical; the reprint round-trips.
- `idr-expect` names a function by a symbol with no comma or space or
  by its Idris definition, which also matches its clones; after
  lowering by its mangled symbol.
- `T/determinism/threads-*`: the parallelism proof; they also compare
  the remark stream of the function passes, one thread against the pool
  (the stderr of `--remarks-filter=idr-vectorize,idr-narrow-lanes`).
- `T/compile-times.sh` reads the timing report as JSON
  (`-mlir-output-format=json`) and records per compilation parse,
  `idr-simplify` with its round count, the `VerifierPass` sum, the
  analyses' sum, LLVM and the rest; `--against` compares each column
  and lists programs whose round count grew.
- `T/programs/prelude/every-interfaces-export` and
  `every-types-export`: unchanged; they must pass within their limits.

### C9.3 The repository rules (`T/spec`, coordinator)

`spec/cpp-starter` becomes `spec/mlir-layout` (the five presets, no
exceptions or RTTI, `-Werror`, no `.cppm`, no `import`, every library a
`add_mlir_library`, nothing `thread_local`, `static` mutable or
`std::atomic` but the three exceptions of C1.1). `spec/file-size`,
`spec/verifier-every-pass` and `spec/no-local-headers` search `.cpp`,
`.h` and `.cc` (`FI/tools` keep `.cc`; the generator stays listed in
`T/spec/file-size/allowed`); `spec/no-local-headers` accepts no header
beside a `.cpp`. `spec/verifier-every-pass` no longer names idr-eval's
lowering (`T/spec/verifier-every-pass/run:8`). `spec/dialects-current`
is unchanged.

## C10. Rulings

The packet's first rulings:

- **`idr.func` lands at once**, with `idr.call` and `idr.return`, in
  the handoff and in every fixture. Two-step adoption would keep the
  discardable facts alive for a stage, which is the thing being removed.
- **Two keys, two attributes.** `instance` is the frontend's knowledge
  (Idris types, implementations, shapes); `clone` is the specializer's
  (runtime patterns). Neither is parsed from a name. Several `idr.func`
  may share one instance: a specialization's clone and `idr-rc`'s excl
  copy keep their origin's, `idr-accumulate`'s and `idr-trmc`'s clones
  copy it. `clone` is unique per key; `instance` is not unique per
  function.
- **The erased grade is deleted from the dialect**, not only from the
  handoff: a type nothing can emit is a case every pass would still
  carry.
- **Declarations stay monomorphic.** A parametric `!idr.data<@T, […]>`
  is not taken: the instance's structure is the `instance` attribute on
  its declaration, and readability comes from names and aliases.
- **Canonicalization is upstream's pass.** The per-pattern counts go;
  a test that needs a count states the property with `idr-expect`; the
  round's statistics remark is tested by `T/idr/obs/stats.mlir`.
- **The round's convergence is upstream's composite pass**, one
  fingerprint per round.
- **Tracy is a preset, not the default build**, and the compiler alone
  is instrumented.
- **`idr-accumulate` stays**, measured against LLVM's tail-recursion
  elimination at integration (`bench/` ack, fib, tak); the measurement
  decides a later deletion, not this packet.
- **Case blocks are named by position in their parent**, so two
  compilations of one program give one name.

The rulings R01 to R48 were made on the lanes' returns and the
critics' reports, with the owner's decisions of 2026-10-12. Each is
binding; the section in parentheses carries its contract text.

- **R01. The function ops in the ODS** (C1.2). `idr.func` declares
  `OpAsmOpInterface` plainly and no separate `CallableOpInterface`,
  which `FunctionOpInterface` carries; it gains `hasVerifier` for the
  clone fact and holds the one copy of the rule that a body taking in a
  callee without Idris's proof of termination loses its own, as
  `absorb`, which contify (U04) and the inliner's clone callback (U05)
  call. `idr.call` carries its own effects (R07) and answers
  consumption through `consumesOperand` (R08). `idr.return` is
  unchanged. `idr.func`'s body stays `AnyRegion`.
- **R02. The instance key is text** (C1.2, C1.6). Every part of
  `#idr.instance` is a `StringAttr`; it is no symbol use, keeps nothing
  alive and follows no rename. `InstanceKey` is two strings and
  `InstanceArg` goes. U04's contify keeps today's users map over the
  module region: a clone's self-reference keeps it from being
  contified.
- **R03. The grade type stays** (C1.2, C7.1). `Idr_QType` keeps its
  required permission and three-part format; a default-valued
  permission is withdrawn. Types suggest names through
  `OpAsmTypeInterface`, `Idr_QType` forwarding to its carrier.
  `Idr_CtorOp` gets no field names: a case argument is named by its
  pattern variable's `NameLoc`, else `f0`, `f1`, ….
- **R04. Two discardable attributes** (C1.2, C2.2, C4). `program` and
  `stack`, with generated helpers; `total`, `break_last`, `effects` and
  `clone` become `idr.func`'s, and `hole` goes (a clone's hole is its
  parameter's position).
- **R05. Code MLIR calls without a table** (C2.0, C1.2, C3.2). It
  resolves no sibling function and reads declarations only by bounded
  scans; a declaration rule of a verifier is `verifySymbolUses`; a
  nested manager writes no declaration and no other function's
  signature or facts; no canonicalization pattern touches a symbol.
  U17's `foldsWith` probe stays; if
  `MLIR_ENABLE_EXPENSIVE_PATTERN_API_CHECKS` reports it as a change,
  U17 feeds on the structural tests alone.
- **R06. The force preparation** (C1.1, C3.3). `ForceAtCapture` and
  `ForceOfOneConstant` leave the dialect for `idr-inline`'s first step
  (U05, `Prepare.cpp`); `prepareForceAtCapture` goes.
- **R07. Call-site effects** (C1.3, C2.2, C9.1). The owner's decision:
  `idr-effects` writes each `idr.call`'s effects from its callee's and
  the closures it is passed, which keeps the rule that a closure's
  effect counts where it is passed; `CallOp::getEffects` (U02) reads
  the attribute and looks nothing up; `verifySymbolUses` refuses a call
  whose effects lacks its callee's. `idr-lower`'s phase 0 drops it.
- **R08. Consumption by grade** (C2.2). One
  `consumes(OpOperand &, SymbolTable * = nullptr)`; the `func::CallOp`
  case goes; only `idr-rc` and `idr-rc-place` pass a table, through
  `useOf`.
- **R09. The symbol helpers by name** (C2.0, C1.1). `INC/IR/Symbols.h`
  is the one home of lookup; `idr::lookupSymbol` and its template, the
  overloads `holdsReferences(Type, SymbolTableCollection &, Operation *)`
  and `listCons(Operation *, Type, Type)` go; the users of every symbol
  come from one `SymbolUserMap` local to a run. U17's patterns call
  `declarationOf` and `constructorOf`.
- **R10. Layout, include, link and build rules** (C1.1, C1.5, C2.0,
  C9.3). One area header per library and none beside a `.cpp`; the
  coordinator's CMake lists and who deletes each old area's list; 400
  lines per `.cpp`, `.h` and `.cc`; three exceptions to the state rule.
- **R11. TypeGraph in IdrIR; one components utility** (C1.1, C2.1,
  C4). The module verifier constructs `TypeGraph` directly, so `IdrIR`
  includes nothing of `IdrAnalysis`; `containsItself` replaces the
  verifier's second search. Every graph's components come from
  `INC/Support/Scc.h`.
- **R12. Homes of IDR/Graph's helpers** (C1.1). The tail-position
  helpers go to `INC/Analysis/Tail.h` (`idr::tail`, U09), which U08 and
  U13 include; `SymbolUses` and `refersTo` go; `fieldsOf` becomes a
  static of `IdrTail`; `runsAtMostOnce` becomes
  `idr::narrow::runsAtMostOnce(scf::ForOp)` in `INC/Transforms/Narrow.h`,
  which U15 includes.
- **R13. The owned stage's vocabulary** (C2.0, C4).
  `INC/IR/Ownership.h` (U02) is shared by the owned walk and the
  passes; `IdrNarrow` and `IdrExpect` include it and do not link
  `IdrOwnership`. The owned walk stays in `verifyRegions`.
- **R14. The analyses** (C2.1). One table with readers and
  invalidation, the library-private analyses listed, the preservation
  obligations per pass, per-function parts built in parallel into slots
  and merged serially in module order.
- **R15. Nests preserve nothing** (C2.0, C1.3, C3.2). A nested manager
  and `runPipeline` destroy every module analysis; `idr-round-facts`
  computes what the round's function step reads; `idr-redirect` reads
  no sibling op. `idr-tail-loops` reads no parent analysis, so no
  top-level nest depends on a step `--without` can remove.
- **R16. The rewrite rule** (C2.0, C1.3). Never mutate while walking:
  a pattern, the greedy driver, or a collected plan applied through an
  `IRRewriter`.
- **R17. Nested passes are unregistered** (C1.3). The six passes of
  C1.3's second table are `PassWrapper`s their module pass builds; the
  module pass keeps the statistics.
- **R18. `idr-rc` in five steps** (C1.3, C1.4). It refuses a module
  already in the owned stage; writes owned grades from `Borrows` (with
  `Reuses` when `reuse`); runs `idr.func(idr-rc-place)`; takes
  `SymbolTable` again, removes every clone fact, runs `shareTainted`,
  solves `Exclusivity` (re-solving per specialization round through
  `getAnalysisManager().invalidate` with `SymbolTable` preserved) and
  writes the excl grades into signatures and call results; runs
  `idr.func(idr-rc-commit)`; takes `SymbolTable` again and erases every
  original that grade specialization copied and nothing uses. Copies are
  `<f>.excl`, keep their origin's `instance` and carry no `clone`.
  `IdrRc` keeps the options `reuse` and `sink` and the statistics
  `borrowed`, `exclusive`, `takes`, `reuses`, `dups`, `drops`; U14
  builds `createIdrRc(IdrRcOptions{reuse, sink})`.
- **R19. The tail passes' anchors** (C1.3). `idr-accumulate` and
  `idr-trmc` are module passes that plan and rewrite one function at a
  time in module order and insert `<f>.acc` and `<f>.trmc`, copying
  every attribute but `clone`; `idr-tail-loops` is a function pass that
  reads its declarations by `declarationOf` and `constructorOf`;
  `idr-returned-arguments` computes `Returned` and nests its rewrite.
  Today's names of the statistics and options stay.
- **R20. `idr-tail-calls`** (C1.3, C1.4). A module pass, last in the
  pipeline: `TailCallPlan`, its counts copied into the statistics, then
  a rewrite nested over `llvm.func`, then a count of `musttail` calls.
  Its LLVM tail-position test is its own (`TailPosition.cpp`), not
  `INC/Analysis/Tail.h`.
- **R21. The pipeline** (C1.4, C5). The five anchorless upstream
  lowering passes run per function; `idr-target` runs first in the
  driver's manager; `--without` names top-level steps and the options
  `reuse`, `sink` and `in-place`; dumps follow top-level passes, named
  and numbered as C1.4 says.
- **R22. The inliner** (C3.3, C1.2). The dialect's inliner interface
  mirrors func's; the component pipeline runs only on a callable an
  iteration inlined into; inlining decides exactly as today; the
  dialect depends on `cf` and no longer on `func`.
- **R23. The loop's instrumentation** (C3.1, C5, C8.1). Added by the
  manager's owner in idris-mlir and idris-mlir-opt; `idr-simplify`
  fails without it; it emits the remarks, the statistics remark, the
  round's frame and the plots. U23's `addInstrumentation` emits zones
  only.
- **R24. Ranges and Lengths** (C1.1, C1.3, C2.1). `idr::Ranges`
  (IdrAnalysis, U11) is the seeded interprocedural solver, read by
  `idr-narrow`, `idr-narrow-words` and `idr-in-bounds`; the free
  `runSolver` and `rangeOf` of `IDR/Narrow` go. `idr::inbounds::Lengths`
  is private to `IdrInBounds`, its constructor taking `Ranges` and the
  `SymbolTable`; `accessedArray` is in `INC/Transforms/InBounds.h`,
  which U15 includes (`IdrExpect` links `IdrInBounds`). The `Built`
  origin replaces `callOrigin`'s rewalk, and the same guards are proved:
  a fixture that proved only through the rewalk is kept proved by the
  constructor-time table. `ValueBoundsConstraintSet` replaces nothing.
- **R25. Escapes on the sparse backward base** (C2.1). U13 reads the
  pinned `SparseAnalysis.cpp`; if the backward base visits only live
  blocks or reads `PredecessorState` outside the return rule, the solver
  loads `loadBaselineAnalyses` beside `Escapes`, else `Escapes` alone.
  The base's `SymbolTableCollection` is never filled.
- **R26. Defunctionalization as it can be done** (C2.4). C2.4 states
  U07's fixed decisions: the keys come from `Slots`, value conversions
  are tried first, signatures convert through `FuncSignaturePattern`,
  calls and returns through the lane's slot-keyed patterns, and one
  full conversion runs on the module.
- **R27. The evaluated suspension** (C1.2, C1.3, C2.4, C6.4). Every
  Delay is emitted as `idr.delay`; the dialect hoists a value body out,
  folds a force of an evaluated delay, leaves it to `idr-isolate`, and
  converts it to the memo sum's forced constructor.
- **R28. The erased grade deleted** (C0, C6.1). The owner's decision:
  each lane removes its uses; an undroppable erased position is refused
  by Translate with `unsupported (type)`; the corpus is byte-identical
  but for those refusals, which the qualification lists by name and
  count.
- **R29. The clone fact and first facts** (C1.3, C2.2, C4).
  `FuncOp::verify` checks the clone fact; a pass's own copy drops it
  (`removeCloneAttr`); every reader uses `getClone()`; a pass that
  creates an `idr.func` writes its first facts through the accessors;
  `idr-specialize` inherits a clone's effects as today and sets `clone`
  after `insert` returns the name; `idr-effects` rewrites effects on
  every function and call each round.
- **R30. The Idris side's shapes** (C1.6, C6.1). One quantity type,
  the generated `Quantity`; `Binder` a record; `TFn` and `Data` carry
  `key` and lose `idrisName`; binder names as `Shown`; the registry's
  multiplicity its own.
- **R31. Names** (C2.3, C6.3, C9.2). Readable symbols, derived
  functions by kind, mangling at `idr-lower`'s phase 0, `idr-expect`
  naming a function by symbol or by Idris definition; handoff-readable
  refuses `$<digits>$` in a symbol.
- **R32. Locations** (C6.5). C6.5 stands; every C++ reader of a source
  position reads a `FileLineColRange`'s start.
- **R33. The handoff's text** (C1.7, C7.3). The owner's decision: the
  dumps are the readability target; a generated `printOp` per dialect
  gives the declarative head, Emit appends regions and location, and
  the generic form covers what the format subset does not.
- **R34. Streaming emission** (C6.7). Emit writes the module to a
  handle through a temporary file, so no String of the whole module
  exists; the frontend's `--timing` phases follow.
- **R35. Printer names, aliases and hook owners** (C1.1, C2.3, C5,
  C7). One helper in `IDR/IR/Asm.cpp`; aliases shorten characters and
  decide nothing; the inliner interface (`idr::addInlinerInterface` in
  `INC/IR/Func.h`), `verifyOperationAttribute` and
  `verifyRegionArgAttribute` are U02's, and U01 writes no inliner
  interface; `registerIdr` and `registerCallEffects` go; U04's and
  U06's `Support` partitions go with `Support.cppm`.
- **R36. Actions** (C1.1). `INC/Support/Actions.h` is U14's, `perform`
  being `IDR/Support/Perform.cppm:15-26` unchanged in meaning (a skipped
  action leaves the IR as it was); U06 declares `idr::RaiseAction` and
  `idr::SpecializeCloneAction`, and `IdrSpecialize` links `IdrSupport`.
  `perform` runs from worker threads in `idr-redirect`; MLIR runs no
  handler unless one is installed; no lock of ours.
- **R37. Layouts** (C1.2, C2.1). Eager, immutable, `valid()`; the tag
  limit in `idr.data`'s verifier; the names `INC/IR/Layout.h` and
  `INC/Target/Target.h` publish; `Layouts::of` and `layout::stackMark`
  go. Making `Layouts`
  total is not taken.
- **R38. Remarks from function passes** (C2.0, C9.2). Diagnostics only;
  the determinism tests compare them. A data race found in the pinned
  remark engine is reported as a seam with the evidence, never fixed
  with a lock of ours.
- **R39. Profiling** (C1.4, C1.5, C5, C8). `addInstrumentation` in every
  build, adding nothing without `TRACY_ENABLE`; zones by Tracy's C API
  from one mutex-guarded instrumentation; allocation tracking behind
  `IDRIS_MLIR_PROFILE_MEMORY`.
- **R40. `Passes.td`** (C1.3). The coordinator writes it with no
  `let constructor` and today's option and statistic names but these:
  `IdrEffects` loses its scope and memo comment and its
  `dependentDialects`, describes effects on every `idr.func` and
  `idr.call`, and counts io, crash, diverge; `IdrRoundFacts` is
  `Pass<"idr-round-facts", "::mlir::ModuleOp">`, summary
  `Compute the analyses the round's function step reads`;
  `IdrSimplify` keeps `max-rounds` 64 and `rounds`, lists C3.2's round
  and says that the round's statistics are reported as
  `<pass>.<statistic>` in the loop's statistics remark;
  `IdrCanonicalize`, `IdrRcPlace` and `IdrRcCommit` are absent;
  `IdrInline` says it first prepares forces and canonicalizes only a
  function an iteration inlined into; `IdrRedirect` is U06's block;
  `IdrSpecialize`'s comment above `dependentDialects` is
  `// Clones are inserted through the module's SymbolTable analysis.`;
  `IdrBindingTimes` says `free for every parameter` for
  `not recursive`; `IdrIdentity` is anchored on `::idr::FuncOp`, counts
  `numCalls` only and reads its callee's effects; `IdrIsolate` and
  `IdrDemand` depend on `::idr::IdrDialect`, and `IdrIsolate` writes
  `total`, and `break_last` when the enclosing function has it;
  `IdrAccumulate`, `IdrTrmc`, `IdrReturnedArguments` and `IdrTailCalls`
  are anchored on `::mlir::ModuleOp`, `IdrTailLoops` on
  `::idr::FuncOp`, `IdrNarrowLanes` and `IdrVectorize` on
  `::mlir::func::FuncOp`; `IdrRc` has the options `reuse` and `sink`
  (forwarded to `idr-rc-place`), the statistics `numBorrowed`,
  `numExclusive`, `numTakes`, `numReuses`, `numDups`, `numDrops`, and
  describes the five steps; `IdrNarrow` counts `numVersioned` only and
  depends on arith, scf and ub; `IdrLower` gains one sentence on phase
  0; `IdrExpect` takes U15's restated entries.
- **R41. Arity** (C6.4). `Lam` stays unary: a partial call builds one
  closure per missing parameter, as the curried type requires.
- **R42. Covered defaults** (C6.4). Translate drops a default its
  alternatives cover; `DropCoveredDefault` goes. A covered default a
  C++ pass might still leave is a path the analyses see, never a
  miscompile.
- **R43. Corrections** (C1.3, C2.5, C5). `tailcc` is `idr-tail-calls`'
  decision, not phase 0's; the driver already reads `.mlirbc`;
  upstream's range passes replace nothing in `idr-narrow`
  (`arith-int-range-narrowing` narrows only `idr-narrow-lanes`' copy;
  `arith-unsigned-when-equivalent` is a later measurement), and value
  bounds nothing in `idr-in-bounds`. F-round-2's merge stays deferred;
  `Returned` (func stage) and `Identities` (idr stage) stay two
  analyses, and `Holds` keeps stopping at arrays, each a seam for a
  later packet.
- **R44. Confirmation at the pin** (C0). Lanes read the pinned headers
  under `.toolchain/llvm-project/mlir` for every upstream signature
  this packet recalls, write to the pinned spelling, take a named
  fallback where one is given, and report a difference in the handoff;
  no lane patches upstream. The list: the `OpAsmInterface` hooks (U01);
  `OpToOpPassAdaptor`'s preserved set and the analysis manager of a
  dynamic pipeline on the current op (every module pass with
  `runPipeline`); `AnalysisManager::invalidate` and `clear`,
  `InlinerConfig`'s clone callback and `setDefaultPipeline`, the
  `Inliner` constructor and `RunPipelineHelperTy` (U05, U08);
  `SymbolTable::insert` renaming a collision (U06, U09);
  `upliftWhileToForLoop` and `moveLoopInvariantCode` (U09);
  `walkAndApplyPatterns`' limits (fallback: the greedy driver),
  `mlir::SymbolUserMap` (fallback: one `getSymbolUses` walk bucketed by
  root reference and resolved through the `SymbolTable` analysis),
  `CallGraph`'s `GraphTraits` (U03, U04, U08, U09, U10, U12, U13); the
  sparse backward base's gating (U13); `populateIntRangeNarrowingPatterns`
  and the carried `upstream/09` patch (U11);
  `OpPrintingFlags::printNameLocAsPrefix` and the upstream lowering
  passes' constructors and anchors (U14); `mlir::tblgen::Operator`'s
  format accessors (U20, fallback: the record's fields);
  canonicalize's `test-convergence` option (U21);
  `-mlir-output-format=json` (U22).
- **R45. Split files granted now**, created only if needed and reported
  in the unit lists: U01 `IDR/IR/OpsCon.cpp` (con, field, tag, dest.of)
  and `IDR/IR/OpsMatchSyntax.cpp` (the match syntax); U06
  `IDR/Analysis/BindingTimes.cpp`; U07 `IDR/Analysis/LabelSites.cpp`;
  U13 `IDR/Analysis/IdentitiesRecord.cpp`,
  `IDR/Analysis/IdentitiesRebuilds.cpp` and
  `IDR/Analysis/EscapesCycles.cpp`.
- **R46. The declarative printer checked against the generic form**
  (C9.2). The samples cover one op per directive of the subset; the
  owned-stage fixtures' `idr.reuse` round trip covers
  `functional-type(operands, ...)`; the expected transcript holds no
  erased sample.
- **R47. Qualification** (README, Qualification). No `(A)` row of an
  analysis appears twice between two consecutive steps that both
  preserve it; per round, `(A) References` appears under `idr-effects`,
  `idr-inline` and `idr-specialize` only, `(A) Effects` under
  `idr-effects` only, `(A) Identities` under `idr-round-facts` only,
  `(A) CloneTable` and `(A) BindingTimes` under `idr-round-facts` and
  `idr-specialize` only, and no `(A)` row under a function pass. Also
  recorded: the `VerifierPass` share per round and after `idr-rc`, the
  serial residue per round, the `Canonicalizer` and `CSE` rows under
  `idr-inline`, `int-range-optimizations` nested against the module
  placement, the round counts, the peak RSS of stage 0 and of
  every-interfaces-export, the stage-0 `idr.func` count (58,305 before)
  and the corpus programs newly refused. Upstream patches that would
  remove whole-module verifies are later work, named from these
  records.
- **R48. Documents.** `findings.md`, `ownership.json`, `README.md`,
  `work-units.md`, `orchestrator.md`, `PINS.md` and `validate.sh`
  follow these rulings. `PINS.md` retires `mlir-cxx-api`,
  `zones-on-demand` and `clang-module-layout-forward-declaration`, adds
  the Tracy pin, edits `simplify-structural-fixpoint` for the loop's
  instrumentation, and keeps `inline-unreachable`. All 23 lanes are
  dispatched at once when the environment allows; where it caps
  concurrency lower, the orchestrator says so with the number and starts
  the next lane, in the order U01 to U23, as each returns.

## C11. Deleted

These leave the tree. The validator refuses, outside a dispatch's Delete
section, the names README's "Retired mechanisms" lists; the rest are
named here for the lanes that delete them.

- `SymbolScope`, `HoldMemo`, `SymbolsHeld`, `holdsSymbols`,
  `publishedScopes`, `publishedScopeOwner`, `publishedMemos`,
  `publishedMemoOwner`
- `PipelineStatistics`, `OpenRound`, `CloseRound`, `pipelineSteps`,
  `IDR/Support/Counts.cppm`
- `Idr_KnownAttributes`, `verifyDiscardableAttrs`; the discardable
  `idr.total`, `idr.break_last`, `idr.effects`, `idr.clone` and
  `idr.hole` (the attributes `#idr.effects` and `#idr.clone` stay)
- `Idr_ErasedAttr`, `!idr.erased`, `#idr.erased`, the quantity `Zero`,
  `erased()`, `isErased`, `ErasedT`, `Gone`, `Erased` (in `CS`),
  `erasedValue`
- `data Use`, `InstanceArg` and `idrisName` (in `CS`); `mangle(` (in
  `CS`), `$40$`
- `idr::lookupSymbol`, the overloads
  `holdsReferences(Type, SymbolTableCollection &, Operation *)` and
  `listCons(Operation *, Type, Type)`, `graph::SymbolUses`,
  `graph::refersTo`, the `func::CallOp` case of `consumes`
- `registerIdr`, `registerCallEffects`, `prepareForceAtCapture`,
  `DropCoveredDefault`
- `Layouts::of`, `layout::stackMark`; the free `runSolver` and `rangeOf`
  of `IDR/Narrow`
- `Mlir.cppm`, `export module`, `import idr.`, `let constructor` (in
  `Passes.td`)
- `IDRIS_MLIR_TRACY_DIR`, `TracySampling.h`
- `idr-canonicalize`, `IdrCanonicalize`
