// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// An upstream op stands only where the specification admits it: an
// admitted op at the stages its record gives it, and, while the program is
// as the frontend wrote it, no op no list names. A program past the
// frontend's stage is a pass's output, held by the verifier that runs
// after every pass. At the first stage an array's size, a buffer
// allocated, a static buffer and a view of a buffer all stand: the size
// until bufferization, the allocation and the static buffer from it on,
// and the view, which upstream's models make and no list names, at any
// stage past the frontend's. An array's size at the graded stage, past
// bufferization, is refused at the op; so are an allocation and a static
// buffer at the higher stage, before it, and a view there, where every
// upstream op is admitted. A lowered program is upstream's, and no list
// holds there.
idr.program @stages root(@main) stage(first) {
  memref.global "private" constant @table : memref<2xi64> = dense<[1, 2]>
  idr.func @main() {
    idr.return
  }
  idr.func @size(%v: tensor<?xi64>) -> index {
    %zero = arith.constant 0 : index
    %n = tensor.dim %v, %zero : tensor<?xi64>
    idr.return %n : index
  }
  idr.func @fresh() -> memref<4xi64> {
    %b = memref.alloc() : memref<4xi64>
    idr.return %b : memref<4xi64>
  }
  idr.func @view(%b: memref<4xi64>) {
    %v = memref.subview %b[1] [2] [1] : memref<4xi64> to memref<2xi64, strided<[1], offset: 1>>
    idr.return
  }
}

// -----

idr.program @stages root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @size(%v: tensor<?xi64>) -> index {
    %zero = arith.constant 0 : index
    // expected-error @below {{}}
    %n = tensor.dim %v, %zero : tensor<?xi64>
    idr.return %n : index
  }
}

// -----

idr.program @stages root(@main) stage(higher) {
  idr.func @main() {
    idr.return
  }
  idr.func @fresh() -> memref<4xi64> {
    // expected-error @below {{}}
    %b = memref.alloc() : memref<4xi64>
    idr.return %b : memref<4xi64>
  }
}

// -----

idr.program @stages root(@main) stage(higher) {
  // expected-error @below {{}}
  memref.global "private" constant @table : memref<2xi64> = dense<[1, 2]>
  idr.func @main() {
    idr.return
  }
}

// -----

idr.program @stages root(@main) stage(higher) {
  idr.func @main() {
    idr.return
  }
  idr.func @view(%b: memref<4xi64>) {
    // expected-error @below {{}}
    %v = memref.subview %b[1] [2] [1] : memref<4xi64> to memref<2xi64, strided<[1], offset: 1>>
    idr.return
  }
}

// -----

idr.program @stages root(@main) stage(lowered) {
  memref.global "private" constant @table : memref<2xi64> = dense<[1, 2]>
  llvm.func @main() {
    %e = tensor.empty() : tensor<2xi64>
    llvm.return
  }
}
