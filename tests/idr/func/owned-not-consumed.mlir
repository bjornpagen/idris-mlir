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
// CHECK-LABEL: idr.func private @bump(
// CHECK: idr.take %{{.*}} @L::@C : !idr.own<!L> -> (!idr.own<!idr.token>, i64, !idr.own<!L>)
// CHECK: idr.reuse %{{.*}} @L::@C(%{{.*}}, %{{.*}}) : (!idr.own<!idr.token>, i64, !idr.own<!L>) -> !idr.own<!L>

idr.data @P {
  idr.ctor @MkP (i64, i64)
}
// expected-note @+1 {{the value is defined here}}
idr.func private @leak(%s: !idr.own<!idr.str>) -> i64 {
  %v = idr.borrow %s : !idr.own<!idr.str>
  %n = idr.str.length %v
  // expected-error @+1 {{returns while a value still holds a reference}}
  return %n : i64
}
idr.func private @pair(%x: i64) -> !idr.data<@P> {
  %p = idr.con @P::@MkP(%x, %x) : (i64, i64) -> !idr.data<@P>
  return %p : !idr.data<@P>
}

// -----

idr.data @L box {
  idr.ctor @N ()
  idr.ctor @C (i64, !idr.box<@L>)
}
idr.func private @bump(%l: !idr.own<!idr.box<@L>>) -> !idr.own<!idr.box<@L>> {
  %v = idr.borrow %l : !idr.own<!idr.box<@L>>
  %r = idr.match %v : !idr.box<@L> -> (!idr.own<!idr.box<@L>>) {
  case @C(%h: i64, %t: !idr.box<@L>) {
    %w:3 = idr.take %l @L::@C : !idr.own<!idr.box<@L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<@L>>)
    %one = arith.constant 1 : i64
    %h2 = arith.addi %w#1, %one : i64
    %o = idr.reuse %w#0 @L::@C(%h2, %w#2) : (!idr.own<!idr.token>, i64, !idr.own<!idr.box<@L>>) -> !idr.own<!idr.box<@L>>
    idr.yield %o : !idr.own<!idr.box<@L>>
  }
  default {
    idr.yield %l : !idr.own<!idr.box<@L>>
  }
  }
  return %r : !idr.own<!idr.box<@L>>
}
