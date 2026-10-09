// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not=idr.apply --implicit-check-not='!idr.lazy' < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// A list of Lazy actions that no constructor ever builds: @first is called
// with the empty list only, so the case for a cell forces a suspension no
// label reaches, and applies the closure its value holds, which no label
// reaches either. The cell's key is still a memo sum, with its states and
// no label, so that nothing lazy is left; the closure's key is the empty
// set, so its apply never runs and gives poison: no closure is left for
// the lowering.
// CHECK: idr.data @[[L:lazy\$[0-9]+]] box memo
// CHECK-NEXT: idr.ctor @running ()
// CHECK-NEXT: idr.ctor @forced (!idr.data<@Act>)
// CHECK-NEXT: }
// CHECK: idr.data @List box {
// CHECK-NEXT: idr.ctor @Nil ()
// CHECK-NEXT: idr.ctor @Cons (!idr.box<@[[L]]>, !idr.box<@List>)
// CHECK-LABEL: func.func private @first(
// CHECK: idr.force %{{.*}} : !idr.box<@[[L]]> -> !idr.data<@Act>
// CHECK: %[[P:.*]] = ub.poison : i64
// CHECK: call @first(%{{.*}}, %[[P]])
module attributes {idr.program} {
  idr.data @Act {
    idr.ctor @MkAct (!idr.fn<(i64) -> (i64)>)
  }
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (!idr.lazy<!idr.data<@Act>>, !idr.box<@List>)
  }
  func.func private @first(%l: !idr.box<@List>, %x: i64) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Nil() {
      idr.yield %x : i64
    }
    case @Cons(%h: !idr.lazy<!idr.data<@Act>>, %t: !idr.box<@List>) {
      %a = idr.force %h : !idr.lazy<!idr.data<@Act>> -> !idr.data<@Act>
      %f = idr.field %a[@MkAct, 0] : !idr.data<@Act> -> !idr.fn<(i64) -> (i64)>
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %z = func.call @first(%t, %y) : (!idr.box<@List>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %nil = idr.constant #idr.con<@List::@Nil, []> : !idr.box<@List>
    %c = arith.constant 7 : i64
    %r = func.call @first(%nil, %c) : (!idr.box<@List>, i64) -> i64
    return %r : i64
  }
}
