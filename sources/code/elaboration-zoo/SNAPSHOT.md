# Snapshot: elaboration-zoo (minimal dependently typed elaborators)

- **Upstream:** `AndrasKovacs/elaboration-zoo` on GitHub
  (https://github.com/AndrasKovacs/elaboration-zoo).
- **Revision:** default branch at `9626d6c7a40efa753a757f435df3710efc805d2f`, the HEAD resolved
  with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/AndrasKovacs/elaboration-zoo/9626d6c7a40efa753a757f435df3710efc805d2f/<path>`.
- **Paths:** relative to the repository root.
- **Licence:** BSD-3-Clause style (`LICENSE`, "Copyright András Kovács here (c) 2016, All
  rights reserved", with the three-clause redistribution conditions).
- **Threads:** elaborators (Fast dependent type checking and elaboration).

**What is here and why.**
- `GluedEval.hs`: the minimal demo of glued evaluation (`VTop Name Spine ~Val`) and the
  reasoning for it (credited to Olle Fredriksson's sixty).
- `05-pruning/`: typed metas and pruning (`README.md`; `Unification.hs` with partial
  renamings that prune, intersection of spines, non-linear spines; `Evaluation.hs`,
  `Value.hs`, `Metacontext.hs`, `Syntax.hs`, `Elaboration.hs`).
- `03-holes/pattern-unification.txt`: the tutorial note on pattern unification.
- `README.md`, `LICENSE`.

**Not taken:** the other numbered packages (01–04, 06 first-class polymorphism) and the
`experiments/` directory (sigma unification, runtime code generation, universe
polymorphism). Nothing was built or run.

## File manifest

Every stored file except this one: 11 files, 33,749 bytes in all.

```
SHA-256                                                               bytes  path
0f26ffd3e79d136a4e5570d10548493a289832f2ff78445ed068281cadb5ad4a       5574  03-holes/pattern-unification.txt
d2b70f92826da529d80e97f7f0a7853f3dd0a4c7cc5bbe39a475f165bd987da7       4486  05-pruning/Elaboration.hs
170d52616bf5ed903f23d1401f52a47c6517ef96bebc0f44d2deec00c69e7c5f       2148  05-pruning/Evaluation.hs
f77f6322361f6ee31cfd0fee4cdc10d23b8da97784cd069717e1e12214febbed       1075  05-pruning/Metacontext.hs
7589966058a34e95b7546f09de1d830a04a127fe17b1a4dadb012fdb01edb5ab       2009  05-pruning/README.md
883e8b9002aa8e0a18364d675ae4810c559c0c7ca19862d07c89077b9070b483       1352  05-pruning/Syntax.hs
026b126bc63a42a748c9f029589527d5b28e2e7f92c93f50cc89899d95237e63       9266  05-pruning/Unification.hs
66de73aeda44899dea38a14cd144c5e085b271ec4acdb5876a6348b876c43202        418  05-pruning/Value.hs
f4c25f59c0abaf84f4a70e2d3c1c520e5c2a4bed6ae604d0edccb965947b0314       4662  GluedEval.hs
a6a9022913ec9863b3f2619eca5d9ebfffd984624ee9d480de108de8d0633eff       1532  LICENSE
b1bdd5ae1bbda95b8906774713b985313c777be6866ecf65d06b49abccfa7430       1227  README.md
```
