<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane programs-2: what was done

**Scope:** `tests/programs/` topics linear, nat, partial, prelude, semantics
and stack. No other topic exists beyond these and programs-1's six.

**Inputs:** AGENTS.md, both guidelines, `audits/SUMMARY.md` and `audits/programs.md`.

**What changed:** only files in the scope. No compiler code. No git.

## Result

`make test only='programs/linear programs/nat programs/partial programs/prelude programs/semantics programs/stack' threads=2`,
on the build in `build/dev` (18:20 to 18:55): **196/221 passing**. The 221 are
77 directories plus the 144 instances of `semantics/prim`.

- Every one of the 144 `prim@` instances passes.
- Each of the 25 failures is a compiler bug, listed below with its evidence.
- No test in the scope fails because the test is wrong.

At the start, the audit's run had 97 failures across all twelve topics. A
baseline I ran in this scope gave 34/40 for linear, nat, partial and stack.

Two of my runs, between 18:13 and 18:16, were void. Another lane was
editing `tests/runner/one.sh` at the time: the `stderr` path was relative
and was resolved after `cd`. The lane fixed it at 18:16, and the numbers
above come from a run after that.

## Deleted

There are 21 test directories in all. Four of them were merged into one new
fixture.

| path | reason |
| --- | --- |
| prelude/prelude | SUMMARY §3.1: subsumed by the every-*-export set; stale "evaluated at compile time" claim |
| prelude/prelude-lists | SUMMARY §3.1: subsumed by every-types-export and every-interfaces-export; stale compile-time claim |
| prelude/string-functions | SUMMARY §3.2: the claim (strings written straight to the output) was stated nowhere |
| prelude/prelude-show | merge-into every-show-export, which shows each of these types at every precedence |
| prelude/show-values | merge-into every-show-export (signed values, nested Maybe/Either/pairs, Doubles at each precedence) |
| prelude/prelude-traverse | merge-into every-interfaces-export, which holds `*>`, for_, traverse_, sequence_, when and unless over IO |
| prelude/prelude-user-types | merge-into every-interfaces-export (user Show/Eq/Ord/Monoid/Functor with defaults); stale compile-time claim |
| prelude/math-showcase | merge-into prelude-math (Newton, Simpson, Mandelbrot). Its user `Arith` dictionary with a heap-free mark is data/nbody's shape, and its `Arith.idr` was a second copy of nbody's |
| semantics/closed-shift-negative | SUMMARY §3.4 / §3.7 item 4: Sem's `shiftAmounts` holds -1 and -3 for signed types |
| semantics/closed-string-to-int | exact duplicate: `prim__cast_StringInt "12.7"` on a literal is closed-literal-conversion's first line, and cast-from-string has the same row at run time |
| semantics/closed-double-tie | exact duplicate: `prim__cast_DoubleString 12.886856079101562` on a literal is closed-literal-conversion's second line |
| semantics/crash-location | byte-identical to basic/guards-messages-div-zero (same Prog.idr shape, same `division by zero at Prog.idr:6:1`) |
| semantics/mutual-recursion | merge-into stack/mutual-pure-tail-calls: the same even/odd pair, ten million deep, with `constant-stack` stated |
| partial/loop-breakers | SUMMARY §3.2: the loop-breaker claim was unchecked, and even/odd is the stack test's |
| partial/crash-after-output | merge-into basic/let-after-output, the stronger case (output, then a crash computed after it). missing-case stays, so idr/e2e/crash's deletion still has its two replacements |
| partial/partial-untaken-divergence | merged into partial/partial-divergent-call (see below) |
| partial/lambda-terminates | The harness no longer reads `mlir.check` ("mlir.check: not read; state its property in mlir.expect"). Its property cannot be stated in idr-expect: a lambda's function carries its definition's NameLoc, so `@Main.main` names main and its lambdas together. `not-total=@Main.main` fails on the lambdas, and `total=@Main.main` fails on main. Naming a lambda by its generated hash is forbidden, so it was deleted (see *Future vocabulary*) |
| linear/leet-reverse-list, leet-kth-from-end, leet-palindrome-list, leet-rotate | merged into linear/leet-relink-in-place: one rev/countRev scaffolding copied four times (RF one fact, one place) |

Also deleted:
- **The 72 output-only `semantics/prim-<type>-<family>-<k>` directories:**
  litter of the old Sem naming (SUMMARY §3.6).
- **The untracked `linear/leet-valid-parentheses/build/`.**
- **`partial/partial-divergent-call/mlir.check`:** replaced by an mlir.expect.
- **The NEEDS-ACCEPTANCE line of `semantics/prim/expected`:** all 144 instances pass,
  so the build confirmed it. This was the only mark in the scope.

## Rewritten

- **linear/leet-relink-in-place** (new; the four merged programs).
  - It holds one program with every function of the four. Its
    `expected-stdout` is their four reviewed expected files, concatenated.
    Palindrome's lines do not depend on n, so its stdin of 50000 became the
    shared 100000.
  - Its mlir.expect states the properties of all four: rev, countRev and app
    get tests-nothing, counts-nothing and reuses-in-place; removeAt gets
    tests-nothing.
  - It passes.
- **linear/leet-valid-parentheses.**
  - `tests-nothing=@Main.check` claimed more than the contract. check took an
    unrestricted `List Char`, and testing the count of a shared cell is
    correct. Its comment also leaned on "static lists" and on a
    specialized-by-grade copy, both inlining and compile-time choices.
  - The input is now a linear `LList (!* Char)` (`linear` converts the
    literals, and `nested` builds its input linearly), so the property is
    the contract.
  - It passes.
- **partial/partial-divergent-call.**
  - partial-untaken-divergence's distinct case, `safeDiv 84 2` (divergence
    on a path the call does not take) and `collatz 27`, is merged in.
    `expected-stdout` is the two reviewed files' lines.
  - The FileCheck `call @Main.spin(`, which broke on any clone name, became
    `idr-optimize: calls=@Main.main:@Main.spin calls=@Main.main:@Main.collatz`.
  - It passes.
- **nat/nat-parity.** The comment claimed "mlir.expect states that some loop
  holds no big", but there was no mlir.expect. Now it states
  `idr-narrow: word-loop=@Main.parity`, and it **fails on a compiler bug**
  (below).
- **stack/list-length, stack/replicate-take-deep, prelude/map-deep, prelude/traverse-deep.**
  - Each read `constant-stack` at idr-narrow, "the step after the group"
    (PROG-5).
  - Each now reads it at `idr-tail-calls`, the step after which the row's
    definition is complete (loops or `musttail`). stack/mutual-pure-tail-calls
    already stated it this way.
  - That leaves one way to state constant stack, and no comment explains
    the pipeline's group structure any more.
  - list-length and map-deep pass. replicate-take-deep's property holds, and
    the test fails only on its leak. traverse-deep fails on its bug.
- **prelude/split-prefixes.**
  - `tests-nothing=@$idris-mlir.root` pinned inlining: it now fails with
    "nothing is taken apart in @$idris-mlir.root", because putChunks is no
    longer inlined into the root.
  - It was replaced by `tests-nothing=@Data.List.splitAt`, so the claim is
    stated of span and splitAt, the functions it is about, and the comment
    about inlining is gone.
  - It fails on a compiler bug.
- **prelude/char-list-pipeline.** Two pins were dropped:
  - `reuses-in-place=@Main.putChunks` named a function the inliner removes
    (PROG-4).
  - `reuses-in-place=@Main.body` is stronger than the contract. It fails
    on the boxes of IO-continuation and `isLower` delay closures, which
    inlining places in body: "a box of @Prelude.Types.isLower.delay... gets
    a fresh cell in @Main.body". Body's contract is about list cells, and
    `resets-unshared=@Main.body`, which holds, keeps it.

  The test fails on compiler bugs.
- **Stale comments** (PROG-7, PROG-8):
  - **Compile-time evaluation**, rewritten to say that a closed call runs at
    run time, or that no folder sees the value:
    - semantics/absurd-body and semantics/erased-witness;
    - nat/nat-sum; partial/tail-loop-deep; prelude/integer-bits;
    - prelude/prelude-math, which also cited the deleted accept/partial-integer.
  - **The Scheme and R6RS printer comparisons**, removed from
    semantics/closed-double-infinity and semantics/closed-double-subnormal.
  - **semantics/crash-integer-shift-huge:** its compile-time folding sentence
    was rewritten.
- **nat-parity's comment** now names the function that mlir.expect checks.

Kept as they are, because each checks something today and its rewrite needs
a generator: every `rewrite-as-property` and `merge-into:<generated fixture>`
row of the audit in this scope. These are:
- cast-from-string, double-subnormals, double-ties, double-infinities-nan,
  double-cast-nan, integer-bits, negate-fixed-width (Sem.idr is outside this
  lane);
- nat-large;
- the leet programs that state distinct properties;
- enum-stepping, erased-witness, literal-match, mixed-widths;
- closed-char-to-string, closed-integer-shift, closed-double-infinity,
  closed-double-subnormal;
- every-types-export's `live-cells 2` (PROG-16);
- io-loop-through-helper's and forever-until-crash's restated factor
  (PROG-17).

## Failing on compiler bugs (25)

Item numbers are SUMMARY §5's. The cause of each hidden compile failure was
found by compiling without the tree printer (`tools/compile.sh --num-threads=2`).

| test | bug | evidence |
| --- | --- | --- |
| linear/linear-string-iterator | §5.12 | `'llvm.call' op operand type mismatch: expected operand type 'i64', but provided '!llvm.ptr'` |
| prelude/every-builtin-export, every-cast-export, every-io-export, every-ops-export, string-pack | §5.12 | the same `llvm.call` mismatch |
| prelude/every-eqord-export, every-show-export | §5.12 | the same, hidden under the tree printer's "File name too long" as compile exit 1 |
| prelude/every-uninhabited-export, char-list-accumulated | §5.9 | `'idr.yield' op idr-rc-exclusive: gives a value of '!idr.own<...List...>' where the solver proved '!idr.excl...'` |
| prelude/every-types-export | §5.9 | the same on `SnocList[Int]` and `List[Int]` (hidden: compile exit 1) |
| prelude/every-interfaces-export | §5.9 | the same on `List[Int]`. It takes 28 s without dumps, and hits the 60 s timeout with them: a §5.39 timeout whose verdict is this bug |
| prelude/double-basics | §5.13 | `idr.cell.new allocates in @Main.main.delay.*`; `idr.str.show_sint` and `idr.str.append` in a delay |
| prelude/double-cast-nan | §5.13 | `idr.str.show_sint` and `idr.str.append allocate in @$idris-mlir.root` |
| prelude/traverse-deep | §5.14 | stack exhausted; `constant-stack: the stack grows with the recursion of @Prelude.Interfaces.foldr[PrimIO.IO ...]` |
| stack/for-long-list | §5.14 | stack exhausted after 0 of 4 lines |
| stack/io-loop-through-helper | §5.11 | exit 139 after main; `idris-rt: live cells 30017` |
| stack/replicate-take-deep | §5.10 | live cells 10000000 (its constant-stack property holds) |
| nat/nat-large, prelude/double-subnormals | §5.10 | live cells 1 |
| prelude/double-infinities-nan, postponed-lambdas | §5.10 | live cells 3 |
| prelude/split-prefixes | §5.10 and §5.9's family | live cells 18. `tests-nothing: idr.take in @Data.List.span[Char].spec.* tests a value of '!idr.own<...List[Char]...>', which is not exclusive`, and the same in `@Data.List.splitAt[Char]`, though every list the program takes apart is fresh. The `.excl` copies exist, but the non-exclusive copies are the ones called |
| prelude/char-list-pipeline | §5.10 and §5.9's family | live cells 172. `tests-nothing: idr.take in @Prelude.Types.List.reverseOnto[Char] tests a value ... which is not exclusive`, on lists the program read or generated fresh (plausible) |
| nat/nat-parity | **new** | `expected word-loop: @Main.parity computes on bigs in each of its loops` after idr-narrow |

More on the new bug, nat-parity:
- **The promise:** Passes.td's IdrNarrow says "A loop whose natural argument
  only descends ... is versioned: one test on entry that the argument is
  small, then a copy of the loop in which it is proved to stay small".
- **The real pipeline:** in the owned IR, parity's scf.while passes back
  `idr.big.pred` of a `dup`/`borrow` of the `match_lit` default's binder. The
  loop is not versioned (dump `0_18_idr-narrow.mlir`).
- **The hand fixture:** idr/narrow/descending writes `idr.big.pred %n` of the
  argument itself, at stage `first`.

No idr-narrow statistic is in the test. The dump holds no word loop.

Fixed since the audit:
- **Now passing:** linear/linear-catch-all and linear-nested-match (§5.22,
  after e6d8d6d8) and prelude/every-primio-export (§5.30: `covers` holds again).
- **§5.38, the tree printer's noise:** it still hides the cause in the
  every-*-export compiles. This lane does not change the harness.

## What a future generator or harness must cover for what was deleted

- **Naming a lambda (vocabulary, SUMMARY §6 step 4).**
  - idr-expect needs a way to name the functions the frontend writes for a
    definition's lambdas apart from the definition itself. Today they share
    its NameLoc.
  - Then `total` can be stated of main's lambdas and `not-total` of main
    alone. That would restore lambda-terminates: "a function's fact is about
    its own loops", with main partial and its lambdas total.
- **A per-type reuses-in-place** (for example, a reuse row restricted to a
  data type's boxes), so that char-list-pipeline can say "body complements
  each character into its own list cell" without counting closure boxes.
- **Roots forms of tests-nothing, counts-nothing and reuses-in-place**
  (PROG-4), so that split-prefixes can again state its root's own takes,
  wherever putChunks ends up.
- **G1 and G5 (show and Prelude laws over generated runtime values)** take
  what prelude, prelude-lists, prelude-show and show-values held:
  - Show of runtime negatives at every width;
  - the first character of a show;
  - `-0.0` in a constructor;
  - Ints, Doubles and Lists from stdin rather than constants.

  The every-*-export set holds these as constants.
- **G5 and Fuzz's dictionary** get the literals of closed-string-to-int
  (`"12.7"`) and closed-double-tie (`12.886856079101562`). Both are still in
  closed-literal-conversion and cast-from-string (§3.7 item 8).
- **G4 (`semantics/crash@<guard>`)** takes the crash fixtures:
  - it must include the located form `<cause> at Prog.idr:L:C` for a
    definition loaded from its TTC (crash-location's case, kept today by
    basic/guards-messages-div-zero);
  - and each guard with output before it (crash-after-output's case, kept
    by basic/let-after-output).
- **G7 (recursion and tail graphs)** must include even/odd mutual recursion
  (mutual-recursion, loop-breakers), a divergent callee on an untaken path
  (partial-untaken-divergence, now in partial-divergent-call), and the
  shapes of the stack topic.
- **G2 (linear lists)** takes the leet corpus as seeds. leet-relink-in-place
  holds rev, countRev, removeAt, splitRev, app and same together.
- **G-HO and user dictionaries:** math-showcase's numerics over a user
  `Arith` instance for Int, Double and Complex. Only data/nbody covers that
  shape now.

## Notes

- **The layout is not flattened.** The owner asked for one flat test
  directory, but tests/Main.idr names each topic's pool, and Main.idr is
  outside this lane. So `tests/programs/<topic>/` is not flattened here.
- **Running tests while lanes run.** Every run of `make test` rebuilds the
  runner, and other lanes are editing the harness. A run between 18:13 and
  18:16 lost every verdict to the relative `stderr` path in one.sh.
