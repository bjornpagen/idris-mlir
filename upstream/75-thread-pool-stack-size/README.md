<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Support] A thread pool's workers cannot be given a stack size

On llvm main at 416f328b (the pin), `StdThreadPool::grow` starts each
worker with `llvm::thread`'s default stack size
(`llvm/lib/Support/ThreadPool.cpp`; `llvm::thread::DefaultStackSize`,
8 MiB on Darwin and the system's default elsewhere,
`llvm/lib/Support/Threading.cpp`; *read*), and no strategy or
constructor says otherwise. The compiler runs every thread on one stack
size, its measured bound with a margin, the main thread included
(proposals/0000 D33, C43); MLIR's context pool's workers get the OS
default instead.

## Reproduce

Nothing to run: no parameter exists (*read*).

## Patch

`llvm.patch`: `ThreadPoolStrategy::StackSizeInBytes`, when set, is the
stack size of every thread the pool starts; otherwise the default
stands. The compiler builds its pool with it and hands it to MLIR
(`MLIRContext::setThreadPool`). Unit test
`StdThreadPoolTest.StackSizeInBytes` (a smoke test: the tasks run). Not
built.

## Upstreaming plan

Status: carried (2026-10-21); not filed.

- Where: one pull request to llvm/llvm-project, `[Support]`.
- Upstream test: the unit test above.
- The patch goes when the pin's pool takes a stack size.
