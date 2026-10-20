// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@fill -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// A buffer bufferization made is a cell like any other, but upstream's
// ops hold plain types: memref.alloc's result takes no grade, and a
// memref.store takes the element without its reference. Counting starts
// and ends the grade at two ops of its own, which change no count: the
// alloc's fresh reference is adopted right after it, and an owned value
// is given to the store that writes it, which moves its reference in. So a
// buffer filled with a cell it was just given counts nothing. The buffer
// is then read back, its cell taken out by a load, and the input byte is
// the number stored and sets the buffer's length, 1 to 4: on each the
// program prints what it printed before counting and leaves no cell live,
// the buffer, its cell and the cells the buffer never had filled freed.
!L = !idr.data<"L">
#types = #idr.types<
  "L" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]
>
idr.program @buffers root(@root) stage(first) types #types {
  idr.func @fill(%n: index, %x: i64) -> memref<?x!idr.box<!L>> {
    %a = memref.alloc(%n) : memref<?x!idr.box<!L>>
    %nil = idr.constant !idr.box<!L> #idr.con<!L, @Nil, []>
    %c = idr.con !idr.box<!L> @Cons(%x : i64, %nil : !idr.box<!L>)
    %c0 = arith.constant 0 : index
    memref.store %c, %a[%c0] : memref<?x!idr.box<!L>>
    return %a : memref<?x!idr.box<!L>>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %c4 = arith.constant 4 : i64
    %one = arith.constant 1 : i64
    %r = arith.remui %x, %c4 : i64
    %k = arith.addi %r, %one : i64
    %n = arith.index_cast %k : i64 to index
    %a = idr.call @fill(%n, %x) : (index, i64) -> memref<?x!idr.box<!L>>
    %c0 = arith.constant 0 : index
    %l = memref.load %a[%c0] : memref<?x!idr.box<!L>>
    %h = idr.match %l : !idr.box<!L> -> (i64) {
    case @Nil() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Cons(%y: i64, %t: !idr.box<!L>) {
      idr.yield %y : i64
    }
    }
    %w1 = idr.io.put_sint %h, %w0 : i64
    %w2 = idr.io.put_sint %k, %w1 : i64
    return %w2 : !idr.world
  }
}
