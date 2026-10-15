// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: awk 'BEGIN { ORS = "" } NR == 1, /^idr\.program / { print $0 "\n"; next } /^  idr\.func/ { n++ } /^\}$/ { for (i = 0; i <= n; i++) print c[i == 0 ? 0 : n + 1 - i]; print $0 "\n"; next } { c[n] = c[n] $0 "\n" }' %s > %t.reversed.mlir
// RUN: idris-mlir-opt %t.reversed.mlir --idr-defunctionalize > %t2.mlir
// RUN: grep '= !idr.data<' %t.mlir | sort > %t.sums
// RUN: grep '= !idr.data<' %t2.mlir | sort > %t2.sums
// RUN: diff %t.sums %t2.sums
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the sums' printed forms, as C01's printer writes them.
// A sum is named from its key, the closure type and its labels, never by
// where it first appears: the same module with its functions in reverse
// order makes the same sums under the same names. Each (type, labels) is
// one sum: {@Main.b} of i64 -> i64 (the result of @Main.onlyB),
// {@Main.zneg} of i1 -> i1, and {@Main.a, @Main.b} of i64 -> i64 (the
// argument of @Main.use).
// CHECK-DAG: ![[B:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, closures [@Main.b()]
// CHECK-DAG: ![[N:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, closures [@Main.zneg()]
// CHECK-DAG: ![[AB:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, closures [@Main.a(), @Main.b()]
// CHECK-NOT: !idr.fn
// CHECK-LABEL: idr.func @Main.onlyB() -> ![[B]]
// CHECK-LABEL: idr.func @Main.neg() -> ![[N]]
// CHECK-LABEL: idr.func @Main.use(
// CHECK-SAME: %{{.*}}: ![[AB]]
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
    %w2 = idr.io.put_int signed %x, %w1 : i64
    return %w2 : !idr.world
  }
}
