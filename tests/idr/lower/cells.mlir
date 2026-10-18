// NEEDS-ACCEPTANCE: each producer of a cell lowers alone, writing the header, and idr.cell.init writes the fields (S3): a fresh cell is the runtime's, a frame's cell an alloca, a recycle of an exclusive token its cell with no test, and a recycle of a shared token its cell or a fresh one when it is null.
// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,calls-only=@fresh:[@idris_rt_cell],calls-only=@frame:[],calls-only=@exclusive:[],calls-only=@shared:[@idris_rt_cell]' -o /dev/null
// A cell's memory comes from its producer, one op per source: the
// runtime's heap, the function's frame, or a token's cell. Each writes the
// cell's header; idr.cell.init then writes its fields, the same however the
// cell was made. A token passed in is no take's here, so every recycle
// writes the header and every field. Each function returns its box: where a
// cell may go is idr-rc's decision, which the lowering does not ask.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @cells root(@Prog.main) stage(owned) {
  idr.func @fresh(%x: i64, %t: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %k = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    return %c : !idr.own<!idr.box<!L>>
  }
  idr.func @frame(%x: i64, %t: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %k = idr.cell.stack : !idr.cell<!idr.box<!L>, @C>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    return %c : !idr.own<!idr.box<!L>>
  }
  idr.func @exclusive(%tok: !idr.excl<!idr.token>, %x: i64, %t: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %k = idr.cell.recycle %tok : !idr.excl<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    return %c : !idr.own<!idr.box<!L>>
  }
  idr.func @shared(%tok: !idr.own<!idr.token>, %x: i64, %t: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %k = idr.cell.recycle %tok : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
    %c = idr.cell.init %k : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    return %c : !idr.own<!idr.box<!L>>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
