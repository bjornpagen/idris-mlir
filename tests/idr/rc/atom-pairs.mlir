// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=tests-nothing=@span,tests-nothing=@break,tests-nothing=@splitAt,tests-nothing=@header -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// RUN: %status 1 idris-mlir-opt %s --idr-rc --idr-expect=holds=tests-nothing=@withCell -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=SHARED < %t.err
// span, break and splitAt give a pair of empty lists where their input ends:
// static data, an unboxed sum whose two slots are the empty list's atom.
// No take hands out a cell of it, and nothing counts, frees or writes it,
// so it is in every exclusive tree as an atom is: it joins the pair they
// build around an exclusive list, and the join is exclusive. So taking their
// own recursive result apart tests no count (tests-nothing), and neither
// does a caller that takes the prefix apart and conses onto it, as
// reverse-complement's '>' :: hdr does (@header). A static pair holding a
// cell with fields is not built only of atoms: a take would hand out that
// cell, so @withCell's result stays owned, and its take tests the count.
// CHECK-LABEL: func.func private @span(
// CHECK-SAME: -> !idr.excl<!idr.data<@P>>
// CHECK-LABEL: func.func private @break(
// CHECK-SAME: -> !idr.excl<!idr.data<@P>>
// CHECK-LABEL: func.func private @splitAt(
// CHECK-SAME: -> !idr.excl<!idr.data<@P>>
// CHECK-LABEL: func.func private @withCell(
// CHECK-SAME: -> !idr.own<!idr.data<@P>>
// CHECK-LABEL: func.func private @header(
// CHECK-SAME: -> !idr.excl<!idr.box<@L>>
// SHARED: error: expected tests-nothing: idr.take in @withCell tests a value of '!idr.own<!idr.data<@P>>', which is not exclusive
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i32, !idr.box<@L>)
  }
  idr.data @P {
    idr.ctor @MkPair (!idr.box<@L>, !idr.box<@L>)
  }
  func.func private @build(%n: i32) -> !idr.box<@L> {
    %k = arith.extsi %n : i32 to i64
    %r = idr.match_lit %k : i64 -> (!idr.box<@L>) {
    case 0 {
      %e = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
      idr.yield %e : !idr.box<@L>
    }
    default {
      %one = arith.constant 1 : i32
      %m = arith.subi %n, %one : i32
      %t = func.call @build(%m) : (i32) -> !idr.box<@L>
      %c = idr.con @L::@C(%n, %t) : (i32, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  // span (< 10): the longest prefix of elements below 10, and the rest.
  func.func private @span(%xs: !idr.box<@L>) -> !idr.data<@P> {
    %empty = idr.constant #idr.con<@P::@MkPair, [#idr.con<@L::@N, []>, #idr.con<@L::@N, []>]> : !idr.data<@P>
    %nil = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %r = idr.match %xs : !idr.box<@L> -> (!idr.data<@P>) {
    case @N() {
      idr.yield %empty : !idr.data<@P>
    }
    case @C(%h: i32, %t: !idr.box<@L>) {
      %c10 = arith.constant 10 : i32
      %below = arith.cmpi slt, %h, %c10 : i32
      %k = arith.extui %below : i1 to i64
      %s = idr.match_lit %k : i64 -> (!idr.data<@P>) {
      case 0 {
        %p = idr.con @P::@MkPair(%nil, %xs) : (!idr.box<@L>, !idr.box<@L>) -> !idr.data<@P>
        idr.yield %p : !idr.data<@P>
      }
      default {
        %rest = func.call @span(%t) : (!idr.box<@L>) -> !idr.data<@P>
        %q = idr.match %rest : !idr.data<@P> -> (!idr.data<@P>) {
        case @MkPair(%ys: !idr.box<@L>, %zs: !idr.box<@L>) {
          %c = idr.con @L::@C(%h, %ys) : (i32, !idr.box<@L>) -> !idr.box<@L>
          %p = idr.con @P::@MkPair(%c, %zs) : (!idr.box<@L>, !idr.box<@L>) -> !idr.data<@P>
          idr.yield %p : !idr.data<@P>
        }
        }
        idr.yield %q : !idr.data<@P>
      }
      }
      idr.yield %s : !idr.data<@P>
    }
    }
    return %r : !idr.data<@P>
  }
  // break (== 10): the prefix before the first 10, and the rest from it.
  func.func private @break(%xs: !idr.box<@L>) -> !idr.data<@P> {
    %empty = idr.constant #idr.con<@P::@MkPair, [#idr.con<@L::@N, []>, #idr.con<@L::@N, []>]> : !idr.data<@P>
    %nil = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %r = idr.match %xs : !idr.box<@L> -> (!idr.data<@P>) {
    case @N() {
      idr.yield %empty : !idr.data<@P>
    }
    case @C(%h: i32, %t: !idr.box<@L>) {
      %c10 = arith.constant 10 : i32
      %stop = arith.cmpi eq, %h, %c10 : i32
      %k = arith.extui %stop : i1 to i64
      %s = idr.match_lit %k : i64 -> (!idr.data<@P>) {
      case 0 {
        %rest = func.call @break(%t) : (!idr.box<@L>) -> !idr.data<@P>
        %q = idr.match %rest : !idr.data<@P> -> (!idr.data<@P>) {
        case @MkPair(%ys: !idr.box<@L>, %zs: !idr.box<@L>) {
          %c = idr.con @L::@C(%h, %ys) : (i32, !idr.box<@L>) -> !idr.box<@L>
          %p = idr.con @P::@MkPair(%c, %zs) : (!idr.box<@L>, !idr.box<@L>) -> !idr.data<@P>
          idr.yield %p : !idr.data<@P>
        }
        }
        idr.yield %q : !idr.data<@P>
      }
      default {
        %p = idr.con @P::@MkPair(%nil, %xs) : (!idr.box<@L>, !idr.box<@L>) -> !idr.data<@P>
        idr.yield %p : !idr.data<@P>
      }
      }
      idr.yield %s : !idr.data<@P>
    }
    }
    return %r : !idr.data<@P>
  }
  // splitAt n: the first n elements, and the rest.
  func.func private @splitAt(%n: i64, %xs: !idr.box<@L>) -> !idr.data<@P> {
    %empty = idr.constant #idr.con<@P::@MkPair, [#idr.con<@L::@N, []>, #idr.con<@L::@N, []>]> : !idr.data<@P>
    %nil = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %r = idr.match_lit %n : i64 -> (!idr.data<@P>) {
    case 0 {
      %p = idr.con @P::@MkPair(%nil, %xs) : (!idr.box<@L>, !idr.box<@L>) -> !idr.data<@P>
      idr.yield %p : !idr.data<@P>
    }
    default {
      %s = idr.match %xs : !idr.box<@L> -> (!idr.data<@P>) {
      case @N() {
        idr.yield %empty : !idr.data<@P>
      }
      case @C(%h: i32, %t: !idr.box<@L>) {
        %one = arith.constant 1 : i64
        %m = arith.subi %n, %one : i64
        %rest = func.call @splitAt(%m, %t) : (i64, !idr.box<@L>) -> !idr.data<@P>
        %q = idr.match %rest : !idr.data<@P> -> (!idr.data<@P>) {
        case @MkPair(%ys: !idr.box<@L>, %zs: !idr.box<@L>) {
          %c = idr.con @L::@C(%h, %ys) : (i32, !idr.box<@L>) -> !idr.box<@L>
          %p = idr.con @P::@MkPair(%c, %zs) : (!idr.box<@L>, !idr.box<@L>) -> !idr.data<@P>
          idr.yield %p : !idr.data<@P>
        }
        }
        idr.yield %q : !idr.data<@P>
      }
      }
      idr.yield %s : !idr.data<@P>
    }
    }
    return %r : !idr.data<@P>
  }
  // span (< 10) again, ending in a static pair whose first list is a cell.
  func.func private @withCell(%xs: !idr.box<@L>) -> !idr.data<@P> {
    %ended = idr.constant #idr.con<@P::@MkPair, [#idr.con<@L::@C, [0 : i32, #idr.con<@L::@N, []>]>, #idr.con<@L::@N, []>]> : !idr.data<@P>
    %nil = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %r = idr.match %xs : !idr.box<@L> -> (!idr.data<@P>) {
    case @N() {
      idr.yield %ended : !idr.data<@P>
    }
    case @C(%h: i32, %t: !idr.box<@L>) {
      %c10 = arith.constant 10 : i32
      %below = arith.cmpi slt, %h, %c10 : i32
      %k = arith.extui %below : i1 to i64
      %s = idr.match_lit %k : i64 -> (!idr.data<@P>) {
      case 0 {
        %p = idr.con @P::@MkPair(%nil, %xs) : (!idr.box<@L>, !idr.box<@L>) -> !idr.data<@P>
        idr.yield %p : !idr.data<@P>
      }
      default {
        %rest = func.call @withCell(%t) : (!idr.box<@L>) -> !idr.data<@P>
        %q = idr.match %rest : !idr.data<@P> -> (!idr.data<@P>) {
        case @MkPair(%ys: !idr.box<@L>, %zs: !idr.box<@L>) {
          %c = idr.con @L::@C(%h, %ys) : (i32, !idr.box<@L>) -> !idr.box<@L>
          %p = idr.con @P::@MkPair(%c, %zs) : (!idr.box<@L>, !idr.box<@L>) -> !idr.data<@P>
          idr.yield %p : !idr.data<@P>
        }
        }
        idr.yield %q : !idr.data<@P>
      }
      }
      idr.yield %s : !idr.data<@P>
    }
    }
    return %r : !idr.data<@P>
  }
  // '>' :: hdr, where hdr is what break gives before the first 10.
  func.func private @header(%xs: !idr.box<@L>) -> !idr.box<@L> {
    %p = func.call @break(%xs) : (!idr.box<@L>) -> !idr.data<@P>
    %r = idr.match %p : !idr.data<@P> -> (!idr.box<@L>) {
    case @MkPair(%hdr: !idr.box<@L>, %rest: !idr.box<@L>) {
      %gt = arith.constant 62 : i32
      %c = idr.con @L::@C(%gt, %hdr) : (i32, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  func.func private @sum(%l: !idr.box<@L>, %acc: i32) -> i32 {
    %r = idr.match %l : !idr.box<@L> -> (i32) {
    case @N() {
      idr.yield %acc : i32
    }
    case @C(%h: i32, %t: !idr.box<@L>) {
      %a = arith.addi %acc, %h : i32
      %s = func.call @sum(%t, %a) : (!idr.box<@L>, i32) -> i32
      idr.yield %s : i32
    }
    }
    return %r : i32
  }
  // The first list's sum, times 1000, plus the second's.
  func.func private @sums(%p: !idr.data<@P>) -> i32 {
    %r = idr.match %p : !idr.data<@P> -> (i32) {
    case @MkPair(%a: !idr.box<@L>, %b: !idr.box<@L>) {
      %z = arith.constant 0 : i32
      %k = arith.constant 1000 : i32
      %sa = func.call @sum(%a, %z) : (!idr.box<@L>, i32) -> i32
      %sb = func.call @sum(%b, %z) : (!idr.box<@L>, i32) -> i32
      %m = arith.muli %sa, %k : i32
      %s = arith.addi %m, %sb : i32
      idr.yield %s : i32
    }
    }
    return %r : i32
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %c12 = arith.constant 12 : i32
    %c2 = arith.constant 2 : i64
    %z = arith.constant 0 : i32
    %l1 = func.call @build(%c12) : (i32) -> !idr.box<@L>
    %p1 = func.call @span(%l1) : (!idr.box<@L>) -> !idr.data<@P>
    %s1 = func.call @sums(%p1) : (!idr.data<@P>) -> i32
    %l2 = func.call @build(%c12) : (i32) -> !idr.box<@L>
    %h2 = func.call @header(%l2) : (!idr.box<@L>) -> !idr.box<@L>
    %s2 = func.call @sum(%h2, %z) : (!idr.box<@L>, i32) -> i32
    %l3 = func.call @build(%c12) : (i32) -> !idr.box<@L>
    %p3 = func.call @splitAt(%c2, %l3) : (i64, !idr.box<@L>) -> !idr.data<@P>
    %s3 = func.call @sums(%p3) : (!idr.data<@P>) -> i32
    %l4 = func.call @build(%c12) : (i32) -> !idr.box<@L>
    %p4 = func.call @withCell(%l4) : (!idr.box<@L>) -> !idr.data<@P>
    %s4 = func.call @sums(%p4) : (!idr.data<@P>) -> i32
    %w1 = idr.io.put_int signed %s1, %w : i32
    %w2 = idr.io.put_int signed %s2, %w1 : i32
    %w3 = idr.io.put_int signed %s3, %w2 : i32
    %w4 = idr.io.put_int signed %s4, %w3 : i32
    return %w4 : !idr.world
  }
}
