# Snapshot: GHC wiki, Data Parallel Haskell pages

- **Upstream:** the GHC GitLab wiki, `https://gitlab.haskell.org/ghc/ghc/-/wikis/data-parallel`
  and its sub-pages (the developer-level DPH documentation, migrated from the old Trac wiki).
- **Revision:** none recorded: live wiki pages, fetched as Markdown source with the `.md` suffix.
  The front page's status reads: "Work on the DPH project stopped around 2010 at which point the
  implementation began to bit-rot. In June 2018 the implementation was removed from the GHC source
  tree." `data-parallel-benchmark-status.md` is dated "3nd December 2010".
- **Fetched:** 2026-10-09, from `https://gitlab.haskell.org/ghc/ghc/-/wikis/<slug>.md` (HTTP 200).
- **Paths:** flat, human-readable names as in `docs/ghc/`: the wiki slug with `/` replaced by `-`
  (so `data-parallel/replicate` is `data-parallel-replicate.md`).
- **Files:** 15.
- **Licence:** GHC wiki content, no licence stated (verify).
- **Topic:** Flattened data: packed, columnar and nested layouts (cluster `flattening`).

| File | Slug | Why |
| --- | --- | --- |
| `data-parallel.md` | `data-parallel` | index and the project's final status |
| `data-parallel-benchmark-status.md` | `data-parallel/benchmark-status` | the December 2010 benchmark status: SMVM "1000x slower than the C version", OOM; Barnes-Hut "fusion doesn't work"; QuickSort does not compile (SpecConstr loop); QuickHull 6× slower than `Data.Vector` |
| `data-parallel-replicate.md` | `data-parallel/replicate` | "Preventing space blow-up due to replicate": smvm, `treeLookup`'s exponential space, the plan that became the virtual-segment representation |
| `data-parallel-design.md`, `data-parallel-library.md` | `data-parallel/design`, `.../library` | high-level design and package structure |
| `data-parallel-vectorisation.md`, `data-parallel-closure-conversion.md` | `.../vectorisation`, `.../closure-conversion` | the (out of date) plans for vectorisation on top of closure conversion |
| `data-parallel-optimisation.md` | `data-parallel/optimisation` | "Optimisation, and problems therewith" |
| `data-parallel-regular.md` | `data-parallel/regular` | the plan for regular multi-dimensional arrays (the Repa line) |
| `data-parallel-vect-pragma.md` | `data-parallel/vect-pragma` | the `VECTORISE` pragma |
| `data-parallel-desugaring.md` | `data-parallel/desugaring` | array comprehension desugaring |
| `data-parallel-example.md`, `data-parallel-smp.md`, `data-parallel-related.md`, `data-parallel-work-plan.md` | `.../example`, `.../smp`, `.../related`, `.../work-plan` | by-example introduction, shared-memory execution, related work, the old work plan |

**Not taken.** `data-parallel/repositories`, `data-parallel/dec2010-release`,
`data-parallel/benchmarks` (2007), `data-parallel/live-fusion`; the user-level HaskellWiki page.

## File manifest

```
SHA-256                                                                bytes  path
73753279975c878f7ecf71af438c325e784effb633dabb44f1134858ea5b232f      19455  data-parallel-benchmark-status.md
0107a7bb71f050b73cfc5cdad8eb1611cea1e0b3de1bf918cf538c1b398c4ea3       7032  data-parallel-closure-conversion.md
0dfb4272b82e9b89bfa6249a897a05fbee3a51cb201c4b5e725ac28490295207       7165  data-parallel-design.md
9cb4d8a8784b5c6bb3533fad3c4ff1205aacc9bf690f9dc1abd53a1f8f9aeed7       3301  data-parallel-desugaring.md
472931f48d689837609ab6fbcea66d418391b81d83349bd65dfef72b08e73df9       2439  data-parallel-example.md
76808cb6bf774d71b2f07b535bba87db1aa689b16163c689ef5e25f7fc9f417e       4002  data-parallel-library.md
c06b586fdcfef4736face105012ff3925bcc956cebc40db049463e3c0a24826b       8974  data-parallel-optimisation.md
200181332bc7f05b4e700fc7b4137c65d2117bfa0b5b403de8d8f7a3c253e6b5      27027  data-parallel-regular.md
1d9e141df89ea7108770f947830684c624166814349a2cb810a31b8190c1c6e6       2960  data-parallel-related.md
7b715d8fa6e14e8036487828aacf94de201709619d88801c83ce5e0f2d0a97df      26244  data-parallel-replicate.md
7d15835670b056ef70fd6876cb03f26b487943c1a146bc81a743dff37fc2951c       4056  data-parallel-smp.md
ffb77d9b7f4e3e78758e05da9de8f54c7baefd9cbfaec600a905b1f8225acb6f      10523  data-parallel-vect-pragma.md
34cdb4239c61ed17d5032489e1258a63243d51a3d507c519a201cbeffabf4e73       8236  data-parallel-vectorisation.md
6fa5d65a100e07fc3c2db96fee404e211ecd47117b6a48db711fcd9b99608bd2      10396  data-parallel-work-plan.md
ccfc8bdffb809389f72fbfb15f503057770e35cf999d4cec8a2037b5ed4c73ba       2297  data-parallel.md
```
