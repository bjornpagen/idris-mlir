# [mlir][arith] `arith-int-range-narrowing` makes shifts and remainders compute something else

At `llvmorg-23.1.2`, the narrowing patterns (`arith-int-range-narrowing`,
`arith::populateIntRangeNarrowingPatterns`) rewrite an elementwise op on a
narrower type when integer range analysis proves that its operands and
results fit that type. For three kinds of op that is not enough, and the
narrowed op computes something else than the op it replaces:

1. A shift (`shli`, `shrsi`, `shrui`) whose amount can reach the narrow
   width. Amount and result fit, but on the narrow type a shift by its
   width or more is poison.
2. `remsi` whose dividend can be the narrow type's minimum while its
   divisor can be -1. On `i64`, `-2^31 rem -1` is 0; on `i32` it
   overflows, and `arith-to-llvm` makes it `llvm.srem`, for which that is
   undefined behaviour (x86's `idiv` traps).
3. `remui` narrowed with a sign truncation. The signed ops are restricted
   to signed casts, but the unsigned ones may take either; an operand whose
   signed range fits but may be negative is truncated, and the narrow op
   reads -2 as 2^32 - 2 where the wide one read 2^64 - 2:
   (2^64 - 2) % 7 = 0, but (2^32 - 2) % 7 = 2.

## Reproduce

`narrowing.mlir` bounds the operands with `minui`, `maxsi` and `minsi`,
which the analysis reads:

```mlir
// x in [0, 2^20], s in [0, 40]
func.func @shift(%x: i64, %s: i64) -> i64 {
  %xmax = arith.constant 1048576 : i64
  %smax = arith.constant 40 : i64
  %a = arith.minui %x, %xmax : i64
  %b = arith.minui %s, %smax : i64
  %r = arith.shrui %a, %b : i64
  return %r : i64
}

// x in [-2^31, 0], y in [-2, -1]
func.func @rem(%x: i64, %y: i64) -> i64 {
  %xmin = arith.constant -2147483648 : i64
  %zero = arith.constant 0 : i64
  %ymin = arith.constant -2 : i64
  %ymax = arith.constant -1 : i64
  %x1 = arith.maxsi %x, %xmin : i64
  %a = arith.minsi %x1, %zero : i64
  %y1 = arith.maxsi %y, %ymin : i64
  %b = arith.minsi %y1, %ymax : i64
  %r = arith.remsi %a, %b : i64
  return %r : i64
}

// x in [-2, 0]
func.func @remu(%x: i64) -> i64 {
  %xmin = arith.constant -2 : i64
  %zero = arith.constant 0 : i64
  %c7 = arith.constant 7 : i64
  %x1 = arith.maxsi %x, %xmin : i64
  %a = arith.minsi %x1, %zero : i64
  %r = arith.remui %a, %c7 : i64
  return %r : i64
}

func.func @remu_of_minus_two() -> i64 {
  %m2 = arith.constant -2 : i64
  %r = func.call @remu(%m2) : (i64) -> i64
  return %r : i64
}
```

```sh
mlir-opt --arith-int-range-narrowing="int-bitwidths-supported=32" narrowing.mlir
```

All three ops become `i32` ops:

```mlir
    %4 = arith.shrui %2, %3 : i32        // %3 up to 40
    %6 = arith.remsi %4, %5 : i32        // %4 may be -2^31 while %5 is -1
    %3 = arith.remui %2, %c7_i32 : i32   // %2 = trunci of a value in [-2, 0]
```

The wrong remainder shows once the call is inlined and folded:
`mlir-opt --inline --canonicalize narrowing.mlir` makes
`@remu_of_minus_two` return `arith.constant 0 : i64`; after the narrowing,
the same pipeline makes it return `arith.constant 2 : i64`.

We expected each of the three ops to stay on `i64`: the ranges admit the
inputs on which the narrow form differs.

## Cause

`mlir/lib/Dialect/Arith/Transforms/IntRangeOptimizations.cpp:378-397`
(`NarrowElementwise::matchAndRewrite`): for each target width the pattern
merges the cast kinds that the operand and result ranges allow
(`checkTruncatability`) and restricts the signed ops (`divsi`,
`ceildivsi`, `floordivsi`, `remsi`, `maxsi`, `minsi`, `shrsi`) to
`CastKind::Signed`. Nothing else about the op is asked: not the shift's
amount, not the remainder's overflow in the narrow type, and the unsigned
ops keep `CastKind::Both`, so a sign truncation is allowed for them.

## Proposed fix

In `NarrowElementwise`, for a target width `w`:

- a shift narrows only when its amount's `umax` is below `w`;
- `remsi` does not narrow when the dividend's range holds the signed
  minimum of `w` bits and the divisor's holds -1 (for `divsi` the result's
  fit already excludes that case);
- the unsigned ops (`divui`, `ceildivui`, `remui`, `shrui`, `maxui`,
  `minui`) get `CastKind::Unsigned`, as the signed ones get `Signed`.

Add the three functions of `narrowing.mlir` to
`mlir/test/Dialect/Arith/int-range-narrowing.mlir`, expecting their ops to
stay on `i64`.

## Status upstream

The shift (case 1) is fixed on main by 44a4dbf32 ("[MLIR][Arith] Don't
narrow shifts whose amount can exceed the target width",
[#218495](https://github.com/llvm/llvm-project/pull/218495)), for
[#218191](https://github.com/llvm/llvm-project/issues/218191); it is not
on `release/23.x`. The remainders are not (checked at 161d9dca, October
2026): `remsi` still has no check for the narrow minimum rem -1, and the
unsigned ops still allow either cast
(`IntRangeOptimizations.cpp:396-402` there). Cases 2 and 3 are the part
this report sends. When the pin moves past 44a4dbf32, drop the shift
from this report, `narrowing.mlir`, its check and `exact`, and keep the
rest.

## Our workaround

None: the patch below is carried. `idr-narrow-lanes` versions a vectorized
loop when its wide integer ops fit 32 bits, and upstream's narrowing of the
copy leaves wide each op whose 32-bit form would compute something else.
Before the patch, it versioned a loop only when every such op was an arith
op whose 32-bit form computes what it computes (a shift's amount below 32,
no INT32_MIN % -1, no negative word read unsigned), a second copy of the
narrowing's own decision.

## Patch

`llvm.patch` is main's 44a4dbf32 (#218495, the shift) backported
unchanged, and the proposed fix for the remainders on top: `remsi` does
not narrow when the dividend's range holds the target width's signed
minimum and the divisor's holds -1, and the ops that read their operands
unsigned get `CastKind::Unsigned`. Tests for each in
`mlir/test/Dialect/Arith/int-range-narrowing.mlir`. Built into the pinned
toolchain; `tests/upstream/int-range-narrowing-exactness` checks the
reproducer. The lit test uses the test dialect's `test.with_bounds`,
which the pinned build does not have, so it has not been run.

## Upstreaming plan

Status: file upstream.

The shift backport is already on main and is not filed. One issue for
the two remainder cases, citing #218495, and a pull request with the
remainder part alone.

- Where: llvm/llvm-project. `remsi` does not narrow when the dividend's
  range holds the target width's signed minimum and the divisor's holds
  -1, and the ops that read their operands unsigned get
  `CastKind::Unsigned`.
- Upstream test: `@remsi_narrow_min_by_minus_one`, `@remsi_above_narrow_min`
  and `@remui_of_negative` in `int-range-narrowing.mlir`.
- When the pin moves past 44a4dbf32, the backported part leaves the
  patch; the rest stays until upstream has it.
