// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 1' %s > %t.reuse.mlir
// RUN: idris-mlir-opt %t.reuse.mlir | idris-mlir-opt | FileCheck %s
// The owned stage is what a function's grades say: a function with an owned
// value is in it, and idr.func's verifier keeps the stage's rule there,
// with no attribute to say so and no look at the rest of the module. A
// function whose owned value is never consumed is refused; another in the
// same module, which holds no owned value, builds a plain constructor and
// is not asked. A reuse, the owned stage's own constructor, prints and
// parses back with its token among its operands' types.
// CHECK-LABEL: idr.func @bump(
// CHECK: idr.take %{{.*}} : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
// CHECK: idr.reuse %{{.*}} @C(%{{.*}}, %{{.*}}) : (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>>

!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.program @"owned-not-consumed" root(@root) stage(owned) {
  // expected-note @+1 {{the value is defined here}}
  idr.func @leak(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length borrow %v
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %n : i64
  }
  idr.func @pair(%x: i64) -> !P {
    %p = idr.con !P @MkP(%x : i64, %x : i64)
    return %p : !P
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"owned-not-consumed" root(@root) stage(owned) {
  idr.func @bump(%l: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %one = arith.constant 1 : i64
      %h2 = arith.addi %w#1, %one : i64
      %o = idr.reuse %w#0 !idr.own<!idr.box<!L>> @C(%h2 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %o : !idr.own<!idr.box<!L>>
    }
    default {
      idr.yield %l : !idr.own<!idr.box<!L>>
    }
    }
    return %r : !idr.own<!idr.box<!L>>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
