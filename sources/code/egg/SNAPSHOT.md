# Snapshot: egg, the e-graph library

- **Upstream:** `egraphs-good/egg` on GitHub.
- **Revision:** `main` at `2f31b28e3f9d78e02273b6c6d4201b5b0720b343` ("Extraction optimization
  (#367)", 2026-07-19), the pin `sources/README.md` recorded on 2026-09-26. It is 7 commits ahead
  of and 0 behind the latest release tag `v0.11.0` (`fb6167957beb5dd7c784121459e08ebd1ccb1a00`,
  2025-12-04), and `Cargo.toml` says `version = "0.11.0"`; `main` was at
  `73975c9819efb4af2f3c6c1b44fa53f8c5742574` on 2026-10-23.
- **Fetched:** 2026-10-23, from
  `https://raw.githubusercontent.com/egraphs-good/egg/2f31b28e3f9d78e02273b6c6d4201b5b0720b343/<path>`;
  every file under `src/` at that commit, and the root `Cargo.toml`, `README.md` and `LICENSE`.
- **Paths:** relative to the repository root (so `src/egraph.rs`).
- **Files:** 26 (plus this file).
- **Licence:** MIT (`LICENSE`, "Copyright 2019 Max Willsey", the MIT text; `license = "MIT"` in
  `Cargo.toml`).
- **Topic:** Analyses, solvers and dense side tables (P0 audit 5.7, item 16); equality saturation
  (Rewriting), with `willsey-2021-egg`.
- Nothing was built or run; the files were read only.

**What is here, and why.** The library `willsey-2021-egg` describes, whole: the e-graph and its
rebuilding (`src/egraph.rs`, `src/eclass.rs`, `src/unionfind.rs`), languages and analyses
(`src/language.rs`), e-matching by an abstract machine (`src/machine.rs`, `src/pattern.rs`,
`src/multipattern.rs`, `src/subst.rs`), rewrites and the runner with its scheduler and limits
(`src/rewrite.rs`, `src/run.rs`), extraction (`src/extract.rs`, and by integer programming
`src/lp_extract.rs`), explanations (`src/explain.rs`), and the tutorials (`src/tutorials/`).

Not taken: `tests/`, `benches/`, `doc/`, `CHANGELOG.md`, `Makefile`, `CITATION.bib`.

**How to fetch more.**

```bash
rev=2f31b28e3f9d78e02273b6c6d4201b5b0720b343
p=tests/math.rs
mkdir -p "code/egg/$(dirname $p)"
curl -sL --fail -o "code/egg/$p" "https://raw.githubusercontent.com/egraphs-good/egg/$rev/$p"
```

## File manifest

Every stored file except this one: 26 files, 380,924 bytes in all. Computed 2026-10-23 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
bb4eeededdc4b27881a0704f9d3f5b3824bae004da8ce45c4ef34f5c27de8fcc       2136  Cargo.toml
33ec94d67f8eff8e107cbd61c6af1502c6e414c5ec70923cf47515f015233969       1050  LICENSE
76667e9f1e5b6d53a3ba80210e19670c31fc4270ea68598f384380e38e21894a       2865  README.md
a10f9c987b4ea635ad28b21532b84b678ea0d7f1da0c5bd0bd553156de1b26c7       7735  src/dot.rs
d7ac6ac851090485946b1b250fd47902bde6153a68ee25e7d85c6ac13548fcee       3654  src/eclass.rs
7582d7a8191dd0dae8619ccaa431203e010f2f3a7dfa631f723067e2b67f589e      53625  src/egraph.rs
c55360d1667f7d2f1c3dd4efbb5b136304ff4fe567ae94ce2eb0c58a23f3f225      69161  src/explain.rs
595cc7d8834927a27b3e6d630a8ed2a0065a3ccd4787c0f2d904ce8246f977b0      10406  src/extract.rs
96f9eabc43a3b8fb34e16d3ed7aeda0d5a03eb90c97cecf3464782025ccce78d      31270  src/language.rs
5ed4e29b3533219d05f3e95d0f5f7861503b8419126224fffaf24f3c0a291cf8       3831  src/lib.rs
1ee34d542c5c14b0886ccba054e98b346a6a3552615f35cf04d6efb711cb0b47      16430  src/lp_extract.rs
41cf8f9ffb71210466ae7978434e69782e576ed883a6e77f7c793292112e4abf      11269  src/machine.rs
851649b6d5b956aa1fd4d8f326855506d83536a42d235c9542b4d047dac961ef      16453  src/macros.rs
c76fbd3cbd562b64a7b208cd3cc6d8fa5c3332824c7466419da5605e12780b52      10891  src/multipattern.rs
7c19c9d588e04999b6443a58021cad997659231844357709061e86db9b38c11e      16096  src/pattern.rs
de9e82fc8d8b76f90f0c2497ff5c8d424b67140e6df8ce412d533e4ac015b68e      22010  src/rewrite.rs
6c1fe13fcb391ae0fa993bcd6dfcea23f27627c3ee853346281e6165fe3e86e4      32409  src/run.rs
fa789d88098c998337aafa3f61cbf22f3b899f02226120632fbf8a5f3b2c6cd3       4347  src/sexp.rs
a73da3c785dc443ffbc1fb2542e093e7a840fe493eae662d8f987d31ace8c516       5172  src/subst.rs
eb6d011038b08c50dbe8bcf118147047459a0622199740d878e53dcac8dea9ea       8832  src/test.rs
8333841f74ccc0ff325d5c0c2007a0798233ec9c2e3c88d629aa0458968d2234      28950  src/tutorials/_01_background.rs
e28311904bae54722ff7d1b15018e4b466f5ccb318e88889dfba327d6382bb40       7395  src/tutorials/_02_getting_started.rs
fd99b82b4766e7584c1ada8d0008cb8caf69640a24301d17bbc46f1bdfecfa69       5419  src/tutorials/_03_explanations.rs
a1bc64c9a40f0fb6b3bc557f637630fbe947f574ff4dca82f4e8513259b6b688       1051  src/tutorials/mod.rs
c81b6279541ac8be9383dfc6b3bd3809d9dc943a027dd775fe9a39c1e6d4f6ca       2300  src/unionfind.rs
e5a6f0d41b8912f1ba0e96db44be17f9fcf80d977282cb1f9953b95ccb448fa8       6167  src/util.rs
```
