func.func private @never() -> i32 {
  ub.unreachable
}

func.func @main() -> i32 {
  %0 = func.call @never() : () -> i32
  return %0 : i32
}
