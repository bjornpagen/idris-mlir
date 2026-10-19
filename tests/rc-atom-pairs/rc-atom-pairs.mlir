// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=tests-nothing=@span,tests-nothing=@break,tests-nothing=@splitAt -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-rc --idr-expect=holds=tests-nothing=@withCell -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=SHARED < %t.err
// span, break and splitAt give a pair of empty lists where their input ends:
// static data, an unboxed sum whose two slots are the empty list's atom.
// No take hands out a cell of it, and nothing counts, frees or writes it,
// so it is in every exclusive tree as an atom is: it joins the pair they
// build around an exclusive list, and the join is exclusive. So taking
// their own recursive result apart tests no count (tests-nothing). A
// static pair holding a cell with fields is not built only of atoms: a
// take would hand out that cell, so @withCell's result stays owned, and so
// do the lists it holds; taking the first apart tests the count. (The pair
// itself, an unboxed sum, is its fields already: its unpack tests
// nothing.)
// SHARED: error: expected tests-nothing: idr.take in @withCell tests
!L = !idr.data<"L", list [@N() nil, @C(i32, !idr.box<!idr.data<"L">>) cons]>
!P = !idr.data<"P", plain [@MkPair(!idr.box<!L>, !idr.box<!L>)]>
idr.program @"atom-pairs" root(@root) stage(first) {
  idr.func @build(%n: i32) -> !idr.box<!L> {
    %k = arith.extsi %n : i32 to i64
    %r = idr.match_lit %k : i64 -> (!idr.box<!L>) {
    case 0 {
      %e = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
      idr.yield %e : !idr.box<!L>
    }
    default(%d0: i64) {
      %one = arith.constant 1 : i32
      %m = arith.subi %n, %one : i32
      %t = idr.call @build(%m) : (i32) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%n : i32, %t : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  // span (< 10): the longest prefix of elements below 10, and the rest.
  idr.func @span(%xs: !idr.box<!L>) -> !P {
    %empty = idr.constant !P #idr.con<!P, @MkPair, [#idr.con<!L, @N, []>, #idr.con<!L, @N, []>]>
    %nil = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %r = idr.match %xs : !idr.box<!L> -> (!P) {
    case @N() {
      idr.yield %empty : !P
    }
    case @C(%h: i32, %t: !idr.box<!L>) {
      %c10 = arith.constant 10 : i32
      %below = arith.cmpi slt, %h, %c10 : i32
      %k = arith.extui %below : i1 to i64
      %s = idr.match_lit %k : i64 -> (!P) {
      case 0 {
        %p = idr.con !P @MkPair(%nil : !idr.box<!L>, %xs : !idr.box<!L>)
        idr.yield %p : !P
      }
      default(%d1: i64) {
        %rest = idr.call @span(%t) : (!idr.box<!L>) -> !P
        %q = idr.match %rest : !P -> (!P) {
        case @MkPair(%ys: !idr.box<!L>, %zs: !idr.box<!L>) {
          %c = idr.con !idr.box<!L> @C(%h : i32, %ys : !idr.box<!L>)
          %p = idr.con !P @MkPair(%c : !idr.box<!L>, %zs : !idr.box<!L>)
          idr.yield %p : !P
        }
        }
        idr.yield %q : !P
      }
      }
      idr.yield %s : !P
    }
    }
    return %r : !P
  }
  // break (== 10): the prefix before the first 10, and the rest from it.
  idr.func @break(%xs: !idr.box<!L>) -> !P {
    %empty = idr.constant !P #idr.con<!P, @MkPair, [#idr.con<!L, @N, []>, #idr.con<!L, @N, []>]>
    %nil = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %r = idr.match %xs : !idr.box<!L> -> (!P) {
    case @N() {
      idr.yield %empty : !P
    }
    case @C(%h: i32, %t: !idr.box<!L>) {
      %c10 = arith.constant 10 : i32
      %stop = arith.cmpi eq, %h, %c10 : i32
      %k = arith.extui %stop : i1 to i64
      %s = idr.match_lit %k : i64 -> (!P) {
      case 0 {
        %rest = idr.call @break(%t) : (!idr.box<!L>) -> !P
        %q = idr.match %rest : !P -> (!P) {
        case @MkPair(%ys: !idr.box<!L>, %zs: !idr.box<!L>) {
          %c = idr.con !idr.box<!L> @C(%h : i32, %ys : !idr.box<!L>)
          %p = idr.con !P @MkPair(%c : !idr.box<!L>, %zs : !idr.box<!L>)
          idr.yield %p : !P
        }
        }
        idr.yield %q : !P
      }
      default(%d2: i64) {
        %p = idr.con !P @MkPair(%nil : !idr.box<!L>, %xs : !idr.box<!L>)
        idr.yield %p : !P
      }
      }
      idr.yield %s : !P
    }
    }
    return %r : !P
  }
  // splitAt n: the first n elements, and the rest.
  idr.func @splitAt(%n: i64, %xs: !idr.box<!L>) -> !P {
    %empty = idr.constant !P #idr.con<!P, @MkPair, [#idr.con<!L, @N, []>, #idr.con<!L, @N, []>]>
    %nil = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %r = idr.match_lit %n : i64 -> (!P) {
    case 0 {
      %p = idr.con !P @MkPair(%nil : !idr.box<!L>, %xs : !idr.box<!L>)
      idr.yield %p : !P
    }
    default(%d3: i64) {
      %s = idr.match %xs : !idr.box<!L> -> (!P) {
      case @N() {
        idr.yield %empty : !P
      }
      case @C(%h: i32, %t: !idr.box<!L>) {
        %one = arith.constant 1 : i64
        %m = arith.subi %n, %one : i64
        %rest = idr.call @splitAt(%m, %t) : (i64, !idr.box<!L>) -> !P
        %q = idr.match %rest : !P -> (!P) {
        case @MkPair(%ys: !idr.box<!L>, %zs: !idr.box<!L>) {
          %c = idr.con !idr.box<!L> @C(%h : i32, %ys : !idr.box<!L>)
          %p = idr.con !P @MkPair(%c : !idr.box<!L>, %zs : !idr.box<!L>)
          idr.yield %p : !P
        }
        }
        idr.yield %q : !P
      }
      }
      idr.yield %s : !P
    }
    }
    return %r : !P
  }
  // span (< 10) again, ending in a static pair whose first list is a cell.
  idr.func @withCell(%xs: !idr.box<!L>) -> !P {
    %ended = idr.constant !P #idr.con<!P, @MkPair, [#idr.con<!L, @C, [0 : i32, #idr.con<!L, @N, []>]>, #idr.con<!L, @N, []>]>
    %nil = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %r = idr.match %xs : !idr.box<!L> -> (!P) {
    case @N() {
      idr.yield %ended : !P
    }
    case @C(%h: i32, %t: !idr.box<!L>) {
      %c10 = arith.constant 10 : i32
      %below = arith.cmpi slt, %h, %c10 : i32
      %k = arith.extui %below : i1 to i64
      %s = idr.match_lit %k : i64 -> (!P) {
      case 0 {
        %p = idr.con !P @MkPair(%nil : !idr.box<!L>, %xs : !idr.box<!L>)
        idr.yield %p : !P
      }
      default(%d4: i64) {
        %rest = idr.call @withCell(%t) : (!idr.box<!L>) -> !P
        %q = idr.match %rest : !P -> (!P) {
        case @MkPair(%ys: !idr.box<!L>, %zs: !idr.box<!L>) {
          %c = idr.match %ys : !idr.box<!L> -> (!idr.box<!L>) {
          case @N() {
            %one = idr.con !idr.box<!L> @C(%h : i32, %nil : !idr.box<!L>)
            idr.yield %one : !idr.box<!L>
          }
          case @C(%y: i32, %yt: !idr.box<!L>) {
            %sum = arith.addi %h, %y : i32
            %two = idr.con !idr.box<!L> @C(%sum : i32, %yt : !idr.box<!L>)
            idr.yield %two : !idr.box<!L>
          }
          }
          %p = idr.con !P @MkPair(%c : !idr.box<!L>, %zs : !idr.box<!L>)
          idr.yield %p : !P
        }
        }
        idr.yield %q : !P
      }
      }
      idr.yield %s : !P
    }
    }
    return %r : !P
  }
  // '>' :: hdr, where hdr is what break gives before the first 10.
  idr.func @sum(%l: !idr.box<!L>, %acc: i32) -> i32 {
    %r = idr.match %l : !idr.box<!L> -> (i32) {
    case @N() {
      idr.yield %acc : i32
    }
    case @C(%h: i32, %t: !idr.box<!L>) {
      %a = arith.addi %acc, %h : i32
      %s = idr.call @sum(%t, %a) : (!idr.box<!L>, i32) -> i32
      idr.yield %s : i32
    }
    }
    return %r : i32
  }
  // The first list's sum, times 1000, plus the second's.
  idr.func @sums(%p: !P) -> i32 {
    %r = idr.match %p : !P -> (i32) {
    case @MkPair(%a: !idr.box<!L>, %b: !idr.box<!L>) {
      %z = arith.constant 0 : i32
      %k = arith.constant 1000 : i32
      %sa = idr.call @sum(%a, %z) : (!idr.box<!L>, i32) -> i32
      %sb = idr.call @sum(%b, %z) : (!idr.box<!L>, i32) -> i32
      %m = arith.muli %sa, %k : i32
      %s = arith.addi %m, %sb : i32
      idr.yield %s : i32
    }
    }
    return %r : i32
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c12 = arith.constant 12 : i32
    %c2 = arith.constant 2 : i64
    %z = arith.constant 0 : i32
    %l1 = idr.call @build(%c12) : (i32) -> !idr.box<!L>
    %p1 = idr.call @span(%l1) : (!idr.box<!L>) -> !P
    %s1 = idr.call @sums(%p1) : (!P) -> i32
    %l2 = idr.call @build(%c12) : (i32) -> !idr.box<!L>
    %p2 = idr.call @break(%l2) : (!idr.box<!L>) -> !P
    %s2 = idr.call @sums(%p2) : (!P) -> i32
    %l3 = idr.call @build(%c12) : (i32) -> !idr.box<!L>
    %p3 = idr.call @splitAt(%c2, %l3) : (i64, !idr.box<!L>) -> !P
    %s3 = idr.call @sums(%p3) : (!P) -> i32
    %l4 = idr.call @build(%c12) : (i32) -> !idr.box<!L>
    %p4 = idr.call @withCell(%l4) : (!idr.box<!L>) -> !P
    %s4 = idr.call @sums(%p4) : (!P) -> i32
    %w1 = idr.io.put_sint %s1, %w : i32
    %w2 = idr.io.put_sint %s2, %w1 : i32
    %w3 = idr.io.put_sint %s3, %w2 : i32
    %w4 = idr.io.put_sint %s4, %w3 : i32
    return %w4 : !idr.world
  }
}
