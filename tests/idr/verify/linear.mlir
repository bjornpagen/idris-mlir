// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A value of !idr.lin<T> is used at most once on every path: by
// idr.lin.use, or by a position whose type is linear too. Any value enters
// a linear position through idr.lin.enter.

module attributes {idr.program} {
idr.data @Box {
  idr.ctor @MkBox tag 0 (!idr.lin<i64>)
}
func.func private @take(%x: !idr.lin<i64>) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  return %v : i64
}
// Once on each path: passed on in one region, used in the other.
func.func private @branch(%b: i64, %x: !idr.lin<i64>) -> i64 {
  %r = idr.match_lit %b : i64 -> (i64) {
  case 0 {
    %t = func.call @take(%x) : (!idr.lin<i64>) -> i64
    idr.yield %t : i64
  }
  default {
    %v = idr.lin.use %x : !idr.lin<i64>
    idr.yield %v : i64
  }
  }
  return %r : i64
}
// A field of a linear type holds the value itself.
func.func private @boxed(%x: i64) -> !idr.data<@Box> {
  %e = idr.lin.enter %x : !idr.lin<i64>
  %c = idr.con @Box::@MkBox(%e) : (!idr.lin<i64>) -> !idr.data<@Box>
  return %c : !idr.data<@Box>
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

module attributes {idr.program} {
func.func private @twice(%x: !idr.lin<i64>) -> i64 {
  %a = idr.lin.use %x : !idr.lin<i64>
  // expected-error @+1 {{uses a linear value that is already used on the same path}}
  %b = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %a, %b : i64
  return %s : i64
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

// Entered once, a value is linear from then on.
module attributes {idr.program} {
func.func private @take(%x: !idr.lin<i64>) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  return %v : i64
}
func.func private @f(%x: i64) -> i64 {
  %e = idr.lin.enter %x : !idr.lin<i64>
  %a = func.call @take(%e) : (!idr.lin<i64>) -> i64
  // expected-error @+1 {{uses a linear value that is already used on the same path}}
  %b = func.call @take(%e) : (!idr.lin<i64>) -> i64
  %s = arith.addi %a, %b : i64
  return %s : i64
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

// expected-error @+1 {{expects !idr.lin of a runtime type other than the world, got '!idr.world'}}
func.func private @f(%w: !idr.lin<!idr.world>) {
  return
}
