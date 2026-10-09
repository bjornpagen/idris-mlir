// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// RUN: idris-mlir-opt %s --idr-lower --convert-linalg-to-loops --canonicalize --cse --expand-strided-metadata --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts | FileCheck %s --check-prefix=LLVM
// A loop over an array's index space is one linalg.generic after lowering,
// over the array's memref view: a generated array is a new array, whose
// element 0 is the fill, and a parallel generic over the view of its
// elements from 1 on, writing each from linalg.index plus one; a fold is a
// reduction generic over the array into a slot of the function's frame
// (one alloca, at its entry), the init stored before and the result loaded
// after, the reduction dimension run in index order. A generate whose body
// is a fold over an array from outside is one generic of two dimensions,
// parallel then reduction, after a parallel one that writes each element's
// init, both over the elements from 1 on. A generate whose body reads
// arrays from outside at its own index (zipWith over frozen arrays) is two
// generics under one test that the arrays have the elements the loop
// reads: the first reads them as inputs, from element 1 as the loop does,
// and only computes, since that test proves each read's guard; the other
// reads them as written, each after its guard. No idr
// op is left; convert-linalg-to-loops then makes the loops of what is
// left, and the whole lowers to the LLVM dialect alone.
// CHECK-LABEL: func.func private @squares(
// CHECK: llvm.call @idris_rt_array_new(
// CHECK: linalg.generic
// CHECK-SAME: iterator_types = ["parallel"]
// CHECK-SAME: outs(%{{.*}} : memref<?xi64, strided<[1], offset: 1>>)
// CHECK: linalg.index 0
// CHECK: arith.muli
// CHECK: linalg.yield
// CHECK-NOT: idr.
// CHECK: return
// CHECK-LABEL: func.func private @total(
// CHECK: memref.alloca() : memref<i64>
// CHECK: memref.store
// CHECK: linalg.generic
// CHECK-SAME: iterator_types = ["reduction"]
// CHECK-SAME: ins(%{{.*}} : memref<?xi64>) outs(%{{.*}} : memref<i64>)
// CHECK: arith.addi
// CHECK: linalg.yield
// CHECK: memref.load
// CHECK-NOT: idr.
// CHECK: return
// CHECK-LABEL: func.func private @rows(
// CHECK: llvm.call @idris_rt_array_new(
// CHECK: linalg.generic
// CHECK-SAME: iterator_types = ["parallel"]
// CHECK: linalg.yield
// CHECK: linalg.generic
// CHECK-SAME: iterator_types = ["parallel", "reduction"]
// CHECK-SAME: ins(%{{.*}} : memref<?xf64>) outs(%{{.*}} : memref<?xf64, strided<[1], offset: 1>>)
// CHECK: linalg.index 0
// CHECK: linalg.index 1
// CHECK: arith.addf
// CHECK: linalg.yield
// CHECK-NOT: linalg.generic
// CHECK-NOT: idr.
// CHECK: return
// CHECK-LABEL: func.func private @zip(
// CHECK: arith.cmpi ule
// CHECK: arith.cmpi ule
// CHECK: scf.if
// CHECK: linalg.generic
// CHECK-SAME: ins(%{{.*}}, %{{.*}} : memref<?xf64, strided<[1], offset: 1>>, memref<?xf64, strided<[1], offset: 1>>)
// CHECK-NOT: llvm.call
// CHECK: arith.mulf
// CHECK: linalg.yield
// CHECK: } else {
// CHECK: linalg.generic
// CHECK: llvm.call @idris_rt_crash
// CHECK: arith.mulf
// CHECK-NOT: idr.
// CHECK: return
// LLVM-NOT: linalg.
// LLVM-NOT: memref.
// LLVM-NOT: unrealized_conversion_cast
// LLVM: llvm.func
// LLVM-NOT: linalg.
// LLVM-NOT: memref.
// LLVM-NOT: unrealized_conversion_cast
module attributes {idr.program} {
  func.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 4 : i64
    %a, %w1 = func.call @squares(%n, %w) : (i64, !idr.world) -> (memref<?xi64>, !idr.world)
    %s, %w2 = func.call @total(%a, %w1) : (memref<?xi64>, !idr.world) -> (i64, !idr.world)
    %v, %w3 = func.call @ones(%n, %w2) : (i64, !idr.world) -> (memref<?xf64>, !idr.world)
    %r, %w4 = func.call @rows(%n, %v, %w3) : (i64, memref<?xf64>, !idr.world) -> (memref<?xf64>, !idr.world)
    %z, %w5 = func.call @zip(%v, %r, %n, %w4) : (memref<?xf64>, memref<?xf64>, i64, !idr.world) -> (memref<?xf64>, !idr.world)
    return %w5 : !idr.world
  }
  // generate n (\i => i * i)
  func.func private @squares(%n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %zero = arith.constant 0 : i64
    %a, %w1 = idr.array.generate %n, %zero, %w : i64 -> memref<?xi64> (%i: i64) {
      %sq = arith.muli %i, %i : i64
      idr.yield %sq : i64
    }
    return %a, %w1 : memref<?xi64>, !idr.world
  }
  // foldl (+) 0
  func.func private @total(%a: memref<?xi64>, %w: !idr.world) -> (i64, !idr.world) {
    %zero = arith.constant 0 : i64
    %s, %w1 = idr.array.fold %a, %zero, %w : memref<?xi64>, i64 -> i64 (%acc: i64, %x: i64, %i: i64) {
      %t = arith.addi %acc, %x : i64
      idr.yield %t : i64
    }
    return %s, %w1 : i64, !idr.world
  }
  func.func private @ones(%n: i64, %w: !idr.world) -> (memref<?xf64>, !idr.world) {
    %one = arith.constant 1.0 : f64
    %a, %w1 = idr.array.new %n, %one, %w : f64 -> memref<?xf64>
    return %a, %w1 : memref<?xf64>, !idr.world
  }
  // generate n (\i => ifoldl (\acc, j, x => acc + x / (i + j + 1)) 0.0 v): each
  // element a row's reduction over v, the fold's world forged in the body.
  func.func private @rows(%n: i64, %v: memref<?xf64>, %w: !idr.world) -> (memref<?xf64>, !idr.world) {
    %zero = arith.constant 0.0 : f64
    %one = arith.constant 1 : i64
    %r, %w1 = idr.array.generate %n, %zero, %w : f64 -> memref<?xf64> (%i: i64) {
      %w0 = idr.world.new
      %i1 = arith.addi %i, %one : i64
      %s, %w2 = idr.array.fold %v, %zero, %w0 : memref<?xf64>, f64 -> f64 (%acc: f64, %x: f64, %j: i64) {
        %ij = arith.addi %i1, %j : i64
        %d = arith.sitofp %ij : i64 to f64
        %m = arith.divf %x, %d : f64
        %t = arith.addf %acc, %m : f64
        idr.yield %t : f64
      }
      idr.yield %s : f64
    }
    return %r, %w1 : memref<?xf64>, !idr.world
  }
  // zipWith (*) u v: each element the product of u's and v's at its index.
  func.func private @zip(%u: memref<?xf64>, %v: memref<?xf64>, %n: i64, %w: !idr.world) -> (memref<?xf64>, !idr.world) {
    %zero = arith.constant 0.0 : f64
    %r, %w1 = idr.array.generate %n, %zero, %w : f64 -> memref<?xf64> (%i: i64) {
      %w0 = idr.world.new
      %c0 = arith.constant 0 : index
      %du = memref.dim %u, %c0 : memref<?xf64>
      %nu = arith.index_cast %du : index to i64
      %iu = idr.check.in_bounds %i, %nu, "array index out of bounds"
      %x, %w2 = idr.array.get %u[%iu], %w0 : memref<?xf64> -> f64
      %w3 = idr.world.new
      %dv = memref.dim %v, %c0 : memref<?xf64>
      %nv = arith.index_cast %dv : index to i64
      %iv = idr.check.in_bounds %i, %nv, "array index out of bounds"
      %y, %w4 = idr.array.get %v[%iv], %w3 : memref<?xf64> -> f64
      %p = arith.mulf %x, %y : f64
      idr.yield %p : f64
    }
    return %r, %w1 : memref<?xf64>, !idr.world
  }
}
