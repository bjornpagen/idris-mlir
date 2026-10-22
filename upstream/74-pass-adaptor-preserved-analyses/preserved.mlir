// mlir-opt preserved.mlir -mlir-disable-threading \
//   -pass-pipeline='builtin.module(inline,func.func(cse),inline)' \
//   -mlir-timing -mlir-timing-display=tree
//
// Nothing here is common to CSE, so CSE changes nothing and preserves every
// analysis on each function. At the pin the func.func adaptor preserves
// none, so the module's CallGraph is invalidated and the second Inliner's
// row holds an "(A) CallGraph" child; with the patch the adaptor preserves
// what every nested run preserved, and only the first Inliner computes it.
func.func private @f(%x: i32) -> i32 {
  return %x : i32
}
func.func @g(%x: i32) -> i32 {
  %r = func.call @f(%x) : (i32) -> i32
  return %r : i32
}
