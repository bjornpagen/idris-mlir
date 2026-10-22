// RUN: idris-mlir-opt %s --idr-pipeline=from=owned | mlir-translate --mlir-to-llvmir | FileCheck %s
// CHECK: noalias
