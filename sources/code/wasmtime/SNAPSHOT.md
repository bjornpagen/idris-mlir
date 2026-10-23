# Snapshot: Cranelift's entity crate, dense IDs and their side tables

- **Upstream:** `bytecodealliance/wasmtime` on GitHub, directory `cranelift/entity/` (the
  `cranelift-entity` crate).
- **Revision:** tag `v50.0.0` (lightweight), commit `ebe5e8df1f4e12c5fc2f5954926881d8d61367d8`
  ("Release Wasmtime 50.0.0", 2026-10-20), the latest Wasmtime release on 2026-10-23.
- **Fetched:** 2026-10-23, from
  `https://raw.githubusercontent.com/bytecodealliance/wasmtime/ebe5e8df1f4e12c5fc2f5954926881d8d61367d8/<path>`;
  every file under `cranelift/entity/` at that commit.
- **Paths:** relative to the repository root (so `cranelift/entity/src/map.rs`).
- **Files:** 13 (plus this file).
- **Licence:** Apache-2.0 WITH LLVM-exception (`cranelift/entity/LICENSE`, byte-identical to the
  repository's root `LICENSE`, and `license` in `cranelift/entity/Cargo.toml`).
- **Topic:** Analyses, solvers and dense side tables (P0 audit 5.7, item 13).
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `cranelift/entity/src/lib.rs` | the crate's statement of the design ("array-based data structures using densely numbered entity references as mapping keys"), the `EntityRef` trait and `entity_impl!` |
| `cranelift/entity/src/primary.rs` | `PrimaryMap`: the vector that owns the entities and hands out their references |
| `cranelift/entity/src/map.rs` | `SecondaryMap`: per-entity side information as a plain vector with a default value |
| `cranelift/entity/src/set.rs` | `EntitySet`: a secondary set of entities |
| `cranelift/entity/src/sparse.rs` | `SparseMap`: the sparse representation, for few entities |
| `cranelift/entity/src/list.rs` | `EntityList` and `ListPool`: compact lists of references in a shared pool |
| `cranelift/entity/src/packed_option.rs` | `PackedOption` and `ReservedValue`: an optional reference in the reference's own width |
| `cranelift/entity/src/{boxed_slice,iter,keys}.rs` | the frozen map and the iterators |
| `cranelift/entity/{README.md,Cargo.toml,LICENSE}` | the crate's description, manifest and licence |

**How to fetch more.**

```bash
rev=ebe5e8df1f4e12c5fc2f5954926881d8d61367d8
p=cranelift/codegen/src/ir/dfg.rs
mkdir -p "code/wasmtime/$(dirname $p)"
curl -sL --fail -o "code/wasmtime/$p" "https://raw.githubusercontent.com/bytecodealliance/wasmtime/$rev/$p"
```

## File manifest

Every stored file except this one: 13 files, 129,810 bytes in all. Computed 2026-10-23 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
31000c9dada080f4cae0af1e66709e9e00370230c26fd7da0c0ecb84997e694e        746  cranelift/entity/Cargo.toml
268872b9816f90fd8e85db5a28d33f8150ebb8dd016653fb39ef1f94f2686bc5      12243  cranelift/entity/LICENSE
96ceffbfd88fb06e3b41aa4d3087cffbbf8441d04eba7ab09662a72ab600a321       2231  cranelift/entity/README.md
f8d0afbb525314d1b41d5aa5ac5885bff59f4d037007d4fae28f2a915c8591d6       7665  cranelift/entity/src/boxed_slice.rs
61fefdc49cafad4cacba5f5a7ad2396a23160642c688a7f0b0734277391847cd       3236  cranelift/entity/src/iter.rs
b8c2fba26dee15bf3d1880bb2b41e8d66fe1428d242ee6d9fd30ee94bbd0407d       1419  cranelift/entity/src/keys.rs
5402267ece61d5c4b2437b30cf130aa16349d95e9bbcd60b09e72e5760173dff      13086  cranelift/entity/src/lib.rs
646eefcba9b4aafde5e243d8a7f4e0f998867d0197d69504a598dbd4c16813a6      33296  cranelift/entity/src/list.rs
0990e011a392d5f2024e80653607cac1bcb35a25cc78d6c5afb8cc7a4e732973      13089  cranelift/entity/src/map.rs
ac190d67bcfc7d64c95344ed63c89d545c8dbd9cf710c5d44aef0adcc5730394       5106  cranelift/entity/src/packed_option.rs
6b1bd9c1ad14c7ba35234e876a4b955f56dc2591645dc38b9bd18ab5f1cd1e60      16239  cranelift/entity/src/primary.rs
60cc38f977d8675a86921eff1085038eca8b17a202a8178d6811d1bed9f87438       8351  cranelift/entity/src/set.rs
783d2354d525c053477d805e582ff2a704ed2044b039a664b0460312714168c7      13103  cranelift/entity/src/sparse.rs
```
