// RUN: idris-mlir-opt %s --idr-tail-loops --idr-narrow -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=word-loop=@parity -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-tail-loops --idr-expect=holds=word-loop=@parity -o /dev/null 2> %t.tagged.err
// RUN: FileCheck %s --check-prefix=TAGGED < %t.tagged.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=word-loop=@count -o /dev/null 2> %t.count.err
// RUN: FileCheck %s --check-prefix=COUNT < %t.count.err
// A loop whose natural only descends to zero is versioned: one test on
// entry that the natural is small, then a loop on words alone, with no tag
// test and no call on bigs in it. Before idr-narrow the loop computes on
// the natural. A sum that grows with every step is not proved small, and
// stays a big, with its fast path inline.
// TAGGED: error: expected word-loop: @parity computes on bigs in each of its loops
// COUNT: error: expected word-loop: @count computes on bigs in each of its loops
module {
  func.func private @parity(%n: !idr.nat, %odd: i1) -> i1 attributes {idr.total} {
    %r = idr.match_lit %n : !idr.nat -> (i1) {
    case #idr.big<"0"> {
      idr.yield %odd : i1
    }
    default {
      %k = idr.big.pred %n
      %true = arith.constant true
      %flip = arith.xori %odd, %true : i1
      %s = func.call @parity(%k, %flip) : (!idr.nat, i1) -> i1
      idr.yield %s : i1
    }
    }
    return %r : i1
  }
  func.func private @count(%n: !idr.nat, %acc: !idr.nat) -> !idr.nat attributes {idr.total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<"0"> {
      idr.yield %acc : !idr.nat
    }
    default {
      %k = idr.big.pred %n
      %two = idr.constant #idr.big<"2"> : !idr.nat
      %more = idr.big.add %acc, %two : !idr.nat
      %s = func.call @count(%k, %more) : (!idr.nat, !idr.nat) -> !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  func.func @Main.main(%n: !idr.nat) -> (i1, !idr.nat) {
    %false = arith.constant false
    %p = func.call @parity(%n, %false) : (!idr.nat, i1) -> i1
    %zero = idr.constant #idr.big<"0"> : !idr.nat
    %c = func.call @count(%n, %zero) : (!idr.nat, !idr.nat) -> !idr.nat
    return %p, %c : i1, !idr.nat
  }
}
