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
// nothing to do. The unfitted input fails cells-fit, by name, after whatever
// the layouts it could not build reported.
// @S16 is a record of 16 strings, so widths are built by nesting. Boxing
// is the values' type alone: a boxed record's values are !idr.box of it.
// NEEDS-ACCEPTANCE: the printed types, as C01's printer and layout::fit's retyping write them, and cells-fit's text.

// Widest first: @W (256) leaves @Holder's cell at 130, which fits, and
// @V (128) stays unboxed; then @W's own cell holds 256 through @S16. The
// grade of a linear argument is kept around its new carrier.
// CHECK: @keepW(%{{[^:]*}}: !idr.lin<!idr.box<!{{[A-Za-z0-9_$.]+}}>>)
// CHECK: @keepV(%{{[^:]*}}: !{{[A-Za-z0-9_$.]+}})
// UNFIT: expected cells-fit: {{.*}} holds 385 counted references
!S16 = !idr.data<"S16", plain [@s(!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)]>
!W = !idr.data<"W", plain [@w(!S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16)]>
!V = !idr.data<"V", plain [@v(!S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16)]>
!Holder = !idr.data<"Holder", plain [@h(!W, !V, !idr.str)]>
module {
  idr.func private @keepW(%w: !idr.lin<!W>) -> i64 {
    %v = idr.lin.use %w : !idr.lin<!W>
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func private @keepV(%v: !V) -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// Ties go to the smaller name: @P and @Q take 130 each, and boxing @P
// leaves 131 in @Two's cell.
// CHECK-LABEL: {{//}} -----
// UNFIT: expected cells-fit: {{.*}} holds 260 counted references
!S16 = !idr.data<"S16", plain [@s(!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)]>
!P = !idr.data<"P", plain [@p(!S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !idr.str, !idr.str)]>
!Q = !idr.data<"Q", plain [@q(!S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !idr.str, !idr.str)]>
!Two = !idr.data<"Two", plain [@t(!P, !Q)]>
module {
  idr.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// An array's element is a cell's worth of slots too: an element of @W
// would hold 256, so @W becomes a box, and then @S16 in @W's cell.
// CHECK-LABEL: {{//}} -----
// CHECK: @first(%{{[^:]*}}: memref<?x!idr.box<!{{[A-Za-z0-9_$.]+}}>, #idr.world>)
// UNFIT: expected cells-fit: {{.*}} holds 256 counted references
!S16 = !idr.data<"S16", plain [@s(!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)]>
!W = !idr.data<"W", plain [@w(!S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16)]>
module {
  idr.func private @first(%a: memref<?x!W, #idr.world>) -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
  idr.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A closure sum is made here, of one label that captures @W: two of its
// values would put 512 in @Cell's cell, so the sum becomes a box (fit
// runs once closures are sums), then @W in the sum's cell, then @S16.
// CHECK-LABEL: {{//}} -----
// CHECK: idr.func private @pack(
// CHECK-SAME: -> !idr.box<
// CHECK: con @k(
// CHECK-SAME: -> !idr.box<
!S16 = !idr.data<"S16", plain [@s(!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)]>
!W = !idr.data<"W", plain [@w(!S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16)]>
!Cell = !idr.data<"Cell", plain [@c(!idr.fn<() -> (i64)>, !idr.fn<() -> (i64)>)]>
module {
  idr.func private @k(%w: !W) -> i64 {
    %one = arith.constant 1 : i64
    return %one : i64
  }
  idr.func private @strings(%s: !idr.str) -> !S16 {
    %v = idr.con @s(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) : (!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str) -> !S16
    return %v : !S16
  }
  idr.func private @wide(%s: !idr.str) -> !W {
    %t = idr.call @strings(%s) : (!idr.str) -> !S16
    %v = idr.con @w(%t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t, %t) : (!S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16) -> !W
    return %v : !W
  }
  idr.func private @pack(%w: !W) -> !idr.box<!Cell> {
    %f = idr.closure @k(%w) : (!W) -> !idr.fn<() -> (i64)>
    %c = idr.con @c(%f, %f) : (!idr.fn<() -> (i64)>, !idr.fn<() -> (i64)>) -> !idr.box<!Cell>
    return %c : !idr.box<!Cell>
  }
  idr.func @main() -> i64 {
    %s = idr.constant "s" : !idr.str
    %w = idr.call @wide(%s) : (!idr.str) -> !W
    %c = idr.call @pack(%w) : (!W) -> !idr.box<!Cell>
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// Nothing to do: 15 of @S16 and 15 strings are 255, which a header counts.
// CHECK-LABEL: {{//}} -----
!S16 = !idr.data<"S16", plain [@s(!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)]>
!Fits = !idr.data<"Fits", plain [@f(!S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)]>
module {
  idr.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A sum of several constructors is looked through, never boxed: a read of
// one of its fields may already run where its constructor is not known.
// @U's slots hold @W's 256, so @W becomes a box inside it, then @S16.
// CHECK-LABEL: {{//}} -----
// UNFIT: expected cells-fit: {{.*}} holds 256 counted references
!S16 = !idr.data<"S16", plain [@s(!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)]>
!W = !idr.data<"W", plain [@w(!S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16, !S16)]>
!U = !idr.data<"U", plain [@a(!W), @b(!idr.str)]>
!Hold = !idr.data<"Hold", plain [@h(!U)]>
module {
  idr.func @main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
