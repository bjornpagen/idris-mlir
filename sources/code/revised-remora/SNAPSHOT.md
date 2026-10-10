# Snapshot: Revised-Remora (the dissertation's Redex model, with bidirectional inference)

- **Upstream:** `jrslepak/Revised-Remora` on GitHub (https://github.com/jrslepak/Revised-Remora),
  "Semantic model based on a revision of the ESOP'14 paper".
- **Revision:** `master` at `0b7b8ad3d757a09536679f515fb30033a3b092ad` (last commit
  2020-04-10).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/jrslepak/Revised-Remora/0b7b8ad3d757a09536679f515fb30033a3b092ad/<path>`.
- **Paths:** relative to the repository root.
- **Files:** 12 (the whole repository except `.gitignore`).
- **Licence:** none stated (no licence file; GitHub's licence API returns 404). Verify before
  redistributing.
- **Threads:** typed-rank (Array languages and typed array programming); G.

**What is here and why.** The model that `slepak-2020-dissertation` cites for chapters 4 and
6 (its margin note 23):
- `language.rkt` (explicit Remora: atoms/expressions, `Dim`/`Shape` indices, `Arr`, Π, Σ, ∀);
  `typing-rules.rkt` (the explicit type judgment; `type-app` at lines 299–325 finds each
  argument's frame by `drop-suffix` and the principal frame by `largest-frame`;
  `normalize-idx` at 797–823 is the canonical form of indices; line 570 notes that
  type/index equivalence is still syntactic equality of normal forms);
  `reduction.rkt` (type-directed reduction); `well-formedness.rkt`.
- `implicit-lang.rkt`, `elab-lang.rkt`, `bidirectional.rkt` (implicit Remora and its
  bidirectional elaboration: `synth-app` at 277–429 with rules `app:∀`, `app:Π`,
  `app:->*f`, `app:->*a`, `App:->*c`, `app:->0` that introduce existential argument-frame and
  frame-extension shape variables and call `equate`; `equate` at 1072–1174 with its trimming
  shortcuts before the solver; subtyping-as-instantiation at 430–700).
- `makanin-wrapper.rkt` (adapter to the `makanin` package, `code/makanin-algo/`: maps the
  solver's equivalence classes back to dimension equalities and solved shape variables);
  `inez-wrapper.rkt` (adapter to Inez, Manolios and Papavasileiou's ILP-modulo-theories
  solver, which decides the Presburger side: existentials eliminated, validity checked as
  unsatisfiability of the negation); `erased-lang.rkt` (the partially erased language of
  dissertation ch. 10); `list-utils.rkt`.

Nothing was built or run (it needs Racket, Redex, the `makanin` package and an Inez binary).

**How to fetch more.** The repository is fully taken.

## File manifest

Every stored file except this one: 12 files, 250,969 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
cd4cd8ab539c64941cf2522892e327b49129dd18d5701f5c34524e6501e13aa5         73  README.md
f2fb1918c8e6eed8e3ab99691c866e0fb9f21de4ec024008323a74e8f69c4191      74624  bidirectional.rkt
16abf558e220aa0f2c7073242d8e38bad8fb5d73915fb6c409a52b260ca534e0      20810  elab-lang.rkt
4a0eeeb4925e2155074e77ce2be04cc588daf1885fff30a9ec24d23536ba6630       9770  erased-lang.rkt
dedd251708a71bb737a243b36edf346541c6bacb76d6e1c072e6b5b3ab46d010       6677  implicit-lang.rkt
fb3e0667be1a121352cf82d8df9618d195faf1f6be97f3e24509717e649ed0c1      49735  inez-wrapper.rkt
d4ab7f2cf3f3d879e8a4126cd7e32bf20920484def689d8699c2fa65ca78a07e       7687  language.rkt
8e8636219f2ceb4a9680be5aeaa0b73f2ea38f201141354509fe4cf094a9ef75       4325  list-utils.rkt
53cf44914536ee8e3cdd00c26ef7005221ce2d82dc7ccbc3436af50981125b9a      27139  makanin-wrapper.rkt
abef93a2ecb745f3aeb1a3390054e81d15a52a6a390381e9a06b72cbdf2c89bc      10447  reduction.rkt
ec623ad25e4858e92c9f7db7336ce5d15fb99b0bb74e1fb4684fce7728efffb1      37314  typing-rules.rkt
92145b80eb27cf3c42e567ec3b75e22b02c1b7df98b581da5fbb2fbb6215da59       2368  well-formedness.rkt
```
