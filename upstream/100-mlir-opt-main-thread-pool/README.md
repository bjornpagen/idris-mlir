<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] MlirOptMain runs its input on a thread pool its caller cannot give

On llvm main at 416f328b (the pin), the stream overload of `MlirOptMain`
(`mlir/lib/Tools/mlir-opt/MlirOptMain.cpp:790`) makes a temporary
context to learn whether `--mlir-disable-threading` was given, and when
threading is enabled it takes that context's own pool (`:810-812`),
which every context it makes for its input then shares
(`processBuffer`, `:701-703`). Nothing a caller passes reaches that
choice (*read*). A tool built on `MlirOptMain` cannot say how its
worker threads are made: `llvm::DefaultThreadPool`'s default strategy,
`llvm::thread`'s default stack size, nothing set up on a new thread.

idris-mlir-opt is such a tool. The compiler runs every one of its
threads on one stack size, its measured bound with a margin, and gives
each a signal stack, so that reaching the stack's guard is the tool's
internal error (proposals/0000 D33, C43). idris-mlir and
idris-mlir-reduce make their own contexts and hand each a pool whose
workers run on the tools' stack (`MLIRContext::setThreadPool`,
`upstream/75-thread-pool-stack-size`), and will set each worker's
signal stack up as it starts (`upstream/101-thread-pool-thread-start`);
idris-mlir-opt's workers run on the system's default stack, with
neither.

## Reproduce

Nothing to run at the pin: no parameter exists (*read*).
`callers-pool.cpp` gives `MlirOptMain` a pool and checks, from a pass,
that the context the pass runs in shares it; it prints `ok` with the
patch and does not build without it. Not built or run (D56).

## Patch

`llvm.patch`: `MlirOptMainConfig::setThreadPool(llvm::ThreadPoolInterface *)`
names a pool the caller owns, which must outlive the call;
`getThreadPool()` reads it. When threading is enabled, `MlirOptMain`
hands that pool to every context it makes for its input instead of the
temporary context's own; `--mlir-disable-threading` still disables
threading, and with no pool set nothing changes. The temporary context
still makes its own pool, which starts no thread until a task is
enqueued (`StdThreadPool::grow` runs from `asyncEnqueue`), and none is.
Unit test `MlirOptMain.CallersThreadPool`
(`mlir/unittests/Tools/MlirOptMainTest.cpp`, a new unittest directory),
the same check as `callers-pool.cpp`. Applies to the pin alone and
touches no file another carried patch does (*read*); not built.

The API it adds, for the tools' driver: `mlir::MlirOptMainConfig &
mlir::MlirOptMainConfig::setThreadPool(llvm::ThreadPoolInterface *pool)`.
idris-mlir-opt builds its pool as the other tools do
(`idr::driver::onToolStack`, foreign/idr/include/idr/Driver/Tool.h),
declares it before `MlirOptMain` is called so that it outlives the call,
and sets it on the config it already builds.

## Check

`tests/upstream-mlir-opt-main-thread-pool` (to write): `mlir_check` of
`callers-pool.cpp`, which prints `ok` when the pass's context shares
the caller's pool.

## Upstreaming plan

Status: carried (2026-10-22); not filed.

- Where: one pull request to llvm/llvm-project, `[mlir]`, on its own.
- Upstream test: the unit test above, in a new
  `mlir/unittests/Tools` directory.
- The patch goes when the pin's `MlirOptMain` takes a caller's pool.
