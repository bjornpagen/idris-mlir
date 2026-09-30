# [mlir][scf] `upliftWhileToForLoop` gives the counter's result one step short

At `llvmorg-23.1.2`, `scf::upliftWhileToForLoop` (and so
`populateUpliftWhileToForPatterns`) replaces the `scf.while` result that
holds the induction variable with the value the variable has in the *last
iteration*, not the value the loop ends with. An `scf.while` returns what
its `scf.condition` forwards when the condition is false: for
`while (i < n) i += step`, the first `i` that is not below `n`.

## Reproduce

No `mlir-opt` pass runs the uplift outside MLIR's test passes, so the
reproducer is a small program against the MLIR libraries (`uplift.cpp`,
built by `CMakeLists.txt`) that applies the patterns, with the greedy
driver's folding, to `counter.mlir`:

```mlir
func.func @count() -> index {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %c10 = arith.constant 10 : index
  %r = scf.while (%i = %c0) : (index) -> index {
    %go = arith.cmpi slt, %i, %c10 : index
    scf.condition(%go) %i : index
  } do {
  ^bb0(%i: index):
    %next = arith.addi %i, %c1 : index
    scf.yield %next : index
  }
  return %r : index
}
```

```sh
cmake -G Ninja -DMLIR_DIR=<prefix>/lib/cmake/mlir -B build && ninja -C build
build/uplift counter.mlir
```

The result returns `arith.constant 9 : index`. The loop ends with `i = 10`.
With a lower bound at or above the upper bound the loop runs no iteration
and ends with the lower bound, but the uplift gives a value below it: for
`lb = 5, ub = 3, step = 1`, `5 + ((3 - 5 + 0) / 1 - 1) * 1 = 2`.

MLIR's own test (`mlir/test/Dialect/SCF/uplift-while.mlir`) checks this
value: `lb + ((ub - lb + step - 1) / step - 1) * step`.

## Cause

`mlir/lib/Dialect/SCF/Transforms/UpliftWhileToFor.cpp:244-250`:

```cpp
Value stepDec = arith::SubIOp::create(rewriter, loc, step, one);
Value len = arith::SubIOp::create(rewriter, loc, ub, lb);
len = arith::AddIOp::create(rewriter, loc, len, stepDec);
len = arith::DivSIOp::create(rewriter, loc, len, step);
len = arith::SubIOp::create(rewriter, loc, len, one);
Value res = arith::MulIOp::create(rewriter, loc, len, step);
res = arith::AddIOp::create(rewriter, loc, lb, res);
```

The `- 1` makes it the last iteration's value, and nothing clamps the trip
count at zero.

## Proposed fix

The value the loop ends with is `lb + max(ceildiv(ub - lb, step), 0) * step`:
drop the `SubIOp` of `one`, and select `lb` when `ub <= lb`. Update
`uplift-while.mlir` to match.

## Our workaround

`idr-tail-loops` uplifts a counted loop only when nothing uses the value its
counter ends with (`PINS.md`: `uplift-final-counter`). Idris loops return
what they accumulate, so the counter's final value is rarely used.
