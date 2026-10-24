// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A value built of a part claims what the part gives it: a part used once
// moves its one reference in with all it claims, and a part used many
// times gives nothing, since its other uses reach its cells as well. So,
// before references are counted, a pair of one list in both fields claimed
// `unique deep` is the error, and a pair of two lists each used once
// verifies at that claim.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
#Pair = #idr.family<"Pair" [] {
    @MkPair (!idr.data<#List>, !idr.data<#List>)
  }>
!Many = !idr.graded<many, counted unique deep, !idr.data<#List>>
!Deep = !idr.graded<many, counted unique deep, !idr.data<#Pair>>
idr.program @pairs root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @both(%xs: !Many) -> !Deep {
    // expected-error @below {{}}
    %p = idr.data.con(%xs : !Many, %xs : !Many) : !Deep
    idr.return %p : !Deep
  }
}

// -----

#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
#Pair = #idr.family<"Pair" [] {
    @MkPair (!idr.data<#List>, !idr.data<#List>)
  }>
!Once = !idr.graded<once, counted unique deep, !idr.data<#List>>
!Deep = !idr.graded<many, counted unique deep, !idr.data<#Pair>>
idr.program @pairs root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @two(%xs: !Once, %ys: !Once) -> !Deep {
    %p = idr.data.con(%xs : !Once, %ys : !Once) : !Deep
    idr.return %p : !Deep
  }
}
