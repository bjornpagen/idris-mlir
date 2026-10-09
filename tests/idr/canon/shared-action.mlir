// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// An IO action that is run twice, as an action forced twice is: its
// constructor holds the closure of a bind entered into its linear field,
// and the field read out of the shared action is an ordinary function. The
// closure holds the linear halves of the bind, so its one use is the entry
// (the verifier's rule, checked after the pass): taking the constructor
// apart leaves the closure entered and used, and the two applies read the
// use. Without the pair the closure would have the two applies, each a
// call that passes the linear halves: two uses of each. A field read once
// and applied once still becomes the call.

idr.data @IORes {
  idr.ctor @MkIORes (i64, !idr.world)
}
idr.data @IO {
  idr.ctor @MkIO (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
}
func.func private @bind(%act: !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>,
                        %w: !idr.world) -> !idr.data<@IORes>

// CHECK-LABEL: func.func @twice(
// CHECK: %[[C:.*]] = idr.closure @bind(
// CHECK-NEXT: %[[E:.*]] = idr.lin.enter %[[C]]
// CHECK-NEXT: %[[F:.*]] = idr.lin.use %[[E]]
// CHECK: idr.apply %[[F]](
// CHECK: idr.apply %[[F]](
func.func @twice(%act: !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>,
                 %w: !idr.world) -> !idr.data<@IORes> {
  %c = idr.closure @bind(%act) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
     -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  %e = idr.lin.enter %c : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
  %io = idr.con @IO::@MkIO(%e) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
      -> !idr.data<@IO>
  %f = idr.field %io[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  %r1 = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  %w1 = idr.field %r1[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
  %r2 = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  return %r2 : !idr.data<@IORes>
}

// The action is chosen by a match and read after it: the read moves into
// each region (case-of-case), where it meets the constructor, and the
// closure each region builds leaves it entered and used.
// CHECK-LABEL: func.func @chosen_twice(
// CHECK: %[[M:.*]] = idr.match_lit
// CHECK: idr.closure @bind(
// CHECK-NEXT: idr.lin.enter
// CHECK-NEXT: idr.lin.use
// CHECK: idr.closure @bind(
// CHECK-NEXT: idr.lin.enter
// CHECK-NEXT: idr.lin.use
// CHECK: idr.apply %[[M]](
// CHECK: idr.apply %[[M]](
func.func @chosen_twice(%k: i64,
                        %a: !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>,
                        %b: !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>,
                        %w: !idr.world) -> !idr.data<@IORes> {
  %io = idr.match_lit %k : i64 -> (!idr.data<@IO>) {
  case 0 {
    %c = idr.closure @bind(%a) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
       -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %e = idr.lin.enter %c : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %x = idr.con @IO::@MkIO(%e) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
       -> !idr.data<@IO>
    idr.yield %x : !idr.data<@IO>
  }
  default {
    %c = idr.closure @bind(%b) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
       -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %e = idr.lin.enter %c : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
    %x = idr.con @IO::@MkIO(%e) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
       -> !idr.data<@IO>
    idr.yield %x : !idr.data<@IO>
  }
  }
  %f = idr.field %io[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  %r1 = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  %w1 = idr.field %r1[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
  %r2 = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  return %r2 : !idr.data<@IORes>
}

// Read once and applied once, the closure is the apply's: a call.
// CHECK-LABEL: func.func @once(
// CHECK-SAME: %[[ACT:[a-z0-9_]+]]: !idr.lin<
// CHECK-SAME: %[[W:[a-z0-9_]+]]: !idr.world)
// CHECK-NOT: idr.closure
// CHECK: %[[R:.*]] = call @bind(%[[ACT]], %[[W]])
// CHECK-NEXT: return %[[R]]
func.func @once(%act: !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>,
                %w: !idr.world) -> !idr.data<@IORes> {
  %c = idr.closure @bind(%act) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
     -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  %e = idr.lin.enter %c : !idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>
  %io = idr.con @IO::@MkIO(%e) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>>)
      -> !idr.data<@IO>
  %f = idr.field %io[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
  return %r : !idr.data<@IORes>
}
