// remove-dead-values on a function reached only through func.constant in a
// nested module: with the bug, @inc returns ub.poison.
module {
  builtin.module @inner {
    func.func private @inc(%x: i64) -> i64 {
      %c1 = arith.constant 1 : i64
      %y = arith.addi %x, %c1 : i64
      return %y : i64
    }
    func.func @run(%x: i64) -> i64 {
      %f = func.constant @inc : (i64) -> i64
      %y = func.call_indirect %f(%x) : (i64) -> i64
      return %y : i64
    }
  }
}
