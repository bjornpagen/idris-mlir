// RUN: idris-mlir-cc %s --check --remarks=idr-simplify --remarks-file=%t.yaml 2> %t.remarks
// RUN: FileCheck %s < %t.remarks
// RUN: FileCheck %s --check-prefix=YAML < %t.yaml
// RUN: idris-mlir-cc %s --check --remarks-file=%t.all.yaml 2> %t.quiet
// RUN: FileCheck %s --check-prefix=ALL < %t.all.yaml
// RUN: FileCheck %s --check-prefix=QUIET --allow-empty < %t.quiet
// The simplify loop traces each of its rounds in an Analysis remark, with
// the round's number among its facts (--remarks prints every kind); the
// last round is the fixpoint, and the loop's statistics follow. With
// --remarks-file the remarks go to a file too, as YAML documents: those of
// --remarks' categories, or of all of them while none is printed.
// CHECK: remark: [Analysis] round {{.*}}Category:idr-simplify {{.*}}round=1
// CHECK: remark: [Passed] idr-simplify {{.*}}fixpoint{{.*}}changed nothing
// CHECK-NOT: [Analysis] round
// CHECK: remark: [Analysis] statistics {{.*}}Category:idr-simplify
// YAML: --- !Analysis
// YAML-NEXT: Pass: idr-simplify
// YAML-NEXT: Name: round
// YAML: --- !Passed
// YAML-NEXT: Pass: idr-simplify
// ALL: Pass: idr-simplify
// ALL-NEXT: Name: round
// QUIET-NOT: remark
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
