# Decision: prelude and base are the library; linear code comes from `libs/`

The user decided this on 2026-10-01 ("we must implement idris 2 fully,
upstream prelude and base only. all these other packages, especially for
linear, we may just want to have our better in-house implementation").

- **Which libraries the compiler implements.** Idris 2 the language, in
  full, for programs over the upstream prelude and base. The add-on
  packages shipped with Idris (`contrib`, `linear`, `network`, `test`) are
  no commitment: upstream's own documentation says contrib "will
  eventually be disbanded in favour of third-party packages". Where a
  program needs linear data or arrays, the compiler ships its own package,
  `libs/mlir-linear`, designed for its analyses: `Linear.Array` (a mutable
  array threaded at quantity 1, filled at creation so a read gives the
  element and not a `Maybe`, an index out of bounds a crash as for base's
  primitive underneath) and `Linear.Notation` (`-@`, `!*`). It is plain
  Idris over base's `Data.IOArray.Prims` and `unsafePerformIO`, which the
  stock Chez backend then ran as the oracle; since `decision-no-oracle.md`
  nothing requires that. This supersedes
  `decision-linear-libraries.md`'s "no library of our own"; that
  decision's other points stand (no language change, soundness never
  rests on a library signature).
- **Linear arrays are `memref`, not tensors.** A linear array has
  reference semantics on every backend: one mutable object behind a linear
  API. The faithful representation of a mutable object is `memref`, where
  a write is in place by construction and a copy never happens, so there is
  no in-place decision for One-Shot Bufferize to make and nothing to
  reject; a program that shares the array (bound unrestricted) sees the
  one object, as Chez does, never a miscompile. The tensor → One-Shot path
  of mutable-buffers.md §5 and §9 (W1/W2) is for value-semantic data,
  `Vect` as a value (representation.md R12), when that lands. What the
  types keep is quantity 1 on the handle, which the verifier checks after
  every pass; what the compiler proves is exclusivity (`!idr.q<one, excl,
  ...>` on every array thread of the fixtures), and the properties the
  fixtures state are `counts-nothing` and `no-heap-allocation` on the
  loops.
- **How the library's effects reach the IR.** `unsafePerformIO` in a
  trusted library forges a world (`idr.world.new`, `Idr_PerformsIO`, a
  write of the IO resource): the chain on it is ordered by the world as
  every IO chain is, two chains by their effects, as any two IO ops are;
  CSE never merges two forged worlds, nothing hoists or deletes one, and a
  function that reaches one performs IO, which keeps compile-time
  evaluation off it. User code's `%MkWorld` stays `unsupported (world)`.
- **Measured (2026-10-01, this container, `make bench --runs 3`, one
  run):** fannkuch-redux over `Linear.Array` at n = 10 runs 0.216 s
  against 0.621 s for the `IOArray` version and 0.508 s for C;
  spectral-norm over `Array Double` at n = 1000 runs 0.054 s, as C does
  (0.054 s), same digits; qsort (Beans) 1.307 s against C's 1.301 s;
  unionfind (Beans) 0.204 s against C's 0.146 s. Every loop of the six
  fixtures changes no count and allocates nothing.
- **Next:** the fixtures that use upstream's `linear` (`Data.Linear.LList`,
  `Data.Linear.Notation`) move onto `libs/mlir-linear` (task #103), and the
  `linear` row leaves the trust table; `Fin`-indexed and length-indexed
  arrays wait for `Fin n` as a ranged word (representation.md R5).
