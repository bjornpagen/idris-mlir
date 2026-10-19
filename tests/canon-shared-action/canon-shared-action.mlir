// RUN: idris-mlir-opt %s --idr-expect=holds=reads-fields=@twice,reads-fields=@chosen_twice -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=reads-no-fields=@twice,applies=@twice,\
// RUN: reads-no-fields=@chosen_twice,applies=@chosen_twice -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// An IO action that is run twice, as an action forced twice is: its
// constructor holds the closure of a bind entered into its linear field,
// and the field read out of the shared action is an ordinary function. The
// closure holds the linear halves of the bind, so its one use is the entry
// (the verifier's rule, checked after the pass): taking the constructor
// apart leaves the closure entered and used, and the two applies read the
// use. Without the pair the closure would have the two applies, each a
// call that passes the linear halves: two uses of each.

!IO = !idr.data<"IO", plain [@MkIO(!idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>)]>
idr.program @"shared-action" root(@root) stage(higher) {
  idr.func @bind(%act: !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>,
                          %w: !idr.world) -> !idr.world {
    idr.crash "no body"
    ub.unreachable
  }

  idr.func @twice(%act: !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>,
                   %w: !idr.world) -> !idr.world {
    %e = idr.closure @bind(%act) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>)
       -> !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>
    %io = idr.con !IO @MkIO(%e : !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>)
    %f = idr.field %io : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!idr.world)>
    %w1 = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!idr.world)>
    %w2 = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.world)>
    return %w2 : !idr.world
  }

  // The action is chosen by a match and read after it: the read moves into
  // each region (case-of-case), where it meets the constructor, and the
  // closure each region builds leaves it entered and used.
  idr.func @chosen_twice(%k: i64,
                          %a: !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>,
                          %b: !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>,
                          %w: !idr.world) -> !idr.world {
    %io = idr.match_lit %k : i64 -> (!IO) {
    case 0 {
      %e = idr.closure @bind(%a) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>)
         -> !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>
      %x = idr.con !IO @MkIO(%e : !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>)
      idr.yield %x : !IO
    }
    default(%d: i64) {
      %e = idr.closure @bind(%b) : (!idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>)
         -> !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>
      %x = idr.con !IO @MkIO(%e : !idr.lin<!idr.fn<(!idr.world) -> (!idr.world)>>)
      idr.yield %x : !IO
    }
    }
    %f = idr.field %io : !IO @MkIO[0] -> !idr.fn<(!idr.world) -> (!idr.world)>
    %w1 = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!idr.world)>
    %w2 = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.world)>
    return %w2 : !idr.world
  }

  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
