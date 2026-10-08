func.func private @ignores(%x: i64) -> i64 {
  %c = arith.constant 7 : i64
  return %c : i64
}

func.func private @caller(%b: i64) -> i64 {
  %t = func.call @ignores(%b) : (i64) -> i64
  return %t : i64
}

func.func @main(%a: i64) -> (i64, (i64) -> i64) {
  %f = func.constant @ignores : (i64) -> i64
  %t = func.call @caller(%a) : (i64) -> i64
  return %t, %f : i64, (i64) -> i64
}
