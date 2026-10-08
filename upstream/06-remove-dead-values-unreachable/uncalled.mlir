func.func private @ext(i32)

func.func private @g(%x: i32) {
  func.call @ext(%x) : (i32) -> ()
  return
}
