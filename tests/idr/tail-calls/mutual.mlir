// RUN: idris-mlir-cc %s -o %t.o --no-eval
// RUN: %cc %t.o -o %t
// RUN: env IDRIS_RT_STACK=1048576 %t > %t.out
// RUN: FileCheck %s < %t.out
// RUN: idris-mlir-cc %s --emit=mlir -o %t.mlir --no-eval
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@Prog.main -o /dev/null
// RUN: idris-mlir-cc %s --emit=mlir -o %t.calls.mlir --no-eval --without=idr-tail-calls
// RUN: %status 1 idris-mlir-opt %t.calls.mlir --idr-expect=holds=constant-stack=@Prog.main -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=GROWS < %t.err
// Functions that call one another in tail position, none itself: a
// recursion that idr-tail-loops makes no loop of (no_inline keeps the
// functions apart, as a loop breaker does). idr-tail-calls makes each of
// those calls a guaranteed tail call, so ten million of them run on a 1 MiB
// stack; without it, the stack grows with the recursion. @spin and @turn
// return nine words, more than the targets return in registers: they write
// them through a pointer, which each tail call passes on.
// CHECK: 19999999
// CHECK-NEXT: 10000000
// CHECK-NEXT: 10000008
// GROWS: expected constant-stack: the stack grows with the recursion of
module attributes {idr.program} {
  idr.data @Unit {
    idr.ctor @MkUnit ()
  }
  idr.data @Nine {
    idr.ctor @Nine (i64, i64, i64, i64, i64, i64, i64, i64, i64)
  }
  func.func private @a(%n: i64, %acc: i64) -> i64 attributes {no_inline} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %one = arith.constant 1 : i64
      %add = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %s = arith.addi %acc, %add : i64
      %x = func.call @b(%m, %s) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @b(%n: i64, %acc: i64) -> i64 attributes {no_inline} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %one = arith.constant 1 : i64
      %add = arith.constant 2 : i64
      %m = arith.subi %n, %one : i64
      %s = arith.addi %acc, %add : i64
      %x = func.call @c(%m, %s) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @c(%n: i64, %acc: i64) -> i64 attributes {no_inline} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %one = arith.constant 1 : i64
      %add = arith.constant 3 : i64
      %m = arith.subi %n, %one : i64
      %s = arith.addi %acc, %add : i64
      %x = func.call @a(%m, %s) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @spin(%n: i64, %v: !idr.data<@Nine>) -> !idr.data<@Nine> attributes {no_inline} {
    %r = idr.match_lit %n : i64 -> (!idr.data<@Nine>) {
    case 0 {
      idr.yield %v : !idr.data<@Nine>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f0 = idr.field %v[@Nine, 0] : !idr.data<@Nine> -> i64
      %f1 = idr.field %v[@Nine, 1] : !idr.data<@Nine> -> i64
      %f2 = idr.field %v[@Nine, 2] : !idr.data<@Nine> -> i64
      %f3 = idr.field %v[@Nine, 3] : !idr.data<@Nine> -> i64
      %f4 = idr.field %v[@Nine, 4] : !idr.data<@Nine> -> i64
      %f5 = idr.field %v[@Nine, 5] : !idr.data<@Nine> -> i64
      %f6 = idr.field %v[@Nine, 6] : !idr.data<@Nine> -> i64
      %f7 = idr.field %v[@Nine, 7] : !idr.data<@Nine> -> i64
      %f8 = idr.field %v[@Nine, 8] : !idr.data<@Nine> -> i64
      %g0 = arith.addi %f0, %one : i64
      %g1 = arith.addi %f1, %one : i64
      %g2 = arith.addi %f2, %one : i64
      %g3 = arith.addi %f3, %one : i64
      %g4 = arith.addi %f4, %one : i64
      %g5 = arith.addi %f5, %one : i64
      %g6 = arith.addi %f6, %one : i64
      %g7 = arith.addi %f7, %one : i64
      %g8 = arith.addi %f8, %one : i64
      %w = idr.con @Nine::@Nine(%g0, %g1, %g2, %g3, %g4, %g5, %g6, %g7, %g8) : (i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.data<@Nine>
      %x = func.call @turn(%m, %w) : (i64, !idr.data<@Nine>) -> !idr.data<@Nine>
      idr.yield %x : !idr.data<@Nine>
    }
    }
    return %r : !idr.data<@Nine>
  }
  func.func private @turn(%n: i64, %v: !idr.data<@Nine>) -> !idr.data<@Nine> attributes {no_inline} {
    %r = idr.match_lit %n : i64 -> (!idr.data<@Nine>) {
    case 0 {
      idr.yield %v : !idr.data<@Nine>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f0 = idr.field %v[@Nine, 0] : !idr.data<@Nine> -> i64
      %f1 = idr.field %v[@Nine, 1] : !idr.data<@Nine> -> i64
      %f2 = idr.field %v[@Nine, 2] : !idr.data<@Nine> -> i64
      %f3 = idr.field %v[@Nine, 3] : !idr.data<@Nine> -> i64
      %f4 = idr.field %v[@Nine, 4] : !idr.data<@Nine> -> i64
      %f5 = idr.field %v[@Nine, 5] : !idr.data<@Nine> -> i64
      %f6 = idr.field %v[@Nine, 6] : !idr.data<@Nine> -> i64
      %f7 = idr.field %v[@Nine, 7] : !idr.data<@Nine> -> i64
      %f8 = idr.field %v[@Nine, 8] : !idr.data<@Nine> -> i64
      %g0 = arith.addi %f0, %one : i64
      %g1 = arith.addi %f1, %one : i64
      %g2 = arith.addi %f2, %one : i64
      %g3 = arith.addi %f3, %one : i64
      %g4 = arith.addi %f4, %one : i64
      %g5 = arith.addi %f5, %one : i64
      %g6 = arith.addi %f6, %one : i64
      %g7 = arith.addi %f7, %one : i64
      %g8 = arith.addi %f8, %one : i64
      %w = idr.con @Nine::@Nine(%g0, %g1, %g2, %g3, %g4, %g5, %g6, %g7, %g8) : (i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.data<@Nine>
      %x = func.call @spin(%m, %w) : (i64, !idr.data<@Nine>) -> !idr.data<@Nine>
      idr.yield %x : !idr.data<@Nine>
    }
    }
    return %r : !idr.data<@Nine>
  }
  func.func @Prog.main(%w: !idr.world) -> (!idr.data<@Unit>, !idr.world) {
    %nl = arith.constant 10 : i32
    %n = arith.constant 10000000 : i64
    %zero = arith.constant 0 : i64
    %r = func.call @a(%n, %zero) : (i64, i64) -> i64
    %w1 = idr.io.put_int signed %r, %w : i64
    %w2 = idr.io.put_char %nl, %w1
    %k0 = arith.constant 0 : i64
    %k1 = arith.constant 1 : i64
    %k2 = arith.constant 2 : i64
    %k3 = arith.constant 3 : i64
    %k4 = arith.constant 4 : i64
    %k5 = arith.constant 5 : i64
    %k6 = arith.constant 6 : i64
    %k7 = arith.constant 7 : i64
    %k8 = arith.constant 8 : i64
    %v0 = idr.con @Nine::@Nine(%k0, %k1, %k2, %k3, %k4, %k5, %k6, %k7, %k8) : (i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.data<@Nine>
    %v = func.call @spin(%n, %v0) : (i64, !idr.data<@Nine>) -> !idr.data<@Nine>
    %first = idr.field %v[@Nine, 0] : !idr.data<@Nine> -> i64
    %last = idr.field %v[@Nine, 8] : !idr.data<@Nine> -> i64
    %w3 = idr.io.put_int signed %first, %w2 : i64
    %w4 = idr.io.put_char %nl, %w3
    %w5 = idr.io.put_int signed %last, %w4 : i64
    %w6 = idr.io.put_char %nl, %w5
    %unit = idr.constant #idr.con<@Unit::@MkUnit, []> : !idr.data<@Unit>
    return %unit, %w6 : !idr.data<@Unit>, !idr.world
  }
}
