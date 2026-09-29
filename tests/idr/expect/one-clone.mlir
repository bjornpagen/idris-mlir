// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@iter -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=one-clone=@loop -o /dev/null 2> %t.none.err
// RUN: FileCheck %s --check-prefix=NONE < %t.none.err
// RUN: sed -n 's|^// TWO-COPIES: ||p' %s > %t.two.mlir
// RUN: %status 1 idris-mlir-opt %t.two.mlir --idr-expect=holds=one-clone=@iter -o /dev/null 2> %t.two.err
// RUN: FileCheck %s --check-prefix=TWO < %t.two.err
// Every call of @iter reaches one function, the clone the calls share,
// whatever its name. Calls that reach two copies fail, and so does the
// property of a function that nothing calls.
// NONE: error: expected one-clone: no call of @loop or of a clone of it
// TWO: error: expected one-clone: the calls of @iter reach @iter$a @iter$b
// TWO-COPIES: module {
// TWO-COPIES:   func.func private @iter$a(%n: i64) -> i64 attributes {idr.origin = "iter"} {
// TWO-COPIES:     return %n : i64
// TWO-COPIES:   }
// TWO-COPIES:   func.func private @iter$b(%n: i64) -> i64 attributes {idr.origin = "iter"} {
// TWO-COPIES:     return %n : i64
// TWO-COPIES:   }
// TWO-COPIES:   func.func @main(%n: i64) -> (i64, i64) {
// TWO-COPIES:     %a = func.call @iter$a(%n) : (i64) -> i64
// TWO-COPIES:     %b = func.call @iter$b(%n) : (i64) -> i64
// TWO-COPIES:     return %a, %b : i64, i64
// TWO-COPIES:   }
// TWO-COPIES: }
module {
  func.func private @iter$a(%n: i64) -> i64 attributes {idr.origin = "iter"} {
    %r = func.call @iter$a(%n) : (i64) -> i64
    return %r : i64
  }
  func.func @main(%n: i64) -> (i64, i64) {
    %a = func.call @iter$a(%n) : (i64) -> i64
    %b = func.call @iter$a(%n) : (i64) -> i64
    return %a, %b : i64, i64
  }
}
