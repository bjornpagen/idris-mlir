# R1 lane: the tools (`idr.driver`)

Read `README.md` beside this file first.

idris-mlir-cc becomes the module `idr.driver` (namespace `idr::driver`),
library `idr_driver`; each tool's `main` is a thin plain unit.

## Files

| File | Lines | What it holds |
|---|---|---|
| tools/idris-mlir-cc.cc | 1121 | the command line (`cl::opt` globals), `stepName`, `dump`, `writeOutput`; Cpu, `selectCpu`; the runtime: Member, `readMembers`, `markAnnotated`, `sameTarget`, `prepareMember`, `moduleFlagString`, `isPrepared`, `besideObject`, `preparedBitcode`, `readRuntime`, `nativeRuns`, `namesApart`, `linkRuntime`, `retarget`, `emit`, `externalize`, `prepare` (--prepare-runtime); Verdict, `status`, `setTarget`, `run` (the pipeline, LLVM, output); Compilation, `compile`, `runOnLargeStack`; `main`. Imports idr.target (R0) |
| tools/idris-mlir-opt.cc | 77 | UpliftWhileToFor, Invocation, `optMain`, `main` |
| tools/idris-mlir-reduce.cc | 20 | `main` |
| tools/idris-mlir-tblgen.cc | 703 | the TableGen backend that writes the Idris side's vocabulary of each dialect Emit writes (tools/dialects.sh): naming, kinds, parameters, `emitOp`, `emitDef`, `emitEnum`, `emitDiscardable`, `emitIdrisDialect`, `main` |

## Proposed map

- `idr.driver`: `:options` (every `cl::opt`, in one unit, so that their
  registration order, and with it `--help`, stays as it is), `:cpu`,
  `:output` (`dump`, `writeOutput`, `emit`), `:runtime` (reading, linking,
  retargeting and preparing the runtime: one unit per function),
  `:compile` (Verdict, `run`, `setTarget`, Compilation, `compile`,
  `runOnLargeStack`), and `idr::driver::main(argc, argv)`;
  tools/idris-mlir-cc.cc becomes a `main` that calls it.
- idris-mlir-opt.cc, idris-mlir-reduce.cc: already thin; UpliftWhileToFor
  and Invocation may move into a module (`idr.opt`) or stay if the file
  stays one concept.
- idris-mlir-tblgen: it links TableGen's libraries and none of the
  dialect's, so it cannot import idr.mlir (which links MLIR's IR). Give it
  its own pair: a module wrapping TableGen's API (`mlir/TableGen/*`,
  `llvm/TableGen/*`) as idr.mlir wraps MLIR's, its own library, and the
  generator as a module (`idr.tblgen`, namespace idr::tblgen) under 400
  lines a unit, with a thin `main`. If that is not worth it, keep it plain
  and say why; it stays on the file-size list until split.

## Imports and links

idr.driver: idr.mlir, idr.dialect, idr.target, and whatever pipeline
entry points it calls (`registerIdr`, `pipelineSteps` are global-module
declarations of idr/Idr.h, re-exported by idr.dialect). idris-mlir-cc links
`idr_driver` and `idr_dialect`; `CXX_SCAN_FOR_MODULES` is already on for
it (R0).

## Special

- --prepare-runtime: the prepared runtime must export the same symbols
  (README.md's dump script compares them); the bitcode section, the
  available_externally fast paths stay as they are.
  `IDRIS_MLIR_RUNTIME` and `IDRIS_MLIR_RUNTIME_BITCODE_SECTION` are compile
  definitions of the idris-mlir-cc target, read by two `cl::init`s: move
  them to `idr_driver`, where the units that read them are.
- Macros: `cpu_features.h` (the target entry's X-macro list),
  `idris_rt.h`, `idr/TargetEntry.h` (generated): in the global module
  fragment of each unit that uses them. Your cpu_features.h allowed line
  follows its include to the new file; it stays allowed (the runtime lane
  owns that header).
- `cl::opt` globals are static constructors in the compiler (fine: the
  runtime's archive check is about the runtime only).
- idris-mlir-cc compiles on the runtime's reserved-stack runner
  (`idris_rt_run_on_stack`, runtime/start.cc, which uses rt.platform):
  keep that path as it is.

## Allowed lines that are yours

no-local-headers:

    foreign/idr/tools/idris-mlir-cc.cc: cpu_features.h   (stays, at its new file)

file-size:

    foreign/idr/tools/idris-mlir-cc.cc
    foreign/idr/tools/idris-mlir-tblgen.cc

## Do not touch

lib/ (other lanes' and R0's modules), runtime/, include/idr/Idr.h,
CMakeLists.txt's target entry (the definitions it hands the tools stay
what they are).
