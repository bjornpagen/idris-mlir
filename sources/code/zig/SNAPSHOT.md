# Snapshot: Zig MultiArrayList and the compiler's flat IRs

- **Upstream:** `ziglang/zig` on GitHub.
- **Revision:** tag `0.15.2`, commit `e4cbd752c8c05f131051f8c873cff7823177d7d3` (annotated tag
  object `3eac10ac2933d96a71a90a1424659238169d5f28`; `master` was at
  `738d2be9d6b6ef3ff3559130c05159ef53336224` on 2026-10-09).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/ziglang/zig/e4cbd752c8c05f131051f8c873cff7823177d7d3/<path>`;
  the file list was chosen from the tree at that commit.
- **Paths:** relative to the repository root (so `lib/std/multi_array_list.zig`).
- **Files:** 5 (plus this file).
- **Licence:** MIT (Expat) (`LICENSE`, "Copyright (c) Zig contributors").
- **Topic:** Flattened data: packed, columnar and nested layouts.
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `lib/std/multi_array_list.zig` | `std.MultiArrayList(T)`: a structure-of-arrays derived at compile time from a struct type (one array per field) or a tagged union (a `tags` array and an array of the untagged union); one allocation, field arrays ordered by alignment, descending |
| `lib/std/zig/Ast.zig` | the self-hosted compiler's syntax tree as data built on it: `tokens` and `nodes` are `MultiArrayList`s, a node is `{tag: u8, main_token: u32, data: 8-byte union}`, children are `u32` indices, and what does not fit goes in `extra_data: []u32`, decoded by `extraData(index, T)` from the field list of `T` |
| `lib/std/zig/Zir.zig` | the untyped IR in the same style (`instructions: MultiArrayList(Inst).Slice`, `string_bytes`, `extra`), written to and read from cache files as these arrays with a `Header` of their lengths |
| `src/InternPool.zig` | the typed compiler's hash-consing store: every type and value is an `Index` (`enum(u32)`), its flat form an `Item {tag, data: u32}` with `extra`/`limbs` arrays, its rich form a `Key` union; interning maps a `Key` to its one `Index` (sharded, per-thread lists), so equality of interned types and values is equality of indices |
| `LICENSE` | licence |

Not taken: `lib/std/zig/AstGen.zig` (568 KB), `src/Air.zig`, `src/Sema.zig`, `lib/std/meta.zig`.
The tests of `MultiArrayList` (from line 650 of the stored file) are part of it.

**How to fetch more.**

```bash
rev=e4cbd752c8c05f131051f8c873cff7823177d7d3
p=src/Air.zig
mkdir -p "code/zig/$(dirname $p)"
curl -sL --fail -o "code/zig/$p" "https://raw.githubusercontent.com/ziglang/zig/$rev/$p"
```

## File manifest

Every stored file except this one: 5 files, 909,393 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
5c537d6853e005298a285d508cff9ac7192cea23576c840d485b2b586a7ff177       1080  LICENSE
7e755ded94d6c31487185e903b637b5285aee81c2e874c6a8312a79ea17995e3      43556  lib/std/multi_array_list.zig
6f7078dde1517b052a97d7c1e0348f163e016a8a5ba12d7e572980baec9356ee     148759  lib/std/zig/Ast.zig
6787a258b3c1f6fd530cf15b571c98e1d31d0c42e95012a481ae38c8f000e4a8     204779  lib/std/zig/Zir.zig
5b7572236aa12f48d2762e2aa434d28661c8669311befccc4057200e1bcdcb6a     511219  src/InternPool.zig
```
