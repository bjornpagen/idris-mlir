// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc,idr.func(idr-tail-loops),idr-narrow))' -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed 's/stage(first)/stage(higher)/' %s > %t.higher.mlir
// RUN: idris-mlir -c %t.higher.mlir -o %t.o
// RUN: %cc %t.o -o %t
// RUN: printf '\0000\n' | %t | FileCheck %s --match-full-lines --check-prefix=ZERO
// RUN: printf '\001301\n' | %t | FileCheck %s --match-full-lines --check-prefix=PAST
// RUN: printf '\3774611686018427387903\n' | %t | FileCheck %s --match-full-lines --check-prefix=SMALLEST
// RUN: printf '\0014611686018427387904\n' | %t | FileCheck %s --match-full-lines --check-prefix=LARGE
// RUN: printf '\00018446744073709551616\n' | %t | FileCheck %s --match-full-lines --check-prefix=HUGE
// RUN: printf '\000-7\n' | %t | FileCheck %s --match-full-lines --check-prefix=NEGATIVE
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=word-loop=@parity,word-loop=@drain -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc,idr.func(idr-tail-loops)),idr-expect{holds=word-loop=@parity})' -o /dev/null 2> %t.tagged.err
// RUN: FileCheck %s --check-prefix=TAGGED < %t.tagged.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=word-loop=@count -o /dev/null 2> %t.count.err
// RUN: FileCheck %s --check-prefix=COUNT < %t.count.err
// A loop whose natural only descends to zero is versioned: one test on
// entry that the natural is small, then a loop on words alone, with no tag
// test and no call on bigs in it, and the loop as it was for a natural
// that is not small. Before idr-narrow the loop computes on the natural. A
// sum that grows with every step is not proved small, and stays a big,
// with its fast path inline.
// The program reads a byte, n, for @parity and @count, and then a line, a
// natural m (an Integer clamped at 0), which @drain takes at most 300
// steps down: a loop that carries a word beside its natural, which ends
// however large m is, so both of its versions run. Each version means
// what the loop did: the narrowed program prints what the program as
// written does on each input below (%differential, whose two sides both
// pass through idr-narrow on their way down), and the program, compiled
// whole by idris-mlir (stage higher, which a program with no closure may
// say), prints what Nat says, n mod 2, 2n and m - 300 clamped at 0, at the
// edges of the versions: m below the 300 steps and past them, the largest
// small natural (2^62 - 1, the word versions), the smallest large one
// (2^62, the loop as it was), 2^64 and a negative m, each with n of 0, 1
// and 255 (the end of input reads as 255).
// ZERO: 0
// ZERO-NEXT: 0
// ZERO-NEXT: 0
// PAST: 1
// PAST-NEXT: 2
// PAST-NEXT: 1
// SMALLEST: 1
// SMALLEST-NEXT: 510
// SMALLEST-NEXT: 4611686018427387603
// LARGE: 1
// LARGE-NEXT: 2
// LARGE-NEXT: 4611686018427387604
// HUGE: 0
// HUGE-NEXT: 0
// HUGE-NEXT: 18446744073709551316
// NEGATIVE: 0
// NEGATIVE-NEXT: 0
// NEGATIVE-NEXT: 0
// TAGGED: error: expected word-loop: @parity computes on bigs in each of its loops
// COUNT: error: expected word-loop: @count computes on bigs in each of its loops
// STDIN:
// STDIN: \0000
// STDIN: \00000\n
// STDIN: \00011\n
// STDIN: \0001299\n
// STDIN: \0001300\n
// STDIN: \0377301\n
// STDIN: \00004611686018427387903\n
// STDIN: \00014611686018427387904\n
// STDIN: \03774611686018427387905\n
// STDIN: \000118446744073709551616\n
// STDIN: \0000-7\n
// STDIN: \0377-4611686018427387905\n
idr.program @descending root(@Main.main) stage(first) types #idr.types<> {
  idr.func @parity(%n: !idr.nat, %odd: i1) -> i1 attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (i1) {
    case #idr.big<0> {
      idr.yield %odd : i1
    }
    default(%d: !idr.nat) {
      %k = idr.big.pred %n
      %true = arith.constant true
      %flip = arith.xori %odd, %true : i1
      %s = idr.call @parity(%k, %flip) : (!idr.nat, i1) -> i1
      idr.yield %s : i1
    }
    }
    return %r : i1
  }
  idr.func @count(%n: !idr.nat, %acc: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %acc : !idr.nat
    }
    default(%d: !idr.nat) {
      %k = idr.big.pred %n
      %two = idr.constant !idr.nat #idr.big<2>
      %more = idr.big.add %acc, %two : !idr.nat
      %s = idr.call @count(%k, %more) : (!idr.nat, !idr.nat) -> !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  // What is left of %n after at most %steps predecessors.
  idr.func @drain(%n: !idr.nat, %steps: i64) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %n : !idr.nat
    }
    default(%d: !idr.nat) {
      %s = idr.match_lit %steps : i64 -> (!idr.nat) {
      case 0 {
        idr.yield %n : !idr.nat
      }
      default(%e: i64) {
        %k = idr.big.pred %n
        %one = arith.constant 1 : i64
        %fewer = arith.subi %steps, %one : i64
        %t = idr.call @drain(%k, %fewer) : (!idr.nat, i64) -> !idr.nat
        idr.yield %t : !idr.nat
      }
      }
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = idr.big.from_uint %c : i32 : !idr.nat
    %false = arith.constant false
    %p = idr.call @parity(%n, %false) : (!idr.nat, i1) -> i1
    %zero = idr.constant !idr.nat #idr.big<0>
    %k = idr.call @count(%n, %zero) : (!idr.nat, !idr.nat) -> !idr.nat
    %nl = arith.constant 10 : i32
    %pw = arith.extui %p : i1 to i64
    %w2 = idr.io.put_sint %pw, %w1 : i64
    %w3 = idr.io.put_char %nl, %w2
    %kb = idr.nat.to_big %k
    %t = idr.big.show %kb
    %w4 = idr.io.put_str %t, %w3
    %w5 = idr.io.put_char %nl, %w4
    %line, %w6 = idr.io.get_line %w5
    %i = idr.big.from_str %line
    %m = idr.nat.from_big %i
    %limit = arith.constant 300 : i64
    %left = idr.call @drain(%m, %limit) : (!idr.nat, i64) -> !idr.nat
    %lb = idr.nat.to_big %left
    %lt = idr.big.show %lb
    %w7 = idr.io.put_str %lt, %w6
    %w8 = idr.io.put_char %nl, %w7
    return %w8 : !idr.world
  }
}
