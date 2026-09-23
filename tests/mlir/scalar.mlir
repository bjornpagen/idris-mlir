module {
  func.func @add_constants() -> i64 {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %sum = arith.addi %one, %two : i64
    return %sum : i64
  }
}
