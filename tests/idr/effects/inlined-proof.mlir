// RUN: idris-mlir-opt %s --idr-optimize --idr-expect=holds=total=@keeps,never-calls=@keeps:@proved,not-total=@loses,never-calls=@loses:@unproved -o /dev/null
// RUN: idris-mlir-opt %s --idr-contify --idr-expect=holds=total=@keeps_parent,never-calls=@keeps_parent:@keeps_case,not-total=@loses_parent,never-calls=@loses_parent:@loses_case -o /dev/null
// The fact total says every loop of a function's own body is one Idris
// proved terminating. A body that takes in one without that proof, by
// inlining or contification, loses it: a loop of the callee's may close
// there. One that takes in a proved body keeps it. The optimizer inlines a
// helper into a loop, which calls itself and so stays out of line;
// contification, a case block that calls its parent back.
idr.program @"inlined-proof" root(@Main.main) stage(first) {
  idr.func @proved(%x: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  idr.func @unproved(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @keeps(%x: i64, %n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %p = idr.call @proved(%x) : (i64) -> i64
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %z = idr.call @keeps(%p, %m) : (i64, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @loses(%x: i64, %n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %p = idr.call @unproved(%x) : (i64) -> i64
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %z = idr.call @loses(%p, %m) : (i64, i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @keeps_case(%x: i64) -> i64 attributes {total} {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %one = arith.constant 1 : i64
      %y = arith.subi %x, %one : i64
      %z = idr.call @keeps_parent(%y) : (i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @keeps_parent(%x: i64) -> i64 attributes {total} {
    %r = idr.call @keeps_case(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @loses_case(%x: i64) -> i64 {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %z = idr.call @loses_parent(%x) : (i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @loses_parent(%x: i64) -> i64 attributes {total} {
    %r = idr.call @loses_case(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %a = idr.call @keeps_parent(%x) : (i64) -> i64
    %b = idr.call @loses_parent(%a) : (i64) -> i64
    %d = idr.call @keeps(%b, %x) : (i64, i64) -> i64
    %e = idr.call @loses(%d, %x) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %e, %w1 : i64
    return %w2 : !idr.world
  }
}
