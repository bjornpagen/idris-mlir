// RUN: idris-mlir-opt %s -split-input-file --idr-defunctionalize -verify-diagnostics -o /dev/null
// An evaluated suspension holds its value in the forced state of a cell no
// label reaches, which the keys of its type do not follow: a closure or a
// suspension it holds is a value the analysis of labels loses there, and
// the program is refused at the delay, as at any op the analysis does not
// see through.
module attributes {idr.program} {
  idr.func private @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    // expected-error @+1 {{unsupported (runtime closure): a closure reaches 'idr.delay', where the analysis of its labels loses it}}
    %t = idr.delay : !idr.lazy<!idr.fn<(i64) -> (i64)>> {
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    %g = idr.force %t : !idr.lazy<!idr.fn<(i64) -> (i64)>> -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %g(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}

// -----

module attributes {idr.program} {
  idr.func private @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %s = idr.suspend @one() : () -> !idr.lazy<i64>
    // expected-error @+1 {{unsupported (laziness): a suspension reaches 'idr.delay', where the analysis of its labels loses it}}
    %t = idr.delay : !idr.lazy<!idr.lazy<i64>> {
      idr.yield %s : !idr.lazy<i64>
    }
    %u = idr.force %t : !idr.lazy<!idr.lazy<i64>> -> !idr.lazy<i64>
    %v = idr.force %u : !idr.lazy<i64> -> i64
    %w1 = idr.io.put_int signed %v, %w : i64
    return %w1 : !idr.world
  }
}
