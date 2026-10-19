// RUN: idris-mlir-opt %s --idr-accumulate -o %t.acc.mlir
// RUN: idris-mlir-opt %s --idr-accumulate --mlir-disable-threading -o %t.acc.serial.mlir
// RUN: cmp %t.acc.mlir %t.acc.serial.mlir
// RUN: idris-mlir-opt %t.acc.mlir --idr-accumulate -o %t.again.mlir
// RUN: diff -q %t.acc.mlir %t.again.mlir
// RUN: idris-mlir-opt %t.acc.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@length,constant-stack=@steps,constant-stack=@count,constant-stack=@twos})' -o /dev/null
// RUN: idris-mlir-opt %t.acc.mlir '--idr-expect=holds=returns-argument=@down:0,returns-argument=@down_out:0,calls-only=@down:[],calls-only=@down_out:[],calls-only=@as_integer:[],straight-line=@as_integer' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.acc.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@both})' -o /dev/null 2> %t.both.err
// RUN: FileCheck %s --check-prefix=BOTH < %t.both.err
// RUN: %status 1 idris-mlir-opt %t.acc.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@depth})' -o /dev/null 2> %t.depth.err
// RUN: FileCheck %s --check-prefix=DEPTH < %t.depth.err
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// RUN: %differential %t.acc.mlir %t.reference.mlir
// RUN: sed 's/%double = arith.muli %n, %c2 : i64/%double = arith.muli %n, %n : i64/' %t.reference.mlir > %t.wrong.mlir
// RUN: not %differential %s %t.wrong.mlir 2>&1 | FileCheck %s --check-prefix=WRONG
// A tail that adds its own result carries the sum. @length adds one,
// @steps adds an argument: each calls a clone with zero and the clone adds
// before the call, which idr-tail-loops makes a loop. @count already adds
// before its call, so it is left to that pass. @both adds two self calls,
// and @depth inspects its result: neither carries a sum, and the stack
// grows with the call.
// A countdown that adds one from zero is the argument, the sum of that
// many ones. Adding two is the accumulator clone, not the argument.
// The same countdown after simplification has lifted the constants out of
// the branches. A sum of big ones is the argument as an Integer.
//
// Each sum is the one the recursion computes: the program runs each
// function on n = d * 10^e, for the input's two digits d and e, and on a
// list of n elements, and writes what each returns; the REFERENCE lines
// write the sums themselves: n, 3n, n + 5, n, 2n, n, n, and 0 for @depth
// and @both (on n mod 8, since @both calls itself twice). The program
// means the same as written and after idr-accumulate, on n = 0, 1, 2, 7
// and a million (@depth, which grows the stack, on n mod 8). A reference
// whose @twos is n * n is told apart on n = 1.
// WRONG: differential: loops-accumulate.mlir and {{.*}}wrong.mlir differ on '10'
// STDIN: 00
// STDIN: 10
// STDIN: 20
// STDIN: 70
// STDIN: 16
// BOTH: expected constant-stack: {{.*}}@both
// DEPTH: expected constant-stack: {{.*}}@depth
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @accumulate root(@root) stage(first) {

  idr.func @length(%xs: !idr.box<!List>) -> !idr.nat attributes {total} {
    %one = idr.constant !idr.nat #idr.big<1>
    %zero = idr.constant !idr.nat #idr.big<0>
    %r = idr.match %xs : !idr.box<!List> -> (!idr.nat) {
    case @Nil() {
      idr.yield %zero : !idr.nat
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %n = idr.call @length(%rest) : (!idr.box<!List>) -> !idr.nat
      %s = idr.big.add %n, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @steps(%k: !idr.nat, %n: !idr.nat) -> !idr.nat attributes {total} {
    %zero = idr.constant !idr.nat #idr.big<0>
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %zero : !idr.nat
    }
    default(%d0: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @steps(%k, %p) : (!idr.nat, !idr.nat) -> !idr.nat
      %s = idr.big.add %c, %k : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @count(%n: !idr.nat, %acc: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %acc : !idr.nat
    }
    default(%d1: !idr.nat) {
      %p = idr.big.pred %n
      %one = idr.constant !idr.nat #idr.big<1>
      %more = idr.big.add %acc, %one : !idr.nat
      %s = idr.call @count(%p, %more) : (!idr.nat, !idr.nat) -> !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @both(%n: !idr.nat) -> !idr.nat attributes {total} {
    %zero = idr.constant !idr.nat #idr.big<0>
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %zero : !idr.nat
    }
    default(%d2: !idr.nat) {
      %p = idr.big.pred %n
      %a = idr.call @both(%p) : (!idr.nat) -> !idr.nat
      %b = idr.call @both(%p) : (!idr.nat) -> !idr.nat
      %s = idr.big.add %a, %b : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @depth(%xs: !idr.box<!List>) -> !idr.nat attributes {total} {
    %zero = idr.constant !idr.nat #idr.big<0>
    %one = idr.constant !idr.nat #idr.big<1>
    %r = idr.match %xs : !idr.box<!List> -> (!idr.nat) {
    case @Nil() {
      idr.yield %zero : !idr.nat
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %n = idr.call @depth(%rest) : (!idr.box<!List>) -> !idr.nat
      %s = idr.match_lit %n : !idr.nat -> (!idr.nat) {
      case #idr.big<0> {
        idr.yield %zero : !idr.nat
      }
      default(%d3: !idr.nat) {
        idr.yield %one : !idr.nat
      }
      }
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @down(%n: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      %zero = idr.constant !idr.nat #idr.big<0>
      idr.yield %zero : !idr.nat
    }
    default(%d4: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @down(%p) : (!idr.nat) -> !idr.nat
      %one = idr.constant !idr.nat #idr.big<1>
      %s = idr.big.add %c, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @twos(%n: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      %zero = idr.constant !idr.nat #idr.big<0>
      idr.yield %zero : !idr.nat
    }
    default(%d5: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @twos(%p) : (!idr.nat) -> !idr.nat
      %two = idr.constant !idr.nat #idr.big<2>
      %s = idr.big.add %c, %two : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @down_out(%n: !idr.nat) -> !idr.nat attributes {total} {
    %one = idr.constant !idr.nat #idr.big<1>
    %zero = idr.constant !idr.nat #idr.big<0>
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %zero : !idr.nat
    }
    default(%d6: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @down_out(%p) : (!idr.nat) -> !idr.nat
      %s = idr.big.add %c, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @as_integer(%n: !idr.nat) -> !idr.big attributes {total} {
    %one = idr.constant !idr.big #idr.big<1>
    %zero = idr.constant !idr.big #idr.big<0>
    %r = idr.match_lit %n : !idr.nat -> (!idr.big) {
    case #idr.big<0> {
      idr.yield %zero : !idr.big
    }
    default(%d7: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @as_integer(%p) : (!idr.nat) -> !idr.big
      %s = idr.big.add %c, %one : !idr.big
      idr.yield %s : !idr.big
    }
    }
    return %r : !idr.big
  }
  // A list of n elements, built by a loop.
  idr.func @build(%n: i64, %acc: !idr.box<!List>) -> !idr.box<!List> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.box<!List>) {
    case 0 {
      idr.yield %acc : !idr.box<!List>
    }
    default(%d8: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %l = idr.con !idr.box<!List> @Cons(%n : i64, %acc : !idr.box<!List>)
      %x = idr.call @build(%m, %l) : (i64, !idr.box<!List>) -> !idr.box<!List>
      idr.yield %x : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func @pow10(%e: i64, %acc: i64) -> i64 attributes {total} {
    %r = idr.match_lit %e : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d9: i64) {
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
  idr.func @word(%n: !idr.nat) -> i64 {
    %b = idr.nat.to_big %n
    %w = idr.big.to_int %b : i64
    return %w : i64
  }
  // The program: each function on n = d * 10^e and on a list of n
  // elements; @depth and @both on n mod 8.
  idr.func @root(%w: !idr.world) -> !idr.world {
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
    %small = arith.andi %n, %seven : i64
    %nil = idr.con !idr.box<!List> @Nil()
    %list = idr.call @build(%n, %nil) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %short = idr.call @build(%small, %nil) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %nb = idr.big.from_sint %n : i64
    %nn = idr.nat.from_big %nb
    %sb = idr.big.from_sint %small : i64
    %sn = idr.nat.from_big %sb
    %three = idr.constant !idr.nat #idr.big<3>
    %five = idr.constant !idr.nat #idr.big<5>
    %r1 = idr.call @length(%list) : (!idr.box<!List>) -> !idr.nat
    %r2 = idr.call @steps(%three, %nn) : (!idr.nat, !idr.nat) -> !idr.nat
    %r3 = idr.call @count(%nn, %five) : (!idr.nat, !idr.nat) -> !idr.nat
    %r4 = idr.call @down(%nn) : (!idr.nat) -> !idr.nat
    %r5 = idr.call @twos(%nn) : (!idr.nat) -> !idr.nat
    %r6 = idr.call @down_out(%nn) : (!idr.nat) -> !idr.nat
    %r7b = idr.call @as_integer(%nn) : (!idr.nat) -> !idr.big
    %r8 = idr.call @depth(%short) : (!idr.box<!List>) -> !idr.nat
    %r9 = idr.call @both(%sn) : (!idr.nat) -> !idr.nat
    %x1 = idr.call @word(%r1) : (!idr.nat) -> i64
    %x2 = idr.call @word(%r2) : (!idr.nat) -> i64
    %x3 = idr.call @word(%r3) : (!idr.nat) -> i64
    %x4 = idr.call @word(%r4) : (!idr.nat) -> i64
    %x5 = idr.call @word(%r5) : (!idr.nat) -> i64
    %x6 = idr.call @word(%r6) : (!idr.nat) -> i64
    %x7 = idr.big.to_int %r7b : i64
    %x8 = idr.call @word(%r8) : (!idr.nat) -> i64
    %x9 = idr.call @word(%r9) : (!idr.nat) -> i64
    %sp = arith.constant 32 : i32
    %v1 = idr.io.put_sint %x1, %w2 : i64
    %v2 = idr.io.put_char %sp, %v1
    %v3 = idr.io.put_sint %x2, %v2 : i64
    %v4 = idr.io.put_char %sp, %v3
    %v5 = idr.io.put_sint %x3, %v4 : i64
    %v6 = idr.io.put_char %sp, %v5
    %v7 = idr.io.put_sint %x4, %v6 : i64
    %v8 = idr.io.put_char %sp, %v7
    %v9 = idr.io.put_sint %x5, %v8 : i64
    %v10 = idr.io.put_char %sp, %v9
    %v11 = idr.io.put_sint %x6, %v10 : i64
    %v12 = idr.io.put_char %sp, %v11
    %v13 = idr.io.put_sint %x7, %v12 : i64
    %v14 = idr.io.put_char %sp, %v13
    %v15 = idr.io.put_sint %x8, %v14 : i64
    %v16 = idr.io.put_char %sp, %v15
    %v17 = idr.io.put_sint %x9, %v16 : i64
    return %v17 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@root) stage(first) {
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
// REFERENCE:   idr.func @root(%w: !idr.world) -> !idr.world {
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
// REFERENCE:     %c2 = arith.constant 2 : i64
// REFERENCE:     %three = arith.constant 3 : i64
// REFERENCE:     %five = arith.constant 5 : i64
// REFERENCE:     %zero = arith.constant 0 : i64
// REFERENCE:     %thrice = arith.muli %n, %three : i64
// REFERENCE:     %plus = arith.addi %n, %five : i64
// REFERENCE:     %double = arith.muli %n, %c2 : i64
// REFERENCE:     %sp = arith.constant 32 : i32
// REFERENCE:     %v1 = idr.io.put_sint %n, %w2 : i64
// REFERENCE:     %v2 = idr.io.put_char %sp, %v1
// REFERENCE:     %v3 = idr.io.put_sint %thrice, %v2 : i64
// REFERENCE:     %v4 = idr.io.put_char %sp, %v3
// REFERENCE:     %v5 = idr.io.put_sint %plus, %v4 : i64
// REFERENCE:     %v6 = idr.io.put_char %sp, %v5
// REFERENCE:     %v7 = idr.io.put_sint %n, %v6 : i64
// REFERENCE:     %v8 = idr.io.put_char %sp, %v7
// REFERENCE:     %v9 = idr.io.put_sint %double, %v8 : i64
// REFERENCE:     %v10 = idr.io.put_char %sp, %v9
// REFERENCE:     %v11 = idr.io.put_sint %n, %v10 : i64
// REFERENCE:     %v12 = idr.io.put_char %sp, %v11
// REFERENCE:     %v13 = idr.io.put_sint %n, %v12 : i64
// REFERENCE:     %v14 = idr.io.put_char %sp, %v13
// REFERENCE:     %v15 = idr.io.put_sint %zero, %v14 : i64
// REFERENCE:     %v16 = idr.io.put_char %sp, %v15
// REFERENCE:     %v17 = idr.io.put_sint %zero, %v16 : i64
// REFERENCE:     return %v17 : !idr.world
// REFERENCE:   }
// REFERENCE: }
