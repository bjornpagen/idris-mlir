// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %t > %t.out
// RUN: FileCheck %s < %t.out
// Loops of every shape idr-tail-loops makes run as the recursion they
// replace: a count up to a bound (an scf.for), a count down to zero, a
// fold over a list, output before the decision, an IO fold whose
// result is its recursive call's rebuilt (record eta), and a count up to a
// bound that returns its counter (an scf.for whose counter ends past the
// bound by part of a step, or at its start when it never runs).
// CHECK: 285
// CHECK-NEXT: 7
// CHECK-NEXT: 6
// CHECK-NEXT: 3
// CHECK-NEXT: 2
// CHECK-NEXT: 1
// CHECK-NEXT: 0
// CHECK-NEXT: 1
// CHECK-NEXT: 2
// CHECK-NEXT: 3
// CHECK-NEXT: 12
// CHECK-NEXT: 5
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(!Unit, !idr.world)]>
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @loops root(@Prog.main) stage(higher) {
  idr.func @upto(%i: i64, %n: i64, %acc: i64) -> i64 attributes {total} {
    %lt = arith.cmpi slt, %i, %n : i64
    %b = arith.extui %lt : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %j = arith.addi %i, %c1 : i64
      %sq = arith.muli %i, %i : i64
      %a = arith.addi %acc, %sq : i64
      %x = idr.call @upto(%j, %n, %a) : (i64, i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // until i n = if i < n then until (i + 3) n else i
  idr.func @until(%i: i64, %n: i64) -> i64 attributes {total} {
    %lt = arith.cmpi slt, %i, %n : i64
    %b = arith.extui %lt : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      idr.yield %i : i64
    }
    default(%d: i64) {
      %c3 = arith.constant 3 : i64
      %j = arith.addi %i, %c3 : i64
      %x = idr.call @until(%j, %n) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @count(%acc: i64, %n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %a = arith.addi %acc, %c1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = idr.call @count(%a, %m) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @sum(%acc: i64, %xs: !idr.box<!List>) -> i64 attributes {total} {
    %r = idr.match %xs : !idr.box<!List> -> (i64) {
    case @Nil() {
      idr.yield %acc : i64
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %a = arith.addi %acc, %x : i64
      %s = idr.call @sum(%a, %rest) : (i64, !idr.box<!List>) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @echo(%n: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %nl = arith.constant 10 : i32
    %w1 = idr.io.put_sint %n, %w : i64
    %w2 = idr.io.put_char %nl, %w1
    %r = idr.match_lit %n : i64 -> (!idr.world) {
    case 0 {
      idr.yield %w2 : !idr.world
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = idr.call @echo(%m, %w2) : (i64, !idr.world) -> !idr.world
      idr.yield %x : !idr.world
    }
    }
    return %r : !idr.world
  }
  idr.func @traverse(%xs: !idr.box<!List>, %w: !idr.world) -> !IORes attributes {total} {
    %unit = idr.constant !Unit #idr.con<!Unit, @MkUnit, []>
    %nl = arith.constant 10 : i32
    %r = idr.match %xs : !idr.box<!List> -> (!IORes) {
    case @Nil() {
      %done = idr.con !IORes @MkIORes(%unit : !Unit, %w : !idr.world)
      idr.yield %done : !IORes
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %w1 = idr.io.put_sint %x, %w : i64
      %w2 = idr.io.put_char %nl, %w1
      %next = idr.call @traverse(%rest, %w2) : (!idr.box<!List>, !idr.world) -> !IORes
      %u = idr.field %next : !IORes @MkIORes[0] -> !Unit
      %w3 = idr.field %next : !IORes @MkIORes[1] -> !idr.world
      %again = idr.con !IORes @MkIORes(%u : !Unit, %w3 : !idr.world)
      idr.yield %again : !IORes
    }
    }
    return %r : !IORes
  }
  idr.func @Prog.main(%w: !idr.world) -> (!Unit, !idr.world) {
    %nl = arith.constant 10 : i32
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c7 = arith.constant 7 : i64
    %c10 = arith.constant 10 : i64
    %nil = idr.con !idr.box<!List> @Nil()
    %l3 = idr.con !idr.box<!List> @Cons(%c3 : i64, %nil : !idr.box<!List>)
    %l2 = idr.con !idr.box<!List> @Cons(%c2 : i64, %l3 : !idr.box<!List>)
    %l1 = idr.con !idr.box<!List> @Cons(%c1 : i64, %l2 : !idr.box<!List>)
    %u = idr.call @upto(%c0, %c10, %c0) : (i64, i64, i64) -> i64
    %w1 = idr.io.put_sint %u, %w : i64
    %w2 = idr.io.put_char %nl, %w1
    %k = idr.call @count(%c0, %c7) : (i64, i64) -> i64
    %w3 = idr.io.put_sint %k, %w2 : i64
    %w4 = idr.io.put_char %nl, %w3
    %s = idr.call @sum(%c0, %l1) : (i64, !idr.box<!List>) -> i64
    %w5 = idr.io.put_sint %s, %w4 : i64
    %w6 = idr.io.put_char %nl, %w5
    %w7 = idr.call @echo(%c3, %w6) : (i64, !idr.world) -> !idr.world
    %r = idr.call @traverse(%l1, %w7) : (!idr.box<!List>, !idr.world) -> !IORes
    %unit = idr.field %r : !IORes @MkIORes[0] -> !Unit
    %w8 = idr.field %r : !IORes @MkIORes[1] -> !idr.world
    %c5 = arith.constant 5 : i64
    %f = idr.call @until(%c0, %c10) : (i64, i64) -> i64
    %w9 = idr.io.put_sint %f, %w8 : i64
    %w10 = idr.io.put_char %nl, %w9
    %z = idr.call @until(%c5, %c2) : (i64, i64) -> i64
    %w11 = idr.io.put_sint %z, %w10 : i64
    %w12 = idr.io.put_char %nl, %w11
    return %unit, %w12 : !Unit, !idr.world
  }
}
