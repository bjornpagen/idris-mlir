# Compiler Support for Sparse Tensor Computations in MLIR

- **Authors:** Aart J. C. Bik, Penporn Koanantakool, Tatiana Shpeisman, Nicolas Vasilache, Bixia Zheng, Fredrik Kjolstad
- **Venue / year:** ACM Transactions on Architecture and Code Optimization (TACO) 19(4), 2022, DOI 10.1145/3544559; arXiv preprint `2202.04305` (2022-02-09)
- **Canonical link:** https://doi.org/10.1145/3544559 (arXiv: https://arxiv.org/abs/2202.04305)
- **License:** CC BY 4.0 for the arXiv version (the licence the arXiv record links); the journal version's licence was not checked (ACM, `dl.acm.org` is not fetched by this library)
- **Thread(s):** F, G (topic: Array languages and typed array programming / lowering target)
- **Storage form:** raw LaTeX source (arXiv e-print `2202.04305`)
- **Status:** stored

## Provenance

Fetched 2026-10-09 from `https://arxiv.org/e-print/2202.04305` (HTTP 200, gzip-compressed
tar, 77,416 bytes, SHA-256
`2eea1069786e9ad1a3ee1f2e809bd52eacaf9545262e7a4f84b0139ccb88d13a`). The arXiv abstract
page names the related DOI `10.1145/3544559`. Unpacked with `tar xzf`; no `.aux`/`.log`
files were present. The bundle shipped `mlir.bbl` with no `.bib`; by the library's
convention the orphan `.bbl` was removed (the bibliography is therefore not reproducible
from this folder; the published references are in the journal version).

The arXiv text predates later renames in the dialect: it writes `dimLevelType`,
`dimOrdering`, `pointers` and `indices`, which are `map = (...) -> (... : level-format)`,
positions and coordinates at the LLVM pin
(`code/mlir/include/mlir/Dialect/SparseTensor/IR/SparseTensorAttrDefs.td`).

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `mlir.tex` | 77,699 | `bab1e1206b277c82761d737d0bb971b9d2435b3ceba939de5433ac8ccca2a365` |
| `overview.pdf` | 9,635 | `7eb3b886ce6c01e4fb933d047c7ecd1f42d9c5c86e43d4328fce6025b92055ec` |
| `band-512.png` | 1,759 | `192a62049910ac1f0bbb314cafdacb3b296ee6a53310012ed5174395822056d6` |
| `rand-512.png` | 12,081 | `ca49eddee8b4a35731c7249dec8bf4a2f7f13eef2d95c3151cab33f85b567a9f` |
| `search1.png` | 24,304 | `c8680e06b2b99d6fd239db35ed7bfcf24fcdcbd78183f385c9eee7d88c404e3a` |

## Related entries

- `kjolstad-2017-taco` (the TACO paper whose iteration lattices and level formats this
  dialect follows) is already in the library.
