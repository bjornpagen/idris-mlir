// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// idr-rc makes every reference explicit, and the module passes the owned
// stage's verifier, which idris-mlir-opt runs after the pass: every
// reference is consumed exactly once on every path.

// A map over a list builds each new cell in the one it matched: the field
// that goes on takes its own reference, the matched cell is reset, and the
// new constructor reuses it. The empty case drops the list on entry.
// CHECK-LABEL: func.func private @map(
// CHECK-SAME: %[[L:[^:]*]]: !idr.box<@L>)
// CHECK: idr.match %[[L]]
// CHECK: case @N()
// CHECK-NEXT: idr.dec %[[L]]
// CHECK: case @C(%[[H:[^:]*]]: i64, %[[T:[^:]*]]: !idr.box<@L>)
// CHECK-NEXT: idr.inc %[[T]] : !idr.box<@L>
// CHECK-NEXT: %[[W:.*]] = idr.reset %[[L]] @L::@C
// CHECK: %[[T2:.*]] = func.call @map(%[[T]])
// CHECK: idr.reuse %[[W]] @L::@C(%{{.*}}, %[[T2]])
// CHECK-NOT: idr.con @L::@C
// CHECK-LABEL: func.func private @sum(

// A function that only reads its list borrows it: no count changes in it,
// and none in a loop over it.
// CHECK-SAME: {idr.borrowed}
// CHECK-NOT: idr.inc
// CHECK-NOT: idr.dec
// CHECK-LABEL: func.func private @both(

// A string consumed twice takes one more reference; one consumed once and
// read by a primitive is dropped after its last read.
// CHECK-SAME: %[[A:[^:]*]]: !idr.str, %[[B:[^:]*]]: !idr.str)
// CHECK: idr.inc %[[A]] : !idr.str
// CHECK-NEXT: %{{.*}} = idr.con @Two::@Two(%[[A]], %[[A]])
// CHECK: idr.str.length %[[B]]
// CHECK-NEXT: idr.dec %[[B]] : !idr.str
// CHECK-LABEL: func.func private @scalars(

// Worlds, erased values and scalars hold no references.
// CHECK-NOT: idr.inc
// CHECK-NOT: idr.dec
// CHECK: return
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @N tag 0 () {quantities = []}
    idr.ctor @C tag 1 (i64, !idr.box<@L>) {quantities = ["w", "w"]}
  }
  idr.data @Two {
    idr.ctor @Two tag 0 (!idr.str, !idr.str) {quantities = ["w", "w"]}
  }
  func.func private @map(%l: !idr.box<@L>) -> !idr.box<@L> {
    %n = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %r = idr.match %l : !idr.box<@L> -> (!idr.box<@L>) {
    case @N() {
      idr.yield %n : !idr.box<@L>
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %h2 = arith.muli %h, %h : i64
      %t2 = func.call @map(%t) : (!idr.box<@L>) -> !idr.box<@L>
      %c = idr.con @L::@C(%h2, %t2) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  func.func private @sum(%l: !idr.box<@L>, %acc: i64) -> i64 {
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %a = arith.addi %acc, %h : i64
      %s = func.call @sum(%t, %a) : (!idr.box<@L>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func private @both(%a: !idr.str, %b: !idr.str) -> (!idr.data<@Two>, i64) {
    %p = idr.con @Two::@Two(%a, %a) : (!idr.str, !idr.str) -> !idr.data<@Two>
    %n = idr.str.length %b
    return %p, %n : !idr.data<@Two>, i64
  }
  func.func private @scalars(%w: !idr.world {idr.quantity = "1"}, %e: !idr.erased {idr.quantity = "0"},
                             %x: i64) -> !idr.world {
    %w2 = idr.io.put_int signed %x, %w : i64
    return %w2 : !idr.world
  }
  func.func @root(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c = idr.constant "x" : !idr.str
    %p:2 = func.call @both(%c, %c) : (!idr.str, !idr.str) -> (!idr.data<@Two>, i64)
    %l = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %m = func.call @map(%l) : (!idr.box<@L>) -> !idr.box<@L>
    %z = arith.constant 0 : i64
    %s = func.call @sum(%m, %z) : (!idr.box<@L>, i64) -> i64
    %w2 = idr.io.put_int signed %s, %w : i64
    %e = idr.constant #idr.erased : !idr.erased
    %w3 = func.call @scalars(%w2, %e, %s) : (!idr.world, !idr.erased, i64) -> !idr.world
    return %w3 : !idr.world
  }
}
