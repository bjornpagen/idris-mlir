# U12 — One-Shot bufferization on idr.func, with the release model

## Permitted outcome
1. Mandatory. A new module pass `idr-bufferize`, built by the generated
   `idr::createIdrBufferize()`, that runs One-Shot Bufferize on the whole
   program through upstream's module driver (as C18 generalizes it to
   `FunctionOpInterface`), with the options of C15 section 3, and leaves no
   tensor type and no `bufferization` op in the module.
2. Mandatory. External `BufferizableOpInterface` models of ours for
   `idr.func`, `idr.call`, `idr.return` (the boundaries), `idr.lin.enter`
   (a release) and `idr.lin.use`, `idr.con`, `idr.field`, `idr.force`
   (cells), `idr.match`, `idr.match_lit`, `idr.yield` (matches),
   `idr.tie_shape` and `ub.poison` (values), exactly as C15 section 4
   specifies, attached by `idr::bufferize::registerModels`.
3. Mandatory. The in-place promise of a linear array is `mustBufferizeInPlace`
   on every link of a thread, decided by the link test of C15 section 4.2
   from the IR alone: no option, attribute or flag.
4. Mandatory. Allocation is upstream's `memref.alloc` with no `alignment`
   (`bufferAlignment = 0`), copying upstream's `memref.copy` (their runtime
   meaning is C16 and C17); no ownership-based deallocation.
5. Mandatory. The pass ends with the one retyping of D42 through C01's
   `DataRemap` of kind `"buffers"` (C15 section 4.6).
6. Mandatory. Every failure is an internal error, and a copy at a link
   names the link and the conflicting read (C15 section 5); a copy forced
   at a call into a cycle of calls is a `missed` remark.
7. Mandatory. `idr::bufferize::copies`, the predicate U17's `in-place`
   property reads (C24).
8. Consumer adaptations: none outside the writes below. Every line another
   lane must add (the `def` in `Passes.td`, the include in `Pipeline.h`,
   the build list) is reported, not written.

## Owner / exclusive writes
- `IDR/Transforms/Bufferize` (`foreign/idr/lib/Transforms/Bufferize/`),
  new: `Models.h`, `Bufferize.cpp`, `Functions.cpp`, `Linear.cpp`,
  `Data.cpp`, `Values.cpp`.
- `INC/Transforms/Bufferize.h` (`foreign/idr/include/idr/Transforms/Bufferize.h`),
  new.

Nothing in these paths exists today; nothing is deleted from them.

**Excluded:**
- `INC/Transforms/Passes.td`, `IDR/Transforms/Pipeline.cpp`,
  `INC/Transforms/Pipeline.h`: U06 (C12). The `def` and the pipeline row
  are U06's, from C15 section 1.
- `IDR/Transforms/CMakeLists.txt`, `INC/Transforms/CMakeLists.txt`: the
  coordinator. Report the library of C15 section 6.
- `INC/IR/IdrOwnershipOps.td`, `INC/IR/IdrOps.td`, `INC/IR/IdrMatchOps.td`,
  `INC/IR/IdrTypes.td`, `IDR/IR/OpsScalars.cpp` (the lin folds),
  `IDR/IR/Types.cpp` (`QType::verify`), `IDR/IR/Grades.cpp`: U01 (C01, C02).
- `INC/IR/IdrArrayOps.td`, `IDR/IR/OpsArrays.cpp` (`idr.tie_shape`),
  `IDR/Transforms/StructureLoops`: U11 (C11).
- `upstream/`, `PINS.md`, `tests/upstream`: U16 (C18, the generalized
  module driver).
- `IDR/Conversion` (lowering of `memref.alloc`, `memref.copy`,
  `ub.poison`, `idr.tie_shape`): U10 (C16). `runtime/`: U19 (C17).
- `IDR/Transforms/Ownership`, `IDR/Transforms/Stack`,
  `IDR/Transforms/Demand`, `IDR/Analysis/Ownership`: U08 (C14).
- `tests/idr`, `IDR/Transforms/Expect`: U17 (C24). `tests/programs` and
  the rest of `tests/`: U18.
- The three tools and `lib/Driver`: U06.

## Read first
- `proposals/0004-compile-time/contracts.md`: C15 (yours), C18, C01,
  C02, C11, C12, C14, C16, C17, C24. Until it exists, the files in
  `proposals/0004-compile-time/contracts/`.
- 0003 §8 whole (`proposals/0003-typed-apl/README.md:1125-1259`), §7
  (`:957-1040`), §4.5 (`:791-846`), §12 (`:1429-1461`), §13
  (`:1463-1483`), §19 D17, D18, D33, D34, D42, D43 (`:1827-1946`), §20
  U1 (`:1991-2011`), §21 items 2, 3, 5 (`:2035-2052`).
- 0004 §4 stages 10 and 11 (`proposals/0004-compile-time/README.md:972-989`),
  §2.5 (what is refused, and that a broken invariant is an internal
  error), D2, D17, D19, D29 (`:1536-1590, 1644-1655`).
- Upstream, pinned (`.toolchain/build/llvm-project/mlir/`):
  - `lib/Dialect/Bufferization/Transforms/OneShotModuleBufferize.cpp`
    (whole, 652 lines): the driver you call, and the shape C18 generalizes.
  - `lib/Dialect/Bufferization/Transforms/FuncBufferizableOpInterfaceImpl.cpp`
    (whole) and its header: the models yours are shaped on, and
    `func_ext::FuncAnalysisState`.
  - `include/mlir/Dialect/Bufferization/IR/BufferizableOpInterface.td`
    (every method's contract, `:28-645`) and `BufferizableOpInterface.h`
    (`:253-431` the options and `TraversalConfig`, `:435-602`
    `AnalysisState`, `:620-764` the helpers).
  - `include/mlir/Dialect/Bufferization/IR/UnstructuredControlFlow.h`.
  - `lib/Dialect/Bufferization/IR/BufferizableOpInterface.cpp:348-487`
    (defaults), `:602-691` (`findValueInReverseUseDefChain`).
  - `lib/Dialect/Bufferization/Transforms/OneShotAnalysis.cpp:150-184`
    (where `mustBufferizeInPlace` is asked), `:1495-1569` (the
    pre-analysis check and its message), `:1634-1673`.
  - `lib/Dialect/Bufferization/Transforms/Bufferize.cpp:281-490`
    (`bufferizeOp`, `bufferizeBlockSignature`),
    `TensorCopyInsertion.cpp`, `IR/BufferizationOps.cpp:27-70`
    (`castOrReallocMemRefValue`).
  - `lib/Dialect/SCF/Transforms/BufferizableOpInterfaceImpl.cpp:321-428`
    (`scf.index_switch`), `:1127-1202` (`scf.yield`).
  - `lib/Transforms/RemoveDeadValues.cpp:199-215` (the poison it leaves).
  - `include/mlir/IR/Remarks.h:620-745` (`remark::missed`).
  - `sources/docs/mlir/docs/Bufferization.md` ("Debugging Buffer Copies",
    "Destination-Passing Style").
- The live tree: `include/idr/IR/IdrOps.td:15-100` (`idr.func`,
  `idr.call`, `idr.return`), `:200-247` (`idr.con`, `idr.field`);
  `include/idr/IR/IdrOwnershipOps.td:166-204` (the linear ops);
  `lib/IR/OpsScalars.cpp:125-145` (their folds, D43);
  `include/idr/IR/IdrMatchOps.td` (whole); `include/idr/IR/IdrClosureOps.td:91-102`
  (`idr.force`); `include/idr/IR/Grades.h` (`linear`, `unrestricted`,
  `isLinear`); `include/idr/IR/IdrTypes.td:120-160` (`QType`);
  `lib/IR/Types.cpp:15-35` (`QType::verify`);
  `include/idr/Transforms/Stack.h` and `lib/Transforms/Stack/Stack.cpp:35-45`
  (how a pass header and unit are written); `lib/Transforms/Narrow/Lanes.cpp:70-90`
  (remarks in this tree); `lib/Transforms/Inline/Inline.cpp:315-322`
  (a pass that extends `getDependentDialects`).

## Fixed decisions
- One pass, `idr-bufferize`, on `::mlir::ModuleOp`, no option; statistics
  `numAllocs "allocs"`, `numInPlace "in-place"`, `numCopies "copies"`;
  dependent dialects bufferization, memref, linalg (C12 section 2).
- The steps are upstream's `runOneShotModuleBufferize` written out
  (analysis, copies, bufferization), so the remarks and the link error sit
  between them; the retyping is the last step (C15 section 3).
- The options are C15 section 3's table, each value as given; in
  particular `bufferAlignment = 0`, identity layouts at every boundary,
  `allowReturnAllocsFromLoops = true`, upstream's default `allocationFn`
  (`memref.alloc`) and `memCpyFn` (`memref.copy`).
- `B(T)` is `getMemRefTypeWithStaticIdentityLayout(T)`: the one buffer
  type of a cell. Every boundary model (function, call, cell, wrapper)
  uses it and never consults the callee's signature for a type.
- A wrapped tensor (`!idr.lin<tensor>`) is no tensor to One-Shot. Its
  enter is a release, its use a writable root, and its type changes only
  in the retyping, with every other type that holds a tensor.
- A link is an enter whose operand's reverse use-def chain, along
  equivalent aliases only, reaches an `idr.lin.use` result (C15 4.2);
  links are `mustBufferizeInPlace`, always; heads are plain releases.
- Models answer from types and aliasing; none writes or reads an
  attribute (`bufferization.writable` is never written).
- The call model reads the module analysis only through the
  `FuncAnalysisState` extension, and with no extension answers
  conservatively without a symbol lookup, so a nested per-function
  analysis reads no sibling.
- The models are registered by the pass's `getDependentDialects`; no tool
  change.
- File layout and names: C15 section 6. The namespace is
  `idr::bufferize`; models are classes in an anonymous namespace of their
  unit; `Models.h` is internal to the directory.

## Inputs
- C18: `mlir::bufferization::func_ext::FuncAnalysisState` keyed by
  `mlir::FunctionOpInterface` (`readBbArgs`, `writtenBbArgs`,
  `aliasingReturnVals`, `equivalentFuncArgs`, `analyzedFuncOps`,
  `symbolTables`); `analyzeModuleOp`, `insertTensorCopies`,
  `bufferizeModuleOp` over every `FunctionOpInterface` op of the module,
  ordering by `CallOpInterface`, returns found as the `ReturnLike`
  terminators of the body's blocks; a function with no such terminator
  analyzed with no aliasing result instead of failing; the "all other ops"
  loop skipping `FunctionOpInterface` ops.
- C01: `idr::FuncOp`, `idr::CallOp` (with `getProperties()`),
  `idr::ReturnOp`, `idr::ConOp`, `idr::FieldOp`, `idr::ForceOp`,
  `idr::MatchOp`, `idr::MatchLitOp`, `idr::YieldOp` (parents only the two
  matches), `idr::LinEnterOp`, `idr::LinUseOp`; `idr::linear(Type)`;
  `QType` accepting `tensor<...>` and identity-layout `memref<...>`
  carriers at (one, plain); `idr::DataRemap` (C01 §7,
  `include/idr/IR/Symbols.h`): `DataRemap(module, kind, leaf)` and
  `retype(root)`.
- C11 §4: `idr::TieShapeOp` (operand 0 the shaped value, result 0 the
  same type), valid on a memref, declaring no `BufferizableOpInterface`
  in ODS. C11 §1: a value array is a ranked tensor; a linear array
  `!idr.lin<tensor<...>>`.
- C12: the `def` and row 9; `idr::impl::IdrBufferizeBase`.
- C17 and C16: the meaning of `memref.alloc` and `memref.copy` (this lane
  only emits them).
- C24: what `in-place` asks of `copies`.

## Outputs
- C15: everything in `contracts/C15-bufferization.md` (in `contracts.md`
  once assembled): the pass, `idr::createIdrBufferize()`,
  `idr::bufferize::registerModels`, `idr::bufferize::copies`, the models
  and their answers, the options, the output's promises (section 7).
- Consumers: U06 (the pipeline row and the include), U08 (memrefs from
  bufferization), U10 (what to lower), U17 (`copies`, fixtures), U19 (the
  IR its hooks serve).

## Implement
- `include/idr/Transforms/Bufferize.h`: C15 section 2 verbatim, with a
  header comment saying what the pass is.
- `lib/Transforms/Bufferize/Models.h`: the declarations C15 section 6
  lists, in `namespace idr::bufferize`.
- `Bufferize.cpp`: `GEN_PASS_DEF_IDRBUFFERIZE`; the pass struct deriving
  `idr::impl::IdrBufferizeBase`, overriding `getDependentDialects` (base,
  then `registerModels`) and `runOnOperation` (C15 section 3's steps).
  The diagnostic handler: a `ScopedDiagnosticHandler` that keeps every
  error-severity diagnostic it sees (location, message, notes) and lets
  the others through; on a failure, the link error of C15 section 5 when
  a link has a dominated read of its operand, else each kept error
  re-emitted with the `internal error: idr-bufferize: ` prefix. The
  remarks walk `idr::CallOp`s after the analysis. The retyping is
  `idr::DataRemap(module, "buffers", leaf).retype(module)`. `registerModels` (two
  `registry.addExtension(+[](MLIRContext *ctx, Dialect *) {...})`, one on
  `idr::IdrDialect` calling `attachFunctionModels`, `attachLinearModels`,
  `attachDataModels` and `attachTieShapeModel`, one on
  `mlir::ub::UBDialect` calling `attachPoisonModel`), `copies`,
  `bufferType`, `cellType`, `boundaryType`, `cellBuffer`.
  The link test is a function of `Linear.cpp` the pass also calls; declare
  it in `Models.h` as `bool isLink(idr::LinEnterOp, const
  mlir::bufferization::AnalysisState &)`.
- `Functions.cpp`: `FuncModel`, `CallModel`, `ReturnModel` (C15 4.1),
  written from upstream's `FuncBufferizableOpInterfaceImpl.cpp`,
  `attachFunctionModels`.
- `Linear.cpp`: `EnterModel`, `UseModel`, `isLink` (C15 4.2),
  `attachLinearModels`.
- `Data.cpp`: `ConModel`; one `HeapReadModel<Op>` template for
  `idr.field` and `idr.force`; one `MatchModel<Op>` template for
  `idr.match` and `idr.match_lit`; `YieldModel` (C15 4.3, 4.4);
  `attachDataModels`.
- `Values.cpp`: `TieShapeModel`, `PoisonModel` (C15 4.5),
  `attachTieShapeModel` (on the idr extension) and `attachPoisonModel`
  (on the ub extension).
- Failure paths in the models: a `getBuffer` or
  `castOrReallocMemRefValue` failure returns `failure()`; the driver turns
  it into section 5's internal error. No model emits `unsupported`.
- Comments say why each answer is what it is (a release, a heap read, a
  cell's layout), in the repository's voice, citing no document.

## Delete
Nothing exists in U12's writes to delete. The lane builds none of the
earlier array drafts' mechanisms, which 0003 and 0004 replaced: the
`--demand-in-place` option reaching bufferization, a discardable
`idr.demand_in_place` mark, a `DemandInPlace` analysis-state extension,
`unsupported (uniqueness)` for a copy at a release, a pass that rewrote
declarations' field types in place after bufferization, and the
`idr.array.alloc`/`idr.array.copy` ops as `allocationFn`/`memCpyFn`
(upstream has both; the runtime counts `memref.copy`'s elements by the
cell's description, C17 §4).

## NOT TO DO
- Do not add an option, a `PipelineOptions` field or a pass option to
  `idr-bufferize`; `--demand-in-place` and its kin are gone (D2, U06's
  deletion).
- Do not write `bufferization.writable`, `bufferization.buffer_layout` or
  any attribute of ours on any op or argument, even inside the pass.
- Do not run or add ownership-based deallocation,
  `promote-buffers-to-stack` or `buffer-deallocation-pipeline` (D18).
- Do not make `idr::QType` a `TensorLikeType`, put the grade in a
  tensor's encoding, or lower `idr.func` to `func.func` to avoid C18
  (0003 §18).
- Do not write a module driver of your own or copy upstream's: call the
  C18 functions (0003 §21 item 5).
- Do not edit `Passes.td`, `Pipeline.cpp`, `Pipeline.h`, any CMake file,
  the tools, `lib/IR`, `include/idr/IR`, `lib/Conversion` or `runtime/`;
  report the line instead.
- Do not add a tensor case to the folds of `idr.lin.enter`/`idr.lin.use`
  (D43, U01's file anyway).
- Do not re-derive One-Shot's analysis (aliasing, conflicts) in a pass of
  ours; the link error's dominated-read note is the only walk, and only on
  a failure.
- Do not report a copy at a link as `unsupported` or give it a refusal
  rule (C04): it is an internal error.
- Do not register the models from the tools or from `IdrDialect::initialize`.

## Tempting partial solutions
- Leaving `bufferAlignment` at upstream's 64: every `memref.alloc` gets
  `alignment = 64`, which idr-lower refuses as an internal error (C16
  §3, C17 §3). Rejected by: a fixture whose module after the pass holds
  `memref.alloc` with no `alignment`.
- An allocation op of ours as `allocationFn`: a second spelling of
  upstream's allocation before counting. The grade a fresh cell takes is
  counting's (C14). Rejected by review: `allocationFn` is not set.
- Letting the `idr.func` model retype `!idr.lin<tensor>` arguments only:
  wrapped block arguments, `scf.for` iter_args, match results and data
  types holding tensors stay tensors. Rejected by: the 0003 §17 stage 1
  fixture in which a linear array crosses a branch and a match's yield and
  bufferizes with its grade kept (the verifier after the pass), and a
  record holding an array that verifies after the pass.
- Making every `idr.lin.enter` `mustBufferizeInPlace`: `thaw` of a
  constant or of an array still read becomes an internal error instead of
  its copy. Rejected by: a `thaw` fixture whose argument is read after,
  which bufferizes with one `memref.copy` into a fresh `memref.alloc`.
- Marking links with an attribute in the frontend or before the pass: a
  fact in a discardable attribute (AGENTS.md). Rejected by review: the
  link test reads the IR.
- Resolving the callee in the call model under every state: a nested
  `eliminate-empty-tensors` would read sibling functions. Rejected by
  review of `CallModel` (no lookup without the extension).
- `isWritable` true on `idr.field` results: two reads of one cell's array
  would both write it in place. Rejected by: a fixture that reads one
  array field twice and writes each read, which bufferizes with a copy
  for each write.
- Reporting upstream's raw message for a link conflict: names one op, not
  both. Rejected by: the fixture of a link's buffer read after its
  release, whose expected error is at the enter with a `read here` note.

## Acceptance
- `python3 proposals/0004-compile-time/check-units.py` on the five units
  shows no error of U12's own code; an error on a declaration C01, C11 or
  C18 owns (one not in the tree yet) is reported as a seam with the
  contract it names, never worked around. A unit not yet in the build is
  reported as new.
- Source review: `Bufferize.h` matches C15 section 2; the options match
  C15 section 3; each model answers as C15 section 4 says; no string
  `"unsupported ("` and no `Option<` in U12's files; no attribute is
  written by any model; `rg 'func::FuncOp' foreign/idr/lib/Transforms/Bufferize`
  finds nothing.
- Behaviour the owner's machine checks (U17 writes the fixtures; list
  them in the handoff with NEEDS-ACCEPTANCE where the transcript is
  unknown):
  - a function that writes a linear array in a loop through a recursive
    call bufferizes with no `memref.copy` (`in-place=@f`);
  - a link whose buffer is read after its release: exit status failure,
    `internal error: idr-bufferize: the linear array released here is
    read after its release` at the enter, `read here` at the read;
  - a linear array across a `cf.br` and a match's `idr.yield` keeps
    `!idr.lin<memref<...>>` and verifies;
  - a record holding an array: its identified type after the pass holds a
    memref, and the module verifies;
  - `thaw` of an array read after: one `memref.copy` into a fresh
    `memref.alloc`;
  - after the pass, no `tensor` type and no `bufferization` op
    (`idr-expect` or `FileCheck --implicit-check-not`).
- `make test-idr` and the array programs of `tests/programs/arrays` pass
  on both targets, on the owner's machine.

## Stop and return
Return the handoff of the common obligations: the six new paths, each
mapped to an obligation above; the declarations supplied (C15); the lines
other lanes must add (U06: the `def`, row 9 and the include; the
coordinator: the `IdrBufferize` library and its links, C15 section 6);
`check-units.py`'s last lines; NEEDS-ACCEPTANCE files (none are yours to
write); and every seam: a C18, C01 or C11 declaration your code names that
the contract text does not fix, with the exact signature you coded
against. Report a contract conflict (for example C24 treating every
`memref.copy` as a copy) to the coordinator and keep working.
