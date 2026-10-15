// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@mk,not-called=@curry,not-called=@add -o /dev/null
// NEEDS-ACCEPTANCE: that the chain folds in the root, by inlining and the case of a known constructor.
// A call whose result is applied, and that result applied again. After
// defunctionalization both applies are dispatches. The optimizer works
// callee first, so @curry and @mk are final, and small, when the root
// inlines them: each dispatch then meets the constructor the inlined body
// built and folds to a direct call, inlined in turn. No call of the chain
// is left.
idr.program @chain root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @curry(%a: i64, %x: i64) -> !idr.fn<(i64) -> i64> attributes {total} {
    %s = arith.addi %a, %x : i64
    %f = idr.closure @add(%s) : (i64) -> !idr.fn<(i64) -> i64>
    return %f : !idr.fn<(i64) -> i64>
  }
  idr.func @mk(%a: i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>> attributes {total} {
    %f = idr.closure @curry(%a) : (i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
    return %f : !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.call @mk(%n) : (i64) -> !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
    %g = idr.apply %f(%n) : !idr.fn<(i64) -> !idr.fn<(i64) -> i64>>
    %r = idr.apply %g(%n) : !idr.fn<(i64) -> i64>
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
