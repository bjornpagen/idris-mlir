// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,calls-only=@fresh:[@idris_rt_cell],calls-only=@frame:[@idris_rt_dec]' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// A cell's memory comes from its producer: the runtime's heap, or the
// function's frame, which asks the runtime for no memory; idr.cell.init
// then writes its fields, the same however the cell was made. A recycle of
// a take's token, the third producer, is exclusive.mlir's. @fresh returns
// its box; @frame's box is of the frame and dies with it, so @frame reads
// it and drops it, which releases its fields and frees nothing.
// A heap cell holds what init wrote: the root makes one by @fresh, of the
// byte it reads and N, and matches it, so the program, lowered and as
// written, prints the byte, as the reference at the end (REF), with no
// cell, does (%differential, on 0, 255 and the end of input).
// STDIN: \0000
// STDIN: \0377
// STDIN:
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @cells root(@Prog.main) stage(owned) {
  idr.func @fresh(%x: i64, %t: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %k = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    return %c : !idr.own<!idr.box<!L>>
  }
  idr.func @frame(%x: i64, %t: !idr.own<!idr.box<!L>>) -> i64 {
    %k = idr.cell.stack : !idr.cell<!idr.box<!L>, @C, frame>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C, frame> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    %v = idr.borrow %c : !idr.q<many, own, !idr.box<!L>, frame>
    %h = idr.field %v : !idr.q<many, borrow, !idr.box<!L>, frame> @C[0] -> i64
    idr.drop %c : !idr.q<many, own, !idr.box<!L>, frame>
    return %h : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %nil = idr.con !idr.own<!idr.box<!L>> @N()
    %l = idr.call @fresh(%x, %nil) : (i64, !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>>
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (i64) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.yield %h : i64
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      %z = arith.constant -1 : i64
      idr.yield %z : i64
    }
    }
    idr.drop %l : !idr.own<!idr.box<!L>>
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %w2 = idr.io.put_sint %x, %w1 : i64
// REF:     return %w2 : !idr.world
// REF:   }
// REF: }
