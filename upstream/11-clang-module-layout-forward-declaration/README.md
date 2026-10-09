# [clang][modules] "Cannot get layout of forward declarations" generating `DenseSet<Operation *>` in a module partition

At `llvmorg-23.1.2` (with assertions), clang aborts while generating code
for the constructor of a class in a C++20 module partition. The constructor
uses `llvm::SetVector<mlir::Operation *>` (so `DenseSet<Operation *>`'s
`DenseMap<Operation *, DenseSetEmpty, ...>`). The partition imports a sibling
partition whose exported class holds a `DenseSet<mlir::Operation *>` member,
and both import a module that wraps the LLVM and MLIR headers in its global
module fragment and re-exports their names. The other module units of the
build that use the same set types compile.

```
Assertion failed: D && "Cannot get layout of forward declarations!"
  (clang/lib/AST/RecordLayoutBuilder.cpp: getASTRecordLayout: 3387)
3. llvm/ADT/DenseMap.h:852:12: Generating code for declaration
   'llvm::DenseMap<mlir::Operation *, llvm::detail::DenseSetEmpty, ...>'
```

It does not depend on optimization (`-O0` to `-O2`), debug info or the
sanitizers. It needs every unit compiled as CMake compiles C++20 modules,
the object and the BMI in one step (`-fmodule-output=`): with BMIs from
`--precompile` it compiles.

## Reproduce

Not yet reduced to upstream code only: the reproducer is this repository's
`foreign/idr/lib/Stack/Escape.cppm` before the workaround, `Escape.cppm`
here, compiled in place of today's unit with the build's command for it,
against the build's modules (`idr.mlir`, the wrapper of the LLVM and MLIR
headers; `idr.dialect`, the generated dialect; `idr.graph`; and the sibling
partition `idr.stack:recursion`). `tests/upstream/clang-module-layout-forward-declaration`
does that after `make build`. Removing either partition's use of the set
types, or one of its imports, makes it compile; a standalone reduction of the
same shape over the LLVM headers alone does not crash yet. Reducing it is the
next step before filing.

## Expected

The unit compiles: the definition of `DenseMap<Operation *, DenseSetEmpty,
...>` is reachable through the imported wrapper module.

## Status upstream

Not filed yet, and not known to be fixed (checked at main ed390ca4,
October 2026). Main's 08eb97dea
([#219926](https://github.com/llvm/llvm-project/pull/219926)) may be
related; that is unconfirmed. Once reduced, run the reduction against main.

## Our workaround

`Escape.cppm`'s worklist and caller sets hold `func::FuncOp` (they only ever
hold functions) instead of `Operation *`, which instantiates no
`DenseSet<Operation *>` in that unit (`PINS.md`,
`clang-module-layout-forward-declaration`).

## Why there is no patch

The crash is not reduced: it reproduces only inside this repository's
module graph, and without a reduction neither the cause in clang nor a
fix is known. A patch would be a guess.

## Upstreaming plan

Status: not ready; whether the clang of the pin, llvm main at 7208ba24,
still crashes is open until the check has run on every target.

At 23.1.2 the crash was the x86_64 Linux build's. On arm64 macOS the
clang of 23.1.2 compiled the report's unit, and so does the clang of
7208ba24 (2026-10-08, in place with the build's own command, and from a
copy of the units with `-fmodule-output=` per unit). The check ran on
Linux alone (`targets`), and that file is gone: it runs on every target
and expects the unit to compile. Where it passes on every target, the
report, the check and the PINS.md entry go; where it fails, this plan
applies.

- Where: reduce it first (cvise or by hand, over a copy of the units the
  check compiles, keeping `-fmodule-output=` per unit); run the reduction
  against main and against 08eb97dea (#219926), which may be related.
  If a commit on main fixes it, the pin moves past that commit: the pin
  is a commit of main, so there is no backport. Nothing is sent until it
  is reduced.
- Upstream test: the reduction, as a `clang/test/Modules` test in
  `split-file` form.
