// mlir-opt call-cycles.mlir -inline
//
// The inliner builds mlir::CallGraph, whose nodes now carry dense indices
// and whose components it may read once kept: the output is the pin's.
// Its components are {a, b}, {c}, {leaf}, {root} and the external node;
// getSCCs gives each after every component it calls (root after the three,
// the external node last), as a check of the kept components asserts.
func.func private @a(%x: i32) -> i32 {
  %r = func.call @b(%x) : (i32) -> i32
  return %r : i32
}
func.func private @b(%x: i32) -> i32 {
  %c = arith.constant 1 : i32
  %s = arith.subi %x, %c : i32
  %r = func.call @a(%s) : (i32) -> i32
  return %r : i32
}
func.func private @c(%x: i32) -> i32 {
  %r = func.call @c(%x) : (i32) -> i32
  return %r : i32
}
func.func private @leaf(%x: i32) -> i32 {
  return %x : i32
}
func.func @root(%x: i32) -> i32 {
  %p = func.call @a(%x) : (i32) -> i32
  %q = func.call @c(%p) : (i32) -> i32
  %r = func.call @leaf(%q) : (i32) -> i32
  return %r : i32
}
