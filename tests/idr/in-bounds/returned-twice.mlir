// RUN: idris-mlir-opt %s --idr-in-bounds --remove-dead-values --idr-in-bounds --idr-expect=holds=bounds-checked=@onePastBack -o /dev/null
// Each run of idr-in-bounds judges the module as it is then. The access
// here may run one past the end of the array @wrap gives back, so its
// check stays in both runs, and both ask whether %n is that array's length:
// through @wrap, to the argument @give returns. Between the runs,
// remove-dead-values drops @give's unused parameter and the operand its
// call passes for it, so the argument @give returns is no longer its
// second; a run that read what an earlier one found would ask the call for
// an operand it no longer has.
module {
  func.func private @give(%unused: i64, %a: memref<?xi64>) -> memref<?xi64> {
    return %a : memref<?xi64>
  }

  func.func private @wrap(%a: memref<?xi64>) -> memref<?xi64> {
    %c0 = arith.constant 0 : i64
    %b = func.call @give(%c0, %a) : (i64, memref<?xi64>) -> memref<?xi64>
    return %b : memref<?xi64>
  }

  func.func @onePastBack(%n: i64, %i: i64, %w: !idr.world) -> !idr.world {
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new %n, %z, %w : i64 -> memref<?xi64>
    %b = func.call @wrap(%a) : (memref<?xi64>) -> memref<?xi64>
    %lo = arith.cmpi sge, %i, %z : i64
    %hi = arith.cmpi sle, %i, %n : i64
    %ok = arith.andi %lo, %hi : i1
    %r = scf.if %ok -> !idr.world {
      %ib.z = arith.constant 0 : index
      %ib.d = memref.dim %b, %ib.z : memref<?xi64>
      %ib.n = arith.index_cast %ib.d : index to i64
      %ib = idr.check.in_bounds %i, %ib.n, "array index out of bounds"
      %s1 = idr.array.set %b[%ib], %i, %w1 : memref<?xi64>, i64
      scf.yield %s1 : !idr.world
    } else {
      scf.yield %w1 : !idr.world
    }
    return %r : !idr.world
  }
}
