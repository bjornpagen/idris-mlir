// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the sums' printed forms and the dispatches, as C01's printer and C06's conversion write them.
// A Lazy value picked at runtime, stored in a field and forced later: the
// suspensions become constructors of a sum, the field's type follows, and
// forcing is a match that calls the suspended function.
// CHECK: ![[F0:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, closures [@later(i64), @now(){{.*}}]
// CHECK: !{{[A-Za-z0-9_$.]+}} = !idr.data<"Box"{{.*}}[@MkBox(![[F0]]){{.*}}]
// CHECK-NOT: !idr.fn
// CHECK-LABEL: idr.func @Main.main(
// CHECK: %[[L:.*]] = {{(idr\.)?}}field %{{.*}} : !Box @MkBox[0] -> ![[F0]]
// CHECK-NEXT: match %[[L]] : ![[F0]] -> (i64) {
// CHECK-NEXT: case @later(%[[X:.*]]: i64) {
// CHECK-NEXT: call @later(%[[X]]) : (i64) -> i64
// CHECK: case @now() {
// CHECK-NEXT: call @now() : () -> i64
!Box = !idr.data<"Box", plain [@MkBox(!idr.fn<() -> (i64)>)]>
idr.program @lazy root(@Main.main) stage(higher) {
  idr.func @now() -> i64 attributes {total} {
    %c = arith.constant 7 : i64
    return %c : i64
  }
  idr.func @later(%x: i64) -> i64 attributes {total} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %s = idr.match_lit %n : i64 -> (!idr.fn<() -> (i64)>) {
    case 65 {
      %a = idr.closure @now() : () -> !idr.fn<() -> (i64)>
      idr.yield %a : !idr.fn<() -> (i64)>
    }
    default {
      %b = idr.closure @later(%n) : (i64) -> !idr.fn<() -> (i64)>
      idr.yield %b : !idr.fn<() -> (i64)>
    }
    }
    %box = idr.con !Box @MkBox(%s : !idr.fn<() -> (i64)>)
    %l = idr.field %box : !Box @MkBox[0] -> !idr.fn<() -> (i64)>
    %r = idr.apply %l() : !idr.fn<() -> (i64)>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
