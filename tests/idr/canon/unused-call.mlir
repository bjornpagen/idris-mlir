// RUN: idris-mlir-opt %s --idr-effects --canonicalize --idr-expect=holds=never-calls=@main:@square,\
// RUN: calls=@main:@partial,calls=@main:@divides,calls=@main:@writes -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=calls=@main:@square -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --canonicalize=test-convergence=true -o /dev/null
// NEEDS-ACCEPTANCE: that a call's effects are its callee's (idr::effectsOf, R02), and that a callee whose effects idr-effects has not solved may do anything, so canonicalize alone keeps its call.
// An unused call goes when its callee is pure, total and cannot crash.
// What a call may do is its callee's effects, which idr-effects solves
// once over the call graph and writes on each function; the call carries
// none of its own. A callee idr-effects has not solved may do anything, so
// canonicalize alone keeps every call.

idr.program @"unused-call" root(@root) stage(first) {
  idr.func @square(%x: i64) -> i64 attributes {total} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @partial(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @divides(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %r = idr.div signed %x, %y : i64
    return %r : i64
  }
  idr.func @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    return %w1 : !idr.world
  }

  idr.func @main(%x: i64, %w: !idr.world) -> !idr.world {
    %a = idr.call @square(%x) : (i64) -> i64
    %b = idr.call @partial(%x) : (i64) -> i64
    %c = idr.call @divides(%x) : (i64) -> i64
    %w1 = idr.call @writes(%x, %w) : (i64, !idr.world) -> !idr.world
    return %w1 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
