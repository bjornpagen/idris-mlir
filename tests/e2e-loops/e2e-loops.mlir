// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: echo -n 00 | %t | FileCheck %s --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n 10 | %t | tail -n 1 | FileCheck %s --check-prefix=ONE --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n 20 | %t | tail -n 1 | FileCheck %s --check-prefix=TWO --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n 30 | %t | tail -n 1 | FileCheck %s --check-prefix=THREE --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n 40 | %t | tail -n 1 | FileCheck %s --check-prefix=FOUR --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n 16 | %t | tail -n 1 | FileCheck %s --check-prefix=MILLION --match-full-lines --implicit-check-not={{.}}
// Loops of every shape idr-tail-loops makes run as the recursion they
// replace: a count up to a bound (an scf.for), a count down to zero, a
// fold over a list, output before the decision, an IO fold whose
// result is its recursive call's rebuilt (record eta), and a count up to a
// bound that returns its counter (an scf.for whose counter ends past the
// bound by part of a step, or at its start when it never runs).
//
// The last line runs the three counting loops to a bound read at run
// time, d * 10^e for the input's two digits d and e: 0, where no loop
// runs; 1, 2, 3 and 4, where the counter that steps by 3 ends past the
// bound by 2, by 1, at it, and by 2 again after a second step; and a
// million, which only a loop runs on the stack: the sum of the squares
// below the bound, the count, and the counter. The lines before it do not
// read the input, and are checked on the first run alone.
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
// CHECK-NEXT: 0 0 0
// ONE: 0 1 3
// TWO: 1 2 3
// THREE: 5 3 3
// FOUR: 14 4 6
// MILLION: 333332833333500000 1000000 1000002
!Unit = !idr.data<"Unit">
!IORes = !idr.data<"IORes">
!List = !idr.data<"List">
#types = #idr.types<
  "IORes" = plain [@MkIORes(!Unit, !idr.world)],
  "List" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons],
  "Unit" = plain [@MkUnit()]
>
idr.program @loops root(@Prog.main) stage(higher) types #types {
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
  idr.func @pow10(%e: i64, %acc: i64) -> i64 attributes {total} {
    %r = idr.match_lit %e : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %c10 = arith.constant 10 : i64
      %f = arith.subi %e, %c1 : i64
      %a = arith.muli %acc, %c10 : i64
      %x = idr.call @pow10(%f, %a) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
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
    %digit, %w13 = idr.io.get_byte %w12
    %places, %w14 = idr.io.get_byte %w13
    %c48 = arith.constant 48 : i32
    %dv = arith.subi %digit, %c48 : i32
    %ev = arith.subi %places, %c48 : i32
    %d = arith.extsi %dv : i32 to i64
    %e = arith.extsi %ev : i32 to i64
    %p = idr.call @pow10(%e, %c1) : (i64, i64) -> i64
    %n = arith.muli %d, %p : i64
    %sp = arith.constant 32 : i32
    %un = idr.call @upto(%c0, %n, %c0) : (i64, i64, i64) -> i64
    %w15 = idr.io.put_sint %un, %w14 : i64
    %w16 = idr.io.put_char %sp, %w15
    %kn = idr.call @count(%c0, %n) : (i64, i64) -> i64
    %w17 = idr.io.put_sint %kn, %w16 : i64
    %w18 = idr.io.put_char %sp, %w17
    %fn = idr.call @until(%c0, %n) : (i64, i64) -> i64
    %w19 = idr.io.put_sint %fn, %w18 : i64
    %w20 = idr.io.put_char %nl, %w19
    return %unit, %w20 : !Unit, !idr.world
  }
}
