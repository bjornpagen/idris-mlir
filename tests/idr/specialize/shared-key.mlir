// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: FileCheck %s --check-prefix=CALLS < %t.mlir
// RUN: FileCheck %s --check-prefix=NODES < %t.mlir
// NEEDS-ACCEPTANCE: the order of the copies after their owner (by name) and of the root among the functions.
// Calls whose keys are equal share one copy. @applyN loops, so it is never
// inlined, and it specializes on the closure it is given, a constructor of
// its sum after defunctionalization, whose label is static and whose
// capture is a runtime leaf. The first two calls pass closures of @add
// over different values, one key; the third a closure of @sub, another
// key. So the root calls two copies, the first one twice, and the module
// holds exactly two.
// CALLS-LABEL: idr.func @Main.main(
// CALLS: call @[[ADD:applyN\.spec\.[0-9a-f]+]](
// CALLS-NEXT: call @[[ADD]](
// CALLS-NEXT: call @[[SUB:applyN\.spec\.[0-9a-f]+]](
// CALLS-NOT: call @[[ADD]](
// NODES-COUNT-2: idr.func @applyN.spec.
// NODES-NOT: idr.func @applyN.spec.
idr.program @"shared-key" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @sub(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.subi %a, %x : i64
    return %y : i64
  }
  idr.func @applyN(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %z = idr.call @applyN(%f, %m, %y) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %m = arith.addi %n, %n : i64
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @add(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
    %h = idr.closure @sub(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r1 = idr.call @applyN(%f, %n, %n) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %r2 = idr.call @applyN(%g, %n, %n) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %r3 = idr.call @applyN(%h, %n, %n) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %s = arith.addi %r1, %r2 : i64
    %t = arith.addi %s, %r3 : i64
    %w2 = idr.io.put_int signed %t, %w1 : i64
    return %w2 : !idr.world
  }
}
