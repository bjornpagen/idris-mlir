# Snapshot: GCC link-time optimization, partitioning and options

- **Upstream:** `gcc-mirror/gcc` on GitHub, the read-only mirror of
  `gcc.gnu.org/git/gcc.git`.
- **Revision:** `master` (= `trunk`) at `575b8ec6ec455504622d9ad3ac7a8c555c5bcedf` (committed
  2026-10-10T20:28:23Z; `git ls-remote https://github.com/gcc-mirror/gcc.git HEAD`).
- **Fetched:** 2026-10-10, from
  `https://raw.githubusercontent.com/gcc-mirror/gcc/575b8ec6ec455504622d9ad3ac7a8c555c5bcedf/<path>`
  (HTTP 200 each).
- **Paths:** relative to the repository root (so `gcc/lto/lto-partition.cc`).
- **Files:** 2 (one whole file, one excerpt).
- **Licence:** `gcc/lto/lto-partition.cc` GPL-3.0-or-later (its header); `gcc/doc/invoke.texi`
  GFDL-1.3-or-later with Invariant Sections ("GNU General Public License", "Funding Free
  Software") and Front- and Back-Cover Texts (its header). Study only; never copied into this
  repository's code.
- **Threads:** sharded-compilation (topic: Sharded and incremental compilation).

**What is here and why.**

- `gcc/lto/lto-partition.cc`, whole: WHOPR's partitioning of the symbol table for the
  LTRANS stage (`lto_1_to_1_map`, `lto_max_map`, `lto_cache_map`, `lto_balanced_map`,
  `lto_locality_map`), and the renaming and promotion of statics that cross partitions
  (`privatize_symbol_name`, `promote_symbol`, `rename_statics`,
  `lto_promote_cross_file_statics`).
- `gcc/doc/invoke.texi.lto-excerpt`: lines 16003–16343 of `gcc/doc/invoke.texi`, in the
  Optimize Options node, from `@opindex flto` to the end of the `-ffat-lto-objects` entry:
  `-flto[=n]`, `-flto=jobserver`/`auto`, `-flto-partition=`, `-flto-incremental=`,
  `-flto-incremental-cache-size=`, `-flto-compression-level=`,
  `-flto-toplevel-asm-heuristics`, `-fuse-linker-plugin` and `-ffat-lto-objects`, unchanged.
  The whole file is 1,489,965 bytes (SHA-256
  `d648e988d06fd172d71d7171396073ce920113b3786fc6f145758e9d74411345`, git blob `66d80f17…`);
  only the excerpt is stored. The `.lto-excerpt` suffix marks that the file is not the
  upstream file. The partition-size parameters that `lto-partition.cc` reads
  (`param_lto_partitions`, `param_min_partition_size`, `param_max_partition_size`) are not
  documented in `invoke.texi` at this revision; their definitions (`gcc/params.opt`) were not
  taken.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `gcc/lto/lto-partition.cc` | 63,996 | `5c6035aba707312281ddd907c2321199ecf46cdf581a622dfab112f63478dcca` |
| `gcc/doc/invoke.texi.lto-excerpt` | 16,622 | `2d5ef59c7222ee680436f8889248d5bcdc018253e3837339fde5e1eff8359e69` |

**How to fetch more.** `curl -L --fail -o <file> https://raw.githubusercontent.com/gcc-mirror/gcc/575b8ec6ec455504622d9ad3ac7a8c555c5bcedf/<path>`;
the excerpt is reproduced by `sed -n 16003,16343p gcc/doc/invoke.texi`. Related files at
this revision: `gcc/lto/lto.cc` (the WPA and LTRANS driver), `gcc/lto-wrapper.cc`,
`gcc/params.opt`, `gcc/doc/lto.texi` (the LTO internals chapter).

## File manifest

Every stored file except this one: 2 files, 80,618 bytes in all. Computed 2026-10-10; check
with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
2d5ef59c7222ee680436f8889248d5bcdc018253e3837339fde5e1eff8359e69      16622  gcc/doc/invoke.texi.lto-excerpt
5c6035aba707312281ddd907c2321199ecf46cdf581a622dfab112f63478dcca      63996  gcc/lto/lto-partition.cc
```
