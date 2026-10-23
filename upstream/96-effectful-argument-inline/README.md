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
block drops the write. `Eager.idr` shows the same for an unused `let`, an
argument an inlined function ignores, a constructor's field a match
ignores, and the effectful argument of a recursive call in a function
that is an identity on another argument: the stock Idris prints none of
them (*measured*, same build).

## Cause

Call-by-name substitution in `Compiler.Inline`, which eager evaluation
does not license (*read* at 89ba32eb):

- `tryApply` binds each argument to a parameter by substitution
  (`takeFromStack`), so an argument the body never uses is never
  evaluated; so does a lambda applied to an argument, and `pickAlt`, which
  binds a known constructor's fields to the alternative's variables;
- `eval` of a `CLet _ _ YesInline val sc` with `used First sc < 1`
  substitutes `val` and so drops it; only `NotInline` lets are kept.

`Compiler.Opts.Identity` has its own copy of the fault: its self-recursive
case reads only the argument at the identity's index, and
`rewriteIdentityFlag` then makes the function its argument, dropping the
recursive call's others. The log shows the write gone after the first
`inlineDef`, before the identity pass runs (`--log compiler:10`).

Our type checker, compiler/checker, has no `Compiler.Inline` or `Opts.*`,
and the frontend reads TT, never CExp, so programs idris-mlir compiles are
not affected; only what the stock host compiles is.

## Patch

`idris.patch`, against 89ba32eb: wherever the inliner binds a value to a
variable by substitution (a call's parameters, an applied lambda's
variable, a `let`, a known constructor's fields under a match), a value
the body never uses that is a computation is kept, evaluated before the
body by a `let` the inliner never inlines, the first outermost. A value
that is no computation (a variable, a literal, a lambda, a delay, an erased
argument, a function applied to fewer arguments than it takes, a
constructor or a primitive operation that cannot fail applied to such, or
the force of such) is dropped as before. A recursive call is an identity's
only where its other arguments are no computations.

The two earlier attempts (2026-10-21 and 2026-10-22, never carried) bound
every argument that was not of such a form, used or not, by a kept `let`.
An implementation's dictionary passed to a method is then let-bound, its
projection no longer reduces, and the records nest: base's `Data.Bits` did
not finish in 25 minutes, and the second stalled after
`Control.Monad.ST` at 9.6 GB. This patch binds only what the body drops,
and every value the body uses is substituted as before, so a dictionary's
projection reduces as it did.

What it leaves: a value used more than once is still substituted at each
use, and one used in only some branches of a case still runs only there;
binding those would block the reductions above. A lambda written applied
to an argument is beta-reduced before the inliner sees it, by the
elaborator's normalisation of a right-hand side (`normaliseArgHoles` in
`TTImp.Elab`), which drops an argument the lambda ignores. And a lazy
argument stays unevaluated (`Eager.idr`'s last line), though a pattern
`let` written as the whole of a lazy argument is elaborated with the delay
inside the case block's result (*read* in the log of
`lazily (let () = say "lazy" in 0)`), so the elaborated term evaluates the
`let`'s scrutinee when the argument is passed, and with the patch it runs
there.

## Testing

On scratch builds of 89ba32eb (Chez 10.4.1, 2026-10-22, an 8-core Apple
M2 Max virtual machine at load average about 4): the stock Idris; one with
this patch alone; and one with 96, 104 to 107 and 109. Each built itself
and all its libraries (prelude, base, contrib, network, test, linear,
papers).

- `Bug.idr` prints `7`; `Eager.idr` prints each ignored computation once,
  in order, and not the delayed one (stock: none of them).
- base, built from clean by each Idris against its own prelude
  (`idris2 --build base.ipkg`, 136 modules, `/usr/bin/time -l`), three
  times each: stock 19.22, 19.25 and 19.04 s wall, 298 MB peak resident;
  with this patch 19.48, 19.15 and 19.16 s, 293 MB. Its TTC files are
  0.5% larger (39,848 KB against 39,652 KB). With every Idris patch (96,
  104 to 109) base builds in 19.22 s at 323 MB peak, against 18.95 s and
  302 MB with 104 to 107 alone.
- Upstream's own tests, run as upstream's runner runs them, on the build
  with 96, 104 to 107 and 109: in the groups basic, casetree, coverage,
  error, evaluator, failing, interface, linear, perf, reg, termination,
  total and with, 391 of 392 pass, as without 96 (the one failure,
  `casetree/heuristics001`, is 105's); in the groups that compile and
  run programs, chez, allschemes, base, prelude, codegen and typedd-book,
  147 of 153 pass, as without 96; the six that fail fail alike without
  96 and on the stock Idris (chez and codegen run there too, 60 of 66):
  four chez tests build a C library from the source tree's `config.mk`,
  which the runner's copy of the tests lacks, and two codegen tests print
  the same `rm` complaint. With every Idris patch, 96 and 104 to 109,
  those groups and twelve more pass as they do without 96, 108 and 109
  but for 108's `literate/literate006` (108's README).

`tests/upstream-effectful-argument-inline` checks `Bug.idr` and
`Eager.idr` on the pinned Idris.

## When it goes

When the Idris pin carries upstream's own fix (the check then passes
without the patch). Until then the bootstrap applies the patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call. The patch goes when the pin moves
past upstream's fix, which `tests/upstream-effectful-argument-inline`
shows by passing on an unpatched pin.
