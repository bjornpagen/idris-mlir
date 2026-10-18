// NEEDS-ACCEPTANCE: that labels reads the sum of labels at @pick's result and holds of the labels it runs, and no-closures of @pick, whose sum of labels is no closure; that the module parses with the closure constant written type first; and that the -verify-diagnostics run passes: one error at each closure left and one at @pick, whose sum runs more than the list of one names.
// RUN: idris-mlir-opt %s '--idr-expect=holds=labels=@pick:result:[@add,@twice],no-closures=@pick' -o /dev/null
// RUN: idris-mlir-opt %s '--idr-expect=holds=no-closures,labels=@pick:result:[@add]' -verify-diagnostics -o /dev/null
// No closure is left where none is built, applied or a constant (@pick,
// whose value is a sum of labels, as defunctionalization makes a closure's
// type); each closure left is one error, in the function that holds it. A
// sum of labels runs the functions its labels name: @pick's runs @add and
// @twice, and a list of one fails.
!Pick = !idr.data<"Pick", closures [@add(i64) label @add, @twice() label @twice]>
idr.program @closures root(@root) stage(higher) {
  idr.func @add(%x: i64, %y: i64) -> i64 {
    %r = arith.addi %x, %y : i64
    return %r : i64
  }
  idr.func @twice(%x: i64) -> i64 {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  idr.func @make(%x: i64) -> !idr.fn<(i64) -> (i64)> {
    // expected-error @below {{expected no-closures: a closure is built in @make}}
    %f = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func @use(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    // expected-error @below {{expected no-closures: a closure is applied in @use}}
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @known() -> !idr.fn<(i64, i64) -> (i64)> {
    // expected-error @below {{expected no-closures: a closure is a constant in @known}}
    %f = idr.constant !idr.fn<(i64, i64) -> (i64)> #idr.closure<@add, []>
    return %f : !idr.fn<(i64, i64) -> (i64)>
  }
  // expected-error @below {{expected labels: the sum at result 0 of @pick runs @add @twice}}
  idr.func @pick() -> !Pick {
    %f = idr.con !Pick @twice()
    return %f : !Pick
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
