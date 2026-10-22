// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A value Idris proved used once is used at most once on every path, field
// by field, as a match binds each field of its scrutinee once: reading two
// fields of it is no second use, and the program verifies; reading one
// field twice is a second use of that field, and the second read is the
// error.
#Row = #idr.family<"Row" [] {
    @End ()
    @Cell (i64, i64, !idr.self)
  }>
!Cell = !idr.data<#Row @Cell>
!Once = !idr.graded<once, counted, !Cell>
idr.program @fields root(@main) stage(graded) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @both(%x: !Once) -> i64 {
    %a = idr.data.field %x[0] : !Once -> i64
    %b = idr.data.field %x[1] : !Once -> i64
    %s = arith.addi %a, %b : i64
    idr.return %s : i64
  }
}

// -----

#Row = #idr.family<"Row" [] {
    @End ()
    @Cell (i64, i64, !idr.self)
  }>
!Cell = !idr.data<#Row @Cell>
!Once = !idr.graded<once, counted, !Cell>
idr.program @fields root(@main) stage(graded) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @again(%x: !Once) -> i64 {
    %a = idr.data.field %x[0] : !Once -> i64
    // expected-error @below {{}}
    %b = idr.data.field %x[0] : !Once -> i64
    %s = arith.addi %a, %b : i64
    idr.return %s : i64
  }
}
