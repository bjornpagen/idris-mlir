// RUN: idris-mlir-opt %s --idr-effects --idr-expect=holds=facts-as-marked -o /dev/null
// RUN: sed 's/{expect.facts = "drop move delay merge"} : (i64) -> i64 \/\/ square/{expect.facts = "delay"} : (i64) -> i64/' %s > %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-effects --idr-expect=holds=facts-as-marked -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=WRONG < %t.err
// What an op answers about itself, a call from the effects idr-effects
// found for its callee: an unused call may be dropped, and an op moved
// across anything, when it only computes, as a division does once its
// guard has run; an op may be delayed when it performs no IO, though it
// may crash, as a guard may, or not return; and two equal ops are one
// value when they have no effect at all, which a guard, a crash and IO
// have. A call's effects are its callee's, which it carries no copy of:
// by the time effects are known, no closure is passed to a call.
// WRONG: error: expected facts-as-marked: in @main, idr.call answers "drop move delay merge", not "delay"
// WRONG-NOT: error:

idr.program @queries root(@root) stage(first) {
  idr.func @square(%x: i64) -> i64 attributes {total} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @partial(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @divides(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %r = idr.div signed %x, %y : i64
    return %r : i64
  }
  idr.func @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    return %w1 : !idr.world
  }
  // May do anything: it performs IO, and Idris did not prove that it ends.
  idr.func @anything(%x: i64) -> i64 {
    %w = idr.world.new
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    %r = idr.call @anything(%x) : (i64) -> i64
    return %r : i64
  }
  // A function Idris proved that reaches one it did not, as a call of an
  // interface's method reaches its implementation, may not return either.
  idr.func @proved_calls_partial(%x: i64) -> i64 attributes {total} {
    %r = idr.call @partial(%x) : (i64) -> i64
    return %r : i64
  }

  idr.func @main(%x: i64, %y: i64, %w: !idr.world) -> !idr.world {
    %three = arith.constant 3 : i64
    %a = idr.call @square(%x) {expect.facts = "drop move delay merge"} : (i64) -> i64 // square
    %b = idr.call @square(%three) {expect.facts = "drop move delay merge"} : (i64) -> i64
    %c = idr.call @partial(%x) {expect.facts = "delay"} : (i64) -> i64
    %d = idr.call @partial(%three) {expect.facts = "delay"} : (i64) -> i64
    %e = idr.call @divides(%x) {expect.facts = "delay"} : (i64) -> i64
    %f = idr.call @anything(%three) {expect.facts = ""} : (i64) -> i64
    %pp = idr.call @proved_calls_partial(%x) {expect.facts = "delay"} : (i64) -> i64
    %w1 = idr.call @writes(%x, %w) {expect.facts = ""} : (i64, !idr.world) -> !idr.world
    %y1 = idr.check.nonzero %y, "division by zero" {expect.facts = "delay"} : i64
    %q = idr.div signed %x, %y1 {expect.facts = "move delay merge"} : i64
    %r = idr.div signed %x, %three {expect.facts = "move delay merge"} : i64
    %n = idr.match_lit %x : i64 -> (i64) attributes {expect.facts = "delay"} {
    case 0 {
      idr.yield %y : i64
    }
    default {
      idr.crash "no"
      ub.unreachable
    }
    }
    %ch = arith.constant 65 : i32
    %w2 = idr.io.put_char %ch, %w1 {expect.facts = ""}
    return %w2 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
