// RUN: idris-mlir-opt %s --idr-lower --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts | FileCheck %s --implicit-check-not=unrealized_conversion_cast --implicit-check-not=func. --implicit-check-not='llvm.call %'
// After idr-lower, upstream's conversions take the module to the LLVM
// dialect alone, and no cast is left. No cell holds code: the force of a
// memo cell calls its label's function by name, for a static cell and a
// new one alike, so no call is indirect.
// CHECK-DAG: llvm.mlir.global private @{{__idr\.caf\.[0-9a-f]+}}()
// CHECK-DAG: llvm.func @Prog.main() -> i64
// CHECK-DAG: llvm.call @add(%{{.*}}, %{{.*}}) : (i64, i64) -> i64
!lazy$0 = !idr.data<"lazy$0", memo [@add(i64, i64), @running(), @forced(i64)]>
module {
  idr.func private @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func private @run(%t: !idr.box<!lazy$0>) -> i64 {
    %r = idr.force %t : !idr.box<!lazy$0> -> i64
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %c = idr.constant #idr.con<@add, [40, 2]> : !idr.box<!lazy$0>
    %two = arith.constant 2 : i64
    %d = idr.con @add(%two, %two) : (i64, i64) -> !idr.box<!lazy$0>
    %r = idr.call @run(%c) : (!idr.box<!lazy$0>) -> i64
    %s = idr.call @run(%d) : (!idr.box<!lazy$0>) -> i64
    %t = arith.addi %r, %s : i64
    return %t : i64
  }
}
