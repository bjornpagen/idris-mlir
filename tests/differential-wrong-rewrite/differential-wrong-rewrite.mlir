// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.first.mlir
// RUN: %differential %s %t.first.mlir
// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// RUN: sed 's/%one = arith.constant 1 : i64/%one = arith.constant 2 : i64/' %s > %t.wrong.mlir
// RUN: not %differential %s %t.wrong.mlir 2>&1 | FileCheck %s
// %differential holds the program a pass made to the program it was
// given, from both sides: what idr-defunctionalize makes of a closure
// chosen at run time (a program at `first`), and what the steps up to
// counting make of it (at `owned`), each compiled from its own stage, print
// what the module as written prints on every one-byte input and the empty
// one; a rewrite by hand that captures 2 where the program captures 1
// prints 2 for the byte 0x00, where the program prints 1, and is named
// there. The empty input reads as 0xff (getChar's end of input), on which
// the two agree.
// CHECK: differential: differential-wrong-rewrite.mlir and {{.*}}wrong.mlir differ on the byte 0x00
// CHECK-NEXT: differential-wrong-rewrite.mlir: exit 0, stdout:
// CHECK-NEXT: 1
// CHECK-NEXT: wrong.mlir: exit 0, stdout:
// CHECK-NEXT: 2
idr.program @"differential-wrong-rewrite" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @dbl(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @pick(%n: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %one = arith.constant 1 : i64
      %f = idr.closure @add(%one) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      %g = idr.closure @dbl() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = call @pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
