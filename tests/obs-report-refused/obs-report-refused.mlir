// RUN: %status 3 idris-mlir -c %s -o %t.o --num-threads 1 --report=%t.report
// RUN: FileCheck %s < %t.report
// RUN: test ! -e %t.o
// RUN: %status 3 idris-mlir -c %s -o %t.4.o --num-threads 4 --report=%t.4.report
// RUN: cmp %t.report %t.4.report
// A refusal, here idr-knots' of an array that can hold itself, fails the
// compilation with status 3, and the report, written whatever the
// verdict, says so: the verdict, then the refusal as
// `<severity> <rule> <file:line>`, the rule read from the diagnostic's
// data (a space of its phrase written `-`). No object is written, and the
// report is the same however many threads compile.
// CHECK: verdict: refused
!Node = !idr.data<"Node">
#types = #idr.types<
  "Node" = plain [@MkNode(memref<?x!idr.box<!idr.data<"Node">>, #idr.world>)]
>
idr.program @"report-refused" root(@Prog.main) stage(higher) types #types {
  idr.func @grow(%node: !idr.box<!Node>, %w: !idr.world) -> !idr.world {
    %one = arith.constant 1 : i64
    // CHECK-NEXT: diagnostic: error cycle {{.*}}report-refused.mlir:[[#@LINE+1]]{{$}}
    %a, %w1 = idr.array.new [%one], %node, %w : !idr.box<!Node> -> memref<?x!idr.box<!Node>, #idr.world>
    return %w1 : !idr.world
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
