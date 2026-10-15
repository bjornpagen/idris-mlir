// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-optimize -o %t.mlir
// RUN: FileCheck %s --implicit-check-not=@mk.raise. < %t.mlir
// NEEDS-ACCEPTANCE: the ops between each kept call and its dispatch, as defunctionalization writes the dispatch; and that @pmk's calls are raised.
// Raising runs the callee's body where the apply was, so it must not move
// that body past anything observable. @mk is partial: its body could fail
// to terminate, so no op with an effect may lie between its call and the
// apply (output in the first case, the guard of a division, which may
// crash, in the second), and the apply must be in the call's block (the
// third: it runs only in one region). A total callee that computes only,
// @pmk, has nothing to observe, so its call is raised, a closed one
// included (the fourth) and one across output (the fifth). Both loop, so
// neither is inlined. The calls of @mk stay where they were, before what
// they may not cross.
// CHECK-LABEL: idr.func @Main.main(
// CHECK: call @mk(
// CHECK-NEXT: idr.io.put_int
// CHECK: call @mk(
// CHECK-NEXT: idr.check.nonzero
// CHECK: call @mk(
// CHECK-NEXT: match_lit
// CHECK: call @[[PMK:pmk\.raise\.[0-9a-f]+]](
// CHECK: call @[[PMK]](
idr.program @"not-raised" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @mk(%a: i64, %k: i64) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %v = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @mk(%a, %m) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @pmk(%a: i64, %k: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %v = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @pmk(%a, %m) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %c7 = arith.constant 7 : i64
    %f1 = idr.call @mk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %n, %w1 : i64
    %r1 = idr.apply %f1(%n) : !idr.fn<(i64) -> (i64)>
    %f2 = idr.call @mk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.check.nonzero %n, "division by zero" : i64
    %q = idr.div signed %r1, %g : i64
    %r2 = idr.apply %f2(%q) : !idr.fn<(i64) -> (i64)>
    %f3 = idr.call @mk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r3 = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %z = idr.apply %f3(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    %f4 = idr.call @pmk(%c7, %c7) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r4 = idr.apply %f4(%r3) : !idr.fn<(i64) -> (i64)>
    %f5 = idr.call @pmk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %w3 = idr.io.put_int signed %r4, %w2 : i64
    %r5 = idr.apply %f5(%r2) : !idr.fn<(i64) -> (i64)>
    %w4 = idr.io.put_int signed %r5, %w3 : i64
    return %w4 : !idr.world
  }
}
