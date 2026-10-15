// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@pick -o /dev/null
// A parameter that a function returns leaves the call with the reference it
// came with: it is owned. Borrowed, `pick` would take a reference of its
// own to return it, and the list its caller built would be shared from
// then on, so that `bump` could not update it in place.
!L = !idr.data<"L", list [@N(), @C(i64, !idr.box<!idr.data<"L">>)]>
module {
  idr.func private @pick(%a: !idr.box<!L>, %b: i64) -> !idr.box<!L> {
    return %a : !idr.box<!L>
  }
  idr.func private @bump(%l: !idr.box<!L>) -> !idr.box<!L> {
    %n = idr.constant #idr.con<@N, []> : !idr.box<!L>
    %c1 = arith.constant 1 : i64
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      idr.yield %n : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %h2 = arith.addi %h, %c1 : i64
      %t2 = idr.call @bump(%t) : (!idr.box<!L>) -> !idr.box<!L>
      %c = idr.con @C(%h2, %t2) : (i64, !idr.box<!L>) -> !idr.box<!L>
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %x = arith.constant 7 : i64
    %n = idr.constant #idr.con<@N, []> : !idr.box<!L>
    %l = idr.con @C(%x, %n) : (i64, !idr.box<!L>) -> !idr.box<!L>
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
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
