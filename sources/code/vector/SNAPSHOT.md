# Snapshot: Haskell `vector`, Data.Vector.Unboxed

- **Upstream:** `haskell/vector` on GitHub (the package `vector` lives in its `vector/`
  subdirectory).
- **Revision:** tag `vector-0.13.2.0`, commit `d9d0d46623fdecce7652f59caa4a28849292a0e7` (a
  lightweight tag; `master` was at `d0f42e056202fa24b479833dbc21222c1964d096` on 2026-10-09).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/haskell/vector/d9d0d46623fdecce7652f59caa4a28849292a0e7/<path>`;
  the file list was chosen from the tree at that commit.
- **Paths:** relative to the repository root (so `vector/src/Data/Vector/Unboxed/Base.hs`).
- **Files:** 8 (plus this file).
- **Licence:** BSD-3-Clause (`vector/LICENSE`, "Copyright (c) 2008-2012, Roman Leshchinskiy",
  2020-2022 Kuleshevich, Khudyakov, Lelechenko).
- **Topic:** Flattened data: packed, columnar and nested layouts.
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `vector/src/Data/Vector/Unboxed/Base.hs` | the data families `Vector a` and `MVector s a`, the class `Unbox`, and its instances: `()` as a length only, primitives over `Data.Vector.Primitive`, `Bool` as a byte array, `Complex a` and `Arg a b` as vectors of pairs, the deriving helpers `UnboxViaPrim`, `As`/`IsoUnbox` (a product type through a tuple representation, defaulted by `GHC.Generics`) and `DoNotUnboxLazy`/`Strict`/`NormalForm` (a field kept as a boxed vector) |
| `vector/internal/unbox-tuple-instances` | the generated instances for tuples of 2 to 6: `data instance Vector (a, b) = V_2 !Int !(Vector a) !(Vector b)`, each method distributed over the components; O(1) `zip`/`unzip` |
| `vector/internal/GenUnboxTuple.hs` | the generator of that file |
| `vector/src/Data/Vector/Unboxed.hs` | the user-facing module and its documentation of how a new instance is defined |
| `vector/src/Data/Vector/Generic/Base.hs`, `vector/src/Data/Vector/Generic/Mutable/Base.hs` | the method sets (`basicLength`, `basicUnsafeSlice`, `basicUnsafeRead`/`Write`, `basicUnsafeIndexM`, `basicUnsafeFreeze`, ...) an `Unbox` instance must provide |
| `vector/LICENSE`, `vector/README.md` | licence, summary |

Not taken: `Data/Vector/Unboxed/Mutable.hs`, `Data/Vector/Primitive*.hs`, the fusion framework
(`Data/Vector/Fusion/**`), `Data/Vector/Generic.hs` (93 KB), tests and benchmarks.

## File manifest

Every stored file except this one: 8 files, 179,013 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
a2bb7af96394e2cf79f5ceb0b7c85b088219814339fd0edb61d4fafb6dfd1c71       1676  vector/LICENSE
1ced56c128f5d2abdba42270ceec17364c5f941869995f607c4304e6872dc6a8       3405  vector/README.md
e80e5cf99ce0048f82dcf3ecf78d3dec65288a904d8950e7e144817c44d0ebfb       9218  vector/internal/GenUnboxTuple.hs
88fd46952b91682cc940b6e7ff60c8d69d7056984e320461c2f15ec39c07e56a      41896  vector/internal/unbox-tuple-instances
5aa5fe253bd503c22d989f6c0a9c79af1880c7b52e15a67f2384b31c7cab5903       5307  vector/src/Data/Vector/Generic/Base.hs
95db546776f6c6c4e71f35354284cb682d7728f4abc2a493c23e7eecfbe9f2d8       5440  vector/src/Data/Vector/Generic/Mutable/Base.hs
1af9cbfc0e47a5c338cbd09ed80fc51a5967345379fb629caed060e60901b657      66752  vector/src/Data/Vector/Unboxed.hs
6d2698c93adcab2fdcb01c325081242423ea93ed8d1c89467d8edfae83fbb2ae      45319  vector/src/Data/Vector/Unboxed/Base.hs
```
