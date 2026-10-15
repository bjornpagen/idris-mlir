// NEEDS-ACCEPTANCE: written before idr-bufferize and the cutover's verifier existed: check that idris-mlir-opt parses and verifies this module, that --idr-bufferize bufferizes it, and that in-place=@callee and in-place=@caller hold of the result.
// One-Shot Module Bufferize across idr.func boundaries: @callee writes the
// tensor it is given and returns it, and @caller passes a tensor it does
// not read again, so neither copies. @never ends in ub.unreachable, which
// the pinned driver refuses ("cannot bufferize func.func without
// func.return"), and nothing calls it.
module {
  idr.func private @callee(%t: tensor<4xi64>, %v: i64) -> tensor<4xi64> attributes {total} {
    %c0 = arith.constant 0 : index
    %r = tensor.insert %v into %t[%c0] : tensor<4xi64>
    return %r : tensor<4xi64>
  }
  idr.func private @never(%t: tensor<4xi64>) -> tensor<4xi64> {
    ub.unreachable
  }
  idr.func private @caller(%v: i64) -> i64 attributes {total} {
    %t = tensor.splat %v : tensor<4xi64>
    %r = idr.call @callee(%t, %v) : (tensor<4xi64>, i64) -> tensor<4xi64>
    %c1 = arith.constant 1 : index
    %x = tensor.extract %r[%c1] : tensor<4xi64>
    return %x : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 7 : i64
    %x = idr.call @caller(%n) : (i64) -> i64
    %w2 = idr.io.put_int signed %x, %w : i64
    return %w2 : !idr.world
  }
}
