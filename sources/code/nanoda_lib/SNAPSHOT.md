# Snapshot: nanoda_lib (a Lean 4 kernel checker in Rust)

- **Upstream:** `ammkrn/nanoda_lib` on GitHub (https://github.com/ammkrn/nanoda_lib), crate
  version 0.4.19 (`Cargo.toml`).
- **Revision:** default branch at `3a2407216ee84a75f9e1aead6803d0578be06ae7`, the HEAD resolved
  with `git ls-remote` on 2026-10-09.
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/ammkrn/nanoda_lib/3a2407216ee84a75f9e1aead6803d0578be06ae7/<path>`.
- **Paths:** relative to the repository root.
- **Licence:** Apache-2.0 (`LICENSE`; `Cargo.toml` `license = "Apache-2.0"`).
- **Threads:** elaborators (Fast dependent type checking and elaboration).

**What is here and why.**
- `src/util.rs`: the hash-consed DAG (`IndexSet` arenas, 32-bit `Ptr` with a bit choosing the
  persistent export-file DAG or the per-check DAG, so pointer equality is structural
  equality), cached `num_loose_bvars`/`has_fvars`/hash per node, the `ExprCache`
  (instantiate, abstract and level-substitution caches keyed by pointer and offset), the
  thread-count option.
- `src/tc.rs`: inference, whnf, lazy delta, `def_eq` with the `eq_cache` (sorted pointer
  pairs) and `defeq_fail_cache`.
- `src/expr.rs`, `src/union_find.rs` (present but not referenced by `tc.rs` at this
  revision), `src/unique_hasher.rs`, `src/main.rs`, `Cargo.toml`, `README.md`, `LICENSE`.

**Not taken:** `inductive.rs`, `quot.rs`, `parser.rs`, the pretty printer, `level.rs`,
`name.rs`, `env.rs`, the tests. The README gives no benchmark. Nothing was built or run.

## File manifest

Every stored file except this one: 9 files, 161,145 bytes in all.

```
SHA-256                                                               bytes  path
0a17b333776ee3f363ba7a51f47e421dc69f93662d5e131870a9d6d95fa9e5d7        859  Cargo.toml
c8858a5a76440bbca484e134cf7df46385d090dd18b2c58e650f939258802e5b      10141  LICENSE
4442003879ac4ac7d455df1db16e0c5646652e6c9b44451f5d877345b8ff65d2       6517  README.md
7ea1a70e11c7adf1fa2f4be8e8a2f10f7fcd6441d73117fdc206a55ac2d76e3c      33675  src/expr.rs
245ceaef34e8925cacaa3c5b99ce096a8c744710ce1f9184423e5a0333e8b35a       2524  src/main.rs
59d8a7d5b4481a9038031fabe819d3e2384f2dd68eb343805fa946e3499b3fda      58990  src/tc.rs
2728ab1d2dcd84489a6bb4fa984af22c40236bf813205e42a1c55ca825bdc757       5571  src/union_find.rs
e457ec69139dee08c4f21f3fee5bc9a2cfe6bb14e5d5bd217ca35d6a368daea5        881  src/unique_hasher.rs
57b2022b743ad5f31cc08d18dfa5092f2246b6a57b2b49770deb0f53cd3e7561      41987  src/util.rs
```
