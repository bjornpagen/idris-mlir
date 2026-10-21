// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// A matched box whose field is a box read by field reads: the match's
// reuse site gives the field as its take's field, and the same box is
// met again as a read box on the walk. It is taken apart once, by the
// first site: met again, every use of it already moves to that take's
// field, so no site of its own takes it apart a second time where no
// use says it dies (the block's start, before the read that defines
// it). The root prints the tag of what @go rebuilt, 1, for the byte it
// reads.
// STDIN: \0007
// A matched box whose field is a box read by field reads: the match's
// reuse site gives the field as its take's field, and the same box is
// also met as a read box. It is taken apart once, by the first site.
!T = !idr.data<"T">
!P = !idr.data<"P">
!L = !idr.data<"L">
!L1 = !idr.data<"L1">
!A = !idr.data<"A">
#types = #idr.types<
  "A" = plain [@Def(i64, i64), @NoDef(!idr.box<!L1>)],
  "L" = list [@Nil() nil, @Cons(!idr.box<!P>, !idr.box<!L>) cons],
  "L1" = plain [@Cons1(!idr.box<!P>, !idr.box<!L>)],
  "P" = plain [@MkP(i64, !idr.box<!T>)],
  "T" = plain [@Leaf(), @Node(i64, !idr.box<!T>)]
>
idr.program @"fixture" root(@root) stage(first) types #types {
  idr.func @sum(%t: !idr.box<!T>) -> i64 attributes {total} {
    %r = idr.match %t : !idr.box<!T> -> (i64) {
    case @Leaf() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Node(%x: i64, %rest: !idr.box<!T>) {
      %s = idr.call @sum(%rest) : (!idr.box<!T>) -> i64
      %v = arith.addi %x, %s : i64
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
  idr.func @go(%a: !idr.box<!A>) -> !idr.box<!A> attributes {total} {
    %r = idr.match %a : !idr.box<!A> -> (!idr.box<!A>) {
    case @Def(%x: i64, %y: i64) {
      %b = idr.con !idr.box<!A> @Def(%y : i64, %x : i64)
      idr.yield %b : !idr.box<!A>
    }
    case @NoDef(%l1: !idr.box<!L1>) {
      %pr = idr.field %l1 : !idr.box<!L1> @Cons1[0] -> !idr.box<!P>
      %rest = idr.field %l1 : !idr.box<!L1> @Cons1[1] -> !idr.box<!L>
      %k = idr.field %pr : !idr.box<!P> @MkP[0] -> i64
      %t = idr.field %pr : !idr.box<!P> @MkP[1] -> !idr.box<!T>
      %s = idr.call @sum(%t) : (!idr.box<!T>) -> i64
      %k2 = arith.addi %k, %s : i64
      %p2 = idr.con !idr.box<!P> @MkP(%k2 : i64, %t : !idr.box<!T>)
      %l2 = idr.con !idr.box<!L1> @Cons1(%p2 : !idr.box<!P>, %rest : !idr.box<!L>)
      %b = idr.con !idr.box<!A> @NoDef(%l2 : !idr.box<!L1>)
      idr.yield %b : !idr.box<!A>
    }
    }
    return %r : !idr.box<!A>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %leaf = idr.constant !idr.box<!T> #idr.con<!T, @Leaf, []>
    %node = idr.con !idr.box<!T> @Node(%x : i64, %leaf : !idr.box<!T>)
    %pr = idr.con !idr.box<!P> @MkP(%x : i64, %node : !idr.box<!T>)
    %nil = idr.constant !idr.box<!L> #idr.con<!L, @Nil, []>
    %l1 = idr.con !idr.box<!L1> @Cons1(%pr : !idr.box<!P>, %nil : !idr.box<!L>)
    %a = idr.con !idr.box<!A> @NoDef(%l1 : !idr.box<!L1>)
    %r = idr.call @go(%a) : (!idr.box<!A>) -> !idr.box<!A>
    %tag = idr.tag %r : !idr.box<!A>
    %s = idr.str.show_sint %tag : i64
    %w1 = idr.io.put_str %s, %w0
    return %w1 : !idr.world
  }
}
