<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane: the Benchmarks Game program regex-dna

Scope: the new directory `bench/regex-dna/`. Nothing outside it was edited
(apart from this report). No compiler code was touched, nothing was rebuilt,
and git was not used.

## What was made

`bench/regex-dna/` has the layout every benchmark uses:

- `Main.idr`: the game's regex-dna in ordinary Idris over the stock Prelude
  and `Data.List`, with no packages. It reads all of stdin. It removes the
  FASTA headers and newlines with the pattern `>.*\n|\n`. It counts the
  game's nine variant patterns (`agggtaaa|tttaccct` …
  `agggtaa[cgt]|[acg]ttaccct`) on the stripped sequence and prints each
  pattern and its count. It then replaces the eleven IUB codes in turn, in
  the game's order (`B`→`(c|g|t)`, `D`→`(a|g|t)`, `H`→`(a|c|t)`,
  `K`→`(g|t)`, `M`→`(a|c)`, `N`→`(a|c|g|t)`, `R`→`(a|g)`, `S`→`(c|g)`,
  `V`→`(a|c|g)`, `W`→`(a|t)`, `Y`→`(c|t)`), and prints a blank line and the
  three lengths. The regex engine is the same subset as regex-redux's:
  literals, classes, `.`, `*` and alternation, with a backtracking matcher
  in continuation style and Perl's leftmost-first meaning.
- `main.c`: the same algorithm in C, on one core, in the order of the
  game's single-threaded C entry. It uses POSIX `regcomp`/`regexec`, which
  is what `bench/regex-redux/main.c` uses, so the suite pins no second
  regex library.
- `input-from`: `fasta 5000000`. That is the game's measured size, and the
  same input regex-redux takes.

## Verification

- The fasta generator was built from `bench/fasta/main.c` with the pinned
  clang. For both sizes below the Idris output and the C output were
  compared with `cmp`.
- **fasta 10000**: the outputs are byte-identical, and they match the
  game's published `regexdna-output.txt` (counts 0 3 9 8 10 3 4 3 5;
  lengths 101745, 100000, 133640).
- **fasta 5000000** (the game's size): the outputs are byte-identical and
  match the game's published output for that size (counts 356 1250 4252
  2894 5435 1537 1431 1608 2178; lengths 50833411, 50000000, 66800214).
  This compiler's program took 153.6 s wall and peaked at 4.1 GB RSS. It
  printed nothing on stderr and exited 0.
- **`bench/run.sh --runs 1 regex-dna`** reported "Outputs agree", exit 0.
  Times: this compiler 140.7 s, Idris Chez 134.5 s, clang -O2 13.2 s.
  Compile time 3.1 s.

## Compiler bugs met and worked around inside the language

The first version was regex-redux's program with the IUB table in place of
its replacements. It does not compile, and neither does
`bench/regex-redux/Main.idr` itself with the current `build/dev`.
`bench/regex-redux` is outside this lane, so it was left as it is.

### 1. SUMMARY §5 bug 9: idr-rc-exclusive gives an `!idr.own` yield where the solver proved `!idr.excl`

```
idris-mlir: internal error: 'idr.yield' op idr-rc-exclusive: gives a value of
'!idr.own<!idr.box<...List[Char]...>>' where the solver proved '!idr.excl<...List[Char]...>'
```

Minimal reproducer. It fails to compile and never has to run:

```idris
module Main
import Prelude
import Data.List

subst : Char -> List Char -> List Char -> List Char
subst c rep = go []
  where
    go : List Char -> List Char -> List Char
    go acc [] = reverse acc
    go acc (x :: rest) = go (x :: acc) rest

main : IO ()
main = do
  s <- getLine
  putStrLn (pack (subst (chr 97) (unpack "xy") (unpack s)))
```

What the IR showed (`-mlir-print-ir-after-failure`): specialization makes
`reverseOnto[Char].spec.<h>`, which is `reverse`, i.e. `reverseOnto` with
its accumulator fixed to the constant `[]`. Its exclusive clone
`.spec.<h>.excl.<h>` returns `!idr.excl<List>`. That clone's recursive
call, though, goes to the general clone `reverseOnto[Char].excl.<h>`, whose
signature returns `!idr.own<List>`, and the commit (`Commit.cpp` `meet`)
refuses the yield. The same thing happens when the accumulator is a
`SnocList` and the conversion is `acc <>> []`, or `sx <>> [x]` (the
specializer fixes the `[x]` shape too). It also happens with `List Re`
when the parser accumulates alternatives in reverse.

Without the `reverse` (`go acc [] = acc`) the reproducer compiles. So does
`reverse` of an `unpack` result on its own, and so does `reverse` at the
end of an IO read loop (`readAll` below).

Workaround in the committed program:

- `subst` writes its output front to back, with no accumulator. The first
  argument holds what is still to be written of the last replacement, so
  every cell is in tail position modulo the constructor and the
  replacement is a tail call. The output takes no stack, and no reverse is
  specialized on `[]` in that context.
- The parser is a recursive descent (`parseAlts`/`parseSeq`/`starred`)
  that builds its lists in order. That is fine for patterns this short.

### 2. A new one: the leak verifier refuses a `SnocList`→`List` conversion from inside the parser

```
Main.idr:21:1: error: 'idr.yield' op ends a path on which a value still holds a reference
asList : SnocList a -> List a
Main.idr:26:3: note: called from
  parseAlts : List Char -> SnocList Re -> SnocList Re -> Re
idris-mlir: internal error: 'idr.yield' op ends a path on which a value still holds a reference
```

Reproducer: take the committed `Main.idr` and replace its parser with the
form below. Everything else stays as committed.

```idris
asList : SnocList a -> List a
asList [<] = []
asList (sx :< x) = sx <>> [x]

mutual
  parseAlts : List Char -> SnocList Re -> SnocList Re -> Re
  parseAlts [] cur alts = Alt (asList (alts :< Seq (asList cur)))
  parseAlts ('|' :: cs) cur alts = parseAlts cs [<] (alts :< Seq (asList cur))
  parseAlts ('*' :: cs) (cur :< r) alts = parseAlts cs (cur :< Star r) alts
  parseAlts cs cur alts = let (atom, rest) = parseAtom cs in parseAlts rest (cur :< atom) alts
  -- parseAtom, parseSet as committed
parse s = parseAlts (unpack s) [<] [<]
```

I reduced this toward a smaller program: `Re` with only `Lit`/`Seq`/`Alt`,
and a parser with no `*` or classes. That program fails with bug 1
instead. So the leak error depends on the surrounding program, and the
reproducer above is the smallest one I have that shows it. Its message is
an internal error, a verifier finding on the compiler's own output, not a
refusal of the program. The committed recursive-descent parser avoids it.

## Deleted, rewritten

Nothing. This lane only created a new directory.

## Notes for the rest of the swarm

- `bench/regex-redux/Main.idr` does not compile at HEAD's `build/dev`
  (bug 1, at `subst.go`'s `reverse acc` and at `parseAlts`). Rewriting its
  `subst` and its parser as `bench/regex-dna/Main.idr` has them makes it
  compile. That rewrite belongs to whoever owns `bench/regex-redux`.
- The regex engine (`Re`, the parser, `match`, `countMatches`, `subst`) is
  now in two benchmarks. Every benchmark is one self-contained `Main.idr`
  (`bench/run.sh` copies only that file), so the copy cannot be shared
  without a package. The two copies should stay the same. If they ever
  have to differ, the engine belongs in a `libs/` package.

## For a future generator or harness

Nothing was deleted. The check this benchmark has is `bench/run.sh`'s
`agree` against clang's output. The game's published outputs at 10000 and
5000000 are listed above, and a pinned expected output at a small size
(fasta 10000) would check the program without the C reference.
