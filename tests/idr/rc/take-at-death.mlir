// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@flip,resets-unshared -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-every-cell=@keep -o /dev/null
// NEEDS-ACCEPTANCE: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A box that is still used in the region of the match that saw its
// constructor is taken apart where it dies, after that use: its fields move
// out of its cell into the constructor built there. Before that point the
// region reads its fields as borrowed from it, which is still alive, so no
// field takes a reference of its own only for the box to drop it again.
// `flip` reads the node's tag and then rebuilds it with its subtrees
// swapped: it counts nothing. `keep` stores the tail in a new cell before
// the list dies: the tail is borrowed from the list there, so it gets a
// reference of its own for the cell, and the take's copy of it is dropped.
// The owned stage's verifier checks after idr-rc that the counts balance.
!T = !idr.data<"T", plain [@L(), @N(!idr.box<!idr.data<"T">>, i64, !idr.box<!idr.data<"T">>)]>
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @"take-at-death" root(@root) stage(first) {
  idr.func @flip(%t: !idr.box<!T>) -> !idr.box<!T> {
    %r = idr.match %t : !idr.box<!T> -> (!idr.box<!T>) {
    case @L() {
      idr.yield %t : !idr.box<!T>
    }
    case @N(%l: !idr.box<!T>, %x: i64, %rt: !idr.box<!T>) {
      %k = idr.tag %t : !idr.box<!T>
      %y = arith.addi %x, %k : i64
      %n = idr.con !idr.box<!T> @N(%rt : !idr.box<!T>, %y : i64, %l : !idr.box<!T>)
      idr.yield %n : !idr.box<!T>
    }
    }
    return %r : !idr.box<!T>
  }
  idr.func @keep(%p: !idr.box<!List>) -> !idr.box<!List> {
    %r = idr.match %p : !idr.box<!List> -> (!idr.box<!List>) {
    case @Nil() {
      idr.yield %p : !idr.box<!List>
    }
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      %kept = idr.con !idr.box<!List> @Cons(%h : i64, %t : !idr.box<!List>)
      %k = idr.tag %p : !idr.box<!List>
      %n = idr.con !idr.box<!List> @Cons(%k : i64, %kept : !idr.box<!List>)
      idr.yield %n : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %x = arith.constant 7 : i64
    %leaf = idr.constant !idr.box<!T> #idr.con<!T, @L, []>
    %nil = idr.constant !idr.box<!List> #idr.con<!List, @Nil, []>
    %t = idr.con !idr.box<!T> @N(%leaf : !idr.box<!T>, %x : i64, %leaf : !idr.box<!T>)
    %f = idr.call @flip(%t) : (!idr.box<!T>) -> !idr.box<!T>
    %l = idr.con !idr.box<!List> @Cons(%x : i64, %nil : !idr.box<!List>)
    %k = idr.call @keep(%l) : (!idr.box<!List>) -> !idr.box<!List>
    %a = idr.tag %f : !idr.box<!T>
    %b = idr.tag %k : !idr.box<!List>
    %s = arith.addi %a, %b : i64
    %w2 = idr.io.put_sint %s, %w : i64
    return %w2 : !idr.world
  }
}
