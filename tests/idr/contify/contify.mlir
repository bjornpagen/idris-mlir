// NEEDS-ACCEPTANCE: that before idr-contify the property reports @step.case1 at its one call (mlir-22), and that idr-contify, taking cycles of calls from CallCycles (S13), moves it into @step; the second RUN writes no module (S2's default argument).
// RUN: idris-mlir-opt %s --idr-expect=holds=contified -verify-diagnostics -o /dev/null
// RUN: idris-mlir-opt %s --idr-contify --idr-expect=holds=contified -o /dev/null
// A function called once, from another function, is a continuation of that
// function: Idris makes one of every `if` on a right-hand side, and here
// `@step`'s case block calls `@step` back, a cycle the inliner refuses.
// idr-contify inlines it into its one caller. A function called twice, one
// a closure names, and one only its own call reaches are not continuations,
// and stay.
idr.program @contify root(@root) stage(higher) {
  idr.func @step(%n: i64, %acc: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    // expected-error @below {{expected contified: @step.case1 is called once, from @step, and is still a function}}
    %r = idr.call @step.case1(%done, %n, %acc) : (i1, i64, i64) -> i64
    return %r : i64
  }
  idr.func @step.case1(%done: i1, %n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default(%d: i1) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %a = idr.call @twice(%acc) : (i64) -> i64
      %s = idr.call @step(%m, %a) : (i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @twice(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @named(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @lonely(%x: i64) -> i64 {
    %y = idr.call @lonely(%x) : (i64) -> i64
    return %y : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : i64
    %n = arith.constant 7 : i64
    %t = idr.call @twice(%n) : (i64) -> i64
    %f = idr.closure @named() : () -> !idr.fn<(i64) -> (i64)>
    %g = idr.call @named(%t) : (i64) -> i64
    %v = idr.apply %f(%g) : !idr.fn<(i64) -> (i64)>
    %r = idr.call @step(%v, %c0) : (i64, i64) -> i64
    %w2 = idr.io.put_sint %r, %w : i64
    return %w2 : !idr.world
  }
}
