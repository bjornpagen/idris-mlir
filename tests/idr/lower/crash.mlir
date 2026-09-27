// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --idr-lower | FileCheck %s
// rule: LOW-CRASH-1, LOW-DIV-1, SEM-CRASH-1
// CHECK-DAG: @__idr_str_{{[0-9]+}}("idris-mlir: division by zero at Prog.idr:6:7\0A")
// CHECK-DAG: @__idr_str_{{[0-9]+}}("idris-mlir: division by zero at Prog.idr:7:7\0A")
// CHECK-LABEL: func.func private @Prog.d(
// CHECK: arith.cmpi eq, %{{.*}}, %{{.*}} : i64
// CHECK: scf.if
// CHECK: call @__idr_crash(
// CHECK: arith.divsi
// CHECK: arith.remsi
// CHECK: call @__idr_crash(
// CHECK: arith.remui
// CHECK-LABEL: func.func private @__idr_crash(
// CHECK: call @__idr_flush()
// CHECK: llvm.call @_exit(
module attributes {idr.version = 0 : i64, idr.entry = @Prog.r, idr.entry_kind = "int"} {
  func.func private @Prog.d(%x: i64 {idr.quantity = "w"}, %y: i64 {idr.quantity = "w"}) -> i64 {
    %q = idr.div signed %x, %y : i64 loc("Prog.idr":6:7)
    %m = idr.mod %x, %y : i64 loc("Prog.idr":7:7)
    %s = arith.addi %q, %m : i64
    return %s : i64
  }
  func.func private @Prog.r() -> i64 {
    %a = arith.constant 10 : i64
    %b = arith.constant 0 : i64
    %c = func.call @Prog.d(%a, %b) : (i64, i64) -> i64
    return %c : i64
  }
}
