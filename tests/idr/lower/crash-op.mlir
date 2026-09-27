// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --idr-lower | FileCheck %s
// rule: IDR-CRASH-1, LOW-CRASH-2
// A crash calls the crash helper with its message and location; its result
// is poison, since it is never produced.
// CHECK-DAG: @__idr_str_{{[0-9]+}}("idris-mlir: unhandled input for Main.name at Main.idr:3:1\0A")
// CHECK-LABEL: func.func private @Main.name(
// CHECK: cf.cond_br
// CHECK: call @__idr_crash(
// CHECK: ub.poison : !llvm.ptr
// CHECK: ub.poison : i64
module attributes {idr.version = 3 : i64, idr.entry = @Main.main, idr.entry_kind = "int"} {
  func.func private @Main.name(%n: i64 {idr.quantity = "w"}) -> !idr.str {
    %one = arith.constant 1 : i64
    %b = arith.cmpi eq, %n, %one : i64
    cf.cond_br %b, ^one, ^other
  ^one:
    %s = idr.str.lit "one" : !idr.str
    return %s : !idr.str
  ^other:
    %c = idr.crash "unhandled input for Main.name" : !idr.str loc("Main.idr":3:1)
    return %c : !idr.str
  }
  func.func private @Main.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
