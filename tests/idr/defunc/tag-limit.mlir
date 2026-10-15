// RUN: awk '/^ *\/\/ LABELS$/ { for (i = 1; i <= 65536; i++) printf "  idr.func private @l%d(%%k: !idr.fn<(i64) -> (i64)>, %%x: i64) -> i64 attributes {total} {\n    return %%x : i64\n  }\n", i; next } /^ *\/\/ CASES$/ { for (i = 1; i <= 65536; i++) printf "    case %d {\n      %%v = idr.closure @l%d(%%k) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>\n      idr.yield %%v : !idr.fn<(i64) -> (i64)>\n    }\n", i, i; next } { print }' %s > %t.labels.mlir
// RUN: %status 1 idris-mlir-opt %t.labels.mlir --idr-defunctionalize -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// NEEDS-ACCEPTANCE: the diagnostic's text, as U01's verifier of the type writes it with C04's rule; and that the 65,537-label module defunctionalizes within the suite's time bound on both targets.
// The one representation limit defunctionalization leaves: a box holds
// its tag in the runtime's cell header, which has room for 2^16
// constructors. Here a key holds 65,537 labels, @base and the 65,536
// labels @grow may build (the first RUN line writes their functions where
// the LABELS line stands and their cases where the CASES line stands),
// each capturing a value of the key itself, so the key is on a cycle of
// captures and its sum must be a box: one tag too many, refused once, as a
// limit of the cell's representation, never of a count the optimizer
// keeps. Every smaller set converts.
// CHECK: unsupported (layout)
// CHECK-NOT: error:
module {
  idr.func private @base(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  // LABELS
  idr.func private @grow(%k: !idr.fn<(i64) -> (i64)>, %n: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    // CASES
    default {
      idr.yield %k : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func private @loop(%k: !idr.fn<(i64) -> (i64)>, %n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %k(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default {
      %g = idr.call @grow(%k, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> !idr.fn<(i64) -> (i64)>
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %y = idr.call @loop(%g, %m) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %b = idr.closure @base() : () -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @loop(%b, %n) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
