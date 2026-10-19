// RUN: idris-mlir-opt %s --idr-expect=holds=output-fused=@constant -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=output-fused=@appended -verify-diagnostics -o /dev/null
// Output writes the pieces a string is built of instead of the string, so
// no string is built only to be written: a constant is no string built
// (@constant), and a concatenation written as it is was (@appended).
idr.program @"output-fused" root(@root) stage(first) {
  idr.func @constant(%w: !idr.world) -> !idr.world {
    %s = idr.constant !idr.str "n = "
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
  idr.func @appended(%a: !idr.str, %b: !idr.str, %w: !idr.world) -> !idr.world {
    %s = idr.str.append %a, %b
    // expected-error @below {{expected output-fused: }}
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
