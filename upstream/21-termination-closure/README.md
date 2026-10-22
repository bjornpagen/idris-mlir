<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A termination check closes over every path of what it reaches

At the pin (third_party/Idris2 at 1c630e67), `calcTerminating`
(`src/Core/Termination/SizeChange.idr`) checks a function by walking every
unchecked function it reaches through calls, then closing the size-change
graphs of all their calls under composition: for every pair of reached
functions, every distinct graph of every path between them. Only the graphs
from a function back to itself are read (`findLoops`), and only the
function asked about gets a verdict (`checkTerminating`). Two costs follow,
and they multiply:

- the closure grows with the square of what is reached, and more, though a
  path from a function back to itself never leaves its strongly connected
  component, so a call between two components is on no loop;
- the next function that reaches the same code walks it and closes it
  again: a `total` function calling into a large `covering` part of a
  program pays for all of it, and so does every other.

## Reproduce

`Reach.idr`, the shape of `tests/upstream-termination-closure/Main.idr`
with a chain of 160: `covering` functions with no loop, each matching its
first argument and calling one of the next two with its arguments
permuted, and 25 `total` functions that call the first. With the toolchain's (unpatched) Idris,
`idris2 --check Reach.idr` takes 33.8 s (arm64 macOS, 2026-10-10). The
time is linear in the number of `total` callers (chain of 80: 7.5 s with
25 callers, 25.7 s with 100) and grows with the cube of the chain (chain of
160: 64.7 s with 25 callers, on a loaded machine), where both should be
linear.

Found by this compiler's frontend, which asks for the termination of every
definition it translates: its own sources are `covering`, so nothing was
checked before it asked, and from `Core.Context.prettyName` the walk
reached 366 functions and 959 calls, and the closure did not end.

## Expected

The check is linear in what it reaches, but for the loops themselves: the
closure runs over the calls inside components, and a function a check found
terminating is not searched again.

## The fix

The smaller fix, which keeps upstream's closure:

- `insideComponents` finds the strongly connected components of the calls
  the walk collected (Tarjan's algorithm) and keeps the calls inside one.
  The closure over them holds exactly the graphs from a function to one of
  its own component that the closure over every call holds, found in the
  same order: a call that leaves a component never composes into a path
  back to it, and the work list, popped least first, takes the calls inside
  in the same order whatever else it holds. So every verdict, and every
  message's call path, is unchanged.
- `settle` records as terminating each function a successful search
  visited whose verdict no later check could change: every name it refers
  to (with its case blocks', as `totRefs` reads them) is terminating
  already, a primitive, or settled by the same search. A function not
  defined yet, a constructor whose type's positivity is not checked yet, or
  a reference the call graph does not record (under `assert_total`, or a
  guarded `Delay`) to an unchecked function may still become
  non-terminating, and so may everything that refers to one; those are left
  unchecked. A case block is settled with its parent: no call reaches one
  (the parent's graph inlines it), so it is on no loop. `setTerminating`
  goes through `addDef`, which does not add the name to what the TTC saves.
- `addCases` moves out of `calcTerminating`'s `where` so `settle` can use
  it.

With it `Reach.idr` checks in about a second.

## Why there is no patch

There is no `idris.patch`: nothing the stock Idris builds meets the bug;
it only builds stage 0 and the benchmarks' Chez baseline. The Idris that
elaborates what this compiler consumes is our type checker in
compiler/checker, Idris's checker copied into our tree, which carried the
smaller fix as its own code from 96bea9f1 and has since gone further.

Since 31013e5a the checker closes no graphs. Its check finds the
components of the calls it reaches, as the smaller fix does, and decides
each with the size-change search its frontend's verdicts read too
(`loopsTerminate`): from each function, walks are extended a call at a
time, each function keeps only the weakest walks to it, and a walk back
to the function is judged by its powers as it is found, the first that
goes round for ever being the answer (compiler/checker/README.md). Its
verdicts are the size-change principle's, as the closure's are (*read*).
A failed check names the function the closure names, the greatest by
name of those with a loop that goes round for ever; the loop its message
lists is the first such one the search meets, which need not be the one
the closure listed. `settle` is the smaller fix's, with 51's lookups.

## Testing

The checker, whose `SizeChange.idr` was the pin's file before the smaller
fix, checked `Reach.idr` with it in 0.8 s, a chain of 320 with 100
callers in 1.2 s, and the 702 programs of this repository's corpus gave
byte-identical output with and without it (arm64 macOS, 2026-10-09).
Those are measurements of the smaller fix (96bea9f1); the search that
replaced its closure (31013e5a) is not built or run yet (D56).
`tests/upstream-termination-closure` checks a chain of 240 through the
frontend, which the pinned checker does not finish within the step
limit.

## Upstreaming plan

Status: recorded, not carried; nothing goes to idris-lang/Idris2 from
here. Idris accepts no contribution that arises from generative AI or a
coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report was written with one.
Whether to report the bug upstream is Bjorn's call alone, in his own
words and from his own understanding; nothing here is drafted for it.
The report goes when the Idris pin carries upstream's own fix; the
checker keeps its search, which `tests/upstream-termination-closure`
checks.
