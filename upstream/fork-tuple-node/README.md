<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A tuple is elaborated once per reading at every level

At the pin, `(l, r)`, `()` and `(x ** p)` with the type of `x` left out
desugar to an alternative of two candidates, the type and the value,
each elaborated in full and nested at each level of a tuple, so a tuple
costs more than its size: 433 s for a 22-tuple under `printLn`
(proposals/0000 D55, measured there).

## The fix

The fork (compiler/idris) carries it as its own code, landed in e5b39cb2
(lane L17, 2026-10-21, unbuilt): the syntax is one node, `ITypeOrValue`,
holding its parts once (`Overlaid`: `PairOf`, `UnitOf`, `DPairOf`), and
its expected type's sort (`Universe`, `Known`, `Unknown`) decides which
reading it is. While the sort is unknown a pair's parts are elaborated
once, against unknowns of their own, and the site waits for the sort; at
the last chance it takes upstream's rule between the two readings. Where
the two readings are different terms (a dependent pair whose name is
bound implicitly or substituted, an idiom bracket, a reflected term), it
is still the alternative of the two.

`pull-request.diff` is that commit's change for this entry, laid out
against third_party/Idris2 at its gitlink (89ba32eb): each hunk is the
change written against upstream's file, without the fork's other
deviations, so that it applies to the pin alone and states exactly what
a re-sync of the fork carries. It was made by merging the commit's tuple
hunks three ways (the fork at e5b39cb2's parent, at e5b39cb2, and
upstream's file) and writing each conflict against upstream's text; the
commit's other changes, the `Delaying` origin in `TTImp/Elab/Case.idr`
among them, are left out. Upstream's files were read at 89ba32eb, each
the blob the other fork entries' diffs name as their base. The
conflicts:

- `TTImp/TTImp/Functor.idr`: e5b39cb2 wrote the node on the named
  functions the fork had then (`mapRawImp`); upstream maps through its
  `Functor` instances, as the fork does again, so the node is a case of
  `Functor RawImp'` and `Overlaid'` has an instance of its own, as the
  fork now writes them.
- `TTImp/Elab/Ambiguity.idr`: upstream's `delayOnFailure` takes the
  expected type as a `Maybe` and tells its elaborator only whether it is
  a retry, where the fork's hands it the expected type normalised again.
  The diff normalises it again in the elaborator, as upstream's
  `checkAlternative` does, and names no delayed-elaboration reference
  (`DLY`), which upstream does not have.
- `TTImp/TTImp.idr`: the import of `Idris.Syntax.Builtin` (the pair's
  names) beside upstream's imports.

Later fork changes to the same lines follow the fork's other deviations
(interned names in 31013e5a, `knownUN KUnit` for `UN $ Basic "Unit"`),
not this entry, and are not in the diff.

## Why there is no patch

The fork is ours: a fix to its upstream code is fork code, recorded in
PINS.md, never a patch the bootstrap applies. The stock Idris, which
builds only stage 0 and the benchmarks' Chez baseline, is not patched.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). The entry goes when a
re-sync of the fork brings upstream's own single node, or never, where
the change is this compiler's subset.
