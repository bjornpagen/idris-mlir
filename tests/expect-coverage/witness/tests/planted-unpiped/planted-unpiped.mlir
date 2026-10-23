// RUN: idris-mlir-opt %s -split-input-file --idr-expect=holds=unpiped=@main -verify-diagnostics -o /dev/null
// unpiped holds of the first module and fails on the second, each as it
// is written, which no pass of the compiler made
// expected-error @+1 {{expected unpiped: }}
