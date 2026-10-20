// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@pick -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// A parameter that a function returns leaves the call with the reference it
// came with: it is owned. Borrowed, `pick` would take a reference of its
// own to return it, and the list its caller built would be shared from
// then on, so that `bump` could not update it in place. The input byte
// sets the list's length, 0 to 3, so bump and the root's match run on the
// empty list and on cells, and every run prints what it printed before
// counting and leaves no cell live.
!L = !idr.data<"L">
#types = #idr.types<
  "L" = list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]
>
idr.program @returned root(@root) stage(first) types #types {
  idr.func @pick(%a: !idr.box<!L>, %b: i64) -> !idr.box<!L> {
    return %a : !idr.box<!L>
  }
  idr.func @bump(%l: !idr.box<!L>) -> !idr.box<!L> {
    %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %c1 = arith.constant 1 : i64
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      idr.yield %n : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %h2 = arith.addi %h, %c1 : i64
      %t2 = idr.call @bump(%t) : (!idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%h2 : i64, %t2 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @build(%n: i64) -> !idr.box<!L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!L>) {
    case 0 {
      %e = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
      idr.yield %e : !idr.box<!L>
    }
    default(%d0: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = idr.call @build(%m) : (i64) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%n : i64, %t : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c4 = arith.constant 4 : i64
    %k = arith.remui %byte, %c4 : i64
    %x = arith.constant 7 : i64
    %l = idr.call @build(%k) : (i64) -> !idr.box<!L>
    %p = idr.call @pick(%l, %x) : (!idr.box<!L>, i64) -> !idr.box<!L>
    %b = idr.call @bump(%p) : (!idr.box<!L>) -> !idr.box<!L>
    %s = idr.match %b : !idr.box<!L> -> (i64) {
    case @N() {
      idr.yield %x : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      idr.yield %h : i64
    }
    }
    %w2 = idr.io.put_sint %s, %w0 : i64
    return %w2 : !idr.world
  }
}
