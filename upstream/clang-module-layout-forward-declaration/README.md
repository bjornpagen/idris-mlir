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

## Our workaround

`Escape.cppm`'s worklist and caller sets hold `func::FuncOp` (they only ever
hold functions) instead of `Operation *`, which instantiates no
`DenseSet<Operation *>` in that unit (`PINS.md`,
`clang-module-layout-forward-declaration`).
