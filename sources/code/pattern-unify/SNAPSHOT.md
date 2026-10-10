# Snapshot: dynamic pattern unification in Haskell (Gundry and McBride)

- **Upstream:** the source tarball of `papers/gundry-2012-dynamic-pattern-unification`,
  `http://adam.gundry.co.uk/pub/pattern-unify/pattern-unification-2012-07-10.tar.gz`
  (20,843 bytes; tar member dates 2012-07-10).
- **Revision:** the dated tarball `pattern-unification-2012-07-10`; no version control
  revision. A later copy lives in `adamgundry/type-inference` (`src/PatternUnify`), not
  taken.
- **Fetched:** 2026-10-09 (HTTP 200); listed with `tar tzvf`, then unpacked with `tar xzf`.
- **Paths:** relative to the tarball's root directory `pattern-unification-2012-07-10/`.
- **Files:** 7.
- **Licence:** none stated in the tarball or on the page (verify).
- **Threads:** kernels-trust (Fast dependent type checking and elaboration).

**What is here and why.** The program the paper is written around: `Unify.lhs` (the
unification algorithm: decomposition, twin variables for heterogeneous equations, pruning,
inversion, postponement of problems outside the pattern fragment), `Check.lhs` (the
typechecker for the small full-spectrum theory), `Context.lhs` (the metacontext as a zipper
of metavariables and problems), `Tm.lhs` (spine-form, β-normal terms with hereditary
substitution), `Kit.lhs`, `Test.lhs` (the test problems), `README.txt` (requires GHC with the
`unbound` library and the SHE preprocessor). The pruning rule in `Unify.lhs` carries the error
recorded in the thesis errata stored with the paper.

Nothing was built or run.

## File manifest

Every stored file except this one: 7 files, 82704 bytes in all. Computed 2026-10-09 over
the stored copies; check with `shasum -a 256 <path>` from this folder.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `Check.lhs` | 7691 | `3855c9d1f2fc52d0ff9021dd2e52bb3f524760aa10a65aafa13ea818a825b523` |
| `Context.lhs` | 9523 | `279195adb39f49d2d220e2f00c56e91c0cef3c87fc8eab6a9a20df193d39a78f` |
| `Kit.lhs` | 2702 | `7738e7d567271328ddaad8e4d792232e9a0e17c0102e9b6f6f816cf035faac1f` |
| `README.txt` | 425 | `b7724003701c1b2d8673594bd7df87d7c9934f74956b9a0145fc684fabf8cc51` |
| `Test.lhs` | 25219 | `5467298b6fda69d9ab3878686641c55e78fd62eea72aafbde0e867f085ecaf6f` |
| `Tm.lhs` | 10132 | `20c46c102fba500d1afb0bd4079c4d396ca041dc27aad45c4add0c960ec04271` |
| `Unify.lhs` | 27012 | `c995cc76619201bd5f67c8e9ad17ace0423e948ad5cc0a9982e2d2f4a9f1b363` |
