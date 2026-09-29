// RUN: idris-mlir-cc %s -o %t.ll --emit=llvm
// RUN: FileCheck %s < %t.ll
// RUN: idris-mlir-cc %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 124 timeout 2 %t
// An endless loop without effects is kept: idr-tail-loops puts idr.may_loop
// in the loop of a function that is not total, and nothing asserts forward
// progress, so neither MLIR nor LLVM deletes it. The program is still
// running when its time is up.
// CHECK-NOT: mustprogress
module attributes {idr.program} {
  func.func private @Prog.spin(%n: i64) -> i64 {
    %c1 = arith.constant 1 : i64
    %m = arith.addi %n, %c1 : i64
    %r = func.call @Prog.spin(%m) : (i64) -> i64
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %c = arith.constant 1 : i64
    %r = func.call @Prog.spin(%c) : (i64) -> i64
    return %r : i64
  }
}
