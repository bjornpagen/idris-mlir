// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// A memo sum's force runs the region of every label, but a label whose
// cell only a function that never runs makes (@never, which nothing
// calls) is made by nothing: its region never runs, and nothing is proved
// of its captures, which are shared. So the cell its region builds of a
// capture is no exclusive value, and idr-rc's solve and its commit agree
// on it. The root forces a cell of the other label, and prints the head
// of the list it gives, the byte read, as the program as written does
// (%differential, on 0, 1, 255 and the end of input).
// STDIN: \0000
// STDIN: \0001
// STDIN: \0377
// STDIN:
!List = !idr.data<"List", plain [@Nil(), @Cons(i64, !idr.box<!idr.data<"List">>)]>
!Lazy = !idr.data<"Lazy", memo [@keep(!idr.box<!List>) label @keep, @one(i64) label @one, @running() running, @forced(!idr.box<!List>) forced]>
idr.program @"capture-unmade" root(@Prog.main) stage(first) {
  idr.func @keep(%l: !idr.box<!List>) -> !idr.box<!List> attributes {total} {
    %c = arith.constant 7 : i64
    %r = idr.con !idr.box<!List> @Cons(%c : i64, %l : !idr.box<!List>)
    return %r : !idr.box<!List>
  }
  idr.func @one(%x: i64) -> !idr.box<!List> attributes {total} {
    %nil = idr.con !idr.box<!List> @Nil()
    %r = idr.con !idr.box<!List> @Cons(%x : i64, %nil : !idr.box<!List>)
    return %r : !idr.box<!List>
  }
  idr.func @Lazy.force(%t: !idr.box<!Lazy>) -> !idr.box<!List> {
    %r = idr.match %t : !idr.box<!Lazy> -> (!idr.box<!List>) {
    case @keep(%l0: !idr.box<!List>) {
      %v = idr.memo.run %t : !idr.box<!Lazy> @keep -> !idr.box<!List> {
      ^bb0(%l: !idr.box<!List>):
        %c = arith.constant 9 : i64
        %m = idr.con !idr.box<!List> @Cons(%c : i64, %l : !idr.box<!List>)
        %v0 = idr.call @keep(%m) : (!idr.box<!List>) -> !idr.box<!List>
        idr.array.yield %v0, %v0 : !idr.box<!List>, !idr.box<!List>
      }
      idr.yield %v : !idr.box<!List>
    }
    case @one(%x0: i64) {
      %v = idr.memo.run %t : !idr.box<!Lazy> @one -> !idr.box<!List> {
      ^bb0(%x: i64):
        %v0 = idr.call @one(%x) : (i64) -> !idr.box<!List>
        idr.array.yield %v0, %v0 : !idr.box<!List>, !idr.box<!List>
      }
      idr.yield %v : !idr.box<!List>
    }
    case @running() {
      idr.crash "a suspension forced itself"
      ub.unreachable
    }
    case @forced(%v: !idr.box<!List>) {
      idr.yield %v : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func @never(%l: !idr.box<!List>) -> !idr.box<!List> {
    %t = idr.con !idr.box<!Lazy> @keep(%l : !idr.box<!List>)
    %v = idr.call @Lazy.force(%t) : (!idr.box<!Lazy>) -> !idr.box<!List>
    return %v : !idr.box<!List>
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %t = idr.con !idr.box<!Lazy> @one(%x : i64)
    %l = idr.call @Lazy.force(%t) : (!idr.box<!Lazy>) -> !idr.box<!List>
    %h = idr.match %l : !idr.box<!List> -> (i64) {
    case @Nil() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Cons(%y: i64, %rest: !idr.box<!List>) {
      idr.yield %y : i64
    }
    }
    %w2 = idr.io.put_sint %h, %w1 : i64
    return %w2 : !idr.world
  }
}
