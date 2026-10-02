// RUN: idris-mlir-opt %s --idr-target --idr-lower --idr-vectorize --idr-narrow-lanes --canonicalize --cse | FileCheck %s
// RUN: idris-mlir-opt %s --idr-target --idr-lower --idr-vectorize --idr-narrow-lanes --idr-expect=holds=narrowed-lanes=@rows,narrowed-lanes=@squares -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-target --idr-lower --idr-vectorize --idr-narrow-lanes --idr-expect=holds=narrowed-lanes=@eighth -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=WIDE < %t.err
// RUN: %status 1 idris-mlir-opt %s --idr-target --idr-lower --idr-vectorize --idr-narrow-lanes --idr-expect=holds=narrowed-lanes=@inexact -o /dev/null 2> %t.inexact
// RUN: FileCheck %s --check-prefix=INEXACT < %t.inexact
// RUN: idris-mlir-opt %s --idr-target --idr-pipeline | FileCheck %s --check-prefix=LLVM
// After idr-narrow-lanes a vectorized loop whose body computes on the
// 64-bit index has two versions: when the sizes it reads are at most a
// bound (one test on entry), a copy whose integer lanes are i32, the
// sizes behind arith.minui so that the analysis knows the bound, its
// conversion to double from the i32 word and marked non-negative (the
// signed conversion is the one the target has for 32-bit lanes);
// otherwise the loop as it was, on i64 lanes (and the loop of the last
// tile, which runs once, keeps its i64 lanes). The bound is the body's:
// the squares fit i32 below 2^15, the rows' (i + j) * (i + j + 1) below
// 2^14, its division by 2 floored as Idris's `div` is (a signed
// remainder by 2 included). A body no bound above 2^8 makes fit (the
// eighth power) stays one loop on 64-bit lanes, and so does each body
// whose ops fit but whose 32-bit forms would compute something else
// (@inexact): a shift by up to 40, poison on i32; a signed remainder
// that sees INT32_MIN % -1 at index 0, which overflows on i32; an
// unsigned remainder of a word that is negative at indices 0 and 1, read
// as another number on i32. The whole pipeline reaches the LLVM dialect
// with the 32-bit lanes in it.
// CHECK-LABEL: func.func private @squares(
// CHECK: arith.cmpi ule
// CHECK: scf.if
// CHECK: arith.minui
// CHECK: scf.for
// CHECK-NOT: arith.muli {{.*}} : vector<4xi64>
// CHECK: arith.muli {{.*}} : vector<4xi32>
// CHECK: arith.extui {{.*}} nneg : vector<4xi32> to vector<4xi64>
// CHECK: vector.transfer_write {{.*}} : vector<4xi64>
// CHECK-NOT: arith.muli {{.*}} : vector<4xi64>
// CHECK: } else {
// CHECK: scf.for
// CHECK: arith.muli {{.*}} : vector<4xi64>
// CHECK: return
// CHECK-LABEL: func.func private @eighth(
// CHECK-NOT: scf.if
// CHECK: arith.muli {{.*}} : vector<4xi64>
// CHECK-NOT: scf.if
// CHECK: return
// CHECK-LABEL: func.func private @inexact(
// CHECK-NOT: scf.if
// CHECK: arith.shrui {{.*}} : vector<4xi64>
// CHECK-NOT: scf.if
// CHECK: arith.remsi {{.*}} : vector<4xi64>
// CHECK-NOT: scf.if
// CHECK: arith.remui {{.*}} : vector<4xi64>
// CHECK-NOT: scf.if
// CHECK: return
// CHECK-LABEL: func.func private @rows(
// CHECK: arith.cmpi ule
// CHECK: scf.if
// CHECK: arith.minui
// CHECK: scf.for
// CHECK: scf.for
// CHECK-NOT: arith.muli {{.*}} : vector<4xi64>
// CHECK: arith.muli {{.*}} : vector<4xi32>
// CHECK: arith.remsi {{.*}} : vector<4xi32>
// CHECK: arith.uitofp {{.*}} nneg : vector<4xi32> to vector<4xf64>
// CHECK: arith.divf {{.*}} : vector<4xf64>
// CHECK-NOT: arith.muli {{.*}} : vector<4xi64>
// CHECK: } else {
// CHECK: scf.for
// CHECK: scf.for
// CHECK: arith.muli {{.*}} : vector<4xi64>
// CHECK: arith.sitofp {{.*}} : vector<4xi64> to vector<4xf64>
// CHECK: return
// WIDE: error: expected narrowed-lanes: a loop computes integer lanes of 64 bits with no 32-bit version in @eighth
// INEXACT: error: expected narrowed-lanes: a loop computes integer lanes of 64 bits with no 32-bit version in @inexact
// LLVM-NOT: vector.
// LLVM-NOT: affine.
// LLVM-NOT: linalg.
// LLVM: llvm.mul %{{.*}} : vector<4xi32>
// LLVM: llvm.uitofp nneg %{{.*}} : vector<4xi32> to vector<4xf64>
// LLVM: llvm.store %{{.*}} : vector<4xf64>, !llvm.ptr
// LLVM-NOT: vector.
// LLVM-NOT: affine.
// LLVM-NOT: linalg.
module attributes {idr.program} {
  func.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 7 : i64
    %a, %w1 = func.call @squares(%n, %w) : (i64, !idr.world) -> (memref<?xi64>, !idr.world)
    %b, %w2 = func.call @eighth(%n, %w1) : (i64, !idr.world) -> (memref<?xi64>, !idr.world)
    %c, %w3 = func.call @inexact(%n, %w2) : (i64, !idr.world) -> (memref<?xi64>, !idr.world)
    %v, %w4 = func.call @ones(%n, %w3) : (i64, !idr.world) -> (memref<?xf64>, !idr.world)
    %r, %w5 = func.call @rows(%n, %v, %w4) : (i64, memref<?xf64>, !idr.world) -> (memref<?xf64>, !idr.world)
    return %w5 : !idr.world
  }
  func.func private @squares(%n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %zero = arith.constant 0 : i64
    %a, %w1 = idr.array.generate %n, %zero, %w : i64 -> memref<?xi64> (%i: i64) {
      %sq = arith.muli %i, %i : i64
      idr.yield %sq : i64
    }
    return %a, %w1 : memref<?xi64>, !idr.world
  }
  func.func private @eighth(%n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %zero = arith.constant 0 : i64
    %a, %w1 = idr.array.generate %n, %zero, %w : i64 -> memref<?xi64> (%i: i64) {
      %sq = arith.muli %i, %i : i64
      %fourth = arith.muli %sq, %sq : i64
      %eighth = arith.muli %fourth, %fourth : i64
      idr.yield %eighth : i64
    }
    return %a, %w1 : memref<?xi64>, !idr.world
  }
  func.func private @inexact(%n: i64, %w: !idr.world) -> (memref<?xi64>, !idr.world) {
    %zero = arith.constant 0 : i64
    %c41 = arith.constant 41 : i64
    %min = arith.constant -2147483648 : i64
    %m1 = arith.constant -1 : i64
    %two = arith.constant 2 : i64
    %seven = arith.constant 7 : i64
    %a, %w1 = idr.array.generate %n, %zero, %w : i64 -> memref<?xi64> (%i: i64) {
      %s = arith.remui %i, %c41 : i64
      %r = arith.shrui %i, %s : i64
      idr.yield %r : i64
    }
    %b, %w2 = idr.array.generate %n, %zero, %w1 : i64 -> memref<?xi64> (%i: i64) {
      %x = arith.addi %i, %min : i64
      %d = arith.subi %m1, %i : i64
      %r = arith.remsi %x, %d : i64
      idr.yield %r : i64
    }
    %c, %w3 = idr.array.generate %n, %zero, %w2 : i64 -> memref<?xi64> (%i: i64) {
      %x = arith.subi %i, %two : i64
      %r = arith.remui %x, %seven : i64
      idr.yield %r : i64
    }
    return %c, %w3 : memref<?xi64>, !idr.world
  }
  func.func private @ones(%n: i64, %w: !idr.world) -> (memref<?xf64>, !idr.world) {
    %one = arith.constant 1.0 : f64
    %a, %w1 = idr.array.new %n, %one, %w : f64 -> memref<?xf64>
    return %a, %w1 : memref<?xf64>, !idr.world
  }
  func.func private @rows(%n: i64, %v: memref<?xf64>, %w: !idr.world) -> (memref<?xf64>, !idr.world) {
    %zero = arith.constant 0.0 : f64
    %zeroi = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %unit = arith.constant 1.0 : f64
    %r, %w1 = idr.array.generate %n, %zero, %w : f64 -> memref<?xf64> (%i: i64) {
      %w0 = idr.world.new
      %i1 = arith.addi %i, %one : i64
      %s, %w2 = idr.array.fold %v, %zero, %w0 : memref<?xf64>, f64 -> f64 (%acc: f64, %x: f64, %j: i64) {
        %ij = arith.addi %i, %j : i64
        %ij1 = arith.addi %ij, %one : i64
        %p = arith.muli %ij, %ij1 : i64
        %q = arith.divsi %p, %two : i64
        %rem = arith.remsi %p, %two : i64
        %below = arith.cmpi slt, %rem, %zeroi : i64
        %down = arith.subi %q, %one : i64
        %h = arith.select %below, %down, %q : i64
        %k = arith.addi %h, %i1 : i64
        %d = arith.sitofp %k : i64 to f64
        %e = arith.divf %unit, %d : f64
        %m = arith.mulf %e, %x : f64
        %t = arith.addf %acc, %m : f64
        idr.yield %t : f64
      }
      idr.yield %s : f64
    }
    return %r, %w1 : memref<?xf64>, !idr.world
  }
}
