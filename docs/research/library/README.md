# `docs/research/sources/` — first-principles optimization source corpus

This folder holds the **non-paper primary sources** for the first-principles optimization
study: snapshots of official documentation, selected pinned source excerpts, small pointer
files for large trees that are intentionally not vendored, authorized open-access paper
copies, and a harvested/de-duplicated BibTeX bibliography. Papers stored as raw LaTeX/PDF
source live in the sibling `docs/research/papers/` tree and are owned by a different phase.

> **The written report, `docs/research/first-principles-optimization.md`, is DEFERRED to a
> later pass and is not part of this tree.** This pass is **sources-only**: it collects and
> indexes the material the report will reason from, and records where that material came
> from. `handoff.md` is the entry point for the next pass: it maps each report thread to the
> exact local paths that serve it and lists what the sources cannot settle.

## Layout

```
docs/research/sources/
├── README.md            this file
├── ACCESS.md            reachability matrix, pins, resolved URLs, exact fetch commands
├── MANIFEST.md          master inventory of every target source and its status
├── oa-locations.md      open-access acquisition record (DOI-only + previously-unresolved rows)
├── handoff.md           thread -> source map and "what the report still needs"
├── bibliography.bib     harvested + de-duplicated BibTeX from the paper corpus (642 entries)
├── docs/                official documentation snapshots (presentational prose)
│   ├── mlir/            MLIR docs at llvmorg-23.1.2
│   ├── llvm/            selected LLVM docs at llvmorg-23.1.2
│   ├── idris2/          Idris 2 docs at the submodule pin
│   ├── ghc/             GHC commentary wiki (raw .md) + selected users-guide pages
│   ├── mlton/           selected MLton guide pages
│   ├── tinygrad/        tinygrad docs + README
│   └── ssa-book/        SSA-based Compiler Design (free PDF)
├── code/                selected pinned source excerpts
│   ├── mlir/            headers/TableGen interfaces at llvmorg-23.1.2
│   ├── idris2/          Core/Compiler/TTImp sources at the submodule pin
│   ├── tinygrad/        Thread A modules + the BEAM search module
│   └── mlton/           closure-convert / SSA / RSSA pass sources
├── pointers/            small files for large trees not vendored
│   ├── ghc.md
│   ├── mlir-lib-trees.md
│   └── ssa-book.md
└── oa-papers/           authorized open-access copies of link-only papers
    └── <shortname>/     PDF/PS/TeX plus a per-folder README.md with provenance
```

### Path conventions

Writes preserve the source repository's own relative paths, but each snapshot is rooted at
the *component* level to avoid `component/component/` duplication:

- `docs/mlir/<path>` is relative to `llvm-project/mlir/` (so `docs/mlir/docs/...`,
  `docs/mlir/include/mlir/...`).
- `docs/llvm/<path>` is relative to `llvm-project/llvm/` (so `docs/llvm/docs/...`).
- `code/mlir/<path>` is likewise relative to `llvm-project/mlir/`.
- `docs/idris2/<path>` and `code/idris2/<path>` are relative to the `Idris2/` repo root
  (so `docs/idris2/docs/source/...`, `code/idris2/src/Core/...`).
- `docs/mlton/<path>`, `code/mlton/<path>`, `docs/tinygrad/<path>` and
  `code/tinygrad/<path>` are relative to their repo roots
  (so `code/mlton/mlton/ssa/contify.fun`, `code/tinygrad/tinygrad/uop/ops.py`).
- GHC and the SSA book use flat, human-readable names under `docs/ghc/` and
  `docs/ssa-book/`.

## Pins

Use these exact revisions for every fetch (they are also recorded in `ACCESS.md` §2):

| Component | Pin | Resolved commit |
| --- | --- | --- |
| LLVM / MLIR | tag `llvmorg-23.1.2` | `2d56740342c3bd86a7525fb4c147252757589e30` |
| Idris 2 (submodule) | pinned commit `1c630e67` | `1c630e67c386629a0fbbc6b78a59176fde7f0a76` |
| tinygrad | `master` | `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a` |
| MLton | `master` | `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37` |
| GHC | not vendored (live docs) | pointer only — see `pointers/ghc.md` |
| SSA book | Wayback snapshot `20210621194509` | see `docs/ssa-book/` and `pointers/ssa-book.md` |

Raw bases: `https://raw.githubusercontent.com/<repo>/<pin>/<path>`.

## How to use this tree

1. Read `MANIFEST.md` for the inventory and the `stored` / `pointer` / `unresolved` status
   of each row; `unresolved` rows carry a reason.
2. Read `ACCESS.md` for the reachability matrix, the pin table, and the exact, reproducible
   fetch commands.
3. Read the relevant snapshot under `docs/` for official prose, and the excerpts under
   `code/` for the exact interfaces/implementations the report must reason about.
4. When a row is marked `pointer`, the large tree is deliberately not vendored; the pointer
   file names the pin and the exact URL pattern to fetch individual files on demand.
5. `oa-locations.md` records which link-only papers have an authorized open-access copy, the
   direct URL, host/version/license, and the API that surfaced it. The copies themselves are
   under `oa-papers/<shortname>/`, each with its own `README.md`.
6. `bibliography.bib` aggregates the `.bib` files found in `docs/research/papers/` (read-only)
   and entries added to cover papers catalogued in `papers/INDEX.md`. It is de-duplicated by
   citation key (case-insensitive), DOI, and title: **680 harvested entries → 596 unique →
   642 total** after adding 46 INDEX-coverage entries. If the paper corpus grows, re-harvest
   rather than editing here.

## Corrections recorded in this pass

These are deliberate corrections to the plan/brief and to `ACCESS.md`; the report pass
should trust these, not the earlier rows.

- **`third_party/Idris2` is NOT checked out in this working tree.** The submodule is empty,
  so the Idris 2 doc and code snapshots were fetched from the pinned **raw GitHub URLs**
  (`https://raw.githubusercontent.com/idris-lang/Idris2/1c630e67.../...`) rather than read
  from the local submodule. Anyone who expects to read `third_party/Idris2/src/...` locally
  must first run `git submodule update --init`; that does not change this corpus.
- **Erasure is not `Compiler/Erase.idr`.** There is no such file. Erasure lives in
  `code/idris2/src/Core/LinearCheck.idr` (multiplicity/erasure inference with `Erased`
  nodes) plus the `eraseArgs` / `safeErase` fields of `GlobalDef` in
  `code/idris2/src/Core/Context/Context.idr`.
- **Idris 2 case optimization is `src/Compiler/CaseOpts.idr`** (not `CaseOpt.idr`).
- **`TTImp` is `src/TTImp/**`** (not `src/Core/TTImp/**`).
- **MLton RSSA lives under `mlton/backend/`** (e.g. `mlton/backend/ssa2-to-rssa.fun`,
  `mlton/backend/rssa.fun`, `mlton/backend/packed-representation.fun`), not a `mlton/rssa/`
  directory.
- **`RewriterBase` has no separate header** at this pin: it is declared in
  `code/mlir/include/mlir/IR/PatternMatch.h`, which is vendored.
- **tinygrad's BEAM search is `tinygrad/codegen/opt/search.py`** (located from the pinned
  `tinygrad/codegen/{opt,late,decomp}` trees), not guessed.
- **GHC has no `inliner` or `unarisation` commentary pages** (HTTP 404 at fetch time). The
  nearest captured material is `docs/ghc/commentary-compiler-core-to-core-pipeline.md`,
  `...-opt-ordering.md`, `...-code-gen.md`, and `...-backends.md`.
- Several MLIR dialects named in the plan (`arith`, `cf`, `index`, `ptr`, `scf`, `ub`,
  `pdl`) have **no standalone `.md` file** in `mlir/docs/Dialects/` at `llvmorg-23.1.2`;
  their docs are generated from ODS/TableGen and are covered by the full `mlir/docs/**`
  snapshot.
- **ScienceDirect returned HTTP 403, not 200.** `ACCESS.md` §3b labelled `taha-2000` and
  `wadler-1990` "ScienceDirect PDF (verified 200)"; live probes show they are not
  scriptable. Both are recorded link-only in `papers/INDEX.md` and `oa-locations.md`.
- The `ssabook.gforge.inria.fr` host is dead; the PDF was retrieved via the Wayback Machine.

## Known holes in this corpus

- The empty `third_party/Idris2` submodule (see above).
- The `docs-ghc-unarisation` gap (no such GHC commentary page).
- The dead `ssabook.gforge.inria.fr` (Wayback substitution).
- `dl.acm.org`, `sciencedirect.com`, and some green-OA repositories (Edinburgh, St Andrews,
  ETH, ANU) block or fail scripted fetches; the affected papers are enumerated in
  `oa-locations.md` §3 with the action each still needs.
- HAL serves an Anubis bot challenge to scripted clients; it was not solved/evaded.

## Deferred

- `docs/research/first-principles-optimization.md` — the report itself (later pass).
- Pointer files for large **non**-documentation/code sources owned by other threads
  (memory/GC, prior-art compilers, defunctionalisation, etc.) are not written here; they
  belong to the phases that own those threads.
