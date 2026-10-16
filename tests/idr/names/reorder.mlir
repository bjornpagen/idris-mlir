// RUN: awk 'BEGIN { ORS = "" } NR == 1, /^idr\.program / { print $0 "\n"; next } /^  idr\.func/ { n++ } /^\}$/ { for (i = 0; i <= n; i++) print c[i == 0 ? 0 : n + 1 - i]; print $0 "\n"; next } { c[n] = c[n] $0 "\n" }' %s > %t.reversed.mlir
// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %s --idr-optimize --mlir-disable-threading -o %t.serial.mlir
// RUN: cmp %t.mlir %t.serial.mlir
// RUN: idris-mlir-opt %t.reversed.mlir --idr-optimize -o %t.reversed.out.mlir
// RUN: sed -n 's/^ *idr\.func \(private \)\{0,1\}@\([^(]*\)(.*/\2/p' %t.mlir | sort > %t.names
// RUN: sed -n 's/^ *idr\.func \(private \)\{0,1\}@\([^(]*\)(.*/\2/p' %t.reversed.out.mlir | sort > %t.reversed.names
// RUN: grep -q '[.]spec[.]' %t.names
// RUN: diff %t.names %t.reversed.names
// NEEDS-ACCEPTANCE: the pipeline's output under one thread is byte-identical to its output under the pool.
// NEEDS-ACCEPTANCE: that the optimizer makes the specialization nodes here, as the binding-time rule allows.
// A function the optimizer makes is named from its key, the owner and
// the static pattern, never from a counter or from the order the work ran
// in: the same module with its functions in reverse order (the first RUN
// line writes it) gives the same set of symbols, the specializations of
// @apply on 1 and 2 and of @scale on 3 among them.
idr.program @reorder root(@Main.main) stage(first) {
  idr.func @apply(%k: i64, %n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %k : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @apply(%k, %m) : (i64, i64) -> i64
      %s = arith.addi %y, %k : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @scale(%k: i64, %n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %k : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @scale(%k, %m) : (i64, i64) -> i64
      %q = arith.subi %y, %k : i64
      idr.yield %q : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %k1 = arith.constant 1 : i64
    %k2 = arith.constant 2 : i64
    %k3 = arith.constant 3 : i64
    %a = idr.call @apply(%k1, %n) : (i64, i64) -> i64
    %b = idr.call @apply(%k2, %n) : (i64, i64) -> i64
    %d = idr.call @scale(%k3, %n) : (i64, i64) -> i64
    %ab = arith.addi %a, %b : i64
    %r = arith.addi %ab, %d : i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
