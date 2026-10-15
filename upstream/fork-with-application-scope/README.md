<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A with application in a local definition or a record update is refused

At the pin (third_party/Idris2 at 1c630e67), a with block's clause may call
the with block again with `f pats | w` on its right-hand side. `withRHS`
(`src/TTImp/WithClause.idr:218-274`) rewrites each such application to a
call of the with block's function, looking through the right-hand side's
terms; it does not look into a local block's definitions or into a record
update's fields (`wrhs (ILocal ...)` and `wrhs (IUpdate ...)`, each marked
`-- TODO!`). An application written there is left as it is, and
elaborating it fails with `with application not implemented yet`.

## Reproduce

`WithScope.idr`: three definitions with the same with block, each calling
it again on a smaller value; `direct` from its right-hand side, `local`
from a `where` definition, `update` inside a record update's field. With
the toolchain's (unpatched) Idris, `idris2 --check WithScope.idr` accepts
`direct` and reports `with application not implemented yet` for `local` and
`update` (arm64 macOS, 2026-10-15).

## Expected

All three check: the call is the same wherever on the right-hand side it is
written.

## The fix

`pull-request.diff`, against the pin, is the change: `wrhs` rewrites the
clauses of a local block's definitions (`wrhsD`, through `wrhsC`, as it
rewrites a case block's clauses) and the value of each field of a record
update (`wrhsU`). The upstream test is `tests/idris2/with/with013`.

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
Idris; `WithScope.idr` has not been run through the fork, since nothing is
built on the machine the change was written on.

## Upstreaming plan

Status: carried as the fork's code; nothing goes to idris-lang/Idris2
from here. Idris accepts no contribution that arises from generative AI
or a coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report, the diff and the fork's
change were written with one.

- `pull-request.diff` is the record of what the fork changed against the
  pin, laid out as a stock checkout with the upstream test it would carry.
  At a re-sync of compiler/idris (compiler/idris/README.md) it says what to
  look for upstream: if upstream has fixed the bug its own way, the fork
  takes upstream's code and drops this change; if not, the change is
  carried forward onto the new base.
- When upstream's fix arrives: this directory and the PINS.md entry go.
- Whether to report the bug upstream is Bjorn's call alone, in his own
  words and from his own understanding; nothing here is drafted for it.
