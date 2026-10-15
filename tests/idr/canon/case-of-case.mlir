// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// Case-of-case: the single consumer of a match's result moves into every
// region that yields, when in some region it meets a value it folds or
// canonicalizes against.


// putStr (maybe "none" show m): each region writes its own string, and
// `show` becomes put_int.
// CHECK-LABEL: idr.func private @put_maybe(
// CHECK-SAME: %[[M:.*]]: !Maybe, %[[W:.*]]: !idr.world)
// CHECK: %[[R:.*]] = {{(idr\.)?}}match %[[M]] : !Maybe -> (!idr.world) {
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
!Maybe = !idr.data<"Maybe", plain [@Nothing(), @Just(i64)]>
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.func private @put_maybe(%m: !Maybe, %w: !idr.world) -> !idr.world {
  %s = idr.match %m : !Maybe -> (!idr.str) {
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
// CHECK-LABEL: idr.func private @field_of(
// CHECK-SAME: %{{.*}}: i64, %[[P:.*]]: !P)
// CHECK: match_lit
// CHECK-NEXT: case 0 {
// CHECK-NEXT: %[[F:.*]] = {{(idr\.)?}}field %[[P]][@MkP, 0]
// CHECK-NEXT: idr.yield %[[F]] : i64
// CHECK: default {
// CHECK-NEXT: idr.yield %{{.*}} : i64
idr.func private @field_of(%b: i64, %p: !P) -> i64 {
  %q = idr.match_lit %b : i64 -> (!P) {
  case 0 {
    idr.yield %p : !P
  }
  default {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %c = idr.con @MkP(%one, %two) : (i64, i64) -> !P
    idr.yield %c : !P
  }
  }
  %f = idr.field %q[@MkP, 0] : !P -> i64
  return %f : i64
}

// The consumer does not move up past an op with effects, but a match free
// of effects moves down past it to the consumer: show m is computed after
// the character is written, and each region writes its own string.
// CHECK-LABEL: idr.func private @past_effect(
// CHECK: idr.io.put_char
// CHECK-NEXT: match
// CHECK-NEXT: case @Nothing() {
// CHECK-NEXT: idr.io.put_str
// CHECK: case @Just(%[[X:.*]]: i64) {
// CHECK-NEXT: idr.io.put_int signed %[[X]]
idr.func private @past_effect(%m: !Maybe, %w: !idr.world) -> !idr.world {
  %s = idr.match %m : !Maybe -> (!idr.str) {
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

// A match with an effect (a region crashes) does not move past output, and
// the consumer does not move up past it: both stay.
// CHECK-LABEL: idr.func private @both_effects(
// CHECK: match_lit
// CHECK: crash
// CHECK: idr.io.put_char
// CHECK-NEXT: idr.io.put_str
idr.func private @both_effects(%n: i64, %w: !idr.world) -> !idr.world {
  %s = idr.match_lit %n : i64 -> (!idr.str) {
  case 0 {
    %c = idr.constant "zero" : !idr.str
    idr.yield %c : !idr.str
  }
  default {
    idr.crash "no"
    ub.unreachable
  }
  }
  %ch = arith.constant 65 : i32
  %w1 = idr.io.put_char %ch, %w
  %w2 = idr.io.put_str %s, %w1
  return %w2 : !idr.world
}

// Nothing to meet: the consumer stays after the match.
// CHECK-LABEL: idr.func private @nothing_to_meet(
// CHECK: match
// CHECK: case @Just
// CHECK-NEXT: idr.yield
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: idr.io.put_str
idr.func private @nothing_to_meet(%m: !Maybe, %a: !idr.str, %b: !idr.str,
                           %w: !idr.world) -> !idr.world {
  %s = idr.match %m : !Maybe -> (!idr.str) {
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
// CHECK-LABEL: idr.func private @crash_region(
// CHECK: case 0 {
// CHECK-NEXT: idr.io.put_int
// CHECK: case 1 {
// CHECK-NEXT: idr.io.put_str
// CHECK: default {
// CHECK-NEXT: crash
// CHECK-NEXT: ub.unreachable
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: return
idr.func private @crash_region(%n: i64, %w: !idr.world) -> !idr.world {
  %s = idr.match_lit %n : i64 -> (!idr.str) {
  case 0 {
    %t = idr.str.show signed %n : i64
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
  %w1 = idr.io.put_str %s, %w
  return %w1 : !idr.world
}

// A match of a match: the consumer is itself a match, and in each region it
// meets a known constructor, so each region keeps only the case it takes.
// CHECK-LABEL: idr.func private @match_of_match(
// CHECK-SAME: %[[C:.*]]: i64)
// CHECK-DAG: %[[ONE:.*]] = arith.constant 1 : i64
// CHECK-DAG: %[[TWO:.*]] = arith.constant 2 : i64
// CHECK: %[[R:.*]] = {{(idr\.)?}}match_lit %[[C]] : i64 -> (i64) {
// CHECK-NEXT: case 0 {
// CHECK-NEXT: idr.yield %[[ONE]] : i64
// CHECK: default {
// CHECK-NEXT: idr.yield %[[TWO]] : i64
// CHECK-NOT: {{(idr\.| )match }}
// CHECK: return %[[R]]
idr.func private @match_of_match(%c: i64) -> i64 {
  %one = arith.constant 1 : i64
  %two = arith.constant 2 : i64
  %p = idr.match_lit %c : i64 -> (!Maybe) {
  case 0 {
    %j = idr.con @Just(%one) : (i64) -> !Maybe
    idr.yield %j : !Maybe
  }
  default {
    %n = idr.con @Nothing() : () -> !Maybe
    idr.yield %n : !Maybe
  }
  }
  %r = idr.match %p : !Maybe -> (i64) {
  case @Just(%x: i64) {
    idr.yield %x : i64
  }
  case @Nothing() {
    idr.yield %two : i64
  }
  }
  return %r : i64
}

// A consumer whose region uses a value made after the match cannot move up
// into the match, where that value does not exist yet; the match, free of
// effects, moves down to it instead, and there the consumer meets each
// constructor: one match is left, of the literal. The product stays before
// it: nothing in the region folds against it.
// CHECK-LABEL: idr.func private @uses_later(
// CHECK-SAME: %[[C:.*]]: i64)
// CHECK: %[[K:.*]] = arith.muli %[[C]], %[[C]]
// CHECK-NEXT: %[[R:.*]] = {{(idr\.)?}}match_lit %[[C]] : i64 -> (i64) {
// CHECK-NEXT: case 0 {
// CHECK-NEXT: idr.yield %{{.*}} : i64
// CHECK: default {
// CHECK-NEXT: idr.yield %[[K]] : i64
// CHECK-NOT: {{(idr\.| )match }}
// CHECK: return %[[R]]
idr.func private @uses_later(%c: i64) -> i64 {
  %one = arith.constant 1 : i64
  %p = idr.match_lit %c : i64 -> (!Maybe) {
  case 0 {
    %j = idr.con @Just(%one) : (i64) -> !Maybe
    idr.yield %j : !Maybe
  }
  default {
    %n = idr.con @Nothing() : () -> !Maybe
    idr.yield %n : !Maybe
  }
  }
  %k = arith.muli %c, %c : i64
  %r = idr.match %p : !Maybe -> (i64) {
  case @Just(%x: i64) {
    idr.yield %x : i64
  }
  case @Nothing() {
    idr.yield %k : i64
  }
  }
  return %r : i64
}

// The value a consumer meets may be one match deeper: no region of the
// outer match yields a constructor, but one yields the result of an inner
// match, whose regions do. fst (if b then (if c then (1, 2) else (3, 4))
// else p): the consumer moves through both matches and folds against each
// pair; only the read of p is left.
// CHECK-LABEL: idr.func private @nested(
// CHECK-SAME: %{{.*}}: i64, %{{.*}}: i64, %[[P:.*]]: !P)
// CHECK-NOT: {{(idr\.| )con }}
// CHECK: field %[[P]][@MkP, 0]
// CHECK-NOT: {{(idr\.| )con }}
// CHECK: return
idr.func private @nested(%b: i64, %c: i64, %p: !P) -> i64 {
  %q = idr.match_lit %b : i64 -> (!P) {
  case 0 {
    %inner = idr.match_lit %c : i64 -> (!P) {
    case 0 {
      %one = arith.constant 1 : i64
      %two = arith.constant 2 : i64
      %x = idr.con @MkP(%one, %two) : (i64, i64) -> !P
      idr.yield %x : !P
    }
    default {
      %three = arith.constant 3 : i64
      %four = arith.constant 4 : i64
      %y = idr.con @MkP(%three, %four) : (i64, i64) -> !P
      idr.yield %y : !P
    }
    }
    idr.yield %inner : !P
  }
  default {
    idr.yield %p : !P
  }
  }
  %f = idr.field %q[@MkP, 0] : !P -> i64
  return %f : i64
}

// A match none of whose regions yields never completes, so in a region of
// another match nothing after it runs: the region ends in ub.unreachable
// right after it. Here the consumer that case-of-case moved into that region
// goes, and the region keeps only the match that crashes.
// CHECK-LABEL: idr.func private @never_yields(
// CHECK: case 0 {
// CHECK-NEXT: match_lit
// CHECK: crash "zero"
// CHECK: crash "other"
// CHECK-NEXT: ub.unreachable
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: ub.unreachable
// CHECK-NEXT: }
idr.func private @never_yields(%b: i64, %c: i64) -> i64 {
  %q = idr.match_lit %b : i64 -> (!P) {
  case 0 {
    %inner = idr.match_lit %c : i64 -> (!P) {
    case 0 {
      idr.crash "zero"
      ub.unreachable
    }
    default {
      idr.crash "other"
      ub.unreachable
    }
    }
    idr.yield %inner : !P
  }
  default {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %x = idr.con @MkP(%one, %two) : (i64, i64) -> !P
    idr.yield %x : !P
  }
  }
  %f = idr.field %q[@MkP, 0] : !P -> i64
  return %f : i64
}

// A match on a constant takes the one region the constant selects: when
// that region crashes, the match never completes whatever the others
// yield, and nothing after it runs, here a function body's apply and
// return.
// CHECK-LABEL: idr.func private @taken_never_completes(
// CHECK-NOT: {{(idr\.| )apply }}
// CHECK: crash "taken"
// CHECK-NOT: {{(idr\.| )apply }}
// CHECK-NOT: return
// CHECK: ub.unreachable
// CHECK-NEXT: }
idr.func private @taken_never_completes(%f: !idr.fn<(i64) -> (i64)>) -> i64 {
  %t = arith.constant 1 : i64
  %r = idr.match_lit %t : i64 -> (i64) {
  case 0 {
    %z = arith.constant 0 : i64
    idr.yield %z : i64
  }
  default {
    idr.crash "taken"
    ub.unreachable
  }
  }
  %y = idr.apply %f(%r) : !idr.fn<(i64) -> (i64)>
  return %y : i64
}
