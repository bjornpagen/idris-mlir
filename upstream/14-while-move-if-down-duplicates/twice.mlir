// One scf.if result forwarded twice by scf.condition. The loop runs once:
// both after-region arguments are 7, so it yields 14, which is not below 1,
// and @main returns 14.
func.func @main() -> i32 {
  %c0 = arith.constant 0 : i32
  %c1 = arith.constant 1 : i32
  %c7 = arith.constant 7 : i32
  %r:2 = scf.while (%i = %c0) : (i32) -> (i32, i32) {
    %go = arith.cmpi slt, %i, %c1 : i32
    %v = scf.if %go -> i32 {
      scf.yield %c7 : i32
    } else {
      scf.yield %i : i32
    }
    scf.condition(%go) %v, %v : i32, i32
  } do {
  ^bb0(%a: i32, %b: i32):
    %s = arith.addi %a, %b : i32
    scf.yield %s : i32
  }
  return %r#0 : i32
}
