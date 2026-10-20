// RUN: idris-mlir-opt %s --idr-expect=holds=not-called=@gone,not-called=@absent -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=not-called=@kept,not-called=@Prog.twice,not-called=@self -verify-diagnostics -o /dev/null
// No call of a function, or of a copy of it, is left. A copy is any
// function whose location names the Idris definition it was made from, as
// Emit names every function's location and every copy keeps it; its
// symbol and its `instance` say nothing. @gone is still a function, which
// nothing calls; @kept is called, and so is a copy of Prog.twice; @self,
// which nothing else calls, calls itself. A function the module never had
// is not called either (@absent).
idr.program @"not-called" root(@main) stage(first) types #idr.types<> {
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
  idr.func @self(%x: i64) -> i64 {
    // expected-error @below {{expected not-called: }}
    %y = idr.call @self(%x) : (i64) -> i64
    return %y : i64
  }
  idr.func @main() -> i64 {
    %x = arith.constant 3 : i64
    // expected-error @below {{expected not-called: }}
    %a = idr.call @kept(%x) : (i64) -> i64
    // expected-error @below {{expected not-called: }}
    %b = idr.call @Prog.twice.spec.0123456789abcdef(%x) : (i64) -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
}
