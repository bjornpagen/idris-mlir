// RUN: awk 'BEGIN { ORS = "" } NR == 1, /^idr\.program / { print $0 "\n"; next } /^  idr\.func/ { n++ } /^\}$/ { for (i = 0; i <= n; i++) print c[i == 0 ? 0 : n + 1 - i]; print $0 "\n"; next } { c[n] = c[n] $0 "\n" }' %s > %t.reversed.mlir
// RUN: sed 's/%q = arith.subi %y, %x : i64/%q = arith.addi %y, %x : i64/' %s > %t.edited.mlir
// RUN: not cmp -s %s %t.edited.mlir
// RUN: idris-mlir-opt %s --mlir-print-op-generic | grep -o 'sym_name = "[^"]*"' | sort > %t.input.names
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize))' --mlir-print-op-generic | grep -o 'sym_name = "[^"]*"' | sort > %t.names
// RUN: idris-mlir-opt %t.reversed.mlir --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize))' --mlir-print-op-generic | grep -o 'sym_name = "[^"]*"' | sort > %t.reversed.names
// RUN: idris-mlir-opt %t.edited.mlir --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize))' --mlir-print-op-generic | grep -o 'sym_name = "[^"]*"' | grep -v '"scale' | sort > %t.edited.names
// RUN: comm -13 %t.input.names %t.names | grep -q .
// RUN: diff %t.names %t.reversed.names
// RUN: grep -v '"scale' %t.names | diff - %t.edited.names
// A function the optimizer makes is named from its key, the function it
// copies and the static pattern it is copied for, never from a counter,
// from the order the work ran in or from the module around it. @apply is
// specialized on each of its two closures and @scale on its one, so the
// optimizer makes functions the input does not hold (RUN 8). Then:
// - the same module with its functions in reverse order (RUN 1) gives the
//   same set of symbols (RUN 9);
// - the module with the body of @scale alone edited (RUN 2) gives the same
//   symbols for every function not made from @scale (RUN 10).
// Symbols are read off the generic form's `sym_name`, so the custom form's
// printing of a function is no part of the check.
idr.program @keys root(@Main.main) stage(higher) {
  idr.func @add(%k: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %k : i64
    return %y : i64
  }
  idr.func @mul(%k: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.muli %x, %k : i64
    return %y : i64
  }
  idr.func @apply(%n: i64, %f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %z = idr.call @apply(%m, %f, %y) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @scale(%n: i64, %f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
      %q = arith.subi %y, %x : i64
      %z = idr.call @scale(%m, %f, %q) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %k = arith.extui %c : i32 to i64
    %f = idr.closure @add(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %g = idr.closure @mul(%k) : (i64) -> !idr.fn<(i64) -> (i64)>
    %zero = arith.constant 0 : i64
    %a = idr.call @apply(%k, %f, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %b = idr.call @apply(%k, %g, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %d = idr.call @scale(%k, %g, %zero) : (i64, !idr.fn<(i64) -> (i64)>, i64) -> i64
    %ab = arith.addi %a, %b : i64
    %r = arith.addi %ab, %d : i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
