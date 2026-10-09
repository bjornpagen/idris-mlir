// RUN: idris-mlir -c %s -o %t.o --no-eval
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
module attributes {idr.program} {
  idr.data @Unit {
    idr.ctor @MkUnit ()
  }
  idr.data @IORes {
    idr.ctor @MkIORes (!idr.data<@Unit>, !idr.world)
  }
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  func.func private @upto(%i: i64, %n: i64, %acc: i64) -> i64 attributes {idr.total} {
    %lt = arith.cmpi slt, %i, %n : i64
    %b = arith.extui %lt : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %j = arith.addi %i, %c1 : i64
      %sq = arith.muli %i, %i : i64
      %a = arith.addi %acc, %sq : i64
      %x = func.call @upto(%j, %n, %a) : (i64, i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // until i n = if i < n then until (i + 3) n else i
  func.func private @until(%i: i64, %n: i64) -> i64 attributes {idr.total} {
    %lt = arith.cmpi slt, %i, %n : i64
    %b = arith.extui %lt : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      idr.yield %i : i64
    }
    default {
      %c3 = arith.constant 3 : i64
      %j = arith.addi %i, %c3 : i64
      %x = func.call @until(%j, %n) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @count(%acc: i64, %n: i64) -> i64 attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %a = arith.addi %acc, %c1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = func.call @count(%a, %m) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @sum(%acc: i64, %xs: !idr.box<@List>) -> i64 attributes {idr.total} {
    %r = idr.match %xs : !idr.box<@List> -> (i64) {
    case @Nil() {
      idr.yield %acc : i64
    }
    case @Cons(%x: i64, %rest: !idr.box<@List>) {
      %a = arith.addi %acc, %x : i64
      %s = func.call @sum(%a, %rest) : (i64, !idr.box<@List>) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func private @echo(%n: i64, %w: !idr.world) -> !idr.world attributes {idr.total} {
    %nl = arith.constant 10 : i32
    %w1 = idr.io.put_int signed %n, %w : i64
    %w2 = idr.io.put_char %nl, %w1
    %r = idr.match_lit %n : i64 -> (!idr.world) {
    case 0 {
      idr.yield %w2 : !idr.world
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = func.call @echo(%m, %w2) : (i64, !idr.world) -> !idr.world
      idr.yield %x : !idr.world
    }
    }
    return %r : !idr.world
  }
  func.func private @traverse(%xs: !idr.box<@List>, %w: !idr.world) -> !idr.data<@IORes> attributes {idr.total} {
    %unit = idr.constant #idr.con<@Unit::@MkUnit, []> : !idr.data<@Unit>
    %nl = arith.constant 10 : i32
    %r = idr.match %xs : !idr.box<@List> -> (!idr.data<@IORes>) {
    case @Nil() {
      %done = idr.con @IORes::@MkIORes(%unit, %w) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
      idr.yield %done : !idr.data<@IORes>
    }
    case @Cons(%x: i64, %rest: !idr.box<@List>) {
      %w1 = idr.io.put_int signed %x, %w : i64
      %w2 = idr.io.put_char %nl, %w1
      %next = func.call @traverse(%rest, %w2) : (!idr.box<@List>, !idr.world) -> !idr.data<@IORes>
      %u = idr.field %next[@MkIORes, 0] : !idr.data<@IORes> -> !idr.data<@Unit>
      %w3 = idr.field %next[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
      %again = idr.con @IORes::@MkIORes(%u, %w3) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
      idr.yield %again : !idr.data<@IORes>
    }
    }
    return %r : !idr.data<@IORes>
  }
  func.func @Prog.main(%w: !idr.world) -> (!idr.data<@Unit>, !idr.world) {
    %nl = arith.constant 10 : i32
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c7 = arith.constant 7 : i64
    %c10 = arith.constant 10 : i64
    %nil = idr.con @List::@Nil() : () -> !idr.box<@List>
    %l3 = idr.con @List::@Cons(%c3, %nil) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %l2 = idr.con @List::@Cons(%c2, %l3) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %l1 = idr.con @List::@Cons(%c1, %l2) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %u = func.call @upto(%c0, %c10, %c0) : (i64, i64, i64) -> i64
    %w1 = idr.io.put_int signed %u, %w : i64
    %w2 = idr.io.put_char %nl, %w1
    %k = func.call @count(%c0, %c7) : (i64, i64) -> i64
    %w3 = idr.io.put_int signed %k, %w2 : i64
    %w4 = idr.io.put_char %nl, %w3
    %s = func.call @sum(%c0, %l1) : (i64, !idr.box<@List>) -> i64
    %w5 = idr.io.put_int signed %s, %w4 : i64
    %w6 = idr.io.put_char %nl, %w5
    %w7 = func.call @echo(%c3, %w6) : (i64, !idr.world) -> !idr.world
    %r = func.call @traverse(%l1, %w7) : (!idr.box<@List>, !idr.world) -> !idr.data<@IORes>
    %unit = idr.field %r[@MkIORes, 0] : !idr.data<@IORes> -> !idr.data<@Unit>
    %w8 = idr.field %r[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
    %c5 = arith.constant 5 : i64
    %f = func.call @until(%c0, %c10) : (i64, i64) -> i64
    %w9 = idr.io.put_int signed %f, %w8 : i64
    %w10 = idr.io.put_char %nl, %w9
    %z = func.call @until(%c5, %c2) : (i64, i64) -> i64
    %w11 = idr.io.put_int signed %z, %w10 : i64
    %w12 = idr.io.put_char %nl, %w11
    return %unit, %w12 : !idr.data<@Unit>, !idr.world
  }
}
