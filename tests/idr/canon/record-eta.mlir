// RUN: idris-mlir-opt %s --canonicalize --idr-tail-loops -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@traverse,constant-stack=@known -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@shared -o /dev/null 2> %t.shared.err
// RUN: FileCheck %s --check-prefix=SHARED < %t.shared.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@unknown -o /dev/null 2> %t.unknown.err
// RUN: FileCheck %s --check-prefix=UNKNOWN < %t.unknown.err
// Record eta: a constructor rebuilt from the fields of a value of that
// constructor, each read once, is the value. An IO fold returns the IORes
// of its recursive call rebuilt from its fields, the world among them, so
// with eta the call is a tail call and the fold a loop. Without it, when a
// field is read again or the value may be another constructor, the call
// stays under the rebuilt constructor, and the stack grows with the list.
// SHARED: error: expected constant-stack: the stack grows with the recursion of @shared
// UNKNOWN: error: expected constant-stack: the stack grows with the recursion of @unknown
module {
  idr.data @Unit {
    idr.ctor @MkUnit ()
  }
  idr.data @IORes {
    idr.ctor @MkIORes (!idr.data<@Unit>, !idr.world)
  }
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  idr.data @Pair {
    idr.ctor @Left (i64, i64)
    idr.ctor @Right (i64, i64)
  }

  // traverse_ printLn xs, as the Prelude's foldr over IO raises it.
  func.func private @traverse(%xs: !idr.box<@List>, %w: !idr.world) -> !idr.data<@IORes> {
    %unit = idr.constant #idr.con<@Unit::@MkUnit, []> : !idr.data<@Unit>
    %r = idr.match %xs : !idr.box<@List> -> (!idr.data<@IORes>) {
    case @Nil() {
      %done = idr.con @IORes::@MkIORes(%unit, %w) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
      idr.yield %done : !idr.data<@IORes>
    }
    case @Cons(%x: i64, %rest: !idr.box<@List>) {
      %w1 = idr.io.put_int signed %x, %w : i64
      %next = func.call @traverse(%rest, %w1) : (!idr.box<@List>, !idr.world) -> !idr.data<@IORes>
      %u = idr.field %next[@MkIORes, 0] : !idr.data<@IORes> -> !idr.data<@Unit>
      %w2 = idr.field %next[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
      %again = idr.con @IORes::@MkIORes(%u, %w2) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
      idr.yield %again : !idr.data<@IORes>
    }
    }
    return %r : !idr.data<@IORes>
  }

  // A field that is also read elsewhere keeps the constructor.
  func.func private @shared(%xs: !idr.box<@List>, %n: i64) -> (!idr.data<@Pair>, i64) {
    %r:2 = idr.match %xs : !idr.box<@List> -> (!idr.data<@Pair>, i64) {
    case @Nil() {
      %p = idr.con @Pair::@Left(%n, %n) : (i64, i64) -> !idr.data<@Pair>
      idr.yield %p, %n : !idr.data<@Pair>, i64
    }
    case @Cons(%x: i64, %rest: !idr.box<@List>) {
      %next:2 = func.call @shared(%rest, %x) : (!idr.box<@List>, i64) -> (!idr.data<@Pair>, i64)
      %a = idr.field %next#0[@Left, 0] : !idr.data<@Pair> -> i64
      %b = idr.field %next#0[@Left, 1] : !idr.data<@Pair> -> i64
      %again = idr.con @Pair::@Left(%a, %b) : (i64, i64) -> !idr.data<@Pair>
      %s = arith.addi %a, %x : i64
      idr.yield %again, %s : !idr.data<@Pair>, i64
    }
    }
    return %r#0, %r#1 : !idr.data<@Pair>, i64
  }

  // @Pair has two constructors: rebuilding @Left from a value that may be
  // @Right would change it.
  func.func private @unknown(%xs: !idr.box<@List>) -> !idr.data<@Pair> {
    %r = idr.match %xs : !idr.box<@List> -> (!idr.data<@Pair>) {
    case @Nil() {
      %z = arith.constant 0 : i64
      %p = idr.con @Pair::@Right(%z, %z) : (i64, i64) -> !idr.data<@Pair>
      idr.yield %p : !idr.data<@Pair>
    }
    case @Cons(%x: i64, %rest: !idr.box<@List>) {
      %next = func.call @unknown(%rest) : (!idr.box<@List>) -> !idr.data<@Pair>
      %a = idr.field %next[@Left, 0] : !idr.data<@Pair> -> i64
      %b = idr.field %next[@Left, 1] : !idr.data<@Pair> -> i64
      %again = idr.con @Pair::@Left(%a, %b) : (i64, i64) -> !idr.data<@Pair>
      idr.yield %again : !idr.data<@Pair>
    }
    }
    return %r : !idr.data<@Pair>
  }

  // Where a match has taken a value apart, the case's own fields rebuild
  // its constructor: each region is the value again.
  func.func private @known(%xs: !idr.box<@List>) -> !idr.data<@Pair> {
    %r = idr.match %xs : !idr.box<@List> -> (!idr.data<@Pair>) {
    case @Nil() {
      %z = arith.constant 0 : i64
      %p = idr.con @Pair::@Right(%z, %z) : (i64, i64) -> !idr.data<@Pair>
      idr.yield %p : !idr.data<@Pair>
    }
    case @Cons(%x: i64, %rest: !idr.box<@List>) {
      %next = func.call @known(%rest) : (!idr.box<@List>) -> !idr.data<@Pair>
      %s = idr.match %next : !idr.data<@Pair> -> (!idr.data<@Pair>) {
      case @Left(%a: i64, %b: i64) {
        %l = idr.con @Pair::@Left(%a, %b) : (i64, i64) -> !idr.data<@Pair>
        idr.yield %l : !idr.data<@Pair>
      }
      case @Right(%a: i64, %b: i64) {
        %q = idr.con @Pair::@Right(%a, %b) : (i64, i64) -> !idr.data<@Pair>
        idr.yield %q : !idr.data<@Pair>
      }
      }
      idr.yield %s : !idr.data<@Pair>
    }
    }
    return %r : !idr.data<@Pair>
  }

  func.func @Prog.main(%xs: !idr.box<@List>, %w: !idr.world) -> (!idr.data<@IORes>, !idr.data<@Pair>, i64, !idr.data<@Pair>, !idr.data<@Pair>) {
    %c3 = arith.constant 3 : i64
    %a = func.call @traverse(%xs, %w) : (!idr.box<@List>, !idr.world) -> !idr.data<@IORes>
    %b:2 = func.call @shared(%xs, %c3) : (!idr.box<@List>, i64) -> (!idr.data<@Pair>, i64)
    %c = func.call @unknown(%xs) : (!idr.box<@List>) -> !idr.data<@Pair>
    %d = func.call @known(%xs) : (!idr.box<@List>) -> !idr.data<@Pair>
    return %a, %b#0, %b#1, %c, %d : !idr.data<@IORes>, !idr.data<@Pair>, i64, !idr.data<@Pair>, !idr.data<@Pair>
  }
}
