# Uniqueness pipeline: the engineering design against our code

Stream "uniqueness-pipeline". memory-theory.md settled the theory and the
shape of the design: exclusivity as an `i1` that folds, owned-stage types,
`!idr.uniq<T>`, and inference on MLIR's DataFlow framework.
mlir-ownership-types.md, review-external-2.md ("the dream", steps 1-4) and
linear-libs.md settled the rest. This note does not redo any of that. It
turns it into engineering against the code as it is:
- `foreign/idr/lib/Ownership`: Borrow, ResetReuse, Take, Counting, Counts,
  Rc, Verify, Ops;
- `lib/Stack`, `lib/Lower/Counting.cc`, the ownership ops of `IdrOps.td`;
- `runtime/rc.cc`.

It also measures the potential, statically and dynamically, and it tests
four fixes as scratch builds of our own passes. Everything here was run in
the stream's scratch directory, against the built `idris-mlir`,
`idris-mlir-opt` and the pinned toolchain. The commands, scripts and raw
tables are in uniqueness-pipeline-experiments.md.

## The questions

1. How much is there to gain: how many runtime reuse tests, incs and decs
   do the tests/ and bench/ programs execute, and how many could go?
2. For each of the five steps (inference, untested reset, report and
   opt-in error, no counting for unique values, coexistence with Lean's
   runtime-checked reuse), what changes in which file:
   - the IR before and after;
   - what hand-written code goes, in favour of which MLIR mechanism;
   - the verifier rules;
   - the tests, as idr-expect properties;
   - the soundness argument, and the counterexamples it must reject.
3. How to close the three known gaps: the case-block split that loses
   reuse (bubble sort), contification, and the returned-parameter borrow
   (`pick xs = xs`).

## The answer in one page

**Measured, the biggest losses today are not the missing static proof.**
They are three defects in how reuse is placed, and one pass we do not have.
Each was confirmed by rebuilding one of our own passes in scratch and
rerunning the program. Outputs were identical; the owned-stage verifier
passed after every pass.

| defect | where | fix | measured |
|---|---|---|---|
| D1. A reset is placed after a use that consumes the box, so the callee always sees count 2 and copies | `ResetReuse.cc:106-115` (`dies`) | a use that may consume the box moves it: no reset after it | rbtree (n = 10^5): runtime reuse tests 5.13M → 3.10M; tests that find the cell exclusive 22% → 100%; incs 4.69M → 2.66M; cells freed unreused 2.85M → 0.82M. Time at n = 10^6: 2.06 s → 1.02 s |
| D2. `inc field; …; reset parent` where a take at the parent's death would move the field | `ResetReuse.cc:143-151` (`reset`) and `Counts.cc:152-156` | `idr.reset` becomes an `idr.take` at the death point; `idr.reset` is deleted | every remaining inc in rbtree (2.66M) is such a pair. With them read as moves, the static analysis proves 100% of rbtree's and cfold's tests exclusive (0 wrong verdicts at runtime) |
| D3. A returned parameter is borrowed (`pick xs = xs`), so the callee incs it and the caller's value is shared | `Borrow.cc:155-179` (`collect`) | a parameter that escapes by return is owned | cfold: incs 43k → 27k. Static proof 0% → 79% (100% with D2) |
| D4. An Idris `case`/`if` is a separate function (a case block), called from both arms after case-of-case; the upstream inliner refuses A→B→A (`Inliner.cpp:709-715`) | none today | contify: a private function whose only use is one call from another function is inlined with `mlir::inlineCall` | bubble sort n = 3000: reuses 0 → 2 sites, 0.37 s → 0.23 s. rbtree: cells freed unreused 0.82M → 0.10M (only the Leaf atoms); reuses 2.38M → 3.10M |

- A fifth defect keeps the flagship linear benchmark from compiling at all.
  `bench/gate/linear/linrb` fails in Emit: "'idr.match' op uses a linear
  value that is already used on the same path" (§6.4).
- With D1-D4 fixed, **rbtree is count-free by static proof.** The prototype
  analysis on MLIR's DataFlow framework proves every take exclusive (3.10M),
  every inc a move (2.66M) and every dec a free (2.46M). So rbtree runs no
  count test, no inc, and no dec test at all. All of that was checked
  against the runtime: no site the analysis calls exclusive ever met a
  shared cell.
- **Programs that really share data keep runtime tests, as they must.**
  - rbtree-ck: 85% of tests find the cell exclusive at runtime, and 0% can
    be proved.
  - deriv: 21% at runtime, 0% proved.
  - nqueens: 99.9% at runtime, 0% proved.

  So step 5 (coexistence) is the common case, not a corner.

**The design, in one line per step** (§2-§5 give the details):
0. **Prerequisites (D1-D5).**
   - take-at-death replaces reset, so one op, `idr.take`, does both;
   - escaping parameters are owned;
   - `idr-contify` (upstream `inlineCall`);
   - the Emit fix.
1. **Inference.** An `ExclusiveAnalysis :
   dataflow::SparseForwardDataFlowAnalysis`, loaded with the upstream
   `DeadCodeAnalysis` and `SparseConstantPropagation`.
   - It runs inside idr-rc, after counting.
   - Its lattice is (shared?, a static cover: the constructors of static
     cells the value may reach). The cover is new here and was measured
     necessary: cfold's `Var 1` leaves.
   - It commits the result as types: `!idr.uniq<T, [cover]>`.
   - Prototyped: 500 lines in scratch, of which the analysis is 150.
2. **Untested reset.** `idr.take` of a `!idr.uniq` operand yields a
   `!idr.cell<@T::@C>` instead of a nullable `!idr.token`.
   - LowerTake materializes the indicator as `arith.constant true`, and the
     pipeline's `canonicalize` deletes the test, the incs and the dec
     (checked on lowered code).
   - LowerReuse on a cell builds no null test, and stores no header for the
     same constructor.
3. **Report and demand.**
   - Every take that stays dynamic gets `remark::missed` (MLIR's remark
     engine, which idris-mlir-cc already streams with `--remarks`), with
     its reason.
   - `--directive in-place=F` turns those into `unsupported (in-place)`
     for F.
   - Default: no rejection.
4. **No counting for unique values.**
   - `!idr.uniq` values cannot be inc'd (an ODS constraint).
   - Their `idr.dec` lowers to a free of the tree without count tests.
   - Count-free cell layouts buy nothing: the count shares an 8-byte
     header with `info`.
5. **Coexistence.** `!idr.uniq` is a static fact about an ordinary counted
   cell of count 1.
   - Plain `!idr.box` keeps today's runtime path unchanged.
   - `idr.share` forgets the fact, and `idr.borrow` lends it.
   - Bufferization's `private-function-dynamic-ownership` `i1` is the
     measured-first extension for mixed call sites.

## 1. Where we start, measured

### 1.1 Static counts in the lowered code of tests/ and bench/

Sixty programs compiled with `--directive dump-mlir`:
- tests/e2e v1-v3 (46 programs; the v0 programs are scalar and have no
  heap);
- bench/ (8);
- bench/gate/suite (6 of 8: qsort and unionfind are rejected for arrays and
  `System`);
- bench/gate/linear (0 of 2: D5).

Counts are in the final idr form (after idr-tail-loops) and as runtime calls
in the lowered code after `canonicalize`.

| program | box takes (tests) | resets (tests) | reuses (null tests) | inc | dec box/token/other | lowered calls inc/dec/reset/free_cell |
|---|---:|---:|---:|---:|---:|---:|
| e2e-v3-prelude | 0 | 0 | 0 | 0 | 0/0/9 | 0/9/0/0 |
| e2e-v3-prelude-lists | 6 | 0 | 3 | 0 | 5/3/1 | 3/12/0/3 |
| e2e-v3-prelude-traverse | 2 | 0 | 0 | 0 | 1/2/0 | 1/3/0/2 |
| e2e-v3-prelude-show | 2 | 0 | 1 | 0 | 1/1/18 | 1/21/0/1 |
| e2e-v3-prelude-user-types | 0 | 0 | 0 | 0 | 0/0/2 | 0/2/0/0 |
| e2e-v3-vect | 12 | 0 | 4 | 5 | 18/8/7 | 11/37/0/8 |
| gate-rbtree | 13 | 36 | 79 | 48 | 29/24/0 | 62/42/36/24 |
| gate-rbtree-ck | 15 | 36 | 79 | 49 | 30/26/0 | 65/45/36/26 |
| gate-nqueens | 2 | 0 | 0 | 1 | 2/2/0 | 3/4/0/2 |
| gate-cfold | 12 | 4 | 22 | 5 | 6/12/0 | 13/18/4/12 |
| gate-binarytrees | 0 | 0 | 0 | 0 | 3/0/0 | 0/3/0/0 |
| gate-deriv | 119 | 0 | 61 | 105 | 145/84/2 | 233/266/0/84 |
| **all 60** | **183** | **76** | **249** | **213** | **240/162/39** | **392/462/76/162** |

**48 of the 60 programs count nothing at all.**
- Compile-time evaluation folds the e2e programs' data away.
- bench/ is numeric.

So the test corpus does not exercise uniqueness. The gate suite is where
the design can be measured, and its programs belong in tests/e2e with the
properties of §2-§5.

### 1.2 Dynamic counts, and what a static proof could remove

Measurement:
- Each program's idr-rc output was instrumented: an observer call before
  every take, reset, reuse, inc and dec records the header it sees.
- It was built the plain way (idr-tail-loops, idr-lower, LLVM -O2, the
  runtime archive), run on the gate's small inputs, and its output diffed
  against the program built by the real pipeline. All were identical.
- The static verdicts come from the prototype analysis (§2.1) in three
  modes:
  - **A**: on today's IR;
  - **B**: assuming every function's owned box parameters exclusive, which
    is the upper bound for cloning, not a sound verdict;
  - **M**: reading `inc field; … reset parent` as the move that D2 makes
    it.

"Tests" counts runtime exclusivity tests: box takes plus resets, without
takes of nullary constructors.
- "-v": the program with D1 fixed.
- "-c2": with D1, D3 and D4 fixed.

| program | tests | found exclusive at runtime | static A | static M | incs | incs that are moves | decs | decs that become frees (M) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| rbtree | 5,132,982 | 1,115,005 | 0 | 0 | 4,694,162 | 2,660,164 | 2,460,209 | 0 |
| rbtree-v | 3,098,984 | 3,098,984 | 0 | **3,098,984** | 2,660,164 | 2,660,164 | 2,460,209 | **2,460,209** |
| rbtree-c2 | 3,098,984 | 3,098,984 | 0 | **3,098,984** | 2,660,164 | 2,660,164 | 2,460,209 | **2,460,209** |
| rbtree-ck | 5,032,984 | 975,034 | 0 | 0 | 4,714,147 | 2,660,164 | 2,460,210 | 0 |
| rbtree-ck-c2 | 2,999,001 | 2,562,208 | 0 | 0 | 2,680,164 | 2,660,164 | 2,460,210 | 0 |
| cfold | 148,825 | 148,825 | 0 | 0 | 43,144 | 26,760 | 6,006 | 0 |
| cfold-c2 | 165,208 | 165,208 | 131,071 | **165,208** | 26,760 | 26,760 | 6,005 | **6,005** |
| deriv | 61,924 | 12,905 | 0 | 0 | 142,020 | 0 | 114,627 | 0 |
| nqueens | 1,965 | 1,964 | 0 | 0 | 2,056 | 0 | 1,966 | 0 |
| binarytrees | 0 | 0 | 0 | 0 | 0 | 0 | 5,458 | 5,458 |
| e2e-v3-prelude-lists | 19 | 19 | 19 | 19 | 0 | 0 | 3 | 2 |
| e2e-v3-vect | 44 | 3 | 3 | 3 | 8 | 0 | 40 | 13 |

**Soundness check of the prototype.** For every run, and every take or
reset that mode A or M calls static, the runtime found the cell exclusive
every time (`check_sound.py`). There were **0 violations** across 17
program variants.

Mode B has violations, as expected: it assumes what cloning would have to
establish. For example, rbtree's `ins` on the original IR (2.08M), and
deriv's shared subterms (33.6k).

**What the numbers say.**
- **rbtree** is Perceus's showcase, "an unshared tree: full reuse".
  - Today 78% of its reuse tests fail at runtime, and every one of those
    failures is self-inflicted (D1; §6.1).
  - With D1, 100% succeed at runtime.
  - With D2 the analysis proves all of them, plus every dec a free and
    every inc a move: zero counting.
- **cfold** succeeds 100% at runtime today.
  - It needs D3 (a returned borrowed parameter), the static cover (the
    constant `Var 1` leaves) and D2 to be proved.
- **rbtree-ck, deriv and nqueens** share for real: checkpoints, shared
  subterms, shared tails. Nothing can be proved there, and the runtime path
  is the right answer. The static half adds nothing to them, and the
  dynamic half loses nothing.
- **vect**: 41 of 44 tests fail because the cells are stack cells, which
  are "never exclusive" (`idris_rt.h:48-54`). That is the stack/reuse
  exclusion of memory-theory §6.6, and it is out of scope here.

### 1.3 Timings (n as noted, best-of-3 or mean-of-3, plain builds without LTO; noisy machine)

| program | today | fixed | what |
|---|---:|---:|---|
| rbtree, n = 10^6 | 2.06 s | 1.02 s (D1); 0.82 s (D1+D3+D4) | mean of 3 |
| rbtree-ck, n = 10^6 | 2.40 s | 1.74 s (D1+D3) | mean of 3 |
| bubble sort on a linear list, n = 3000 | 0.37 s | 0.23 s (D4) | the real pipeline via idris-mlir-opt on the contified emitted module |
| cfold, depth 20 | 0.57 s | 0.64 s (D1+D3) | no gain: D3's value is the static proof, not speed |

## 2. Step 1: uniqueness inference

### 2.1 The analysis, prototyped on MLIR's DataFlow framework

`ExclusiveAnalysis` is a
`dataflow::SparseForwardDataFlowAnalysis<ExclusiveLattice>`.
- It is loaded with `DeadCodeAnalysis` and `SparseConstantPropagation`
  into one `DataFlowSolver`.
- `initializeAndRun` runs on the module after counting.

The prototype (`proto/ExclProbe.cc` in the scratch directory; its core is
quoted in the experiments file) links against `libidr_dialect.a` and the
pinned MLIR, and runs on the real idr-rc dumps.
- **Lattice.** A value is `(bits, statics)`.
  - `bits` is a bitset: atom (a static cell), exclusive heap tree, shared.
    0 is the optimistic bottom.
  - `statics` is the set of constructors of static cells the value may
    reach, deeply.
  - `join` is the union. `exclusive()` means shared is not in the bits.
  - A take of `@C` is static iff the value is exclusive and `@C ∉ statics`.
    The per-constructor cover refines memory-theory's
    `exclusive < unknown`: a tree whose leaves include the static constant
    `Var 1` is still exclusive for every take of `Add` or `Mul`, which
    cannot be `Var`. Without the cover, cfold proves 0; with it, 79%.
- **Transfer functions (`visitOperation`).**
  - `idr.con`, `idr.reuse`: heap-exclusive iff every box-holding field is
    exclusive; the cover is the union of the fields'. A `con {idr.stack}`
    is shared.
  - `idr.constant`: an atom, whose cover is every constructor in the
    constant.
  - `idr.lin.enter`, `idr.lin.use`: the operand's value.
  - `idr.take`, `idr.field`: the fields of an exclusive value are
    exclusive (deep), with the same cover. Otherwise they are shared.
    Shallow runtime exclusivity does not pass down.
  - Match region arguments (`visitNonControlFlowArguments`): the same
    rule, from the scrutinee.
  - Anything else: shared.
  - Calls, returns and region yields are the framework's.
    - Private callees join their call sites
      (`AbstractSparseForwardDataFlowAnalysis::visitCallableOperation`,
      SparseAnalysis.cpp:263-290).
    - Results join the callee's returns (`visitCallOperation`, :229-261).
    - `idr.match`/`match_lit` yields go through our
      `RegionBranchOpInterface`, which works unchanged.
- **Taint on today's IR.** `idr.inc` has no result, so sharing is a fact
  about a path, not an SSA value. A value is joined with shared before
  solving (in `initialize`) when:
  - it has an `idr.inc`;
  - it was read (field or match argument) from a value that is tainted
    that way;
  - it is lent to a borrowed parameter that the callee incs (D3's escape).

  This approximation is flow-insensitive, and it held with 0 violations.
  With the typed owned stage (`%a, %b = idr.dup %v`, mlir-ownership-types)
  it becomes exact SSA provenance, and the taint set goes away.
- **Two changes the solver needs from us.**
  1. **Drop `idr.clone` at idr-rc.** A clone's self-reference in
     `idr.clone<@f, key>` is a non-call symbol use, so the framework sees
     unknown callers and every clone's parameters are pessimistic. That is
     deliberate for the simplify rounds (IdrOps.td:1008-1014), and pointless
     once they are over. The prototype strips it. Nothing after idr-rc
     reads it (only `Stack/Recursion.cc:23`, which runs before).
  2. **Functions a closure names keep unknown callers.** The framework does
     this by itself: an address-taken symbol has unknown callers.

**Before (real, `bump` from memory-theory §5, idr-rc dump).** The
prototype's verdicts:

```
0  take       Main.bump  bits=7 (atom|heap|shared)  runtime     -- joined: ys (inc'd) and build n
2  take       Main.bump  bits=7                     runtime
5  dec        root       bits=3                     free        -- bump's result: fresh or reused
8  dec        root       bits=7  tainted            count       -- ys, inc'd twice
```

With `--assume-exclusive-params` (mode B), both takes are static. Cloning
`bump` for its exclusive call sites (`bump (build n)`, `bump zs` after the
borrowed `total' zs`) gives exactly that.

**After (hand-written; the new types do not parse in the built tool):**

```mlir
// idr-rc: the exclusive clone; its callers pass what build returns.
func.func private @Main.bump$uniq(%arg0: !idr.lin<!idr.uniq<!idr.box<@Main.L>>>)
    -> !idr.uniq<!idr.box<@Main.L>> {
  %c1 = arith.constant 1 : i64
  %n = idr.constant #idr.con<@Main.L::@N, []> : !idr.uniq<!idr.box<@Main.L>>
  %1 = idr.lin.use %arg0 : !idr.lin<!idr.uniq<!idr.box<@Main.L>>>
  %2 = idr.match %1 : !idr.uniq<!idr.box<@Main.L>> -> (!idr.uniq<!idr.box<@Main.L>>) {
  case @N() {
    idr.yield %n : !idr.uniq<!idr.box<@Main.L>>
  }
  case @C(%h: i64, %t: !idr.box<@Main.L>) {
    %3:3 = idr.take %1 @Main.L::@C : !idr.uniq<!idr.box<@Main.L>>
             -> (!idr.cell<@Main.L::@C>, i64, !idr.uniq<!idr.box<@Main.L>>)
    %4 = arith.addi %3#1, %c1 : i64
    %5 = idr.lin.enter %3#2 : !idr.lin<!idr.uniq<!idr.box<@Main.L>>>
    %6 = func.call @Main.bump$uniq(%5) : (!idr.lin<!idr.uniq<!idr.box<@Main.L>>>)
           -> !idr.uniq<!idr.box<@Main.L>>
    %7 = idr.reuse %3#0 @Main.L::@C(%4, %6) : (i64, !idr.uniq<!idr.box<@Main.L>>)
           -> !idr.uniq<!idr.box<@Main.L>>
    idr.yield %7 : !idr.uniq<!idr.box<@Main.L>>
  }
  }
  return %2 : !idr.uniq<!idr.box<@Main.L>>
}
// root: a borrow lends the exclusive list and keeps it exclusive.
%25 = call @Main.build(%3) : (i64) -> !idr.uniq<!idr.box<@Main.L>>
%b  = idr.borrow %25 : !idr.uniq<!idr.box<@Main.L>> -> !idr.box<@Main.L>
%26 = call @Main.total$39$(%b) : (!idr.box<@Main.L>) -> i64
%27 = idr.lin.enter %25 : !idr.lin<!idr.uniq<!idr.box<@Main.L>>>
%28 = call @Main.bump$uniq(%27) : (...) -> !idr.uniq<!idr.box<@Main.L>>
```

Today's N case, `take @N -> token; dec token`, disappears: a nullary box
constructor is always a static atom, so its take yields no token (§6.5).

### 2.2 Files and passes

- **New:**
  - `lib/Ownership/Exclusive.cc`: the lattice, the analysis, the commit
    and the clone rule. About 300 lines, by the prototype.
  - `IdrOps.td` gets:
    - the type `!idr.uniq<T, [cover]>`;
    - the type `!idr.cell<@T::@C>`;
    - `idr.borrow` (a view, with no runtime form);
    - `idr.share` (forgets exclusivity, with no runtime form).
- **idr-rc (`Rc.cc:21-51`)** runs, in order:
  1. take-at-death (ResetReuse);
  2. borrow inference;
  3. counting;
  4. drop `idr.clone`;
  5. solve;
  6. clone for exclusive call sites (optional, §2.5);
  7. commit;
  8. the owned-stage verifier.
- **The commit** sets the types (`Value::setType`) of the values proved
  exclusive: parameters, results, and SSA values inside bodies.
  - At a use that needs the plain type (a borrowed call argument), it
    inserts `idr.borrow`.
  - At a consuming position of plain type (a closure capture, an apply
    argument, a field of a con that is not exclusive), it inserts
    `idr.share`.
  - The commit is keyed by value, not by type, so the dialect-conversion
    framework does not fit it. It is a direct walk.
- **Every op that takes a box** accepts `!idr.uniq` of it through a
  projection, as `unrestricted()` does for `!idr.lin` today
  (`Counting.cc:12`, Types). These ops are con fields, match scrutinee,
  field, tag, take, lin.enter/use, yield, return and dec.
  - `func.call` needs nothing: its verifier checks the signatures
    (FuncOps.cpp:80), and that check is the caller half of the entente.
  - `func.return` checks the callee half.
  - `scf.while`'s type rules make a loop carry `!idr.uniq` only when every
    iteration yields one.
- **What is not deleted:** the runtime test stays, as the dynamic path of
  §5.
- **What must not be copied:** Borrow.cc's hand-written fixpoint. The
  analysis sits on the solver from day one. Moving borrow inference onto
  `AbstractSparseBackwardDataFlowAnalysis` is memory-theory's path step 2,
  and is not needed here.

### 2.3 Verifier rules (local, after every pass)

- **U1.** The operand of `!idr.uniq<T, S>` is a box, or an unboxed sum
  with a box slot. S names constructors of the types reachable from T.
- **U2 (producers).**
  - An `idr.con`/`idr.reuse` result of `!idr.uniq` has every box-holding
    field `!idr.uniq`, with its cover contained in the result's.
  - An `idr.con {idr.stack}` is never `!idr.uniq`.
  - An `idr.constant` may be `!idr.uniq<T, S>` only if every constructor
    in it is nullary or in S. A fold that would turn a fresh
    constructor into static data therefore fails to materialize, and
    `OperationFolder` drops it (FoldUtils.cpp:275-300).
  - A take of a `!idr.uniq` gives `!idr.uniq` box-holding fields with the
    same cover. A take of a plain box gives plain fields.
- **U3 (no duplication).** `idr.inc` does not accept `!idr.uniq`, by an ODS
  operand constraint: `Idr_CountedType` loses it.
  - The owned-stage rule already checks "consumed exactly once on every
    path" for every tracked value (Verify.cc:110-120, 147-167), so a
    `!idr.uniq` value cannot be duplicated at all. Exclusivity holds by
    construction, not by trust.
- **U4.** `idr.borrow`'s result is used only before its owner's consuming
  use. That is Verify.cc's `alive()`/`owners` (:87-102), extended from
  `idr.field` to `idr.borrow`.

### 2.4 Tests (idr-expect properties)

- `exclusive-param=@f:i`: parameter i of @f is `!idr.uniq`.
- `exclusive-result=@f`.
- Must hold, as lit tests on idr-rc:
  - bump on a fresh list (the clone's parameter);
  - `let ys = build n in total' ys + total' (bump ys)` (a borrow, then a
    consume);
  - rbtree's `ins` after D1-D4;
  - cfold's `cfold`.
- Must not hold, as e2e tests diffed against Chez, and lit tests expecting
  the property to fail:
  - memory-theory §8's must-NOT list (Lin1, twoTails, a static tail, a
    field inc, the Esc leak, pick, a closure applied twice, a stack cell);
  - rbtree-ck's `insert`.
- Verifier negatives (lit, `%status 1`):
  - an `idr.inc` of a `!idr.uniq`;
  - a `!idr.uniq` con with a shared field;
  - a `!idr.uniq` constant with a non-nullary constructor outside its
    cover;
  - `func.call` passing a box to a `!idr.uniq` parameter (MLIR's own
    error).

### 2.5 Soundness, and what it must reject

- **Induction.** The solver is optimistic. The invariant "every value
  flowing into a private function's parameter is exclusive" holds by
  induction on the length of execution, as for SCCP. Every source of
  sharing enters the lattice as shared:
  - an inc;
  - a constant outside the cover;
  - a stack cell;
  - an unknown caller;
  - an apply's result;
  - a leaking borrow.
- **After the commit, types carry it.** U2 and U3 make "never
  duplicated since construction" a local property (Marshall 2022,
  Theorem 5: freshness plus linear edges).
- **Counterexamples, each rejected by one rule:**
  1. Lin1 (`bump ys` twice): the inc taints ys, and bump's parameter joins
     shared. Checked: bits 7.
  2. twoTails: `(ys, ys)` needs an inc.
  3. `bump (C n (C 2 (C 3 N)))`: the static tail puts `@C` in the cover, so
     every take of `@C` stays dynamic. A write to .rodata cannot happen.
  4. `let t = tail xs in (bump xs, total' t)`: the field inc taints xs
     (read-from propagation).
  5. `pick` returning its borrowed parameter: D3 makes the parameter owned.
     If it were not, the leak rule would taint the caller's argument.
  6. A closure applied twice: the function a closure names has unknown
     callers, so its parameters are shared.
  7. A stack cell passed to a reusing callee: a `con {idr.stack}` is
     shared.
  8. Mixed call sites (rbtree-ck's checkpoints): the join is shared.
     Checked: 0 static, 0 violations.
  9. `believe_me`/`assert_linear` stay rejected (memory-theory §7.1). The
     inference is unsound the day they are accepted.
- **Cloning.** One key per function: "every owned box parameter exclusive".
  - Iterate: solve, redirect call sites whose arguments are all exclusive
    to the clone, solve again. There is at most one clone per function.
  - On the measured suite, cloning adds nothing once D2 is in (A = M for
    rbtree and cfold). bump's mixed callers need it.
  - Build it second, when a program in tests/ needs it.

## 3. Step 2: untested reset for exclusive scrutinees

### 3.1 Lowering, checked

`LowerTake` (`Lower/Counting.cc:92-135`) keeps its one shape. The
condition of its `scf.if` is:
- `runtime.exclusive(cell)` (`Lower/Runtime.cc:147-154`) for a plain box;
- `arith.constant true` for a `!idr.uniq` box.

The pipeline's existing `canonicalize` step deletes the dead branch. This
was checked on the real lowered `bump`: in `07-idr-lower.mlir`, the take's
condition was replaced by `arith.constant true`, then
`idris-mlir-opt --canonicalize --cse` was run.
- **Before:** two loads, two compares, an `and`, an `scf.if` whose else
  branch calls `idris_rt_inc(tail)` and `idris_rt_dec(cell)`.
- **After:**

```mlir
%19 = func.call @Main.bump(%17) : (!llvm.ptr) -> !llvm.ptr
%20 = llvm.icmp "eq" %arg0, %2 : !llvm.ptr        // the reuse's null test: still there
%21 = scf.if %20 -> (!llvm.ptr) {
  %24 = llvm.call @idris_rt_cell(%1, %0) : (i64, i32) -> !llvm.ptr
  scf.yield %24 : !llvm.ptr
} else {
  llvm.store %5, %arg0 : i32, !llvm.ptr             // count := 1
  llvm.store %0, %8 : i32, !llvm.ptr                // info := C's
  scf.yield %arg0 : !llvm.ptr
}
```

The test, the incs and the dec are gone. What remains is removed by the
type of the token, not by LLVM: LLVM cannot know that `%arg0` is not null.
- `idr.take` of a `!idr.uniq` yields `!idr.cell<@T::@C>`, a token that is
  certainly present. `LowerReuse` (`:60-86`) on a cell builds no null test
  and no allocation branch.
- A reuse of the same constructor stores no header at all. The count is
  already 1, and the info word is the same (`cellInfo(tag, objs, kind)`).
  A different constructor of the same size stores only the info word.

So `bump$uniq` becomes: load, add, call, two stores. That is FP²'s fip
code, and a C programmer's.

### 3.2 Files, deletions, rules

- **Deleted.**
  - The last use of the reset machinery goes with D2 (§6.2): `ResetOp`
    (IdrOps.td:907-918), `LowerReset` (`Lower/Counting.cc:43-56`),
    `idris_rt_reset` (`rc.cc:139-151`), and the ResetOp cases of
    Borrow.cc:159 and Verify.cc:240.
  - `Verify.cc`'s `fits()` walk to the defining reset (:237-251): the
    cell's type names its constructor, so the size check reads the type.
  - `ResetReuse.cc:19-25`'s "planned" paragraph.
- **Rules.**
  - A `!idr.cell` is consumed exactly once: by `idr.reuse`, or by
    `idr.dec`, which frees the memory.
  - The reuse's constructor has the cell's size (layouts, as today).
  - A take of a `!idr.uniq<T, S>` whose constructor is in S is invalid: it
    must `idr.share` first.
- **The mechanism is bufferization's.** A constant ownership indicator
  folds `bufferization.dealloc` away in `buffer-deallocation-simplification`.
  Here upstream `canonicalize` folds `scf.if` on a constant. We write no
  fold of our own.

### 3.3 Tests

- `tests-nothing=@f` (new) generalizes `reuses-in-place`:
  - every take in @f is on a `!idr.uniq`;
  - every reuse builds in a `!idr.cell`;
  - no op in @f lowers to a runtime exclusivity test.
- Must hold: `bump$uniq`, rbtree's `ins` after D1-D4, cfold's `cfold`.
  This is the README's promise, stated as the property.
- e2e: rbtree and bubble built in tests/e2e with a runtime statistic
  (proposed `IDRIS_RT_STATS=1`: cells allocated, cells freed, runtime tests
  passed and failed). The expected result is "allocates exactly n cells".
  Today `IDRIS_RT_LIVE` reports only live cells.

### 3.4 Soundness

- A static take differs from the dynamic one only in skipping the branch
  its test would have taken anyway. The operand is exclusive by U2-U3, and
  never static for its constructor (U4 and the cover).
- A reuse into a `!idr.cell` writes memory that no other reference reaches.
- **Counterexamples:**
  - The static tail (the cover sends it to the runtime path, where the
    persistent cell's count 0 fails the test and is copied).
  - A stack cell (never `!idr.uniq`).
  - `idr-tail-loops` carrying a value around a loop. `scf.while` block
    arguments are `!idr.uniq` only if every yield is, so an iteration that
    can see a shared value carries a plain box.

## 4. Step 3: the report, and the opt-in rejecting error

memory-theory §6.11: never reject correct Idris by default. The gate
(`bench/gate/README.md`, experiment 4) says "reject linrb-shared". That
becomes: reject it under a demand.

- **Report.** After solving, walk back from each take that stays dynamic to
  the first place sharing entered, bounded by a visited set. The reason is
  one of:
  - "used again after `<loc>`" (an inc or dup, with the use that needed it);
  - "a compile-time constant of `@C`" (the cover);
  - "a stack cell";
  - "joined at `<call or yield loc>` with `<reason>`";
  - "lent to `<f>`, which keeps it" (a leaking borrow, before D3);
  - "the parameter of `<f>`, which a closure calls";
  - "a field of `<reason>`".

  It is emitted as
  `remark::missed(loc, RemarkOpts::name("reuse-tested").category("idr-rc").function(fn))`
  (mlir/IR/Remarks.h:711). That is MLIR's remark engine, which
  `idris-mlir-cc --remarks=<regex>` and `--remarks-file` already stream
  (`idris-mlir-cc.cc:75-80, 390-392`). It is One-Shot's `print-conflicts`
  in our terms.
- **Demand.** `tools/compile.sh --directive in-place=Main.ins` passes the
  directive to idris-mlir, which already reads `--directive` (`no-eval`,
  `dump-mlir`), and it reaches idr-rc as a pass option `in-place`.
  - For every function it names, a dynamic take is an error:
    `unsupported (in-place): the cell of @Main.Tree::@Node in Main.ins is
    tested at runtime: joined at Main.idr:88 (Main.mkMap) with a value used
    again after the call (as prev)`.
  - No language change and no pragma. The profile rejects unknown pragmas,
    which is why this is a directive.
- **README.** README.md:41-44 promises the rejection unconditionally. It
  should say "under `--directive in-place=`".
- **What it deletes:** nothing, and it writes no diagnostics framework: MLIR
  remarks, and the existing `unsupported` error path.
- **Tests:**
  - tests/profile reject: linrb-shared with the directive exits 1, naming
    the call site and "used again".
  - linrb with the directive compiles, which needs D5 fixed, and has
    `tests-nothing=@Main.ins` and `counts-nothing=@Main.ins`.
  - A remark test: `--remarks=idr-rc` on Lin1 prints the reason naming the
    second `bump ys`.
- **Soundness:** the report changes no code. The demand only rejects.

## 5. Step 4: no reference counting for values unique over their lifetime

- **Engineering.**
  - Under U3, `!idr.uniq` values carry no inc by construction.
  - Their `idr.dec` lowers by type to `idris_rt_free_tree(cell,
    hasStatics)`, a new entry beside `releaseAll` in `rc.cc`. It frees the
    cell and its box-holding slots without decrementing: the count is known
    to be 1.
    - With an empty cover, static children are impossible, so there are no
      loads of counts at all.
    - With a cover, a child whose count is 0 (static) is skipped.
    - Other counted slots (strings, bigs, closures) are dec'd as today.
  - This is `bufferization.dealloc … if (%true)` becoming `memref.dealloc`
    in `lower-deallocations`.
- **Measured potential** (mode M, D1-D4 fixed): rbtree 2.46M of 2.46M decs
  become frees, and 2.66M of 2.66M incs are moves that vanish with D2.
  - The whole program then counts nothing.
  - binarytrees: all 5,458 decs.
  - cfold: all 6,005 decs and 26,760 incs.
  - deriv, nqueens and rbtree-ck: none, because they share.
- **Count-free layouts are not worth a representation change.** The header
  is `{uint32_t count; uint32_t info;}` (`idris_rt.h:61-64`), and cells are
  8-byte slotted. Dropping the count saves 0 bytes. Every gain is in the
  ops, and step 4 removes those without touching the layout. That answers
  memory-theory's "count-free types" conjecture for this runtime: keep the
  word.
- **Tests:**
  - `frees-without-counting=@f`: every dec in @f drops a `!idr.uniq`, and
    there is no inc.
  - `counts-nothing=@Main.ins` on rbtree.
  - e2e: `IDRIS_RT_LIVE` 0 at exit, and the allocation statistic of §3.3.
- **Soundness:**
  - A `!idr.uniq` tree has count 1 at every cell that is not static (U2
    and U3).
  - Its fields are exclusive or covered statics.
  - Freeing without tests frees exactly the cells a dec would have freed.
  - **Counterexample:** a `!idr.uniq` list whose element is a shared
    string. The string slot is not box-holding, so it is dec'd, not freed.

## 6. The known gaps, and the defects found by measuring

### 6.1 D1: reset after a consuming use (found here)

rbtree's `ins` today (idr-rc dump, `isRed r` inlined into a match on `r`):

```mlir
idr.inc %6#5 : !idr.box<@Main.Tree>                                   // for the reset below
%16 = func.call @Main.ins$spec$1(%6#5, %arg1) : (!idr.box<@Main.Tree>, i64) -> !idr.box<@Main.Tree>
%17 = idr.reset %6#5 @Main.Tree::@Node : <@Main.Tree> -> !idr.token   // after ins consumed r
```

- **Why it happens.** `dies` (`ResetReuse.cc:100-116`) puts the reset after
  the box's last use. Here that use is the call that consumes it.
  Counting then keeps a second reference alive across the call.
- **The effect.** The callee's take of `r` always sees count 2 and copies.
  The caller's reset then succeeds, since the copy dropped a reference.
  One copy per level of every insert: 78% of rbtree's tests fail.
- **Lean's `Dmain`** skips only a ctor that stores x (`isCtorUsing`).
  Inlining `isRed` exposed the call case, which Lean's separate `isRed`
  never does.
- **Fix, tested in scratch:** in `dies`, a last use that may consume the
  box (a call, an apply, a con, a closure, a reuse, `lin.enter`/`lin.use`)
  moves it, and places no reset. Three lines.
- **Results:**
  - rbtree tests found exclusive: 22% → 100%;
  - time: 2.06 s → 1.02 s;
  - rbtree-ck: 2.40 s → 1.74 s (with D3 too);
  - the lit RUN lines of tests/idr/{rc,stack,lower} and expect/counting
    give the same exit status as the built tool.
- **Property** `resets-unshared=@f` (new): every take and reset in @f
  consumes a value that @f never incs, directly or through anything read
  from it. It would have caught D1.

### 6.2 D2: `idr.reset` becomes `idr.take` at the death point (found here)

- **What happens today.** When the box is still used in the region, D
  places `idr.reset` where it dies. Counting makes each field used after
  that point take its own reference where it is read (`Counts.cc:152-156`).
  The runtime reset then drops them again (`releaseOwned` in
  `idris_rt_reset`). So every such field is inc'd and dec'd. For the
  static analysis the parent looks shared, because its field was inc'd.
- **The change.** Emit `%tok, %f… = idr.take %box @C` at the death point
  (`ResetReuse.cc:143-151`). Replace the uses of the region's field
  arguments *after* it by the take's results; uses before it stay borrowed
  reads. The fields move with no count change on the exclusive path, as
  `takeAtEntry` (`Take.cc`) already does at a region's start. This is
  memory-theory §6.4's "prefer take", made the only form.
- **Measured** as the probe's M mode:
  - every one of rbtree's 2.66M remaining incs is such a pair;
  - with them read as moves, 100% of rbtree's and cfold's tests are proved
    (0 violations).
- **Deletes:** `idr.reset`, `LowerReset`, `idris_rt_reset`, and Verify.cc's
  reset case: one op for two.
- **Soundness.**
  - Before the take, the parent is alive, so borrowed reads are valid.
  - A field consumed before the parent dies needs a dup, which counting
    already inserts: the field is borrowed there. The take then yields the
    parent's own reference, which counting drops if unused.
  - **Counterexample** to check: `case p of C x xs => (consume xs, length p)`.
    xs gets a dup at the consume, `p` is taken after `length p`, and the
    take's xs is dropped. Counts end balanced (Verify.cc checks).

### 6.3 D3 and the known gap: the returned-parameter borrow (`pick xs = xs`)

- **What happens today.** `Borrow.cc:155-179` makes a parameter owned for
  resets and takes, owned call arguments, applies and stores, but not for
  return.
  - A returned borrowed parameter is inc'd by the callee.
  - The caller's value is then shared after the call (memory-theory §7.9).
  - cfold's `reassoc (e) = e` case is exactly this.
- **Fix, tested:** own the operands of `func.return` and of `idr.yield`
  (`own()` follows read-from chains). The global form uses the escape
  summaries idr-stack already computes: a parameter whose deep node
  escapes (`Stack/Escape.h:88-89`, `parameters`) is owned. That covers
  return, capture and store in one rule, and makes "a borrowed call
  preserves the caller's exclusivity" true by construction.
- **Measured:** cfold incs 43k → 27k. Proof 0% → 79%, and 100% with D2.
- **Test:** `counts-nothing=@pick`. Today pick incs its borrowed parameter
  to return it; owned, it counts nothing.

### 6.4 D4 and the known gaps: contification, and the case-block split (bubble sort)

The mechanism, from the emitted module of bubble sort:
- Emit writes `bubble`'s `if` as `case block 866 in bubble` with one call
  site, in tail position.
- In the first simplify round, case-of-case (`Dialect/Canonicalize/Meet.cc`)
  moves the call into both arms of `match_lit (x > y)`, passing the
  constants `True` and `False`.
- The upstream inliner then refuses the case block, because it calls
  `bubble` back (`Inliner.cpp:709-715`, "A->B->A").
- idr-specialize does not key on the constant Bool, because the case block
  is on a cycle (`Specialize.cc:5-9`).
- So `bubble` takes its cell and frees it (`idr.dec %token`), and the case
  block allocates a new one. architecture.md measured the same on tree
  insertion.

**Contify, tested on the real pipeline.**
- A private function whose only symbol use is one `func.call` from another
  function is inlined there with `mlir::inlineCall` (InliningUtils.h:152)
  and erased. The call graph policy of the upstream `Inliner` is not the
  utility's.
- It runs before the first simplify round, while each case block still has
  exactly one call.
- The prototype's `--contify` mode (40 lines) contified 84 functions in
  bubble's emitted module. Then `idris-mlir-opt --idr-simplify
  --idr-defunctionalize --canonicalize --idr-stack --idr-rc`:
  - `bubble` reuses its cell on both paths (2 `idr.reuse`, where there were
    0);
  - output identical;
  - 0.37 s → 0.23 s at n = 3000.
- On rbtree (with D1 and D3) it removed the remaining unreused cells:
  0.82M → 0.10M, the Leaf atoms.
- Is it load-bearing? It removes a function. It adds no attribute.
- Termination: each step removes a function.
- Counterexamples it must leave alone:
  - a function with two call sites (it is not a continuation);
  - an address-taken function (closures);
  - a function whose only use is its own recursive call.
- A function body ending in `ub.unreachable` cannot be inlined
  (PINS.md `inline-unreachable`). Such a case block must stay, as today.
- Fluet-Weeks' full A-analysis (several call sites with one continuation)
  is a later refinement. With contification before case-of-case, Idris
  case blocks never need it.
- **Property** `contified` (new): no private function other than a loop
  breaker has exactly one call site, in another function, and no other
  use.
- **Behaviour property** `reuses-every-cell=@f` (new): no cell a take in @f
  yields is freed; each is reused. This is the right property for bubble,
  whose N case must allocate, so today's `reuses-in-place` cannot hold.

### 6.5 D5 and small representation fixes

- **D5: linrb does not compile.**
  - `CaseF` (`compiler/src/IdrisMLIR/Emit/Bodies.idr:188-199`) coerces the
    scrutinee to plain with `idr.lin.use`.
  - It emits the default region with the old `env`, so a catch-all
    variable bound to the scrutinee (`a' => … ins kx vx a'`) uses the
    linear binder a second time.
  - The linear verifier rejects the emitted module: "'idr.match' op uses a
    linear value that is already used on the same path".
  - Rewriting the catch-alls as explicit patterns moves the error to
    `balance1`'s fall-through clauses. It is the same cause.
  - **Fix:** bind the scrutinee variable to the used value inside the
    regions. `coerce` re-enters it where a linear position needs it.
  - Until then the gate's experiment 4 cannot be run on the compiler.
- **A nullary box constructor's take yields no token.**
  - Today `take @N -> !idr.token; dec token` tests a static atom at
    runtime. The test always fails, then there is a `dec` of a persistent
    cell, then `free_cell(null)`. That is 100,000 times in rbtree and once
    per list end in bump.
  - Nullary box constructors are always static (`ConOp::fold`). Make that a
    rule (the ConOp verifier rejects a nullary box con after the fold), and
    give the nullary take no token.
  - representation.md R3's immediates would go further.
- **`ResetReuse.cc:166` copies discardable attributes** from con to reuse.
  - With `!idr.uniq` in types, no fact travels that way, and the copy
    should go (memory-theory-code-notes).

## 7. Step 5: coexistence with Lean-style runtime-checked reuse

- **One op, two types.**
  - `idr.take`/`idr.reuse`/`idr.dec` on a plain `!idr.box` is today's
    runtime path, unchanged: test, lazy per-cell copy (Perceus), nullable
    token, counted drop.
  - On a `!idr.uniq` it is the static path.
  - `!idr.uniq` is a static fact about an ordinary cell of count 1. So
    `idr.share` needs no runtime action. After it the cell is an ordinary
    counted cell, and every dynamic op works on it.
  - The runtime never sees two kinds of cells. rc.cc changes only by
    adding `free_tree`.
- **Where the dynamic path stays, measured:**
  - rbtree-ck: 85% of tests succeed at runtime, 0% can be proved;
  - deriv: 21%;
  - nqueens: 99.9%, because shared tails leave a few conflicts;
  - stack cells (vect): the stack/reuse exclusion, until escape summaries
    get reuse-equivalence edges (memory-theory §6.6).
- **The optional extension, measure first:** bufferization's
  `private-function-dynamic-ownership` (Bufferization Passes.td:119-142).
  - It adds an `i1` argument per memref argument of a private function, so
    that ownership crosses calls dynamically.
  - Ours would be "deeply exclusive by construction", passed with each
    owned box argument. Takes lower to `%i1 ∨ rt_is_unique(cell)`.
  - A true `i1` makes the fields' `i1` true: deep exclusivity survives a
    mixed join, where the runtime test alone is shallow.
  - Upstream `sccp` folds it where constant.
  - Its payoff is bounded by rbtree-ck's 2.56M runtime successes, most of
    which the runtime test already finds. So it waits for a program where
    deep propagation matters.
- **Tests:**
  - rbtree-ck, deriv and nqueens outputs equal Chez's (the differential
    oracle);
  - the runtime statistic shows their reuse rates. A drop in the rate is a
    regression.
- **Soundness:**
  - The dynamic path is today's, and it is correct.
  - The static path is a subset of the dynamic path's behaviours: the
    exclusive branch.
  - `idr.share` only forgets.
  - Counterexample: a `!idr.uniq` value captured by a closure that is
    applied twice. `share` at the capture makes it plain, and the apply
    borrows and incs, as today.

## 8. The pipeline, in order

1. `idr-contify` (new, upstream `inlineCall`): before `idr-simplify`, or as
   its first step in round 1. Fixes D4.
2. The simplify group, `idr-defunctionalize`, `canonicalize`, `idr-stack`:
   unchanged.
3. `idr-rc`:
   1. take-at-death reset/reuse (D1, D2);
   2. borrow inference with escaping parameters owned (D3);
   3. counting;
   4. drop `idr.clone`;
   5. `ExclusiveAnalysis` on the DataFlow solver;
   6. optional clones;
   7. commit to `!idr.uniq`/`!idr.cell`, with `idr.borrow`/`idr.share`;
   8. report and demand (step 3).
4. `idr-tail-loops`: `scf.while` carries the types.
5. `idr-lower`: take, reuse and dec lower by type. Upstream `canonicalize`
   deletes the constant-true branches (step 2), and `free_tree` handles
   uniq drops (step 4).

**Order of work, by measured payoff per line of code:**
1. D1 (3 lines, 2x on rbtree);
2. D4 (contify, 1.6x on bubble);
3. D5 (unblocks linrb);
4. D3;
5. D2 (deletes an op);
6. step 1 with the taint rule, and steps 2 and 4;
7. step 3;
8. the typed owned stage, which turns the taint rule into SSA;
9. cloning, and the dynamic-ownership `i1`, only when a program in tests/
   needs them.

## 9. Open questions

- **Cloning vs. loop versioning for mixed callers.** On this suite cloning
  buys nothing once D2 is in. bump-style mixed callers need it. Is one key
  per function enough in real programs?
- **Stack and exclusivity** (vect: 41 of 44 tests fail on stack cells).
  Should idr-stack run with a reuse-equivalence edge, or after the
  analysis?
- **The cover's size.** In the measured programs a cover lists at most a
  few constructors (cfold: `Var`). A cap, with "any constructor" as top,
  bounds the lattice.
- **D2's interaction with Counts.cc's placement.** The field-inc rule
  (`Counts.cc:152-156`) should apply only to fields read after a take
  that is not at the region's start. Its tests (tests/idr/rc/counts.mlir)
  must be restated as properties first.
- **An allocation statistic in the runtime** (`IDRIS_RT_STATS`) is the
  test API that every e2e property of this note wants.
