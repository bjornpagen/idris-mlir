// RUN: %status 1 idris-mlir-opt %s --idr-rc -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// idr-rc counts a module once: in the owned stage its references are
// explicit already.
// CHECK: error: idr-rc: the module is already in the owned stage
module {
  func.func private @f(%s: !idr.own<!idr.str>) -> !idr.own<!idr.str> {
    return %s : !idr.own<!idr.str>
  }
}
