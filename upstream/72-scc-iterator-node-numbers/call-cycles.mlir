// mlir-opt call-cycles.mlir -inline
//
// The inliner walks the call graph's components with scc_iterator, which
// keeps its visit numbers by node number once the graph numbers its nodes
// (73). Two cycles and a chain into them: the output is the pin's, the
// components and their order unchanged.
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
