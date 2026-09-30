// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=contified -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: idris-mlir-opt %s --idr-contify --idr-expect=holds=contified -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// A function called once, from another function, is a continuation of that
// function: Idris makes one of every `if` on a right-hand side, and here
// `@step`'s case block calls `@step` back, a cycle the inliner refuses.
// idr-contify inlines it into its one caller. A function called twice, one
// a closure names, and one only its own call reaches are not continuations,
// and stay.
// BEFORE: error: expected contified: @step$case is called once, from @step, and is still a function
// CHECK-NOT: func.func private @step$case
// CHECK-DAG: func.func private @twice
// CHECK-DAG: func.func private @named
// CHECK-DAG: func.func private @lonely
module attributes {idr.program} {
  func.func private @step(%n: i64, %acc: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    %r = func.call @step$case(%done, %n, %acc) : (i1, i64, i64) -> i64
    return %r : i64
  }
  func.func private @step$case(%done: i1, %n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %a = func.call @twice(%acc) : (i64) -> i64
      %s = func.call @step(%m, %a) : (i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func private @twice(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  func.func private @named(%x: i64) -> i64 {
    return %x : i64
  }
  func.func private @lonely(%x: i64) -> i64 {
    %y = func.call @lonely(%x) : (i64) -> i64
    return %y : i64
  }
  func.func @root(%w: !idr.world, %n: i64) -> !idr.world {
    %c0 = arith.constant 0 : i64
    %t = func.call @twice(%n) : (i64) -> i64
    %f = idr.closure @named() : () -> !idr.fn<(i64) -> (i64)>
    %g = func.call @named(%t) : (i64) -> i64
    %v = idr.apply %f(%g) : !idr.fn<(i64) -> (i64)>
    %r = func.call @step(%v, %c0) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w : i64
    return %w2 : !idr.world
  }
}
