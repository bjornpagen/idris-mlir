# Snapshot: makanin-algo (Slepak's word-equation solver for shapes)

- **Upstream:** `jrslepak/makanin-algo` on GitHub (https://github.com/jrslepak/makanin-algo),
  "Implementation of Makanin's algorithm for string equation satisfiability" (Racket package
  `makanin`).
- **Revision:** `master` at `64e3ac616ce29b62a0ee522ee59c5098f21cd0d0` (last commit
  2020-06-01).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/jrslepak/makanin-algo/64e3ac616ce29b62a0ee522ee59c5098f21cd0d0/<path>`.
- **Paths:** relative to the repository root.
- **Files:** 6.
- **Licence:** none stated (no licence file; GitHub's licence API returns 404). Verify before
  redistributing.
- **Threads:** typed-rank (Array languages and typed array programming).

**What is here and why.** The solver of `slepak-2020-dissertation` chapter 7, which
`code/revised-remora/makanin-wrapper.rkt` calls:
- `solve.rkt` (entry points: `solve-monoid-eqn*`, `solve-semigroup-eqn*`, their `/t`
  variants that also return the equivalence relation on constants, `transport*`);
- `generalized-eqn.rkt`, `ge-base.rkt` (generalized equations: bases as variable or
  constant spanning a column interval; the transport step);
- `enumerate.rkt` (enumeration of boundary alignments and of end-preserving monotone
  injections, the nondeterministic choices as streams);
- `diophantine.rkt` (the linear-population pruning check), `utils.rkt`.

**Not taken:** `info.rkt`, `tests.rkt`, `.gitignore`. Nothing was built or run.

## File manifest

Every stored file except this one: 6 files, 76,962 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
b9e497f125cb9f5829a02d1107cf0ae56607ffdf43cb1ea74392fa0dfd89daeb      12873  diophantine.rkt
c37a775ee47b033c94ae883626edb02818609a36028bb0023ed84b4d417c9401       7823  enumerate.rkt
83d7050116d603bfb6351aad2b218229eea40f9807ebf95048bd7487c0037693      11125  ge-base.rkt
56dd4ac03ebdd3fd779708a99068035239c8636d06edf87a4324ca7d5e28316a      22502  generalized-eqn.rkt
22fd1ea7a608735418024c2b301d2be0ee792069ebb6b7628562740ec8a3048f      18717  solve.rkt
01f8b46b783398eec284eab9ab25ba32b5f04a2986ed50f8195cfd4fef7237d5       3922  utils.rkt
```
