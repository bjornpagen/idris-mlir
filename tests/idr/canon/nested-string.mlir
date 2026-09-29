// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// A string built by matches nested in one another, as `show` builds one for
// a Maybe inside a pair, is written piece by piece: output moves into the
// outer match, then into the match nested in each region, until it meets
// the builders and output fusion takes them apart. Other consumers do not
// look through nested matches, and output stops where nothing is built.

idr.data @Maybe {
  idr.ctor @Nothing tag 0 ()
  idr.ctor @Just tag 1 (i64)
}
idr.data @Either {
  idr.ctor @Left tag 0 (i64)
  idr.ctor @Right tag 1 (i64)
}
idr.data @P {
  idr.ctor @MkP tag 0 (i64, i64)
}

// putStr (case m of Nothing => none; Just x => case e of Left y => "Left "
// ++ show y; Right y => show y), after a write the string does not depend
// on. No region of the outer match yields a string being built, nor anything
// else output folds against: every string is built one match further in.
// Nothing is built at runtime: each leaf writes its pieces, in order, after
// the first write.
// CHECK-LABEL: func.func @nested(
// CHECK-SAME: %[[M:.*]]: !idr.data<@Maybe>, %[[E:.*]]: !idr.data<@Either>, %[[NONE:.*]]: !idr.str, %[[W:.*]]: !idr.world)
// CHECK-NOT: idr.str.
// CHECK: %[[W1:.*]] = idr.io.put_str %{{.*}}, %[[W]]
// CHECK-NEXT: idr.match %[[M]]
// CHECK-NEXT: case @Nothing() {
// CHECK-NEXT: idr.io.put_str %[[NONE]], %[[W1]]
// CHECK: case @Just(
// CHECK-NEXT: idr.match %[[E]]
// CHECK-NEXT: case @Left(%[[Y:.*]]: i64) {
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_str %{{.*}}, %[[W1]]
// CHECK-NEXT: idr.io.put_int signed %[[Y]], %[[W2]]
// CHECK: case @Right(%[[Z:.*]]: i64) {
// CHECK-NEXT: idr.io.put_int signed %[[Z]], %[[W1]]
// CHECK-NOT: idr.str.
// CHECK: return
func.func @nested(%m: !idr.data<@Maybe>, %e: !idr.data<@Either>, %none: !idr.str,
                  %w: !idr.world) -> !idr.world {
  %s = idr.match %m : !idr.data<@Maybe> -> (!idr.str) {
  case @Nothing() {
    idr.yield %none : !idr.str
  }
  case @Just(%x: i64) {
    %t = idr.match %e : !idr.data<@Either> -> (!idr.str) {
    case @Left(%y: i64) {
      %l = idr.constant "Left " : !idr.str
      %n = idr.str.show signed %y : i64
      %a = idr.str.append %l, %n
      idr.yield %a : !idr.str
    }
    case @Right(%y: i64) {
      %n = idr.str.show signed %y : i64
      idr.yield %n : !idr.str
    }
    }
    idr.yield %t : !idr.str
  }
  }
  %open = idr.constant "(" : !idr.str
  %w1 = idr.io.put_str %open, %w
  %w2 = idr.io.put_str %s, %w1
  return %w2 : !idr.world
}

// Three matches deep, a string built only in the innermost: output reaches
// it, one match at a time, and writes the number there.
// CHECK-LABEL: func.func @three_deep(
// CHECK-SAME: %[[X:[^:]*]]: i64
// CHECK-NOT: idr.str.show
// CHECK: case 0 {
// CHECK: case 0 {
// CHECK: case 0 {
// CHECK-NEXT: idr.io.put_int signed %[[X]]
// CHECK-NOT: idr.str.show
// CHECK: return
func.func @three_deep(%x: i64, %a: i64, %b: i64, %c: i64, %sa: !idr.str, %sb: !idr.str, %sc: !idr.str,
                      %w: !idr.world) -> !idr.world {
  %s = idr.match_lit %a : i64 -> (!idr.str) {
  case 0 {
    %t = idr.match_lit %b : i64 -> (!idr.str) {
    case 0 {
      %u = idr.match_lit %c : i64 -> (!idr.str) {
      case 0 {
        %n = idr.str.show signed %x : i64
        idr.yield %n : !idr.str
      }
      default {
        idr.yield %sc : !idr.str
      }
      }
      idr.yield %u : !idr.str
    }
    default {
      idr.yield %sb : !idr.str
    }
    }
    idr.yield %t : !idr.str
  }
  default {
    idr.yield %sa : !idr.str
  }
  }
  %w1 = idr.io.put_str %s, %w
  return %w1 : !idr.world
}

// The nested matches build nothing: they choose among strings that already
// exist. Output stays after the outer match, written once.
// CHECK-LABEL: func.func @nothing_built(
// CHECK: %[[S:.*]] = idr.match
// CHECK-NOT: idr.io.put_str
// CHECK: %[[T:.*]] = idr.match
// CHECK-NOT: idr.io.put_str
// CHECK: idr.yield %[[T]] : !idr.str
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: %[[W1:.*]] = idr.io.put_str %[[S]]
// CHECK-NEXT: return %[[W1]]
func.func @nothing_built(%m: !idr.data<@Maybe>, %e: !idr.data<@Either>, %p: !idr.str,
                         %q: !idr.str, %r: !idr.str, %w: !idr.world) -> !idr.world {
  %s = idr.match %m : !idr.data<@Maybe> -> (!idr.str) {
  case @Nothing() {
    idr.yield %p : !idr.str
  }
  case @Just(%x: i64) {
    %t = idr.match %e : !idr.data<@Either> -> (!idr.str) {
    case @Left(%y: i64) {
      idr.yield %q : !idr.str
    }
    case @Right(%y: i64) {
      idr.yield %r : !idr.str
    }
    }
    idr.yield %t : !idr.str
  }
  }
  %w1 = idr.io.put_str %s, %w
  return %w1 : !idr.world
}

// The match a region yields from is not in that region: output moved into
// the region would not sit next to it, so it could go no further. It stays
// after the outer match.
// CHECK-LABEL: func.func @yielded_from_outside(
// CHECK: %[[T:.*]] = idr.match %{{.*}} : !idr.data<@Either>
// CHECK: idr.str.show
// CHECK: %[[S:.*]] = idr.match %{{.*}} : !idr.data<@Maybe>
// CHECK-NOT: idr.io.put
// CHECK: idr.yield %[[T]] : !idr.str
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: %[[W1:.*]] = idr.io.put_str %[[S]]
// CHECK-NEXT: %[[W2:.*]] = idr.io.put_str %[[T]], %[[W1]]
// CHECK-NEXT: return %[[W2]]
func.func @yielded_from_outside(%m: !idr.data<@Maybe>, %e: !idr.data<@Either>, %p: !idr.str,
                                %w: !idr.world) -> !idr.world {
  %t = idr.match %e : !idr.data<@Either> -> (!idr.str) {
  case @Left(%y: i64) {
    %n = idr.str.show signed %y : i64
    idr.yield %n : !idr.str
  }
  case @Right(%y: i64) {
    idr.yield %p : !idr.str
  }
  }
  %s = idr.match %m : !idr.data<@Maybe> -> (!idr.str) {
  case @Nothing() {
    idr.yield %p : !idr.str
  }
  case @Just(%x: i64) {
    idr.yield %t : !idr.str
  }
  }
  %w1 = idr.io.put_str %s, %w
  %w2 = idr.io.put_str %t, %w1
  return %w2 : !idr.world
}

// A consumer other than output does not look through nested matches, even
// where it would meet a constructor: fst of a pair chosen two matches deep
// stays after the outer match.
// CHECK-LABEL: func.func @field_nested(
// CHECK: %[[Q:.*]] = idr.match_lit
// CHECK-NOT: idr.field
// CHECK: %[[R:.*]] = idr.match_lit
// CHECK-NOT: idr.field
// CHECK: idr.yield %[[R]] : !idr.data<@P>
// CHECK-NEXT: }
// CHECK-NEXT: }
// CHECK-NEXT: %[[F:.*]] = idr.field %[[Q]][@MkP, 0]
// CHECK-NEXT: return %[[F]]
func.func @field_nested(%a: i64, %b: i64, %p: !idr.data<@P>) -> i64 {
  %q = idr.match_lit %a : i64 -> (!idr.data<@P>) {
  case 0 {
    idr.yield %p : !idr.data<@P>
  }
  default {
    %r = idr.match_lit %b : i64 -> (!idr.data<@P>) {
    case 0 {
      idr.yield %p : !idr.data<@P>
    }
    default {
      %c = idr.con @P::@MkP(%a, %b) : (i64, i64) -> !idr.data<@P>
      idr.yield %c : !idr.data<@P>
    }
    }
    idr.yield %r : !idr.data<@P>
  }
  }
  %f = idr.field %q[@MkP, 0] : !idr.data<@P> -> i64
  return %f : i64
}
