<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: lane programs-1 (programs a to f)

Scope: the 68 tests of kind program whose names start with a to f, but
not bounded-*. Only those tests were edited; nothing of the compiler, the
harness or another lane's tests. No git command but `git show` (read, for
the pre-change programs) was run.

## How the expected files were made

No expected file was copied from the compiler's output. Each was written
from the program's meaning: by hand where it is short, and otherwise by a
Python model of the program written from its source and the runtime's
documented semantics (the text of a double, `runtime/Doubles/Printing.cpp`;
`cast` from String, `runtime/Numerals/Reading.cpp`; truncation of a double;
Euclidean `div`/`mod` of Integer; buffers as little-endian bytes; getChar's
255 at the end of input). Where a test already had a case, the model was
first checked to reproduce the old expected file exactly (action-forced-
twice, bubble-sort, cast-from-string, char-list-*, double-*, every-io-
export, file-*, foldlm-deep, every-num-export's first line), and only then
used for the new inputs. Each program was then compiled without dumps and
run on every case; a disagreement was investigated until it was either my
model's error (fixed) or a compiler bug (below, the test kept).

Where a program fails to compile today on a known bug, the new lines were
compiled on their own in a scratch program, so the expected values are
checked against the compiler wherever it can build them.

## Per test: what it checks now that it did not

Verdicts are from `make test only=<these 67> threads=2` after the
change: 34 pass, 33 fail. "Fails on" names the bug, numbered as in the
next section, or SUMMARY §5 where it is a known one.

| test | cases (was) | what it checks now | verdict |
| --- | --- | --- | --- |
| absurd-body | 3 (1) | `get (A k)` on a byte read at run time (0, 128, 255 at the end of input), beside the closed call | fails on heap-free only (bug 6, §5.13) |
| action-forced-twice | 6 (1) | n = 1, 2, 3, 5, 8, 9: both branches of `twice` (k > 5 at n = 9), forced chains of every depth; Python model reproduces the old case | fails on leaks only (§5.10), stdout right |
| arity-raising | 5 (1) | 0 (only liftoff), 1, 3, 9, and the end of input (207 lines) | pass |
| array-of-arrays | 5 (1) | 0 (no row), 1, 2, 4, 9; the diagonal is 11 n(n-1)/2 | fails: bug 2 (n = 0 segfaults after main), leaks (§5.10) |
| auto-runtime-argument | 9 (1) | the `n > 2` boundary (2, 3), 0, 1, negative, empty line, no input, not a number, 40 | pass |
| base-trace | 2 (1) | trace runs after the output before it and before the line it is in, and never in the untaken branch; the branch is chosen by input | fails on bug 4 (trace of a run-time string leaks) |
| bits8-past-127 | 9 (1) | program changed: the byte is the line's length mod 256, so the cases cross 0, 1, 127/128, 200, 255/256, 383/384; `i > 127` agrees with `b > 127`, and the Nat and Integer forms agree | pass |
| bounds-back-edge, bounds-negative-index, bounds-negative-size, bounds-unrelated-size | 8 each (1) | n = 0..5, 1000 and no input: each program's crash happens exactly where the access is outside the array, and every case where it is not (n = 0, or n < 2 for unrelated-size) runs to the end | fail on leaks only: the hand-built ArrayData stays live when main returns (1 cell, §5.10 class); every crash case holds |
| bounds-mixed-calls, bounds-one-past | 8 each (1) | as above; these crash on every n, including 0 | pass |
| bubble-sort | 6 (1) | n = 0, 1, 2, 3, 300, 1500; new line: the result has the input's length and sum (a permutation) beside sorted; digest from a Python model that reproduces 300's | fails to compile (§5.12, before and after) |
| buffer-bytes | 1 | writes of 256 and -1 as Int (modulo 256), 128 at the first byte; each write touches only its byte | fails on leak only (§5.10) |
| buffer-ops | 1 | each width at its extremes (Bits64 all ones, Int64 least) and at the last offset it fits (Bits16 at 30, Bits32 at 28), read signed and unsigned; final bytes from a little-endian Python model of the whole program | fails: bug 3 (segfault after main, before and after the change) behind the dump-name failure |
| buffer-range | 7 (1) | program changed: the offset is read, so a 2-byte word at 0, 1, 2 is read and at 3, 9, 207 and -1 crashes | fails on leak only in the non-crash cases (§5.10 class) |
| call-pattern | 4 (1) | n = 0, 1, 5, 9: ack 3 n = 2^(n+3) - 3 | pass |
| cast-from-string | 1 (1; 40 lines, now 78) | 38 new strings: empty, signs alone, -0, +0, -0x0, 127/128/255/256, ±2^62, ±2^63, 2^64, 0xFFFFFFFFFFFFFFFF, 2^53 + 1 (ties to even), 1e400, ±1e-400, INF, Infinity, -nan, 1.0e, 0o8, 0b, 1.5E3; a Python implementation of Reading.cpp's documented grammar reproduces the old 40 lines | fails on bug 5 (-0 as Double) |
| char-list-pipeline, char-list-accumulated | 7 each (1) | empty input, text with no record, bodies of exactly 8 and 17 characters (chunk ends), adjacent and empty records and a header at the end of input, letters outside ACGT; four generated lines instead of three, so the accumulated program's reversed order shows (the generator's lines are L1 L2 L1 L2) | pipeline: leaks (before and after); accumulated: fails to compile (§5.9, before and after) |
| chars | 8 (1) | constants at each end of the surrogates (55295/55296, 57343/57344) and U+10FFFF; bytes 0x00, 0x5F (last below the surrogates after + 55200), 0x60 (first in them), 0x7F, 0x80, 0xFF, end of input | pass |
| clock-monotonic | 1 | 100000 readings in a row, each not earlier than the one before | pass |
| closed-calls | 4 (1) | n = 0 (fib 0, gcd = 1071), 1, 2, 9 | pass |
| closed-char-to-string | 1 | every end of UTF-8's lengths: U+0000, U+007F, U+0080, U+07FF, U+0800, U+FFFF, U+10000, U+10FFFF | pass |
| closed-double-text | 1 | merged from closed-double-infinity and closed-double-subnormal: inf, -inf, nan, overflow to inf; ±5e-324, 1e-323, largest subnormal, smallest normal, largest double | pass |
| closed-integer-shift | 1 | shifts across 2^62 and 2^63 of each sign, 2^64 right by 1, amount 0, a negative amount past 2^62 | pass |
| closed-literal-conversion | 1 | Int literals by FromString in hex, past 2^63, grouped, and one with a space (0); Double texts each side of 1e-3 and 1e10 | pass |
| closure-result-roundtrip | 3 (1) | x = 0, 4, and 207 (end of input) | fails: hangs on every input (before and after; three cases keep the test inside its 300 s) |
| crash-div-zero | 4 (1) | program changed: the divisor is read, so 0 crashes before anything is printed, and 5, -1, 207 print then crash on the closed call | pass |
| crash-integer-shift-huge | 1 | a shift by 2^6 past a word is printed first, so the output before the crash is kept | pass |
| crash-mod-zero | 6 (1) | program changed: the divisor is the byte read + 1, so 256 (end of input, byte 255) crashes, and divisors 1, 3, 7, 255 print then crash on the closed call | fails on heap-free only (bug 6, §5.13) |
| deep-recursion | 7 (1) | 0, 1, 2, 3, no input, 2000000 (model reproduces 1000000's) | pass |
| dependent-pair-family-eta | 1 | Empty, and Full at each outcome of the comparison (LT, EQ, GT), built at the unexpanded family | pass |
| double-basics | 5 (1) | 0 (inf, nan, -inf, signed zeros), 1 (1e19 cast wraps), 7, 9, 207; libm lines held to a few ulp | fails on heap-free (§5.13, before and after) |
| double-cast-nan | 3 (1) | the crash happens only on NaN: 5 and 207 print 1 and 1 | fails on heap-free (§5.13, before and after) |
| double-infinities-nan | 4 (1) | 0 (everything NaN), 1 (x 1.7e308 still finite), 2 (past the largest), 7 | fails on leak (before and after), stdout right |
| double-subnormals | 4 (1) | 0 (NaN), 1, 7, 9 | fails on leak (before and after), stdout right |
| double-ties | 4 (1) | 0 (NaN), 1, 7, 9 | pass |
| enum-stepping | 7 (1) | stepN on a byte read: n = 0, 1, 6, 7, 13, 254, 255 give n mod 7 | pass |
| environment-arguments | 1 | set without overwrite keeps the value, with overwrite replaces it, an empty value, unset of a set name | fails to compile (§5.12, before and after) |
| erased-argument-to-a-variable | 4 (1) | empty line, no input, a 5000-character line | pass |
| erased-elem-later-match, erased-elem-match | 1 | Here at the first, second and third target, a target of 0 (the Z branch); the cut path's targets, not only their number | pass |
| erased-field | 1 | erased at a function type, Type, Void and List Nat, beside Int's extremes | pass |
| erased-index-forced-index | 1 | start and len each 0 and not | pass |
| erased-witness | 4 (1) | the functions on a byte read (0, 9, 128, 255) | fails on heap-free only (bug 6, §5.13) |
| every-basics-export | 1 | the truth tables of && and \|\|; && , \|\| and ifThenElse never compute the operand the first decides (a partial function that crashes on it) | fails on bug 1 (a lazy argument's case is computed) |
| every-cast-export | 1 | Integer, Int and Nat casts across 2^62 each way (checked alone: they agree) | fails to compile (§5.12, before and after) |
| every-eqord-export | 1 | 0.0 == -0.0, NaN unequal to itself and GT both ways, max with NaN, "" and non-ASCII string order, Bits64 max vs 0, Int min vs max, Integer across -2^62 (checked alone: they agree) | fails to compile (§5.12, before and after) |
| every-io-export | 4 (1) | no input (getLine "", getChar '\255' written as ÿ), two newlines, no final newline; Python model reproduces the old case | fails to compile (§5.12, before and after) |
| every-num-export | 1 | Integer's arithmetic across 2^62 and -2^62 (13 operations each, Euclidean div/mod) | pass |
| every-primio-export | 3 (1) | no input, a 4097-character line | pass |
| every-show-export | 1 | -0.0 and (-0.0), inf, (-inf), nan at App; Integer at 2^62, bracketed when negative | fails to compile (before and after; the new lines alone hit §5.12) |
| exit-with | 5 (1) | program changed: the status is the digit read (1, 3, 9, 207), and on 0 main returns | pass |
| file-bytes-echo | 8 (1) | empty input, 1, 7, 8, 14 bytes (the chunk is 7), all 256 byte values, 30001 random bytes | pass |
| file-lines-eof | 7 (1) | empty input, one line with and without its newline, one and two empty lines, a 10000-character line | pass |
| foldlm-deep | 6 (1) | 0, 1, 249999, 250000, no input | pass |
| for-long-list | 4 (1) | 0, 1, no input | fails on 1000000 only (§5.14, before and after) |
| forever-until-crash | 5 (1) | no input, one line, no newline, empty lines | pass |
| fused-stored-string | 6 (1) | bytes 0, 0x61, 0x7F (one UTF-8 byte), 0x80, 0xC3 (two) | pass |

Unchanged and failing as before: every-builtin-export, every-interfaces-
export, every-ops-export, every-uninhabited-export (dump names, compile
timeout, §5.12, §5.9).

## Merged

- `closed-double-infinity` and `closed-double-subnormal` are one property
  (a Double primitive applied to literals means the runtime's text) over
  different literals: now one test, `closed-double-text`, with the
  specials (inf, -inf, nan, overflow to inf) and the ends of the
  subnormals and of the range. The two directories are deleted; only
  audit reports named them.

Not merged, with the reason:
- `double-infinities-nan`, `double-subnormals`, `double-ties`: the same
  shape, but double-ties passes and the other two fail on leaks of
  `show (Just d)`; merged, the tie checks would be hidden behind that leak.
- the six `bounds-*`: six different index tests, each its own program.
- `crash-div-zero`, `crash-mod-zero`: two primitives' guards.

## Unchanged, with the reason

- `every-builtin-export`, `every-interfaces-export` (already has the empty
  structures and the laziness of `and`/`or`), `every-interpolation-export`,
  `every-ops-export`, `every-prelude-export`, `every-uninhabited-export`:
  each line already checks the value its contract fixes, and their exports
  have no edge a new value would cross.

## Compiler bugs found

New, each with a reproducer that stands alone:

1. **A lazy argument holding a `case` computes its scrutinee eagerly.**
   Test: every-basics-export, line `ifThenElse True (the Int 1) (if boom 1
   then 2 else 3)`. Expected `1`; got the crash `unhandled input for
   Main.boom`, exit 1. Reduced:

       partial
       boom2 : Int -> Int
       boom2 0 = 5
       pick : Lazy Int -> Int
       pick _ = 1
       partial
       main : IO ()
       main = printLn (pick (case boom2 1 of { 5 => 1; _ => 2 }))

   prints nothing and crashes; `pick (boom2 1)` and `pick (boom2 1 + 1)`
   print 1, and so does `False && boom 1`. A crash is an effect, so the
   scrutinee may not be moved out of the delay.
2. **array-of-arrays on stdin `0`** (an `IOArray (IOArray Int)` of size 0,
   main ending in the `| Nothing =>` branch of a pattern bind): prints `no
   row`, the live count, then jumps to address 0 on the program's thread
   (EXC_BAD_ACCESS, exit 139). n >= 1 exits 0.
3. **buffer-ops returns into a stack address after main** (EXC_BAD_ACCESS
   at 0x16fdfd8a0, exit 139), before and after this change; the dump
   tree printer's "File name too long" hid it. Reduced (with `import
   Data.Buffer`): `Nothing <- newBuffer (-1) | Just _ => ...; putStrLn
   "negative"; Just buf <- newBuffer 32 | Nothing => ...; setBits16 buf 1
   0x0102; setBits32 buf 3 0x04030201; setBits64 buf 8
   0x0807060504030201; setInt8 buf 0 (-1)`. Removing any one statement
   makes it exit 0 (each still leaking 1 cell), so it reads as a stack
   overwrite, not as one operation's fault.
4. **`trace` of a run-time string leaks one cell.** base-trace, case
   a-line: `line <- getLine; putStrLn (trace "x" line)` ends with `live
   cells 1`; with a literal value (`trace "traced" "hi"`) nothing is live.
5. **`cast "-0"` to Double is -0.0; Reading.cpp documents 0.0.** Its
   comment: an integer literal's "value is exact; ... Double the nearest
   double, as fromInteger does", and the integer -0 is 0. The decimal
   path (fast_float) keeps the sign, and so does the based path
   (`-0x0`). cast-from-string pins the documented 0.0; if -0.0 is meant,
   the documentation is what changes, and these two lines with it.
6. **Heap-free holds or not in the same program shape** (§5.13). After
   `c <- getChar`, `printLn` of an Int made from c allocates
   (`idr.str.show_sint`, `idr.str.append` in `main.lam` or `main.delay`)
   in absurd-body, erased-witness and crash-mod-zero, while enum-stepping
   and crash-div-zero, written the same way, are heap-free. All three
   passed before, with only closed values printed; their cases all hold.

Known ones these tests now also show (SUMMARY §5):
- leaks, §5.10: action-forced-twice (1 to 185 cells, growing with n),
  the four bounds-* programs' non-crash cases (the ArrayData, 1),
  buffer-range's non-crash cases (the Buffer, 1), buffer-bytes,
  char-list-pipeline (172 on its given input), double-infinities-nan (3),
  double-subnormals (1);
- §5.12 (`llvm.call` operand mismatch): bubble-sort, environment-
  arguments, every-cast/eqord/io/show-export. Smallest reproducer met:
  `main = putStrLn (showPrec App (the Double (-0.0)))` (also at App for
  Integer, NaN, -inf; `show` alone compiles);
- §5.9 (idr-rc-exclusive gives `!idr.own` where it proved `!idr.excl`):
  char-list-accumulated; smallest met: `main = printLn [a && b | a <-
  [False, True], b <- [False, True]]`. every-basics-export's truth tables
  are written as tuples so as not to depend on it;
- closure-result-roundtrip hangs on every input; for-long-list's million
  exhausts the stack (§5.14).

## Notes for the orchestrator

- Empty case directories are not kept by git. Mine have an empty
  `expected-stdout` where they would be empty (for-long-list/no-input).
  Three of other lanes' tests have one: sequence-deep/cases/no-input,
  traverse-deep/cases/no-input, when-unless-loops/cases/no-input.
- Crash sites moved only where a comment line was added: double-cast-nan
  (Main.idr:10:1), crash-div-zero and crash-mod-zero (Prog.idr:7:1), each
  read from the run and checked to be the definition the guard is in.
- `make check`: 25/33; the eight failures (dialect-text, driver-shape,
  emit-dialects, facts-in-types, file-size, frontend-imports, mlir-layout,
  zones) are other lanes' witness work, none names a file of this lane.

