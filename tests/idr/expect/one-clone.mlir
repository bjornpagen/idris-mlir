// NEEDS-ACCEPTANCE: that one-clone and specialized-once hold of @iter's one copy, which calls only itself, and that the -verify-diagnostics run passes: one-clone fails, at the module, of @loop, which nothing calls, and specialized-once at the call in @walk$a, the copy of walk that calls another copy.
// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@iter,specialized-once=@iter -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@loop,specialized-once=@walk -verify-diagnostics -o /dev/null
// expected-error @-4 {{expected one-clone: no call of @loop or of a copy of it}}
// Every call of @iter reaches one function, the copy the calls share,
// whatever its name: a copy is found by its location, which names the
// function it was made from. Calls that reach two copies fail
// (one-clone-two-copies.mlir), and so does the property of a function
// that nothing calls. A copy that calls another copy of its function was
// specialized for a call in that copy (@walk$a).
idr.program @"one-clone" root(@main) stage(first) {
  idr.func @iter$a(%n: i64) -> i64 {
    %r = idr.call @iter$a(%n) : (i64) -> i64
    return %r : i64
  } loc("iter")
  idr.func @walk$a(%n: i64) -> i64 {
    // expected-error @below {{expected specialized-once: @walk$a, a copy of @walk, calls @walk$b, another copy of it}}
    %r = idr.call @walk$b(%n) : (i64) -> i64
    return %r : i64
  } loc("walk")
  idr.func @walk$b(%n: i64) -> i64 {
    %r = idr.call @walk$b(%n) : (i64) -> i64
    return %r : i64
  } loc("walk")
  idr.func @main() -> i64 {
    %n = arith.constant 1 : i64
    %a = idr.call @iter$a(%n) : (i64) -> i64
    %b = idr.call @iter$a(%n) : (i64) -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
}
