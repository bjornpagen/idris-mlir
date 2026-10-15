// RUN: idris-mlir-opt %s --idr-deduplicate | FileCheck %s
// What is not one function twice over stays twice: a pair of which only
// one is total, a pair whose effects differ (a fact a call of the one kept
// would state of both), a pair whose bodies differ, and a pair on a cycle
// of two, whose members are no candidates: each refers to the other, so
// neither is one function apart from the other. Which definition a
// function is an instance of is no reason: that is merge-named.mlir.
// CHECK-DAG: idr.func private @A.tot(
// CHECK-DAG: idr.func private @B.tot(
// CHECK-DAG: idr.func private @A.eff(
// CHECK-DAG: idr.func private @B.eff(
// CHECK-DAG: idr.func private @A.inc(
// CHECK-DAG: idr.func private @B.dec(
// CHECK-DAG: idr.func private @A.ping(
// CHECK-DAG: idr.func private @B.ping(
module {
  idr.func private @A.tot(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func private @B.tot(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func private @A.eff(%x: i64) -> i64 attributes {effects = #idr.effects<none>} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func private @B.eff(%x: i64) -> i64 attributes {effects = #idr.effects<crash>} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func private @A.inc(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.addi %x, %c : i64
    return %y : i64
  }
  idr.func private @B.dec(%x: i64) -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    %y = arith.subi %x, %c : i64
    return %y : i64
  }
  idr.func private @A.ping(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @B.ping(%m) : (i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func private @B.ping(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default {
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
    %w2 = idr.io.put_int signed %r, %w : i64
    return %w2 : !idr.world
  }
}
