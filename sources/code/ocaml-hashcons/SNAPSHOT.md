# Snapshot: ocaml-hashcons

- **Upstream:** `backtracking/ocaml-hashcons` on GitHub (J.-C. Filliâtre's hash-consing
  library, the code of `papers/filliatre-2006-hash-consing/`).
- **Revision:** tag `1.4.0`, commit `9d6a7855e70ac59f8e434efdc301aa9c9bc81991` (annotated tag
  object `5cdd67c99ec3611029df5e0650b0188314a38af0`; `master` was at
  `4d10dc7721be74e87fff7538a268a37d40c898b7` on 2026-10-09).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/backtracking/ocaml-hashcons/9d6a7855e70ac59f8e434efdc301aa9c9bc81991/<path>`.
- **Paths:** relative to the repository root.
- **Files:** 6 (plus this file).
- **Licence:** GNU LGPL with the OCaml special exception on linking (`COPYING` says "version 2",
  `LICENSE` and the file headers say version 2.1; verify). Study only: nothing of it is to be
  copied into this repository's code.
- **Topic:** Flattened data: packed, columnar and nested layouts.
- Nothing was built or run; the files were read only.

**What is here, and why.** `hashcons.mli` (the private record `{hkey; tag; node}`, the generic
and functorial `Make(HashedType)` tables, `Hset`/`Hmap` Patricia-tree sets and maps keyed by
tags) and `hashcons.ml` (the weak hash table: buckets of weak pointers, the stored hash key
reused on resize, a single lookup-or-insert), with `README.md`, `CHANGES.md`, `COPYING`,
`LICENSE`. Not taken: `test.ml`, `test_qs.ml`, `rule110.ml`, build files.

## File manifest

Every stored file except this one: 6 files, 72,232 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
7ad17adf5f2213d59592a86c27b28b5980e4960f6d5fc0beed1080f63125c1cd        731  CHANGES.md
80cf49a9830e44dfbcfeef4478f04cecff603256fac003346059610421d4cdd2        469  COPYING
e9684ff81666d63a1746f6b3f0d904db100d092fb4f15032ea4fdc0b89762e4d      27534  LICENSE
cda0d13777e3084337eb9e5841a3ace3291352a93acb40646b23641b849a47cf        444  README.md
4ac7c254d7714b0fc0b2880a99d26fbb6f06ccc6bdd21f8fc3bcac48477e71e6      33635  hashcons.ml
d5e8c2184166cef0f944635f3c5544166110416c683a06e0e083cae465210725       9419  hashcons.mli
```
