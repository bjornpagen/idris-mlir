// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@preds:#idr.big<4>/_/#idr.big<18446744073709551616>' -o /dev/null
// The runtime folds the predecessor of a constant; zero has none, so its
// predecessor, on a path a match excludes, stays as it is.
idr.program @pred root(@root) stage(first) {
  idr.func @preds() -> (!idr.nat, !idr.nat, !idr.nat) {
    %five = idr.constant !idr.nat #idr.big<5>
    %zero = idr.constant !idr.nat #idr.big<0>
    %large = idr.constant !idr.nat #idr.big<18446744073709551617>
    %a = idr.big.pred %five
    %b = idr.big.pred %zero
    %c = idr.big.pred %large
    return %a, %b, %c : !idr.nat, !idr.nat, !idr.nat
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
