// NEEDS-ACCEPTANCE: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// Eight labels reach one closure type: some by a direct yield, the rest
// through the field of a box, whose own four labels are a subset. The
// analysis joins the overlapping sets until they stop growing; each sum
// holds every label that reaches it once, in name order, whatever order
// the program met them in.
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
