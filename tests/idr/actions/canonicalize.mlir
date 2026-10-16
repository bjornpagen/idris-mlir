// NEEDS-ACCEPTANCE: that skipping every idr-canonicalize-run action leaves the module as idr-canonicalize received it, and that idr-canonicalize changes it otherwise.
// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-canonicalize)))' --mlir-disable-threading -mlir-debug-counter=idr-canonicalize-run-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-canonicalize)))' -o %t.done.mlir
// RUN: not diff %t.none.mlir %t.done.mlir
!Maybe = !idr.data<"Maybe", plain [@Nothing(), @Just(i64)]>
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.program @"case-of-case" root(@root) stage(higher) {
  idr.func @put_maybe(%m: !Maybe, %w: !idr.world) -> !idr.world {
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

  idr.func @field_of(%b: i64, %p: !P) -> i64 {
    %q = idr.match_lit %b : i64 -> (!P) {
    case 0 {
      idr.yield %p : !P
    }
    default {
      %one = arith.constant 1 : i64
      %two = arith.constant 2 : i64
      %c = idr.con !P @MkP(%one : i64, %two : i64)
      idr.yield %c : !P
    }
    }
    %f = idr.field %q : !P @MkP[0] -> i64
    return %f : i64
  }

  idr.func @past_effect(%m: !Maybe, %w: !idr.world) -> !idr.world {
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

  idr.func @both_effects(%n: i64, %w: !idr.world) -> !idr.world {
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

  idr.func @nothing_to_meet(%m: !Maybe, %a: !idr.str, %b: !idr.str,
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

  idr.func @crash_region(%n: i64, %w: !idr.world) -> !idr.world {
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

  idr.func @match_of_match(%c: i64) -> i64 {
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %p = idr.match_lit %c : i64 -> (!Maybe) {
    case 0 {
      %j = idr.con !Maybe @Just(%one : i64)
      idr.yield %j : !Maybe
    }
    default {
      %n = idr.con !Maybe @Nothing()
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

  idr.func @uses_later(%c: i64) -> i64 {
    %one = arith.constant 1 : i64
    %p = idr.match_lit %c : i64 -> (!Maybe) {
    case 0 {
      %j = idr.con !Maybe @Just(%one : i64)
      idr.yield %j : !Maybe
    }
    default {
      %n = idr.con !Maybe @Nothing()
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

  idr.func @nested(%b: i64, %c: i64, %p: !P) -> i64 {
    %q = idr.match_lit %b : i64 -> (!P) {
    case 0 {
      %inner = idr.match_lit %c : i64 -> (!P) {
      case 0 {
        %one = arith.constant 1 : i64
        %two = arith.constant 2 : i64
        %x = idr.con !P @MkP(%one : i64, %two : i64)
        idr.yield %x : !P
      }
      default {
        %three = arith.constant 3 : i64
        %four = arith.constant 4 : i64
        %y = idr.con !P @MkP(%three : i64, %four : i64)
        idr.yield %y : !P
      }
      }
      idr.yield %inner : !P
    }
    default {
      idr.yield %p : !P
    }
    }
    %f = idr.field %q : !P @MkP[0] -> i64
    return %f : i64
  }

  idr.func @never_yields(%b: i64, %c: i64) -> i64 {
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
      %x = idr.con !P @MkP(%one : i64, %two : i64)
      idr.yield %x : !P
    }
    }
    %f = idr.field %q : !P @MkP[0] -> i64
    return %f : i64
  }

  idr.func @taken_never_completes(%f: !idr.fn<(i64) -> (i64)>) -> i64 {
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
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
