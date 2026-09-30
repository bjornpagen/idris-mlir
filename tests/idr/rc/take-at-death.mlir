// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@flip,resets-unshared -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=reuses-every-cell=@keep -o /dev/null
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
module attributes {idr.program} {
  idr.data @T box {
    idr.ctor @L ()
    idr.ctor @N (!idr.box<@T>, i64, !idr.box<@T>)
  }
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  func.func private @flip(%t: !idr.box<@T>) -> !idr.box<@T> {
    %r = idr.match %t : !idr.box<@T> -> (!idr.box<@T>) {
    case @L() {
      idr.yield %t : !idr.box<@T>
    }
    case @N(%l: !idr.box<@T>, %x: i64, %rt: !idr.box<@T>) {
      %k = idr.tag %t : !idr.box<@T>
      %y = arith.addi %x, %k : i64
      %n = idr.con @T::@N(%rt, %y, %l) : (!idr.box<@T>, i64, !idr.box<@T>) -> !idr.box<@T>
      idr.yield %n : !idr.box<@T>
    }
    }
    return %r : !idr.box<@T>
  }
  func.func private @keep(%p: !idr.box<@List>) -> !idr.box<@List> {
    %r = idr.match %p : !idr.box<@List> -> (!idr.box<@List>) {
    case @Nil() {
      idr.yield %p : !idr.box<@List>
    }
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      %kept = idr.con @List::@Cons(%h, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
      %k = idr.tag %p : !idr.box<@List>
      %n = idr.con @List::@Cons(%k, %kept) : (i64, !idr.box<@List>) -> !idr.box<@List>
      idr.yield %n : !idr.box<@List>
    }
    }
    return %r : !idr.box<@List>
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %x = arith.constant 7 : i64
    %leaf = idr.constant #idr.con<@T::@L, []> : !idr.box<@T>
    %nil = idr.constant #idr.con<@List::@Nil, []> : !idr.box<@List>
    %t = idr.con @T::@N(%leaf, %x, %leaf) : (!idr.box<@T>, i64, !idr.box<@T>) -> !idr.box<@T>
    %f = func.call @flip(%t) : (!idr.box<@T>) -> !idr.box<@T>
    %l = idr.con @List::@Cons(%x, %nil) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %k = func.call @keep(%l) : (!idr.box<@List>) -> !idr.box<@List>
    %a = idr.tag %f : !idr.box<@T>
    %b = idr.tag %k : !idr.box<@List>
    %s = arith.addi %a, %b : i64
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
