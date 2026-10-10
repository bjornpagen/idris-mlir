# Snapshot: StructArrays.jl (docs and core source)

- **Upstream:** `JuliaArrays/StructArrays.jl` on GitHub.
- **Revision:** tag `v0.7.3`, commit `4a1e271029b3c562bcff5056f1a861a24a76eb3e` (annotated tag
  object `fc32be68bd819424987b519608ea9dc5e48e965c`; `master` was at
  `54d754578858e0d37e1d7b54c0455fce2fada1df` on 2026-10-09).
- **Fetched:** 2026-10-09, from
  `https://raw.githubusercontent.com/JuliaArrays/StructArrays.jl/4a1e271029b3c562bcff5056f1a861a24a76eb3e/<path>`;
  the file list was chosen from the tree at that commit.
- **Paths:** relative to the repository root (so `src/structarray.jl`, `docs/src/index.md`). The
  documentation is kept here with the code, at its repository paths, rather than as a separate
  `docs/` snapshot, because both come from the one repository at one revision.
- **Files:** 15 (plus this file).
- **Licence:** MIT "Expat" (`LICENSE.md`, "Copyright (c) 2018: Pietro Vertechi").
- **Topic:** Flattened data: packed, columnar and nested layouts.
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `docs/src/index.md` | `StructArray`: an `AbstractArray` of structs stored as one array per field, element structs built on `getindex`; construction from field arrays (a view) or from an array of structs (a copy); `LazyRow`; `replace_storage` (e.g. GPU arrays) |
| `docs/src/advanced.md` | custom layouts: overloading `staticschema`, `component` and `createinstance`; mutate-or-widen accumulation (`append!!`) |
| `docs/src/counterintuitive.md` | what a view of materialized elements means for mutation |
| `docs/src/examples.md`, `docs/src/reference.md` | examples and the API list |
| `src/interface.jl` | the three-function layout interface and its generic defaults (the schema of `T` is its field names and types) |
| `src/structarray.jl` | the `StructArray{T,N,C,I}` type, constructors, the recursive `unwrap` predicate, `getindex`/`setindex!`, `similar` |
| `src/utils.jl` | `buildfromschema`, `map_params`, the generated per-field loops (`foreachfield`) that recurse into nested `StructArray` columns |
| `src/collect.jl` | collecting an iterator into a `StructArray`, widening a column's element type when a new element does not fit |
| `src/lazy.jl`, `src/constructionbase.jl`, `src/StructArrays.jl` | lazy rows, construction without constructors, the module |
| `LICENSE.md`, `README.md`, `Project.toml` | licence, summary, version |

Not taken: `src/sort.jl`, `src/tables.jl`, `ext/` (GPU, StaticArrays, SparseArrays, LinearAlgebra
extensions), `test/`, `docs/make.jl`.

## File manifest

Every stored file except this one: 15 files, 69,523 bytes in all. Computed 2026-10-09 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
ad435e33539a46b6ca0ef92c0311d18f8b6b08629c483aa1ed1fdd5c0e1a8664       1170  LICENSE.md
b9b3d659d2fc4a8269f67466dc7f07ad29bea2c018619e46f61770a3a27c8a84       2239  Project.toml
8c0531177021b1a7a0b1fd86319ef9c18f4fd6b3de627d0f65bfabfc3873eedc        729  README.md
b3f1d12ed1b53db22124bfa1698ca6906efeb5c39b0c081b2fcefac1e5389e54       4614  docs/src/advanced.md
56dbe131f65e1d58dee82eab3ac9cab4e041074be5a00f7e3993583c71cde2ca       5764  docs/src/counterintuitive.md
f0549c13685d3cbcc584dc149692a6f78ba0f56a9ef2e4597f09faca647b0a69       2138  docs/src/examples.md
54e0d01b54df448b3db9d7632745d10033bfa1f251365c375d355e80855804f8       6782  docs/src/index.md
6bf4ddb9936e1d5579f193b9a5e8a60d4227ac7a87329ef29a30f4e364f7ffca        787  docs/src/reference.md
1bf61ca388275fbf2d22d7d703100abeff0664850473cb278b8e4efae5fd6b1d       1282  src/StructArrays.jl
240bfd7d6108af5819a525db964b10c0f9f32f5d291864c6edf4533eaa883fcc       5923  src/collect.jl
fc7da81d15d81157ea69e36226109696d1a3f05c3ce32c6cfd7940839b2eec4a       1063  src/constructionbase.jl
1eff6389dff861ebcc96b87f52a01e56dd59f1738ff1c74b2924a6c27112cb1a       2049  src/interface.jl
97c2cd3be0e3cbd9bd727b4cdec4f434aec1308caeec336d7fd5147889f3a03c       3357  src/lazy.jl
19e0a665aea782113d145f9a8e483a615de797199dd5a012ff7cbec929a22fac      24074  src/structarray.jl
ee3ec6cf5e3230efcf6f98cb88e39a4d1bda8689d824fa5f58450dc6bb4dff66       7552  src/utils.jl
```
