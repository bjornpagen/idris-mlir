// RUN: idris-mlir-opt %s --idr-stack --idr-rc --idr-tail-loops | FileCheck %s
// Counting runs on functional code, and idr-tail-loops turns what it
// counted into loops, which keep the owned stage's rule (idris-mlir-opt
// verifies it after each pass). A consumer that only reads its list borrows
// it, and its loop carries the borrowed list with no count changed; a string
// built along the way is carried owned.
// CHECK-LABEL: func.func private @sumAcc(
// CHECK-SAME: {idr.borrowed}
// CHECK: scf.while
// CHECK-NOT: idr.inc
// CHECK-NOT: idr.dec
// CHECK-LABEL: func.func private @drain(
// CHECK: scf.while
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @N tag 0 () {quantities = []}
    idr.ctor @C tag 1 (i64, !idr.box<@L>) {quantities = ["w", "w"]}
  }
  func.func private @sumAcc(%acc: i64, %l: !idr.box<@L>) -> i64 attributes {idr.total} {
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %a = arith.addi %acc, %h : i64
      %s = func.call @sumAcc(%a, %t) : (i64, !idr.box<@L>) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func private @drain(%l: !idr.box<@L>, %s: !idr.str) -> !idr.str attributes {idr.total} {
    %r = idr.match %l : !idr.box<@L> -> (!idr.str) {
    case @N() {
      idr.yield %s : !idr.str
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %x = idr.str.show signed %h : i64
      %s2 = idr.str.append %s, %x
      %d = func.call @drain(%t, %s2) : (!idr.box<@L>, !idr.str) -> !idr.str
      idr.yield %d : !idr.str
    }
    }
    return %r : !idr.str
  }
  func.func @root(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %l = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %z = arith.constant 0 : i64
    %n = func.call @sumAcc(%z, %l) : (i64, !idr.box<@L>) -> i64
    %e = idr.constant "" : !idr.str
    %m = idr.constant #idr.con<@L::@C, [1, #idr.con<@L::@N, []>]> : !idr.box<@L>
    %s = func.call @drain(%m, %e) : (!idr.box<@L>, !idr.str) -> !idr.str
    %w2 = idr.io.put_int signed %n, %w : i64
    %w3 = idr.io.put_str %s, %w2
    return %w3 : !idr.world
  }
}
