// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='{{(idr\.| )apply }}' --implicit-check-not='!idr.lazy' < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A list of Lazy actions that no constructor ever builds: @first is called
// with the empty list only, so the case for a cell forces a suspension no
// label reaches, and applies the closure its value holds, which no label
// reaches either. The cell's key is still a memo sum, with its states and
// no label, so that nothing lazy is left; the closure's key is the empty
// set, so its apply never runs and gives poison: no closure is left for
// the lowering.
// NEEDS-ACCEPTANCE: the sums' printed forms; @Act and @List are remade with the converted field types.
// CHECK-DAG: ![[L:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, memo [@running(), @forced({{.*}})]
// CHECK-DAG: = !idr.data<{{[^,]*}}, closures []
// CHECK-LABEL: idr.func @first(
// CHECK: force %{{.*}} : !idr.box<![[L]]> ->
// CHECK: %[[P:.*]] = ub.poison : i64
// CHECK: call @first(%{{.*}}, %[[P]])
!Act = !idr.data<"Act", plain [@MkAct(!idr.fn<(i64) -> (i64)>)]>
!List = !idr.data<"List", list [@Nil() nil, @Cons(!idr.lazy<!Act>, !idr.box<!idr.data<"List">>) cons]>
idr.program @"unreached-cell" root(@Prog.main) stage(higher) {
  idr.func @first(%l: !idr.box<!List>, %x: i64) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Nil() {
      idr.yield %x : i64
    }
    case @Cons(%h: !idr.lazy<!Act>, %t: !idr.box<!List>) {
      %a = idr.force %h : !idr.lazy<!Act> -> !Act
      %f = idr.field %a : !Act @MkAct[0] -> !idr.fn<(i64) -> (i64)>
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %z = idr.call @first(%t, %y) : (!idr.box<!List>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %nil = idr.constant #idr.con<!List, @Nil, []> : !idr.box<!List>
    %c = arith.constant 7 : i64
    %r = idr.call @first(%nil, %c) : (!idr.box<!List>, i64) -> i64
    return %r : i64
  }
}
