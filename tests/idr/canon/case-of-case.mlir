// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// rule: IDR-MATCH-5, IDR-MATCH-6, ELIM-G-7, OPT-SAFE-1
// A3, case-of-case: the single consumer of a match's result moves into every
// region that yields, when in some region it meets a value it folds or
// canonicalizes against.

idr.data @Maybe {
  idr.ctor @Nothing tag 0 () {quantities = []}
  idr.ctor @Just tag 1 (i64) {quantities = ["w"]}
}
idr.data @P {
  idr.ctor @MkP tag 0 (i64, i64) {quantities = ["w", "w"]}
}

// putStr (maybe "none" show m): each region writes its own string, and
// `show` becomes put_int.
// CHECK-LABEL: func.func @put_maybe(
// CHECK-SAME: %[[M:.*]]: !idr.data<@Maybe>, %[[W:.*]]: !idr.world)
// CHECK: %[[R:.*]] = idr.match %[[M]] : !idr.data<@Maybe> -> (!idr.world) {
// CHECK-NEXT: case @Nothing() {
// CHECK-NEXT: %[[W1:.*]] = idr.io.put_str %{{.*}}, %[[W]]
// CHECK-NEXT: idr.yield %[[W1]] : !idr.world
// CHECK-NEXT: }
// CHECK-NEXT: case @Just(%[[X:.*]]: i64) {
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_int signed %[[X]], %[[W]] : i64
// CHECK-NEXT: idr.yield %[[W2]] : !idr.world
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: return %[[R]]
func.func @put_maybe(%m: !idr.data<@Maybe>, %w: !idr.world) -> !idr.world {
  %s = idr.match %m : !idr.data<@Maybe> -> (!idr.str) {
  case @Nothing() {
    %c = idr.constant "none" : !idr.str
    idr.yield %c : !idr.str
  }
  case @Just(%x: i64) {
    %t = idr.str.show signed %x : i64
    idr.yield %t : !idr.str
  }
  }
  %w1 = idr.io.put_str %s, %w
  return %w1 : !idr.world
}

// A consumer that folds on a constructor: fst (if b then (1, 2) else p).
// CHECK-LABEL: func.func @field_of(
// CHECK-SAME: %{{.*}}: i64, %[[P:.*]]: !idr.data<@P>)
// CHECK: idr.match_lit
// CHECK-NEXT: case 0 {
// CHECK-NEXT: %[[F:.*]] = idr.field %[[P]][@MkP, 0]
// CHECK-NEXT: idr.yield %[[F]] : i64
// CHECK: default {
// CHECK-NEXT: idr.yield %{{.*}} : i64
func.func @field_of(%b: i64, %p: !idr.data<@P>) -> i64 {
  %q = idr.match_lit %b : i64 -> (!idr.data<@P>) {
  case 0 {
    idr.yield %p : !idr.data<@P>
  }
  default {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %c = idr.con @P::@MkP(%one, %two) : (i64, i64) -> !idr.data<@P>
    idr.yield %c : !idr.data<@P>
  }
  }
  %f = idr.field %q[@MkP, 0] : !idr.data<@P> -> i64
  return %f : i64
}

// The consumer does not move past an op with effects.
// CHECK-LABEL: func.func @past_effect(
// CHECK: idr.match
// CHECK: idr.io.put_char
// CHECK-NEXT: idr.io.put_str
func.func @past_effect(%m: !idr.data<@Maybe>, %w: !idr.world) -> !idr.world {
  %s = idr.match %m : !idr.data<@Maybe> -> (!idr.str) {
  case @Nothing() {
    %c = idr.constant "none" : !idr.str
    idr.yield %c : !idr.str
  }
  case @Just(%x: i64) {
    %t = idr.str.show signed %x : i64
    idr.yield %t : !idr.str
  }
  }
  %ch = arith.constant 65 : i32
  %w1 = idr.io.put_char %ch, %w
  %w2 = idr.io.put_str %s, %w1
  return %w2 : !idr.world
}

// Nothing to meet: the consumer stays after the match.
// CHECK-LABEL: func.func @nothing_to_meet(
// CHECK: idr.match
// CHECK: case @Just
// CHECK-NEXT: idr.yield
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: idr.io.put_str
func.func @nothing_to_meet(%m: !idr.data<@Maybe>, %a: !idr.str, %b: !idr.str,
                           %w: !idr.world) -> !idr.world {
  %s = idr.match %m : !idr.data<@Maybe> -> (!idr.str) {
  case @Nothing() {
    idr.yield %a : !idr.str
  }
  case @Just(%x: i64) {
    idr.yield %b : !idr.str
  }
  }
  %w1 = idr.io.put_str %s, %w
  return %w1 : !idr.world
}

// A region that crashes does not get the consumer.
// CHECK-LABEL: func.func @crash_region(
// CHECK: case 0 {
// CHECK-NEXT: idr.io.put_str
// CHECK: case 1 {
// CHECK-NEXT: idr.io.put_str
// CHECK: default {
// CHECK-NEXT: idr.crash
// CHECK-NEXT: ub.unreachable
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: return
func.func @crash_region(%n: i64, %w: !idr.world) -> !idr.world {
  %s = idr.match_lit %n : i64 -> (!idr.str) {
  case 0 {
    %c = idr.constant "zero" : !idr.str
    idr.yield %c : !idr.str
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
  %w1 = idr.io.put_str %s, %w
  return %w1 : !idr.world
}

// A match of a match: the consumer is itself a match, and in each region it
// meets a known constructor, so each region keeps only the case it takes.
// CHECK-LABEL: func.func @match_of_match(
// CHECK-SAME: %[[C:.*]]: i64)
// CHECK-DAG: %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-DAG: %[[TWO:.*]] = arith.constant 2 : i64
// CHECK: %[[R:.*]] = idr.match_lit %[[C]] : i64 -> (i64) {
// CHECK-NEXT: case 0 {
// CHECK-NEXT: idr.yield %[[ONE]] : i64
// CHECK: default {
// CHECK-NEXT: idr.yield %[[TWO]] : i64
// CHECK-NOT: idr.match
// CHECK: return %[[R]]
func.func @match_of_match(%c: i64) -> i64 {
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %p = idr.match_lit %c : i64 -> (!idr.data<@Maybe>) {
  case 0 {
    %j = idr.con @Maybe::@Just(%one) : (i64) -> !idr.data<@Maybe>
    idr.yield %j : !idr.data<@Maybe>
  }
  default {
    %n = idr.con @Maybe::@Nothing() : () -> !idr.data<@Maybe>
    idr.yield %n : !idr.data<@Maybe>
  }
  }
  %r = idr.match %p : !idr.data<@Maybe> -> (i64) {
  case @Just(%x: i64) {
    idr.yield %x : i64
  }
  case @Nothing() {
    idr.yield %two : i64
  }
  }
  return %r : i64
}

// A consumer whose region uses a value made after the match cannot move
// into the match, where that value does not exist yet.
// CHECK-LABEL: func.func @uses_later(
// CHECK: idr.match_lit
// CHECK: %[[K:.*]] = arith.muli
// CHECK: idr.match %{{.*}} : !idr.data<@Maybe> -> (i64) {
// CHECK: idr.yield %[[K]] : i64
func.func @uses_later(%c: i64) -> i64 {
  %one = arith.constant 1 : i64
  %p = idr.match_lit %c : i64 -> (!idr.data<@Maybe>) {
  case 0 {
    %j = idr.con @Maybe::@Just(%one) : (i64) -> !idr.data<@Maybe>
    idr.yield %j : !idr.data<@Maybe>
  }
  default {
    %n = idr.con @Maybe::@Nothing() : () -> !idr.data<@Maybe>
    idr.yield %n : !idr.data<@Maybe>
  }
  }
  %k = arith.muli %c, %c : i64
  %r = idr.match %p : !idr.data<@Maybe> -> (i64) {
  case @Just(%x: i64) {
    idr.yield %x : i64
  }
  case @Nothing() {
    idr.yield %k : i64
  }
  }
  return %r : i64
}
