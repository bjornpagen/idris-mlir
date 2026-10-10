# Snapshot: Remora (ESOP'14 Redex model and Racket prototype)

- **Upstream:** `jrslepak/Remora` on GitHub (https://github.com/jrslepak/Remora), "Dependently-typed
  language with Iverson-style implicit lifting".
- **Revision:** `master` at `1a831dec554df9a7ef3eeb10f0d22036f1f86dbd` (last commit
  2020-03-24).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/jrslepak/Remora/1a831dec554df9a7ef3eeb10f0d22036f1f86dbd/<path>`.
- **Paths:** relative to the repository root (so `semantics/dependent-lang.rkt`).
- **Files:** 12.
- **Licence:** none stated. The repository has no licence file (GitHub's licence API returns
  404); all rights reserved by default. Excerpts kept for study only: verify before
  redistributing.
- **Threads:** typed-rank (Array languages and typed array programming); G.

**What is here and why.**
- `semantics/` (the PLT Redex model of `slepak-2014-remora`, appendix D):
  `Readme.md`; `language.rkt` (untyped calculus: rank-directed lifting, `lift`/`map`/`collapse`
  reductions); `dependent-lang.rkt` (the typed calculus and its type judgment: the
  `frame-contribution`, `largest-frame` and `larger-frame` metafunctions that compute the
  principal frame, lines 137–150 and 298–335); `typed-reduction.rkt` (type-directed
  reduction); `redex-utils.rkt` (a helper both require).
- `remora/` (the `#lang remora/dynamic` Racket prototype): `Readme.md`;
  `dynamic/lang/semantics.rkt` (`apply-rem-array`, lines 27–170: the run-time frame/cell
  machinery: expected ranks, principal frame by `prefix-max`, cell and frame sizes, and the
  replication-by-quotient indexing of every argument cell; empty-frame handling by result
  shape annotation); `dynamic/lang/syntax.rkt` (the surface forms that feed it);
  `scribblings/{application,arrays,boxes}.scrbl` (the documentation of lifting, arrays and
  boxes).
- `notes/composition.txt` (design notes on composing reranked functions).

**Not taken:** `aliens/` (third-party PDFs: `dk-2013.pdf`, `tr87.pdf`), the basis library,
records, the reader, the examples (including the 707 KB `spambase.data`) and the remaining
scribblings. Nothing was built or run.

**How to fetch more.** Same URL pattern with another path from
`https://api.github.com/repos/jrslepak/Remora/git/trees/1a831dec554df9a7ef3eeb10f0d22036f1f86dbd?recursive=1`.

## File manifest

Every stored file except this one: 12 files, 180,349 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
ca528915813204c8b64fcc635e181c8e5bec8a7e5e7fa3a1abf1d955615323c1       3876  notes/composition.txt
72b71c212efd6430873c2e91fe60a609b3e6c6efc0c2ab071cbaadd8e56eec93        686  remora/Readme.md
657b52e9b3bcd9c5d47080da0c8ce7b0213b3e51754d5ddafe945428b17c4106      24931  remora/dynamic/lang/semantics.rkt
15ee68b59491dc7ca87035adc3e56732c3b0935e45ec5dc73ed4a3ea8610375a      10023  remora/dynamic/lang/syntax.rkt
6afd9117202b866b643f010e6c531b06f914df14f48e993c27bda91fa1c4196d       8321  remora/scribblings/application.scrbl
67b5b12fc53a885f677d4c18b387765ed1d723aeeb052f606ccc86250042a248       4411  remora/scribblings/arrays.scrbl
8816f8bd684fe6b284162def97ee64cdcb0470d50b4c19fd3cc2d2a6c0f0e6cf       2056  remora/scribblings/boxes.scrbl
d9b9ca7a4404cb2ee56ebc90a9dba53d502b4b7a1103a209603d9cd039407600       1445  semantics/Readme.md
119d2a3f119e60483db51a5e7804207564b37d2fed7992d937b44170a14f053a      48021  semantics/dependent-lang.rkt
64abc6e64797d1a37900b5c191910dc4789df7ac7b1e0da2b8bf51feb713be3a      41640  semantics/language.rkt
8d98286644dd5f940472f5bfb68f94db701c0f67536a9985ab5cac0471dbcbc1        861  semantics/redex-utils.rkt
531e0b8c0c9337371f88e7008b31f9b7a70aba04941c7600e10d20b852fa9910      34078  semantics/typed-reduction.rkt
```
