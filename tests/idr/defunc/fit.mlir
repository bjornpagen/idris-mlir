// RUN: idris-mlir-opt %s -split-input-file --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir -split-input-file --idr-expect=holds=cells-fit -o /dev/null
// RUN: idris-mlir-opt %t.mlir -split-input-file --idr-defunctionalize > %t.again.mlir
// RUN: diff %t.mlir %t.again.mlir
// RUN: not idris-mlir-opt %s -split-input-file --idr-expect=holds=cells-fit -o /dev/null 2>&1 | FileCheck %s --check-prefix=UNFIT
// A cell's header counts its object slots in 8 bits, and an unboxed sum
// spreads its slots over the cell that holds it. Once the types are final,
// idr-defunctionalize makes a box of each record or closure sum a cell
// cannot hold, the widest first and ties by name, until every cell fits
// (cells-fit), and retypes its values everywhere; a second run finds
// nothing to do. The unfitted input fails cells-fit, by name.
// @S16 is a record of 16 strings, so widths are built by nesting.

// Widest first: @W (256) leaves @Holder's cell at 130, which fits, and
// @V (128) stays unboxed; then @W's own cell holds 256 through @S16. The
// grade of a linear argument is kept around its new carrier.
// CHECK-DAG: idr.data @W box {
// CHECK-DAG: idr.data @S16 box {
// CHECK-DAG: idr.data @V {
// CHECK: @keepW(%{{.*}}: !idr.lin<!idr.box<@W>>)
// CHECK: @keepV(%{{.*}}: !idr.data<@V>)
// UNFIT: cells-fit: the cell of @Holder::@h holds 385 counted references
module attributes {idr.program} {
  idr.data @S16 {
    idr.ctor @s (!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)
  }
  idr.data @W {
    idr.ctor @w (!idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>)
  }
  idr.data @V {
    idr.ctor @v (!idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>)
  }
  idr.data @Holder box {
    idr.ctor @h (!idr.data<@W>, !idr.data<@V>, !idr.str)
  }
  func.func private @keepW(%w: !idr.lin<!idr.data<@W>>) -> i64 {
    %v = idr.lin.use %w : !idr.lin<!idr.data<@W>>
    %z = arith.constant 0 : i64
    return %z : i64
  }
  func.func private @keepV(%v: !idr.data<@V>) -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
  func.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// Ties go to the smaller name: @P and @Q take 130 each, and boxing @P
// leaves 131 in @Two's cell.
// CHECK-LABEL: // -----
// CHECK-DAG: idr.data @P box {
// CHECK-DAG: idr.data @Q {
// CHECK-DAG: idr.data @S16 {
// UNFIT: cells-fit: the cell of @Two::@t holds 260 counted references
module attributes {idr.program} {
  idr.data @S16 {
    idr.ctor @s (!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)
  }
  idr.data @P {
    idr.ctor @p (!idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.str, !idr.str)
  }
  idr.data @Q {
    idr.ctor @q (!idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.str, !idr.str)
  }
  idr.data @Two box {
    idr.ctor @t (!idr.data<@P>, !idr.data<@Q>)
  }
  func.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// An array's element is a cell's worth of slots too: an element of @W
// would hold 256, so @W becomes a box, and then @S16 in @W's cell.
// CHECK-LABEL: // -----
// CHECK-DAG: idr.data @W box {
// CHECK-DAG: idr.data @S16 box {
// CHECK: @first(%{{.*}}: memref<?x!idr.box<@W>>)
// UNFIT: cells-fit: an element of an array of @W holds 256 counted references
module attributes {idr.program} {
  idr.data @S16 {
    idr.ctor @s (!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)
  }
  idr.data @W {
    idr.ctor @w (!idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>)
  }
  func.func private @first(%a: memref<?x!idr.data<@W>>) -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
  func.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A closure sum is made here, of one label that captures @W: two of its
// values would put 512 in @Cell's cell, so the sum becomes a box (fit
// runs once closures are sums), then @W in the sum's cell, then @S16.
// CHECK-LABEL: // -----
// CHECK-DAG: idr.data @{{fn\$[0-9]+}} box closures {
// CHECK-DAG: idr.data @W box {
// CHECK-DAG: idr.data @S16 box {
module attributes {idr.program} {
  idr.data @S16 {
    idr.ctor @s (!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)
  }
  idr.data @W {
    idr.ctor @w (!idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>)
  }
  idr.data @Cell box {
    idr.ctor @c (!idr.fn<() -> (i64)>, !idr.fn<() -> (i64)>)
  }
  func.func private @k(%w: !idr.data<@W>) -> i64 {
    %one = arith.constant 1 : i64
    return %one : i64
  }
  func.func private @strings(%s: !idr.str) -> !idr.data<@S16> {
    %v = idr.con @S16::@s(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) : (!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str) -> !idr.data<@S16>
    return %v : !idr.data<@S16>
  }
  func.func private @wide(%s: !idr.str) -> !idr.data<@W> {
    %t = func.call @strings(%s) : (!idr.str) -> !idr.data<@S16>
    %v = idr.con @W::@w(%t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t) : (!idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>) -> !idr.data<@W>
    return %v : !idr.data<@W>
  }
  func.func private @pack(%w: !idr.data<@W>) -> !idr.box<@Cell> {
    %f = idr.closure @k(%w) : (!idr.data<@W>) -> !idr.fn<() -> (i64)>
    %c = idr.con @Cell::@c(%f, %f) : (!idr.fn<() -> (i64)>, !idr.fn<() -> (i64)>) -> !idr.box<@Cell>
    return %c : !idr.box<@Cell>
  }
  func.func @main() -> i64 {
    %s = idr.constant "s" : !idr.str
    %w = func.call @wide(%s) : (!idr.str) -> !idr.data<@W>
    %c = func.call @pack(%w) : (!idr.data<@W>) -> !idr.box<@Cell>
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// Nothing to do: 15 of @S16 and 15 strings are 255, which a header counts.
// CHECK-LABEL: // -----
// CHECK-DAG: idr.data @S16 {
// CHECK-DAG: idr.data @Fits box {
module attributes {idr.program} {
  idr.data @S16 {
    idr.ctor @s (!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)
  }
  idr.data @Fits box {
    idr.ctor @f (!idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)
  }
  func.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A sum of several constructors is looked through, never boxed: a read of
// one of its fields may already run where its constructor is not known.
// @U's slots hold @W's 256, so @W becomes a box inside it, then @S16.
// CHECK-LABEL: // -----
// CHECK-DAG: idr.data @U {
// CHECK-DAG: idr.data @W box {
// CHECK-DAG: idr.data @S16 box {
// UNFIT: cells-fit: the cell of @Hold::@h holds 256 counted references
module attributes {idr.program} {
  idr.data @S16 {
    idr.ctor @s (!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)
  }
  idr.data @W {
    idr.ctor @w (!idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>, !idr.data<@S16>)
  }
  idr.data @U {
    idr.ctor @a (!idr.data<@W>)
    idr.ctor @b (!idr.str)
  }
  idr.data @Hold box {
    idr.ctor @h (!idr.data<@U>)
  }
  func.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
