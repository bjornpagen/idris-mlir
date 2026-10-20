// RUN: awk '/^ *\/\/ CHAIN$/ { for (i = 1; i <= 70; i++) printf "      %%k%d = idr.big.pred %%k%d\n", i, i - 1; next } { print }' %s > %t.chain.mlir
// RUN: idris-mlir-opt %t.chain.mlir --pass-pipeline='builtin.module(idr.program(idr-rc,idr.func(idr-tail-loops),idr-narrow))' -o %t.mlir
// RUN: %differential %t.chain.mlir %t.mlir
// RUN: sed 's/stage(first)/stage(higher)/' %t.chain.mlir > %t.higher.mlir
// RUN: idris-mlir -c %t.higher.mlir -o %t.o
// RUN: %cc %t.o -o %t
// RUN: printf '\000' | %t | FileCheck %s --match-full-lines --check-prefix=N0
// RUN: printf '\001' | %t | FileCheck %s --match-full-lines --check-prefix=N1
// RUN: printf '\107' | %t | FileCheck %s --match-full-lines --check-prefix=N71
// RUN: printf '\110' | %t | FileCheck %s --match-full-lines --check-prefix=N72
// RUN: printf '\216' | %t | FileCheck %s --match-full-lines --check-prefix=N142
// RUN: printf '\217' | %t | FileCheck %s --match-full-lines --check-prefix=N143
// RUN: %t < /dev/null | FileCheck %s --match-full-lines --check-prefix=N255
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=word-loop=@deep,word-loop=@carried -o /dev/null
// A loop whose natural only descends to zero is versioned however far it
// descends in one trip: the first RUN line writes, where the CHAIN line
// stands, 70 predecessors of the natural one after another, and the
// descent is read back through each of them, every value asked once (a
// predecessor is of a natural that is not zero, so a trip takes 71 only
// from a natural of 71 or more, and a smaller one ends in one last
// trip). And a loop that carries a word beside its natural is versioned
// too: only a value that holds a reference can be passed borrowed out of
// a loop, and a word holds none.
// The versions compute what the loops did: on every one-byte input the
// narrowed program prints what the chain as written does (%differential,
// whose two sides both pass through idr-narrow on their way down), and
// the chain, compiled whole by idris-mlir (stage higher, which a program
// with no closure may say), prints the parity of the trips @deep makes,
// 71 steps each, then n: the edges of one trip and of two (n of 0, 1, 71,
// 72, 142 and 143) and the end of input, which reads as 255.
// A natural past the small range takes the loop as it was, but none
// descends from 2^62 to zero in a test's time: narrow-descending's @drain,
// which a word bounds, runs both versions.
// N0: 00
// N1: 11
// N71: 171
// N72: 072
// N142: 0142
// N143: 1143
// N255: 0255
idr.program @versioned root(@Main.main) stage(first) types #idr.types<> {
  idr.func @deep(%n: !idr.nat, %odd: i1) -> i1 attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (i1) {
    case #idr.big<0> {
      idr.yield %odd : i1
    }
    default(%d: !idr.nat) {
      %true = arith.constant true
      %flip = arith.xori %odd, %true : i1
      %trip = idr.constant !idr.nat #idr.big<71>
      %last = idr.big.cmp lt %n, %trip : !idr.nat
      %s = idr.match_lit %last : i1 -> (i1) {
      case 1 {
        idr.yield %flip : i1
      }
      default(%e: i1) {
        %k0 = idr.big.pred %n
        // CHAIN
        %t = idr.call @deep(%k70, %flip) : (!idr.nat, i1) -> i1
        idr.yield %t : i1
      }
      }
      idr.yield %s : i1
    }
    }
    return %r : i1
  }
  idr.func @carried(%n: !idr.nat, %step: i64, %acc: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (i64) {
    case #idr.big<0> {
      idr.yield %acc : i64
    }
    default(%d: !idr.nat) {
      %k = idr.big.pred %n
      %more = arith.addi %acc, %step : i64
      %s = idr.call @carried(%k, %step, %more) : (!idr.nat, i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = idr.big.from_uint %c : i32 : !idr.nat
    %false = arith.constant false
    %p = idr.call @deep(%n, %false) : (!idr.nat, i1) -> i1
    %one = arith.constant 1 : i64
    %zero = arith.constant 0 : i64
    %k = idr.call @carried(%n, %one, %zero) : (!idr.nat, i64, i64) -> i64
    %pw = arith.extui %p : i1 to i64
    %w2 = idr.io.put_sint %pw, %w1 : i64
    %w3 = idr.io.put_sint %k, %w2 : i64
    return %w3 : !idr.world
  }
}
