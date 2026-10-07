func.func private @ext(i32)

func.func private @never() -> i1 {
  %false = arith.constant false
  return %false : i1
}

func.func @main(%v: i32) {
  %no = func.call @never() : () -> i1
  cf.br ^bb1(%v : i32)
^bb1(%a: i32):
  scf.if %no {
    func.call @ext(%a) : (i32) -> ()
  }
  return
}
