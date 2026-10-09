// RUN: idris-mlir-opt %s --idr-effects --idr-expect=holds=facts-as-marked -o /dev/null
// RUN: sed 's/{expect.facts = "drop move delay"} : (i64) -> i64 \/\/ square/{expect.facts = "delay"} : (i64) -> i64/' %s > %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-effects --idr-expect=holds=facts-as-marked -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=WRONG < %t.err
// What lib/Facts answers about ops, from the facts idr-effects finds: an
// unused call may be dropped, and an op moved across anything, when it only
// computes, as a division does once its guard has run; an op may be
// delayed when it performs no IO, though it may crash, as a guard may, or
// not return; a closed call may be evaluated when what it runs
// performs no IO. A closure a call is given counts by its label when it is
// made where the call is, and as anything when it is not.
// WRONG: error: expected facts-as-marked: in @main, func.call answers "drop move delay", not "delay"
// WRONG-NOT: error:

func.func private @square(%x: i64) -> i64 attributes {idr.total} {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @partial(%x: i64) -> i64 {
  %r = arith.muli %x, %x : i64
  return %r : i64
}
func.func private @divides(%x: i64) -> i64 attributes {idr.total} {
  %y = idr.check.nonzero %x, "division by zero" : i64
  %r = idr.div signed %x, %y : i64
  return %r : i64
}
func.func private @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {idr.total} {
  %c = arith.constant 65 : i32
  %w1 = idr.io.put_char %c, %w
  return %w1 : !idr.world
}
func.func private @applies(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {idr.total} {
  %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}
func.func private @external(i64) -> i64
// A function Idris proved that reaches one it did not, as a call of an
// interface's method reaches its implementation, may not return either.
func.func private @proved_calls_partial(%x: i64) -> i64 attributes {idr.total} {
  %r = func.call @partial(%x) : (i64) -> i64
  return %r : i64
}
// An IO action, or any closure Idris proved is used once, is linear.
func.func private @applies_once(%f: !idr.lin<!idr.fn<(i64) -> (i64)>>, %x: i64) -> i64 attributes {idr.total} {
  %g = idr.lin.use %f : !idr.lin<!idr.fn<(i64) -> (i64)>>
  %r = idr.apply %g(%x) : !idr.fn<(i64) -> (i64)>
  return %r : i64
}

func.func @main(%x: i64, %y: i64, %w: !idr.world, %g: !idr.fn<(i64) -> (i64)>) -> !idr.world {
  %three = arith.constant 3 : i64
  %a = func.call @square(%x) {expect.facts = "drop move delay"} : (i64) -> i64 // square
  %b = func.call @square(%three) {expect.facts = "drop move delay evaluate"} : (i64) -> i64
  %c = func.call @partial(%x) {expect.facts = "delay"} : (i64) -> i64
  %d = func.call @partial(%three) {expect.facts = "delay evaluate"} : (i64) -> i64
  %e = func.call @divides(%x) {expect.facts = "delay"} : (i64) -> i64
  %f = func.call @external(%three) {expect.facts = ""} : (i64) -> i64
  %pp = func.call @proved_calls_partial(%x) {expect.facts = "delay"} : (i64) -> i64
  %w1 = func.call @writes(%x, %w) {expect.facts = ""} : (i64, !idr.world) -> !idr.world
  %sq = idr.constant #idr.closure<@square, []> : !idr.fn<(i64) -> (i64)>
  %h = func.call @applies(%sq, %x) {expect.facts = "drop move delay"} : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  %cr = idr.constant #idr.closure<@divides, []> : !idr.fn<(i64) -> (i64)>
  %i = func.call @applies(%cr, %three) {expect.facts = "delay evaluate"} : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  %made = idr.closure @square() : () -> !idr.fn<(i64) -> (i64)>
  %j = func.call @applies(%made, %x) {expect.facts = "drop move delay"} : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  %k = func.call @applies(%g, %x) {expect.facts = ""} : (!idr.fn<(i64) -> (i64)>, i64) -> i64
  %lsq = idr.lin.enter %sq : !idr.lin<!idr.fn<(i64) -> (i64)>>
  %l = func.call @applies_once(%lsq, %x) {expect.facts = "drop move delay"} : (!idr.lin<!idr.fn<(i64) -> (i64)>>, i64) -> i64
  %lcr = idr.lin.enter %cr : !idr.lin<!idr.fn<(i64) -> (i64)>>
  %m = func.call @applies_once(%lcr, %x) {expect.facts = "delay"} : (!idr.lin<!idr.fn<(i64) -> (i64)>>, i64) -> i64
  %y1 = idr.check.nonzero %y, "division by zero" {expect.facts = "delay"} : i64
  %q = idr.div signed %x, %y1 {expect.facts = "move delay"} : i64
  %r = idr.div signed %x, %three {expect.facts = "move delay"} : i64
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
