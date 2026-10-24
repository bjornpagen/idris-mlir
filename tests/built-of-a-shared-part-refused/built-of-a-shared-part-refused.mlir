// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// Before references are counted, a value used many times claims nothing
// of its sharing, since counting makes each of its uses a reference of its
// own; once they are counted, each reference is explicit and a value claims
// what its own reaches. And a value built of parts claims no more than they
// give it: a part claims what its type says, and a value spread over every
// slot of a new array gives it nothing beyond its storage, each slot
// reaching it. Refused: a list used many times claimed `unique deep` before
// counting; a cell over a tail that claims nothing claimed `unique self`;
// an array of rank 1 full of one list claimed `unique deep`. Verified: the
// same list after counting, a cell over a tail that claims its own cells,
// that array claiming its storage, and an array of rank 0, whose one slot
// holds the list once, claimed `unique deep`.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!Many = !idr.graded<many, counted unique deep, !idr.data<#List>>
idr.program @shared root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  // expected-error @below {{}}
  idr.func @keep(%xs: !Many) -> !Many {
    idr.return %xs : !Many
  }
}

// -----

#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!Many = !idr.graded<many, counted unique deep, !idr.data<#List>>
idr.program @shared root(@main) stage(owned) {
  idr.func @main() {
    idr.return
  }
  idr.func @keep(%xs: !Many) -> !Many {
    idr.return %xs : !Many
  }
}

// -----

#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!Bare = !idr.graded<once, counted, !idr.data<#List>>
!Self = !idr.graded<once, counted unique self, !idr.data<#List @Cons>>
idr.program @cells root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @onto(%x: i64, %xs: !Bare) -> !Self {
    // expected-error @below {{}}
    %c = idr.data.con(%x : i64, %xs : !Bare) : !Self
    idr.return %c : !Self
  }
}

// -----

#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!OnceSelf = !idr.graded<once, counted unique self, !idr.data<#List>>
!Self = !idr.graded<once, counted unique self, !idr.data<#List @Cons>>
idr.program @cells root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @onto(%x: i64, %xs: !OnceSelf) -> !Self {
    %c = idr.data.con(%x : i64, %xs : !OnceSelf) : !Self
    idr.return %c : !Self
  }
}

// -----

#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!Once = !idr.graded<once, counted unique deep, !idr.data<#List>>
!Full = !idr.graded<once, counted unique deep, memref<?x!idr.data<#List>, #idr.mutable>>
idr.program @arrays root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @full(%n: index, %fill: !Once) -> !Full {
    // expected-error @below {{}}
    %a = idr.array.new [%n], %fill : !Once -> !Full
    idr.return %a : !Full
  }
}

// -----

#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!Once = !idr.graded<once, counted unique deep, !idr.data<#List>>
!Storage = !idr.graded<once, counted unique self, memref<?x!idr.data<#List>, #idr.mutable>>
!Ref = !idr.graded<once, counted unique deep, memref<!idr.data<#List>, #idr.mutable>>
idr.program @arrays root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @full(%n: index, %fill: !Once) -> !Storage {
    %a = idr.array.new [%n], %fill : !Once -> !Storage
    idr.return %a : !Storage
  }
  idr.func @one(%fill: !Once) -> !Ref {
    %r = idr.array.new [], %fill : !Once -> !Ref
    idr.return %r : !Ref
  }
}
