# Snapshot addendum: Proof-Oriented Programming in F*, tactics and typeclasses chapters

Addendum to `docs/pop-in-fstar/SNAPSHOT.md` (staged by the SMT cluster of this pass at the
same revision; `book/under_the_hood/uth_smt.rst` and `LICENSE` were fetched here too and are
byte-identical to that cluster's copies, so they are not stored twice); merge it there.
Written by the elaborators cluster of the 2026-10-09 pass.

- **Upstream:** `FStarLang/PoP-in-FStar` on GitHub (the book rendered at
  https://fstar-lang.org/tutorial/).
- **Revision:** `958d86f2eb158f349785e447228dbf016818c6be`, the HEAD resolved with
  `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/FStarLang/PoP-in-FStar/958d86f2eb158f349785e447228dbf016818c6be/<path>`.
- **Licence:** Apache-2.0 (`LICENSE`).
- **Threads:** elaborators (Fast dependent type checking and elaboration).

**What is here and why.**
- `book/intro.rst`: the design of F* as a proof-oriented language mixing SMT, tactics and
  computation.
- `book/part3/part3_typeclasses.rst`: typeclasses in F*, resolved by a tactic (Meta-F*).
- `book/part5/part5_meta.rst`: Meta-F* tactics and metaprogramming, the companion of
  `papers/martinez-2019-meta-fstar`.
- Read but staged by the SMT cluster: `book/under_the_hood/uth_smt.rst` (the SMT encoding:
  the single `Term` sort, boxing, patterns, fuel and ifuel, `--query_stats`, rlimit,
  `--quake`, hints and unsat cores).

Nothing was built or run.

## File manifest

The files this addendum adds: 3 files, 72,093 bytes in all.

```
SHA-256                                                               bytes  path
8d62005b0123b0be307e162a0ce7b5328dd46a1e5e04a7ac707d8ccec5461825      21986  book/intro.rst
f691742b427ac3615b043e9167151785ddf162b39f59298529e088a3d5e89fb4      27454  book/part3/part3_typeclasses.rst
a9affd82146983754c5de197df1f692baae6f5f4fcf7be56cb477f5890c93a4c      22653  book/part5/part5_meta.rst
```
