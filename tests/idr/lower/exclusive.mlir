// NEEDS-ACCEPTANCE: a recycle of an exclusive token parses (the base could not parse this file) and lowers to the token's cell with no test; a recycle of an owned token tests it for null (S3).
// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,straight-line=@exclusive,calls-only=@exclusive:[],calls=@owned:@idris_rt_inc,calls=@owned:@idris_rt_cell' -o /dev/null
// A take of an exclusive value moves its fields out with no count test:
// the cell is the token. A recycle of an exclusive token is its cell, with
// no null test and no allocation. So the exclusive function runs one path
// and asks the runtime for nothing. A take of an owned value tests its
// count, giving a field that moves on a reference of its own when the
// cell is shared, and a recycle of its token tests for null, allocating a
// cell when it is.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @exclusive root(@Prog.main) stage(owned) {
  idr.func @exclusive(%l: !idr.excl<!idr.box<!L>>, %x: i64) -> !idr.excl<!idr.box<!L>> {
    %w:3 = idr.take %l : !idr.excl<!idr.box<!L>> @C -> (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<!L>>)
    %k = idr.cell.recycle %w#0 : !idr.excl<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %w#2 : !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
    return %c : !idr.excl<!idr.box<!L>>
  }
  idr.func @owned(%l: !idr.own<!idr.box<!L>>, %x: i64) -> !idr.own<!idr.box<!L>> {
    %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
    %k = idr.cell.recycle %w#0 : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %w#2 : !idr.own<!idr.box<!L>>)
    return %c : !idr.own<!idr.box<!L>>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
