# Snapshot: Kontroli kernel (the revision measured in the CPP 2022 paper)

- **Upstream:** `01mf02/kontroli-rs` on GitHub (https://github.com/01mf02/kontroli-rs).
- **Revision:** `c980688be66a7357725c1dcc41ca2c21ff282bc2` (committed 2021-09-08), the
  revision `papers/farber-2022-kontroli` names for its line count (`main.tex`, footnote in
  §7.3 "Kernel Size & Supported Features"); HEAD on 2026-10-09 was `22bfbdfc6d20502589c4c53369cf76ebcb1b8178`, not taken.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/01mf02/kontroli-rs/c980688be66a7357725c1dcc41ca2c21ff282bc2/<path>`.
- **Paths:** relative to the repository root (so `kontroli/src/kernel/reduce.rs`).
- **Files:** 11 (`kontroli/src/kernel/*.rs`, 9 files, plus `README.md` and `LICENSE`).
- **Licence:** GPL-3.0 (`LICENSE`).
- **Threads:** kernels-trust (Fast dependent type checking and elaboration).

**What is here and why.** A second, independently written checker for Dedukti's calculus
in Rust, `#![no_std]`, used to measure how far a small kernel can go and where concurrency
pays: `typing.rs` (inference and checking; checking of rule right-hand sides is the part
deferred to a thread pool), `reduce.rs` and `state.rs` (the abstract machine ported from
Dedukti, with `Rc<RefCell<…>>` states and thunks), `convertible.rs` (a work-list
convertibility check: equal terms are skipped, otherwise both sides go to whnf and are
compared structurally), `matching.rs`, `subst.rs`, `share.rs` (constants mapped to one
canonical pointer), `rterm.rs`, `mod.rs`.

The nine kernel files total 913 lines with comments and blank lines (`wc -l`); the paper
reports 663 lines of code (Tokei).

**Not taken:** the parser, `kocheck` (the command-line program), the generic term type
outside `kernel/`, tests and examples. Nothing was built or run.

## File manifest

Every stored file except this one: 11 files, 67800 bytes in all. Computed 2026-10-09 over
the stored copies; check with `shasum -a 256 <path>` from this folder.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `LICENSE` | 35149 | `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986` |
| `README.md` | 2588 | `20a67bf6d28c4e60256cbe23d6f399a5c7a19c774c2495dc3bed106f5c2496ec` |
| `kontroli/src/kernel/convertible.rs` | 2467 | `5637c81f8487369e6bc97147e13554c4ac49f668148f0f73c32794081300571e` |
| `kontroli/src/kernel/matching.rs` | 2650 | `35bb47584a21619820f7aaa479878ba48539719bfd5e5575f35a938ee396a890` |
| `kontroli/src/kernel/mod.rs` | 1161 | `909c4983855fc2b8bc999d5fbdd7b72945bf425a00c60ef5b1527d568413a6aa` |
| `kontroli/src/kernel/reduce.rs` | 6543 | `2a8c7708f207a00a9293f018028e9dba2877169516aaab6187657dec86ba0286` |
| `kontroli/src/kernel/rterm.rs` | 2185 | `cbad0c1438078e84c315d8124bcb8b4c65515aed8ed9ddc2f075d497aca1c2f2` |
| `kontroli/src/kernel/share.rs` | 2021 | `0472e80878bc7a1b2c82f1a913c77dba894adb20b9ae063f6a6125f86496e0e5` |
| `kontroli/src/kernel/state.rs` | 3603 | `459b24bdbcd5ad2196839ca3411382756807aec709cf6849360d44dd82533082` |
| `kontroli/src/kernel/subst.rs` | 2333 | `15686f57269c144e8a684439474597aab86e4d36c7c43357e03c678a2abfe5e1` |
| `kontroli/src/kernel/typing.rs` | 7100 | `ad519e1dc84ef4fdfdd8fcfa507c625147425c18d452824e3354ca5fbc5c0f97` |
