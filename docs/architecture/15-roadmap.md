# 15. Roadmap

## Status

p0, v0, v1, v2 and v3 are implemented (`docs/architecture/VERSION` is
`v3`), and so is the cutover, which changed how v3 is compiled but not the
profile's version. Everything after v3 is planned in [the plan](../plan.md), the only
plan; this file records what was done and how it differed from what was
planned.

Each step ends at a stop point: the user reviews the artifacts before the
next step starts. A step's exit criteria are all required, and a step does
not end on a promise to fix something later.

## Done

| Version | Scope |
| --- | --- |
| p0 | pinned toolchain (GCC, CMake, Ninja, LLVM/MLIR); the cpp-starter structure; the `idr` dialect skeleton; the harnesses |
| v0 | first-order, monomorphic, heap-free, pure `main : Int` programs; the `idr` v0 ops and passes; the accept, reject, semantics, crash, determinism and heap-free suites |
| v1 | IO with `do`, static strings and `Char`, polymorphism and the guaranteed eliminations (`ELIM-G-1` to `ELIM-G-9`), arity raising, output fusion, the differential suite against Chez |
| v2 | user interfaces resolved at compile time, `do` over user monads, `Double`, the math showcase, `bench/` |
| v3 | the stock Prelude imported explicitly by IO programs; `Integer`, `Nat`, lists and streams at compile time; `Data.Vect` with compile-time indices |
| after v3 | first-order Core with join points and loops (`CORE-LOOP-1`, `cf` in the contract); one driver with a whistle and generalization (`ELIM-G-19`); choices (`ELIM-G-20`) |
| the cutover | Idris does types, monomorphisation and representations; MLIR does the program: `Simplify` and first-order Core deleted; a higher-order `idr` dialect with closures, boxes, bigs and runtime strings; the simplify loop (`inline`, `idr-specialize`, `idr-eval`), `idr-defunctionalize`, `idr-tail-loops` and `idr-check-profile`; compile-time evaluation by running the program's own code in a JIT; the runtime in C, with vendored Ryu |

- **RM-V1-1. The v1 entry experiment.** Under `-o`, the definitions
  admitted by `PROF-LIB-1` and ordinary user code loaded from TTC keep
  every fact the frontend needs (`FE-TTC-2`), and `do` in a `--no-prelude`
  module desugars to the library's `>>=` and `>>`. Confirmed before v1.
- **RM-V2-1. The v2 entry experiment.** Interfaces, their superclasses and
  methods reach checked TT as records of implementations, and `Double`
  primitives behave as Chez computes them. Confirmed before v2; the
  results are in `FE-TR-6` and `SEM-DBL-*`.

## What comes next

Every value has a runtime representation since the cutover, and the
heap-free profile rejects only what would allocate (`PROF-HEAP-*`). So the
memory milestones of [the plan](../plan.md) (section 10) are "lower instead
of reject", op by op: M1 lowers boxes and runtime strings instead of
rejecting them (`PROF-DATA-3`, `PROF-HEAP-3`, `PROF-PRIM-4`), M2 bigs
(`PROF-TYPE-4`), and M3 closures that `idr-defunctionalize` cannot remove
(`PROF-HEAP-1`, `PROF-HEAP-2`, `PROF-HEAP-4`). Each rejection is withdrawn
when its op is lowered with a heap.

## History

The cutover ([the plan](../plan.md), section 1) differed from v3's rules as
follows; the profile stays v3, and each change is marked in its rule:
- Idris does types and MLIR does programs (`GOAL-P2`, `GOAL-P4`,
  `GOAL-P6`, D14). `Simplify`, its supercompiling driver, choices, arity
  raising and first-order Core are deleted: `ELIM-G-5`, `ELIM-G-17`,
  `ELIM-G-19`, `ELIM-G-20`, `CORE-INV-*`, `CORE-CHECK-1`, `CORE-OPT-1`,
  `PROF-HEAP-5`, `SEM-BIG-1`, `IDR-MOD-1`, `IDR-MATCH-1`, `IDR-MATCH-3`,
  `LOW-SWITCH-1`, `LOW-BLOCK-1` and `LOW-STR-1` are withdrawn.
- New: `ELIM-SPEC-1`, `ELIM-SPEC-2`, `ELIM-EVAL-1`, `ELIM-CLOS-1`,
  `OPT-PIPE-5`, `OPT-CALL-1`, `SEM-EVAL-6`, `SEM-EVAL-7`, `EVAL-1`,
  `SEM-HOST-1`, the `IDR-*` rules of closures, boxes, bigs, strings,
  constants and matches with regions, and the `LOW-*` rules of their
  lowering, the runtime and JIT mode.
- Compile-time evaluation runs total code only (`SEM-EVAL-6`). Four
  programs that evaluated partial code were split (`PROF-GEN-4`), and
  three reject fixtures became accepts.
- The compile-time budget (the plan's decision 13) is withdrawn: compile
  time is measured and reported, never a gate.
- `IDR-DATA-4`, `PROF-TYPE-4`, `PROF-DATA-3`, `PROF-PRIM-4`,
  `PROF-HEAP-1` to `-4`: recursive data, `Integer` and strings have
  representations, and only their dynamic allocation is rejected.
- The JIT is ORC's `LLJIT`, not `mlir::ExecutionEngine`, which aborts in a
  static musl process (`PINS.md`: `jit-lljit`).


The cleanup after v3 ([the plan](../plan.md), section 9) differed from
v3's rules as follows:
- `PROF-IO-1`, `PROF-IO-2` (withdrawn): the `idris-mlir-io` package and
  its module `IdrisMLIR.IO` are removed. Programs and tests do their IO
  through the Prelude (`PROF-IO-4`), and `DRV-FLOW-2` no longer passes
  `-p idris-mlir-io`.
- `SEM-IO-3`, `SEM-IO-5`: no profile program reaches `idr.io.get_char` or
  `idr.io.exit` any more. Their end-to-end fixtures (`echo-invalid-utf8`,
  `exit-status`) are retired, and only dialect tests remain.
- `SEM-IO-2`: the Prelude's `putChar` writes UTF-8 where the reference
  writes one byte, so fixtures now put only ASCII with it.

The driver rewrite after v3 differed from v3's rules as follows:
- `ELIM-G-19`, `ELIM-G-20` (new) replace `ELIM-G-10` to `ELIM-G-14`,
  `ELIM-G-16` and `ELIM-G-18`: one driver decides every call, and a match
  whose alternatives yield different static values is a choice.
- `PROF-HEAP-1`, `PROF-HEAP-2`, `PROF-PRIM-4`, `PROF-DATA-3`: a value
  picked at runtime from a known set is a choice and compiles; only one
  built by recursion on runtime data is rejected.
- `CORE-LOOP-1`, `LOW-BLOCK-1` (new): loops are recursive join points,
  lowered to `cf` blocks; `LOW-TAIL-1/2` and `OPT-PIPE-2` are withdrawn.

v3 differed from its plan as follows, each recorded in the rule it
changes:
- The Prelude was admitted whole rather than module by module: what the
  heap-free profile cannot express is rejected where it is used, with its
  rule, so admitting a module no longer promises that all of it compiles.
- `SEM-BIG-1`, `SEM-REC-1`, `SEM-REC-2` (new): `Integer`, recursive data
  and codata exist at compile time only, and recursive data is built
  strictly where it is written.
- `ELIM-G-12` to `ELIM-G-16` (new, since withdrawn except `ELIM-G-15`):
  calls on known arguments, library `%inline`, string join points, what is
  known about runtime strings, and complete compile-time evaluation within
  a budget.
- `SEM-CRASH-2` (new): missing cases crash, as the reference does.
- `SEM-IO-7`, `IDR-IO-2` (new): the Prelude's `getChar` reads bytes.
- `DIAG-LOC-1`: errors inside library code are reported at the user's code.
- `OPT-PIPE-4` (new): 64-byte code alignment, after a benchmark's speed
  depended on unrelated code.
v2 differed from its plan as follows, each recorded in the rule it
changes:
- `FE-TR-6` (new): implementations are compile-time values resolved during
  translation, not dictionaries eliminated later: a polymorphic method body
  cannot be translated before its type variables are known, as the v2
  entry experiment (`RM-V2-1`) showed.
- `ELIM-G-10`, `ELIM-G-11` (new, since withdrawn): functions that return
  strings, and Idris's case and with blocks, are unfolded where they are
  called.
- `OPT-PIPE-3`: loop breakers are marked `no_inline`, after the inliner
  unrolled mutual recursion; `control-flow-sink` was measured and left out.
- `PROF-HEAP-5`: moving a prefix is rejected only when an effect happens
  between building and running the action.
- `PROF-PRAG-1` allows `%default`; `PROF-LIB-1` admits `FromDouble`.
- `SEM-DBL-5`: exact decimal ties round up, as Chez does, where Ryu rounds
  to even; found by differential fuzzing.
- `SEM-DEV-2` (new): LLVM may fold or replace libm calls.
- `LOW-SEL-1` (new): selects of idr values.

p0, v0 and v1 differed from draft 2 as follows:
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

