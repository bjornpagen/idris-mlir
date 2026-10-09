// RUN: idris-mlir-opt %s | FileCheck %s
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s
// A closure's type holds a function type and is written as MLIR writes
// one: a single result without parentheses, unless it is a function type
// itself. The parser reads a single result in parentheses too, which is how
// the frontend writes every result list.

// CHECK: func.func private @closures(!idr.fn<(i64) -> i64>, !idr.fn<() -> ()>, !idr.fn<(i64) -> (i64, i64)>, !idr.fn<(i64) -> ((i64) -> i64)>, !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>)
func.func private @closures(!idr.fn<(i64) -> (i64)>, !idr.fn<() -> ()>,
                            !idr.fn<(i64) -> (i64, i64)>, !idr.fn<(i64) -> ((i64) -> (i64))>,
                            !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>)
