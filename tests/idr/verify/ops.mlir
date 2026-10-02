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
