# Decision: threads and raw pointers are outside the language

The user decided this on 2026-10-06. The compiler implements a subset of
Idris 2 where the subset is what makes the heap and the analyses exact.
Threads and raw pointers are not in that subset.

- **Threads.** `fork`, `threadWait` and the primitives they call
  (`prim__fork`, `prim__threadWait`) start another schedule of effects and
  share mutable state between them. The heap is a dag of immutable values
  plus mutable cells that one world orders. A second thread is a second
  world writing the same cells, which counting cannot see and which the
  world's order does not sequence. There is no scheduler, no thread-safe
  runtime and no shared-memory model to add one later without replacing
  that heap. A program that forks is rejected with `unsupported
  (threads)`, naming the definition.
- **Collector finalizers.** `onCollect` and `onCollectAny` register a
  computation to run when the collector frees a pointer. Release here is
  the counting walk, which runs while the releasing thread still holds the
  world, and which does not call back into the program. A finalizer would
  be an effect at a time the world does not name. They are rejected with
  `unsupported (finalizer)`.
- **Raw pointers.** `prim__castPtr`, `prim__forgetPtr`, `prim__nullPtr`,
  `prim__nullAnyPtr`, `prim__getNullAnyPtr` and `prim__getString` are
  addresses the runtime does not account for: untyped, nullable, free to
  alias any heap value. `System.getEnv` is the same, because it returns
  the environment through `prim__getString` of a pointer. References this
  compiler keeps are heap values it allocated and counts. A raw pointer
  has no count, so exclusivity and the acyclic-heap check would be guesses.
  They are rejected with `unsupported (raw pointer)`. `AnyPtr` stays, as
  the type of the three standard-stream handles, which are the runtime's
  own small integers, not addresses.
- **`unsafePerformIO` stays an escape hatch.** A trusted library may run
  an IO action for a pure value; the effects happen where the value is
  demanded, in order with every other effect. User code may not write it.
  That is the existing refusal (`unsupported (world)`), unchanged.
- **Being a subset is the point.** The same rule as the acyclic heap: the
  programs given up are the ones whose meaning needs a collector, a
  scheduler or an untracked address, and they are told why. A new prelude
  export the compiler cannot handle is still a gap in the coverage check;
  these names are the decided exclusions, not a gap.
