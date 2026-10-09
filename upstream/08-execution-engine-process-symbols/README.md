# [mlir] `ExecutionEngine` cannot be created in a statically linked process

At `llvmorg-23.1.2`, `mlir::ExecutionEngine::create` always opens the
current process's symbols through the dynamic loader and aborts in
`cantFail` when that fails, which it always does in a static executable.
There is no option to leave the process out.

## Reproduce

No `mlir-opt` command shows this: it takes a statically linked program that
creates an `ExecutionEngine`. Built with the pinned toolchain against musl
as a static PIE (as `idris-mlir` is):

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

`ExecutionEngine::lookup` searches the main JITDylib's link order, so it
finds a name where the JIT-compiled code finds it. With the default
options it returns what it did before (the platform JITDylib between main
and the process defines only ORC's `__lljit.*` helpers); with the option
off it, too, sees only the symbols the engine is given. Libraries in
`sharedLibPaths` that do not implement the init/destroy protocol are
reached only through the process (they are opened `RTLD_GLOBAL`), which
the option's documentation states.

Verified: the diff applies to llvm main (7208ba24) and to
llvmorg-23.1.2, the pin then (`git apply --check`); the patched
`ExecutionEngine.cpp` and `Invoke.cpp` of llvm main pass `-fsyntax-only`
against llvm main's headers. Against 23.1.2: the `Invoke.cpp` unit
tests and the new `WithoutProcessSymbols` (9 tests) pass when built
against the patched `ExecutionEngine.cpp` with that toolchain's
googletest and static libraries, and the test's
`lookup` check fails against a `lookup` that searches main alone; a
static-PIE musl program creates an engine with the option off, calls a
registered function, gets an error (not an abort) for an unregistered
one, and gets an error from `create` with the option on.

## Testing on main

On llvm main at 7208ba24 (2026-10-08), with the seven code diffs of
01-08 applied together (02-07's `llvm.patch` and 08's
`pull-request.diff`), a Release build with assertions
(`-DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD=Native
-DBUILD_SHARED_LIBS=ON -DLLVM_ENABLE_ASSERTIONS=ON`, clang 18, x86_64
Linux) builds without errors and passes `ninja check-mlir`: 4102 passed,
630 unsupported, 1 expectedly failed, none failed.

Then, with this patch's `ExecutionEngine.cpp`/`.h` changes alone
reverted, `MLIRExecutionEngineTests` does not build (the test uses the
new `enableProcessSymbols` option); with them back,
`*ProcessSymbols*` passes, as do the other ExecutionEngine unit tests in
the run above.

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

Status: file upstream. Upstream `main` (7208ba24, 2026-10-08) has not
changed this code (`ExecutionEngine.cpp` differs from llvmorg-23.1.2 only
in unrelated data-layout and IRBuilder lines), and no issue or pull
request on llvm/llvm-project covers it.

- Where: one pull request to llvm/llvm-project (MLIR ExecutionEngine), as
  `submission.md` says. No issue, and not a Bugzilla bug. The pull
  request's title and body are the squash commit message.
- Upstream test: `WithoutProcessSymbols` in
  `mlir/unittests/ExecutionEngine/Invoke.cpp`, which `pull-request.diff`
  adds. There is no `tests/upstream` check: no `mlir-opt` command shows
  the bug, and the unit test is its check upstream.
