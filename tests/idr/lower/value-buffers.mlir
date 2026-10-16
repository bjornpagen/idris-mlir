// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,calls-only=@alloc2:[@idris_rt_array_new],call-order=@alloc2:[@idris_rt_array_new],calls-only=@copyStrings:[@idris_rt_memref_copy],calls-only=@copyWords:[],calls-only=@copyStrided:[@idris_rt_memref_copy]' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls-only=@loadString:[],calls-only=@storeString:[@idris_rt_dec],calls-only=@extent:[@idris_rt_crash],crash-sites=@extent:1,calls-only=@tied:[],lowered=@tied' -o /dev/null
// NEEDS-ACCEPTANCE: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
// NEEDS-ACCEPTANCE: the lowered forms of value buffers, a memref in a function on a descriptor built at its use by upstream's patterns; check each function's calls.
// A buffer bufferization made is a cell of the runtime: an allocation of
// any rank is one idris_rt_array_new of the saturating product of its
// sizes, with no allocator of upstream's, so no function asks for any
// other. A copy of elements that hold references is the runtime's counted
// copy; a copy of contiguous words is one memcpy, and a copy through a
// strided view the runtime's again. A load of a counted element takes no
// reference (counting places it); a store releases the element it
// overwrites. A natural too large to be an extent is the crash `array too
// large`. A tie is no op at run time. Static data is named by its content
// under __idr, and a descriptor of a cell holds the cell, never upstream's
// marker of a pointer that was not allocated.
idr.program @"value-buffers" root(@root) stage(first) {
  idr.func @alloc2(%a: index, %b: index) -> memref<?x?xf64> {
    %m = memref.alloc(%a, %b) : memref<?x?xf64>
    return %m : memref<?x?xf64>
  }
  idr.func @copyStrings(%x: memref<?x!idr.str>, %y: memref<?x!idr.str>) {
    memref.copy %x, %y : memref<?x!idr.str> to memref<?x!idr.str>
    return
  }
  idr.func @copyWords(%x: memref<?xf64>, %y: memref<?xf64>) {
    memref.copy %x, %y : memref<?xf64> to memref<?xf64>
    return
  }
  idr.func @copyStrided(%x: memref<?xf64>, %y: memref<?xf64>, %n: index) {
    %s = memref.subview %x[1] [%n] [2] : memref<?xf64> to memref<?xf64, strided<[2], offset: 1>>
    memref.copy %s, %y : memref<?xf64, strided<[2], offset: 1>> to memref<?xf64>
    return
  }
  idr.func @loadString(%x: memref<?x!idr.str>, %i: index) -> !idr.str {
    %s = memref.load %x[%i] : memref<?x!idr.str>
    return %s : !idr.str
  }
  idr.func @storeString(%x: memref<?x!idr.str>, %i: index, %s: !idr.str) {
    memref.store %s, %x[%i] : memref<?x!idr.str>
    return
  }
  idr.func @extent(%n: !idr.nat) -> index {
    %e = idr.nat.to_extent %n : !idr.nat
    return %e : index
  }
  idr.func @tied(%x: memref<?xf64>, %n: index) -> f64 {
    %c0 = arith.constant 0 : index
    %y = idr.tie_shape %x dims(%n) : memref<?xf64>
    %v = memref.load %y[%c0] : memref<?xf64>
    return %v : f64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
