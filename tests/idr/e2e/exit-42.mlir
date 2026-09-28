// RUN: idris-mlir-cc %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 42 %t
// A `main : Int` root: the low 8 bits of its result (298) are the exit
// status. The area comes from a function that is not total, so it is not
// evaluated and runs.
module attributes {idr.program} {
  idr.data @Shape {
    idr.ctor @Circle tag 0 (i64) {quantities = ["w"]}
    idr.ctor @Rect tag 1 (i64, i64, !idr.erased) {quantities = ["w", "w", "0"]}
  }
  func.func private @area(%s: !idr.data<@Shape> {idr.quantity = "w"}) -> i64 {
    %r = idr.match %s : !idr.data<@Shape> -> (i64) {
    case @Circle(%x: i64) {
      %c3 = arith.constant 3 : i64
      %xx = arith.muli %x, %x : i64
      %a = arith.muli %c3, %xx : i64
      idr.yield %a : i64
    }
    case @Rect(%w: i64, %h: i64, %e: !idr.erased) {
      %b = arith.muli %w, %h : i64
      idr.yield %b : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %e = idr.constant #idr.erased : !idr.erased
    %c6 = arith.constant 6 : i64
    %c7 = arith.constant 7 : i64
    %s = idr.con @Shape::@Rect(%c6, %c7, %e) : (i64, i64, !idr.erased) -> !idr.data<@Shape>
    %a = func.call @area(%s) : (!idr.data<@Shape>) -> i64
    %c256 = arith.constant 256 : i64
    %t = arith.addi %a, %c256 : i64
    return %t : i64
  }
}
