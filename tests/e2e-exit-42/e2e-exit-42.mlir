// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 42 %t
// RUN: sed 's/arith.constant 6 :/arith.constant 0 :/' %s > %t.0.mlir
// RUN: idris-mlir -c %t.0.mlir -o %t.0.o
// RUN: %cc %t.0.o -o %t.0
// RUN: %t.0
// RUN: sed 's/arith.constant 6 :/arith.constant 15 :/; s/arith.constant 7 :/arith.constant 17 :/' %s > %t.255.mlir
// RUN: idris-mlir -c %t.255.mlir -o %t.255.o
// RUN: %cc %t.255.o -o %t.255
// RUN: %status 255 %t.255
// RUN: sed 's/arith.constant 6 :/arith.constant 16 :/; s/arith.constant 7 :/arith.constant 16 :/' %s > %t.256.mlir
// RUN: idris-mlir -c %t.256.mlir -o %t.256.o
// RUN: %cc %t.256.o -o %t.256
// RUN: %status 1 %t.256 > %t.256.out 2> %t.256.err
// RUN: FileCheck %s --check-prefix=PAST --match-full-lines < %t.256.err
// RUN: count 0 < %t.256.out
// RUN: sed 's/arith.constant 6 :/arith.constant -1 :/; s/arith.constant 7 :/arith.constant 1 :/' %s > %t.minus.mlir
// RUN: idris-mlir -c %t.minus.mlir -o %t.minus.o
// RUN: %cc %t.minus.o -o %t.minus
// RUN: %status 1 %t.minus 2> %t.minus.err
// RUN: FileCheck %s --check-prefix=NEGATIVE --match-full-lines < %t.minus.err
// A `main : Int` root: its result, 42, is the exit status; so is any from
// 0 to 255, both ends included. Any other result is no status a parent
// could tell from its low 8 bits (256 would read as 0, -1 as 255), so the
// program ends as a crash that names it, and prints nothing else. Each
// variant is the program with the rectangle's sides changed by the sed.
// PAST: idris-mlir: main returned 256, which is not an exit status (0 to 255)
// NEGATIVE: idris-mlir: main returned -1, which is not an exit status (0 to 255)
!Shape = !idr.data<"Shape">
#types = #idr.types<
  "Shape" = plain [@Circle(i64), @Rect(i64, i64)]
>
idr.program @"exit-42" root(@Prog.main) stage(higher) types #types {
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
