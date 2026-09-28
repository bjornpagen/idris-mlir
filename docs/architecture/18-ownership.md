# 18. Who owns what

*Informative.* This note lists every component of the compiler, where it
comes from, and how much of it is ours. It follows `GOAL-3`: stand on
existing infrastructure, and write only what neither Idris nor MLIR and
LLVM provide.

Three kinds of ownership:
- **borrowed**: an upstream component used as it is, pinned
  ([11-toolchain](11-toolchain.md));
- **ported**: a published technique, reimplemented here on borrowed
  infrastructure, with its source named;
- **original**: designed here.

Only three things are original:
- **the glue**: the `idr` contract ([08](08-idr-dialect.md)), and the
  code that connects the parts (`Translate`, `Emit`, the pipeline's
  order, the registry);
- **the guarantees**: the profile, whose rules reject what the compiler
  cannot deliver within them, with a named rule ([02](02-profile.md));
  today the heap-free rules (`idr-check-profile`), later `MEM-LIN-1` and
  `ELIM-FIN-1` ([the plan](../plan.md));
- **compile-time evaluation as runtime evaluation run early**: total code
  is always evaluated, partial code never, by running the program's own
  lowered code with its own runtime (`SEM-EVAL-6`).

## The Idris side

| Component | What it does | Upstream | Ownership |
| --- | --- | --- | --- |
| Parsing, elaboration, type checking, totality, quantities | checked TT and `Defs` | Idris 2, at the pinned gitlink | borrowed, unmodified |
| The backend registration and the incremental and whole-program callbacks | `idris-mlir` is stock Idris with one backend | Idris's `mainWithCodegens` | borrowed |
| `Frontend.Profile` | the profile's checks on TT | ours; Idris's lexer and flags | original (the guarantees) |
| `Frontend.Translate` | TT to full Core; monomorphisation; representations | MLton's and Futhark's monomorphisers; Idris's normalizer; Idris's `ZERO`/`SUCC` flags | ported, on borrowed normalization |
| Full Core (`Term a`, `TermF`) | the Idris IR | Bird and Paterson's nested datatypes; base's `Deriving.*` | ported; derivations borrowed |
| The registry | privileged knowledge of library definitions | ours | original (glue) |
| `Emit` | full Core to the contract's text | ours | original (glue) |
| Loop breakers | cut the call graph's cycles for the inliner | GHC's inliner (Peyton Jones and Marlow) | ported |

## The MLIR side

| Component | What it does | Upstream | Ownership |
| --- | --- | --- | --- |
| The `idr` dialect's machinery: ODS, traits, interfaces, verifiers, the parser and printer | the contract as MLIR | MLIR | borrowed; the op set is original (glue) |
| Folders and canonicalizations: known constructor, beta, case-of-case, output fusion | shrink the program | MLIR's `canonicalize` and DRR; GHC's and Lean's simplifiers | ported, on borrowed drivers |
| `inline`, `sccp`, `cse`, `symbol-dce`, `remove-dead-values`, `int-range-optimizations` | generic optimization | MLIR | borrowed |
| `idr-effects` | effect and crash facts over the call graph | Lean's function facts | ported |
| `idr-specialize` | specialization on constant-like arguments | Futhark's defunctionalisation by static values, Lean's `fixedHO`, call-pattern specialization; generalization from offline partial evaluation | ported |
| `idr-eval` | compile-time evaluation | ORC's `LLJIT`; the executable's own lowering and runtime | borrowed JIT; the rule is original |
| `idr-defunctionalize` | closures to sums | Reynolds; MLton's `ClosureConvert`; MLIR's dataflow framework | ported, on a borrowed framework |
| `idr-tail-loops` | self tail calls to `scf.while` | MLton's `Contify` | ported |
| `idr-check-profile` | the heap-free rules | ours | original (the guarantees) |
| `idr-loop-breakers` | cut the cycles the simplify loop closes, every round | GHC's inliner (Peyton Jones and Marlow) | ported |
| `idr-prune` | empty the code dead-code analysis proves unreachable, before `remove-dead-values` | MLIR's dead-code analysis | borrowed analysis; a workaround (`PINS.md`: `prune-before-remove-dead-values`) |
| `idr-simplify` | the fixpoint of the passes above | MLIR's pass manager; a structural hash of the module | original (glue) |
| `idr-lower` | the contract to `func`, `arith`, `scf`, `llvm` | MLIR's dialect conversion; layouts after Chataing, Dolan, Scherer and Yallop | borrowed framework, ported layouts |
| `convert-scf-to-cf`, `convert-to-llvm` | to the LLVM dialect | MLIR | borrowed |
| `idris-mlir-opt`, `idris-mlir-reduce` | tools for tests and debugging | `mlir-opt`, `mlir-reduce` | borrowed, with our dialect registered |

## LLVM, the runtime and the toolchain

| Component | What it does | Upstream | Ownership |
| --- | --- | --- | --- |
| O3, `MergeFunctions`, code generation, full LTO | the object file | LLVM | borrowed |
| The link | static-PIE executables | `lld`, musl, compiler-rt, libunwind | borrowed |
| libc and libm | the OS interface, math | musl | borrowed (vendored) |
| Shortest `Double` printing | `SEM-DBL-5` | Ryu (Adams) | borrowed (vendored), with our tie wrapper |
| UTF-8 validation and counting | strings | simdutf | borrowed (vendored) |
| Number parsing | `cast` from `String` | fast_float | borrowed (vendored) |
| Bignums | `Integer` | GMP | borrowed (vendored) |
| Allocation | the runtime's heap | snmalloc | borrowed (vendored) |
| IO buffering, crashes, the JIT's arena, the C interface | the runtime's own code | ours | original (glue) |
| The toolchain's build | two-stage LLVM on musl | LLVM's CMake; cpp-starter's discipline | borrowed |
| The test runner and oracles | golden tests; `FileCheck`; the Chez backend; `Refl` proofs | Idris's `Test.Golden`; LLVM; Idris | borrowed |
