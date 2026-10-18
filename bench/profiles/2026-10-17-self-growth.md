<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# The self-compile's frontend under the growth check (2026-10-17)

Self-hosting's S2.2 (proposals/0003-self-host/checker/README.md §12): the
polymorphism checker, a growth graph whose cycles are judged by potentials,
replaces the refusals S2.1 had to patch away. Gate 3 is the self compile's
frontend step with no patch: the frontend on Chez over a fresh copy of
`compiler/src`, against a prefix whose fork package that frontend built.
arm64 macOS, the typecheck machine; no LLVM built.

## Gate 3 before the hard cleanup (*measured*, idle)

`/tmp/0003c-final/gate3`: exit 0, no refusal, no internal error, 1,494 s.

| Phase | ms |
| --- | --- |
| checks | 753 |
| reachable | 8,978 |
| growth | 67,075 |
| translate | 596,413 |
| emit | 775,030 |

- Peak resident memory: 5.15 GB.
- The module is 82,419,409 bytes (S2.1: 75,015,773), with about 69,773
  Core functions and 6,743 data types (S2.1: 63,464 and 5,932). The
  checker's own sources and option (a)'s method instances account for the
  growth.

## Gate 3 after the hard cleanup (*measured*, under load)

The cleaned tree with its regression fixed (§12 of the checker's record),
the machine shared with other gates: exit 0, no refusal, no internal
error, 1,575 s.

| Phase | ms |
| --- | --- |
| checks | 766 |
| reachable | 9,554 |
| growth | 77,202 |
| translate | 559,011 |
| emit | 866,416 |

- Peak resident memory: 5.56 GB.
- The module is 82,221,964 bytes; the Core dump 78,950,368.

## The growth phase (*measured*, self compile)

- 1,093 s at the first integration that admitted the self compile.
- 88.5 s: three joins folded `++` from the left (the head bound, 608 s;
  the site lists, 42 s; the arc ends, 133 s), and arcs were sorted by
  index lookups (232 s).
- 69.4 s: the check's tables were `Vect`s read by position; as trees
  (`Places n d`) the check fell from 33 s to 0.6 s.
- 67.1 s: each static argument of a request is read once
  (`TS.readings`), and a request carries its heights.

## Translate (*measured*)

Translate went from 339 s (S2.1) to 596 s. The source is most of it: the
dictionary passes ran three times instead of two, because the checker's
own `SortedSet` and `SortedMap` uses read a field before the pass that
builds it, which voids that pass. Option (a)'s method instances add 8.5%
per pass and the checker's bookkeeping about 8%. Reading each static
argument once took translate to 565.2 s with Core identical. Translating
only the instances that relied on a field found built late, instead of
the whole program again, is separate work.

## What is not measured

- The C++ reader and the pipeline on the self module (S3, the owner's
  build).
- `make self` itself, stages 1 to 3.
