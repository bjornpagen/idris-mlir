func.func private @ext(i32)

func.func private @never() -> i1 {
  %false = arith.constant false
  return %false : i1
}

func.func private @f() -> i32 {
  %c = arith.constant 1 : i32
  return %c : i32
}

func.func @main() {
  %r = func.call @f() : () -> i32
  %no = func.call @never() : () -> i1
  scf.if %no {
    %s = func.call @f() : () -> i32
    func.call @ext(%s) : (i32) -> ()
  }
  return
}
