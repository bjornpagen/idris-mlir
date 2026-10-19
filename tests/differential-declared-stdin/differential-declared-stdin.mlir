// RUN: idris-mlir-opt %s --canonicalize -o %t.canonical.mlir
// RUN: %differential %s %t.canonical.mlir
// RUN: sed 's/%k = arith.constant 0 : i64/%k = arith.constant 1 : i64/' %s > %t.wrong.mlir
// RUN: not %differential %s %t.wrong.mlir 2>&1 | FileCheck %s
// A fixture that declares its inputs, one per STDIN line, is run on those
// and no others. The program prints the first byte it reads, and a rewrite
// by hand that adds 1 when the second byte is a newline differs only on an
// input of two bytes, which no one-byte input is: it is found on the
// declared '7\n', after the two declared inputs on which it agrees.
// STDIN:
// STDIN: 77
// STDIN: 7\n
// CHECK: differential: differential-declared-stdin.mlir and {{.*}}wrong.mlir differ on '7\n'
// CHECK-NEXT: differential-declared-stdin.mlir: exit 0, stdout:
// CHECK-NEXT: 55
// CHECK-NEXT: wrong.mlir: exit 0, stdout:
// CHECK-NEXT: 56
idr.program @"differential-declared-stdin" root(@Main.main) stage(higher) {
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %d, %w2 = idr.io.get_byte %w1
    %a = arith.extui %c : i32 to i64
    %b = arith.extui %d : i32 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 10 {
      %k = arith.constant 0 : i64
      %y = arith.addi %a, %k : i64
      idr.yield %y : i64
    }
    default(%e: i64) {
      idr.yield %a : i64
    }
    }
    %w3 = idr.io.put_sint %r, %w2 : i64
    return %w3 : !idr.world
  }
}
