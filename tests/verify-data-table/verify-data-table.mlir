// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: sed '/^\/\/ -----/,$d' %s > %t.first.mlir
// RUN: idris-mlir-opt %t.first.mlir | FileCheck %s
// RUN: idris-mlir-opt %t.first.mlir --emit-bytecode -o %t.first.mlirbc
// RUN: idris-mlir-opt %t.first.mlirbc | FileCheck %s
// A data type is its name wherever it occurs, and the program's table
// holds every body once, in name order: a label's function and by_name
// and an instance round-trip through the table's text and bytecode alike,
// and a type the program reaches that its table does not declare, a table
// out of name order, a name with two bodies, and a member that holds a
// type nothing defines (a table is closed: what a member holds is a
// member) are refused.

// CHECK: #data_types = #idr.types<
// CHECK-NEXT: "Memo" = memo [@run() label @force by_name, @running() running, @forced(i64) forced]
// CHECK-NEXT: "Pair" = plain [@P(i64, !idr.box<!Pair>)] instance #idr.instance<"Main.Pair", []>
// CHECK-NEXT: >
// CHECK: idr.program @table root(@root) stage(higher) types #data_types {
// CHECK: idr.func @hold(%{{.*}}: !idr.box<!Pair>, %{{.*}}: !idr.box<!Memo>)
!Pair = !idr.data<"Pair">
!Memo = !idr.data<"Memo">
#types = #idr.types<
  "Memo" = memo [@run() label @force by_name, @running() running, @forced(i64) forced],
  "Pair" = plain [@P(i64, !idr.box<!Pair>)] instance #idr.instance<"Main.Pair", []>
>
idr.program @table root(@root) stage(higher) types #types {
  idr.func @force(%m: !idr.box<!Memo>) -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
  idr.func @hold(%p: !idr.box<!Pair>, %m: !idr.box<!Memo>) {
    return
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T">
// expected-error @+1 {{'idr.program' op reaches the data type "T", which its table does not declare}}
idr.program @undeclared root(@root) stage(first) types #idr.types<> {
  idr.func @hold(%t: !T) {
    return
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// expected-error @below {{the data types are in name order, each once, and "B" comes before "A"}}
#types = #idr.types<
  "B" = plain [@B()],
  "A" = plain [@A()]
>
idr.program @order root(@root) stage(first) types #types {
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// expected-error @below {{the data type "T" has another body already}}
#types = #idr.types<"T" = plain [@A(i64)], "T" = plain [@B()]>
idr.program @twice root(@root) stage(first) types #types {
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!Pair = !idr.data<"Pair">
!Missing = !idr.data<"Missing">
// expected-error @+2 {{the data type "Pair" holds "Missing", which nothing defines}}
#types = #idr.types<
  "Pair" = plain [@P(i64, !idr.box<!Missing>)]
>
idr.program @open root(@root) stage(first) types #types {
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
