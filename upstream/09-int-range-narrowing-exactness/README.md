# [mlir][arith] `arith-int-range-narrowing` makes remainders compute something else

At `llvmorg-23.1.2`, the narrowing patterns (`arith-int-range-narrowing`,
`arith::populateIntRangeNarrowingPatterns`) rewrite an elementwise op on a
narrower type when integer range analysis proves that its operands and
results fit that type. For two kinds of op that is not enough, and the
narrowed op computes something else than the op it replaces:

1. `remsi` whose dividend can be the narrow type's minimum while its
   divisor can be -1. On `i64`, `-2^31 rem -1` is 0; on `i32` it
   overflows, and `arith-to-llvm` makes it `llvm.srem`, for which that is
   undefined behaviour (x86's `idiv` traps).
2. `remui` narrowed with a sign truncation. The signed ops are restricted
   to signed casts, but the unsigned ones may take either; an operand whose
   signed range fits but may be negative is truncated, and the narrow op
   reads -2 as 2^32 - 2 where the wide one read 2^64 - 2:
   (2^64 - 2) % 7 = 0, but (2^32 - 2) % 7 = 2.

This report had a third case, a shift whose amount can reach the narrow
width (poison there); main fixed it in 44a4dbf32, and the pin has it.

## Reproduce

`narrowing.mlir` bounds the operands with `maxsi` and `minsi`, which the
analysis reads:

```mlir
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

Both ops become `i32` ops:

```mlir
    %6 = arith.remsi %4, %5 : i32        // %4 may be -2^31 while %5 is -1
    %3 = arith.remui %2, %c7_i32 : i32   // %2 = trunci of a value in [-2, 0]
```

The wrong remainder shows once the call is inlined and folded:
`mlir-opt --inline --canonicalize narrowing.mlir` makes
`@remu_of_minus_two` return `arith.constant 0 : i64`; after the narrowing,
the same pipeline makes it return `arith.constant 2 : i64`.

We expected both ops to stay on `i64`: the ranges admit the inputs on
which the narrow form differs.

## Cause

`mlir/lib/Dialect/Arith/Transforms/IntRangeOptimizations.cpp:378-397` at
llvmorg-23.1.2 (`NarrowElementwise::matchAndRewrite`): for each target
width the pattern merges the cast kinds that the operand and result
ranges allow (`checkTruncatability`) and restricts the signed ops (`divsi`,
`ceildivsi`, `floordivsi`, `remsi`, `maxsi`, `minsi`, `shrsi`) to
`CastKind::Signed`. Nothing else about the op is asked: not the
remainder's overflow in the narrow type, and the unsigned ops keep
`CastKind::Both`, so a sign truncation is allowed for them. Main at
7208ba24 adds only the check of a shift's amount (44a4dbf32); its cast
kinds are at `IntRangeOptimizations.cpp:396-402`.

## Proposed fix

In `NarrowElementwise`, for a target width `w`:

- `remsi` does not narrow when the dividend's range holds the signed
  minimum of `w` bits and the divisor's holds -1 (for `divsi` the result's
  fit already excludes that case);
- the unsigned ops (`divui`, `ceildivui`, `remui`, `shrui`, `maxui`,
  `minui`) get `CastKind::Unsigned`, as the signed ones get `Signed`.

Add a test for each to `mlir/test/Dialect/Arith/int-range-narrowing.mlir`,
expecting its op to stay on `i64`.

## Status upstream

The shift, this report's third case, is fixed on main by 44a4dbf32
("[MLIR][Arith] Don't narrow shifts whose amount can exceed the target
width", [#218495](https://github.com/llvm/llvm-project/pull/218495)),
for [#218191](https://github.com/llvm/llvm-project/issues/218191); the
pin, main at 7208ba24, has it, so this report, `narrowing.mlir` and its
check no longer carry it. The remainders are not fixed: at 7208ba24
`remsi` still has no check for the narrow minimum rem -1, and the
unsigned ops still allow either cast (`IntRangeOptimizations.cpp:396-402`
there). Both still reproduce there (below, "Testing on main").

## Testing on main

On main at 7208ba24 without this patch (an `mlir-opt` of `llvm` and
`mlir` alone, Release with assertions, test dialect included, arm64
macOS), the three functions of the patch's lit test, run as
`int-range-narrowing.mlir` runs them
(`--arith-int-range-narrowing="int-bitwidths-supported=1,8,16,24,32"`):

- `@remsi_narrow_min_by_minus_one`: the `remsi` becomes `i32`, where it
  must stay `i64`. Still broken.
- `@remsi_above_narrow_min`: the `remsi` becomes `i32`, as it may.
- `@remui_of_negative`: the `remui` becomes `i8`, where it must stay
  `i64`. Still broken.

`narrowing.mlir` shows the wrong value: `mlir-opt --inline
--canonicalize` makes `@remu_of_minus_two` return 0, and the same after
`--arith-int-range-narrowing="int-bitwidths-supported=32"` makes it
return 2. With the patch applied to the same tree, all of
`int-range-narrowing.mlir` passes (FileCheck), the three new functions
included.

## Our workaround

None: the patch below is carried. `idr-narrow-lanes` versions a vectorized
loop when its wide integer ops fit 32 bits, and upstream's narrowing of the
copy leaves wide each op whose 32-bit form would compute something else.
Before the patch, it versioned a loop only when every such op was an arith
op whose 32-bit form computes what it computes (a shift's amount below 32,
no INT32_MIN % -1, no negative word read unsigned), a second copy of the
narrowing's own decision.

## Patch

`llvm.patch` is the proposed fix for the remainders, against main at
7208ba24, the pin, which already has 44a4dbf32's shift check: `remsi`
does not narrow when the dividend's range holds the target width's
signed minimum and the divisor's holds -1, and the ops that read their
operands unsigned get `CastKind::Unsigned`. Tests for each in
`mlir/test/Dialect/Arith/int-range-narrowing.mlir`
(`@remsi_narrow_min_by_minus_one`, `@remsi_above_narrow_min`,
`@remui_of_negative`), written with main's `test.with_bounds <...>`
syntax. `tests/upstream/int-range-narrowing-exactness` checks the
reproducer with the pinned tools; the lit test ran on main as "Testing on
main" says (the pinned build has no test dialect).

## Upstreaming plan

Status: reproduced on main at 7208ba24; not yet filed.

The pin has the shift fix, 44a4dbf32, and the patch no longer carries
it. The remainders are still broken on main (`@remsi_narrow_min_by_minus_one`
and `@remui_of_negative` narrow there), so the patch stays and goes
upstream.

- Where: an issue with `narrowing.mlir`'s wrong value, and a pull request
  against main with `llvm.patch`, after the bugs before it in
  `upstream/README.md`'s order.
- Upstream test: the three functions in `int-range-narrowing.mlir`.
- Dropped when the pin has the merged fix.
