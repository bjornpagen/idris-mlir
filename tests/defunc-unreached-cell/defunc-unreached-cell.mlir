// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@step:arg0:[],labels=@run:arg0:[],forces-nothing=@step' -o /dev/null
// A list of Lazy actions that no constructor ever builds: @first is called
// with the empty list only, so the case for a cell forces a suspension no
// label reaches (@step's), and applies the closure its value holds, which
// no label reaches either (@run's). The cell's key is still a memo sum,
// with no label, so that nothing lazy is left, and the closure's key is
// the empty set, so its apply runs nowhere.
!Act = !idr.data<"Act", plain [@MkAct(!idr.fn<(i64) -> (i64)>)]>
!List = !idr.data<"List", list [@Nil() nil, @Cons(!idr.lazy<!Act>, !idr.box<!idr.data<"List">>) cons]>
idr.program @"unreached-cell" root(@Prog.main) stage(higher) {
  idr.func @run(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  idr.func @step(%h: !idr.lazy<!Act>, %x: i64) -> i64 {
    %a = idr.force %h : !idr.lazy<!Act> -> !Act
    %f = idr.field %a : !Act @MkAct[0] -> !idr.fn<(i64) -> (i64)>
    %y = idr.call @run(%f, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %y : i64
  }
  idr.func @first(%l: !idr.box<!List>, %x: i64) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Nil() {
      idr.yield %x : i64
    }
    case @Cons(%h: !idr.lazy<!Act>, %t: !idr.box<!List>) {
      %y = idr.call @step(%h, %x) : (!idr.lazy<!Act>, i64) -> i64
      %z = idr.call @first(%t, %y) : (!idr.box<!List>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %nil = idr.constant !idr.box<!List> #idr.con<!List, @Nil, []>
    %c = arith.constant 7 : i64
    %r = idr.call @first(%nil, %c) : (!idr.box<!List>, i64) -> i64
    return %r : i64
  }
}
