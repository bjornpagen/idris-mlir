# Snapshot: Apache Arrow blog, "Arrow and Parquet" series

- **Upstream:** `apache/arrow-site` on GitHub (rendered at https://arrow.apache.org/blog/).
- **Revision:** `main` at `bf8285bef4296db932fc9a2c81cebef929ee39b4` (2026-10-09).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/apache/arrow-site/bf8285bef4296db932fc9a2c81cebef929ee39b4/<path>`;
  the posts were found in the tree at that commit
  (`https://api.github.com/repos/apache/arrow-site/git/trees/bf8285bef4296db932fc9a2c81cebef929ee39b4?recursive=1`).
- **Paths:** relative to the repository root (so `_posts/2022-10-08-arrow-parquet-encoding-part-2.md`).
- **Files:** 4 (plus this file).
- **Licence:** Apache-2.0 (`LICENSE.txt` from the repository root; each post carries the ASF
  header).
- **Topic:** Flattened data: packed, columnar and nested layouts.
- Nothing was built or run; the files were read only.

**What is here, and why.** The three-part series by the Rust Arrow maintainers (tustvold,
alamb, October 2022) on converting between Arrow's in-memory layout and Parquet's storage
layout, the clearest worked comparison of the two ways to flatten nested optional data:
- `_posts/2022-10-05-arrow-parquet-encoding-part-1.md`: columnar versus record layout; Arrow's
  validity bitmap versus Parquet's definition levels for a nullable primitive column; Arrow is
  O(1) random access, Parquet is not.
- `_posts/2022-10-08-arrow-parquet-encoding-part-2.md`: structs (Arrow: one validity bitmap per
  nullable level; Parquet: definition levels on the leaves only) and lists (Arrow: offsets;
  Parquet: repetition levels, a 0 per row).
- `_posts/2022-10-17-arrow-parquet-encoding-part-3.md`: lists of structs of lists, both
  encodings side by side, and the complications a reader meets.
- `LICENSE.txt`.

Related post not taken: `2022-12-26-querying-parquet-with-millisecond-latency.md`.
The Parquet site's own nested-encoding page points to a Twitter engineering post,
"Dremel made simple with Parquet" (2013); `blog.twitter.com` now redirects to `blog.x.com`,
which returned HTTP 403, and the Wayback availability API returned 429, so it is not stored.

## File manifest

Every stored file except this one: 4 files, 53,640 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30      11358  LICENSE.txt
ea47809781fe20f0ffe4f85a3c4fb9813d7ea507ce5fe2131a7a56c9366ba195       8747  _posts/2022-10-05-arrow-parquet-encoding-part-1.md
989f4e3b66e708be69408e559d5ec263d49bfaf4e7514f5be101c9b5ad64aa29      19689  _posts/2022-10-08-arrow-parquet-encoding-part-2.md
ebf215883913fdd7cbf2cdbf7c676d1c687e2e5eb858fce59a72a6d0c7889d20      13846  _posts/2022-10-17-arrow-parquet-encoding-part-3.md
```
