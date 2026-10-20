// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=builds-nothing=@pair_parts,\
// RUN: reads-no-fields=@pair_parts,builds-nothing=@linear_part,reads-no-fields=@linear_part -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=builds=@kept_whole -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=builds-nothing=@pair_parts,\
// RUN: builds-nothing=@linear_part -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// BEFORE-DAG: expected builds-nothing: {{.*}} in @pair_parts
// BEFORE-DAG: expected builds-nothing: {{.*}} in @linear_part
// A match whose every region that yields gives a constructor of one tag,
// built there for the yield alone, and whose result is only taken apart:
// the match yields the fields, so no constructor is built and no field is
// read. A linear field is the value its region built the constructor of,
// so a linear thread passed back beside a value stays the one thread. A
// result also used whole keeps its constructor.

!P = !idr.data<"P">
!R = !idr.data<"R">
#types = #idr.types<
  "P" = plain [@MkP(i64, i64)],
  "R" = plain [@MkR(i64, !idr.lin<!idr.str>)]
>
idr.program @"yield-fields" root(@root) stage(higher) types #types {
  // let (a, b) = if n == 0 then (1, 2) else (n, n) in a + b
  idr.func @pair_parts(%n: i64) -> i64 {
    %p = idr.match_lit %n : i64 -> (!P) {
    case 0 {
      %one = arith.constant 1 : i64
      %two = arith.constant 2 : i64
      %c = idr.con !P @MkP(%one : i64, %two : i64)
      idr.yield %c : !P
    }
    default(%d: i64) {
      %c = idr.con !P @MkP(%d : i64, %d : i64)
      idr.yield %c : !P
    }
    }
    %a = idr.field %p : !P @MkP[0] -> i64
    %b = idr.field %p : !P @MkP[1] -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }

  // A count beside the string it was read with, the string passed on
  // linearly in each region, then written.
  idr.func @linear_part(%n: i64, %t: !idr.str, %w: !idr.world) -> !idr.world {
    %r = idr.match_lit %n : i64 -> (!R) {
    case 0 {
      %zero = arith.constant 0 : i64
      %l = idr.lin.enter %t : !idr.lin<!idr.str>
      %c = idr.con !R @MkR(%zero : i64, %l : !idr.lin<!idr.str>)
      idr.yield %c : !R
    }
    default(%d: i64) {
      %l = idr.lin.enter %t : !idr.lin<!idr.str>
      %c = idr.con !R @MkR(%d : i64, %l : !idr.lin<!idr.str>)
      idr.yield %c : !R
    }
    }
    %k = idr.field %r : !R @MkR[0] -> i64
    %s = idr.field %r : !R @MkR[1] -> !idr.str
    %w1 = idr.io.put_str %s, %w
    %ks = idr.str.show_sint %k : i64
    %w2 = idr.io.put_str %ks, %w1
    return %w2 : !idr.world
  }

  // The pair is returned whole beside its first part: it is still built.
  idr.func @kept_whole(%n: i64) -> (!P, i64) {
    %p = idr.match_lit %n : i64 -> (!P) {
    case 0 {
      %one = arith.constant 1 : i64
      %c = idr.con !P @MkP(%one : i64, %one : i64)
      idr.yield %c : !P
    }
    default(%d: i64) {
      %c = idr.con !P @MkP(%d : i64, %n : i64)
      idr.yield %c : !P
    }
    }
    %a = idr.field %p : !P @MkP[0] -> i64
    return %p, %a : !P, i64
  }

  idr.func @root(%w: !idr.world) -> !idr.world {
    %n = arith.constant 3 : i64
    %s = idr.call @pair_parts(%n) : (i64) -> i64
    %t = idr.constant !idr.str "x"
    %w1 = idr.call @linear_part(%s, %t, %w) : (i64, !idr.str, !idr.world) -> !idr.world
    return %w1 : !idr.world
  }
}
