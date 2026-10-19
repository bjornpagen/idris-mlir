// RUN: idris-mlir-opt %s --canonicalize '--idr-expect=holds=returns=@folded:#idr.big<-4>/#idr.big<-4>/#idr.big<18446744073709551616>/#idr.big<0>/#idr.big<-1>/#idr.big<0>,returns=@too_large:_/_' -o /dev/null
// idr.big.shl and idr.big.shr fold by calling the runtime: a left shift
// multiplies by 2^amount, a right shift is the floor of the quotient, a
// negative amount shifts the other way, and 0 shifted any amount is 0. A
// shift away from zero whose constant would take more static data than a
// constant made at compile time may stays, to run at runtime.

idr.program @"big-shift" root(@root) stage(first) {
  idr.func @folded() -> (!idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big) {
    %m7 = idr.constant !idr.big #idr.big<-7>
    %one = idr.constant !idr.big #idr.big<1>
    %m1 = idr.constant !idr.big #idr.big<-1>
    %c0 = idr.constant !idr.big #idr.big<0>
    %c64 = idr.constant !idr.big #idr.big<64>
    %huge = idr.constant !idr.big #idr.big<100000000000000000000>
    %mhuge = idr.constant !idr.big #idr.big<-100000000000000000000>
    // -7 >> 1 is the floor of -3.5.
    %a = idr.big.shr %m7, %one
    // A negative amount shifts the other way.
    %b = idr.big.shl %m7, %m1
    %c = idr.big.shl %one, %c64
    // 0 moved any amount, and anything moved toward zero by an amount no word
    // holds.
    %d = idr.big.shl %c0, %huge
    %e = idr.big.shr %m1, %huge
    %f = idr.big.shl %one, %mhuge
    return %a, %b, %c, %d, %e, %f : !idr.big, !idr.big, !idr.big, !idr.big, !idr.big, !idr.big
  }

  idr.func @too_large() -> (!idr.big, !idr.big) {
    %one = idr.constant !idr.big #idr.big<1>
    // One bit past 8 * 2^20.
    %n = idr.constant !idr.big #idr.big<8388609>
    %mn = idr.constant !idr.big #idr.big<-18446744073709551616>
    %a = idr.big.shl %one, %n
    // A right shift by a negative amount grows.
    %b = idr.big.shr %one, %mn
    return %a, %b : !idr.big, !idr.big
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
