// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@pick:result:[@aa,@bb,@cc,@dd,@ee,@ff,@mid,@zz]' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=labels=@pick:result:[@aa,@bb,@cc,@dd,@ee,@ff,@mid,@zz]' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@pick:result:[@aa,@bb,@cc,@dd,@ee,@ff,@mid]' -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=labels-least -o /dev/null
// BEFORE-DAG: expected labels: @pick {{.*}}
// Eight labels reach one closure type: some by a direct yield, the rest
// through the field of a box, whose own four labels are a subset. The
// analysis joins the overlapping sets until they stop growing, so @pick's
// result holds every label that reaches it, once.
// The program means after the pass what it meant before it, on every input
// (the differential); no property here held before the pass, and each list
// of labels with one changed fails after it, so each sum is exactly its
// labels.
!Box = !idr.data<"Box", plain [@Box(!idr.fn<(i64) -> (i64)>)]>
idr.program @"many-labels" root(@Main.main) stage(higher) {
  idr.func @zz(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @mid(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @aa(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @ff(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @bb(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @ee(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.subi %x, %a : i64
    return %y : i64
  }
  idr.func @cc(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @dd(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  idr.func @pick(%n: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %c1 = arith.constant 1 : i64
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %f = idr.closure @zz() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    case 1 {
      %f = idr.closure @mid() : () -> !idr.fn<(i64) -> (i64)>
      %b = idr.con !Box @Box(%f : !idr.fn<(i64) -> (i64)>)
      %g = idr.field %b : !Box @Box[0] -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    case 2 {
      %f = idr.closure @aa() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    case 3 {
      %f = idr.closure @ff() : () -> !idr.fn<(i64) -> (i64)>
      %b = idr.con !Box @Box(%f : !idr.fn<(i64) -> (i64)>)
      %g = idr.field %b : !Box @Box[0] -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    case 4 {
      %f = idr.closure @bb(%c1) : (i64) -> !idr.fn<(i64) -> (i64)>
      %b = idr.con !Box @Box(%f : !idr.fn<(i64) -> (i64)>)
      %g = idr.field %b : !Box @Box[0] -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    case 5 {
      %f = idr.closure @ee(%c1) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    case 6 {
      %f = idr.closure @cc() : () -> !idr.fn<(i64) -> (i64)>
      %b = idr.con !Box @Box(%f : !idr.fn<(i64) -> (i64)>)
      %g = idr.field %b : !Box @Box[0] -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      %f = idr.closure @dd() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = call @pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
