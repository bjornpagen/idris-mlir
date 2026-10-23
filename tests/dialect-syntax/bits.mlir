// The bits IEEE 754 gives each float sample of syntax-samples whose bits
// it fixes, each written as MLIR's hexadecimal literal of a float's bits:
// a sign bit, 11 bits of exponent, 52 of fraction. 0.1 is 1.6 * 2^-4: the
// exponent 1023 - 4 = 0x3FB, and the fraction 0.6 * 2^52, hexadecimal
// 0x0.999...9 with 0.6 of a last place left over, rounds up to
// 0x999999999999A. -0.0 is the sign bit alone. An infinity is the exponent
// all ones and no fraction, of either sign. 4.9e-324 lies between 2^-1075
// and 3 * 2^-1075, so it reads as 2^-1074, the smallest subnormal: the
// exponent 0 and the fraction's last bit. A NaN's sign and payload are
// each host's, so it is no reference: the run checks it is a NaN.
module attributes {
  bits.tenth = 0x3FB999999999999A : f64,
  bits.negative_zero = 0x8000000000000000 : f64,
  bits.infinity = 0x7FF0000000000000 : f64,
  bits.negative_infinity = 0xFFF0000000000000 : f64,
  bits.smallest_subnormal = 0x0000000000000001 : f64
} {
}
