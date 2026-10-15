// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// RUN: idris-mlir-opt %s --idr-lower --canonicalize --cse --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts | FileCheck %s --check-prefix=LLVM
// NEEDS-ACCEPTANCE: the components of a world-ordered array in a lowered signature (cell, first element, size), as C16 section 3 orders them.
// An array a world orders is one runtime cell, allocated by
// idris_rt_array_new with the element layout in its header; its value is
// the descriptor's components, the cell, its first element and its size,
// and memref.dim is the size, no load. A new array writes the fill into
// every element, each taking a reference, and drops the fill's own. The
// guard of a read's index tests it against the size, a register and no
// load from the cell, and crashes when it is out of bounds; the read then
// tests nothing, and gives the element a reference of its own. A write's
// guard tests likewise; the write drops the old element's reference and
// stores the new one. An unboxed sum element is its slots, counted first.
// An element of one uncounted word (a double here) is a slot of its own,
// read and written at its address as every element is, so one path
// serves every element, and nothing of memref is left.
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
// CHECK: return %[[A]], %{{.*}}, %[[L]]
// CHECK-LABEL: func.func private @read(
// CHECK-SAME: %[[B:[^:]*]]: !llvm.ptr, %[[BA:[^:]*]]: !llvm.ptr, %[[BL:[^:]*]]: i64, %[[I:[^:]*]]: i64)
// CHECK-NOT: llvm.load
// CHECK: %[[BD:.*]] = arith.index_cast %[[BL]] : i64 to index
// CHECK: %[[BN:.*]] = arith.index_cast %[[BD]] : index to i64
// CHECK: %[[OUT:.*]] = arith.cmpi uge, %[[I]], %[[BN]] : i64
// CHECK: scf.if %[[OUT]] {
// CHECK: llvm.call @idris_rt_crash(
// CHECK: }
// CHECK-NOT: idris_rt_crash
// CHECK: %[[P:.*]] = llvm.load %{{.*}} : !llvm.ptr -> !llvm.ptr
// CHECK: llvm.call @idris_rt_inc(%[[P]])
// CHECK-LABEL: func.func private @write(
// CHECK-SAME: %[[C:[^:]*]]: !llvm.ptr, %[[CA:[^:]*]]: !llvm.ptr, %[[CL:[^:]*]]: i64, %[[J:[^:]*]]: i64,
// CHECK-NOT: llvm.load
// CHECK: %[[CD:.*]] = arith.index_cast %[[CL]] : i64 to index
// CHECK: %[[CN:.*]] = arith.index_cast %[[CD]] : index to i64
// CHECK: arith.cmpi uge, %[[J]], %[[CN]] : i64
// CHECK: llvm.call @idris_rt_crash(
// CHECK-NOT: idris_rt_crash
// CHECK: %[[OLD:.*]] = llvm.load %{{.*}} : !llvm.ptr -> !llvm.ptr
// CHECK: llvm.call @idris_rt_dec(%[[OLD]])
// CHECK: llvm.store
// CHECK-LABEL: func.func private @length(
// CHECK-SAME: %[[D:[^:]*]]: !llvm.ptr, %[[DA:[^:]*]]: !llvm.ptr, %[[DL:[^:]*]]: i64)
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
// CHECK: llvm.store %{{.*}}, %{{.*}} : f64, !llvm.ptr
// CHECK-NOT: idris_rt_inc
// CHECK-NOT: idris_rt_dec
// CHECK: return
// CHECK-LABEL: func.func private @readD(
// CHECK-SAME: %[[E:[^:]*]]: !llvm.ptr, %[[EA:[^:]*]]: !llvm.ptr, %[[EL:[^:]*]]: i64, %[[K:[^:]*]]: i64)
// CHECK-NOT: llvm.load
// CHECK: %[[ED:.*]] = arith.index_cast %[[EL]] : i64 to index
// CHECK: %[[EN:.*]] = arith.index_cast %[[ED]] : index to i64
// CHECK: arith.cmpi uge, %[[K]], %[[EN]] : i64
// CHECK: llvm.call @idris_rt_crash(
// CHECK-NOT: idris_rt_crash
// CHECK: llvm.load %{{.*}} : !llvm.ptr -> f64
// CHECK-NOT: memref.
// CHECK: return
// CHECK-LABEL: func.func private @writeD(
// CHECK-NOT: llvm.load
// CHECK: arith.cmpi uge
// CHECK: llvm.call @idris_rt_crash(
// CHECK-NOT: idris_rt_crash
// CHECK: llvm.store %{{.*}}, %{{.*}} : f64, !llvm.ptr
// CHECK-NOT: memref.
// CHECK: return
// An IORef is an array of rank 0: the cell of one element and its first
// element, and no size, since it has none to carry.
// CHECK-LABEL: func.func private @makeRef(
// CHECK: %[[ONE:.*]] = arith.constant 1 : i64
// CHECK: %[[R:.*]] = llvm.call @idris_rt_array_new(%[[ONE]], %{{.*}}) : (i64, i32) -> {{.*}}!llvm.ptr
// CHECK: return %[[R]], %{{.*}} : !llvm.ptr, !llvm.ptr
// A read takes a reference of its own.
// CHECK-LABEL: func.func private @readRef(
// CHECK: llvm.call @idris_rt_inc(
// A read that moves the element out takes the array's reference instead,
// and leaves its place null for the write that follows.
// CHECK-LABEL: func.func private @takeRef(
// CHECK-NOT: idris_rt_inc
// CHECK: %[[Z:.*]] = llvm.mlir.zero : !llvm.ptr
// CHECK-NOT: idris_rt_inc
// CHECK: llvm.store %[[Z]], %
// CHECK-NOT: idris_rt_inc
// CHECK: return
// A word of an IORef is read at its one element's address, with no index.
// CHECK-LABEL: func.func private @readRefD(
// CHECK: llvm.load %{{.*}} : !llvm.ptr -> f64
// CHECK: return
// LLVM-NOT: unrealized_conversion_cast
// LLVM-NOT: memref.
// LLVM: llvm.getelementptr
// LLVM-NOT: unrealized_conversion_cast
// LLVM-NOT: memref.
!Opt = !idr.data<"Opt", plain [@None(), @Some(!idr.str)]>
module {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 3 : i64
    %i = arith.constant 1 : i64
    %x = idr.con @None() : () -> !idr.own<!Opt>
    %a, %w1 = idr.call @make(%n, %x, %w) : (i64, !idr.own<!Opt>, !idr.world) -> (!idr.own<memref<?x!Opt, #idr.world>>, !idr.world)
    %b = idr.borrow %a : !idr.own<memref<?x!Opt, #idr.world>>
    %v, %w2 = idr.call @read(%b, %i, %w1) : (memref<?x!Opt, #idr.world>, i64, !idr.world) -> (!idr.own<!Opt>, !idr.world)
    %w3 = idr.call @write(%b, %i, %v, %w2) : (memref<?x!Opt, #idr.world>, i64, !idr.own<!Opt>, !idr.world) -> !idr.world
    %l = idr.call @length(%b) : (memref<?x!Opt, #idr.world>) -> index
    idr.drop %a : !idr.own<memref<?x!Opt, #idr.world>>
    %d = arith.constant 1.5 : f64
    %e, %w4 = idr.call @makeD(%n, %d, %w3) : (i64, f64, !idr.world) -> (!idr.own<memref<?xf64, #idr.world>>, !idr.world)
    %eb = idr.borrow %e : !idr.own<memref<?xf64, #idr.world>>
    %y, %w5 = idr.call @readD(%eb, %i, %w4) : (memref<?xf64, #idr.world>, i64, !idr.world) -> (f64, !idr.world)
    %w6 = idr.call @writeD(%eb, %i, %y, %w5) : (memref<?xf64, #idr.world>, i64, f64, !idr.world) -> !idr.world
    idr.drop %e : !idr.own<memref<?xf64, #idr.world>>
    return %w6 : !idr.world
  }
  idr.func private @make(%n: i64, %x: !idr.own<!Opt>, %w: !idr.world) -> (!idr.own<memref<?x!Opt, #idr.world>>, !idr.world) {
    %a, %w1 = idr.array.new [%n], %x, %w : !idr.own<!Opt> -> !idr.own<memref<?x!Opt, #idr.world>>
    return %a, %w1 : !idr.own<memref<?x!Opt, #idr.world>>, !idr.world
  }
  idr.func private @read(%a: memref<?x!Opt, #idr.world>, %i: i64, %w: !idr.world) -> (!idr.own<!Opt>, !idr.world) {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?x!Opt, #idr.world>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %n, "array index out of bounds"
    %v, %w1 = idr.array.get %a[%j], %w : memref<?x!Opt, #idr.world> -> !idr.own<!Opt>
    return %v, %w1 : !idr.own<!Opt>, !idr.world
  }
  idr.func private @write(%a: memref<?x!Opt, #idr.world>, %i: i64, %y: !idr.own<!Opt>, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?x!Opt, #idr.world>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %n, "array index out of bounds"
    %w1 = idr.array.set %a[%j], %y, %w : memref<?x!Opt, #idr.world>, !idr.own<!Opt>
    return %w1 : !idr.world
  }
  idr.func private @length(%a: memref<?x!Opt, #idr.world>) -> index {
    %c0 = arith.constant 0 : index
    %n = memref.dim %a, %c0 : memref<?x!Opt, #idr.world>
    return %n : index
  }
  idr.func private @bytes(%n: i64, %w: !idr.world) -> (!idr.own<memref<?xi8, #idr.world>>, !idr.world) {
    %z = arith.constant 0 : i8
    %a, %w1 = idr.array.new [%n], %z, %w : i8 -> !idr.own<memref<?xi8, #idr.world>>
    return %a, %w1 : !idr.own<memref<?xi8, #idr.world>>, !idr.world
  }
  idr.func private @makeD(%n: i64, %x: f64, %w: !idr.world) -> (!idr.own<memref<?xf64, #idr.world>>, !idr.world) {
    %a, %w1 = idr.array.new [%n], %x, %w : f64 -> !idr.own<memref<?xf64, #idr.world>>
    return %a, %w1 : !idr.own<memref<?xf64, #idr.world>>, !idr.world
  }
  idr.func private @readD(%a: memref<?xf64, #idr.world>, %i: i64, %w: !idr.world) -> (f64, !idr.world) {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xf64, #idr.world>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %n, "array index out of bounds"
    %v, %w1 = idr.array.get %a[%j], %w : memref<?xf64, #idr.world> -> f64
    return %v, %w1 : f64, !idr.world
  }
  idr.func private @writeD(%a: memref<?xf64, #idr.world>, %i: i64, %y: f64, %w: !idr.world) -> !idr.world {
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xf64, #idr.world>
    %n = arith.index_cast %d : index to i64
    %j = idr.check.in_bounds %i, %n, "array index out of bounds"
    %w1 = idr.array.set %a[%j], %y, %w : memref<?xf64, #idr.world>, f64
    return %w1 : !idr.world
  }
  idr.func private @makeRef(%x: !idr.own<!Opt>, %w: !idr.world) -> (!idr.own<memref<!Opt, #idr.world>>, !idr.world) {
    %r, %w1 = idr.array.new [], %x, %w : !idr.own<!Opt> -> !idr.own<memref<!Opt, #idr.world>>
    return %r, %w1 : !idr.own<memref<!Opt, #idr.world>>, !idr.world
  }
  idr.func private @readRef(%r: memref<!Opt, #idr.world>, %w: !idr.world) -> (!idr.own<!Opt>, !idr.world) {
    %v, %w1 = idr.array.get %r[], %w : memref<!Opt, #idr.world> -> !idr.own<!Opt>
    return %v, %w1 : !idr.own<!Opt>, !idr.world
  }
  idr.func private @takeRef(%r: memref<!Opt, #idr.world>, %y: !idr.own<!Opt>, %w: !idr.world) -> (!idr.own<!Opt>, !idr.world) {
    %v, %w1 = idr.array.get %r[], %w moves : memref<!Opt, #idr.world> -> !idr.own<!Opt>
    %w2 = idr.array.set %r[], %y, %w1 : memref<!Opt, #idr.world>, !idr.own<!Opt>
    return %v, %w2 : !idr.own<!Opt>, !idr.world
  }
  idr.func private @readRefD(%r: memref<f64, #idr.world>, %w: !idr.world) -> (f64, !idr.world) {
    %v, %w1 = idr.array.get %r[], %w : memref<f64, #idr.world> -> f64
    return %v, %w1 : f64, !idr.world
  }
}
