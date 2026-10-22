// RUN: idris-mlir-opt %s --idr-expect=holds=counts-nothing=@owns,tests-nothing=@owns,builds-nothing=@owns,no-heap-allocation=@owns,resets-unshared=@owns,reuses-every-cell=@quiet -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=counts-nothing=@counts,tests-nothing=@shares,reuses-every-cell=@shares,resets-unshared=@resets,reuses-in-place=@fresh,builds-nothing=@fresh,no-heap-allocation=@fresh -verify-diagnostics -o /dev/null
// What counting leaves in a function, as the declarations of its ops say
// to the effect system and the grades of its values say of them. @owns
// takes apart a list cell its type proves unshared: no count is read, its
// token holds the cell, and freeing the token builds nothing. @counts
// takes a reference and gives one back, each a count; @shares takes apart
// a cell its type proves nothing of, so the token may be null, and frees
// it rather than reusing it; @resets gives a value another reference and
// then tests whether it is shared, which it always is; @fresh makes a
// fresh cell on the heap, no recycled one.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!List = !idr.data<#List>
!Cons = !idr.data<#List @Cons>
!Unique = !idr.graded<once, counted unique deep, !Cons>
!Tail = !idr.graded<many, counted unique deep, !List>
!Token = !idr.graded<once, counted unique deep, !idr.reuse_token<{!Cons}>>
!Shared = !idr.graded<once, counted, !idr.reuse_token<{!Cons}>>
!Cell = !idr.cell<!Cons>
idr.program @counting root(@quiet) stage(owned) {
  idr.func @quiet(%x: i64) -> i64 {
    idr.return %x : i64
  }
  idr.func @owns(%x: !Unique) -> i64 {
    %t, %h, %tl = idr.count.take %x : !Unique
    idr.token.free %t : !Token
    idr.count.drop %tl : !Tail
    idr.return %h : i64
  }
  idr.func @counts(%x: !List) -> !List {
    // expected-error @below {{expected counts-nothing: }}
    %y = idr.count.dup %x : !List
    // expected-error @below {{expected counts-nothing: }}
    idr.count.drop %x : !List
    idr.return %y : !List
  }
  idr.func @shares(%x: !Cons) -> i64 {
    // expected-error @below {{expected tests-nothing: }}
    %t, %h, %tl = idr.count.take %x : !Cons
    // expected-error @below {{expected reuses-every-cell: }}
    idr.token.free %t : !Shared
    idr.count.drop %tl : !List
    idr.return %h : i64
  }
  idr.func @resets(%x: !Cons) -> !Cons {
    %y = idr.count.dup %x : !Cons
    // expected-error @below {{expected resets-unshared: }}
    %t, %h, %tl = idr.count.take %x : !Cons
    idr.token.free %t : !Shared
    idr.count.drop %tl : !List
    idr.return %y : !Cons
  }
  // expected-error @below {{expected reuses-in-place: }}
  idr.func @fresh(%x: i64) -> i64 {
    // expected-error @below {{expected reuses-in-place: }}
    // expected-error @below {{expected builds-nothing: }}
    // expected-error @below {{expected no-heap-allocation: }}
    %c = idr.cell.new : !Cell
    idr.return %x : i64
  }
}
