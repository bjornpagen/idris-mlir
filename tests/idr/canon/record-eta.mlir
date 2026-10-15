// RUN: idris-mlir-opt %s --canonicalize --idr-tail-loops -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@traverse,constant-stack=@known -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@shared -o /dev/null 2> %t.shared.err
// RUN: FileCheck %s --check-prefix=SHARED < %t.shared.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@unknown -o /dev/null 2> %t.unknown.err
// RUN: FileCheck %s --check-prefix=UNKNOWN < %t.unknown.err
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@reindex -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// Record eta: a constructor rebuilt from the fields of a value of that
// constructor, each read once, is the value. An IO fold returns the IORes
// of its recursive call rebuilt from its fields, the world among them, so
// with eta the call is a tail call and the fold a loop. Without it, when a
// field is read again or the value may be another constructor, the call
// stays under the rebuilt constructor, and the stack grows with the list.
// SHARED: error: expected constant-stack: the stack grows with the recursion of @shared
// UNKNOWN: error: expected constant-stack: the stack grows with the recursion of @unknown
// A node rebuilt in the case that matched it, from the case's own fields,
// is the node, so it allocates nothing.
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(!Unit, !idr.world)]>
!List = !idr.data<"List", list [@Nil(), @Cons(i64, !idr.box<!idr.data<"List">>)]>
!RB = !idr.data<"RB", plain [@E(), @TB(!idr.box<!idr.data<"RB">>, i64, !idr.box<!idr.data<"RB">>)]>
!Pair = !idr.data<"Pair", plain [@Left(i64, i64), @Right(i64, i64)]>
module {

  // traverse_ printLn xs, as the Prelude's foldr over IO raises it.
  idr.func private @traverse(%xs: !idr.box<!List>, %w: !idr.world) -> !IORes {
    %unit = idr.constant #idr.con<@MkUnit, []> : !Unit
    %r = idr.match %xs : !idr.box<!List> -> (!IORes) {
    case @Nil() {
      %done = idr.con @MkIORes(%unit, %w) : (!Unit, !idr.world) -> !IORes
      idr.yield %done : !IORes
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %w1 = idr.io.put_int signed %x, %w : i64
      %next = idr.call @traverse(%rest, %w1) : (!idr.box<!List>, !idr.world) -> !IORes
      %u = idr.field %next[@MkIORes, 0] : !IORes -> !Unit
      %w2 = idr.field %next[@MkIORes, 1] : !IORes -> !idr.world
      %again = idr.con @MkIORes(%u, %w2) : (!Unit, !idr.world) -> !IORes
      idr.yield %again : !IORes
    }
    }
    return %r : !IORes
  }

  // A field that is also read elsewhere keeps the constructor.
  idr.func private @shared(%xs: !idr.box<!List>, %n: i64) -> (!Pair, i64) {
    %r:2 = idr.match %xs : !idr.box<!List> -> (!Pair, i64) {
    case @Nil() {
      %p = idr.con @Left(%n, %n) : (i64, i64) -> !Pair
      idr.yield %p, %n : !Pair, i64
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %next:2 = idr.call @shared(%rest, %x) : (!idr.box<!List>, i64) -> (!Pair, i64)
      %a = idr.field %next#0[@Left, 0] : !Pair -> i64
      %b = idr.field %next#0[@Left, 1] : !Pair -> i64
      %again = idr.con @Left(%a, %b) : (i64, i64) -> !Pair
      %s = arith.addi %a, %x : i64
      idr.yield %again, %s : !Pair, i64
    }
    }
    return %r#0, %r#1 : !Pair, i64
  }

  // @Pair has two constructors: rebuilding @Left from a value that may be
  // @Right would change it.
  idr.func private @unknown(%xs: !idr.box<!List>) -> !Pair {
    %r = idr.match %xs : !idr.box<!List> -> (!Pair) {
    case @Nil() {
      %z = arith.constant 0 : i64
      %p = idr.con @Right(%z, %z) : (i64, i64) -> !Pair
      idr.yield %p : !Pair
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %next = idr.call @unknown(%rest) : (!idr.box<!List>) -> !Pair
      %a = idr.field %next[@Left, 0] : !Pair -> i64
      %b = idr.field %next[@Left, 1] : !Pair -> i64
      %again = idr.con @Left(%a, %b) : (i64, i64) -> !Pair
      idr.yield %again : !Pair
    }
    }
    return %r : !Pair
  }

  // Where a match has taken a value apart, the case's own fields rebuild
  // its constructor: each region is the value again.
  idr.func private @known(%xs: !idr.box<!List>) -> !Pair {
    %r = idr.match %xs : !idr.box<!List> -> (!Pair) {
    case @Nil() {
      %z = arith.constant 0 : i64
      %p = idr.con @Right(%z, %z) : (i64, i64) -> !Pair
      idr.yield %p : !Pair
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %next = idr.call @known(%rest) : (!idr.box<!List>) -> !Pair
      %s = idr.match %next : !Pair -> (!Pair) {
      case @Left(%a: i64, %b: i64) {
        %l = idr.con @Left(%a, %b) : (i64, i64) -> !Pair
        idr.yield %l : !Pair
      }
      case @Right(%a: i64, %b: i64) {
        %q = idr.con @Right(%a, %b) : (i64, i64) -> !Pair
        idr.yield %q : !Pair
      }
      }
      idr.yield %s : !Pair
    }
    }
    return %r : !Pair
  }

  idr.func private @reindex(%t: !idr.box<!RB>) -> !idr.box<!RB> {
    %r = idr.match %t : !idr.box<!RB> -> (!idr.box<!RB>) {
    case @E() {
      idr.yield %t : !idr.box<!RB>
    }
    case @TB(%l: !idr.box<!RB>, %x: i64, %rr: !idr.box<!RB>) {
      %again = idr.con @TB(%l, %x, %rr) : (!idr.box<!RB>, i64, !idr.box<!RB>) -> !idr.box<!RB>
      idr.yield %again : !idr.box<!RB>
    }
    }
    return %r : !idr.box<!RB>
  }

  idr.func private @Prog.main(%xs: !idr.box<!List>, %w: !idr.world) -> (!IORes, !Pair, i64, !Pair, !Pair) {
    %c3 = arith.constant 3 : i64
    %a = idr.call @traverse(%xs, %w) : (!idr.box<!List>, !idr.world) -> !IORes
    %b:2 = idr.call @shared(%xs, %c3) : (!idr.box<!List>, i64) -> (!Pair, i64)
    %c = idr.call @unknown(%xs) : (!idr.box<!List>) -> !Pair
    %d = idr.call @known(%xs) : (!idr.box<!List>) -> !Pair
    return %a, %b#0, %b#1, %c, %d : !IORes, !Pair, i64, !Pair, !Pair
  }
}
