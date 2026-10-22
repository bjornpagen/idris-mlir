// A resultless switch whose every case leaves it by a jump to the join
// point around it: it has no result and its nested ops declare no effect,
// yet it is not dead, since control leaves through it. ub.unreachable
// after it is reached by no path.
func.func @exit_only(%i: index, %a: i64, %b: i64) -> i64 {
  %r = idr.join tokens(%k) -> (i64) {
    scf.index_switch %i
    case 0 {
      idr.jump %k(%a : i64)
    }
    default {
      idr.jump %k(%b : i64)
    }
    ub.unreachable
  } join(%v: i64) {
    idr.yield %v : i64
  }
  return %r : i64
}
