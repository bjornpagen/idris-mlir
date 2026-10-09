// RUN: idris-mlir-opt %s --idr-expect=holds=not-called=@gone -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=not-called=@kept -o /dev/null 2> %t.kept.err
// RUN: FileCheck %s --check-prefix=KEPT < %t.kept.err
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=not-called=@Prog.twice -o /dev/null 2> %t.clone.err
// RUN: FileCheck %s --check-prefix=CLONE < %t.clone.err
// No call of a function, or of a clone of it (a function whose location
// names the definition it was copied from), is left. @gone is still a
// function, which nothing calls; @kept is called, and so is a clone of
// Prog.twice.
// KEPT: error: expected not-called: @kept is still called, as @kept, in @main
// CLONE: error: expected not-called: @Prog.twice is still called, as @twice$1, in @main
module {
  func.func private @gone(%x: i64) -> i64 {
    return %x : i64
  }
  func.func private @kept(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  func.func private @twice$1(%x: i64) -> i64 {
    %y = arith.muli %x, %x : i64
    return %y : i64
  } loc("Prog.twice")
  func.func @main(%x: i64) -> (i64, i64) {
    %a = func.call @kept(%x) : (i64) -> i64
    %b = func.call @twice$1(%x) : (i64) -> i64
    return %a, %b : i64, i64
  }
}
