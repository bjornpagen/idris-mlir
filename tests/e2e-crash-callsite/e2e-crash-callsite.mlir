// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: echo -n a | %status 1 %t 2>&1 | FileCheck %s --check-prefix=A --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n b | %status 1 %t 2>&1 | FileCheck %s --check-prefix=B --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n c | %status 1 %t 2>&1 | FileCheck %s --check-prefix=C --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n d | %status 1 %t 2>&1 | FileCheck %s --check-prefix=D --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n e | %status 1 %t 2>&1 | FileCheck %s --check-prefix=E --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n f | %status 1 %t 2>&1 | FileCheck %s --check-prefix=F --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n g | %status 1 %t 2>&1 | FileCheck %s --check-prefix=G --match-full-lines --implicit-check-not={{.}}
// RUN: echo -n z | %t 2>&1 | FileCheck %s --check-prefix=NONE --match-full-lines --implicit-check-not={{.}}
// A crash names the place in the source its location holds, wherever in
// the location it is, by the place's start, after its cause; its line is
// all the program writes. Here, one input each: a call site's caller, its
// callee unknown; a place alone; a place under a name; a span; a place
// among other locations; a call site's callee, its caller unknown. A
// location that holds no place names none, and the message is the cause
// alone. Every other input crashes nowhere.
// A: idris-mlir: unhandled input for Main.pick at Main.idr:9:3
// B: idris-mlir: unhandled input for Main.pick at Main.idr:12:5
// C: idris-mlir: unhandled input for Main.pick at Main.idr:20:1
// D: idris-mlir: unhandled input for Main.pick at Main.idr:30:2
// E: idris-mlir: unhandled input for Main.pick at Main.idr:40:7
// F: idris-mlir: unhandled input for Main.pick at Main.idr:50:4
// G: idris-mlir: unhandled input for Main.pick
// NONE: none
idr.program @"crash-callsite" root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %r = idr.match_lit %c : i32 -> (!idr.world) {
    case 97 {
      idr.crash "unhandled input for Main.pick" loc(callsite(unknown at "Main.idr":9:3))
      ub.unreachable
    }
    case 98 {
      idr.crash "unhandled input for Main.pick" loc("Main.idr":12:5)
      ub.unreachable
    }
    case 99 {
      idr.crash "unhandled input for Main.pick" loc("Main.pick"("Main.idr":20:1))
      ub.unreachable
    }
    case 100 {
      idr.crash "unhandled input for Main.pick" loc("Main.idr":30:2 to :17)
      ub.unreachable
    }
    case 101 {
      idr.crash "unhandled input for Main.pick" loc(fused[unknown, "Main.pick"("Main.idr":40:7)])
      ub.unreachable
    }
    case 102 {
      idr.crash "unhandled input for Main.pick" loc(callsite("Main.idr":50:4 at unknown))
      ub.unreachable
    }
    case 103 {
      idr.crash "unhandled input for Main.pick" loc(unknown)
      ub.unreachable
    }
    default(%d: i32) {
      %none = idr.constant !idr.str "none\0A"
      %w2 = idr.io.put_str %none, %w1
      idr.yield %w2 : !idr.world
    }
    }
    return %r : !idr.world
  }
}
