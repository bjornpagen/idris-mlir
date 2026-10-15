// RUN: idris-mlir-opt %s --idr-bufferize --idr-lower | FileCheck %s --implicit-check-not=malloc --implicit-check-not=aligned_alloc --implicit-check-not=@free --implicit-check-not=memrefCopy --implicit-check-not=_mlir_memref_to_llvm_alloc --implicit-check-not=3735928559
// NEEDS-ACCEPTANCE: the allocation a copy targets: `idr::bufferize::copies` reads a memref.copy into a memref.alloc (C15 section 2), the buffer idr-rc later adopts (C14); in-place is read right after idr-bufferize.
// A buffer is a cell of the runtime, freed by counting: every allocation
// bufferization makes lowers to idris_rt_array_new, and the copy a head's
// release makes of an array that is read again to the runtime's counted
// copy for elements that hold references, or to one memcpy for words.
// Nothing of upstream's allocator, deallocator or copy is left.
// CHECK-DAG: llvm.call @idris_rt_array_new(
// CHECK-DAG: llvm.call @idris_rt_memref_copy(
// CHECK-DAG: llvm.intr.memcpy
module {
  idr.func private @words(%n: index) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %t = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %a1 = tensor.insert %x into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %l = idr.lin.enter %t : !idr.lin<tensor<?xi64>>
    %before = tensor.extract %t[%c0] : tensor<?xi64>
    %u = idr.lin.use %l : !idr.lin<tensor<?xi64>>
    %nine = arith.constant 99 : i64
    %u1 = tensor.insert %nine into %u[%c0] : tensor<?xi64>
    %after = tensor.extract %u1[%c0] : tensor<?xi64>
    %s = arith.addi %before, %after : i64
    return %s : i64
  }
  idr.func private @strings(%n: index, %s: !idr.str) -> !idr.str {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?x!idr.str>
    %t = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?x!idr.str>) {
      %a1 = tensor.insert %s into %a[%i] : tensor<?x!idr.str>
      scf.yield %a1 : tensor<?x!idr.str>
    }
    %l = idr.lin.enter %t : !idr.lin<tensor<?x!idr.str>>
    %before = tensor.extract %t[%c0] : tensor<?x!idr.str>
    %u = idr.lin.use %l : !idr.lin<tensor<?x!idr.str>>
    %other = idr.constant "other" : !idr.str
    %u1 = tensor.insert %other into %u[%c0] : tensor<?x!idr.str>
    return %before : !idr.str
  }
  idr.func @root() -> i64 {
    %c4 = arith.constant 4 : index
    %s = idr.constant "kept" : !idr.str
    %v = idr.call @words(%c4) : (index) -> i64
    %r = idr.call @strings(%c4, %s) : (index, !idr.str) -> !idr.str
    return %v : i64
  }
}
