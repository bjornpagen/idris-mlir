// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// idr-structure-loops gives linalg only arrays of words, and the program's
// verifier holds every pass to that from the first stage on: counting meets
// buffers only at their loads, stores and allocations, never inside a
// payload, whose arguments take no grade. A loop of linalg's over strings is
// no program; the same loop over words, the nearest one that is, verifies.
idr.program @counted root(@root) stage(first) types #idr.types<> {
  idr.func @copy(%a: memref<4x!idr.str>, %b: memref<4x!idr.str>) -> i64 {
    // expected-error @below {{an element no linalg op reads or writes}}
    linalg.generic {indexing_maps = [affine_map<(d0) -> (d0)>, affine_map<(d0) -> (d0)>],
                    iterator_types = ["parallel"]}
        ins(%a : memref<4x!idr.str>) outs(%b : memref<4x!idr.str>) {
    ^bb0(%x: !idr.str, %y: !idr.str):
      linalg.yield %x : !idr.str
    }
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func @root() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

idr.program @counted root(@root) stage(first) types #idr.types<> {
  idr.func @copy(%a: memref<4xi64>, %b: memref<4xi64>) -> i64 {
    linalg.generic {indexing_maps = [affine_map<(d0) -> (d0)>, affine_map<(d0) -> (d0)>],
                    iterator_types = ["parallel"]}
        ins(%a : memref<4xi64>) outs(%b : memref<4xi64>) {
    ^bb0(%x: i64, %y: i64):
      linalg.yield %x : i64
    }
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func @root() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
