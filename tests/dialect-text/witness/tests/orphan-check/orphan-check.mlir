// RUN: idris-mlir-opt %s 2>&1 | FileCheck %s --check-prefix=ERR
// ERR: error
// GONE-NEXT: a prefix no RUN line checks
