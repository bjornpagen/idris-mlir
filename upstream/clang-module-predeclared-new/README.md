# [clang][modules] "predeclared global operator new/delete is missing" generating libc++'s `__libcpp_allocate` in a module unit

At `llvmorg-23.1.2` (with assertions), clang reaches an `UNREACHABLE` while
generating code for libc++'s `std::__libcpp_allocate` in a C++20 module
partition that has no global module fragment and builds `std::string`s
(`a + "," + b`). The string templates come from an imported module that
wraps the LLVM headers (and so libc++'s) in its global module fragment and
re-exports their names.

```
predeclared global operator new/delete is missing
UNREACHABLE executed at clang/lib/CodeGen/CGExprCXX.cpp:1397!
3. c++/v1/__new/allocate.h:35:1: Generating code for declaration
   'std::__libcpp_allocate'
```

The replaceable global allocation functions are implicitly declared in every
translation unit ([basic.stc.dynamic.general]); `__builtin_operator_new` in
the imported template should find them. Giving the unit a global module
fragment that includes `<new>` makes it compile.

## Reproduce

Not yet reduced to upstream code only: the reproducer is this repository's
`foreign/idr/lib/Driver/Retarget.cppm` before the workaround,
`Retarget.cppm` here, compiled in place of today's unit with the build's
command for it, against the build's modules (`idr.mlir`, the wrapper of the
LLVM and MLIR headers, and `idr.driver:marks`).
`tests/upstream/clang-module-predeclared-new` does that after `make build`.
A standalone module that imports a wrapper of `<string>` and concatenates
strings compiles, with the same flags; reducing it is the next step before
filing.

## Expected

The unit compiles, as it does with `#include <new>` in a global module
fragment.

## Status upstream

Likely already reported: the open issue
[#189252](https://github.com/llvm/llvm-project/issues/189252) looks like
this bug (checked at main ed390ca4, October 2026). Once reduced, confirm it
against that issue and add the reduction there rather than filing again.

## Our workaround

`Retarget.cppm` builds the feature string in `llvm::SmallString`, which
allocates through `malloc`, so no `std::string` is built in that unit
(`PINS.md`, `clang-module-predeclared-new`).

## Why there is no patch

The crash is not reduced: it reproduces only inside this repository's
module graph, and without a reduction neither the cause in clang nor a
fix is known. A patch would be a guess.

## Upstreaming plan

- Where: reduce it first (cvise or by hand, over a copy of the units the
  check compiles); confirm it is #189252 and add the reduction there. If
  that issue gets a fix, backport it as `llvm.patch`.
- Upstream test: the reduction, as a `clang/test/Modules` test in
  `split-file` form.
- Status: not reduced; likely already reported (#189252).
