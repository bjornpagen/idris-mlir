// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@unread,not-called=@consume,calls-distinct=@Main.main:@sum,calls-read=@Main.main:@sum,calls=@Main.main:@spin,calls=@Main.main:@check -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls-distinct=@Main.main:@spin -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls-read=@Main.main:@spin -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls-distinct=@Main.main:@check -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=calls-read=@Main.main:@check -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-rc --idr-expect=holds=stage=owned -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --canonicalize --idr-expect=holds=calls=@Main.main:@unread -o /dev/null
// NEEDS-ACCEPTANCE: that idr-pure-calls erases the unread calls of pure callees, one that takes a linear value among them, and merges the identical ones, and keeps every other call; and that counting then releases the linear string the erased call took.
// A call holds no effects, so canonicalize and CSE, which read the call
// alone, keep every call: canonicalize alone, effects solved or not, has
// no table, and keeps every call (the last RUN line). idr-pure-calls, the
// step of idr-optimize's inner pipeline after canonicalize, reads the
// callee's summary instead, once the callee is final: a call of a callee
// that does nothing but compute goes when nothing reads its results, and
// is the earlier call's results when an identical call dominates it. Every callee here stays a call: @sum and
// @spin each on a cycle of its own, the rest marked never to inline.
//   - @unread is pure and its one call unread: it goes, and so does @unread.
//   - @sum is total and pure: of its two identical calls, the second is the
//     first's results (idr-pure-calls's `merged`), and its third call,
//     unread, goes (`erased`).
//   - @spin is @sum without Idris's proof that it ends: each call may
//     diverge, and stays, the two identical ones and the unread ones.
//   - @check may crash: both its calls stay, identical and unread.
//   - @consume is pure, and takes a linear string: its unread call goes too.
//     A linear value is used at most once on every path, and one unused is
//     released, so the string the call took is released where the call
//     was, as the owned verifier checks after idr-rc counts the program.
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
    default {
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
    default {
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
    %r = idr.div signed %n, %m : i64
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
    %txt = idr.str.show signed %n : i64
    %l = idr.lin.enter %txt : !idr.lin<!idr.str>
    %e = idr.call @consume(%l) : (!idr.lin<!idr.str>) -> i64
    %t = arith.addi %a, %b : i64
    %w2 = idr.io.put_int signed %t, %w1 : i64
    return %w2 : !idr.world
  }
}
