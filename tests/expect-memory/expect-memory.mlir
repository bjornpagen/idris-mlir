// RUN: idris-mlir-opt %s --idr-expect=holds=aligned-access=@aligned,aligned-access=@stores,reads-nothing=@pure,writes-nothing=@pure,writes-nothing=@aligned -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=aligned-access=@unaligned,reads-nothing=@aligned,writes-nothing=@stores -verify-diagnostics -o /dev/null
// What a lowered function does to memory, by its ops' effects and
// alignments: one that computes in registers reads and writes nothing
// (@pure); a load through a parameter reads, a store writes, and each
// states the alignment its cell's layout gives, or does not (@unaligned).
module {
  llvm.func @pure(%x: i64) -> i64 {
    %y = llvm.add %x, %x : i64
    llvm.return %y : i64
  }
  llvm.func @aligned(%p: !llvm.ptr) -> i64 {
    // expected-error @below {{expected reads-nothing: }}
    %v = llvm.load %p <alignment = 8> : !llvm.ptr -> i64
    llvm.return %v : i64
  }
  llvm.func @stores(%p: !llvm.ptr, %x: i64) {
    // expected-error @below {{expected writes-nothing: }}
    llvm.store %x, %p <alignment = 8> : i64, !llvm.ptr
    llvm.return
  }
  llvm.func @unaligned(%p: !llvm.ptr) -> i64 {
    // expected-error @below {{expected aligned-access: }}
    %v = llvm.load %p : !llvm.ptr -> i64
    llvm.return %v : i64
  }
}
