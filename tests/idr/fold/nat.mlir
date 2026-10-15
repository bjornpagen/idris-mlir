// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@naturals:#idr.big<18446744073709551621>/#idr.big<92233720368547758080>/true/#idr.big<4>/_/#idr.big<0>/#idr.big<12>/#idr.big<5>' -o /dev/null
// The runtime folds the operations on constant naturals, as it computes
// them at runtime, and the results stay naturals: a sum and a product; a
// comparison; a predecessor (zero has none: on a path a match excludes, it
// stays as it is); an Integer clamped at 0; a natural as an Integer.
idr.program @nat root(@root) stage(first) {
  idr.func @naturals() -> (!idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.nat, !idr.nat, !idr.big) {
    %five = idr.constant #idr.big<5> : !idr.nat
    %zero = idr.constant #idr.big<0> : !idr.nat
    %large = idr.constant #idr.big<18446744073709551616> : !idr.nat
    %negative = idr.constant #idr.big<-7> : !idr.big
    %twelve = idr.constant #idr.big<12> : !idr.big
    %s = idr.big.add %five, %large : !idr.nat
    %p = idr.big.mul %five, %large : !idr.nat
    %c = idr.big.cmp lt %five, %large : !idr.nat
    %d = idr.big.pred %five
    %z = idr.big.pred %zero
    %n = idr.nat.from_big %negative
    %m = idr.nat.from_big %twelve
    %i = idr.nat.to_big %five
    return %s, %p, %c, %d, %z, %n, %m, %i
        : !idr.nat, !idr.nat, i1, !idr.nat, !idr.nat, !idr.nat, !idr.nat, !idr.big
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
