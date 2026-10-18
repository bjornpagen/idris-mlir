// NEEDS-ACCEPTANCE: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)`, `idr.io.put_sint` for the signed `put_int` and a function's effects as the property printed before its symbol), parses and passes as before.
// RUN: idris-mlir-opt %s --idr-deduplicate --idr-expect=holds=apart=@A.tot:@B.tot,apart=@A.eff:@B.eff,apart=@A.inc:@B.dec,apart=@A.ping:@B.ping -o /dev/null
// NEEDS-ACCEPTANCE: the two functions that are not total declare diverge, as the verifier's effect rule asks; they are still kept apart.
// What is not one function twice over stays twice: a pair of which only
// one is total, a pair whose effects differ (each function's own facts,
// which every call of it reads, so the one kept would state one of them of
// both), a pair whose bodies differ, and a pair on a cycle of two, whose
// members are no candidates: each refers to the other, so neither is one
// function apart from the other. Which definition a function is an
// instance of is no reason: that is merge-named.mlir.
idr.program @"keep-apart" root(@root) stage(higher) {
  idr.func @A.tot(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @B.tot(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func effects<diverge> @A.eff(%x: i64) -> i64 {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func effects<crash, diverge> @B.eff(%x: i64) -> i64 {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func @A.inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func @B.dec(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.subi %x, %c : i64
    return %y : i64
  }
  idr.func @A.ping(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @B.ping(%m) : (i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @B.ping(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @A.ping(%m) : (i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 7 : i64
    %c = idr.call @A.tot(%n) : (i64) -> i64
    %d = idr.call @B.tot(%c) : (i64) -> i64
    %e = idr.call @A.eff(%d) : (i64) -> i64
    %f = idr.call @B.eff(%e) : (i64) -> i64
    %g = idr.call @A.inc(%f) : (i64) -> i64
    %h = idr.call @B.dec(%g) : (i64) -> i64
    %r = idr.call @A.ping(%h) : (i64) -> i64
    %w2 = idr.io.put_sint %r, %w : i64
    return %w2 : !idr.world
  }
}
