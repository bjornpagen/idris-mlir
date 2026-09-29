// The module of one-clone.mlir's failing run: the calls reach two copies.
module {
  func.func private @iter$a(%n: i64) -> i64 attributes {idr.origin = "iter"} {
    return %n : i64
  }
  func.func private @iter$b(%n: i64) -> i64 attributes {idr.origin = "iter"} {
    return %n : i64
  }
  func.func @main(%n: i64) -> (i64, i64) {
    %a = func.call @iter$a(%n) : (i64) -> i64
    %b = func.call @iter$b(%n) : (i64) -> i64
    return %a, %b : i64, i64
  }
}
