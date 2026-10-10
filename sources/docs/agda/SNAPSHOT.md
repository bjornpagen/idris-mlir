# Snapshot: Agda user manual, with-abstraction and rewriting

- **Upstream:** `agda/agda` on GitHub (https://github.com/agda/agda); rendered at
  https://agda.readthedocs.io/en/latest/language/with-abstraction.html and
  `.../language/rewriting.html`.
- **Revision:** default branch at `83f3fcce37fc5bd11cd7da10bccbe0f59d860037`, the HEAD resolved
  with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/agda/agda/83f3fcce37fc5bd11cd7da10bccbe0f59d860037/<path>`.
- **Paths:** relative to the repository root (so `doc/user-manual/language/...`).
- **Files:** 4.
- **Licence:** MIT-style permission notice (`LICENSE`, "Copyright (c) 2005-2025 remains with
  the authors"); the manual is part of the repository.
- **Threads:** dependent-equality (Array languages and typed array programming).

**What is here and why.**
- `doc/user-manual/language/with-abstraction.lagda.rst`: generalisation over the scrutinee in
  the goal and the argument types (lines 90–171); `rewrite` as sugar for `with lhs | eq` and a
  match on `refl` (564–634); `with ... in eq` (636–697); the cost of normalising and
  re-checking the generalisation (867–885); the translation to an auxiliary function with the
  context split Δ1/Δ2 and the type-correctness check (888–977); worked translations (979–1053);
  ill-typed with-abstractions, the `Σ`/`fst p` example (1055–1095).
- `doc/user-manual/language/rewriting.lagda.rst`: `REWRITE` rules, `+zero`/`+suc` making
  `+comm` go through (54–109), `primRewriteNoMatch` and the `Vec` `++-assoc` rule (119–203),
  the general shape and pattern conditions (278–330: the left-hand side must be neutral, and
  rules fire only after ordinary reduction), and `--confluence-check` (331–350: joinability of
  overlapping left-hand sides and the triangle property).
- `doc/user-manual/language/without-k.lagda.rst`: what `--without-K` restricts in unification.
- `LICENSE`.

**Not taken:** the rest of the manual, the type checker's `Rewriting.hs` and `LHS/Unify.hs`.
To fetch more, use the raw URL pattern above at this revision. Nothing was built or run.

## File manifest

Every stored file except this one: 4 files, 55,487 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
673eb9af047e251e14de6346febc68b31fbc1ba96194cb5d2fe891d6ce4c35c7       2721  LICENSE
72fadd9ab5c0115934de22d7f82f32c684e8a4d25140180df61736fe2c63fa07      13789  doc/user-manual/language/rewriting.lagda.rst
2df3f46cde3904707b7bd32f603568ea5e4ceeb5559e1c0394bdfc9cd5ac1dbc      34492  doc/user-manual/language/with-abstraction.lagda.rst
69d0e41501e12186a8deccb73fd0be3569af6c359456ba8e59ee154ec73686d8       4485  doc/user-manual/language/without-k.lagda.rst
```
