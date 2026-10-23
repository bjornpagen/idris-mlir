<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A case block at a delayed type computes its scrutinee eagerly

At the pin (third_party/Idris2 at 1c630e67, the toolchain's
`idris2` 0.8.0-1c630e67c), a `case` or an `if` written where a `Lazy t` (or
`Inf t`) is expected is checked at the delayed type: each alternative is
delayed, and the block itself is not. The block, its scrutinee included,
is then computed where the argument is built, though the program delays
the whole argument.

## Reproduce

`idris2 -o h H.idr && ./build/exec/h` on:

```idris
module Main

partial
boom : Int -> Int
boom 0 = 5

pick : Lazy Int -> Int
pick _ = 1

partial
main : IO ()
main = printLn (pick (case boom 1 of { 5 => 1; _ => 2 }))
```

It exits 1 with `Unhandled input for Main.boom`; `pick (boom 1)` prints
1. `ifThenElse True 1 (if boom 1 == 5 then 2 else 3)` does the same, as
`if` is a case block on Bool. The checker as the working tree had it gives
the same from `idris-mlir`. Measured on arm64 macOS, 2026-10-19.

## Expected

1: an argument at a delayed type is delayed as written, whatever its
form, and `pick` never forces it.

## Found by

tests/every-basics-export, which checks that `ifThenElse` never computes
the operand its condition does not choose.

## Cause

`checkCase` (`src/TTImp/Elab/Case.idr`) passes the expected type to the
case block's function as its return type. Where that type is `Lazy t`,
each alternative is checked against it, and `checkExp` inserts a `Delay`
around each one; the application of the block's function to the scrutinee
gets none. The checked term is `case0 (boom 1)` with `Delay 1` and
`Delay 2` inside `case0`, so the scrutinee is an ordinary argument,
computed before the block is called.

## The fix

A case block written where a delayed value is expected is that delayed
value. `checkCaseExpected`, once the expected type is known (inside the
`delayElab` that waits for it), elaborates a block expected at `Lazy t`
or `Inf t` as a delay of the block, through `checkDelayAt`, the one
elaborator of a delay, which `checkDelay` now also calls: the block is
checked at `t` and wrapped in one `Delay` of the same reason. Any other
expected type is checked as before. An alternative whose value is itself
delayed is forced inside the delay by `checkExp`'s `AddForce`, which
means the same.

A test for upstream's suite was laid out beside the change,
`lazycase001`'s `LazyCase.idr`, whose `pick (case boom 1 ...)` and `ifThenElse True 1 (if
boom 1 == 5 ...)` must print 1 and whose forced blocks must compute their
scrutinee.

## Why there is no patch

There is no `idris.patch`: nothing the stock Idris builds meets the bug.
The Idris that elaborates what this compiler consumes is our type checker
in compiler/checker, Idris's checker copied into our tree, which has the
change as its own code. The stock Idris only builds stage 0 (the checker,
the frontend and the test runner) and the benchmarks' Chez baseline, and
nothing it builds writes a case block at a delayed type whose scrutinee
must not run.

## Testing

`tests/upstream-lazy-case-scrutinee` exits 1 with `unhandled input for
Main.boom` through the unchanged checker, and prints its expected output
through the changed one.

## Upstreaming plan

Status: recorded, not carried; nothing goes to idris-lang/Idris2 from
here. Idris accepts no contribution that arises from generative AI or a
coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report was written with one.
Whether to report the bug upstream is Bjorn's call alone, in their own
words and from their own understanding; nothing here is drafted for it.
The report goes when the Idris pin carries upstream's own fix; the
checker keeps its own, which `tests/upstream-lazy-case-scrutinee` checks.
