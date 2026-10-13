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
// TWO-COPIES:   idr.func private @iter$a(%n: i64) -> i64 attributes {clone = #idr.clone<@iter$a, #idr.spec_key<"iter", [#idr.key_hole<0>]>>} {
// TWO-COPIES:     return %n : i64
// TWO-COPIES:   }
// TWO-COPIES:   idr.func private @iter$b(%n: i64) -> i64 attributes {clone = #idr.clone<@iter$b, #idr.spec_key<"iter", [#idr.key_hole<0>]>>} {
// TWO-COPIES:     return %n : i64
// TWO-COPIES:   }
// TWO-COPIES:   idr.func @main(%n: i64) -> (i64, i64) {
// TWO-COPIES:     %a = call @iter$a(%n) : (i64) -> i64
// TWO-COPIES:     %b = call @iter$b(%n) : (i64) -> i64
// TWO-COPIES:     return %a, %b : i64, i64
// TWO-COPIES:   }
// TWO-COPIES: }
module {
  idr.func private @iter$a(%n: i64) -> i64 attributes {clone = #idr.clone<@iter$a, #idr.spec_key<"iter", [#idr.key_hole<0>]>>} {
    %r = idr.call @iter$a(%n) : (i64) -> i64
    return %r : i64
  }
  idr.func @main(%n: i64) -> (i64, i64) {
    %a = idr.call @iter$a(%n) : (i64) -> i64
    %b = idr.call @iter$a(%n) : (i64) -> i64
    return %a, %b : i64, i64
  }
}
