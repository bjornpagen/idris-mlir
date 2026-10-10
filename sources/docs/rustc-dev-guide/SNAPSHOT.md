# Snapshot: rustc-dev-guide, queries, incremental compilation and monomorphization

- **Upstream:** `rust-lang/rustc-dev-guide` on GitHub (rendered at
  https://rustc-dev-guide.rust-lang.org/).
- **Revision:** `main` at `20a4fdd79ed91d0e04f7d48919423d799e3375f0` (committed
  2026-10-10T14:56:55Z; `git ls-remote https://github.com/rust-lang/rustc-dev-guide.git HEAD`).
- **Fetched:** 2026-10-10, from
  `https://raw.githubusercontent.com/rust-lang/rustc-dev-guide/20a4fdd79ed91d0e04f7d48919423d799e3375f0/<path>`
  (HTTP 200 each). Each file's git blob hash matches the tree listing at the pin
  (`https://api.github.com/repos/rust-lang/rustc-dev-guide/git/trees/20a4fdd7…?recursive=1`).
- **Paths:** relative to the repository root (so `src/query.md`). All four paths are the ones
  named for this pass; none had moved.
- **Files:** 4.
- **Licence:** MIT OR Apache-2.0 (the repository's `LICENSE-MIT` and `LICENSE-APACHE`, not
  copied here; byte-identical copies, blob hashes `31aa7938…` and `16fe87b0…`, are in
  `docs/rustc-parallel/rustc-dev-guide/`).
- **Threads:** sharded-compilation (topic: Sharded and incremental compilation).

**What is here and why.**

- `src/query.md` — queries as demand-driven compilation: invoking a query, providers and
  how they are registered, external crate metadata, adding a query.
- `src/queries/incremental-compilation.md` — the basic algorithm: try-mark-green and the
  query DAG.
- `src/queries/incremental-compilation-in-detail.md` — the red-green algorithm, stability
  across sessions, `StableHash` and fingerprints, the old and new `DepGraph`, cache
  promotion, query modifiers, the projection query pattern, and the system's shortcomings.
- `src/backend/monomorph.md` — monomorphization: item collection and codegen-unit (CGU)
  partitioning.

**Why a new snapshot, not an addendum to `docs/rustc-parallel/`.** `docs/rustc-parallel/`
holds `rustc-dev-guide/src/parallel-rustc.md` and one Rust blog post
(`blog.rust-lang.org/content/parallel-rustc/index.md`), committed on 2026-10-09 (`96156233`)
with no `SNAPSHOT.md` and no recorded revision. An addendum adds files "at the same revision"
(README, Conventions), and that revision is unknown; this snapshot has its own pin. Its
`parallel-rustc.md` is byte-identical to the file at this pin (blob `c4e06630…`), so the two
snapshots agree, but the file was not taken again.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `src/query.md` | 16,426 | `6268d59be454472132aa7010f867cf74465693fc28a369ee76bde4288bb1ad89` |
| `src/queries/incremental-compilation.md` | 7,529 | `9a24a66edb18c4136c8e322a2f08e444fec369c690ee9d92e976f742c2d953b5` |
| `src/queries/incremental-compilation-in-detail.md` | 27,785 | `8a975481bb5aff355a1d4b3d89c09c924143d508228bd5907a4d6cd8ffb385d3` |
| `src/backend/monomorph.md` | 3,767 | `2ef8f4ed5d5bb5f9748191274110622550ba354620983986b8a8fbc1308e2947` |

**How to fetch more.** `curl -L --fail -o <file> https://raw.githubusercontent.com/rust-lang/rustc-dev-guide/20a4fdd79ed91d0e04f7d48919423d799e3375f0/<path>`.
Other relevant chapters at this revision: `src/queries/query-evaluation-model-in-detail.md`,
`src/queries/salsa.md`, `src/backend/codegen.md`.

## File manifest

Every stored file except this one: 4 files, 55,507 bytes in all. Computed 2026-10-10; check
with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
2ef8f4ed5d5bb5f9748191274110622550ba354620983986b8a8fbc1308e2947       3767  src/backend/monomorph.md
8a975481bb5aff355a1d4b3d89c09c924143d508228bd5907a4d6cd8ffb385d3      27785  src/queries/incremental-compilation-in-detail.md
9a24a66edb18c4136c8e322a2f08e444fec369c690ee9d92e976f742c2d953b5       7529  src/queries/incremental-compilation.md
6268d59be454472132aa7010f867cf74465693fc28a369ee76bde4288bb1ad89      16426  src/query.md
```
