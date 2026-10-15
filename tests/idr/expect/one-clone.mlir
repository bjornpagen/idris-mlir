// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@iter -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=one-clone=@loop -o /dev/null 2> %t.none.err
// RUN: FileCheck %s --check-prefix=NONE < %t.none.err
// RUN: sed -n 's|^// TWO-COPIES: ||p' %s > %t.two.mlir
// RUN: %status 1 idris-mlir-opt %t.two.mlir --idr-expect=holds=one-clone=@iter -o /dev/null 2> %t.two.err
// RUN: FileCheck %s --check-prefix=TWO < %t.two.err
// Every call of @iter reaches one function, the copy the calls share,
// whatever its name: a copy is found by its location, which names the
// function it was made from. Calls that reach two copies fail, and so does
// the property of a function that nothing calls.
// NONE: error: expected one-clone: no call of @loop or of a copy of it
// TWO: error: expected one-clone: the calls of @iter reach @iter$a @iter$b
// TWO-COPIES: idr.program @"two-copies" root(@main) stage(first) {
// TWO-COPIES:   idr.func @iter$a(%n: i64) -> i64 {
// TWO-COPIES:     return %n : i64
// TWO-COPIES:   } loc("iter")
// TWO-COPIES:   idr.func @iter$b(%n: i64) -> i64 {
// TWO-COPIES:     return %n : i64
// TWO-COPIES:   } loc("iter")
// TWO-COPIES:   idr.func @main() -> i64 {
// TWO-COPIES:     %n = arith.constant 1 : i64
// TWO-COPIES:     %a = idr.call @iter$a(%n) : (i64) -> i64
// TWO-COPIES:     %b = idr.call @iter$b(%n) : (i64) -> i64
// TWO-COPIES:     %s = arith.addi %a, %b : i64
// TWO-COPIES:     return %s : i64
// TWO-COPIES:   }
// TWO-COPIES: }
idr.program @"one-clone" root(@main) stage(first) {
  idr.func @iter$a(%n: i64) -> i64 {
    %r = idr.call @iter$a(%n) : (i64) -> i64
    return %r : i64
  } loc("iter")
  idr.func @main() -> i64 {
    %n = arith.constant 1 : i64
    %a = idr.call @iter$a(%n) : (i64) -> i64
    %b = idr.call @iter$a(%n) : (i64) -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
}
