// RUN: idris-mlir-opt %s --canonicalize --idr-lower '--idr-expect=holds=lowered,signature=@pick:(i1,i8,i64,i8,i64)->(i8,i64),straight-line=@pick,calls-only=@pick:[]' -o /dev/null
// canonicalize turns a match that only chooses between two values into
// arith.select, also of an idr type; that select chooses each component,
// on the one path, so a sum chosen by a condition is its components
// chosen, with no branch.
!T = !idr.data<"T", plain [@A(i64), @B()]>
idr.program @select root(@Prog.main) stage(owned) {
  idr.func @pick(%c: i1, %x: !T, %y: !T) -> !T {
    %r = arith.select %c, %x, %y : !T
    return %r : !T
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
