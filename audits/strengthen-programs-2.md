<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: lane programs-2 (programs g to l)

## Scope and method

- **Owned:** the 68 tests of kind program whose names start with g to l.
  After the merge below there are 66.
- **What changed:** test files only: `Main.idr`/`Prog.idr`, `cases/` and
  `expected`. Nothing in the compiler, the runtime, `libs/` or the harness.
  No git.
- **Where the expected outputs come from.** Each test's stdout comes from a
  model written beside it in Python from the program's own definitions,
  the library's documented rules (`libs/mlir-array/Linear/Vec.idr`'s
  growth, `reserve` and `pop`) and the runtime's documented semantics:
  - Int arithmetic wraps;
  - signed division is Euclidean;
  - a Double cast to an Int truncates toward zero, modulo 2^64
    (`runtime/Doubles/Truncation.cpp`);
  - `getChar` reads one byte, and 255 at the end of input;
  - `getLine` drops `\n` and a `\r\n`;
  - Prelude's `Show` of a pair nests.

  For text, Python's UTF-8 decoder is an independent oracle: it replaces
  each maximal subpart, the practice the Unicode Standard recommends. Each
  model was first checked against the test's existing, reviewed expected
  file, and only then given new inputs. The models are not in the tree.
  The expected files are the specification, and no other implementation
  is asked at run time.
- **Inputs at the edges:**
  - zero, one and empty input;
  - the edges of a byte (0x00, 0x7f, 0x80, 0xff);
  - the 2^62 small-integer edge, the 2^63 sign edge and 2^64;
  - the edges of each UTF-8 length;
  - growth and capacity edges (4, 5, 16, 17);
  - the edges of each clause and literal;
  - for each property, a case on which the property's check must say no.
- **Runs.** Every test that compiles was run with
  `make test only=... threads=2`. The tests that the harness cannot compile
  because of the dump printer's "File name too long" (§5.38) were compiled
  without dumps with `tools/compile.sh --num-threads=2`, to see what lies
  under the dump failure.

## Per test: what it checks now that it did not

Each entry says what is new; "fails" names the compiler bug the test
fails on, before and after.

**Text and characters**
- **getline-ill-formed** (passes).
  - New cases:
    - empty input;
    - `boundaries`: the first and last scalar of each UTF-8 length, U+D7FF
      and U+E000 on either side of the surrogates, U+10FFFF, and an
      interior NUL;
    - and 14 ill-formed classes: a lone continuation byte, overlong 2-,
      3- and 4-byte forms, an encoded surrogate, a value past U+10FFFF,
      the bytes F5, FE and FF, sequences cut short, and a lead byte
      followed by ASCII;
    - `cut-at-end`: a final line with no `\n` that ends inside a 4-byte
      sequence.
  - The oracle is Python's decoder; the reviewed `given` case matched it
    exactly.
- **high-chars** (passes).
  - The program writes each UTF-8 length's first and last character
    (127/128, 2047/2048, 65535/65536, 1114111).
  - The input byte is now one of six cases: 00, 7f, 80, ca, ff, and the
    end of input.
  - ff and the end of input must agree, as the runtime documents.
- **linear-string-iterator** (fails: §5.12 `llvm.call` mismatch, as
  before).
  - New cases: `boundaries` (DEL, U+0080, U+07FF/U+0800, U+FFFF/U+10000/
    U+10FFFF, one- and two-character lines, ill-formed bytes, a cut 4-byte
    sequence) and `no-input`.
  - The model reproduced the reviewed case.

**Guards and crash messages.** Each of the five now reads its operands, so
it pins the guard from both sides, where before one constant crashed:
- **guards-messages-div-zero** (passes).
  - Crashes at a divisor of 0, including 0/0 and the least Int over 0.
  - Euclidean quotients: -7/2 = -4, 7/-2 = -3, -7/-2 = 4, -10/11 = -1.
  - The least Int divided by -1 is itself.
- **guards-messages-cast-nan** (passes).
  - Crashes on NaN and on both infinities.
  - Truncates 3.5, -3.5, 1/3 and -0.5.
  - 2^63 and 1e19 wrap modulo 2^64; -2^63 is exact.
- **guards-messages-array-index** (passes).
  - Reads at 0 and at n-1 succeed.
  - Reads at n, at -1, at 1000 and at 0 of an empty array crash.
- **guards-messages-str-head** and **guards-messages-str-index** (fail:
  §5.12, as before).
  - The head of "", "a", "ab", "λx" and an emoji.
  - The index is checked against the length in characters, not bytes
    (index 2 of 日本語 is 語, index 3 crashes), and -1 and 0 of "" crash.
- **Not merged.** These five state one property and would be one test.
  But the two string guards do not compile (§5.12), and one program
  would hide the three that work. Merge them when §5.12 is fixed.

**Implementations and dictionaries**
- **higher-order-dictionary** (fails: refused as `unsupported (static
  argument)`, as before; done-accept-reject.md).
  - Reads two lines and compares them by the record's implementation, as
    Ints and as Strings: "3" against "03" is True as Ints and False as
    Strings.
  - Five cases: equal, unequal, a leading zero, negative, the extremes.
- **implementation-index-function** (fails: §5.38 in the harness, §5.12
  under it).
  - Cases 0, 1 and -1 (Nat 0, and a negative Int beside it) and 12.
- **implementation-runtime-length** (passes).
  - Cases 0, 1, 4 and 1000.
- **implementation-runtime-scope** (fails: a leak of 1, as before; the bug
  below).
  - Five names: the same name as the other scope entry ("b"), the empty
    name, a long one and a non-ASCII one.
- **implementation-shape-value** (passes).
  - n = 0, 4, 2^62-1, 2^62 and 2^64, across the edge of the small naturals.
- **interface-option-monad** (passes).
  - Each bind's test at its edge: a difference of 0 is kept and -1 stops
    the chain, at the first bind and at the second.
  - fmap over None.
  - ap carrying a value through, and a None through.
- **interface-ring-power** (fails: heap-free, §5.13, as before).
  - The powers 0 and 1, which reach each base case.
  - 3^39 and fib 92, the largest an Int holds.
  - fib 93, past it, wrapped.
- **interface-state-monad** (passes).
  - The start state is read: 100, 0, -11 (which ends at 0), max-11 (which
    ends at max) and max-10 (which wraps to min).

**Numbers**
- **integer-bits** (passes).
  - New `word-edges` case: Data.Bits at bit 62 and bit 63 on either side
    of 2^62, ±2^62, -1, 2^63, 2^63-1 and 2^64, and shifts by 0, 63 and 64
    at those edges.
  - `no-input`.
  - Python's integers model base's infinite two's complement, and the
    model reproduced the 39 reviewed lines.
- **literal-match** (passes, heap-free).
  - Before, the program was one constant sum that never took the 0
    clause. Now it classifies the input byte, and the byte less one, at
    runtime: 0, 1, 2, 7, 249, 250, 251 and the end of input (255).
  - So each literal matches only itself, and its neighbours and -1 take
    the default.
  - The output is one fused line, so the program is still heap-free.
- **lazy-double** (passes).
  - n is read: 0, 1, 40, 61, 62, 63, 64 and 100.
  - The values cross 2^62 and 2^64.
  - At n = 100 an unmemoized force is 2^100 additions, so losing the
    sharing is a timeout, not a slow pass.
- **growing-specialization-function** (passes).
  - 2^n applications for n = 0, 1, 5 and 20.
- **hot-loop** (passes).
  - Inputs 0 (which prints 0), 1, '7' and 255, with stdout from the
    model's closed sum.

**Laziness and loops**
- **laziness** (passes).
  - Two lines whose unchosen branch divides by zero at the selector at
    hand (0 on one line, 1 on the other), so each line is checked at both
    selectors.
  - Selectors -1, 0, 1 and 4.
- **lazy-elements** (fails: leak, as before).
  - n = 0 (no output), 1, 3 and 9.
- **lazy-branch-loop**, **lazy-list-branches**, **latent-loop**,
  **latent-loop-delay** (fail: leak, as before).
  - These four are one runtime function in four compile shapes, so their
    expected files are one model's.
  - n = 1, 2, 3, 5, 6, 7 and 9: searches that start at the end, find
    nothing, find one index, and find both.
  - Not merged: each is a regression of its own compile shape.
- **latent-loop-accumulator** (fails: leak, as before).
  - n = 2, 3, 5, 6, 7 and 9, including a sum of -1 (`Just (-1)`, in
    parentheses).
- **let-after-output** (passes).
  - The digit 0 crashes after "first"; 1, 5, 9 and '/' (-1) print both
    lines.
  - The comment grew a line, so the crash site moved to `Main.idr:9:1`.

**IORef and IOArray** (each fails on its leak, as before: §5.10, and the
bug below). Each count is read from the input now; before, these four
were constants:
- **ioref-closures:** 0, 1 and 1000 steps (0 is the identity).
- **ioref-counter:** 0, 1 and 100000.
- **ioref-record-in-place:** 0, 1 and 1000000 rebuilds.
- **ioref-keeps-old-value:** 0, 5 and 1e9.
- **ioarray-ends:** n = 0, 1, 2, 5 and 100000.
- **ioarray-sieve:** n = 0, 1, 2, 3, 4, 25, 49 (p*p = n must be marked),
  100000 and 1000000. The model counts primes by trial division.
- **io-loop-through-helper** (fails: §5.11, a crash after main).
  - `no-input` passes.
  - `buffer-edges`: records of 0, 16, 17 and 33 characters, the record
    buffer's growth edges, after text before the first `>`, with a final
    record that has no newline.
  - It also crashes after main (exit 139, 11 live cells), so §5.11 does not
    need a large input (new evidence).

**Layout**
- **layout-counted-fields** (new; passes): a merge of
  layout-255-counted-fields, layout-256-counted-fields and
  layout-512-counted-fields, which are deleted.
  - It is one property at three edges of the header's 8-bit slot count:
    254 fields unboxed into a 255-slot cell, 256 fields, and 512 fields,
    a count whose low 8 bits are 0's.
  - Each record now holds its own strings in its first and last fields and
    in fields 253 to 256, and every node's are read back. Before, every
    field was the same string and only the spine was counted, so a slot
    read from the wrong place could not show.
  - Inputs '0' (an empty tree), '1', '3' and '9'.
  - One compile instead of three, about 10 s.

**Linear lists (leet)** (all pass; their mlir.expect files are unchanged
and still hold)
- **leet-insertion-sort.**
  - The count, sum and sum of squares of the input and of the sorted list
    are printed, and must be equal (a permutation check).
  - The order check on the unsorted input says False: the check can
    fail.
  - n = 0, 1, 2, 250 and 3000.
- **leet-max-subarray.**
  - A brute force over every contiguous part, on a plain List of the same
    values, is a second implementation that must agree.
  - An all-negative list gives -1.
  - The empty list gives the starting best.
  - n = 0, 1, 5000, 10000 and 100000.
- **leet-merge-sorted.**
  - The merge's count and sum are printed.
  - The order check on evens put before odds says False.
  - n = 0, 1, 2, 10000, 20000 and 100000.
- **leet-partition.**
  - A `partitioned` check holds of the result and is False of the input.
  - n = 0, 1, 8000, 16000 and 100000.
- **leet-remove-duplicates.**
  - The result is strictly increasing, which is False of the input with
    its runs.
  - n = 0, 1, 2, 12500, 37500 and 100000.
- **leet-relink-in-place.**
  - n = 10000, 12345, 12500, 20000 and 40000:
    - removing the k-th from the end of an empty list, of a list shorter
      than k, and at k = n (the head);
    - rotating by a multiple of the length;
    - the palindrome check on lists of length 1 and 2.
  - Every n is at least 10000, because rotate takes its count modulo the
    length and would divide by zero on an empty list.
- **leet-valid-parentheses.**
  - "", ")", "(]", "][", "([]{()})" and one with a bracket left unclosed.
  - n = 0, 1 and 50000.
- **list-length** (passes): cases 0/0 and 1/1 beside the constant-stack
  case.

**Linear data**
- **linear-catch-all** and **linear-nested-match** (pass).
  - n is read: 0 (only the leaf), 1 and 2 (which reach each clause
    first), 10 and 1000.
- **linear-library-lists** and **linear-lollipop** (pass).
  - n = 0, 1, 30 and 1000. At 1000 the hash wraps, and the three forms of
    the lollipop must still agree.
- **linear-ambiguous-let** (passes).
  - The size is read: 0, 3, 2^62 and 2^64, a big natural.
  - Both measures are printed on one line. On two lines, a big k leaked
    one cell: the bug below.

**Linear arrays.** None of these 11 compiles today.
- Seven are refused as `unsupported (polymorphism)` (§5.19):
  linarray-bubble, -fill-sum, -map-fold-traverse, -push-pop,
  -read-past-size, -reserve and -write-past-size.
- Four fail on the dump printer (§5.38) in the harness and, without
  dumps, on §5.8, "'linalg.generic' op consumes a view": linarray-
  combinators, -lanes-exact, -lanes-wide and -rows-crash-order.
- So their new cases come from the models alone. Each model reproduced
  the test's reviewed case first (CHECK), except for map-fold-traverse
  below.
  - **linarray-push-pop:**
    - n = 0: no push, one pop that gives Nothing, capacity 0;
    - 1, 4 and 5 (the growth from 4 to 8);
    - 10, 16, and 17 (the growth from 16 to 32).
  - **linarray-read-past-size:**
    - n = 0, 1, 4 and 8 (full: the read at the size meets no spare
      slot), 5 and 9.
  - **linarray-write-past-size:**
    - n = 0 (a pop of nothing), 1 (both writes out of range), 2, 3 and 5.
  - **linarray-reserve:**
    - k = 0, 1 and 3 (the room the vector already has);
    - 4 (grows to twice), 9, 10 (to the size and the room) and 100.
  - **linarray-fill-sum:** n = 0, 1, 2 and 100000.
  - **linarray-bubble:** n = 0, 1, 2, 3 and 2000.
  - **linarray-map-fold-traverse:**
    - k = 0, 1, 7 and 1e9;
    - **its expected file was wrong:** see the bug list below.
  - **linarray-combinators:** n = 1, 2, 10 and 1000.
  - **linarray-lanes-exact:**
    - n = 0, 1 and 2 (the indices whose residues 32-bit lanes get wrong);
    - 3, 7, 8, 9, 16 and 17 (lane-count edges);
    - 1001.
  - **linarray-lanes-wide:**
    - `empty-and-one`;
    - `square-past-32-bits`: offsets ±46340 and 46339, either side of the
      largest square that fits in 32 bits, and 65536;
    - `past-32-bits`: offsets 2^31-1, -2^31 and 2^32;
    - the given two runs.
  - **linarray-rows-crash-order:**
    - `one-row`, `column-zero`, `empty` and `no-columns`, which reach
      neither zero and print their sums;
    - `div-first` (3 rows of 1 column), where the `div` at row 2 comes
      first and must be the crash. Before, only the `mod` crash was
      tested, so a run that crashed on whichever zero came first in any
      order could not be told apart.
- I dropped an n = 0 crash case for linarray-combinators: its crash site,
  inside Prelude's `Cast Double Int`, cannot be predicted without a run.

**Left as they were**
- hello: the smoke test.
- loads-untrusted-unreached: an acceptance test with no input space.
- **impossible-branch** and **indexed-tags** did gain one runtime choice
  each (both pass, still heap-free):
  - impossible-branch: the kind is read, and a `Maybe (IsSmall k)` decides
    it, so Large reaches the code and still never the impossible clause;
    cases S, L and no input;
  - indexed-tags: a tag whose index is erased, chosen by the input; cases
    0, 1 and no input.

## Compiler bugs found, and test bugs fixed

1. **New, reduced: a heap value used by two IO actions of a do block is
   never freed.**
   - Input: `main = do { line <- getLine; let k = the Nat (cast line);
     printLn k; printLn k }`, with stdin `4611686018427387904` (a big
     Nat, so a heap cell).
   - Expected: `idris-rt: live cells 0`. Got: `live cells 1`.
   - With 5 (a small Nat, not on the heap) it is 0. With a single
     `printLn k` it is 0.
   - The same holds for a tree:
     - `let t = build n s` used by `printLn (count t)` twice leaks 2n
       cells;
     - one `printLn (count t + count t)` leaks none.
   - A String let-bound and used by three `putStrLn` actions leaks 1.
   - It plausibly explains these leaks in this lane, each of which has a
     heap value used by more than one IO action (not each reduced):
     - ioref-closures, n+1 cells (the closure f, used by two printLn);
     - identity-weakening, 7/13/25/247 cells for k = 0/1/3/40 (t, used
       by three actions);
     - implementation-runtime-scope, 1 cell (x, used by three);
     - ioref-keeps-old-value, 3 cells (old and new, used by three).
   - It is probably the common root of much of SUMMARY §5.10, whose
     reading names only memo cells and IORef writes.
   - It showed up while strengthening:
     - layout-counted-fields, and its three predecessors, when the tree
       or its string was printed by two actions;
     - linear-ambiguous-let, when a big k was printed twice.
   - Both tests now print once, so they stay about their own property.
     The reproducer, with its tree and string variants, is in this lane's
     scratchpad (exp/leak2, exp/leak3) and needs a test of its own.
2. **Heap-free fails as soon as main does more than one IO action after
   reading input.**
   - A do block that reads a byte and then makes two or more `putChar`
     calls allocates `idr.cell.new` in `main.delay` and in the `(>>)`
     lambda. A recursive getChar loop allocates in `io_bind`'s lambda.
   - Found while making literal-match read its input. The test now makes
     one fused output, which is heap-free.
   - This is §5.13's family: interface-ring-power fails on it, as before.
3. **§5.12 (`llvm.call` operand mismatch) has a new trigger.**
   - In leet-insertion-sort, adding `same : (Int,Int,Int) -> (Int,Int,Int)
     -> Bool`, a `&&` of Int `==`, makes the compile fail with this error.
   - A small program alone with the same function compiles, so the
     trigger depends on the rest of the program.
   - The test now prints both stats tuples instead.
   - Also: an `==` on a tuple of Ints specializes to a symbol too long for
     the dump printer (§5.38).
4. **Test bug fixed: linarray-map-fold-traverse expected `(12, 12345, [2,
   3, 4, 12, 13, 14])`.**
   - Prelude shows `(a, b, c)` as `(a, (b, c))` (Prelude/Show.idr:210),
     which the compiled leet-insertion-sort and latent-loop-accumulator
     print.
   - The expected file had never been checked, because the program never
     compiled. It is now `(12, (12345, [...]))`.
5. **§5.11 needs no large input.** io-loop-through-helper's new
   100-character `buffer-edges` case also crashes after main (exit 139, 11
   live cells). The empty input does not.
6. **Confirmed under §5.38:** without dumps, the four linarray fixtures
   that the dump printer fails fail on §5.8 ("consumes a view"), and
   implementation-index-function fails on §5.12.

## Runs

`make test only=<the 66> threads=2`, on the build in build/dev, after the
changes: **34/66 pass**.

- Every failure is a compiler bug named above, and none is a wrong
  expected stdout. On every case that runs, stdout is as expected. Where
  a test fails, the harness reports only stderr (live cells), a crash
  after main, a compile failure, or heap-free.
- At the start, the same tests gave 36 of 68. layout-counted-fields
  replaces three that passed, which accounts for the difference.
- No test that passed before now fails.
- `make check`: the failures are other lanes' check scripts. None names a
  test of this lane.
