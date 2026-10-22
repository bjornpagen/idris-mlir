// The loop's region is repetitive: its back edge is the scf.continue
// nested in the scf.if. traverseRegionGraph reads only the terminators of
// the loop region's blocks, here scf.break, and reports it not repetitive
// (isRepetitiveRegion); from the if's then-region it enqueues the loop's
// region, which `visited`, sized by the if's two regions, indexes by the
// loop's region number.
func.func @nested_back_edge(%c: i1, %v: i32) -> i32 {
  %r = scf.loop token(%l) -> i32 {
    scf.if %c {
      scf.continue [%l]
    }
    scf.break [%l] %v : i32
  }
  return %r : i32
}
