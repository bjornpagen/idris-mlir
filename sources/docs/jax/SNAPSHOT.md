# Snapshot: JAX export and shape-polymorphism documentation

- **Upstream:** `jax-ml/jax` on GitHub (rendered at https://docs.jax.dev/en/latest/,
  the successor of `jax.readthedocs.io`).
- **Revision:** `main` at `40a35abdd67b2298decb7d14e89adf4d120f1902` (committed
  2026-10-10T00:28:37Z UTC; `git ls-remote https://github.com/jax-ml/jax.git HEAD`).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/jax-ml/jax/40a35abdd67b2298decb7d14e89adf4d120f1902/<path>`
  (HTTP 200 each).
- **Paths:** relative to the repository root (so `docs/501/shape-polymorphism.md`).
- **Files:** 2.
- **Licence:** Apache-2.0 (the repository's `LICENSE`, which covers its `docs/` tree; not
  copied here, fetch it from the same base).
- **Threads:** G (topic: Array languages and typed array programming / shapes).

**What is here and why.**

- `docs/501/shape-polymorphism.md` — the shape-polymorphism page (`jax-501-shape-poly`):
  dimension variables, symbolic dimension expressions, the partial decision procedure for
  comparisons, user constraints, scopes, and the shape assertions checked at compile time.
  The repository also holds an older copy at `docs/export/shape_poly.md`, marked
  `nosearch: true` and differing only in wording; the `501` page is the current one and the
  only one taken.
- `docs/501/export.md` — the export page: the serialized StableHLO calling convention,
  where dimension variables become `i32`/`i64` scalar arguments of the inner function and
  `@shape_assertion` custom calls check the shape constraints, and device-polymorphic
  (sharding) export.

The implementation of the symbolic dimension expressions and their decision procedure is
in `code/jax/` (same revision).

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `docs/501/shape-polymorphism.md` | 26,592 | `46a9a8351c911de206fa654902260c3cca6d4c6d3a92afc5fd00b945e0d56ebc` |
| `docs/501/export.md` | 37,420 | `fbf0ed77349a4683889d3868741cddd08f63cd4f71ff5f11c353d8885689b5ae` |

**How to fetch more.** `curl -L --fail -o <file> https://raw.githubusercontent.com/jax-ml/jax/40a35abdd67b2298decb7d14e89adf4d120f1902/<path>`;
the tree is listed by
`https://api.github.com/repos/jax-ml/jax/git/trees/40a35abdd67b2298decb7d14e89adf4d120f1902?recursive=1`.
Other relevant pages at this revision: `docs/201/sharding.md`, `docs/301/sharding-ad.md`.
