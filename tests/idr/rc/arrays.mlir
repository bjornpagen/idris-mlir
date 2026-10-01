// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o /dev/null
// An array is a counted value, memref<?xE>: a new one is owned (never
// exclusive: its elements are reached through it), and its fill moves in
// with its reference, exclusive or not. An element read takes a reference of
// its own, which its reader consumes or drops; a value set moves into the
// array. The array itself is only read by get and set, so a function that
// does only that borrows it (a plain parameter). The second RUN line checks
// that the owned module lowers.

// CHECK-LABEL: func.func private @make(
// CHECK: %[[X:.*]] = idr.con @Opt::@Some(%{{.*}}) {{.*}} -> !idr.{{own|excl}}<!idr.data<@Opt>>
// CHECK-NOT: idr.dup
// CHECK: %[[A:.*]], %{{.*}} = idr.array.new %{{.*}}, %[[X]], %{{.*}} : !idr.{{own|excl}}<!idr.data<@Opt>> -> !idr.own<memref<?x!idr.data<@Opt>>>
// CHECK-NEXT: return %[[A]]
// CHECK-LABEL: func.func private @read(
// CHECK-SAME: %[[B:[^:]*]]: memref<?x!idr.data<@Opt>>
// CHECK: %[[V:.*]], %{{.*}} = idr.array.get %[[B]][%{{.*}}], %{{.*}} : memref<?x!idr.data<@Opt>> -> !idr.own<!idr.data<@Opt>>
// CHECK-NEXT: return %[[V]]
// CHECK-LABEL: func.func private @write(
// CHECK-SAME: %[[C:[^:]*]]: memref<?x!idr.data<@Opt>>, %[[S:[^:]*]]: !idr.own<!idr.str>
// CHECK: %[[Y:.*]] = idr.con @Opt::@Some(%[[S]])
// CHECK-NOT: idr.dup
// CHECK: idr.array.set %[[C]][%{{.*}}], %[[Y]], %{{.*}} : memref<?x!idr.data<@Opt>>, !idr.{{own|excl}}<!idr.data<@Opt>>
// CHECK-NOT: idr.drop
// CHECK-LABEL: func.func private @unused(
// CHECK: %[[U:.*]], %{{.*}} = idr.array.get
// CHECK-NEXT: idr.drop %[[U]]
module attributes {idr.program} {
  idr.data @Opt {
    idr.ctor @None ()
    idr.ctor @Some (!idr.str)
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 3 : i64
    %i = arith.constant 1 : i64
    %s = idr.constant "s" : !idr.str
    %a, %w1 = func.call @make(%n, %s, %w) : (i64, !idr.str, !idr.world) -> (memref<?x!idr.data<@Opt>>, !idr.world)
    %v, %w2 = func.call @read(%a, %i, %w1) : (memref<?x!idr.data<@Opt>>, i64, !idr.world) -> (!idr.data<@Opt>, !idr.world)
    %w3 = func.call @write(%a, %s, %i, %w2) : (memref<?x!idr.data<@Opt>>, !idr.str, i64, !idr.world) -> !idr.world
    %w4 = func.call @unused(%a, %i, %w3) : (memref<?x!idr.data<@Opt>>, i64, !idr.world) -> !idr.world
    return %w4 : !idr.world
  }
  func.func private @make(%n: i64, %s: !idr.str, %w: !idr.world) -> (memref<?x!idr.data<@Opt>>, !idr.world) {
    %x = idr.con @Opt::@Some(%s) : (!idr.str) -> !idr.data<@Opt>
    %a, %w1 = idr.array.new %n, %x, %w : !idr.data<@Opt> -> memref<?x!idr.data<@Opt>>
    return %a, %w1 : memref<?x!idr.data<@Opt>>, !idr.world
  }
  func.func private @read(%a: memref<?x!idr.data<@Opt>>, %i: i64, %w: !idr.world) -> (!idr.data<@Opt>, !idr.world) {
    %v, %w1 = idr.array.get %a[%i], %w : memref<?x!idr.data<@Opt>> -> !idr.data<@Opt>
    return %v, %w1 : !idr.data<@Opt>, !idr.world
  }
  func.func private @write(%a: memref<?x!idr.data<@Opt>>, %s: !idr.str, %i: i64, %w: !idr.world) -> !idr.world {
    %y = idr.con @Opt::@Some(%s) : (!idr.str) -> !idr.data<@Opt>
    %w1 = idr.array.set %a[%i], %y, %w : memref<?x!idr.data<@Opt>>, !idr.data<@Opt>
    return %w1 : !idr.world
  }
  func.func private @unused(%a: memref<?x!idr.data<@Opt>>, %i: i64, %w: !idr.world) -> !idr.world {
    %v, %w1 = idr.array.get %a[%i], %w : memref<?x!idr.data<@Opt>> -> !idr.data<@Opt>
    return %w1 : !idr.world
  }
}
