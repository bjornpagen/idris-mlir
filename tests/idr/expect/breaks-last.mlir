// RUN: idris-mlir-opt %s --idr-expect=holds=breaks-last -o /dev/null
// RUN: sed 's/@Main.show(%x: i64) -> i64 attributes {no_inline}/@Main.show(%x: i64) -> i64/; s/@Builtin.helper(%x: i64) -> i64 attributes {idr.break_last}/@Builtin.helper(%x: i64) -> i64 attributes {idr.break_last, no_inline}/' %s > %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=breaks-last -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// A function that breaks last may break a cycle of such functions alone
// (@Builtin.one), and a clone may break any cycle, as the newest does; a
// cycle that holds a function that does not break last must break at one
// (@Main.show). Moved to @Builtin.helper, the breaker of that cycle fails
// the property.
// CHECK: error: expected breaks-last: @Builtin.helper breaks last, and breaks a cycle that holds a function that does not
// CHECK-NOT: error:
module {
  func.func private @Builtin.helper(%x: i64) -> i64 attributes {idr.break_last} {
    %r = func.call @Main.show(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @Main.show(%x: i64) -> i64 attributes {no_inline} {
    %r = func.call @Builtin.helper(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @Builtin.one(%x: i64) -> i64 attributes {idr.break_last, no_inline} {
    %r = func.call @Builtin.two(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @Builtin.two(%x: i64) -> i64 attributes {idr.break_last} {
    %r = func.call @Builtin.one(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @Builtin.go$spec$1(%x: i64) -> i64 attributes {idr.break_last, no_inline, idr.clone = #idr.clone<@Builtin.go$spec$1, #idr.spec_key<"Builtin.go", [#idr.key_hole<0>]>>} {
    %r = func.call @Main.back(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @Main.back(%x: i64) -> i64 {
    %r = func.call @Builtin.go$spec$1(%x) : (i64) -> i64
    return %r : i64
  }
}
