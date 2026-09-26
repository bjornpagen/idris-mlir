# 15. Roadmap

Each step ends at a stop point: the user reviews the artifacts before the
next step starts. A step's exit criteria are all required. A step does not
end on a promise to fix something later.

## p0: foundation (no Idris language features)

Scope:
1. **Toolchain.** `bootstrap-gcc`, `bootstrap-cmake`, `bootstrap-ninja`;
   `bootstrap-llvm` rebuilt with them and extended (`TC-BOOT-*`);
   `toolchain.lock.json` schema 3.
2. **cpp-starter structure.** `CMakeLists.txt` gate, `CMakePresets.json`,
   `PINS.md`, `docs/cpp-profile.md` (`TC-CPP-*`, `TC-DEV-*`).
3. **C++ skeleton.** In `foreign/idr/`: the `idr` dialect registered with no
   ops yet, `idris-mlir-opt`, and `idris-mlir-cc` running `OPT-PIPE-1` on
   upstream ops (steps 3–7 and 9–11).
4. **Harnesses.** `lit`/`FileCheck` wired into `dev.py test-idr`, `TEST-SPEC-1`,
   and `docs/architecture/VERSION`.
5. **Verification experiments.** Each result updates the spec before v0
   starts:
   - `--no-prelude` leaves `Defs.imported` empty (`FE-ENTRY-2` stage 2);
   - `scf.index_switch` on a constant canonicalizes to its selected region
     (the example in [08](08-idr-dialect.md));
   - `symbol-dce` never removes an `idr.data` still referenced by a type
     (`IDR-DATA-1`);
   - LLVM/MLIR headers compile in the cpp-starter C++26 profile (`TC-DEV-5`);
   - a 1:N conversion across `func.call` and `func.return` works in the
     pinned MLIR (`LOW-*`).
6. **Documentation.** `AGENTS.md` and `README.md` state the new structure.

Exit criteria:
- every tool is built by the pinned toolchain, with a provenance stamp;
- `idris-mlir-cc` turns a hand-written `func`/`arith` module into an
  executable that exits 42;
- `dev.py check`, `build`, `test`, `test-idr` and `test-mlir-tools` pass;
- the experiment results are recorded.

Stop point: the user sees the toolchain, the skeleton, and the experiment
results.

## v0: first-order, monomorphic, heap-free

Scope: profile v0 ([02](02-profile.md)), semantics v0 ([03](03-semantics.md)),
and the contract v0 ([08](08-idr-dialect.md)):
- **Idris side:** `Frontend.Profile`, `Frontend.Roots`, `Frontend.Translate`,
  `Core`, `Core.Check`, `Emit`.
- **C++ side:**
  - the `idr` ops with their verifiers, folders and effects;
  - `idr-check-input`, `idr-tail-loops`, `idr-lower`;
  - the index-switch pattern and the crash lowering.
- **Fixtures:**
  - the accept, reject, semantics, crash, determinism and heap-free suites;
  - programs: shapes/area, enum stepping, records, erased witnesses, mutual
    recursion, a deep tail loop.

Exit criteria:
- `TEST-SPEC-1` passes with `VERSION = v0`;
- every suite passes;
- `TEST-HEAP-1` holds for every program.

Stop point: the user and the lead read one program's IR at every stage
(`--dump-after=all`).

## v1: modules and polymorphism

Before starting: decide open question 1 (multi-module), and add `Double` and
`Char` to 03 if they are included.

Scope:
- several user modules;
- parametric data types and polymorphic functions via `Mono`
  (`ELIM-MONO-*`), with polymorphic recursion rejected;
- `control-flow-sink` added to the pipeline.

## v2: statically known higher-order code

Scope: lambdas, partial application, function arguments and user interfaces,
within `ELIM-DEFUNC-1`; `Defunc` in the middle end. No closure type in the
dialect.

## v3: IO

Before starting: decide open question 2 (the IO surface).

Scope:
- `main : IO ()`;
- world-token erasure;
- the `-o` driver path (`DRV-FLOW-2`);
- differential tests against the stock Chez backend.

## v4: a trusted Prelude subset, static vectors

Before starting: decide open question 3 (Prelude trust).

Scope:
- `Num`, `Eq` and `Ord` at machine types, through the Prelude;
- `Vect n a` with a static `n`, flattened (`ELIM-FORCE-1`).

## After v4 (to be designed, not planned)

- Recursive data, a heap, and memory management, designed from scratch as
  its own discussion. The earlier reference-counting proposal is not a
  default.
- A runtime in cpp-starter dialect code (`src/`).
- Proved rewrites ([07](07-proved-rewrites.md)).
- The constructor-set analysis and guaranteed non-self tail calls.
