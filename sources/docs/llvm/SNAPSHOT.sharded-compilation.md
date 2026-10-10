# Snapshot addendum: clang ThinLTO documentation (merge into `docs/llvm/SNAPSHOT.md`)

This adds 1 file to the existing `docs/llvm/` snapshot; it duplicates none of its 11. Merge
this section into `docs/llvm/SNAPSHOT.md` (and the file count, 11 to 12) when the library is
next consolidated; the snapshot's upstream, revision and licence are unchanged.

- **Upstream:** `llvm/llvm-project`, the `clang/` component.
- **Revision:** llvm main at commit `7208ba24ca2894729cd394475a00d2a7b605e642`, the
  repository's LLVM pin, the same revision as the rest of this snapshot.
- **Fetched:** 2026-10-10, from
  `https://raw.githubusercontent.com/llvm/llvm-project/7208ba24ca2894729cd394475a00d2a7b605e642/clang/docs/ThinLTO.md`
  (HTTP 200). Its git blob hash, `4487b348c0e92d63ce4d288cc60b7c866bb10ed8`, equals
  `git -C .toolchain/llvm-project rev-parse 7208ba24…:clang/docs/ThinLTO.md` in the
  bootstrap's clone.
- **Path:** `clang/docs/ThinLTO.md`, relative to the `llvm-project/` root. The rest of this
  snapshot is relative to `llvm-project/llvm/`; a `clang/` file has no path under that root,
  so this one file keeps its `llvm-project/` path.
- **Files added:** 1.
- **Licence:** Apache-2.0 WITH LLVM-exception.
- **Threads:** sharded-compilation (topic: Sharded and incremental compilation).

**What was taken and why.** Clang's ThinLTO user documentation: the summary-based design
(compile-phase summaries, a thin link, parallel backends), backend parallelism controls,
the incremental cache and its pruning policy, and Integrated Distributed ThinLTO (DTLTO). **Correction:** the pass asked for
`clang/docs/ThinLTO.rst`; at this revision that path is 404, and the page is
`clang/docs/ThinLTO.md` (converted to Markdown, like the five `docs/llvm/` files noted in
`SNAPSHOT.md`). The rendered page is https://clang.llvm.org/docs/ThinLTO.html.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `clang/docs/ThinLTO.md` | 10,913 | `54c5b10e700a26b80c89995927d425be930c7fb5aa169352ef11f6a5e99d1d6e` |

**How to fetch more.** `git -C .toolchain/llvm-project cat-file blob 7208ba24ca2894729cd394475a00d2a7b605e642:clang/docs/<file>`,
or the raw URL above with another path. `clang/docs/LTOVisibility.md` is the other LTO page
at this revision.

## File manifest

The file this addendum adds: 1 file, 10,913 bytes. Computed 2026-10-10; check with
`shasum -a 256 <path>` from `docs/llvm/`.

```
SHA-256                                                           bytes  path
54c5b10e700a26b80c89995927d425be930c7fb5aa169352ef11f6a5e99d1d6e      10913  clang/docs/ThinLTO.md
```
