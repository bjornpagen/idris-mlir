// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A tie names one size for each dynamic dimension of its array, an array
// is a ranked tensor or a buffer, and an array a world orders is no value
// to tie: its sizes are the runtime's record of its allocation, and no
// two of them are proved equal by a type. The last two are the operand's
// type constraint, whose words are ODS's, so only the operand is matched.

idr.program @verify root(@root) stage(first) types #idr.types<> {
  idr.func @f(%x: tensor<?x?xi64>, %n: index) -> tensor<?x?xi64> {
    // expected-error @+1 {{dynamic dimensions}}
    %y = idr.tie_shape %x dims(%n) : tensor<?x?xi64>
    return %y : tensor<?x?xi64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @verify root(@root) stage(first) types #idr.types<> {
  idr.func @f(%x: tensor<4xi64>, %n: index) -> tensor<4xi64> {
    // expected-error @+1 {{dynamic dimensions}}
    %y = idr.tie_shape %x dims(%n) : tensor<4xi64>
    return %y : tensor<4xi64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @verify root(@root) stage(first) types #idr.types<> {
  idr.func @f(%a: memref<?xi64, #idr.world>, %n: index) -> memref<?xi64, #idr.world> {
    // expected-error @+1 {{operand #0 must be}}
    %y = idr.tie_shape %a dims(%n) : memref<?xi64, #idr.world>
    return %y : memref<?xi64, #idr.world>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @verify root(@root) stage(first) types #idr.types<> {
  idr.func @f(%x: tensor<*xi64>, %n: index) -> tensor<*xi64> {
    // expected-error @+1 {{operand #0 must be}}
    %y = idr.tie_shape %x dims(%n) : tensor<*xi64>
    return %y : tensor<*xi64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// What the verifier accepts, the nearest each refusal above has: a size
// per dynamic dimension, two for two, a static one taking none, so an
// array of static shape takes no size, on a ranked tensor or a value
// buffer.
idr.program @verify root(@root) stage(first) types #idr.types<> {
  idr.func @f(%x: tensor<4x?xi64>, %b: memref<?x?xf64>, %z: tensor<?x?xi64>, %k: tensor<4xi64>, %n: index, %m: index) -> (tensor<4x?xi64>, memref<?x?xf64>) {
    %y = idr.tie_shape %x dims(%n) : tensor<4x?xi64>
    %c = idr.tie_shape %b dims(%n, %m) : memref<?x?xf64>
    %t = idr.tie_shape %z dims(%n, %m) : tensor<?x?xi64>
    %s = idr.tie_shape %k dims() : tensor<4xi64>
    return %y, %c : tensor<4x?xi64>, memref<?x?xf64>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
