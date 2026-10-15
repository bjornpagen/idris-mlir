// RUN: %status 1 idris-mlir-opt %s --idr-rc -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// idr-rc counts a module once: in the owned stage its references are
// explicit already.
// CHECK: error: idr-rc: the module is already in the owned stage
idr.program @twice root(@root) stage(owned) {
  idr.func @f(%s: !idr.own<!idr.str>) -> !idr.own<!idr.str> {
    return %s : !idr.own<!idr.str>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
