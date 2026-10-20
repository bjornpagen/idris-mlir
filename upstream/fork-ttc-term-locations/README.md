<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A term read back from a TTC has no locations

At the pin (third_party/Idris2 at 1c630e6), the TTC instance of `Term vars`
(`src/Core/TTC.idr`) writes no node's file context and reads every node
back at `emptyFC`: a `Local`, a `Ref`, an `App`, a `Bind` and its binder,
every one. Building a main file ends by reading the main module back from
its TTC (`buildDeps`, `readAsMain`), so a compiler that reads the checked
terms of the program finds no location in any of them, the main module's
included.

This is not a bug of Idris's: upstream's code generators read the compiled
case trees, and its errors are reported while elaborating, before a term is
written. It is recorded here because this repository's frontend reads the
checked terms (AGENTS.md: the compiler consumes checked Idris TT) and names
in each diagnostic the term an op comes from. With no term located, every
op the frontend emitted fell back to its definition's location (the type
signature's line), and a refusal named a do block's function rather than
its statement (tests/cycle-ioref-knot).

## The change

`pull-request.diff`, against the fork's code before it (which already
carries `upstream/fork-total-frontend-paths`, whose well-founded decoders it
extends), writes each node's location after its tag and reads it back. A
location is written against the location of the node it is part of, the
nearest enclosing one that has one: in that one's file (nearly always) it
is the start line's difference from that one's start line, the start
column, the line count and the end column, each one byte for the usual
sizes; a location in another file, or one inside nothing located, is written
whole; an empty one is a byte. An application of a function to several
arguments keeps the location of each of its applications. `ttcVersion`
moves, so no TTC of the old form is read.

Measured on arm64 macOS (2026-10-19): the installed prelude grows from 2.2
to 3.6 MB and base from 17 to 30 MB; the frontend's time on
bench/k-nucleotide (1.23 to 1.28 s) is within that of other checkouts
without the change (1.24 to 1.57 s), since a definition is decoded only
when it is used.

## Why there is no patch

There is no `idris.patch`. The fork in compiler/idris carries the change as
its own code; the stock Idris builds only the fork, the frontend and the
test runner, none of which reads a term's location from a TTC.

## Upstreaming plan

Status: carried as the fork's code; nothing goes to idris-lang/Idris2
from here (upstream/README.md, **Idris**).

- `pull-request.diff` is the record of what the fork changed, for a re-sync
  of compiler/idris (compiler/idris/README.md): the encoder and decoder of
  a term, its binder and a case tree's leaf are carried onto the new base
  with each node's location.
- It goes if upstream's TTC comes to keep term locations; then this
  directory and the PINS.md entry go.
