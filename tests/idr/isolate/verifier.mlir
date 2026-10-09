// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A lambda's block takes the parameters its closure type names, and yields
// its results. A delay's block takes nothing, since a force passes nothing,
// and yields the suspension's value; and it uses no world from above,
// since a world passes only as an argument or a result.

func.func private @takes(%k: i64) -> !idr.fn<(i64) -> (i64)> {
  // expected-error @+1 {{but its type}}
  %f = idr.lambda : !idr.fn<(i64) -> (i64)> {
  ^bb0(%x: i32):
    idr.yield %k : i64
  }
  return %f : !idr.fn<(i64) -> (i64)>
}

// -----

func.func private @yields(%k: i64) -> !idr.fn<(i64) -> (i64)> {
  %f = idr.lambda : !idr.fn<(i64) -> (i64)> {
  ^bb0(%x: i64):
    %c = arith.constant 1 : i32
    // expected-error @+1 {{but its idr.lambda has results}}
    idr.yield %c : i32
  }
  return %f : !idr.fn<(i64) -> (i64)>
}

// -----

func.func private @argument(%k: i64) -> !idr.lazy<i64> {
  // expected-error @+1 {{but a suspension's body takes nothing}}
  %t = idr.delay : !idr.lazy<i64> {
  ^bb0(%x: i64):
    idr.yield %x : i64
  }
  return %t : !idr.lazy<i64>
}

// -----

func.func private @count(%w: !idr.world) -> i64 {
  %c = arith.constant 0 : i64
  return %c : i64
}
func.func private @world(%w: !idr.world) -> !idr.lazy<i64> {
  // expected-error @+1 {{uses a world from above}}
  %t = idr.delay : !idr.lazy<i64> {
    %n = func.call @count(%w) : (!idr.world) -> i64
    idr.yield %n : i64
  }
  return %t : !idr.lazy<i64>
}
