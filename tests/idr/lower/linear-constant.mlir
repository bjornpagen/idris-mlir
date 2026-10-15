// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,signature=@action:()->(i8,i64,i64),returns=@action:1/2/3,calls-only=@action:[]' -o /dev/null
// A constant with a linear field is laid out as the constant with the
// value itself there: linearity has no runtime form, in static data too.
// So the constant IO action is the Step it holds, Bind (tag 1) of 2 and 3.
!Step = !idr.data<"Step", plain [@Done(i64), @Bind(i64, i64)]>
!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!Step>)]>
idr.program @"linear-constant" root(@Prog.main) stage(owned) {
  idr.func @action() -> !IO {
    %c = idr.constant #idr.con<@MkIO, [#idr.con<@Bind, [2, 3]>]> : !IO
    return %c : !IO
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
