# R1 lane: the runtime (`rt.*`)

Read `README.md` beside this file first.

R0 made the runtime's platform layer the module `rt.platform`
(runtime/Platform: partitions `:cpu`, `:faults`, `:memory`, `:stacks`, one
unit per function under `Posix/`, `X86_64/`, `Aarch64/`; a private file set
of `idris_rt`, which now scans for modules). Do the same for the rest of
runtime/: modules `rt.<area>`, namespaces `rt::<area>`, no local header but
`idris_rt.h`.

## What the pilot showed

- Every path the runtime takes works with modules on the pinned clang:
  the fat LTO objects and the embedded bitcode (`.llvm.lto`),
  `--prepare-runtime` (the same exported symbols; private names change:
  `rt::platform::stackLimit` mangles as `_ZN2rt8platformW2rtW8platform...`,
  and `.str.N` numbering moves), the `available_externally` fast paths
  (the four bench programs' `.ll` are byte-identical), idr-eval's JIT on
  the native runtime (runtime/eval.cc imports rt.platform), and
  tests/toolchain/runtime-archive-check.
- Every interface unit defines a module initializer (`_ZGIW2rtW8platform`
  and one per partition) that nothing calls; no unit gets a static
  constructor for an import, so the archive check passes. Keep checking
  that (`check-archive.sh`, `.init_array`).
- tests/toolchain/cpu-features-aarch64 compiles the AArch64 processor test,
  now a unit of rt.platform, so it precompiles rt.platform's interfaces for
  the target first (any `runtime/Platform/*.cppm`, partitions named after
  their file). A new partition there needs nothing more; a partition that
  imports another must be precompiled after it (the test's loop is in
  file order).

## Files

| File | Lines | What it holds |
|---|---|---|
| internal.h | 89 | the runtime's internals in namespace rt: `allocate`, `release`, `newCell`, `freeCell`, `arenaActive`, `writeAll`, `formatUnsigned`, `formatSigned`, `encodeUtf8`, Numeral, `readNumeral`, `bigOfDigits`, `formatDouble`, `newString`, `mutableBytes`, `stringOf`, `gmpReady`, ... |
| alloc.cc | 77 | rt::allocate, release, newCell, freeCell (snmalloc) |
| rc.cc | 166 | reference counting: `idris_rt_inc`, `idris_rt_dec`, freeing |
| strings.cc | 343 | strings (simdutf): `newString`, `mutableBytes`, `stringOf`, the C ABI's string functions |
| io.cc | 260 | output buffer, input, `writeAll`, number formatting, `encodeUtf8` |
| numbers.cc | 175 | `readNumeral`, Numeral (fast_float) |
| big.cc | 318 | bigs (GMP): `bigOfDigits`, the C ABI's big functions |
| double.cc | 123 | `formatDouble` (Ryu) |
| gmp.cc | 44 | GMP's allocation hooks, `gmpReady` |
| arrays.cc | 27 | `idris_rt_array_new` |
| eval.cc | 90 | compile-time evaluation's arena, crash report and meter (compiler-only entry points, annotated `idris-rt-compiler`); imports rt.platform |
| start.cc | 210 | the program's entry, the processor test, the reserved-stack runner; imports rt.platform |
| idris_rt.h | 502 | the C ABI: stays a header (C and generated code read it) |
| cpu_features.h, cpu_x86_64.h, cpu_aarch64.h | 17, 31, 44 | the target entry's X-macro lists of processor features: idr-lower (lib/Lower/Pass.cc) and idris-mlir-cc read them too |
| check-archive.sh, link_check.c | | the archive check and the link check |
| foreign/idr/bench/gate/runtime.cc, runtime.h; bench/alloc/shapes.cc | 492, 131; 194 | the memory gate's runtime prototype and the allocation-shapes benchmark: experiments no build compiles (bench/README.md) |

## Proposed map

- `rt.alloc` (alloc.cc, gmp.cc's hooks), `rt.rc` (rc.cc), `rt.text`
  (strings.cc; io.cc's text output and formatting), `rt.io` (the buffer
  and input) if io.cc splits that way, `rt.numbers` (numbers.cc),
  `rt.big` (big.cc), `rt.double` (double.cc), `rt.eval` (eval.cc),
  `rt.start` (start.cc). One partition per concept, one unit per function.
- The C ABI's functions (`extern "C" idris_rt_...`) keep their C language
  linkage, which attaches them to the global module: they may be defined
  in module units (with idris_rt.h in the global module fragment), and
  their symbols do not change.
- internal.h goes: each declaration moves to the partition of the module
  that defines it.

## Special

- The runtime's profile applies to module units as to any (-O3, the
  target's baseline, bitcode with the native code, no FP contraction, no
  exceptions, no RTTI, no C++ library at link time): keep every module a
  file set of `idris_rt`, private, so the archive stays one archive.
- The vendored headers (snmalloc, simdutf, fast_float, Ryu, GMP) are C++
  or C headers: include them in the global module fragment of the units
  that use them, as idris_rt.h's macros are.
- Annotations stay on definitions: `idris-rt-baseline` (the processor test
  and what it calls stay at the baseline; `[[gnu::always_inline]]` helpers
  of start.cc), `idris-rt-compiler` (eval.cc's entry points, which
  --prepare-runtime leaves out of the prepared runtime).
- `cpu_features.h` and its lists stay headers (macros: `__builtin_cpu_supports`
  needs a string literal). Do not move or rename them without the lower
  and tools lanes, which include it. If you want them gone from the
  allowed list, generate them from the target entry into the build tree,
  as CMake generates idr/TargetEntry.h, and coordinate the includes.
- The two bench prototypes are no part of the build: convert them, or
  delete them if bench/README.md no longer needs them (say which).
- Gate: the prepared runtime's exported symbols must not change
  (README.md's dump script); run tests/toolchain (runtime-api,
  runtime-archive-check, runtime-prepared, runtime-start, big-cell,
  double-print, cpu-features-aarch64) and the whole `make test`.

## Allowed lines that are yours

no-local-headers:

    foreign/idr/bench/gate/runtime.cc: runtime.h
    runtime/alloc.cc: internal.h
    runtime/arrays.cc: internal.h
    runtime/big.cc: internal.h
    runtime/double.cc: internal.h
    runtime/eval.cc: internal.h
    runtime/gmp.cc: internal.h
    runtime/io.cc: internal.h
    runtime/numbers.cc: internal.h
    runtime/rc.cc: internal.h
    runtime/start.cc: internal.h
    runtime/strings.cc: internal.h

and, staying while the X-macro lists are headers:

    runtime/Platform/Aarch64/CpuFeatures.cc: cpu_features.h
    runtime/Platform/X86_64/CpuFeatures.cc: cpu_features.h
    runtime/start.cc: cpu_features.h

file-size:

    foreign/idr/bench/gate/runtime.cc

## Do not touch

foreign/idr (the compiler: its lanes'), the target entry in CMakeLists.txt
except a new list you generate, idris_rt.h's ABI.
