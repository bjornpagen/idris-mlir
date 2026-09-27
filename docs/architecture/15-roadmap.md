# 15. Roadmap

## Status

p0, v0, v1 and v2 are implemented (`docs/architecture/VERSION` is `v2`),
and the first layer of v3 is in place: `Integer` at compile time
(`SEM-BIG-1`), recursive data at compile time (`SEM-REC-1`), missing cases
that crash (`SEM-CRASH-2`), static control decided during specialization
(`ELIM-G-12`, `ELIM-G-13`), string join points (`ELIM-G-14`), and the stock
Prelude imported explicitly by IO programs (`PROF-PROG-4`,
`tests/e2e/v3/prelude`). What remains before
`VERSION = v3` is in `docs/research/v3-entry.md`.
v2 differs from its plan below as follows, each recorded in the rule it
changes:
- `FE-TR-6` (new): implementations are compile-time values resolved during
  translation, not dictionaries eliminated later: a polymorphic method body
  cannot be translated before its type variables are known
  (`docs/research/v2-entry.md`).
- `ELIM-G-10`, `ELIM-G-11` (new): functions that return strings, and Idris's
  case and with blocks, are unfolded where they are called.
- `OPT-PIPE-3`: loop breakers are marked `no_inline`, after the inliner
  unrolled mutual recursion; `control-flow-sink` was measured and left out.
- `PROF-HEAP-5`: moving a prefix is rejected only when an effect happens
  between building and running the action.
- `PROF-PRAG-1` allows `%default`; `PROF-LIB-1` admits `FromDouble`.
- `SEM-DBL-5`: exact decimal ties round up, as Chez does, where Ryu rounds
  to even; found by differential fuzzing.
- `SEM-DEV-2` (new): LLVM may fold or replace libm calls.
- `LOW-SEL-1` (new): selects of idr values.

p0, v0 and v1 differ from draft 2 as follows:
- `PROF-FN-5` (contract): only missing cases are rejected; a function that
  divides is declared `partial`.
- `LOW-TAIL-4` (new): loops made from recursion carry `idr.may_loop`, after
  MLIR deleted an infinite loop.
- `PROF-ESC-1`: escape hatches are also found lexically.
- `PROF-HEAP-4`: growth is detected by homeomorphic embedding.
- `PROF-LIB-1`: the literal interfaces and their default hints are admitted.
- `OPT-PIPE-1`, `OPT-PIPE-2`: `idr-entry` added; `idr-tail-loops` after
  `inline`.
- `CORE-PASS-1`: `Mono` is fused into `Translate`.
- `LOW-SWITCH-1`, `LOW-IO-1`, `LOW-CRASH-1`: upstream conversion, no
  `EINTR` loop, a crash helper.
- `FE-TR-1`, `DIAG-LOC-1`: TTC keeps neither `let` types nor term
  locations.
- `TC-DEV-3`: the lint graph is deferred (`PINS.md`).

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
- **Idris side:** `Frontend.Profile`, `Frontend.Main`, `Frontend.Translate`,
  `Core` (`Term`, `Code`) and its checks, `Emit`.
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
- `Mono` and `Simplify` (`ELIM-G-1` to `ELIM-G-6`, `ELIM-G-8`, `ELIM-G-9`,
  and `PROF-HEAP-*`).
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
- `control-flow-sink` in the pipeline (measured, no effect, left out:
  `OPT-PIPE-1`).

Exit criteria, met:
- `TEST-SPEC-1` passes with `VERSION = v2`;
- every suite passes, including the differential suite against Chez;
- `TEST-HEAP-1` holds everywhere, with the libm functions of `LOW-EXT-1`;
- `bench/` runs, and its outputs agree across all four compilers.

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
