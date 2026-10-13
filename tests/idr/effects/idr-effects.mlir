// RUN: idris-mlir-opt %s --idr-effects | FileCheck %s
// RUN: idris-mlir-opt %s --idr-effects --idr-effects | FileCheck %s
// idr-effects: #idr.effects on every function and every call. `io` when
// the function takes a world, as a parameter or in data one holds;
// `crash` when it reaches an op that may crash, through calls and through
// the labels of the closures it makes; `diverge` when it reaches, the
// same way, a body without Idris's proof (`total`), its own included. A
// function without a body, and every function that reaches one, does all
// three, which is no attribute. A call may do what its callee may, and
// what the closures it passes may do when applied; a call of a callee that
// may do everything carries none. Running the pass again changes nothing.

idr.data @IORes {
  idr.ctor @MkIORes (i64, !idr.world)
}
// A sum of closures as idr-defunctionalize makes it: one constructor per
// label, named after its function.
idr.data @fn$0 closures {
  idr.ctor @divides ()
  idr.ctor @pure ()
}

// CHECK-LABEL: idr.func private @pure(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @pure(%x: i64) -> i64 attributes {total} {
  %r = arith.addi %x, %x : i64
  return %r : i64
}

// A division by a nonzero constant cannot crash, and needs no guard; a
// stale fact goes.
// CHECK-LABEL: idr.func private @divides_safely(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @divides_safely(%x: i64) -> i64 attributes {total, effects = #idr.effects<io, crash>} {
  %c = arith.constant 3 : i64
  %r = idr.div signed %x, %c : i64
  return %r : i64
}

// CHECK-LABEL: idr.func private @divides(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @divides(%x: i64) -> i64 attributes {total} {
  %y = idr.check.nonzero %x, "division by zero" : i64
  %r = idr.div signed %x, %y : i64
  return %r : i64
}

// CHECK-LABEL: idr.func private @crashes_in_region(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @crashes_in_region(%x: i64) -> i64 attributes {total} {
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

// A byte transfer ends the program when its range lies outside the buffer:
// io, and the crash of the guard of its range.
// CHECK-LABEL: idr.func private @transfers(
// CHECK-SAME: effects = #idr.effects<io, crash>
idr.func private @transfers(%buf: memref<?xi8>, %w: !idr.world) -> !idr.world attributes {total} {
  %zero = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %c0 = arith.constant 0 : index
  %d = memref.dim %buf, %c0 : memref<?xi8>
  %size = arith.index_cast %d : index to i64
  %at = idr.check.range %zero, %one, %size, "a byte range outside the buffer"
  %written, %w1 = idr.io.write_bytes %one, %buf[%at, %one], %w : memref<?xi8>
  %again = idr.check.range %zero, %one, %size, "a byte range outside the buffer"
  %read, %w2 = idr.io.read_bytes %zero, %buf[%again, %one], %w1 : memref<?xi8>
  return %w2 : !idr.world
}

// Taking a world is performing IO, whatever the body does with it.
// CHECK-LABEL: idr.func private @writes(
// CHECK-SAME: effects = #idr.effects<io>
idr.func private @writes(%w: !idr.world) -> !idr.world attributes {total} {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}
// CHECK-LABEL: idr.func private @passes_world(
// CHECK-SAME: effects = #idr.effects<io>
idr.func private @passes_world(%w: !idr.world) -> !idr.world attributes {total} {
  return %w : !idr.world
}
// A world in data counts too.
// CHECK-LABEL: idr.func private @finishes(
// CHECK-SAME: effects = #idr.effects<io>
idr.func private @finishes(%r: !idr.data<@IORes>) -> !idr.world attributes {total} {
  %w = idr.field %r[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
  %w1 = idr.call @writes(%w) : (!idr.world) -> !idr.world
  return %w1 : !idr.world
}

// Crashes flow through calls, and around a cycle of calls.
// CHECK-LABEL: idr.func private @calls(
// CHECK-SAME: effects = #idr.effects<io, crash>
// CHECK: call @divides(%{{.*}}) effects = <crash>
// CHECK: call @writes(%{{.*}}) effects = <io>
idr.func private @calls(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
  %q = idr.call @divides(%x) : (i64) -> i64
  %w1 = idr.call @writes(%w) : (!idr.world) -> !idr.world
  return %w1 : !idr.world
}
// CHECK-LABEL: idr.func private @ping(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @ping(%x: i64) -> i64 attributes {total} {
  %r = idr.call @pong(%x) : (i64) -> i64
  return %r : i64
}
// CHECK-LABEL: idr.func private @pong(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @pong(%x: i64) -> i64 attributes {total} {
  %y = idr.call @ping(%x) : (i64) -> i64
  %r = idr.call @divides(%y) : (i64) -> i64
  return %r : i64
}

// A function that only builds an IO action performs none: it takes no
// world, and whoever runs the action gives it one.
// CHECK-LABEL: idr.func private @makes_writer(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @makes_writer() -> !idr.fn<(!idr.world) -> (!idr.world)> attributes {total} {
  %c = idr.closure @writes() : () -> !idr.fn<(!idr.world) -> (!idr.world)>
  return %c : !idr.fn<(!idr.world) -> (!idr.world)>
}

// A crash reachable only through a closure it makes counts where the
// closure is made: by idr.closure, as a constant, or as a constructor of a
// sum of closures.
// CHECK-LABEL: idr.func private @makes_divider(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @makes_divider() -> !idr.fn<(i64) -> (i64)> attributes {total} {
  %c = idr.closure @divides() : () -> !idr.fn<(i64) -> (i64)>
  return %c : !idr.fn<(i64) -> (i64)>
}
// CHECK-LABEL: idr.func private @has_divider(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @has_divider() -> !idr.fn<(i64) -> (i64)> attributes {total} {
  %c = idr.constant #idr.closure<@divides, []> : !idr.fn<(i64) -> (i64)>
  return %c : !idr.fn<(i64) -> (i64)>
}
// CHECK-LABEL: idr.func private @builds_divider(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @builds_divider() -> !idr.data<@fn$0> attributes {total} {
  %c = idr.con @fn$0::@divides() : () -> !idr.data<@fn$0>
  return %c : !idr.data<@fn$0>
}
// CHECK-LABEL: idr.func private @has_sum_divider(
// CHECK-SAME: effects = #idr.effects<crash>
idr.func private @has_sum_divider() -> !idr.data<@fn$0> attributes {total} {
  %c = idr.constant #idr.con<@fn$0::@divides, []> : !idr.data<@fn$0>
  return %c : !idr.data<@fn$0>
}
// CHECK-LABEL: idr.func private @builds_pure(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @builds_pure() -> !idr.data<@fn$0> attributes {total} {
  %c = idr.con @fn$0::@pure() : () -> !idr.data<@fn$0>
  return %c : !idr.data<@fn$0>
}

// Applying a closure it is given does not count: what the closure may do
// counts where it is made, and a call that passes it on is judged by it.
// CHECK-LABEL: idr.func private @applies(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
  %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}
// Passing @applies a closure of @divides: the closure is made here, and
// the call that passes it may crash when @applies applies it.
// CHECK-LABEL: idr.func private @passes_divider(
// CHECK-SAME: effects = #idr.effects<crash>
// CHECK: call @applies(%{{.*}}, %{{.*}}) effects = <crash>
idr.func private @passes_divider(%x: i64) -> i64 attributes {total} {
  %c = idr.closure @divides() : () -> !idr.fn<(i64) -> (i64)>
  %r = idr.call @applies(%c, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  return %r : i64
}

// A function without a body, and its callers, do everything.
// CHECK-LABEL: idr.func private @external(
// CHECK-NOT: effects
idr.func private @external(i64) -> i64
// CHECK-LABEL: idr.func @main(
// CHECK-SAME: attributes {total}
// CHECK: call @external(%{{.*}}) : (i64) -> i64
idr.func @main() -> i64 attributes {total} {
  %c = arith.constant 1 : i64
  %r = idr.call @external(%c) : (i64) -> i64
  return %r : i64
}

// A world forged in the body is IO that no parameter announces.
// CHECK-LABEL: idr.func private @forges(
// CHECK-SAME: effects = #idr.effects<io>
idr.func private @forges(%c: i32) attributes {total} {
  %w = idr.world.new
  %w1 = idr.io.put_char %c, %w
  return
}

// A body without Idris's proof may diverge, and so may whatever reaches
// it: by a call, around a cycle, or by a closure it makes. Idris's proof
// of a function does not stop it: the proof counts the calls Idris saw,
// and a call of an interface's method reaches its implementation only
// once the dictionary is known, as @method_user's call of @method does.
// CHECK-LABEL: idr.func private @loops(
// CHECK-SAME: effects = #idr.effects<diverge>
idr.func private @loops(%x: i64) -> i64 {
  %r = idr.call @loops(%x) : (i64) -> i64
  return %r : i64
}
// CHECK-LABEL: idr.func private @method(
// CHECK-SAME: effects = #idr.effects<diverge>
idr.func private @method(%x: i64) -> i64 attributes {total} {
  %r = idr.call @loops(%x) : (i64) -> i64
  return %r : i64
}
// CHECK-LABEL: idr.func private @method_user(
// CHECK-SAME: effects = #idr.effects<diverge>
idr.func private @method_user(%x: i64) -> i64 attributes {total} {
  %r = idr.call @method(%x) : (i64) -> i64
  return %r : i64
}
// CHECK-LABEL: idr.func private @makes_looper(
// CHECK-SAME: effects = #idr.effects<diverge>
idr.func private @makes_looper() -> !idr.fn<(i64) -> (i64)> attributes {total} {
  %c = idr.closure @loops() : () -> !idr.fn<(i64) -> (i64)>
  return %c : !idr.fn<(i64) -> (i64)>
}
// A cycle Idris proved does not diverge.
// CHECK-LABEL: idr.func private @proved_cycle(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @proved_cycle(%x: i64) -> i64 attributes {total} {
  %r = idr.call @proved_cycle(%x) : (i64) -> i64
  return %r : i64
}
