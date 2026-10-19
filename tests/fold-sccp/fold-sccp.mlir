// RUN: idris-mlir-opt %s --sccp --idr-expect=holds=returns=@second:7,reads-no-fields=@second,returns=@main:7 -o /dev/null
// SCCP propagates a constructor constant through a call into a private
// function, where the field read of it folds.


!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.program @sccp root(@main) stage(first) {
  idr.func @second(%p: !P) -> i64 {
    %y = idr.field %p : !P @MkP[1] -> i64
    return %y : i64
  }

  idr.func @main() -> i64 {
    %a = arith.constant 6 : i64
    %b = arith.constant 7 : i64
    %p = idr.con !P @MkP(%a : i64, %b : i64)
    %r = idr.call @second(%p) : (!P) -> i64
    return %r : i64
  }
}
