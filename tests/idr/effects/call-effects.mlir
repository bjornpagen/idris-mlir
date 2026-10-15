// RUN: idris-mlir-opt %s --idr-effects --idr-expect=holds=effects=@square:none,effects=@boxes:none,effects=@crashes:crash,effects=@partial:diverge,effects=@writes:io,effects=@main:io+crash+diverge -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --idr-expect=holds=facts-as-marked -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --cse --canonicalize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls-distinct=@main:@square -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls-read=@main:@unused -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls-distinct=@main:@boxes -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls-read=@main:@boxes -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --idr-canonicalize=test-convergence=true -o /dev/null
// NEEDS-ACCEPTANCE: that a call answers move and delay with its callee's effects as idr-effects found them, and that canonicalize and CSE keep every call.
// idr-effects finds what each function may do, once, on the function. A
// call holds no effects: what it may do is its callee's, which a pass that
// knows the program's functions reads by the callee's name. So the
// dialect's rewrites move a call of a function that only computes across
// anything, and delay a call that performs no IO, though it may crash or
// not return; a call that performs IO stays in its place. To upstream's
// passes, which read the call alone, a call may do anything: dead code
// removal keeps an unused call and CSE keeps two equal ones, however pure
// the callee. The calls of pure callees are dropped and merged by
// idr-pure-calls, from the callee's summary (optimize/pure-call.mlir).
!Box = !idr.data<"Box", plain [@MkBox(i64)]>
idr.program @"call-effects" root(@root) stage(first) {
  idr.func @square(%x: i64) -> i64 attributes {total} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @unused(%x: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  idr.func @boxes(%x: i64) -> !Box attributes {total} {
    %b = idr.con !Box @MkBox(%x : i64)
    return %b : !Box
  }
  idr.func @crashes(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %r = idr.div signed %x, %y : i64
    return %r : i64
  }
  idr.func @partial(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    return %w1 : !idr.world
  }
  idr.func @main(%x: i64, %w: !idr.world) -> (i64, i64, !Box, !Box, i64, i64, i64, i64, !idr.world) {
    %a = idr.call @square(%x) {expect.facts = "move delay"} : (i64) -> i64
    %b = idr.call @square(%x) {expect.facts = "move delay"} : (i64) -> i64
    %u = idr.call @unused(%x) {expect.facts = "move delay"} : (i64) -> i64
    %b1 = idr.call @boxes(%x) {expect.facts = "move delay"} : (i64) -> !Box
    %b2 = idr.call @boxes(%x) {expect.facts = "move delay"} : (i64) -> !Box
    %u2 = idr.call @boxes(%x) {expect.facts = "move delay"} : (i64) -> !Box
    %c1 = idr.call @crashes(%x) {expect.facts = "delay"} : (i64) -> i64
    %c2 = idr.call @crashes(%x) {expect.facts = "delay"} : (i64) -> i64
    %p1 = idr.call @partial(%x) {expect.facts = "delay"} : (i64) -> i64
    %p2 = idr.call @partial(%x) {expect.facts = "delay"} : (i64) -> i64
    %w1 = idr.call @writes(%x, %w) {expect.facts = ""} : (i64, !idr.world) -> !idr.world
    %w2 = idr.call @writes(%x, %w1) {expect.facts = ""} : (i64, !idr.world) -> !idr.world
    return %a, %b, %b1, %b2, %c1, %c2, %p1, %p2, %w2 : i64, i64, !Box, !Box, i64, i64, i64, i64, !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
