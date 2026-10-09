// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

func.func @f(%d: f64) {
  // expected-error @+1 {{shows a Double, which has no signedness}}
  %s = idr.str.show signed %d : f64
  return
}

// -----

func.func @f(%x: i1) {
  // expected-error @+1 {{operand #0 must be}}
  %s = idr.str.show %x : i1
  return
}

// -----

// idr.big.cmp has no `ne`, as Idris's Integer primitives have none.
func.func @f(%x: !idr.big) {
  // expected-error @+1 {{'predicate'}}
  %b = idr.big.cmp ne %x, %x
  return
}

// -----

// put_list writes characters or strings, as pack and concat build them.
idr.data @Ints box {
  idr.ctor @Nil ()
  idr.ctor @Cons (i64, !idr.box<@Ints>)
}
func.func @f(%xs: !idr.box<@Ints>, %w: !idr.world) -> !idr.world {
  // expected-error @+1 {{writes a list of characters or of strings}}
  %w1 = idr.io.put_list %xs, %w : !idr.box<@Ints>
  return %w1 : !idr.world
}

// -----

// A new array takes one size per dimension: an IORef's, of rank 0, none.
func.func @f(%n: i64, %z: i64, %w: !idr.world) -> !idr.world {
  // expected-error @+1 {{takes 1 sizes for an array of rank 0}}
  %r, %w1 = idr.array.new [%n], %z, %w : i64 -> memref<i64>
  return %w1 : !idr.world
}

// -----

// An access takes one index per dimension.
func.func @f(%a: memref<?xi64>, %w: !idr.world) -> !idr.world {
  // expected-error @+1 {{takes 0 indices for an array of rank 1}}
  %x, %w1 = idr.array.get %a[], %w : memref<?xi64> -> i64
  return %w1 : !idr.world
}

// -----

// A word holds no reference, so there is nothing to move out.
func.func @f(%r: memref<i64>, %w: !idr.world) -> !idr.world {
  // expected-error @+1 {{moves out an element that holds no reference}}
  %x, %w1 = idr.array.get %r[], %w moves : memref<i64> -> i64
  %w2 = idr.array.set %r[], %x, %w1 : memref<i64>, i64
  return %w2 : !idr.world
}

// -----

// The next IO after a read that moves its element out writes that element:
// output between would come before the place is filled again.
func.func @f(%r: memref<!idr.str>, %s: !idr.str, %w: !idr.world) -> !idr.world {
  // expected-error @+1 {{moves its element out, but its world does not go next to a write of that element in its block}}
  %x, %w1 = idr.array.get %r[], %w moves : memref<!idr.str> -> !idr.str
  %w2 = idr.io.put_str %s, %w1
  %w3 = idr.array.set %r[], %x, %w2 : memref<!idr.str>, !idr.str
  return %w3 : !idr.world
}

// -----

// The write that follows writes another element, and the one moved out
// would stay empty.
func.func @f(%a: memref<?x!idr.str>, %i: i64, %j: i64, %s: !idr.str, %w: !idr.world) -> !idr.world {
  // expected-error @+1 {{moves its element out, but its world does not go next to a write of that element in its block}}
  %x, %w1 = idr.array.get %a[%i], %w moves : memref<?x!idr.str> -> !idr.str
  %w2 = idr.array.set %a[%j], %s, %w1 : memref<?x!idr.str>, !idr.str
  return %w2 : !idr.world
}

// -----

// A world that goes nowhere fills nothing again.
func.func @f(%r: memref<!idr.str>, %w: !idr.world) -> !idr.str {
  // expected-error @+1 {{moves its element out, but its world does not go next to a write of that element in its block}}
  %x, %w1 = idr.array.get %r[], %w moves : memref<!idr.str> -> !idr.str
  return %x : !idr.str
}
