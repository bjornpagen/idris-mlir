// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %s --idr-defunctionalize --mlir-disable-threading > %t.serial.mlir
// RUN: cmp %t.mlir %t.serial.mlir
// RUN: awk 'BEGIN { ORS = "" } NR == 1, /^idr\.program / { print $0 "\n"; next } /^  idr\.func/ { n++ } /^\}$/ { for (i = 0; i <= n; i++) print c[i == 0 ? 0 : n + 1 - i]; print $0 "\n"; next } { c[n] = c[n] $0 "\n" }' %s > %t.reversed.mlir
// RUN: idris-mlir-opt %t.reversed.mlir --idr-defunctionalize > %t2.mlir
// RUN: grep '= !idr.data<' %t.mlir | sort > %t.sums
// RUN: count 3 < %t.sums
// RUN: grep '= !idr.data<' %t2.mlir | sort > %t2.sums
// RUN: diff %t.sums %t2.sums
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.onlyB:result:[@Main.b],labels=@Main.neg:result:[@Main.zneg],labels=@Main.use:arg0:[@Main.a,@Main.b]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=labels=@Main.onlyB:result:[@Main.b],labels=@Main.neg:result:[@Main.zneg],labels=@Main.use:arg0:[@Main.a,@Main.b]' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.onlyB:result:[@Main.a,@Main.b]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.neg:result:[]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@Main.use:arg0:[@Main.b]' -o /dev/null
// BEFORE-DAG: expected labels: @Main.onlyB {{.*}}
// BEFORE-DAG: expected labels: @Main.neg {{.*}}
// BEFORE-DAG: expected labels: @Main.use {{.*}}
// A sum is named from its key, the closure type and its labels, never by
// where it first appears: the same module with its functions in reverse
// order makes the same sums under the same names. Each (type, labels) is
// one sum: {@Main.b} of i64 -> i64 (the result of @Main.onlyB),
// {@Main.zneg} of i1 -> i1, and {@Main.a, @Main.b} of i64 -> i64 (the
// argument of @Main.use).
// The program means after the pass what it meant before it, on every input
// (the differential); no property here held before the pass, and each list
// of labels with one changed fails after it, so each sum is exactly its
// labels.
idr.program @"sum-names" root(@Main.main) stage(higher) {
  idr.func @Main.a(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @Main.b(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @Main.zneg(%b: i1) -> i1 attributes {total} {
    %t = arith.constant true
    %r = arith.xori %b, %t : i1
    return %r : i1
  }
  idr.func @Main.onlyB() -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %f = idr.closure @Main.b() : () -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.neg() -> !idr.fn<(i1) -> (i1)> attributes {total} {
    %f = idr.closure @Main.zneg() : () -> !idr.fn<(i1) -> (i1)>
    return %f : !idr.fn<(i1) -> (i1)>
  }
  idr.func @Main.use(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %fb = idr.call @Main.onlyB() : () -> !idr.fn<(i64) -> (i64)>
    %fa = idr.closure @Main.a() : () -> !idr.fn<(i64) -> (i64)>
    %r1 = idr.call @Main.use(%fa, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %r2 = idr.call @Main.use(%fb, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %g = idr.call @Main.neg() : () -> !idr.fn<(i1) -> (i1)>
    %e = arith.cmpi eq, %r1, %r2 : i64
    %ne = idr.apply %g(%e) : !idr.fn<(i1) -> (i1)>
    %x = arith.extui %ne : i1 to i64
    %w2 = idr.io.put_sint %x, %w1 : i64
    return %w2 : !idr.world
  }
}
