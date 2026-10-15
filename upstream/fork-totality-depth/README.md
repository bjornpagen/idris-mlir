<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] Whether a function is total depends on a count of constructors

At the pin (third_party/Idris2 at 1c630e67), the termination checker's
comparison of a call's argument with a parameter (`sizeCompare`,
`src/Core/Termination/CallGraph.idr:154-277`) looks under matching
constructors on both sides only as deep as a count, `%totality_depth`
(default 5, `totalLimit` in `ElabDirectives`). A recursion that decreases
one level further down is refused as not total, and the same definition is
accepted after `%totality_depth 7`: acceptance is decided by a number, not
by the program.

## Reproduce

`Depth.idr`: `deep` calls itself on its list with the seventh element
removed, which is smaller by looking under six matching `(::)`; `shallow`
does the same five deep. With the toolchain's (unpatched) Idris, `idris2
--check Depth.idr` reports `deep is not total, possibly not terminating due
to recursive path Depth.deep` and accepts `shallow` (arm64 macOS,
2026-10-15). Upstream's own test `tests/idris2/total/total025/Pragma.idr`
shows the count deciding: the same recursion is refused at depth 1 and
accepted at depth 3.

## Expected

Both are total: the comparison looks under matching constructors as far as
the two terms go.

## Cause

The count bounds a search that is exponential without it. `sizeCompare s t`
first compares `s` with each argument of `t`'s constructor (descending `t`
alone), and then, when `s` has the same constructor, each argument of `s`
with the matching argument of `t` (descending both in step). The same pair
of subterms is reached along every interleaving of the two descents, so the
work grows with the binomial of the two depths; the count, decremented on
each step in step, keeps it polynomial and cuts off what is beyond it.

A second, smaller fault: an as pattern compares with both of its sides and
keeps the first answer that is not `Unknown` (`knownOr`), so a side that is
`Same` hides a side that is `Smaller`. With more depth a side can become
`Same` where it was `Unknown`, and a recursion found decreasing at a lower
depth would then be lost.

## The fix

`pull-request.diff`, against the pin, is the change:

- A comparison is a function of the two subterms it compares, and a pair
  of paths names them: from the term checked and from the parameter, each
  step into an application's argument by its position, into a dotted
  pattern, into either side of an as pattern, or into a metavariable's
  solution. Each comparison is remembered by its pair of paths (one memo
  per comparison of an argument with a parameter), so each pair is
  compared once and the work is bounded by the product of the two terms'
  sizes. The comparison is what upstream's computes with an unbounded
  count, and terminates without one: every step descends one of the two
  terms, but for a metavariable's solution, which the occurs check keeps
  acyclic.
- An as pattern's sides are joined with `|+|` (the strongest answer), so
  an answer never weakens as the comparison looks deeper: everything the
  pin accepts is accepted.
- `%totality_depth`, the `TotalityDepth` directive, `setTotalLimit` and
  `totalLimit` are gone, with their documentation; a program that writes
  the pragma is refused by the parser. `total025`'s `Pragma.idr` checks
  both recursions total with no pragma.

## Why there is no patch

There is no `idris.patch`. The Idris that elaborates what this compiler
consumes is the fork in compiler/idris, which carries the change as its own
code; the stock Idris only builds stage 0 and the benchmarks' Chez
baseline.

## Testing at the pin

`pull-request.diff` applies to the pin (`git -C third_party/Idris2 apply
--check`). With it and the other `upstream/fork-*/pull-request.diff` applied in order to
a copy of the pin, the pinned compiler's 292 modules typecheck with the
toolchain's Idris (`idris2 --typecheck idris2api.ipkg`, arm64 macOS,
2026-10-15). No stock Idris has been built with it and upstream's suite has
not run with it. The fork with the change typechecks with the toolchain's
Idris; `Depth.idr` has not been run through the fork, since nothing is built
on the machine the change was written on.

## Upstreaming plan

Status: carried as the fork's code; nothing goes to idris-lang/Idris2
from here. Idris accepts no contribution that arises from generative AI
or a coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report, the diff and the fork's
change were written with one.

- `pull-request.diff` is the record of what the fork changed against the
  pin, laid out as a stock checkout with upstream's test (`total025`)
  changed to what it would check. At a re-sync of compiler/idris
  (compiler/idris/README.md) it says what to look for upstream: if upstream
  has removed the count its own way, the fork takes upstream's code and
  drops this change; if not, the change is carried forward onto the new
  base.
- When upstream's fix arrives: this directory and the PINS.md entry go.
- Whether to report the bug upstream is Bjorn's call alone, in his own
  words and from his own understanding; nothing here is drafted for it.
