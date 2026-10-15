// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// A value free of effects (an allocation aside) that only a match's regions
// use moves into each region that uses it; there it meets its consumer.


// putStr (show x) in both regions of a match on b: the string moves into
// each region, where output fusion writes the number without building it.
// CHECK-LABEL: idr.func private @write_in_both(
// CHECK-SAME: %[[B:.*]]: !Bool, %[[X:.*]]: i64, %[[W:.*]]: !idr.world)
// CHECK-NOT: idr.str.show
// CHECK: match %[[B]]
// CHECK: case @False() {
// CHECK: idr.io.put_int signed %[[X]]
// CHECK: case @True() {
// CHECK: idr.io.put_int signed %[[X]]
// CHECK-NOT: idr.str.show
!Bool = !idr.data<"Bool", plain [@False(), @True()]>
idr.func private @write_in_both(%b: !Bool, %x: i64, %w: !idr.world) -> !idr.world {
  %s = idr.str.show signed %x : i64
  %r = idr.match %b : !Bool -> (!idr.world) {
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
// CHECK-LABEL: idr.func private @scrutinee(
// CHECK: %[[N:.*]] = arith.addi
// CHECK-NEXT: match_lit %[[N]]
idr.func private @scrutinee(%x: i64) -> i64 {
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
// CHECK-LABEL: idr.func private @used_after(
// CHECK: %[[S:.*]] = idr.str.append
// CHECK: match_lit
// CHECK: call @keep(%[[S]])
// CHECK: call @keep(%[[S]])
idr.func private @keep(%a0: !idr.str) -> i64 {
  idr.crash "no body"
  ub.unreachable
}
idr.func private @used_after(%n: i64, %a: !idr.str, %b: !idr.str) -> i64 {
  %s = idr.str.append %a, %b
  %r = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    %k = idr.call @keep(%s) : (!idr.str) -> i64
    idr.yield %k : i64
  }
  default {
    idr.yield %n : i64
  }
  }
  %k2 = idr.call @keep(%s) : (!idr.str) -> i64
  %t = arith.addi %r, %k2 : i64
  return %t : i64
}

// A value with an effect (a guard, which may crash) stays before the match.
// CHECK-LABEL: idr.func private @may_crash(
// CHECK: idr.check.nonzero
// CHECK: match_lit
idr.func private @may_crash(%n: i64, %x: i64, %y: i64) -> i64 {
  %y1 = idr.check.nonzero %y, "division by zero" : i64
  %q = idr.div signed %x, %y1 : i64
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
