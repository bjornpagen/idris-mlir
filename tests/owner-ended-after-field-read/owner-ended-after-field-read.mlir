// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A value Idris proved used once may have a field read and then its owner
// ended: the read is a use of that field, and the op that ends the owner
// reads no field. It moves the cell into a token and the fields out, each
// a value of its own, and is the cell's use alone. Each function here
// reads the head of a list cell used once, which nothing claims unique,
// or the word of a pair held in place, and then gives its tail on through
// one of the three ops that end an owner after counting has placed its
// takes: the test of sharing (@matched), the take fused with the recycle
// of the cell into a new one (@recycled), and the unpack of a value in
// place (@unpacked). The test's shared region takes the list at many
// uses, as the runtime found it shared, so the tail it reads is used many
// and takes its reference by a dup. At the graded stage counting's ops may
// stand and nothing is counted yet, so what the verifier holds them to is
// the linearity rule and each op's own. The first module verifies; each
// one refused after it differs from @matched by one thing: a use that
// takes the whole list in place of the test, or the test's shared region
// binding the list used once.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!List = !idr.data<#List>
!Cons = !idr.data<#List @Cons>
!Once = !idr.graded<once, counted, !Cons>
!Token = !idr.graded<once, counted unique deep, !idr.reuse_token<{!Cons}>>
#Pair = #idr.family<"Pair" [] {
    @MkPair (i64, !List)
  }>
!OncePair = !idr.graded<once, counted, !idr.data<#Pair>>
idr.program @owners root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @matched(%xs: !Once) -> (i64, !List) {
    %h = idr.data.field %xs[0] : !Once -> i64
    %tail = idr.count.match_unique %xs : !Once -> (!List) unique {
    ^bb0(%t: !Token, %head: i64, %tl: !List):
      idr.token.free %t : !Token
      idr.yield %tl : !List
    } shared {
    ^bb0(%s: !Cons):
      %tl = idr.data.field %s[1] : !Cons -> !List
      %d = idr.count.dup %tl : !List
      idr.count.drop %s : !Cons
      idr.yield %d : !List
    }
    idr.return %h, %tail : i64, !List
  }
  idr.func @recycled(%xs: !Once) -> !Cons {
    %h = idr.data.field %xs[0] : !Once -> i64
    %one = arith.constant 1 : i64
    %next = arith.addi %h, %one : i64
    %cell, %head, %tl = idr.count.take_into %xs : !Once -> (!idr.cell<!Cons>, i64, !List)
    %ys = idr.cell.init %cell : !idr.cell<!Cons> (%next : i64, %tl : !List) -> !Cons
    idr.return %ys : !Cons
  }
  idr.func @unpacked(%p: !OncePair) -> (i64, !List) {
    %n = idr.data.field %p[0] : !OncePair -> i64
    %m, %l = idr.count.unpack %p : !OncePair
    idr.return %n, %l : i64, !List
  }
}

// -----

// The list given back whole after its head is read: a second use of the
// head, which only an op that ends the owner is not.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!Cons = !idr.data<#List @Cons>
!Once = !idr.graded<once, counted, !Cons>
idr.program @owners root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @whole(%xs: !Once) -> (i64, !Once) {
    %h = idr.data.field %xs[0] : !Once -> i64
    // expected-error @below {{uses a value used once that is already used on the same path}}
    idr.return %h, %xs : i64, !Once
  }
}

// -----

// The test's shared region binding the list used once: the cell it holds
// is shared, so what it is given is used many.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (i64, !idr.self)
  }>
!List = !idr.data<#List>
!Cons = !idr.data<#List @Cons>
!Once = !idr.graded<once, counted, !Cons>
!Token = !idr.graded<once, counted unique deep, !idr.reuse_token<{!Cons}>>
idr.program @owners root(@main) stage(graded) {
  idr.func @main() {
    idr.return
  }
  idr.func @matched(%xs: !Once) -> !List {
    // expected-error @below {{binds in its shared region other than}}
    %tail = idr.count.match_unique %xs : !Once -> (!List) unique {
    ^bb0(%t: !Token, %head: i64, %tl: !List):
      idr.token.free %t : !Token
      idr.yield %tl : !List
    } shared {
    ^bb0(%s: !Once):
      %tl = idr.data.field %s[1] : !Once -> !List
      %d = idr.count.dup %tl : !List
      idr.yield %d : !List
    }
    idr.return %tail : !List
  }
}
