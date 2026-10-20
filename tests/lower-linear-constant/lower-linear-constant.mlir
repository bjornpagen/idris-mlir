// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@action:()->(i8,i64,i64),returns=@action:1/2/3,calls-only=@action:[]' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// A constant with a linear field is laid out as the constant with the
// value itself there: linearity has no runtime form, in static data too.
// So the constant IO action is the Step it holds, Bind (tag 1) of 2 and 3.
// The root takes the Step out of the action and matches it: the program,
// lowered and as written, exits with 23, Bind's 2 and 3, as the reference
// at the end (REF) does (%differential, on the one input, none, since it
// reads none).
// STDIN:
!Step = !idr.data<"Step">
!IO = !idr.data<"IO">
#types = #idr.types<
  "IO" = plain [@MkIO(!idr.lin<!Step>)],
  "Step" = plain [@Done(i64), @Bind(i64, i64)]
>
idr.program @"linear-constant" root(@Prog.main) stage(owned) types #types {
  idr.func @action() -> !IO {
    %c = idr.constant !IO #idr.con<!IO, @MkIO, [#idr.con<!Step, @Bind, [2, 3]>]>
    return %c : !IO
  }
  idr.func @Prog.main() -> i64 {
    %io = idr.call @action() : () -> !IO
    %s = idr.field %io : !IO @MkIO[0] -> !Step
    %r = idr.match %s : !Step -> (i64) {
    case @Done(%x: i64) {
      idr.yield %x : i64
    }
    case @Bind(%a: i64, %b: i64) {
      %ten = arith.constant 10 : i64
      %t = arith.muli %a, %ten : i64
      %v = arith.addi %t, %b : i64
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.main() -> i64 {
// REF:     %c = arith.constant 23 : i64
// REF:     return %c : i64
// REF:   }
// REF: }
