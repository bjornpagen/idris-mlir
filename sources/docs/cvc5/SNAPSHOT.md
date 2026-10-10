# Snapshot: cvc5 licence and build notes

- **Upstream:** `cvc5/cvc5` on GitHub.
- **Revision:** `a3f47bdffd29f30f65f886e180f233227cb4b27e`, the HEAD resolved with `git ls-remote https://github.com/cvc5/cvc5 HEAD` on 2026-10-09.
- **Fetched:** 2026-10-09, from `https://raw.githubusercontent.com/cvc5/cvc5/a3f47bdffd29f30f65f886e180f233227cb4b27e/<path>`.
- **Paths:** relative to the repository root.
- **Licence:** BSD-3-Clause for cvc5 (`COPYING`); third-party pieces as listed there.
- **Threads:** decision-procedures (Fast dependent type checking and elaboration).

**What is here and why.** The licence and installation guide, for the licence and static-build questions. `COPYING` gives cvc5's modified BSD licence, the bundled MiniSat code, the default LGPL-3 links (GMP, and MPFR unless `--no-mpfr`), CaDiCaL (MIT) and SymFPU (its own licence, referenced but not reproduced in `COPYING`; not checked), the optional GPLv3 libraries (CLN, glpk-cut-log, CoCoALib, Normaliz) that only `--gpl` enables (`--no-gpl` is the default), and the optional CryptoMiniSat, Kissat, LibPoly and libedit. `INSTALL.rst` documents `./configure.sh --static` and `--static-binary`, `--auto-download` building GMP, MPFR, CaDiCaL and SymFPU from source for static or cross builds, and on macOS (lines 32–42) that `--static` yields static dependencies in a binary that is still dynamically linked, since Apple discourages static system libraries.

**Not taken:** the sources, `README.md` and `configure.sh` (fetched for reading, not stored). Nothing was built or run.

## File manifest

2 files, 32,342 bytes in all. Computed 2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                                bytes  path
74541a329605b0b949ccb6a4deb3cc22ab3efae773e46d1cb6b252bf797620ed        7343  COPYING
df1251f73ad317ed11e5fa1777e64f4fb353e1569f758e91b30588bb5eeaac6c       24999  INSTALL.rst
```
