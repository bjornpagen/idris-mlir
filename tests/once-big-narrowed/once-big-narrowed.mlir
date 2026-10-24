// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A big a word takes the place of where it fits gives up the reference the
// op it was passed to took, as counting gives up a value whose last use is
// behind it; and a big Idris proved used once has one owner, which no drop
// ends and no take can, a big having no constructor to take apart, so it
// leaves its linear position first, moving its reference to a value used
// many, whose word is read and which is dropped. @widen is passed a
// natural used once, which it takes as an Integer; @main passes it 3, a
// small cast into the linear position, so the conversion fits a small and
// becomes its word. The slice from the graded stage to the owned stage is
// verified after every pass, so it verifies, with nothing expected, only
// where the narrowed conversion reads the word of a value used many and
// drops only a value used many.
!OnceNat = !idr.graded<once, counted, !idr.nat<_>>
!SmallNat = !idr.graded<many, static, !idr.nat<_>>
idr.program @narrowed root(@main) stage(graded) {
  idr.func @main() {
    %three = arith.constant 3 : i64
    %small = idr.big.small %three : (i64) -> !SmallNat
    %n = idr.lin.cast %small : !SmallNat -> !OnceNat
    %b = idr.call @widen(%n) : (!OnceNat) -> !idr.big
    idr.return
  }
  idr.func @widen(%n: !OnceNat) -> !idr.big {
    %b = idr.nat.to_big %n : (!OnceNat) -> !idr.big
    idr.return %b : !idr.big
  }
}
