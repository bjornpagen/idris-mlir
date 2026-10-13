// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='!idr.lazy' < %t.mlir
// A trusted library's effect happens where its value is demanded, so a
// label whose function reaches an effect the program's outside observes
// (output here, as trace's) is `by_name`: its cell keeps no value, and
// every force runs it. One that forges a world only to use an array, which
// nothing outside sees, keeps its memo. So does a label a static constant
// names, effect or not: a top-level constant names one value, evaluated
// once, and its effect is observed that once. Which ops the outside
// observes is the trait on their class, said once beside each op: a
// clock reading is one, and an error's text, the same at every call, is
// none, though both are IO in the world's order.
// CHECK-DAG: idr.ctor @traced (i64) by_name{{$}}
// CHECK-DAG: idr.ctor @sized (i64){{$}}
// CHECK-DAG: idr.ctor @shout (){{$}}
// CHECK-DAG: idr.ctor @clocked (i64) by_name{{$}}
// CHECK-DAG: idr.ctor @errtext (i64){{$}}
module attributes {idr.program} {
  idr.func private @traced(%x: i64) -> i64 attributes {total} {
    %w = idr.world.new
    %s = idr.constant "forced\0A" : !idr.str
    %w1 = idr.io.put_str %s, %w
    return %x : i64
  }
  idr.func private @sized(%n: i64) -> i64 attributes {total} {
    %w = idr.world.new
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64>
    %l = arith.index_cast %d : index to i64
    return %l : i64
  }
  idr.func private @shout() -> i64 attributes {total} {
    %w = idr.world.new
    %s = idr.constant "once\0A" : !idr.str
    %w1 = idr.io.put_str %s, %w
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func private @clocked(%x: i64) -> i64 attributes {total} {
    %w = idr.world.new
    %t, %w1 = idr.io.clock_monotonic %w
    %r = arith.addi %t, %x : i64
    return %r : i64
  }
  idr.func private @errtext(%x: i64) -> i64 attributes {total} {
    %w = idr.world.new
    %s, %w1 = idr.io.strerror %x, %w : !idr.str
    return %x : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = idr.suspend @traced(%n) : (i64) -> !idr.lazy<i64>
    %u = idr.suspend @sized(%n) : (i64) -> !idr.lazy<i64>
    %k = idr.constant #idr.closure<@shout, []> : !idr.lazy<i64>
    %e = idr.suspend @clocked(%n) : (i64) -> !idr.lazy<i64>
    %f = idr.suspend @errtext(%n) : (i64) -> !idr.lazy<i64>
    %a = idr.force %t : !idr.lazy<i64> -> i64
    %b = idr.force %u : !idr.lazy<i64> -> i64
    %d = idr.force %k : !idr.lazy<i64> -> i64
    %g = idr.force %e : !idr.lazy<i64> -> i64
    %h = idr.force %f : !idr.lazy<i64> -> i64
    %ab = arith.addi %a, %b : i64
    %abd = arith.addi %ab, %d : i64
    %abdg = arith.addi %abd, %g : i64
    %abdgh = arith.addi %abdg, %h : i64
    %w2 = idr.io.put_int signed %abdgh, %w1 : i64
    return %w2 : !idr.world
  }
}
