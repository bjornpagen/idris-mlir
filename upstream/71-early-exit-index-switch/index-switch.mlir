// mlir-opt index-switch.mlir -convert-scf-to-cf
//
// At the pin with 65 alone, the verifier refuses the switch's case 0
// ("expected region to end with scf.yield") and case 1. With the patch the
// break lowers to a branch to the loop's exit block, and case 1 stays an
// unreachable block.
func.func @index_switch_break(%i: index, %v: i32) -> i32 {
  %r = scf.loop token(%loop) -> i32 {
    scf.index_switch %i
    case 0 {
      scf.break [%loop] %v : i32
    }
    case 1 {
      ub.unreachable
    }
    default {
      scf.yield
    }
    scf.continue [%loop]
  }
  return %r : i32
}
