// Two callers that differ only in which of two equal callees they call.
// With the hook, partition refinement finds @leaf_a and @leaf_b one class,
// then @call_a and @call_b one class, since their calls name one class;
// without it, @call_a and @call_b differ by their callee's symbol. The
// compiler's deduplication shows it (L18); upstream, the patch's unit test.
func.func private @leaf_a(%x: i32) -> i32 {
  return %x : i32
}
func.func private @leaf_b(%x: i32) -> i32 {
  return %x : i32
}
func.func private @call_a(%x: i32) -> i32 {
  %r = func.call @leaf_a(%x) : (i32) -> i32
  return %r : i32
}
func.func private @call_b(%x: i32) -> i32 {
  %r = func.call @leaf_b(%x) : (i32) -> i32
  return %r : i32
}
