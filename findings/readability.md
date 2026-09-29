# Readability and steerability: can a human steer this compiler?

The second outside review says the code "reads agent-written" and that the
owner could not read their own test. This stream asks what that means in
practice, measures it, and proposes what a human-steerable compiler of this
kind would look like, with the path from here to there.

Companion file: `readability-architecture-draft.md` is a draft of the
one-page overview recommended in section 4, written against the code as it
is today. It includes the pipeline diagram, the IR stages, the invariants
table, a glossary and a guide to reading a dump.

## The questions

1. Where does the prose in comments, pass descriptions, tests and error
   messages hurt comprehension? What exactly is the "agent-written" tell?
2. Can a competent compiler engineer who is new to the repo tell what a
   test checks, and why it would fail? The case study is
   `tests/idr/rc/loops.mlir`. What test style fixes this?
3. The scaffolding: what does each piece of process machinery cost, and
   which pieces pay for themselves at this size?
4. Steerability: what does a human owner need in order to catch the bugs
   that agents miss? What does an exemplary codebase of this kind look like,
   and how do we get there?

## Verdict

- **The tell is not missing articles.** Measured against upstream MLIR's
  own comments, idris-mlir uses *more* articles. The real signature is
  abstraction: ten times as many possessive chains ("the owned stage's
  rule"), seven times as many nominal clauses ("turns what it counted into
  loops"), twice the colons and semicolons, and a private vocabulary of
  about fifteen terms ("label", "key", "leaves", "tails", "round", "meets",
  "only computes") that is defined nowhere a newcomer would look (1.1).
- **Most of the code is well explained, but only for a reader who already
  knows it.** The comments say *what* precisely and often say *why*. What
  they lack is an entry point: a map, a glossary and one example per
  concept.
- **The tests state properties, but they state them in a private language,
  and they check less than they claim.** `rc/loops.mlir` claims two
  properties and checks one of them. Its pipeline includes a pass that has
  no effect on its input. The property that actually protects it, the
  ownership verifier, is invisible in the file (2.1). A rewrite in the
  proposed style is verified below: it passes, and it fails for the right
  reasons under two mutations.
- **The scaffolding has one big structural problem.** The C++ style profile
  (cpp-starter) is waived for 100% of the C++ in the repo: the dialect by
  `PIN(mlir-cxx-api)`, the runtime by `PIN(runtime-quarantine)`, and the
  profile's own zones do not exist. Yet the profile drives a half-finished
  C++-modules migration: 892 lines of re-exports so that 720 lines can live
  in 25 files. It also accounts for 13 of the 25 PINS entries and several
  spec tests. The rest of the machinery mostly pays for itself: the oracles,
  idr-expect, the upstream bug reports, the architectural spec tests and
  bisect.sh (3).
- **The best safety nets are invisible.** The reviewer asked for "a fuzzer
  or differential testing against the upstream Idris backend". Both already
  exist: `tests/fuzz`, the Chez comparison in every e2e test,
  `tests/equivalence` and `tests/twolevels`. An outside expert could not
  find them. That is the steerability problem in one example (4.2).

---

## 1. Prose

### 1.1 What the tell actually is (measured)

Comment text was extracted from the tracked files and compared with the
pinned MLIR's own transforms (`mlir/lib/Transforms`, SCF and bufferization
transforms) and MLIR's tests. The script is in the scratchpad
(`research/readability/`). Words counted exclude code.

| Corpus | Words | Articles | what / which / whose | Possessive `'s` per 1000 words | Mean sentence length (words) | Sentences over 35 words | `:` + `;` per 1000 words |
|---|---|---|---|---|---|---|---|
| idris-mlir C++ comments (`foreign/idr`) | 21,363 | 13.3% | 1.5% | 13.6 | 18.8 | 9% | 30 |
| idris-mlir Idris doc comments (`compiler/src`) | 7,851 | 14.5% | 1.5% | 22.4 | 15.0 | 3% | 34 |
| idris-mlir lit test prose (`tests/idr`) | 8,316 | 13.5% | 1.1% | 11.4 | 22.0 | 14% | 33 |
| PINS.md + AGENTS.md + README.md | 4,597 | 8.3% | 0.8% | 13.3 | **40.1** | **27%** | 56 |
| upstream MLIR transforms (comments) | 55,752 | 10.6% | 0.2% | 1.4 | 13.5 | 2% | 15 |
| upstream MLIR tests (prose) | 17,276 | 6.1% | 0.2% | 1.2 | 19.3 | 7% | (CHECK syntax) |

What the numbers show:

- **Articles are not missing.** The claim "article-light" does not hold for
  the code. It holds only for list fragments in the docs.
- **Possessive chains are ten times as common as in MLIR.** Examples: "the
  owned stage's rule" (`Verify.cc:1`, `rc/loops.mlir:3`), "the clone's
  tails", "the callee's owner", "the dead box's cell", "the emitted
  module's call".
- **Nominal clauses are seven times as common.** "turns what it counted
  into loops", "what a call of `fn` may do", "what flows to it from what it
  reaches" (`Infer.cc:1`).
- **Colons and semicolons appear at twice MLIR's rate.** One sentence
  carries a definition, a qualification and an exception, separated by
  punctuation instead of broken into sentences.
- **The docs average 40 words a sentence.** That is three times upstream.
  More than a quarter of their sentences are over 35 words.

Upstream MLIR comments are short, imperative, and they name the thing: "Walk
the operations and collect ...". idris-mlir's comments are declarative and
abstract: "What X may do, from Y and Z." Each style is a choice. The
problem is that the abstract style makes the reader rebuild the concrete
picture every time, and an owner reviewing agent output does not have the
time for that.

### 1.2 Six patterns that hurt, with rewrites

**P1. Possessive chains and noun stacks.** Each `'s` adds one step of
indirection that the reader must resolve.

> Before (`tests/idr/rc/loops.mlir:2-4`): "Counting runs on functional code,
> and idr-tail-loops turns what it counted into loops, which keep the owned
> stage's rule (idris-mlir-opt verifies it after each pass)."
>
> After: "idr-rc inserts idr.inc and idr.dec into recursive functions. Then
> idr-tail-loops rewrites each self tail call as an scf.while. After both
> passes, every reference must still be consumed exactly once on every
> path. idris-mlir-opt checks this after each pass."

**P2. Private vocabulary, used before it is defined.** The frequency of
each term in comments is in parentheses: "key" (124), "label" (98),
"slot" (76), "round" (67), "consumer" (46), "leaves" (37), "meets" (23),
"closed call" (18), "only computes" (12), "owned stage" (12), "loop
breaker" (11), "binding time" (9), "static shape" (5). Each has a precise
meaning, and each is defined in exactly one file, often in passing. For
example, "label" means "the function a closure calls", and the term is
defined only in `Lower/Layout.h:61`. Someone new to the repo meets them all
in the first test they open.

> Before (`tests/idr/specialize/linear-shared.mlir:3-6`): "A call on a
> static shape moves the shape's leaves into the clone's call. Here the pair
> is read twice, so it outlives each call: a clone taking its linear field
> would use it a second time next to the pair."
>
> After: "idr-specialize normally clones a function for an argument that is
> partly known at compile time. The clone takes only the runtime parts of
> the argument. For `MkP a b` it would take `a` and `b` instead of the
> pair. Here @use passes the same pair to @first twice. A clone taking the
> linear field `a` directly would receive `a` twice, and that breaks
> linearity. So the pass must not specialize: both calls still pass the
> pair."

**P3. The whole idea in one sentence.** The worst case is
`Specialize/Raise.cc:1-17`: its first sentence is over 80 words, with three
nested parentheses and a semicolon inside a parenthesis.

> Before: "Raising: the single consumer of a call's result, an apply of it (of
> one field of it, `idr.field %r[@C, i]`, for an action in a constructor such
> as `MkIO f`, and through the one use of a linear value; the result may
> first pass a linear position, entered and used at once), moves into a
> clone of the callee that takes the apply's arguments too and returns what
> the apply returns (arity raising). In the clone, the apply ... moves to
> every tail of the body ..."
>
> After:
> ```
> // Arity raising.
> //
> // When a call's result is only ever applied, call a clone that takes the
> // apply's arguments too and does the apply itself:
> //
> //   %f = call @mk(%x)            %r = call @mk$raised(%x, %y)
> //   %r = idr.apply %f(%y)   ==>
> //
> // Inside the clone, the apply moves to every place the body returns from
> // (its "tails"). There it usually meets the idr.closure or idr.con that
> // the body built, and canonicalization folds the pair away. This is how
> // an IO action built by a recursive function becomes a loop: raising
> // turns `run (loop n)` into a self call, and idr-tail-loops turns the
> // self call into an scf.while.
> //
> // Also handled: the apply may read a field first (`MkIO f`), and the
> // result may pass through idr.lin.enter/use on the way.
> //
> // Safety: raising moves work from the call to the apply. So nothing
> // between them may observe the difference (see canRaise below).
> ```

**P4. Headlines that restate the name.** 105 comment lines begin
"Whether ..." or "What ..." (81 in C++, 24 in Idris). Many sit above a
function whose name already says it:

> Before (`Facts/Functions/TakesWorld.cc:1`): "// Whether a function takes a
> world." above `bool facts::takesWorld(func::FuncOp fn)`.
>
> After: delete it, or say why the question matters: "// A function that
> takes a world performs IO: a world reaches a function only as a
> parameter, never through a global."

**P5. Claims no test checks.** A comment that asserts a property reads as a
guarantee. The owner cannot tell which claims are enforced.

- `rc/loops.mlir:5-6` says "a string built along the way is carried
  owned". The only CHECK for `@drain` is `scf.while`. (The ownership
  verifier does enforce it implicitly, but the test does not say so. See
  2.1.)
- `tests/e2e/v3/vect/Main.idr:3-4` says the vector's "index exists at
  compile time only". The test has no `mlir.check` or `mlir.expect`, so
  only stdout is checked.
- 23 of the 36 commented e2e programs have no IR check at all. Their
  comments need an audit: does each claim have a check?

**P6. Error messages in the compiler's terms, not the user's.** Two real
messages (run in the scratchpad):

> Before: `Main:20:1--20:21:mlir backend: Main.combine: unsupported (runtime
> closure): an implementation chosen at runtime: ($resolved364 [__])`
>
> After: `Main.idr:20:1: unsupported (runtime closure): combine uses an
> interface implementation that is chosen at runtime (choose returns plus
> or times). This compiler resolves every implementation at compile time.
> Pass the operation as a plain function (Int -> Int -> Int) instead.`

> Before: `Poly:6:1--6:24:mlir backend: Poly.depth: unsupported
> (polymorphism): polymorphic recursion: Poly.depth calls Poly.depth with a
> type or an implementation that is not its own, unchanged`
>
> After: `Poly.idr:6:1: unsupported (polymorphism): depth calls itself at a
> different type (a becomes (a, a)). This compiler makes one copy of a
> polymorphic function per type, so this would need infinitely many. Make
> the recursive call use the same type.`

Internal errors say only `idris-mlir-cc: internal error: step 5 (idr-rc)
failed` (`idris-mlir-cc.cc:465`). Before exiting, they should write the
module that went into the failing step and print the next commands. MLIR
already has the mechanism: `PassManager::enableCrashReproducerGeneration`,
and `--mlir-print-ir-after-failure` (MLIR `PassManagement.md:1317,1429`).

> After: `internal error: idr-rc produced IR that fails the ownership
> verifier (see the error above). Input to idr-rc saved as prog.05-in.mlir.
> Reproduce: idris-mlir-opt prog.05-in.mlir --idr-rc. Shrink:
> idris-mlir-reduce ... Find the action: tools/bisect.sh ...`

### 1.3 What already reads well, and why

This is not all bad, and the good examples show the target:

- `Passes/TailLoops.cc:1-20` explains the transformation with an explicit
  payload shape: `(continue : i1, A, R)`. The reader can check the dump
  against it.
- `runtime/idris_rt.h` explains the header's count values as a list, each
  with a reason ("an overflow leaks the object instead of freeing it while
  it is still in use").
- `Simplify.cc:10-18` explains why the obvious approach
  (`OperationFingerPrint`) fails, with the upstream line that causes it.
  This is the best kind of why-comment.
- `tests/idr/specialize/binding-times.mlir` puts the Idris equation above
  each expected remark. The reader sees the source, then the verdict.
- `tests/idr/rc/verify.mlir` and `tests/idr/verify/linear.mlir` use
  `-verify-diagnostics`: small input, error on the line it concerns. These
  are the most readable tests in the repo.
- The op descriptions in `IdrOps.td:860-950` (inc, dec, reset, reuse, take)
  are clear. The problem is that only 6 of 63 ops have a `description`. The
  rest live in `//` comments that no tool can collect (4.1).

---

## 2. Tests

### 2.1 Case study: `tests/idr/rc/loops.mlir`

The file (57 lines) and what a newcomer runs into, in reading order:

1. **Line 1: `--idr-stack --idr-rc --idr-tail-loops`.** Three passes, and
   the file is in `rc/`. Which pass is under test? The output with and
   without `--idr-stack` is byte-identical (verified with `diff` in the
   scratchpad). The pass is noise that makes the reader wonder what it
   contributes.
2. **Lines 2-6, the comment.** It uses five concepts in one sentence:
   "counting", "functional code", "what it counted", "the owned stage's
   rule", and an implicit verifier. None is defined here.
3. **The main property is invisible.** The strongest check in this test is
   that idris-mlir-opt exits 0, because it runs the ownership verifier after
   each pass. That fact appears only in a parenthesis. No reader would guess
   that the RUN line itself is the assertion.
4. **Half the claim is unchecked by name.** "A string built along the way is
   carried owned": the `@drain` CHECKs look only for `scf.while`.
5. **The CHECK-NOT scope needs FileCheck expertise.** `CHECK-NOT: idr.inc`
   after `CHECK: scf.while` covers the text from `scf.while` to the next
   `CHECK-LABEL`. An inc hoisted before the loop would not be caught.
   `review-external.md` calls this "a test hole". The owner and the reviewer
   both had to reason about FileCheck's scoping rules. A named property,
   `counts-nothing=@sumAcc`, exists (`Expect/Counting.cc:36`) and says it
   directly.
6. **`CHECK-SAME: {idr.borrowed}`.** It matches anywhere on the signature
   line. It works only because `%acc` is an `i64` and cannot be borrowed.
7. **Noise.** `{quantities = [...]}` on both constructors is the dead
   attribute from `review-external.md`. `@root` exists only to keep the
   functions alive, and nothing says so.
8. **Naming.** `rc/loops.mlir` and `loops/tail-loop.mlir` test different
   things, but their names suggest otherwise.

**The rewrite.** It was verified in the scratchpad through the repo's own
harness (`tests/runner/one.sh`). It passes. It fails under
`--idr-rc=borrow=false`: RUN 1 reports `expected counts-nothing: idr.dec
in @sumAcc`. It also fails without `--idr-tail-loops`: RUN 2 finds the
recursive call.

```mlir
// Property: turning self tail calls into loops keeps reference counting exact.
//
// idr-rc inserts idr.inc and idr.dec into recursive functions; then
// idr-tail-loops rewrites each self tail call as an scf.while. The loop must
// count exactly as the recursion did:
//   - @sumAcc only reads its list, so idr-rc marks the list {idr.borrowed}
//     and inserts no inc or dec. The loop must stay free of counting.
//   - @drain appends to a string it owns, so the loop must release the old
//     string on every iteration.
//
// RUN 1 fails if the loop leaks or double-frees: idris-mlir-opt runs the
// ownership verifier ("every reference is consumed exactly once on every
// path") after each pass. It also fails if @sumAcc counts anything.
// RUN: idris-mlir-opt %s --idr-rc --idr-tail-loops \
// RUN:   --idr-expect=holds=counts-nothing=@sumAcc -o /dev/null
//
// RUN 2 fails if either function is still recursive, or if the list is not
// borrowed.
// RUN: idris-mlir-opt %s --idr-rc --idr-tail-loops | FileCheck %s
// CHECK-LABEL: func.func private @sumAcc(
// CHECK-SAME:    !idr.box<@L> {idr.borrowed}
// CHECK:         scf.while
// CHECK-NOT:     call @sumAcc
// CHECK-LABEL: func.func private @drain(
// CHECK:         scf.while
// CHECK-NOT:     call @drain
// CHECK-LABEL: func.func @root(

module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @N tag 0 ()
    idr.ctor @C tag 1 (i64, !idr.box<@L>)
  }

  // sumAcc acc []        = acc
  // sumAcc acc (h :: t)  = sumAcc (acc + h) t
  func.func private @sumAcc(...)          // body unchanged

  // drain []       s = s
  // drain (h :: t) s = drain t (s ++ show h)
  func.func private @drain(...)           // body unchanged

  // Calls both, so that neither is dead. Not under test.
  func.func @root(...)
}
```

With two small additions to idr-expect (2.5), RUN 2 becomes a property too,
and FileCheck goes away:

```
// RUN: idris-mlir-opt %s --idr-rc --idr-tail-loops -o /dev/null \
// RUN:   --idr-expect=holds=counts-nothing=@sumAcc,borrowed=@sumAcc:1,is-loop=@sumAcc,is-loop=@drain
```

### 2.2 Eighteen tests, judged

"Readable?" asks whether a competent compiler engineer new to the repo can
say, in about a minute, what the test checks and what bug would make it
fail.

| Test | What it checks | Readable? | Why |
|---|---|---|---|
| `idr/rc/loops.mlir` | tail loops keep counting exact | **No** | See 2.1 |
| `idr/rc/counts.mlir` | reuse in @map, nothing counted in @sum, one inc for a doubly used string | Partly | RUN 1 (idr-expect) is excellent. The comment for `@both` sits between `CHECK-LABEL` and its `CHECK-SAME`, so prose and checks interleave |
| `idr/rc/live.mlir` | no cell is live at exit | Partly | The property is clear. `%status 149` is an unexplained magic number: the reader must compute a sum mod 256 by hand |
| `idr/rc/twice.mlir` | idr-rc refuses an owned module | Yes | One sentence, one error |
| `idr/rc/verify.mlir` | ownership verifier rules | **Yes** | `-verify-diagnostics`, one case per split, the error on its line |
| `idr/verify/linear.mlir` | linear values used at most once | **Yes** | Same style |
| `idr/stack/expect.mlir` | no-heap-allocation treats stack cells right | Partly | It tests the test API and the pass together in 6 RUN lines. Dead `quantities` attribute |
| `idr/loops/tail-loop.mlir` | shape of the scf.while | Partly | The comment is good. 20 `CHECK-NEXT` lines pin the order of `ub.poison` constants. By AGENTS.md's own rule, that is a brittle test |
| `idr/specialize/binding-times.mlir` | binding time per parameter | Mostly | The Idris line above each remark is the best practice in the repo. But `@count: other, other` is annotated "an accumulator and a counter": why is a counter not "decreasing"? A reader cannot tell a bug from a design choice |
| `idr/specialize/linear-shared.mlir` | no specialization that would duplicate a linear field | **No** | Jargon ("static shape", "leaves", "clone's call"). See P2 |
| `idr/canon/case-of-case.mlir` | case-of-case rewrites | Mostly | Each case has its Idris expression (`fst (if b then (1, 2) else p)`). 37 `CHECK-NEXT` lines pin exact shapes |
| `idr/pipeline/fixpoint.mlir` | simplify reaches a fixpoint | Partly | "up to where sccp puts the constants, which it reverses on every run" is cryptic. `CHECK-NOT: func.func private @pow(` only covers the text between two matches |
| `idr/expect/quantities.mlir` | quantities-kept catches widening | **No** | The mutants are made by `sed` regexes inside RUN lines. The reader must run the sed in their head to see the input |
| `idr/eval/fold-vs-jit.mlir` | folders agree with JIT-run lowering | Partly | The property ("both runs give the same constant") is clear. But it is 1,165 lines with 343 CHECKs of literal constants, when `diff` of the two outputs would state it directly, as `obs/canonicalize.mlir` does |
| `idr/eval/crash.mlir` | a crashing call stays, with a remark | Yes | Small, and each CHECK is explained |
| `e2e/v1/specialization` | one clone per function argument, no closures left | Yes | Idris source with comments, `mlir.expect` names the property, stdin and stdout are visible |
| `e2e/v3/vect` | Vect programs run correctly | Yes as a behaviour test | The comment's claim about indices is unchecked (P5) |
| `properties/quantities-kept` | no pass drops a quantity, over all fixtures | Yes | One sentence, one named property |

The pattern: tests built on `-verify-diagnostics` and idr-expect are
readable. Long FileCheck tests with `CHECK-NEXT` chains are not. They also
break AGENTS.md's own rule: 47 of 140 dialect tests use `CHECK-NEXT`. For
scale, the median test is 52 lines with 6 CHECKs, and the p90 test is 139
lines with 24.

### 2.3 What makes a lit test readable

A reader needs four things, in this order:

1. **The property, in one sentence, first.** It should say what must hold
   and which pass is under test, not what the pass does in general.
2. **How it fails.** Each RUN line gets one line saying which bug makes it
   fail. This is what the owner lacked in `rc/loops.mlir`.
3. **The smallest input, with the source above it.** Put the Idris equation
   above each function, as `binding-times.mlir` does. Mark helper functions
   "not under test".
4. **Checks named after the property.** Use idr-expect properties, where
   the failure message is a sentence ("expected counts-nothing: idr.dec in
   @sumAcc"), or `-verify-diagnostics`. Keep FileCheck for what is truly
   textual: printer and parser round trips, remarks, and the shape of
   lowered code when the shape *is* the property.

What to avoid:

- more than one property per file;
- a pipeline with passes that are not under test;
- `CHECK-NEXT` chains through incidental ops;
- mutants built by `sed`;
- magic exit codes;
- claims in the comment that no RUN line checks.

### 2.4 Proposed test style

```mlir
// Property: <one sentence: what must hold, and which pass guarantees it>.
//
// <Two to five sentences of context: the input and the mechanism, in plain
// words. Define any term the reader might not know, or name the file that
// defines it.>
//
// RUN <n> fails if <the bug this line catches>.
// RUN: idris-mlir-opt %s --<pass under test> --idr-expect=holds=<property>=@f -o /dev/null
//
// (Only if the shape is the property:)
// RUN <m> fails if <...>.
// RUN: idris-mlir-opt %s --<pass> | FileCheck %s
// CHECK-LABEL: ...

module attributes {idr.program} {
  // <Idris source of @f, one or two lines>
  func.func private @f(...)

  // Keeps @f alive. Not under test.
  func.func @root(...)
}
```

Rules:

- **File name = property.** Use `rc/tail-loop-counting.mlir`, not
  `rc/loops.mlir`.
- **Rejections use `-verify-diagnostics` with `-split-input-file`**, one
  case per split, each with a one-line comment. This includes mutants: write
  the mutated module out as its own split, instead of making it with sed.
- **Exit codes are named in the comment**: "exits 149 = (385 + 1540 + ...)
  mod 256", or better, the program prints its result and the test checks
  stdout.
- **Differential tests diff.** "A and B agree" is `diff` of two outputs.
  Put the expected values in a separate table if they must be checked too.
- **One property per file.** Split `stack/expect.mlir` into "the
  no-heap-allocation property" (a test of idr-expect) and "idr-stack moves
  a non-escaping cell to the stack" (a test of the pass).

### 2.5 Test APIs to add (small)

These are the properties the rewrites need. Each is 20-40 lines in
`lib/Expect/`, in the style of `Counting.cc`:

- `is-loop=@f`: @f makes no self call, directly or through a clone
  (idr-tail-loops).
- `borrowed=@f:i`: parameter i of @f is borrowed (borrow inference).
- `no-self-call`: every function in the module, the same property as a
  pipeline-level check.
- `status-is=N` is not needed. Make programs print their result and check
  stdout instead.
- **Better locations in failure messages.** `counts-nothing` reported
  `idr.dec in @sumAcc` at the `idr.yield %acc` line and at the `arith.addi`
  line (scratchpad experiment): ops that idr-rc inserts borrow a
  neighbour's location. Give inserted ops a provenance location, for
  example `NameLoc("idr-rc: dec of %l after its last use", <loc of the
  last use>)`. Then diagnostics and dumps say *why* an op exists. (This is
  plain MLIR: `NameLoc` or `FusedLoc` with metadata.)

Also: the 140 dialect tests carry 282 wrapper files (`<test>/run`, which is
the same three lines each time, and `<test>/expected`, which is `RUN n: ok`
each time). They hold no information: the harness could derive both by
globbing `tests/idr/**/*.mlir`. See 3.

---

## 3. Scaffolding inventory

Lines are tracked lines (`git ls-files | xargs wc -l`). "Pays" means: it
catches a bug class that review alone would miss, or it saves more time
than it costs, at *this* size (one owner, about 23k lines of compiler).

### 3.1 The compiler proper

| Piece | Lines | Notes |
|---|---|---|
| `foreign/idr/lib` (passes, dialect, lowering, eval) | ~11,700 | Excluding the pieces below |
| `foreign/idr/include` (IdrOps.td, Passes.td, headers) | 1,677 | |
| `foreign/idr/tools` (opt, cc, reduce) | 642 | |
| `compiler/src` (Idris frontend, Core, Emit) | 5,434 | |
| `runtime/` | 1,936 | |
| **Total** | **~21,400** | |

The "15k lines of C++" in the review includes 892 lines of `Mlir.cppm`
(re-exports only), 907 lines of `foreign/idr/bench`, and 600 lines of
`lib/Expect`, which is a test API.

### 3.2 Process machinery

| Piece | Size | What it buys | Verdict |
|---|---|---|---|
| `AGENTS.md` | 55 lines | The real spec: the rules agents must follow | **Keep.** But it is written for agents. A human needs the overview in 4.1, and AGENTS.md should point to it |
| `PINS.md` | 374 lines, 25 entries, 38 `PIN()` sites | 4 entries are real upstream MLIR bugs with reproducers. 11 exist because of cpp-starter or its profile, which governs no code (see below): `mlir-cxx-api`, `runtime-quarantine`, `zones-on-demand`, `clang-libcxx`, `clang-no-reflection` and others. 2 more exist because of the modules migration (`cmake-module-restat`, `cmake-import-std-uuid`). About 8 are platform and toolchain facts (musl, x86_64, LLVM statistics, ThinLTO) | **Keep the 4 bug entries and the platform facts. Replace the 13 profile and modules entries with one paragraph.** The "tombstone ritual" on every bump is worth it only for the bug entries |
| `upstream/` + `tests/upstream` | 338 + 52 lines, 4 bugs | A reduced reproducer per workaround, and a test that fails when upstream fixes it. This is exemplary practice | **Keeps paying, with one caveat: all 4 are "not yet filed".** Machinery that is never filed is half-done. File them |
| cpp-starter profile: spec tests `cpp-starter`, `zones`, `build-preset`, `configure-gate`; PIN entries; CMake profile targets | ~120 lines of tests; ~10 PIN entries; ~80 lines of CMake | Keeps `CMakeLists.txt` matching a template. **The profile is waived for 100% of the C++:** `PIN(mlir-cxx-api)` makes all of `foreign/idr` "quarantine code", `PIN(runtime-quarantine)` does the same for `runtime/`, and the profile's `src/` and `unsafe/` zones do not exist (`PIN(zones-on-demand)`). The `cpp-starter` spec test greps `CMakeLists.txt` for its own flags: it checks that a file contains what it contains | **Ceremony. Cut.** Keep the useful flags as plain build settings (`-fno-exceptions -fno-rtti` as LLVM uses, `-Werror`, the clang-tidy lint preset, which is automatic). Drop the "profile" framing, the zone rules and the template-conformance tests |
| C++ modules migration (`MODULES.md`, `Mlir.cppm`, `lib/Facts` layout, `PIN(cmake-module-restat)`) | 91 + 892 lines; Facts is 720 lines in 25 files; one area of about 13 converted | Nothing yet. The motivation is the profile's "no headers" rule, and the profile is waived for this code. Cost: every name that MLIR code uses must be re-exported by hand. There are 9-line files such as `Functions/IsLibrary.cc`, whose body is one line. Build pitfalls are documented in 6 bullets. Mid-flight: HEAD~4 is "Work in progress from the modules agent" | **Revert.** Put Facts back in 3-4 `.cc` files with one header. Delete `Mlir.cppm`, `MODULES.md` and the restat pin. For readability, fewer, larger files organized by concept beat one function per file. Revisit when MLIR supports modules (the PIN itself says "not expected") |
| Hand-written lit (`tests/lib/lit.sh`) + 282 wrapper files + `pinned-test-tools` spec test | 87 + 789 lines, 282 files | Runs RUN lines without Python. But python3 is already a prerequisite (README, to build LLVM), and the pinned tree has the real lit (`llvm/utils/lit/lit.py`, with `--update-tests`) | **Replace with the real lit** and a 20-line `lit.cfg.py`. This deletes 282 files. It also gains `REQUIRES`, `XFAIL`, per-file parallelism, standard failure output, and test updating |
| Harness layers (`make` → `tests/Runner.idr` → `runner/one.sh` → `run` → `testutils.sh`, which re-executes itself under `timeout` → 19 `tests/lib/*.sh` → `lit.sh` → tool) | 1,567 + 1,589 lines | Timeouts on everything (AGENTS.md requires them, and they do catch hangs), a golden-output discipline, oracles | **Keep the oracles and the timeouts. Flatten the rest.** Seven layers between `make test-idr` and FileCheck is too many for a human to debug. With real lit, the dialect tests need one layer |
| `tests/spec` (20 tests) | 603 lines | Mixed. **Pays:** `frontend-imports`, `no-erased-inputs`, `no-primitive-semantics`, `emit-dialects`, `idris-pin`/`idris-pin-drift`, `timeouts`. They mechanize AGENTS.md rules that an agent *will* break and a reviewer will not notice. **Hygiene, fine:** `stale-stamps`, `lock`, `failed-bootstrap`, `llvm-bootstrap`, `idris-environment`. **Ceremony:** `cpp-starter`, `zones`, `build-preset`, `configure-gate`, `commands` (greps the Makefile for target names), `pin-sites` | **Keep 11, cut 6** |
| Oracles: Chez diff in every e2e test, `tests/fuzz`, `tests/equivalence` (eval vs no-eval), `tests/twolevels` (Idris's evaluator vs compiled code), `tests/toolchain/double-print` | ~1,800 lines of harness + Idris generators | Catch miscompilations that no property states. This is the machinery reviewer 2 asked for, and it already exists | **The most valuable scaffolding in the repo. Advertise it** (4.2) |
| `lib/Expect` (idr-expect) | 600 lines | Named properties: the test API that AGENTS.md asks for | **Pays. Grow it** (2.5) |
| `tools/bisect.sh`, `idris-mlir-reduce`, dumps, remarks, statistics, debug counters | ~400 lines | Steering tools: find the action that broke a program | **Pays. Document it in the overview** |
| `tools/bootstrap.sh`, `doctor.sh`, `verify-pins.sh`, `toolchain.lock.json` | 932 + 82 + 137 lines | A reproducible two-stage LLVM | Pays: the alternative is unreproducible bugs |
| `bench/gate` | 7,656 lines, mostly benchmark programs in C, Koka, Lean, SML and Go, plus 2,307 lines of hand-lowered MLIR | Comparison against other compilers | Pays as a goal-setter. The 2,307 hand-lowered lines are a design sketch: say so in its README |

**The honest summary.** About 70% of the process machinery pays: the
oracles, idr-expect, upstream/, the architectural spec tests, bisect, the
toolchain pinning and the timeouts. What does not pay is the style layer.
The cpp-starter profile, its PINS entries, its spec tests and the modules
migration it drives are over 1,200 lines and 300 files of ceremony that
constrain no line of compiler code. A human reading the repo meets that
layer first (`PINS.md` is linked from the README), and it makes the project
look bigger and more bureaucratic than it is.

---

## 4. Steerability

### 4.1 An exemplary human-steerable compiler of this kind

The goal: **a human owner can predict what the compiler does to their
program, see what each pass did, and spot a broken invariant, without
reading C++.** Agents write most of the code. The human's job is to steer
and to catch the bug classes that agents miss. From this repo's history,
those classes are: limits nobody checks (the header packing), attributes
nothing reads (`quantities`), tests that check less than they claim
(`rc/loops.mlir`), comment claims with no check behind them (P5), and
passes that silently weaken a guarantee.

Nine features, in order of leverage. References are to known practice.
Those in `sources/` are cited by path; the others (Go, rustc, Cranelift,
matklad) are from general knowledge.

1. **One page tells the whole story.** `ARCHITECTURE.md`, about 300 lines:
   - one diagram of the pipeline and its IR stages;
   - per stage, what holds and who checks it;
   - a code map (where each concept lives);
   - a glossary of about 25 terms;
   - "where to look when X goes wrong".

   Models: GHC's commentary pipeline page
   (`sources/docs/ghc/commentary-compiler-core-to-core-pipeline.md`), and
   matklad's ARCHITECTURE.md convention. A draft written against today's
   code is in `readability-architecture-draft.md`.

2. **An invariants table that is generated, not written.** Each invariant
   is a named checker: a verifier rule, an idr-expect property or an
   oracle. A tool lists them per stage (`idris-mlir-opt
   --list-invariants`). CI diffs that list, so **a weakened or deleted rule
   shows up as a one-line diff for the human to approve.** The draft table
   already surfaces three unchecked guarantees:
   - `idr.stack` "never escapes its frame" is trusted after idr-stack runs
     (`Dialect.cc:455-460` checks only its form);
   - header packing is unchecked (`review-external.md`);
   - "no self tail call remains" after idr-tail-loops is checked by nothing.

   A table like this makes such gaps visible *by construction*.

3. **The IR explains itself.**
   - *Values carry Idris names.* Emit writes `%0, %1, ...`
     (`build/ttc/.../Sum.mlir`), so dumps read `%arg3`. With a `NameLoc`
     per binder and MLIR's `--mlir-use-nameloc-as-prefix` (present in the
     pinned `AsmPrinter.cpp:202`), dumps print `%acc`, `%xs`, `%h`, `%t`.
     This was verified in the scratchpad: idr-rc and idr-tail-loops even
     propagate the names (`%acc_0`, `%xs_1`), because they copy locations.
     It is the cheapest large readability win in the repo.
   - *Inserted ops say why they exist* (provenance locations, 2.5).
   - *The stage is visible in every line.* Split the owned stage into its
     own dialect or types, as `review-external.md` and
     `mlir-idioms.md` 1.3 propose. Then a reader of a dump never has to
     check a module attribute to know which rules apply.
   - *Dumps are for humans by default.* Today every dump prints full
     absolute paths in debug locations, and a parameter's line becomes 300
     characters long. Print short locations, or none, unless asked.
   - *A generated dialect and pass reference.* 57 of 63 ops have no
     `description`; their semantics sit in `//` comments. Move them into
     `description` with a three-line example each. Generate the reference
     with `mlir-tblgen --gen-dialect-doc` and `--gen-pass-doc` (MLIR
     `Operations.md:1803`, `PassManagement.md:933`). This is how MLIR
     documents itself.

4. **A dump explorer.** `idris-mlir explain --fn sumAcc Prog.idr` writes one
   HTML page. The Idris source is on the left. The function after each
   pass is in a column, passes that changed it are highlighted, and remarks
   and statistics appear inline. This is Go's `GOSSAFUNC=f` `ssa.html`, the
   single best tool for a human to see what an optimizer did. The inputs
   exist already: `--dump-after=all`, MLIR's
   `--mlir-print-ir-after-change` and `--mlir-print-ir-tree-dir`
   (`PassManagement.md:1296,1363`), and remarks. The tool is about 300
   lines, most of it a Python or shell script that stitches the dumps
   together.

5. **Tests are specifications that a human reads in a minute.**
   - Use the style of 2.4.
   - Add a **curated gallery**: one blessed before/after diff per pass, on
     the smallest interesting program, checked in and regenerated by one
     command. These are like rustc's `tests/mir-opt/*.diff` files, blessed
     with `--bless`, or Cranelift's `precise-output` filetests. The gate
     stays property-based, per AGENTS.md. The gallery is the readable face
     of each pass: a staleness check, not a gate, so it cannot go brittle.
     With the real lit, `--update-tests` does the blessing.

6. **Every error says what to do next.**
   - *User errors* are in Idris terms. They name the construct, give the
     reason in one sentence, and suggest a rewrite (P6). They never show
     internal names like `$resolved364`.
   - *Internal errors* name the pass and the invariant. They save the pass
     input and print the reproduce, reduce and bisect commands.
   - *Budget errors* name the budget and the option that raises it.

7. **Each concept is defined in one place.**
   - Every term in the glossary has one defining comment at its home. Use
     GHC's `Note [Owned stage]` convention: a named, long-form note, cited
     elsewhere as `See Note [Owned stage]`. This is compatible with
     AGENTS.md's "comments do not cite documents", because Notes live in
     the code.
   - The prose style (section 5) keeps every other comment short.

8. **Scaffolding in proportion to the code.** Machinery that enforces a
   *semantic* rule that agents break stays, and is automatic. Machinery that
   enforces a *style* stays only if it is free (a formatter or clang-tidy).
   A human reading the repo top-down should meet the compiler before the
   process.

9. **A review loop built for agent output.**
   - Every agent change says which stage and invariant it touches, in a
     fixed line of the commit message.
   - The generated invariants list is diffed in CI (point 2).
   - A short checklist for the bug classes above:
     - Is any new limit checked?
     - Does any new attribute have a reader?
     - Does each test-comment claim have a RUN line?
     - Did a CHECK get weaker?

     The human reads the checklist answers, not the whole diff.

### 4.2 Where the repo stands against that

| Feature | Today | Gap |
|---|---|---|
| Overview | README has a text pipeline and version list. There is no stage table, no glossary and no code map | Large |
| Invariants | Strong, and machine-checked: verifier after every pass, ownership verifier, idr-expect, 5 whole-corpus properties, 4 oracles. But they are listed nowhere, so the reviewer did not find the fuzzer or the Chez diff | Medium: the checks exist, the map does not |
| Readable IR | No names, full paths in locations, 6 of 63 ops documented in ODS | Large, but cheap to close |
| Dump explorer | Dumps per step, remarks, statistics, action tracing, bisect.sh (all good) | Medium: the parts exist, the view does not |
| Test style | idr-expect and `-verify-diagnostics` are exemplary. 47 of 140 tests use `CHECK-NEXT` chains, and there are 282 wrapper files | Medium |
| Errors | Named rules (`Rule.idr`) are good. Messages leak internal names and never say what to do | Medium |
| One home per concept | Terms are defined once, but in passing and without a way to find them | Medium |
| Proportion | The style layer comes first: `PINS.md`, `MODULES.md` | Medium |
| Review loop | AGENTS.md is followed well, but nothing is aimed at the human reviewer | Large |

### 4.3 The path from here

Ordered by leverage per day of work. Each step is independent.

**Step 1: the entry point (1-2 days).**
- Land `ARCHITECTURE.md` from the draft: diagram, stage and invariants
  table, glossary, code map, reading a dump, where to look.
- Link it first in the README and in AGENTS.md.
- Delete the dead `quantities` attributes in the two tests.
- Rewrite `rc/loops.mlir` as in 2.1.

**Step 2: readable IR (2-3 days).**
- Emit writes a `NameLoc` per Idris binder.
- Dumps default to `--mlir-use-nameloc-as-prefix` and short locations.
  Check first that `quantities-kept` still finds parameters: it already
  unwraps `NameLoc` (`Expect/Quantities.cc:26`).
- Inserted ops get provenance locations.

**Step 3: the test style (1 week).**
- Switch to the real lit and delete the 282 wrapper files.
- Add `is-loop`, `borrowed` and `no-self-call` to idr-expect.
- Rewrite the ten worst tests from 2.2 in the template.
- Turn the 20 `CHECK-NEXT`-heavy tests into properties plus gallery diffs.
- Audit the 23 commented e2e programs without IR checks (P5).

**Step 4: messages (1 week).**
- Rewrite the `unsupported` messages in Idris terms with a next step: 21
  rules, each written once.
- Make internal errors write a reproducer.
- Use diagnostic metadata for the rule instead of the text prefix, as
  `mlir-idioms.md` section 2 suggests.

**Step 5: generated references and the explorer (1-2 weeks).**
- Move op semantics into ODS `description`, and generate the dialect and
  pass docs.
- Write `explain --fn`.
- Write `--list-invariants`, and diff its output in CI.

**Step 6: proportion (2-3 days, mostly deletion).**
- Revert the modules migration.
- Cut the cpp-starter layer (3.2).
- File the 4 upstream bugs.
- Shrink PINS.md to real workarounds.

**Step 7: prose (ongoing).**
- Apply the style guide (section 5) whenever a file is touched.
- Rewrite first the headers of the 10 passes a human reads most:
  Specialize, Raise, CaseOfCase, Sink, Rc, Borrow, Counts, ResetReuse,
  Escape and Simplify.

---

## 5. Proposed comment and prose style

This is written for agents and humans alike. It replaces the house style
where the two conflict.

**Rules.**

1. **Lead with the point, in one sentence of at most 25 words.** Say what
   the code does, or what must hold. Details come after.
2. **One idea per sentence.** Use at most one colon or semicolon in a
   sentence. When a sentence has "which", "whose" and a parenthesis, split
   it.
3. **Name things; do not nominalize.** Write "idr-rc inserts incs", not
   "what counting adds". Write "the verifier checks", not "the rule, which
   the verifier checks".
4. **At most one possessive per noun phrase.** Write "the rule of the owned
   stage" if you must, or better, "the ownership rule".
5. **Show one example for every transformation.** Write the before and
   after, in IR or Idris, in three to six lines (the Raise rewrite in P3).
6. **Define a term where it is first used in a file, or point to its
   Note.** Use the glossary's word; never coin a synonym.
7. **Say why, not what.** A comment that restates the function name gets
   deleted. A why-comment names the alternative that fails, as
   `Simplify.cc` does.
8. **Every claim in a test comment has a RUN line that checks it**, and the
   comment says which one.
9. **Error messages have four parts:**
   - what (in the user's terms);
   - where (a source location);
   - why (one sentence);
   - what to do next.
10. **Plain words over house words.**

    | House word | Plain word |
    |---|---|
    | "a function only computes" | "a function is pure" |
    | "meets" | "finds next to it" |
    | "tails" | "return points" |
    | "leaves" | "runtime parts" |

    Keep a house word only when no plain one exists, and then put it in the
    glossary.

**Three more before/after examples.**

> `Ownership/Verify.cc:1-5`. Before: "The owned stage's rule: each reference
> is consumed exactly once on every path. It extends the world's rule
> (Dialect.cc), which counts uses on the worst path, to exact counts: a
> walk of each function follows the references every value holds along the
> ops, taking the regions of a match as alternatives that must agree where
> they meet again."
>
> After: "The ownership verifier. After idr-rc, every reference must be
> consumed exactly once on every path, and this file checks that after
> every later pass. It walks each function in order and tracks how many
> references each value holds: a consuming use subtracts one, and idr.inc
> adds one. The regions of an idr.match are alternative paths. Each starts
> with the same counts and must end with the same counts. This is the
> exact-count version of the linearity check in Dialect.cc, which checks
> only that a world or `!idr.lin` value is used at most once."

> `Canonicalize/CaseOfCase.cc:1-6`. Before: "Case-of-case: the single
> consumer of a result of a match, another match included, moves into every
> region that yields, when in at least one of them it then meets a value it
> folds or canonicalizes against."
>
> After:
> ```
> // Case-of-case. When a match result has exactly one user, copy that user
> // into each region of the match, if that lets it fold in at least one:
> //
> //   %s = idr.match %m { N: yield "none"; J x: yield show(x) }
> //   put_str %s
> //   ==>
> //   idr.match %m { N: put_str "none"; J x: put_int x }
> //
> // The user runs exactly once on every path before and after.
> ```

> `Passes.td` (idr-specialize), before: "Raising comes first: a `func.call`
> whose result is only applied ... calls instead a clone that takes the
> apply's arguments or the world too, keyed by (callee, consumer); the
> consumer moves to the clone's tails."
>
> After: "Step 1, arity raising: a call whose result is only applied becomes
> a call of a clone that also takes the apply's arguments (see Raise.cc).
> Step 2, specialization: a call with an argument partly known at compile
> time becomes a call of a clone with that part substituted. Clones are
> shared: two calls with the same callee and the same known parts call one
> clone."

---

## What it means for idris-mlir (concrete, ordered)

1. Add `ARCHITECTURE.md` (the draft is in `readability-architecture-draft.md`),
   and link it first in the README and AGENTS.md.
2. Emit writes a `NameLoc` per Idris binder. Dumps use
   `--mlir-use-nameloc-as-prefix` and short locations. idr-rc and
   idr-tail-loops give inserted ops provenance locations.
3. Rewrite `rc/loops.mlir` as in 2.1 (verified). Adopt the 2.4 template.
   Add `is-loop`, `borrowed` and `no-self-call` to idr-expect.
4. Replace `tests/lib/lit.sh` and the 282 wrapper files with the pinned
   llvm-project's lit.
5. Revert the C++ modules migration, and cut the cpp-starter conformance
   layer: 6 spec tests and 13 PINS entries. Keep the flags that do
   work: `-Werror`, clang-tidy, no exceptions and no RTTI.
6. Rewrite the 21 `unsupported` messages as what, where, why, and what to
   do next, with no internal names. Internal errors write a reproducer.
7. Move op semantics into ODS `description`. Generate the dialect and pass
   docs.
8. Build `explain --fn` (a GOSSAFUNC-style HTML page) and
   `--list-invariants`, diffed in CI.
9. File the 4 upstream bugs.
10. Adopt the prose style of section 5. Rewrite the 10 most-read pass
    headers first.

## Open questions

- **Gallery diffs versus AGENTS.md.** "Tests check behaviour, not shape"
  is right for gates. Is a blessed, non-gating before/after diff per pass
  acceptable as documentation? Proposed: yes, as long as a stale diff
  fails only a separate `make gallery` check and never a gate.
- **Are prose metrics worth automating?** Sentence length and possessive
  chains in changed comment lines could be flagged by a 30-line script.
  This is conjecture: it may just become one more piece of ceremony.
  Measure again in a month instead.
- **Who is the reader of AGENTS.md versus ARCHITECTURE.md?** The rules
  apply to both. Proposed: ARCHITECTURE.md holds the design, AGENTS.md
  holds the working rules, and each links to the other.
- **Does `quantities-kept` depend on parameter locations** being positions
  in the emitted file? `Expect/Quantities.cc` says a parameter "is known by
  its location". If so, the NameLoc change must wrap the file location, not
  replace it. The unwrapping loop at `Quantities.cc:26` suggests wrapping
  already works. Verify before landing.
