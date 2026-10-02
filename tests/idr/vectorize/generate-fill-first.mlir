// RUN: idris-mlir-opt %s --idr-target --idr-lower --idr-vectorize --idr-expect=holds=vectorized -o /dev/null
// RUN: idris-mlir-cc %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: echo 10 | %t | FileCheck %s
// A generate's element 0 is its fill, and its body runs at every other
// index: of the squares with the fill 100, ten elements sum to
// 100 + 1 + 4 + ... + 81 = 385. A generate whose body is a fold over an
// array from outside likewise: with the fill 7 and each row i the sum of
// ten ones times i, the rows sum to 7 + 10 * (1 + ... + 9) = 457. Both
// loops run on the target's lanes, over a size the program reads, so their
// tiles are views of the elements from 1 on.
// CHECK: 385
// CHECK-NEXT: 457
module attributes {idr.program} {
  func.func @root(%w: !idr.world) -> !idr.world {
    %nl = arith.constant 10 : i32
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %seven = arith.constant 7 : i64
    %hundred = arith.constant 100 : i64
    %line, %w1 = idr.io.get_line %w
    %n = idr.str.to_int signed %line : i64
    %squares, %w2 = idr.array.generate %n, %hundred, %w1 : i64 -> memref<?xi64> (%i: i64) {
      %sq = arith.muli %i, %i : i64
      idr.yield %sq : i64
    }
    %s, %w3 = idr.array.fold %squares, %zero, %w2 : memref<?xi64>, i64 -> i64 (%acc: i64, %x: i64, %j: i64) {
      %t = arith.addi %acc, %x : i64
      idr.yield %t : i64
    }
    %w4 = idr.io.put_int signed %s, %w3 : i64
    %w5 = idr.io.put_char %nl, %w4
    %ones, %w6 = idr.array.new %n, %one, %w5 : i64 -> memref<?xi64>
    %rows, %w7 = idr.array.generate %n, %seven, %w6 : i64 -> memref<?xi64> (%i: i64) {
      %w0 = idr.world.new
      %row, %w8 = idr.array.fold %ones, %zero, %w0 : memref<?xi64>, i64 -> i64 (%acc: i64, %x: i64, %j: i64) {
        %xi = arith.muli %x, %i : i64
        %t = arith.addi %acc, %xi : i64
        idr.yield %t : i64
      }
      idr.yield %row : i64
    }
    %r, %w9 = idr.array.fold %rows, %zero, %w7 : memref<?xi64>, i64 -> i64 (%acc: i64, %x: i64, %j: i64) {
      %t = arith.addi %acc, %x : i64
      idr.yield %t : i64
    }
    %w10 = idr.io.put_int signed %r, %w9 : i64
    %w11 = idr.io.put_char %nl, %w10
    return %w11 : !idr.world
  }
}
