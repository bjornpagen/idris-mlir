# cpp-modern: all of idris-mlir's C++ at cpp-starter's standard

Stream `cpp-modern`. Research only: nothing in the tree was changed. Detail
lives in four side files:

- `cpp-modern-starter.md`: cpp-starter's patterns and lint innovations,
  with file:line, and what idris-mlir has adopted of them.
- `cpp-modern-audit.md`: every C++ file's worklist: zone, the variants to
  introduce (with their types), the `expected` paths, the concepts, the
  `noexcept` blockers.
- `cpp-modern-lint.md`: the exact `.clang-tidy` of each zone, the custom
  checks, the compiler flags, the CMake and preset changes, the test
  fixtures, and what the gates find in the tree today.
- `cpp-modern-toolchain.md`: what the pinned clang 23.1.2 and libc++
  implement, each feature compiled and run.

Evidence is file:line in `/home/user/idris-mlir` (at d8b70eb) or
`/home/user/bjornpagen/cpp-starter` (cpp-starter), or an experiment under
`scratchpad/research/cpp-modern/` (`snip/` snippets, `lint/` the full-tree
lint run, `lint2/` and `zones/` the lint fixtures, `stdfull/` the
full-scale modules test, `restat/` the rebuild test). *Tested* means
compiled and run on the pinned tools; everything else is marked conjecture.

The user's mandates, as this document reads them:

1. The latest C++ the pinned clang and libc++ support: C++26. Reflection is
   out.
2. The latest features where they fit: `std::expected` and its monadic
   operations; `std::variant` for **every** closed set of alternatives
   (tags, enums with switches, nullable pointers, bool flags, isa-chains
   over our own types, ad-hoc unions); concepts; constrained templates;
   `auto`; ranges; deducing `this`.
3. The entire codebase `noexcept`, enforced.
4. As close to cpp-starter as possible; every remaining deviation forced by
   LLVM or MLIR and recorded in `PINS.md`.
5. No blanket `[[nodiscard]]`; only a lint on a discarded `std::expected`.

---

## 1. The end state

### 1.1 The tree

```
src/                      dialect code: named modules only, import std
  ir/                     module ir: quantity_of, unrestricted, lookups, known_*
  facts/                  module facts: effects, functions, closures, moves, evaluation, infer
  layout/                 module layout: representation, sums, cells, info words
  ownership/              module ownership: counting, borrow, reset/reuse, counts, verify
  stack/                  module stack: escape, recursion, tail, cells
  specialize/             module specialize: binding times, clones, patterns, raise
  passes/                 module passes: defunctionalize, simplify, prune, tail_loops,
                          loop_breakers, inline (partitions)
  canonicalize/           module canonicalize: the C++ patterns, as functions
  lower/                  module lower: runtime calls, matches, patterns as functions
  eval/                   module eval: rounds, outcomes, the driver of the child
  expect/                 module expect: the named properties
  driver/                 module driver: idris-mlir-cc's pipeline as expected<Artifact, ToolError>
foreign/idr/              glue: what TableGen and MLIR's base classes force
  include/idr/*.td        ODS (with discardableAttrs, noexcept extraClassDeclarations)
  mlir_api.cc             module mlir_api: MLIR's headers, re-exported by name
  support/                module support: classify, walk, type_switch, Box, invariant,
                          Error, to_logical, FnConversion (the one place a lambda
                          meets function_traits)
  dialect/, fold/         the hooks ODS declares, each forwarding to a module
  passes/                 one GEN_PASS_DEF unit per pass: the base, its options and
                          statistics, one call into the module
  canonicalize.td         DRR
  tools/                  main() of each tool: cl::opt locals, one call into driver
unsafe/                   fork, mmap, signals, pthreads, JIT memory: plain units, reached
                          through an extern "C++" narrow ABI declared in a partition
                          (cpp-starter's unsafe/net.cc:7-40)
  eval_child.cc, jit.cc, reify.cc, large_stack.cc
runtime/                  the C ABI runtime (unchanged zone)
tests/compile_fail/, tests/lint_fail/, tests/conformance/
```

This is cpp-starter's layout (`AGENTS.md:361-411`): dialect code in `src/`,
quarantine in `foreign/` and `unsafe/`. `PIN(zones-on-demand)` retires:
the zones hold code.

### 1.2 The language

- **C++26** (`CMAKE_CXX_STANDARD 26`, as both repos set), `-fno-exceptions
  -fno-rtti`, `import std;` in every unit, libc++ hardened. Nothing past
  C++26 exists: `-std=c++2d` enables no feature (`cpp-modern-toolchain.md`
  section 1).
- **Every function and lambda is `noexcept`**, spelled cpp-starter's way:
  `auto f(args) noexcept -> T`. The only exceptions are forced by MLIR:
  about 100-120 hooks whose declaration TableGen writes without `noexcept`
  (a definition must repeat its declaration, `snip/decl.cc`), and the one
  non-`noexcept` lambda inside each of `support::walk`,
  `support::type_switch` and `support::walk_attrs`, because
  `llvm::function_traits` has no `noexcept` specialization (an LLVM bug,
  reduced to four lines, `snip/ft.cc`). Overrides of MLIR virtuals *can* be
  `noexcept` and are (`snip/walk.cc:5-7`).
- **Every closed set of alternatives is a `std::variant`**, eliminated by a
  visitor struct with one `noexcept operator()` per alternative
  (cpp-starter `AGENTS.md:1833-1854`), through the member `v.visit(...)`
  (`__cpp_lib_variant` 202306, tested). The audit applies the rule to six
  shapes (tag + payload, null-as-case, bool selector, parallel arrays,
  isa-chain over our own types, enum switched to select behaviour) and
  finds 44 variant types to introduce where the tree has one (`Pattern`).
  A null that means absence becomes `std::optional` (or
  `std::optional<T&>` for a borrow). MLIR's open world enters the closed
  one through `support::classify<Ts...>(x) -> std::variant<Ts...,
  Other<From>>` (tested with MLIR types, `snip/classify.cc`).
- **Recoverable failure is `std::expected<T, E>`** with a typed error that
  answers the caller's decision (cpp-starter `AGENTS.md:1382-1411`):
  `support::Error = std::variant<Rejected{Reason}, Internal{what}>`,
  rendered once by `support::render` and turned into `LogicalResult` by one
  adapter, `support::to_logical` (tested with `and_then`/`transform` and an
  MLIR diagnostic, `snip/support.cc`). No bool plus `llvm::errs()`, no
  error string out-parameter, no null after an emitted error, no
  classification by matching `"unsupported ("` in a message
  (`idris-mlir-cc.cc:371-378`).
- **Generic code is concepts and constrained templates**: no
  `llvm::function_ref` parameter in our own functions (25 today), no
  unconstrained `template <typename Fn>`, no `std::function`, no
  `shared_ptr`, no `new`. Deducing `this` replaces the recursive
  `std::function` (`Dialect.cc:280`) and the `auto &self` lambdas
  (`Scc.h:30`, `BindingTimes.cc:104`). Ranges replace index loops where
  clearer (`AGENTS.md:1079-1080`).
- **No blanket `[[nodiscard]]`** (the user's decision). A discarded
  `std::expected` fails lint: `bugprone-unused-return-value` configured for
  `^::std::expected$` with `AllowCastToVoid: false`, plus a custom check
  for `std::ignore = expected` (both tested, `lint2/t.cc`). libc++ does not
  mark `std::expected` `[[nodiscard]]`, so without the lint a discard is
  silent (`snip/nd.cc`); `LogicalResult` and `FailureOr` are marked by MLIR,
  so `-Werror` already rejects discarding those.
- **cpp-starter's names and format**: `snake_case` for our names,
  `CamelCase` for types (`readability-identifier-naming`); MLIR's names
  stay `camelCase`, and the check leaves them alone automatically (tested:
  an override of an MLIR virtual and the out-of-line definition of a
  generated member are not reported, `lint2/naming.cc`). cpp-starter's
  `.clang-format` verbatim. Three comment forms only: `/** */` on a
  declaration, `/* PIN(name): */`, `/* SAFETY: */` in quarantine; the why
  that idris-mlir's AGENTS.md asks for goes into the `/** */` block.
- **One fail-stop helper**, `support::invariant(bool) noexcept`, until
  clang parses contracts (cpp-starter's own answer,
  `unsafe/net.internal.h:76-81`, `PINS.md:30-41`). It replaces the two
  `assert`s (`Clones.cc:105`, `Defunctionalize.cc:964`), which vanish in
  Release, and `llvm::report_fatal_error` (`Registration.cc:41`).

### 1.3 A converted example

`Ownership/Verify.cc` keeps two maps in which a null owner means "borrowed
parameter" and a bool result means "the path reaches its end"
(`Verify.cc:36-38, 56-60, 94-99, 147`). Converted:

```cpp
struct Owned { int references; };
struct BorrowedFrom { mlir::Value owner; };
struct BorrowedParameter {};
using Holding = std::variant<Owned, BorrowedFrom, BorrowedParameter>;

enum class Reach { End, Unreachable };

struct Alive {
	Checker const& checker;
	auto operator()(Owned held) const noexcept -> bool { return held.references > 0; }
	auto operator()(BorrowedFrom from) const noexcept -> bool { return checker.alive(from.owner); }
	auto operator()(BorrowedParameter) const noexcept -> bool { return true; }
};

auto walk(Checker& checker, mlir::Block& block) noexcept -> std::expected<Reach, Violation>;
```

The magic depth bound of `alive` (`Verify.cc:88`, 1024) goes: a chain of
`BorrowedFrom` ends in an `Owned` or a `BorrowedParameter` by
construction.

### 1.4 How each rule is enforced

cpp-starter's ladder (`AGENTS.md:1690-1721`), each rule at the highest rung
it can reach. Everything in the "lint" rows was run on the pinned
clang-tidy (`cpp-modern-lint.md`).

| Rule | Rung | Mechanism |
|---|---|---|
| C++26, no exceptions, no RTTI | compiler | `CMAKE_CXX_STANDARD 26`, `-fno-exceptions -fno-rtti` (have) |
| `import std`, modules | build graph | `CXX_MODULE_STD ON` on every target; `__cmake_cxx26` with `CXX_EXTENSIONS OFF` (cpp-starter `CMakeLists.txt:190-191`; without it the importer fails, tested) |
| no raw buffers in `src/` | compiler | `-Wunsafe-buffer-usage` on `src/` |
| exhaustive switches | compiler | `-Wswitch` + `-Wcovered-switch-default`; `custom-switch-default` |
| `expected` not discarded | lint + lint-fail test | `bugprone-unused-return-value` (`^::std::expected$`), `custom-expected-ignored` |
| `noexcept` | lint + lint-fail test | `custom-noexcept-function` (TableGen hooks exempt by name), `custom-noexcept-lambda` |
| glue stays in glue | lint | `custom-no-mlir-inheritance` in `src/` |
| no inheritance between our types, `std::function`, `function_ref` parameters, `shared_ptr`, `new`, default arguments, bool parameters, mutable globals, local statics, pointer signatures, `(void)` | lint | the custom checks of `src/.clang-tidy` |
| names | lint | `readability-identifier-naming` |
| variants over tags, `expected` over bool + errs, comment forms | review | cpp-starter's checklist (`AGENTS.md:1757-1795`) with `cpp-modern-audit.md` as the worklist |

---

## 2. The modules decision

readability.md measured the C++-modules migration and recommended
reverting it: "892 lines of re-exports so that 720 lines can live in 25
files", "Nothing yet", and every name MLIR code uses must be re-exported by
hand (readability.md:50-51, 511). The user now mandates closeness to
cpp-starter, whose rule is modules and no project headers
(`AGENTS.md:54, 415-491`), and defers to the evidence. The evidence:

### 2.1 What was measured

1. **Modules work with MLIR at full scale, `import std` included.**
   `idr.mlir`'s 87-header global module fragment followed by `import std;`
   compiles (36 s, 140 MB BMI), and so do all of `idr.facts` and its plain
   importer `Facts/Pass.cc`, each with `import std;` added
   (`scratchpad/research/cpp-modern/stdfull/`). The build tree's `std.pcm`
   is `gnu++26` and must be `c++26` (the one fix, section 1.4). So a revert
   to headers would be a deviation from cpp-starter that MLIR does not
   force, which the mandate rules out.
2. **The 892 lines are three things, of which one is forced.**
   - 196 lines re-export `std` (`Mlir.cppm:697-892`, 181 `using`s, the
     tree's one `NOLINT`). `import std` makes them unnecessary: delete.
   - ~20 lines include `std` headers in the fragment: delete with them.
   - 87 includes and 543 `using` declarations re-export MLIR, LLVM and the
     TableGen-generated idr classes. These are forced: C++ has no way to
     make a global-module-fragment namespace visible wholesale. Tested:
     `export using namespace lib;` compiles, but an importer still gets
     "declaration here is not visible" for `lib::Value`
     (`snip/mods2/`). A name per line is the only mechanism, and it is
     cpp-starter's own shape for a header-only vendor: a foreign module
     that "export[s] a safe module partition ... upward"
     (`AGENTS.md:400-402`; `foreign/exec.cc`). Record it in
     `PIN(mlir-cxx-api)`.
3. **The 25 files are MODULES.md's rule, not cpp-starter's.** MODULES.md
   requires that "interface units declare and never define" and one
   exported function per implementation unit (`lib/MODULES.md:18-23`),
   because of `PIN(cmake-module-restat)`. cpp-starter says the opposite:
   "One partition per concern, in one file (roughly 50-300 lines). Do not
   split a partition into interface and implementation units; split only on
   demonstrated rebuild pain" (`AGENTS.md:444-446`). In cpp-starter's form
   `facts` is 7 files (a primary interface and six partitions), not 25:
   readability.md's critique of the file count is a critique of a
   deviation from cpp-starter.
4. **The rebuild pain is measurable, and it is small once importers are
   modules.**
   - The PIN's stated cause is inaccurate: CMake 4.2 *does* give every
     module edge `restat = 1` (`build/dev/.../idr_dialect.dir/CXX.dd`).
     The real cause is that clang's BMI changes with any byte of the
     interface source, a trailing comment included, even with reduced BMIs
     (the default in clang 23, `Driver/ToolChains/Clang.cpp:4251-4252`):
     tested, `restat/` (every variant of the source gave a new BMI hash).
     So an edit to a partition recompiles its importers.
   - Compile time per unit, same flags as `build/dev` (tested,
     `stdfull/`): a plain unit that includes MLIR's headers takes 17-28 s
     (`Stack/Tail.cc`, 18 lines: 20.6 s, of which 15.7 s parsing headers per
     `-ftime-trace`; `Passes/Prune.cc`: 28.2 s). The same code as a module
     unit importing `idr.mlir` takes 0.4-3.4 s (the 16 implementation units
     of `idr.facts`). A precompiled header of the same 87 headers gives
     4.0 s and 6.9 s for those two plain units.
   - So an edit to a partition costs its importers' 0.4-3.4 s each, not
     20 s each, *once the importers are module units*; today all 9
     importers of `idr.facts` outside the module (its own pass glue and 8
     units of other areas) are plain units, which is what makes the
     declare-only rule look necessary. With 4 cores, rebuilding 10 module
     importers is seconds (conjecture from the per-unit times).
   - A full rebuild of ~85 plain units at ~20 s is ~28 CPU-minutes; as
     module units, ~36 s for `mlir_api` plus ~85 × 2 s, ~3.5 CPU-minutes
     (conjecture: extrapolated from 20 measured units).
5. **What stays a real cost.** The pitfalls MODULES.md lists
   (`lib/MODULES.md:55-77`): every `#include` before every `import`
   (clang #61465), macros do not cross imports (`MLIR_DEFINE_...TYPE_ID`,
   `GEN_PASS_DEF`, `assert`), and `Passes.h.inc` declares
   `createIdr<Pass>()` in the global module. The zoning absorbs most of
   them: TypeID macros, pass bases and hooks are glue in plain units by
   construction, and `assert` is gone.

### 2.2 Recommendation

**Keep modules and finish them in cpp-starter's form, not MODULES.md's.**

- `import std` everywhere; delete `Mlir.cppm`'s `std` block and its
  `NOLINT` (−216 lines).
- Rename: undotted module names (cpp-starter `AGENTS.md:441-443`):
  `idr.mlir` → `mlir_api`, `idr.facts` → `facts`; `.cppm` → `.cc`
  (`AGENTS.md:457-469`).
- One module per area, partitions of 50-300 lines *with their
  definitions*; retire the declare-only rule and the one-function-per-file
  layout. `facts` goes from 25 files to 7.
- Rewrite `PIN(cmake-module-restat)`: its symptom (no `restat`) is wrong;
  the true symptom (any byte of an interface changes its BMI) is a cost,
  not a workaround, and cpp-starter already says how to respond ("split
  only on demonstrated rebuild pain"). Keep the entry only if an area
  demonstrates the pain; then that area may split its partition.
- `lib/MODULES.md` (91 lines) shrinks to the pitfalls and the six steps in
  cpp-starter's form, or folds into the `src/` README (cpp-starter has one
  per zone).
- Net: the re-export module drops to ~650 lines, all forced; the file
  count per area follows cpp-starter's 50-300-line partitions; every unit
  compiles 5-10× faster than a plain one.

This agrees with readability.md where it measured ceremony that constrains
nothing: the grep spec tests go (`cpp-modern-lint.md` section 7), the
profile stops being waived for 100% of the code (the dialect profile
governs `src/`), and PINS.md loses the entries that recorded a waiver.
It disagrees on the revert, on the evidence above.

---

## 3. Deviations from cpp-starter: `PINS.md` after the conversion

Rule: an entry stays only if LLVM, MLIR, the toolchain or the platform
forces it, or the user decided it.

| Entry | Verdict | Why |
|---|---|---|
| `mlir-cxx-api` | **rewrite, narrower**: glue is the TableGen hooks, the pass bases, classes deriving MLIR bases, DRR, `mlir_api`'s re-export list, the static downcasts MLIR's callbacks force (`Inline.cc:154`, `idris-mlir-cc.cc:433`), and `std::function` parameters of MLIR APIs; everything else is dialect code | forced |
| `tablegen-hooks` | **new**: ODS writes hook declarations without `noexcept`; the lint exempts them by name | forced (ODS has no field for it) |
| `llvm-function-traits-noexcept` | **new**, with `upstream/llvm-function-traits-noexcept` (the reproducer is `snip/ft.cc`) and a `tests/upstream/` check, per AGENTS.md | forced (LLVM bug) |
| `clang-tidy-custom-check-invalid-loc` | **new**, with its `upstream/` report: a custom check that binds an implicit declaration aborts clang-tidy (`Loc.isValid()`, `ClangTidyDiagnosticConsumer.cpp:180`); every query has `unless(isImplicit())` | forced (clang-tidy bug) |
| `clang-tidy-custom-checks` | **new**: clang-query checks need `--experimental-custom-checks` | toolchain |
| `clang-contracts` | **new**, cpp-starter's entry verbatim (`PINS.md:30-41`): `support::invariant` | toolchain |
| `libcxx-no-indirect` | **new**: `support::Box<T>` until libc++ ships `std::indirect` | toolchain |
| `libcxx-no-function-ref` | **new**: `llvm::function_ref` stays where an MLIR API takes one | toolchain |
| `signal-handler-state` | **new**: the globals a signal handler reads (`Eval/Child.cc:35-36`), in `unsafe/` | platform (POSIX signals) |
| `unconverted-areas` | **new, temporary**: `-Wno-unsafe-buffer-usage` and the lint baseline on areas not yet converted; deleted with the last area | transition |
| `cmake-module-restat` | **rewrite** as in 2.2, or delete | — |
| `zones-on-demand` | **delete**: the zones hold code | met |
| `llvm-cxx17-headers` | **delete**: its retire condition was the first stage-2 build (`PINS.md:218-224`), and `build/dev` exists and passes | met |
| `runtime-quarantine` | **rewrite**: the runtime keeps its C ABI and C header, and is now `noexcept`, `import std`, and linted with the quarantine profile | forced (C ABI) |
| `clang-libcxx`, `clang-no-reflection`, `no-stdexec`, `cmake-import-std-uuid`, `llvm-force-enable-stats`, `orc-lljit`, the upstream MLIR bug entries, the platform entries | stay | as recorded |

No `mlir-naming` entry: the previous draft proposed one (camelCase as
forced); the naming test shows it is not forced (section 1.2).

Deviations that exist today with no entry, and what happens to each (each
is in the audit or the lint file):

1. no `import std` (`foreign/idr/CMakeLists.txt:159-164`): goes;
2. dotted module names and `.cppm`: go;
3. `//` comments, closers, banners: go;
4. LLVM naming, no `.clang-format`: go;
5. LLVM containers and `raw_ostream`: **stay where they meet MLIR's API**
   (`SmallVector`, `DenseMap`, `StringRef`, `ArrayRef` are its parameter
   types; converting at every call would be worse). Inside our own code,
   `std::span`, `std::string_view`, `std::format`. Record as part of
   `mlir-cxx-api`;
6. mutable globals: the 13 `cl::opt`s become locals of `main` (tested,
   `snip/clopt.cc`); the signal-handler state gets its PIN;
7. function-local statics (`Idr.h:65`, `Registration.cc:16`,
   `Child.cc:92`): go;
8. `shared_ptr` (`Canonicalize/Pass.cc:85,117`): goes
   (`FrozenRewritePatternSet` is itself a shared handle);
9. `std::function` recursion: goes (deducing `this`);
10. the overload-set `Match` (`Specialize/Pattern.cc:15-17`), which
    cpp-starter forbids by name: goes (visitor structs);
11. the four grep spec tests: go (cpp-starter forbids grep checkers,
    `AGENTS.md:1701-1704`);
12. `foreign/idr/bench` (not built, not tested, preprocessor-configured):
    delete.

---

## 4. The plan

Each step keeps behaviour identical, proved by the project's suites and by
three invariance checks (4.4). Each area is converted whole, in one
change: its move to `src/`, modules, `noexcept`, variants, `expected`,
concepts, names, comments. Nobody touches a file twice.

### 4.1 Phase 0: shared prerequisites (one agent, serial, first)

1. **Build**: `__cmake_cxx26` `CXX_EXTENSIONS OFF`; `CXX_MODULE_STD ON`
   everywhere; `Mlir.cppm` → `foreign/idr/mlir_api.cc` (module `mlir_api`),
   without the `std` block; `idr.facts` → `facts` (still in `lib/Facts`
   until wave 1 moves it); the clang warnings of `cpp-modern-lint.md`
   section 6. The force-include of `Support/EnableStatistics.h`
   (`PIN(llvm-force-enable-stats)`) stays on glue units and `mlir_api`
   only: `src/` units import the BMI and need no macro (conjecture: one
   build confirms).
2. **The `support` module** in `foreign/idr/support/` (prototypes tested in
   `snip/support.cc`, `snip/classify.cc`, `snip/fnpat.cc`):
   `classify`, `walk`, `type_switch`, `walk_attrs`, `Box`, `invariant`,
   `Error`/`Rejected`/`Internal`/`render`/`to_logical`, `FnConversion`,
   `definer`/`only_user`, and `references` (the six copies of "what a
   function refers to", `cpp-modern-audit.md` 0.3). This is the one module
   every area imports besides `mlir_api`: keep it stable (an edit rebuilds
   every importer, 2.1 item 4).
3. **ODS**: `discardableAttrs` for the ten `idr.*` names
   (`DialectBase.td:40`); `noexcept` on the `extraClassDeclaration`
   methods; traits `Idr_ReturnsWord`, `Idr_Feedable`. mlir-idioms.md 3.1-3.2
   argues some of these attributes should become types or ops; this step
   is valid either way.
4. **Lint and tests**: the four `.clang-tidy` files; `--experimental-custom-checks`
   in the lint preset; `make check` builds the lint preset;
   `tests/compile_fail/`, `tests/lint_fail/`, `tests/conformance/`;
   `.clang-format`; delete the four grep spec tests. Existing findings are
   baselined per area (a list each area empties, `PIN(unconverted-areas)`).
5. **Upstream reports**: `llvm-function-traits-noexcept` and
   `clang-tidy-custom-check-invalid-loc`, each with reproducer, report,
   `tests/upstream/` check and PIN, in the same change (AGENTS.md).
6. **Record the invariance baseline** (4.4) before any area changes.

### 4.2 Phase 1: the areas, fanned out (parallel agents)

An area imports its dependencies' modules, so waves exist only for that.
Within a wave the order is free. Each row is one agent's change; the
"owns" column is the set of files it may touch (plus its own new files in
`src/<area>/`), so agents never collide.

| Wave | Module | Owns (today's files) | Depends on | Key conversions (`cpp-modern-audit.md`) |
|---|---|---|---|---|
| 1 | `ir` | `include/idr/Idr.h` (non-glue part), `Dialect/Dialect.cc:120-205`, `Dialect/Ops.cc:20-50` | support | lookups → `optional`; `quantity_of` → `classify`; `CallsRuntime` name → `constexpr` |
| 1 | `facts` | `lib/Facts/*` | ir | 25 files → 7; `Effects` = the ODS set; `Termination`; `only` constrained; `Label`; `NotEvaluable` |
| 1 | `layout` | `Lower/Layout.{h,cc}` | ir | `Representation`, `Component`, `CellInfo` + checked `encode` |
| 2 | `ownership` | `lib/Ownership/*` except `Ops.cc` hooks | layout, facts | `Holding`, `Reach`, `Slot`, `Class`/`Origin`, `Position`, `Param` |
| 2 | `stack` | `lib/Stack/*` except `Pass.cc` | layout | `Flow`, `Node`, `Frame`, one `in_tail_position` |
| 2 | `specialize` | `lib/Specialize/*` except `Pass.cc` | facts | `Abstract`, `BindingTime`, `Consumer` (3 variants), `Raised`, `CloneKey`, `Box<Pattern>`, visitor structs |
| 2 | `passes` | `lib/Passes/*`, `Inline/Inline.cc` (module parts) | facts | `Labels`, `Key`, `Tail`, `Rank`; `Scc.h` over a concept; Inline's discarded parse fixed |
| 3 | `lower` | `lib/Lower/*` except `Layout` | layout, stack, ownership | `Mode`, runtime-call table, patterns as functions via `FnConversion`, `Signedness`, `Keys` |
| 3 | `eval` + `unsafe` | `lib/Eval/*`, `idris-mlir-cc.cc:540-570` | lower, facts | `Outcome`, `Run`, `JitError`, `Call`; `Fd`; one `reserve_stack` |
| 3 | `expect`, `canonicalize` patterns | `lib/Expect/*`, `lib/Dialect/Canonicalize/*.cc` (non-hook parts), `Canonicalize/Pass.cc` | facts, passes | property table; function patterns; `shared_ptr` gone |
| 4 | glue | `Dialect/Dialect.cc`, `Dialect/Ops.cc`, `Fold/Fold.cc`, `Ownership/Ops.cc`, every `*/Pass.cc`, `Registration.cc`, `Support/*` | all | hooks become one-line forwards; `Fold`'s `Scope` → one RAII owner per reference; `verifyOperationAttribute` → table |
| 4 | `driver` + tools | `tools/*.cc` | all | `Options`, `Emit`, `Output`, `ToolError`, the `expected` pipeline; `cl::opt` locals |
| any | `runtime` | `runtime/*` | none | `IDRIS_RT_NOEXCEPT`; `Meter` variant; `optional` out-params; quarantine profile |

Each area agent, per file:

1. moves it to `src/<area>/` as a partition of its module (or to glue or
   `unsafe/` as the audit says), with definitions, 50-300 lines;
2. applies the audit row: variants, `expected`, `optional`, concepts;
3. adds `noexcept`, trailing return types, `snake_case` (the lint's
   fix-its), the comment forms;
4. clears its lint baseline and its `-Wno-unsafe-buffer-usage`;
5. runs the gates (4.4) and changes nothing else.

### 4.3 What the dialect work changes about this

The representation, architecture and mlir-idioms streams will change ops
and passes (idioms 3.1-3.2 on the discardable attributes; architecture on
effects as `MemoryEffects`). Converting a file that is then rewritten is
wasted work. So: run phase 0 now; convert areas in the order the dialect
work leaves them stable; and have new dialect work land already converted
(the lint makes it the default once an area is clean).

### 4.4 How to verify behaviour is identical

1. The project's gates after each area: `make build`, `make check` (now
   including the lint preset), `make test`, `make test-idr`,
   `make test-mlir-tools` (AGENTS.md "Checks").
2. **IR invariance.** Before phase 0, run `idris-mlir-cc --emit=mlir` and
   `--dump-after=all` over `tests/e2e` and `bench`, and keep the outputs
   outside the tree. After each area, rerun and diff. The modernization is
   required to be IR-identical; SSA names are deterministic because MLIR
   runs single-threaded (`idris-mlir-cc.cc:341-343`), so a byte diff is
   exact.
3. **Object invariance**: the `.o` of every e2e program should be
   byte-identical too.
4. **Remarks and statistics invariance**: `--stats` and `--remarks-file`
   per program. The typed `Outcome`/`Run` must not change one eval remark.
5. **The lint baseline shrinks monotonically**, checked by count.

The deliberate behaviour changes are separate, small changes with their own
tests, not part of a conversion: the checked info-word encoder (a program
whose tag or object count does not fit is rejected instead of miscompiled),
the Inline default-pipeline parse, and `Child.cc`'s truncated-record
detection.

---

## 5. Risks

- **Compile time of `support` and `mlir_api` edits**: every importer
  rebuilds (2.1 item 4). Keep both stable; add names in batches.
- **`std::variant` as a `DenseMap` key** needs `DenseMapInfoVariant.h`
  (present, tested). A variant of two handles is 16 bytes where one handle
  is 8 (`snip/support.cc`). `Defunctionalize`'s `Key` is already a pair,
  so it does not grow. Measure `bench/` compile times before and after the
  `passes` area.
- **Visitor structs are more verbose than lambda overload sets.**
  cpp-starter chose them deliberately (`AGENTS.md:1851-1854`); the cost is
  one small struct per `visit`. Where one alternative is tested,
  cpp-starter itself uses `std::get_if`/`holds_alternative`
  (`unsafe/net.loop.cc:88,133,168`).
- **The TableGen hooks stay non-`noexcept`** unless ODS grows a field; they
  are about 100-120 one-line forwards, exempt by name. A new hook name not
  in the list is reported, which is the safe direction.
- **The function_traits bug** keeps three lambdas non-`noexcept`. If
  upstream fixes it, the wrappers become plain calls and the PIN goes.
- **The rename to `snake_case`** touches every line that names our own
  functions. The fix-its do it per unit; run it per area, inside that
  area's conversion, so no line is touched twice.

## 6. Open questions

- One module per area (as planned) or one module `idr` with the areas as
  partitions (cpp-starter's single `starter` module)? Per area keeps
  rebuilds local and the interfaces explicit; one module is closer to the
  letter of cpp-starter's example. Per area is recommended; the partition
  form is available inside each.
- `src/`'s module names are unprefixed (`facts`, `lower`): collisions with
  other libraries' module names are impossible today (nothing else ships
  modules here) but not in general. cpp-starter forbids dotted names; an
  `idr_` prefix (`idr_facts`) is the fallback if one ever collides.
- `-fexperimental-library` (only for `optional` as a range): no, unless a
  second wanted feature needs it.
- Should the runtime import `std`? It links no C++ library at runtime
  (`PIN(runtime-quarantine)`); `import std` brings no link-time
  dependency for header-only facilities, but this needs one build to
  confirm (conjecture).
