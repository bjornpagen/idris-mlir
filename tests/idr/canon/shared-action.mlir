// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=reads-no-fields=@twice,applies=@twice,\
// RUN: reads-no-fields=@chosen_twice,applies=@chosen_twice,no-closures=@once,calls=@once:@bind -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
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
idr.program @"shared-action" root(@root) stage(higher) {
  idr.func @bind(%act: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                          %w: !idr.world) -> !IORes {
    idr.crash "no body"
    ub.unreachable
  }

  idr.func @twice(%act: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                   %w: !idr.world) -> !IORes {
    %e = idr.closure @bind(%act) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
       -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%e : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    %f = idr.field %io : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %r1 = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    %w1 = idr.field %r1 : !IORes @MkIORes[1] -> !idr.world
    %r2 = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r2 : !IORes
  }

  // The action is chosen by a match and read after it: the read moves into
  // each region (case-of-case), where it meets the constructor, and the
  // closure each region builds leaves it entered and used.
  idr.func @chosen_twice(%k: i64,
                          %a: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                          %b: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                          %w: !idr.world) -> !IORes {
    %io = idr.match_lit %k : i64 -> (!IO) {
    case 0 {
      %e = idr.closure @bind(%a) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
         -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
      %x = idr.con !IO @MkIO(%e : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
      idr.yield %x : !IO
    }
    default(%d: i64) {
      %e = idr.closure @bind(%b) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
         -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
      %x = idr.con !IO @MkIO(%e : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
      idr.yield %x : !IO
    }
    }
    %f = idr.field %io : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %r1 = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    %w1 = idr.field %r1 : !IORes @MkIORes[1] -> !idr.world
    %r2 = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r2 : !IORes
  }

  // Read once and applied once, the closure is the apply's: a call.
  idr.func @once(%act: !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>,
                  %w: !idr.world) -> !IORes {
    %e = idr.closure @bind(%act) : (!idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
       -> !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>
    %io = idr.con !IO @MkIO(%e : !idr.lin<!idr.fn<(!idr.world) -> (!IORes)>>)
    %f = idr.field %io : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!IORes)>
    %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!IORes)>
    return %r : !IORes
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
