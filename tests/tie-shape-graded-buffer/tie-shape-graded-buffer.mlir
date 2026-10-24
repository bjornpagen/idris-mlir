// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A tie of a value array's buffer used once keeps the buffer's grade with
// its type, and the axes it names are dynamic axes of the buffer under the
// grade, which its inference reads, one size each: a tie of axis 0 with
// one size verifies, and the same tie given no size is the error, which
// its inference reports.
!Once = !idr.graded<once, counted, memref<?xi64>>
idr.program @ties root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @sized(%x: !Once, %n: index) -> !Once {
    %y = idr.array.tie_shape %x axes [0] dims(%n) : !Once -> !Once
    idr.return %y : !Once
  }
}

// -----

!Once = !idr.graded<once, counted, memref<?xi64>>
idr.program @ties root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @unsized(%x: !Once, %n: index) -> !Once {
    // expected-error @below {{}}
    %y = idr.array.tie_shape %x axes [0] dims() : !Once -> !Once
    idr.return %y : !Once
  }
}
