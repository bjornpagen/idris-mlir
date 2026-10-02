// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// RUN: idris-mlir-opt %s --idr-lower --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts | FileCheck %s --check-prefix=LLVM
// An array is one runtime cell, allocated by idris_rt_array_new with the
// element layout in its header, and beside the cell its length: an array
// value is that pair, and memref.dim is the length, no load. A new array
// writes the fill into every element, each taking a reference, and drops
// the fill's own. A read checks the index against the length, two
// registers and no load from the cell, crashes when it is out of bounds,
// and gives the element a reference of its own. A write checks likewise,
// drops the old element's reference and stores the new one. An unboxed sum
// element is its slots, counted first. An element of one uncounted word (a
// double here) is read and written as a memref's element instead: the
// array's view is a descriptor over the cell, and the load and the store
// are memref's, which convert-to-llvm addresses, leaving no cast and no
// memref op behind.
// CHECK-LABEL: func.func private @make(
// CHECK-SAME: %[[N:[^:]*]]: i64, %[[T:[^:]*]]: i8 {{.*}}, %[[S:[^:]*]]: !llvm.ptr)
// CHECK: %[[L:.*]] = arith.maxsi %[[N]], %{{.*}} : i64
// CHECK: %[[A:.*]] = llvm.call @idris_rt_array_new(%[[L]], %{{.*}}) : (i64, i32) -> {{.*}}!llvm.ptr
// CHECK: scf.for
// CHECK-DAG: llvm.store %[[S]]
// CHECK-DAG: llvm.store %[[T]]
// CHECK: llvm.call @idris_rt_inc(%[[S]])
// CHECK: }
// CHECK: llvm.call @idris_rt_dec(%[[S]])
// CHECK: return %[[A]], %[[L]]
// CHECK-LABEL: func.func private @read(
// CHECK-SAME: %[[B:[^:]*]]: !llvm.ptr, %[[BL:[^:]*]]: i64, %[[I:[^:]*]]: i64)
// CHECK-NOT: llvm.load
// CHECK: %[[OUT:.*]] = llvm.icmp "uge" %[[I]], %[[BL]]
// CHECK: scf.if %[[OUT]] {
// CHECK: llvm.call @idris_rt_crash(
// CHECK: }
// CHECK: %[[P:.*]] = llvm.load %{{.*}} : !llvm.ptr -> !llvm.ptr
// CHECK: llvm.call @idris_rt_inc(%[[P]])
// CHECK-LABEL: func.func private @write(
// CHECK-SAME: %[[C:[^:]*]]: !llvm.ptr, %[[CL:[^:]*]]: i64, %[[J:[^:]*]]: i64,
// CHECK-NOT: llvm.load
// CHECK: llvm.icmp "uge" %[[J]], %[[CL]]
// CHECK: llvm.call @idris_rt_crash(
// CHECK: %[[OLD:.*]] = llvm.load %{{.*}} : !llvm.ptr -> !llvm.ptr
// CHECK: llvm.call @idris_rt_dec(%[[OLD]])
// CHECK: llvm.store
// CHECK-LABEL: func.func private @length(
// CHECK-SAME: %[[D:[^:]*]]: !llvm.ptr, %[[DL:[^:]*]]: i64)
// CHECK-NOT: llvm.load
// CHECK: %[[X:.*]] = arith.index_cast %[[DL]] : i64 to index
// CHECK: return %[[X]]
// A byte element takes one byte: the cell's header says the stride is 1
// (the tag bits) with no object slot, and kind array (4 << 24).
// CHECK-LABEL: func.func private @bytes(
// CHECK: %[[INFO:.*]] = llvm.mlir.constant(67108865 : i32) : i32
// CHECK: llvm.call @idris_rt_array_new(%{{.*}}, %[[INFO]])
// CHECK-LABEL: func.func private @makeD(
// CHECK: llvm.call @idris_rt_array_new(
// CHECK: scf.for
// CHECK: memref.store %{{.*}}, %{{.*}} : memref<?xf64>
// CHECK-NOT: idris_rt_inc
// CHECK-NOT: idris_rt_dec
// CHECK: return
// CHECK-LABEL: func.func private @readD(
// CHECK-SAME: %[[E:[^:]*]]: !llvm.ptr, %[[EL:[^:]*]]: i64, %[[K:[^:]*]]: i64)
// CHECK-NOT: llvm.load
// CHECK: llvm.icmp "uge" %[[K]], %[[EL]]
// CHECK: llvm.call @idris_rt_crash(
// CHECK: %[[V:.*]] = builtin.unrealized_conversion_cast %{{.*}} : !llvm.struct<(ptr, ptr, i64, array<1 x i64>, array<1 x i64>)> to memref<?xf64>
// CHECK: memref.load %[[V]][%{{.*}}] : memref<?xf64>
// CHECK-NOT: llvm.load
// CHECK: return
// CHECK-LABEL: func.func private @writeD(
// CHECK-NOT: llvm.load
// CHECK: llvm.icmp "uge"
// CHECK: llvm.call @idris_rt_crash(
// CHECK: memref.store %{{.*}}, %{{.*}}[%{{.*}}] : memref<?xf64>
// CHECK-NOT: llvm.store
// CHECK: return
// LLVM-NOT: unrealized_conversion_cast
// LLVM-NOT: memref.
// LLVM: llvm.getelementptr
// LLVM-NOT: unrealized_conversion_cast
// LLVM-NOT: memref.
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
    %l = func.call @length(%b) : (memref<?x!idr.data<@Opt>>) -> index
    idr.drop %a : !idr.own<memref<?x!idr.data<@Opt>>>
    %d = arith.constant 1.5 : f64
    %e, %w4 = func.call @makeD(%n, %d, %w3) : (i64, f64, !idr.world) -> (!idr.own<memref<?xf64>>, !idr.world)
    %eb = idr.borrow %e : !idr.own<memref<?xf64>>
    %y, %w5 = func.call @readD(%eb, %i, %w4) : (memref<?xf64>, i64, !idr.world) -> (f64, !idr.world)
    %w6 = func.call @writeD(%eb, %i, %y, %w5) : (memref<?xf64>, i64, f64, !idr.world) -> !idr.world
    idr.drop %e : !idr.own<memref<?xf64>>
    return %w6 : !idr.world
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
  func.func private @length(%a: memref<?x!idr.data<@Opt>>) -> index {
    %c0 = arith.constant 0 : index
    %n = memref.dim %a, %c0 : memref<?x!idr.data<@Opt>>
    return %n : index
  }
  func.func private @bytes(%n: i64, %w: !idr.world) -> (!idr.own<memref<?xi8>>, !idr.world) {
    %z = arith.constant 0 : i8
    %a, %w1 = idr.array.new %n, %z, %w : i8 -> !idr.own<memref<?xi8>>
    return %a, %w1 : !idr.own<memref<?xi8>>, !idr.world
  }
  func.func private @makeD(%n: i64, %x: f64, %w: !idr.world) -> (!idr.own<memref<?xf64>>, !idr.world) {
    %a, %w1 = idr.array.new %n, %x, %w : f64 -> !idr.own<memref<?xf64>>
    return %a, %w1 : !idr.own<memref<?xf64>>, !idr.world
  }
  func.func private @readD(%a: memref<?xf64>, %i: i64, %w: !idr.world) -> (f64, !idr.world) {
    %v, %w1 = idr.array.get %a[%i], %w : memref<?xf64> -> f64
    return %v, %w1 : f64, !idr.world
  }
  func.func private @writeD(%a: memref<?xf64>, %i: i64, %y: f64, %w: !idr.world) -> !idr.world {
    %w1 = idr.array.set %a[%i], %y, %w : memref<?xf64>, f64
    return %w1 : !idr.world
  }
}
