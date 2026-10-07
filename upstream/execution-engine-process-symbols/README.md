# [mlir] `ExecutionEngine` cannot be created in a statically linked process

At `llvmorg-23.1.2`, `mlir::ExecutionEngine::create` always adds a
generator for the current process's symbols and aborts if that fails,
which it always does in a static executable. There is no option to skip it.

## Reproduce

No `mlir-opt` command shows this: it takes a statically linked program that
creates an `ExecutionEngine`. Built with the pinned toolchain against musl
with `-static` (as `idris-mlir-cc` is):

```cpp
#include "mlir/ExecutionEngine/ExecutionEngine.h"
#include "mlir/Parser/Parser.h"
// ... register the LLVM dialect and the LLVM IR translation, parse any
// module in the llvm dialect, then:
auto engine = mlir::ExecutionEngine::create(*module);
```

The process aborts inside `create`, in the `cantFail` below: the error is
that the process's own symbols cannot be opened (`dlopen(NULL)` needs a
dynamic loader, which a static musl executable has none of).

Expected: an `ExecutionEngine` that resolves only the symbols the caller
registers (`registerSymbols`), or an error returned from `create`.

## Cause

`mlir/lib/ExecutionEngine/ExecutionEngine.cpp:393-395`:

```cpp
cantFail(llvm::orc::DynamicLibrarySearchGenerator::GetForCurrentProcess(
    dataLayout.getGlobalPrefix()))
```

and `LLJITBuilder` links the process's symbols by default as well
(`LLJIT.h:415`, `setLinkProcessSymbolsByDefault`).

## Proposed fix

An `ExecutionEngineOptions` field, say `linkProcessSymbols` (default
`true`, today's behaviour). When false, `create` adds no process-symbol
generator and calls `setLinkProcessSymbolsByDefault(false)` on the builder,
and every symbol comes from `sharedLibPaths` and `registerSymbols`. In any
case, the failure should become an `Expected` error from `create` instead of
`cantFail`.

## Why there is no patch

idris-mlir does not create an `ExecutionEngine`, so it carries no fix for
it. Compile-time evaluation (`foreign/idr/lib/Eval/Jit.cppm`) builds ORC's
`LLJIT`, which `ExecutionEngine` wraps, for reasons of its own beyond this
bug: the engine links through RuntimeDyld (`RTDyldObjectLinkingLayer` with a
`SectionMemoryManager`) where the evaluator relies on JITLink's in-process
memory manager and its page protections; it adds a packed-argument wrapper
for every function with external linkage; and it keeps the execution
session to itself, whose error reports the evaluator quotes when a lookup
fails. With `LLJIT` the evaluator links no process symbol by default and
binds the runtime's functions, the libm functions lowered code calls and
the target entry's library calls itself.

The proposed fix is drafted as `pull-request.diff`, for the pull request:
`ExecutionEngineOptions::linkProcessSymbols` (default `true`); when
`false`, `create` adds no process-symbol generator and builds the `LLJIT`
with `setLinkProcessSymbolsByDefault(false)`. Building the `LLJIT` or
opening the process's symbols now fails `create` with an error instead of
aborting. A unit test in `mlir/unittests/ExecutionEngine/Invoke.cpp`. It
applies to the pin and `ExecutionEngine.cpp` compiles with it; the unit
test has not been run.

## Upstreaming plan

Status: file upstream.

- Where: a pull request to llvm/llvm-project (MLIR ExecutionEngine), with
  this report as its description; no issue needed.
- Upstream test: the `WithoutProcessSymbols` unit test `pull-request.diff`
  adds.
  This bug has no `tests/upstream` check, since no `mlir-opt` command
  shows it; the unit test is its check upstream.
