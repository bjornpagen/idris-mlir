// RUN: idris-mlir-opt %s --idr-effects --canonicalize --cse -o %t.upstream.mlir
// RUN: idris-mlir-opt %t.upstream.mlir --idr-expect=holds=not-called=@unread,not-called=@consume,calls-distinct=@Main.main:@sum,calls-read=@Main.main:@sum,calls=@Main.main:@spin,calls=@Main.main:@check,calls-read=@Main.main:@fresh -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --canonicalize --cse --idr-expect=holds=calls-distinct=@Main.main:@spin,calls-read=@Main.main:@spin,calls-distinct=@Main.main:@check,calls-read=@Main.main:@check,calls-distinct=@Main.main:@fresh -verify-diagnostics -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-optimize,symbol-dce))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@unread,not-called=@consume,calls-distinct=@Main.main:@sum,calls-read=@Main.main:@sum,calls=@Main.main:@spin,calls=@Main.main:@check,calls-read=@Main.main:@fresh -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-rc --idr-expect=holds=stage=owned -o /dev/null
// A call says what it may do by its own effects, as an llvm.call holds its
// memory effects: idr-effects writes each call's with its callee's, and
// idr-optimize writes them once the callee is final. Upstream canonicalize
// and cse read the call alone, so they do for a call what they do for any
// op: a call of a callee that does nothing but compute goes when nothing
// reads its results, and is the earlier call's results when an identical
// call dominates it. A call that gives a linear value says it makes a
// fresh one, so two such calls stay two, and one nothing reads still goes.
// Every callee here stays a call: @sum and @spin each on a cycle of their
// own, the rest marked never to inline.
//   - @unread is pure and its one call unread: it goes.
//   - @sum is total and pure: of its two identical calls, the second is the
//     first's results, and its third call, unread, goes.
//   - @spin is @sum without Idris's proof that it ends: each call may
//     diverge, and stays, the two identical ones and the unread ones.
//   - @check may crash: both its calls stay, identical and unread.
//   - @consume is pure, and takes a linear string: its unread call goes too.
//     A linear value is used at most once on every path, and one unused is
//     released, so the string the call took is released where the call
//     was, as the owned verifier checks after idr-rc counts the program.
//   - @fresh is pure and gives a linear string: its two identical calls,
//     each read, stay two.
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
    default(%d2: i64) {
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
    default(%d2: i64) {
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
  idr.func @fresh(%n: i64) -> !idr.lin<!idr.str> attributes {total, no_inline} {
    %s = idr.str.show_sint %n : i64
    %l = idr.lin.enter %s : !idr.lin<!idr.str>
    return %l : !idr.lin<!idr.str>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %z = arith.constant 0 : i64
    %u = idr.call @unread(%n) : (i64) -> i64
    %a = idr.call @sum(%n, %z) : (i64, i64) -> i64
    %b = idr.call @sum(%n, %z) : (i64, i64) -> i64
    %d = idr.call @sum(%n, %n) : (i64, i64) -> i64
    // expected-error @below {{calls @spin and reads nothing it gives}}
    %s1 = idr.call @spin(%n, %z) : (i64, i64) -> i64
    // expected-error @below {{calls @spin again on what an earlier call took}}
    // expected-error @below {{calls @spin and reads nothing it gives}}
    %s2 = idr.call @spin(%n, %z) : (i64, i64) -> i64
    // expected-error @below {{calls @check and reads nothing it gives}}
    %k1 = idr.call @check(%n) : (i64) -> i64
    // expected-error @below {{calls @check again on what an earlier call took}}
    // expected-error @below {{calls @check and reads nothing it gives}}
    %k2 = idr.call @check(%n) : (i64) -> i64
    %txt = idr.str.show_sint %n : i64
    %l = idr.lin.enter %txt : !idr.lin<!idr.str>
    %e = idr.call @consume(%l) : (!idr.lin<!idr.str>) -> i64
    %f1 = idr.call @fresh(%n) : (i64) -> !idr.lin<!idr.str>
    // expected-error @below {{calls @fresh again on what an earlier call took}}
    %f2 = idr.call @fresh(%n) : (i64) -> !idr.lin<!idr.str>
    %u1 = idr.lin.use %f1 : !idr.lin<!idr.str>
    %n1 = idr.str.length %u1
    %u2 = idr.lin.use %f2 : !idr.lin<!idr.str>
    %n2 = idr.str.length %u2
    %t0 = arith.addi %a, %b : i64
    %t1 = arith.addi %t0, %n1 : i64
    %t = arith.addi %t1, %n2 : i64
    %w2 = idr.io.put_sint %t, %w1 : i64
    return %w2 : !idr.world
  }
}
