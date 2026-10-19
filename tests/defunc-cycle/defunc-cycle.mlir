// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.ping:result:[@Main.zero,@Main.p],labels=@Main.pong:result:[@Main.q],labels=@Main.p:arg0:[@Main.q],labels=@Main.q:arg0:[@Main.zero,@Main.p]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=labels=@Main.ping:result:[@Main.zero,@Main.p],labels=@Main.pong:result:[@Main.q],labels=@Main.p:arg0:[@Main.q],labels=@Main.q:arg0:[@Main.zero,@Main.p]' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.ping:result:[@Main.zero]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.pong:result:[@Main.q,@Main.p]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.p:arg0:[@Main.q,@Main.zero]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.q:arg0:[@Main.p]' -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=labels-least -o /dev/null
// BEFORE-DAG: expected labels: @Main.ping {{.*}}
// BEFORE-DAG: expected labels: @Main.pong {{.*}}
// BEFORE-DAG: expected labels: @Main.p {{.*}}
// BEFORE-DAG: expected labels: @Main.q {{.*}}
// ping 0 = zero; ping n = p (pong (n - 1)); pong n = q (ping (n - 1)):
// @Main.p captures only closures of @Main.q, and @Main.q only closures of
// @Main.p or @Main.zero, so the two keys of the type have different labels,
// but each holds the other: a cycle, which no unboxed sum can stand for.
// Each key still has exactly the labels that reach it.
// The program means after the pass what it meant before it, on every input
// (the differential); no property here held before the pass, and each list
// of labels with one changed fails after it, so each sum is exactly its
// labels.
idr.program @cycle root(@Main.main) stage(higher) {
  idr.func @Main.zero(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @Main.p(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = arith.addi %y, %c1 : i64
    return %z : i64
  }
  idr.func @Main.q(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = arith.addi %y, %y : i64
    return %z : i64
  }
  idr.func @Main.ping(%n: i64) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %f = idr.closure @Main.zero() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = idr.call @Main.pong(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
      %h = idr.closure @Main.p(%g) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":7:3)
      idr.yield %h : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.pong(%n: i64) -> !idr.fn<(i64) -> (i64)> {
    %c1 = arith.constant 1 : i64
    %m = arith.subi %n, %c1 : i64
    %g = idr.call @Main.ping(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
    %h = idr.closure @Main.q(%g) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":9:3)
    return %h : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.call @Main.ping(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
