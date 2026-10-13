// RUN: idris-mlir-opt %s --idr-expect=holds=quantities-kept=%s -o /dev/null
// RUN: cp %s %t.emitted.mlir
// RUN: sed 's/%h: !idr.lin<i64>/%h: i64/; s/call @consume(%e) : (!idr.lin<i64>) -> i64/call @consume(%e) : (i64) -> i64/; s/idr.lin.enter %x : !idr.lin<i64>/arith.addi %x, %x : i64/' %t.emitted.mlir > %t.widened.mlir
// RUN: %status 1 idris-mlir-opt %t.widened.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.widened.err
// RUN: FileCheck %s --check-prefix=WIDENED < %t.widened.err
// RUN: sed 's/(!idr.lin<i64>, i64)/(i64, i64)/; s/%a: !idr.lin<i64>/%a: i64/' %t.emitted.mlir > %t.field.mlir
// RUN: %status 1 idris-mlir-opt %t.field.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.field.err
// RUN: FileCheck %s --check-prefix=FIELD < %t.field.err
// RUN: sed 's/!idr.lin<!idr.data<@Handle>>/!idr.data<@Handle>/g; s/%a: !idr.lin<i64>/%a: i64/' %t.emitted.mlir > %t.bound.mlir
// RUN: %status 1 idris-mlir-opt %t.bound.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.bound.err
// RUN: FileCheck %s --check-prefix=BOUND < %t.bound.err
// RUN: sed 's/%l: !idr.lin<i64>/%l: i64/; s/!idr.fn<(!idr.lin<i64>) -> i32>/!idr.fn<(i64) -> i32>/g; s/idr.lin.use %l : !idr.lin<i64>/arith.addi %l, %l : i64/' %t.emitted.mlir > %t.lam.mlir
// RUN: %status 1 idris-mlir-opt %t.lam.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.lam.err
// RUN: FileCheck %s --check-prefix=LAMBDA < %t.lam.err
// RUN: sed '/@build.trmc/d' %t.emitted.mlir > %t.noclone.mlir
// RUN: idris-mlir-opt %s --idr-expect=holds=quantities-kept=%t.noclone.mlir -o /dev/null
// RUN: sed 's/%t: !idr.lin<i64>/%t: i64/' %t.emitted.mlir > %t.span.mlir
// RUN: %status 1 idris-mlir-opt %t.span.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.span.err
// RUN: FileCheck %s --check-prefix=SPAN < %t.span.err
// The module as emitted keeps its quantities, which are its types. A
// linear parameter made unrestricted, a linear constructor field made
// unrestricted, a field a match bound linearly (of a linear value)
// bound unrestricted (of the value made unrestricted), and a lambda's
// linear parameter made unrestricted are each an error. A binder is
// its name over its definition's span: the extra linear parameter a
// destination-passing clone takes at its function's name over the
// span of the function's one unrestricted parameter (@build.trmc,
// against the emitted module without it) is no binder Idris proved a
// quantity of, and two parameters of one definition at the one span
// under different names (@wide) are each held to their own.
// WIDENED: error: expected quantities-kept: parameter 0 of @consume has quantity w, and Idris proved 1
// FIELD: error: expected quantities-kept: the fields of @Handle::@MkHandle have other quantities than Idris proved
// BOUND: error: expected quantities-kept: bound field 0 of @open has quantity w, and Idris proved 1
// LAMBDA: error: expected quantities-kept: parameter 0 of @lam has quantity w, and Idris proved 1
// SPAN: error: expected quantities-kept: parameter 0 of @wide has quantity w, and Idris proved 1
module {
  idr.data @Handle {
    idr.ctor @MkHandle (!idr.lin<i64>, i64)
  }
  idr.func private @consume(%h: !idr.lin<i64>) -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func private @open(%h: !idr.lin<!idr.data<@Handle>>) -> i64 {
    %r = idr.match %h : !idr.lin<!idr.data<@Handle>> -> (i64) {
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
  idr.func private @lam() -> !idr.fn<(!idr.lin<i64>) -> i32> {
    %f = idr.lambda : !idr.fn<(!idr.lin<i64>) -> i32> {
    ^bb0(%l: !idr.lin<i64>):
      %u = idr.lin.use %l : !idr.lin<i64>
      %t = arith.trunci %u : i64 to i32
      idr.yield %t : i32
    }
    return %f : !idr.fn<(!idr.lin<i64>) -> i32>
  }
  idr.func private @build(%n: i64 loc("arg"("Main.idr":22:1 to :17))) -> i64 {
    return %n : i64
  }
  idr.func private @build.trmc(%n: i64 loc("arg"("Main.idr":22:1 to :17)), %h: !idr.lin<i64> loc("build"("Main.idr":22:1 to :17))) -> i64 { return %n : i64 }
  idr.func private @wide(%t: !idr.lin<i64> loc("t"("Main.idr":30:1 to :20)), %a: i64 loc("arg"("Main.idr":30:1 to :20))) -> i64 {
    return %a : i64
  }
}
