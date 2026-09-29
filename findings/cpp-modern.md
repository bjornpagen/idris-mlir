# cpp-modern: all of idris-mlir's C++ at cpp-starter's standard

Stream `cpp-modern`. Research only: nothing in the tree was changed. Detail
lives in four side files:

- `cpp-modern-starter.md`: (a) cpp-starter's patterns and lint gates, with
  file:line.
- `cpp-modern-audit.md`: (b) the audit of `foreign/idr`, `runtime/` and the
  tools, area by area, with the `std::variant` or `std::expected` each site
  becomes.
- `cpp-modern-lint.md`: (c) the gates to copy, the exact `.clang-tidy`,
  custom checks tested on the pinned clang-tidy, and what they find in the
  tree today.
- `cpp-modern-toolchain.md`: (e) what the pinned clang 23.1.2 and libc++
  implement, each feature tested in the scratch directory.

Evidence is file:line in `/home/user/idris-mlir` (idris-mlir) or
`/home/user/bjornpagen/cpp-starter` (cpp-starter), or a snippet compiled with
`.toolchain/llvm-musl/bin/clang++` under
`scratchpad/research/cpp-modern/snip/`. Everything marked *tested* was
compiled and run on the pinned tools. Everything else is conjecture, and says
so.

---

## 0. The mandate, and how it is enforced

### 0.1 The end state

Every line of C++ in idris-mlir (`foreign/idr/lib`, `foreign/idr/tools`,
`runtime/`, `foreign/idr/bench`) is cpp-starter dialect code in
C++26. The only exceptions are what LLVM and MLIR force, and each of those
is a thin, named piece of glue with a `PINS.md` entry.

- **Language:** `-std=c++26` on the pinned clang 23.1.2 with libc++,
  `-fno-exceptions -fno-rtti`. `import std;` in every unit (tested: it
  works next to MLIR's headers, §0.4). Nothing past C++26 exists to use
  (§0.2).
- **Every function is `noexcept`.** The exceptions are the hooks whose
  declarations TableGen writes, and lambdas handed to an LLVM template that
  cannot take a `noexcept` callable. Each exception is exempted by a
  matcher, not by a comment (§0.3).
- **Every non-void function is `[[nodiscard]]`**, and a discarded
  `std::expected` fails the build. This matters here because libc++ does
  *not* mark `std::expected` nodiscard. Discarding an `mlir::FailureOr`
  warns today; discarding a `std::expected` is silent (tested,
  `snip/nd.cc`). Moving to `std::expected` without this gate would lose a
  check.
- **Closed alternatives are `std::variant`,** visited by a visitor struct
  with one `operator()` per alternative (cpp-starter AGENTS.md:1833-1854),
  or by the C++26 member `v.visit(...)`. That covers every tag enum with a
  payload, every bool that selects behaviour, every null handle or pointer
  used as a case, every `bool unknown` next to data, every parallel
  `SmallVector<bool>`, and every isa-chain that classifies our own closed
  set of types or ops. The audit finds 31 such sites, listed with the
  variant each becomes (`cpp-modern-audit.md`).
- **Recoverable failure is `std::expected<T, E>`.** `E` is a typed error
  that says what the caller decides: `Rejected{Rule}`, `Internal{...}` or
  `Budget{...}`. It is never a string prefix and never a bool plus
  `llvm::errs()`. At an MLIR boundary, one adapter in `idr.support` turns
  `expected` into `LogicalResult`/`FailureOr` and back.
- **Generic code is concepts and constrained templates:** no
  `llvm::function_ref` inside our own code, no unconstrained `template
  <typename Fn>`, no `std::function`, no `shared_ptr`. `auto` and trailing
  return types throughout (cpp-starter's spelling, `auto f() -> T`).
  Deducing `this` replaces the `std::function` and `auto &self` recursive
  lambdas. `std::optional<T&>` replaces nullable pointers and nullable op
  handles. Ranges replace index loops.
- **Modules everywhere.** All code is in named modules. What is left in
  plain translation units is TableGen glue only: the dialect's and ops'
  generated hooks, the `GEN_PASS_DEF` pass bases, and DRR. Each glue unit
  forwards to a module function in one line.
- **MLIR's inheritance is confined to four shapes of glue.** These are the
  TableGen pass base, one `FnConversion<Op, auto Fn>` adapter for every
  conversion pattern, `RewritePatternSet::add(fn)` for every rewrite pattern
  (MLIR's `FnPattern`, PatternMatch.h:912; tested), and the dialect's
  interfaces. No project type inherits from another project type (a custom
  check).
- **Lint is a build.** The `lint` preset runs clang-tidy with cpp-starter's
  quarantine checks, the modernize and LLVM/MLIR checks, and eleven
  clang-query custom checks. It fails on any finding. `make check` runs it,
  and compile-fail tests pin the compiler-rung rules (§0.5).

### 0.2 The language level: C++26, and nothing past it is worth having

*Tested* (`snip/`, `cpp-modern-toolchain.md`):

- The pinned clang accepts `-std=c++26`/`c++2c` (`__cplusplus` 202400) and
  also `-std=c++2d` (`__cplusplus` 202700;
  `clang/include/clang/Basic/LangStandards.def:197`). `c++2d` enables
  nothing: no clang feature is gated on `CPlusPlus29` apart from version
  macros (`grep CPlusPlus29 clang/lib`). libc++ maps every `__cplusplus`
  above 202302 to `_LIBCPP_STD_VER 26`
  (`libcxx/include/__configuration/language.h:33-36`). CMake 4.2 knows no
  `cxx_std_29` (`Modules/Compiler/Clang.cmake:321` stops at `cxx_std_26`).
  **Mandate: `CMAKE_CXX_STANDARD 26`, as both repos already set.**
- `-fexperimental-library` adds, of what we would use, only optional's range
  support (`_LIBCPP_HAS_EXPERIMENTAL_OPTIONAL_ITERATOR`,
  `__configuration/experimental.h:36`; tested). It is a module-ABI flag, so
  it would have to go into the global flags for the std module's BMI too.
  Not worth it: leave it off.
- Reflection is a stub: `^^` is a cc1-only flag, and `^^S` gives "unknown
  or unimplemented reflectable entity" (tested). The user dropped it; the
  `clang-no-reflection` PIN stays.
- Contracts (`pre`, `post`, `contract_assert`) are not implemented: there is
  no flag. P2688 pattern matching is not implemented either. cpp-starter's
  own answer for a clang graph without contracts is one fail-stop helper
  (`unsafe/net.internal.h:76-81`, `PINS.md:30-41`, `clang-contracts`). Adopt
  it: `idr::invariant(bool)` traps. It replaces the two `assert`s
  (`Specialize/Clones.cc:105`, `Passes/Defunctionalize.cc:964`), which vanish
  under `NDEBUG` in Release, and `llvm::report_fatal_error`
  (`Registration.cc:41`).
- **Usable today, and to be used:**
  - `std::expected` with the monadic `and_then`, `or_else`, `transform` and
    `transform_error`, and `expected<void, E>`;
  - `std::variant` with the member `visit` (P2637, `__cpp_lib_variant`
    202306), and `constexpr` variants;
  - `std::optional<T&>` (P2988, `__cpp_lib_optional` 202506), and
    optional's `and_then`/`transform`;
  - deducing `this`, `auto(x)`, `if consteval`, `[[assume]]`,
    `std::unreachable`, `std::to_underlying`, `using enum`;
  - pack indexing (`T...[0]`), structured-binding packs
    (`auto [...xs] = t`), structured bindings as conditions, `_`
    placeholders, `= delete("why")`, computed `static_assert` messages;
  - expansion statements (`template for`, P1306), concept template
    parameters (P2841), variadic `friend`, `#embed`;
  - `std::print`/`std::format`, formatting of ranges, `ranges::to`,
    `views::enumerate`, `zip`, `concat`, `chunk_by`, `ranges::fold_left`,
    `ranges::contains`;
  - `std::flat_map`, `std::mdspan`, `std::span::at`,
    `std::saturating_add`, `std::bit_cast`, `std::byteswap`.
- **Not in libc++ 23 (so not in the mandate):** `std::function_ref`,
  `std::move_only_function`, `std::copyable_function`,
  `std::inplace_vector`, `std::indirect`, `std::polymorphic`,
  `std::generator`, `std::execution`, `views::cartesian_product`,
  `std::runtime_format`, `std::start_lifetime_as`, and the
  `trivially_relocatable_if_eligible` keyword (the feature macro is defined
  but the keyword does not parse).
  - Two gaps shape the design. Without `std::indirect`, the recursive
    `Pattern` of idr-specialize fakes a box with a one-element
    `std::vector` (`Specialize/Pattern.h:47-51`, "Exactly one"). A 30-line
    `idr::Box<T>` in `idr.support` replaces it; its PIN retires when libc++
    ships `indirect`.
  - Without `std::function_ref`, `llvm::function_ref` stays the one erased
    callable, and only at MLIR boundaries.

### 0.3 noexcept everywhere: what the API allows, and the enforcement

Under `-fno-exceptions` clang already treats every call as nounwind, so
`noexcept` does not change code generation. It is a contract that the
`noexcept` operator reports and that libc++ reads through
`is_nothrow_move_constructible` / `move_if_noexcept`. The mandate is to
state the contract on every function, so that it is true by construction
and checked.

What the LLVM/MLIR API allows. *Tested* in `snip/walk.cc`, `snip/fref.cc`,
`snip/fnpat.cc` and `snip/decl.cc`:

| Site | noexcept? | Evidence |
|---|---|---|
| Virtual overrides of MLIR bases (`runOnOperation`, `matchAndRewrite`, `initialize`, `getDependentDialects`, `Listener::notify*`, `Action::print`, `AnalysisState::print`) | **yes**: an overrider may be stricter than the virtual | `void runOnOperation() noexcept override` and `matchAndRewrite(...) const noexcept override` compile (`walk.cc`, `fnpat.cc`) |
| Hooks whose declaration TableGen writes (`fold` ×41, `verify` ×10, `verifySymbolUses` ×5, `inferResultRanges` ×5, `getCanonicalizationPatterns` ×5, `parse`/`print` ×8, `getSuccessorRegions`…, `IdrDialect::initialize`/`verifyOperationAttribute`/…, interface methods such as `getCrashCause`) | **no**: the definition must repeat the generated declaration's exception specification ("exception specification in declaration does not match previous declaration", `decl.cc`). ODS has no field for `noexcept` | ~120 definitions in `Dialect/*.cc` and `Fold/Fold.cc` |
| Methods we declare ourselves in ODS `extraClassDeclaration` / `extraClassDefinition` | yes: we write the declaration | — |
| Lambdas given to `llvm::function_ref`, `llvm::any_of`, `map_range` | yes | `fref.cc` |
| Lambdas given to `Operation::walk`, `TypeSwitch::Case`/`Default`, and anything else that deduces its argument through `llvm::function_traits` | **no** | `walk.cc`: "type `void ((lambda)::*)(FuncOp) const noexcept` cannot be used prior to `::`". `llvm/ADT/STLExtras.h:66-104` specializes `function_traits` for `R (C::*)(Args...) const` and non-`noexcept` function pointers only. Reduced to LLVM alone in C++17 (`snip/ft.cc`, four lines). **An upstream bug**: file `upstream/llvm-function-traits-noexcept` with that reproducer, add a `tests/upstream/` check, and add the PIN |
| `RewritePatternSet::add(fn)` with a `noexcept` function | yes: deduction goes through the function-pointer conversion | `fnpat.cc` |
| The C ABI (`runtime/idris_rt.h`) | yes, behind a macro: `link_check.c` includes the header as C, so `IDRIS_RT_NOEXCEPT` expands to `noexcept` in C++ only, as `IDRIS_RT_NORETURN` does already (`idris_rt.h:18-23`) | — |
| `pthread_create` / `sigaction` callbacks (`idris-mlir-cc.cc:544`, `Eval/Child.cc:54,93`) | yes: a `noexcept` function converts to the plain function pointer | — |
| Code in TableGen's `.inc` output, DRR patterns | not ours: system headers, outside every check | — |

Enforcement. This is cpp-starter's ladder (AGENTS.md:1690-1721), each rule
at the highest rung it can reach:

1. **clang-tidy custom checks** (clang-query, `--experimental-custom-checks`,
   in the pinned clang-tidy: `clang-tools-extra/clang-tidy/custom/`). Both
   were tested on the tree (`cpp-modern-lint.md` §3). The first exempts
   exactly the forced cases:

   ```yaml
   - Name: noexcept-function
     Query: |
       match functionDecl(isDefinition(), unless(isNoThrow()), unless(isImplicit()),
         unless(isExpansionInSystemHeader()),
         unless(cxxMethodDecl(ofClass(cxxRecordDecl(isLambda())))),
         unless(cxxMethodDecl(ofClass(cxxRecordDecl(isExpansionInFileMatching("/build/.*\\.inc$")))))).bind("fn")
   - Name: noexcept-lambda
     Query: |
       match cxxMethodDecl(ofClass(cxxRecordDecl(isLambda())), unless(isNoThrow()),
         unless(hasAncestor(callExpr(callee(functionDecl(isExpansionInSystemHeader())))))).bind("l")
   ```

   The first exempts the members of TableGen-generated classes by where the
   class is declared. The second exempts a lambda only when it is an
   argument of a call into LLVM/MLIR. Measured before any conversion: 52
   findings in `Lower/Runtime.cc`, 30 in `Specialize/Pattern.cc`, 23 in
   `tools/idris-mlir-cc.cc` (sample, §3 of the lint file).
2. **One wrapper, so that the lambda exemption shrinks to one file.**
   `idr.support` exports `walk<Op>(Operation &, std::invocable<Op> auto &&f)
   requires std::is_nothrow_invocable_v<...>` and `typeSwitch`. Their one
   non-`noexcept` inner lambda is the only place that hands MLIR a
   callable. After that conversion, `noexcept-lambda` can drop its
   system-header exemption and exempt only `lib/Support/`.
3. **performance-noexcept-move-constructor / -swap / -destructor**
   (in `performance-*`, already on).
4. **A compile-fail test** in cpp-starter's form
   (`tests/compile_fail/CMakeLists.txt`, cpp-starter). A unit that
   discards an `expected` must fail with its pinned diagnostic. The
   noexcept rule is a lint rule, so its test is a lint-fail test instead: a
   fixture with one non-`noexcept` function, on which `lint` must report
   `custom-noexcept-function`.

### 0.4 Deviations from cpp-starter: what stays, what goes, and what is missing

The rule: a deviation stays only if LLVM or MLIR forces it, or it is a scope
decision the user made. Each one has a PINS.md entry saying which.

Today's `PINS.md` entries:

| Entry | Verdict | Why |
|---|---|---|
| `mlir-cxx-api` | **stays, narrowed.** Rewrite it to name the four glue shapes of §0.1 and nothing else. "All MLIR-facing code is quarantine code" becomes "only TableGen glue is plain; everything else is dialect code in modules" | forced (inheritance, CRTP, `.inc`) |
| `cmake-module-restat` | **stays, amended.** "Interfaces declare and never define" forbids templates and concepts in interfaces, and they must be defined there. One stable `idr.support` interface (`Box`, `classify`, `walk`, `expected`↔`LogicalResult`, visitor helpers, concepts) is exempt: it changes rarely, which is the point of the rule | CMake/clang tooling |
| `zones-on-demand` | stays | nothing is dialect code outside MLIR's reach. Everything touches `mlir::Value` |
| `orc-lljit`, `prune-before-remove-dead-values`, `remove-dead-values-address-taken`, `inline-unreachable`, `llvm-force-enable-stats` | stay | upstream LLVM/MLIR bugs and ABI |
| `platform-gate-x86_64`, `versions-in-lock-file`, `stage2-thinlto`, `musl-thread-stacks`, `no-sanitizer-runtimes`, `darwin-inert-mitigations`, `cmake-import-std-uuid`, `runtime-cx16`, `simdutf-dispatch`, `linux-uapi-from-host`, `mirrored-sources`, `idris-support-host-cc` | stay | user scope or platform facts; not about the C++ profile |
| `clang-libcxx` | **stays, and gains a use.** Clang has warnings GCC lacks. Add `-Wunsafe-buffer-usage` (tested), which puts cpp-starter's no-pointer-arithmetic rule (§12, §24) at the compiler rung in dialect code. Turn it off only on the unsafe files. Add `-Wshadow-all -Wcomma -Wextra-semi -Wmissing-noreturn -Wunreachable-code-aggressive -Wcovered-switch-default` too | toolchain choice |
| `clang-no-reflection` | stays | user decision |
| `no-stdexec` | stays | nothing is async |
| `llvm-cxx17-headers` | **goes.** Its retire condition was the first stage-2 build ("the first `make build` does", `PINS.md:204`), and `build/dev` exists and passes | met |
| `runtime-quarantine` | **stays, narrowed.** The runtime keeps its C ABI, but it can be `noexcept` (by macro), `[[nodiscard]]`, `std::bit_cast`/`std::span`/`std::optional` internally (header-only), and linted by the quarantine profile, which today it is not: `CXX_CLANG_TIDY` is on for `idris_rt` only through the preset | vendored C++ headers, C ABI |

Deviations that exist today with **no** PINS entry. Each must be removed or
recorded:

1. **No `import std`.** `CXX_MODULE_STD OFF` on `idr_dialect` and the tools
   (`foreign/idr/CMakeLists.txt:159-164`) says "The MLIR API is not
   module-aware, so no target imports std". Instead, `lib/Mlir.cppm`
   re-exports ~150 `std` names under
   `// NOLINTBEGIN(bugprone-std-namespace-modification)` (`Mlir.cppm:699-892`),
   the one lint suppression in the tree. *Tested*: a module unit whose
   global fragment includes `mlir/IR/BuiltinOps.h` and then `import std;`,
   and a plain unit that includes MLIR headers and then imports `std` and
   that module, compile, link against `libMLIRIR` and run
   (`snip/mods/a.cppm`, `b.cc`). **Goes**: turn `CXX_MODULE_STD` on and
   delete the `std` block and the NOLINT. Only the order rule stays: every
   `#include` before every `import` (clang #61465, `MODULES.md:57-60`).
   Verify at full scale in phase 0 (§2).
2. **Dotted module names** (`idr.mlir`, `idr.facts`) against cpp-starter
   AGENTS.md:441-443 ("No dotted module names anywhere"), and **`.cppm`**
   against AGENTS.md:457-469 (".cc" only; "interface-ness is declared by the
   build"). **Goes**: `idr_facts` or `facts` in `lib/Facts/facts.cc`. The
   rename is cheap now, while one area is converted.
3. **`//` comments, `} // namespace` closers, banners**
   (`//===---===//` in `Defunctionalize.cc`), against AGENTS.md:1445-1482
   (three comment forms only). idris-mlir's AGENTS.md wants comments that
   explain why, and those carry real value. **Conform in form, keep the
   content**: a why-comment becomes a `/** */` block on its declaration,
   in-function narration moves into that block or into a better name, and
   closers and banners go.
4. **Style: LLVM naming (camelCase) and LLVM formatting**, with no
   `.clang-format` at all. cpp-starter uses snake_case, east-`const`, tabs
   and 140 columns (`.clang-format`). The naming is forced in practice:
   TableGen generates `getFoo()` accessors, and our overrides must be named
   `runOnOperation`. Mixing the two conventions would be worse than either.
   **Record** `mlir-naming` (camelCase, forced). **Adopt** cpp-starter's
   `.clang-format` except `ColumnLimit` and `IndentWidth`, which also
   follow LLVM (record them under the same PIN), and adopt trailing return
   types and east `const` (`modernize-use-trailing-return-type` has
   fix-its).
5. **LLVM containers and `raw_ostream`** in place of std containers and
   `std::print`. `SmallVector`, `DenseMap`, `StringRef`, `ArrayRef` and
   `raw_ostream` are MLIR's API types: passing `std::` types across it
   means converting at every call. **Record** `llvm-adt` (forced at the API
   boundary). Inside our own code, prefer `std::span`/`std::string_view`
   where the value never meets MLIR, and `std::format` into a `Twine` or a
   diagnostic.
6. **Mutable globals**: 13 `cl::opt`s (`idris-mlir-cc.cc:66-110`), and
   `guardLow`/`guardHigh` plus a function-local `static char alternate[]`
   (`Eval/Child.cc:34-35,93`). The `cl::opt`s go: LLVM supports `cl::opt`
   as locals of `main`, parsed before use, and typed values go to `run()`
   as an `Options` aggregate. The signal-handler globals are unsafe code
   by nature: **record** them with a SAFETY comment.
7. **Function-local static** `CallsRuntime::getHelper`'s `static const
   std::string` (`include/idr/Idr.h:64-71`). **Goes**: a `constexpr`
   function computes the name from `getOperationName()` at compile time
   (`std::string` is `constexpr` in libc++; tested,
   `constexpr_string.cc`), or TableGen writes it into the trait
   parameter.
8. **Shared ownership**: `std::shared_ptr<const FrozenRewritePatternSet>`
   (`Canonicalize/Pass.cc:85,117`). **Goes**: `FrozenRewritePatternSet`
   is itself a cheap copyable handle over an internal `shared_ptr`
   (`mlir/Rewrite/FrozenRewritePatternSet.h:34-38,95`), so the member can
   be the set.
9. **`std::function`** for a recursive lambda (`Dialect/Dialect.cc:280`)
   and the `auto &self` trick (`Passes/Scc.h:30-57`). **Go**: deducing
   `this`.
10. **Variadic-inheritance overload set** `Match` (`Specialize/Pattern.cc:15-17`),
    which cpp-starter forbids by name (AGENTS.md:1851-1854). **Goes**:
    visitor structs.

### 0.5 Enforcement summary

| Rule | Rung | Mechanism |
|---|---|---|
| C++26, no exceptions, no RTTI | compiler flags | `CMAKE_CXX_STANDARD 26`, `-fno-exceptions -fno-rtti` (have) |
| `import std`, modules only | build graph | `CXX_MODULE_STD ON`; plain units listed by name in a `glue` file set |
| no raw buffers in dialect code | compiler | `-Wunsafe-buffer-usage` on every unit but the unsafe ones |
| exhaustive `switch` over enums | compiler | `-Wswitch` (in `-Wall`) + `-Wcovered-switch-default` + no `default` |
| `[[nodiscard]]` + `expected` not discarded | compiler + lint + compile-fail test | `custom-nodiscard`, `bugprone-unused-return-value` with `^::std::expected$` (cpp-starter's option, `.clang-tidy:49-50`), `tests/compile_fail/discarded_expected` |
| `noexcept` | lint + lint-fail test | `custom-noexcept-function`, `custom-noexcept-lambda` |
| no inheritance between our types, no `std::function`/`shared_ptr`/`new`/default arguments/bool parameters/mutable globals/local statics | lint | eleven custom checks (`cpp-modern-lint.md` §2) |
| variants over tag+payload, `expected` over bool+errs, comment forms, visitor form | review | cpp-starter's checklist (AGENTS.md:1757-1795), plus `cpp-modern-audit.md` as the worklist |

---

## 1. Summary of findings (a)–(e)

- **(a) cpp-starter** (`cpp-modern-starter.md`). One concept, one mechanism
  (AGENTS.md:28-60). Closed sums are variants with visitor structs,
  failure is `expected` with a typed, retry-classifying error
  (AGENTS.md:1382-1411), and "failure is transparent" (1412-1423). Concepts,
  not inheritance, tags or `enable_if`. Every non-void function is
  `[[nodiscard]]`, and `std::ignore =` / `auto _ =` are the only ways to
  discard (1350-1380). Three comment forms. PINS.md is a tombstone
  registry. The lint innovations are:
  - the enforcement ladder with the rule that every rule "aspires upward"
    (1690-1721);
  - a *quarantine* clang-tidy profile that does not flag the ABI casts
    that justify the zone (`.clang-tidy:1-50`);
  - `bugprone-unused-return-value` configured for `expected`/`optional`;
  - compile-fail tests with a pinned diagnostic
    (`tests/compile_fail/CMakeLists.txt`);
  - a configure gate that pins every tool version (`CMakeLists.txt:1-81`);
  - a hardening profile in one interface target (`CMakeLists.txt:100-164`);
  - target-scoped, PIN-registered lint carve-outs
    (`foreign/CMakeLists.txt:29-37`);
  - no grep checkers, by decision (AGENTS.md:1701-1704).
- **(b) The audit** (`cpp-modern-audit.md`): 0 `noexcept`, 0
  `std::expected` and 1 `std::variant` in ~10.5k lines of our C++. There
  are 31 closed alternatives modelled as tags, bools, null handles or
  parallel arrays; the worst:
  - `Labels{bool unknown; names}` and
    `Key = pair<FnType, ArrayAttr>`, with null meaning "unknown" or "no
    closure" (`Passes/Defunctionalize.cc:75,409`);
  - `Abstract{Kind, param}`, where `param` means nothing for `Top`
    (`Specialize/BindingTimes.cc`);
  - `Run{Status, message}`, where `message` means something for 2 of the 5
    statuses (`Eval/Child.h:28-46`);
  - `Runtime(bool jit)`, branched on in 7 methods (`Lower/Runtime.cc`);
  - the ownership verifier's two maps, `held`/`owners`, with a null owner
    meaning "borrowed parameter" (`Ownership/Verify.cc`);
  - `Layouts::components`/`counted`: parallel vectors from two copies of
    the same isa-chain, a third copy in `Runtime::constant`
    (`Lower/Layout.cc:269-299`, `Runtime.cc:294-306`);
  - `Escapes::Flow = optional<...>`, where `nullopt` means *escape*, not
    absence (`Stack/Escape.h:79`).
  - Errors are `bool` + `llvm::errs()` in the tool (12 functions),
    `unique_ptr` + `std::string &error` in the JIT, and null returns after
    an emitted error in five places.
  - Rewrite patterns are classes where MLIR offers function patterns.
  - `discardableAttrs` in ODS is unused, so ten `"idr.*"` attribute names
    are string literals repeated across files.
- **(c) Lint** (`cpp-modern-lint.md`): the proposed `.clang-tidy` (exact
  text), eleven custom checks tested on the pinned clang-tidy, the preset
  and `make lint`, and the per-directory profiles: dialect, glue, unsafe,
  runtime. The results of a full run over all 102 units are recorded there.
- **(d) The plan**: §2 below.
- **(e) The toolchain** (`cpp-modern-toolchain.md`): §0.2 above, with every
  snippet.

---

## 2. The conversion plan, merged with phase 2 of MODULES.md

Principle: each step keeps behaviour identical, which the existing suites
and three new invariance checks prove (§2.3), and each area is converted
whole: modules, noexcept, variants, expected and concepts in one pass, so
nobody touches a file twice.

### 2.1 Phase 0: shared prerequisites (one agent, serial, first)

1. **Toolchain and build:**
   - `CXX_MODULE_STD ON` for `idr_dialect` and the tools. Delete the `std`
     block of `Mlir.cppm` and its NOLINT.
   - Rename modules to undotted names and `.cppm` to `.cc`
     (`idr.facts` → `facts` or `idr_facts`, `idr.mlir` → `mlir_api`).
   - Add the clang warnings of §0.4 (`-Wunsafe-buffer-usage` goes on area
     by area, as each area converts: a `set_source_files_properties`
     `-Wno-unsafe-buffer-usage` on unconverted units, with a PIN, deleted
     as each area lands).
2. **The `support` module** (today's `lib/Support`, converted first). This is
   the one interface allowed to define templates (§0.4). It exports:
   - `Box<T>`: a value-semantic heap box, `std::indirect` until libc++ has
     it, with a PIN.
   - `classify<Ts...>(from) -> std::variant<Ts..., Other<From>>`: the
     bridge from MLIR's open `isa`/`dyn_cast` to a closed sum. Prototype
     tested with MLIR types (`snip/classify.cc`).
   - `walk<Op>(root, f)` and `typeSwitch` for `noexcept` callables: the one
     place a non-`noexcept` lambda meets `function_traits` (PIN
     `llvm-function-traits-noexcept`, with its `upstream/` report and
     `tests/upstream/` check in the same change, per AGENTS.md).
   - `toLogical(expected<void,E>)`, `toFailureOr(expected<T,E>)`,
     `fromFailureOr`. `emit(Operation&, E const&)` renders a typed error as
     the diagnostic. With the diagnostic metadata that mlir-idioms.md
     proposes (its table at line 311), `Rejected{Rule}` becomes the
     `#idr.rule<...>` a handler reads, instead of the `"unsupported ("`
     prefix `idris-mlir-cc.cc:371-378` matches today.
   - `FnConversion<Op, auto Fn>`, the one conversion-pattern class (tested,
     `snip/fnpat.cc`).
   - `invariant(bool)`: the contracts stand-in (PIN `clang-contracts`,
     cpp-starter's own).
   - The concepts the areas share: `OpHandle`, `Lattice` (join, top,
     equality), `DiagnosticError`.
3. **The lint preset and gates** (`cpp-modern-lint.md`):
   - `.clang-tidy` profiles per directory;
   - `make lint` added to `make check`;
   - the `compile_fail` and `lint_fail` fixtures;
   - `.clang-format`.

   Only the fixtures must pass at first. Existing findings are baselined
   per area, a list that each area empties.
4. **ODS:** declare the ten `idr.*` discardable attributes in
   `Idr_Dialect`'s `discardableAttrs`
   (`mlir/include/mlir/IR/DialectBase.td:40`). The generated
   `getXAttrHelper()` gives typed `get`/`set`/`isAttrPresent`, and every
   string literal goes. mlir-idioms.md §3.1 argues these facts should not
   be discardable attributes at all. That is a dialect change; this step is
   only its C++ half, and it is valid either way.

### 2.2 Phase 1: the areas, fanned out (parallel agents)

Every area has a dependency set. The order within a wave is free. Waves
exist only because an area imports its dependencies' modules:

| Wave | Area (module) | Depends on | Key conversions (`cpp-modern-audit.md`) |
|---|---|---|---|
| 1 | `facts` (already a module) | support | one `Effects` lattice in place of struct-of-bools *and* the TableGen `Effect` bit enum; `Evaluation::total` → `Budget` enum; `only(op, std::predicate<Effects const&> auto)` |
| 1 | `lower::layout` (Layout.h/.cc) | support | `Representation` variant; `Component{Type, Counting}` in place of parallel `types`/`counted`; `SumLayout::tag` → `optional<IntegerType>`; `InfoWord` checked constructor (`expected`, the review-external packing bug) |
| 2 | `ownership` | layout | `Holding` variant (verifier); `Class` → `Origin`-carrying variant (counts); `Use` enum stays |
| 2 | `stack` | layout | `Flow` → `variant<Escapes, Forwards>`; `cell()` → `optional<Value>` |
| 2 | `specialize` | facts, support | `Abstract` variant; `Consumer` optionals; `Clone const*` → `optional<Clone const&>`; `Pattern::Linear` → `Box<Pattern>`; visitor structs |
| 2 | `passes` (defunctionalize, simplify, prune, tail-loops, loop-breakers) | facts, support | `Labels`/`Key` variants; `stronglyConnected` over a concept, not `function_ref` |
| 3 | `lower` (runtime, patterns, pass) | layout, stack, ownership | `Mode = variant<Executable{root, RootKind}, Jit>`; runtime calls as a typed table; `FnConversion` patterns; `Signedness` enum |
| 3 | `eval` | lower, facts | `Outcome` variant; `Jit::compile -> expected<Jit, JitError>`; `Call` product instead of three parallel arrays |
| 3 | `expect`, `inline`, `canonicalize` | facts, passes | `Property` table + `optional<Check>`; function patterns |
| 4 | glue: `Dialect/`, `Fold/`, `Registration.cc` | all | hooks become one-line forwards; `Fold`'s `Scope` → one RAII owner per runtime reference |
| 4 | tools | all | `Options` aggregate; `Emit`/`Output`/`Cpu`/`Dump` variants; `expected<Artifact, ToolError>` pipeline; `cl::opt` locals; typed `raw_pwrite_stream` |
| any | `runtime/` | none | `IDRIS_RT_NOEXCEPT`, `[[nodiscard]]`, `optional<size_t>` in place of `bool isInteger(..., size_t &)`, `std::bit_cast`, the quarantine lint profile; keep the C ABI |

Each area agent follows MODULES.md's six steps and adds, per file:

- `noexcept` and `[[nodiscard]]`;
- trailing return types;
- the variants and `expected`s the audit lists;
- concepts on its templates;
- the removal of `llvm::function_ref` wherever the callee is our own;
- the three comment forms;
- clearing its lint baseline.

### 2.3 How to verify behaviour is identical

1. The project's own gates after each area: `make build`, `make check`,
   `make test`, `make test-idr`, `make test-mlir-tools` (AGENTS.md "Checks").
2. **IR invariance.** Before phase 0, run `idris-mlir-cc --emit=mlir` and
   `--dump-after=all` over the whole `tests/e2e` and `bench` corpus, and
   keep the outputs out of the tree. After each area, rerun and `diff`.
   The C++ modernization is required to be IR-identical. SSA names are
   deterministic because MLIR runs single-threaded
   (`idris-mlir-cc.cc:341-343`), so a byte diff is exact. Any difference is
   a behaviour change and blocks the area.
3. **Object invariance** for the tools: the `.o` of every e2e program
   should be byte-identical too, since LLVM's input is identical. A
   difference in LLVM IR but not in MLIR means a tool-level change.
4. **Statistics and remarks invariance**: `--stats` and
   `--remarks-file` output per program. The typed `Outcome`/`Run` changes
   must not change a single eval remark.
5. **The lint baseline shrinks monotonically**, which is checked by count.

### 2.4 Risks

- **Compile time.** Module units that import `std` and `mlir_api` pay two
  BMIs. Measured at small scale only: `std.pcm` 7.5 s once, 37 MB; a unit
  over it 13 s. `cmake-module-restat` still rebuilds every importer when an
  interface changes, so keep `support` stable.
- **`std::variant` as a `DenseMap` key** needs `llvm/ADT/DenseMapInfoVariant.h`
  (present in the pinned tree). A variant of MLIR handles is 16 bytes where
  a pointer was 8. The defunctionalization maps are the hot ones: measure
  `bench/` compile times before and after.
- **Visitor structs are more verbose than lambda overload sets.**
  cpp-starter chose them deliberately. The cost is one small struct per
  `visit`.
- **The upstream `function_traits` bug** makes `walk`/`TypeSwitch` the one
  place where `noexcept` cannot reach. If upstream fixes it, the support
  wrapper becomes a no-op and the PIN goes.
- **The TableGen hooks stay non-`noexcept` forever** unless ODS grows a
  field. That is about 120 thin forwards, exempt by one matcher.
- **Churn against the other streams.** The dialect streams
  (representation, architecture, mlir-idioms) will change ops and passes.
  Converting a file that a representation change then rewrites is wasted
  work. So run phase 0 now and convert areas in the order the dialect work
  leaves them stable, or have the dialect work land converted.

---

## 3. Open questions

- Snake_case for our own functions next to MLIR's camelCase: this document
  recommends recording camelCase as forced. The user may prefer
  cpp-starter's names in module interfaces and camelCase only in glue.
- Should `foreign/idr`'s dialect code move to a `src/` zone? Only the glue
  would then be `foreign/`. That would match cpp-starter's layout exactly,
  at the cost of moving every file once. The move can be free if it
  coincides with each area's modules conversion.
- `-fexperimental-library` for optional's range support: no, unless a
  second feature behind it becomes wanted.
- Does `import std` hold at full scale with the 60-header global fragment
  of `mlir_api`? It was tested with two MLIR headers only. Phase 0 answers
  it first; if it fails, the `std` re-export stays as a PIN with an
  `upstream/` clang report.
