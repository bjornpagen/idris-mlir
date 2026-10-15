// RUN: awk '/^ *\/\/ REQUESTS$/ { for (n = 1; n <= 1025; n++) printf "    %%k%d = arith.constant %d : i64\n    %%r%d = idr.call @loop(%%k%d, %%x) : (i64, i64) -> i64\n    %%a%d = arith.addi %%a%d, %%r%d : i64\n", n, n, n, n, n, n - 1, n; next } { print }' %s > %t.requests.mlir
// RUN: idris-mlir-opt %t.requests.mlir --idr-optimize -o %t.mlir 2> %t.err
// RUN: not grep -q unsupported %t.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@loop -o /dev/null
// RUN: idris-mlir -c %t.requests.mlir -o %t.o
// NEEDS-ACCEPTANCE: that the one call left of @loop is the 1,025th, by call-site order, and the compile's time under the suite's bound.
// Specialization has a budget, which stops it and never refuses the
// program: one function asks one owner for at most 1,024 distinct keys.
// The root here asks @loop, which is on a cycle and so never inlined, for
// 1,025, one per constant (the first RUN line writes the calls where the
// REQUESTS line stands): the module compiles, nothing is unsupported, and
// the request past the budget is not made, so a call of @loop itself is
// left. The program is the same program, less specialized.
module {
  idr.func private @loop(%k: i64, %n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %k : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.call @loop(%k, %m) : (i64, i64) -> i64
      %z = arith.addi %y, %k : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %a0 = arith.constant 0 : i64
    // REQUESTS
    %w2 = idr.io.put_int signed %a1025, %w1 : i64
    return %w2 : !idr.world
  }
}
