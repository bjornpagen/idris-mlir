// RUN: idris-mlir-opt %s --idr-lower | mlir-translate --mlir-to-llvmir | FileCheck %s
// CHECK: noalias
