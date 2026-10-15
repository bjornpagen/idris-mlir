// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: FileCheck %s --implicit-check-not=.spec. < %t.mlir
// A closed call is never specialized, whether or not its callee is total:
// specializing a partial callee that never ends would unroll it one copy
// at a time, and a closed call runs at run time. @partial calls itself, so
// it is never inlined either, and its call stays with its constants.
// CHECK: call @partial(%{{.*}}, %{{.*}}) : (i64, i64) -> i64
idr.program @"closed-call" root(@Main.main) stage(first) {
  idr.func @partial(%a: i64, %b: i64) -> i64 {
    %c = idr.call @partial(%b, %a) : (i64, i64) -> i64
    return %c : i64
  }
  idr.func @total(%a: i64, %b: i64) -> i64 attributes {total} {
    %c = arith.addi %a, %b : i64
    return %c : i64
  }
  idr.func @use(%n: i64) -> i64 attributes {total} {
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %p = idr.call @partial(%c3, %c4) : (i64, i64) -> i64
    %t = idr.call @total(%c3, %c4) : (i64, i64) -> i64
    %s = arith.addi %p, %t : i64
    %s2 = arith.addi %s, %n : i64
    return %s2 : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %r = idr.call @use(%x) : (i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
