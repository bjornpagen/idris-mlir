// RUN: idris-mlir-opt %s --idr-effects | FileCheck %s
// RUN: idris-mlir-opt %s --idr-effects --idr-effects | FileCheck %s
// rule: IDR-FACT-1, IDR-EFF-1, IDR-EFF-2
// idr-effects: a function is effectful if it reaches an idr.io op, through
// calls or the closures it creates; it may crash if it reaches an op that
// may crash. A call of a function without a body does both. Running the
// pass again changes nothing.

// CHECK-LABEL: func.func private @pure(
// CHECK-SAME: attributes {idr.effect = "pure", idr.total}
func.func private @pure(%x: i64) -> i64 attributes {idr.total} {
  %r = arith.addi %x, %x : i64
  return %r : i64
}

// A division by a nonzero constant cannot crash; a stale fact goes.
// CHECK-LABEL: func.func private @divides_safely(
// CHECK-SAME: attributes {idr.effect = "pure"}
func.func private @divides_safely(%x: i64) -> i64 attributes {idr.may_crash} {
  %c = arith.constant 3 : i64
  %r = idr.div signed %x, %c : i64
  return %r : i64
}

// CHECK-LABEL: func.func private @divides(
// CHECK-SAME: attributes {idr.effect = "pure", idr.may_crash}
func.func private @divides(%x: i64) -> i64 {
  %r = idr.div signed %x, %x : i64
  return %r : i64
}

// CHECK-LABEL: func.func private @crashes_in_region(
// CHECK-SAME: attributes {idr.effect = "pure", idr.may_crash}
func.func private @crashes_in_region(%x: i64) -> i64 {
  %r = idr.match_lit %x : i64 -> (i64) {
  case 0 {
    idr.yield %x : i64
  }
  default {
    idr.crash "no"
    ub.unreachable
  }
  }
  return %r : i64
}

// CHECK-LABEL: func.func private @writes(
// CHECK-SAME: attributes {idr.effect = "effectful"}
func.func private @writes(%w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}

// Facts flow through calls, and around a cycle of calls.
// CHECK-LABEL: func.func private @calls(
// CHECK-SAME: attributes {idr.effect = "effectful", idr.may_crash}
func.func private @calls(%x: i64, %w: !idr.world) -> !idr.world {
  %q = func.call @divides(%x) : (i64) -> i64
  %w1 = func.call @writes(%w) : (!idr.world) -> !idr.world
  return %w1 : !idr.world
}
// CHECK-LABEL: func.func private @ping(
// CHECK-SAME: attributes {idr.effect = "effectful"}
func.func private @ping(%w: !idr.world) -> !idr.world {
  %w1 = func.call @pong(%w) : (!idr.world) -> !idr.world
  return %w1 : !idr.world
}
// CHECK-LABEL: func.func private @pong(
// CHECK-SAME: attributes {idr.effect = "effectful"}
func.func private @pong(%w: !idr.world) -> !idr.world {
  %w1 = func.call @ping(%w) : (!idr.world) -> !idr.world
  %w2 = func.call @writes(%w1) : (!idr.world) -> !idr.world
  return %w2 : !idr.world
}

// A closure's effects count where it is created, by idr.closure or as a
// constant, not where it is applied.
// CHECK-LABEL: func.func private @makes_writer(
// CHECK-SAME: attributes {idr.effect = "effectful"}
func.func private @makes_writer() -> !idr.fn<(!idr.world) -> (!idr.world)> {
  %c = idr.closure @writes() : () -> !idr.fn<(!idr.world) -> (!idr.world)>
  return %c : !idr.fn<(!idr.world) -> (!idr.world)>
}
// CHECK-LABEL: func.func private @has_divider(
// CHECK-SAME: attributes {idr.effect = "pure", idr.may_crash}
func.func private @has_divider() -> !idr.fn<(i64) -> (i64)> {
  %c = idr.constant #idr.closure<@divides, []> : !idr.fn<(i64) -> (i64)>
  return %c : !idr.fn<(i64) -> (i64)>
}
// CHECK-LABEL: func.func private @applies(
// CHECK-SAME: attributes {idr.effect = "pure"}
func.func private @applies(%f: !idr.fn<(!idr.world) -> (!idr.world)>, %w: !idr.world) -> !idr.world {
  %w1 = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!idr.world)>
  return %w1 : !idr.world
}

// A function without a body, and its callers, do everything.
// CHECK-LABEL: func.func private @external(
// CHECK-SAME: attributes {idr.effect = "effectful", idr.may_crash}
func.func private @external(i64) -> i64
// CHECK-LABEL: func.func @main(
// CHECK-SAME: attributes {idr.effect = "effectful", idr.may_crash}
func.func @main() -> i64 {
  %c = arith.constant 1 : i64
  %r = func.call @external(%c) : (i64) -> i64
  return %r : i64
}
