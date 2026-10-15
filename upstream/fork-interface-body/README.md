<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] An interface body drops every declaration that is not a method

At the pin (third_party/Idris2 at 1c630e67), the body of an interface is
parsed as any top-level declarations (`ifaceDecl`, `src/Idris/Parser.idr`),
and elaborated by keeping the method signatures, abstract types and default
definitions and nothing else (`getSig` and `getDefault`, through
`mapMaybe`, in `elabInterface`, `src/Idris/Elab/Interface.idr:51-66, 239-241,
297-300`). A data declaration with constructors, a record, a namespace, a
`parameters` block, a `failing` block, `%runElab`, a directive such as
`%default`, a nested interface or implementation is dropped without a word.
The upstream comment above it says what is missing: `-- TODO: Check all
the parts of the body are legal`.

## Reproduce

`Dropped.idr`: an interface whose body declares `data Colour = Red |
Green`, and a definition of type `Colour`. With the toolchain's (unpatched)
Idris, `idris2 --check Dropped.idr` reports `Undefined name Colour` at the
use, and nothing at the declaration; without the use, the file checks
(arm64 macOS, 2026-10-15). A dropped `failing` block's check is skipped, a
dropped `%default total` leaves the defaults unchecked, and neither says so.

## Expected

The declaration is refused where it is written, with an error that says
what an interface body may hold.

## The fix

`pull-request.diff`, against the pin, is the change:

- `bodyPart` reads each declaration of the body as what an interface
  holds, `BodyPart`: a signature (a claim, or an abstract `data`) or a
  default definition, and refuses any other declaration at its location.
  `getSig` and `getDefault` are gone; `splitParts` gives the signatures and
  the defaults, each in the order written, which is what the two
  `mapMaybe`s gave.
- A fixity declaration in the body changes the syntax while it is
  desugared and declares nothing, so it is still accepted.
- The upstream test (`tests/idris2/interface/interface037`) checks that a
  data declaration is refused and that signatures, an abstract type and a
  default are accepted.

Nothing the packages Idris ships (prelude, base, contrib, linear, network,
test, papers) or this repository's libraries declare in an interface body
is refused: their bodies hold claims, `using` blocks of claims, abstract
types and defaults.

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
Idris; `Dropped.idr` has not been run through the fork, since nothing is
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
