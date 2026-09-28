// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A value free of effects (an allocation aside) that only a match's regions
// use moves into each region that uses it; there it meets its consumer.

idr.data @Bool {
  idr.ctor @False tag 0 () {quantities = []}
  idr.ctor @True tag 1 () {quantities = []}
}

// putStr (show x) in both regions of a match on b: the string moves into
// each region, where output fusion writes the number without building it.
// CHECK-LABEL: func.func @write_in_both(
// CHECK-SAME: %[[B:.*]]: !idr.data<@Bool>, %[[X:.*]]: i64, %[[W:.*]]: !idr.world)
// CHECK-NOT: idr.str.show
// CHECK: idr.match %[[B]]
// CHECK: case @False() {
// CHECK: idr.io.put_int signed %[[X]]
// CHECK: case @True() {
// CHECK: idr.io.put_int signed %[[X]]
// CHECK-NOT: idr.str.show
func.func @write_in_both(%b: !idr.data<@Bool>, %x: i64, %w: !idr.world) -> !idr.world {
  %s = idr.str.show signed %x : i64
  %r = idr.match %b : !idr.data<@Bool> -> (!idr.world) {
  case @False() {
    %c = idr.constant "no: " : !idr.str
    %w1 = idr.io.put_str %c, %w
    %w2 = idr.io.put_str %s, %w1
    idr.yield %w2 : !idr.world
  }
  case @True() {
    %c = idr.constant "yes: " : !idr.str
    %w1 = idr.io.put_str %c, %w
    %w2 = idr.io.put_str %s, %w1
    idr.yield %w2 : !idr.world
  }
  }
  return %r : !idr.world
}

// Used by the match itself (its scrutinee): the value stays.
// CHECK-LABEL: func.func @scrutinee(
// CHECK: %[[N:.*]] = arith.addi
// CHECK-NEXT: idr.match_lit %[[N]]
func.func @scrutinee(%x: i64) -> i64 {
  %n = arith.addi %x, %x : i64
  %r = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    idr.yield %n : i64
  }
  default {
    %c = arith.constant 7 : i64
    idr.yield %c : i64
  }
  }
  return %r : i64
}

// Used after the match too: the value stays.
// CHECK-LABEL: func.func @used_after(
// CHECK: %[[S:.*]] = idr.str.append
// CHECK: idr.match_lit
// CHECK: call @keep(%[[S]])
// CHECK: call @keep(%[[S]])
func.func private @keep(!idr.str) -> i64
func.func @used_after(%n: i64, %a: !idr.str, %b: !idr.str) -> i64 {
  %s = idr.str.append %a, %b
  %r = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    %k = func.call @keep(%s) : (!idr.str) -> i64
    idr.yield %k : i64
  }
  default {
    idr.yield %n : i64
  }
  }
  %k2 = func.call @keep(%s) : (!idr.str) -> i64
  %t = arith.addi %r, %k2 : i64
  return %t : i64
}

// A value with an effect (it may crash) stays before the match.
// CHECK-LABEL: func.func @may_crash(
// CHECK: %[[Q:.*]] = idr.div
// CHECK: idr.match_lit
func.func @may_crash(%n: i64, %x: i64, %y: i64) -> i64 {
  %q = idr.div signed %x, %y : i64
  %r = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    idr.yield %q : i64
  }
  default {
    idr.yield %n : i64
  }
  }
  return %r : i64
}
