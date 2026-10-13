// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A closed call is never specialized, whether or not its callee is total:
// specializing a partial callee that never ends would unroll it one clone
// at a time, and a closed call runs at run time.
// CHECK-NOT: .spec
// CHECK-LABEL: idr.func private @use(
// CHECK: call @partial(%{{.*}}, %{{.*}}) : (i64, i64) -> i64
// CHECK: call @total(%{{.*}}, %{{.*}}) : (i64, i64) -> i64
module attributes {idr.program} {
  idr.func private @partial(%a: i64, %b: i64) -> i64 {
    %c = idr.call @partial(%b, %a) : (i64, i64) -> i64
    return %c : i64
  }
  idr.func private @total(%a: i64, %b: i64) -> i64 attributes {total} {
    %c = arith.addi %a, %b : i64
    return %c : i64
  }
  idr.func private @use(%n: i64) -> i64 attributes {total} {
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %p = idr.call @partial(%c3, %c4) : (i64, i64) -> i64
    %t = idr.call @total(%c3, %c4) : (i64, i64) -> i64
    %s = arith.addi %p, %t : i64
    %s2 = arith.addi %s, %n : i64
    return %s2 : i64
  }
  idr.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
