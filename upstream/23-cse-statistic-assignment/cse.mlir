func.func @f(%a: i32) -> i32 {
  %x = arith.addi %a, %a : i32
  %y = arith.addi %a, %a : i32
  %r = arith.addi %x, %y : i32
  return %r : i32
}

func.func @g(%a: i32) -> i32 {
  %x = arith.muli %a, %a : i32
  %y = arith.muli %a, %a : i32
  %z = arith.muli %a, %a : i32
  %r = arith.addi %x, %y : i32
  %s = arith.addi %r, %z : i32
  return %s : i32
}

func.func @h(%a: i32) -> i32 {
  return %a : i32
}
