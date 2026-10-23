// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A cast out of a linear position may forget what the value's grade claims
// of its sharing, so it reaches an op that takes the bare type, and the
// program verifies; a cast into one never raises a claim, since no cast
// proves what Idris and exclusivity did not, and the cast is the error.
#Row = #idr.family<"Row" [] {
    @End ()
    @Cell (i64, i64, !idr.self)
  }>
!Cell = !idr.data<#Row @Cell>
!Claimed = !idr.graded<once, counted unique self, !Cell>
idr.program @casts root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @forgets(%x: !Claimed) -> !Cell {
    %y = idr.lin.cast %x : !Claimed -> !Cell
    idr.return %y : !Cell
  }
}

// -----

#Row = #idr.family<"Row" [] {
    @End ()
    @Cell (i64, i64, !idr.self)
  }>
!Cell = !idr.data<#Row @Cell>
!Claimed = !idr.graded<once, counted unique self, !Cell>
idr.program @casts root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @raises(%x: !Cell) -> !Claimed {
    // expected-error @below {{}}
    %y = idr.lin.cast %x : !Cell -> !Claimed
    idr.return %y : !Claimed
  }
}
