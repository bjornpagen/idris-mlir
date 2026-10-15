// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 42 %t
// A `main : Int` root: its result, 42, is the exit status. The area comes
// from a function that is not total, so it is not evaluated and runs.
!Shape = !idr.data<"Shape", plain [@Circle(i64), @Rect(i64, i64)]>
module {
  idr.func private @area(%s: !Shape) -> i64 {
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
    %s = idr.con @Rect(%c6, %c7) : (i64, i64) -> !Shape
    %a = idr.call @area(%s) : (!Shape) -> i64
    return %a : i64
  }
}
