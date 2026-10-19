<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: fixtures-3 (lower-, names-, narrow-, obs-, optimize-, pipeline-, raise-)

77 fixtures owned; 68 strengthened, 9 left as they were (each with its
reason below). Nothing outside these 77 directories was edited.

## The forms used, all the harness's

- `%differential BEFORE AFTER` after the line that makes AFTER: the module
  as written against what the pass (or the chain up to it) made of it.
- A reference program, `// REF:` lines at the end of the fixture, taken out
  by `sed -n 's|^// REF: ||p' %s > %t.ref.mlir` (as obs-lowered-mixed takes
  out its HALFWAY module) and held to the pass's output by
  `%differential %t.ref.mlir %t.mlir`. A reference is a `stage(higher)`
  program that computes the expected output by other means (words, `arith`,
  `put_char` a character at a time, `big.cmp`/`select` where the fixture
  matches): an oracle for meaning that shares nothing of the construct the
  fixture lowers. It sits at the end of the file because `lit_lowered`
  reads a module's stage from the first `idr.program ... stage(...)` line,
  comments included.
- Declared inputs (`// STDIN:`) at the edges where the classes of a byte
  are known (0, 1, 127/128, 255, the end of input, the bounds of an array or
  a buffer, the small range's 2^62 - 1 / 2^62, 2^64, negatives); the full
  byte box (no `STDIN`) where every byte is its own case (recursion depths,
  closures chosen by the byte).
- For a fixture at stage `first` with no closure: the same module said to
  be at `higher` (`sed 's/stage(first)/stage(higher)/'`), compiled whole by
  idris-mlir, linked by `%cc`, run with `printf ... | %t`, and its stdout
  and stderr (a crash's cause and site, `[[#@LINE+1]]`-anchored to the
  guard) checked by FileCheck. This is the absolute check where the
  differential cannot see (it compares stdout and status, not stderr).
- A case on which each new property must fail: a sed-made neighbour that
  the same check refuses (narrow-select-lanes, lower-strided-symbol,
  names-from-keys), or a near miss that must succeed (lower-closure-left,
  lower-internal-errors, obs-foreign-pass-name, obs-lowered-untargeted).
  The reference differential was shown failing by hand on a wrong
  reference (lower-arrays: 2.25 for 2.5 is named on the first input).

## Per test: what it checks now that it did not

### raise- (8): the raised program means the program (%differential)

| test | now |
| --- | --- |
| raise-apply | every byte: 0 picks @sub, 1 @add, the rest recurse |
| raise-builds-actions | every byte (lists of 0 to 255 actions, printed in order); its @read renamed @downFrom, since a program may not define the C library's `read` (it could never link) |
| raise-closed-world | the loop after idr-tail-loops prints the countdown (one input, none) |
| raise-io-loop | the loop after idr-tail-loops, every byte (countdowns of 0 to 255) |
| raise-known-constructor | every byte: 0 the constant action, the rest @put's |
| raise-shared-key | every byte |
| raise-sunk-call | every byte: 0 the applying region, the rest the other |
| raise-sunk-call-paths | two bytes, n of 0/1/255 with b of 0, 1, end of input: every region of every match (one-byte inputs only ever gave b the end of input) |

### optimize- (5)

| test | now |
| --- | --- |
| optimize-caller-cap | the capped chain prints what the chain as written does, every byte |
| optimize-case-of-case-calls | every byte: 0 crashes after `Anone`, 1 takes every non-crashing region, the rest crash in @across_computing after output; the differential compares the output before each crash, which is what case-of-case may not move |
| optimize-never-returns-twice | every byte exits as written, nothing printed |
| optimize-once | the optimized program (the action log run now writes it) means the program, every byte |
| optimize-pure-call | both the upstream canonicalize/cse output and the optimizer's mean the program, every byte; 0 crashes in @check, so a deleted crash would show |

### narrow- (3)

| test | now |
| --- | --- |
| narrow-descending | a new loop, @drain, takes a natural read from a line at most 300 steps down (a word bounds it), so both versions run: m below and past 300, 2^62 - 1 (the word versions), 2^62 (the loop as it was), 2^64, negatives; the differential on 13 inputs; the whole compile's output pinned (n mod 2, 2n, m - 300 clamped) on 6; `word-loop=@drain` stated |
| narrow-versioned | the differential, every byte; the whole compile's output pinned at the trip edges (n of 0, 1, 71, 72, 142, 143, end of input). @deep fixed: it applied `idr.big.pred` to zero (70 predecessors on n < 71), outside the op's contract ("the predecessor of a natural that is not zero"); the program never ended on n of 1 (the runtime's pred of 0 is -1). A trip now takes 71 only from n >= 71 |
| narrow-select-lanes | the rule's other side: the same loop with an addition of the i64 lanes in place of the select fails `narrowed-lanes` |

### names- (2)

| test | now |
| --- | --- |
| names-from-keys | each optimized function, name with body, compared (not the set of names): with threading off, with the functions reversed, with the root's two calls of @apply swapped (a counter in call order would swap the copies' names; reversal alone never could), and after the @scale edit for every function not made from @scale; the @scale functions are shown to differ (the comparison reads bodies); the optimized program means the program, every byte |
| names-reserved | the lowered program links with the runtime and runs as written (the reserved-looking names collide with nothing at link time) |

### lower- (36 of 37): lowered program against the program and a reference

Each now links and runs the lowered program (%differential against the
module as written and against a reference), with a root that reads input
and reaches each case the fixture lowers. A root that returned a constant
or read nothing now reads a byte (or a line) and prints.

| test | the root now reaches |
| --- | --- |
| lower-arrays | an index from input: in bounds (0, 2) and past (3, 255: the guard crashes); a double written and read back; @read/@write renamed (C library names) |
| lower-atom | @isNil of the atom and of a cell (`calls-only` of the root gains `@idris_rt_cell`, which the cell makes) |
| lower-atom-unfolded | @atom run |
| lower-big-fast-path | every byte against a word-only reference; the large root run on sums crossing the small range both ways (2^62 - 1 + 1, -2^62 - 1, large + large back to 1, 2^127) |
| lower-box | a word with the byte in its top and bottom 8 bits (negative from 128): the whole 64-bit field read back; `first` of Nil |
| lower-buffer | an offset from input: store 258 as 32 bits, load 16 bits there and one byte on, copy two bytes and load them (258, 1, 258); offsets 0, 4 fit, 5 and 255 crash at the store's guard (little-endian, as both targets are) |
| lower-cells | a heap cell made by @fresh, matched (@frame's cell dies with its frame, so it is not run) |
| lower-closure-left | a closure or lazy *type* (a parameter) is refused past higher too; each refused program verifies when said to be at higher (near misses) |
| lower-constants | the static string twice, the big, the list's head and the sum's Double printed, against `put_char`s and words |
| lower-counting | a list taken apart shared, rebuilt exclusive (recycled), taken apart exclusive (freed), @static for 0 and not, @counts' string |
| lower-crash | each crash reached by input (division by zero for 0, @Main.never for 1, @Main.name otherwise), and the whole compile's stdout and stderr (cause and site) pinned for each |
| lower-data-layout | A, B of (byte - 128) (sign-extended), C of byte * 2^40 |
| lower-entry | each root kind runs: the status root exits 3, both IO roots print `hi` |
| lower-exclusive | @exclusive on an exclusive cell; @owned on a shared one (new cell, old kept) and then exclusive |
| lower-force-by-name | forced twice: the effect happens twice (`loudloud`, status 2) |
| lower-force-excl | every state forced: @one, @plus, forced, and running (crash) for 0 |
| lower-force-view | forced twice (the second reads what was settled), @one, running (crash) for 0 |
| lower-in-bounds | @proven on x mod 3, @checked on x (crash from 3) |
| lower-internal-attrs | the in-LLVM module (given the target) compiled by idris-mlir as is, exits 3 |
| lower-internal-errors | the same module with 64-bit pointers lowers (near miss) |
| lower-io | every op's output, bytes 0, 65, 127, 128, 255, end of input |
| lower-layout | each limit and one past: 255 and 256 strings, 65,536 and 65,537 constructors, as before 258 counted references; each compiled whole and run, reading the slot it names (the last string differs from the rest, so a wrong offset shows) |
| lower-linear | runs, exits 7 |
| lower-linear-constant | the Step taken out of the constant action and matched: 23 |
| lower-llvm-facts | head of Nil (crash) and of [x]; each colour; the first character of x - 128 shown (`-`, one to three digits); `scalar_at` before the start, at each scalar, inside the é, past the end; 14 edge bytes |
| lower-mangle | every mangled function called and linked: 3x + 1 |
| lower-match-lit | byte 1, 255 (-1), others; "one", "two", others; 0, others, 2^62, negatives; the reference uses comparisons only. Fails (bug 3) |
| lower-may-loop | the loop entered and left on 0 (the only input on which it ends) |
| lower-nat | three lines: a + 1 (a natural not zero, as pred asks), b, i; the small range's edge, large, negative. Fixed: the root applied pred to the constant 0 |
| lower-select | the select chosen at run time by the byte's low bit |
| lower-static-thunk | the stream walked n steps (each a force of the same static cell): n + 1 |
| lower-strided-symbol | the descriptor pinned from both sides: no map (no stride) and an open offset (stride and offset) |
| lower-string-build | packs and concatenates multibyte lists (1, 2 and 4-byte UTF-8, an empty string in the middle) and the empty ones |
| lower-strings-bigs | every result printed; the whole compile pinned on one input (28 values, each computed by hand from the runtime's definitions) and each guard reached (index past the end, divisor 0, 1 / 0 as the Double) with its cause and site |
| lower-to-llvm | the in-LLVM module run: the static cell forced twice (88) |
| lower-world | the character from input |

### obs- (10 of 11)

| test | now |
| --- | --- |
| obs-debug-counter | the program optimized with every copy skipped, and with none, means the program (5 edge counts) |
| obs-foreign-pass-name | near miss: an option naming a pass it runs (idr-optimize) prints and writes the object |
| obs-lowered-input | the program reads a byte (circle or rectangle); the lowered module, compiled as is, prints 56 for 7 and matches the program and a reference on every byte |
| obs-lowered-mixed | neither refused module writes an object |
| obs-lowered-untargeted | near miss: the same module given the target compiles, links, exits 42. Fails (bug 6) |
| obs-print-ir-threads | printing changes no byte of the object |
| obs-print-with-object | -c refused by every --print action, -o by one (which writes nothing) |
| obs-report-accepted | each statistic key on one line (runs summed, not listed) |
| obs-report-refused | no object; the report the same at 1 and 4 threads |
| obs-stats | --stats changes no byte of the object |

### pipeline- (4 of 10)

| test | now |
| --- | --- |
| pipeline-do-block | the unfolded block prints 1 to 16 in order (against the program and a loop) |
| pipeline-inputs | the -o-names-the-input case runs on a copy, which is compared after (before, it ran on the repository's own test file, which a regression would have overwritten); -o and --report naming one file is refused and writes nothing |
| pipeline-runtime-names | idris_rt_cell (a runtime function) and read (a C library symbol the runtime calls) refused too |
| pipeline-stages | a step skipped (idr-lower at higher) and a step back (idr-defunctionalize at lowered) refused; the program taken down a stage at a time exits 42 |

### Left as they were

- lower-value-buffers: its root reads uninitialized string slots and its
  strided view reads past its source buffer; it exists for the static
  properties and is not a program to run, and RUN 1 fails on a known bug
  (SUMMARY §5 #8) before anything else.
- optimize-specialize-ends: none of its functions ends, by design.
- pipeline-endless-loop, pipeline-layout, pipeline-link,
  pipeline-one-pipeline (byte-identical objects already),
  pipeline-reported-error-fails, pipeline-time-trace,
  obs-report-link-failure: their contracts are checked exactly; nothing
  within them was left open.

## Compiler bugs (each failing test fails only on these)

1. **idr-narrow versions no loop after idr-rc.** `descends`
   (foreign/idr/lib/Transforms/Narrow/Versions.cpp) follows a
   predecessor's operand, but idr-rc writes `%b = idr.borrow %n` and
   `idr.big.pred borrow %b`, so the operand is a borrow's result, an op
   with no regions, and `descends` returns false. The `versioned`
   statistic is 0. Tests: narrow-descending (`word-loop=@parity`,
   `word-loop=@drain`: "computes on bigs in each of its loops"),
   narrow-versioned (`@deep`, `@carried`). Expected: each loop versioned;
   got: none. The meaning is right on both paths (the differential and the
   pinned outputs hold).
2. **Re-optimizing an optimized program is an internal error.** Input:
   raise-builds-actions after `idr-defunctionalize,idr-optimize,symbol-dce`
   (a verified program at `first`), given the pipeline from `first`, which
   runs idr-optimize again (`idris-mlir-opt t.mlir --idr-optimize` alone
   reproduces it). Expected: it compiles. Got: `internal error: two keys
   name then.spec.0f29be378093e8de: a function of the program and
   builtin.module {idr.key = #idr.spec_key<"then", ...>}`. Test:
   raise-builds-actions RUN 2.
3. **A string literal match lowers to the big comparison.** idr-lower
   turns `idr.match_lit` on `!idr.str` into `llvm.call
   @idris_rt_big_cmp(ptr, ptr)`, which the verifier refuses (`operand type
   mismatch: expected operand type 'i64', but provided '!llvm.ptr'`). It
   is now reached by the whole pipeline too, once the key is read at run
   time. Test: lower-match-lit RUN 3 (the whole compile against the
   reference) and RUN 4 (the chain). SUMMARY §5 #12, now pinned to this op.
4. **A function named @main is an internal error.** A verified program
   whose function is `@main` (lower-layout's generated root was) fails with
   `internal error: idr-entry: @main names a symbol already`, not a
   refusal naming the symbol (as pipeline-runtime-names' are) or a rename.
   The Idris frontend never writes an unqualified `main`; found while
   running lower-layout, whose root is now `@start`. No test states it.
5. **The small root imports the runtime's big functions**
   (lower-big-fast-path RUN 12: `_idris_rt_big_add`, `_cmp`, `_mul`, ...):
   the small cases are not inline. Pre-existing.
6. **`foldsBalanced` dereferences an unloaded dialect** (SUMMARY §5 #1),
   now also hit by `idris-mlir-opt --idr-target` on a module of the LLVM
   dialect alone (obs-lowered-untargeted RUN 6, exit 139 in
   `IdrDialect::foldLeakCount`), as by narrow-select-lanes RUN 5.
7. Pre-existing, unchanged: raise-shared-key (`not-called` §5 #26),
   pipeline-do-block (`not-called=@bind`), lower-value-buffers (§5 #8).

## For the harness's owner (not this lane's to change)

- **%differential is common-mode for every pass in the registered
  pipeline.** BEFORE is compiled by the pipeline from its stage, which
  runs the pass under test as well (idr-optimize, idr-narrow, idr-rc,
  idr-lower), so a miscompile by that pass on the fixture's form shows on
  both sides and agrees; what it catches is the rest of the pipeline,
  phase order, and hand-made mutants. That is why this lane added
  references (REF) and whole-compile checks with hand-computed outputs.
  A BEFORE that skips the pass under test (an action skipped, as
  obs-debug-counter does with a debug counter, in `lit_pipeline_from`)
  would make it an oracle for the pass itself.
- `lit_lowered` takes a module's stage from the first `idr.program ...
  stage(...)` line of the file, comments included.
- The differential compares stdout and status, never stderr: two programs
  crashing with different causes agree.
- A RUN line cannot hold `%s` but as the substitution (a sed of `%small`
  breaks); sed patterns here capture instead.
- REF lines are a reference program held in comments and taken out by sed:
  if the vocabulary is to hold one way of stating a reference, this is the
  candidate.

## Runs

- `make test-idr only='lower- names- narrow- obs- optimize- pipeline-
  raise-' threads=2` (79 tests: these 77, actions-narrow-lanes and the
  pipeline-timing script): before 69/79 in 52 s, after 68/79 in 205 s.
  The failures: the same ten, plus obs-lowered-untargeted (bug 6, its new
  near miss, after every old line holds). Alone, a fixture with declared
  inputs takes 2 to 4 s, one with the full byte box about 6 s.
- `make check`: 31/33; dialect-text (fold-*, guards-*, e2e-loops: other
  lanes' fixtures) and file-size (C++ units) fail, none of this lane's.
