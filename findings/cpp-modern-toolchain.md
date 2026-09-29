# cpp-modern (e): what the pinned clang and libc++ implement

Side file of `cpp-modern.md`. The pinned compiler is
`.toolchain/llvm-musl/bin/clang++`, clang 23.1.2 (llvm-project
85ac5602624), with libc++ from the same tree, target
`x86_64-unknown-linux-musl`. Every row below is a snippet in
`scratchpad/research/cpp-modern/snip/`, compiled with
`-std=c++26 -fno-exceptions -fno-rtti -O1` and run; "works" means it
compiled and exited 0 (re-run for this file: `snip/rerun/`).

## 1. Language level

- `-std=c++26` and `-std=c++2c` give `__cplusplus` 202400; `-std=c++2d`
  gives 202700 and enables nothing more (no clang feature is gated on the
  C++29 flag but the version macros; libc++ maps every `__cplusplus` above
  202302 to `_LIBCPP_STD_VER 26`, `libcxx/include/__configuration/language.h:33-36`).
  CMake 4.2 knows no `cxx_std_29`. **The mandate is C++26**, which both
  repos already set (`CMAKE_CXX_STANDARD 26`).
- `-fexperimental-library` adds, of what we would use, only `std::optional`
  as a range (`snip/optional_range.cc` fails without it, compiles with it).
  It is a module-ABI flag (it would have to be global, the std BMI too).
  Leave it off.

## 2. What works (to be used)

| Feature | Snippet | Feature macro |
|---|---|---|
| `std::expected`, monadic `and_then`/`or_else`/`transform`/`transform_error` | `expected_monadic`, `expected_void`, `expected_ref_ops`, `expected_swap_eq` | `__cpp_lib_expected` 202211 |
| `std::variant` member `visit`, `visit<R>`, `constexpr` variants | `variant_visit_member`, `variant_ctad_visit_r`, `variant_constexpr` | `__cpp_lib_variant` 202306 |
| `std::optional<T&>`, optional `and_then`/`transform` | `optional_ref2`, `optional_ref_ret`, `optional_and_then` | `__cpp_lib_optional` 202506 |
| deducing `this` | `deducing_this` | `__cpp_explicit_this_parameter` 202110 |
| pack indexing `T...[0]` | `pack_index` | `__cpp_pack_indexing` 202311 |
| structured-binding packs `auto [...xs] = t`, bindings as conditions | `sb_pack`, `sb_condition` | `__cpp_structured_bindings` 202411 |
| expansion statements `template for` | `template_for` | — |
| `_` placeholder variables | `placeholder` | `__cpp_placeholder_variables` 202306 |
| `= delete("reason")` | `delete_reason` | `__cpp_deleted_function` 202403 |
| computed `static_assert` messages | `static_assert_msg` | — |
| concept template parameters | `concept_template_template` | — |
| variadic `friend` | `variadic_friend` | `__cpp_variadic_friend` 202403 |
| `#embed` | `embed` | — |
| `[[indeterminate]]` (erroneous behaviour) | `erroneous` | — |
| `auto(x)`, `if consteval`, `[[assume]]`, `std::unreachable`, `std::to_underlying`, `using enum`, lambda attributes | `auto_decay`, `if_consteval`, `assume`, `unreachable`, `to_underlying`, `enum_using`, `lambda_attrs` | — |
| `constexpr std::string`, `static constexpr` in `constexpr` functions, `constexpr` virtual | `constexpr_string`, `static_constexpr_in_constexpr`, `constexpr_virtual_var` | `__cpp_constexpr` 202406 |
| `std::print`, `std::format`, formatting ranges | `print`, `format_ranges` | `__cpp_lib_print` 202207 |
| `ranges::to`, `views::enumerate`, `zip`, `concat`, `chunk_by`, `ranges::fold_left`, `ranges::contains` | `ranges_to`, `enumerate_zip`, `fold_left`, `contains` | `__cpp_lib_ranges_concat` 202403 and others |
| `std::flat_map`, `std::mdspan`, `std::span::at` | `flat_map`, `std_span_at` | `__cpp_lib_flat_map` 202511, `__cpp_lib_mdspan` 202406 |
| `std::saturating_add` (the C++26 name) | `sat2` | `__cpp_lib_saturation_arithmetic` 202603 |
| `std::bit_cast`, `std::byteswap`, bit operations | `bit_ops` | — |
| libc++ extensive hardening | `hardened_std` | — |

Tested with MLIR linked (`snip/support.cc`, against `libMLIRIR` and
`libMLIRFuncDialect`): `std::expected<int, std::variant<Rejected,
Internal>>` with `and_then`/`transform` and a member `visit` rendering the
error as an MLIR diagnostic; a `noexcept` walk wrapper; `classify<Ts...>`
from an MLIR `Type` into `std::variant<Ts..., Other<Type>>`
(`snip/classify.cc`); `llvm::DenseMap<std::variant<mlir::Type,
mlir::Attribute>, int>` through `llvm/ADT/DenseMapInfoVariant.h` (16 bytes
per key, where a handle is 8); a value-semantic `Box<T>`.

Modules, tested at full scale (`scratchpad/research/cpp-modern/stdfull/`):
`idr.mlir` with its 87-header global module fragment followed by
`import std;` compiles (36 s, 140 MB BMI), and so do the whole `idr.facts`
module and its plain importer `Facts/Pass.cc` with `import std;` added,
once `std.pcm` is built `-std=c++26` rather than `gnu++26`
(`cpp-modern-lint.md` section 7).

## 3. What does not work (not in the mandate)

| Feature | Result | Consequence |
|---|---|---|
| Reflection (P2996) | `<meta>` absent; `^^T` "type name requires a specifier" (`refl1-4`, `reflection*`) | the user dropped it; `PIN(clang-no-reflection)` stays |
| Contracts (P2900) | `pre`/`post`/`contract_assert` do not parse (`contracts`) | one `support::invariant` as in cpp-starter (`PIN(clang-contracts)`) |
| Pattern matching (P2688) | `x match {...}` does not parse (`pattern_match`) | `visit` with visitor structs |
| `std::function_ref` | absent (`function_ref`, `function_ref_exp`) | constrained templates inside our code; `llvm::function_ref` only where MLIR's API takes one (`PIN(libcxx-no-function-ref)`) |
| `std::indirect`, `std::polymorphic` | absent (`indirect`) | `support::Box<T>` for the recursive `Pattern` (`PIN(libcxx-no-indirect)`) |
| `std::inplace_vector` | header absent (`inplace_vector`) | `llvm::SmallVector` with a named inline capacity |
| `std::move_only_function`, `std::copyable_function` | absent (`move_only_function`) | not needed |
| `std::generator` | header absent (`generator`) | not needed (coroutines are forbidden anyway, `AGENTS.md:928-934`) |
| `views::cartesian_product` | absent (`cartesian`) | not needed |
| `std::runtime_format` | absent (`runtime_format`) | `std::vformat` |
| `std::start_lifetime_as` | absent (`start_lifetime`) | the runtime keeps its casts in quarantine |
| `std::add_sat` (the old name) | absent (`saturation`) | use `std::saturating_add` |
| `trivially_relocatable_if_eligible` | the macro `__cpp_trivial_relocatability` 202502 is defined but the keyword does not parse (`trivially_relocatable`, `trivially_reloc2`) | not needed |
| `noexcept` lambdas through `llvm::function_traits` | fails (`walk.cc` with `-DWALK_NOEXCEPT`, `-DTS_NOEXCEPT`, `-DFREF_NOEXCEPT`; `ft.cc`, four lines of LLVM, fails in C++17 too) | an LLVM bug (`STLExtras.h:66-104` has no `noexcept` specializations): `upstream/llvm-function-traits-noexcept`, `PIN(llvm-function-traits-noexcept)`, and the `support::walk`/`type_switch` wrappers |

## 4. What MLIR's API allows for `noexcept`

| Site | `noexcept`? | Evidence |
|---|---|---|
| Overrides of MLIR virtuals (`runOnOperation`, `matchAndRewrite`, `initialize`, `getDependentDialects`, listener and action hooks) | yes: an override may be stricter | `snip/walk.cc:5-7`, `snip/fnpat.cc` |
| Hooks whose declaration TableGen writes (`fold`, `verify`, `parse`, `print`, `getEffects`, `inferResultRanges`, interface methods, dialect hooks) | no: the definition must repeat the declaration | `snip/decl.cc` ("exception specification in declaration does not match previous declaration") |
| Methods we declare in ODS `extraClassDeclaration` | yes: we write the declaration in the `.td` | — |
| Lambdas to `llvm::function_ref`, `llvm::any_of`, `map_range`, `std::function` parameters | yes | `snip/fref.cc` |
| Lambdas to `Operation::walk`, `TypeSwitch`, `Attribute::walk`, `TypeConverter::addConversion` | no (the bug above) | `snip/walk.cc` |
| `RewritePatternSet::add(fn)` with a `noexcept` function | yes | `snip/fnpat.cc` (`PatternMatch.h:910-929`) |
| `FnConversion<Op, auto Fn>`: a conversion pattern from a `noexcept` function | yes | `snip/fnpat.cc` |
| `pthread_create`, `sigaction` callbacks | yes: a `noexcept` function converts to the plain pointer | — |
