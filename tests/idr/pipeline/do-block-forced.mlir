// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: that the whole chain unfolds in @Main.main, as C06's memo sums and C07's local loop make it.
// A chain of statements linked the way `>>` links them once their thunks
// are constants: each statement forces the next statement's constant
// suspension. Defunctionalization makes each suspension a constructor of
// its memo sum, so each force is a case of a known constructor, which the
// optimizer's cleanup turns into a call of the next statement, inlined in
// the bounded loop that follows: the chain unfolds however long it is.
// CHECK-LABEL: idr.func @Main.main(
// CHECK-NOT: force
// CHECK-NOT: call @s
module {
  idr.func private @s1() -> i64 attributes {total} {
    %t = idr.constant #idr.closure<@s2, []> : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %c = arith.constant 1 : i64
    %r = arith.addi %v, %c : i64
    return %r : i64
  }
  idr.func private @s2() -> i64 attributes {total} {
    %t = idr.constant #idr.closure<@s3, []> : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %c = arith.constant 2 : i64
    %r = arith.addi %v, %c : i64
    return %r : i64
  }
  idr.func private @s3() -> i64 attributes {total} {
    %t = idr.constant #idr.closure<@s4, []> : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %c = arith.constant 3 : i64
    %r = arith.addi %v, %c : i64
    return %r : i64
  }
  idr.func private @s4() -> i64 attributes {total} {
    %t = idr.constant #idr.closure<@s5, []> : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %c = arith.constant 4 : i64
    %r = arith.addi %v, %c : i64
    return %r : i64
  }
  idr.func private @s5() -> i64 attributes {total} {
    %t = idr.constant #idr.closure<@s6, []> : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %c = arith.constant 5 : i64
    %r = arith.addi %v, %c : i64
    return %r : i64
  }
  idr.func private @s6() -> i64 attributes {total} {
    %t = idr.constant #idr.closure<@s7, []> : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %c = arith.constant 6 : i64
    %r = arith.addi %v, %c : i64
    return %r : i64
  }
  idr.func private @s7() -> i64 attributes {total} {
    %t = idr.constant #idr.closure<@s8, []> : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %c = arith.constant 7 : i64
    %r = arith.addi %v, %c : i64
    return %r : i64
  }
  idr.func private @s8() -> i64 attributes {total} {
    %c = arith.constant 8 : i64
    return %c : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %t = idr.constant #idr.closure<@s1, []> : !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w1 = idr.io.put_int signed %v, %w : i64
    return %w1 : !idr.world
  }
}
