# 15. Roadmap

Each step ends at a stop point: the user reviews the artifacts before the
next step starts. A step's exit criteria are all required, and a step does
not end on a promise to fix something later.

## p0: foundation (no Idris language features)

Scope:
1. **Toolchain.** `bootstrap-gcc`, `bootstrap-cmake`, `bootstrap-ninja`;
   `bootstrap-llvm` rebuilt with them and extended (`TC-BOOT-*`);
   `toolchain.lock.json` schema 3.
2. **cpp-starter structure.** `CMakeLists.txt` gate, `CMakePresets.json`,
   `PINS.md`, `docs/cpp-profile.md` (`TC-CPP-*`, `TC-DEV-*`).
3. **C++ skeleton.** In `foreign/idr/`: the `idr` dialect registered with no
   ops, `idris-mlir-opt`, and `idris-mlir-cc` running `OPT-PIPE-1`'s upstream
   steps.
4. **Harnesses.** `lit`/`FileCheck` in `dev.py test-idr`; `TEST-SPEC-1`;
   `docs/architecture/VERSION`.
5. **Verification experiments.** Each result updates the spec before v0
   starts:
   - `--no-prelude` leaves `Defs.imported` empty (`FE-*` stage 2);
   - `scf.index_switch` on a constant canonicalizes to its selected region;
   - `symbol-dce` leaves `idr.data` alone (`IDR-DATA-1`);
   - LLVM/MLIR headers compile in the cpp-starter C++26 profile (`TC-DEV-5`);
   - 1:N and 1:0 conversion across `func.call` and `func.return` works.
6. **Documentation.** `AGENTS.md` and `README.md` state the new structure.

Exit criteria:
- every tool is built by the pinned toolchain, with a provenance stamp;
- `idris-mlir-cc` turns a hand-written `func`/`arith` module into an
  executable that exits 42;
- all suites pass;
- the experiment results are recorded.

## v0: first-order, monomorphic, heap-free, pure

Scope: profile v0 ([02](02-profile.md)), semantics v0, and contract v0:
- **Idris side:** `Frontend.Profile`, `Frontend.Roots`, `Frontend.Translate`,
  `Core`, `Core.Check`, `Emit`.
- **C++ side:**
  - the `idr` v0 ops with their verifiers, folders and effects;
  - `idr-check-input`, `idr-tail-loops`, `idr-lower`;
  - the index-switch pattern and the crash lowering.
- **Fixtures:**
  - the accept, reject, semantics, crash, determinism and heap-free suites;
  - programs: shapes/area, enum stepping, records, erased witnesses, mutual
    recursion, a deep tail loop.

Exit criteria: `TEST-SPEC-1` passes with `VERSION = v0`, every suite passes,
and `TEST-HEAP-1` holds everywhere.

Stop point: the user and the lead read one program's IR at every stage.

## v1: hello world, the MLton core

Goal: IO programs with `do`, static strings and `Char`, compiled heap-free by
the guaranteed eliminations. This version builds the machinery everything
later relies on, so it has three internal stop points.

- **RM-V1-1. Entry experiment (before any v1 code).** Under `-o`:
  - confirm that the definitions admitted by `PROF-LIB-1`, and ordinary user
    code loaded from TTC, keep every fact the frontend needs (`FE-TTC-2`);
  - confirm that `do` in a `--no-prelude` module desugars to
    `IdrisMLIR.IO`'s `>>=` and `>>`.

  The results update 02 and 04 before implementation.

**v1a: polymorphism and eliminations on pure code.**
- `Mono`, `Simplify` (`ELIM-G-1` to `ELIM-G-6`, `ELIM-G-8`, `ELIM-G-9`), and
  `HeapCheck`.
- Fixtures: `compose`, `twice`, a `Pair`/`Maybe`-like user type, a
  `State`-style monad written with plain functions, and each `PROF-HEAP-*`
  rejection.
- Stop point: the Core before and after `Simplify`, side by side.

**v1b: the IO path.**
- The `idris-mlir-io` package (`PROF-IO-*`, `TC-LIB-1`).
- The `-o` driver path (`FE-ENTRY-4`, `DRV-FLOW-2`).
- World tokens, `idr.io.*` ops and their lowering (`LOW-IO-*`).
- Arity raising for IO.
- Fixture: hello world.
- Stop point: hello world at every stage, from TT to machine code.

**v1c: strings, characters, output fusion.**
- `ELIM-G-6` on strings, `ELIM-G-7`, `idr.str.lit`, `idr.to_char`, `put_int`,
  `get_char`.
- Fixtures:
  - `putStrLn` of literals and branches;
  - printing numbers;
  - an echo loop over stdin;
  - multi-module programs;
  - `TEST-DIFF-1` against stock Chez for every IO fixture.

Exit criteria:
- `TEST-SPEC-1` passes with `VERSION = v1`;
- every suite, including the differential suite, passes;
- `TEST-HEAP-1` holds everywhere.

## v2: interfaces and monads in general

Scope:
- user-defined interfaces, whose dictionaries are static records removed by
  `ELIM-G-2` and `ELIM-G-3`;
- `do` over any user monad through a user-defined `Monad` interface;
- `Double`, specified in 03 first;
- `control-flow-sink` in the pipeline.

## v3 onward: the Prelude's dependencies, layer by layer

The Prelude is deferred like GC (D15). Its modules are admitted bottom-up,
each imported explicitly, and each only once it is fully covered by the test
suite:
- first the non-recursive parts of `Prelude.Basics`, `Prelude.Types`,
  `Prelude.Ops` and `Prelude.Interfaces` (`Bool`, `Maybe`, `Either`, and
  `Num`/`Eq`/`Ord` at machine types);
- then the rest, as far as the heap-free profile allows.

Each layer is a profile version with its own rules and exit criteria. The
stock Prelude imported implicitly is not a goal until memory management
exists.

## After the memory design (to be designed, not planned)

- Recursive data, a heap, and memory management, designed from scratch as
  their own discussion. The earlier reference-counting proposal is not a
  default.
- Strings built at runtime, and escape analysis that puts bounded,
  non-escaping values on the stack.
- A runtime in cpp-starter dialect code (`src/`).
- Proved rewrites ([07](07-proved-rewrites.md)).
- Constructor-set analysis, and guaranteed non-self tail calls.
