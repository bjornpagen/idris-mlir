// NEEDS-ACCEPTANCE: that effects reads each function's declared set, which covers its body as the program's verifier asks, written as this wave prints a function's effects (`idr.func effects<...> @f`); and that the -verify-diagnostics run passes, one error at each function given another set.
// RUN: idris-mlir-opt %s --idr-expect=holds=effects=@pure:none,effects=@divides:crash,effects=@unsolved:io+crash+diverge -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=effects=@pure:crash,effects=@divides:none -verify-diagnostics -o /dev/null
// What a function may do is the set it holds: none for one that only
// computes and is total (@pure), crash for one whose guard may (@divides),
// and everything for one no pass solved, which holds the default
// (@unsolved).
idr.program @"solved-effects" root(@root) stage(first) {
  // expected-error @below {{expected effects: @pure may do none, not crash}}
  idr.func effects<none> @pure(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  // expected-error @below {{expected effects: @divides may do crash, not none}}
  idr.func effects<crash> @divides(%x: i64, %y: i64) -> i64 attributes {total} {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    return %q : i64
  }
  idr.func @unsolved(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
