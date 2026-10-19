// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,calls-only=@alloc2:[@idris_rt_array_new],call-order=@alloc2:[@idris_rt_array_new],calls-only=@copyStrings:[@idris_rt_memref_copy],calls-only=@copyWords:[],calls-only=@copyStrided:[@idris_rt_memref_copy]' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls-only=@loadString:[@idris_rt_inc],calls-only=@storeString:[@idris_rt_dec],calls-only=@extent:[@idris_rt_crash],crash-sites=@extent:1,calls-only=@tied:[],lowered=@tied' -o /dev/null
// A buffer bufferization made is a cell of the runtime: an allocation of
// any rank is one idris_rt_array_new of the saturating product of its
// sizes, with no allocator of upstream's, so no function asks for any
// other. A copy of elements that hold references is the runtime's counted
// copy; a copy of contiguous words is one memcpy, and a copy through a
// strided view the runtime's again. A load of a counted element takes no
// reference: counting places one where it is needed, here the one the
// returned element gives its caller; a store releases the element it
// overwrites. A natural too large to be an extent is the crash `array too
// large`. A tie is no op at run time. Static data is named by its content
// under a reserved name, and a descriptor of a cell holds the cell, never
// upstream's marker of a pointer that was not allocated.
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
  // The root calls each function on buffers whose sizes are read at run
  // time, so that each is part of the program.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %ci = arith.extui %c : i32 to i64
    %n = arith.index_cast %ci : i64 to index
    %c0 = arith.constant 0 : index
    %m = idr.call @alloc2(%n, %n) : (index, index) -> memref<?x?xf64>
    %sa = memref.alloc(%n) : memref<?x!idr.str>
    %sb = memref.alloc(%n) : memref<?x!idr.str>
    idr.call @copyStrings(%sa, %sb) : (memref<?x!idr.str>, memref<?x!idr.str>) -> ()
    %fa = memref.alloc(%n) : memref<?xf64>
    %fb = memref.alloc(%n) : memref<?xf64>
    idr.call @copyWords(%fa, %fb) : (memref<?xf64>, memref<?xf64>) -> ()
    idr.call @copyStrided(%fa, %fb, %n) : (memref<?xf64>, memref<?xf64>, index) -> ()
    %s = idr.call @loadString(%sa, %c0) : (memref<?x!idr.str>, index) -> !idr.str
    idr.call @storeString(%sb, %c0, %s) : (memref<?x!idr.str>, index, !idr.str) -> ()
    %big = idr.big.from_sint %c : i32
    %nat = idr.nat.from_big %big
    %e = idr.call @extent(%nat) : (!idr.nat) -> index
    %v = idr.call @tied(%fa, %e) : (memref<?xf64>, index) -> f64
    %w2 = idr.io.put_double %v, %w1
    return %w2 : !idr.world
  }
}
