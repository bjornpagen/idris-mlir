# Starting experiment and existing test coverage

> Research snapshot from before the scaffold. See [the current architecture](../architecture.md) and [repository README](../../README.md) for implemented scope.

Source audit at `1c630e67c386629a0fbbc6b78a59176fde7f0a76`.
This records inspected source, scripts, and expected outputs, not tests run
during this audit.

## Decision

Start with **an external typed-Core inspection tool**, using the harness pattern
from `tests/idris2/api/api001` and the small vector language in
`tests/idris2/basic/basic001/Vect.idr`.

Use both existing `Codegen` callbacks:

1. `incCompileFile` observes a successfully processed module before TTC writing.
2. `compileExpr` observes a program and its imported definitions later.

The first deliverable is evidence that we can preserve types, multiplicities,
and checked bodies across a module boundary. MLIR lowering follows that evidence.
No changes to TT, CExp, or the existing backend implementations are needed for
this investigation.

## Why these two fixtures

[`api001/LazyCodegen.idr`](../../third_party/Idris2/tests/idris2/api/api001/LazyCodegen.idr) is a
complete external-codegen registration example. It imports `Core.Context`,
`Compiler.Common`, `Idris.Driver`, and `Idris.Syntax`, and registers a `MkCG`
through `mainWithCodegens`. Its existing test only demonstrates that the
compilation callback is invoked; it does not inspect Core or incremental hooks.

[`basic001/Vect.idr`](../../third_party/Idris2/tests/idris2/basic/basic001/Vect.idr) contains its own
`Nat`, addition, indexed `Vect`, dependent `foldl`, reverse, append, length,
and `zipWith`. The test runs **without Prelude**, which keeps the initial
dependency graph small. It includes:

- An explicitly erased type-family argument: `foldl (0 b : Nat -> Type)`.
- Symbolic length relationships in `append` and `zipWith`.
- A dependent higher-order function and lambdas in `foldl`/`reverse`.
- An explicitly runtime length argument in `vlength`.
- A valid equal-length `zipWith` expression and a rejected unequal-length one
  in its REPL input/expected output.

This tests the project's central distinction: **erased information can remain
useful compiler information**, while some indices still require runtime values.
It also avoids mistaking the current Prelude optimizations for our own work.
Start with the datatype, `plus`, and `append`; add `foldl`/`reverse` after basic
export works. Their dependent higher-order structure is a second step, not a
prerequisite for the first successful probe.

The original fixture is not an executable benchmark and uses its own `Nat`;
do not silently treat it as Prelude Nat arithmetic. A split-module derivative
will need appropriate module declarations and export visibility.

## The first experiment, concretely

Create an isolated `experiments/core-inspect/` package, linked to the pinned
Idris API. This location is proposed; no implementation has been added yet.
Give the tool a codegen name such as `core-inspect`. Its incremental callback
should inspect typed context directly, without `getIncCompileData`.

First run the self-contained vector fixture through checking with the new
incremental codegen enabled and Prelude disabled. This needs no target `main`
and no native-code implementation. Then introduce a small module importing
the fixture's declarations to inspect them after a TTC reload. An executable
driver for the final compilation callback can be added after the module probe.

Export a structural summary first, not a wall of pretty-printed Core:

- Definition identity and kind; signature availability.
- Binder types and multiplicities, with stable binder IDs.
- Constructor field types and result indices.
- Checked-clause count, environments, and body structure; CT/RT-tree availability.
- Separate term/type references; erasure and specialization argument metadata.
- Explicit missing or unsupported information.

For the same declarations, collect:

| Observation | What it establishes |
| --- | --- |
| Fresh module inside `incCompileFile` | Information available before serialization |
| Reloaded module through `lookupCtxtExact` | What ordinary TTC persistence retains |
| Persisted typed sidecar reloaded by our tool | Whether our own boundary preserves the facts we need |
| Unchanged rebuild | Callback/cache behavior, not just semantic content |
| Changed signature or erased annotation | Whether affected sidecars/dependents become invalid |
| Missing or stale sidecar | Explicit rebuild/error/fallback policy; no silent use of stale facts |

Alpha-normalize binders and sort definitions in comparison output. Keep
unavailable information distinct from a known empty set. Compare the common
semantic fields across fresh and cached observations, and separately assert
the expected metadata omissions. Do not demand that raw compiler records or
runtime trees be identical: TTC intentionally does not serialize `treeRT`.

Acceptance for the first slice:

1. `append` retains its input lengths and result-length expression in the export.
2. `foldl`'s type-family argument is recorded as erased when that fixture is added.
3. `vlength`'s runtime length is not accidentally classified as erased.
4. Checked clauses and their bound references export without dangling IDs.
5. Imported definitions are either understood from retained data/sidecars or
   reported unsupported with a specific reason.
6. The deliberately mismatched vectors still fail in Idris; the module callback
   must not report successful checked output for the failed module.

After adding runtime lowering, separately assert that proof-only arguments do
not appear in the generated runtime ABI. A typed export should retain the facts
about them, not pretend they never existed.

## Existing tests to use next

| Existing fixture | What its current test actually checks | Use in our work |
| --- | --- | --- |
| [`casetree003/ForcedPats.idr`](../../third_party/Idris2/tests/idris2/casetree/casetree003/ForcedPats.idr) | REPL inspection of forced patterns, CT tree, erasure metadata, and compiled code | Preserve dependent pattern relationships; do not reintroduce unnecessary scrutiny |
| [`casetree004/LocalArgs.idr`](../../third_party/Idris2/tests/idris2/casetree/casetree004/LocalArgs.idr) | Type checking with an erased equality argument and an index depending on a function call | Proof erasure with useful type-level dependencies |
| [`codegen/fix3515`](../../third_party/Idris2/tests/codegen/fix3515/Main.idr) | Executes two cases and inspects the CT/compiled distinction around unit matching | Ensure typed-case lowering preserves the existing behavior |
| [`basic012/VIndex.idr`](../../third_party/Idris2/tests/idris2/basic/basic012/VIndex.idr) | Type checks use of an explicitly available length index | Distinguish runtime indices from erased indices |
| [`linear006/ZFun.idr`](../../third_party/Idris2/tests/idris2/linear/linear006/ZFun.idr) | Rejects a runtime use of a quantity-zero function while allowing type-check-time evaluation | Preserve relevance restrictions; negative fixture, not a successful runtime input |
| [`linear007/LCase.idr`](../../third_party/Idris2/tests/idris2/linear/linear007/LCase.idr) | Rejects an unused linear variable; also contains valid linear `lplus` | Extract a valid linear fixture and retain the negative case separately |
| [`spec001/Mult3.idr`](../../third_party/Idris2/tests/idris2/evaluator/spec001/Mult3.idr) | Logs specialization; the run script inspects generated JavaScript for multiplication specialized at 3 | Establish existing specialization as baseline with a dynamic operand |
| [`spec001/Desc2.idr`](../../third_party/Idris2/tests/idris2/evaluator/spec001/Desc2.idr) | Logs specialization on a type constructor, result type, and Functor dictionary | Later test for higher-order/dictionary information and generated definitions |
| [`chez/nat2fin`](../../third_party/Idris2/tests/chez/nat2fin/Test.idr) | Inspects generated Scheme for an optimized finite-index literal | Structural code-quality checks already exist; do not claim this optimization as new |
| [`chez/chez006`](../../third_party/Idris2/tests/chez/chez006/TypeCase.idr) | Runs runtime type matching and separately rejects matching erased types | Not every type argument is erased; preserve runtime typecase or explicitly reject it in the initial subset |
| [`chez/inlineiobind`](../../third_party/Idris2/tests/chez/inlineiobind/Main.idr) | Inspects Scheme to ensure IO bind was inlined | Later effectful lowering needs both structural checks and an added runtime-order check |
| [`refc/reuse`](../../third_party/Idris2/tests/refc/reuse/Main.idr) | Runs persistent tree insertions and inspects generated C reuse code | Keep the old tree valid; measure allocation improvements beyond existing dynamic reuse |
| [`misc/import001`](../../third_party/Idris2/tests/idris2/misc/import001/run) | Loads modules without Prelude, touches a dependency, then loads again | Existing multi-module/rebuild pattern; extend with explicit typed-sidecar assertions |

Do not import all these tests unchanged into a tiny experimental compiler.
Some intentionally contain errors or holes; others inspect target-specific code
or require substantial runtime support. Reuse their semantic cases in phases.

## How this repository runs tests

[tests/README.md](../../third_party/Idris2/tests/README.md) describes `run` scripts and `expected`
golden files. [tests/Main.idr](../../third_party/Idris2/tests/Main.idr) constructs the pools.
The runner is [Test.Golden](../../third_party/Idris2/libs/test/Test/Golden.idr).

Important consequences for our experiment:

- The API tests are **not included in the ordinary test runner**. The separate
  [API CI job](../../third_party/Idris2/.github/workflows/ci-idris2-and-libs.yml) installs the API
  and invokes `api001/run` and `api002/run` explicitly. Filtering ordinary
  tests for `idris2/api` does not provide that coverage.
- `tests/idris2/perf` is described as elaborator/compiler performance regression
  material. The runner's `--timing` measures the entire test script. Neither is
  a controlled native-runtime benchmark suite for this project.
- `allbackends` is currently instantiated for Chez, Node, Racket, and RefC.
  A new external codegen is not automatically included. Most tests elsewhere
  are not duplicated across every backend either.
- `testutils.sh` clears `build` and `prefix` when sourced. A fresh/cache
  comparison must source it once, then run both phases within that script;
  separate script invocations would erase the cache under test.
- The golden runner ignores the process status of its shell pipeline and
  compares normalized stdout. Its `idris2` wrapper also pipes through name
  cleanup. For our experimental harness, check compiler/exporter process
  status directly and check artifacts as well as expected content. Use
  explicit status assertions for intentional errors. `set -e` alone does not
  recover the compiler's status from that existing pipeline.
- A missing tool/backend can cause a pool to be skipped. Count executed tests
  and skips; do not treat a clean summary as proof a new backend was exercised.

## A specific incremental-mode trap

[`Core.Context.addImportedInc`](../../third_party/Idris2/src/Core/Context.idr) can remove the
selected codegen from `incrementalCGs` if an imported module lacks its data.
Selecting our new backend and immediately importing an ordinary prebuilt Prelude
could therefore disable the callback we want to study. The no-Prelude vector
fixture is a purposeful starting point, not just a shorter example.

Next, build the small dependency modules with our exporter enabled. Only then
expand to Prelude/base and decide how to manage their sidecars. Existing docs
also warn about stale artifacts when changing incremental modes; keep the
experiment's build directories separate from normal test and library builds.

## First performance target after the export works

Use a scalar operation specialized by a static argument, inspired by `Mult3`,
with the other operand supplied at runtime. It provides a small path through
typed Core, specialization, erasure, MLIR arithmetic, and native execution.
Match Idris's arithmetic semantics; `Nat` is not automatically a machine word.

For a fixed-width first kernel, use a separately declared `Bits64` fixture and
document its modular arithmetic contract. Check behavior at boundary values,
absence of residual static arguments/dispatch, and allocation/call overhead.
Compare with existing backends and a hand-written low-level implementation.
Existing `%spec` already removes substantial abstraction in the Nat example;
matching it establishes correctness before claiming any improvement.

Vector layout changes, broad ownership optimization, and GPU execution come
after this first measured slice. They each need additional representation or
semantic decisions that would obscure the initial interface experiment.

No Idris/API build or test execution was performed in this audit. The existing
tool lookup found no compiler or MLIR tools on PATH; the next implementation
step includes establishing a local, pinned Idris/API build before writing
goldens from observed exporter output.
