func.func @f(%lb: index, %ub: index, %step: index, %m: memref<i64>) {
  %p = ub.poison : i64
  %r = scf.for %i = %lb to %ub step %step iter_args(%a = %p) -> (i64) {
    %c = arith.constant 1 : i64
    memref.store %c, %m[] : memref<i64>
    scf.yield %p : i64
  }
  return
}
