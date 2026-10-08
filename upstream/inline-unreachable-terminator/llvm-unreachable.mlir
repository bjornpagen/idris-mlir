llvm.func @never() -> i32 {
  llvm.unreachable
}

func.func @main() -> i32 {
  %0 = llvm.call @never() : () -> i32
  return %0 : i32
}
