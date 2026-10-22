<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Support] A thread pool's workers cannot be set up as they start

On llvm main at 416f328b (the pin), `StdThreadPool::grow`
(`llvm/lib/Support/ThreadPool.cpp:44`) starts each worker by naming it
and applying the strategy's placement (`apply_thread_strategy`, `:53`)
before it takes tasks; nothing of the client's runs on a worker before
a task does, and `ThreadPoolStrategy` (`llvm/include/llvm/Support/Threading.h:115`)
has no field for it (*read*; no such hook on main either, *read*
2026-10-22). What a new thread does not inherit cannot be set up for a
pool's workers. An alternate signal stack is such a thing: POSIX gives
a new thread none, and LLVM's own signal handling installs one only on
the thread that first registers its handlers
(`llvm/lib/Support/Unix/Signals.inc:300-318`, `:337`).

The compiler's tools run every thread on one stack size behind a guard,
and reaching a guard is the tool's internal error (proposals/0000 D33,
C43): the runtime's handler for the fault, installed with
`SA_ONSTACK`, says so. On a pool's worker it never runs: the guard is
the C library's, the worker has no signal stack, so the kernel cannot
deliver the fault to the handler and the tool dies of a bare SIGSEGV
(SIGBUS or SIGSEGV on Darwin).

## Reproduce

`signal-stack.cpp`: a pool of one worker on a 256 KiB stack
(`upstream/75-thread-pool-stack-size`) whose task recurses into its
guard, with a handler for the fault, installed with `SA_ONSTACK`, that
prints `ok`. Without the hook's line it dies of the fault at the pin,
the handler never running; with the patch the worker installs its
signal stack as it starts and the handler prints `ok` (*conjecture*:
not built or run, D56).

## Patch

`llvm.patch`: `ThreadPoolStrategy::OnThreadStart`, a `void (*)()`,
when set, is called once on every thread a pool built with the strategy
starts, on that thread, after `apply_thread_strategy` and before it runs
any task. It is a function pointer, not a callable object, so that a
strategy held in a global (`llvm::parallel::strategy`,
`llvm/lib/Support/Parallel.cpp:27`) stays constant-initialized, as
LLVM's coding standards ask of globals. Unset, nothing changes. Unit
test `StdThreadPoolTest.OnThreadStart`: every task finds the mark its
thread's hook set. Applies after `upstream/75-thread-pool-stack-size`,
whose lines it neighbours; not built.

`llvm::parallel`'s executor starts its own threads and honours neither
this field nor 75's; nothing in the tree uses it (*read*: the tools'
parallel work is MLIR's, on the context's pool), so the patch leaves it.

The API it adds, for the tools' driver and the runtime:
`void (*llvm::ThreadPoolStrategy::OnThreadStart)()`.
`idr::driver::onToolStack` (foreign/idr/include/idr/Driver/Tool.h),
which every tool's pool is built through, sets it to a function of the
runtime that installs the tools' signal stack on the calling thread.

Why not a pool of our own: `MLIRContext::setThreadPool` takes any
`ThreadPoolInterface`, so the tools could start their workers
themselves, but that is `StdThreadPool` written again to add one call.

## Check

`tests/upstream-thread-pool-thread-start` (to write): `mlir_check` of
`signal-stack.cpp`, which prints `ok` when a worker's guard fault
reaches the handler on the worker's signal stack.

## Upstreaming plan

Status: carried (2026-10-22); not filed.

- Where: one pull request to llvm/llvm-project, `[Support]`, after 75's,
  whose lines it neighbours.
- Upstream test: the unit test above.
- The patch goes when the pin's pool runs a client's function on each
  thread it starts.
