# R1 lane: stack, inline, expect, canonicalize, fold (and support)

Read `README.md` beside this file first.

Five small areas, each its own module and library, plus a check on
lib/Support, which R0 already converted (`idr.support`: actions, pattern
counts, pipeline statistics; `EnableStatistics.h` stays a force-included
header, PIN(llvm-force-enable-stats)). Nothing is left to do in
lib/Support unless one of your areas needs a name it does not export.

## Files

| File | Lines | What it holds |
|---|---|---|
| lib/Stack/Recursion.h / .cc | 36 / 67 | Cycles (the call graph's cycles, through closures); imports idr.graph |
| lib/Stack/Escape.h / .cc | 105 / 205 | Escapes (which cons may outlive their frame); imports idr.graph |
| lib/Stack/Pass.cc | 69 | idr-stack's glue and its decision (marks cons with `idr::layout::stackMark`); imports idr.layout |
| lib/Inline/Inline.cc | 187 | idr-inline: Decisions, `decide`, the pass; imports idr.facts, idr.graph |
| lib/Expect/Expect.h | 134 | the properties idr-expect checks, one function each |
| lib/Expect/*.cc | 22-289 | Allocation, Breakers, Clones, Closures, Continuations, Counting, Facts, Folds, Loops, Output, Quantities, Words; Pass.cc (154: the pass and its lookups: `fail`, `where`, `isCloneOf`, `locationNames`, `namedFunctions`, `named`, `lookup`) |
| lib/Canonicalize/Pass.cc | 121 | idr-canonicalize: canonicalize with its rewrites counted (`regionLevel`, the pass); imports idr.support |
| lib/Fold/Fold.cc | 441 | the ops' `fold` hooks over strings and bigs (members: plain units) and their helpers (Scope, `extended`, `wrapped`, `compared`, `strUnary`, `bigBinary`, `bigDivision`, `listElements`), and `idr::stringOfList` (declared in Idr.h: plain) |

## Proposed map

- `idr.stack` (namespace idr::stack): `:recursion` (Cycles), `:escape`
  (Escapes), each type's members in a unit, and the decision Pass.cc makes
  (`idr::stack::mark` or so) in a unit; glue `Pass.cc` thin. Imports
  idr.mlir, idr.dialect, idr.graph, idr.layout.
- `idr.inlining` (namespace idr::inlining, since `inline` is a keyword;
  lib/Inline may keep its name): Decisions and `decide`; glue `Pass.cc`.
  Imports idr.mlir, idr.dialect, idr.facts, idr.graph.
- `idr.expect`: one partition per family of properties (allocation,
  cycles, clones, closures, continuations, counting, facts, folds, loops,
  output, quantities, words), one unit per property; `:lookup` for
  Pass.cc's helpers; glue `Pass.cc`. Imports idr.mlir, idr.dialect,
  idr.facts, idr.graph, and idr.ownership once it exists (Counting.cc's
  `readFrom`).
- `idr.canonicalize`: what Pass.cc does besides the generated base
  (`regionLevel`, the pattern set it collects), if anything is left once
  the glue is thin; glue `Pass.cc`. Imports idr.mlir, idr.dialect,
  idr.support.
- Fold: the `fold` hooks stay plain, split by op family (`Fold/Strings.cc`,
  `Fold/Bigs.cc`, `Fold/Heads.cc`, ...) and `Fold/StringOfList.cc`; their
  helpers become `idr.fold` (namespace idr::fold), which the hooks import.
  The helpers call the runtime natively: `idris_rt.h` in the global module
  fragment of the units that call it.

## Special

- `Expect/Counting.cc` includes `Ownership/Ownership.h` for `readFrom`. The
  ownership lane replaces that one line with `import idr.ownership;` and
  deletes its allowed line; leave that line alone. If you split Counting.cc,
  keep the include in the unit that calls `readFrom` and say so.
- `Expect/Folds.cc` includes `idris_rt.h` for a macro: global module
  fragment.
- `inline` is a C++ keyword: no namespace or module component may be it.

## Allowed lines that are yours

no-local-headers:

    foreign/idr/lib/Expect/Allocation.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Breakers.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Clones.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Closures.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Continuations.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Counting.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Facts.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Folds.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Loops.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Output.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Pass.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Quantities.cc: Expect/Expect.h
    foreign/idr/lib/Expect/Words.cc: Expect/Expect.h
    foreign/idr/lib/Stack/Escape.cc: Stack/Escape.h
    foreign/idr/lib/Stack/Escape.h: Stack/Recursion.h
    foreign/idr/lib/Stack/Pass.cc: Stack/Escape.h
    foreign/idr/lib/Stack/Pass.cc: Stack/Recursion.h
    foreign/idr/lib/Stack/Recursion.cc: Stack/Recursion.h

(`foreign/idr/lib/Expect/Counting.cc: Ownership/Ownership.h` is the
ownership lane's.)

file-size:

    foreign/idr/lib/Fold/Fold.cc

## Do not touch

lib/Support, lib/Graph, lib/Layout, lib/Facts (R0's modules: ask before
changing an interface), lib/Dialect (the hooks lane's; idr.canon there is
the dialect's canonicalization helpers, not idr-canonicalize), other
lanes' directories.
