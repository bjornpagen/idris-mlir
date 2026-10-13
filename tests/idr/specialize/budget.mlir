// RUN: awk '/^ *\/\/ CLONES$/ { for (n = 1; n <= 1024; n++) printf "  idr.func private @apply.spec%d(%%x: i64) -> i64 attributes {clone = #idr.clone<@apply.spec%d, #idr.spec_key<\"apply\", [#idr.key_closure<\"add\", [%d : i64]>, #idr.key_hole<0>]>>, total} {\n    %%k = arith.constant %d : i64\n    %%y = arith.addi %%k, %%x : i64\n    idr.return %%y : i64\n  }\n", n, n, n, n; next } { print }' %s > %t.clones.mlir
// RUN: %status 1 idris-mlir-opt %t.clones.mlir --idr-specialize -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// The clones of one function are bounded by a budget, an assertion that the
// construction is finite: going past it is the error `unsupported
// (compile-time budget)`, which names the function. The clones are counted
// from the clone facts the module holds, over the whole compilation, so a
// module that already holds as many clones of @apply as the budget allows
// (each for a closure of @add over another constant, which the first RUN
// line writes where the CLONES line stands) has none left for the closure
// of @neg.
// CHECK: error: unsupported (compile-time budget): specializing @apply made more than {{[0-9]+}} clones of it
// CHECK-NOT: error:
module attributes {idr.program} {
  idr.func private @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    idr.return %y : i64
  }
  idr.func private @neg(%x: i64) -> i64 attributes {total} {
    %z = arith.constant 0 : i64
    %y = arith.subi %z, %x : i64
    idr.return %y : i64
  }
  idr.func private @apply(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    idr.return %y : i64
  }
  // CLONES
  idr.func private @use(%x: i64) -> i64 attributes {total} {
    %f = idr.closure @neg() : () -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @apply(%f, %x) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    idr.return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %s = idr.call @use(%x) : (i64) -> i64
    %w2 = idr.io.put_int signed %s, %w1 : i64
    idr.return %w2 : !idr.world
  }
}
