// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A buffer is lent to upstream's ops as its bare carrier under a lifetime
// (idr.carrier %v in %l): its holder keeps it at its grade and no count
// changes, so the carrier is a reference of no one's, and nothing made of
// it may outlive the lifetime or become anyone's. The function's verifier
// follows every alias of a loan and refuses each way out, at the op that
// takes it, with a note at the loan: an alias given out of the region that
// binds the loan's lifetime, returned from the function, stored into
// memory as a value, or made a reference of its own by an op of ours. A
// loan read inside its region, which gives back a word, verifies. Each
// module that is refused differs from one that verifies by its way out
// alone, so the refusal is the loan's.
idr.program @loans root(@main) stage(graded) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @size(%v: memref<?xi64>) -> i64 {
    %n = idr.lifetime -> i64 {
    ^bb0(%l: !idr.lifetime<view>):
      %bare = idr.carrier %v in %l : memref<?xi64>, !idr.lifetime<view>
      %zero = arith.constant 0 : index
      %d = memref.dim %bare, %zero : memref<?xi64>
      %w = arith.index_cast %d : index to i64
      idr.yield %w : i64
    }
    idr.return %n : i64
  }
}

// -----

// Given out of the region that binds its lifetime: the opener's result is
// the alias, outside that region.
idr.program @loans root(@main) stage(graded) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @leaks(%v: memref<?xi64>) -> memref<?xi64> {
    // expected-error @below {{}}
    %out = idr.lifetime -> memref<?xi64> {
    ^bb0(%l: !idr.lifetime<view>):
      // expected-note @below {{}}
      %bare = idr.carrier %v in %l : memref<?xi64>, !idr.lifetime<view>
      idr.yield %bare : memref<?xi64>
    }
    idr.return %out : memref<?xi64>
  }
}

// -----

// Returned from the function, lent under this activation's lifetime, whose
// region is the function's body.
idr.program @loans root(@main) stage(graded) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @gives(%v: memref<?xi64>) -> memref<?xi64> {
    %l = idr.activation
    // expected-note @below {{}}
    %bare = idr.carrier %v in %l : memref<?xi64>, !idr.lifetime<view>
    // expected-error @below {{}}
    idr.return %bare : memref<?xi64>
  }
}

// -----

// Stored as the value a write puts into a buffer of buffers.
idr.program @loans root(@main) stage(graded) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @stores(%v: memref<?xi64>, %outer: memref<1xmemref<?xi64>>) {
    idr.lifetime {
    ^bb0(%l: !idr.lifetime<view>):
      // expected-note @below {{}}
      %bare = idr.carrier %v in %l : memref<?xi64>, !idr.lifetime<view>
      %zero = arith.constant 0 : index
      // expected-error @below {{}}
      memref.store %bare, %outer[%zero] : memref<1xmemref<?xi64>>
      idr.yield
    }
    idr.return
  }
}

// -----

// Made a reference of its own by an op of ours: a cast into a linear
// position, which counting would then own.
!Owned = !idr.graded<once, counted, memref<?xi64>>
idr.program @loans root(@main) stage(graded) {
  idr.func @main() -> i64 {
    %c = arith.constant 0 : i64
    idr.return %c : i64
  }
  idr.func @adopts(%v: memref<?xi64>) -> !Owned {
    %r = idr.lifetime -> !Owned {
    ^bb0(%l: !idr.lifetime<view>):
      // expected-note @below {{}}
      %bare = idr.carrier %v in %l : memref<?xi64>, !idr.lifetime<view>
      // expected-error @below {{}}
      %own = idr.lin.cast %bare : memref<?xi64> -> !Owned
      idr.yield %own : !Owned
    }
    idr.return %r : !Owned
  }
}
