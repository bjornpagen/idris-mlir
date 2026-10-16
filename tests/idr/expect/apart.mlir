// NEEDS-ACCEPTANCE: that apart holds of two functions made from code of their own and fails once, at @merged, whose location fuses both names.
// RUN: idris-mlir-opt %s --idr-expect=holds=apart=@inc:@dec -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=apart=@Main.inc:@Main.dec -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// Two functions are apart while each is made from code of its own. One
// whose location fuses both names, as deduplication leaves the function it
// keeps of two it merged, is made from both, and the two are one.
// CHECK-DAG: error: expected apart: @merged is made from both {{.*}} and {{.*}}
idr.program @apart root(@root) stage(first) {
  idr.func @inc(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    return %y : i64
  }
  idr.func @dec(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %y = arith.subi %x, %one : i64
    return %y : i64
  }
  idr.func @merged(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  } loc(fused["Main.inc", "Main.dec"])
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
