// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// Raising runs the callee's body where the apply was, so it must not move
// that body past anything observable. @mk is partial: its body could fail
// to terminate, so no op with an effect may lie between its call and the
// apply (output in the first case, the guard of a division, which may
// crash, in the second), and the apply must be in the call's block (the
// third: it runs only in one region). A closed call of a pure, total callee
// is idr-eval's, which runs it to the end (the fourth). A pure and total
// callee that cannot crash has nothing to observe, so its call is raised
// even across output (the fifth), and the raised call is where the apply
// was, after the output.
// CHECK-LABEL: func.func @Main.main(
// CHECK: %[[F1:.*]] = call @mk(
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_int
// CHECK-NEXT: %[[R1:.*]] = idr.apply %[[F1]](
// CHECK-NEXT: %[[F2:.*]] = call @mk(
// CHECK-NEXT: %[[G:.*]] = idr.check.nonzero
// CHECK-NEXT: %[[Q:.*]] = idr.div signed %[[R1]], %[[G]]
// CHECK-NEXT: %[[R2:.*]] = idr.apply %[[F2]](%[[Q]])
// CHECK-NEXT: %[[F3:.*]] = call @mk(
// CHECK-NEXT: idr.match_lit
// CHECK-NEXT: case 0 {
// CHECK-NEXT: idr.apply %[[F3]](
// CHECK: %[[F4:.*]] = call @pmk(%{{.*}}) : (i64) -> !idr.fn<(i64) -> (i64)>
// CHECK-NEXT: %[[R4:.*]] = idr.apply %[[F4]](
// CHECK-NEXT: %[[W3:.*]] = idr.io.put_int signed %[[R4]], %[[W2]]
// CHECK-NEXT: %[[R5:.*]] = call @[[PMK:pmk\$raise\$[0-9]+]](%{{.*}}, %[[R2]]) : (i64, i64) -> i64
// CHECK-NEXT: idr.io.put_int signed %[[R5]], %[[W3]]
// CHECK-NOT: call @mk$raise
// CHECK: func.func private @[[PMK]](
// CHECK-SAME: idr.effects = #idr.effects<none>{{.*}}idr.total
// CHECK-NOT: func.func private @mk$raise
module attributes {idr.program} {
  func.func private @add(%a: i64, %x: i64) -> i64 attributes {idr.effects = #idr.effects<none>, idr.total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  func.func private @mk(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {idr.effects = #idr.effects<diverge>} {
    %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func private @pmk(%a: i64) -> !idr.fn<(i64) -> (i64)> attributes {idr.effects = #idr.effects<none>, idr.total} {
    %f = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
    return %f : !idr.fn<(i64) -> (i64)>
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world attributes {idr.effects = #idr.effects<io, crash>} {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %c7 = arith.constant 7 : i64
    %f1 = func.call @mk(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %w2 = idr.io.put_int signed %n, %w1 : i64
    %r1 = idr.apply %f1(%n) : !idr.fn<(i64) -> (i64)>
    %f2 = func.call @mk(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.check.nonzero %n, "division by zero" : i64
    %q = idr.div signed %r1, %g : i64
    %r2 = idr.apply %f2(%q) : !idr.fn<(i64) -> (i64)>
    %f3 = func.call @mk(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r3 = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %z = idr.apply %f3(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default {
      idr.yield %n : i64
    }
    }
    %f4 = func.call @pmk(%c7) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r4 = idr.apply %f4(%r3) : !idr.fn<(i64) -> (i64)>
    %f5 = func.call @pmk(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %w3 = idr.io.put_int signed %r4, %w2 : i64
    %r5 = idr.apply %f5(%r2) : !idr.fn<(i64) -> (i64)>
    %w4 = idr.io.put_int signed %r5, %w3 : i64
    return %w4 : !idr.world
  }
}
