<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A totality check drops a call to a definition its module does not import

At the pin (third_party/Idris2 at 1c630e67, the toolchain's
`idris2` 0.8.0-1c630e67c), a `total` function that reaches a non-terminating
`covering` function through another module is accepted as total, unless the
module that defines the loop is imported directly. The termination check
walks the reached calls. `resolveCall`
(`src/Core/Termination/SizeChange.idr:267-270`) looks each callee up in the
context, and when the lookup fails it logs "Not found" and drops the call.
A callee from a module that is not imported is not in the context, so the
path through it is never seen.

## Reproduce

Four modules in one directory, each with `%default total`:

```idris
module LA
export covering
loop : Nat -> Nat
loop x = loop (S x)

module LB
import LA
export covering
viaLoop : Nat -> Nat
viaLoop x = loop x

module LC
import LB
caller : Nat -> Nat
caller x = viaLoop x

module LD
import LA
import LB
caller : Nat -> Nat
caller x = viaLoop x
```

The results, measured on arm64 macOS on 2026-10-16:
- `idris2 --check LC.idr` exits 0, accepting `caller` as total.
- `idris2 --check LD.idr` fails with "caller is not total, possibly not
  terminating due to function LA.loop being reachable via LB.viaLoop ->
  LA.loop".

The two `caller`s are the same function, and only the imports differ.

## Expected

Both are refused: totality is a property of what a function reaches,
whatever its module imports.

## Found by

Lane G4 of the checker swarm (`proposals/0003-self-host/checker`),
removing `covering` from `Frontend/Program.idr`'s `program`. The pinned
Idris called `program` total even while `translateIOProgram`, which it
calls, was still `covering`. `Program.idr` does not import `Finite`, which
holds the loop. So a totality claim checked across modules is weaker than
it reads. `tools/policies.txt` and `tests/spec/totality` should not lean on
the checker to find a `covering` callee in an unimported module.

## The fork

`compiler/idris/src/Core/Termination/SizeChange.idr:297` has the same
lookup and the same "Not found" drop, so the fork's totality check of user
programs presumably has the bug too. That is not yet measured.

## Why there is no patch

Recorded now and fixed later: Bjorn deferred upstream fixes found during
other work on 2026-10-16. The likely fix is to resolve the callee through
the whole set of loaded definitions (including those reached through
indirect imports), or to refuse, not drop, a call whose callee cannot be
resolved. That needs reading how the context holds definitions from
modules that were not imported.

## Upstreaming plan

Status: recorded, with a reproducer; no fix. Nothing goes to
idris-lang/Idris2 from here (**Idris**, upstream/README.md).

When it is fixed, all of these land in one change:
- the fix, in the place that reaches the bug:
  - the fork's own code, with its `pull-request.diff` against the pin, if
    the fork has the bug;
  - an `idris.patch` for the stock Idris that builds stage 0, if that
    needs it;
- a `tests/upstream/totality-unimported-callee/` check;
- a PINS.md entry.

Whether to report it upstream is Bjorn's call alone, in his own words.
