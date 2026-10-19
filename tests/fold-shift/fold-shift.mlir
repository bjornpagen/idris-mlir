// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@signed:0/-2/-2/-1/-9223372036854775808/0,returns=@unsigned:-112/25/0,returns-argument=@by_zero:0 -o /dev/null
// The shifts fold to Idris's meaning for every amount: Scheme's
// ash wrapped to the width, a negative signed amount shifting the other
// way, and from the width up only the fill (0, or -1 for a negative value
// shifted right). A shift by 0 is its value.

idr.program @shift root(@root) stage(first) {
  idr.func @signed() -> (i64, i64, i64, i64, i64, i64) {
    %one = arith.constant 1 : i64
    %m8 = arith.constant -8 : i64
    %c2 = arith.constant 2 : i64
    %cm2 = arith.constant -2 : i64
    %c63 = arith.constant 63 : i64
    %c64 = arith.constant 64 : i64
    %c70 = arith.constant 70 : i64
    // 1 << 64: past the width, 0.
    %a = idr.shls %one, %c64 : i64
    // -8 << -2 is -8 >> 2.
    %b = idr.shls %m8, %cm2 : i64
    %c = idr.shrs %m8, %c2 : i64
    // A negative value shifted right past the width is its sign.
    %d = idr.shrs %m8, %c70 : i64
    // 1 << 63 wraps to the most negative Int.
    %e = idr.shls %one, %c63 : i64
    // A positive value shifted right past the width is 0.
    %f = idr.shrs %one, %c70 : i64
    return %a, %b, %c, %d, %e, %f : i64, i64, i64, i64, i64, i64
  }

  idr.func @unsigned() -> (i8, i8, i8) {
    %v = arith.constant 200 : i8
    %c1 = arith.constant 1 : i8
    %c3 = arith.constant 3 : i8
    %c9 = arith.constant 9 : i8
    // 200 << 1 is 400, wrapped to 144 (printed as the i8 -112).
    %a = idr.shlu %v, %c1 : i8
    // A right shift of an unsigned value fills with zeros.
    %b = idr.shru %v, %c3 : i8
    %c = idr.shru %v, %c9 : i8
    return %a, %b, %c : i8, i8, i8
  }

  idr.func @by_zero(%x: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %r = idr.shls %x, %c0 : i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
