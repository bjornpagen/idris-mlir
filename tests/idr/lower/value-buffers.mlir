// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s --implicit-check-not=malloc --implicit-check-not=aligned_alloc --implicit-check-not=@free --implicit-check-not=memrefCopy --implicit-check-not=_mlir_memref_to_llvm_alloc --implicit-check-not=3735928559
// NEEDS-ACCEPTANCE: the lowered forms of value buffers as C16 sections 4.1 to 4.10 write them; check each function's body.
// A buffer bufferization made is a cell of the runtime: an allocation of
// any rank is one idris_rt_array_new of the saturating product of its
// sizes, with no allocator of upstream's. A copy of elements that hold
// references is the runtime's counted copy; a copy of contiguous words is
// one memcpy, and a copy through a strided view the runtime's again. A
// load of a counted element takes no reference (counting places it); a
// store releases the element it overwrites. A natural too large to be an
// extent is the crash `array too large`. A tie is no op at run time.
// Static data is named by its content under __idr.
// CHECK-DAG: llvm.mlir.global private constant @__idr.msg.{{[0-9a-f]{16}}}
// CHECK-DAG: array too large
// CHECK-LABEL: func.func private @alloc2(
// CHECK: llvm.intr.umul.with.overflow
// CHECK: llvm.call @idris_rt_array_new(
// CHECK-NOT: llvm.call @idris_rt_array_new(
// CHECK: return
// CHECK-LABEL: func.func private @copyStrings(
// CHECK: llvm.call @idris_rt_memref_copy(
// CHECK: return
// CHECK-LABEL: func.func private @copyWords(
// CHECK: llvm.intr.memcpy
// CHECK-NOT: idris_rt_memref_copy
// CHECK: return
// CHECK-LABEL: func.func private @copyStrided(
// CHECK: llvm.call @idris_rt_memref_copy(
// CHECK: return
// CHECK-LABEL: func.func private @loadString(
// CHECK-NOT: idris_rt_inc
// CHECK: return
// CHECK-LABEL: func.func private @storeString(
// CHECK: llvm.call @idris_rt_dec(
// CHECK: return
// CHECK-LABEL: func.func private @extent(
// CHECK: llvm.call @idris_rt_crash(
// CHECK: return
// CHECK-LABEL: func.func private @tied(
// CHECK-NOT: idr.tie_shape
// CHECK: return
module {
  idr.func private @alloc2(%a: index, %b: index) -> memref<?x?xf64> {
    %m = memref.alloc(%a, %b) : memref<?x?xf64>
    return %m : memref<?x?xf64>
  }
  idr.func private @copyStrings(%x: memref<?x!idr.str>, %y: memref<?x!idr.str>) {
    memref.copy %x, %y : memref<?x!idr.str> to memref<?x!idr.str>
    return
  }
  idr.func private @copyWords(%x: memref<?xf64>, %y: memref<?xf64>) {
    memref.copy %x, %y : memref<?xf64> to memref<?xf64>
    return
  }
  idr.func private @copyStrided(%x: memref<?xf64>, %y: memref<?xf64>, %n: index) {
    %s = memref.subview %x[1] [%n] [2] : memref<?xf64> to memref<?xf64, strided<[2], offset: 1>>
    memref.copy %s, %y : memref<?xf64, strided<[2], offset: 1>> to memref<?xf64>
    return
  }
  idr.func private @loadString(%x: memref<?x!idr.str>, %i: index) -> !idr.str {
    %s = memref.load %x[%i] : memref<?x!idr.str>
    return %s : !idr.str
  }
  idr.func private @storeString(%x: memref<?x!idr.str>, %i: index, %s: !idr.str) {
    memref.store %s, %x[%i] : memref<?x!idr.str>
    return
  }
  idr.func private @extent(%n: !idr.nat) -> index {
    %e = idr.nat.to_extent %n
    return %e : index
  }
  idr.func private @tied(%x: memref<?xf64>, %n: index) -> f64 {
    %c0 = arith.constant 0 : index
    %y = idr.tie_shape %x dims(%n) : memref<?xf64>
    %v = memref.load %y[%c0] : memref<?xf64>
    return %v : f64
  }
}
