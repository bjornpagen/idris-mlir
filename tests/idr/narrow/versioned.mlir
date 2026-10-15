// RUN: awk '/^ *\/\/ CHAIN$/ { for (i = 1; i <= 70; i++) printf "      %%k%d = idr.big.pred %%k%d\n", i, i - 1; next } { print }' %s > %t.chain.mlir
// RUN: idris-mlir-opt %t.chain.mlir --pass-pipeline='builtin.module(idr.program(idr-rc,idr.func(idr-tail-loops),idr-narrow))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=word-loop=@deep,word-loop=@carried -o /dev/null
// NEEDS-ACCEPTANCE: that a loop whose natural descends through 70 predecessors in one trip, and one that carries a word beside its natural, are each versioned into a loop on words.
// A loop whose natural only descends to zero is versioned however far it
// descends in one trip: the first RUN line writes, where the CHAIN line
// stands, 70 predecessors of the natural one after another, and the
// descent is read back through each of them, every value asked once. And
// a loop that carries a word beside its natural is versioned too: only a
// value that holds a reference can be passed borrowed out of a loop, and
// a word holds none.
idr.program @versioned root(@root) stage(first) {
  idr.func @deep(%n: !idr.nat, %odd: i1) -> i1 attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (i1) {
    case #idr.big<0> {
      idr.yield %odd : i1
    }
    default {
      %k0 = idr.big.pred %n
      // CHAIN
      %true = arith.constant true
      %flip = arith.xori %odd, %true : i1
      %s = idr.call @deep(%k70, %flip) : (!idr.nat, i1) -> i1
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
    default {
      %k = idr.big.pred %n
      %more = arith.addi %acc, %step : i64
      %s = idr.call @carried(%k, %step, %more) : (!idr.nat, i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%n: !idr.nat) -> (i1, i64) {
    %false = arith.constant false
    %p = idr.call @deep(%n, %false) : (!idr.nat, i1) -> i1
    %one = arith.constant 1 : i64
    %zero = arith.constant 0 : i64
    %c = idr.call @carried(%n, %one, %zero) : (!idr.nat, i64, i64) -> i64
    return %p, %c : i1, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
