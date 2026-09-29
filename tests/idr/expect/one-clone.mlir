// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@iter -o /dev/null
// RUN: sed 's/call @iter\$b(/call @iter$a(/' %s > %t.shared.mlir
// RUN: sed 's/call @iter\$a(/call @iter$b(/' %s > %t.other.mlir
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=one-clone=@loop -o /dev/null 2> %t.none.err
// RUN: FileCheck %s --check-prefix=NONE < %t.none.err
// RUN: %status 1 idris-mlir-opt %S/one-clone-two.mlir --idr-expect=holds=one-clone=@iter -o /dev/null 2> %t.two.err
// RUN: FileCheck %s --check-prefix=TWO < %t.two.err
// Every call of @iter reaches one function, the clone both share, whatever
// its name; calls reaching two copies fail, and so does a property about
// a function nothing calls.
// NONE: error: expected one-clone: no call of @loop or of a clone of it
// TWO: error: expected one-clone: the calls of @iter reach @iter$a @iter$b
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
