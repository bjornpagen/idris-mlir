// RUN: idris-mlir-opt %s --idr-expect=holds=quantities-kept=%s -o /dev/null
// RUN: cp %s %t.emitted.mlir
// RUN: sed 's/idr.quantity = "1"/idr.quantity = "w"/' %t.emitted.mlir > %t.widened.mlir
// RUN: %status 1 idris-mlir-opt %t.widened.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.widened.err
// RUN: FileCheck %s --check-prefix=WIDENED < %t.widened.err
// RUN: sed 's/ {idr.quantity = "w"}//' %t.emitted.mlir > %t.dropped.mlir
// RUN: %status 1 idris-mlir-opt %t.dropped.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.dropped.err
// RUN: FileCheck %s --check-prefix=DROPPED < %t.dropped.err
// RUN: sed 's/quantities = \["1", "w"\]/quantities = ["w", "w"]/' %t.emitted.mlir > %t.field.mlir
// RUN: %status 1 idris-mlir-opt %t.field.mlir --idr-expect=holds=quantities-kept=%t.emitted.mlir -o /dev/null 2> %t.field.err
// RUN: FileCheck %s --check-prefix=FIELD < %t.field.err
// The module as emitted keeps its quantities. A linear parameter made
// unrestricted, a parameter without a quantity, and a constructor field
// widened are each an error.
// WIDENED: error: expected quantities-kept: parameter 0 of @consume has quantity w, and Idris proved 1
// DROPPED: error: expected quantities-kept: parameter 0 of @keep has no quantity
// FIELD: error: expected quantities-kept: the fields of @Handle::@MkHandle have other quantities than Idris proved
module {
  idr.data @Handle {
    idr.ctor @MkHandle tag 0 (i64, i64) {quantities = ["1", "w"]}
  }
  func.func private @consume(%h: i64 {idr.quantity = "1"}) -> i64 {
    return %h : i64
  }
  func.func @keep(%x: i64 {idr.quantity = "w"}) -> i64 {
    %r = func.call @consume(%x) : (i64) -> i64
    return %r : i64
  }
}
