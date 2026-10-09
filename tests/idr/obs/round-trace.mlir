// RUN: idris-mlir-opt %s --mlir-disable-threading --idr-target --idr-simplify --remarks-filter=idr-simplify -o /dev/null 2> %t.remarks
// RUN: FileCheck %s < %t.remarks
// The simplify loop traces each of its rounds in an Analysis remark, with
// the round's number among its facts (--remarks-filter prints every kind);
// the last round is the fixpoint, and the loop's statistics follow.
// CHECK: remark: [Analysis] round {{.*}}Category:idr-simplify {{.*}}round=1
// CHECK: remark: [Passed] idr-simplify {{.*}}fixpoint{{.*}}changed nothing
// CHECK-NOT: [Analysis] round
// CHECK: remark: [Analysis] statistics {{.*}}Category:idr-simplify
module attributes {idr.program} {
  func.func private @twice(%x: i64) -> i64 attributes {idr.total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = func.call @twice(%n) : (i64) -> i64
    %w2 = idr.io.put_int signed %t, %w1 : i64
    return %w2 : !idr.world
  }
}
