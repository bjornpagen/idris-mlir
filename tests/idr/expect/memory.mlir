// NEEDS-ACCEPTANCE: that aligned-access fails once at the llvm.load that states no alignment, and reads-nothing and writes-nothing once each at the load and the store through a pointer parameter.
// RUN: idris-mlir-opt %s --idr-expect=holds=aligned-access=@aligned,aligned-access=@stores,reads-nothing=@pure,writes-nothing=@pure,writes-nothing=@aligned -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=aligned-access=@unaligned,reads-nothing=@aligned,writes-nothing=@stores -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 3
// What a lowered function does to memory, by its ops' effects and
// alignments: one that computes in registers reads and writes nothing
// (@pure); a load through a parameter reads, a store writes, and each
// states the alignment its cell's layout gives, or does not (@unaligned).
// CHECK-DAG: error: expected aligned-access: {{.*}} in @unaligned states no alignment
// CHECK-DAG: error: expected reads-nothing: {{.*}} reads memory in @aligned
// CHECK-DAG: error: expected writes-nothing: {{.*}} writes memory in @stores
module {
  llvm.func @pure(%x: i64) -> i64 {
    %y = llvm.add %x, %x : i64
    llvm.return %y : i64
  }
  llvm.func @aligned(%p: !llvm.ptr) -> i64 {
    %v = llvm.load %p <alignment = 8> : !llvm.ptr -> i64
    llvm.return %v : i64
  }
  llvm.func @stores(%p: !llvm.ptr, %x: i64) {
    llvm.store %x, %p <alignment = 8> : i64, !llvm.ptr
    llvm.return
  }
  llvm.func @unaligned(%p: !llvm.ptr) -> i64 {
    %v = llvm.load %p : !llvm.ptr -> i64
    llvm.return %v : i64
  }
}
