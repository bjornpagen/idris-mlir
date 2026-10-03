# R1 lane: the passes' remainder

Read `README.md` beside this file first.

lib/Passes is a grab bag of passes that R0 left in place (R0 moved out
what other areas shared: Scc, Tail and Trips to idr.graph, the tail
position modulo a constructor with them, and idr-target to idr.target).
Each pass's glue belongs to the library whose logic it runs: give each
family a module and a library, and leave no lib/Passes behind (or only
what one module still holds, renamed after it).

## Files

| File | Lines | What it holds |
|---|---|---|
| Contify.cc | 113 | idr-contify (`usersBySymbol`, `continuationCall`); imports idr.facts |
| Defunctionalize.cc | 1193 | idr-defunctionalize: Labels, LabelLattice, FieldAnchor, FieldLabels, Module, LabelAnalysis (a sparse dataflow analysis, with MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID), Flow, Sink, Converter (700 lines); imports idr.graph (`namespace graph = idr::graph;`) |
| LoopBreakers.cc | 93 | idr-loop-breakers (`choose`); imports idr.facts, idr.graph |
| Narrow.cc | 542 | idr-narrow: NaturalRanges, Facts, narrowing of ops, arguments, results, carried values, versions; imports idr.ranges; includes Ownership/Ownership.h (`isStatic`, `stageAttr`, `ownedStage`) |
| NarrowLanes.cc | 414 | idr-narrow-lanes: widths, Copy; imports idr.graph (`runsAtMostOnce`) |
| Prune.cc | 139 | idr-prune; defines `idr::returnNever` (include/idr/Passes.h) |
| ReturnedArguments.cc | 244 | idr-returned-arguments |
| Simplify.cc | 231 | idr-simplify (a loop of rounds, its statistics); defines `idr::simplifyRound` (include/idr/Passes.h); imports idr.support |
| TailLoops.cc | 578 | idr-tail-loops: Loop, Decision, WhileDo; has its own `passesOnPrevious` and `isSelfCall`; includes Ownership.h and uses nothing of it; includes idr/Passes.h (`returnNever`) |
| Trmc.cc | 197 | idr-trmc; imports idr.graph (Modulo, `moduloAt`, `fieldsOf`, `isSelfCall`, `passesOnPrevious`) |
| Vectorize.cc | 179 | idr-vectorize; imports idr.target (`vectorBits`) |
| include/idr/Passes.h | 23 | `simplifyRound`, `returnNever` |

## Proposed map

One module per family, each with its glue (the generated base) as a plain
`Pass.cc` or `<Pass>/Pass.cc`:

- `idr.defunctionalize`: `:labels` (Labels, the lattice, field labels),
  `:analysis` (LabelAnalysis: declare `static mlir::TypeID
  resolveTypeID();` and define it in a unit, as lib/Support/Actions does),
  `:converter` (Converter split by what it converts, each under 400
  lines).
- `idr.narrow`: idr-narrow and idr-narrow-lanes, one partition each.
  Imports idr.ranges, idr.graph and idr.ownership (see below).
- `idr.tail` (or `idr.loops`): idr-tail-loops, idr-trmc and
  idr-returned-arguments. TailLoops' own `passesOnPrevious` and
  `isSelfCall` are the ones idr.graph exports: use those (one
  representation), after checking they mean the same.
- `idr.simplify`: idr-simplify, idr-prune, idr-contify, idr-loop-breakers;
  `simplifyRound` and `returnNever` move out of include/idr/Passes.h into
  it, and the header goes.
- `idr.vectorize`: idr-vectorize. Imports idr.target.

## Imports and links

As listed; each library linked from `idr_dialect`.

## Special

- Narrow.cc's `#include "Ownership/Ownership.h"` is the ownership lane's to
  replace (one line, `import idr.ownership;`); leave it, and keep it in the
  unit that uses `isStatic`/`stageAttr` if you split the file. Until the
  ownership lane lands, a module unit cannot get those names: keep that
  code in a plain unit, or land after the ownership lane.
- TailLoops.cc's include of Ownership.h is unused: delete it, and its
  allowed line.
- Simplify's round is a textual pipeline (`simplifyRound`), whose
  statistics and remarks tests/idr/obs reads: its text must not change.

## Allowed lines that are yours

no-local-headers:

    foreign/idr/lib/Passes/Prune.cc: idr/Passes.h
    foreign/idr/lib/Passes/Simplify.cc: idr/Passes.h
    foreign/idr/lib/Passes/TailLoops.cc: Ownership/Ownership.h
    foreign/idr/lib/Passes/TailLoops.cc: idr/Passes.h

(`foreign/idr/lib/Passes/Narrow.cc: Ownership/Ownership.h` is the
ownership lane's.)

file-size:

    foreign/idr/lib/Passes/Defunctionalize.cc
    foreign/idr/lib/Passes/Narrow.cc
    foreign/idr/lib/Passes/NarrowLanes.cc
    foreign/idr/lib/Passes/TailLoops.cc

## Do not touch

lib/Graph, lib/Ranges, lib/Target, lib/Support, lib/Facts (R0's modules:
ask before changing an interface), lib/Ownership, other lanes'
directories.
