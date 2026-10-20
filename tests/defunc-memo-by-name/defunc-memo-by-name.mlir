// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=by-name=@traced,not-by-name=@sized,not-by-name=@shout,by-name=@clocked,not-by-name=@errtext' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=by-name=@traced,not-by-name=@sized,not-by-name=@shout,by-name=@clocked,not-by-name=@errtext' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=not-by-name=@traced' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=by-name=@sized' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=by-name=@shout' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=not-by-name=@clocked' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=by-name=@errtext' -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=labels-least -o /dev/null
// BEFORE-DAG: expected by-name: {{.*}}@traced
// BEFORE-DAG: expected not-by-name: {{.*}}@sized
// BEFORE-DAG: expected not-by-name: {{.*}}@shout
// BEFORE-DAG: expected by-name: {{.*}}@clocked
// BEFORE-DAG: expected not-by-name: {{.*}}@errtext
// A trusted library's effect happens where its value is demanded, so a
// label whose function reaches an effect the program's outside observes
// (output here, as trace's) is `by_name`: its cell keeps no value, and
// every force runs it. One that forges a world only to use an array, which
// nothing outside sees, keeps its memo. So does a label a static constant
// names, effect or not: a top-level constant names one value, evaluated
// once, and its effect is observed that once. Which ops the outside
// observes is the trait on their class, said once beside each op: a
// clock reading is one, and an error's text, the same at every call, is
// none, though both are IO in the world's order. @Main.main forces the
// cells of @traced and of @shout twice each, so what it prints says which
// cells kept their memo (`forced` twice, `once` once), and it prints
// whether the clock reading came after the byte, not the reading, so that
// its output is the same on every run and the program before the pass and
// after it print alike on every byte. Each property is flipped once after
// the pass, and each flip fails.
idr.program @"memo-by-name" root(@Main.main) stage(higher) types #idr.types<> {
  idr.func @traced(%x: i64) -> i64 attributes {total} {
    %w = idr.world.new
    %s = idr.constant !idr.str "forced\0A"
    %w1 = idr.io.put_str %s, %w
    return %x : i64
  }
  idr.func @sized(%n: i64) -> i64 attributes {total} {
    %w = idr.world.new
    %z = arith.constant 0 : i64
    %a, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<?xi64, #idr.world>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?xi64, #idr.world>
    %l = arith.index_cast %d : index to i64
    return %l : i64
  }
  idr.func @shout() -> i64 attributes {total} {
    %w = idr.world.new
    %s = idr.constant !idr.str "once\0A"
    %w1 = idr.io.put_str %s, %w
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @clocked(%x: i64) -> i64 attributes {total} {
    %w = idr.world.new
    %t, %w1 = idr.io.clock_monotonic %w
    %r = arith.addi %t, %x : i64
    return %r : i64
  }
  idr.func @errtext(%x: i64) -> i64 attributes {total} {
    %w = idr.world.new
    %s, %w1 = idr.io.strerror %x, %w : !idr.str
    return %x : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = idr.suspend @traced(%n) : (i64) -> !idr.lazy<i64>
    %u = idr.suspend @sized(%n) : (i64) -> !idr.lazy<i64>
    %k = idr.constant !idr.lazy<i64> #idr.closure<@shout, []>
    %e = idr.suspend @clocked(%n) : (i64) -> !idr.lazy<i64>
    %f = idr.suspend @errtext(%n) : (i64) -> !idr.lazy<i64>
    %a = idr.force %t : !idr.lazy<i64> -> i64
    %a2 = idr.force %t : !idr.lazy<i64> -> i64
    %b = idr.force %u : !idr.lazy<i64> -> i64
    %d = idr.force %k : !idr.lazy<i64> -> i64
    %d2 = idr.force %k : !idr.lazy<i64> -> i64
    %g = idr.force %e : !idr.lazy<i64> -> i64
    %h = idr.force %f : !idr.lazy<i64> -> i64
    %late = arith.cmpi sge, %g, %n : i64
    %l = arith.extui %late : i1 to i64
    %aa = arith.addi %a, %a2 : i64
    %ab = arith.addi %aa, %b : i64
    %abd = arith.addi %ab, %d : i64
    %abdd = arith.addi %abd, %d2 : i64
    %abdl = arith.addi %abdd, %l : i64
    %abdlh = arith.addi %abdl, %h : i64
    %w2 = idr.io.put_sint %abdlh, %w1 : i64
    return %w2 : !idr.world
  }
}
