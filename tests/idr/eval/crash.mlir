// RUN: idris-mlir-opt %s --idr-eval --remarks-filter=idr-eval 2> %t.remarks | FileCheck %s
// RUN: FileCheck %s --check-prefix=REMARK < %t.remarks
// A total call can still crash: the guard of a division, by zero. The
// crash leaves the call in place, to crash at runtime, with a Missed remark
// naming it; the calls after it in the round still run, in a new child.
// CHECK-LABEL: func.func @Prog.main()
// CHECK: %[[Q:.*]] = call @half(%{{.*}}) : (i64) -> i64
// CHECK: %[[R:.*]] = arith.constant 7 : i64
// CHECK: return %[[Q]], %[[R]] : i64, i64
// REMARK: crash.mlir:{{[0-9]+}}:10: remark: [Missed] Crashed {{.*}}Function=half{{.*}}division by zero
// REMARK-NEXT: %a = func.call @half(%z)
// REMARK: crash.mlir:{{[0-9]+}}:10: remark: [Passed] Evaluated {{.*}}Function=half
// REMARK-NEXT: %b = func.call @half(%two)
module {
  func.func private @half(%x: i64) -> i64 attributes {idr.total, idr.effects = #idr.effects<none>} {
    %c = arith.constant 14 : i64
    %y = idr.check.nonzero %x, "division by zero" : i64
    %q = idr.div signed %c, %y : i64
    return %q : i64
  }
  func.func @Prog.main() -> (i64, i64) {
    %z = arith.constant 0 : i64
    %a = func.call @half(%z) : (i64) -> i64
    %two = arith.constant 2 : i64
    %b = func.call @half(%two) : (i64) -> i64
    return %a, %b : i64, i64
  }
}
