# Snapshot: Futhark compiler excerpts

- **Upstream:** `diku-dk/futhark` on GitHub.
- **Revision:** `master` at `304c56ff73c48f1842ed3971fe19805a3a85c766`, the pin this library
  already records for Futhark (sources/README.md, Pins, resolved 2026-09-26). On 2026-10-09
  `master` had moved to `e641ce0c7e41c1edf285b06cc833179bc6a30690`; the recorded pin was kept so
  the library has one Futhark revision.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/diku-dk/futhark/304c56ff73c48f1842ed3971fe19805a3a85c766/<path>`;
  the file list was chosen from the tree at that commit
  (`https://api.github.com/repos/diku-dk/futhark/git/trees/304c56ff73c48f1842ed3971fe19805a3a85c766?recursive=1`).
- **Paths:** relative to the repository root (so `src/Futhark/Optimise/Fusion.hs`).
- **Files:** 20 (plus this file).
- **Licence:** ISC (`LICENSE`, "Copyright (c) 2013-2022. DIKU, University of Copenhagen").
- **Topic:** Array languages and typed array programming (data-parallel functional array compilers).
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `LICENSE`, `README.md` | licence and project summary |
| `src/Futhark/Passes.hs` | the pass pipelines (`standardPipeline`, `gpuPipeline`, `seqmemPipeline`, `gpumemPipeline`, `mcPipeline`): where fusion, flattening and the memory passes sit |
| `src/Futhark/IR/SOACS/SOAC.hs` | the SOAC IR: `Screma` (scan/reduce/map fused form), `Hist`, `Stream`, and the new nonuniform `FlatMap` |
| `src/Futhark/IR/SegOp.hs` | the flattened target: `SegMap`/`SegRed`/`SegScan`/`SegHist` with a level and a `SegSpace` |
| `src/Futhark/Optimise/Fusion.hs`, `Fusion/GraphRep.hs`, `Fusion/TryFusion.hs`, `Fusion/Composing.hs`, `Fusion/Screma.hs` | graph-based vertical and horizontal fusion (descendant of the T2 paper) |
| `src/Futhark/Pass/Flatten.hs`, `Flatten/Incremental.hs`, `Flatten/Distribute.hs` | flattening with uniform/nonuniform distinction, incremental (multi-versioned) flattening, map distribution |
| `src/Language/Futhark/TypeChecker/Consumption.hs` | source-level uniqueness/alias (consumption) checking |
| `src/Futhark/IR/TypeCheck.hs` | core-IR type checker, which re-checks consumption (occurrence traces) on the IR |
| `src/Futhark/Optimise/ArrayShortCircuiting.hs` | memory-level short-circuiting (the successor of in-place lowering; Munksgaard et al. SC 2022) |
| `src/Language/Futhark/TypeChecker/Terms/Unsized.hs`, `TySolve.hs`, `Unify.hs` | type inference with size variables (constraint generation, solving, unification of sizes) |
| `src/Futhark/Internalise/AccurateSizes.hs` | size handling when internalising source to core IR |

Not taken (fetch more from the same base if needed): `Pass/Flatten/{SOAC,BasicOp,Loop,Match,Intrablock,WithAcc,...}.hs`,
`Optimise/ArrayShortCircuiting/ArrayCoalescing.hs` (83 KB, the analysis proper),
`Language/Futhark/TypeChecker/Terms.hs` (91 KB), the AD pass, and the code generators
(`CodeGen/ImpGen/GPU/*`).

**How to fetch more.**

```bash
rev=304c56ff73c48f1842ed3971fe19805a3a85c766
p=src/Futhark/Pass/Flatten/SOAC.hs
mkdir -p "code/futhark/$(dirname $p)"
curl -sL --fail -o "code/futhark/$p" "https://raw.githubusercontent.com/diku-dk/futhark/$rev/$p"
```

## File manifest

Every stored file except this one: 20 files, 500,810 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
d029ffa271dcee84cc883fb9e83744f703401e2abb097b8ef084fff0674d935b        767  LICENSE
2dd231f2a53a43012a006d23781a2acad877b851997e304333a2d97b1188307d       1861  README.md
8083cb8f870eb4c56587108fc11dc2d78f928bf2c502305c2cc6ae8c5db79918      42595  src/Futhark/IR/SOACS/SOAC.hs
765fe4eb910f36711ce8f86bdcc0cff8c46574d6721366836c7da0766079b2c9      53140  src/Futhark/IR/SegOp.hs
c2ca879488865abfd67591f4ba60b94a19153840eae27967a6ffcf41def30d2a      47776  src/Futhark/IR/TypeCheck.hs
077cd5ebce1fb9d4f4c1123a54392936d13d557df1530d9afe65f8f37896d5f2       4143  src/Futhark/Internalise/AccurateSizes.hs
0bb5bbe4722958c60f32312cc33f0179acba56fb157ca28c4ec33c4dd184ba5f       9347  src/Futhark/Optimise/ArrayShortCircuiting.hs
ea5c9def67918990caee8c43a0b8a46d35a0579d7d425b3a8d1a6af5a5f961df      30111  src/Futhark/Optimise/Fusion.hs
f29b51e2af53f9f2e1933f3ff17588f2899648d0388eb176362d31c2b7a4f8d1       9734  src/Futhark/Optimise/Fusion/Composing.hs
95c5c2b433a2e9d253209fdab1d1f9e28963ebbe003ae71dec7d8af7558392ed      15915  src/Futhark/Optimise/Fusion/GraphRep.hs
706a442dc3dce6d5574b52ab8d52bbcb575f287ef48d31b8bb25c9258eeb207b      17780  src/Futhark/Optimise/Fusion/Screma.hs
c022d55416483f1f6429eca65725464c1e8068c9de0a30b8e5718c15244c42e9      32023  src/Futhark/Optimise/Fusion/TryFusion.hs
f6596cf65f402c6a4ca191542b72c634171592c46012efa19b16c7f3ffec504c      31534  src/Futhark/Pass/Flatten.hs
1a0d5703d18b5da6661bf8119f003dfa2ae8af0507a6faad007dc84ac2fac47e      27041  src/Futhark/Pass/Flatten/Distribute.hs
9250bc6138f5ac80a68c5b69fa1af11f7bee693b0601d0f5e33b94284797a89f      20987  src/Futhark/Pass/Flatten/Incremental.hs
a51505f8d9016ba746885a6b57499489cdfb13c39416bcd5c098143904786e44       6119  src/Futhark/Passes.hs
34f02f1447a12c51878600673c7862861954ad9fbf0dad2a4e27c1eb91817ffc      41031  src/Language/Futhark/TypeChecker/Consumption.hs
94f1b5a2dbcf333bcefdb153a78368e37ad1232327aaccb0a130eed3c85ec37e      48045  src/Language/Futhark/TypeChecker/Terms/Unsized.hs
f367195e78d5da7d9cbf4ba099f974e5459c9344317d59338e5537ba224c3b9c      26403  src/Language/Futhark/TypeChecker/TySolve.hs
0ac58e28e567907dc86607f102e38b923dadab384be960ed698e59da9cfc52c6      34458  src/Language/Futhark/TypeChecker/Unify.hs
```
