# Frontend adapter

This is the only project component importing Idris compiler implementation
modules. Build it using the matching compiler/API under `.toolchain/idris2`.

The initial `core-inspect` backend implements the documented `Codegen` interface.
Its incremental callback writes a `.ttsummary` file beside each newly compiled
module's TTC file. The driver calls it after successful module processing and
before serialization. It reads retained TT through `Defs`; it never calls
`getCompileData` or `getIncCompileData`.

Inspection version 1 records names, definition kinds, signature availability,
pi-binder quantities (`Rig0`, `Rig1`, `RigW`), and checked-clause counts. Rows
are sorted. It does not serialize bodies, types, index relationships, or a
runtime ABI. Missing signatures are reported as unavailable, not inferred.

Start with `tests/frontend/fixtures/Vectors.idr`, using `--no-prelude` and
`--inc core-inspect --check`. The frontend integration test supplies these flags
and uses disposable working directories. Generated files do not enter Git.

An unchanged module may skip the callback. Imports without this backend's
incremental data can disable its incremental mode. Extending the tests to
cross-module cached inspection and explicit sidecar invalidation is the next
milestone. Do not silently import an ordinary prebuilt Prelude and assume the
incremental callback ran.
