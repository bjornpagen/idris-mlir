// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,calls-only=@fresh:[@idris_rt_cell],calls-only=@frame:[]' -o /dev/null
// A cell's memory comes from its producer: the runtime's heap, or the
// function's frame, which asks the runtime for nothing; idr.cell.init then
// writes its fields, the same however the cell was made. A recycle of a
// take's token, the third producer, is exclusive.mlir's. Each function
// returns its box: where a cell may go is idr-rc's decision, which the
// lowering does not ask.
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
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
