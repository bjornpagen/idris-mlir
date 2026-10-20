// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// Whether a value a match yields would fold with a consumer in a later
// match's regions is asked of a copy of the consumer, so asking changes
// nothing of the program. A commutative op has its fold move a constant
// operand last: asked on the op itself, each ask of the two consumers here
// (an xor of the match's result, a constant in one region, with a value no
// region knows) relinked the use the walk over the result's uses was on,
// and the walk alternated between the two for ever. The canonicalizer ends,
// and the program prints what it printed before on every byte.
idr.program @"sink-probe-fold" root(@root) stage(first) types #idr.types<> {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %bit = arith.andi %byte, %c1 : i64
    %half = arith.shrui %byte, %c1 : i64
    %third = arith.shrui %byte, %c2 : i64
    %v = idr.match_lit %bit : i64 -> (i64) {
    case 0 {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    default(%d: i64) {
      idr.yield %byte : i64
    }
    }
    %m = idr.match_lit %third : i64 -> (i64) {
    case 0 {
      %a = arith.xori %v, %half : i64
      idr.yield %a : i64
    }
    default(%d: i64) {
      %b = arith.xori %v, %third : i64
      idr.yield %b : i64
    }
    }
    %w1 = idr.io.put_sint %m, %w0 : i64
    return %w1 : !idr.world
  }
}
