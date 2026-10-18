// NEEDS-ACCEPTANCE: that the -verify-diagnostics run passes: one-clone fails, at the module, of calls of @iter that reach two copies of it.
// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@iter -verify-diagnostics -o /dev/null
// expected-error @-3 {{expected one-clone: the calls of @iter reach @iter$a @iter$b}}
// Every call of @iter reaches one function, the copy the calls share;
// calls that reach two copies of it, each found by its location, fail.
idr.program @"two-copies" root(@main) stage(first) {
  idr.func @iter$a(%n: i64) -> i64 {
    return %n : i64
  } loc("iter")
  idr.func @iter$b(%n: i64) -> i64 {
    return %n : i64
  } loc("iter")
  idr.func @main() -> i64 {
    %n = arith.constant 1 : i64
    %a = idr.call @iter$a(%n) : (i64) -> i64
    %b = idr.call @iter$b(%n) : (i64) -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
}
