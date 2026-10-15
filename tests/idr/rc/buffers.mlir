// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@fill -o /dev/null
// NEEDS-ACCEPTANCE: where idr-rc puts the two boundary ops.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A buffer bufferization made is a cell like any other, but upstream's
// ops hold plain types: memref.alloc's result takes no grade, and a
// memref.store takes the element without its reference. Counting starts
// and ends the grade at two ops of its own, which change no count: the
// alloc's fresh reference is adopted right after it, and an owned value
// is given to the store that writes it, which moves its reference in. So a
// buffer filled with a cell it was just given counts nothing.
// CHECK-LABEL: idr.func @fill(
// CHECK: %[[A:.*]] = memref.alloc(
// CHECK-NEXT: idr.own.adopt %[[A]]
// CHECK: %[[G:.*]] = idr.own.give
// CHECK-NEXT: memref.store %[[G]],
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @buffers root(@main) stage(first) {
  idr.func @fill(%n: index, %x: i64) -> memref<?x!idr.box<!L>> {
    %a = memref.alloc(%n) : memref<?x!idr.box<!L>>
    %nil = idr.constant #idr.con<!L, @Nil, []> : !idr.box<!L>
    %c = idr.con !idr.box<!L> @Cons(%x : i64, %nil : !idr.box<!L>)
    %c0 = arith.constant 0 : index
    memref.store %c, %a[%c0] : memref<?x!idr.box<!L>>
    return %a : memref<?x!idr.box<!L>>
  }
  idr.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
