<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: lane fixtures-2

Scope: the dialect fixtures named `e2e-*`, `effects-*`, `expect-*`, `fold-*`,
`func-*`, `guards-*`, `identity` and `loops-*` (102 fixtures). 82 were
strengthened; 20 `expect-*` and `effects-*` fixtures were left as they are
(listed at the end, with why). Nothing outside these tests was edited.

## The forms used, one way each

- **Fold against run** (every `fold-*` table, every `guards-fold-*` but
  `unguarded`). The table of rows is written twice, in one module: `@rows`
  yields a row's operands, chosen by the byte read, and `@at_run_time`
  applies the ops to them; `@folded` applies the same ops to each row's
  constants inside the row, where the folders run. The root calls
  `@folded`; `sed 's/idr.call @folded(/idr.call @at_run_time(/'` makes the
  run form, and `%differential %t.run.mlir %s` holds the two to the same
  stdout and exit on the byte of each row (declared `// STDIN:` lines, one
  per row, the empty input for the default row, which keeps each fixture
  at a few seconds instead of 257 runs). Each row prints its operands too,
  so that an operand has two consumers and case-of-case cannot move the op
  into the rows of the run form, where it would fold and the comparison
  would be fold against fold. (While the tables were built, a FileCheck of
  the run form after the optimizer showed exactly that in two fixtures:
  an operand with one consumer folded in the rows. That check is not kept,
  since the repository rule dialect-text forbids FileCheck of module text
  and no idr-expect property says an op is still there; the construction
  is kept, and each comment says why.) Two more lines keep the oracle
  honest:
  - `folded=@folded` (added to the fixture's canonicalize line): every row
    did fold;
  - a planted wrong fold: a one-row `sed` mutant of the folded form, and
    `not %differential ... | FileCheck` naming the row's input, so each
    table is shown to see its rows.
  For the scalar ops the oracle is a second implementation (the folder's
  APInt code against the lowering's arith ops); for bigs and strings it is
  the runtime at run time against the runtime at compile time, which
  checks the folders' conversions and refusals.
- **A reference program** (effects-*, loops-*): where the fixture's claim
  has a run-time consequence, a hand-written module of `// REFERENCE:`
  lines, which computes the answer another way (closed forms, tables, no
  call or guard to move), is the oracle: `%differential %s
  %t.reference.mlir`, and again after the pass under test. The reference
  follows the module in the file (see the harness defect below).
- **Translation validation of a pass the pipeline does not run**
  (`--int-range-optimizations`, `--sccp`, `--control-flow-sink`,
  `--loop-invariant-code-motion`): `%differential %s %t.after.mlir` is a
  real check only for these. For a pass in idris-mlir's own pipeline, both
  sides of a differential run that pass, so a fixture's module against its
  own pass output compares the pipeline with itself; I did not add such
  lines where they would check nothing, and used a reference instead.
- **Oracle tests** (expect-*): each property's fixture now holds a case it
  holds of and one it fails on, and at the property's edges (n - 1, n,
  n + 1 for counts and bounds, set order, a name one character off).

## Per test: what it checks now that it did not

### fold-
| test | now also checks |
| --- | --- |
| fold-division | 17 rows: divs/mods on each sign, MIN, MAX, -1, 1, MIN/MAX against each other; divu/modu past 127; a zero divisor of each kind (both crash); fold = lowering |
| fold-shift | 17 rows: amounts 0, 1, w-1, w, past w, negative, MIN, MAX; shls/shrs on i64 and on i8 read signed, shlu/shru on i8 |
| fold-to-char | 16 rows: 0, 127/128, both surrogate ends and neighbours, U+10FFFF and +1, -1, MIN, MAX, a value whose low 32 bits are a character, i8 read both ways |
| fold-to-int | 19 rows at i64/i32/i8: fractions, -0.0, subnormal, 2^63, -2^63, 2^64, 1e300 (wraps to 0), NaN and -inf (both crash) |
| fold-big-shift | 21 rows: 2^62 edges, 2^63 edges, >1 word, amounts 0, ±1, 64, 4096, past a word (on 0); the existing function renamed `@shifts` |
| fold-nat | 12 rows: add, mul, cmp lt/eq, pred, from_big, to_big at 0, 1, 2^62±1, 2^63, 2^64±1, 10^30 |
| fold-pred | 14 rows of pred at 1, 2^62±1, 2^63, 2^64±1, 10^30 (never 0, which no program reaches) |
| fold-string-offsets | 20 rows: every offset in and around a 2- and 4-byte character, the end, past it, negative, MIN, MAX, the empty string, a 3-byte character first |
| fold-strings | 8 rows of pack/concat and the built strings' lengths; the known leak is now the last line, so the differential and the mutant run |
| fold-balanced | 11 rows of append (with its length, so it is built), reverse, neg; `folds-balanced` now covers every row's folds |
| fold-add-zero | the identity fold of x + 0 / 0 + x (Integer and natural, the natural's left zero is new) against the runtime adding a zero no fold knows, at the 2^62, 2^63, 2^64 edges |
| fold-data | the layout read at run time: tags of a two-constructor sum, a match on it, record fields (MIN, MAX, "é"), list head/tag/tail tag |
| fold-array-dim | the extent of arrays made at run time (sizes -3, -1, 0, 1, 2, 5, 1000, MIN, -2^62) against the folded clamp |
| fold-closure | a closure built at run time and applied, against the constant closure; wrapping sums |
| fold-range | `%differential` of `--int-range-optimizations` on all 257 inputs, printing every comparison; the root reads a signed byte; two near misses a bound one inside the range does not decide (`returns=..._/_`) |
| fold-sccp | `%differential` of `--sccp`; a near miss `@first` whose field is read at run time (`returns=@first:_`, `reads-fields`) |
| fold-poison-fields | the near miss: the same constructor of a constant word builds nothing (`builds-nothing=@wrap_constant`) |

### guards-
| test | now also checks |
| --- | --- |
| guards-fold-in-bounds | 14 rows: 0, last, length, -1, "", 2- and 4-byte characters (index counts characters), MIN, MAX; folded decision = run-time guard |
| guards-fold-nonzero | 10 rows: divisors 1, -1, 2, MIN, MAX, bigs at the 2^62/2^64 edges, zero of each kind |
| guards-fold-nonempty | 8 rows: one character of 1, 2, 4 bytes, longer, "" |
| guards-fold-finite | 13 rows: ±0.0, subnormal, max finite, 2^63, odd past 2^53, 1e300 as a big, ±inf, NaN with payload and sign |
| guards-fold-range | 14 rows: ends at and past the size, empty ranges at start/end/past end, negative offset and count, MIN, overflowing ends |
| guards-fold-unguarded | the near miss: the same 11 ops on the nearest accepted constants all fold (`returns=@satisfying:-4/3/1/1/-2/...`) |

### e2e-
| test | now also checks |
| --- | --- |
| e2e-crash-callsite | seven location forms, one input each (callsite caller, plain, named, span start, fused, callsite callee, unknown → no site); the crash line is the program's whole output (`--implicit-check-not={{.}}`); a non-crashing input |
| e2e-doubles | 30 values: both ends of the positional range (largest below 1e-3, 1e-3, largest below 1e10, 1e10), subnormal ends, max, 1e23, 2^53+1, NaN of both signs, ±inf; expected lines computed from the documented rule, exact output |
| e2e-eval | closed calls at the base, one past it, 20! (largest that fits), 21! (wraps), dashes of 0 and of "" |
| e2e-exit-42 | statuses 0 and 255 (both ends), 256 and -1 crash with `main returned N, which is not an exit status (0 to 255)` and print nothing else |
| e2e-loops | the three counting loops on a bound read at run time: 0, 1, 2, 3, 4 (each remainder of the step) and 10^6 (stack); the whole output exact |
| e2e-put-list | inputs "y" (no crash, its own string), 0xe9 (two-byte UTF-8 in both lists), end of input (U+00FF); exact stdout and stderr |
| e2e-statuses | an unknown option is status 2 and leaves a stale output untouched; a successful compile replaces a stale output, links and runs |

### effects-
| test | now also checks |
| --- | --- |
| effects-alloc | facts of every string/big builder (`[move delay]`, 17 ops) and every reader (`[move delay merge]`, 10 ops, `nat.to_big` among them) |
| effects-crash-call | run: output before the crash, nothing after, against a reference, as written and after canonicalize/cse/control-flow-sink; planted wrong reference |
| effects-div | run: a guard crashes only on the branch or loop that runs it, all 8 bit choices, after control-flow-sink and LICM too; planted reference that speculates the guard |
| effects-crash | run: each kind of refused guard (index, empty, zero, NaN, inf, negative index) still crashes with its result unused, after canonicalize/cse; planted reference |
| effects-io | run: BBAA on 0–3 byte inputs (forged-world writes and reads kept), after canonicalize/cse/sink; the known facts line moved last |
| effects-memo-label | run: a memo forced twice crashes on 0, gives 1 1 otherwise; `effects=@forces_twice:crash` |
| effects-forced-labels | run: by-name forcing writes "11" before the crash, before and after defunctionalization; planted reference writing "1" |
| effects-force-strict | run: a forced cell of @boom crashes, of @seven gives 14 |
| effects-inlined-proof | run: 0 on 0, 1, 2, 255, empty, as written and after `--idr-optimize`, `--idr-contify` |
| effects-queries | facts of a match whose arms only compute (`[drop move delay merge]`) and one with an unproved call (`[delay]`) |
| effects-loop | near miss: the same effect-free loop whose result is used stays (`loops=@used:1`) |
| effects-long-cycle | callers of the ring inherit (`@entry:crash`), its callees do not (`@leaf:none`) |
| effects-read-past-drop | a third split, a read both regions use, gives no error; the two errors are the only ones |

### func-
| test | now also checks |
| --- | --- |
| func-call-effects | facts of calls holding io, diverge, crash+diverge, io+crash |
| func-call-effects-contain | the error names what the call lacks (diverge of crash+diverge; crash where io is held); supersets hold |
| func-call-effects-cse | calls of a crashing function stay, unread and equal ones included |
| func-call-type | argument 1 mismatch, zero arguments, a grade mismatch (borrow for owned) at the owned stage |
| func-linear-twice | a region may leave the value unused; a use before a match and one inside, and uses in nested regions, are refused at the match (the verifier's stated location) |
| func-owned-not-consumed | consumed once holds; twice is refused at the second drop; once on one path of a match only is refused at the match |
| func-two-blocks | the one-block body that ends in ub.unreachable, in the body or a match region, holds |

### loops- and identity
| test | now also checks |
| --- | --- |
| loops-accumulate | run: every accumulated function's value (n, 3n, n+5, n, 2n, n, n, 0, 0) on n = 0, 1, 2, 7, 10^6, before and after idr-accumulate; `not-called` restated as `calls-only=@f:[]` (the root now calls them); planted reference |
| loops-tail-loop | run: echo, count, sum of squares, list sum, fib (n mod 16), until's stop, on 12 bounds around each period, before and after idr-rc + tail-loops; @spin made unreachable at run time; planted reference |
| loops-trmc | run at the owned stage: the copy of [1..5] sums 15, length 5, @depth all 0, the linear copy 0, as written, after idr-trmc and after tail-loops |
| loops-trmc-counter | run: replicate and take (all, past the end, half) on n = 0, 1, 2, 3, 10^6, before and after the loops |
| identity | near miss `@bump` (one more than its argument) keeps its calls; the line of functions that keep calls now runs before the line that fails on the known bug |

### expect-
| test | now also checks |
| --- | --- |
| expect-allocation | holds of static data (`@static`); a string built fails (`@appends`) |
| expect-apart | holds of a fused function and a third; a function is not apart from itself; an absent function fails |
| expect-computes-nothing | a function that only returns its parameter holds |
| expect-constant-stack | a two-function musttail cycle holds; a cycle with one frame-keeping call fails, at that member |
| expect-continuations | the holding side: after `--idr-contify`, `contified` holds |
| expect-counted-loop | nested counted loops hold; a counted beside a tested loop fails at the tested one |
| expect-crash-sites | exact count at 1, 2, 3; calls are no place before lowering (the oracle's stated scope) |
| expect-dims-known | asking a given array's extent beside a made one holds |
| expect-facts | a guard and a call of a guarding function are `[delay]` |
| expect-folded | a refused guard and a call of constants are not asked to fold |
| expect-guards | two guards give two errors |
| expect-largest-function | the bound is inclusive: 7 holds, 6 fails |
| expect-linker-names | the holding side (module without bad names); `_` and digits allowed; space and non-ASCII refused |
| expect-lowered | the holding side of `in-llvm` and module-wide `lowered` |
| expect-malformed | eight more argument shapes refused (returns, call-order, signature, loops, apart, negative bound, negative count, one unknown effect among known) |
| expect-memory | a load and a store: reads, writes and two unaligned accesses |
| expect-not-called | a function the module never had holds; a self-calling one fails |
| expect-output-fused | a string also measured is still written in pieces, so fails as written and holds after canonicalize (module-wide) |
| expect-paths | the loop count is exact on both sides (0 and 2 for 1) |
| expect-proved | a total function calling an unproved one still holds `total` |
| expect-reaches | a direct callee, a self-recursion reaches itself, a leaf does not |
| expect-returns | `returns-on-paths` in either order; an extra written constant no path returns fails at the function |
| expect-signature | the holding side of `entry` |
| expect-solved-effects | a set in any order is the same; one of two effects is not it |
| expect-stage | fails against each of the four other stages |
| expect-unknown | names one letter short, of another case, one character long, are unknown |
| expect-words | a natural outside the loop is no value of the loop |

## Runs

- Baseline (before): `make test-idr only='e2e- effects- expect- fold- func- guards- identity loops-' threads=2`: of my 101, all passed but effects-io, fold-strings and identity (the three known bugs below).
- After: the same command: 119/126 (the selection also matches tests of
  other lanes and the script e2e-even-group). Failing: effects-io,
  fold-strings and identity, each only at its known bug's line (below);
  expect-coverage (a script, not mine: the leftover `typed-reads` row, as
  before); defunc-capture-field, defunc-memo-by-name, defunc-tag-limit
  (other lanes', failing before too).
- `make check`: 32/33; only file-size fails (C++ units over 400 lines,
  not this lane's). dialect-text passes; during the lane it flagged the
  module-text FileChecks above (removed) and `--check-prefixes=` in
  e2e-loops (rewritten with one prefix per FileCheck).

## Compiler bugs found or pinned

1. **The string folders over-release** (SUMMARY §5 item 15), now measured:
   each fold of `idr.str.pack` or `idr.str.concat` over a non-empty
   constant list leaves the folders' count at -1, independent of the
   list's length (1, 2 or 3 elements, chars or strings); an empty list
   leaves 0; `str.append` leaves 0. fold-strings' 8 rows give -15 under
   `--idr-contracts` in `--idr-optimize`. Test: fold-strings, RUN 5 and 6
   (`expected folds-balanced: -15 cells`, `contract folds-balanced broken
   by idr-optimize`). The fold-versus-run differential of the same rows
   holds: the folded strings are right, only the count is wrong.
2. **`idr.world.new` answers "may be delayed"** (§5 item 16), unchanged:
   effects-io's facts line. New: its run-time consequence does not show
   with today's passes: the program writes BBAA, as written and after
   canonicalize, cse and control-flow-sink.
3. **The identity analysis misses `@carry`** (§5 item 23), unchanged:
   identity's last line. Its other side (the near miss `@bump`, @loops,
   @drift, @flip keep their calls) now runs before it and holds.
4. **A root named `@main` cannot be lowered** (new, minor): a verified
   program whose root is `@main` stops at `internal error: idr-entry: @main
   names a symbol already` (found making effects-io runnable). The
   frontend always qualifies the root (`Main.main`), so no Idris program
   reaches it; but the verifier accepts the module and a later pass treats
   it as an internal error, not a refusal. Fixtures root at `@Prog.main`.

No test fails on anything but items 1–3.

## Harness defects found (not this lane's to fix)

- **`lit_lowered` reads a fixture's stage from the first line of the file
  that mentions `idr.program ... stage(...)`, comments included**
  (`harness/lib/differential.sh`, `sed -n 's/.*idr\.program
  .*stage(...)/p' | head -n 1`). A fixture whose comment holds another
  program (a `// REFERENCE:` module at stage first above a module at stage
  owned) is lowered from the wrong stage (`idr-knots runs on a program at
  first, not owned`). Every reference here follows its module, which
  avoids it; the parse should read the module's own op.
- **lit substitutes `%s` and `%t` inside SSA names in RUN lines**: a `sed`
  mutant naming `%str`, `%twice` or `%two` gets the file path spliced in.
  The names here avoid the prefixes; lit's substitution of `%t` and `%s`
  should stop at an identifier character.
- **dialect-text's orphan check reads `--check-prefix=` only**, so a
  RUN line with `--check-prefixes=A,B` makes A's and B's lines orphans;
  either the rule reads the plural form or the vocabulary says to use the
  singular (e2e-loops now does).
- **`%differential` against a pass that idris-mlir's pipeline runs
  compares the pipeline with itself**: BEFORE is compiled by the pipeline,
  which runs that pass too. It validates only passes outside the pipeline,
  hand rewrites, and two forms of one program; README's "translation
  validation of a pass is two lines" holds only for those. This lane used
  references and run forms instead.

## Left as they are

- effects-array-memref-effects, effects-idr-effects: two-sided already,
  every function of a lattice case; a run needs forged arrays or a world
  no root has.
- expect-by-name, calls, closures, counting, does, fused, growth, in-place,
  moves-out, narrowed-lanes, one-clone, placement, quantities,
  resets-unshared, reuses-every-cell, structured-loops, tests-nothing,
  vectorized: each already holds its property's holding and failing case
  in the oracle's own fixture; the owned-stage ones would need hand-made
  graded IR for each new case, beyond a few seconds of value each.

## For the next lane

- The fold tables are written twice (run form and folded form) by
  design: two forms that must agree, the differential catching any drift
  between them. A generator in the harness (Sem's table) would write them
  once; the shape here (`@rows`, `@at_run_time`, `@folded`, the root swap,
  per-row STDIN) is the one it would emit.
- `crash-sites` counts a call of a never-returning function only after
  lowering; its row comment in Lookup.cpp reads as if before too.
