// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@pick:result:[@add,@dbl],calls=@Main.main:@add,calls=@Main.main:@dbl' -o /dev/null
// A function picked at runtime between two labels, one with a capture: the
// closure type becomes a sum with a constructor per label, whose fields are
// the captures, and the application a match that calls the label. What is
// left is no closure.
idr.program @choice root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @dbl(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @pick(%n: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %c1 = arith.constant 1 : i64
      %f = idr.closure @add(%c1) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      %g = idr.closure @dbl() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %g : !idr.fn<(i64) -> (i64)>
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
