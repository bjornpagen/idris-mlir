<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] The inliner drops an argument a body never uses, effects and all

At Idris 2 main 89ba32eb (2026-10-14, the commit third_party/Idris2
moves to; the code is the same at the earlier gitlink 1c630e67c),
`Bug.idr`, built by the stock Idris on Chez, prints `0`, not `7`, and
exits 0 (*measured* at 1c630e67c, audits/p0/design/idris-identity-bug.md).
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

## The fix

`pull-request.diff`, against 89ba32eb:

- `isValue` in `Core.CompileExpr`: an expression whose evaluation can
  only give a value (a local, a lambda, a delay, a constant, an erased
  value, a constructor of values);
- `tryApply` binds each argument it consumes that is not a value by a
  `NotInline` let, outermost first, and the body takes the let's name;
- an unused `YesInline` let is dropped only when its value is a value;
  otherwise it stays, `NotInline`;
- `cexpIdentity` takes a `let` past its value only when the value is a
  value, and a self-recursive call only when its other arguments are
  values.

This follows eager evaluation (AGENTS.md) and costs the stock host's
output some unused dictionary and literal evaluations (*conjecture*,
unmeasured). Not built.

## Why there is no patch

It is recorded, not carried: nothing the stock Idris builds reaches it.
The stock host builds stage 0 (the checker, the frontend, the test runner)
and the benchmarks' Chez baseline, and no `.idr` outside third_party
writes `unsafePerformIO` under `let () =` (*measured*, grep); libs/'s
`LArray` and the rest of `Array.Core` are bodiless `%extern`. The day a
library body with an effectful `let` the body ignores reaches the stock
host, this diff becomes `idris.patch`, which the bootstrap's `idris` step
applies to its copy of the checkout, with a PINS.md entry; until then a
library avoids the shape (the lane rule in the dispatch's common
obligations).

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in his own words, is his call. The report goes when the Idris
pin carries upstream's own fix, or with `tests/upstream-effectful-argument-inline`
showing the pinned Idris prints `7`.
