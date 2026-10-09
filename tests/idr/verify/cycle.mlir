// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: awk '/^\/\/ -----$/ { n = 0; next } { line[++n] = $0 } END { for (i = 1; i <= n; i++) print line[i] }' %s > %t.knot.mlir
// RUN: not idris-mlir-opt %t.knot.mlir --idr-defunctionalize -o /dev/null 2>&1 | FileCheck %s
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

module attributes {idr.program} {
  idr.data @Node box {
    idr.ctor @MkNode (memref<?x!idr.box<@Node>>)
  }
  func.func private @grow(%node: !idr.box<@Node>, %w: !idr.world) -> !idr.world {
    %one = arith.constant 1 : i64
    // expected-error @+1 {{unsupported (cycle): an array of Node can hold a reference to itself through Node -> array of Node -> Node}}
    %a, %w1 = idr.array.new [%one], %node, %w : !idr.box<@Node> -> memref<?x!idr.box<@Node>>
    return %w1 : !idr.world
  }
  func.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An IORef is an array of rank 0: a node that holds one can be written
// into it.
module attributes {idr.program} {
  idr.data @Node box {
    idr.ctor @MkNode (memref<!idr.box<@Node>>)
  }
  func.func private @knot(%node: !idr.box<@Node>, %w: !idr.world) -> !idr.world {
    // expected-error @+1 {{unsupported (cycle): an IORef of Node can hold a reference to itself through Node -> IORef of Node -> Node}}
    %r, %w1 = idr.array.new [], %node, %w : !idr.box<@Node> -> memref<!idr.box<@Node>>
    return %w1 : !idr.world
  }
  func.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

module attributes {idr.program} {
  idr.data @A box {
    idr.ctor @MkA (memref<?x!idr.box<@B>>)
  }
  idr.data @B box {
    idr.ctor @Leaf ()
    idr.ctor @MkB (!idr.box<@A>)
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %zero = arith.constant 0 : i64
    %leaf = idr.con @B::@Leaf() : () -> !idr.box<@B>
    // expected-error @+1 {{unsupported (cycle): an array of B can hold a reference to itself through B -> A -> array of B -> B}}
    %a, %w1 = idr.array.new [%zero], %leaf, %w : !idr.box<@B> -> memref<?x!idr.box<@B>>
    return %w1 : !idr.world
  }
}

// -----

module attributes {idr.program} {
  idr.data @Grid box {
    idr.ctor @MkGrid (memref<?xmemref<?xi64>>)
  }
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %two = arith.constant 2 : i64
    %zero = arith.constant 0 : i64
    %row, %w1 = idr.array.new [%two], %zero, %w : i64 -> memref<?xi64>
    %rows, %w2 = idr.array.new [%two], %row, %w1 : memref<?xi64> -> memref<?xmemref<?xi64>>
    %g = idr.con @Grid::@MkGrid(%rows) : (memref<?xmemref<?xi64>>) -> !idr.box<@Grid>
    %l = idr.constant #idr.con<@List::@Cons, [1, #idr.con<@List::@Nil, []>]> : !idr.box<@List>
    return %w2 : !idr.world
  }
}

// -----

module attributes {idr.program} {
  idr.data @lazy$0 box memo labels [@ones] {
    idr.ctor @ones ()
    idr.ctor @running ()
    idr.ctor @forced (!idr.box<@Stream>)
  }
  idr.data @Stream box {
    idr.ctor @Cons (i64, !idr.box<@lazy$0>)
  }
  func.func private @ones() -> !idr.box<@Stream> attributes {idr.total} {
    %s = idr.constant #idr.con<@Stream::@Cons, [1, #idr.con<@lazy$0::@ones, []>]> : !idr.box<@Stream>
    return %s : !idr.box<@Stream>
  }
  func.func @Prog.main() -> i64 {
    %s = func.call @ones() : () -> !idr.box<@Stream>
    %h = idr.field %s[@Cons, 0] : !idr.box<@Stream> -> i64
    return %h : i64
  }
}

// -----

module attributes {idr.program} {
  func.func private @zero() -> i64 attributes {idr.total} {
    %c = arith.constant 0 : i64
    return %c : i64
  }
  func.func private @first(%a: memref<?x!idr.fn<() -> (i64)>>) -> i64 attributes {idr.total} {
    %w = idr.world.new
    %z = arith.constant 0 : i64
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?x!idr.fn<() -> (i64)>>
    %n = arith.index_cast %d : index to i64
    %i = idr.check.in_bounds %z, %n, "array index out of bounds"
    %f, %w1 = idr.array.get %a[%i], %w : memref<?x!idr.fn<() -> (i64)>> -> !idr.fn<() -> (i64)>
    %r = idr.apply %f() : !idr.fn<() -> (i64)>
    return %r : i64
  }
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %one = arith.constant 1 : i64
    %z = arith.constant 0 : i64
    %k = idr.closure @zero() : () -> !idr.fn<() -> (i64)>
    %a, %w1 = idr.array.new [%one], %k, %w : !idr.fn<() -> (i64)> -> memref<?x!idr.fn<() -> (i64)>>
    %c = idr.closure @first(%a) : (memref<?x!idr.fn<() -> (i64)>>) -> !idr.fn<() -> (i64)>
    %c0 = arith.constant 0 : index
    %d = memref.dim %a, %c0 : memref<?x!idr.fn<() -> (i64)>>
    %n = arith.index_cast %d : index to i64
    %i = idr.check.in_bounds %z, %n, "array index out of bounds"
    %w2 = idr.array.set %a[%i], %c, %w1 : memref<?x!idr.fn<() -> (i64)>>, !idr.fn<() -> (i64)>
    %r = func.call @first(%a) : (memref<?x!idr.fn<() -> (i64)>>) -> i64
    %w3 = idr.io.put_int signed %r, %w2 : i64
    return %w3 : !idr.world
  }
}
