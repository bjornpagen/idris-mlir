// RUN: idris-mlir-cc %s --check --remarks=idr-simplify --remarks-file=%t.yaml 2> %t.remarks
// RUN: FileCheck %s < %t.remarks
// RUN: FileCheck %s --check-prefix=YAML < %t.yaml
// RUN: idris-mlir-cc %s --check --remarks-file=%t.all.yaml 2> %t.quiet
// RUN: FileCheck %s --check-prefix=ALL < %t.all.yaml
// RUN: FileCheck %s --check-prefix=QUIET --allow-empty < %t.quiet
// The simplify loop traces each round in an Analysis remark (--remarks
// prints every kind): the round, the functions, the clones, the ops, the
// milliseconds. The last round is the fixpoint, and the loop's statistics
// follow. --remarks-file writes the remarks as YAML: of --remarks'
// categories, or of all of them, printing none.
// CHECK: remark: [Analysis] round | Category:idr-simplify | {{.*}}clones={{[0-9]+}}, functions={{[1-9][0-9]*}}, ms={{[0-9]+\.[0-9]+}}, ops={{[1-9][0-9]*}}, round=1{{$}}
// CHECK: remark: [Passed] idr-simplify | Category:idr-simplify | Remark="fixpoint: round {{[1-9][0-9]*}} changed nothing"
// CHECK-NOT: [Analysis] round
// CHECK: remark: [Analysis] statistics | Category:idr-simplify | {{.*}}idr-eval.evaluated={{[0-9]+}}
// YAML: --- !Analysis
// YAML-NEXT: Pass: idr-simplify
// YAML-NEXT: Name: round
// YAML: - round: '1'
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
  func.func @Prog.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %t = func.call @twice(%n) : (i64) -> i64
    %w2 = idr.io.put_int signed %t, %w1 : i64
    return %w2 : !idr.world
  }
}
