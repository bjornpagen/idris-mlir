// RUN: not idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=refuted=@main})' -o /dev/null 2>&1 | FileCheck %s
// CHECK: {{expected refuted: }}
