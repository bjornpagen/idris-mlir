// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@iter,specialized-once=@iter -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@loop,one-clone=@step,specialized-once=@walk -verify-diagnostics -o /dev/null
// expected-error-re @-3 {{expected one-clone: {{.*}}@loop}}
// expected-error-re @-4 {{expected one-clone: {{.*}}@step}}
// Every call of @iter reaches one function, the copy the calls share,
// whatever its name: a copy is found by its location, which names the
// function it was made from. Calls that reach two copies fail (@step), and
// so does the property of a function that nothing calls (@loop). A copy that calls another copy of its function was
// specialized for a call in that copy (@walk$a).
idr.program @"one-clone" root(@main) stage(first) {
  idr.func @iter$a(%n: i64) -> i64 {
    %r = idr.call @iter$a(%n) : (i64) -> i64
    return %r : i64
  } loc("iter")
  idr.func @walk$a(%n: i64) -> i64 {
    // expected-error @below {{expected specialized-once: }}
    %r = idr.call @walk$b(%n) : (i64) -> i64
    return %r : i64
  } loc("walk")
  idr.func @walk$b(%n: i64) -> i64 {
    %r = idr.call @walk$b(%n) : (i64) -> i64
    return %r : i64
  } loc("walk")
  idr.func @step$a(%n: i64) -> i64 {
    return %n : i64
  } loc("step")
  idr.func @step$b(%n: i64) -> i64 {
    return %n : i64
  } loc("step")
  idr.func @main() -> i64 {
    %n = arith.constant 1 : i64
    %a = idr.call @iter$a(%n) : (i64) -> i64
    %b = idr.call @iter$a(%n) : (i64) -> i64
    %c = idr.call @step$a(%n) : (i64) -> i64
    %d = idr.call @step$b(%n) : (i64) -> i64
    %s = arith.addi %a, %b : i64
    %t = arith.addi %c, %d : i64
    %u = arith.addi %s, %t : i64
    return %u : i64
  }
}
