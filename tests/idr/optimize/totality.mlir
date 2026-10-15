// RUN: awk '/^ *\/\/ CHAIN$/ { for (f = 1; f <= 12; f++) { printf "  idr.func @f%d(%%x: i64) -> i64 attributes {total} {\n    %%v0 = arith.addi %%x, %%x : i64\n", f; for (i = 1; i < 2000; i++) printf "    %%v%d = arith.addi %%v%d, %%x : i64\n", i, i - 1; if (f < 12) printf "    %%r = idr.call @f%d(%%v1999) : (i64) -> i64\n    return %%r : i64\n  }\n", f + 1; else printf "    return %%v1999 : i64\n  }\n" } next } /^ *\/\/ REQUESTS$/ { for (k = 1; k <= 1025; k++) printf "    %%k%d = arith.constant %d : i64\n    %%a%d = idr.call @apply(%%k%d, %%n) : (i64, i64) -> i64\n    %%u%d = arith.addi %%u%d, %%a%d : i64\n", k, k, k, k, k, k - 1, k; next } { print }' %s > %t.budgets.mlir
// RUN: idris-mlir-opt %t.budgets.mlir --idr-optimize -o %t.mlir 2> %t.err
// RUN: not grep -q unsupported %t.err
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=largest-function=10000 -o /dev/null
// NEEDS-ACCEPTANCE: the run time of the module, whose 1,025 requests make as many copies as the rule over recursive components keys.
// No count refuses a program: a size policy only stops optimizing, and
// specialization stops by the request chain, never by a count of keys.
// The root asks @apply for 1,025 specializations, one per constant (the
// REQUESTS line), and the chain of the CHAIN line meets the inliner's
// per-caller cap. The optimizer exits 0, says nothing of `unsupported`,
// and leaves every function within the cap.
idr.program @totality root(@Main.main) stage(first) {
  // CHAIN
  // @apply is on a cycle of its own, so it is never inlined; its first
  // parameter is passed itself at every call, so a constant there is
  // static, and each constant is its own key.
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
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %u0 = idr.call @f1(%n) : (i64) -> i64
    // REQUESTS
    %w2 = idr.io.put_int signed %u1025, %w1 : i64
    return %w2 : !idr.world
  }
}
