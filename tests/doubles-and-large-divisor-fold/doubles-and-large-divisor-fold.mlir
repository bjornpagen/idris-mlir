// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// After the first stage, nothing a fold would replace is left of a
// computation on constants whose result IEEE 754 fixes, and a computation
// whose result it leaves open is left to run. Every value is written out,
// so the root keeps it.
//
// In the first program each of upstream's Double ops IEEE fixes computes
// once on constants, at round to nearest, ties to even, the rounding a
// Double has where an op names none. The property holds each to being
// computed, not to its value; the value each gives, from IEEE 754 (0.1 is
// 0x3FB999999999999A, 0.2 is 0x3FC999999999999A, 0.9 is
// 0x3FECCCCCCCCCCCCD):
//   0.1 + 0.2: the exact sum is 0x1.33333333333338p-2, half an ulp past
//     0x1.3333333333333p-2, whose last digit is odd, so the tie goes up:
//     0x3FD3333333333334, 0.30000000000000004;
//   1.0 - 0.9: the two lie within a factor of two, so the difference is
//     exact (Sterbenz): 0x3FB9999999999998, 0.09999999999999998;
//   0.1 * 3.0: the exact product is the same 0x1.33333333333338p-2, the
//     same tie: 0x3FD3333333333334;
//   1.0 / 3.0: the bits past the last kept one begin 01, below half, so
//     they go: 0x3FD5555555555555;
//   1.0 / 0.0: division by zero gives an infinity, its sign the exclusive
//     or of the operands' signs: +inf, 0x7FF0000000000000, no NaN;
//   -(0.0): negation flips the sign bit alone: -0.0, 0x8000000000000000;
//   0.1 < 0.2 holds, and a NaN == a NaN does not: a NaN is unordered with
//     every value, itself among them, and an ordered predicate is false on
//     an unordered pair, whatever the NaN's sign and payload;
//   2^53 + 1 as a signed word is midway between the Doubles 2^53 and
//     2^53 + 2, and the tie goes to the even significand: 2^53,
//     0x4340000000000000;
//   the word -1 read unsigned is 2^64 - 1, which is nearer 2^64 than the
//     Double below it, 2^64 - 2048: 2^64, 0x43F0000000000000;
//   floor(-2.5) rounds toward negative infinity, -3.0
//     (0xC008000000000000), and ceil(-2.5) toward positive infinity, -2.0
//     (0xC000000000000000).
// It also divides bigs by a big past the small range (-2^62 to 2^62 - 1),
// which its sign keeps from zero, so the division's guard holds and the
// quotient is computed: 10^30 by 2^62, the product of 2^31 with itself,
// which the program computes, is 216840434497; 10^30 by -2^63, which the
// program holds as a constant, is -108420217248, rounded up as Integer's
// div rounds a quotient by a negative divisor, so that the remainder is
// not negative.
!Str = !idr.graded<many, static, !idr.str>
!BigS = !idr.graded<many, static, !idr.big>
idr.program @computed root(@main) stage(first) {
  idr.func @main() {
    %tenth = arith.constant 0.1 : f64
    %fifth = arith.constant 0.2 : f64
    %ninetenths = arith.constant 0.9 : f64
    %zero = arith.constant 0.0 : f64
    %one = arith.constant 1.0 : f64
    %three = arith.constant 3.0 : f64
    %minusTwoAndAHalf = arith.constant -2.5 : f64
    %nan = arith.constant 0x7FF8000000000000 : f64
    %sum = arith.addf %tenth, %fifth : f64
    %sumText = idr.str.show_double %sum : (f64) -> !idr.str
    idr.io.put_str %sumText : (!idr.str) -> ()
    %difference = arith.subf %one, %ninetenths : f64
    %differenceText = idr.str.show_double %difference : (f64) -> !idr.str
    idr.io.put_str %differenceText : (!idr.str) -> ()
    %product = arith.mulf %tenth, %three : f64
    %productText = idr.str.show_double %product : (f64) -> !idr.str
    idr.io.put_str %productText : (!idr.str) -> ()
    %third = arith.divf %one, %three : f64
    %thirdText = idr.str.show_double %third : (f64) -> !idr.str
    idr.io.put_str %thirdText : (!idr.str) -> ()
    %infinity = arith.divf %one, %zero : f64
    %infinityText = idr.str.show_double %infinity : (f64) -> !idr.str
    idr.io.put_str %infinityText : (!idr.str) -> ()
    %negativeZero = arith.negf %zero : f64
    %negativeZeroText = idr.str.show_double %negativeZero : (f64) -> !idr.str
    idr.io.put_str %negativeZeroText : (!idr.str) -> ()
    %less = arith.cmpf olt, %tenth, %fifth : f64
    %lessWritten = arith.extui %less : i1 to i32
    idr.io.put_char %lessWritten : (i32) -> ()
    %same = arith.cmpf oeq, %nan, %nan : f64
    %sameWritten = arith.extui %same : i1 to i32
    idr.io.put_char %sameWritten : (i32) -> ()
    %pastTwoTo53 = arith.constant 9007199254740993 : i64
    %signed = arith.sitofp %pastTwoTo53 : i64 to f64
    %signedText = idr.str.show_double %signed : (f64) -> !idr.str
    idr.io.put_str %signedText : (!idr.str) -> ()
    %allOnes = arith.constant -1 : i64
    %unsigned = arith.uitofp %allOnes : i64 to f64
    %unsignedText = idr.str.show_double %unsigned : (f64) -> !idr.str
    idr.io.put_str %unsignedText : (!idr.str) -> ()
    %down = math.floor %minusTwoAndAHalf : f64
    %downText = idr.str.show_double %down : (f64) -> !idr.str
    idr.io.put_str %downText : (!idr.str) -> ()
    %up = math.ceil %minusTwoAndAHalf : f64
    %upText = idr.str.show_double %up : (f64) -> !idr.str
    idr.io.put_str %upText : (!idr.str) -> ()
    %dividend = idr.constant !BigS #idr.big<1000000000000000000000000000000>
    %twoTo31 = idr.constant !BigS #idr.big<2147483648>
    %twoTo62 = idr.big.mul %twoTo31, %twoTo31 : (!BigS, !BigS) -> !idr.big
    %quotient = idr.big.div %dividend, %twoTo62 : (!BigS, !idr.big) -> !idr.big
    %quotientText = idr.big.show %quotient : (!idr.big) -> !idr.str
    idr.io.put_str %quotientText : (!idr.str) -> ()
    %minusTwoTo63 = idr.constant !BigS #idr.big<-9223372036854775808>
    %negative = idr.big.div %dividend, %minusTwoTo63 : (!BigS, !BigS) -> !idr.big
    %negativeText = idr.big.show %negative : (!idr.big) -> !idr.str
    idr.io.put_str %negativeText : (!idr.str) -> ()
    idr.return
  }
}

// -----

// In the second program each computation gives a NaN, whose sign and
// payload IEEE leaves to each machine, so none is a constant and each is
// left to run where the program is: infinity plus negative infinity,
// infinity minus itself, zero times infinity and zero by zero, each an
// invalid operation of IEEE 754, whose result is a quiet NaN; and the root
// of -1.0, a negative number, invalid too.
idr.program @left root(@main) stage(first) {
  idr.func @main() {
    %zero = arith.constant 0.0 : f64
    %minusOne = arith.constant -1.0 : f64
    %infinity = arith.constant 0x7FF0000000000000 : f64
    %negativeInfinity = arith.constant 0xFFF0000000000000 : f64
    // expected-error @below {{expected folded: }}
    %sum = arith.addf %infinity, %negativeInfinity : f64
    %sumText = idr.str.show_double %sum : (f64) -> !idr.str
    idr.io.put_str %sumText : (!idr.str) -> ()
    // expected-error @below {{expected folded: }}
    %difference = arith.subf %infinity, %infinity : f64
    %differenceText = idr.str.show_double %difference : (f64) -> !idr.str
    idr.io.put_str %differenceText : (!idr.str) -> ()
    // expected-error @below {{expected folded: }}
    %product = arith.mulf %zero, %infinity : f64
    %productText = idr.str.show_double %product : (f64) -> !idr.str
    idr.io.put_str %productText : (!idr.str) -> ()
    // expected-error @below {{expected folded: }}
    %quotient = arith.divf %zero, %zero : f64
    %quotientText = idr.str.show_double %quotient : (f64) -> !idr.str
    idr.io.put_str %quotientText : (!idr.str) -> ()
    // expected-error @below {{expected folded: }}
    %root = math.sqrt %minusOne : f64
    %rootText = idr.str.show_double %root : (f64) -> !idr.str
    idr.io.put_str %rootText : (!idr.str) -> ()
    idr.return
  }
}
