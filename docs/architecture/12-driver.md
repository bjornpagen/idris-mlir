# 12. Executables, commands, artifacts

## Executables

| Executable | Language | Role |
| --- | --- | --- |
| `idris-mlir` | Idris | Stock Idris driver plus the `mlir` backend. Checks the program and writes `.core` and `.mlir`. For IO programs (`-o`) it also runs the rest of the chain. |
| `idris-mlir-opt` | C++ | `mlir-opt` with the `idr` dialect and passes registered. For tests and debugging. |
| `idris-mlir-cc` | C++ | Runs `OPT-PIPE-1` in process, from contract text to an object file, evaluating at compile time with its own JIT (`ELIM-EVAL-1`). |
| `idris-mlir-reduce` | C++ | `mlir-reduce` with the `idr` dialect and passes registered, built by `foreign/idr`: shrinks a module that makes a pass fail ([14-testing](14-testing.md)). *Since the cutover.* |

- **DRV-OPT-1 (p0).** `idris-mlir-opt` registers:
  - the upstream dialects and passes that `OPT-PIPE-1` uses;
  - the `idr` dialect;
  - the passes `idr-loop-breakers`, `idr-effects`, `idr-specialize`,
    `idr-eval`, `idr-prune`, `idr-simplify`, `idr-defunctionalize`,
    `idr-tail-loops`, `idr-check-profile` and `idr-lower` (*revised at the
    cutover*; before, `idr-check-input`, `idr-entry` and `idr-lower`), with
    their options: `idr-simplify`'s `inline-iterations` and `clone-limit`
    (`OPT-PIPE-5`, `ELIM-SPEC-2`), `idr-specialize`'s `clone-limit` and
    `idr-lower`'s `jit` (`LOW-JIT-1`);
  - the pipeline `--idr-pipeline`, which runs steps 1–10 of `OPT-PIPE-1`.

  Otherwise it behaves like `mlir-opt`: it registers every upstream dialect,
  unlike `idris-mlir-cc` (`IDR-IN-1`).
- **DRV-CC-1 (p0).** The command line is:

  ```sh
  idris-mlir-cc INPUT.mlir (-o OUTPUT | --check) [--emit=obj|asm|llvm|mlir]
                [--cpu=CPU] [--runtime=ARCHIVE] [--no-eval] [--remarks=REGEX]
                [--timing] [--dump-after=PASS|all] [--dump-dir=DIR]
  ```

  - It parses `INPUT` with a registry of exactly the contract's dialects
    (`IDR-IN-1`), and verifies the module after every pass.

  - `--emit=obj` (the default) writes an ELF object file;
  - `asm` writes the same code as assembly text (v3);
  - `llvm` writes LLVM IR after optimization;
  - `mlir` writes the LLVM dialect.
  - `--cpu` chooses the target CPU (`LOW-TARGET-1`; `x86-64-v3` by
    default).
  - `--runtime` names the runtime archive whose bitcode joins the program
    (`TC-LINK-1`); by default the one `make build` made, and `''` links
    none.
  - `--dump-after` writes the module after the named step (or after every
    step) into the dump directory as `NN-STEP.mlir`. This is how each stage's
    IR is inspected; the dump after `idr-simplify` is the module after the
    simplify loop (`TEST-ELIM-1`).
  - *Since the cutover:*
    - `--check` runs the pipeline up to `idr-check-profile` and writes
      nothing: the frontend runs it for `main : Int` programs, so that
      `idris-mlir --check` reports a profile rejection (`DIAG-EXIT-1`);
    - `--no-eval` turns `idr-eval` off (`ELIM-EVAL-1`, `TEST-EQUIV-1`);
    - `--remarks=REGEX` prints the MLIR remarks of the matching categories,
      such as `idr-eval` (`DIAG-HEAP-1`);
    - `--timing` reports the time of each pass, of JIT compilation and of
      evaluation, and of each LLVM stage.

    The pipeline's parameters are fixed (`PROF-GEN-5`): `idris-mlir-cc`
    has no option for the clone limit or the inliner's `max-iterations`,
    which only `idris-mlir-opt` sets, for tests (`DRV-OPT-1`).
- **DRV-CC-2 (p0).** Exit status:
  - `0`: success, and `OUTPUT` is complete;
  - `1`: the input violates the contract, or a pass failed. The input came
    from the Idris side, so this is an internal compiler error
    (`DIAG-ICE-1`).
  - `2`: usage error.
  - `3`: a profile rejection by `idr-check-profile` (*since the cutover*), a
    user error. The message is `unsupported (<RULE>)` with the op's
    location chain; the frontend reports it as an Idris error at the
    innermost location in user code (`DIAG-LOC-1`).
  - `4`: a compile-time evaluation the machine could not finish (`EVAL-1`,
    *since the cutover*), which the frontend reports at the call.

  On failure `OUTPUT` is not created, and any existing `OUTPUT` is left
  untouched.

## Compiling a program

- **DRV-FLOW-1 (v0).** A `main : Int` program compiles with exactly these three
  steps:

  ```sh
  idris-mlir --no-prelude --cg mlir --inc mlir --check Prog.idr   # → build/ttc/<v>/Prog.{core,mlir}
  idris-mlir-cc build/ttc/<v>/Prog.mlir -o build/exec/Prog.o
  <pinned clang> -fuse-ld=lld -static-pie -Wl,--gc-sections -Wl,--icf=all \
    build/exec/Prog.o -o build/exec/Prog -lgmp
  ```

  The link is `TC-LINK-2`'s. `tools/compile.sh` (`make compile SRC=Prog.idr
  OUT=Prog`) runs the same steps, and the test harness uses that same
  implementation. There is only one copy of the chain. *Since the
  cutover*, the first step also runs `idris-mlir-cc --check` on the
  `.mlir` it wrote, so a profile rejection fails it, with no artifact left
  (`FE-ART-1`).
- **DRV-FLOW-2 (v1).** An IO program compiles with one command:

  ```sh
  idris-mlir --no-prelude --cg mlir -o prog Main.idr
  ```

  The whole-program callback writes `build/exec/prog.core` and
  `build/exec/prog.mlir`, then runs `idris-mlir-cc` and the pinned `clang`
  itself, with `DRV-FLOW-1`'s link, and leaves `build/exec/prog`. It finds
  both tools through the toolchain paths recorded at build time, never
  through `PATH`. Any failure in the chain is reported as an Idris error; a
  failure after `.mlir` exists is an internal error (`DIAG-ICE-1`).
  `tools/compile.sh` uses this path for IO programs.
- **DRV-DUMP-1 (v1).** The Idris codegen directive `--directive dump-core`
  writes the Core after `Translate` as `01-translate.core` (*revised at the
  cutover*: `02-simplify.core`, first-order Core, is gone), into the
  directory `<output>.dump/` next to the program
  (`build/exec/prog.dump/`) or the module's TTC. `--directive dump-mlir` passes `--dump-after=all` and
  that directory to `idris-mlir-cc`.
  Together they show a program at every stage, from TT to object code.
  Two more directives exist for tests only: `--directive break-shape=<key>`
  breaks a registry entry's shape (`HOOK-SHAPE-1`,
  [17-registry](17-registry.md)), and `--directive no-eval` passes
  `--no-eval` to `idris-mlir-cc` (`TEST-EQUIV-1`).
- **DRV-DET-1 (v0).** The same inputs and toolchain produce byte-identical
  `.core`, `.mlir`, object files and executables.
  - Test: `tests/e2e/v0/determinism`

## Artifacts

| Artifact | Written by | Contents |
| --- | --- | --- |
| `<Module>.core` | `idris-mlir` | printed `Core` (`CORE-DUMP-1`) |
| `<Module>.mlir` | `idris-mlir` | the contract (`IDR-*`) |
| `NN-PASS.mlir` | `idris-mlir-cc --dump-after` | the module after each pass |
| `Prog.o`, `Prog` | `idris-mlir-cc`, the pinned `clang` | object file, executable |

- **DRV-ART-1 (v0).** No tool leaves a partial or stale artifact after a
  failure (`FE-ART-1`, `DRV-CC-2`).
