// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc,idr.func(idr-tail-loops)))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@count,constant-stack=@upto,constant-stack=@spin,constant-stack=@sum,constant-stack=@echo -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=counted-loop=@upto,counted-loop=@until -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=counted-loop=@count -o /dev/null 2> %t.count.err
// RUN: FileCheck %s --check-prefix=COUNT < %t.count.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@fib -o /dev/null 2> %t.fib.err
// RUN: FileCheck %s --check-prefix=FIB < %t.fib.err
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// RUN: %differential %t.mlir %t.reference.mlir
// RUN: sed 's/%w11 = idr.io.put_sint %end, %w10 : i64/%w11 = idr.io.put_sint %n, %w10 : i64/' %t.reference.mlir > %t.wrong.mlir
// RUN: not %differential %s %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// A self tail call in a region of a match whose results are returned
// becomes a loop, so the stack stays constant; a call that is not in tail
// position stays, and the stack grows with it. A loop that counts up to a
// bound becomes an scf.for, whether or not its result is the counter; one
// that counts down to zero keeps its test against zero, and is an
// scf.while.
// COUNT: error: expected counted-loop: {{.*}}@count
// FIB: error: expected constant-stack: {{.*}}@fib
//
// Each loop computes what its recursion does, on every bound: the program
// runs them on n, the byte read (the empty input reads as 255), and
// writes what @echo writes, from n down to 0, then the count, the sum of
// the squares below n, the sum of a list, fib (n mod 16), and where @until
// stops, the first multiple of 3 at or past n. The REFERENCE lines compute
// each in another way: the count down by a count up, the sums and the
// stop by their closed forms, fib by its table. The program means the same
// as written and after counting and idr-tail-loops, on 0 to 5, 15 to 17
// (around fib's period), 100, 254 and the empty input; @spin, which never
// returns, is called only for the byte 300, which no input is. A reference
// whose stop is n itself is told apart on 1.
// WRONG: differential: loops-tail-loop.mlir and {{.*}}wrong.mlir differ on '\0001'
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0005
// STDIN: \0017
// STDIN: \0020
// STDIN: \0021
// STDIN: \0144
// STDIN: \0376
// STDIN:
!List = !idr.data<"List">
#types = #idr.types<
  "List" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]
>
idr.program @"tail-loop" root(@Main.main) stage(first) types #types {
  idr.func @count(%acc: i64, %n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d0: i64) {
      %c1 = arith.constant 1 : i64
      %a = arith.addi %acc, %c1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = idr.call @count(%a, %m) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // upto i n acc = if i < n then upto (i + 1) n (acc + i * i) else acc
  idr.func @upto(%i: i64, %n: i64, %acc: i64) -> i64 attributes {total} {
    %lt = arith.cmpi slt, %i, %n : i64
    %b = arith.extui %lt : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d1: i64) {
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
    default(%d2: i64) {
      %c3 = arith.constant 3 : i64
      %j = arith.addi %i, %c3 : i64
      %x = idr.call @until(%j, %n) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // spin x = spin (x + 1)
  idr.func @spin(%x: i64) -> i64 {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    %r = idr.call @spin(%y) : (i64) -> i64
    return %r : i64
  }
  // sum acc (x :: xs) = sum (acc + x) xs
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
  // echo n = do printLn n; if n == 0 then pure () else echo (n - 1): what
  // the body computes before the decision, the world, goes round too.
  idr.func @echo(%n: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %w1 = idr.io.put_sint %n, %w : i64
    %r = idr.match_lit %n : i64 -> (!idr.world) {
    case 0 {
      idr.yield %w1 : !idr.world
    }
    default(%d3: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = idr.call @echo(%m, %w1) : (i64, !idr.world) -> !idr.world
      idr.yield %x : !idr.world
    }
    }
    return %r : !idr.world
  }
  idr.func @fib(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    case 1 {
      idr.yield %n : i64
    }
    default(%d4: i64) {
      %c1 = arith.constant 1 : i64
      %c2 = arith.constant 2 : i64
      %a = arith.subi %n, %c1 : i64
      %b = arith.subi %n, %c2 : i64
      %x = idr.call @fib(%a) : (i64) -> i64
      %y = idr.call @fib(%b) : (i64) -> i64
      %s = arith.addi %x, %y : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %byte, %w0 = idr.io.get_byte %w
    %n = arith.extui %byte : i32 to i64
    %nil = idr.con !idr.box<!List> @Nil()
    %c7 = arith.constant 7 : i64
    %xs = idr.con !idr.box<!List> @Cons(%c7 : i64, %nil : !idr.box<!List>)
    %c0 = arith.constant 0 : i64
    %c15 = arith.constant 15 : i64
    %small = arith.andi %n, %c15 : i64
    %a = idr.call @count(%c0, %n) : (i64, i64) -> i64
    %u = idr.call @upto(%c0, %n, %c0) : (i64, i64, i64) -> i64
    %b = idr.match_lit %n : i64 -> (i64) {
    case 300 {
      %v = idr.call @spin(%c0) : (i64) -> i64
      idr.yield %v : i64
    }
    default(%d5: i64) {
      idr.yield %c0 : i64
    }
    }
    %s = idr.call @sum(%b, %xs) : (i64, !idr.box<!List>) -> i64
    %w1 = idr.call @echo(%n, %w0) : (i64, !idr.world) -> !idr.world
    %c = idr.call @fib(%small) : (i64) -> i64
    %t = idr.call @until(%c0, %n) : (i64, i64) -> i64
    %sp = arith.constant 32 : i32
    %w2 = idr.io.put_char %sp, %w1
    %w3 = idr.io.put_sint %a, %w2 : i64
    %w4 = idr.io.put_char %sp, %w3
    %w5 = idr.io.put_sint %u, %w4 : i64
    %w6 = idr.io.put_char %sp, %w5
    %w7 = idr.io.put_sint %s, %w6 : i64
    %w8 = idr.io.put_char %sp, %w7
    %w9 = idr.io.put_sint %c, %w8 : i64
    %w10 = idr.io.put_char %sp, %w9
    %w11 = idr.io.put_sint %t, %w10 : i64
    return %w11 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@Main.main) stage(first) types #idr.types<> {
// REFERENCE:   idr.func @countup(%i: i64, %n: i64, %w: !idr.world) -> !idr.world attributes {total} {
// REFERENCE:     %gt = arith.cmpi sgt, %i, %n : i64
// REFERENCE:     %r = idr.match_lit %gt : i1 -> (!idr.world) {
// REFERENCE:     case true {
// REFERENCE:       idr.yield %w : !idr.world
// REFERENCE:     }
// REFERENCE:     default(%d: i1) {
// REFERENCE:       %v = arith.subi %n, %i : i64
// REFERENCE:       %w1 = idr.io.put_sint %v, %w : i64
// REFERENCE:       %c1 = arith.constant 1 : i64
// REFERENCE:       %j = arith.addi %i, %c1 : i64
// REFERENCE:       %x = idr.call @countup(%j, %n, %w1) : (i64, i64, !idr.world) -> !idr.world
// REFERENCE:       idr.yield %x : !idr.world
// REFERENCE:     }
// REFERENCE:     }
// REFERENCE:     return %r : !idr.world
// REFERENCE:   }
// REFERENCE:   idr.func @Main.main(%w: !idr.world) -> !idr.world {
// REFERENCE:     %c, %w0 = idr.io.get_byte %w
// REFERENCE:     %n = arith.extui %c : i32 to i64
// REFERENCE:     %c0 = arith.constant 0 : i64
// REFERENCE:     %c1 = arith.constant 1 : i64
// REFERENCE:     %c2 = arith.constant 2 : i64
// REFERENCE:     %c3 = arith.constant 3 : i64
// REFERENCE:     %c6 = arith.constant 6 : i64
// REFERENCE:     %c15 = arith.constant 15 : i64
// REFERENCE:     %w1 = idr.call @countup(%c0, %n, %w0) : (i64, i64, !idr.world) -> !idr.world
// REFERENCE:     %nm = arith.subi %n, %c1 : i64
// REFERENCE:     %n2 = arith.muli %n, %c2 : i64
// REFERENCE:     %n2m = arith.subi %n2, %c1 : i64
// REFERENCE:     %p1 = arith.muli %nm, %n : i64
// REFERENCE:     %p2 = arith.muli %p1, %n2m : i64
// REFERENCE:     %squares = arith.divsi %p2, %c6 : i64
// REFERENCE:     %up = arith.addi %n, %c2 : i64
// REFERENCE:     %steps = arith.divsi %up, %c3 : i64
// REFERENCE:     %end = arith.muli %steps, %c3 : i64
// REFERENCE:     %small = arith.andi %n, %c15 : i64
// REFERENCE:     %fib = idr.match_lit %small : i64 -> (i64) {
// REFERENCE:     case 0 {
// REFERENCE:       %f0 = arith.constant 0 : i64
// REFERENCE:       idr.yield %f0 : i64
// REFERENCE:     }
// REFERENCE:     case 1 {
// REFERENCE:       %f1 = arith.constant 1 : i64
// REFERENCE:       idr.yield %f1 : i64
// REFERENCE:     }
// REFERENCE:     case 2 {
// REFERENCE:       %f2 = arith.constant 1 : i64
// REFERENCE:       idr.yield %f2 : i64
// REFERENCE:     }
// REFERENCE:     case 3 {
// REFERENCE:       %f3 = arith.constant 2 : i64
// REFERENCE:       idr.yield %f3 : i64
// REFERENCE:     }
// REFERENCE:     case 4 {
// REFERENCE:       %f4 = arith.constant 3 : i64
// REFERENCE:       idr.yield %f4 : i64
// REFERENCE:     }
// REFERENCE:     case 5 {
// REFERENCE:       %f5 = arith.constant 5 : i64
// REFERENCE:       idr.yield %f5 : i64
// REFERENCE:     }
// REFERENCE:     case 6 {
// REFERENCE:       %f6 = arith.constant 8 : i64
// REFERENCE:       idr.yield %f6 : i64
// REFERENCE:     }
// REFERENCE:     case 7 {
// REFERENCE:       %f7 = arith.constant 13 : i64
// REFERENCE:       idr.yield %f7 : i64
// REFERENCE:     }
// REFERENCE:     case 8 {
// REFERENCE:       %f8 = arith.constant 21 : i64
// REFERENCE:       idr.yield %f8 : i64
// REFERENCE:     }
// REFERENCE:     case 9 {
// REFERENCE:       %f9 = arith.constant 34 : i64
// REFERENCE:       idr.yield %f9 : i64
// REFERENCE:     }
// REFERENCE:     case 10 {
// REFERENCE:       %f10 = arith.constant 55 : i64
// REFERENCE:       idr.yield %f10 : i64
// REFERENCE:     }
// REFERENCE:     case 11 {
// REFERENCE:       %f11 = arith.constant 89 : i64
// REFERENCE:       idr.yield %f11 : i64
// REFERENCE:     }
// REFERENCE:     case 12 {
// REFERENCE:       %f12 = arith.constant 144 : i64
// REFERENCE:       idr.yield %f12 : i64
// REFERENCE:     }
// REFERENCE:     case 13 {
// REFERENCE:       %f13 = arith.constant 233 : i64
// REFERENCE:       idr.yield %f13 : i64
// REFERENCE:     }
// REFERENCE:     case 14 {
// REFERENCE:       %f14 = arith.constant 377 : i64
// REFERENCE:       idr.yield %f14 : i64
// REFERENCE:     }
// REFERENCE:     default(%o: i64) {
// REFERENCE:       %f15 = arith.constant 610 : i64
// REFERENCE:       idr.yield %f15 : i64
// REFERENCE:     }
// REFERENCE:     }
// REFERENCE:     %seven = arith.constant 7 : i64
// REFERENCE:     %sp = arith.constant 32 : i32
// REFERENCE:     %w2 = idr.io.put_char %sp, %w1
// REFERENCE:     %w3 = idr.io.put_sint %n, %w2 : i64
// REFERENCE:     %w4 = idr.io.put_char %sp, %w3
// REFERENCE:     %w5 = idr.io.put_sint %squares, %w4 : i64
// REFERENCE:     %w6 = idr.io.put_char %sp, %w5
// REFERENCE:     %w7 = idr.io.put_sint %seven, %w6 : i64
// REFERENCE:     %w8 = idr.io.put_char %sp, %w7
// REFERENCE:     %w9 = idr.io.put_sint %fib, %w8 : i64
// REFERENCE:     %w10 = idr.io.put_char %sp, %w9
// REFERENCE:     %w11 = idr.io.put_sint %end, %w10 : i64
// REFERENCE:     return %w11 : !idr.world
// REFERENCE:   }
// REFERENCE: }
