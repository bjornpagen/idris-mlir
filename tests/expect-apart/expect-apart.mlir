// RUN: idris-mlir-opt %s --idr-expect=holds=apart=@inc:@dec,apart=@merged:@inc -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=apart=@Main.inc:@Main.dec,apart=@inc:@inc,apart=@inc:@absent -verify-diagnostics -o /dev/null
// expected-error @unknown {{expected apart: }}
// expected-error-re @-4 {{expected apart: {{.*}}@absent}}
// Two functions are apart while each is made from code of its own. One
// whose location fuses both names, as deduplication leaves the function it
// keeps of two it merged, is made from both, and the two are one; it is
// still apart from a third (@inc, whose location names neither). A
// function is never apart from itself, and two of which one has no
// function at all are not two (@absent).
idr.program @apart root(@root) stage(first) types #idr.types<> {
  // expected-error @below {{expected apart: }}
  idr.func @inc(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    return %y : i64
  }
  idr.func @dec(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %y = arith.subi %x, %one : i64
    return %y : i64
  }
  idr.func @merged(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  } loc(fused["Main.inc", "Main.dec"])
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
