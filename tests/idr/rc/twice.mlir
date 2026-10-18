// NEEDS-ACCEPTANCE: that idr-rc's first step, idr-rc-cells, refuses a program in the owned stage by its record's stage (StagedPass), naming itself.
// RUN: %status 1 idris-mlir-opt %s --idr-rc -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// idr-rc counts a program once: in the owned stage its references are
// explicit already, and its steps require the first stage.
// CHECK: error: internal error: idr-rc-cells runs on a program at first, not owned
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
