// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %t > %t.out
// RUN: FileCheck %s < %t.out
// RUN: idris-mlir-opt %s --idr-target --idr-pipeline --idr-expect=holds=constant-stack=@Prog.main -o /dev/null
// Functions that call one another in tail position, none itself: a
// recursion that idr-tail-loops makes no loop of, and that the optimizer
// never inlines, since its functions are on a cycle. idr-tail-calls makes
// each of those calls a guaranteed tail call: the pipeline's module keeps a
// constant stack, and ten million of them run.
// @spin and @turn
// return nine words, more than the targets return in registers: they write
// them through a pointer, which each tail call passes on.
// CHECK: 19999999
// CHECK-NEXT: 10000000
// CHECK-NEXT: 10000008
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!Nine = !idr.data<"Nine", plain [@Nine(i64, i64, i64, i64, i64, i64, i64, i64, i64)]>
idr.program @mutual root(@Prog.main) stage(higher) {
  idr.func @a(%n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %add = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %s = arith.addi %acc, %add : i64
      %x = idr.call @b(%m, %s) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @b(%n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %add = arith.constant 2 : i64
      %m = arith.subi %n, %one : i64
      %s = arith.addi %acc, %add : i64
      %x = idr.call @c(%m, %s) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @c(%n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %add = arith.constant 3 : i64
      %m = arith.subi %n, %one : i64
      %s = arith.addi %acc, %add : i64
      %x = idr.call @a(%m, %s) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @spin(%n: i64, %v: !Nine) -> !Nine {
    %r = idr.match_lit %n : i64 -> (!Nine) {
    case 0 {
      idr.yield %v : !Nine
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f0 = idr.field %v : !Nine @Nine[0] -> i64
      %f1 = idr.field %v : !Nine @Nine[1] -> i64
      %f2 = idr.field %v : !Nine @Nine[2] -> i64
      %f3 = idr.field %v : !Nine @Nine[3] -> i64
      %f4 = idr.field %v : !Nine @Nine[4] -> i64
      %f5 = idr.field %v : !Nine @Nine[5] -> i64
      %f6 = idr.field %v : !Nine @Nine[6] -> i64
      %f7 = idr.field %v : !Nine @Nine[7] -> i64
      %f8 = idr.field %v : !Nine @Nine[8] -> i64
      %g0 = arith.addi %f0, %one : i64
      %g1 = arith.addi %f1, %one : i64
      %g2 = arith.addi %f2, %one : i64
      %g3 = arith.addi %f3, %one : i64
      %g4 = arith.addi %f4, %one : i64
      %g5 = arith.addi %f5, %one : i64
      %g6 = arith.addi %f6, %one : i64
      %g7 = arith.addi %f7, %one : i64
      %g8 = arith.addi %f8, %one : i64
      %w = idr.con !Nine @Nine(%g0 : i64, %g1 : i64, %g2 : i64, %g3 : i64, %g4 : i64, %g5 : i64, %g6 : i64, %g7 : i64, %g8 : i64)
      %x = idr.call @turn(%m, %w) : (i64, !Nine) -> !Nine
      idr.yield %x : !Nine
    }
    }
    return %r : !Nine
  }
  idr.func @turn(%n: i64, %v: !Nine) -> !Nine {
    %r = idr.match_lit %n : i64 -> (!Nine) {
    case 0 {
      idr.yield %v : !Nine
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %f0 = idr.field %v : !Nine @Nine[0] -> i64
      %f1 = idr.field %v : !Nine @Nine[1] -> i64
      %f2 = idr.field %v : !Nine @Nine[2] -> i64
      %f3 = idr.field %v : !Nine @Nine[3] -> i64
      %f4 = idr.field %v : !Nine @Nine[4] -> i64
      %f5 = idr.field %v : !Nine @Nine[5] -> i64
      %f6 = idr.field %v : !Nine @Nine[6] -> i64
      %f7 = idr.field %v : !Nine @Nine[7] -> i64
      %f8 = idr.field %v : !Nine @Nine[8] -> i64
      %g0 = arith.addi %f0, %one : i64
      %g1 = arith.addi %f1, %one : i64
      %g2 = arith.addi %f2, %one : i64
      %g3 = arith.addi %f3, %one : i64
      %g4 = arith.addi %f4, %one : i64
      %g5 = arith.addi %f5, %one : i64
      %g6 = arith.addi %f6, %one : i64
      %g7 = arith.addi %f7, %one : i64
      %g8 = arith.addi %f8, %one : i64
      %w = idr.con !Nine @Nine(%g0 : i64, %g1 : i64, %g2 : i64, %g3 : i64, %g4 : i64, %g5 : i64, %g6 : i64, %g7 : i64, %g8 : i64)
      %x = idr.call @spin(%m, %w) : (i64, !Nine) -> !Nine
      idr.yield %x : !Nine
    }
    }
    return %r : !Nine
  }
  idr.func @Prog.main(%w: !idr.world) -> (!Unit, !idr.world) {
    %nl = arith.constant 10 : i32
    %n = arith.constant 10000000 : i64
    %zero = arith.constant 0 : i64
    %r = idr.call @a(%n, %zero) : (i64, i64) -> i64
    %w1 = idr.io.put_sint %r, %w : i64
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
    %v0 = idr.con !Nine @Nine(%k0 : i64, %k1 : i64, %k2 : i64, %k3 : i64, %k4 : i64, %k5 : i64, %k6 : i64, %k7 : i64, %k8 : i64)
    %v = idr.call @spin(%n, %v0) : (i64, !Nine) -> !Nine
    %first = idr.field %v : !Nine @Nine[0] -> i64
    %last = idr.field %v : !Nine @Nine[8] -> i64
    %w3 = idr.io.put_sint %first, %w2 : i64
    %w4 = idr.io.put_char %nl, %w3
    %w5 = idr.io.put_sint %last, %w4 : i64
    %w6 = idr.io.put_char %nl, %w5
    %unit = idr.constant !Unit #idr.con<!Unit, @MkUnit, []>
    return %unit, %w6 : !Unit, !idr.world
  }
}
