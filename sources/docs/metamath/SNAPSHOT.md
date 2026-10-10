# Snapshot: Metamath (the book, a fast verifier's README, the list of verifiers)

- **Upstreams and revisions:**
  - `book/`: `metamath/metamath-book` on GitHub at `a54c715930739fd11589595c310823ec5eb57eee`
    (committed 2023-12-15; HEAD resolved with `git ls-remote` on 2026-10-09), from
    `https://raw.githubusercontent.com/metamath/metamath-book/a54c715930739fd11589595c310823ec5eb57eee/<path>`.
    This is the LaTeX source of Norman Megill and David A. Wheeler, *Metamath: A Computer
    Language for Mathematical Proofs* (Lulu Press, 2019, ISBN 978-0-359-70223-7), as
    maintained since (title page: `metamath.tex` line 839; the BibTeX in `book/README.md`
    gives the first edition's title, "A Computer Language for Pure Mathematics").
  - `knife/README.md`: `metamath/metamath-knife` at
    `76fc9f7f39f46f4c43499a0c2bd1402eb8b1cf9a` (committed 2025-05-07; HEAD on 2026-10-09),
    file `README.md`.
  - `other.html`: `https://us.metamath.org/other.html`, a live, unpinned page (HTTP 200,
    53,605 bytes), saved as served.
- **Fetched:** 2026-10-09.
- **Paths:** flat, human-readable: `book/` keeps the repository's own file names.
- **Files:** 10.
- **Licence:** book: CC0 1.0 (`book/LICENSE.md`); `knife/README.md`: metamath-knife is
  MIT OR Apache-2.0 (the README's licence section); `other.html`: the page's footer reads "Copyright terms: Public domain".
- **Threads:** kernels-trust (Fast dependent type checking and elaboration).

**What is here and why.** Metamath is the smallest-kernel, fastest-checking system with a
large library, and the ancestor of MM0:
- `book/metamath.tex` (Chapter 4 "The Metamath Language", §4.1 the complete specification:
  a proof is an RPN label sequence checked by substitution and disjoint-variable conditions;
  Appendix C, the formal system), `book/README.md`, `book/abstract.txt`, `book/errata.md`,
  `book/narrow.sty`, `book/normal.sty`, `book/special-settings.sty` (the last two are empty
  in the upstream), `book/LICENSE.md`;
- `knife/README.md` (metamath-knife, a parallel and incremental verifier in Rust, fork of
  smetamath-rs/smm3: "over 28,000 proofs can be proved in less than a second", run as
  `--jobs 4`; no machine stated);
- `other.html` (the list of known Metamath verifiers, with self-reported times: smm3
  "verifies set.mm in 0.7s on a 2-core, 2-way SMT Intel i5 1.6GHz CPU as of June 18, 2016";
  verify.lua "needs 40 min"; mmverify.py "350 lines of Python").

**Not taken:** the book's `cover/` images, `german/` translation and `metamath.pdf`;
metamath-knife's sources; `set.mm` itself. Nothing was built or run.

## File manifest

Every stored file except this one: 10 files, 800130 bytes in all. Computed 2026-10-09 over
the stored copies; check with `shasum -a 256 <path>` from this folder.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `book/LICENSE.md` | 6941 | `4c2357663d074c5b677c5f04c03691f30e85921a988fd17a008d7bd71a0b1622` |
| `book/README.md` | 3987 | `b12d5c0955a832493c6a126cb06afe4fd96a384712f69946e68d073b627e7f95` |
| `book/abstract.txt` | 682 | `10894fe5456cdb45fa95967d5b77ac4bf65e6030cfc5061d1abfe1a942bf9264` |
| `book/errata.md` | 2291 | `26a47d709771540da333295efc5f6e2c5edfafbc356335198e03d6506a201237` |
| `book/metamath.tex` | 726052 | `4488714b120f8680ea76936080bf938ef0c7114d64ad1ebe7d25afac92063360` |
| `book/narrow.sty` | 1286 | `4f1202be4cef1510c86becc5e7a08c30697d7618872226138c9387eff7b3ab1e` |
| `book/normal.sty` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `book/special-settings.sty` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `knife/README.md` | 5286 | `537b13c02f1f9ad9839e252c08bd30738a79991b626ea9e594c36d31de14ce1c` |
| `other.html` | 53605 | `08af8c1340f0a5e4974bbc241aaa9a29eed186592d32673df95e86ee06c42fb0` |
