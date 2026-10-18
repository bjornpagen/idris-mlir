// NEEDS-ACCEPTANCE: that skipping every idr-pure-calls action keeps the unread pure call of @unread, and that the module verifies.
// RUN: idris-mlir-opt %s --idr-optimize --mlir-disable-threading -mlir-debug-counter=idr-pure-calls-erase-count=0,idr-pure-calls-merge-count=0 -mlir-print-debug-counter -o %t.kept.mlir 2> %t.kept.err
// RUN: idris-mlir-opt %t.kept.mlir --idr-expect=holds=calls=@Main.main:@unread -o /dev/null
// RUN: FileCheck %s --check-prefix=COUNTED < %t.kept.err
// RUN: idris-mlir-opt %s --idr-optimize -o %t.done.mlir
// RUN: idris-mlir-opt %t.done.mlir --idr-expect=holds=not-called=@unread -o /dev/null
// idr-pure-calls is a step of idr-optimize, an optimization: each erase and
// each merge it makes is an action, which MLIR's debug counter, counting
// on one thread, skips at a count of 0. Skipped, the unread call of the
// pure @unread stays a call and the module is as valid as before; done,
// @unread goes.
// COUNTED-DAG: idr-pure-calls-erase{{ +}}: {{[{][1-9][0-9]*}},0,0}
// COUNTED-DAG: idr-pure-calls-merge{{ +}}: {{[{][1-9][0-9]*}},0,0}
idr.program @"pure-call" root(@Main.main) stage(first) {
  idr.func @unread(%n: i64) -> i64 attributes {total, no_inline} {
    %r = arith.muli %n, %n : i64
    return %r : i64
  }
  idr.func @sum(%n: i64, %acc: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %a = arith.addi %acc, %n : i64
      %y = idr.call @sum(%m, %a) : (i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @spin(%n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %a = arith.addi %acc, %n : i64
      %y = idr.call @spin(%m, %a) : (i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @check(%n: i64) -> i64 attributes {total, no_inline} {
    %m = idr.check.nonzero %n, "division by zero" : i64
    %r = idr.divs %n, %m : i64
    return %r : i64
  }
  idr.func @consume(%x: !idr.lin<!idr.str>) -> i64 attributes {total, no_inline} {
    %s = idr.lin.use %x : !idr.lin<!idr.str>
    %r = idr.str.length %s
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %z = arith.constant 0 : i64
    %u = idr.call @unread(%n) : (i64) -> i64
    %a = idr.call @sum(%n, %z) : (i64, i64) -> i64
    %b = idr.call @sum(%n, %z) : (i64, i64) -> i64
    %d = idr.call @sum(%n, %n) : (i64, i64) -> i64
    %s1 = idr.call @spin(%n, %z) : (i64, i64) -> i64
    %s2 = idr.call @spin(%n, %z) : (i64, i64) -> i64
    %k1 = idr.call @check(%n) : (i64) -> i64
    %k2 = idr.call @check(%n) : (i64) -> i64
    %txt = idr.str.show_sint %n : i64
    %l = idr.lin.enter %txt : !idr.lin<!idr.str>
    %e = idr.call @consume(%l) : (!idr.lin<!idr.str>) -> i64
    %t = arith.addi %a, %b : i64
    %w2 = idr.io.put_sint %t, %w1 : i64
    return %w2 : !idr.world
  }
}
