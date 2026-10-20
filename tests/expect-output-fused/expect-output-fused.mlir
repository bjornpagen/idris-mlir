// RUN: idris-mlir-opt %s --idr-expect=holds=output-fused=@constant -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=output-fused=@appended,output-fused=@measured -verify-diagnostics -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=output-fused -o /dev/null
// Output writes the pieces a string is built of instead of the string, so
// no string is built only to be written: a constant is no string built
// (@constant), and a concatenation written as it is was (@appended). The
// rule is that output never writes what such a builder made: one also read
// for its length (@measured) is still written in pieces, and the string is
// kept for its length alone. After the folds, which write the pieces, it
// holds of the whole module.
idr.program @"output-fused" root(@root) stage(first) types #idr.types<> {
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
  idr.func @measured(%a: !idr.str, %b: !idr.str, %w: !idr.world) -> (i64, !idr.world) {
    %s = idr.str.append %a, %b
    %n = idr.str.length %s
    // expected-error @below {{expected output-fused: }}
    %w1 = idr.io.put_str %s, %w
    return %n, %w1 : i64, !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
