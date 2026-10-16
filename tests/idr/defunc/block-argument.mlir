// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// A function of several blocks, as inlining a callee that ends in
// ub.unreachable leaves one: a closure reaches the second block through
// a block argument of a branch. The branch declares what it forwards
// (upstream's branch interface), so the argument holds both labels and
// the function's result is their sum, which the root dispatches on.
idr.program @"block-argument" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @dbl(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @pick(%b: i1, %n: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @dbl() : () -> !idr.fn<(i64) -> (i64)>
    cf.cond_br %b, ^join(%f : !idr.fn<(i64) -> (i64)>), ^join(%g : !idr.fn<(i64) -> (i64)>)
  ^join(%h: !idr.fn<(i64) -> (i64)>):
    return %h : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %z = arith.constant 0 : i64
    %b = arith.cmpi eq, %n, %z : i64
    %f = idr.call @pick(%b, %n) : (i1, i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
