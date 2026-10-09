// RUN: idris-mlir-opt %s | FileCheck %s --check-prefix=PRINT
// RUN: idris-mlir-opt %s --cse | FileCheck %s
// RUN: idris-mlir-opt %s -o %t.short.mlir
// RUN: idris-mlir-opt %s --emit-bytecode -o %t.short.mlirbc
// RUN: idris-mlir-opt %t.short.mlirbc -o %t.short.again.mlir
// RUN: cmp %t.short.mlir %t.short.again.mlir
// RUN: awk 'BEGIN { print "module {"; print "  idr.data @List box {"; print "    idr.ctor @Nil ()"; print "    idr.ctor @Cons (i64, !idr.box<@List>)"; print "  }"; print "  func.func @long() -> !idr.box<@List> {"; printf "    %%l = idr.constant #idr.con<@List::@Cons, "; for (i = 0; i < 10000; i++) { cell = i ? ", [%d]" : "[%d]"; printf cell, i }; print " tail #idr.con<@List::@Nil, []> along 1> : !idr.box<@List>"; print "    return %l : !idr.box<@List>"; print "  }"; print "}" }' > %t.long.mlir
// RUN: idris-mlir-opt %t.long.mlir -o %t.text.mlir
// RUN: FileCheck %s --check-prefix=LONG < %t.text.mlir
// RUN: idris-mlir-opt %t.text.mlir -o %t.again.mlir
// RUN: cmp %t.text.mlir %t.again.mlir
// RUN: idris-mlir-opt %t.long.mlir --emit-bytecode -o %t.long.mlirbc
// RUN: idris-mlir-opt %t.long.mlirbc -o %t.bytecode.mlir
// RUN: cmp %t.text.mlir %t.bytecode.mlir
// A list constant is flat: its cells of one constructor, linked through one
// field, are one attribute, a run, however long the list. A list is read
// into that form however it is written, cell by cell or as a run, so the
// two constants below print alike, and are the same attribute: cse keeps
// one of them. A run reads back, from its text and from bytecode, as the
// same module; a run of 10^4 cells too, printed on one line, which as cells
// nested in cells would take as many levels of recursion to print, read
// and write.
// PRINT-LABEL: func.func @same(
// PRINT-NEXT: idr.constant #idr.con<@List::@Cons, [1], [2], [3], [4] tail #idr.con<@List::@Nil, []> along 1> : !idr.box<@List>
// PRINT-NEXT: idr.constant #idr.con<@List::@Cons, [1], [2], [3], [4] tail #idr.con<@List::@Nil, []> along 1> : !idr.box<@List>
// CHECK-LABEL: func.func @same(
// CHECK-NEXT: %[[L:.*]] = idr.constant #idr.con<@List::@Cons, [1], [2], [3], [4] tail #idr.con<@List::@Nil, []> along 1> : !idr.box<@List>
// CHECK-NEXT: return %[[L]], %[[L]]
// LONG: #idr.con<@List::@Cons, [0], [1], [2], {{.*}}, [9998], [9999] tail #idr.con<@List::@Nil, []> along 1>
module {
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  func.func @same() -> (!idr.box<@List>, !idr.box<@List>) {
    %cells = idr.constant #idr.con<@List::@Cons, [1, #idr.con<@List::@Cons, [2, #idr.con<@List::@Cons, [3, #idr.con<@List::@Cons, [4, #idr.con<@List::@Nil, []>]>]>]>]> : !idr.box<@List>
    %run = idr.constant #idr.con<@List::@Cons, [1], [2], [3], [4] tail #idr.con<@List::@Nil, []> along 1> : !idr.box<@List>
    return %cells, %run : !idr.box<@List>, !idr.box<@List>
  }
}
