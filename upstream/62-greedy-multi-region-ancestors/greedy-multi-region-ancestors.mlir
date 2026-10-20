// RUN: mlir-opt %s -canonicalize -debug-only=greedy-rewriter 2>&1 \
// RUN:   -o /dev/null | FileCheck %s
// REQUIRES: asserts

// Each case folds an addition of two constants. An op with several regions
// is revisited once the worklist is empty, not after each change in each of
// its regions: the switch is processed a bounded number of times, however
// many cases fold.

// CHECK-COUNT-4: Processing operation : 'scf.index_switch'
// CHECK-NOT: Processing operation : 'scf.index_switch'
func.func @f(%i: index, %x: i64) -> i64 {
  %r = scf.index_switch %i -> i64
  case 0 {
    %c = arith.constant 0 : i64
    %d = arith.constant 1 : i64
    %s = arith.addi %c, %d : i64
    %t = arith.addi %s, %x : i64
    scf.yield %t : i64
  }
  case 1 {
    %c = arith.constant 1 : i64
    %d = arith.constant 1 : i64
    %s = arith.addi %c, %d : i64
    %t = arith.addi %s, %x : i64
    scf.yield %t : i64
  }
  case 2 {
    %c = arith.constant 2 : i64
    %d = arith.constant 1 : i64
    %s = arith.addi %c, %d : i64
    %t = arith.addi %s, %x : i64
    scf.yield %t : i64
  }
  case 3 {
    %c = arith.constant 3 : i64
    %d = arith.constant 1 : i64
    %s = arith.addi %c, %d : i64
    %t = arith.addi %s, %x : i64
    scf.yield %t : i64
  }
  case 4 {
    %c = arith.constant 4 : i64
    %d = arith.constant 1 : i64
    %s = arith.addi %c, %d : i64
    %t = arith.addi %s, %x : i64
    scf.yield %t : i64
  }
  case 5 {
    %c = arith.constant 5 : i64
    %d = arith.constant 1 : i64
    %s = arith.addi %c, %d : i64
    %t = arith.addi %s, %x : i64
    scf.yield %t : i64
  }
  case 6 {
    %c = arith.constant 6 : i64
    %d = arith.constant 1 : i64
    %s = arith.addi %c, %d : i64
    %t = arith.addi %s, %x : i64
    scf.yield %t : i64
  }
  case 7 {
    %c = arith.constant 7 : i64
    %d = arith.constant 1 : i64
    %s = arith.addi %c, %d : i64
    %t = arith.addi %s, %x : i64
    scf.yield %t : i64
  }
  default {
    scf.yield %x : i64
  }
  return %r : i64
}
