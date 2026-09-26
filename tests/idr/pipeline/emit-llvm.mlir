// RUN: idris-mlir-cc %s -o %t.ll --emit=llvm
// RUN: FileCheck %s < %t.ll
// rule: LOW-ATTR-1, LOW-CC-1, SEM-EVAL-5, LOW-TARGET-1, LOW-TAIL-4
// An infinite loop without effects is kept: nothing asserts termination or
// forward progress, and llvm.sideeffect keeps LLVM from deleting it.
// CHECK: define {{.*}}i64 @Prog.spin(
// CHECK: call void @llvm.sideeffect()
// CHECK-NEXT: br label
// CHECK: define {{.*}}i32 @main()
// CHECK: call void @llvm.sideeffect()
// CHECK-NEXT: br label
// CHECK: attributes #0 = { nofree norecurse noreturn nosync nounwind memory(inaccessiblemem: readwrite) }
module attributes {idr.version = 0 : i64, idr.entry = @Prog.main, idr.entry_kind = "int"} {
  func.func private @Prog.spin(%n: i64 {idr.quantity = "w"}) -> i64 attributes {idr.name = "spin"} {
    %r = func.call @Prog.spin(%n) : (i64) -> i64
    return %r : i64
  }
  func.func private @Prog.main() -> i64 attributes {idr.name = "main"} {
    %c = arith.constant 1 : i64
    %r = func.call @Prog.spin(%c) : (i64) -> i64
    return %r : i64
  }
}
