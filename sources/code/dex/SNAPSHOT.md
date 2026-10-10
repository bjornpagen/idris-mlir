# Snapshot: Dex compiler excerpts

- **Upstream:** `google-research/dex-lang` on GitHub.
- **Revision:** `main` at `25e2e389b90403ae2f8d67fb6d52f47d23c439ee` (the pin this library
  records for dex-lang, sources/README.md, Pins; `git ls-remote` on 2026-10-09 returned the same
  commit).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/google-research/dex-lang/25e2e389b90403ae2f8d67fb6d52f47d23c439ee/<path>`;
  the file list was chosen from
  `https://api.github.com/repos/google-research/dex-lang/git/trees/25e2e389b90403ae2f8d67fb6d52f47d23c439ee?recursive=1`.
- **Paths:** relative to the repository root (so `src/lib/Lower.hs`).
- **Files:** 13 (plus this file).
- **Licence:** BSD-3-Clause (`LICENSE`, "Copyright 2019 Google LLC"; each source file points to it).
- **Topic:** Array languages and typed array programming.
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `LICENSE`, `README.md` | licence and project summary |
| `lib/prelude.dx` | the `Ix` index-set interface (`size'`, `ordinal`, `unsafe_from_ordinal`), `Fin`, the range index sets (`RangeFrom`, `RangeTo`, ...) and the tuple instances that make `(n & m)=>a` a flattened table |
| `src/lib/Types/Core.hs` | the core IR: `TabPiType` (dependent table types with an `IxDict`), `IxType`, the `For` and `Seq` higher-order primitives |
| `src/lib/Simplify.hs` | simplification to first-order code (the paper's Section 4), with tables of functions turned into tables of data |
| `src/lib/Linearize.hs`, `src/lib/Transpose.hs` | linearization and transposition (forward mode, then reverse by transposition, with `Accum` for cotangents) |
| `src/lib/Lower.hs` | `lowerFullySequential`: `for` becomes `seq`, arrays become destinations, destination-passing to elide copies |
| `src/lib/Vectorize.hs` | loop vectorization over the destination-style IR |
| `src/lib/Imp.hs`, `src/lib/Types/Imp.hs` | lowering to the imperative IR that `ImpToLLVM` compiles |
| `src/old/MLIR/Lower.hs` | an abandoned MLIR backend (scalar ops only, through `std`/`llvm`; arrays, `case` and higher-order ops raise "not supported") |
| `src/old/Parallelize.hs` | the older parallelism-extraction (flattening of nested `for`) pass |

Not taken: `ImpToLLVM.hs` (59 KB), `Inference.hs` (108 KB), `Name.hs` (129 KB), the runtime
(`dexrt.cpp`, `work-stealing.c`), the JAX bridge.

**How to fetch more.**

```bash
rev=25e2e389b90403ae2f8d67fb6d52f47d23c439ee
p=src/lib/ImpToLLVM.hs
mkdir -p "code/dex/$(dirname $p)"
curl -sL --fail -o "code/dex/$p" "https://raw.githubusercontent.com/google-research/dex-lang/$rev/$p"
```

## File manifest

Every stored file except this one: 13 files, 416,887 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
ccb6e433d42937be62bc7e8a7e7c636d8e74dd64870375ef0895f978feff6aa6       1448  LICENSE
eabcb9f66f7a0b7d5dcc522d9467ef05186db7e1e9d9487d88c24b0e679fb800       5480  README.md
6f1c94e06b4cff8e2a5a989e4373cc87f7c6fcc667953ca17885d652af3dbd50      78889  lib/prelude.dx
fed4eb75f98029234a55351ea28296e0d7c172c03050b69231029b3fb128aa61      65928  src/lib/Imp.hs
c0feebfe33131d15d36d7d2ba4878ac6427e808489535e00d401f281b615f62f      29196  src/lib/Linearize.hs
c7bfbf0379086cb4d7fb7d2fe9afc66ef08dda1fec9ef220a9fdb1f244ac6b99      13109  src/lib/Lower.hs
d6bcb3769cb0de970a2db2088cbb442975e8c869d93051e26ec412b3a940bd9a      48603  src/lib/Simplify.hs
131a66d59ba4aca666a61a4cc5cebdf90b070621b1375707793ed9fefe2ae9c9      12495  src/lib/Transpose.hs
e5dca872c37922742de18fc374adf5bc31676a96dc49947a87e143340c1fc5c7      89577  src/lib/Types/Core.hs
f1ef883da8de10c639cefa265e724e03737a0d5177816e4c392e8ae119d9c183      21200  src/lib/Types/Imp.hs
f6faafcb93f16f49b69bfd7f3df22ff9ae4f38d879e443d992794a2839fcb6a8      26734  src/lib/Vectorize.hs
4e11d288f8f6863d32b3ca154cf21f3361d60707c7c122cb0b154127912afdc0      13173  src/old/MLIR/Lower.hs
bd735fb8923a9dc2393738a01056faca5171b9ce00a45896767738976c54f9fd      11055  src/old/Parallelize.hs
```
