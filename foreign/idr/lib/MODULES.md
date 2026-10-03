# Modules

The C++ of this repository, the compiler's `foreign/idr` and the runtime's
`runtime/`, is moving to C++ named modules, one area at a time: many small
files, one concept per file, a namespace per module, and no headers of our
own. `foreign/idr/lib/Facts` (`idr.facts`) is the template of a converted
area, and `runtime/Platform` (`rt.platform`) that of the runtime: read them
first. An area not yet converted is a list of plain translation units, and
two ratchets (`tests/spec/no-local-headers`, `tests/spec/file-size`) list
what it still does that a module may not; converting the area deletes its
lines there.

## The rules

- **All C++ is in named modules.** The exceptions are what TableGen
  generates and the hooks that define its members: the dialect, a
  generated op's `verify`, `fold` and `canonicalize`, the pass bases
  (`GEN_PASS_DEF_*`) and the DRR patterns. A member of a class attached to
  the global module cannot be defined inside a named module, so these are
  plain units for good. They include only `idr/Idr.h`, which declares what
  TableGen generates, and import modules for the rest. A tool's `main` is
  a thin plain unit too.
- **No local headers.** A module has no header; a unit imports it. The
  exceptions are `runtime/idris_rt.h`, the C ABI, which C and generated code
  read, and what TableGen generates (its `.inc` files and `idr/Idr.h`
  around them). A header that carries macros only, which no import carries,
  is the build's (`lib/Support/EnableStatistics.h`, force-included) or the
  target entry's (`idr/TargetEntry.h`, generated).
- **A namespace mirrors its module:** `idr.facts` is `idr::facts`,
  `rt.platform` is `rt::platform`.
- **One concept per file:** a `.cc` defines one exported function with its
  private helpers, or the members of one type. A unit over 400 lines is
  two concepts.
- **File names are CamelCase,** after what they define.
- **Comments say why** the code is as it is; they do not cite documents.

## The shape

- A module is `<prefix>.<area>`, lower case: `idr.<area>` in `foreign/idr`,
  `rt.<area>` in `runtime`. Its primary interface `<Area>/<Area>.cppm`
  holds only `export import :<topic>;` lines.
- A partition `<module>:<topic>` is `<Area>/<Topic>.cppm`: declarations
  only, no function bodies, not even in a class. What only the area's own
  units share is declared there outside the `export` block (module
  linkage).
- Every definition is in an implementation unit, `module <module>;`, at
  `<Area>/<Topic>/<Name>.cc`. A platform layer, whose target entry picks the
  units that implement it, groups them by system instead:
  `runtime/Platform/Posix/<Name>.cc`, `runtime/Platform/X86_64/<Name>.cc`.
- A template is defined where it is declared, since each user instantiates
  it: keep it thin and put the work in a function of a unit, as
  `idr::graph::stronglyConnected` numbers its nodes and calls
  `idr::graph::components`.
- `foreign/idr/lib/Mlir.cppm` is `idr.mlir`, the only global module
  fragment that includes MLIR's and LLVM's headers, and
  `foreign/idr/lib/Dialect/Dialect.cppm` is `idr.dialect`, the only one
  that includes `idr/Idr.h`. They re-export with `export using`, operators
  included (argument-dependent lookup finds only what is exported):
  `idr.mlir` every name of MLIR, LLVM and the C++ library the code of
  `lib/` uses, and the C names of the integer types; `idr.dialect` the
  dialect's whole interface.
- An area's pass glue is `lib/<Area>/Pass.cc` and stays thin: the
  generated base, its options and statistics, and a call into the module
  (`lib/Facts/Pass.cc`). A hook may likewise call into a module. Glue
  belongs to the library whose logic it runs.
- A plain unit uses a module with `import <module>;`, placed after its last
  `#include`, the `GEN_PASS_DEF` block's included.

## Libraries

- Each module of `foreign/idr/lib` is one static library, made by
  `idr_library` (`foreign/idr/cmake/IdrLibrary.cmake`): `idr_<area>`, but
  `idr.dialect`'s, which is `idr_ods`, since `idr_dialect` is the aggregate
  the tools link. It lists its interfaces, its implementation units, its
  glue, and in `LINKS` exactly the libraries of the modules its units
  import. The build finds a module only in what a library links, so a unit
  that imports a module above its library, or beside it, fails to build
  (`tests/toolchain/module-imports`); `tests/spec/module-links` checks that
  `LINKS` is the import list itself.
- `idr_dialect` is the aggregate: the dialect's definitions and hooks, the
  areas not yet converted as plain units, and every module's library.
- The layering, each module importing only what is below it:

  | Module | Holds | Imports |
  |---|---|---|
  | `idr.mlir` | MLIR and LLVM | |
  | `idr.dialect` | the dialect's declarations (`idr/Idr.h`) | |
  | `idr.support` | actions, pattern counts, pipeline statistics | `idr.mlir` |
  | `idr.ranges` | the integer ranges of bigs and naturals | `idr.mlir` |
  | `idr.graph` | strongly connected components, tail position, loop trips | `idr.mlir`, `idr.dialect` |
  | `idr.layout` | cells, sums, labels and their code: values at runtime | `idr.mlir`, `idr.dialect` |
  | `idr.facts` | what a function may do | `idr.mlir`, `idr.dialect` |
  | `idr.target` | the module's target, and LLVM's pipeline for it | `idr.mlir` |

- The runtime is one archive, `idris_rt`, which the archive check reads and
  `--prepare-runtime` prepares: its modules are file sets of it, private,
  compiled with the runtime's profile like its other units, and nothing
  outside the runtime imports them.

## Converting an area

1. Split the area's headers into partitions by topic; copy each
   declaration with its comment into its partition's `export` block, and
   move the area into its own namespace.
2. Move each definition into its own implementation unit, which starts with
   `module <module>;`, then `import idr.mlir;`, `import idr.dialect;` and
   the other modules it uses. Keep the code as it was: behaviour must not
   change.
3. Move the pass's logic from the glue into the module (see
   `idr::facts::infer`); leave the glue the generated base.
4. Delete the headers. In each user replace the `#include` with
   `import <module>;` after its last `#include`, adding the includes the
   header brought (usually `"idr/Idr.h"`).
5. Make the area's `lib/<Area>/CMakeLists.txt` an `idr_library` call
   (`lib/Facts/CMakeLists.txt`), and link it from `idr_dialect`.
6. A name the code needs that `idr.mlir` does not export: add
   `using <namespace>::<Name>;` to that namespace's block in
   `lib/Mlir.cppm`, in order (or in `lib/Dialect/Dialect.cppm` for an idr
   name); a header it does not include yet goes in its global module
   fragment. Either recompiles everything, so collect them.
7. Delete the area's lines from `tests/spec/no-local-headers/allowed` and
   `tests/spec/file-size/allowed`; both fail on a line that is no longer
   needed.

## Pitfalls

- An `#include` after an `import` in the same unit can fail ("duplicate
  explicit instantiation of `ilist_node_base`", clang #61465). Every include
  comes first, in plain units and in module units' global module fragments.
  A header of an area not yet converted may import a module after its own
  includes (`Lower/Runtime.h` imports `idr.layout`); include it after the
  unit's other headers if one clashes.
- Macros do not cross an import. A module unit that needs one includes the
  header that defines it in its own global module fragment, before its
  module declaration: `<cstdint>` for `INT64_MAX`, the runtime's
  `idris_rt.h`, `cpu_features.h` for the target entry's list,
  `llvm/ADT/Statistic.h` for `LLVM_ENABLE_STATS`. That is the one exception
  to `idr.mlir` and `idr.dialect` being the only includers of MLIR, LLVM
  and TableGen's output: such a header is parsed again.
- `Passes.h.inc` declares each `createIdr<Pass>()` in the global module, so
  a module cannot define it ("declaration in module follows declaration in
  the global module"): the `GEN_PASS_DEF` block is glue.
- A function defined in a class in a module interface is not implicitly
  inline, and an edit to it recompiles every importer: define it in an
  implementation unit. A `constexpr` function must be defined where it is
  declared, so a member that was `constexpr` in a header becomes a plain
  one, defined in a unit. MLIR's `MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID`
  defines a body in the class: declare `static mlir::TypeID resolveTypeID();`
  instead and define it in a unit (`lib/Support/Actions`).
- A declaration of the global module fragment that the purview does not
  name may be dropped from the module: export what the code needs, including
  what it needs implicitly (`std::tuple_size` and `std::tuple_element`, for
  a structured binding of `llvm::enumerate`).
- A module-attached class cannot be forward-declared from the global module:
  a plain header that names one imports its module, or the declaration that
  needs it moves to where it is used (`Ownership/Rc.cc`).
- Every interface unit defines a module initializer (`_ZGIW…`). Nothing
  calls one that has nothing to initialize, and no unit gets a static
  constructor for an import; the runtime's archive check keeps it so.
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
  reports inside MLIR's headers) and in the runtime. Add none; clear your
  area's where you can.
