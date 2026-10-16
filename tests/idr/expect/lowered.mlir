// NEEDS-ACCEPTANCE: that lowered holds of an llvm.func and fails once at a declaration whose signature takes the world, and that in-llvm holds of the CLEAN module and fails once for the func.func left.
// RUN: sed -n 's|^// CLEAN: ||p' %s > %t.clean.mlir
// RUN: idris-mlir-opt %s --idr-expect=holds=lowered=@f -o /dev/null
// RUN: idris-mlir-opt %t.clean.mlir --idr-expect=holds=in-llvm -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=lowered=@g,in-llvm -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 2
// After idr-lower nothing of the idr dialect is left, a type in a
// signature included (@g takes the world, which has no runtime form); after
// the conversion to LLVM every op is the LLVM dialect's (the CLEAN
// module), and a func.func is not.
// CHECK-DAG: error: expected lowered: the signature holds a type of the idr dialect in @g
// CHECK-DAG: error: expected in-llvm: {{.*}} is left in @g
// CLEAN: module {
// CLEAN:   llvm.func @f(%x: i64) -> i64 {
// CLEAN:     llvm.return %x : i64
// CLEAN:   }
// CLEAN: }
module {
  llvm.func @f(%x: i64) -> i64 {
    llvm.return %x : i64
  }
  func.func private @g(!idr.world) -> i64
}
