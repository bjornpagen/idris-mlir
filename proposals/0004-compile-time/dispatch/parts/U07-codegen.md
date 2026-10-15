# U07 — Code generation in size-balanced bins, in parallel, and the vectorization schedule

## Permitted outcome

1. Mandatory. After O3 the optimized program is partitioned into bins of
   call-graph components grouped by top-level namespace and cut by content
   hash at 2^15 LLVM instructions (D20, D26, D41): `Partition::of` in
   `IDR/Target/Partition.cpp`, a function of the module's content alone.
2. Mandatory. Every symbol another bin names becomes external, hidden,
   dso_local, under the reserved prefix `__idr.`; symbols read inside one
   bin stay internal; a private `unnamed_addr` constant is copied into each
   bin that reads it; every `musttail` caller sits in its callee's bin
   (D33); module inline assembly is in the first bin.
3. Mandatory. Code generation per bin on the driver's thread pool, S2's
   shape (D21): the module written once as bitcode, each bin read lazily
   in an `LLVMContext` of its own, one object per bin, largest started
   first; `writeObjects` in `IDR/Driver/Artifacts.cpp`.
4. Mandatory. Without `-c` a compilation leaves one object per bin,
   `<base>.<bin>.o`, listed in `Artifacts::objects` in bin-name order, which
   the link passes (0004 §5.3 item 6); with `-c` the objects are one
   archive at `-o` in bin-name order, LLVM's deterministic mode, the
   archive kind of the triple (D32). `Artifacts::archivePath` (with `-c`)
   and `objects` replace `objectPath`; `emit` stays for the prepared
   runtime's one object.
5. Mandatory. idr-target writes the module's
   `dlti.target_system_spec` with the CPU's `max_vector_op_width`, LLVM's
   answer for the entry's CPU (0003 §7.1, D29); `vectorBits` goes.
6. Mandatory. The vectorization schedule (0003 D20, D29, stage 1): one
   library of ours in `IDR/Target/Schedules.cpp`, parsed once per context
   into the transform dialect's library module, entry point
   `idr.vectorization` (`vectorizeSchedule`), with one transform op of
   ours, `transform.idr.vectorize_lanes`, that computes each loop over an
   array on the target's lanes; `registerScheduleLibrary` puts both on a
   registry.
7. Mandatory. The output is the same bytes at 1, 2 and 8 threads: the
   bin count and every name depend on the module, never on `--num-threads`.

Consumer adaptations this lane makes: none outside its writes. The lines
other lanes write against C13 are listed under Outputs.

## Owner / exclusive writes

- `INC/Target/Target.h` (changed): every declaration of C13 §2.
- `IDR/Target/Target.cpp` (changed): idr-target, plus the vector width.
- `IDR/Target/Optimize.cpp`: unchanged (`machine`, `optimize`).
- `IDR/Target/Schedules.cpp` (new): the library, its loading, the op.
- `IDR/Target/Partition.cpp` (new): `Partition`.
- `IDR/Target/Vectors.cpp`, `IDR/Target/TargetOptions.cpp`: owned and not
  created (C13 §1).
- `INC/Target/ScheduleOps.td` (new): the ODS of
  `transform.idr.vectorize_lanes`, C13 §4's text.
- `INC/Driver/Artifacts.h`, `IDR/Driver/Artifacts.cpp` (changed): the
  files of a compilation (the handoff `<base>.mlirbc`, C22), `emit`,
  `writeObjects`.

**Excluded:** `IDR/Driver/Run.cpp`, `Compile.cpp`, `Main.cpp`,
`Prepare.cpp`, `INC/Driver/Compile.h`, `INC/Transforms/Passes.td`,
`IDR/Transforms/Pipeline.cpp`, the three tools (U06, which writes every
call into C13); `IDR/Target/CMakeLists.txt`, `foreign/idr/lib/CMakeLists.txt`,
`foreign/idr/include/idr/Target/CMakeLists.txt` (coordinator: the build and
tablegen lines); `IDR/Transforms/Vectorize`, `IDR/Transforms/Narrow`
(U09); `INC/IR/Symbols.h` (U01, C21); `INC/Support/Scc.h` (U03);
`INC/Support/Profile.h` (U06); `IDR/Conversion` (U10); every test (U17,
U18).

## Read first

- `contracts.md` (until it exists, `contracts/`): C13 whole; C12 §3 row 20
  and §5; C21 §1-2; C16 for the static data names under `__idr.`.
- 0004 `README.md` §5 (lines 1026-1227), §4 stages 13-16 and the
  determinism rules (999-1024), D20, D21, D26, D30, D32, D33, D41 (§11).
- 0003 `README.md` §7 (957-1040), §7.1 (1041-1100), D20, D29, §15's target
  row.
- Our code: `lib/Target/Target.cpp:1-87`, `Optimize.cpp:1-60`,
  `include/idr/Target/Target.h:1-51`, `lib/Driver/Artifacts.cpp:1-104`,
  `include/idr/Driver/Artifacts.h:1-81`, `lib/Driver/Run.cpp:143-216`
  (stage 13, the pool at 228-239), `Compile.cpp:65-113` (the link),
  `Prepare.cpp:38-153` (the runtime's one object), `LinkRuntime.cpp:130-145`,
  `ReadRuntime.cpp:127-166`, `lib/Transforms/Vectorize/Vectorize.cpp:1-204`
  (the logic the op takes), `lib/Transforms/Pipeline.cpp:134-147`,
  `include/idr/Support/Scc.h:1-56`, `include/idr/Support/Profile.h:44-81`,
  `include/idr/Conversion/Mangle.h:15-20`, `tests/spec/file-size/run`
  (400 lines a unit), `tests/spec/mlir-layout/run:93-104` (no static
  mutable state, no `std::atomic`).
- Upstream: `L/lib/LTO/LTOBackend.cpp:517-570`;
  `L/include/llvm/Bitcode/BitcodeReader.h:195-214`;
  `L/lib/Bitcode/Writer/BitcodeWriter.cpp:1683-1798`;
  `L/lib/IR/Function.cpp:610-638`; `L/include/llvm/Object/ArchiveWriter.h:21-68`;
  `L/lib/Object/Archive.cpp:1098-1108`; `L/include/llvm/Support/ThreadPool.h`
  (`ThreadPoolTaskGroup`); `L/lib/Transforms/Utils/SplitModule.cpp:114-296`;
  `L/lib/Passes/PassBuilderPipelines.cpp:1380-1390`;
  `M/lib/Dialect/DLTI/DLTI.cpp:523-607`; `M/lib/Interfaces/DataLayoutInterfaces.cpp:760-778`;
  `M/include/mlir/Dialect/Transform/IR/TransformDialect.td:93-101`;
  `M/lib/Dialect/Transform/Transforms/InterpreterPass.cpp:129-153`;
  `M/include/mlir/Dialect/Linalg/TransformOps/LinalgTransformOps.td:2264-2340, 2605-2660`;
  `M/lib/Dialect/Linalg/TransformOps/DialectExtension.cpp:27-60` (an
  extension's shape); `M/lib/Dialect/Vector/TransformOps/VectorTransformOps.cpp:81-121`.

## Fixed decisions

- The files are C13 §1's. Every declaration other lanes use is in
  `Target.h` or `Artifacts.h`, exactly as C13 §2 writes it.
- The bin target is `binInstructions = 2^15` (D26); D41's cut uses
  `binInstructions / 4` and `2 * binInstructions`; the hash test is
  `hash / 2^49 < size`, exact because the target is a power of two.
- A part's hash and a bin's name are C21's `contentHash` of the sorted
  node names joined by `\n`; the part hash is read back as a number. No
  second implementation of the hash.
- The graph is the reference graph of definitions (calls and every other
  use through constants); copied constants are no node; aliases go with
  their base object; components come from `idr::components`.
- Without `-c` the objects are files `<base>.<bin>.o`, named by
  `Artifacts::addObject` and armed when named; with `-c` they are one
  archive at `-o`, members `<bin name>.o`. Link order and archive order are
  bin-name order. These are the names U06 already calls: `writeObjects`,
  `Artifacts::objects`, `registerScheduleLibrary`, `vectorizeSchedule`.
- S2 only: the split is after the whole-module O3 and the runtime's
  bodies were linked before it (`Run.cpp:182-193`); no available_externally
  definition survives O3, and none is linked per bin.
- The pool is the one the caller passes (the context's); tasks write
  only their own slot; no `std::atomic`, no `thread_local`, no static
  mutable state.
- The schedule's per-loop logic is today's (`Vectorize.cpp:60-165`) with
  one change: lanes on the last parallel dimension, 1 on every other, and
  the lane dimension's loop is the one peeled. The width is read with
  `mlir::DataLayout`, never `transform.dlti.query` (C13 §3 says why).
- The schedule's clean step is three upstream pattern ops; no
  canonicalization runs inside the schedule.
- `transform.idr.vectorize_lanes` is a gap filled by ours, ratified by the
  owner: it goes when upstream can express the schedule (C13 §4); its
  `.td` comment says so.
- Idris source's module is `<base>.mlirbc` (C22).
- Remarks `Vectorized` and `Scalar`, category `idr-lanes`.
- Internal errors are those C13 names: an appending global, a position
  count that differs, two bins with one name, a taken or empty promoted
  name, a dropped symbol still used, a tile that does not vectorize, a
  module without the width, a library that does not load.

## Inputs

- C12: `IdrTarget`'s declaration from Passes.td (`GEN_PASS_DECL_IDRTARGET`,
  `GEN_PASS_DEF_IDRTARGET`); `Report.h`'s `Report` and `cannotWrite`;
  `Profile.h`'s `IDR_ZONE_IN` and `ThreadTrace` (C12 §5); row 20 of the
  pipeline, where the interpreter runs the entry point.
- C21: `std::string idr::contentHash(llvm::StringRef key)` in
  `include/idr/IR/Symbols.h`.
- C16: static data are named `__idr.<what>.<hash>`; this lane keeps such
  a name when it promotes the symbol.
- C22: the handoff is MLIR bytecode, `<base>.mlirbc`.
- `include/idr/Support/Scc.h:23-24` (`idr::components`), as it stands.

## Outputs

- C13, whole: `Target.h` (`machine`, `optimize`, `cpuDevice`,
  `vectorWidthKey`, `vectorizeSchedule`, `registerScheduleLibrary`,
  `binInstructions`, `Bin`, `Partition`), `Artifacts.h` (`archivePath`,
  `objects`, `addObject`, `emit`, `writeObjects`), idr-target's DLTI
  attribute, the library and `transform.idr.vectorize_lanes`, the loop
  form the schedule leaves.
- Consumers: U06 (the `writeObjects` call in `Run.cpp`, the link's
  `objects`, `registerScheduleLibrary` in the three tools, row 20's entry
  point, `IdrTarget`'s description); U09 (the loop form); U10 (names kept
  under `__idr.`); U17 (fixtures run `--idr-target` before the schedule);
  U18 (artifact names, archive readers, bin counts, the inline assembly
  record, D33's two-bin program, D41's edit fixture, determinism); the
  coordinator (C13 §7's build and tablegen lines).

## Implement

**`Target.h`.** C13 §2's text with comments that say why. Keep
`GEN_PASS_DECL_IDRTARGET`. Forward-declare `llvm::Module`,
`llvm::Target`, `llvm::Triple`, `mlir::DialectRegistry`; include
`llvm/Support/Error.h`, `llvm/ADT/SmallVector.h`, `llvm/ADT/ArrayRef.h`,
`llvm/Target/TargetMachine.h` and the standard headers it names.

**`Target.cpp`.** Keep `TargetPass::runOnOperation` (`:40-72`). After the
data layout, a static `vectorWidth(const llvm::TargetMachine &)`: a scratch
`llvm::LLVMContext` and `llvm::Module` with the machine's triple and data
layout, a declared `void()` function, and
`machine.getTargetTransformInfo(function).getRegisterBitWidth(llvm::TargetTransformInfo::RGK_FixedWidthVector).getFixedValue()`.
Write `TargetSystemSpecAttr` of one entry `cpuDevice` →
`TargetDeviceSpecAttr` of one entry `vectorWidthKey` → `IntegerAttr` i64,
under `DLTIDialect::kTargetSystemDescAttrName`. Delete `vectorBits`.

**`Schedules.cpp`.** The library text of C13 §4 as two
`llvm::StringLiteral`s around the entry point's name, spliced from
`vectorizeSchedule` when the library is parsed. `idr/Target/ScheduleOps.h.inc` and `idr/Target/ScheduleOps.cpp.inc`
under `GET_OP_CLASSES`. `VectorizeLanesOp::getEffects`: `consumesHandle`
of the target, `producesHandle` of the result, `modifiesPayload`.
`VectorizeLanesOp::apply`: for each payload op, the per-generic function
of C13 §4 on the `TransformRewriter` (so handles track the rewrite): the
widest word, the width from `DataLayout::closest(op).getDevicePropertyValue`,
the sizes, `linalg::vectorizeOpPrecondition` on the check sizes,
`scf::tileUsingSCF`, `rewriter.replaceOp(op, tiled->replacements)`, the
lane loop `tiled->loops[laneDim]` (an internal error when the loop count
is not the rank), `scf::peelForLoopAndSimplifyBounds`, `linalg::vectorize`
on each tile of the peeled loop (`assumeDynamicDimsMatchVecSizes = true`)
and of the remainder (`false`), `rewriter.replaceOp(tile, replacements)`.
The result holds each function vectorized once. The two extensions and
`registerScheduleLibrary` (`registry.addExtensions<ScheduleOps, ScheduleLibrary>()`),
each with `MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID`.

**`Partition.cpp`.** C13 §5 in this order: positions; appending globals
refused; kinds; refs (a small walk over constants with a visited set);
node edges through copies and aliases; `idr::components`; an
`llvm::EquivalenceClasses<unsigned>` over nodes, each component's members
joined, then the joins;
parts with size, key, hash, group; sort; cut; bins named, sorted by name,
checked distinct; each symbol's bin and each bin's members (aliases with
their base object); then promotion over every bin's direct references
through the copies it holds; renames checked against
`Module::getNamedValue`. `extract`: C13 §5's closing paragraph; errors
are `llvm::createStringError` with the internal error's words.

**`Artifacts.h`, `Artifacts.cpp`.** `archivePath` and `objects` as C13
§2 says; `paths` holds the archive with `-c` in place of the object;
`addObject(bin)` names `<base>.<bin>.o`, appends it to `objects` and
`paths`, and arms a remover for it once the artifacts are armed (an
`armed` member set by `arm`). A static `objectCode(llvm::Module &,
llvm::TargetMachine &, llvm::raw_pwrite_stream &)` that `emit` and the
tasks share. `writeObjects` as C13 §6: `Partition::of` (its Error reported
as `internal error: ...`), the bitcode into a `std::string`, a
`std::vector` of per-bin slots (the object bytes, or the failure text),
the task group, the reports in bin order, then each object written whole
at `addObject`, or the archive through `llvm::writeArchive`.

## Delete

- `idr::target::vectorBits` (`Target.h:42-47`, `Target.cpp:78-87`), the
  per-triple lane width idr-vectorize read, with its comment; 0003 §15's
  target row.
- `Artifacts::objectPath` and the comment that names one object
  (`Artifacts.h:31-38, 62`), and the one-object code generation of a
  program: `emit` stays only for the runtime.
- Today's tile shape of the vectorizer (every parallel dimension at the
  lanes, the outermost loop peeled, `Vectorize.cpp:103-146`) does not
  move into the op; the op takes the shape C13 §4 fixes.

## NOT TO DO

- Do not edit `Run.cpp`, `Compile.cpp`, `Prepare.cpp`, the tools,
  `Passes.td` or `Pipeline.cpp` (U06): every call into C13 is U06's line.
- Do not write a CMakeLists: report the build and tablegen lines of C13
  §4 and §7 as seams.
- Do not use `llvm::SplitModule` or `CloneModule` (D21: their serial work
  grows with bins times module size).
- Do not split before O3, translate per unit, link the runtime's bitcode
  per unit, or emit cross-unit attributes: §5.4's second step.
- Do not write the tile-and-fuse schedule or `L1_cache_size_in_bytes`
  (0003 stage 3).
- Do not keep idr-vectorize, `vectorBits` or a lane width anywhere but
  idr-target's attribute; do not touch `IDR/Transforms/Vectorize` or
  `Narrow` (U09).
- Do not copy XXH3 or format hex digits yourself (C21 owns the hash).
- Do not add an option, a bin count from `--num-threads`, an environment
  variable or a mode (D2).
- Do not write tests or expected files (U17, U18).

## Tempting partial solutions

- **Bins as many as threads.** Rejected: the objects would change with
  `--num-threads`; acceptance needs the objects byte-identical at 1, 2
  and 8 threads.
- **`SplitModule` with a callback that writes bitcode per part.**
  Rejected: D21; the serial clone loop is what this design keeps out.
- **Bin objects in a temporary directory, removed after the link.**
  Rejected: the build's objects are an artifact the tests read
  (`tests/lib/e2e.sh:126`), named from the base like every other file.
- **Bin names from their position in the cut.** Rejected: a name made
  from a counter (D18); one edit would rename every later bin.
- **Keeping `transform.dlti.query` in the library.** Rejected: on our
  modules it stops at `dlti.dl_spec` (C13 §3), so the schedule would fail
  on every function.
- **A script without an op of ours, vectorizing full tiles only and
  leaving remainders as generics.** Rejected: C24's `vectorized` fails on
  a generic with a parallel dimension and a body of words, and no script
  can name the sizes at every rank (C13 §4).
- **Canonicalizing inside the schedule.** Rejected: a second
  canonicalization configuration beside `idr::createCanonicalizerPass()`.
- **A defaulted width (128) when the module has none.** Rejected: a
  fallback; a module without idr-target's attribute is an internal error.
- **Checking after the cut that no `musttail` crosses bins.** Rejected:
  the join makes it unexpressible; a check would validate and discard.

## Acceptance

- `python3 proposals/0004-compile-time/check-units.py
  foreign/idr/lib/Target/Target.cpp foreign/idr/lib/Target/Optimize.cpp
  foreign/idr/lib/Driver/Artifacts.cpp` passes, apart from failures that
  name a missing C21 or C12 declaration; `Schedules.cpp` and
  `Partition.cpp` are new (the script says so) and are syntax-checked with
  the flags of `Target.cpp`'s compile command, with the op's
  `.inc` generated into a scratch directory and C21's header missing.
- Source review: no `vectorBits`, `objectPath` or `SplitModule` in the
  writes; U06's calls (`Run.cpp:167, 246`, `Compile.cpp:68`,
  `Pipeline.cpp:94`, the two tools) compile against `Target.h` and
  `Artifacts.h` as written; no `std::atomic`, `thread_local` or static
  mutable variable; no
  unit over 400 lines; `binInstructions` the one number of the cut, with
  its quarter and double; no name made from a counter or a position; the
  library text is C13 §4's.
- On the owner's machine (listed for U18 and the coordinator, not run
  here): every program's expected output unchanged; `tests/determinism`
  at 1, 2 and 8 threads byte-identical over the objects, the `-c` archive
  and the executable; each corpus program's bin count recorded; the inline
  assembly record on both targets; D33's two-bin tail-call program runs;
  D41's edit fixture keeps every other bin's members; the bench's compile
  times within 5% and runtimes within 2% (0004 §10), spectral-norm-linear's
  vectors kept.

## Stop and return

Return the handoff the common obligations define when C13's declarations
are written in the ten owned paths (seven written, `Optimize.cpp` as it
is, two absent), the
check-units run and the manual syntax checks are reported with their last
lines, and the seams are listed: the build and tablegen lines of C13 §7
(coordinator); any C21, C12 or `Scc.h` declaration
that differs from what C13 assumes. Report an ownership conflict with
the exact path and keep working on the rest.
