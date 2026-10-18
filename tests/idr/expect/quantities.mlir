// RUN: idris-mlir-opt %s --idr-expect=holds=quantities-kept=%s -o /dev/null
// RUN: cp %s %t.emitted.mlir
// RUN: sed 's/@consume(%h: !idr.lin<i64>)/@consume(%h: i64)/; s/call @consume(%e) : (!idr.lin<i64>) -> i64/call @consume(%e) : (i64) -> i64/; s/idr.lin.enter %x : !idr.lin<i64>/arith.addi %x, %x : i64/; s#// WIDENED: #// expected-error #' %t.emitted.mlir > %t.widened.mlir
// RUN: idris-mlir-opt %t.widened.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -verify-diagnostics -o /dev/null
// RUN: sed 's/!idr.lin<!Handle>/!Handle/g; s/%a: !idr.lin<i64>/%a: i64/; s#// BOUND: #// expected-error #' %t.emitted.mlir > %t.bound.mlir
// RUN: idris-mlir-opt %t.bound.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -verify-diagnostics -o /dev/null
// RUN: sed 's/%l: !idr.lin<i64>/%l: i64/; s/!idr.fn<(!idr.lin<i64>) -> i32>/!idr.fn<(i64) -> i32>/g; s/idr.lin.use %l : !idr.lin<i64>/arith.addi %l, %l : i64/; s#// LAMBDA: #// expected-error #' %t.emitted.mlir > %t.lam.mlir
// RUN: idris-mlir-opt %t.lam.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -verify-diagnostics -o /dev/null
// RUN: sed '/@build.trmc/d' %t.emitted.mlir > %t.noclone.mlir
// RUN: idris-mlir-opt %s --idr-expect=holds=quantities-kept=%t.noclone.mlir -o /dev/null
// RUN: sed 's/%w: !idr.lin<i64>/%w: i64/; /@wide/s#"Main.idr"#"%t.span.mlir"#g; s#// SPAN: #// expected-error #' %t.emitted.mlir > %t.span.mlir
// RUN: idris-mlir-opt %t.span.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -verify-diagnostics -o /dev/null
// The module as emitted keeps its quantities, which are its types. A
// linear parameter made unrestricted, a field a match bound linearly (of
// a linear value) bound unrestricted (of the value made unrestricted), and
// a lambda's linear parameter, its function's, made unrestricted are each
// an error. A constructor's fields are its type's body, set once, so no
// pass changes their quantities. A binder is its name over its
// definition's span: the extra linear parameter a
// destination-passing clone takes at its function's name over the
// span of the function's one unrestricted parameter (@build.trmc,
// against the emitted module without it) is no binder Idris proved a
// quantity of, and two parameters of one definition at the one span
// under different names (@wide) are each held to their own.
//
// Each variant is the emitted module with one change, its errors marked
// `// <VARIANT>: @below {{...}}`, which the variant's sed alone makes an
// expectation. A binder's error is at its location, which for a span Emit
// wrote is in the Idris source: the span variant names its own file in
// @wide's spans, whose line is @wide's, and a span's key reads its line
// and column alone, so the emitted module's binders are found the same.
!Handle = !idr.data<"Handle", plain [@MkHandle(!idr.lin<i64>, i64)]>
idr.program @quantities root(@root) stage(higher) {
  // WIDENED: @below {{expected quantities-kept: parameter 0 of @consume has quantity w, and Idris proved 1}}
  idr.func @consume(%h: !idr.lin<i64>) -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
  // BOUND: @below {{expected quantities-kept: parameter 0 of @open has quantity w, and Idris proved 1}}
  idr.func @open(%h: !idr.lin<!Handle>) -> i64 {
    %r = idr.match %h : !idr.lin<!Handle> -> (i64) {
    // BOUND: @below {{expected quantities-kept: bound field 0 of @open has quantity w, and Idris proved 1}}
    case @MkHandle(%a: !idr.lin<i64>, %b: i64) {
      idr.yield %b : i64
    }
    }
    return %r : i64
  }
  idr.func @keep(%x: i64) -> i64 {
    %e = idr.lin.enter %x : !idr.lin<i64>
    %r = idr.call @consume(%e) : (!idr.lin<i64>) -> i64
    return %r : i64
  }
  // LAMBDA: @below {{expected quantities-kept: parameter 0 of @lam.lambda has quantity w, and Idris proved 1}}
  idr.func @lam.lambda(%l: !idr.lin<i64>) -> i32 {
    %u = idr.lin.use %l : !idr.lin<i64>
    %t = arith.trunci %u : i64 to i32
    return %t : i32
  }
  idr.func @lam() -> !idr.fn<(!idr.lin<i64>) -> i32> {
    %f = idr.closure @lam.lambda() : () -> !idr.fn<(!idr.lin<i64>) -> i32>
    return %f : !idr.fn<(!idr.lin<i64>) -> i32>
  }
  idr.func @build(%n: i64 loc("arg"("Main.idr":22:1 to :17))) -> i64 {
    return %n : i64
  }
  idr.func @build.trmc(%n: i64 loc("arg"("Main.idr":22:1 to :17)), %h: !idr.lin<i64> loc("build"("Main.idr":22:1 to :17))) -> i64 { return %n : i64 }
  // SPAN: @below {{expected quantities-kept: parameter 0 of @wide has quantity w, and Idris proved 1}}
  idr.func @wide(%w: !idr.lin<i64> loc("t"("Main.idr":70:1 to :20)), %a: i64 loc("arg"("Main.idr":70:1 to :20))) -> i64 {
    return %a : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
