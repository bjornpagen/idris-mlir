// At sccp's fixpoint: the one constant is used by an op that cannot fold it,
// so sccp has nothing to propagate. It still erases the constant and makes an
// equal one, which composite-fixed-point-pass's fingerprint counts as a change.
func.func @one() -> i32 {
  %c = arith.constant 1 : i32
  return %c : i32
}
