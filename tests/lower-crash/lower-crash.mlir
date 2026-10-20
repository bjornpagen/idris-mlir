// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed 's/stage(first)/stage(higher)/' %s > %t.higher.mlir
// RUN: idris-mlir -c %t.higher.mlir -o %t.o
// RUN: %cc %t.o -o %t
// RUN: printf '\000' | %status 1 %t > %t.zero.out 2> %t.zero.err
// RUN: FileCheck %s --check-prefix=ZERO --allow-empty < %t.zero.out
// RUN: FileCheck %s --check-prefix=ZERO-ERR --match-full-lines < %t.zero.err
// RUN: printf '\001' | %status 1 %t > %t.one.out 2> %t.one.err
// RUN: FileCheck %s --check-prefix=ONE --match-full-lines < %t.one.out
// RUN: FileCheck %s --check-prefix=ONE-ERR --match-full-lines < %t.one.err
// RUN: printf '\002' | %status 1 %t > %t.two.out 2> %t.two.err
// RUN: FileCheck %s --check-prefix=TWO --match-full-lines < %t.two.out
// RUN: FileCheck %s --check-prefix=TWO-ERR --match-full-lines < %t.two.err
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,crash-sites=@Main.name:1,crash-sites=@Main.never:1,never-returns=@Main.never,crash-sites=@Main.half:1,calls-only=@Main.half:[@idris_rt_crash]' -o /dev/null
// idr.crash calls the runtime's crash, which does not return, with its
// message and location; a function that never returns ends after it, with
// no return. The guard of a division by what may be zero is the same
// crash, at the division's location, when the divisor is zero, and then
// gives the divisor to the division, which tests nothing itself: the
// function may crash at that one place. What a crash prints is the
// program's output. The root reads a byte n and reaches each crash by it:
// 255 / n crashes for 0; @Main.name crashes for anything but 1, after
// the quotient is printed; and for 1, @Main.never, after "one" is. The
// program, lowered and as written, prints and exits alike on every byte
// (%differential), and compiled whole by idris-mlir (stage higher, which a
// program with no closure may say), it prints what it did before each
// crash, and the crash its cause at its location, on stderr.
// ZERO-NOT: {{.}}
// ZERO-ERR: idris-mlir: division by zero at Main.idr:9:5
// ONE: 255one
// ONE-ERR: idris-mlir: unhandled input for Main.never at Main.idr:6:1
// TWO: 127
// TWO-ERR: idris-mlir: unhandled input for Main.name at Main.idr:3:1
idr.program @crash root(@Main.main) stage(first) types #idr.types<> {
  idr.func @Main.name(%n: i64) -> !idr.str {
    %r = idr.match_lit %n : i64 -> (!idr.str) {
    case 1 {
      %s = idr.constant !idr.str "one"
      idr.yield %s : !idr.str
    }
    default(%d: i64) {
      idr.crash "unhandled input for Main.name" loc("Main.idr":3:1)
      ub.unreachable
    }
    }
    return %r : !idr.str
  }
  idr.func @Main.never(%n: i64) -> i64 {
    idr.crash "unhandled input for Main.never" loc("Main.idr":6:1)
    ub.unreachable
  }
  idr.func @Main.half(%a: i64, %b: i64) -> i64 {
    %c = idr.check.nonzero %b, "division by zero" : i64 loc("Main.idr":9:5)
    %q = idr.divs %a, %c : i64 loc("Main.idr":9:5)
    return %q : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %all = arith.constant 255 : i64
    %q = idr.call @Main.half(%all, %n) : (i64, i64) -> i64
    %w2 = idr.io.put_sint %q, %w1 : i64
    %s = idr.call @Main.name(%n) : (i64) -> !idr.str
    %w3 = idr.io.put_str %s, %w2
    %v = idr.call @Main.never(%n) : (i64) -> i64
    %w4 = idr.io.put_sint %v, %w3 : i64
    return %w4 : !idr.world
  }
}
