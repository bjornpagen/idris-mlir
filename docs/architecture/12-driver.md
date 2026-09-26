# 12. Executables, commands, artifacts

## Executables

| Executable | Language | Role |
| --- | --- | --- |
| `idris-mlir` | Idris | Stock Idris driver plus the `mlir` backend. Checks the program and writes `.core` and `.mlir`. |
| `idris-mlir-opt` | C++ | `mlir-opt` with the `idr` dialect and passes registered. For tests and debugging. |
| `idris-mlir-cc` | C++ | Runs `OPT-PIPE-1` in process, from contract text to an object file. |

- **DRV-OPT-1 (p0).** `idris-mlir-opt` registers:
  - the upstream dialects and passes that `OPT-PIPE-1` uses;
  - the `idr` dialect;
  - `idr-check-input`, `idr-tail-loops` and `idr-lower`;
  - the pipeline `--idr-pipeline`, which runs steps 1–10 of `OPT-PIPE-1`.

  Otherwise it behaves like `mlir-opt`.
- **DRV-CC-1 (p0).** The command line is:

  ```sh
  idris-mlir-cc INPUT.mlir -o OUTPUT [--emit=obj|llvm|mlir] [--dump-after=PASS|all] [--dump-dir=DIR]
  ```

  - `--emit=obj` (the default) writes an ELF object file;
  - `llvm` writes LLVM IR after optimization;
  - `mlir` writes the LLVM dialect.
  - `--dump-after` writes the module after the named pass (or after every
    pass) into the dump directory as `NN-PASS.mlir`. This is how each stage's
    IR is inspected.
- **DRV-CC-2 (p0).** Exit status:
  - `0`: success, and `OUTPUT` is complete;
  - `1`: the input violates the contract, or a pass failed. The input came
    from the Idris side, so this is an internal compiler error
    (`DIAG-ICE-1`).
  - `2`: usage error.

  On failure `OUTPUT` is not created, and any existing `OUTPUT` is left
  untouched.

## Compiling a program (v0–v2)

- **DRV-FLOW-1 (v0).** A program compiles with exactly these three steps:

  ```sh
  idris-mlir --no-prelude --cg mlir --inc mlir --check Prog.idr   # → build/ttc/<v>/Prog.{core,mlir}
  idris-mlir-cc build/ttc/<v>/Prog.mlir -o build/exec/Prog.o
  <pinned gcc> build/exec/Prog.o -o build/exec/Prog
  ```

  `tools/dev.py compile Prog.idr -o Prog` runs the same steps, and the test
  harness uses that same implementation. There is only one copy of the chain.
- **DRV-FLOW-2 (v3).** From v3, the Idris backend's whole-program callback
  (`-o`) runs these steps itself, so that `idris-mlir -o prog Main.idr` alone
  produces the executable.
- **DRV-DET-1 (v0).** The same inputs and toolchain produce byte-identical
  `.core`, `.mlir`, object files and executables.
  - Test: `tests/e2e/v0/determinism`

## Artifacts

| Artifact | Written by | Contents |
| --- | --- | --- |
| `<Module>.core` | `idris-mlir` | printed `Core` (`CORE-DUMP-1`) |
| `<Module>.mlir` | `idris-mlir` | the contract (`IDR-*`) |
| `NN-PASS.mlir` | `idris-mlir-cc --dump-after` | the module after each pass |
| `Prog.o`, `Prog` | `idris-mlir-cc`, `gcc` | object file, executable |

- **DRV-ART-1 (v0).** No tool leaves a partial or stale artifact after a
  failure (`FE-ART-1`, `DRV-CC-2`).
