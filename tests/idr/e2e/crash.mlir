// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: %status 1 %t > %t.out 2> %t.err
// RUN: FileCheck %s --check-prefix=OUT < %t.out
// RUN: FileCheck %s --check-prefix=ERR < %t.err
// A crash writes pending output, then its message with the Idris location
// to stderr, and exits with status 1; nothing after it runs.
// OUT: before
// OUT-NOT: after
// ERR: idris-mlir: unhandled input for Main.pick at Main.idr:7:1
module attributes {idr.program} {
  func.func private @pick(%n: i64) -> !idr.str {
    %r = idr.match_lit %n : i64 -> (!idr.str) {
    case 0 {
      %s = idr.constant "zero" : !idr.str
      idr.yield %s : !idr.str
    }
    default {
      idr.crash "unhandled input for Main.pick" loc("Main.idr":7:1)
      ub.unreachable
    }
    }
    return %r : !idr.str
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %s = idr.constant "before\n" : !idr.str
    %w1 = idr.io.put_str %s, %w
    %c, %w2 = idr.io.get_byte %w1
    %n = arith.extui %c : i32 to i64
    %p = func.call @pick(%n) : (i64) -> !idr.str
    %w3 = idr.io.put_str %p, %w2
    %a = idr.constant "after\n" : !idr.str
    %w4 = idr.io.put_str %a, %w3
    return %w4 : !idr.world
  }
}
