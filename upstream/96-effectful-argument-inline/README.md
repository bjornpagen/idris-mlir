<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] The inliner drops an argument a body never uses, effects and all

At Idris 2 main 89ba32eb (2026-10-14, third_party/Idris2's gitlink),
`Bug.idr`, built by the stock Idris on Chez, prints `0`, not `7`, and
exits 0 (*measured* at 1c630e67c, audits/p0/design/idris-identity-bug.md,
and on a scratch build of 89ba32eb on Chez 10.4.1, 2026-10-22).
`set (MkArr d) i x = let () = unsafePerformIO (... prim__arraySet ...)
in MkArr d` elaborates the pattern `let` to a case block whose body is
its first argument and whose fourth argument is the write; inlining the
block drops the write.

## Cause

Call-by-name substitution in `Compiler.Inline`, which eager evaluation
does not license (*read* at 89ba32eb):

- `tryApply` binds each argument to a parameter by substitution
  (`takeFromStack`), so an argument the body never uses is never
  evaluated;
- `eval` of a `CLet _ _ YesInline val sc` with `used First sc < 1`
  substitutes `val` and so drops it; only `NotInline` lets are kept.

`Compiler.Opts.Identity` has its own copy of the fault: `cexpIdentity`
reads a `let`'s body and ignores its value but for the Nat-unsucc case,
and its self-recursive case reads only the argument at the identity's
index; `rewriteIdentityFlag` then marks the function `Inline`, and the
inliner drops the rest. The log shows the write gone after the first
`inlineDef`, before the identity pass runs (`--log compiler:10`).

Our type checker, compiler/checker, has no `Compiler.Inline` or `Opts.*`,
and the frontend reads TT, never CExp, so programs idris-mlir compiles are
not affected; only what the stock host compiles is.

## Why there is no patch

A patch is owed under D121 (the stock host builds stage 0, the checker,
the frontend, the specification, the libraries and the test runner, and
our code there may write an effectful `let` whose value the body ignores),
but none is carried: the two written so far break Idris's own base
library.

- The first (2026-10-21, never built): an argument or unused let value
  that is not a value (a local, a lambda, a delay, a constant, an erased
  value, a constructor of values) is bound by a `NotInline` let, and the
  identity pass looks through only values. *Measured* on a full bootstrap
  of 89ba32eb with it (2026-10-22): base's `Data.Bits` does not finish in
  25 minutes, against 1 s for the stock Idris. While inlining, the
  inliner stands for a variable by a reference to a name it makes up, and
  an implementation's dictionary is a reference to a global or a record
  with a computed field (`oneBits`, a cast of a literal), none of which
  that test calls a value; so every dictionary passed to an inlined method
  is let-bound, the projection no longer reduces, and the records nest in
  one another: after 66 definitions the inlined expressions are 50 times
  the stock Idris's largest.
- The second: references, closures (a function applied to fewer
  arguments than it takes), constructors of such and primitive operations
  that cannot fail are substituted as before, and only a call with its
  arguments, an external primitive, an operation that can fail, a case or
  a force is let-bound. `Data.Bits` then checks, but the base build stops
  making progress a few modules later (after `Control.Monad.ST`; the next
  in its order is `Data.Ref`), its process at 9.6 GB after 27 minutes: an
  implementation that is a function of other dictionaries is a call with
  its arguments, so it is let-bound too, with the same nesting
  (*conjecture* for this module: its expressions were not logged).

So the fix cannot be a test of the argument's form alone: the inliner
must keep an effect's evaluation without losing the reduction of a
dictionary's projection, for example by binding an argument only where
the body drops or duplicates it, or by marking the case blocks a pattern
`let` makes as demanding their scrutinee. Until it lands, an effectful
`let` whose value the body ignores is dropped on the stock host.
`tests/upstream-effectful-argument-inline` checks that the pinned Idris
still prints `0`.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in his own words, is his call. The report goes when the Idris pin
carries upstream's own fix; it becomes a carried `idris.patch`, with its
check turned to expect `7`, when ours is written and verified.
