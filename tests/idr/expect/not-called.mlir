// NEEDS-ACCEPTANCE: that not-called holds of @gone, and that the -verify-diagnostics run passes: it fails at the call of @kept and at the call of a copy of Prog.twice.
// RUN: idris-mlir-opt %s --idr-expect=holds=not-called=@gone -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=not-called=@kept,not-called=@Prog.twice -verify-diagnostics -o /dev/null
// No call of a function, or of a copy of it, is left. A copy is any
// function whose location names the Idris definition it was made from, as
// Emit names every function's location and every copy keeps it; its
// symbol and its `instance` say nothing. @gone is still a function, which
// nothing calls; @kept is called, and so is a copy of Prog.twice.
idr.program @"not-called" root(@main) stage(first) {
  idr.func @gone(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @kept(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @Prog.twice.spec.0123456789abcdef(%x: i64) -> i64 {
    %y = arith.muli %x, %x : i64
    return %y : i64
  } loc("Prog.twice"("Prog.idr":3:1))
  idr.func @main() -> i64 {
    %x = arith.constant 3 : i64
    // expected-error @below {{expected not-called: @kept is still called, as @kept, in @main}}
    %a = idr.call @kept(%x) : (i64) -> i64
    // expected-error @below {{expected not-called: @Prog.twice is still called, as @Prog.twice.spec.0123456789abcdef, in @main}}
    %b = idr.call @Prog.twice.spec.0123456789abcdef(%x) : (i64) -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
}
