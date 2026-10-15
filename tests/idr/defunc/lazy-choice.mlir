// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s --implicit-check-not='!idr.lazy' < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures -o /dev/null
// NEEDS-ACCEPTANCE: the memo sum's printed form, as C01's printer writes it.
// A choice between two suspensions made at run time: the match's yields
// reach its result through the region-branch edges upstream's interface
// declares, so the forced value's cell may be either suspension, and both
// are constructors of one memo sum. Nothing about a suspension is lost on
// the way; an op that does not declare how a suspension moves through it
// is refused by the verifier where it is written (verify/flow.mlir).
// CHECK: ![[M:[A-Za-z0-9_$.]+]] = !idr.data<{{[^,]*}}, memo [@one(), @two(), @running(), @forced(i64)]
// CHECK-LABEL: idr.func @Main.main(
// CHECK: force %{{.*}} : !idr.box<![[M]]> -> i64
module {
  idr.func private @one() -> i64 attributes {total} {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func private @two() -> i64 attributes {total} {
    %c = arith.constant 2 : i64
    return %c : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %t = idr.match_lit %n : i64 -> (!idr.lazy<i64>) {
    case 65 {
      %x = idr.suspend @one() : () -> !idr.lazy<i64>
      idr.yield %x : !idr.lazy<i64>
    }
    default {
      %y = idr.suspend @two() : () -> !idr.lazy<i64>
      idr.yield %y : !idr.lazy<i64>
    }
    }
    %v = idr.force %t : !idr.lazy<i64> -> i64
    %w2 = idr.io.put_int signed %v, %w1 : i64
    return %w2 : !idr.world
  }
}
