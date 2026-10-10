# Snapshot: Data Parallel Haskell libraries (excerpts)

- **Upstream:** `ghc/packages-dph` on GitHub ("Mirror of packages-dph repository"), the DPH
  libraries that GHC's vectoriser targeted.
- **Revision:** `master` at `64eca669f13f4d216af9024474a3fc73ce101793` (2016-07-05, "Prepare dph for
  a vectInfoVar type change"), the last commit; GHC removed the vectoriser in 2018 (see
  [`code/ghc-vectoriser/SNAPSHOT.md`](../ghc-vectoriser/SNAPSHOT.md)).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/ghc/packages-dph/64eca669f13f4d216af9024474a3fc73ce101793/<path>`;
  the file list was chosen from `https://api.github.com/repos/ghc/packages-dph/git/trees/64eca669f13f4d216af9024474a3fc73ce101793?recursive=1`.
- **Paths:** relative to the repository root (so `dph-prim-seq/Data/Array/Parallel/Unlifted/Sequential/UVSegd.hs`).
- **Files:** 20 (plus this file).
- **Licence:** BSD-3-Clause style (`LICENSE`: "Copyright (c) 2001-2012, The DPH Team": Chakravarty,
  Keller, Leshchinskiy, Lippmeier, Roldugin). GitHub reports the licence as "Other" (verify).
- **Topic:** Flattened data: packed, columnar and nested layouts (cluster `flattening`).
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `LICENSE`, `README` | licence; the package map, including the README's verdict that `dph-lifted-copy` "can cause the vectorised program to have worse asymptotic complexity" and `dph-lifted-vseg` "directly encodes sharing between array segments" |
| `dph-prim-seq/.../Sequential/USegd.hs` | the plain segment descriptor (lengths, indices, element count) |
| `dph-prim-seq/.../Sequential/USSegd.hs` | the scattered segment descriptor (sources, starts over several data blocks) |
| `dph-prim-seq/.../Sequential/UVSegd.hs` | the virtual segment descriptor (vsegids mapping virtual to physical segments, with lazy "redundant" and "culled" forms and a manifest flag) |
| `dph-prim-seq/.../Sequential/USel.hs` | the two-way selector (tags, indices, element counts) used for sums and conditionals |
| `dph-prim-seq/.../Unlifted/Vectors.hs` | `Vectors`, "irregular two dimensional arrays" of primitive elements: the data blocks behind scattered segments |
| `dph-prim-interface/Data/Array/Parallel/Unlifted.hs` | the flat, unlifted array API the lifted layer is built on |
| `dph-lifted-vseg/.../PArray/PData/Base.hs` | the `PR` class: the primitive operations every representation implements |
| `dph-lifted-vseg/.../PArray/PData/Nested.hs` | nested arrays: `PNested` with a `VSegd`, data blocks, and lazy pre-demoted `Segd` and pre-concatenated data |
| `dph-lifted-vseg/.../PArray/PData/Sum2.hs`, `Tuple2.hs` | sums as a selector plus one array per alternative; tuples as tuples of arrays |
| `dph-lifted-vseg/.../PArray/PRepr/Base.hs`, `Instances.hs` | `PRepr`/`PA`: conversion between user types and the generic sum-of-products representation |
| `dph-lifted-vseg/.../Lifted/Closure.hs`, `Combinators.hs` | closures (`:->`) and array closures, and the lifted combinators the vectoriser calls |
| `dph-lifted-vseg/examples/treeLookup/TreeLookupVectorised.hs`, `examples/smvm/SMVMVectorised.hs` | the two programs that exposed the replicate blow-up |
| `dph-lifted-copy/.../PArray/PData.hs` | the deprecated copying representation, for comparison |
| `dph-examples/examples/real/NBody/Solver/NestedBH/Solver.hs` | Barnes-Hut with a nested tree, the running example of the papers |

**Not taken.** `dph-prim-par/` (the gang-parallel implementation, including `UPVSegd.hs` and the
distributed `Dist` types), `dph-lifted-boxed/`, `dph-lifted-base/`, the `Tuple3`–`Tuple7`, `Int`,
`Double`, `Word8`, `Unit`, `Void` and `Wrap` instances, the stream-fusion modules
(`dph-prim-seq/.../Stream/*`), `dph-test/`, `dph-buildbot/` and the remaining examples. Fetch any of
them from the raw URL pattern above at the same revision.

## File manifest

Every stored file except this one: 20 files, 192,683 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                                bytes  path
fd83274ffc89a2cd77cf9fbc2e28a9e292e8bd9b69badd073ce6fabab4603e82       1638  LICENSE
20faf8adf2efdbcf74a8c70b370a2bde846e9d55f2be9d29b24ae8997ef8f0af       3447  README
90ab4625ad7be601d08a97d2f683abc8711bca292ed7703b67b9866341da1159       5713  dph-examples/examples/real/NBody/Solver/NestedBH/Solver.hs
36eb84c12cc82e8dc60d39260a262cc95d8195dad52516154f5f22c6f8141afd       6050  dph-lifted-copy/Data/Array/Parallel/PArray/PData.hs
529190b4b2ce116c739d83cfb20995a31d7eae98eebf6d2e8a0330cc95afef32      22151  dph-lifted-vseg/Data/Array/Parallel/Lifted/Closure.hs
9105100b73e449284215e014900b21a9ea4f35552796e62b82fccfed9691b9da       7613  dph-lifted-vseg/Data/Array/Parallel/Lifted/Combinators.hs
77b6ad264b77f470b895581a369c44a6f6cf80949a9a2a12f72aff3384949f45      10584  dph-lifted-vseg/Data/Array/Parallel/PArray/PData/Base.hs
751c53c6a32cf11d8a0dcc58949fe612f445c3816c47b7a5778979478d9e8b33      30192  dph-lifted-vseg/Data/Array/Parallel/PArray/PData/Nested.hs
dea201dd9b6165e62dc8e8b5d90d23c4c5d79578af2d978e7905de8ebafe3173      18899  dph-lifted-vseg/Data/Array/Parallel/PArray/PData/Sum2.hs
ba038af07fb906885fe379153d02099c3fc98f926747a21a031e3df64a19d036       7913  dph-lifted-vseg/Data/Array/Parallel/PArray/PData/Tuple2.hs
25d2fec45aed6b6b39bf816ce8c1b04d364a20220281887d67f38b92de8e227b       8746  dph-lifted-vseg/Data/Array/Parallel/PArray/PRepr/Base.hs
a11377b3c276126b50089406cbcebc399496f879e0438ffd2363dfbfb078a0af       5488  dph-lifted-vseg/Data/Array/Parallel/PArray/PRepr/Instances.hs
00454bbdd6af5f1acab3a1480065e36b8b8ea687dd13b827a6cbca4d7600d886       1742  dph-lifted-vseg/examples/smvm/SMVMVectorised.hs
36ebbff17d908f0ea650442b688ae1589790c1e717aeb52ca934deac2c353aab       3287  dph-lifted-vseg/examples/treeLookup/TreeLookupVectorised.hs
f85988a94fc9b40ebc3f7c70f8837044763078744776a7541285cfe13d33e54f      10836  dph-prim-interface/Data/Array/Parallel/Unlifted.hs
8144a01537c2cb6097ffc18459153ef27576ba2bb76a8310641d603ff4716374      10563  dph-prim-seq/Data/Array/Parallel/Unlifted/Sequential/USSegd.hs
864641bc7b9c69584345b70979424028881ad77e665584f1e470d7ad071bf8af       5915  dph-prim-seq/Data/Array/Parallel/Unlifted/Sequential/USegd.hs
505857078ab70feab16b5e7f34704b629e7d814693642d5d3aa741797220fa58       3266  dph-prim-seq/Data/Array/Parallel/Unlifted/Sequential/USel.hs
0ba89e0b2e457e16a0c979cc46c1eeade93d4341557fc68b2b667297cc4f1735      19956  dph-prim-seq/Data/Array/Parallel/Unlifted/Sequential/UVSegd.hs
28dfb80c9e68cb35f1fd9a5aa4f36bd9acc26f8b0ca8a0a485cbbbba3e0e6b54       8684  dph-prim-seq/Data/Array/Parallel/Unlifted/Vectors.hs
```
