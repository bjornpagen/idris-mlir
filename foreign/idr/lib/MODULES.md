# Modules in lib/

The C++ of `lib/` is moving from headers to C++ named modules, one area at a
time. `lib/Facts` (`idr.facts`) is converted and is the template: read it
first. Every other area is a list of plain translation units in its own
`lib/<Area>/CMakeLists.txt`, so an area's conversion touches its own
directory, its users' includes, and at most a few lines of `lib/Mlir.cppm`.

## The shape

- `lib/Mlir.cppm` is `idr.mlir`, the only global module fragment that
  includes MLIR, LLVM or the TableGen-generated idr headers (`idr/Idr.h`).
  It re-exports with `export using` every name the code of `lib/` used when
  it was written, operators included (argument-dependent lookup finds only
  what is exported). Every module unit imports it.
- One module per area, `idr.<area>`, lower case. `lib/<Area>/<Area>.cppm`
  is its primary interface and holds only `export import :<topic>;` lines.
- A partition `idr.<area>:<topic>` is `lib/<Area>/<Topic>.cppm`: declarations
  only, no function bodies, not even in a class. What only the area's own
  units share is declared there outside the `export` block (module linkage).
- Every definition is in an implementation unit, `module idr.<area>;`, at
  `lib/<Area>/<Topic>/<Name>.cc`: one exported function with its private
  helpers (anonymous namespace), or the members of one type.
- What TableGen declares stays in plain translation units in the global
  module: the dialect, op hooks (a generated op's `verify`, `fold`,
  `canonicalize`), pass glue (`GEN_PASS_DEF_*`) and DRR patterns. So
  `lib/Dialect` and `lib/Fold` stay plain, and so do the tools. An area's
  glue is `lib/<Area>/Pass.cc` and stays thin: the generated base, its
  options and statistics, and a call into the module (`lib/Facts/Pass.cc`).
  A hook may likewise call into a module.
- A module has no header. A plain unit uses it with `import idr.<area>;`,
  placed after its last `#include`, the `GEN_PASS_DEF` block's included.

## Converting an area

1. Split the area's headers into partitions by topic; copy each
   declaration with its comment into its partition's `export` block.
2. Move each definition into its own implementation unit, which starts with
   `module idr.<area>;`, then `import idr.mlir;` and `import idr.<other>;`
   for each other area it uses. Keep the code as it was: behaviour must not
   change.
3. Move the pass's logic from the glue into the module (see
   `idr::facts::infer`); leave the glue the generated base.
4. Delete the headers. In each user replace the `#include` with
   `import idr.<area>;` after its last `#include`, adding the includes the
   header brought (usually `"idr/Idr.h"`).
5. In `lib/<Area>/CMakeLists.txt`, list the interfaces in
   `FILE_SET idr_<area> TYPE CXX_MODULES` and the other units as `PRIVATE`
   sources (`lib/Facts/CMakeLists.txt`).
6. A name the code needs that `idr.mlir` does not export: add
   `using <namespace>::<Name>;` to that namespace's block in
   `lib/Mlir.cppm`, in order; a header it does not include yet goes in its
   global module fragment. Either recompiles everything, so collect them.

## Pitfalls

- An `#include` after an `import` in the same unit fails ("duplicate
  explicit instantiation of `ilist_node_base`", clang #61465). Every
  include comes first, in plain units and in module units' global module
  fragments.
- Macros do not cross an import. A module unit that needs one includes the
  header that defines it in its own global module fragment, before its
  module declaration: `<cassert>` for `assert`, the runtime's `idris_rt.h`,
  `mlir/Support/TypeID.h` for `MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID`.
  That is the one exception to `idr.mlir` being the only includer of MLIR
  and LLVM: such a header is parsed again (TypeID.h costs a second).
- `Passes.h.inc` declares each `createIdr<Pass>()` in the global module, so
  a module cannot define it ("declaration in module follows declaration in
  the global module"): the `GEN_PASS_DEF` block is glue.
- A function defined in a class in a module interface is not implicitly
  inline, and an edit to it recompiles every importer: define it in an
  implementation unit.
- Touching an interface recompiles every importer, transitively
  (`PINS.md`: `cmake-module-restat`); touching `lib/Mlir.cppm` or
  `idr/Idr.h` recompiles everything that imports.
- `lib/Support/EnableStatistics.h` is force-included in every unit, module
  units too; it defines macros only, which may precede `module;`.

## Checking

- Iterate in a build of your own: `.toolchain/cmake/bin/cmake --preset dev
  -B <scratch>/build`, then `ninja -C <scratch>/build -j3 idr_dialect`. It
  reads the shared tree without taking `build/.tree.lock`.
- Then, under the locks: `make build`, `make check`, `make test-idr`,
  `make test-mlir-tools`.
- Lint: `.toolchain/cmake/bin/cmake --preset lint -B <scratch>/lint`, then
  `ninja -C <scratch>/lint -k 0 idr_dialect`. The tree is not lint-clean
  yet: findings older than the modules remain in most areas (unchecked
  `optional` access, signed bitwise operations, enum sizes, analyzer
  reports inside MLIR's headers). Add none; clear your area's where you
  can.
