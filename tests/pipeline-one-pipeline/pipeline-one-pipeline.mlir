// RUN: idris-mlir -c %s -o %t.driver.o
// RUN: idris-mlir-opt %s --idr-target --idr-pipeline -o %t.pipeline.mlir
// RUN: idris-mlir -c %t.pipeline.mlir -o %t.pipeline.o
// RUN: cmp %t.driver.o %t.pipeline.o
// idris-mlir runs one pipeline, the one idris-mlir-opt runs as
// --idr-pipeline once --idr-target has given the module the build's
// target, as idris-mlir gives it. A module of the LLVM dialect alone goes
// to LLVM as it is (obs-lowered-input), so the pipeline's output, compiled
// by idris-mlir, is the same object, byte for byte, as the module
// compiled by idris-mlir directly. Which steps there are, and their order,
// are the pipeline's own business, and no part of this check.
idr.program @"one-pipeline" root(@Main.main) stage(higher) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %k : i64
    return %y : i64
  }
  idr.func @loop(%n: i64, %f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %z = idr.call @loop(%m, %f, %y) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %k = arith.extui %c : i32 to i64
    %f = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %n = arith.constant 5 : i64
    %zero = arith.constant 0 : i64
    %r = idr.call @loop(%n, %f, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
