// main returns 40 + 2; the smoke test checks the process exit status.
module {
  func.func @main() -> i32 {
    %forty = arith.constant 40 : i32
    %two = arith.constant 2 : i32
    %sum = arith.addi %forty, %two : i32
    return %sum : i32
  }
}
