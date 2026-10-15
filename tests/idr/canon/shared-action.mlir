// RUN: idris-mlir-opt %s --canonicalize | FileCheck %s
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// An IO action that is run twice, as an action forced twice is: its
// constructor holds the closure of a bind entered into its linear field,
// and the field read out of the shared action is an ordinary function. The
// closure holds the linear halves of the bind, so its one use is the entry
// (the verifier's rule, checked after the pass): taking the constructor
// apart leaves the closure entered and used, and the two applies read the
// use. Without the pair the closure would have the two applies, each a
// call that passes the linear halves: two uses of each. A field read once
// and applied once still becomes the call.

!IORes = !idr.data<"IORes", plain [@MkIORes(i64, !idr.world)]>
!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)]>
idr.func private @bind(%act: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                        %w: !idr.world) -> !IORes {
  idr.crash "no body"
  ub.unreachable
}

// CHECK-LABEL: idr.func private @twice(
// CHECK: %[[C:.*]] = {{(idr\.)?}}closure @bind(
// CHECK-NEXT: %[[E:.*]] = idr.lin.enter %[[C]]
// CHECK-NEXT: %[[F:.*]] = idr.lin.use %[[E]]
// CHECK: apply %[[F]](
// CHECK: apply %[[F]](
idr.func private @twice(%act: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                 %w: !idr.world) -> !IORes {
  %c = idr.closure @bind(%act) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
     -> !idr.fn<(!idr.world) -> (!IORes)>
  %e = idr.lin.enter %c : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
  %io = idr.con @MkIO(%e) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
      -> !IO
  %f = idr.field %io[@MkIO, 0] : !IO -> !idr.fn<(!idr.world) -> (!IORes)>
  %r1 = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
  %w1 = idr.field %r1[@MkIORes, 1] : !IORes -> !idr.world
  %r2 = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
  return %r2 : !IORes
}

// The action is chosen by a match and read after it: the read moves into
// each region (case-of-case), where it meets the constructor, and the
// closure each region builds leaves it entered and used.
// CHECK-LABEL: idr.func private @chosen_twice(
// CHECK: %[[M:.*]] = {{(idr\.)?}}match_lit
// CHECK: closure @bind(
// CHECK-NEXT: idr.lin.enter
// CHECK-NEXT: idr.lin.use
// CHECK: closure @bind(
// CHECK-NEXT: idr.lin.enter
// CHECK-NEXT: idr.lin.use
// CHECK: apply %[[M]](
// CHECK: apply %[[M]](
idr.func private @chosen_twice(%k: i64,
                        %a: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                        %b: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                        %w: !idr.world) -> !IORes {
  %io = idr.match_lit %k : i64 -> (!IO) {
  case 0 {
    %c = idr.closure @bind(%a) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
       -> !idr.fn<(!idr.world) -> (!IORes)>
    %e = idr.lin.enter %c : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %x = idr.con @MkIO(%e) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
       -> !IO
    idr.yield %x : !IO
  }
  default {
    %c = idr.closure @bind(%b) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
       -> !idr.fn<(!idr.world) -> (!IORes)>
    %e = idr.lin.enter %c : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %x = idr.con @MkIO(%e) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
       -> !IO
    idr.yield %x : !IO
  }
  }
  %f = idr.field %io[@MkIO, 0] : !IO -> !idr.fn<(!idr.world) -> (!IORes)>
  %r1 = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
  %w1 = idr.field %r1[@MkIORes, 1] : !IORes -> !idr.world
  %r2 = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
  return %r2 : !IORes
}

// Read once and applied once, the closure is the apply's: a call.
// CHECK-LABEL: idr.func private @once(
// CHECK-SAME: %[[ACT:[a-z0-9_]+]]: !idr.lin<
// CHECK-SAME: %[[W:[a-z0-9_]+]]: !idr.world)
// CHECK-NOT: {{(idr\.| )closure }}
// CHECK: %[[R:.*]] = call @bind(%[[ACT]], %[[W]])
// CHECK-NEXT: return %[[R]]
idr.func private @once(%act: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                %w: !idr.world) -> !IORes {
  %c = idr.closure @bind(%act) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
     -> !idr.fn<(!idr.world) -> (!IORes)>
  %e = idr.lin.enter %c : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
  %io = idr.con @MkIO(%e) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
      -> !IO
  %f = idr.field %io[@MkIO, 0] : !IO -> !idr.fn<(!idr.world) -> (!IORes)>
  %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
  return %r : !IORes
}
