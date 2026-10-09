// RUN: idris-mlir-opt %s --canonicalize -o %t.upstream.mlir
// RUN: idris-mlir-opt %s --idr-canonicalize -o %t.counted.mlir
// RUN: diff %t.upstream.mlir %t.counted.mlir
// RUN: idris-mlir-opt %s --mlir-disable-threading --pass-pipeline="builtin.module(func.func(idr-canonicalize))" --remarks-filter=idr-canonicalize -o %t.functions.mlir 2> %t.remarks
// RUN: diff %t.upstream.mlir %t.functions.mlir
// RUN: FileCheck %s < %t.remarks
// RUN: idris-mlir-opt %s --mlir-disable-threading --pass-pipeline="builtin.module(func.func(idr-canonicalize{max-iterations=1}))" --remarks-filter-missed=idr-canonicalize --mlir-pass-statistics -o %t.stopped.mlir 2> %t.stopped
// RUN: FileCheck %s --check-prefix=STOPPED < %t.stopped
// RUN: %status 1 idris-mlir-opt %s --idr-canonicalize="max-iterations=1 test-convergence=true" -o %t.failed.mlir
// idr-canonicalize leaves what canonicalize leaves, and counts the patterns
// that applied, by name, in an Analysis remark on each function where any
// did; here the writes of an appended string are fused. A run that stops
// before its fixpoint is a Missed remark and a statistic, and a failure
// only when test-convergence asks.
// CHECK: remark: [Analysis] patterns | Category:idr-canonicalize | Function=append | {{.*}}={{[1-9][0-9]*}}
// CHECK-NOT: Function=nothing
// STOPPED: remark: [Missed] unconverged | Category:idr-canonicalize | Function=append | Reason="the greedy driver stopped before a fixpoint, at max-iterations=1"
// STOPPED: IdrCanonicalize
// STOPPED-DAG: (S) {{ *[1-9][0-9]*}} rewrites - Rewrites by patterns
// STOPPED-DAG: (S) {{ *[1-9][0-9]*}} unconverged - Runs that stopped before a fixpoint

func.func @append(%n: i64, %w: !idr.world) -> !idr.world {
  %a = idr.constant "n = " : !idr.str
  %nl = idr.constant "\n" : !idr.str
  %s = idr.str.show signed %n : i64
  %t = idr.str.append %s, %nl
  %u = idr.str.append %a, %t
  %w1 = idr.io.put_str %u, %w
  return %w1 : !idr.world
}

func.func @nothing(%n: i64) -> i64 {
  return %n : i64
}
