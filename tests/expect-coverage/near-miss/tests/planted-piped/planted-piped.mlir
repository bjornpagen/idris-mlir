// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=piped=@main})' -o /dev/null
// piped holds of what the pipeline made of this module
