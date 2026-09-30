// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A value of !idr.lin<T> is used at most once on every path: by
// idr.lin.use, or by a position whose type is linear too. Any value enters
// a linear position through idr.lin.enter.

module attributes {idr.program} {
idr.data @Box {
  idr.ctor @MkBox (!idr.lin<i64>)
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

// expected-error @+1 {{expects a grade of a plain type, got one of '!idr.world'}}
func.func private @f(%w: !idr.lin<!idr.world>) {
  return
}

// -----

// Matching binds the fields of a value used once as used once: a region
// argument may be the field's type or its linear type.
module attributes {idr.program} {
idr.data @P {
  idr.ctor @MkP (i64, !idr.lin<i64>)
}
func.func private @fst(%p: !idr.lin<!idr.data<@P>>) -> i64 {
  %v = idr.lin.use %p : !idr.lin<!idr.data<@P>>
  %r = idr.match %v : !idr.data<@P> -> (i64) {
  case @MkP(%a: !idr.lin<i64>, %b: !idr.lin<i64>) {
    %x = idr.lin.use %a : !idr.lin<i64>
    idr.yield %x : i64
  }
  }
  return %r : i64
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.data @P {
  idr.ctor @MkP (i64)
}
func.func private @f(%p: !idr.data<@P>) -> i64 {
  // expected-error @+1 {{case @MkP must take the constructor's fields}}
  %r = idr.match %p : !idr.data<@P> -> (i64) {
  case @MkP(%a: !idr.lin<i32>) {
    %z = arith.constant 0 : i64
    idr.yield %z : i64
  }
  }
  return %r : i64
}

// -----

// A closure holding a linear value is linear too: it is applied where it
// is made, or entered into a linear type and used once from there.
module attributes {idr.program} {
func.func private @add(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %v, %y : i64
  return %s : i64
}
func.func private @now(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %r = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}
func.func private @later(%x: !idr.lin<i64>) -> !idr.lin<!idr.fn<(i64) -> (i64)>> {
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %e = idr.lin.enter %f : !idr.lin<!idr.fn<(i64) -> (i64)>>
  return %e : !idr.lin<!idr.fn<(i64) -> (i64)>>
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

module attributes {idr.program} {
func.func private @add(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %v, %y : i64
  return %s : i64
}
func.func private @twice(%x: !idr.lin<i64>, %y: i64) -> i64 {
  // expected-error @+1 {{captures a linear value, so its one use must apply it or enter it into a linear type}}
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %a = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
  %b = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
  %s = arith.addi %a, %b : i64
  return %s : i64
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

module attributes {idr.program} {
func.func private @add(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %v, %y : i64
  return %s : i64
}
func.func private @keep(%f: !idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> {
  return %f : !idr.fn<(i64) -> (i64)>
}
func.func private @passed(%x: !idr.lin<i64>) -> !idr.fn<(i64) -> (i64)> {
  // expected-error @+1 {{captures a linear value, so its one use must apply it or enter it into a linear type}}
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %k = func.call @keep(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
  return %k : !idr.fn<(i64) -> (i64)>
}
func.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}
