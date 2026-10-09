// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not=idr.closure < %t.mlir
// A closure moves into a call only on a path that runs. Here the call is in
// the region a match on a constant never takes, the one call of @g, so no
// label reaches @g's parameter: the call passes the program's poison there,
// and the closure is a constructor of its sum, as every closure is.
// CHECK-LABEL: func.func @Prog.main(
// CHECK: idr.match_lit
// CHECK: default {
// CHECK: %[[P:.*]] = ub.poison : {{.*}}
// CHECK-NEXT: call @g(%[[P]])
module attributes {idr.program} {
  func.func private @add(%k: i64, %x: i64) -> i64 attributes {idr.total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  func.func private @g(%f: !idr.fn<(i64) -> (i64)>) -> i64 {
    %one = arith.constant 1 : i64
    %r = idr.apply %f(%one) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %k = arith.constant 2 : i64
    %c = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %zero = arith.constant 0 : i64
    %r = idr.match_lit %zero : i64 -> (i64) {
    case 0 {
      idr.yield %zero : i64
    }
    default {
      %v = func.call @g(%c) : (!idr.fn<(i64) -> (i64)>) -> i64
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
}
