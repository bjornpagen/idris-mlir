// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: awk '/^\/\/ -----$/ { n = 0; next } { line[++n] = $0 } END { for (i = 1; i <= n; i++) print line[i] }' %s > %t.knot.mlir
// RUN: not idris-mlir-opt %t.knot.mlir --idr-defunctionalize -o /dev/null 2>&1 | FileCheck %s
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// Idris is strict and its data immutable, so the heap is acyclic, which is
// what lets counting free everything: an object only points at objects
// older than it. An array is the one cell written after it is made, so a
// knot needs an array whose element can reach the array again, a question
// of types: a program in which one can is refused, at the first array made
// of such a type, naming each type on the cycle. Data that is only built,
// a box of arrays of words or a list, holds no knot, nor does a memo cell,
// which is written once with a value computed from older captures. Before
// idr-defunctionalize a closure names no type yet, so the last program
// passes; after it, the closures in its array are a sum whose label holds
// that array, and the program is refused.
// CHECK: error: unsupported (cycle): an array of {{.*}} can hold a reference to itself through

!Node = !idr.data<"Node", plain [@MkNode(memref<?x!idr.box<!idr.data<"Node">>, #idr.world>)]>
idr.program @cycle root(@Prog.main) stage(first) {
  idr.func @grow(%node: !idr.box<!Node>, %w: !idr.world) -> !idr.world {
    %one = arith.constant 1 : i64
    // expected-error @+1 {{unsupported (cycle): an array of Node can hold a reference to itself through Node -> array of Node -> Node}}
    %a, %w1 = idr.array.new [%one], %node, %w : !idr.box<!Node> -> memref<?x!idr.box<!Node>, #idr.world>
    return %w1 : !idr.world
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An IORef is an array of rank 0: a node that holds one can be written
// into it.
!Node = !idr.data<"Node", plain [@MkNode(memref<!idr.box<!idr.data<"Node">>, #idr.world>)]>
idr.program @cycle root(@Prog.main) stage(first) {
  idr.func @knot(%node: !idr.box<!Node>, %w: !idr.world) -> !idr.world {
    // expected-error @+1 {{unsupported (cycle): an IORef of Node can hold a reference to itself through Node -> IORef of Node -> Node}}
    %r, %w1 = idr.array.new [], %node, %w : !idr.box<!Node> -> memref<!idr.box<!Node>, #idr.world>
    return %w1 : !idr.world
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A library's code has no place in a source file, only its name: the
// prefix installs no library sources. A knot whose array only a library
// makes, as base's newIORef makes an IORef, is reported at the program's
// own type on the cycle, which closes the knot.
!Node = !idr.data<"Node", plain [@MkNode(memref<!idr.box<!idr.data<"Node">>, #idr.world>)]>
idr.program @cycle root(@Prog.main) stage(first) {
  // expected-error @+1 {{unsupported (cycle): an IORef of Node can hold a reference to itself through Node -> IORef of Node -> Node}}
  idr.func @newIORef(%node: !idr.box<!Node>, %w: !idr.world) -> (memref<!idr.box<!Node>, #idr.world>, !idr.world) {
    %r, %w1 = idr.array.new [], %node, %w : !idr.box<!Node> -> memref<!idr.box<!Node>, #idr.world> loc(unknown)
    return %r, %w1 : memref<!idr.box<!Node>, #idr.world>, !idr.world
  } loc("Data.IORef.newIORef")
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!A = !idr.data<"A", plain [@MkA(memref<?x!idr.box<!idr.data<"B", plain [@Leaf(), @MkB(!idr.box<!idr.data<"A">>)]>>, #idr.world>)]>
!B = !idr.data<"B", plain [@Leaf(), @MkB(!idr.box<!idr.data<"A", plain [@MkA(memref<?x!idr.box<!idr.data<"B">>, #idr.world>)]>>)]>
idr.program @cycle root(@Prog.main) stage(first) {
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %zero = arith.constant 0 : i64
    %leaf = idr.con !idr.box<!B> @Leaf()
    // expected-error @+1 {{unsupported (cycle): an array of B can hold a reference to itself through B -> A -> array of B -> B}}
    %a, %w1 = idr.array.new [%zero], %leaf, %w : !idr.box<!B> -> memref<?x!idr.box<!B>, #idr.world>
    return %w1 : !idr.world
  }
}

// -----

!Grid = !idr.data<"Grid", plain [@MkGrid(memref<?xmemref<?xi64, #idr.world>, #idr.world>)]>
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @cycle root(@Prog.main) stage(first) {
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %two = arith.constant 2 : i64
    %zero = arith.constant 0 : i64
    %row, %w1 = idr.array.new [%two], %zero, %w : i64 -> memref<?xi64, #idr.world>
    %rows, %w2 = idr.array.new [%two], %row, %w1 : memref<?xi64, #idr.world> -> memref<?xmemref<?xi64, #idr.world>, #idr.world>
    %g = idr.con !idr.box<!Grid> @MkGrid(%rows : memref<?xmemref<?xi64, #idr.world>, #idr.world>)
    %l = idr.constant #idr.con<!List, @Cons, [1, #idr.con<!List, @Nil, []>]> : !idr.box<!List>
    return %w2 : !idr.world
  }
}

// -----

!lazy$0 = !idr.data<"lazy$0", memo [@ones() label @ones, @running() running, @forced(!idr.box<!idr.data<"Stream", plain [@Cons(i64, !idr.box<!idr.data<"lazy$0">>)]>>) forced]>
!Stream = !idr.data<"Stream", plain [@Cons(i64, !idr.box<!idr.data<"lazy$0", memo [@ones() label @ones, @running() running, @forced(!idr.box<!idr.data<"Stream">>) forced]>>)]>
idr.program @cycle root(@Prog.main) stage(first) {
  idr.func @ones() -> !idr.box<!Stream> attributes {total} {
    %s = idr.constant #idr.con<!Stream, @Cons, [1, #idr.con<!lazy$0, @ones, []>]> : !idr.box<!Stream>
    return %s : !idr.box<!Stream>
  }
  idr.func @Prog.main() -> i64 {
    %s = idr.call @ones() : () -> !idr.box<!Stream>
    %h = idr.field %s : !idr.box<!Stream> @Cons[0] -> i64
    return %h : i64
  }
}

// -----

idr.program @cycle root(@Prog.main) stage(higher) {
  idr.func @zero() -> i64 attributes {total} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  idr.func @first(%a: memref<?x!idr.fn<() -> (i64)>, #idr.world>) -> i64 attributes {total} {
    %w = idr.world.new
    %z = arith.constant 0 : i64
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?x!idr.fn<() -> (i64)>, #idr.world>
    %n = arith.index_cast %d : index to i64
    %i = idr.check.in_bounds %z, %a, "array index out of bounds" : memref<?x!idr.fn<() -> (i64)>, #idr.world>
    %f, %w1 = idr.array.get %a[%i], %w : memref<?x!idr.fn<() -> (i64)>, #idr.world> -> !idr.fn<() -> (i64)>
    %r = idr.apply %f() : !idr.fn<() -> (i64)>
    return %r : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %one = arith.constant 1 : i64
    %z = arith.constant 0 : i64
    %k = idr.closure @zero() : () -> !idr.fn<() -> (i64)>
    %a, %w1 = idr.array.new [%one], %k, %w : !idr.fn<() -> (i64)> -> memref<?x!idr.fn<() -> (i64)>, #idr.world>
    %c = idr.closure @first(%a) : (memref<?x!idr.fn<() -> (i64)>, #idr.world>) -> !idr.fn<() -> (i64)>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?x!idr.fn<() -> (i64)>, #idr.world>
    %n = arith.index_cast %d : index to i64
    %i = idr.check.in_bounds %z, %a, "array index out of bounds" : memref<?x!idr.fn<() -> (i64)>, #idr.world>
    %w2 = idr.array.set %a[%i], %c, %w1 : memref<?x!idr.fn<() -> (i64)>, #idr.world>, !idr.fn<() -> (i64)>
    %r = idr.call @first(%a) : (memref<?x!idr.fn<() -> (i64)>, #idr.world>) -> i64
    %w3 = idr.io.put_int signed %r, %w2 : i64
    return %w3 : !idr.world
  }
}
