// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

idr.program @ops root(@root) stage(first) {
  idr.func @f(%d: f64) {
    // expected-error @+1 {{shows a Double, which has no signedness}}
    %s = idr.str.show signed %d : f64
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @ops root(@root) stage(first) {
  idr.func @f(%x: i1) {
    // expected-error @+1 {{operand #0 must be}}
    %s = idr.str.show %x : i1
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// idr.big.cmp has no `ne`, as Idris's Integer primitives have none.
idr.program @ops root(@root) stage(first) {
  idr.func @f(%x: !idr.big) {
    // expected-error @+1 {{'predicate'}}
    %b = idr.big.cmp ne %x, %x
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// put_list writes characters or strings, as pack and concat build them.
!Ints = !idr.data<"Ints", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"Ints">>) cons]>
idr.program @ops root(@root) stage(first) {
  idr.func @f(%xs: !idr.box<!Ints>, %w: !idr.world) -> !idr.world {
    // expected-error @+1 {{writes a list of characters or of strings}}
    %w1 = idr.io.put_list %xs, %w : !idr.box<!Ints>
    return %w1 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A new array takes one size per dimension: an IORef's, of rank 0, none.
idr.program @ops root(@root) stage(first) {
  idr.func @f(%n: i64, %z: i64, %w: !idr.world) -> !idr.world {
    // expected-error @+1 {{takes 1 sizes for an array of rank 0}}
    %r, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<i64, #idr.world>
    return %w1 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An access takes one index per dimension.
idr.program @ops root(@root) stage(first) {
  idr.func @f(%a: memref<?xi64, #idr.world>, %w: !idr.world) -> !idr.world {
    // expected-error @+1 {{takes 0 indices for an array of rank 1}}
    %x, %w1 = idr.array.get %a[], %w : memref<?xi64, #idr.world> -> i64
    return %w1 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An element of an array a world orders is rebuilt in its place by
// idr.array.update: the element moves into the region, which binds no
// world, and the first value it yields moves back in; the values after it
// leave the op, as an exchange gives the old element out. A word holds no
// reference and is rebuilt as well.
!R = !idr.data<"R", plain [@MkR(!idr.str)]>
idr.program @ops root(@root) stage(first) {
  idr.func @bump(%a: memref<?x!idr.box<!R>, #idr.world>, %i: i64, %w: !idr.world) -> !idr.world {
    %w1 = idr.array.update %a[%i], %w {
    ^bb0(%old: !idr.box<!R>):
      %x = idr.field %old : !idr.box<!R> @MkR[0] -> !idr.str
      %y = idr.str.append %x, %x
      %new = idr.con !idr.box<!R> @MkR(%y : !idr.str)
      idr.array.yield %new : !idr.box<!R>
    } : memref<?x!idr.box<!R>, #idr.world>
    return %w1 : !idr.world
  }
  idr.func @swap(%r: memref<i64, #idr.world>, %y: i64, %w: !idr.world) -> (i64, !idr.world) {
    %x, %w1 = idr.array.update %r[], %w {
    ^bb0(%old: i64):
      idr.array.yield %y, %old : i64, i64
    } : memref<i64, #idr.world> -> i64
    return %x, %w1 : i64, !idr.world
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
