// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// Canonicalization drops and moves code as lib/Facts answers: an unused
// call goes, and output moves across a call, only when the call only
// computes; a value that may crash moves only where it still runs on every
// path.

idr.data @Maybe {
  idr.ctor @Nothing ()
  idr.ctor @Just (i64)
}
func.func private @square(%x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @unknown(%x: i64) -> i64 attributes {idr.total} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @partial(%x: i64) -> i64 attributes {idr.effects = #idr.effects<diverge>} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @crashes(%x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<crash>} {
  %r = idr.div signed %x, %x : i64
  return %r : i64
}
func.func private @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
  %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}

// Unused calls go exactly when lib/Facts says they may be dropped
// (effects/queries.mlir states its answers).
// CHECK-LABEL: func.func @unused(
// CHECK-NOT: call @square
// CHECK: call @unknown
// CHECK: call @partial
// CHECK: call @crashes
// CHECK-NOT: call @square
func.func @unused(%x: i64) {
  %a = func.call @square(%x) : (i64) -> i64
  %b = func.call @unknown(%x) : (i64) -> i64
  %c = func.call @partial(%x) : (i64) -> i64
  %d = func.call @crashes(%x) : (i64) -> i64
  return
}

// Case-of-case moves output into a match across a call that only
// computes, where it writes the number one region shows; the match itself
// may crash, so it cannot move down instead.
// CHECK-LABEL: func.func @across_computing(
// CHECK: idr.match_lit
// CHECK-NEXT: case 0 {
// CHECK-NEXT: idr.io.put_int
func.func @across_computing(%n: i64, %x: i64, %w: !idr.world) -> (!idr.world, i64) {
  %s = idr.match_lit %n : i64 -> (!idr.str) {
  case 0 {
    %t = idr.str.show signed %x : i64
    idr.yield %t : !idr.str
  }
  case 1 {
    %c = idr.constant "one" : !idr.str
    idr.yield %c : !idr.str
  }
  default {
    idr.crash "no"
    ub.unreachable
  }
  }
  %q = func.call @square(%x) : (i64) -> i64
  %w1 = idr.io.put_str %s, %w
  return %w1, %q : !idr.world, i64
}

// Output stays after a call that may crash, or that applies a closure it
// is given, which may.
// CHECK-LABEL: func.func @across_crashing(
// CHECK: call @crashes
// CHECK-NEXT: idr.io.put_str
func.func @across_crashing(%n: i64, %x: i64, %w: !idr.world) -> (!idr.world, i64) {
  %s = idr.match_lit %n : i64 -> (!idr.str) {
  case 0 {
    %t = idr.str.show signed %x : i64
    idr.yield %t : !idr.str
  }
  case 1 {
    %c = idr.constant "one" : !idr.str
    idr.yield %c : !idr.str
  }
  default {
    idr.crash "no"
    ub.unreachable
  }
  }
  %q = func.call @crashes(%x) : (i64) -> i64
  %w1 = idr.io.put_str %s, %w
  return %w1, %q : !idr.world, i64
}
// CHECK-LABEL: func.func @across_given(
// CHECK: call @applies
// CHECK-NEXT: idr.io.put_str
func.func @across_given(%n: i64, %g: !idr.fn<(i64) -> (i64)>, %x: i64, %w: !idr.world) -> (!idr.world, i64) {
  %s = idr.match_lit %n : i64 -> (!idr.str) {
  case 0 {
    %t = idr.str.show signed %x : i64
    idr.yield %t : !idr.str
  }
  case 1 {
    %c = idr.constant "one" : !idr.str
    idr.yield %c : !idr.str
  }
  default {
    idr.crash "no"
    ub.unreachable
  }
  }
  %q = func.call @applies(%g, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  %w1 = idr.io.put_str %s, %w
  return %w1, %q : !idr.world, i64
}

// A match that may crash, which every region of a later match uses, moves
// into each of them, where a match of it meets its constructor: it still
// runs on every path, before anything it could hide.
// CHECK-LABEL: func.func @delayed_crash(
// CHECK-SAME: %[[C:[^:]*]]: i64, %[[N:[^:]*]]: i64)
// CHECK-NOT: idr.match_lit %[[C]]
// CHECK: idr.match_lit %[[N]]
// CHECK-NEXT: case 0 {
// CHECK: idr.crash
// CHECK: default {
// CHECK: idr.crash
func.func @delayed_crash(%c: i64, %n: i64) -> i64 {
  %p = idr.match_lit %c : i64 -> (!idr.data<@Maybe>) {
  case 0 {
    %j = idr.con @Maybe::@Just(%n) : (i64) -> !idr.data<@Maybe>
    idr.yield %j : !idr.data<@Maybe>
  }
  default {
    idr.crash "no"
    ub.unreachable
  }
  }
  %r = idr.match_lit %n : i64 -> (i64) {
  case 0 {
    %a = idr.match %p : !idr.data<@Maybe> -> (i64) {
    case @Nothing() {
      %one = arith.constant 1 : i64
      idr.yield %one : i64
    }
    case @Just(%y: i64) {
      idr.yield %y : i64
    }
    }
    idr.yield %a : i64
  }
  default {
    %b = idr.match %p : !idr.data<@Maybe> -> (i64) {
    case @Nothing() {
      %two = arith.constant 2 : i64
      idr.yield %two : i64
    }
    case @Just(%y: i64) {
      %z = arith.addi %y, %y : i64
      idr.yield %z : i64
    }
    }
    idr.yield %b : i64
  }
  }
  return %r : i64
}
