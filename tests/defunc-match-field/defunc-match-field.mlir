// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls=@run:@add,calls=@run:@dbl' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=calls=@run:@add,calls=@run:@dbl' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// BEFORE-DAG: expected calls: @run {{.*}}@add
// BEFORE-DAG: expected calls: @run {{.*}}@dbl
// A closure kept in a constructor's field and bound again by a match's
// region argument: the field's anchor holds every label any constructor
// put there, and the match declares that each region argument reads its
// field's anchor, so the bound closure's labels are known and its apply is
// a dispatch.
// The program means after the pass what it meant before it, on every input
// (the differential), and no property here held before the pass.
!Op = !idr.data<"Op", plain [@Unary(!idr.fn<(i64) -> (i64)>), @None()]>
idr.program @"match-field" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @dbl(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @run(%o: !Op, %x: i64) -> i64 attributes {total} {
    %r = idr.match %o : !Op -> (i64) {
    case @Unary(%f: !idr.fn<(i64) -> (i64)>) {
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    case @None() {
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @dbl() : () -> !idr.fn<(i64) -> (i64)>
    %o1 = idr.con !Op @Unary(%f : !idr.fn<(i64) -> (i64)>)
    %o2 = idr.con !Op @Unary(%g : !idr.fn<(i64) -> (i64)>)
    %a = idr.call @run(%o1, %n) : (!Op, i64) -> i64
    %b = idr.call @run(%o2, %a) : (!Op, i64) -> i64
    %w2 = idr.io.put_sint %b, %w1 : i64
    return %w2 : !idr.world
  }
}
