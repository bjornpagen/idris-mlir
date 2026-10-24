// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// After the first stage, nothing a fold would replace is left of a Double's
// conversion to an integer whose Double is finite, the condition its guard
// states; a conversion of a NaN or an infinity is left to run. Every value
// is written out, so the root keeps it.
//
// In the first program a Double computed from constants, 6.0e19 + 4.0e19,
// exactly 1.0e20 (each of the three is an integer below 2^53 times a power
// of two), passes the guard that it is finite and is truncated to an
// Integer, 100000000000000000000, past the small range (-2^62 to 2^62 - 1),
// so a cell: a constant that stands only at a static hold, where the
// conversion's result, at a hold its count frees, is not. Only a fold that
// decides the guard over the Double it computed, and places the Integer as
// static data where its text is read, leaves nothing to run; the text is
// written out.
idr.program @finite root(@main) stage(first) {
  idr.func @main() {
    %sixTimes = arith.constant 6.0e19 : f64
    %fourTimes = arith.constant 4.0e19 : f64
    %sum = arith.addf %sixTimes, %fourTimes : f64
    %checked = idr.check.finite %sum, non_finite_cast at #idr.site<"Main.idr", 3, 5, "Main.main"> : (f64) -> f64
    %integer = idr.big.from_double %checked : (f64) -> !idr.big
    %text = idr.big.show %integer : (!idr.big) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
}

// -----

// In the second program each conversion is written with no guard before
// it, as no program the frontend writes is, so its own guard's condition is
// all that stands between it and its operand: a NaN is no integer, nor an
// infinity, and each conversion is left to run where the program is.
idr.program @nonfinite root(@main) stage(first) {
  idr.func @main() {
    %nan = arith.constant 0x7FF8000000000000 : f64
    %infinity = arith.constant 0x7FF0000000000000 : f64
    // expected-error @below {{expected folded: }}
    %word = idr.f64.to_int %nan : (f64) -> i64
    %wordText = idr.str.show_sint %word : (i64) -> !idr.str
    idr.io.put_str %wordText : (!idr.str) -> ()
    // expected-error @below {{expected folded: }}
    %integer = idr.big.from_double %infinity : (f64) -> !idr.big
    %integerText = idr.big.show %integer : (!idr.big) -> !idr.str
    idr.io.put_str %integerText : (!idr.str) -> ()
    idr.return
  }
}
