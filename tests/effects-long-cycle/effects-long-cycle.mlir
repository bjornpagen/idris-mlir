// RUN: awk '/^ *\/\/ RING$/ { for (i = 1; i < 3000; i++) printf "  idr.func @f%d(%%x: i64) -> i64 attributes {total} {\n    %%r = idr.call @f%d(%%x) : (i64) -> i64\n    return %%r : i64\n  }\n", i, i + 1; next } { print }' %s > %t.ring.mlir
// RUN: idris-mlir-opt %t.ring.mlir --idr-effects --idr-expect=holds=effects=@f0:crash,effects=@f1:crash,effects=@f1500:crash,effects=@f2999:crash,effects=@f3000:crash,effects=@apart:none,effects=@leaf:none,effects=@entry:crash -o /dev/null
// What a function may do is solved over the call graph, each function's
// effects only growing, in a set of three, so the solve ends however long
// a cycle is: no count stops it before every member has what one of them
// may do. The first RUN line writes, where the RING line stands, @f1 to
// @f2999, each calling the next; @f3000 calls @f0 back, and @f0 may crash,
// so every member of the ring may crash. @apart, outside the ring, does
// nothing but compute. What a ring may do flows to its callers, never to
// its callees: @entry, which calls into the ring's middle, may crash, and
// @leaf, which @f0 calls, still only computes.
idr.program @"long-cycle" root(@root) stage(first) types #idr.types<> {
  idr.func @f0(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %q = idr.divs %x, %y : i64
    %l = idr.call @leaf(%q) : (i64) -> i64
    %r = idr.call @f1(%l) : (i64) -> i64
    return %r : i64
  }
  // RING
  idr.func @f3000(%x: i64) -> i64 attributes {total} {
    %r = idr.call @f0(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @leaf(%x: i64) -> i64 attributes {total} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @entry(%x: i64) -> i64 attributes {total} {
    %r = idr.call @f1500(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @apart(%x: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
