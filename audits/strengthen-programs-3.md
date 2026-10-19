<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: lane programs-3 (programs m to z)

Scope: the 79 tests of kind program whose names start with m through z,
the six of suite test-mlir-tools among them. Only those tests were edited;
nothing of the compiler, and no git command was run.

## Result

- 72 of the 79 were changed; after two merges they are 70 tests. 7 are
  unchanged, with the reason below.
- Merges (one property, one program, more cases):
  - `records-nested-past-the-cell` went into `records-past-the-cell`. Both
    were "a record spread over a cell holds more counted references than
    its header counts". The one program now builds both lists, the flat
    one (257 references per cell) and the nested one (3840), from one
    digit, with cases 0, 1, 3, 4 and the end of input (207 cells).
  - `vect-runtime-length-accumulator` and `vect-runtime-length-match` became
    `vect-runtime-length`: one instance for every runtime length, whether
    the recursion ends on a counter or on a match three constructors deep.
    Cases 0, 1, 2, 3, 5, 10, 1000 and no input.
  - No other test in the lane refers to the three deleted names.
- Where expected output was not obvious, it comes from an oracle written
  for the lane, in the scratchpad, never from the compiler's run:
  - nbody: the same double operations, in the same order, in IEEE
    arithmetic. It reproduces the committed 1000-step case exactly.
  - prelude-math and vect: the same operations, plus a copy of the
    runtime's Double layout (`runtime/Doubles/Printing.cpp`: positional
    for exponents -3 to 9, else `d.ddde-x`). They reproduce the committed
    case 5 exactly.
  - memo-shared-stream: Int arithmetic modulo 2^64 (Prims' `wrap`).
  - postponed-lambdas, registry-nat-operations, nat-large and
    mutual-io-if-case-with: small models of each program. Each reproduces
    the committed case.
- A case with no `stdin` is the end of input, which getChar reads as 0xff
  (character 255). It is used as an edge throughout. So is the byte `/`,
  which is digit -1 for the programs that read `ord c - 48`.

## Runs

Every changed test was run with `make test only=... threads=2` (the
upstream six with `make test-mlir-tools`) after its last edit.

- **Pass (41):** map-deep, memo-lazy, missing-case, mixed-widths,
  multi-module, mutual-io-if-case-with, mutual-pure-tail-calls,
  named-implementations, nat-loop, nat-sum, negate-fixed-width,
  partial-cast-pointer, partial-divergent-call, prelude-getline,
  prelude-input, prelude-math, records, registry-identity-hook,
  runtime-choice, runtime-closure-growing-choice, self-forcing-caf,
  sequence-deep, shapes, shared-result, show-rose-breakers,
  sortedmap-one-ord-two-ways, specialize-growing-accumulator, spin-atom,
  stack-exhausted, state-monad, totality-past-depth, type-level-shapes,
  vect, vect-runtime-length, when-unless-loops, with-application-scope,
  and the five changed upstream-* tests. The test-mlir-tools suite is
  5/5.
- **Fail, every case's stdout as expected, only on a known compiler bug:**
  - live cells at exit (§5.10): memo-shared-stream, method-runtime-implicits,
    nat-large, postponed-lambdas, records-past-the-cell,
    registry-nat-operations, replicate-take-deep,
    runtime-lazy-value-growing-choice, split-prefixes, st-sum;
  - heap-free (§5.13): nbody, recursive-string;
  - idr-narrow's word-loop: nat-parity;
  - split-prefixes' tests-nothing.
- **Fail at compile, on a known bug.** These cases cannot be run until the
  bug is fixed. They come from the oracles above.
  - the `llvm.call` mismatch (§5.12): polymorphic-recursion-swapped,
    registry-pointer-handles, sorted-set, sortedmap-map-after-insert,
    sortedmap-opaque-key, string-loop-one-value-twice, string-pack,
    string-primitive-runtime-match;
  - idr-rc-exclusive's yield (§5.9): sortedmap;
  - idr-rc's owned verifier: thunk-consumes-list;
  - the abort in `ownership::readFrom`: transpose-last-two-axes;
  - `unsupported (polymorphism)` (§5.19): vec-pop-then-push.

  registry-pointer-handles and sorted-set fail at compile both as they were
  and as changed. Each version was recompiled without dumps to check:
  `tools/compile.sh --num-threads=2` gives the same `llvm.call` error.
- **Fail with a wrong stdout or a timeout (§5.20, §5.14), with new evidence:**
  stream-take, stream-take-before, traverse-deep (see Bugs).
- **New compiler bug:** show-dependent-pair (see Bugs).
- `make check`: 26/33. The seven that fail are dialect-text, driver-shape,
  emit-dialects, facts-in-types, file-size, rules-covered and zones. They
  are other lanes' work in progress (planted witness/near-miss lines, a
  `static argument` rule, the C++ file size), and none of them reads a file
  of this lane.

## Per test: what it checks now that it did not

| test | now checks |
| --- | --- |
| map-deep | n = 0, 1, 2 and no input (empty list through map), beside 10^6 |
| memo-lazy | each forced constant's value after the first force: l0 = 1; l18 = 10^18, below 2^62; l19 = 10^19, past 2^63; l20 = 10^20, past 2^64. Small-to-big crossings in Nat addition |
| memo-shared-stream | seeds 0, 5, 9 and end of input (207): the 88th element at s·F(89), below 2^63 at 5 and wrapped modulo 2^64 at 9 and 207 |
| method-runtime-implicits | results write each argument in its own digits, so swapping any two arguments changes the output (the old sum `v+d+k+n+b` could not see a swap of d and n); qGen called directly with k ≠ 0 |
| missing-case | both covered inputs in both orders ("12", "21": "not reached" printed); a crash on the first read with no output (3, 0, end of input); a crash on the second read after output (1 then end of input). Each cause is checked whole |
| mixed-widths | each field of the four-width constructor read back at its own width, at each width's least, greatest and greatest+1 (wrapped); Bits64 at 2^64-1 and 2^63 |
| multi-module | the imported recursion's base clause (count 0) |
| mutual-io-if-case-with | n = 0, 1, 2, 3, 999999, 1000001, 1000002 and no input, from a model of the three functions; constant stack on the large ones |
| mutual-pure-tail-calls | 0, 1, no input, and 10^7+1 (odd) beside 10^7 |
| named-implementations | each implementation chosen in a branch picked by an input byte (0, 1, -1, end of input), not only by a constant |
| nat-large | bases 0 (pred 0 = 0, compare EQ, `S (pred 0) /= 0`), 1, 3 (3^62), -1 (cast to 0) and 207 (207^62) |
| nat-loop | 0, 3·10^6 steps, and a negative Int cast to Nat (0) |
| nat-parity | the input now decides the parity (n = d·10^8 + d): odd at 1, even at 0 and 2, and 0 for -1. Before, every input was even, so the first line could not fail |
| nat-sum | m = 0, 900, and negative (0) |
| nbody | 0 steps (both energies equal), 1, 20000 and no input, from the IEEE oracle |
| negate-fixed-width | 0, the greatest, the least and 2^(w-1) at each width, for 23 values where there were 10 |
| partial-cast-pointer | stdout's and stderr's handles beside stdin's (none null after the round trip) |
| partial-divergent-call | the end of input (≠ '9'); collatz's base case |
| polymorphic-recursion-swapped | depth 0, and a depth read at run time (0, 1, 8, -1 → 0, 207): even depths keep the order, odd ones swap it |
| postponed-lambdas | n = 0, 3, 9 and -1: every Left/Right/Nothing branch of all twelve lines, the IO `for` printing 0, 1 or 2 "small", and negatives shown with parentheses inside Left and without in a list |
| prelude-getline | end of input (0 lines); an empty first line ending the loop; "\r\n" alone; no final newline; a trailing '\r' kept when no '\n' follows; "\r\n" then "\n" |
| prelude-input | end of input (six 255s); the bytes 0x00, 0x7f, 0x80, 0xff, 0x01 (0xff reads as 255, as the end does) |
| prelude-math | n = 0 (no picture; the signed zero in `-0.0 + -0.125i`), 1 and 2, from the oracle |
| records | the two widths now take separate digits (1406), so an error in one cannot cancel one in the other (the old sum 14+6) |
| records-past-the-cell | merged, above: both cell shapes at 0, 1, 3, 4 and 207 cells |
| recursive-string | the digit boundaries 0, 9, 10, 99, 100, 255 |
| registry-identity-hook | bytes 0 and 255 |
| registry-nat-operations | d = 0, 1, 9, -1, from a model (integerToNat clamping, minus truncating, compare, foldr mult) |
| registry-pointer-handles | getEnv after a refused overwrite, of an empty value, after unsetEnv, and of a variable never set (null handle) |
| replicate-take-deep | 0, 1, 3 (take of half rounds down), and 10^7+1 |
| runtime-choice | "aa", "ba", "a\0" (the list of length 0 at both positions), end of input |
| runtime-closure-growing-choice | levels 0, 1, 2, 3, 20, 40, 41: the function doubles every second level, 2^20 and 2^21 applications at the top |
| runtime-lazy-value-growing-choice | levels 0, 1, 2 and 255 (1 + ⌈n/2⌉) |
| self-forcing-caf | a lazy value that forces another twice prints twice before the knot crashes: the crash is specific to self-forcing, and output before it is written |
| sequence-deep | 0, 249999 (nothing printed), 250000, no input |
| shapes | the Circle branch too (12042) |
| shared-result | the left walk ('a') and end of input beside 'b' |
| show-dependent-pair | the empty vector, and a negative element (no parentheses inside a list) |
| show-rose-breakers | depths 0, 1, 30 and no input |
| sorted-set | the empty set; delete of an absent element; a difference with itself; and a property over 2000 drawn numbers in [-250, 249]: the elements strictly increase, every drawn number is contained, 492 distinct (oracle), least and greatest. The property is shown failing beside it (a list out of order, 251 never drawn) |
| sortedmap | the empty map's lookup, keys and delete; delete of an absent key; an empty build |
| sortedmap-map-after-insert | map over a map with one key inserted twice (the second value kept), and over the empty map |
| sortedmap-one-ord-two-ways | -1, 0, no input, and Int's greatest, whose successor wraps to the least and sorts first |
| sortedmap-opaque-key | n = 1 and 0 (colliding keys: the later value kept), -3 (negatives in the descending order), 7 (insert overwrites) |
| specialize-growing-accumulator | 0, 1, end of input (207000 steps) |
| spin-atom | end of input |
| split-prefixes | empty input; a header with no newline; a header only; digits only; exactly one chunk of 4; 4 + 1 |
| st-sum | sumTo 1 and sumTo 0 (a thread that only reads its reference) |
| stack-exhausted | inputs whose recursion fits (0, 10, 1000, no input): the recursion's value (from a model), not a crash, so the crash is the stack's and not the program's |
| state-monad | zero ticks returns the initial state unchanged |
| stream-take | the count is read at run time: 0, 1, 10, 100, no input |
| stream-take-before | the bound is read at run time: 0, 1, 40, 64 (equal is not past), 2^61 (sum 2^62 - 1) |
| string-loop-one-value-twice | a line that is not "go", the empty line, "gone" |
| string-pack | characters of 4 UTF-8 bytes (U+1F600) and the last scalar value U+10FFFF through pack and fastUnpack, shown as `'\128512'`; fastUnpack of ""; empty fastConcat and fastPack |
| string-primitive-runtime-match | alternatives that are prefixes of each other ("9"/"97", "25"/"255") and of equal length ("97"/"98"), each reached: tab, nul, b, end of medium, end of input, and two that fall through |
| thunk-consumes-list | k = 0 (forced where made) and 9 |
| totality-past-depth | the empty list, a list at each depth exactly, and one past it |
| transpose-last-two-axes | k = 0, 1000, no input |
| traverse-deep | 0, 49999, 50000, no input |
| type-level-shapes | 0, 1, 1000, no input (count is 10 + 3k) |
| vec-pop-then-push | the empty word |
| vect | x = 0, 1, 9, -1, from the oracle (sum is base's left fold, foldr a right one) |
| vect-runtime-length | merged, above |
| when-unless-loops | 0 and no input (nothing); 1; 250000 and 250001 (the two loops' bounds: `<` against `<=`) |
| with-application-scope | the three with-recursions from a count read at run time (no input, 1, 1000), beside the constant 5 |
| upstream-constructor-implicit-mark | C3's implicit A takes the first clause, F the second |
| upstream-erased-constant-pattern | the constant clauses match (h 0 = 1, tp Integer = 1, pv (MkP 0) = 1, len [] = 0): the pattern is a match on both sides, not a variable |
| upstream-erased-coverage-nested-match | g Z = 1, fp [] = [], Pick True = Nat |
| upstream-evaluator-char-text | '"', NUL, DEL, U+1F600 and U+10FFFF, each its own text |
| upstream-relevant-implicit-split | the empty list, and one with negative and zero elements (sumF 2, count 3, wb False) |

Unchanged, and why:
- **main-private-in-import:** stdout is already exactly the contract
  ("main", not "helper").
- **nonterminating:** it is compiled only; it states no run.
- **registry-scalar-bytes:** it is already exhaustive over every scalar
  value.
- **tail-loop-deep, void-field:** a closed constant whose one value is the
  contract.
- **unreachable:** any added case would be invented coverage.
- **upstream-termination-closure:** the contract is how long the checker
  takes on a fixed chain.

## Compiler bugs found

1. **New: two dependent pairs, one with an empty vector, fail in idr-rc.**
   - Test: show-dependent-pair.
   - Input (no stdin):

     ```idris
     main = do
       printLn (the (n ** Vect n Int) (2 ** [1, 2]))
       printLn (the (n ** Vect n Int) (0 ** []))
     ```

   - Expected: `(2 ** [1, 2])` then `(0 ** [])`.
   - Got: `idris-mlir: internal error: 'idr.match' op leaves a value with 0
     references on one path and 1 on another` (note: `loc("arg")`).
     Under the harness, the tree printer's "File name too long" lines hide
     it.
   - Each pair alone compiles and prints right, and so do `(2 ** ..)` with
     `(1 ** [3])`. So the failure is the empty vector beside a non-empty
     one.
2. **New minimal form of the leak (§5.10): a string read by getLine and
   used twice leaves one cell live.**
   - Program:

     ```idris
     main = do
       line <- getLine
       printLn (the Int (cast line))
       printLn (the Int (cast line))
     ```

   - On stdin "5\n" it prints `idris-rt: live cells 1`; used once, 0; on
     an empty line, 0.
   - Shown in the suite by records-past-the-cell case 0: its string feeds
     both lists, and 1 cell is live with no list built.
   - vect-runtime-length parses its line once, so its property stays
     separate from this bug.
3. **The records leak grows with the input (§5.10).**
   - records-past-the-cell: live cells = 4k + 1 for k cells of each shape
     (k = 1 gives 5, 3 gives 13, 4 gives 17, 207 gives 829).
   - Each list leaks two per cell, as the two old tests did separately
     (2k + 1 each).
4. **Other leaks that grow with the input (§5.10):**
   - replicate-take-deep leaks n cells for n elements (n = 1 gives 1,
     3 gives 3, 10^7 gives 10^7; 0 gives 0);
   - runtime-lazy-value-growing-choice leaks about n/2 (n = 97 gives 48,
     255 gives 127);
   - nat-large leaks 1 only when p is past the small range (bases 2, 3,
     207; not 0, 1, -1);
   - st-sum leaks 1 per runST (3 for three).
5. **Streams (§5.20), new evidence.**
   - stream-take, `sum (take n (countFrom 1 (+1)))`: n = 0 and 1 give 0
     and 1, right; n = 10 gives 40 (expected 55), n = 100 gives 490
     (expected 5050).
   - stream-take-before, `sum (takeBefore (> b) (powers of 2))`: b = 0 and
     1 give 0 and 1, right, so it ends when the first or the second
     element passes. b = 40, 64 and 2^61 never end (exit 124 at 60 s;
     expected 63, 127, 2^62 - 1).
   - So a run that is right on the first one or two elements goes wrong
     past them.
6. **traverse_ loses constant stack (§5.14), new evidence.** traverse-deep
   exhausts the 1 MiB stack already at 49999 and at 50000 elements, with
   nothing printed. 0 elements is fine.
7. **No new bug** in the oracle-checked numeric programs: nbody,
   prelude-math, vect and negate-fixed-width agree with IEEE and
   two's-complement arithmetic on every new case. This includes the
   signed zero and the modulo-2^64 wraps.

## Notes for the orchestrator

- Case directories were added as files; the merged tests are new
  directories (`tests/vect-runtime-length`) and replacements
  (`tests/records-past-the-cell`). The removed directories are
  `tests/records-nested-past-the-cell`, `tests/vect-runtime-length-accumulator`
  and `tests/vect-runtime-length-match`.
- stream-take-before now costs 3 × 60 s while bug 5 stands: its hanging
  cases run to the harness's timeout. Once the bug is fixed, each case
  takes milliseconds.
