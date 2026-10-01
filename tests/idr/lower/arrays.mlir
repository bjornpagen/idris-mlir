// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// An array is one runtime cell, allocated by idris_rt_array_new with the
// element layout in its header; its elements are read and written here. A
// new array writes the fill into every element, each taking a reference,
// and drops the fill's own. A read checks the index against the length,
// crashes when it is out of bounds, and gives the element a reference of
// its own. A write checks likewise, drops the old element's reference and
// stores the new one. An unboxed sum element is its slots, counted first.
// CHECK-LABEL: func.func private @make(
// CHECK-SAME: %[[N:[^:]*]]: i64, %[[T:[^:]*]]: i8 {{.*}}, %[[S:[^:]*]]: !llvm.ptr)
// CHECK: %[[A:.*]] = llvm.call @idris_rt_array_new(%[[N]], %{{.*}}) : (i64, i32) -> !llvm.ptr
// CHECK: scf.for
// CHECK-DAG: llvm.store %[[S]]
// CHECK-DAG: llvm.store %[[T]]
// CHECK: llvm.call @idris_rt_inc(%[[S]])
// CHECK: }
// CHECK: llvm.call @idris_rt_dec(%[[S]])
// CHECK: return %[[A]]
// CHECK-LABEL: func.func private @read(
// CHECK-SAME: %[[B:[^:]*]]: !llvm.ptr, %[[I:[^:]*]]: i64)
// CHECK: %[[L:.*]] = llvm.load %{{.*}} : !llvm.ptr -> i64
// CHECK: %[[OUT:.*]] = llvm.icmp "uge" %[[I]], %[[L]]
// CHECK: scf.if %[[OUT]] {
// CHECK: llvm.call @idris_rt_crash(
// CHECK: }
// CHECK: %[[P:.*]] = llvm.load %{{.*}} : !llvm.ptr -> !llvm.ptr
// CHECK: llvm.call @idris_rt_inc(%[[P]])
// CHECK-LABEL: func.func private @write(
// CHECK: llvm.icmp "uge"
// CHECK: llvm.call @idris_rt_crash(
// CHECK: %[[OLD:.*]] = llvm.load %{{.*}} : !llvm.ptr -> !llvm.ptr
// CHECK: llvm.call @idris_rt_dec(%[[OLD]])
// CHECK: llvm.store
module attributes {idr.program, idr.stage = "owned"} {
  idr.data @Opt {
    idr.ctor @None ()
    idr.ctor @Some (!idr.str)
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 3 : i64
    %i = arith.constant 1 : i64
    %x = idr.con @Opt::@None() : () -> !idr.own<!idr.data<@Opt>>
    %a, %w1 = func.call @make(%n, %x, %w) : (i64, !idr.own<!idr.data<@Opt>>, !idr.world) -> (!idr.own<memref<?x!idr.data<@Opt>>>, !idr.world)
    %b = idr.borrow %a : !idr.own<memref<?x!idr.data<@Opt>>>
    %v, %w2 = func.call @read(%b, %i, %w1) : (memref<?x!idr.data<@Opt>>, i64, !idr.world) -> (!idr.own<!idr.data<@Opt>>, !idr.world)
    %w3 = func.call @write(%b, %i, %v, %w2) : (memref<?x!idr.data<@Opt>>, i64, !idr.own<!idr.data<@Opt>>, !idr.world) -> !idr.world
    idr.drop %a : !idr.own<memref<?x!idr.data<@Opt>>>
    return %w3 : !idr.world
  }
  func.func private @make(%n: i64, %x: !idr.own<!idr.data<@Opt>>, %w: !idr.world) -> (!idr.own<memref<?x!idr.data<@Opt>>>, !idr.world) {
    %a, %w1 = idr.array.new %n, %x, %w : !idr.own<!idr.data<@Opt>> -> !idr.own<memref<?x!idr.data<@Opt>>>
    return %a, %w1 : !idr.own<memref<?x!idr.data<@Opt>>>, !idr.world
  }
  func.func private @read(%a: memref<?x!idr.data<@Opt>>, %i: i64, %w: !idr.world) -> (!idr.own<!idr.data<@Opt>>, !idr.world) {
    %v, %w1 = idr.array.get %a[%i], %w : memref<?x!idr.data<@Opt>> -> !idr.own<!idr.data<@Opt>>
    return %v, %w1 : !idr.own<!idr.data<@Opt>>, !idr.world
  }
  func.func private @write(%a: memref<?x!idr.data<@Opt>>, %i: i64, %y: !idr.own<!idr.data<@Opt>>, %w: !idr.world) -> !idr.world {
    %w1 = idr.array.set %a[%i], %y, %w : memref<?x!idr.data<@Opt>>, !idr.own<!idr.data<@Opt>>
    return %w1 : !idr.world
  }
}
