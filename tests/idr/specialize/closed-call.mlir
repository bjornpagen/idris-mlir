// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A closed call is never specialized, whether or not its callee has
// idr.total: it is idr-eval's, and what idr-eval leaves runs as it is
// (specializing a partial callee that never ends would unroll it one clone
// at a time). An erased argument is not a static value: it neither makes a
// call specializable nor keeps a closed call from being closed.
// CHECK-NOT: $spec$
// CHECK-LABEL: func.func private @use(
// CHECK: call @partial(%{{.*}}, %{{.*}}) : (i64, i64) -> i64
// CHECK: call @total(%{{.*}}, %{{.*}}) : (i64, i64) -> i64
// CHECK: call @erasing(%{{.*}}, %{{.*}}) : (!idr.erased, i64) -> i64
// CHECK: call @erasing(%{{.*}}, %{{.*}}) : (!idr.erased, i64) -> i64
module attributes {idr.program} {
  func.func private @partial(%a: i64, %b: i64) -> i64 {
    %c = func.call @partial(%b, %a) : (i64, i64) -> i64
    return %c : i64
  }
  func.func private @total(%a: i64, %b: i64) -> i64 attributes {idr.total} {
    %c = arith.addi %a, %b : i64
    return %c : i64
  }
  func.func private @erasing(%e: !idr.erased, %b: i64) -> i64 attributes {idr.total} {
    return %b : i64
  }
  func.func private @use(%n: i64, %e: !idr.erased) -> i64 attributes {idr.total} {
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %erased = idr.constant #idr.erased : !idr.erased
    %p = func.call @partial(%c3, %c4) : (i64, i64) -> i64
    %t = func.call @total(%c3, %c4) : (i64, i64) -> i64
    %x = func.call @erasing(%erased, %n) : (!idr.erased, i64) -> i64
    %y = func.call @erasing(%e, %c3) : (!idr.erased, i64) -> i64
    %s = arith.addi %p, %t : i64
    %s2 = arith.addi %s, %x : i64
    %s3 = arith.addi %s2, %y : i64
    return %s3 : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
