// RUN: idris-mlir-opt %s --idr-expect=holds=lowered=@f -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=lowered=@g,in-llvm -verify-diagnostics -o /dev/null
// RUN: sed '/^  func.func private @g/d' %s > %t.llvm.mlir
// RUN: idris-mlir-opt %t.llvm.mlir --idr-expect=holds=lowered,in-llvm -o /dev/null
// After idr-lower nothing of the idr dialect is left, a type in a
// signature included (@g takes the world, which has no runtime form); after
// the conversion to LLVM every op is the LLVM dialect's (@f, of which
// in-llvm says nothing), and a func.func is not. The module without @g
// (the sed drops it) is lowered and all LLVM.
module {
  llvm.func @f(%x: i64) -> i64 {
    llvm.return %x : i64
  }
  // expected-error @below {{expected lowered: }}
  // expected-error @below {{expected in-llvm: }}
  func.func private @g(!idr.world) -> i64
}
