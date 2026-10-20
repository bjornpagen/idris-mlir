// One-Shot Module Bufferize across idr.func boundaries, through upstream's own
// models of FunctionOpInterface, CallOpInterface and ReturnLike: @callee
// writes the tensor it is given and returns it, and @caller passes a tensor
// it does not read again, so neither copies. @never ends in ub.unreachable,
// which the pinned driver refuses ("cannot bufferize func.func without
// func.return"), and nothing calls it. @constant returns a constant array,
// whose global is a symbol of the program, the symbol table bufferized, and
// not of the module around it; @writes writes the array its call returns,
// a buffer that is not writable, so it writes a copy.
idr.program @"idr-call" root(@root) stage(first) types #idr.types<> {
  idr.func @callee(%t: tensor<4xi64>, %v: i64) -> tensor<4xi64> attributes {total} {
    %c0 = arith.constant 0 : index
    %r = tensor.insert %v into %t[%c0] : tensor<4xi64>
    return %r : tensor<4xi64>
  }
  idr.func @never(%t: tensor<4xi64>) -> tensor<4xi64> {
    ub.unreachable
  }
  idr.func @caller(%v: i64) -> i64 attributes {total} {
    %t = tensor.splat %v : tensor<4xi64>
    %r = idr.call @callee(%t, %v) : (tensor<4xi64>, i64) -> tensor<4xi64>
    %c1 = arith.constant 1 : index
    %x = tensor.extract %r[%c1] : tensor<4xi64>
    return %x : i64
  }
  idr.func @constant() -> tensor<3xi64> attributes {total} {
    %c = arith.constant dense<[1, 2, 3]> : tensor<3xi64>
    return %c : tensor<3xi64>
  }
  idr.func @writes(%v: i64) -> i64 attributes {total} {
    %c0 = arith.constant 0 : index
    %r = idr.call @constant() : () -> tensor<3xi64>
    %w = tensor.insert %v into %r[%c0] : tensor<3xi64>
    %x = tensor.extract %w[%c0] : tensor<3xi64>
    return %x : i64
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 7 : i64
    %x = idr.call @caller(%n) : (i64) -> i64
    %y = idr.call @writes(%n) : (i64) -> i64
    %s = arith.addi %x, %y : i64
    %w2 = idr.io.put_sint %s, %w : i64
    return %w2 : !idr.world
  }
}
