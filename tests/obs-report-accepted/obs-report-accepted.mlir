// RUN: idris-mlir -c %s -o %t.1.o --num-threads 1 --report=%t.1.report
// RUN: FileCheck %s < %t.1.report
// RUN: grep '^statistic: ' %t.1.report > %t.statistics
// RUN: env LC_ALL=C sort -c %t.statistics
// RUN: sed 's/=.*//' %t.statistics | uniq -d | count 0
// RUN: idris-mlir -c %s -o %t.3.o --num-threads 3 --report=%t.3.report
// RUN: cmp %t.1.report %t.3.report
// RUN: idris-mlir -c %s -o %t.5.o --num-threads 5 --report=%t.5.report
// RUN: cmp %t.1.report %t.5.report
// RUN: idris-mlir -c %s -o %t.13.o --num-threads 13 --report=%t.13.report
// RUN: cmp %t.1.report %t.13.report
// --report writes what a compilation came to: its verdict, each diagnostic,
// and each statistic of every pass that ran, summed over the pass's runs,
// as `<pass>.<statistic>` in the bytewise order of the keys. A sum does not
// depend on how the runs were spread over threads, so neither does the
// report. Each key is on one line: a pass that runs more than once
// (canonicalize, cse, symbol-dce) has its runs summed, not listed.
// CHECK: verdict: accepted
// CHECK-NOT: diagnostic:
// CHECK: statistic: idr-optimize.
!Shape = !idr.data<"Shape", plain [@Circle(i64), @Rect(i64, i64)]>
idr.program @"report-accepted" root(@Prog.main) stage(higher) {
  idr.func @area(%s: !Shape) -> i64 {
    %r = idr.match %s : !Shape -> (i64) {
    case @Circle(%x: i64) {
      %c3 = arith.constant 3 : i64
      %xx = arith.muli %x, %x : i64
      %a = arith.muli %c3, %xx : i64
      idr.yield %a : i64
    }
    case @Rect(%w: i64, %h: i64) {
      %b = arith.muli %w, %h : i64
      idr.yield %b : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %c6 = arith.constant 6 : i64
    %c7 = arith.constant 7 : i64
    %s = idr.con !Shape @Rect(%c6 : i64, %c7 : i64)
    %a = idr.call @area(%s) : (!Shape) -> i64
    return %a : i64
  }
}
