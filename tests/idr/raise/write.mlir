// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-specialize > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// Output is the other consumer that moves into its callee. @show builds a
// string at runtime, recursively, and @print only writes it: the pair
// becomes a call of a clone that takes the world and writes, at each tail,
// what @show would return, using the world once on every path. Output
// fusion then writes the pieces of each append in order, and a piece that
// is a call of @show is written the same way, by the clone itself: no
// string is built at runtime. @show is pure, total and cannot crash, so the
// call of it for the right subtree is raised across the output of the left
// one. @label is partial, so output between its call and the write keeps
// the pair, and so does a string with a second use.
// CHECK-LABEL: func.func private @print(
// CHECK-SAME: %[[T:[a-z0-9_]+]]: !idr.box<@T> {idr.quantity = "w"}, %[[W:[a-z0-9_]+]]: !idr.world
// CHECK-NEXT: %[[W1:.*]] = call @[[SHOW:show\$raise\$[0-9]+]](%[[T]], %[[W]]) : (!idr.box<@T>, !idr.world) -> !idr.world
// CHECK-NEXT: return %[[W1]]
// CHECK-LABEL: func.func private @labelled(
// CHECK: %[[S:.*]] = call @label(
// CHECK-NEXT: idr.io.put_int
// CHECK-NEXT: idr.io.put_str %[[S]]
// CHECK: %[[S2:.*]] = call @label(
// CHECK-NEXT: idr.io.put_str %[[S2]]
// CHECK-NEXT: idr.io.put_str %[[S2]]
// CHECK: func.func private @[[SHOW]](
// CHECK-SAME: %[[A:[a-z0-9_]+]]: !idr.box<@T> {{.*}}, %[[V:[a-z0-9_]+]]: !idr.world {{.*}}) -> !idr.world
// CHECK-SAME: idr.effect = "effectful"{{.*}}idr.total
// CHECK: idr.match %[[A]] : !idr.box<@T> -> (!idr.world) {
// CHECK-NEXT: case @Leaf(%[[N:.*]]: i64) {
// CHECK-NEXT: %[[V1:.*]] = idr.io.put_int signed %[[N]], %[[V]] : i64
// CHECK-NEXT: idr.yield %[[V1]] : !idr.world
// CHECK: case @Node(%[[L:.*]]: !idr.box<@T>, %[[R:.*]]: !idr.box<@T>) {
// CHECK-NEXT: %[[V2:.*]] = idr.io.put_str %{{.*}}, %[[V]]
// CHECK-NEXT: %[[V3:.*]] = func.call @[[SHOW]](%[[L]], %[[V2]])
// CHECK-NEXT: %[[V4:.*]] = idr.io.put_str %{{.*}}, %[[V3]]
// CHECK-NEXT: %[[V5:.*]] = func.call @[[SHOW]](%[[R]], %[[V4]])
// CHECK-NEXT: %[[V6:.*]] = idr.io.put_str %{{.*}}, %[[V5]]
// CHECK-NEXT: idr.yield %[[V6]] : !idr.world
// CHECK-NOT: idr.str
module attributes {idr.program} {
  idr.data @T box {
    idr.ctor @Leaf tag 0 (i64) {quantities = ["w"]}
    idr.ctor @Node tag 1 (!idr.box<@T>, !idr.box<@T>) {quantities = ["w", "w"]}
  }
  func.func private @show(%t: !idr.box<@T> {idr.quantity = "w"}) -> !idr.str attributes {idr.effect = "pure", idr.total} {
    %open = idr.constant "(" : !idr.str
    %space = idr.constant " " : !idr.str
    %close = idr.constant ")" : !idr.str
    %r = idr.match %t : !idr.box<@T> -> (!idr.str) {
    case @Leaf(%n: i64) {
      %s = idr.str.show signed %n : i64
      idr.yield %s : !idr.str
    }
    case @Node(%l: !idr.box<@T>, %r: !idr.box<@T>) {
      %a = func.call @show(%l) : (!idr.box<@T>) -> !idr.str
      %b = func.call @show(%r) : (!idr.box<@T>) -> !idr.str
      %x1 = idr.str.append %open, %a
      %x2 = idr.str.append %x1, %space
      %x3 = idr.str.append %x2, %b
      %x4 = idr.str.append %x3, %close
      idr.yield %x4 : !idr.str
    }
    }
    return %r : !idr.str
  }
  func.func private @print(%t: !idr.box<@T> {idr.quantity = "w"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.world attributes {idr.effect = "effectful", idr.total} {
    %s = func.call @show(%t) : (!idr.box<@T>) -> !idr.str
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
  func.func private @label(%n: i64 {idr.quantity = "w"}) -> !idr.str attributes {idr.effect = "pure"} {
    %s = idr.str.show signed %n : i64
    return %s : !idr.str
  }
  func.func private @labelled(%n: i64 {idr.quantity = "w"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.world attributes {idr.effect = "effectful"} {
    %s = func.call @label(%n) : (i64) -> !idr.str
    %w1 = idr.io.put_int signed %n, %w : i64
    %w2 = idr.io.put_str %s, %w1
    %s2 = func.call @label(%n) : (i64) -> !idr.str
    %w3 = idr.io.put_str %s2, %w2
    %w4 = idr.io.put_str %s2, %w3
    return %w4 : !idr.world
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world attributes {idr.effect = "effectful"} {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %w2 = func.call @labelled(%n, %w1) : (i64, !idr.world) -> !idr.world
    return %w2 : !idr.world
  }
}
