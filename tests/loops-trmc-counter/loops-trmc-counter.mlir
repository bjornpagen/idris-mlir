// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc,idr-trmc,idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@replicate,constant-stack=@take})' -o %t.loops.mlir
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// RUN: %differential %t.loops.mlir %t.reference.mlir
// Data.List's replicate and take: a constructor around a call of the
// function itself on the predecessor of a natural, which the function then
// no longer needs. Were the parameter borrowed, the predecessor would be
// dropped after the call, between the call and the constructor, where
// idr-trmc moves no call past. Borrow inference counts such a call as the
// tail call idr-trmc makes it, and the parameter is owned: both functions
// become loops that write each cell to the destination they got.
//
// The loops make the lists the recursion does: the program replicates 7
// n times, for n = d * 10^e of the input's two digits, and writes the sum
// and the length of the list, of the first n + 1 of it (all of it), and of
// the first n / 2; the REFERENCE lines, after the module, write 7n, n,
// 7n, n, 7(n / 2) and n / 2. The program means the same as written and
// after the loops are made, for n = 0, 1, 2, 3 and a million.
// STDIN: 00
// STDIN: 10
// STDIN: 20
// STDIN: 30
// STDIN: 16
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @"trmc-counter" root(@Prog.main) stage(first) {
  idr.func @replicate(%n: !idr.nat, %x: i64) -> !idr.box<!List> {
    %nil = idr.constant !idr.box<!List> #idr.con<!List, @Nil, []>
    %r = idr.match_lit %n : !idr.nat -> (!idr.box<!List>) {
    case #idr.big<0> {
      idr.yield %nil : !idr.box<!List>
    }
    default(%d0: !idr.nat) {
      %m = idr.big.pred %n
      %t = idr.call @replicate(%m, %x) : (!idr.nat, i64) -> !idr.box<!List>
      %c = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
      idr.yield %c : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func @take(%n: !idr.nat, %l: !idr.box<!List>) -> !idr.box<!List> {
    %nil = idr.constant !idr.box<!List> #idr.con<!List, @Nil, []>
    %r = idr.match_lit %n : !idr.nat -> (!idr.box<!List>) {
    case #idr.big<0> {
      idr.yield %nil : !idr.box<!List>
    }
    default(%d1: !idr.nat) {
      %m = idr.big.pred %n
      %s = idr.match %l : !idr.box<!List> -> (!idr.box<!List>) {
      case @Cons(%h: i64, %rest: !idr.box<!List>) {
        %t = idr.call @take(%m, %rest) : (!idr.nat, !idr.box<!List>) -> !idr.box<!List>
        %c = idr.con !idr.box<!List> @Cons(%h : i64, %t : !idr.box<!List>)
        idr.yield %c : !idr.box<!List>
      }
      default(%d2: !idr.box<!List>) {
        idr.yield %nil : !idr.box<!List>
      }
      }
      idr.yield %s : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func @pow10(%e: i64, %acc: i64) -> i64 attributes {total} {
    %r = idr.match_lit %e : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %ten = arith.constant 10 : i64
      %f = arith.subi %e, %one : i64
      %a = arith.muli %acc, %ten : i64
      %x = idr.call @pow10(%f, %a) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // The sum and the length of a list, by a loop.
  idr.func @stats(%l: !idr.box<!List>, %acc: i64, %len: i64) -> (i64, i64) attributes {total} {
    %r:2 = idr.match %l : !idr.box<!List> -> (i64, i64) {
    case @Cons(%h: i64, %rest: !idr.box<!List>) {
      %a = arith.addi %acc, %h : i64
      %one = arith.constant 1 : i64
      %m = arith.addi %len, %one : i64
      %s:2 = idr.call @stats(%rest, %a, %m) : (!idr.box<!List>, i64, i64) -> (i64, i64)
      idr.yield %s#0, %s#1 : i64, i64
    }
    default(%d4: !idr.box<!List>) {
      idr.yield %acc, %len : i64, i64
    }
    }
    return %r#0, %r#1 : i64, i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %dc, %w1 = idr.io.get_byte %w
    %ec, %w2 = idr.io.get_byte %w1
    %c48 = arith.constant 48 : i32
    %dv = arith.subi %dc, %c48 : i32
    %ev = arith.subi %ec, %c48 : i32
    %d = arith.extsi %dv : i32 to i64
    %e = arith.extsi %ev : i32 to i64
    %one = arith.constant 1 : i64
    %p = idr.call @pow10(%e, %one) : (i64, i64) -> i64
    %n = arith.muli %d, %p : i64
    %seven = arith.constant 7 : i64
    %zero = arith.constant 0 : i64
    %c2 = arith.constant 2 : i64
    %nb = idr.big.from_sint %n : i64
    %nn = idr.nat.from_big %nb
    %more = arith.addi %n, %one : i64
    %mb = idr.big.from_sint %more : i64
    %mn = idr.nat.from_big %mb
    %half = arith.divsi %n, %c2 : i64
    %hb = idr.big.from_sint %half : i64
    %hn = idr.nat.from_big %hb
    %l = idr.call @replicate(%nn, %seven) : (!idr.nat, i64) -> !idr.box<!List>
    %a:2 = idr.call @stats(%l, %zero, %zero) : (!idr.box<!List>, i64, i64) -> (i64, i64)
    %t = idr.call @take(%mn, %l) : (!idr.nat, !idr.box<!List>) -> !idr.box<!List>
    %b:2 = idr.call @stats(%t, %zero, %zero) : (!idr.box<!List>, i64, i64) -> (i64, i64)
    %u = idr.call @take(%hn, %l) : (!idr.nat, !idr.box<!List>) -> !idr.box<!List>
    %c:2 = idr.call @stats(%u, %zero, %zero) : (!idr.box<!List>, i64, i64) -> (i64, i64)
    %sp = arith.constant 32 : i32
    %v1 = idr.io.put_sint %a#0, %w2 : i64
    %v2 = idr.io.put_char %sp, %v1
    %v3 = idr.io.put_sint %a#1, %v2 : i64
    %v4 = idr.io.put_char %sp, %v3
    %v5 = idr.io.put_sint %b#0, %v4 : i64
    %v6 = idr.io.put_char %sp, %v5
    %v7 = idr.io.put_sint %b#1, %v6 : i64
    %v8 = idr.io.put_char %sp, %v7
    %v9 = idr.io.put_sint %c#0, %v8 : i64
    %v10 = idr.io.put_char %sp, %v9
    %v11 = idr.io.put_sint %c#1, %v10 : i64
    return %v11 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@Prog.main) stage(first) {
// REFERENCE:   idr.func @pow10(%e: i64, %acc: i64) -> i64 attributes {total} {
// REFERENCE:     %r = idr.match_lit %e : i64 -> (i64) {
// REFERENCE:     case 0 {
// REFERENCE:       idr.yield %acc : i64
// REFERENCE:     }
// REFERENCE:     default(%d: i64) {
// REFERENCE:       %one = arith.constant 1 : i64
// REFERENCE:       %ten = arith.constant 10 : i64
// REFERENCE:       %f = arith.subi %e, %one : i64
// REFERENCE:       %a = arith.muli %acc, %ten : i64
// REFERENCE:       %x = idr.call @pow10(%f, %a) : (i64, i64) -> i64
// REFERENCE:       idr.yield %x : i64
// REFERENCE:     }
// REFERENCE:     }
// REFERENCE:     return %r : i64
// REFERENCE:   }
// REFERENCE:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REFERENCE:     %dc, %w1 = idr.io.get_byte %w
// REFERENCE:     %ec, %w2 = idr.io.get_byte %w1
// REFERENCE:     %c48 = arith.constant 48 : i32
// REFERENCE:     %dv = arith.subi %dc, %c48 : i32
// REFERENCE:     %ev = arith.subi %ec, %c48 : i32
// REFERENCE:     %d = arith.extsi %dv : i32 to i64
// REFERENCE:     %e = arith.extsi %ev : i32 to i64
// REFERENCE:     %one = arith.constant 1 : i64
// REFERENCE:     %p = idr.call @pow10(%e, %one) : (i64, i64) -> i64
// REFERENCE:     %n = arith.muli %d, %p : i64
// REFERENCE:     %seven = arith.constant 7 : i64
// REFERENCE:     %c2 = arith.constant 2 : i64
// REFERENCE:     %all = arith.muli %n, %seven : i64
// REFERENCE:     %half = arith.divsi %n, %c2 : i64
// REFERENCE:     %part = arith.muli %half, %seven : i64
// REFERENCE:     %sp = arith.constant 32 : i32
// REFERENCE:     %v1 = idr.io.put_sint %all, %w2 : i64
// REFERENCE:     %v2 = idr.io.put_char %sp, %v1
// REFERENCE:     %v3 = idr.io.put_sint %n, %v2 : i64
// REFERENCE:     %v4 = idr.io.put_char %sp, %v3
// REFERENCE:     %v5 = idr.io.put_sint %all, %v4 : i64
// REFERENCE:     %v6 = idr.io.put_char %sp, %v5
// REFERENCE:     %v7 = idr.io.put_sint %n, %v6 : i64
// REFERENCE:     %v8 = idr.io.put_char %sp, %v7
// REFERENCE:     %v9 = idr.io.put_sint %part, %v8 : i64
// REFERENCE:     %v10 = idr.io.put_char %sp, %v9
// REFERENCE:     %v11 = idr.io.put_sint %half, %v10 : i64
// REFERENCE:     return %v11 : !idr.world
// REFERENCE:   }
// REFERENCE: }

