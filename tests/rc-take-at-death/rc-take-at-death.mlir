// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@flip,resets-unshared -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-every-cell=@keep -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
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
// The input byte is the key and says whether the tree is a leaf and the
// list empty, so both functions run on both of their cases, and every run
// prints what it printed before counting and leaves no cell live.
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
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %leaf = idr.constant !idr.box<!T> #idr.con<!T, @L, []>
    %nil = idr.constant !idr.box<!List> #idr.con<!List, @Nil, []>
    %bit0 = arith.andi %x, %c1 : i64
    %t = idr.match_lit %bit0 : i64 -> (!idr.box<!T>) {
    case 0 {
      idr.yield %leaf : !idr.box<!T>
    }
    default(%d0: i64) {
      %n = idr.con !idr.box<!T> @N(%leaf : !idr.box<!T>, %x : i64, %leaf : !idr.box<!T>)
      idr.yield %n : !idr.box<!T>
    }
    }
    %f = idr.call @flip(%t) : (!idr.box<!T>) -> !idr.box<!T>
    %bit1 = arith.andi %x, %c2 : i64
    %l = idr.match_lit %bit1 : i64 -> (!idr.box<!List>) {
    case 0 {
      idr.yield %nil : !idr.box<!List>
    }
    default(%d1: i64) {
      %c = idr.con !idr.box<!List> @Cons(%x : i64, %nil : !idr.box<!List>)
      idr.yield %c : !idr.box<!List>
    }
    }
    %k = idr.call @keep(%l) : (!idr.box<!List>) -> !idr.box<!List>
    %a = idr.match %f : !idr.box<!T> -> (i64) {
    case @L() {
      idr.yield %c1 : i64
    }
    case @N(%fl: !idr.box<!T>, %fx: i64, %fr: !idr.box<!T>) {
      idr.yield %fx : i64
    }
    }
    %b = idr.call @total(%k) : (!idr.box<!List>) -> i64
    %w1 = idr.io.put_sint %a, %w0 : i64
    %w2 = idr.io.put_sint %b, %w1 : i64
    return %w2 : !idr.world
  }
  // The elements, each a digit of its own, the head the highest.
  idr.func @total(%l: !idr.box<!List>) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Nil() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      %s = idr.call @total(%t) : (!idr.box<!List>) -> i64
      %k = arith.constant 1000 : i64
      %hk = arith.muli %h, %k : i64
      %v = arith.addi %hk, %s : i64
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
}
