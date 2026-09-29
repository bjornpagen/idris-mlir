// RUN: idris-mlir-opt %s --idr-effects | FileCheck %s
// RUN: idris-mlir-opt %s --idr-effects --idr-effects | FileCheck %s
// idr-effects: #idr.effects on every function. `io` when the function
// takes a world, as a parameter or in data one holds; `crash` when it
// reaches an op that may crash, through calls and through the labels of
// the closures it makes. A function without a body, and every function
// that reaches one, does both. Running the pass again changes nothing.

idr.data @IORes {
  idr.ctor @MkIORes tag 0 (i64, !idr.world)
}
// A sum of closures as idr-defunctionalize makes it: one constructor per
// label, named after its function.
idr.data @fn$0 closures {
  idr.ctor @divides tag 0 ()
  idr.ctor @pure tag 1 ()
}

// CHECK-LABEL: func.func private @pure(
// CHECK-SAME: idr.effects = #idr.effects<none>
func.func private @pure(%x: i64) -> i64 attributes {idr.total} {
  %r = arith.addi %x, %x : i64
  return %r : i64
}

// A division by a nonzero constant cannot crash; a stale fact goes.
// CHECK-LABEL: func.func private @divides_safely(
// CHECK-SAME: idr.effects = #idr.effects<none>
func.func private @divides_safely(%x: i64) -> i64 attributes {idr.effects = #idr.effects<io, crash>} {
  %c = arith.constant 3 : i64
  %r = idr.div signed %x, %c : i64
  return %r : i64
}

// CHECK-LABEL: func.func private @divides(
// CHECK-SAME: idr.effects = #idr.effects<crash>
func.func private @divides(%x: i64) -> i64 {
  %r = idr.div signed %x, %x : i64
  return %r : i64
}

// CHECK-LABEL: func.func private @crashes_in_region(
// CHECK-SAME: idr.effects = #idr.effects<crash>
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

// Taking a world is performing IO, whatever the body does with it.
// CHECK-LABEL: func.func private @writes(
// CHECK-SAME: idr.effects = #idr.effects<io>
func.func private @writes(%w: !idr.world) -> !idr.world {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}
// CHECK-LABEL: func.func private @passes_world(
// CHECK-SAME: idr.effects = #idr.effects<io>
func.func private @passes_world(%w: !idr.world) -> !idr.world {
  return %w : !idr.world
}
// A world in data counts too.
// CHECK-LABEL: func.func private @finishes(
// CHECK-SAME: idr.effects = #idr.effects<io>
func.func private @finishes(%r: !idr.data<@IORes>) -> !idr.world {
  %w = idr.field %r[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
  %w1 = func.call @writes(%w) : (!idr.world) -> !idr.world
  return %w1 : !idr.world
}

// Crashes flow through calls, and around a cycle of calls.
// CHECK-LABEL: func.func private @calls(
// CHECK-SAME: idr.effects = #idr.effects<io, crash>
func.func private @calls(%x: i64, %w: !idr.world) -> !idr.world {
  %q = func.call @divides(%x) : (i64) -> i64
  %w1 = func.call @writes(%w) : (!idr.world) -> !idr.world
  return %w1 : !idr.world
}
// CHECK-LABEL: func.func private @ping(
// CHECK-SAME: idr.effects = #idr.effects<crash>
func.func private @ping(%x: i64) -> i64 {
  %r = func.call @pong(%x) : (i64) -> i64
  return %r : i64
}
// CHECK-LABEL: func.func private @pong(
// CHECK-SAME: idr.effects = #idr.effects<crash>
func.func private @pong(%x: i64) -> i64 {
  %y = func.call @ping(%x) : (i64) -> i64
  %r = func.call @divides(%y) : (i64) -> i64
  return %r : i64
}

// A function that only builds an IO action performs none: it takes no
// world, and whoever runs the action gives it one.
// CHECK-LABEL: func.func private @makes_writer(
// CHECK-SAME: idr.effects = #idr.effects<none>
func.func private @makes_writer() -> !idr.fn<(!idr.world) -> (!idr.world)> {
  %c = idr.closure @writes() : () -> !idr.fn<(!idr.world) -> (!idr.world)>
  return %c : !idr.fn<(!idr.world) -> (!idr.world)>
}

// A crash reachable only through a closure it makes counts where the
// closure is made: by idr.closure, as a constant, or as a constructor of a
// sum of closures.
// CHECK-LABEL: func.func private @makes_divider(
// CHECK-SAME: idr.effects = #idr.effects<crash>
func.func private @makes_divider() -> !idr.fn<(i64) -> (i64)> {
  %c = idr.closure @divides() : () -> !idr.fn<(i64) -> (i64)>
  return %c : !idr.fn<(i64) -> (i64)>
}
// CHECK-LABEL: func.func private @has_divider(
// CHECK-SAME: idr.effects = #idr.effects<crash>
func.func private @has_divider() -> !idr.fn<(i64) -> (i64)> {
  %c = idr.constant #idr.closure<@divides, []> : !idr.fn<(i64) -> (i64)>
  return %c : !idr.fn<(i64) -> (i64)>
}
// CHECK-LABEL: func.func private @builds_divider(
// CHECK-SAME: idr.effects = #idr.effects<crash>
func.func private @builds_divider() -> !idr.data<@fn$0> {
  %c = idr.con @fn$0::@divides() : () -> !idr.data<@fn$0>
  return %c : !idr.data<@fn$0>
}
// CHECK-LABEL: func.func private @has_sum_divider(
// CHECK-SAME: idr.effects = #idr.effects<crash>
func.func private @has_sum_divider() -> !idr.data<@fn$0> {
  %c = idr.constant #idr.con<@fn$0::@divides, []> : !idr.data<@fn$0>
  return %c : !idr.data<@fn$0>
}
// CHECK-LABEL: func.func private @builds_pure(
// CHECK-SAME: idr.effects = #idr.effects<none>
func.func private @builds_pure() -> !idr.data<@fn$0> {
  %c = idr.con @fn$0::@pure() : () -> !idr.data<@fn$0>
  return %c : !idr.data<@fn$0>
}

// Applying a closure it is given does not count: what the closure may do
// counts where it is made, and a call that passes it on is judged by it.
// CHECK-LABEL: func.func private @applies(
// CHECK-SAME: idr.effects = #idr.effects<none>
func.func private @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
  %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}

// A function without a body, and its callers, do everything.
// CHECK-LABEL: func.func private @external(
// CHECK-SAME: idr.effects = #idr.effects<io, crash>
func.func private @external(i64) -> i64
// CHECK-LABEL: func.func @main(
// CHECK-SAME: idr.effects = #idr.effects<io, crash>
func.func @main() -> i64 {
  %c = arith.constant 1 : i64
  %r = func.call @external(%c) : (i64) -> i64
  return %r : i64
}
