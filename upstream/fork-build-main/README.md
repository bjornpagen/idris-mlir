<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] Building a program needs the caller to hold the elaborator's session state

At the pin (third_party/Idris2 at 1c630e67), `buildDeps`
(`src/Idris/ModTree.idr:279-305`) builds a main file and what it imports in
the caller's session: it takes the unification state (`Ref UST UState`) and
the metadata (`Ref MD Metadata`) as auto arguments, and expects the context
to have been reset (`resetContext`, `src/Idris/REPL/Common.idr:178-190`).
A driver that only builds a program therefore makes and holds the
elaborator's state itself, upstream's REPL and `Idris.Driver` among them.

This is not a bug of Idris's. It is recorded here because this repository's
frontend is a driver of the fork that only builds programs, and is total:
`UState` holds constraints over the evaluator's values (`NF`), whose
closures are not strictly positive, so a total definition cannot name it.
Building, which elaborates and so evaluates whatever a program's types
compute, is the one operation of the fork the frontend takes on trust with
the evaluator.

## The change

`pull-request.diff`, against the pin, adds `buildMain mainFile` beside
`buildDeps`: it makes the unification state and the metadata for the main
module's origin (`ctxtPathToNS mainFile`), resets the context to that
origin, and runs `buildDeps mainFile`, returning its errors. In the fork,
whose delayed elaborators live in a cell of their own (`Ref DLY
DelayedElabs`, compiler/idris/README.md), it makes that cell too. It is the
frontend driver's own sequence, moved into the fork so that the frontend
never names the session's state.

## Testing at the pin

`pull-request.diff` applies to the pin (`git -C third_party/Idris2 apply
--check`). With it and the other `upstream/fork-*/pull-request.diff` applied in order to
a copy of the pin, the pinned compiler's 292 modules typecheck with the
toolchain's Idris (`idris2 --typecheck idris2api.ipkg`, arm64 macOS,
2026-10-15).

## Why there is no patch

There is no `idris.patch`. The fork in compiler/idris carries the function
as its own code; the stock Idris has no caller for it.

## Upstreaming plan

Status: carried as the fork's code; nothing goes to idris-lang/Idris2
from here (upstream/README.md, **Idris**), and upstream needs nothing of
it: its own drivers hold the session.

- `pull-request.diff` is the record of what the fork added against the
  pin, for a re-sync of compiler/idris (compiler/idris/README.md): the
  function is carried forward onto the new base, beside `buildDeps`,
  whatever upstream does to the latter.
- It goes when the frontend no longer builds through it; then this
  directory and the PINS.md text go.
