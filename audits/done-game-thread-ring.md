<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane: Benchmarks Game thread-ring

## What was added

`bench/thread-ring/`, in the flat layout every benchmark has:

- `Main.idr`: thread-ring over the stock Prelude and base (`Data.IOArray`),
  no packages file.
- `main.c`: the C reference, the same algorithm.
- `input`: `50000000`, the game's measured size.

The game specifies 503 threads in a ring passing a token. Threads are
outside this compiler's language, so both files implement the same workload
under a deterministic cooperative scheduler, and the comment at the top of
each file says so. The ring is explicit state: one mailbox per thread
(slot i holds thread i + 1's mailbox). The scheduler visits the threads
round-robin in ring order. A thread whose mailbox is empty is blocked on
its receive and yields. A thread whose mailbox holds the token takes it and
passes it to the next thread, less one. The thread that receives 0 prints
its name. The output is the game's format: the name, then a newline.

## Verification (arm64 macOS, build/dev as it stood)

- `tools/compile.sh --num-threads=2` compiles it. The C reference builds
  with the pinned clang, as `bench/run.sh` builds it (`-O2`, target CPU,
  `-ffp-contract=off`, the link flags from `--print-link-flags`), with no
  warnings under `-Wall -Wextra`.
- Small sizes 0, 1, 502, 503, 1000 and 12345: both programs print
  `n mod 503 + 1` (1, 2, 503, 1, 498, 274). 498 for n = 1000 is the game's
  published reference output.
- Game size 50000000: both print `292\n`, byte-identical (`cmp`), which is
  the game's published output for that size.
- `bench/run.sh --runs 1 thread-ring` reports "Outputs agree". Times:
  this compiler 4.122 s, Idris Chez 6.074 s, clang -O2 0.374 s. Compile
  time 3.394 s.

## Compiler bug found (SUMMARY §5, bug 9: idr-rc-exclusive)

The first version kept the ring as a list zipper (threads ahead, threads
behind in reverse, `reverse` at the end of each lap), which is the more
natural form for a ring in Idris. It does not compile:

    idris-mlir: internal error: 'idr.yield' op idr-rc-exclusive: gives a value of
    '!idr.own<!idr.box<!idr.data<"Prelude.Basics.List[Main.Thread]...">>>' where the
    solver proved '!idr.excl<!idr.box<...List[Main.Thread]...>>'

Minimal reproducer (it fails to compile; it never has to run):

```idris
module Main
import Prelude

data Thread = Blocked Int | Holding Int Int

schedule : List Thread -> List Thread -> Int
schedule behind [] = schedule [] (reverse behind)
schedule behind (Blocked i :: ahead) = schedule (Blocked i :: behind) ahead
schedule behind (Holding i k :: ahead) = schedule (Blocked i :: behind) ahead

ring : Int -> List Thread
ring i = if i > 503 then [] else Blocked i :: ring (i + 1)

main : IO ()
main = putStrLn (show (schedule [] (Holding 1 5 :: ring 2)))
```

What bisection showed:

- Without the `reverse behind` clause (`schedule behind [] = 0`), it
  compiles.
- With a list literal as the argument in place of `ring 2`, it compiles.
- With the elements as `Int` or `Maybe Int` in place of `Thread`, it
  compiles.
- Building the ring with an accumulator, or running one lap at a time
  (`pass` returning the reversed list to an outer `run` loop), still fails.
- A `record Thread { name : Int; mailbox : Maybe Int }` fails the same way.

This is the same failure SUMMARY §5 bug 9 lists for
`programs/prelude/every-uninhabited-export` and regex-redux. The reproducer
above is a smaller witness for whoever fixes it. The committed benchmark
works around it inside the language: the mailboxes are an
`IOArray (Maybe Int)`, which is also exactly what the C reference does. No
test or mark was left failing in this scope.

## Deleted, rewritten

Nothing. This lane only created a new directory.

## For a future generator or harness

`bench/run.sh` checks agreement between this compiler and clang, but not
the game's published output. A check against the game's reference outputs
(498 for thread-ring at 1000) would need a per-benchmark small-size
expected file. None exists in the layout today, so none was added.
