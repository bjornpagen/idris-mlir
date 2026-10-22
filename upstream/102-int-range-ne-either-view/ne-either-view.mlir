// A value that is -5 or 5 is never 0: its unsigned bounds, [5, 2^64 - 5],
// exclude 0, though its signed ones, [-5, 5], do not. With the patch,
// `mlir-opt --int-range-optimizations` folds the `ne` to true and the `eq`
// to false; at the pin both comparisons stay.
func.func @never_zero(%c: i1) -> (i1, i1) {
  %neg = arith.constant -5 : i64
  %pos = arith.constant 5 : i64
  %zero = arith.constant 0 : i64
  %x = arith.select %c, %neg, %pos : i64
  %ne = arith.cmpi ne, %x, %zero : i64
  %eq = arith.cmpi eq, %x, %zero : i64
  return %ne, %eq : i1, i1
}
