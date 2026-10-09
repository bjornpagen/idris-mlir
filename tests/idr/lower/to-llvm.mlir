// RUN: idris-mlir-opt %s --idr-lower --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts | FileCheck %s --implicit-check-not=unrealized_conversion_cast --implicit-check-not=func. --implicit-check-not='llvm.call %'
// After idr-lower, upstream's conversions take the module to the LLVM
// dialect alone, and no cast is left. No cell holds code: the force of a
// memo cell calls its label's function by name, for a static cell and a
// new one alike, so no call is indirect.
// CHECK-DAG: llvm.mlir.global private @__idr_caf_{{[0-9]+}}()
// CHECK-DAG: llvm.func @Prog.main() -> i64
// CHECK-DAG: llvm.call @add(%{{.*}}, %{{.*}}) : (i64, i64) -> i64
module attributes {idr.program} {
  idr.data @lazy$0 box memo labels [@add] {
    idr.ctor @add (i64, i64)
    idr.ctor @running ()
    idr.ctor @forced (i64)
  }
  func.func private @add(%k: i64, %x: i64) -> i64 attributes {idr.total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  func.func private @run(%t: !idr.box<@lazy$0>) -> i64 {
    %r = idr.force %t : !idr.box<@lazy$0> -> i64
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %c = idr.constant #idr.con<@lazy$0::@add, [40, 2]> : !idr.box<@lazy$0>
    %two = arith.constant 2 : i64
    %d = idr.con @lazy$0::@add(%two, %two) : (i64, i64) -> !idr.box<@lazy$0>
    %r = func.call @run(%c) : (!idr.box<@lazy$0>) -> i64
    %s = func.call @run(%d) : (!idr.box<@lazy$0>) -> i64
    %t = arith.addi %r, %s : i64
    return %t : i64
  }
}
