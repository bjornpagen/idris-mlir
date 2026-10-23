# Snapshot: Go's SSA backend, dense value IDs and sparse sets

- **Upstream:** `golang/go` on GitHub.
- **Revision:** tag `go1.27.3` (lightweight), commit `2aae1000ea1d4b28923b96db28acf4e3b99d6aff`
  ("[release-branch.go1.27] go1.27.3", 2026-10-20), the latest Go release on 2026-10-23.
- **Fetched:** 2026-10-23, from
  `https://raw.githubusercontent.com/golang/go/2aae1000ea1d4b28923b96db28acf4e3b99d6aff/<path>`;
  the file list was chosen from the tree at that commit.
- **Paths:** relative to the repository root (so `src/cmd/compile/internal/ssa/value.go`).
- **Files:** 8 (plus this file).
- **Licence:** BSD-3-Clause (`LICENSE`, "Copyright 2009 The Go Authors"), with the patent grant in
  `PATENTS`.
- **Topic:** Analyses, solvers and dense side tables (P0 audit 5.7, item 12).
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `src/cmd/compile/internal/ssa/value.go` | `Value`: an SSA value whose `ID` is a small integer dense within its function |
| `src/cmd/compile/internal/ssa/func.go` | `Func`: the per-function ID allocators for blocks and values (`bid`, `vid`), and `newSparseSet`/`retSparseSet` and their map variants, which take sets and maps sized by those IDs from a reused cache and give them back |
| `src/cmd/compile/internal/ssa/id.go` | `idAlloc`, the allocator of dense IDs |
| `src/cmd/compile/internal/ssa/sparseset.go` | `sparseSet`, Briggs and Torczon's representation over IDs ("from https://research.swtch.com/sparse, in turn, from Briggs and Torczon") |
| `src/cmd/compile/internal/ssa/sparsemap.go` | `sparseMap`, the same representation holding a value per ID |
| `src/cmd/compile/internal/ssa/README.md` | the package's own description of the IR |
| `LICENSE`, `PATENTS` | licence and patent grant |

Not taken: the rest of `src/cmd/compile/internal/ssa/` (among them `sparsemappos.go`,
`sparsetree.go`, `block.go`, `cache.go`, `allocators.go`).

**How to fetch more.**

```bash
rev=2aae1000ea1d4b28923b96db28acf4e3b99d6aff
p=src/cmd/compile/internal/ssa/sparsetree.go
mkdir -p "code/go/$(dirname $p)"
curl -sL --fail -o "code/go/$p" "https://raw.githubusercontent.com/golang/go/$rev/$p"
```

## File manifest

Every stored file except this one: 8 files, 61,897 bytes in all. Computed 2026-10-23 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad       1453  LICENSE
96f408bfae65bf137fc2525d3ecb030271c50c1e90799f87abf8846d8dd505cc       1303  PATENTS
b7fec025e02fe9be0766432d4a14cf8b7f8be82185eb1f15264b8a5cde6e5651       9142  src/cmd/compile/internal/ssa/README.md
c1317a6f408e56f5238d73957afb3c595120b7bbfd55d82507aad742372969da      26966  src/cmd/compile/internal/ssa/func.go
0d95d9b17b31e4677f25dca65491345963fc6b8ab2c23c356c2cee0f75ddefed        576  src/cmd/compile/internal/ssa/id.go
2fe4836f406f327f3c4748f8445870d05ca9e6309f56b6a013dbf54da7019b43       2165  src/cmd/compile/internal/ssa/sparsemap.go
f7b335756234bc83907779b979ad44ed51293d2ed481a37dff527848faf5b210       1582  src/cmd/compile/internal/ssa/sparseset.go
1b9c1aae99ee4b7563415261d10f09965a8427dfdf9216989b94025e5e715efc      18710  src/cmd/compile/internal/ssa/value.go
```
