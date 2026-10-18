// NEEDS-ACCEPTANCE: that the root, now the IO root the root rule admits (it prints what it computed), keeps every action of idr-optimize seen at least once.
// NEEDS-ACCEPTANCE: that skipping idr-optimize-inline, idr-identity-call or idr-constants-replace leaves a module that verifies and differs from the one idr-optimize makes, each action seen at least once.
// RUN: idris-mlir-opt %s --idr-optimize -o %t.done.mlir
// RUN: idris-mlir-opt %s --idr-optimize --mlir-disable-threading -mlir-debug-counter=idr-optimize-inline-count=0 -mlir-print-debug-counter -o %t.idr-optimize-inline.mlir 2> %t.idr-optimize-inline.err
// RUN: FileCheck %s --check-prefix=IDR_OPTIMIZE_INLINE < %t.idr-optimize-inline.err
// RUN: not diff %t.idr-optimize-inline.mlir %t.done.mlir
// RUN: idris-mlir-opt %s --idr-optimize --mlir-disable-threading -mlir-debug-counter=idr-identity-call-count=0 -mlir-print-debug-counter -o %t.idr-identity-call.mlir 2> %t.idr-identity-call.err
// RUN: FileCheck %s --check-prefix=IDR_IDENTITY_CALL < %t.idr-identity-call.err
// RUN: not diff %t.idr-identity-call.mlir %t.done.mlir
// RUN: idris-mlir-opt %s --idr-optimize --mlir-disable-threading -mlir-debug-counter=idr-constants-replace-count=0 -mlir-print-debug-counter -o %t.idr-constants-replace.mlir 2> %t.idr-constants-replace.err
// RUN: FileCheck %s --check-prefix=IDR_CONSTANTS_REPLACE < %t.idr-constants-replace.err
// RUN: not diff %t.idr-constants-replace.mlir %t.done.mlir
// @inc, a leaf, is inlined; @weaken gives back its argument (Data.Fin's
// weaken); every run of @seven returns 7, which its caller reads from its
// summary.
// IDR_OPTIMIZE_INLINE: idr-optimize-inline{{ +}}: {{[{][1-9][0-9]*}},0,0}
// IDR_IDENTITY_CALL: idr-identity-call{{ +}}: {{[{][1-9][0-9]*}},0,0}
// IDR_CONSTANTS_REPLACE: idr-constants-replace{{ +}}: {{[{][1-9][0-9]*}},0,0}
idr.program @inner root(@main) stage(first) {
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    return %y : i64
  }
  idr.func @weaken(%i: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %i : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      %z = idr.constant !idr.nat #idr.big<0>
      idr.yield %z : !idr.nat
    }
    default(%d0: !idr.nat) {
      %k = idr.big.pred %i
      %w = idr.call @weaken(%k) : (!idr.nat) -> !idr.nat
      %one = idr.constant !idr.nat #idr.big<1>
      %s = idr.big.add %w, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }
  idr.func @seven(%n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %c = arith.constant 7 : i64
      idr.yield %c : i64
    }
    default(%d1: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %x = idr.call @seven(%m) : (i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @main(%w: !idr.world) -> !idr.world {
    %b, %w1 = idr.io.get_byte %w
    %n = arith.extui %b : i32 to i64
    %r = idr.call @seven(%n) : (i64) -> i64
    %s = idr.call @inc(%r) : (i64) -> i64
    %three = idr.constant !idr.nat #idr.big<3>
    %v = idr.call @weaken(%three) : (!idr.nat) -> !idr.nat
    %k = idr.match_lit %v : !idr.nat -> (i64) {
    case #idr.big<3> {
      %yes = arith.constant 1 : i64
      idr.yield %yes : i64
    }
    default(%other: !idr.nat) {
      %no = arith.constant 0 : i64
      idr.yield %no : i64
    }
    }
    %w2 = idr.io.put_sint %s, %w1 : i64
    %w3 = idr.io.put_sint %k, %w2 : i64
    return %w3 : !idr.world
  }
}
