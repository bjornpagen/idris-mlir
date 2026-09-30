// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// Values of one closure type with different sets of labels: mkInc returns
// only @Main.inc and mkAdd only @Main.add, while @Main.use and the join of
// the match take either. Each (type, labels) is its own sum, and where a
// value moves into a slot with more labels, at the calls of @Main.use and
// at the yields of the match, a match rebuilds its constructor in the
// larger sum.
// CHECK: idr.data @[[F0:fn\$[0-9]+]] closures {
// CHECK-NEXT: idr.ctor @Main.inc ()
// CHECK-NEXT: }
// CHECK: idr.data @[[F1:fn\$[0-9]+]] closures {
// CHECK-NEXT: idr.ctor @Main.add (i64)
// CHECK-NEXT: }
// CHECK: idr.data @[[F2:fn\$[0-9]+]] closures {
// CHECK-NEXT: idr.ctor @Main.add (i64)
// CHECK-NEXT: idr.ctor @Main.inc ()
// CHECK-NEXT: }
// CHECK-NOT: !idr.fn
// CHECK-LABEL: func.func private @Main.mkInc()
// CHECK-SAME: -> !idr.data<@[[F0]]>
// CHECK-LABEL: func.func private @Main.mkAdd(
// CHECK-SAME: -> !idr.data<@[[F1]]>
// CHECK-LABEL: func.func private @Main.use(
// CHECK-SAME: %{{.*}}: !idr.data<@[[F2]]>
// CHECK-LABEL: func.func @Main.main(
// CHECK: %[[I:.*]] = call @Main.mkInc() : () -> !idr.data<@[[F0]]>
// CHECK: %[[A:.*]] = call @Main.mkAdd(%{{.*}}) : (i64) -> !idr.data<@[[F1]]>
// The calls:
// CHECK: %[[I2:.*]] = idr.match %[[I]] : !idr.data<@[[F0]]> -> (!idr.data<@[[F2]]>) {
// CHECK-NEXT: case @Main.inc() {
// CHECK-NEXT: %[[C:.*]] = idr.con @[[F2]]::@Main.inc() : () -> !idr.data<@[[F2]]>
// CHECK-NEXT: idr.yield %[[C]] : !idr.data<@[[F2]]>
// CHECK: call @Main.use(%[[I2]], %{{.*}}) : (!idr.data<@[[F2]]>, i64) -> i64
// CHECK: %[[A2:.*]] = idr.match %[[A]] : !idr.data<@[[F1]]> -> (!idr.data<@[[F2]]>) {
// CHECK-NEXT: case @Main.add(%[[X:.*]]: i64) {
// CHECK-NEXT: %[[D:.*]] = idr.con @[[F2]]::@Main.add(%[[X]]) : (i64) -> !idr.data<@[[F2]]>
// CHECK-NEXT: idr.yield %[[D]] : !idr.data<@[[F2]]>
// CHECK: call @Main.use(%[[A2]], %{{.*}}) : (!idr.data<@[[F2]]>, i64) -> i64
// The join:
// CHECK: idr.match_lit %{{.*}} : i64 -> (!idr.data<@[[F2]]>) {
// CHECK-NEXT: case 0 {
// CHECK-NEXT: %[[J:.*]] = idr.match %[[I]] : !idr.data<@[[F0]]> -> (!idr.data<@[[F2]]>) {
// CHECK: idr.yield %[[J]] : !idr.data<@[[F2]]>
// CHECK: default {
// CHECK-NEXT: %[[K:.*]] = idr.match %[[A]] : !idr.data<@[[F1]]> -> (!idr.data<@[[F2]]>) {
// CHECK: idr.yield %[[K]] : !idr.data<@[[F2]]>
module attributes {idr.program} {
  func.func private @Main.inc(%x: i64) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  func.func private @Main.add(%a: i64, %x: i64) -> i64 attributes {idr.total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  func.func private @Main.mkInc() -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
    %f = idr.closure @Main.inc() : () -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func private @Main.mkAdd(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {idr.total} {
    %f = idr.closure @Main.add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func private @Main.use(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {idr.total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %i = func.call @Main.mkInc() : () -> !idr.fn<(i64) -> (i64)>
    %a = func.call @Main.mkAdd(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r1 = func.call @Main.use(%i, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %r2 = func.call @Main.use(%a, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %j = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      idr.yield %i : !idr.fn<(i64) -> (i64)>
    }
    default {
      idr.yield %a : !idr.fn<(i64) -> (i64)>
    }
    }
    %r3 = idr.apply %j(%n) : !idr.fn<(i64) -> (i64)>
    %s1 = arith.addi %r1, %r2 : i64
    %s = arith.addi %s1, %r3 : i64
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
}
