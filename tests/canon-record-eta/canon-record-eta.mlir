// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(canonicalize,idr.func(idr-tail-loops)))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@traverse,constant-stack=@known -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@shared -o /dev/null 2> %t.shared.err
// RUN: FileCheck %s --check-prefix=SHARED < %t.shared.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@unknown -o /dev/null 2> %t.unknown.err
// RUN: FileCheck %s --check-prefix=UNKNOWN < %t.unknown.err
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@reindex -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@traverse,constant-stack=@known})' -o /dev/null 2> %t.noeta.err
// RUN: FileCheck %s --check-prefix=NOETA < %t.noeta.err
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=no-heap-allocation=@reindex -o /dev/null
// RUN: %differential %s %t.mlir
// NOETA-DAG: expected constant-stack: {{.*}}@traverse
// NOETA-DAG: expected constant-stack: {{.*}}@known
// Record eta: a constructor rebuilt from the fields of a value of that
// constructor, each read once, is the value. An IO fold returns the IORes
// of its recursive call rebuilt from its fields, the world among them, so
// with eta the call is a tail call and the fold a loop. Without it, when a
// field is read again or the value may be another constructor, the call
// stays under the rebuilt constructor, and the stack grows with the list.
// Without canonicalize, idr-tail-loops leaves @traverse and @known
// growing, and @reindex allocates. The root runs every function on a
// list as long as the byte it reads modulo 8, and the program prints after
// the passes what it printed before, on every byte.
// SHARED: expected constant-stack: {{.*}}@shared
// UNKNOWN: expected constant-stack: {{.*}}@unknown
// A node rebuilt in the case that matched it, from the case's own fields,
// is the node, so it allocates nothing.
!Unit = !idr.data<"Unit", plain [@MkUnit()]>
!IORes = !idr.data<"IORes", plain [@MkIORes(!Unit, !idr.world)]>
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
!RB = !idr.data<"RB", plain [@E(), @TB(!idr.box<!idr.data<"RB">>, i64, !idr.box<!idr.data<"RB">>)]>
!Pair = !idr.data<"Pair", plain [@Left(i64, i64), @Right(i64, i64)]>
idr.program @"record-eta" root(@root) stage(first) {

  // traverse_ printLn xs, as the Prelude's foldr over IO raises it.
  idr.func @traverse(%xs: !idr.box<!List>, %w: !idr.world) -> !IORes {
    %unit = idr.constant !Unit #idr.con<!Unit, @MkUnit, []>
    %r = idr.match %xs : !idr.box<!List> -> (!IORes) {
    case @Nil() {
      %done = idr.con !IORes @MkIORes(%unit : !Unit, %w : !idr.world)
      idr.yield %done : !IORes
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %w1 = idr.io.put_sint %x, %w : i64
      %next = idr.call @traverse(%rest, %w1) : (!idr.box<!List>, !idr.world) -> !IORes
      %u = idr.field %next : !IORes @MkIORes[0] -> !Unit
      %w2 = idr.field %next : !IORes @MkIORes[1] -> !idr.world
      %again = idr.con !IORes @MkIORes(%u : !Unit, %w2 : !idr.world)
      idr.yield %again : !IORes
    }
    }
    return %r : !IORes
  }

  // A field that is also read elsewhere keeps the constructor.
  idr.func @shared(%xs: !idr.box<!List>, %n: i64) -> (!Pair, i64) {
    %r:2 = idr.match %xs : !idr.box<!List> -> (!Pair, i64) {
    case @Nil() {
      %p = idr.con !Pair @Left(%n : i64, %n : i64)
      idr.yield %p, %n : !Pair, i64
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %next:2 = idr.call @shared(%rest, %x) : (!idr.box<!List>, i64) -> (!Pair, i64)
      %a = idr.field %next#0 : !Pair @Left[0] -> i64
      %b = idr.field %next#0 : !Pair @Left[1] -> i64
      %again = idr.con !Pair @Left(%a : i64, %b : i64)
      %s = arith.addi %a, %x : i64
      idr.yield %again, %s : !Pair, i64
    }
    }
    return %r#0, %r#1 : !Pair, i64
  }

  // @Pair has two constructors: rebuilding @Left from a value that may be
  // @Right would change it.
  idr.func @unknown(%xs: !idr.box<!List>) -> !Pair {
    %r = idr.match %xs : !idr.box<!List> -> (!Pair) {
    case @Nil() {
      %z = arith.constant 0 : i64
      %p = idr.con !Pair @Right(%z : i64, %z : i64)
      idr.yield %p : !Pair
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %next = idr.call @unknown(%rest) : (!idr.box<!List>) -> !Pair
      %a = idr.field %next : !Pair @Left[0] -> i64
      %b = idr.field %next : !Pair @Left[1] -> i64
      %again = idr.con !Pair @Left(%a : i64, %b : i64)
      idr.yield %again : !Pair
    }
    }
    return %r : !Pair
  }

  // Where a match has taken a value apart, the case's own fields rebuild
  // its constructor: each region is the value again.
  idr.func @known(%xs: !idr.box<!List>) -> !Pair {
    %r = idr.match %xs : !idr.box<!List> -> (!Pair) {
    case @Nil() {
      %z = arith.constant 0 : i64
      %p = idr.con !Pair @Right(%z : i64, %z : i64)
      idr.yield %p : !Pair
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %next = idr.call @known(%rest) : (!idr.box<!List>) -> !Pair
      %s = idr.match %next : !Pair -> (!Pair) {
      case @Left(%a: i64, %b: i64) {
        %l = idr.con !Pair @Left(%a : i64, %b : i64)
        idr.yield %l : !Pair
      }
      case @Right(%a: i64, %b: i64) {
        %q = idr.con !Pair @Right(%a : i64, %b : i64)
        idr.yield %q : !Pair
      }
      }
      idr.yield %s : !Pair
    }
    }
    return %r : !Pair
  }

  idr.func @reindex(%t: !idr.box<!RB>) -> !idr.box<!RB> {
    %r = idr.match %t : !idr.box<!RB> -> (!idr.box<!RB>) {
    case @E() {
      idr.yield %t : !idr.box<!RB>
    }
    case @TB(%l: !idr.box<!RB>, %x: i64, %rr: !idr.box<!RB>) {
      %again = idr.con !idr.box<!RB> @TB(%l : !idr.box<!RB>, %x : i64, %rr : !idr.box<!RB>)
      idr.yield %again : !idr.box<!RB>
    }
    }
    return %r : !idr.box<!RB>
  }

  idr.func @Prog.main(%xs: !idr.box<!List>, %w: !idr.world) -> (!IORes, !Pair, i64, !Pair, !Pair) {
    %c3 = arith.constant 3 : i64
    %a = idr.call @traverse(%xs, %w) : (!idr.box<!List>, !idr.world) -> !IORes
    %b:2 = idr.call @shared(%xs, %c3) : (!idr.box<!List>, i64) -> (!Pair, i64)
    %c = idr.call @unknown(%xs) : (!idr.box<!List>) -> !Pair
    %d = idr.call @known(%xs) : (!idr.box<!List>) -> !Pair
    return %a, %b#0, %b#1, %c, %d : !IORes, !Pair, i64, !Pair, !Pair
  }
  // Writes a pair: its constructor's number, then its two fields.
  idr.func @put_pair(%p: !Pair, %w: !idr.world) -> !idr.world {
    %r = idr.match %p : !Pair -> (!idr.world) {
    case @Left(%a: i64, %b: i64) {
      %c = arith.constant 76 : i32
      %w1 = idr.io.put_char %c, %w
      %w2 = idr.io.put_sint %a, %w1 : i64
      %w3 = idr.io.put_sint %b, %w2 : i64
      idr.yield %w3 : !idr.world
    }
    case @Right(%a: i64, %b: i64) {
      %c = arith.constant 82 : i32
      %w1 = idr.io.put_char %c, %w
      %w2 = idr.io.put_sint %a, %w1 : i64
      %w3 = idr.io.put_sint %b, %w2 : i64
      idr.yield %w3 : !idr.world
    }
    }
    return %r : !idr.world
  }
  // The list n-1, ..., 1, 0.
  idr.func @down(%n: i64) -> !idr.box<!List> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.box<!List>) {
    case 0 {
      %nil = idr.con !idr.box<!List> @Nil()
      idr.yield %nil : !idr.box<!List>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %t = idr.call @down(%m) : (i64) -> !idr.box<!List>
      %l = idr.con !idr.box<!List> @Cons(%m : i64, %t : !idr.box<!List>)
      idr.yield %l : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  // The program's root runs the functions above on a list as long as the
  // byte it reads modulo 8: @unknown only on the empty list, since on any
  // other it reads a Left's fields of the Right its last call gives.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c8 = arith.constant 8 : i64
    %n = arith.remui %byte, %c8 : i64
    %xs = idr.call @down(%n) : (i64) -> !idr.box<!List>
    %res = idr.call @traverse(%xs, %w0) : (!idr.box<!List>, !idr.world) -> !IORes
    %w1 = idr.field %res : !IORes @MkIORes[1] -> !idr.world
    %p, %s = idr.call @shared(%xs, %byte) : (!idr.box<!List>, i64) -> (!Pair, i64)
    %w2 = idr.call @put_pair(%p, %w1) : (!Pair, !idr.world) -> !idr.world
    %w3 = idr.io.put_sint %s, %w2 : i64
    %k = idr.call @known(%xs) : (!idr.box<!List>) -> !Pair
    %w4 = idr.call @put_pair(%k, %w3) : (!Pair, !idr.world) -> !idr.world
    %nil = idr.con !idr.box<!List> @Nil()
    %u = idr.call @unknown(%nil) : (!idr.box<!List>) -> !Pair
    %w5 = idr.call @put_pair(%u, %w4) : (!Pair, !idr.world) -> !idr.world
    %e = idr.con !idr.box<!RB> @E()
    %t = idr.con !idr.box<!RB> @TB(%e : !idr.box<!RB>, %byte : i64, %e : !idr.box<!RB>)
    %t2 = idr.call @reindex(%t) : (!idr.box<!RB>) -> !idr.box<!RB>
    %v = idr.match %t2 : !idr.box<!RB> -> (i64) {
    case @TB(%l: !idr.box<!RB>, %x: i64, %rr: !idr.box<!RB>) {
      idr.yield %x : i64
    }
    default(%d: !idr.box<!RB>) {
      %z = arith.constant -1 : i64
      idr.yield %z : i64
    }
    }
    %w6 = idr.io.put_sint %v, %w5 : i64
    return %w6 : !idr.world
  }
}
