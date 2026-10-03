# R1 lane: lowering (`idr.lower`)

Read `README.md` beside this file first.

lib/Lower is idr-lower (idr types to LLVM in two phases) and idr-tail-calls.
Make it the module `idr.lower` (namespace `idr::lower`, as today), library
`idr_lower`. The layouts it builds values in are already R0's `idr.layout`
(namespace `idr::layout`); the cells idr-stack puts on the stack are built
here (`stackCell`, R0 moved it from lib/Stack, and its mark is
`idr::layout::stackMark`).

## Files

| File | Lines | What it holds |
|---|---|---|
| Runtime.h / Runtime.cc | 157 / 463 | class Runtime (calls of the runtime's C functions, crashes, cells, counting, static data, closure code); `crashMessage`; helpers `describe`, `ptrType`, `i64Constant`, `i32Constant`, `at`, `alignAt` |
| Patterns.h / Patterns.cc | 102 / 565 | `IdrPattern`, `Fields`; the phase-2 patterns of cons, tags, fields, constants, crashes, division, chars and bytes, runtime calls (`addRuntimeCalls` over the dialect's op list), comparisons; `populatePatterns`; declarations of the other `populate*`, `lowerMatches`, `lowerArrayLoops`, `arrayView`, `stackCell` |
| Arrays.cc | 256 | array patterns, `arrayView`, `populateArrayPatterns` |
| Bigs.cc | 264 | big patterns, `populateBigPatterns` |
| Closures.cc | 72 | closure and apply patterns |
| Counting.cc | 252 | dup, drop, reuse, take, share, borrow patterns; `Fields::kept` |
| Strings.cc | 196 | string patterns |
| Matches.cc | 155 | phase 1: `lowerMatch`, `lowerMatchLit`, `lowerMatches` |
| Loops.cc | 330 | phase 1: `lowerGenerate`, `lowerFold`, `lowerArrayLoops` |
| Facts.h / Facts.cc | 41 / 95 | class Facts (LLVM attributes at function boundaries) |
| StackCell.cc | 30 | `stackCell` |
| Pass.cc | 236 | idr-lower's glue and logic: `findRoot`, `requiredCpuFeatures`, `emitMain`, `checkNoClosures`, the pass |
| TailCalls.cc | 662 | idr-tail-calls: glue and its logic (Known, Frame, ReturnRegisters, `prepare`, `recall`, `cyclesOf`, its own `inTailPosition` on LLVM calls); imports idr.graph |

## Proposed map

- `:runtime` (Runtime.cppm): Runtime, `crashMessage`. Runtime's members
  are 450 lines: split by concern into units (calls and crashes, cells,
  counting, static data, closure code), or into types of their own if a
  concern stands alone (static data does); the shared helpers in the
  partition outside `export`.
- `:patterns`: `IdrPattern`, `Fields`, the `populate*` functions,
  `arrayView`, `stackCell`; one unit per `populate*` with its patterns
  (Arrays, Bigs, Closures, Counting, Strings, and Patterns.cc's own set
  split under 400 lines: cells, scalars, runtime calls).
- `:phases`: `lowerMatches`, `lowerArrayLoops` and their helpers.
- `:facts`: Facts, `Facts/Facts.cc`.
- `:tailcalls`: TailCalls.cc's logic, one concept per unit; its glue in
  `TailCalls/Pass.cc` (or `Pass.cc` beside idr-lower's).
- Glue: `Pass.cc` (idr-lower's base and options, a call into the module),
  the logic of Pass.cc into the module.
- Drop R0's transitional `using layout::...;` declarations in Runtime.h:
  name the layout types `layout::` or import them where used.

## Imports and links

idr.mlir, idr.dialect, idr.layout, idr.graph (tail calls). Library
`idr_lower`, linked from `idr_dialect`.

## Special

- `addRuntimeCalls<... #include "idr/IdrOps.cc.inc" (GET_OP_LIST) ...>`
  includes the dialect's op list inside a template argument list. In a
  module unit that text include follows the imports; it is a list of class
  names (every op is exported by idr.dialect), not declarations, so it is
  safe. If clang disagrees, keep that function in a plain unit.
- Pass.cc includes `cpu_features.h` (the target entry's X-macro list) and
  `idris_rt.h`: macros, so they go in the global module fragment of the
  unit that needs them. Your allowed line for cpu_features.h follows the
  include if it moves (`<new file>: cpu_features.h`); it stays allowed,
  since the runtime lane owns that header.
- Runtime.h imports idr.layout after its includes (a transitional header,
  MODULES.md pitfalls); it goes away with the header.
- The JIT mode of Runtime (idr-eval) is the eval lane's user: Runtime's
  interface must not change in meaning.

## Allowed lines that are yours

no-local-headers:

    foreign/idr/lib/Lower/Arrays.cc: Lower/Patterns.h
    foreign/idr/lib/Lower/Bigs.cc: Lower/Patterns.h
    foreign/idr/lib/Lower/Closures.cc: Lower/Patterns.h
    foreign/idr/lib/Lower/Counting.cc: Lower/Patterns.h
    foreign/idr/lib/Lower/Facts.cc: Lower/Facts.h
    foreign/idr/lib/Lower/Loops.cc: Lower/Patterns.h
    foreign/idr/lib/Lower/Matches.cc: Lower/Patterns.h
    foreign/idr/lib/Lower/Pass.cc: Lower/Facts.h
    foreign/idr/lib/Lower/Pass.cc: Lower/Patterns.h
    foreign/idr/lib/Lower/Pass.cc: cpu_features.h   (stays, at its new file)
    foreign/idr/lib/Lower/Patterns.cc: Lower/Patterns.h
    foreign/idr/lib/Lower/Patterns.h: Lower/Runtime.h
    foreign/idr/lib/Lower/Runtime.cc: Lower/Runtime.h
    foreign/idr/lib/Lower/StackCell.cc: Lower/Patterns.h
    foreign/idr/lib/Lower/Strings.cc: Lower/Patterns.h

file-size:

    foreign/idr/lib/Lower/Patterns.cc
    foreign/idr/lib/Lower/Runtime.cc
    foreign/idr/lib/Lower/TailCalls.cc

## Do not touch

lib/Layout (R0's idr.layout: ask before changing an interface), lib/Stack
(the stack lane's), runtime/ (cpu_features.h is the runtime lane's), other
lanes' directories.
