# [mlir] `ExecutionEngine` cannot be created in a statically linked process

At `llvmorg-23.1.2`, `mlir::ExecutionEngine::create` always opens the
current process's symbols through the dynamic loader and aborts in
`cantFail` when that fails, which it always does in a static executable.
There is no option to leave the process out.

## Reproduce

No `mlir-opt` command shows this: it takes a statically linked program that
creates an `ExecutionEngine`. Built with the pinned toolchain against musl
as a static PIE (as `idris-mlir-cc` is):

```cpp
#include "mlir/ExecutionEngine/ExecutionEngine.h"
#include "mlir/Parser/Parser.h"
// ... register the LLVM dialect and the LLVM IR translation, parse any
// module in the llvm dialect, then:
auto engine = mlir::ExecutionEngine::create(*module);
```

The process aborts inside `create`:

```
Failure value returned from cantFail wrapped call
Dynamic loading not supported
UNREACHABLE executed at llvm/include/llvm/Support/Error.h:810!
```

Expected: an `ExecutionEngine` that resolves only the symbols the caller
gives it (`registerSymbols`), or an error returned from `create`.

## Cause

The process's symbols are resolved in two places, and both need
`dlopen(NULL)`:

- `mlir/lib/ExecutionEngine/ExecutionEngine.cpp:393-395` adds
  `cantFail(DynamicLibrarySearchGenerator::GetForCurrentProcess(...))` to
  the main JITDylib;
- `LLJITBuilder` (`llvm/lib/ExecutionEngine/Orc/LLJIT.cpp:841`) creates
  its own `<Process Symbols>` JITDylib with the same kind of generator and
  links it after main and the platform. `ExecutionEngine.cpp:376-381`
  builds it under `cantFail` too.

The second one cannot simply be switched off:
`setLinkProcessSymbolsByDefault(false)` leaves no process-symbols JITDylib,
and the generic IR platform `ExecutionEngine` uses refuses to start without
one (`LLJIT.cpp:1237`, "Native platforms require a process symbols
JITDylib"). The draft of this fix that did that made `create` fail for
every caller who turned the option off.

## The fix

`pull-request.diff` keeps the process's symbols in one place. `create`
sets up the LLJIT's process-symbols JITDylib itself
(`setProcessSymbolsJITDylibSetup`); the JITDylib always exists, so the
platform starts, and the new `ExecutionEngineOptions::enableProcessSymbols`
(default `true`) decides whether it holds the process generator. The
duplicate generator on the main JITDylib is gone. The link order is the
data: main (JIT-compiled code and `registerSymbols`), the platform, then
the process. Building the LLJIT, opening the process included, returns an
error from `create` instead of aborting.

One behaviour changes for default users: `ExecutionEngine::lookup`
searches only the main JITDylib (`LLJIT::lookupLinkerMangled`), so it no
longer returns process symbols that happened to be materialized there.
JIT-compiled code still calls them through the link order. Libraries in
`sharedLibPaths` that do not implement the init/destroy protocol are
reached only through the process (they are opened `RTLD_GLOBAL`), which the
option's documentation states.

Verified against the pin: the diff applies (`git apply --check`); the
pinned `Invoke.cpp` unit tests and the new `WithoutProcessSymbols` (9
tests) pass when built against the patched `ExecutionEngine.cpp` with the
pinned googletest and the installed static libraries; a static-PIE musl
program creates an engine with the option off, calls a registered
function, gets an error (not an abort) for an unregistered one, and gets
an error from `create` with the option on.

## Why there is no patch

There is no `llvm.patch`, and there is no `PINS.md` entry. The compiler
uses `LLJIT`, so the bug does not affect it. Compile-time evaluation
(`foreign/idr/lib/Eval/Jit.cppm`) builds ORC's `LLJIT`, which
`ExecutionEngine` wraps, for reasons of its own beyond this bug: the
engine links through RuntimeDyld (`RTDyldObjectLinkingLayer` with a
`SectionMemoryManager`) where the evaluator relies on JITLink's in-process
memory manager and its page protections; it adds a packed-argument wrapper
for every function with external linkage; and it keeps the execution
session to itself, whose error reports the evaluator quotes when a lookup
fails. With `LLJIT` the evaluator links no process symbol by default and
binds the runtime's functions, the libm functions lowered code calls and
the target entry's library calls itself.

The report is still a pull request we intend to send, drafted as
`pull-request.diff`, which this repository does not apply.

## Upstreaming plan

Status: file upstream. Upstream `main` has not changed this code
(`ExecutionEngine.cpp` differs from the pin only in unrelated data-layout
and IRBuilder lines), and no open pull request covers it.

- Where: one pull request to llvm/llvm-project (MLIR ExecutionEngine), as
  `submission.md` says. No issue, and not a Bugzilla bug. The pull
  request's title and body are the squash commit message.
- Upstream test: `WithoutProcessSymbols` in
  `mlir/unittests/ExecutionEngine/Invoke.cpp`, which `pull-request.diff`
  adds. There is no `tests/upstream` check: no `mlir-opt` command shows
  the bug, and the unit test is its check upstream.
