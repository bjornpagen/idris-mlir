// RUN: idris-mlir-cc %s -o %t.ll --emit=llvm
// RUN: FileCheck %s < %t.ll
// rule: LOW-ATTR-1, LOW-CC-1, SEM-EVAL-5, LOW-TARGET-1, LOW-TAIL-4, LOW-TAIL-5
// An infinite loop without effects is kept: idr-tail-loops puts idr.may_loop
// in the loop of a function that is not total, and nothing asserts
// termination or forward progress (no mustprogress), so neither MLIR nor
// LLVM deletes it: the loop's body is the effect idr.may_loop lowers to.
// CHECK: define {{.*}}i32 @main()
// CHECK: [[L:[0-9]+]]:
// CHECK-NEXT: tail call void asm sideeffect "", ""()
// CHECK-NEXT: br label %[[L]]
// CHECK-NOT: mustprogress
module attributes {idr.program} {
  func.func private @Prog.spin(%n: i64 {idr.quantity = "w"}) -> i64 {
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
