// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.pick:result:[@Main.inc,@Main.twice],labels=@Main.twice:arg0:[@Main.inc,@Main.twice],labels=@Main.later:result:[@Main.one,@Main.force],labels=@Main.force:arg0:[@Main.one,@Main.force],calls=@Main.main:@Main.neg' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=labels=@Main.pick:result:[@Main.inc,@Main.twice],labels=@Main.twice:arg0:[@Main.inc,@Main.twice],labels=@Main.later:result:[@Main.one,@Main.force],labels=@Main.force:arg0:[@Main.one,@Main.force],calls=@Main.main:@Main.neg' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.pick:result:[@Main.inc]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.twice:arg0:[@Main.twice]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.later:result:[@Main.one]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.force:arg0:[@Main.force]' -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=labels-least -o /dev/null
// BEFORE-DAG: expected labels: @Main.pick {{.*}}
// BEFORE-DAG: expected labels: @Main.twice {{.*}}
// BEFORE-DAG: expected labels: @Main.later {{.*}}
// BEFORE-DAG: expected labels: @Main.force {{.*}}
// BEFORE-DAG: expected calls: @Main.main {{.*}}@Main.neg
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0007
// STDIN: \0020
// STDIN: \0024
// Closures that a recursion on a runtime value makes larger: each level
// captures a closure of its own type, so no unboxed sum over labels stands
// for them, and each key holds its own label and the one that grows it.
// pick's closures and later's suspensions grow alike. The unrelated
// closure type in the same module has its one label, which the apply in
// @Main.main calls.
// The program means after the pass what it meant before it, on every input
// (the differential); no property here held before the pass, and each list
// of labels with one changed fails after it, so each sum is exactly its
// labels.
idr.program @growing root(@Main.main) stage(higher) {
  idr.func @Main.inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @Main.twice(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %z : i64
  }
  idr.func @Main.neg(%b: i1) -> i1 attributes {total} {
    %t = arith.constant true
    %r = arith.xori %b, %t : i1
    return %r : i1
  }
  idr.func @Main.force(%l: !idr.fn<() -> (i64)>) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %v = idr.apply %l() : !idr.fn<() -> (i64)>
    %r = arith.addi %v, %c1 : i64
    return %r : i64
  }
  // pick 0 = inc; pick n = twice (pick (n - 1))
  idr.func @Main.pick(%n: i64) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %f = idr.closure @Main.inc() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = idr.call @Main.pick(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
      %h = idr.closure @Main.twice(%g) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":16:5)
      idr.yield %h : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  // later 0 = Delay 1; later n = Delay (force (later (n - 1)))
  idr.func @Main.one() -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    return %c1 : i64
  }
  idr.func @Main.later(%n: i64) -> !idr.fn<() -> (i64)> {
    %r = idr.match_lit %n : i64 -> (!idr.fn<() -> (i64)>) {
    case 0 {
      %f = idr.closure @Main.one() : () -> !idr.fn<() -> (i64)>
      idr.yield %f : !idr.fn<() -> (i64)>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = idr.call @Main.later(%m) : (i64) -> !idr.fn<() -> (i64)>
      %h = idr.closure @Main.force(%g) : (!idr.fn<() -> (i64)>) -> !idr.fn<() -> (i64)>
      idr.yield %h : !idr.fn<() -> (i64)>
    }
    }
    return %r : !idr.fn<() -> (i64)>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.call @Main.pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %l = idr.call @Main.later(%n) : (i64) -> !idr.fn<() -> (i64)>
    %s = idr.apply %l() : !idr.fn<() -> (i64)>
    %neg = idr.closure @Main.neg() : () -> !idr.fn<(i1) -> (i1)>
    %b = arith.cmpi eq, %r, %s : i64
    %nb = idr.apply %neg(%b) : !idr.fn<(i1) -> (i1)>
    %x = arith.extui %nb : i1 to i64
    %w2 = idr.io.put_sint %x, %w1 : i64
    return %w2 : !idr.world
  }
}
