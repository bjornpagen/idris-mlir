// RUN: idris-mlir-opt %s -split-input-file --idr-defunctionalize --idr-expect=holds=calls=@main:@label -o /dev/null
// RUN: %status 1 idris-mlir-opt %s -split-input-file --idr-expect=holds=calls=@main:@label -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: idris-mlir-opt %s -split-input-file --idr-expect=holds=labels-least -o /dev/null
// BEFORE: expected calls: @main {{.*}}@label
// BEFORE: expected calls: @main {{.*}}@label
// BEFORE: expected calls: @main {{.*}}@label
// A closure converts whatever grade it moves through: each edge it moves
// along (lin.enter, lin.use, a constructor's field, a match's region
// argument) joins two values of one carrier, the type without its
// outermost grade, so its one label fits the key, and the apply becomes a
// call of the label. The quantities Idris proved stay where they were,
// which the contracts check of the pass. Each split is one grade shape,
// and in each the call was not there before the pass (one failure per
// split).

// A plain closure, entered into a linear value and used back as plain,
// then kept in a constructor's field.
!Box = !idr.data<"Box">
#types = #idr.types<
  "Box" = plain [@MkBox(!idr.fn<(i64) -> (i64)>)]
>
idr.program @"grade-plain" root(@main) stage(higher) types #types {
  idr.func @label(%k: i64, %x: i64) -> i64 attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @main() -> i64 {
    %k = arith.constant 1 : i64
    %f = idr.closure @label(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %fl = idr.lin.enter %f : !idr.lin<!idr.fn<(i64) -> (i64)>>
    %fu = idr.lin.use %fl : !idr.lin<!idr.fn<(i64) -> (i64)>>
    %b = idr.con !Box @MkBox(%fu : !idr.fn<(i64) -> (i64)>)
    %r = idr.match %b : !Box -> (i64) {
    case @MkBox(%g: !idr.fn<(i64) -> (i64)>) {
      %two = arith.constant 2 : i64
      %y = idr.apply %g(%two) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
}

// -----

// A closure that takes a linear argument: the argument stays linear
// through the dispatch to the label's call.
!Box = !idr.data<"Box">
#types = #idr.types<
  "Box" = plain [@MkBox(!idr.fn<(!idr.lin<i64>) -> (i64)>)]
>
idr.program @"grade-linear-argument" root(@main) stage(higher) types #types {
  idr.func @label(%k: i64, %x: !idr.lin<i64>) -> i64 attributes {total} {
    %v = idr.lin.use %x : !idr.lin<i64>
    %r = arith.addi %k, %v : i64
    return %r : i64
  }
  idr.func @main() -> i64 {
    %k = arith.constant 1 : i64
    %f = idr.closure @label(%k) : (i64) -> !idr.fn<(!idr.lin<i64>) -> (i64)>
    %b = idr.con !Box @MkBox(%f : !idr.fn<(!idr.lin<i64>) -> (i64)>)
    %r = idr.match %b : !Box -> (i64) {
    case @MkBox(%g: !idr.fn<(!idr.lin<i64>) -> (i64)>) {
      %two = arith.constant 2 : i64
      %x = idr.lin.enter %two : !idr.lin<i64>
      %y = idr.apply %g(%x) : !idr.fn<(!idr.lin<i64>) -> (i64)>
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
}

// -----

// A closure that returns a linear result, itself linear because it is
// entered at once, kept in a linear constructor's field and used once: the
// result of the dispatch keeps its grade.
!Box = !idr.data<"Box">
#types = #idr.types<
  "Box" = plain [@MkBox(!idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>)]
>
idr.program @"grade-linear-result" root(@main) stage(higher) types #types {
  idr.func @label(%k: i64, %x: i64) -> !idr.lin<i64> attributes {total} {
    %s = arith.addi %k, %x : i64
    %r = idr.lin.enter %s : !idr.lin<i64>
    return %r : !idr.lin<i64>
  }
  idr.func @main() -> i64 {
    %k = arith.constant 1 : i64
    %f = idr.closure @label(%k) : (i64) -> !idr.fn<(i64) -> (!idr.lin<i64>)>
    %fl = idr.lin.enter %f : !idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>
    %b = idr.con !idr.lin<!Box> @MkBox(%fl : !idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>)
    %r = idr.match %b : !idr.lin<!Box> -> (i64) {
    case @MkBox(%g: !idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>) {
      %two = arith.constant 2 : i64
      %gu = idr.lin.use %g : !idr.lin<!idr.fn<(i64) -> (!idr.lin<i64>)>>
      %y = idr.apply %gu(%two) : !idr.fn<(i64) -> (!idr.lin<i64>)>
      %v = idr.lin.use %y : !idr.lin<i64>
      idr.yield %v : i64
    }
    }
    return %r : i64
  }
}
