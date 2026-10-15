// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// `if b then f x else g x` takes its branches as suspensions: the match
// chooses one, and it is forced after the match. The force moves into the
// match's regions, where it meets the suspension its region built, built
// there or constant, which nothing else uses: each region calls its
// branch, and no cell is built. A loop through a branch is then a call,
// which the call graph sees.
idr.func private @then(%x: i64) -> i64 attributes {total} {
  %c1 = arith.constant 1 : i64
  %y = arith.addi %x, %c1 : i64
  return %y : i64
}
idr.func private @else(%x: i64) -> i64 attributes {total} {
  %c2 = arith.constant 2 : i64
  %y = arith.muli %x, %c2 : i64
  return %y : i64
}
// CHECK-LABEL: @choose(
// CHECK-NOT: {{(idr\.| )suspend }}
// CHECK-NOT: {{(idr\.| )force }}
// CHECK: call @else(
// CHECK-NOT: {{(idr\.| )force }}
// CHECK: call @then(
// CHECK-NOT: {{(idr\.| )force }}
// CHECK: return
idr.func private @choose(%b: i64, %x: i64) -> i64 {
  %s = idr.match_lit %b : i64 -> (!idr.lazy<i64>) {
  case 0 {
    %t = idr.suspend @else(%x) : (i64) -> !idr.lazy<i64>
    idr.yield %t : !idr.lazy<i64>
  }
  default {
    %t = idr.suspend @then(%x) : (i64) -> !idr.lazy<i64>
    idr.yield %t : !idr.lazy<i64>
  }
  }
  %r = idr.force %s : !idr.lazy<i64> -> i64
  return %r : i64
}

// A suspension of constants folds to a constant, one cell in static data,
// whose force runs its label once: that force stays. The region that built
// its suspension calls its branch.
// CHECK-LABEL: @constant(
// CHECK: default {
// CHECK-NEXT: call @then(
idr.func private @constant(%b: i64, %x: i64) -> i64 {
  %s = idr.match_lit %b : i64 -> (!idr.lazy<i64>) {
  case 0 {
    %c3 = arith.constant 3 : i64
    %t = idr.suspend @else(%c3) : (i64) -> !idr.lazy<i64>
    idr.yield %t : !idr.lazy<i64>
  }
  default {
    %t = idr.suspend @then(%x) : (i64) -> !idr.lazy<i64>
    idr.yield %t : !idr.lazy<i64>
  }
  }
  %r = idr.force %s : !idr.lazy<i64> -> i64
  return %r : i64
}

// A suspension its region forces too is shared: the later force reads the
// cell the first one filled. That region keeps the cell and forces it
// twice; only the other region calls.
// CHECK-LABEL: @shared(
// CHECK: case 0 {
// CHECK-NEXT: %[[T:.*]] = {{(idr\.)?}}suspend @else(
// CHECK-COUNT-2: force %[[T]]
// CHECK: default {
// CHECK-NEXT: call @then(
// CHECK: return
idr.func private @shared(%b: i64, %x: i64) -> i64 {
  %s:2 = idr.match_lit %b : i64 -> (!idr.lazy<i64>, i64) {
  case 0 {
    %t = idr.suspend @else(%x) : (i64) -> !idr.lazy<i64>
    %u = idr.force %t : !idr.lazy<i64> -> i64
    idr.yield %t, %u : !idr.lazy<i64>, i64
  }
  default {
    %t = idr.suspend @then(%x) : (i64) -> !idr.lazy<i64>
    %c0 = arith.constant 0 : i64
    idr.yield %t, %c0 : !idr.lazy<i64>, i64
  }
  }
  %r = idr.force %s#0 : !idr.lazy<i64> -> i64
  %y = arith.addi %r, %s#1 : i64
  return %y : i64
}
