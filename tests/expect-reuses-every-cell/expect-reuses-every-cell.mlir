// RUN: idris-mlir-opt %s --idr-expect=holds=reuses-every-cell=@rebuild -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=reuses-every-cell=@drop -verify-diagnostics -o /dev/null
// The cell a take yields is recycled (@rebuild), or freed: @drop drops its
// token, and the cell goes.
!L = !idr.data<"L">
#types = #idr.types<
  "L" = list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]
>
idr.program @"reuses-every-cell" root(@Prog.main) stage(owned) types #types {
  idr.func @rebuild(%l: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %c = idr.cell.recycle %w#0 : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
      %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%w#1 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %b : !idr.own<!idr.box<!L>>
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.yield %l : !idr.own<!idr.box<!L>>
    }
    }
    return %r : !idr.own<!idr.box<!L>>
  }
  idr.func @drop(%l: !idr.own<!idr.box<!L>>) -> i64 {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (i64) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      idr.drop %w#2 : !idr.own<!idr.box<!L>>
      // expected-error @below {{expected reuses-every-cell: }}
      idr.drop %w#0 : !idr.own<!idr.token>
      idr.yield %h : i64
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
      idr.drop %l : !idr.own<!idr.box<!L>>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
