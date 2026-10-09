# Decision: threads, raw pointers and foreign calls are outside the language

The user decided threads and raw pointers on 2026-10-06, and `%foreign`
and the C ABI on 2026-10-07. The compiler implements a subset of Idris 2
where the subset is what makes the heap and the analyses exact. Threads,
raw pointers and a foreign calling convention are not in that subset.

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
- **Raw pointers.** An address the runtime does not account for is
  untyped, nullable and free to alias any heap value. References this
  compiler keeps are heap values it allocated and counts. A raw pointer
  has no count, so exclusivity and the acyclic-heap check would be guesses.
  So no address reaches a program: raw memory, `System.FFI`'s
  `prim__malloc` and `malloc`, is rejected with `unsupported (raw
  pointer)`, which names nothing else.
- **Base's pointers are runtime handles** (proposal 0002, owner decision
  O1). With `%foreign` outside user code, every `Ptr t` or `AnyPtr` a
  program holds comes from a primitive the compiler recognizes, so it is a
  handle, never an address: an `i64` slot of the runtime's handle table,
  which holds an open file, an open directory, a file's times or a string.
  `0`, `1` and `2` are the standard streams, as before, and `-1` is null,
  since `0` is standard input. Base's pointer operations are handle
  operations: `prim__castPtr` and `prim__forgetPtr` are the identity,
  `prim__getNullAnyPtr` is the null handle, `prim__nullAnyPtr` and
  `prim__nullPtr` test for it, `prim__getString` reads a string handle's
  string with a reference of its own, and `System.FFI`'s `prim__free`
  frees a handle. So `getEnv`, `currentDir`, `nextDirEntry`, `fGetLine`
  and `fGetChars` compile as base writes them.
- **`%foreign` and the C ABI.** A `%foreign` spec names another language's
  calling convention and a symbol in it. `%extern` as a C export, a C
  calling convention, libffi, and a C symbol declared or called from user
  code are that ABI. The runtime calls the operating system behind its
  platform layer. A program does not, and there is no libffi and no C
  calling convention to add. A program that asks for one is rejected with
  `unsupported`, and the message names `%foreign` or the extern. Dropping
  the pragma would compile a call the compiler has no meaning for.
  A buffer operation is a runtime primitive, with one meaning in the
  runtime, as every primitive has. The scheme spec upstream writes on one
  names that primitive. It is not a C ABI, and it is not this exclusion.
- **`unsafePerformIO` stays an escape hatch.** A trusted library may run
  an IO action for a pure value; the effects happen where the value is
  demanded, in order with every other effect. User code may not write it.
  That is the existing refusal (`unsupported (world)`), unchanged.
- **Being a subset is the point.** The same rule as the acyclic heap: the
  programs given up are the ones whose meaning needs a collector, a
  scheduler, an untracked address or a foreign symbol, and they are told
  why. A new prelude export the compiler cannot handle is still a gap in
  the coverage check; these names, and `%foreign` and the C ABI, are the
  decided exclusions, not a gap.
