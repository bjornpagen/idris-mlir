// NEEDS-ACCEPTANCE: that lowered holds of an llvm.func, and that the -verify-diagnostics run passes: lowered fails at the declaration whose signature takes the world, and in-llvm at the func.func left and nowhere in the llvm.func.
// RUN: idris-mlir-opt %s --idr-expect=holds=lowered=@f -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=lowered=@g,in-llvm -verify-diagnostics -o /dev/null
// After idr-lower nothing of the idr dialect is left, a type in a
// signature included (@g takes the world, which has no runtime form); after
// the conversion to LLVM every op is the LLVM dialect's (@f, of which
// in-llvm says nothing), and a func.func is not.
module {
  llvm.func @f(%x: i64) -> i64 {
    llvm.return %x : i64
  }
  // expected-error @below {{expected lowered: the signature holds a type of the idr dialect in @g}}
  // expected-error @below {{expected in-llvm: func.func is left in @g}}
  func.func private @g(!idr.world) -> i64
}
