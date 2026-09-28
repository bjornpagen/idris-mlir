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

## Our workaround

`PINS.md`: `orc-lljit`. `idr-eval` (`foreign/idr/lib/Eval/Jit.cc`) uses
ORC's `LLJIT`, which `ExecutionEngine` wraps, with
`setLinkProcessSymbolsByDefault(false)` and an `absoluteSymbols` table of
the runtime's functions and the libc and libm functions that lowered code
calls, all linked into `idris-mlir-cc`.
