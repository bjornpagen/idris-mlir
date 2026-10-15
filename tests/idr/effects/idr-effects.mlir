// RUN: idris-mlir-opt %s --idr-effects | FileCheck %s
// RUN: idris-mlir-opt %s --idr-effects --idr-effects | FileCheck %s
// idr-effects: #idr.effects on every function and every call of a
// defunctionalized module. `io` when the function takes a world, as a
// parameter or in data one holds, or forges one; `crash` when it reaches an
// op that may crash; `diverge` when it reaches a body without Idris's proof
// (`total`), its own included. It reaches what it calls and the labels a
// dispatch of its runs; building a constructor of a sum of closures runs
// nothing. A function that may do all three carries no attribute. A
// call's effects are its callee's. Running the pass again changes nothing.

// A sum of closures as idr-defunctionalize makes it: one constructor per
// label, named after its function.
// CHECK-LABEL: idr.func private @pure(
// CHECK-SAME: effects = #idr.effects<none>
!IORes = !idr.data<"IORes", plain [@MkIORes(i64, !idr.world)]>
!fn$0 = !idr.data<"fn$0", closures [@divides(), @pure()]>
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
idr.func private @transfers(%buf: memref<?xi8, #idr.world>, %w: !idr.world) -> !idr.world attributes {total} {
  %zero = arith.constant 0 : i64
  %one = arith.constant 1 : i64
  %c0 = arith.constant 0 : index
  %d = memref.dim %buf, %c0 : memref<?xi8, #idr.world>
  %size = arith.index_cast %d : index to i64
  %at = idr.check.range %zero, %one, %size, "a byte range outside the buffer"
  %written, %w1 = idr.io.write_bytes %one, %buf[%at, %one], %w : memref<?xi8, #idr.world>
  %again = idr.check.range %zero, %one, %size, "a byte range outside the buffer"
  %read, %w2 = idr.io.read_bytes %zero, %buf[%again, %one], %w1 : memref<?xi8, #idr.world>
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
idr.func private @finishes(%r: !IORes) -> !idr.world attributes {total} {
  %w = idr.field %r[@MkIORes, 1] : !IORes -> !idr.world
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

// Building a closure runs nothing, whatever its label may do: a
// constructor of a sum of closures, built or a constant, is a value.
// CHECK-LABEL: idr.func private @builds_divider(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @builds_divider() -> !fn$0 attributes {total} {
  %c = idr.con @divides() : () -> !fn$0
  return %c : !fn$0
}
// CHECK-LABEL: idr.func private @has_sum_divider(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @has_sum_divider() -> !fn$0 attributes {total} {
  %c = idr.constant #idr.con<@divides, []> : !fn$0
  return %c : !fn$0
}

// Running one is a dispatch on its sum, each arm a call of its label: it
// may do what any of them may.
// CHECK-LABEL: idr.func private @runs(
// CHECK-SAME: effects = #idr.effects<crash>
// CHECK: call @divides(%{{.*}}) effects = <crash>
// CHECK: call @pure(%{{.*}}) effects = <none>
idr.func private @runs(%f: !fn$0, %x: i64) -> i64 attributes {total} {
  %r = idr.match %f : !fn$0 -> (i64) {
  case @divides() {
    %d = idr.call @divides(%x) : (i64) -> i64
    idr.yield %d : i64
  }
  case @pure() {
    %p = idr.call @pure(%x) : (i64) -> i64
    idr.yield %p : i64
  }
  }
  return %r : i64
}

// A function that may do everything carries no attribute: no writer
// stores the full set.
// CHECK-LABEL: idr.func private @everything(
// CHECK-NOT: effects
idr.func private @everything(%x: i64, %w: !idr.world) -> !idr.world {
  %d = idr.call @divides(%x) : (i64) -> i64
  %w1 = idr.call @everything(%d, %w) : (i64, !idr.world) -> !idr.world
  return %w1 : !idr.world
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
// it: by a call, around a cycle, or by a dispatch on a label of it. Idris's proof
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
// A cycle Idris proved does not diverge.
// CHECK-LABEL: idr.func private @proved_cycle(
// CHECK-SAME: effects = #idr.effects<none>
idr.func private @proved_cycle(%x: i64) -> i64 attributes {total} {
  %r = idr.call @proved_cycle(%x) : (i64) -> i64
  return %r : i64
}
