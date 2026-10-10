# Snapshot: ghc-typelits-natnormalise (normalising type-level Nat arithmetic in GHC)

- **Upstream:** `clash-lang/ghc-typelits-natnormalise` on GitHub
  (https://github.com/clash-lang/ghc-typelits-natnormalise); on Hackage as
  `ghc-typelits-natnormalise`.
- **Revision:** default branch at `44c1a880be312d73c175dda131a8f97ff0d22a75` (commit
  2026-09-19; older than two weeks at fetch time).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/clash-lang/ghc-typelits-natnormalise/44c1a880be312d73c175dda131a8f97ff0d22a75/<path>`.
- **Paths:** relative to the repository root (so `src/GHC/TypeLits/Normalise/SOP.hs`).
- **Files:** 6.
- **Licence:** BSD-2-Clause, © 2015–2016 University of Twente, 2017–2018 QBayLogic B.V.
  (`LICENSE`).
- **Threads:** typed-rank (Array languages and typed array programming); E.

**What is here and why.** The "typelits-natnormalise idea": decide equalities of `Nat`
expressions over `+`, `-`, `*`, `^` by normalising both sides to a sum-of-products form and
comparing syntactically, and derive unifiers when they differ.
- `src/GHC/TypeLits/Normalise/SOP.hs` (the normal form: grammar and invariants in the module
  header, merge and simplification functions);
- `src/GHC/TypeLits/Normalise/Unify.hs` (conversion between GHC types and SOP;
  `unifyNats`/`unifiers` at lines 410–618: `Win`/`Lose`/`Draw` with the substitution rules
  listed in the comment at 453–485; inequality solving; `isNatural`/`canBeNatural` guards
  against subtraction going negative);
- `src/GHC/TypeLits/Normalise.hs` (the plugin: the module header documents the unsound
  `allow-negated-numbers` option and why);
- `doc/ghc-typelits-natnormalise-hcar.tex` (the HCAR entry), `README.md`, `LICENSE`.

**Not taken:** `Compat.hs`, the tests, CI, cabal files. Nothing was built or run.

## File manifest

Every stored file except this one: 6 files, 86,127 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
2e5de76e485ad18c484797d5d1bedd7c3daee26f7b570cb5ae7576a6f4cc524e       1356  LICENSE
8b67407978092ccccd4d8d74135a35c6075a2f1d4d685a00a475ea23f49eeb94       1057  README.md
4c8da5f5e8a39beabfe56b473c13fb4a2beecf74f1f4861d5d05e1a3dee128ad       3015  doc/ghc-typelits-natnormalise-hcar.tex
aeb910fa62f21677dee8489dd574887a858353d9e266eebb7af655ec90513ae7      35280  src/GHC/TypeLits/Normalise.hs
78143e2e6ed74ef52e2c327037a9ed9132aff545e9af38c00686d1bae72033dd       9130  src/GHC/TypeLits/Normalise/SOP.hs
c4c848aa428d841ac4af73be711dc7db896423695fe637aa7738b35a6643f178      36289  src/GHC/TypeLits/Normalise/Unify.hs
```
