func.func private @g(%a: i32) -> i32 {
  %c = arith.constant 1 : i32
  %r = arith.addi %a, %c : i32
  return %r : i32
}

func.func @f(%a: i32) -> i32 {
  %r = func.call @g(%a) : (i32) -> i32
  return %r : i32
}
