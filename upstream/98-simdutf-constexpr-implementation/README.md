<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [simdutf] The implementation constructors are not constexpr, so no program can hold an implementation as a constant

At simdutf 9.3.2 (8d82299, the pin of third_party/simdutf) and on its
master (read 2026-10-21), the base class's constructor
(`include/simdutf/implementation.h:7511`) and every architecture's
(`src/simdutf/<arch>/implementation.h`, the class `final`) only store
three constants, a name, a description and the instruction sets the
kernels require, but none is `constexpr`. A class whose only
constructors are not `constexpr` is no literal type, so a program cannot
hold an implementation as a constant object of its own class: the object
needs a dynamic initializer at startup, and the only way to the kernels
that needs none is through the virtual table and
`get_active_implementation()`, simdutf's choice at run time.

This repository's runtime is built with the one implementation its
target fixes, and calls it directly: the target's features are known
when the program is built, and the startup check refuses a machine
without them. A call through the virtual table is an indirect call, which
the program's stack bound must take as reaching every function of its
type, so simdutf's dispatch would read as a cycle; and a dynamic
initializer is work at startup for a fact known when the program is
built. The runtime holds `inline constexpr Utf8 utf8{}`, `Utf8` the
target's implementation class (`runtime/Strings/Simd.h`), which does not
compile at the pin.

## Reproduce

`constant.cpp` holds such a constant, of the fallback implementation, and
calls through it:

    c++ -std=c++20 -fsyntax-only -DSIMDUTF_IMPLEMENTATION_FALLBACK=1 \
        -I <simdutf>/include -I <simdutf>/src constant.cpp

At the pin (host Apple clang 21, arm64 macOS, 2026-10-21, *measured*):

    error: constexpr variable cannot have non-literal type 'const simdutf::fallback::implementation'
    note: 'implementation' is not literal because it is not an aggregate and has no constexpr constructors other than copy or move constructors

With `simdutf.patch` applied to a copy of the release's tree it compiles
under `-std=c++17` and `-std=c++20`, and so does the same constant of
the arm64, haswell, icelake and westmere classes; at `-O2` the constant
is an internal constant with no initializer at startup, and `count`
calls `simdutf::fallback::implementation::count_utf8` directly (*measured*,
same host).

## Patch

`simdutf.patch`, against the release, which applies to the pin: `constexpr`
on the base constructor and on the constructor of arm64, fallback,
haswell, icelake, lasx, lsx, ppc64 and westmere. Their initializers are
string literals and the `instruction_set` enumerators, constant
expressions; the destructor stays the defaulted, protected, trivial one.
rvv's constructor is left as it is: it asks the processor whether it has
Zvbb (`internal::detect_supported_architectures()`), which no constant
can. Nothing else changes: an implementation constructed at run time, as
simdutf's own list constructs them, is constructed as before.

It is carried since simdutf became a patch project of `tools/patches.sh`
(2026-10-21): the bootstrap's `simdutf` step exports third_party/simdutf
with its patches for the runtime's build.

## Upstreaming plan

Status: carried (2026-10-21); not filed. simdutf's `AI_USAGE_POLICY.md`
requires a human in the loop who has read and reviewed the change and can
answer for it in review, and encourages disclosing tool assistance: Bjorn
files it, in his own words, if he chooses to.

- One pull request, "Make the implementation constructors constexpr",
  from `simdutf.patch`. The body says what it enables (an implementation
  held as a constant and called directly, with no static initializer) and
  why rvv is left out. CONTRIBUTING.md asks that every change be tested
  with `ctest --test-dir build`; that is not run here. A test the pull
  request could add: `constant.cpp`'s constant, in a unit compiled for
  each implementation the build enables but rvv.
- When a simdutf release with the change is pinned, the patch, its
  PINS.md entry and this directory go.
