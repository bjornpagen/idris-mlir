// RUN: awk '/^ *\/\/ CHAIN$/ { for (f = 1; f <= 12; f++) { printf "  idr.func private @f%d(%%x: i64) -> i64 attributes {total} {\n    %%v0 = arith.addi %%x, %%x : i64\n", f; for (i = 1; i < 2000; i++) printf "    %%v%d = arith.addi %%v%d, %%x : i64\n", i, i - 1; if (f < 12) printf "    %%r = idr.call @f%d(%%v1999) : (i64) -> i64\n    return %%r : i64\n  }\n", f + 1; else printf "    return %%v1999 : i64\n  }\n" } next } { print }' %s > %t.chain.mlir
// RUN: idris-mlir-opt %t.chain.mlir --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=largest-function=10000 -o /dev/null
// RUN: grep -q 'call @f[0-9]*(' %t.mlir
// RUN: %status 1 idris-mlir-opt %t.chain.mlir --idr-expect=holds=largest-function=1000 -o /dev/null
// NEEDS-ACCEPTANCE: the chain's sizes against the cap as idr::inlineSize counts them, and the run time of the 24,000-op module.
// A chain of twelve functions, each called once and each of about 2,000
// operations (the first RUN line writes them where the CHAIN line
// stands): every one is worth inlining by the rule, so without a bound the
// root would absorb all 24,000 operations. The per-caller cap stops it: a
// call is inlined only while its caller, with the callee's final body in,
// stays at or under 10,000 operations, so after the optimizer no function
// is larger than that, and some call of the chain is left, which the cap
// kept. The cap stops inlining and never rejects: the module optimizes.
// The last line checks that the property reads sizes at all: before the
// optimizer, each function of the chain is over a bound of 1,000.
module {
  // CHAIN
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %r = idr.call @f1(%n) : (i64) -> i64
    %w2 = idr.io.put_int signed %r, %w1 : i64
    return %w2 : !idr.world
  }
}
