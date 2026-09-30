// RUN: idris-mlir-opt %s --idr-expect=holds=quantities-kept=%s -o /dev/null
// RUN: cp %s %t.emitted.mlir
// RUN: sed 's/%h: !idr.lin<i64>/%h: i64/; s/(!idr.lin<i64>) -> i64/(i64) -> i64/; s/idr.lin.enter %x : !idr.lin<i64>/arith.addi %x, %x : i64/' %t.emitted.mlir > %t.widened.mlir
// RUN: %status 1 idris-mlir-opt %t.widened.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.widened.err
// RUN: FileCheck %s --check-prefix=WIDENED < %t.widened.err
// RUN: sed 's/(!idr.lin<i64>, i64)/(i64, i64)/; s/%a: !idr.lin<i64>/%a: i64/' %t.emitted.mlir > %t.field.mlir
// RUN: %status 1 idris-mlir-opt %t.field.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.field.err
// RUN: FileCheck %s --check-prefix=FIELD < %t.field.err
// RUN: sed 's/!idr.lin<!idr.data<@Handle>>/!idr.data<@Handle>/g; s/%a: !idr.lin<i64>/%a: i64/' %t.emitted.mlir > %t.bound.mlir
// RUN: %status 1 idris-mlir-opt %t.bound.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.bound.err
// RUN: FileCheck %s --check-prefix=BOUND < %t.bound.err
// The module as emitted keeps its quantities, which are its types. A
// linear parameter made unrestricted, a linear constructor field made
// unrestricted, and a field a match bound linearly (of a linear value)
// bound unrestricted (of the value made unrestricted) are each an error.
// WIDENED: error: expected quantities-kept: parameter 0 of @consume has quantity w, and Idris proved 1
// FIELD: error: expected quantities-kept: the fields of @Handle::@MkHandle have other quantities than Idris proved
// BOUND: error: expected quantities-kept: bound field 0 of @open has quantity w, and Idris proved 1
module {
  idr.data @Handle {
    idr.ctor @MkHandle (!idr.lin<i64>, i64)
  }
  func.func private @consume(%h: !idr.lin<i64>) -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
  func.func private @open(%h: !idr.lin<!idr.data<@Handle>>) -> i64 {
    %r = idr.match %h : !idr.lin<!idr.data<@Handle>> -> (i64) {
    case @MkHandle(%a: !idr.lin<i64>, %b: i64) {
      idr.yield %b : i64
    }
    }
    return %r : i64
  }
  func.func @keep(%x: i64) -> i64 {
    %e = idr.lin.enter %x : !idr.lin<i64>
    %r = func.call @consume(%e) : (!idr.lin<i64>) -> i64
    return %r : i64
  }
}
