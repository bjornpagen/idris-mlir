# Snapshot: smalltt (high-performance dependently typed elaboration demo)

- **Upstream:** `AndrasKovacs/smalltt` on GitHub (https://github.com/AndrasKovacs/smalltt).
- **Revision:** default branch at `ea99b0f478e50dcb81ea19e40bfb4262339b22aa`, the HEAD resolved
  with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/AndrasKovacs/smalltt/ea99b0f478e50dcb81ea19e40bfb4262339b22aa/<path>`.
- **Paths:** relative to the repository root (so `src/Unification.hs`).
- **Licence:** MIT (`LICENSE.txt`, "Copyright 2021 András Kovács").
- **Threads:** elaborators (Fast dependent type checking and elaboration).

**What is here and why.**
- `README.md`: the design notes (NbE, contextual metas, glued evaluation, hash consing,
  strict/lazy, approximate conversion with rigid/flex/full states, paired values, eta-short
  solutions, meta freezing and approximate occurs checking, GHC RTS settings) and every
  benchmark table (elaboration speed, asymptotics, raw conversion, raw evaluation) across
  smalltt, Agda 2.6.2, Coq 8.13.2, Lean 4 nightly 2021-11-20 and Idris 2, with the machine
  (Intel 1165G7, 16 GB, 28 W).
- `bench/README.md`: the exact commands per system; `bench/conv_eval.{stt,lean,idr,v}`,
  `bench/asymptotics.stt`, `bench/stlc_small.stt`: the benchmark sources for the conversion
  and asymptotics tables (the 5k/10k/100k generated files, 0.2–6 MB each, were not taken).
- `src/CoreTypes.hs` (values with `VUnfold` glued heads, `G` paired values, meta entries),
  `src/Evaluation.hs` (eval, force, quote with three unfolding options, zonk),
  `src/Unification.hs` (partial renamings, rigid/flex quotation, approximate occurs check with
  a per-meta cache, eta contraction, the Rigid/Flex/Full unifier),
  `src/Elaboration.hs`, `src/MetaCxt.hs`, `src/LvlSet.hs` (bitset masks for meta scopes),
  `src/Cxt*.hs`, `src/InCxt.hs`, `src/TopCxt.hs`, `src/SymTable.hs` (the custom hash table),
  `src/Common.hs`, `LICENSE.txt`, `CITATION.cff`.

**Not taken:** `src/GenTestFiles.hs` (benchmark generator), the parser and lexer, the
pretty printer, `Exceptions.hs`, the large generated benchmark files. Nothing was built or
run.

## File manifest

Every stored file except this one: 23 files, 148,928 bytes in all.

```
SHA-256                                                               bytes  path
155747178ce098fbc7b4dfab2b1a34d6ae79a4d8012a8ca55a1662d5f36bc6fc        276  CITATION.cff
5d948ab79016e701b647e5d72db2c98e01a7486eb9c03efefeb5dc97f70435f8       1056  LICENSE.txt
0ae84e3f07972c8678f1e6168bf9f6b4d989b64f75e0d25b5e028a96b228f2e4      42485  README.md
7cab8ed12932c91df076d74b57b9f8e2923c5bdecefdb51235646d8f2e08d31d        354  bench/README.md
538e22ed0ee8ad5db0f525b79a37a0b2b83332c3576f137c801f559470078dad      10860  bench/asymptotics.stt
fd29cfad58081b43988438fa70471853db306010bcc021f6805f211068991d85       4712  bench/conv_eval.idr
49c0b3324910f946e84d6397a31e2a55f7adbaf1fdea73cdd0116e1940d72569       4249  bench/conv_eval.lean
4ae4617c1eb396a26014401a23e2f1ddba322632fcd9b9730eb415eda0355488       3845  bench/conv_eval.stt
a3ef75d4243daffae895b02efabe37d5f2f5f0deac70fbf93cb9e907337a22b1       6233  bench/conv_eval.v
a39d1f7fd45e191d89edd9681f9b706c1146c49a8941414e5e30c70b00ef498c       1867  bench/stlc_small.stt
3da586f682fa668d6a6fe5e2f31dcd63fe3812eaad458cc4139d5a31624eba92      12641  src/Common.hs
6efc910cd8daee99bdfa4056eb2e03e6990db6d77221ca08d9212d1369ccbe9d       7280  src/CoreTypes.hs
e274ce34f2b0a7c53c4d9fb58c65277b8d7e8eacf9dec9b46a209dc3a2193167        104  src/Cxt.hs
3d27ddbcaab43769b908964ad133583f7c0f4cf66c3365b1f2d1578a8345a476       1831  src/Cxt/Extension.hs
a1ca7c727e0d7c02a96e4f3823d3e4ed29ab1c12cd2f1f049b0e28d9232039f4        624  src/Cxt/Types.hs
6e28f25782cc2ed4da677616c5d59b96d69a87801dc43f38be87f3ac801f1724       9591  src/Elaboration.hs
19129d265076f17fabb88d7057c4cbd111ed08ea24cc49cb1e496ee256899a4d       8071  src/Evaluation.hs
dbf91c7f7bb9b8e06ae98d5f1acd41d0b4249b531b70b6229af93e75130b84d0       1990  src/InCxt.hs
eb8bac4a5fa894de1e141a8c2dda3e302abcd4c75914acc7f5e79bb0302b820e        862  src/LvlSet.hs
49f3252d9afd74bda6ba4236f29f69257aa3510667a8337ea554b3374451aad4        844  src/MetaCxt.hs
b7832327d62870ee20927abd9f4b01906dad096e3679f18173a407a7789e6cf1      12533  src/SymTable.hs
11a505a950d45f92af6b99cdbd6ab4a5ceac3526900079e422d0653d4f111018       1639  src/TopCxt.hs
3cc1135e28973747a16757768a524717457026714dc1c0c3c7e7e1889c8e6704      14981  src/Unification.hs
```
