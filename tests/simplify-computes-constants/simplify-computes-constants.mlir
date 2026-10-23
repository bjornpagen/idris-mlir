// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// After the first stage, the program computes from constants nothing a
// fold would: a string, a big and a Double, each computed by the runtime
// function the op's fold calls. In the first program everything folds:
// "a" ++ "b"; the product of two bigs past the small range, and its text;
// the product of two smalls at a counted hold, and its text; 7 / 2, whose
// divisor its guard admits; and "2.5" read as a Double, and its text. In
// the second what no fold may compute is left, and only that: exp 1.0, a C
// library function whose last digit is each library's; "nan" read as a
// Double, a NaN, whose sign and payload are each machine's; and 7 / 0,
// whose guard fails, so the program crashes there and nothing is computed.
// Each value is written out, so the root keeps it.
!Str = !idr.graded<many, static, !idr.str>
!BigS = !idr.graded<many, static, !idr.big>
idr.program @folds root(@main) stage(first) {
  idr.func @main() {
    %a = idr.constant !Str "a"
    %b = idr.constant !Str "b"
    %ab = idr.str.append %a, %b : (!Str, !Str) -> !Str
    idr.io.put_str %ab : (!Str) -> ()
    %x = idr.constant !BigS #idr.big<4611686018427387904>
    %y = idr.constant !BigS #idr.big<4611686018427387905>
    %product = idr.big.mul %x, %y : (!BigS, !BigS) -> !BigS
    %productText = idr.big.show %product : (!BigS) -> !Str
    idr.io.put_str %productText : (!Str) -> ()
    %six = idr.constant !BigS #idr.big<6>
    %seven = idr.constant !BigS #idr.big<7>
    %small = idr.big.mul %six, %seven : (!BigS, !BigS) -> !idr.big
    %smallText = idr.big.show %small : (!idr.big) -> !Str
    idr.io.put_str %smallText : (!Str) -> ()
    %two = idr.constant !BigS #idr.big<2>
    %quotient = idr.big.div %seven, %two : (!BigS, !BigS) -> !idr.big
    %quotientText = idr.big.show %quotient : (!idr.big) -> !Str
    idr.io.put_str %quotientText : (!Str) -> ()
    %written = idr.constant !Str "2.5"
    %real = idr.str.to_double %written : (!Str) -> f64
    %realText = idr.str.show_double %real : (f64) -> !Str
    idr.io.put_str %realText : (!Str) -> ()
    idr.return
  }
}

// -----

!Str = !idr.graded<many, static, !idr.str>
!BigS = !idr.graded<many, static, !idr.big>
idr.program @left root(@main) stage(first) {
  idr.func @main() {
    %one = arith.constant 1.0 : f64
    // expected-error @below {{expected folded: }}
    %e = math.exp %one : f64
    %eText = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %eText : (!Str) -> ()
    %written = idr.constant !Str "nan"
    // expected-error @below {{expected folded: }}
    %nan = idr.str.to_double %written : (!Str) -> f64
    %nanText = idr.str.show_double %nan : (f64) -> !Str
    idr.io.put_str %nanText : (!Str) -> ()
    %seven = idr.constant !BigS #idr.big<7>
    %zero = idr.constant !BigS #idr.big<0>
    // expected-error @below {{expected folded: }}
    %quotient = idr.big.div %seven, %zero : (!BigS, !BigS) -> !idr.big
    %quotientText = idr.big.show %quotient : (!idr.big) -> !Str
    idr.io.put_str %quotientText : (!Str) -> ()
    idr.return
  }
}
