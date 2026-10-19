<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Strengthening the suite: fixtures-4

## Scope

The 70 fixtures named `rc-*`, `reduce-*`, `returned-*`, `roles-*`,
`specialize-*`, `stack-*`, `structure-*`, `syntax-*`, `tail-calls-*`,
`tie-shape-*`, `vectorize-*`, `verify-*` and `world-*`. Nothing of the
compiler was edited. One harness change, below, is outside the tests: it is
what "the run leaves no live cell" needs.

## Runs

| run | before | after |
| --- | --- | --- |
| `make test-idr` on the 70 (threads=2) | 59/70 | 56/70, plus `differential-wrong-rewrite` and `differential-declared-stdin`, which pass (72 run, 58 pass) |
| `make check` | | 9/33; no failure names a file of this lane (my tests, `harness/lib/differential.sh`, `harness/README.md`, this report): the failures are other lanes' check scripts mid-change (new `witness:`/`near miss:` lines with `expected` not yet updated, `dialect-text`'s new rule on other fixtures) and the known `file-size` |

The 11 failing before still fail, each at the same bug (§ Bugs, known).
The 3 new failures are the strengthened tests catching compiler bugs:
`rc-buffers` (bug 1, new), `structure-tabulate` (bug 2, new, a silent
miscompile), `structure-transpose` (bug 3, known, now reached by a run).

## The harness: `%differential` holds every run to no live cell

`harness/lib/differential.sh`, `lit_differential`: each program now runs
with `IDRIS_RT_LIVE=1`; a run whose last stderr line is `idris-rt: live
cells N` with N not 0 fails the line, naming the module and the input
(`differential: <module> leaves N cells live on <input>`). A crash or an
exit with a status of the program's own writes no count and is held to
none, as `run_ours` holds every program test. The README's paragraph on the
differential says so. Why here and not as a new form: a stage-`first` or
`owned` module runs only through the differential (idris-mlir takes a
`higher` module or an LLVM one), and "a program this compiler built frees
every cell" is already the rule of every other run; the differential was
the one run that did not hold it. Shown failing: `rc-live` takes every
`idris_rt_dec` out of the lowered module and the differential names the
leak on the empty input. The other lanes' fixtures that use the
differential (122 when I looked) ran after the change; none reports a leak.

## Per test

### rc- (the run leaves no live cell; every path is run)

Every runnable rc fixture now has `idris-mlir-opt %s --idr-rc -o
%t.owned.mlir` and `%differential %s %t.owned.mlir`: the counted program
means what the uncounted one meant, on the empty input and every byte, and
no run leaves a cell live. Each root reads a byte that sets the shapes, so
that every case of every function under test runs on some input. The
properties the fixtures stated are kept as they were.

| test | inputs now | paths run that were not |
| --- | --- | --- |
| rc-arrays | length 0 to 3, index 0 to 4 | the empty array, the last element, indices past the end (the bounds crash, through `idr.check.in_bounds`, as the frontend writes it); a value set and read back; the `Opt` read taken apart |
| rc-atom-pairs | list 1..n, n 0 to 15; splitAt's count 0 to 4 | every function's end at the empty list and its stop at an element (lists were descending from 12, so span stopped at once and withCell's empty-head path never ran); `@build` replaced by an ascending `@upto` |
| rc-buffers | buffer length 1 to 4, the element the byte | the buffer read back by `memref.load` (fails: bug 1) |
| rc-consumed | 0 to 5 keys | `ins`'s third path (the right subtree a node), never run before; the tree's weighted sum printed |
| rc-counted-linalg | | the nearest that verifies: the same linalg loop over words |
| rc-counts | list length 0 to 7 | `map` and `sum` on cells (the root mapped only the empty list) |
| rc-dies-apart | lengths 0 to 3 and 0 to 2 | `sumAfterTag`'s empty case, `tail`'s `NN` case, `headOnly`'s empty case, `numbers`' `V0` (`mkV` now makes it at 0) |
| rc-exclusive | length 0 to 4 | every function on the empty list |
| rc-kept-fields | key the byte, three bits for leaf or node | each function's `Leaf` case; the trees' keys weighted by depth printed, not tags alone |
| rc-live | lengths 0 to 12 and 0 to 2 | the empty list; the differential before and after counting; the leak mutant (the form's negative case) |
| rc-nested-reuse | the numbers the byte and its half | both fields of the rebuilt cell printed |
| rc-regions-counted | sizes 0 to 3, both arms, three switch cases | every function was dead (root returned 0); `@make` now fills its buffer before it is read. Fails at RUN 1 as before (bug 1) |
| rc-returned | length 0 to 3 | `bump`'s cells and the root's empty case |
| rc-second-redirect | length 0 to 4 | the differential runs first and holds; the old property still fails (known) |
| rc-share-trap | length 0 to 5 | the shared list's every cell, the empty list |
| rc-stack-cell | the number, the tail a cell or empty | the frame cell's tail given back at the frame's end |
| rc-take-at-death | key, leaf or node, empty or not | `flip`'s `L` and `keep`'s `Nil` cases |
| rc-verify | | the nearest that verifies for the three refusals that had none: both regions of a match drop, a cell recycled at its own size, a list packed while its reference lives |

### specialize-

Each now writes the pipeline's output (`idr-defunctionalize`/`idr-optimize`,
`symbol-dce`) to `%t.mlir` and holds it to the module as written with
`%differential`, on every byte. The `idr-expect` line stays in the pipeline,
since copies are named by locations the printed module does not carry.

- specialize-countdown: the Integer accumulator starts at 2^62 - 128, so
  the counts the byte sets cross the runtime's small-integer edge; compiled
  by idris-mlir and run, it prints 5k and 2^62 - 128 + k at k = 127 (2^62 -
  1, the last small one), 128 (2^62) and 255, checked exactly.
- specialize-growing: the count is the byte mod 16 (2^15 applications at
  most), so every byte ends.
- specialize-higher-order: `@read` renamed `@readList` (a definition named
  `read` is refused as the runtime's symbol).
- specialize-dictionary, -partial-list, -static-table: the differential.
- specialize-binding-times: two cases the rule had none of: a parameter
  passed back through a match's default region is fixed (`@spin`), and two
  passed back in each other's positions vary (`@swap`).

### stack-

- stack-expect: the module after `idr-rc-cells`/`idr-rc-stack` held to the
  one as written by the differential; the root reads a byte for the number
  and whether the tail is a cell, and `@head` now runs on the empty list.
- stack-linear-box: the same after `--idr-rc`.

### structure-

Each root used to return 0 (the functions dead) or run one constant. Now
each makes its arrays at sizes the byte sets and prints what pins every
element at its index; the module after the pass is held to the one as
written by the differential.

- structure-tabulate: sums weighted by position (rank 1 and 2), and a
  guarded division by 0 to 2 that must crash only where there is an element
  (an empty domain divides nothing). Fails: bug 2.
- structure-columns: 1 to 4 records, both fields of the first, the last
  or one between.
- structure-transpose: `@swap` on 1..3 by 1..3, corners read at their
  transposed places; `@back` and `@same` on static arrays; held both after
  `idr-structure-loops` and after `--canonicalize`. Fails at the first
  differential: bug 3.
- structure-never-returns: 0 to 2 elements: the empty domain does not
  crash and prints its size; the others crash. The differential holds; the
  old property still fails (known).
- structure-ordered: the ordered loops print in index order, the integer
  sums, a float sum (1e16 then ones) whose result changes if reassociated,
  and the crash only where there is an element. Fails at the differential:
  bug 3 (its old property line, still failing, comes after).
- structure-dynamic-cells: sizes 1 to 3 per dimension, corners read; fails
  at RUN 1 as before (the pass's assertion).

### tie-shape-, roles-, reduce-, vectorize-

- tie-shape-dims-fold: a root ties arrays of 0 to 4 elements and prints
  every dimension the functions read; `--canonicalize`'s output held to the
  module as written.
- tie-shape-verify: the nearest each refusal has: two sizes for two
  dynamic dimensions on a tensor, none for a static shape (`dims()`).
- roles-contify: the module with every move made is held to the one as
  written; the root counts 0 to 31 doubling steps from 1 (it started from
  0, so every run printed 0).
- reduce-regions: the interestingness test is shown both ways (the module
  as written is interesting, one without the literal match is not), and the
  reduced module is no longer than the original printed.
- vectorize-rows: the root read element 0 of arrays of 0 to 255 elements
  (byte 0 read out of bounds); it now makes 1 to 256 and reads the first and
  the last of each; the program, linked and run, prints exactly what IEEE
  doubles added in index order give, at 1, 7 (no whole number of lanes on
  any target) and 256 elements. These lines come before the known failing
  RUN line and hold.

### verify-, syntax-, world- (each rule: the smallest refused, the nearest accepted)

A split with no expected diagnostic was added where a refusal had no
accepted neighbour; it holds the refused function with the one thing the
rule refuses put right.

| test | added |
| --- | --- |
| verify-widths | i8 for i7 and i1, i64 for i128; a dup of a value that holds a reference |
| verify-only-atoms | the exclusive reference to an atom |
| verify-nat | 0 for -1; the difference as an Integer; the sum of naturals; a natural's predecessor; the clamping conversion; `from_uint`; a natural key |
| verify-generic | the generic match and literal match that verify, and the constant of a constructor the type has |
| verify-match | refused: `case 255` beside `case -1` of `i8` (one key); accepted: one case per constructor, `ub.unreachable` ending a region, a default region, distinct keys, `i8`'s keys 255 and -128, distinct strings |
| verify-ops | `show_uint` of a byte, `big.cmp eq`/`lt`, a list of characters written, an IORef of no size, an array of one, a read at one index |
| verify-data | f64, i8, i64 fields; two names; base's list; one body written twice for one name |
| verify-effects | `effects<io>` for the writer; a set that says more than the body does |
| verify-closure | the leading parameter captured, both, none; an apply at the closure's types |
| verify-cells | a cell of the constructor with fields; a hole at the box's field written once through its destination; `idr.unpack` of a constructor without a cell |
| verify-cycle | a node holding an IORef of words, in an IORef and an array of nodes |
| verify-flow | the choices as matches, a select of words, a delay at the closure's own carrier (the file still fails at its two known refusals) |
| verify-owned-stage | the value dropped; the box built in a new cell; the cell filled and its box dropped; a frame cell's box owned and dropped |
| verify-program | refused: alignment 16 (the smallest past 8); accepted: a memo sum in a box, a type with its body, alignment 8 in an allocation and a global, the identity and a strided layout, a linalg op of words |
| verify-values | a constructor, field and tag of the type, constants of what a constant holds, a constant closure at its type |
| verify-attributes | an attribute of no dialect on an op |
| syntax-grades-invalid | the quantity spelt `one`, the world and a destination at no grade, an owned linear reference |
| syntax-inherent-invalid | the same ops with an attribute of no dialect that no syntax spells |
| syntax-facts-roundtrip | refused: `no_inline` and `instance` of the wrong kind (only `total` was) |
| syntax-constants | one cell prints as a constructor, two as a run, and a one-cell run is refused |

Unchanged, with the reason:
- verify-con-owned-field, world-once: each refusal already has its
  neighbour in the file.
- verify-roundtrip: the three printed forms are checked already (and every
  idris-mlir-opt line reads back from the generic form and bytecode); it
  fails on the known `@Just (` printing.
- syntax-closures, syntax-grades, syntax-refusal, syntax-nested-constant:
  printer contracts already stated at their edges (no results, several,
  nested; every spelling; a 100,000-deep attribute).
- tail-calls-decided-loops, -positions, -long-continuation, returned-threaded:
  modules of upstream dialects with no program and no C entry, nothing to
  run; the first two and returned-threaded fail on the known foldsBalanced
  crash. tail-calls-mutual already runs ten million calls against closed
  forms.

## Bugs

### New

1. **idr-rc asserts on a `memref.load` of a counted element from a buffer
   the function holds.** Test: `rc-buffers` (RUN 1, and the differential);
   it is also why `rc-regions-counted` fails at RUN 1 (its `@viewInLoop`).
   Input (stage first): a function that does `memref.alloc` of
   `memref<?x!idr.box<!L>>`, stores a cons in it, and `memref.load`s it
   back, then `idr.tag` of what it loaded; `idris-mlir-opt --idr-rc`.
   Expected: the owned module. Got: `Assertion failed: (isa<To>(Val) &&
   "cast<Ty>() argument of incompatible type!")` in
   `mlir::memref::LoadOp::getMemref()` from `idr::ownership::readFrom`
   (`Reuses` analysis, idr-rc-grades). The same load of an `i64` element
   passes, and a load from a parameter's buffer passes: the buffer's
   value has been graded by then, so its type is no memref and
   `getMemref()`'s cast fails. A variant: a `tensor.extract_slice` of a
   static tensor, bufferized to `memref.subview`, asserts the same way in
   `readFrom` through `ViewLikeOpInterface::getViewSource`
   (`SubViewOp::getMixedOffsets`).

2. **remove-dead-values poisons the elements of an `idr.tabulate` read only
   inside a nested region (a silent miscompile).** Test:
   `structure-tabulate` (the differential: the module as written prints `00`
   then crashes on the empty input, the lowered one `140` then crashes).
   Input: `idr.tabulate [%n]` yielding `i*i`, summed by an `scf.for` whose
   body does `tensor.extract %t[%i]` (or by `idr.fold_last`, same result),
   printed. `idris-mlir-opt --remove-dead-values` turns the region into
   `%p = ub.poison : i64; idr.array.yield %p`. The same module at stage
   higher, compiled with idris-mlir and run: byte 3 prints 0 (expected 0 +
   1 + 4 = 5), byte 5 prints 0 (expected 30). idris-mlir's own pipeline runs
   `remove-dead-values{canonicalize=false}` before `idr-structure-loops`.
   With `tensor.generate` in place of `idr.tabulate` the elements are
   kept, so it is ours: liveness does not see the yielded element flow into
   the tabulate's results (its `RegionBranchOpInterface`). A tensor read
   by `tensor.extract` at the function's top level keeps its elements.

### Known, now reached by a run

3. **The owned verifier refuses counting's output in front of linalg ops**
   (SUMMARY §5.2 item 8): "'linalg.transpose' op consumes a view, which
   holds no reference" (`structure-transpose`, a transpose of a tabulated
   array) and the same for `linalg.generic` from `idr.fold_last`
   (`structure-ordered`). No program that transposes or folds a tabulated
   array compiles from the first stage.

### Known, unchanged

rc-second-redirect (exclusive copy of @bump), structure-dynamic-cells and
structure-never-returns (idr-structure-loops), tail-calls-decided-loops,
tail-calls-positions and returned-threaded (foldsBalanced on a module of
upstream dialects), vectorize-rows (the cleanup schedule), verify-flow
(`arith.select` of a closure no longer refused), verify-roundtrip
(`@Just (` printed).

### Observations, not bugs by the contract

- An `idr.array.get`/`set` whose index no `idr.check.in_bounds` checked
  reads and writes out of bounds silently (rc-arrays' first draft printed
  values for an empty array). The frontend writes the guard before each
  such op; the verifier does not require it.
- world-once's comment says a world is used exactly once on every path; a
  function that never uses its world verifies. The fixture checks "at most
  once", which is what the verifier holds.
- A hand-written function named `read` (or another C name the runtime
  uses) compiles at one stage and is refused at another, depending on
  whether it was inlined: "the program defines read, which the runtime
  refers to too".
