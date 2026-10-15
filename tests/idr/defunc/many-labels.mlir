// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the sums' printed forms and the dispatches, as C01's printer and C06's conversion write them.
// Eight labels reach one closure type: some by a direct yield, the rest
// through the field of a box, whose own four labels are a subset. The
// analysis joins the overlapping sets until they stop growing; each sum
// holds every label that reaches it once, in name order, whatever order
// the program met them in.
// CHECK: ![[F0:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, closures [@bb(i64), @cc(), @ff(), @mid()]
// CHECK: ![[F1:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, closures [@aa(), @bb(i64), @cc(), @dd(), @ee(i64), @ff(), @mid(), @zz()]
// CHECK-NOT: !idr.fn
!Box = !idr.data<"Box", plain [@Box(!idr.fn<(i64) -> (i64)>)]>
module {
  idr.func private @zz(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func private @mid(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func private @aa(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func private @ff(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func private @bb(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func private @ee(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.subi %x, %a : i64
    return %y : i64
  }
  idr.func private @cc(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func private @dd(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  // CHECK-LABEL: idr.func private @pick(
  idr.func private @pick(%n: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %c1 = arith.constant 1 : i64
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %f = idr.closure @zz() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    case 1 {
      %f = idr.closure @mid() : () -> !idr.fn<(i64) -> (i64)>
      %b = idr.con @Box(%f) : (!idr.fn<(i64) -> (i64)>) -> !Box
      %g = idr.field %b[@Box, 0] : !Box -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    case 2 {
      %f = idr.closure @aa() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    case 3 {
      %f = idr.closure @ff() : () -> !idr.fn<(i64) -> (i64)>
      %b = idr.con @Box(%f) : (!idr.fn<(i64) -> (i64)>) -> !Box
      %g = idr.field %b[@Box, 0] : !Box -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    case 4 {
      %f = idr.closure @bb(%c1) : (i64) -> !idr.fn<(i64) -> (i64)>
      %b = idr.con @Box(%f) : (!idr.fn<(i64) -> (i64)>) -> !Box
      %g = idr.field %b[@Box, 0] : !Box -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    case 5 {
      %f = idr.closure @ee(%c1) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    case 6 {
      %f = idr.closure @cc() : () -> !idr.fn<(i64) -> (i64)>
      %b = idr.con @Box(%f) : (!idr.fn<(i64) -> (i64)>) -> !Box
      %g = idr.field %b[@Box, 0] : !Box -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    default {
      %f = idr.closure @dd() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  // CHECK-LABEL: idr.func @Main.main(
  // CHECK: match %{{.*}} : ![[F1]] -> (i64) {
  // CHECK: case @aa() {
  // CHECK: case @zz() {
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = call @pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
