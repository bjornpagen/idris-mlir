# Uniqueness pipeline: experiments, scripts and raw data

The companion of uniqueness-pipeline.md. Everything ran in the stream's
scratch directory, `research/uniqueness-pipeline/` under the session
scratchpad. Nothing was built in the repository tree. Each tool invocation
was wrapped in `timeout`, and each compile took the shared lock.

## The tools

- **`cc.sh`** runs `tools/compile.sh` with the Makefile's environment
  (`IDRIS2_PREFIX`, `PATH`, `IDRIS_MLIR_ROOT`, `CHEZ`) under
  `flock -s build/.tree.lock`.
- **`one.sh NAME SRCDIR INPUT`** copies the sources, compiles with
  `--directive dump-mlir`, and runs `static_count.py` on the dumps.
  - It counts in `06-idr-tail-loops.mlir`: box takes, sum takes, resets,
    reuses, incs by type, decs by type, box cons, stack cons.
  - It counts in `08-canonicalize.mlir`: calls of `idris_rt_inc`, `_dec`,
    `_reset` and `_free_cell`.
- **`instrument.py`** (with `gen_cnt.py` and `run_inst.sh`) inserts, before
  every take of a box, reset, reuse, inc and dec in `05-idr-rc.mlir`, a call
  of a C observer. The observer records per site:
  - hits;
  - count == 1;
  - persistent (count 0);
  - stack bit;
  - immediate.

  The instrumented module is built the plain way:
  `idris-mlir-opt --idr-tail-loops --idr-lower --canonicalize --cse
  --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts`, then
  `mlir-translate`, then clang -O2 `-march=x86-64-v3`, static-pie, with
  `libidris_rt.a` and `-lgmp`. It is run on the input, and its output is
  compared with the program built by the real pipeline. **Every output was
  identical.**
- **`plain.sh IN OUT`** is the same build without the observers, and is
  used for the timings. It has no LTO, so the runtime calls are not
  inlined, unlike `idris-mlir-cc`.
- **`proto/excl-probe`** is the exclusivity analysis prototype. It is
  `ExclProbe.cc`, 500 lines, compiled with the flags of
  `compile_commands.json` and linked with the exact link line of
  `idris-mlir-opt` from `build/dev/build.ninja`. It links against
  `libidr_dialect.a`.
  - `excl-probe FILE` prints one line per take, reset, reuse, inc and dec,
    in textual order: site, kind, function, lattice bits, verdict, and
    whether the value is tainted.
  - `--assume-exclusive-params` is mode B.
  - `EXCL_MOVES=1` is mode M.
  - `EXCL_DEBUG=1` prints each function's parameter lattices and the call
    arguments that are shared.
  - `--contify IN OUT` runs the contification of §6.4.
- **`variant/opt-v`** and **`variant/opt-v2`** are `idris-mlir-opt` linked
  from its own object file. A copy of `libidr_dialect.a` has the
  `ResetReuse.cc.o` member (v), and then the `Borrow.cc.o` member too (v2),
  replaced by the scratch sources below.
  - `mk.sh`/`mk2.sh NAME` run `--idr-stack --idr-rc` of the variant on the
    program's `03-canonicalize.mlir`.
  - `mk3.sh NAME` first contifies the emitted module, runs the real
    `--idr-simplify --idr-defunctionalize --canonicalize`, then v2's
    `--idr-stack --idr-rc`.
  - Each then instruments, runs and joins.
- **`join.py`**, **`table.py`** and **`check_sound.py`** join the probe's
  verdicts with the dynamic counts.
  - `check_sound.py` lists every site where a verdict of "static" (mode A
    or M) met a cell that was not exclusive at runtime.
  - It found **none**, over rbtree, rbtree-v, rbtree-v2, rbtree-c2,
    rbtree-ck-v, rbtree-ck-v2, rbtree-ck-c2, cfold, cfold-v2, cfold-c2,
    deriv-v2, deriv-c2, nqueens-v2, nqueens-c2, binarytrees-c2, vect,
    vect-v2, prelude-lists, prelude-lists-v2 and prelude-show.
- **The existing lit RUN lines** of `tests/idr/{rc,stack,lower}/*.mlir` and
  `tests/idr/expect/counting.mlir` were run with both the built
  `idris-mlir-opt` and `opt-v2`. The exit statuses were identical file for
  file; the substitution of `%s`, `not` and `FileCheck` was crude, so some
  lines fail identically with both.

## The two pass variants

D1, reset after a consuming use (`ResetReuse.cc`, in `dies`):

```diff
@@ -106,6 +106,11 @@
     Operation *last = users.back();
     if (last->hasTrait<OpTrait::IsTerminator>())
       return;
+    // A use that may consume the box moves it on: a reset after it would
+    // keep a second reference alive across the use, and turn the in-place
+    // update of whoever receives the box into a copy.
+    if (isa<func::CallOp, ApplyOp, ConOp, ClosureOp, ReuseOp, LinEnterOp, LinUseOp>(last))
+      return;
```

D3, a returned parameter is owned (`Borrow.cc`, in `collect`):

```diff
@@ -174,6 +174,12 @@
       } else if (isa<ConOp, ClosureOp, ReuseOp>(op)) {
         for (Value operand : op->getOperands())
           ownIfParam(operand);
+      } else if (isa<func::ReturnOp, YieldOp>(op)) {
+        // A parameter that is returned escapes the call: borrowed, the
+        // callee would take a reference of its own to return, and the
+        // caller's value would be shared from then on.
+        for (Value operand : op->getOperands())
+          own(operand);
       }
```

D4, contification (in the probe):

```cpp
int contify(ModuleOp module) {
  InlinerInterface interface(module.getContext());
  InlinerConfig config;
  int count = 0;
  for (bool changed = true; changed;) {
    changed = false;
    for (auto fn : llvm::make_early_inc_range(module.getOps<func::FuncOp>())) {
      if (fn.isPublic() || fn.isExternal())
        continue;
      auto uses = SymbolTable::getSymbolUses(fn, module);
      if (!uses || !llvm::hasSingleElement(*uses))
        continue;
      auto call = dyn_cast<func::CallOp>(uses->begin()->getUser());
      if (!call || call->getParentOfType<func::FuncOp>() == fn)
        continue;
      if (failed(inlineCall(interface, config.getCloneCallback(), call, fn, &fn.getBody(),
                            /*shouldCloneInlinedRegion=*/false)))
        continue;
      call.erase();
      fn.erase();
      ++count;
      changed = true;
    }
  }
  return count;
}
```

It contified 84 functions in bubble's emitted module, and 96 in rbtree's.
The result verifies, and it runs through the real pass list.

## The analysis core (prototype)

```cpp
struct Excl {
  uint8_t bits = 0;                        // 1 atom (static), 2 exclusive heap tree, 4 shared; 0 bottom
  llvm::SmallVector<Attribute, 2> statics; // constructors of static cells reachable (deep)
  static Excl join(const Excl &a, const Excl &b);   // union of both
  bool exclusive() const { return bits != 0 && (bits & 4) == 0; }
};
class ExclLattice : public dataflow::Lattice<Excl> { ... };

class ExclAnalysis : public dataflow::SparseForwardDataFlowAnalysis<ExclLattice> {
  // initialize(): join `shared` into every tainted value, then the base's.
  // setToEntryState(): shared (mode B: exclusive for owned box parameters).
  // visitOperation():
  //   con {idr.stack}          -> shared
  //   con, reuse               -> heap-exclusive iff every box-holding field is exclusive;
  //                               cover = union of the fields' covers
  //   constant                 -> atom; cover = every constructor in the attribute
  //   lin.enter, lin.use       -> the operand's value
  //   take, field              -> exclusive (atom|heap) iff the operand is; same cover
  //   anything else            -> shared
  // visitNonControlFlowArguments(): a match's case arguments, from the scrutinee as take.
  // Calls, returns, yields: the framework (private callees join call sites).
};
// Solver: DeadCodeAnalysis + SparseConstantPropagation + ExclAnalysis;
// idr.clone attributes stripped first (their self-reference hides callers).
// Verdict: take/reset of @C is static iff exclusive() and @C not in statics;
// a take of a nullary constructor is "nullary"; a dec of an exclusive value is "free".
```

The taint set, before solving:
- every value with an `idr.inc`;
- every value it was read from (`idr.field` operand, match scrutinee),
  transitively;
- every value passed to a borrowed parameter that "leaks", meaning the
  callee incs it or lends it to a leaking parameter, computed to a
  fixpoint;
- the `lin.enter`/`lin.use` aliases of each.

In mode M, an inc of a field whose parent has an `idr.reset` user is read
as a move, and taints neither.

## Raw data

### Static counts: 64 programs

All compile except:
- gate-qsort: `%extern prim__newArray`;
- gate-unionfind: imports `System`;
- gate-linrb and gate-linrb-shared: D5, an internal error in Emit.

The 48 programs not listed in the note's table have every count 0:
- all of tests/e2e/v1 and v2;
- bench/{ack, ackdyn, collatz, fib, harmonic, mandelbrot, nbody, tak};
- e2e-v3 call-pattern, choice, compile-time-evaluation, missing-case,
  partial-*, prelude-input, prelude-io, prelude-math, show-values,
  specialize-growing-accumulator, static-evaluation and symbols.

### Dynamic, per function (rbtree, n = 10^5, today)

| function | kind | sites | executions | cell exclusive |
|---|---|---:|---:|---:|
| ins$spec$1 | inc | 24 | 4,224,726 | - |
| ins$spec$1 | take | 6 | 2,709,091 | 738,522 |
| ins$spec$1 | dec of a token (cell freed unreused) | 12 | 2,569,113 | - |
| ins$spec$1 | dec | 14 | 2,194,180 | - |
| ins$spec$1 | reuse | 39 | 2,070,546 | - |
| ins$spec$1 | reset | 18 | 1,930,568 | 189,976 |
| ins$spec$2 | (the same pattern, 10% of the keys) | | | |
| case block in makeTree | take | 1 | 100,000 | 100,000 |

### After D1 (rbtree-v)

- Takes 3,099,006, of which 2,999,006 exclusive. The other 100,000 are
  takes of the static `Leaf` atom.
- Resets 99,978, all exclusive.
- Incs 2,660,164.
- Decs of tokens 815,030.

### After D1, D3 and D4 (rbtree-c2)

- Decs of tokens 100,000: only the `Leaf` takes.
- Reuses 3,098,984.

### bubble (n = 3000), the real pass list on the emitted module

| | `idr.reuse` in the module | tokens freed (static sites) | time |
|---|---:|---:|---:|
| as emitted | 0 | 4 | 0.33-0.40 s |
| contified first | 2 | 3 | 0.20-0.28 s |

An earlier hand-contified version, made from the `03-canonicalize.mlir`
dump by replacing the two case-block calls with their bodies, ran in
0.18-0.19 s. Today's build ran in 0.30-0.39 s.

### Lowered `bump`, constant-true indicator

In `07-idr-lower.mlir`, `%25 = llvm.and %20, %24 : i1` was replaced with
`%25 = arith.constant true`, then `idris-mlir-opt --canonicalize --cse` was
run.
- The `scf.if` with the incs and the dec disappears.
- The reuse's `llvm.icmp "eq" %arg0, null` and the two header stores
  remain. These are what `!idr.cell<@T::@C>` removes.

### linrb (D5)

```
Main.idr:52:10: error: 'idr.match' op uses a linear value that is already used on the same path
    then case a of
```

The emitted `ins` matches `%0 = idr.lin.use %arg3`, and its default region
passes `%arg3` (the linear binder) to `Main.ins` again.
- Rewriting both catch-alls of `ins` as explicit `Node Black …`/`Leaf`
  patterns moves the error to `balance1` (Main.idr:23), whose fall-through
  clauses re-read the matched fields.
- The cause is `CaseF` in `Emit/Bodies.idr:188-199`: it coerces the
  scrutinee with `coerce ix l Plain (env x)`, but emits each region with
  the unchanged `env`.

## Loose notes

- The probe's taint rule is flow-insensitive: a value inc'd anywhere is
  shared everywhere. It proved nothing wrong, and it was precise enough
  for rbtree and cfold once D1-D3 were in. The typed owned stage
  (`idr.dup` with results) makes it exact at no cost, which is one more
  reason for that step.
- `idr.clone`'s self-reference was the single largest source of
  imprecision before it was stripped. Every specialized `ins$spec$N` had
  pessimistic parameters.
- Mode B's violations are the cloning question in numbers. For rbtree
  today, 2.08M of the 2.18M takes it assumes exclusive are not. The
  sharing comes from the caller's reset (D1), which no clone can fix. After
  D1, mode B has 0 violations on rbtree, and it is no longer needed there.
- The gate's hand-lowered `linrb-static.mlir` (experiment 4) is exactly
  what steps 1-4 produce for linrb: no count test, no null test, no dup.
  Its measured 1.24 s against 1.49 s for the dynamic version is the
  upper bound of step 2 alone. D1 and D4 are worth more on rbtree (2x and
  1.25x).
