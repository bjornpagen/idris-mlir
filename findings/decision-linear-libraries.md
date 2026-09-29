# Decision: linear libraries, the contrib LinArray leak, and the language

The user has agreed to this decision.

- **The Idris 2 language does not change.** We don't touch its type
  checker, its quantities or its syntax, and third_party/Idris2 stays
  unmodified. Every optimization works from what the language already
  proves.
- **The leak is a contrib library bug, not a compiler bug.**
  `Data.Linear.Array.newArray`'s continuation may return the array (or a
  closure over it), because its result type is unconstrained. Under QTT,
  returning a linear variable is a legitimate single use. The fix belongs
  in the library: the continuation returns `!*` (Linear Haskell's rule).
  It is reported in `upstream/idris-linarray-escape`, with a test that
  fails once upstream fixes it (PINS.md `linarray-escape`).
- **No library of our own.** Soundness never rests on a library signature:
  the compiler proves exclusivity itself, with bufferization's in-place
  analysis for arrays and the exclusivity analysis for cells. A program
  that uses contrib's API correctly optimizes fully. A program that uses
  the leak gets a copy, or is rejected with `unsupported (uniqueness)`,
  never miscompiled.
- **What is needed instead.** Each array primitive (`prim__newArray`,
  `prim__arrayGet`, `prim__arraySet`, and the Buffer ones) gets its one
  meaning in the registry, as array ops on the tensor → bufferization →
  memref path. Then contrib's `LinArray` and `Data.IOArray` compile as
  they are. Package-keyed trust (findings/linear-libs.md R2) and the `-@`
  constructor fix (R1) are prerequisites.
- **Revisit** only if upstream does not fix the signature and users need
  the escape rejected by Idris's own type checker. Then a small in-repo
  module with the `!*` signature is cheap, and it changes no language.
