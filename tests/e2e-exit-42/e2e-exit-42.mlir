// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 42 %t
// A `main : Int` root: its result, 42, is the exit status.
!Shape = !idr.data<"Shape", plain [@Circle(i64), @Rect(i64, i64)]>
idr.program @"exit-42" root(@Prog.main) stage(higher) {
  idr.func @area(%s: !Shape) -> i64 {
    %r = idr.match %s : !Shape -> (i64) {
    case @Circle(%x: i64) {
      %c3 = arith.constant 3 : i64
      %xx = arith.muli %x, %x : i64
      %a = arith.muli %c3, %xx : i64
      idr.yield %a : i64
    }
    case @Rect(%w: i64, %h: i64) {
      %b = arith.muli %w, %h : i64
      idr.yield %b : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %c6 = arith.constant 6 : i64
    %c7 = arith.constant 7 : i64
    %s = idr.con !Shape @Rect(%c6 : i64, %c7 : i64)
    %a = idr.call @area(%s) : (!Shape) -> i64
    return %a : i64
  }
}
