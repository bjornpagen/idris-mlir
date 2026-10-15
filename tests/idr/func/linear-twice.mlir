// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A value of !idr.lin<T> is used at most once on every path: by
// idr.lin.use, or by a position whose type is linear too. Any value enters
// a linear position through idr.lin.enter. The rule is one function's,
// checked by idr.func's own verifier, so it holds in a module that is no
// whole program as in one that is.

!Box = !idr.data<"Box", plain [@MkBox(!idr.lin<i64>)]>
idr.program @"linear-twice" root(@root) stage(first) {
idr.func @take(%x: !idr.lin<i64>) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  return %v : i64
}
// Once on each path: passed on in one region, used in the other.
idr.func @branch(%b: i64, %x: !idr.lin<i64>) -> i64 {
  %r = idr.match_lit %b : i64 -> (i64) {
  case 0 {
    %t = idr.call @take(%x) : (!idr.lin<i64>) -> i64
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
idr.func @boxed(%x: i64) -> !Box {
  %e = idr.lin.enter %x : !idr.lin<i64>
  %c = idr.con !Box @MkBox(%e : !idr.lin<i64>)
  return %c : !Box
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @"linear-twice" root(@root) stage(first) {
  idr.func @twice(%x: !idr.lin<i64>) -> i64 {
    %a = idr.lin.use %x : !idr.lin<i64>
    // expected-error @+1 {{uses a linear value that is already used on the same path}}
    %b = idr.lin.use %x : !idr.lin<i64>
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// Entered once, a value is linear from then on.
idr.program @"linear-twice" root(@root) stage(first) {
idr.func @take(%x: !idr.lin<i64>) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  return %v : i64
}
idr.func @f(%x: i64) -> i64 {
  %e = idr.lin.enter %x : !idr.lin<i64>
  %a = idr.call @take(%e) : (!idr.lin<i64>) -> i64
  // expected-error @+1 {{uses a linear value that is already used on the same path}}
  %b = idr.call @take(%e) : (!idr.lin<i64>) -> i64
  %s = arith.addi %a, %b : i64
  return %s : i64
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @"linear-twice" root(@root) stage(first) {
  // expected-error @+1 {{expects a grade of a plain type, got one of '!idr.world'}}
  idr.func @f(%w: !idr.lin<!idr.world>) {
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A match takes a linear value apart, as its one use, and binds each
// field at the product of the value's quantity and the field's: of a
// linear value, as the constructor holds the field; of a value used many
// times, as used many times. A default region gets a linear value it did
// not take apart back.
!P = !idr.data<"P", plain [@MkP(i64, !idr.lin<i64>), @Empty()]>
idr.program @"linear-twice" root(@root) stage(first) {
idr.func @snd(%p: !idr.lin<!P>) -> i64 {
  %r = idr.match %p : !idr.lin<!P> -> (i64) {
  case @MkP(%a: i64, %b: !idr.lin<i64>) {
    %x = idr.lin.use %b : !idr.lin<i64>
    idr.yield %x : i64
  }
  default(%q: !idr.lin<!P>) {
    %s = idr.call @snd(%q) : (!idr.lin<!P>) -> i64
    idr.yield %s : i64
  }
  }
  return %r : i64
}
idr.func @shared(%p: !P) -> i64 {
  %r = idr.match %p : !P -> (i64) {
  case @MkP(%a: i64, %b: i64) {
    %x = arith.addi %b, %b : i64
    idr.yield %x : i64
  }
  default {
    %z = arith.constant 0 : i64
    idr.yield %z : i64
  }
  }
  return %r : i64
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

!P = !idr.data<"P", plain [@MkP(!idr.lin<i64>)]>
idr.program @"linear-twice" root(@root) stage(first) {
  idr.func @f(%p: !P) -> i64 {
    // expected-error @+1 {{case @MkP must take the constructor's fields at the scrutinee's grade, 'i64'}}
    %r = idr.match %p : !P -> (i64) {
    case @MkP(%a: !idr.lin<i64>) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!P = !idr.data<"P", plain [@MkP(i64)]>
idr.program @"linear-twice" root(@root) stage(first) {
  idr.func @f(%p: !idr.lin<!P>) -> i64 {
    // expected-error @+1 {{expects a default region without arguments, or one that takes the scrutinee back at its type}}
    %r = idr.match %p : !idr.lin<!P> -> (i64) {
    case @MkP(%a: i64) {
      idr.yield %a : i64
    }
    default(%q: !P) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A closure holding a linear value is linear too: it is applied where it
// is made, or entered into a linear type and used once from there.
idr.program @"linear-twice" root(@root) stage(higher) {
idr.func @add(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %v, %y : i64
  return %s : i64
}
idr.func @now(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %r = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}
idr.func @later(%x: !idr.lin<i64>) -> !idr.lin<!idr.fn<(i64) -> (i64)>> {
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %e = idr.lin.enter %f : !idr.lin<!idr.fn<(i64) -> (i64)>>
  return %e : !idr.lin<!idr.fn<(i64) -> (i64)>>
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @"linear-twice" root(@root) stage(higher) {
idr.func @add(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %v, %y : i64
  return %s : i64
}
idr.func @twice(%x: !idr.lin<i64>, %y: i64) -> i64 {
  // expected-error @+1 {{captures a linear value, so its one use must apply it or enter it into a linear type}}
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %a = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
  %b = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
  %s = arith.addi %a, %b : i64
  return %s : i64
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @"linear-twice" root(@root) stage(higher) {
idr.func @add(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %v, %y : i64
  return %s : i64
}
idr.func @keep(%f: !idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> {
  return %f : !idr.fn<(i64) -> (i64)>
}
idr.func @passed(%x: !idr.lin<i64>) -> !idr.fn<(i64) -> (i64)> {
  // expected-error @+1 {{captures a linear value, so its one use must apply it or enter it into a linear type}}
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %k = idr.call @keep(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
  return %k : !idr.fn<(i64) -> (i64)>
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}
