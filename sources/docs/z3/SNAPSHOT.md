# Snapshot: z3 licence and build notes

- **Upstream:** `Z3Prover/z3` on GitHub.
- **Revision:** `2d08bfcad30cabb7b2819dd2f4c47b7bbf4c377f`, the HEAD resolved with `git ls-remote https://github.com/Z3Prover/z3 HEAD` on 2026-10-09.
- **Fetched:** 2026-10-09, from `https://raw.githubusercontent.com/Z3Prover/z3/2d08bfcad30cabb7b2819dd2f4c47b7bbf4c377f/<path>`.
- **Paths:** relative to the repository root.
- **Licence:** MIT (`LICENSE.txt`, © Microsoft Corporation).
- **Threads:** decision-procedures (Fast dependent type checking and elaboration).

**What is here and why.** The licence and the CMake build guide, for the static-build question. `README-CMake.md` documents `BUILD_SHARED_LIBS` (default `ON`; `OFF` builds the static library; `Z3_BUILD_LIBZ3_SHARED` is kept only for compatibility), installing static and shared variants side by side, position-independent code for both variants, `Z3_USE_LIB_GMP` (default `OFF`: Z3 uses its own multiprecision arithmetic, so a static build needs no GMP), `Z3_SINGLE_THREADED`, and that all language bindings require the shared `libz3` (lines 110–260).

**Not taken:** the rest of the repository (sources, `README.md`, which was fetched for reading, and the Python build system). Nothing was built or run.

## File manifest

2 files, 10,810 bytes in all. Computed 2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                                bytes  path
e617cad2ab9347e3129c2b171e87909332174e17961c5c3412d0799469111337        1096  LICENSE.txt
c3d18fd4539239f310918eb61ffe5e00b15de92638a0f1460d0d552ebef207b0        9714  README-CMake.md
```
