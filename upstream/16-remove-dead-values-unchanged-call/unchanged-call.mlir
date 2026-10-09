// At remove-dead-values' fixpoint: @inc is private, and its one call uses
// its result, so the pass has nothing to erase. It still replaces the call
// with an identical one.
func.func private @inc(%x: i64) -> i64 {
  %c1 = arith.constant 1 : i64
  %y = arith.addi %x, %c1 : i64
  return %y : i64
}

func.func @main(%x: i64) -> i64 {
  %y = func.call @inc(%x) : (i64) -> i64
  return %y : i64
}
