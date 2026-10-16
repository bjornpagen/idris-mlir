// NEEDS-ACCEPTANCE: that labels reads the sum of labels at @pick's result, holds of the labels it runs and fails, once, of a list that names fewer; and that the failing request reports exactly the four errors checked.
// RUN: sed -n 's|^// CLEAN: ||p' %s > %t.clean.mlir
// RUN: idris-mlir-opt %t.clean.mlir --idr-expect=holds=no-closures -o /dev/null
// RUN: idris-mlir-opt %s '--idr-expect=holds=labels=@pick:result:[@add,@twice]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=no-closures,labels=@pick:result:[@add]' -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 4
// A module without closures holds; each closure left, built, applied or a
// constant, is one error, in the function that holds it. A sum of labels,
// as defunctionalization makes a closure's type, runs the functions its
// labels name: @pick's runs @add and @twice, and a list of one fails.
// CHECK-DAG: error: expected no-closures: a closure is built in @make
// CHECK-DAG: error: expected no-closures: a closure is applied in @use
// CHECK-DAG: error: expected no-closures: a closure is a constant in @known
// CHECK-DAG: error: expected labels: the sum at {{.*}} of @pick runs {{.*}}
// CLEAN: idr.program @clean root(@main) stage(first) {
// CLEAN:   idr.func @main(%x: i64) -> i64 {
// CLEAN:     %one = arith.constant 1 : i64
// CLEAN:     %r = arith.addi %x, %one : i64
// CLEAN:     return %r : i64
// CLEAN:   }
// CLEAN: }
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
    %f = idr.closure @add(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func @use(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @known() -> !idr.fn<(i64, i64) -> (i64)> {
    %f = idr.constant #idr.closure<@add, []> : !idr.fn<(i64, i64) -> (i64)>
    return %f : !idr.fn<(i64, i64) -> (i64)>
  }
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
