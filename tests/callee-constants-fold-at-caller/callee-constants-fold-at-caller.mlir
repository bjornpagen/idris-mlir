// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=first},idr-expect{holds=folded=@main})' -verify-diagnostics -o /dev/null
// A call's results are the constants its callee returns, each result its
// own. @two's final body returns 2.0 and 3.0, so after the first stage
// each exp in @main takes its constant: exp, a C library function whose
// last digit is each library's, stays applied, on a constant alone, which
// the property reports at each. @two calls itself, so @main's call of it
// is an effect @main keeps and @two stays a function of its own; the
// inliner may also bring @two's body into @main, which then holds the
// constants itself.
!Str = !idr.graded<many, static, !idr.str>
idr.program @returned root(@main) stage(first) {
  idr.func @two() -> (f64, f64) {
    %again:2 = idr.call @two() <{tail_kind = nontail}> : () -> (f64, f64)
    %a = arith.constant 2.0 : f64
    %b = arith.constant 3.0 : f64
    idr.return %a, %b : f64, f64
  }
  idr.func @main() {
    %r:2 = idr.call @two() <{tail_kind = nontail}> : () -> (f64, f64)
    // expected-error @below {{expected folded: }}
    %e = math.exp %r#0 : f64
    // expected-error @below {{expected folded: }}
    %f = math.exp %r#1 : f64
    %eText = idr.str.show_double %e : (f64) -> !Str
    idr.io.put_str %eText : (!Str) -> ()
    %fText = idr.str.show_double %f : (f64) -> !Str
    idr.io.put_str %fText : (!Str) -> ()
    idr.return
  }
}
