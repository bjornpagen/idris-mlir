// RUN: rm -rf %t.kept %t.spec && mkdir -p %t.kept %t.spec
// RUN: idris-mlir -c %s -o %t.kept.o --dump-dir=%t.kept --mlir-disable-threading -mlir-debug-counter=idr-specialize-clone-count=0 -mlir-print-debug-counter 2> %t.kept.err
// RUN: cat %t.kept/*-idr-simplify.mlir | FileCheck %s --check-prefix=KEPT
// RUN: FileCheck %s --check-prefix=COUNTED < %t.kept.err
// RUN: idris-mlir -c %s -o %t.spec.o --dump-dir=%t.spec
// RUN: cat %t.spec/*-idr-simplify.mlir | FileCheck %s --check-prefix=SPEC
// RUN: %cc %t.kept.o -o %t
// RUN: echo -n a | %t | FileCheck %s --check-prefix=OUT
// Specializing a call, its clone made or shared and the call redirected to
// it, is the action idr-specialize-clone. With MLIR's debug counter at 0
// every such action is skipped: the call of @pow on the closure of @inc
// stays a call of @pow, and runs to the same result. Without the counter
// it calls a clone. The function step of the simplify round redirects on
// worker threads, and MLIR's debug counter counts on one thread only, so
// the counter runs with threading off.
// KEPT-NOT: .spec
// KEPT: call @pow(
// KEPT-NOT: .spec
// COUNTED: idr-specialize-clone{{ +}}: {{[{][1-9][0-9]*}},0,0}
// SPEC: call @pow.spec{{[0-9]+}}(
// OUT: 194
module attributes {idr.program} {
  idr.func private @inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func private @pow(%f: !idr.fn<(i64) -> (i64)>, %n: i64, %x: i64) -> i64 attributes {total} {
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
