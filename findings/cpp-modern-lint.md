# cpp-modern (c): the gates to copy, exactly

Side file of `cpp-modern.md`. What to copy from cpp-starter
(`cpp-modern-starter.md` section 8), what to add for the user's mandate
(`noexcept` everywhere, variants, the discarded-`expected` lint, no blanket
`[[nodiscard]]`), and the text of every file. Every check below was run on
the pinned `.toolchain/llvm-musl/bin/clang-tidy` (LLVM 23.1.2) against
fixtures in `scratchpad/research/cpp-modern/lint2/` and, where marked, over
the tree (`build/dev/compile_commands.json`, 102 units,
`scratchpad/research/cpp-modern/lint/`).

---

## 1. Zones and their profiles

cpp-starter has one clang-tidy profile per zone and never conflates them
(`AGENTS.md:346-352`). The proposed layout (the moves are in
`cpp-modern.md` section 2) is four zones, one `.clang-tidy` each, all
inheriting the root:

| Zone | What lives there | Profile |
|---|---|---|
| `src/` | every module: the passes, analyses, the driver | **dialect**: root + the dialect checks (section 3) |
| `foreign/idr/` | TableGen input and glue: the hooks ODS declares, the `GEN_PASS_DEF` pass bases, DRR, `mlir_api` (the MLIR re-export module), the tools' `main` | **glue**: root + the glue checks |
| `unsafe/` | fork, mmap, signals, pthreads, reading JIT memory: `Eval/Child.cc`, `Eval/Jit.cc`, `Eval/Reify.cc`, the large-stack thread of `idris-mlir-cc` | **quarantine**: root only (cpp-starter's own) |
| `runtime/` | the C ABI runtime | **quarantine**: the root only |

Inheritance works as needed: a child `.clang-tidy` with
`InheritParentConfig: true` keeps the parent's `CustomChecks`, adds its own,
and can disable a parent's check by name (tested,
`scratchpad/research/cpp-modern/inherit/`).

## 2. The root `.clang-tidy` (quarantine profile, every zone)

cpp-starter's `.clang-tidy` verbatim (`.clang-tidy:1-51`), with four
changes:

- `misc-move-constructor-init` is gone from clang-tidy 23 (`--verify-config`:
  "unknown check"); it is `performance-move-constructor-init` now, which
  `performance-*` already enables.

- `CheckedReturnTypes` is `^::std::expected$` only. That is the user's one
  return-value rule. `mlir::LogicalResult` and `mlir::FailureOr` need no
  entry: MLIR declares them `[[nodiscard]]`, so `-Werror` already rejects a
  discarded one. libc++ does not mark `std::expected` (tested, `snip/nd.cc`).
- Two custom checks every zone shares: `noexcept-function` and
  `expected-ignored`.
- The header filter names our directories and excludes build output.

```yaml
---
InheritParentConfig: false
# The quarantine profile (cpp-starter's): real bugs in boundary code. Zones
# add their own rules in their own .clang-tidy.
Checks: >
  -*,
  clang-analyzer-*,
  bugprone-branch-clone,
  bugprone-copy-constructor-init,
  bugprone-dangling-handle,
  bugprone-infinite-loop,
  bugprone-misplaced-operator-in-strlen-in-alloc,
  bugprone-misplaced-widening-cast,
  bugprone-move-forwarding-reference,
  bugprone-multi-level-implicit-pointer-conversion,
  bugprone-not-null-terminated-result,
  bugprone-posix-return,
  bugprone-sizeof-container,
  bugprone-sizeof-expression,
  bugprone-suspicious-memory-comparison,
  bugprone-suspicious-string-compare,
  bugprone-suspicious-stringview-data-usage,
  bugprone-terminating-continue,
  bugprone-unchecked-optional-access,
  bugprone-undefined-memory-manipulation,
  bugprone-use-after-move,
  bugprone-unused-return-value,
  concurrency-*,
  misc-static-assert,
  misc-unused-using-decls,
  modernize-use-nullptr,
  performance-*,
  portability-*,
  -portability-avoid-pragma-once,
  readability-container-size-empty,
  custom-noexcept-function,
  custom-expected-ignored
WarningsAsErrors: '*'
HeaderFilterRegex: '.*/(src|unsafe|foreign/idr/(lib|include|tools)|runtime)/.*'
ExcludeHeaderFilterRegex: '(^|/)(build|\.toolchain|third_party)/'
SystemHeaders: false
FormatStyle: file
CustomChecks:
  - Name: noexcept-function
    Query: |
      match functionDecl(isDefinition(), unless(isNoThrow()), unless(isImplicit()),
        unless(isExpansionInSystemHeader()), unless(isMain()),
        unless(cxxMethodDecl(ofClass(cxxRecordDecl(isLambda())))),
        unless(cxxMethodDecl(ofClass(cxxRecordDecl(isExpansionInSystemHeader())),
          hasAnyName("fold", "verify", "verifyRegions", "verifySymbolUses", "parse", "print",
                     "canonicalize", "getCanonicalizationPatterns", "inferResultRanges",
                     "getEffects", "getSpeculatability", "getSuccessorRegions",
                     "getSuccessorInputs", "getRegionInvocationBounds", "getCrashCause",
                     "initialize", "materializeConstant", "verifyOperationAttribute",
                     "verifyRegionArgAttribute", "parseType", "printType", "parseAttribute",
                     "printAttribute", "getEntrySuccessorOperands",
                     "getMutableSuccessorOperands", "areTypesCompatible",
                     "inferReturnTypes")))).bind("fn")
    Diagnostic:
      - BindName: fn
        Message: "every function is noexcept; only the hooks whose declaration TableGen writes are exempt (PIN(tablegen-hooks))"
        Level: Warning
  - Name: expected-ignored
    Query: |
      match cxxOperatorCallExpr(hasOverloadedOperatorName("="),
        hasArgument(0, declRefExpr(to(varDecl(hasName("::std::ignore"))))),
        hasArgument(1, hasType(hasUnqualifiedDesugaredType(recordType(hasDeclaration(
          classTemplateSpecializationDecl(hasName("::std::expected")))))))).bind("e")
    Diagnostic:
      - BindName: e
        Message: "an expected is never discarded, std::ignore included: check it"
        Level: Warning
CheckOptions:
  bugprone-unused-return-value.AllowCastToVoid: 'false'
  bugprone-unused-return-value.CheckedReturnTypes: '^::std::expected$'
...
```

Why each part is as it is (tested on `lint2/t.cc` and on
`Dialect/Ops.cc`, `Dialect/Dialect.cc`, `Ownership/Ops.cc` of the tree):

- **The TableGen exemption is by name, on members of generated classes.**
  ODS writes the declarations of `fold`, `verify` and the other hooks
  without `noexcept`, and a definition must repeat its declaration's
  exception specification ("exception specification in declaration does
  not match previous declaration", `snip/decl.cc`). An exemption of every
  member of a generated class would also exempt the methods we declare
  ourselves in `extraClassDeclaration` (`getTakenRegion`, `getToken`,
  `getFields`, `getCtors`, `getValueType`, `getFieldType`,
  `isBuildableWith`), which *can* be `noexcept`: we write their declaration
  in the `.td`. Measured on `Dialect/Ops.cc`: exempting whole generated
  classes leaves 33 findings, the name list 41. The 8 extra are exactly
  those methods, which the name list correctly keeps.
- **The previous run's exemption did not work.** It matched classes by
  `isExpansionInFileMatching("/build/.*\\.inc$")`; inside a YAML block
  scalar the backslash reaches the regex doubled, and `DataOp::verify` was
  reported (`lint/out`, `Ops.cc:164`). The 804 `noexcept-function` findings
  of the full run below therefore include ~120 hooks.
  `isExpansionInSystemHeader()` is correct because the generated headers
  come in through `-isystem build/.../include`.
- **`expected-ignored`** closes the one hole in `unused-return-value`:
  `std::ignore = f();` is an assignment, so the value counts as used.
  cpp-starter forbids discarding an `expected` "by either spelling"
  (`AGENTS.md:1374-1376`) but enforces it only by review. Tested: the check
  fires on `std::ignore = parse(3);` and on nothing else.
- **`--experimental-custom-checks`.** Custom (clang-query) checks run only
  with this flag in clang-tidy 23 (`clang-tools-extra/clang-tidy/custom/`).
  The lint preset passes it (section 5); record it as
  `PIN(clang-tidy-custom-checks)` (retire: the flag becomes stable).
- **An upstream bug to file.** A custom check that binds an implicit
  declaration (an implicit `ParmVarDecl` has no source location) aborts the
  assertions build of clang-tidy: `Assertion failed: Loc.isValid()`,
  `ClangTidyDiagnosticConsumer.cpp:180` (reproduced with
  `match declaratorDecl(hasType(pointerType()))` on any TU). Every query
  below has `unless(isImplicit())`, which is the workaround; per AGENTS.md
  that needs `upstream/clang-tidy-custom-check-invalid-loc` with the
  reproducer and a `tests/upstream/` check.

## 3. `src/.clang-tidy`: the dialect profile

cpp-starter's rules for `src/` (`AGENTS.md:365-383`) at the highest rung
clang-tidy can reach. The three files of sections 2-4 were extracted from
this document into a scratch tree (`scratchpad/research/cpp-modern/zones/`)
and run on a fixture per zone: every custom check fires on its line and on
nothing else, the glue's lambda exemption keeps the lambda handed to an
MLIR-style template and reports the other, and `misc-use-internal-linkage`
leaves module-linkage functions of a partition alone (tested on
`zones/src/part.cc`). `--verify-config` knows every listed check (it does
not know custom checks, which run only with the flag).

```yaml
---
InheritParentConfig: true
# Dialect code: every rule of cpp-starter that an AST check can hold, plus
# the project's (noexcept, variants over tags, expected over bool+errs).
Checks: >
  bugprone-*,
  -bugprone-easily-swappable-parameters,
  cppcoreguidelines-avoid-goto,
  cppcoreguidelines-no-malloc,
  cppcoreguidelines-pro-type-const-cast,
  cppcoreguidelines-pro-type-cstyle-cast,
  cppcoreguidelines-pro-type-reinterpret-cast,
  cppcoreguidelines-pro-type-static-cast-downcast,
  cppcoreguidelines-pro-type-union-access,
  cppcoreguidelines-pro-type-vararg,
  cppcoreguidelines-special-member-functions,
  llvm-prefer-isa-or-dyn-cast-in-conditionals,
  llvm-redundant-casting,
  llvm-type-switch-case-types,
  llvm-use-new-mlir-op-builder,
  misc-redundant-expression,
  misc-unused-parameters,
  misc-use-anonymous-namespace,
  misc-use-internal-linkage,
  modernize-avoid-bind,
  modernize-avoid-c-arrays,
  modernize-type-traits,
  modernize-use-constraints,
  modernize-use-designated-initializers,
  modernize-use-integer-sign-comparison,
  modernize-use-ranges,
  modernize-use-starts-ends-with,
  modernize-use-std-bit,
  modernize-use-std-format,
  modernize-use-std-print,
  modernize-use-trailing-return-type,
  modernize-use-using,
  readability-avoid-nested-conditional-operator,
  readability-container-contains,
  readability-identifier-naming,
  readability-use-std-min-max,
  custom-*
CustomChecks:
  - Name: noexcept-lambda
    Query: |
      match cxxMethodDecl(hasOverloadedOperatorName("()"), ofClass(cxxRecordDecl(isLambda())),
        unless(isNoThrow())).bind("l")
    Diagnostic:
      - BindName: l
        Message: "a lambda is noexcept; hand MLIR a callable through support::walk or support::type_switch (PIN(llvm-function-traits-noexcept))"
        Level: Warning
  - Name: no-own-inheritance
    Query: |
      match cxxRecordDecl(isDefinition(), unless(isLambda()), unless(isImplicit()),
        hasDirectBase(cxxBaseSpecifier(hasType(cxxRecordDecl(unless(isExpansionInSystemHeader())))))).bind("c")
    Diagnostic:
      - BindName: c
        Message: "no inheritance between project types: a closed set is a std::variant, an open one a concept"
        Level: Warning
  - Name: no-mlir-inheritance
    Query: |
      match cxxRecordDecl(isDefinition(), unless(isLambda()), unless(isImplicit()),
        hasDirectBase(cxxBaseSpecifier(hasType(cxxRecordDecl(isExpansionInSystemHeader()))))).bind("c")
    Diagnostic:
      - BindName: c
        Message: "inheriting an MLIR base is glue: it lives in foreign/idr (PIN(mlir-cxx-api))"
        Level: Warning
  - Name: no-std-function
    Query: |
      match typeLoc(loc(qualType(hasDeclaration(namedDecl(hasName("::std::function")))))).bind("t")
    Diagnostic:
      - BindName: t
        Message: "std::function: a constrained template, or llvm::function_ref at an MLIR boundary (PIN(libcxx-no-function-ref))"
        Level: Warning
  - Name: no-function-ref
    Query: |
      match parmVarDecl(unless(isImplicit()),
        hasType(qualType(hasDeclaration(namedDecl(hasName("::llvm::function_ref")))))).bind("p")
    Diagnostic:
      - BindName: p
        Message: "our functions take a constrained callable (std::invocable, std::predicate), not function_ref"
        Level: Warning
  - Name: no-shared-ptr
    Query: |
      match typeLoc(loc(qualType(hasDeclaration(namedDecl(hasAnyName("::std::shared_ptr", "::std::weak_ptr",
        "::std::enable_shared_from_this")))))).bind("t")
    Diagnostic:
      - BindName: t
        Message: "shared ownership is forbidden: redesign the ownership graph"
        Level: Warning
  - Name: no-new-delete
    Query: |
      match expr(anyOf(cxxNewExpr(), cxxDeleteExpr()), unless(isExpansionInSystemHeader())).bind("e")
    Diagnostic:
      - BindName: e
        Message: "new/delete: a value, a container, support::Box or std::make_unique"
        Level: Warning
  - Name: no-default-argument
    Query: |
      match parmVarDecl(hasDefaultArgument(), unless(isImplicit()), unless(isExpansionInSystemHeader())).bind("p")
    Diagnostic:
      - BindName: p
        Message: "default arguments are forbidden: an options aggregate"
        Level: Warning
  - Name: no-function-local-static
    Query: |
      match varDecl(isStaticLocal(), unless(isConstexpr()), unless(isExpansionInSystemHeader())).bind("v")
    Diagnostic:
      - BindName: v
        Message: "function-local statics are forbidden"
        Level: Warning
  - Name: no-mutable-global
    Query: |
      match varDecl(hasGlobalStorage(), unless(isStaticLocal()), unless(hasType(isConstQualified())),
        unless(isConstexpr()), unless(parmVarDecl()), unless(isExpansionInSystemHeader())).bind("v")
    Diagnostic:
      - BindName: v
        Message: "non-const globals are forbidden: pass state explicitly"
        Level: Warning
  - Name: bool-parameter
    Query: |
      match functionDecl(unless(isExpansionInSystemHeader()), unless(isImplicit()),
        unless(cxxMethodDecl(isOverride())),
        hasAnyParameter(parmVarDecl(hasType(booleanType())).bind("p")))
    Diagnostic:
      - BindName: p
        Message: "a bool parameter selects behaviour: an enum class or a variant"
        Level: Warning
  - Name: switch-default
    Query: |
      match switchStmt(hasCondition(ignoringParenImpCasts(hasType(hasUnqualifiedDesugaredType(enumType())))),
        has(compoundStmt(has(defaultStmt())))).bind("s")
    Diagnostic:
      - BindName: s
        Message: "a switch over an enum has no default, so -Wswitch proves it exhaustive"
        Level: Warning
  - Name: own-signature-pointer
    Query: |
      match functionDecl(unless(isImplicit()), unless(isExpansionInSystemHeader()),
        unless(cxxMethodDecl(isOverride())), unless(cxxMethodDecl(ofClass(cxxRecordDecl(isLambda())))),
        anyOf(returns(pointerType()), hasAnyParameter(parmVarDecl(hasType(pointerType()))))).bind("f")
    Diagnostic:
      - BindName: f
        Message: "our signatures take T& or std::optional<T&>, and return values or std::optional<T&>, never a pointer"
        Level: Warning
  - Name: void-cast
    Query: |
      match cStyleCastExpr(hasDestinationType(voidType())).bind("c")
    Diagnostic:
      - BindName: c
        Message: "(void) is retired: std::ignore = for an advisory value, auto _ = for a scoped one"
        Level: Warning
CheckOptions:
  readability-identifier-naming.FunctionCase: lower_case
  readability-identifier-naming.MethodCase: lower_case
  readability-identifier-naming.VariableCase: lower_case
  readability-identifier-naming.ParameterCase: lower_case
  readability-identifier-naming.MemberCase: lower_case
  readability-identifier-naming.ConstexprVariableCase: lower_case
  readability-identifier-naming.StructCase: CamelCase
  readability-identifier-naming.ClassCase: CamelCase
  readability-identifier-naming.EnumCase: CamelCase
  readability-identifier-naming.EnumConstantCase: CamelCase
  readability-identifier-naming.ConceptCase: CamelCase
  readability-identifier-naming.TypeAliasCase: CamelCase
  readability-identifier-naming.NamespaceCase: lower_case
  modernize-use-trailing-return-type.TransformLambdas: none
...
```

Notes on the choices:

- **Naming is not forced by MLIR, so it follows cpp-starter.** The previous
  draft proposed a `mlir-naming` PIN (camelCase). Tested: with
  `readability-identifier-naming` set to cpp-starter's `lower_case`, an
  override of an MLIR virtual (`runOnOperation() override`) and the
  out-of-line definition of a generated member (`int Op::verify()`) are
  **not** reported; only our own declarations are (`lint2/naming.cc`). So
  our names are `snake_case` and MLIR's stay `camelCase`, with the check
  holding the line exactly at the boundary, and the check's fix-its do the
  rename. The mixed casing is informative: a camelCase name is MLIR's.
- **`noexcept-lambda` has no exemption in `src/`.** A lambda that MLIR
  deduces through `llvm::function_traits` (`Operation::walk`,
  `llvm::TypeSwitch`, `Attribute::walk`, `TypeConverter::addConversion`:
  `Operation.h`, `AttrTypeSubElements.h:78,193,288`,
  `DialectConversion.h:172-252`) cannot be `noexcept`: `function_traits`
  has no specialization for a `noexcept` call operator
  (`llvm/ADT/STLExtras.h:66-104`; reduced to four lines of LLVM,
  `snip/ft.cc`, fails in C++17 too). `src/` code calls
  `support::walk<Op>(root, f)` and `support::type_switch`, which take a
  `noexcept` callable and hand MLIR the one non-`noexcept` lambda (tested,
  `snip/support.cc`). The `support` partition is glue for this check only:
  it lives in `foreign/idr/support/`, where the glue profile exempts
  lambdas passed to system-header functions (section 4).
- **`no-mlir-inheritance` makes the dialect/glue split mechanical.** Every
  class deriving an MLIR base (a pass, a pattern, an interface model, an
  analysis state, an action) is glue. In `src/` the check has no
  exemption, so those classes cannot drift back.
- **What the checks cannot hold, review does** (cpp-starter's rung 4):
  variant-over-tag, `expected`-over-bool, comment forms. The worklist is
  `cpp-modern-audit.md`.
- `modernize-use-trailing-return-type` fixes cpp-starter's `auto f() -> T`
  mechanically. `TransformLambdas: none` keeps lambdas short.

## 4. `foreign/idr/.clang-tidy`: glue

```yaml
---
InheritParentConfig: true
# Glue: what TableGen and MLIR's base classes force. Inheriting MLIR's
# bases, its pointer handles and the hooks it declares are the reason this
# zone exists (PIN(mlir-cxx-api)); everything else is still checked.
Checks: >
  bugprone-*,
  -bugprone-easily-swappable-parameters,
  llvm-prefer-isa-or-dyn-cast-in-conditionals,
  llvm-use-new-mlir-op-builder,
  modernize-use-trailing-return-type,
  readability-identifier-naming,
  custom-*
CustomChecks:
  - Name: noexcept-lambda
    Query: |
      match cxxMethodDecl(hasOverloadedOperatorName("()"), ofClass(cxxRecordDecl(isLambda())), unless(isNoThrow()),
        unless(hasAncestor(callExpr(callee(functionDecl(isExpansionInSystemHeader())))))).bind("l")
    Diagnostic:
      - BindName: l
        Message: "a lambda is noexcept unless LLVM/MLIR deduces it through function_traits (PIN(llvm-function-traits-noexcept))"
        Level: Warning
  - Name: no-own-inheritance
    Query: |
      match cxxRecordDecl(isDefinition(), unless(isLambda()), unless(isImplicit()),
        hasDirectBase(cxxBaseSpecifier(hasType(cxxRecordDecl(unless(isExpansionInSystemHeader())))))).bind("c")
    Diagnostic:
      - BindName: c
        Message: "glue derives MLIR's bases only, never a project type"
        Level: Warning
CheckOptions:
  readability-identifier-naming.FunctionCase: lower_case
  readability-identifier-naming.VariableCase: lower_case
  readability-identifier-naming.ParameterCase: lower_case
...
```

The glue keeps the root's `noexcept-function`, so a glue function that is
not a TableGen hook is `noexcept` like any other. The rule "a hook forwards
to a module function in one statement" stays review: a trial check on empty
bodies (`statementCountIs(0)`) also fired on empty overrides and empty
lambdas handed to MLIR, so it is not proposed.

## 5. `unsafe/.clang-tidy` and `runtime/.clang-tidy`

`unsafe/` inherits the root unchanged: that is cpp-starter's quarantine
profile, which "does not flag the raw pointers, ABI casts, or C APIs that
define the reason those zones exist" (`AGENTS.md:346-352`), plus
`noexcept-function` and `expected-ignored`.

`runtime/` needs no file of its own: the root's `noexcept-function`
already reports an `extern "C"` definition without `noexcept` (tested,
`zones/runtime/fixture.cc`: `extern "C" int idris_rt_thing(int)` is
reported, the `noexcept` one is not).

`idris_rt.h` stays C (`link_check.c` includes it as C): its
`IDRIS_RT_NORETURN` pattern (`idris_rt.h:18-23`) gains
`#define IDRIS_RT_NOEXCEPT noexcept` under `__cplusplus` and nothing in C.
The runtime today is linted by nothing but the root's four families; with
this file it gets the quarantine profile like `unsafe/`.

## 6. The compiler rung

Clang warnings that hold a rule better than any lint (tested: each flag
exists in clang 23.1.2 and compiles clean on an empty unit under `-Werror`;
`-Wunsafe-buffer-usage` also tested on a snippet):

| Flag | Rule it holds | Where |
|---|---|---|
| `-Wunsafe-buffer-usage` | no pointer arithmetic or raw indexing (`AGENTS.md:761-780, 1272-1299`) | `src/` only; not `unsafe/`, `runtime/`, glue |
| `-Wcovered-switch-default` | no `default` in a covered switch (with `-Wswitch` from `-Wall`) | everywhere |
| `-Wshadow-all` | cpp-starter's `-Wshadow`, and the field and lambda cases | everywhere |
| `-Wcomma`, `-Wextra-semi`, `-Wmissing-noreturn`, `-Wunreachable-code-aggressive` | clang's counterparts of cpp-starter's GCC-only warnings (`CMakeLists.txt:140`) | everywhere |

They go into `idris_mlir_warnings` (`CMakeLists.txt:97-112`), except
`-Wunsafe-buffer-usage`, which goes on the `src/` target. While areas are
converted, an unconverted unit gets
`set_source_files_properties(... COMPILE_OPTIONS -Wno-unsafe-buffer-usage)`
with `PIN(unconverted-areas)`, cpp-starter's own scoped form
(`src/CMakeLists.txt:17-21`); the PIN dies with the last area.

## 7. CMake, presets and tests

- **The lint preset** (today `CMakePresets.json:48-56`) gains the flag:

  ```json
  "CMAKE_CXX_CLANG_TIDY": "${sourceDir}/.toolchain/llvm-musl/bin/clang-tidy;--warnings-as-errors=*;--experimental-custom-checks"
  ```

  and `make check` builds it (`cmake --build --preset lint`). cpp-starter
  runs lint as a build (`CMakePresets.json:48-59`).
- **`__cmake_cxx26`** gets cpp-starter's
  `set_property(TARGET __cmake_cxx26 PROPERTY CXX_EXTENSIONS OFF)`
  (`CMakeLists.txt:190-191`) next to the existing tidy line
  (`idris-mlir CMakeLists.txt:38-42`). Without it, `import std` fails: the
  `std.pcm` of `build/dev` is `gnu++26` and every importer is `c++26`
  (tested: "GNU extensions was enabled in precompiled file").
- **`CXX_MODULE_STD ON`** on every target: delete
  `foreign/idr/CMakeLists.txt:159-164` and `runtime/CMakeLists.txt:106`
  (the runtime can import std: it is C++ with a C ABI).
- **`tests/compile_fail/`**, cpp-starter's form
  (`tests/compile_fail/CMakeLists.txt:1-20`): an `EXCLUDE_FROM_ALL` target
  that must fail with a pinned diagnostic. Its fixtures pin the
  compiler-rung rules:
  - `exception.cc`: a `throw` fails with "cannot use 'throw' with
    exceptions disabled";
  - `switch_default.cc`: a `default` in a covered enum switch fails with
    `-Wcovered-switch-default`;
  - `pointer_arith.cc`: `p[i]` in `src/` fails with
    `-Wunsafe-buffer-usage`.
- **`tests/lint_fail/`**, the same form for the lint rung (new; cpp-starter
  has only the compiler form): one fixture per custom check, built by the
  lint preset, whose test passes when clang-tidy reports the check's name.
  `discarded_expected.cc` pins `bugprone-unused-return-value`,
  `ignored_expected.cc` pins `custom-expected-ignored`,
  `not_noexcept.cc` pins `custom-noexcept-function`,
  `inherits.cc` pins `custom-no-own-inheritance`.
- **`tests/conformance/`**, cpp-starter's `tests/conformance.test.cc`
  form: `consteval` functions checked by `static_assert`, one per C++26
  feature the mandate relies on (`optional<T&>`, the monadic `expected`
  chain, member `visit`, deducing `this`, pack indexing, `template for`,
  `ranges::to`, `saturating_add`). Negative pins cannot be
  `static_assert`s of absence without the preprocessor, so the PINs that
  wait for libc++ (`std::indirect`, `std::function_ref`) are re-tested by
  the PINS.md ritual, as cpp-starter's are.
- **`.clang-format`**: cpp-starter's, verbatim (`.clang-format:1-35`: tabs,
  140 columns, east `const`, `QualifierAlignment: Right`). Formatting is
  not forced by MLIR; the generated `.inc` files are never formatted by us.
- **The four grep spec tests go** (`tests/spec/cpp-starter`, `zones`,
  `build-preset`, `configure-gate`): they grep build files for their own
  contents, and cpp-starter forbids repository grep checkers by decision
  (`AGENTS.md:1701-1704`). The configure gate, the presets and the lint
  build are the mechanisms. readability.md reached the same verdict from
  the other side ("Ceremony. Cut.").

## 8. What the gates find in the tree today

A full run of the previous draft's configuration over all 102 units of
`build/dev` (`lint/run.sh`, 102/102 exit 0), deduplicated by
file:line:check. The dropped blanket `[[nodiscard]]` rows
(`custom-nodiscard` 585, `modernize-use-nodiscard` 24) are left out. The
`noexcept-function` counts include about 120 TableGen hooks, which the
corrected exemption (section 2) removes.

| Area | noexcept-function | noexcept-lambda | trailing-return | no-own-inheritance | bool-parameter | mutable-global | signed-bitwise | unchecked-optional | all |
|---|---|---|---|---|---|---|---|---|---|
| Canonicalize | 4 | 1 | 3 | 0 | 0 | 0 | 0 | 0 | 9 |
| Dialect | 136 | 19 | 150 | 0 | 1 | 0 | 1 | 0 | 313 |
| Eval | 28 | 8 | 38 | 0 | 0 | 2 | 12 | 0 | 110 |
| Expect | 20 | 2 | 44 | 0 | 0 | 0 | 0 | 0 | 68 |
| Facts | 26 | 7 | 57 | 0 | 0 | 0 | 0 | 0 | 91 |
| Fold | 47 | 11 | 50 | 0 | 1 | 0 | 0 | 0 | 110 |
| Inline | 4 | 2 | 8 | 0 | 0 | 0 | 0 | 0 | 16 |
| Lower | 104 | 10 | 126 | 20 | 2 | 0 | 3 | 1 | 281 |
| Ownership | 81 | 6 | 83 | 0 | 2 | 0 | 0 | 5 | 188 |
| Passes | 98 | 11 | 95 | 0 | 1 | 0 | 0 | 0 | 229 |
| Registration | 3 | 2 | 2 | 0 | 0 | 0 | 0 | 0 | 9 |
| Specialize | 61 | 19 | 112 | 1 | 1 | 0 | 2 | 6 | 226 |
| Stack | 13 | 3 | 33 | 0 | 0 | 0 | 0 | 0 | 55 |
| Support | 15 | 1 | 5 | 0 | 0 | 0 | 0 | 0 | 27 |
| include/idr | 11 | 2 | 23 | 0 | 0 | 0 | 0 | 0 | 42 |
| runtime | 141 | 0 | 161 | 0 | 3 | 17 | 40 | 0 | 410 |
| tools | 12 | 3 | 21 | 0 | 0 | 13 | 4 | 1 | 61 |

Other findings, whole tree: `portability-avoid-pragma-once` 26 (disabled
in the root: headers go with the modules), `modernize-use-designated-initializers`
39, `cppcoreguidelines-pro-type-reinterpret-cast` 19 (runtime and `Eval`,
which move to quarantine, plus `Passes/Simplify.cc:140,143`, which become
`std::bit_cast`), `modernize-avoid-c-arrays` 17,
`readability-avoid-nested-conditional-operator` 14,
`readability-container-contains` 7, `performance-enum-size` 5,
`bugprone-unused-return-value` 5, `custom-no-default-argument` 4,
`custom-no-function-local-static` 3, `custom-no-std-function` 2,
`custom-no-shared-ptr` 1, `custom-no-new-delete` 1. The
`unchecked-optional-access` findings are the cases the audit turns into
variants (a checked `optional` read is a `visit`).

A count the full run did not have, measured by grep: 246 `Operation *` in
our signatures and locals (`own-signature-pointer` holds only the
signatures), 23 `Region *`, 17 `Block *`, 25 `function_ref`.
