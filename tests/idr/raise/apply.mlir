// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@pick,not-called=@add,not-called=@sub -o /dev/null
// RUN: FileCheck %s < %t.mlir
// NEEDS-ACCEPTANCE: that the call of @pick is raised, as C09's raising of a call whose result a dispatch consumes makes it.
// A call whose result is applied at once, with only an op without effects
// between them: after defunctionalization the apply is a dispatch on the
// call's result. @pick loops, so it is never inlined, and the call and the
// dispatch become one call of a raised copy of @pick that also takes the
// apply's argument. In the copy the dispatch moves to every tail, where it
// meets the constructor each region builds and folds to a direct call,
// which the copy inlines, and the recursive tail calls the copy itself. So
// neither @pick nor the functions its closures name is called.
// CHECK-LABEL: idr.func @Main.main(
// CHECK: call @{{pick\.raise\.[0-9a-f]+}}(
idr.program @apply root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @sub(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.subi %a, %x : i64
    return %y : i64
  }
  idr.func @pick(%a: i64) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %a : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %f = idr.closure @sub(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    case 1 {
      %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %a, %c1 : i64
      %f = idr.call @pick(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @use(%n: i64, %x: i64) -> i64 {
    %f = idr.call @pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    %r = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %r = idr.call @use(%x, %x) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
