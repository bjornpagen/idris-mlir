// NEEDS-ACCEPTANCE: that a refusal the frontend writes round-trips through text and bytecode: its rule (one word, and a phrase of two as a string), its location and its words.
// RUN: idris-mlir-opt %s -o %t.first.mlir
// RUN: idris-mlir-opt %t.first.mlir -o %t.second.mlir
// RUN: cmp %t.first.mlir %t.second.mlir
// RUN: idris-mlir-opt %s --emit-bytecode -o %t.mlirbc
// RUN: idris-mlir-opt %t.mlirbc -o %t.bytecode.mlir
// RUN: cmp %t.first.mlir %t.bytecode.mlir
// RUN: FileCheck %s < %t.first.mlir
// CHECK-DAG: #idr.refusal<cycle,
// CHECK-DAG: #idr.refusal<"dependent field",
// CHECK-DAG: "M.idr":1:1
// CHECK-DAG: "a knot of references"
module attributes {idr.refusals = [#idr.refusal<cycle, loc("M.idr":1:1), "a knot of references">,
                                   #idr.refusal<"dependent field", loc("M.idr":2:3), "a field whose type a value decides">]} {
}
