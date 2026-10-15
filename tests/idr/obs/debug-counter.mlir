// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize --mlir-disable-threading -mlir-debug-counter=idr-specialize-clone-count=0 -mlir-print-debug-counter -o %t.kept.mlir 2> %t.kept.err
// RUN: FileCheck %s --check-prefix=KEPT < %t.kept.mlir
// RUN: FileCheck %s --check-prefix=COUNTED < %t.kept.err
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.spec.mlir
// RUN: FileCheck %s --check-prefix=SPEC < %t.spec.mlir
// RUN: %status 2 idris-mlir -c %s -o %t.o -mlir-debug-counter=idr-specialize-clone-count=0
// NEEDS-ACCEPTANCE: that skipping the action idr-specialize-clone (C09) leaves the call of @pow.
// Making a specialization node, and redirecting a call to it, is the
// action idr-specialize-clone. In idris-mlir-opt, where experiments live,
// MLIR's debug counter at 0 skips every such action: the call of @pow on
// the closure of @inc stays a call of @pow. Without the counter it calls
// a copy. MLIR's debug counter counts on one thread only, so the counter
// runs with threading off. idris-mlir has no debug counter: a counter that
// skips actions would change the program it compiles, and the option is
// unknown there.
// KEPT: call @pow(
// COUNTED: idr-specialize-clone{{ +}}: {{[{][1-9][0-9]*}},0,0}
// SPEC-NOT: call @pow(
idr.program @"debug-counter" root(@Main.main) stage(higher) {
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @pow(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %r = idr.call @pow(%f, %m, %y) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
      idr.yield %r : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @pow(%f, %n, %n) : (!idr.fn<(i64) -> (i64)>, i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    %nl = arith.constant 10 : i32
    %w3 = idr.io.put_char %nl, %w2
    return %w3 : !idr.world
  }
}
