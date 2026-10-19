// RUN: awk '/^ *\/\/ LABELS$/ { for (i = 1; i <= 65536; i++) printf "  idr.func @l%d(%%k: !idr.fn<(i64) -> (i64)>, %%x: i64) -> i64 attributes {total} {\n    return %%x : i64\n  }\n", i; next } /^ *\/\/ CASES$/ { for (i = 1; i <= 65536; i++) printf "    case %d {\n      %%v = idr.closure @l%d(%%k) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>\n      idr.yield %%v : !idr.fn<(i64) -> (i64)>\n    }\n", i, i; next } { print }' %s > %t.labels.mlir
// RUN: idris-mlir-opt %t.labels.mlir --idr-defunctionalize -o /dev/null
// A box holds its tag in the runtime's cell header, which has room for
// 2^16 constructors, and a sum of more is two levels: an outer tag picks a
// group, each group a sum of at most 2^16. Here a key holds 65,537 labels,
// @base and the 65,536 labels @grow may build (the first RUN line writes
// their functions where the LABELS line stands and their cases where the
// CASES line stands), each capturing a value of the key itself, so the key
// is on a cycle of captures and its sum must be a box: one tag past what a
// header holds, which the representation lifts, so the program is
// defunctionalized like any other, and no count refuses it.
idr.program @"tag-limit" root(@Main.main) stage(higher) {
  idr.func @base(%x: i64) -> i64 attributes {total} {
    return %x : i64
  }
  // LABELS
  idr.func @grow(%k: !idr.fn<(i64) -> (i64)>, %n: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    // CASES
    default(%d: i64) {
      idr.yield %k : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @loop(%k: !idr.fn<(i64) -> (i64)>, %n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %y = idr.apply %k(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %y : i64
    }
    default(%d: i64) {
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
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
