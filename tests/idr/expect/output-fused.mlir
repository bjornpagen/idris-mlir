// NEEDS-ACCEPTANCE: that output-fused holds of a written constant and fails once at the idr.io.put_str of a string built only to be written.
// RUN: idris-mlir-opt %s --idr-expect=holds=output-fused=@constant -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=output-fused=@appended -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// Output writes the pieces a string is built of instead of the string, so
// no string is built only to be written: a constant is no string built
// (@constant), and a concatenation written as it is was (@appended).
// CHECK-DAG: error: expected output-fused: idr.io.put_str writes what {{.*}} built in @appended
idr.program @"output-fused" root(@root) stage(first) {
  idr.func @constant(%w: !idr.world) -> !idr.world {
    %s = idr.constant "n = " : !idr.str
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
  idr.func @appended(%a: !idr.str, %b: !idr.str, %w: !idr.world) -> !idr.world {
    %s = idr.str.append %a, %b
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
