// NEEDS-ACCEPTANCE: that this test, rewritten to the representation wave's printed forms (each match's default region binding the scrutinee, `default(%d: T)` and `idr.io.put_sint` for the signed `put_int`), parses and passes as before.
// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=no-closures,labels=@Main.mkInc:result:[@Main.inc],labels=@Main.mkAdd:result:[@Main.add],labels=@Main.use:arg0:[@Main.add,@Main.inc]' -o /dev/null
// NEEDS-ACCEPTANCE: that each set of labels is its own sum: @Main.mkInc's and @Main.mkAdd's of one label each, @Main.use's of both.
// Values of one closure type with different sets of labels: mkInc returns
// only @Main.inc and mkAdd only @Main.add, while @Main.use and the join of
// the match take either. Each (type, labels) is its own sum, and where a
// value moves into a slot with more labels, at the calls of @Main.use and
// at the yields of the match, a match rebuilds its constructor in the
// larger sum.
idr.program @coerce root(@Main.main) stage(higher) {
  idr.func @Main.inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @Main.add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @Main.mkInc() -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %f = idr.closure @Main.inc() : () -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.mkAdd(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %f = idr.closure @Main.add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.use(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %i = idr.call @Main.mkInc() : () -> !idr.fn<(i64) -> (i64)>
    %a = idr.call @Main.mkAdd(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r1 = idr.call @Main.use(%i, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %r2 = idr.call @Main.use(%a, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %j = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      idr.yield %i : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      idr.yield %a : !idr.fn<(i64) -> (i64)>
    }
    }
    %r3 = idr.apply %j(%n) : !idr.fn<(i64) -> (i64)>
    %s1 = arith.addi %r1, %r2 : i64
    %s = arith.addi %s1, %r3 : i64
    %w2 = idr.io.put_sint %s, %w1 : i64
    return %w2 : !idr.world
  }
}
