# cpp-modern (a): what bjornpagen/cpp-starter is, pattern by pattern

Side file of `cpp-modern.md`. Every claim cites
`/home/user/bjornpagen/cpp-starter` (called cpp-starter) by file:line. The
last section lists what idris-mlir has already adopted and what it has not.

cpp-starter is small: 1910 lines of `AGENTS.md`, 233 lines of `PINS.md`, and
about 3.1k lines of C++ spread over `src/` (dialect), `unsafe/` and
`foreign/` (quarantine), `tests/` and `examples/`. The C++ is a
demonstration of the rules, and the rules are the product.

---

## 1. The prime directive: one concept, one mechanism

`AGENTS.md:28-60` is a table of concepts, each with one blessed mechanism
and the alternatives it forbids. The rows that matter for idris-mlir:

| Concept | Blessed | Forbidden | AGENTS.md |
|---|---|---|---|
| Generic polymorphism | concepts and templates | inheritance, virtual, CRTP, tag dispatch | 35 |
| Closed polymorphism | `std::variant` and visitation | class hierarchies, manual tagged unions | 36 |
| Synchronous failure | `std::expected<T, E>` | exceptions, error code plus out-parameter | 39 |
| Optionality | `std::optional<T>` | null sentinels, magic values | 40 |
| Dynamic ownership | `std::unique_ptr` when a value cannot do | raw owners, `shared_ptr`, `weak_ptr` | 46 |
| Required borrow | `T&`, `T const&` | raw pointers | 47 |
| Optional borrow | `std::optional<T&>` | nullable raw pointers, `optional<reference_wrapper>` | 48 |
| Finite atoms | `enum class` | integer constants, strings as enums | 51 |
| Product data | public `struct` | getter/setter shells | 52 |
| Project dependencies | named modules | project headers, header units | 54 |
| Formatting | `std::format`, `std::print` | iostreams, printf | 55 |
| Configuration | build graph, typed values | project preprocessor conditionals | 56 |

"If the blessed mechanism cannot express a required property, stop and
identify the missing primitive before introducing a second way"
(`AGENTS.md:59-60`). The closing rule is the same in the negative: "If the
modern static mechanism can express the design, the older mechanism is
illegal" (`AGENTS.md:1907-1910`).

## 2. Data modelling

- **Sums are variants.** "Closed alternatives use
  `std::variant<Insert, Delete, Commit>`. Never use inheritance hierarchies,
  C unions, manual discriminator + payload structs, boolean matrices
  encoding states" (`AGENTS.md:612-626`). The state of a connection slot is
  one: `using SlotState = std::variant<std::monostate, Reading, Writing>`
  (`unsafe/net.internal.h:124-143`), each alternative carrying exactly its
  own data (`Reading{received, deadline}`, `Writing{size, sent, deadline}`).
- **The eliminator is a visitor struct**, one `operator()` per
  alternative, and "not an `overload{...}` set built by variadic
  inheritance, which this document forbids" (`AGENTS.md:1833-1854`). The
  quarantine code itself uses `std::get_if`/`holds_alternative` where it
  checks one alternative (`unsafe/net.loop.cc:88,133,168,258-284,332-336`).
- **Optional is absence only.** "Use `std::optional<T>` only for genuine
  absence. Do not encode absence as zero, `-1`, empty string, null raw
  pointer, magic enum case unless that case is semantically real"
  (`AGENTS.md:627-637`). A value whose "absent" case means something else is
  a variant with a named alternative.
- **Finite vocabularies are `enum class`** (`AGENTS.md:639-644`), switched
  on exhaustively with no `default`, so that `-Wswitch` under `-Werror`
  fails the build on a new enumerator (`AGENTS.md:1400-1403`;
  `src/http.cc:22-32`).
- **Products are public aggregates** with designated initialization
  (`AGENTS.md:597-610`; `NetError{.stage = ..., .code = ...}`,
  `unsafe/net.cc:95-97`). `class` is kept for an invariant or a resource
  (`AGENTS.md:648-672`).
- **Boolean parameters that select behaviour** become an enum, a variant or
  an options aggregate, and a state machine is never several booleans
  (`AGENTS.md:1497-1505`). Options aggregates replace default arguments
  (`AGENTS.md:1325-1348`).
- **No exact-type dispatch** (`if constexpr (std::same_as<T, Foo>)`) and no
  exact-type allowlists as semantics (`AGENTS.md:570-591, 1173-1191`); state
  the structural property as a concept instead.

## 3. Failure

- **One mechanism per failure class** (`AGENTS.md:721-742, 1617-1633`):
  `std::expected` for recoverable failure, a C++26 contract for impossible
  programmer state, `static_assert` for compile-time law, termination for
  unrecoverable process failure. "No other assertion or invariant primitive
  exists."
- **Errors are decision surfaces** (`AGENTS.md:1382-1411`). An error type is
  a product with a kind enum, and answers the caller's decision,
  `is_transient()`, by an exhaustive `switch`: `GreetError`
  (`src/core.cc:7-22`), `HttpError` (`src/http.cc:11-35`), `NetError`
  (`unsafe/net.cc:44-67`), `ExecError` (`foreign/exec.cc:33-42`). "Messages are
  rendering, never input: deciding behavior by matching an error's text is
  forbidden" (`AGENTS.md:1408-1410`).
- **Failure is transparent**: on the `unexpected` path every caller-visible
  output is as the caller left it (`AGENTS.md:1412-1423`).
- **Monadic composition** is the canonical form: `parse(input).and_then(validate)
  .and_then(execute)` (`AGENTS.md:1819-1831`), and `main` itself is a
  `.transform(...).value_or(1)` (`src/main.cc:4-11`).
- **Quarantine errors are narrow ABI values lifted once.** The backend
  returns `std::expected<..., WireError>` with
  `WireError = std::array<std::int32_t, 2>` (`unsafe/net.internal.h:30`),
  and one `lift_error` makes the dialect's typed error
  (`unsafe/net.cc:95-97`).
- **Contracts without contracts.** Clang does not parse `contract_assert`,
  so the Clang-readable boundary has exactly one fail-stop helper,
  `invariant(bool) noexcept` calling `std::terminate`
  (`unsafe/net.internal.h:76-81`), registered as `PIN(clang-contracts)`
  (`PINS.md:30-41`), with the instruction "do not proliferate an alternate
  assertion vocabulary into dialect code".

## 4. Return values and discarding

- cpp-starter marks every non-void dialect function `[[nodiscard]]`
  (`AGENTS.md:1350-1380`), and error types at the type level too
  (`export struct [[nodiscard]] GreetError`, `src/core.cc:11`).
  **idris-mlir does not adopt this** (the user's decision); it keeps only
  the lint on a discarded `std::expected` (section 8).
- Discarding has two spellings: `std::ignore = advisory();` destroys at
  once, `auto _ = capability();` holds to scope end; `(void)expr` is
  retired; "an `expected` is never discarded by either spelling"
  (`AGENTS.md:1364-1376`; `unsafe/net.loop.cc:99`, `net.internal.h:117`).

## 5. Ownership, borrowing, mutation

- Values first; `unique_ptr` only for a truly independent lifetime; no raw
  pointer declarations or returns in dialect code; no
  `new`/`delete`/`malloc`/`shared_ptr` (`AGENTS.md:746-780, 1530-1558`).
  The allocation ladder puts `std::inplace_vector` and `std::indirect`
  before `unique_ptr` (`AGENTS.md:1534-1546`).
- Borrows are exactly `T&`, `std::optional<T&>`, `std::span`,
  `std::string_view` (`AGENTS.md:782-797`); owning structs hold no borrows
  (`AGENTS.md:807-809`).
- Resource classes: one RAII owner, non-copyable, `noexcept` moves
  (`AGENTS.md:1509-1527`). The model is `Fd`
  (`unsafe/net.internal.h:83-122`): `explicit Fd(int) noexcept`, `noexcept`
  move constructor and assignment, deleted copies, a destructor that
  closes, `std::ignore = ::close(...)`. A C resource whose type is
  incomplete is owned by `std::unique_ptr<Server, ServerDeleter>` with a
  `noexcept` deleter (`unsafe/net.cc:10-16`).
- No non-const globals, no function-local statics, no `thread_local`;
  "pass dependencies, state, clocks, randomness, and schedulers explicitly"
  (`AGENTS.md:871-902`).
- No `std::function`; `std::function_ref` for an erased non-owning
  callable; templates and concepts otherwise; no `std::bind`
  (`AGENTS.md:1215-1227`).
- No C casts, `reinterpret_cast`, `const_cast`, `dynamic_cast` or static
  downcasts in dialect code; `std::bit_cast` and checked conversions
  instead; pointer/integer conversion only in quarantine
  (`AGENTS.md:1231-1250`). The one conversion helper is `represent_as`
  (`src/handle.cc:35-42`).
- No C arrays, varargs, unions, printf, pointer-plus-length APIs
  (`AGENTS.md:1272-1299`).

## 6. `noexcept`

cpp-starter does not require `noexcept` on dialect functions; its `src/`
has none. Its quarantine code, however, is `noexcept` throughout: every
function of the reactor (`unsafe/net.loop.cc:8-468`, 20 definitions), every
backend declaration (`unsafe/net.internal.h:193-204`,
`unsafe/net.cc:13-37`), the handler's function-pointer type
(`using RawHandler = ... (*)(std::string_view, std::span<char>) noexcept`,
`unsafe/net.internal.h:31`), and the lambda handed across that boundary
(`unsafe/net.cc:141`). Resource moves are `noexcept`
(`AGENTS.md:1522-1523`). The spelling is `auto f(args) noexcept -> T`.
idris-mlir's mandate extends that quarantine discipline to all code.

## 7. Modules, zones and the foreign boundary

- **Zones** (`AGENTS.md:361-411`). `src/`, `tests/`, `examples/` are dialect
  code: "No preprocessor. No headers. No unsafe primitives. No lint
  suppression." `foreign/` and `unsafe/` are quarantine: OS and vendor
  headers, syscalls, ABI casts, and nothing else; quarantine "relaxes
  representation rules, not ownership rules". Each zone has a README of its
  rules (`unsafe/README.md`, `foreign/README.md`).
- **One module per component, internals as partitions**
  (`AGENTS.md:415-446`). The primary interface only `export import`s its
  partitions (`src/starter.cc:1-8`). "No dotted module names anywhere"
  (441-443). "One partition per concern, in one file (roughly 50-300 lines).
  Do not split a partition into interface and implementation units; split
  only on demonstrated rebuild pain" (444-446). One CMake target lists the
  primary interface and every partition in one `FILE_SET CXX_MODULES`
  (`AGENTS.md:168-194`; `src/CMakeLists.txt:1-16`).
- **`.cc` is the only extension**; interface-ness is declared by the build;
  `.cppm` and `.h` are retired or forbidden (`AGENTS.md:457-491`). Header
  units are forbidden (484-489).
- **Every preprocessing directive is forbidden in dialect code**
  (`AGENTS.md:493-518`); platform and feature selection belong in the build
  graph.
- **`import std` everywhere, set once centrally** (`AGENTS.md:196-201`;
  `CMakeLists.txt:83-86`).
- **The foreign boundary pattern.** A dependency that cannot enter a
  module (stdexec: GCC crashes when a module unit includes it) is used by
  one plain TU, and a module partition declares the functions it defines
  in an `extern "C++"` block: a narrow ABI of concrete functions and
  owning standard values (`foreign/exec.cc:1-30`,
  `foreign/exec.backend.cc:1-60`, `unsafe/net.cc:1-40`). The plain TU is
  built with `CXX_SCAN_FOR_MODULES OFF` and `CXX_MODULE_STD OFF`
  (`foreign/CMakeLists.txt:16-27`, `unsafe/CMakeLists.txt:14-23`). "Exactly
  ONE vendor swap boundary" and "nothing outside that list escapes"
  (`AGENTS.md:959-988`).

## 8. The lint and build innovations

1. **The enforcement ladder** (`AGENTS.md:1690-1721`): compiler flags, then
   the build graph, then clang-tidy AST checks, then review. "Every rule
   aspires upward: a review convention is a rule still waiting for its
   mechanism ... When one can, it must — and the prose version is deleted
   the same day." This is also "the adoption filter for outside wisdom".
2. **No grep checkers, by decision** (`AGENTS.md:1701-1704`): whatever is
   visible only in raw text (directives, suppressions, comments,
   extensions) is review convention, deliberately not machine-enforced.
3. **A quarantine clang-tidy profile** (`.clang-tidy:1-51`) that "checks
   boundary code for real correctness, lifetime, concurrency, portability,
   and performance defects; it does not flag the raw pointers, ABI casts,
   or C APIs that define the reason those zones exist"
   (`AGENTS.md:346-352`). It enables a hand-picked `bugprone-*` subset,
   `clang-analyzer-*`, `concurrency-*`, `performance-*`, `portability-*`,
   `misc-static-assert`, `misc-unused-using-decls`, `modernize-use-nullptr`
   and `readability-container-size-empty` (`.clang-tidy:10-40`).
   `WarningsAsErrors: '*'` (42). The header filter excludes build trees and
   standard libraries (43-45). "When Clang can parse the
   reflection-bearing module graph, add a separate dialect profile and
   target rather than weakening or conflating either rule set" (352).
4. **`bugprone-unused-return-value` configured for the error algebra**:
   `AllowCastToVoid: 'false'` and
   `CheckedReturnTypes: '^::std::error_code$;...;^::std::expected$;^::std::optional$'`
   (`.clang-tidy:48-50`).
5. **No suppressions in dialect code**: no `NOLINT*`, no diagnostic pragmas
   (`AGENTS.md:354-357, 1661-1686`). A rule that cannot apply means the
   design changes, the code moves to `unsafe/`/`foreign/`, or the rule
   changes centrally.
6. **Carve-outs are target-scoped and registered.** The two stdexec false
   positives are disabled only on the vendor target
   (`foreign/CMakeLists.txt:29-35`) and recorded as
   `PIN(stdexec-tooling-carveouts)` (`PINS.md:43-57`). A scoped warning
   exception is a `set_source_files_properties` on the named files with its
   PIN (`src/CMakeLists.txt:17-21`, `tests/CMakeLists.txt:141-148`).
7. **Compile-fail tests with a pinned diagnostic**: an `EXCLUDE_FROM_ALL`
   target that must fail to build, run by ctest with
   `PASS_REGULAR_EXPRESSION` naming the diagnostic
   (`tests/compile_fail/CMakeLists.txt:1-20`,
   `tests/compile_fail/discarded_expected.cc:1-7`). "Starting to compile, or
   losing its pinned diagnostic, fails the suite."
8. **A toolchain conformance test**: `consteval` functions checked by
   `static_assert`, one per library feature the profile relies on
   (`tests/conformance.test.cc:1-60`: `optional<T&>` writes through,
   `inplace_vector`, the monadic `expected` chain, reflection). A toolchain
   bump that breaks a relied-on feature fails the build.
9. **The configure gate pins every tool**: the generator, the Ninja and
   CMake series, the compiler and the clang-tidy version, all in the
   top-level `CMakeLists.txt` and nowhere else (`CMakeLists.txt:1-81`;
   `AGENTS.md:66-74, 343-344`).
10. **One language-profile interface target** holds warnings and
    hardening (`CMakeLists.txt:100-164`; `AGENTS.md:236-265`); module-ABI
    flags are global so the std BMI matches every importer
    (`CMakeLists.txt:88-90`), and the synthesized `__cmake_cxx26` target
    gets `CXX_EXTENSIONS OFF` and no clang-tidy (`CMakeLists.txt:190-195`).
11. **Presets are the interface**: `dev`, `release`, `asan-ubsan`, `lint`,
    each with its own build directory; `lint` sets `CMAKE_CXX_CLANG_TIDY`,
    so lint runs as a build (`CMakePresets.json:1-84`; `AGENTS.md:213-234`).
12. **PINS.md as a tombstone registry** (`PINS.md:1-14`): one entry per
    pinned workaround with symptom, sites, workaround, retire condition and
    upstream link; `/* PIN(name): one line */` at each site
    (`src/http.cc:46`, `CMakeLists.txt:25,103,143,166`); on every toolchain
    bump, "read this file top to bottom, re-test every retire condition,
    and delete what upstream fixed".
13. **Three comment forms and no others** (`AGENTS.md:1445-1493`): the
    `/** */` documentation block, `/* PIN(name): ... */`, and
    `/* SAFETY: ... */` in quarantine. `//` does not exist: no banners, no
    `} // namespace`, no narration. Enforcement is review, "by the same
    decision that bans repository grep checks".
14. **The review checklist** (`AGENTS.md:1757-1795`) is the last rung,
    written as questions in priority order ("Can `variant` encode this state
    space? Can `expected` encode this failure?").

## 9. What idris-mlir has, and what it lacks

| cpp-starter item | idris-mlir today | Evidence |
|---|---|---|
| Configure gate | adopted, reads `toolchain.lock.json` | `CMakeLists.txt:1-31` |
| Language profile target, hardening | adopted | `CMakeLists.txt:111-181` |
| Module-ABI flags global | adopted | `CMakeLists.txt:87-91` |
| `__cmake_cxx26` `CXX_EXTENSIONS OFF` | **missing**; tidy off only | `CMakeLists.txt:38-42`. Measured consequence: `build/dev`'s `std.pcm` is built `gnu++26`, and an importer compiled `-std=c++26` fails with "GNU extensions was enabled in precompiled file ... but is currently disabled". Turning `CXX_MODULE_STD` on needs cpp-starter's line |
| Presets `dev`/`release`/`asan-ubsan`/`lint` | adopted | `CMakePresets.json` |
| Quarantine `.clang-tidy` | 4 families only, no options | `.clang-tidy` (bugprone, analyzer, performance) |
| `unused-return-value` for `expected` | **missing** | same |
| Dialect profile | **missing** | nothing is linted as dialect code |
| Compile-fail tests | **missing** | no `compile_fail` |
| Conformance test | **missing** | none |
| Zones `src/`/`unsafe/` | absent by `PIN(zones-on-demand)` | `PINS.md:52-61` |
| Modules | one area (`idr.facts`), dotted names, `.cppm`, declare-only partitions | `lib/MODULES.md` |
| `import std` | off; a 196-line `std` re-export instead | `foreign/idr/CMakeLists.txt:159-164`, `lib/Mlir.cppm:697-892` |
| Variants, `expected`, `noexcept` | 1 variant, 0 `expected`, 0 `noexcept` | `cpp-modern-audit.md` |
| Comment forms, `.clang-format` | `//` throughout, no `.clang-format` | — |
| Grep checkers | 4 spec tests that grep build files (`cpp-starter`, `zones`, `build-preset`, `configure-gate`) | `tests/spec/*/run`. cpp-starter forbids these by decision (`AGENTS.md:1701-1704`): deleting them brings idris-mlir *closer* to it |
