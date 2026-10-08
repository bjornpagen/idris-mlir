// One body, a crash check (scf.if) and a combiner (arith.addi), in two
// linalg.generic ops: @elementwise has one parallel dimension, @rows a
// parallel and a reduction dimension. Each is vectorized at its own sizes,
// with failures suppressed so that the IR left behind is printed.
func.func private @crash()

func.func @elementwise(%in: memref<?xi64>, %out: memref<?xi64>) {
  linalg.generic {indexing_maps = [affine_map<(d0) -> (d0)>, affine_map<(d0) -> (d0)>],
                  iterator_types = ["parallel"]}
      ins(%in : memref<?xi64>) outs(%out : memref<?xi64>) {
  ^bb0(%x: i64, %acc: i64):
    %c0 = arith.constant 0 : i64
    %z = arith.cmpi eq, %x, %c0 : i64
    scf.if %z {
      func.call @crash() : () -> ()
    }
    %t = arith.addi %acc, %x : i64
    linalg.yield %t : i64
  }
  return
}

func.func @rows(%in: memref<?xi64>, %out: memref<?xi64>) {
  linalg.generic {indexing_maps = [affine_map<(d0, d1) -> (d1)>, affine_map<(d0, d1) -> (d0)>],
                  iterator_types = ["parallel", "reduction"]}
      ins(%in : memref<?xi64>) outs(%out : memref<?xi64>) {
  ^bb0(%x: i64, %acc: i64):
    %c0 = arith.constant 0 : i64
    %z = arith.cmpi eq, %x, %c0 : i64
    scf.if %z {
      func.call @crash() : () -> ()
    }
    %t = arith.addi %acc, %x : i64
    linalg.yield %t : i64
  }
  return
}

module attributes {transform.with_named_sequence} {
  transform.named_sequence @__transform_main(%root: !transform.any_op {transform.readonly}) {
    %generics = transform.structured.match ops{["linalg.generic"]} in %root : (!transform.any_op) -> !transform.any_op
    %elementwise, %rows = transform.split_handle %generics : (!transform.any_op) -> (!transform.any_op, !transform.any_op)
    transform.sequence %elementwise : !transform.any_op failures(suppress) {
    ^bb0(%g: !transform.any_op):
      transform.structured.vectorize %g vector_sizes [4] : !transform.any_op
    }
    transform.sequence %rows : !transform.any_op failures(suppress) {
    ^bb0(%g: !transform.any_op):
      transform.structured.vectorize %g vector_sizes [4, 1] : !transform.any_op
    }
    transform.yield
  }
}
