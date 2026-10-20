// RUN: idris-mlir-opt %s | FileCheck %s --check-prefix=PRINT
// RUN: idris-mlir-opt %s -o %t.short.mlir
// RUN: idris-mlir-opt %s --emit-bytecode -o %t.short.mlirbc
// RUN: idris-mlir-opt %t.short.mlirbc -o %t.short.again.mlir
// RUN: cmp %t.short.mlir %t.short.again.mlir
// RUN: awk 'BEGIN { print "!List = !idr.data<\"List\">"; print "#types = #idr.types<\"List\" = list [@Nil() nil, @Cons(i64, !idr.box<!List>) cons]>"; print "idr.program @long root(@root) stage(first) types #types {"; print "  idr.func @long() -> !idr.box<!List> {"; printf "    %%l = idr.constant !idr.box<!List> #idr.con<!List, @Cons, "; for (i = 0; i < 9999; i++) printf "[%d], ", i; print "[9999, #idr.con<!List, @Nil, []>] along 1>"; print "    return %l : !idr.box<!List>"; print "  }"; print "  idr.func @root() -> i64 {"; print "    %zero = arith.constant 0 : i64"; print "    return %zero : i64"; print "  }"; print "}" }' > %t.long.mlir
// RUN: idris-mlir-opt %t.long.mlir -o %t.text.mlir
// RUN: FileCheck %s --check-prefix=LONG < %t.text.mlir
// RUN: idris-mlir-opt %t.text.mlir -o %t.again.mlir
// RUN: cmp %t.text.mlir %t.again.mlir
// RUN: idris-mlir-opt %t.long.mlir --emit-bytecode -o %t.long.mlirbc
// RUN: idris-mlir-opt %t.long.mlirbc -o %t.bytecode.mlir
// RUN: cmp %t.text.mlir %t.bytecode.mlir
// RUN: sed '/%one = /s/]>$/] along 1>/' %s > %t.onerun.mlir
// RUN: not cmp -s %s %t.onerun.mlir
// RUN: not idris-mlir-opt %t.onerun.mlir -o /dev/null 2>&1 | FileCheck %s --check-prefix=ONERUN
// A list constant is flat: its cells of one constructor, linked through one
// field, are one attribute, a run, however long the list. A list is read
// into that form however it is written, cell by cell or as a run, so the
// two constants below print alike, and are the same attribute.
// A run reads back, from its text and from bytecode, as the
// same module; a run of 10^4 cells too, printed on one line, which as cells
// nested in cells would take as many levels of recursion to print, read
// and write.
// PRINT-LABEL: idr.func @same(
// PRINT-NEXT: constant !idr.box<!List> #idr.con<!List, @Cons, [1], [2], [3], [4, #idr.con<!List, @Nil, []>] along 1>
// PRINT-NEXT: constant !idr.box<!List> #idr.con<!List, @Cons, [1], [2], [3], [4, #idr.con<!List, @Nil, []>] along 1>
// One cell is a constructor, never a run of one: the run starts at two
// cells, and the one written as a run is refused.
// PRINT-LABEL: idr.func @edges(
// PRINT-NEXT: constant !idr.box<!List> #idr.con<!List, @Cons, [1, #idr.con<!List, @Nil, []>]>
// PRINT-NEXT: constant !idr.box<!List> #idr.con<!List, @Cons, [1], [2, #idr.con<!List, @Nil, []>] along 1>
// PRINT-NEXT: constant !idr.box<!List> #idr.con<!List, @Nil, []>
// ONERUN: error: expects @Cons of one cell to run along no field, got field 1
// LONG: #idr.con<!List, @Cons, [0], [1], [2], {{.*}}, [9998], [9999, #idr.con<!List, @Nil, []>] along 1>
!List = !idr.data<"List">
#types = #idr.types<
  "List" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]
>
idr.program @run root(@root) stage(first) types #types {
  idr.func @same() -> (!idr.box<!List>, !idr.box<!List>) {
    %cells = idr.constant !idr.box<!List> #idr.con<!List, @Cons, [1, #idr.con<!List, @Cons, [2, #idr.con<!List, @Cons, [3, #idr.con<!List, @Cons, [4, #idr.con<!List, @Nil, []>]>]>]>]>
    %run = idr.constant !idr.box<!List> #idr.con<!List, @Cons, [1], [2], [3], [4, #idr.con<!List, @Nil, []>] along 1>
    return %cells, %run : !idr.box<!List>, !idr.box<!List>
  }
  idr.func @edges() -> (!idr.box<!List>, !idr.box<!List>, !idr.box<!List>) {
    %one = idr.constant !idr.box<!List> #idr.con<!List, @Cons, [1, #idr.con<!List, @Nil, []>]>
    %two = idr.constant !idr.box<!List> #idr.con<!List, @Cons, [1, #idr.con<!List, @Cons, [2, #idr.con<!List, @Nil, []>]>]>
    %nil = idr.constant !idr.box<!List> #idr.con<!List, @Nil, []>
    return %one, %two, %nil : !idr.box<!List>, !idr.box<!List>, !idr.box<!List>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
