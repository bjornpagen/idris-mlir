// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@push:(i64,!llvm.ptr)->!llvm.ptr,signature=@first:(!llvm.ptr)->i64,calls-only=@push:[@idris_rt_cell],calls-only=@first:[],writes-nothing=@first,aligned-access' -o /dev/null
// A boxed constructor is a new cell: the runtime allocates it with its
// header (count 1, the info word: tag 1, one object slot, kind box), and its
// fields are stored at their offsets, the counted ones first: the header
// and the offsets are the runtime's layout.
// A match on a box reads the tag from the low bits of the
// info word, and each case its fields from the cell, writing nothing.
// What is stored is what is read: the root pushes onto Nil a word made
// of the byte it reads in its top and its bottom 8 bits, so that the
// whole 64-bit field is read back (a byte of 128 or more makes it
// negative), and takes the first of that list and of Nil. The program,
// lowered and as written, prints that word and 0, as the reference at
// the end (REF), with no list, does (%differential, on the edges of a
// byte: 0, 1, 127, 128, 255 and the end of input, which reads as 255).
// STDIN: \0000
// STDIN: \0001
// STDIN: \0177
// STDIN: \0200
// STDIN: \0377
// STDIN:
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @box root(@Prog.main) stage(first) {
  idr.func @push(%x: i64, %l: !idr.box<!List>) -> !idr.box<!List> {
    %c = idr.con !idr.box<!List> @Cons(%x : i64, %l : !idr.box<!List>)
    return %c : !idr.box<!List>
  }
  idr.func @first(%l: !idr.box<!List>) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      idr.yield %h : i64
    }
    default(%d: !idr.box<!List>) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %b = arith.extui %c : i32 to i64
    %k = arith.constant 56 : i64
    %top = arith.shli %b, %k : i64
    %x = arith.ori %top, %b : i64
    %n = idr.con !idr.box<!List> @Nil()
    %l = idr.call @push(%x, %n) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %h = idr.call @first(%l) : (!idr.box<!List>) -> i64
    %z = idr.call @first(%n) : (!idr.box<!List>) -> i64
    %w2 = idr.io.put_sint %h, %w1 : i64
    %w3 = idr.io.put_sint %z, %w2 : i64
    return %w3 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %b = arith.extui %c : i32 to i64
// REF:     %k = arith.constant 56 : i64
// REF:     %top = arith.shli %b, %k : i64
// REF:     %x = arith.ori %top, %b : i64
// REF:     %z = arith.constant 0 : i64
// REF:     %w2 = idr.io.put_sint %x, %w1 : i64
// REF:     %w3 = idr.io.put_sint %z, %w2 : i64
// REF:     return %w3 : !idr.world
// REF:   }
// REF: }
