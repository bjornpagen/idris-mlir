# Research library

The vendored research library of idris-mlir: papers, code and documentation snapshots,
and one bibliography. The material was collected on 2026-09-26 for a first-principles
optimization study and organized in this layout on 2026-09-27 (`docs/plan.md`,
section 9). This file is the record of provenance and licences: where every item came
from, at which revision, under which licence, how to fetch it again, and what is still
missing. [INDEX.md](INDEX.md) lists the papers by topic.

The study's report, `docs/research/first-principles-optimization.md`, was deferred by the
sources pass and never written; this library is the material it was to reason from.

On 2026-10-09 five array-languages passes (`apl-lineage`, `typed-rank`, `dataparallel`,
`dependent-equality`, `mlir-stack`) added the prior art for proposal 0004
(`proposals/0004-typed-apl/README.md`): 42 papers, 6 link-only rows, 19 new snapshots and two
addenda to existing ones. [INDEX.md](INDEX.md) files them under [Array languages and typed
array programming](INDEX.md#array-languages-and-typed-array-programming); this file records
their provenance alongside the rest, in the sections below, each part marked with that date.

- [Layout](#layout)
- [Where the old files went](#where-the-old-files-went)
- [How to use the library](#how-to-use-the-library)
- [Conventions](#conventions)
- [Licences](#licences)
- [Snapshots](#snapshots)
- [Pins](#pins)
- [Access record](#access-record): [reachability](#reachability),
  [identifier resolution](#identifier-resolution),
  [non-paper source URLs](#non-paper-source-urls), [fetch commands](#fetch-commands),
  [array-languages passes (2026-10-09)](#array-languages-passes-2026-10-09)
- [How the papers were collected](#how-the-papers-were-collected)
- [Open-access acquisition](#open-access-acquisition)
- [Papers not stored](#papers-not-stored)
- [Planned sources not collected](#planned-sources-not-collected)
- [Bibliography](#bibliography)
- [Corrections](#corrections)
- [Known holes](#known-holes)
- [Open questions at handoff](#open-questions-at-handoff)

## Layout

```
sources/
├── README.md          this file: provenance, licences, access, pins, gaps
├── INDEX.md           the papers by topic, with the snapshots each topic draws on
├── bibliography.bib   one BibTeX file for the library (697 entries)
├── papers/<author>-<year>-<slug>/
│                      README.md (provenance) plus the TeX source, or the PDF when no
│                      TeX source exists, or a web edition or text extraction when
│                      neither does (93 papers indexed in INDEX.md)
├── code/<project>/    selected source excerpts at a pinned revision, each with SNAPSHOT.md
│   ├── co-dfns/       the Co-dfns APL compiler's passes (AGPL-3.0, study only)
│   ├── dex/           Dex prelude, simplifier, linearization, lowering
│   ├── futhark/       Futhark passes: fusion, flattening, short-circuiting, size types
│   ├── ghc-typelits-natnormalise/  GHC plugin normalising type-level Nat
│   ├── idris2/        Core, Compiler and TTImp sources at the submodule pin, plus the
│   │                  rewrite and with elaboration (addendum)
│   ├── jax/           JAX's symbolic-shape solver
│   ├── lean4/         Lean 4's rewrite, subst and generalize tactics
│   ├── makanin-algo/  Makanin's string-equation solver (Remora's shape unifier)
│   ├── mlir/          headers and TableGen interfaces at the LLVM pin (main 7208ba24),
│   │                  plus the array-stack ODS (addendum)
│   ├── mlton/         closure-convert, SSA and RSSA pass sources
│   ├── remora/        Remora's Redex models and dynamic implementation
│   ├── remorac/       the Remora compiler's type checker and frame elaboration
│   ├── revised-remora/  the revised Remora type system
│   ├── tinygrad/      the Thread A modules and the BEAM search module
│   ├── triton/        Triton's MLIR dialect definitions
│   └── type-nat-solver/  GHC plugin deciding type-level Nat with SMT
└── docs/<project>/    documentation snapshots, each with SNAPSHOT.md
    ├── agda/          Agda manual: with-abstraction, rewriting, without-K
    ├── bqn/           BQN docs: the array model, leading axis, rank, under
    ├── futhark/       Futhark language reference and performance guide
    ├── ghc/           GHC commentary wiki (raw .md) and selected users-guide pages
    ├── idris2/        Idris 2 docs at the submodule pin
    ├── j/             the J Dictionary: rank, verbs, adverbs and conjunctions
    ├── jax/           JAX shape polymorphism and export
    ├── llvm/          selected LLVM docs at the LLVM pin (main 7208ba24)
    ├── mlir/          MLIR docs at the LLVM pin (main 7208ba24)
    ├── mlton/         selected MLton guide pages
    ├── mojo/          Mojo docs on inline MLIR and parameters
    ├── rocq/          Rocq manual: equality, rewriting, ring and micromega
    ├── ssa-book/      SSA-based Compiler Design (free PDF)
    └── tinygrad/      tinygrad docs and README
```

The tree omits nineteen paper folders and six documentation snapshots (`docs/go-scheduler/`,
`docs/idris-effects/`, `docs/rust-rc/`, `docs/seastar/`, `docs/swift-rc/`, `docs/tokio/`)
added on 2026-10-07 (commit `cb65104d`), which this file and [INDEX.md](INDEX.md) do not
record yet (see [Known holes](#known-holes)).

## Where the old files went

Until 2026-09-27 the library was two trees: `docs/research/papers/` (the papers pass) and
`docs/research/sources/` (the sources and open-access passes). Files moved with `git mv`;
duplicates and the four folded Markdown files were removed with `git rm` once their
facts were merged.

| Old path | Now |
| --- | --- |
| `docs/research/papers/<shortname>/` | `papers/<shortname>/` |
| `docs/research/papers/INDEX.md` | [INDEX.md](INDEX.md), rewritten by topic |
| `docs/research/sources/oa-papers/<shortname>/` | `papers/<shortname>/`, merged as described below |
| `docs/research/sources/code/<project>/` | `code/<project>/` |
| `docs/research/sources/docs/<project>/` | `docs/<project>/` |
| `docs/research/sources/pointers/ghc.md` | `docs/ghc/SNAPSHOT.md` |
| `docs/research/sources/pointers/mlir-lib-trees.md` | `code/mlir/SNAPSHOT.md` |
| `docs/research/sources/pointers/ssa-book.md` | `docs/ssa-book/SNAPSHOT.md` |
| `docs/research/sources/bibliography.bib` | [bibliography.bib](bibliography.bib) |
| `docs/research/sources/README.md` | this file |
| `docs/research/sources/ACCESS.md` | this file: [Pins](#pins) and [Access record](#access-record) |
| `docs/research/sources/MANIFEST.md` | [INDEX.md](INDEX.md) (papers and threads), [Snapshots](#snapshots), [Planned sources not collected](#planned-sources-not-collected), [Conventions](#conventions) |
| `docs/research/sources/oa-locations.md` | the paper READMEs, [Open-access acquisition](#open-access-acquisition), [Papers not stored](#papers-not-stored) |
| `docs/research/sources/handoff.md` | [INDEX.md](INDEX.md) (sources, read-first lists and claims per topic), [Known holes](#known-holes), [Open questions at handoff](#open-questions-at-handoff) |

**Merging the two paper trees.** 34 folders came from `papers/` and 32 from
`oa-papers/`; 15 names were in both, so the library has 51 paper folders.
- The 17 new open-access folders moved in whole. Three were renamed to the
  `<author>-<year>-<slug>` form: `fractional-uniqueness` →
  `marshall-2024-fractional-uniqueness`, `wadler-linear-types` → `wadler-1990-linear-types`,
  `huang-yallop-2023-defunctionalization` → `huang-2023-defunctionalization`.
- For the 15 shared names, the two READMEs became one that keeps both passes' records, and
  each file is kept once:
  - byte-identical copies, kept once: `bhat-2024-verifying-peephole` (the open-access copy
    was named `LIPIcs.ITP.2024.9.pdf`), `danvy-2001-defunctionalization`,
    `henriksen-2017-futhark`, `lopes-2015-alive`, `ragankelley-2013-halide`,
    `schkufza-2013-stoke`;
  - the same Cambridge Core download taken twice, 15 minutes apart, identical except for
    the per-download stamp, kept once: `marlow-2006-fast-curry`, `peytonjones-1992-stg`,
    `sorensen-1996-positive-supercompiler`;
  - `pal-2023-ruler`: the two unpacked e-prints were identical except `main.bbl`, which
    only the open-access copy had; it moved in, and the raw e-print archive, which unpacks
    to exactly these files, was not kept a second time;
  - different files (another host or version), both kept, the open-access copy under a
    host-specific name: `adams-2019-halide-learning` (`paper-halide-lang.pdf`),
    `ikarashi-2022-exo` (`paper-submitted.pdf`), `kjolstad-2017-taco`
    (`paper-submitted.pdf`), `leroy-2009-compcert` (`paper-author-site.pdf`),
    `marshall-2022-linearity-uniqueness` (`paper-kent.pdf`).

  Each merged README gives the size and SHA-256 of every copy, including a duplicate that
  was not kept when it was not byte-identical.

## How to use the library

1. Start from [INDEX.md](INDEX.md): the papers by topic, with the snapshots and a
   read-first list for each topic.
2. A paper folder's `README.md` gives its provenance: URL, host, version, licence, fetch
   date, and the API or site that surfaced it.
3. A snapshot's `SNAPSHOT.md` gives its upstream, revision, contents and corrections. What
   is deliberately not vendored has a pointer there that names the pin and the URL pattern
   for fetching single files on demand.
4. This file has the pins, the reachability of every host, the exact fetch commands, and
   what is still missing, with what it would take to obtain it.
5. [bibliography.bib](bibliography.bib) is the one BibTeX file; see [Bibliography](#bibliography).

## Conventions

- **Storage.** Raw LaTeX source is preferred; a PDF (or PostScript) is stored only when no
  TeX source exists. Generated files and anything over 20 MB are skipped. arXiv e-prints
  were unpacked with `tar xzf` and their generated files (`.aux`, `.log`, `.out`, `.blg`,
  `.synctex*`, `.fls`, `.fdb_latexmk`) stripped; a `.bbl` was kept where a `.bib` was
  present and removed otherwise, except Ruler's `main.bbl`, which has no `.bib` to be
  regenerated from. Upstream bundles are otherwise as shipped (for example the submission
  PDFs in `zhang-2023-egglog` and the `formal/` directory of `wu-2026-slotted-egraphs`).
  Where neither TeX nor an open PDF exists, the author's or project's web edition is stored
  as HTML with its stylesheet and images (the Jsoftware APL papers); where the only open PDF
  is over 20 MB, the repository's own text extraction is stored and the PDF recorded as
  link-only (`hsu-2019-data-parallel-compiler`). Build scripts shipped in a bundle
  (`Makefile`, `create_diagram.sh`) are stored as shipped and never run.
- **File manifests.** From 2026-10-09 every new folder records the bytes and SHA-256 of each
  stored file: a paper's `README.md` lists them (the larger TeX bundles and
  `iverson-1962-programming-language` in a "File manifest" section), and each new
  `SNAPSHOT.md` or addendum ends with a "File manifest" section.
- **Paper folders** are `papers/<author>-<year>-<slug>/`: the first author's surname, the
  year, a short slug. Each holds a `README.md` with its provenance.
- **Store once, cross-link.** A source that serves several threads (the manifest marked
  these *(shared)*) is stored once; [INDEX.md](INDEX.md) files it under one topic and names it
  in the other topics' "Also" lines.
- **Snapshot paths.** A snapshot keeps the upstream repository's own relative paths, rooted
  at the component to avoid `component/component/`: `docs/mlir/` and `code/mlir/` are
  relative to `llvm-project/mlir/` (`docs/mlir/docs/...`, `code/mlir/include/mlir/...`);
  `docs/llvm/` to `llvm-project/llvm/` (`docs/llvm/docs/...`); `docs/idris2/` and
  `code/idris2/` to the `Idris2/` repository root (`docs/idris2/docs/source/...`,
  `code/idris2/src/Core/...`); `docs/mlton/`, `code/mlton/`, `docs/tinygrad/` and
  `code/tinygrad/` to their repository roots (`code/mlton/mlton/ssa/contify.fun`,
  `code/tinygrad/tinygrad/uop/ops.py`). GHC and the SSA book use flat, human-readable names
  under `docs/ghc/` and `docs/ssa-book/`. The snapshots of 2026-10-09 are relative to their
  repository roots (`code/futhark/src/Futhark/Passes.hs`, `docs/mojo/Mojo/docs/...`,
  `docs/rocq/doc/sphinx/...`); `docs/j/` is relative to `https://www.jsoftware.com/`
  (`docs/j/help/dictionary/d600n.htm`). The `code/mlir/` addendum adds one file under
  `python/mlir/`, still relative to `llvm-project/mlir/`.
- **Addenda.** Files added to an existing snapshot at the same revision are described in an
  addendum next to its `SNAPSHOT.md` (`code/mlir/SNAPSHOT.addendum.md`,
  `code/idris2/SNAPSHOT.dependent-equality.md`), to be merged into it.
- **Revisions.** Every snapshot records its resolved commit or tag (its `SNAPSHOT.md` and
  [Pins](#pins)); every stored paper records its source URL and fetch date.
- **Statuses.** Papers are `stored`, `link-only` (identifier known, no copy stored) or
  `unresolved` (identifier or copy not located, or no canonical reference chosen; the
  reason is given). Identifiers are `resolved` (canonical ID or URL confirmed by API or DOI
  lookup), `resolved-corrected` (the plan's candidate ID, title or attribution was wrong;
  the corrected value is given) or `unresolved`. The manifest's collection statuses were
  `planned` (identified, to collect), `resolved-id` (identifier confirmed in the access
  record, content not yet fetched), `unresolved` and `skip` (intentionally not collected).
- **Licences.** `unknown–verify` or `verify` means not confirmed from the publisher or the
  repository: confirm before redistributing.

## Licences

**Snapshots.**

| Snapshot | Licence |
| --- | --- |
| `code/mlir/`, `docs/mlir/`, `docs/llvm/` | Apache-2.0 WITH LLVM-exception |
| `code/idris2/`, `docs/idris2/` | BSD-3-Clause (verify) |
| `docs/ghc/` | BSD-3-Clause (verify) |
| `code/mlton/`, `docs/mlton/` | MLton license, HPND-style (verify) |
| `code/tinygrad/`, `docs/tinygrad/` | MIT |
| `docs/ssa-book/` | free book (verify) |
| `code/co-dfns/` | AGPL-3.0-or-later (dual-licensed on request); excerpts for study only, never copied into this repository's code |
| `code/dex/` | BSD-3-Clause |
| `code/futhark/`, `docs/futhark/` | ISC |
| `code/ghc-typelits-natnormalise/` | BSD-2-Clause |
| `code/jax/`, `docs/jax/` | Apache-2.0 |
| `code/lean4/` | Apache-2.0 |
| `code/remorac/` | BSD-3-Clause (NVIDIA) |
| `code/remora/`, `code/revised-remora/`, `code/makanin-algo/` | none stated: no licence file, so all rights reserved by default (verify) |
| `code/triton/` | MIT |
| `code/type-nat-solver/` | BSD-3-Clause |
| `docs/agda/` | MIT-style (Agda `LICENSE`) |
| `docs/bqn/` | ISC |
| `docs/j/` | © Jsoftware Inc., all rights reserved (verify) |
| `docs/mojo/` | Apache-2.0 WITH LLVM-exception (the Modular repository's `LICENSE`) |
| `docs/rocq/` | Open Publication License v1.0 (`doc/LICENSE`; options A and B not elected) |

**Papers**, by the licence recorded for the stored copies (each README has the details):

| Licence | Papers |
| --- | --- |
| arXiv non-exclusive licence (a licence to arXiv to distribute; it gives no rights to others) | the 20 TeX papers; the ACM version of `pal-2023-ruler` is CC-BY |
| CC-BY | `bhat-2024-verifying-peephole`, `kjolstad-2017-taco`, `marshall-2022-linearity-uniqueness`; the ACM CC-BY versions of `chataing-2024-unboxed-data-constructors`, `huang-2023-defunctionalization`, `kovacs-2024-closure-free`, `lorenzen-2023-fp2` (the Utrecht copy: other-oa), `marshall-2024-fractional-uniqueness` (the accepted copy states none), `reinking-2021-perceus` (the TR copy states none) |
| CC-BY-ND | `fehr-2022-irdl` |
| CC-BY-NC | `ikarashi-2022-exo` |
| CC-BY-NC-SA | `ragankelley-2013-halide` |
| BRICS OA, no explicit licence (verify) | `danvy-2001-defunctionalization` |
| CUP ©, open-access PDF served by Cambridge Core (verify) | `marlow-2006-fast-curry`, `peytonjones-1992-stg`, `sorensen-1996-positive-supercompiler` |
| publisher ©, author or project copy, no licence stated (verify) | ACM: `adams-2019-halide-learning`, `henriksen-2017-futhark`, `jia-2019-taso`, `leijen-2017-koka-effects`, `leroy-2009-compcert`, `lopes-2015-alive`, `lopes-2021-alive2`, `maranget-2008-pattern-matching`, `mitchell-2010-rethinking-supercompilation`, `mullapudi-2016-halide-autosched`, `panchekha-2015-herbie`, `rondon-2008-liquid-types`, `schkufza-2013-stoke`; Springer: `hovgaard-2018-defunctionalisation` |
| author-hosted, none stated | `wadler-1990-linear-types` |

Papers added on 2026-10-09:

| Licence | Papers |
| --- | --- |
| arXiv non-exclusive licence | `slepak-2019-semantics`, `paszke-2021-dex` (ACM version CC-BY), `allais-2013-new-equations-neutral-terms`, `allais-2025-frex` (the authors' CC BY on the accepted manuscript) |
| CC-BY 4.0 (the arXiv record's licence) | `vasilache-2022-structured-codegen`, `bik-2022-sparse-mlir` |
| CC-BY | `cockx-2020-type-theory-unchained`; `hagedorn-2020-elevate` (ACM version; OpenAlex records the stored Glasgow copy as CC-BY-SA, verify) |
| CC-BY-SA 4.0 | `schenck-2024-automap` |
| personal use only: do not redistribute without consent | `trojahner-2009-qube` (Elsevier ©, UvA-DARE terms); `cockx-2016-unifiers-as-equivalences` (ACM ©, the copy says "personal use. Not for redistribution") |
| © holder, all rights reserved or "may be protected by copyright" (verify) | `cockx-2017-dependent-pattern-matching-thesis` (KU Leuven), `hsu-2019-data-parallel-compiler` (IUScholarWorks statement), `slepak-2020-dissertation` (author) |
| repository licence that may cover the text (verify) | `diatchki-2015-smt` (BSD-3-Clause of `yav/type-nat-solver`; ACM © for the published version) |
| publisher ©, author or project copy, no licence stated (verify) | ACM: `bailly-2023-size-dependent`, `chakravarty-2011-accelerate`, `henriksen-2013-t2-fusion`, `henriksen-2019-incremental-flattening`, `henriksen-2021-size-types`, `mcdonell-2013-accelerate-optimising`, `slepak-2018-constraint`, `steuwer-2015-lift`, `tillet-2019-triton`, `xi-1998-dml-bounds`; Springer: `cockx-2014-overlapping-patterns`, `gibbons-2017-naperian`, `goguen-2006-eliminating-dependent-pattern-matching`, `grelck-2006-sac`, `mcbride-2000-elimination-motive`, `slepak-2014-remora`; CUP: `mcbride-2004-view-from-left`, `xi-2007-dependent-ml`; IEEE: `munksgaard-2022-memory-optimizations` |
| none stated on the web edition (verify) | `iverson-1962-programming-language` (© Wiley/Iverson), `iverson-1980-notation-tool-of-thought` and `iverson-1987-dictionary-of-apl` and `hui-1995-rank-uniformity` (ACM © for the proceedings versions), `bernecky-1980-operators-enclosed-arrays`, `bernecky-1983-satn45-rank-operator`, `hui-2009-rank-operator`; `henriksen-2017-futhark-thesis` (PDF) |

The 2026-10-09 passes used the same sources as before: arXiv, publisher open access,
green-OA repositories (IUScholarWorks, UvA-DARE, Glasgow eprints, Dagstuhl DROPS), author,
lab and project sites, and the Wayback Machine for one dead author page. No paywall was
bypassed; `dl.acm.org` was not scraped; HAL's Anubis challenge and the Cloudflare challenges
of `code.jsoftware.com` and `aplwiki.com` were not solved or evaded.

**How the copies were obtained.** Only arXiv, publisher open access, green-OA
repositories, and author, lab or project copies were used. No Sci-Hub, Library Genesis or
other paywall-bypassing or pirate mirror was ever opened. `dl.acm.org` was never scraped:
its 403 is recorded as an access barrier, not bypassed. HAL's bot challenge (Anubis) was not
solved or evaded. The only borderline hits were CiteSeerX metadata stubs for some closed ACM
papers (`bolingbroke-2010` 10.1.1.173.1355/5410, `reynolds-1972` 10.1.1.110.5892,
`lamping-1990` 10.1.1.90.2386, `turchin-1986` 10.1.1.128.6414); CiteSeerX is a legitimate
academic search engine, but these stubs had no direct authorized PDF and were not
downloaded.

## Snapshots

All fetched on 2026-09-26; the three LLVM snapshots (`code/mlir/`, `docs/llvm/`,
`docs/mlir/`) were re-taken on 2026-10-08 at the new LLVM pin, each from the same file list
(`docs/llvm/`'s five `.rst` files are now their `.md` successors). The rows after
`docs/tinygrad/` were fetched on 2026-10-09, as were the addenda to `code/idris2/` (8 files)
and `code/mlir/` (38 files, read from the bootstrap's clone at the LLVM pin). File counts
exclude `SNAPSHOT.md` and the addenda's own `.md` files; the `code/idris2/` and `code/mlir/`
counts include the files the addenda add.

| Snapshot | Upstream | Revision | Files | Threads | Manifest rows |
| --- | --- | --- | --- | --- | --- |
| [`code/idris2/`](code/idris2/SNAPSHOT.md) | `idris-lang/Idris2` | `1c630e67c386629a0fbbc6b78a59176fde7f0a76` (submodule pin) | 38 (30, and 8 in the [2026-10-09 addendum](code/idris2/SNAPSHOT.dependent-equality.md)) | E, D, I, cross-cutting, dependent-equality | `code-idris2`, `code-idris-transform`, `code-idris-rewrite` |
| [`code/mlir/`](code/mlir/SNAPSHOT.md) | `llvm/llvm-project`, `mlir/` | main at `7208ba24ca2894729cd394475a00d2a7b605e642` | 132 (94, and 38 in the [2026-10-09 addendum](code/mlir/SNAPSHOT.addendum.md)) | F, B, I, G, mlir-stack | `code-mlir`, `apl-mlir-stack` |
| [`code/mlton/`](code/mlton/SNAPSHOT.md) | `MLton/mlton` | `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37` | 16 | D, G | `code-mlton` |
| [`code/tinygrad/`](code/tinygrad/SNAPSHOT.md) | `tinygrad/tinygrad` | `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a` | 19 | A, G, H | `code-tinygrad` |
| [`docs/ghc/`](docs/ghc/SNAPSHOT.md) | GHC commentary wiki; GHC users guide | none: live hosts (users guide `latest` = the 9.14.1 series) | 22 | D, E, cross-cutting | `docs-ghc`, `docs-ghc-stg-cmm-rts`, `docs-ghc-specialise-specConstr`, `pointers-ghc` |
| [`docs/idris2/`](docs/idris2/SNAPSHOT.md) | `idris-lang/Idris2` | `1c630e67c386629a0fbbc6b78a59176fde7f0a76` (submodule pin) | 71 | E, D | `docs-idris2` |
| [`docs/llvm/`](docs/llvm/SNAPSHOT.md) | `llvm/llvm-project`, `llvm/` | main at `7208ba24ca2894729cd394475a00d2a7b605e642` | 11 | F, B, I | `docs-mlir-llvm` |
| [`docs/mlir/`](docs/mlir/SNAPSHOT.md) | `llvm/llvm-project`, `mlir/` | main at `7208ba24ca2894729cd394475a00d2a7b605e642` | 100 | F, B, I | `docs-mlir-llvm` |
| [`docs/mlton/`](docs/mlton/SNAPSHOT.md) | `MLton/mlton` | `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37` | 16 | D, G | `docs-mlton` |
| [`docs/ssa-book/`](docs/ssa-book/SNAPSHOT.md) | `ssabook.gforge.inria.fr` (dead) | Wayback snapshot `20210621194509` | 1 | F, B | `docs-ssa-book`, `book-ssa-compiler-design` |
| [`docs/tinygrad/`](docs/tinygrad/SNAPSHOT.md) | `tinygrad/tinygrad`; `docs.tinygrad.org` | `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a`; the live site index | 29 | A, G | `docs-tinygrad` |
| [`code/co-dfns/`](code/co-dfns/SNAPSHOT.md) | `Co-dfns/Co-dfns` | `073634096d0aa030addddc7cf9d2adebe5200ce2` (v5.7.1) | 17 | apl-lineage | — |
| [`docs/bqn/`](docs/bqn/SNAPSHOT.md) | `mlochbaum/BQN` | `5abbab967fefc68ae9b3c2620d5d38473a90cb66` | 55 | apl-lineage | — |
| [`docs/j/`](docs/j/SNAPSHOT.md) | Jsoftware, *J Dictionary* web edition | none: live host ("last updated 2001-5-3") | 52 | apl-lineage | — |
| [`code/remora/`](code/remora/SNAPSHOT.md) | `jrslepak/Remora` | `1a831dec554df9a7ef3eeb10f0d22036f1f86dbd` | 12 | typed-rank, G | `code-remora` |
| [`code/revised-remora/`](code/revised-remora/SNAPSHOT.md) | `jrslepak/Revised-Remora` | `0b7b8ad3d757a09536679f515fb30033a3b092ad` | 12 | typed-rank, G | `code-remora` |
| [`code/remorac/`](code/remorac/SNAPSHOT.md) | `jrslepak/remorac` | `9bfe4ac37e87f2d314d02a3eb0236db8af903965` | 13 | typed-rank, G | `code-remora` |
| [`code/makanin-algo/`](code/makanin-algo/SNAPSHOT.md) | `jrslepak/makanin-algo` | `64e3ac616ce29b62a0ee522ee59c5098f21cd0d0` | 6 | typed-rank | `code-remora` |
| [`code/type-nat-solver/`](code/type-nat-solver/SNAPSHOT.md) | `yav/type-nat-solver` | `4218b52e1f70df152daa7fc62f7f1c2ef67b60a1` | 4 | typed-rank, E | `code-natsolvers` |
| [`code/ghc-typelits-natnormalise/`](code/ghc-typelits-natnormalise/SNAPSHOT.md) | `clash-lang/ghc-typelits-natnormalise` | `44c1a880be312d73c175dda131a8f97ff0d22a75` | 6 | typed-rank, dependent-equality, E | `code-natsolvers` |
| [`code/futhark/`](code/futhark/SNAPSHOT.md) | `diku-dk/futhark` | `304c56ff73c48f1842ed3971fe19805a3a85c766` (the library pin; `master` was `e641ce0c…` on 2026-10-09) | 20 | dataparallel, G | `code-futhark` |
| [`docs/futhark/`](docs/futhark/SNAPSHOT.md) | `diku-dk/futhark`, `docs/` | `304c56ff73c48f1842ed3971fe19805a3a85c766` | 5 | dataparallel, G | — |
| [`code/dex/`](code/dex/SNAPSHOT.md) | `google-research/dex-lang` | `25e2e389b90403ae2f8d67fb6d52f47d23c439ee` | 13 | dataparallel, G | `code-dex` |
| [`code/lean4/`](code/lean4/SNAPSHOT.md) | `leanprover/lean4` | `7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f` | 7 | dependent-equality | `code-lean-rewrite` |
| [`docs/agda/`](docs/agda/SNAPSHOT.md) | `agda/agda` | `83f3fcce37fc5bd11cd7da10bccbe0f59d860037` | 4 | dependent-equality | `docs-agda-with-rewrite` |
| [`docs/rocq/`](docs/rocq/SNAPSHOT.md) | `rocq-prover/rocq` | `29f5238ebcc99136c8e695babcb658ade8d96fa4` | 6 | dependent-equality | `docs-rocq-rewrite` |
| [`code/jax/`](code/jax/SNAPSHOT.md) | `jax-ml/jax` | `40a35abdd67b2298decb7d14e89adf4d120f1902` (main) | 2 | mlir-stack, G | `apl-mlir-stack` |
| [`docs/jax/`](docs/jax/SNAPSHOT.md) | `jax-ml/jax` | `40a35abdd67b2298decb7d14e89adf4d120f1902` (main) | 2 | mlir-stack, G | `apl-mlir-stack` |
| [`docs/mojo/`](docs/mojo/SNAPSHOT.md) | `modular/modular` | `135c332fec9b326cab8e2f3951a0b2f31d017a5d` (main) | 5 | mlir-stack, F, G | `apl-mlir-stack`, `docs-mojo` (in part) |
| [`code/triton/`](code/triton/SNAPSHOT.md) | `triton-lang/triton` | `11523f38065f52a8117dc3c4d74a2ac59936c19e` (main) | 3 | mlir-stack, G | `apl-mlir-stack` |

The Idris 2 snapshots were fetched from the pinned raw GitHub URLs because
`third_party/Idris2` was not checked out at the time; it is now, at the same pin.

## Pins

Resolved on 2026-09-26, the `llvm/llvm-project` row on 2026-10-08, the rows after
`ssa-book` on 2026-10-09. Raw bases:
`https://raw.githubusercontent.com/<repo>/<pin>/<path>`.

| Component | Pin | Resolved SHA | Source of truth command | In the library |
| --- | --- | --- | --- | --- |
| `third_party/Idris2` (git submodule) | pinned commit `1c630e67` | `1c630e67c386629a0fbbc6b78a59176fde7f0a76` | `git submodule status third_party/Idris2` | `code/idris2/`, `docs/idris2/` |
| this repo `origin/main` HEAD, at access time | `main` | `e37040ac93c9ad244097868e16db482a02fd23ef` | `git ls-remote https://github.com/bjornpagen/idris-mlir.git refs/heads/main` | — |
| local working HEAD, at access time (matched `origin/main`) | `main` | `e37040ac93c9ad244097868e16db482a02fd23ef` | `git rev-parse HEAD` | — |
| `tinygrad/tinygrad` | `master` | `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a` | `git ls-remote https://github.com/tinygrad/tinygrad.git refs/heads/master` | `code/tinygrad/`, `docs/tinygrad/` |
| `MLton/mlton` | `master` | `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37` | `git ls-remote https://github.com/MLton/mlton.git refs/heads/master` | `code/mlton/`, `docs/mlton/` |
| `llvm/llvm-project` | main at a pinned commit (`toolchain.lock.json`) | `7208ba24ca2894729cd394475a00d2a7b605e642`; `mlir` subtree `ec52aa1c2a6f38a131b8edffc6390e1c60cbc4e0` | `tools/verify-pins.sh lock llvm revision` | `code/mlir/`, `docs/mlir/`, `docs/llvm/` |
| `egraphs-good/egg` | `main` | `2f31b28e3f9d78e02273b6c6d4201b5b0720b343` | `git ls-remote https://github.com/egraphs-good/egg refs/heads/main` | not vendored |
| `egraphs-good/egglog` | `main` | `90635860397ce710f8c0a4eeb04154a8ebc3ac05` | `git ls-remote https://github.com/egraphs-good/egglog refs/heads/main` | not vendored |
| `HigherOrderCO/HVM` | `master` | `7365a56cca56a5853c979755891cb86aa343c42d` | `git ls-remote https://github.com/HigherOrderCO/HVM refs/heads/master` | not vendored |
| `HigherOrderCO/Bend` | `main` | `574b6d39a235b539eb19a5c532993a0abb3d11ad` | `git ls-remote https://github.com/HigherOrderCO/Bend refs/heads/main` | not vendored |
| `google-research/dex-lang` | `main` | `25e2e389b90403ae2f8d67fb6d52f47d23c439ee` | `git ls-remote https://github.com/google-research/dex-lang refs/heads/main` | `code/dex/` (excerpts, 2026-10-09) |
| `diku-dk/futhark` | `master` at the 2026-09-26 pin | `304c56ff73c48f1842ed3971fe19805a3a85c766` (`master` was `e641ce0c7e41c1edf285b06cc833179bc6a30690` on 2026-10-09) | `git ls-remote https://github.com/diku-dk/futhark refs/heads/master` | `code/futhark/`, `docs/futhark/` (excerpts, 2026-10-09) |
| `mlochbaum/BQN` | `master` | `5abbab967fefc68ae9b3c2620d5d38473a90cb66` | `git ls-remote https://github.com/mlochbaum/BQN.git HEAD` | `docs/bqn/` |
| `Co-dfns/Co-dfns` | `master` | `073634096d0aa030addddc7cf9d2adebe5200ce2` | `git ls-remote https://github.com/Co-dfns/Co-dfns.git HEAD` | `code/co-dfns/` |
| J Dictionary | none (live host) | — | `docs/j/SNAPSHOT.md` | `docs/j/` |
| `jrslepak/Remora` | `HEAD` | `1a831dec554df9a7ef3eeb10f0d22036f1f86dbd` | `git ls-remote https://github.com/jrslepak/Remora HEAD` | `code/remora/` |
| `jrslepak/Revised-Remora` | `HEAD` | `0b7b8ad3d757a09536679f515fb30033a3b092ad` | `git ls-remote https://github.com/jrslepak/Revised-Remora HEAD` | `code/revised-remora/` |
| `jrslepak/remorac` | `HEAD` | `9bfe4ac37e87f2d314d02a3eb0236db8af903965` | `git ls-remote https://github.com/jrslepak/remorac HEAD` | `code/remorac/` |
| `jrslepak/makanin-algo` | `HEAD` | `64e3ac616ce29b62a0ee522ee59c5098f21cd0d0` | `git ls-remote https://github.com/jrslepak/makanin-algo HEAD` | `code/makanin-algo/` |
| `yav/type-nat-solver` | `HEAD` | `4218b52e1f70df152daa7fc62f7f1c2ef67b60a1` | `git ls-remote https://github.com/yav/type-nat-solver HEAD` | `code/type-nat-solver/`, `papers/diatchki-2015-smt/` |
| `clash-lang/ghc-typelits-natnormalise` | `HEAD` | `44c1a880be312d73c175dda131a8f97ff0d22a75` | `git ls-remote https://github.com/clash-lang/ghc-typelits-natnormalise HEAD` | `code/ghc-typelits-natnormalise/` |
| `leanprover/lean4` | `HEAD` | `7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f` | `git ls-remote https://github.com/leanprover/lean4 HEAD` | `code/lean4/` |
| `agda/agda` | `HEAD` | `83f3fcce37fc5bd11cd7da10bccbe0f59d860037` | `git ls-remote https://github.com/agda/agda HEAD` | `docs/agda/` |
| `rocq-prover/rocq` | `HEAD` | `29f5238ebcc99136c8e695babcb658ade8d96fa4` | `git ls-remote https://github.com/rocq-prover/rocq HEAD` | `docs/rocq/` |
| `jax-ml/jax` | `main` | `40a35abdd67b2298decb7d14e89adf4d120f1902` | `git ls-remote https://github.com/jax-ml/jax.git HEAD` | `code/jax/`, `docs/jax/` |
| `modular/modular` | `main` | `135c332fec9b326cab8e2f3951a0b2f31d017a5d` | `git ls-remote https://github.com/modular/modular.git HEAD` | `docs/mojo/` |
| `triton-lang/triton` | `main` | `11523f38065f52a8117dc3c4d74a2ac59936c19e` | `git ls-remote https://github.com/triton-lang/triton.git refs/heads/main` | `code/triton/` |
| GHC | not vendored (live docs) | — | pointer only: `docs/ghc/SNAPSHOT.md` | `docs/ghc/` |
| SSA book | Wayback snapshot `20210621194509` | — | `docs/ssa-book/SNAPSHOT.md` | `docs/ssa-book/` |

The LLVM pin is a **commit of llvm main**, not a tag or a branch. Until 2026-10-08 it was
the tag `llvmorg-23.1.2`: this library recorded `2d56740342c3bd86a7525fb4c147252757589e30`
for it, which is the annotated tag object, and the commit the tag dereferences to is
`85ac560262434c9ccfc0c183ec22d4138ed647fb` (`mlir` subtree
`ca7b652dc7f3c9b48dc57f408c70f5229dc39363`). Raw fetches use the commit SHA, and the
bootstrap's clone, `.toolchain/llvm-project`, holds its objects. The pinned-repository
SHAs should be re-verified before vendoring (commands in
[Fetch commands](#fetch-commands), §4.9).

## Access record

The reproducible access record of the sources pass (plan step `access`, formerly
`sources/ACCESS.md`): what is reachable, how each host was probed, the resolved identifier
of every paper candidate, and the exact fetch commands for the collection steps. All probes
and API lookups were run on **2026-09-26**. Section numbers §1–§4 are that record's; the
paper READMEs cite them. The array-languages passes of **2026-10-09** add §1b, §3e, §3f, §3g
and §4.10–§4.14, gathered in [their own subsection](#array-languages-passes-2026-10-09).

### Reachability

§1. Probe command used throughout (HTTP status of a `HEAD`-style `GET`, following
redirects):

```bash
curl -s -o /dev/null -w "%{http_code}\n" -L --max-time 25 "<url>"
```

Reachable (HTTP 200):

| Host | Status | What it serves | Notes |
| --- | --- | --- | --- |
| `arxiv.org` (`/abs/<id>`, `/e-print/<id>`) | 200 | Abstract pages and raw TeX/PDF source bundles | Primary paper source. Confirmed for all probed IDs. |
| `export.arxiv.org` (`/api/query`) | 200 | arXiv Atom API for ID/title resolution | Use `https`, not `http` (plain `http` returned empty). |
| `mlir.llvm.org/docs/` | 200 | Rendered MLIR docs | Rendered mirror of the `mlir/docs/**` tree. |
| `raw.githubusercontent.com` | 200 | Raw file tree at any commit/tag | Verified with `llvmorg-23.1.2/mlir/docs/Passes.md`. |
| `api.github.com` | 200 | GitHub REST API (commits, trees, releases) | Used for tree listing and commit SHAs. |
| `github.com` | 200 | Repos: tinygrad, MLton, LLVM, egg, egglog, HVM, Bend, dex-lang, futhark, Idris2 | `git ls-remote` also works. |
| `docs.tinygrad.org` | 200 | tinygrad docs | |
| `egraphs-good.github.io` | 200 | egg/egglog project site | |
| `gitlab.haskell.org` (`/-/wikis/commentary/compiler`) | 200 | GHC compiler commentary wiki | |
| `downloads.haskell.org` (`/ghc/latest/docs/users_guide/`) | 200 | GHC users guide | |
| `www.haskell.org/ghc/` | 200 | GHC landing/docs index | |
| `www.idris-lang.org`, `docs.idris-lang.org` | 200 | Idris 2 docs | |
| `okmij.org/ftp/` | 200 | Oleg Kiselyov's papers (e.g. supercompilation, staging) | Author host. |
| `www.cs.ox.ac.uk` | 200 | Oxford author/lab pages (e.g. Kovács, Orchard, Steuwer) | Author host. |
| `people.mpi-sws.org` | 200 | MPI-SWS author pages (e.g. Daan Leijen / Koka) | Author host. |
| `www.microsoft.com/en-us/research` | 200 | MSR author pages | Author host. |
| `link.springer.com` | 200 | Springer article landing pages | PDFs vary by OA status. |
| `openreview.net` | 200 | OpenReview | |
| `hal.science` | 200 | HAL open archive | |
| `www.semanticscholar.org` | 200 | Semantic Scholar site (web UI only) | |
| `api.openalex.org` | 200 | OpenAlex API | Preferred fallback for DOIs/authors/OA links. |
| `web.archive.org` | 200 | Wayback Machine | Fallback for dead hosts. |
| `iree.dev`, `docs.modular.com/mojo/`, `polygeist.pages.dev` | 200 | IREE, Mojo docs, Polygeist docs | |
| `leanprover.github.io` | 200 | Lean 4 docs site | |

Blocked or absent, with the chosen fallback:

| Host | Status | Observed | Chosen fallback |
| --- | --- | --- | --- |
| `dl.acm.org` | 403 | ACM Digital Library blocks direct fetch (including PDF `oa_url`s OpenAlex returns). | Resolve the DOI via OpenAlex; store the *canonical DOI link* and, where a green-OA copy exists (author site, HAL, institutional repository), fetch that instead. Do not attempt to scrape `dl.acm.org`. |
| `mlton.org`, `www.mlton.org` | 000 (no connection) | MLton project site is dead. | Fetch MLton docs/source from the pinned GitHub mirror (`github.com/MLton/mlton`); use `web.archive.org` snapshots only for pages with no GitHub equivalent. |
| `research-repository.st-andrews.ac.uk` | 000 (no connection) | St Andrews repository unreachable (Tejiščák thesis, Brady thesis live here). | Mark those theses UNRESOLVED for this pass; the related peer-reviewed papers were resolved via DOI/OpenAlex instead. |
| `api.semanticscholar.org` | 429 | Graph API rate-limited. | Use OpenAlex (`api.openalex.org`) as the metadata/OA fallback. |

Fallback priority order for any unresolved paper: **arXiv API (by title) → OpenAlex by
title → OpenAlex/DOI resolution → author/lab host → HAL/OpenReview → Wayback Machine**.

Seen later the same day by the papers and open-access passes: ScienceDirect PDFs returned
403, not the 200 recorded above for `taha-2000-metaml` and `wadler-1990-deforestation`;
`research-repository.st-andrews.ac.uk` returned 503; `research.ed.ac.uk` returned 403;
`research-collection.ethz.ch` returned 500 to the papers pass (the open-access pass then
downloaded `fehr-2022-irdl` from it); ANU Open Research returned 503; HAL served the
open-access pass an Anubis bot challenge (the papers pass had fetched `leroy-2009-compcert`
from HAL with HTTP 200); eScholarship PDFs need a browser User-Agent; MIT DSpace's
`/bitstreams/<uuid>/download` returns 405 and `/server/api/core/bitstreams/<uuid>/content`
works; Utrecht and Chalmers records exposed no direct PDF to the papers pass (the
open-access pass fetched `lorenzen-2023-fp2` through Utrecht's DSpace REST content URL);
`link.springer.com/content/pdf/...` returned a PDF to the papers pass and HTML to the
open-access pass; `ssabook.gforge.inria.fr` does not resolve (000).

### Identifier resolution

§3. Status legend in [Conventions](#conventions). The recommended fetch is the raw-source or
PDF URL the access pass proposed. Licences for ACM/Springer items were **not** individually
verified from the publisher; treat `unknown–verify` as "confirm at collection time before
redistributing". Titles, authors, venues, threads and the licences now recorded are in
[INDEX.md](INDEX.md); this table keeps what the access pass recorded.

§3a. arXiv-confirmed papers:

| Shortname | Canonical link | Fetch recommended | Licence recorded | Status |
| --- | --- | --- | --- | --- |
| `willsey-2021-egg` | https://arxiv.org/abs/2004.03082 | https://arxiv.org/e-print/2004.03082 | arXiv non-exclusive | resolved |
| `zhang-2023-egglog` | https://arxiv.org/abs/2304.04332 | https://arxiv.org/e-print/2304.04332 | arXiv non-exclusive | resolved |
| `zhang-2022-relational-ematching` | https://arxiv.org/abs/2108.02290 | https://arxiv.org/e-print/2108.02290 | arXiv non-exclusive | resolved |
| `wang-2020-spores` | https://arxiv.org/abs/2002.07951 | https://arxiv.org/e-print/2002.07951 | arXiv non-exclusive | resolved-corrected (plan's `2003.02423` is an unrelated physics paper) |
| `zheng-2020-ansor` | https://arxiv.org/abs/2006.06762 | https://arxiv.org/e-print/2006.06762 | arXiv non-exclusive | resolved |
| `yang-2021-tensat` | https://arxiv.org/abs/2101.01332 | https://arxiv.org/e-print/2101.01332 | arXiv non-exclusive | resolved-corrected (plan's `2011.02043` is an unrelated mapping paper) |
| `kovacs-2022-staged` | https://arxiv.org/abs/2209.09729 | https://arxiv.org/e-print/2209.09729 | arXiv non-exclusive | resolved-corrected (plan's `2204.05653` is Kudasov's "Free Monads…") |
| `koehler-2024-guided-eqsat` | https://doi.org/10.1145/3632900 | https://arxiv.org/e-print/2111.13040 (the related sketch paper; see [Corrections](#corrections), papers pass item 9) | ACM © unknown–verify | resolved-corrected (plan's candidate `2306.07214` is an X-ray astronomy paper) |
| `koehler-2021-sketch-eqsat` | https://arxiv.org/abs/2111.13040 | https://arxiv.org/e-print/2111.13040 | arXiv non-exclusive | resolved (this is the plan's "sketch-guided equality saturation, ID to confirm") |
| `ullrich-2019-counting-immutable-beans` | https://arxiv.org/abs/1908.05647 | https://arxiv.org/e-print/1908.05647 | arXiv non-exclusive | resolved |
| `bernardy-2018-linear-haskell` | https://arxiv.org/abs/1710.09756 (DOI 10.1145/3158093) | https://arxiv.org/e-print/1710.09756 | arXiv non-exclusive | resolved |
| `brady-2021-idris2-qtt` | https://arxiv.org/abs/2104.00480 | https://arxiv.org/e-print/2104.00480 | arXiv non-exclusive | resolved |
| `lattner-2020-mlir` | https://arxiv.org/abs/2002.11054 | https://arxiv.org/e-print/2002.11054 | arXiv non-exclusive | resolved |
| `bhat-2022-lambda-ultimate-ssa` | https://arxiv.org/abs/2201.07272 (DOI 10.1109/CGO53902.2022.9741279) | https://arxiv.org/e-print/2201.07272 | arXiv non-exclusive | resolved |
| `sasnauskas-2017-souper` | https://arxiv.org/abs/1711.04422 | https://arxiv.org/e-print/1711.04422 | arXiv non-exclusive | resolved |
| `lucke-2024-transform-dialect` | https://arxiv.org/abs/2409.03864 | https://arxiv.org/e-print/2409.03864 | arXiv non-exclusive | resolved (plan's "Transform Dialect (CGO 2025), ID to confirm") |
| `shivers-2019-remora` | https://arxiv.org/abs/1912.13451 | https://arxiv.org/e-print/1912.13451 | arXiv non-exclusive | resolved (plan's "Remora, ID to confirm") |
| `mendis-2019-ithemal` | https://arxiv.org/abs/1808.07412 | https://arxiv.org/e-print/1808.07412 | arXiv non-exclusive | resolved |
| `wu-2026-slotted-egraphs` | https://arxiv.org/abs/2609.03998 | https://arxiv.org/e-print/2609.03998 | arXiv non-exclusive | resolved (matches plan's "slotted e-graphs / binders, ID to confirm"; ID is future-dated — verify at fetch time) |

§3b. Non-arXiv papers resolved by DOI (via OpenAlex):

| Shortname | Canonical DOI | Fetch recommended | Licence recorded | Status |
| --- | --- | --- | --- | --- |
| `chen-2018-tvm` | https://doi.org/10.5555/3291168.3291211 | https://arxiv.org/e-print/1802.04799 (arXiv version) | arXiv non-exclusive (preprint) | resolved |
| `jia-2019-taso` | https://doi.org/10.1145/3341301.3359630 | (ACM 403) — resolve green OA at collection time | ACM © unknown–verify | resolved |
| `reinking-2021-perceus` | https://doi.org/10.1145/3453483.3454032 | (ACM 403) — Koka repo docs may mirror | ACM © unknown–verify | resolved-corrected (plan's `2004.02812` is a math paper) |
| `pal-2023-ruler` | https://doi.org/10.1145/3622834 | (ACM 403) | ACM © unknown–verify | resolved-corrected (published title differs from plan's "Ruler"; tool is Ruler) |
| `kovacs-2024-closure-free` | https://doi.org/10.1145/3674648 | (ACM 403) | ACM © unknown–verify | resolved |
| `lorenzen-2024-oxidizing-ocaml` | https://doi.org/10.1145/3674642 | (ACM 403) | ACM © unknown–verify | resolved |
| `lorenzen-2023-fp2` | https://doi.org/10.1145/3607840 | (ACM 403) | ACM © unknown–verify | resolved |
| `lorenzen-2022-frame-limited-reuse` | https://doi.org/10.1145/3547634 | (ACM 403) | ACM © unknown–verify | resolved |
| `fehr-2022-irdl` | https://doi.org/10.1145/3519939.3523700 | (ACM 403) | ACM © unknown–verify | resolved |
| `bhat-2024-verifying-peephole` | https://doi.org/10.4230/LIPIcs.ITP.2024.9 | https://drops.dagstuhl.de/ (LIPIcs OA) | CC-BY (LIPIcs default) | resolved-corrected (OpenAlex mislinks this DOI to a Vasilache MLIR-2 paper; title verified from search + LIPIcs) |
| `mitchell-2010-rethinking-supercompilation` | https://doi.org/10.1145/1863543.1863588 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `bolingbroke-2010-supercompilation-by-eval` | https://doi.org/10.1145/1863523.1863540 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `panchekha-2015-herbie` | https://doi.org/10.1145/2737924.2737959 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `schkufza-2013-stoke` | https://doi.org/10.1145/2451116.2451150 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `lopes-2021-alive2` | https://doi.org/10.1145/3453483.3454030 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `lopes-2015-alive` | https://doi.org/10.1145/2737924.2737965 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `leroy-2009-compcert` | https://doi.org/10.1145/1538788.1538814 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `marlow-2006-fast-curry` | https://doi.org/10.1017/S0956796806005995 | Cambridge OA PDF (verified 200) | CUP © unknown–verify | resolved |
| `peytonjones-1992-stg` | https://doi.org/10.1017/S0956796800000319 | Cambridge OA PDF (verified 200) | CUP © unknown–verify | resolved |
| `brady-2004-inductive-families` | https://doi.org/10.1007/978-3-540-24849-1_8 | Springer landing | Springer © unknown–verify | resolved |
| `lee-2001-size-change` | https://doi.org/10.1145/360204.360210 | ACM 403 | ACM © unknown–verify | resolved |
| `rondon-2008-liquid-types` | https://doi.org/10.1145/1375581.1375602 | ACM 403 | ACM © unknown–verify | resolved |
| `danvy-2001-defunctionalization` | https://doi.org/10.1145/773184.773202 | BRICS report https://doi.org/10.7146/brics.v8i23.21684 | BRICS OA | resolved |
| `wurthinger-2017-practical-partial-eval` | https://doi.org/10.1145/3062341.3062381 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `wurthinger-2013-one-vm` | https://doi.org/10.1145/2509578.2509581 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `teiiscak-2020-erasure-calculus` | https://doi.org/10.1145/3408973 | (ACM 403) | ACM © unknown–verify | resolved |
| `chataing-2024-unboxed-data-constructors` | https://doi.org/10.1145/3632893 | (ACM 403) | ACM © unknown–verify | resolved-corrected (plan said "Alexis King, ICFP 2024"; actual authors/venue as shown) |
| `marshall-2022-linearity-uniqueness` | https://doi.org/10.1007/978-3-030-99336-8_13 | Springer OA PDF (verified 200) | Springer OA (verify CC-BY) | resolved |
| `taha-2000-metaml` | https://doi.org/10.1016/S0304-3975(00)00053-0 | ScienceDirect PDF (verified 200) | Elsevier © unknown–verify | resolved |
| `christiansen-2016-elaborator-reflection` | https://doi.org/10.1145/2951913.2951932 | ACM 403 | ACM © unknown–verify | resolved |
| `wadler-1990-deforestation` | https://doi.org/10.1016/0304-3975(90)90147-A | ScienceDirect PDF (verified 200) | Elsevier © unknown–verify | resolved |
| `gill-1993-short-cut` | https://doi.org/10.1145/165180.165214 | ACM 403 | ACM © unknown–verify | resolved |
| `coutts-2007-stream-fusion` | https://doi.org/10.1145/1291151.1291199 | ACM 403 | ACM © unknown–verify | resolved |
| `henriksen-2017-futhark` | https://doi.org/10.1145/3062341.3062354 | ACM 403 | ACM © unknown–verify | resolved |
| `ragankelley-2013-halide` | https://doi.org/10.1145/2499370.2462176 | MIT DSpace OA | MIT OA | resolved |
| `mullapudi-2016-halide-autosched` | https://doi.org/10.1145/2897824.2925952 | ACM 403 | ACM © unknown–verify | resolved |
| `adams-2019-halide-learning` | https://doi.org/10.1145/3306346.3322967 | ACM 403 | ACM © unknown–verify | resolved |
| `ikarashi-2022-exo` | https://doi.org/10.1145/3519939.3523446 | (ACM 403) | ACM © unknown–verify | resolved-corrected (plan said ASPLOS 2021) |
| `kjolstad-2017-taco` | https://doi.org/10.1145/3133901 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `massalin-1987-superoptimizer` | https://doi.org/10.1145/36206.36194 | ACM 403 | ACM © unknown–verify | resolved |
| `bansal-2006-peephole-superoptimizer` | https://doi.org/10.1145/1168918.1168906 | ACM 403 | ACM © unknown–verify | resolved |
| `joshi-2002-denali` | https://doi.org/10.1145/512529.512566 | ACM 403 | ACM © unknown–verify | resolved |
| `pnueli-1998-translation-validation` | https://doi.org/10.1007/BFb0054170 | Springer landing | Springer © unknown–verify | resolved |
| `lafont-1990-interaction-nets` | https://doi.org/10.1145/96709.96718 | ACM 403 | ACM © unknown–verify | resolved |
| `lamping-1990-optimal-reduction` | https://doi.org/10.1145/96709.96711 | ACM 403 | ACM © unknown–verify | resolved |
| `reynolds-1972-definitional-interpreters` | https://doi.org/10.1145/800194.805852 | ACM 403 | ACM © unknown–verify | resolved |
| `turchin-1986-supercompiler` | https://doi.org/10.1145/5956.5957 | ACM 403 | ACM © unknown–verify | resolved |
| `sorensen-1996-positive-supercompiler` | https://doi.org/10.1017/S0956796800002008 | Cambridge OA PDF (verify) | CUP © unknown–verify | resolved |
| `taha-2004-gentle-intro-multistage` | https://doi.org/10.1007/978-3-540-25935-0_3 | Springer landing | Springer © unknown–verify | resolved |
| `rompf-2010-lms` | https://doi.org/10.1145/1868294.1868314 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `leijen-2017-koka-effects` | https://doi.org/10.1145/3009837.3009872 | author host / ACM 403 | ACM © unknown–verify | resolved |
| `blackburn-2008-immix` | https://doi.org/10.1145/1375581.1375586 | ACM 403 | ACM © unknown–verify | resolved |

§3c. The 27 rows the access pass could not confirm are each in [INDEX.md](INDEX.md): in
their topic's "Unresolved" table with the reason, or, where a later pass resolved them,
among the stored or link-only papers with a note of the earlier status.

### Non-paper source URLs

§3d.

| Source | Canonical base URL | Pin |
| --- | --- | --- |
| MLIR docs | https://mlir.llvm.org/docs/ | rendered; canonical tree `mlir/docs/**` |
| LLVM/MLIR raw tree | https://raw.githubusercontent.com/llvm/llvm-project/7208ba24ca2894729cd394475a00d2a7b605e642/ | the LLVM pin, main at `7208ba24` ([Pins](#pins)); the 2026-09-26 record used tag `llvmorg-23.1.2` (= `2d567403…`) |
| LLVM/MLIR GitHub tree API | https://api.github.com/repos/llvm/llvm-project/git/trees/7208ba24ca2894729cd394475a00d2a7b605e642?recursive=1 | the LLVM pin; on 2026-09-26, the tag |
| Idris 2 docs | https://raw.githubusercontent.com/idris-lang/Idris2/1c630e67c386629a0fbbc6b78a59176fde7f0a76/docs/source/ | submodule pin |
| GHC commentary wiki | https://gitlab.haskell.org/ghc/ghc/-/wikis/commentary/compiler | live wiki |
| GHC users guide | https://downloads.haskell.org/ghc/latest/docs/users_guide/ | `latest` |
| MLton guide | https://raw.githubusercontent.com/MLton/mlton/aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37/doc/guide/src/ | `master` patch pin |
| MLton site fallback | https://web.archive.org/web/2023/https://mlton.org/ | Wayback |
| tinygrad docs | https://docs.tinygrad.org/ | live |
| tinygrad repo/README | https://raw.githubusercontent.com/tinygrad/tinygrad/b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a/ | `master` pin |
| egg repo | https://github.com/egraphs-good/egg | `2f31b28e…` |
| egglog repo | https://github.com/egraphs-good/egglog | `90635860…` |
| HVM2 repo | https://github.com/HigherOrderCO/HVM | `7365a56c…` |
| Bend repo | https://github.com/HigherOrderCO/Bend | `574b6d39…` |
| dex-lang repo | https://github.com/google-research/dex-lang | `25e2e389…` |
| Futhark repo | https://github.com/diku-dk/futhark | `304c56ff…` |

### Fetch commands

§4. The documented commands for the collection steps: read-only fetches, not a script to
run, and nothing here builds or runs repository code. Destinations are under this library.

#### 4.1 arXiv API: resolve an ID or a title

```bash
# Confirm an ID (prints title/authors/date/journal-ref/doi)
curl -s "https://export.arxiv.org/api/query?id_list=2004.03082" \
  | python3 -c "import sys,xml.etree.ElementTree as ET; ns={'a':'http://www.w3.org/2005/Atom'}; [print(e.find('a:id',ns).text, '|', ' '.join(e.find('a:title',ns).text.split())) for e in ET.fromstring(sys.stdin.read()).findall('a:entry',ns)]"

# Resolve an uncertain ID by title
curl -sG "https://export.arxiv.org/api/query" \
  --data-urlencode 'search_query=ti:"Staged Compilation with Two-Level Type Theory"' \
  --data-urlencode 'max_results=3'
```

#### 4.2 arXiv `e-print` fetch and unpack (preferred paper form)

```bash
id=2004.03082
shortname=willsey-2021-egg
dest="sources/papers/${shortname}"
mkdir -p "$dest"
curl -L --fail -o "/tmp/${id}.src" "https://arxiv.org/e-print/${id}"
file "/tmp/${id}.src"                      # detect: gzip, tar, or single .tex
# Case A: gzip-compressed tar (most common)
tar -xzf "/tmp/${id}.src" -C "$dest"
# Case B: plain gzip (single file)
#   gunzip -c "/tmp/${id}.src" > "$dest/main.tex"
# Case C: uncompressed tar
#   tar -xf "/tmp/${id}.src" -C "$dest"
# Then remove generated files and enforce size:
find "$dest" -name '*.aux' -delete; find "$dest" -name '*.log' -delete
du -sh "$dest"                             # must be < 20 MB
```

#### 4.3 OpenAlex fallback (by title, then by DOI)

```bash
# Title search
curl -sG "https://api.openalex.org/works" \
  --data-urlencode "search=Perceus garbage free reference counting with reuse" \
  --data-urlencode "per-page=3" --data-urlencode "mailto=research@example.org"

# Batch DOI resolution (authors, year, venue, OA URL)
curl -sG "https://api.openalex.org/works" \
  --data-urlencode "filter=doi:10.1145/3453483.3454032|10.1145/3632900" \
  --data-urlencode "per-page=50" --data-urlencode "mailto=research@example.org"
```

#### 4.4 LLVM / MLIR raw fetch at the pinned commit

The 2026-09-26 pass fetched at the then pin, tag `llvmorg-23.1.2`; the pin is now a commit
of llvm main ([Pins](#pins)), and the 2026-10-08 re-take read the bootstrap's clone instead
(`code/mlir/SNAPSHOT.md`).

```bash
rev=7208ba24ca2894729cd394475a00d2a7b605e642   # toolchain.lock.json, llvm.revision
base="https://raw.githubusercontent.com/llvm/llvm-project/${rev}"

# Single file
curl -L --fail -o /tmp/PatternMatch.h "${base}/mlir/include/mlir/IR/PatternMatch.h"

# Full tree listing (to enumerate mlir/docs/**), then fetch each path
curl -s "https://api.github.com/repos/llvm/llvm-project/git/trees/${rev}?recursive=1" \
  > /tmp/llvm-tree.json
```

#### 4.5 Idris 2 raw fetch at the submodule pin

```bash
pin=1c630e67c386629a0fbbc6b78a59176fde7f0a76
base="https://raw.githubusercontent.com/idris-lang/Idris2/${pin}"
curl -L --fail -o /tmp/TT.idr "${base}/src/Core/TT.idr"
```

#### 4.6 GHC commentary wiki and users guide

```bash
curl -L --fail -o /tmp/ghc-commentary.html \
  "https://gitlab.haskell.org/ghc/ghc/-/wikis/commentary/compiler"
curl -L --fail -o /tmp/ghc-users-guide.html \
  "https://downloads.haskell.org/ghc/latest/docs/users_guide/index.html"
```

#### 4.7 MLton docs and source (GitHub mirror) and the dead-site fallback

```bash
mltonpin=aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37
curl -L --fail -o /tmp/CompilerOverview.adoc \
  "https://raw.githubusercontent.com/MLton/mlton/${mltonpin}/doc/guide/src/CompilerOverview.adoc"

# If a legacy mlton.org page is needed and GitHub has no equivalent:
curl -L --fail -o /tmp/mlton-legacy.html \
  "https://web.archive.org/web/2023/https://mlton.org/<path>"
```

#### 4.8 tinygrad docs and README at the pinned commit

```bash
tpin=b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a
curl -L --fail -o /tmp/tinygrad-README.md \
  "https://raw.githubusercontent.com/tinygrad/tinygrad/${tpin}/README.md"
curl -L --fail "https://docs.tinygrad.org/" -o /tmp/tinygrad-docs-index.html
```

#### 4.9 Pinned-repository SHAs (re-verify before vendoring)

```bash
git ls-remote https://github.com/egraphs-good/egg refs/heads/main
git ls-remote https://github.com/egraphs-good/egglog refs/heads/main
git ls-remote https://github.com/HigherOrderCO/HVM refs/heads/master
git ls-remote https://github.com/HigherOrderCO/Bend refs/heads/main
git ls-remote https://github.com/google-research/dex-lang refs/heads/main
git ls-remote https://github.com/diku-dk/futhark refs/heads/master
```

Single files of the un-vendored MLIR `lib/` trees: the command in `code/mlir/SNAPSHOT.md`.
GHC URL patterns: `docs/ghc/SNAPSHOT.md`. The SSA book's Wayback URL:
`docs/ssa-book/SNAPSHOT.md`.

### Array-languages passes (2026-10-09)

§1b. **Reachability**, probed 2026-10-09 with the §1 command (some passes added
`-A "Mozilla/5.0"` or `-w "%{http_code} %{content_type}"`).

| Host | Status | What it serves | Notes |
| --- | --- | --- | --- |
| `www.jsoftware.com` (`/papers/`, `/help/dictionary/`) | 200 | Jsoftware's web editions of Iverson, Hui and the SHARP APL technical notes; the J Dictionary | Papers are framesets: fetch the frameset, its contents frame and its main frame. |
| `code.jsoftware.com` (NuVoc, wiki essays) | 403 | Cloudflare challenge ("Just a moment...") | Not solved or evaded; NuVoc not fetched. |
| `aplwiki.com` | 403 | Cloudflare challenge | Not fetched. |
| `scholarworks.iu.edu` (`/iuswrrest/api/core/…`) | 200 | IU DSpace 7 REST: item bundles and bitstream content | `/dspace/bitstreams/<uuid>/download` returns an HTML shell; use `/iuswrrest/api/core/bitstreams/<uuid>/content`. |
| `sigplan.org/OpenTOC/` | 200 | SIGPLAN open table of contents | For HOPL 2020 it links only to `dl.acm.org`. |
| `api.crossref.org` | 200 | Crossref works API | DOIs, pages, licences; title search resolved Frex and Allais 2013. |
| `api.semanticscholar.org` | 200 | Graph API (single lookups) | No longer 429 for single lookups, as it was on 2026-09-26. |
| `api.openalex.org` | 200, then 429 | OA locations | Later in the day: 429 "Insufficient budget" (the shared daily budget). |
| `export.arxiv.org` (`/api/query`) | intermittent | arXiv Atom API | 503 once, "Rate exceeded." and empty bodies under parallel use; the abstract pages' `citation_*` metadata were used instead. |
| `dl.acm.org` | 403 | as in §1 | Not bypassed. |
| `khoury.northeastern.edu` (`/~pete/pub/`, `/~jrslepak/`) | 200 | Manolios's and Slepak's papers and dissertation | Author host. |
| `www.cs.ox.ac.uk/people/jeremy.gibbons/` | 200 | Gibbons's papers and code | Author host. |
| `www.cs.cmu.edu/~fp/papers/` | 200 | Pfenning's papers | Author host. |
| `www.cs.bu.edu/~hwxi/` | 404 | Xi's old pages | Use `hwxi.github.io`. |
| `hwxi.github.io` | 200 | Xi's papers | Author host. |
| `staff.fnwi.uva.nl`, `staff.science.uva.nl` (`/c.u.grelck/`) | 404 | Grelck's old pages | Wayback snapshot used for SaC; UvA-DARE for Qube. |
| `pure.uva.nl` (UvA-DARE) | 200 | UvA repository PDFs | Personal-use terms on the cover sheet. |
| `futhark-lang.org` (`/publications/`) | 200 | Futhark group papers and the thesis | Project host. |
| `media.githubusercontent.com` | 200 | Git LFS objects of `tmcdonell.github.io` | `tmcdonell.github.io/papers/*.pdf` serves 131-byte LFS pointers; the bytes come from here. |
| `www.cse.unsw.edu.au/~chak/papers/` | 403 | Chakravarty's old pages | Copies taken from McDonell's site. |
| `michel.steuwer.info` | 200 | Steuwer's papers | Author host. |
| `eprints.gla.ac.uk` | 200 | Glasgow repository | Green OA. |
| `strictlypositive.org` | 200 | McBride's papers (`.ps.gz`, PDF) | Author host. |
| `personal.cis.strath.ac.uk/conor.mcbride/` | 200 | McBride's Strathclyde page | Most links broken; none of the targets listed. |
| `jesper.cx` | 200 | Cockx's papers and thesis | Author host. |
| `www.cambridge.org/core/services/aop-cambridge-core/` | 200 | Cambridge Core open PDFs | `cockx-2016-without-k` fetched, not stored. |
| `drops.dagstuhl.de` | 200 | LIPIcs PDFs | Gold OA. |
| `hal.science` | 200 `text/html` | Anubis bot challenge | Not solved or evaded, as in [Open-access acquisition](#open-access-acquisition). |
| `yav.github.io` | 200 | Diatchki's papers | Fetched, not stored (the author TeX was stored instead). |
| `www.eecs.harvard.edu/~htk/publication/` | 200 | H. T. Kung's publication PDFs | Author host. |
| `dash.harvard.edu` | 000 | Harvard DASH | Not needed. |
| `www.snakeisland.com` | 404 (`/fnrank.pdf`) | Bernecky's company site | No APL88 copy found. |
| `raw.githubusercontent.com`, `api.github.com` | 200 | Pinned files and tree listings | The triton tree request returned non-JSON once; files were fetched by known path. |

§3e. **Identifier resolution**, papers stored on 2026-10-09:

| Shortname | Canonical link | Fetch used | Licence recorded | Status |
| --- | --- | --- | --- | --- |
| `iverson-1962-programming-language` | no DOI (Wiley 1962, LCCN 62-15180) | https://www.jsoftware.com/papers/APL.htm and its frames | none stated (verify) | resolved (bibliography key `APL`) |
| `iverson-1980-notation-tool-of-thought` | https://doi.org/10.1145/358896.358899 | https://www.jsoftware.com/papers/tot.htm | ACM © | resolved (Crossref; OpenAlex: bronze on `dl.acm.org` only) |
| `bernecky-1980-operators-enclosed-arrays` | no DOI | https://www.jsoftware.com/papers/opea.htm | none stated | URL only (Jsoftware papers index) |
| `bernecky-1983-satn45-rank-operator` | no DOI | https://www.jsoftware.com/papers/satn45.htm | none stated | URL only |
| `iverson-1987-dictionary-of-apl` | https://doi.org/10.1145/36983.36984 | https://www.jsoftware.com/papers/APLDictionary.htm | ACM © | resolved (Crossref) |
| `hui-1995-rank-uniformity` | APL95, APL Quote Quad 25(4) | https://www.jsoftware.com/papers/rank.htm | ACM © | DOI not resolved |
| `hui-2009-rank-operator` | no DOI | https://www.jsoftware.com/papers/rank/index.htm | none stated | URL only |
| `hsu-2019-data-parallel-compiler` | https://hdl.handle.net/2022/24749 | IU DSpace REST (§4.10) | "may be protected by copyright" | resolved (item `3ab772c9-92c9-4f59-bd95-40aff99e8c7a`) |
| `slepak-2014-remora` | https://doi.org/10.1007/978-3-642-54833-8_3 | https://khoury.northeastern.edu/~pete/pub/esop-2014.pdf, `.../esop14-full.pdf` | Springer © | resolved (Unpaywall: bronze) |
| `slepak-2018-constraint` | https://doi.org/10.1145/3219753.3219758 | https://khoury.northeastern.edu/~pete/pub/array-2018.pdf | ACM © | resolved (Unpaywall: closed) |
| `slepak-2019-semantics` | https://arxiv.org/abs/1907.00509 | https://arxiv.org/e-print/1907.00509 | arXiv non-exclusive | resolved (arXiv API, v1 2019-07-01) |
| `slepak-2020-dissertation` | no DOI | https://www.khoury.northeastern.edu/~jrslepak/Dissertation.pdf | © author | resolved |
| `gibbons-2017-naperian` | https://doi.org/10.1007/978-3-662-54434-1_21 | https://www.cs.ox.ac.uk/people/jeremy.gibbons/publications/aplicative.pdf (and `.hs`) | Springer © | resolved (Unpaywall: closed; ORA lists the accepted manuscript) |
| `xi-1998-dml-bounds` | https://doi.org/10.1145/277650.277732 | https://www.cs.cmu.edu/~fp/papers/pldi98dml.pdf | ACM © | resolved (Unpaywall: closed) |
| `trojahner-2009-qube` | https://doi.org/10.1016/j.jlap.2009.03.002 | https://pure.uva.nl/ws/files/856220/73195_310901.pdf | Elsevier ©, UvA-DARE personal use | resolved (Unpaywall: bronze; repository `other-oa`) |
| `henriksen-2021-size-types` | https://doi.org/10.1145/3460944.3464310 | https://www.futhark-lang.org/publications/array21.pdf | ACM © | resolved (Unpaywall: closed) |
| `bailly-2023-size-dependent` | https://doi.org/10.1145/3609024.3609412 | https://futhark-lang.org/publications/fhpnc23.pdf | ACM © | resolved (found by search) |
| `diatchki-2015-smt` | https://doi.org/10.1145/2804302.2804307 | `yav/type-nat-solver` `docs/` at `4218b52e` | ACM © / repository BSD-3 | resolved (Unpaywall: closed) |
| `henriksen-2013-t2-fusion` | https://doi.org/10.1145/2502323.2502328 | https://futhark-lang.org/publications/fhpc13.pdf | ACM © | resolved (OpenAlex) |
| `henriksen-2017-futhark-thesis` | no DOI | https://futhark-lang.org/publications/troels-henriksen-phd-thesis.pdf | none stated | resolved (was the unresolved row `henriksen-thesis`) |
| `henriksen-2019-incremental-flattening` | https://doi.org/10.1145/3293883.3295707 | https://futhark-lang.org/publications/ppopp19.pdf | ACM © | resolved (OpenAlex) |
| `munksgaard-2022-memory-optimizations` | https://futhark-lang.org/publications/sc22-mem.pdf | same | IEEE © | IEEE Xplore record not resolved |
| `schenck-2024-automap` | https://doi.org/10.1145/3689774 | https://futhark-lang.org/publications/oopsla24.pdf | CC-BY-SA 4.0 | resolved (OpenAlex) |
| `paszke-2021-dex` | https://arxiv.org/abs/2104.05372 (DOI 10.1145/3473593) | https://arxiv.org/e-print/2104.05372 | arXiv non-exclusive | resolved (was the unresolved row `dex-papers`) |
| `chakravarty-2011-accelerate` | https://doi.org/10.1145/1926354.1926358 | McDonell's site through `media.githubusercontent.com` | ACM © | resolved (OpenAlex) |
| `mcdonell-2013-accelerate-optimising` | https://doi.org/10.1145/2500365.2500595 | same host | ACM © | resolved (OpenAlex) |
| `grelck-2006-sac` | https://doi.org/10.1007/s10766-006-0018-x | Wayback `20190522071605id_` of Grelck's UvA page | Springer © | resolved (was the unresolved row `sac-language`) |
| `steuwer-2015-lift` | https://doi.org/10.1145/2784731.2784754 | https://michel.steuwer.info/files/publications/2015/ICFP-2015.pdf | ACM © | resolved (OpenAlex) |
| `hagedorn-2020-elevate` | https://doi.org/10.1145/3408974 | https://eprints.gla.ac.uk/220121/1/220121.pdf | CC-BY (ACM) | resolved (OpenAlex) |
| `mcbride-2000-elimination-motive` | https://doi.org/10.1007/3-540-45842-5_13 | http://strictlypositive.org/elim.ps.gz | Springer © | resolved (Springer landing page) |
| `mcbride-2004-view-from-left` | https://doi.org/10.1017/S0956796803004829 | http://strictlypositive.org/view.ps.gz | CUP © | resolved |
| `goguen-2006-eliminating-dependent-pattern-matching` | https://doi.org/10.1007/11780274_27 | http://strictlypositive.org/goguen.pdf | Springer © | resolved |
| `cockx-2014-overlapping-patterns` | https://doi.org/10.1007/978-3-642-54833-8_6 | https://jesper.cx/files/overlapping-and-order-independent-patterns.pdf | Springer © | resolved (author page) |
| `cockx-2016-unifiers-as-equivalences` | https://doi.org/10.1145/2951913.2951917 | https://jesper.cx/files/unifiers-as-equivalences.pdf | ACM ©, personal use | resolved (DOI printed on the copy) |
| `cockx-2017-dependent-pattern-matching-thesis` | no DOI (KU Leuven) | https://jesper.cx/files/thesis-final-digital.pdf | © KU Leuven | resolved |
| `cockx-2020-type-theory-unchained` | https://doi.org/10.4230/LIPIcs.TYPES.2019.2 | Dagstuhl DROPS PDF | CC-BY | resolved (DOI printed on the PDF) |
| `allais-2013-new-equations-neutral-terms` | https://doi.org/10.1145/2502409.2502411 (arXiv 1304.0809) | https://arxiv.org/e-print/1304.0809 | arXiv non-exclusive | resolved (arXiv page; Crossref) |
| `allais-2025-frex` | https://doi.org/10.1145/3747506 (arXiv 2306.15375) | https://arxiv.org/e-print/2306.15375 | arXiv non-exclusive | resolved (arXiv journal-ref; Crossref) |
| `xi-2007-dependent-ml` | https://doi.org/10.1017/S0956796806006216 | https://hwxi.github.io/PUBLICATION/MYDATA/DML-jfp07.pdf | CUP © | resolved (author page) |
| `vasilache-2022-structured-codegen` | https://arxiv.org/abs/2202.03293 | https://arxiv.org/e-print/2202.03293 | CC-BY 4.0 | resolved (abstract page metadata) |
| `bik-2022-sparse-mlir` | https://doi.org/10.1145/3544559 (arXiv 2202.04305) | https://arxiv.org/e-print/2202.04305 | CC-BY 4.0 (arXiv) | resolved (DOI from the arXiv record) |
| `tillet-2019-triton` | https://doi.org/10.1145/3315508.3329973 | https://www.eecs.harvard.edu/~htk/publication/2019-mapl-tillet-kung-cox.pdf | ACM © | resolved (OpenAlex: closed) |

§3f. **Identifier resolution**, link-only rows of 2026-10-09: `hui-2020-apl-since-1978`
(10.1145/3386319; Crossref CC-BY 4.0, OpenAlex diamond CC-BY-SA, Semantic Scholar GOLD),
`bernecky-1988-function-rank` (10.1145/55626.55632; OpenAlex closed), `cockx-2021-taming-rew`
(10.1145/3434341; HAL `hal-02901011`, linked from the Agda manual and the author's page),
`cockx-2016-without-k` (10.1017/S0956796816000174), `cockx-2018-proof-relevant-unification`
(10.1017/S095679681800014X), `gregoire-2005-ring` (10.1007/11541868_7). `mlir-cgo-2021`
(10.1109/CGO51591.2021.9370308) is unchanged: its arXiv version is `lattner-2020-mlir`.

§3g. **Non-paper source URLs** of 2026-10-09:

| Source | Canonical base URL | Pin |
| --- | --- | --- |
| Jsoftware papers | https://www.jsoftware.com/papers/ | live |
| J Dictionary | https://www.jsoftware.com/help/dictionary/ | live ("last updated 2001-5-3") |
| BQN repo | https://raw.githubusercontent.com/mlochbaum/BQN/5abbab967fefc68ae9b3c2620d5d38473a90cb66/ | `5abbab96…` |
| Co-dfns repo | https://raw.githubusercontent.com/Co-dfns/Co-dfns/073634096d0aa030addddc7cf9d2adebe5200ce2/ | `07363409…` |
| Remora repos | https://raw.githubusercontent.com/jrslepak/{Remora,Revised-Remora,remorac,makanin-algo}/<sha>/ | [Pins](#pins) |
| type-nat-solver, ghc-typelits-natnormalise | https://raw.githubusercontent.com/{yav/type-nat-solver,clash-lang/ghc-typelits-natnormalise}/<sha>/ | [Pins](#pins) |
| Futhark, dex-lang | https://raw.githubusercontent.com/{diku-dk/futhark,google-research/dex-lang}/<sha>/ | the library's pins |
| Lean 4, Agda, Rocq | https://raw.githubusercontent.com/{leanprover/lean4,agda/agda,rocq-prover/rocq}/<sha>/ | [Pins](#pins) |
| JAX docs and source | https://raw.githubusercontent.com/jax-ml/jax/40a35abdd67b2298decb7d14e89adf4d120f1902/ (rendered: https://docs.jax.dev/en/latest/) | `40a35abd…` |
| Mojo docs | https://raw.githubusercontent.com/modular/modular/135c332fec9b326cab8e2f3951a0b2f31d017a5d/ (rendered: https://docs.modular.com/mojo/) | `135c332f…` |
| Triton source | https://raw.githubusercontent.com/triton-lang/triton/11523f38065f52a8117dc3c4d74a2ac59936c19e/ | `11523f38…` |
| MLIR ODS (addendum) | local: `git -C .toolchain/llvm-project cat-file blob 7208ba24…:mlir/<path>` | LLVM pin |

The fetch commands follow, as run: read-only, each download into its own new directory,
nothing built or run from a download, destinations relative to this library.

#### 4.10 APL lineage: Jsoftware, IU ScholarWorks, BQN, Co-dfns

```bash
# Jsoftware framed paper: the frameset, then its frames, stylesheet and images
curl -sL -O https://www.jsoftware.com/papers/tot.htm          # also tottoc.htm, tot1.htm, adoc.css, img/tot_fig3.jpg
curl -sL -O https://www.jsoftware.com/papers/APL1.htm         # and each APLimg/<name>.bmp it references
# satn45, opea, rank, rank/, APLDictionary: the same pattern (<name>.htm, <name>TOC.htm, the main frame)

# J Dictionary pages
curl -s --fail -O https://www.jsoftware.com/help/dictionary/<page>.htm

# BQN and Co-dfns at their pins (URL-encode ∆ and spaces in Co-dfns paths)
curl -s --fail -o <path> https://raw.githubusercontent.com/mlochbaum/BQN/5abbab967fefc68ae9b3c2620d5d38473a90cb66/<path>
curl -s --fail -o <path> https://raw.githubusercontent.com/Co-dfns/Co-dfns/073634096d0aa030addddc7cf9d2adebe5200ce2/<path>

# Hsu dissertation: list the bundles, then fetch bitstream content
curl -s "https://scholarworks.iu.edu/iuswrrest/api/core/items/3ab772c9-92c9-4f59-bd95-40aff99e8c7a/bundles?embed=bitstreams"
curl -sL --fail -o hsu-dissertation.pdf.txt https://scholarworks.iu.edu/iuswrrest/api/core/bitstreams/8f9f9835-485c-483c-9c87-6ccb45fcfa74/content
curl -sL --fail -o hsu-dissertation.pdf     https://scholarworks.iu.edu/iuswrrest/api/core/bitstreams/dcbd5240-8454-4533-bc0c-ac3ee7628b8e/content   # 30.7 MB, not stored

# OA lookups
curl -s "https://api.openalex.org/works/doi:10.1145/3386319"
curl -s "https://api.crossref.org/works/10.1145/3386319"
```

#### 4.11 Typed rank: author PDFs, the arXiv e-print, the Remora and solver repositories

```bash
fetch() { mkdir "papers/$1" && curl -sL --fail --max-time 120 -o "papers/$1/$2" "$3"; }
fetch slepak-2014-remora paper.pdf https://khoury.northeastern.edu/~pete/pub/esop-2014.pdf
curl -sL --fail -o papers/slepak-2014-remora/paper-full.pdf https://khoury.northeastern.edu/~pete/pub/esop14-full.pdf
fetch slepak-2018-constraint paper.pdf https://khoury.northeastern.edu/~pete/pub/array-2018.pdf
fetch slepak-2020-dissertation Dissertation.pdf https://www.khoury.northeastern.edu/~jrslepak/Dissertation.pdf
fetch gibbons-2017-naperian aplicative.pdf https://www.cs.ox.ac.uk/people/jeremy.gibbons/publications/aplicative.pdf
curl -sL --fail -o papers/gibbons-2017-naperian/aplicative.hs https://www.cs.ox.ac.uk/people/jeremy.gibbons/publications/aplicative.hs
fetch xi-1998-dml-bounds pldi98dml.pdf https://www.cs.cmu.edu/~fp/papers/pldi98dml.pdf
fetch trojahner-2009-qube paper.pdf https://pure.uva.nl/ws/files/856220/73195_310901.pdf
fetch henriksen-2021-size-types paper.pdf https://www.futhark-lang.org/publications/array21.pdf
fetch bailly-2023-size-dependent paper.pdf https://futhark-lang.org/publications/fhpnc23.pdf

# arXiv e-print (§4.2); paper.bbl removed (no .bib present)
mkdir -p /tmp/arxiv-1907.00509 && curl -L --fail -o /tmp/arxiv-1907.00509/src https://arxiv.org/e-print/1907.00509
mkdir papers/slepak-2019-semantics && tar -xzf /tmp/arxiv-1907.00509/src -C papers/slepak-2019-semantics
rm papers/slepak-2019-semantics/paper.bbl

# GitHub raw at pinned commits
raw() { repo=$1 sha=$2 dest=$3; shift 3; for p in "$@"; do mkdir -p "$dest/$(dirname "$p")"; curl -sL --fail -o "$dest/$p" "https://raw.githubusercontent.com/$repo/$sha/$p"; done; }
raw yav/type-nat-solver 4218b52e1f70df152daa7fc62f7f1c2ef67b60a1 papers/diatchki-2015-smt docs/paper.tex docs/refs.bib docs/sigplanconf.cls   # then move docs/* up one level
raw jrslepak/Remora 1a831dec554df9a7ef3eeb10f0d22036f1f86dbd code/remora semantics/Readme.md semantics/dependent-lang.rkt semantics/language.rkt semantics/typed-reduction.rkt semantics/redex-utils.rkt remora/Readme.md remora/dynamic/lang/semantics.rkt remora/dynamic/lang/syntax.rkt remora/scribblings/application.scrbl remora/scribblings/arrays.scrbl remora/scribblings/boxes.scrbl notes/composition.txt
raw jrslepak/Revised-Remora 0b7b8ad3d757a09536679f515fb30033a3b092ad code/revised-remora README.md bidirectional.rkt elab-lang.rkt erased-lang.rkt implicit-lang.rkt inez-wrapper.rkt language.rkt list-utils.rkt makanin-wrapper.rkt reduction.rkt typing-rules.rkt well-formedness.rkt
raw jrslepak/remorac 9bfe4ac37e87f2d314d02a3eb0236db8af903965 code/remorac License.txt README.md design.txt src/remora-internal/typechecker.ml src/remora-internal/typechecker.mli src/remora-internal/basic_ast.mli src/remora-internal/frame_notes.ml src/remora-internal/frame_notes.mli src/remora-internal/map_replicate_ast.ml src/remora-internal/map_replicate_ast.mli src/remora-internal/erased_ast.ml src/remora-internal/erased_ast.mli src/remora-internal/annotation.mli
raw jrslepak/makanin-algo 64e3ac616ce29b62a0ee522ee59c5098f21cd0d0 code/makanin-algo solve.rkt generalized-eqn.rkt diophantine.rkt ge-base.rkt enumerate.rkt utils.rkt
raw yav/type-nat-solver 4218b52e1f70df152daa7fc62f7f1c2ef67b60a1 code/type-nat-solver LICENSE README.mkd src/TypeNatSolver.hs docs/Examples.hs
raw clash-lang/ghc-typelits-natnormalise 44c1a880be312d73c175dda131a8f97ff0d22a75 code/ghc-typelits-natnormalise LICENSE README.md src/GHC/TypeLits/Normalise.hs src/GHC/TypeLits/Normalise/SOP.hs src/GHC/TypeLits/Normalise/Unify.hs doc/ghc-typelits-natnormalise-hcar.tex
```

#### 4.12 Data-parallel compilers: project and author PDFs, the Dex e-print, Futhark and Dex excerpts

The `fetch` and `raw` helpers are those of §4.11.

```bash
fetch henriksen-2013-t2-fusion paper.pdf https://futhark-lang.org/publications/fhpc13.pdf
fetch henriksen-2017-futhark-thesis thesis.pdf https://futhark-lang.org/publications/troels-henriksen-phd-thesis.pdf
fetch henriksen-2019-incremental-flattening paper.pdf https://futhark-lang.org/publications/ppopp19.pdf
fetch munksgaard-2022-memory-optimizations paper.pdf https://futhark-lang.org/publications/sc22-mem.pdf
fetch schenck-2024-automap paper.pdf https://futhark-lang.org/publications/oopsla24.pdf
fetch chakravarty-2011-accelerate paper.pdf https://media.githubusercontent.com/media/tmcdonell/tmcdonell.github.io/master/papers/acc-cuda-damp2011.pdf
fetch mcdonell-2013-accelerate-optimising paper.pdf https://media.githubusercontent.com/media/tmcdonell/tmcdonell.github.io/master/papers/acc-optim-icfp2013.pdf
fetch grelck-2006-sac paper.pdf 'https://web.archive.org/web/20190522071605id_/https://staff.science.uva.nl/c.u.grelck/publications/2006_IJPP_sac.pdf'
fetch steuwer-2015-lift paper.pdf https://michel.steuwer.info/files/publications/2015/ICFP-2015.pdf
fetch hagedorn-2020-elevate paper.pdf https://eprints.gla.ac.uk/220121/1/220121.pdf

mkdir -p /tmp/arxiv-2104.05372 && curl -sL --fail -o /tmp/arxiv-2104.05372/src https://arxiv.org/e-print/2104.05372
mkdir papers/paszke-2021-dex && tar -xzf /tmp/arxiv-2104.05372/src -C papers/paszke-2021-dex

# Futhark and dex-lang excerpts at the library's pins: file lists in each SNAPSHOT.md
raw diku-dk/futhark 304c56ff73c48f1842ed3971fe19805a3a85c766 code/futhark <paths>
raw diku-dk/futhark 304c56ff73c48f1842ed3971fe19805a3a85c766 docs/futhark LICENSE docs/language-reference.rst docs/performance.rst docs/glossary.rst docs/versus-other-languages.rst
raw google-research/dex-lang 25e2e389b90403ae2f8d67fb6d52f47d23c439ee code/dex <paths>
```

#### 4.13 Dependent equality: author PostScript and PDFs, arXiv e-prints, Idris 2, Lean 4, Agda, Rocq

```bash
# PostScript from the author's site, decompressed (no TeX exists)
curl -sL --fail -o /tmp/elim.ps.gz http://strictlypositive.org/elim.ps.gz
mkdir papers/mcbride-2000-elimination-motive && gunzip -c /tmp/elim.ps.gz > papers/mcbride-2000-elimination-motive/elim.ps
curl -sL --fail -o /tmp/view.ps.gz http://strictlypositive.org/view.ps.gz
mkdir papers/mcbride-2004-view-from-left && gunzip -c /tmp/view.ps.gz > papers/mcbride-2004-view-from-left/view.ps
# PDFs
fetch goguen-2006-eliminating-dependent-pattern-matching paper.pdf http://strictlypositive.org/goguen.pdf
fetch cockx-2014-overlapping-patterns paper.pdf https://jesper.cx/files/overlapping-and-order-independent-patterns.pdf
fetch cockx-2016-unifiers-as-equivalences paper.pdf https://jesper.cx/files/unifiers-as-equivalences.pdf
fetch cockx-2017-dependent-pattern-matching-thesis thesis.pdf https://jesper.cx/files/thesis-final-digital.pdf
fetch cockx-2020-type-theory-unchained paper.pdf https://drops.dagstuhl.de/storage/00lipics/lipics-vol175-types2019/LIPIcs.TYPES.2019.2/LIPIcs.TYPES.2019.2.pdf
fetch xi-2007-dependent-ml paper.pdf https://hwxi.github.io/PUBLICATION/MYDATA/DML-jfp07.pdf
# arXiv e-prints (§4.2)
for p in 1304.0809:allais-2013-new-equations-neutral-terms 2306.15375:allais-2025-frex; do
  id=${p%%:*}; d=papers/${p#*:}; mkdir -p /tmp/arxiv-$id "$d"
  curl -L --fail -o /tmp/arxiv-$id/src https://arxiv.org/e-print/$id && tar -xzf /tmp/arxiv-$id/src -C "$d"
done
rm papers/allais-2013-new-equations-neutral-terms/main.bbl   # orphan: no .bib
# GitHub raw at pinned commits
raw idris-lang/Idris2 1c630e67c386629a0fbbc6b78a59176fde7f0a76 code/idris2 src/TTImp/Elab/Rewrite.idr src/Core/Normalise.idr src/Core/GetType.idr src/TTImp/ProcessDef.idr src/TTImp/Elab/Utils.idr src/TTImp/WithClause.idr libs/prelude/Builtin.idr libs/base/Data/Nat.idr
raw leanprover/lean4 7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f code/lean4 LICENSE src/Lean/Meta/KAbstract.lean src/Lean/Meta/Tactic/Rewrite.lean src/Lean/Elab/Tactic/Rewrite.lean src/Lean/Meta/Tactic/Subst.lean src/Lean/Meta/Tactic/Generalize.lean src/Init/Tactics.lean
raw agda/agda 83f3fcce37fc5bd11cd7da10bccbe0f59d860037 docs/agda LICENSE doc/user-manual/language/with-abstraction.lagda.rst doc/user-manual/language/rewriting.lagda.rst doc/user-manual/language/without-k.lagda.rst
raw rocq-prover/rocq 29f5238ebcc99136c8e695babcb658ade8d96fa4 docs/rocq doc/LICENSE doc/sphinx/proofs/writing-proofs/equality.rst doc/sphinx/proof-engine/tactics.rst doc/sphinx/proofs/writing-proofs/reasoning-inductives.rst doc/sphinx/addendum/ring.rst doc/sphinx/addendum/micromega.rst
```

The Idris 2 files were compared with `cmp` against `third_party/Idris2` (byte-identical).

#### 4.14 MLIR stack: arXiv e-prints, the Triton PDF, JAX, Mojo, Triton and the MLIR ODS

```bash
# arXiv TeX (unpack with tar xzf; strip generated files; drop an orphan .bbl)
curl -L --fail -o eprint-2202.03293/src https://arxiv.org/e-print/2202.03293
curl -L --fail -o eprint-2202.04305/src https://arxiv.org/e-print/2202.04305
# Triton author PDF
curl -L --fail -o triton-pdf/paper.pdf https://www.eecs.harvard.edu/~htk/publication/2019-mapl-tillet-kung-cox.pdf
curl -s "https://api.openalex.org/works/doi:10.1145/3315508.3329973?mailto=research@example.org"
# JAX
jax=40a35abdd67b2298decb7d14e89adf4d120f1902
for p in docs/501/shape-polymorphism.md docs/501/export.md \
         jax/_src/export/shape_poly.py jax/_src/export/shape_poly_decision.py; do
  curl -L --fail -o "jax/$p" "https://raw.githubusercontent.com/jax-ml/jax/$jax/$p"; done
# Mojo docs
mod=135c332fec9b326cab8e2f3951a0b2f31d017a5d
for p in Mojo/docs/site/reference/inline-mlir.mdx Mojo/docs/stdlib/internal/mlir.md \
         Mojo/docs/stdlib/internal/pop_dialect.md Mojo/docs/site/faq.md \
         Mojo/docs/site/manual/parameters/index.mdx; do
  curl -L --fail -o "mojo/$p" "https://raw.githubusercontent.com/modular/modular/$mod/$p"; done
# Triton ODS
tri=11523f38065f52a8117dc3c4d74a2ac59936c19e
for p in include/triton/Dialect/Triton/IR/TritonOps.td include/triton/Dialect/Triton/IR/TritonTypes.td \
         include/triton/Dialect/TritonGPU/IR/TritonGPUAttrDefs.td; do
  curl -L --fail -o "triton/$p" "https://raw.githubusercontent.com/triton-lang/triton/$tri/$p"; done
# MLIR ODS addendum (the bootstrap's clone; file list in code/mlir/SNAPSHOT.addendum.md)
git -C .toolchain/llvm-project cat-file blob 7208ba24ca2894729cd394475a00d2a7b605e642:mlir/<path>
```

## How the papers were collected

All on 2026-09-26, recorded in commits `4d95feb` and `ae672fe` (the passes overlapped: the
open-access pass's Cambridge Core downloads are stamped 14:37 UTC, the papers pass's
14:52):
- **Access pass** (plan step `access`): the access record above. No file was fetched.
- **Manifest**: a skeleton of the full target inventory across threads A–J plus
  cross-cutting, with the plan's inventory sections as the rows; the snapshot rows were
  later marked stored. Rows shared by several threads were to be stored once and
  cross-linked.
- **Papers pass** (steps `papers-arxiv`, `papers-other` and `papers-index-commit`; commit
  `4d95feb`, and `6884b5a` removed a stray LaTeX original,
  `lattner-2020-mlir/implications.tex.orig`): 98 entries — 20 stored as TeX (arXiv
  e-prints), 14 stored as PDF (no TeX available), 37 link-only (DOI recorded, no OA copy
  obtained) and 27 unresolved rows. Link-only then meant: `dl.acm.org` blocked (HTTP 403)
  and the item's only indexed OA location on ACM; Elsevier/ScienceDirect PDFs returned HTTP
  403; Springer landing pages are not OA; two green-OA repositories were intermittently
  unavailable.
- **Sources pass** (commit `ae672fe`): the documentation and code snapshots, the pointers,
  the harvested bibliography and the handoff to the report. Sources only: the report was
  deferred. The manifest said that unresolved rows should be re-attempted in the
  `papers-other` step before giving up; the papers and open-access passes did.
- **Open-access pass**: authorized open-access copies of link-only and unresolved papers
  (next section), stored in `sources/oa-papers/` (also commit `ae672fe`).
- **Bib-verify pass**: bibliography entries for the catalogued papers (see
  [Bibliography](#bibliography)).

The library merge of 2026-09-27 moved all of it here and merged the two paper trees (see
[Where the old files went](#where-the-old-files-went)). [INDEX.md](INDEX.md) has the current
counts.

- **Array-languages passes** (2026-10-09), for proposal 0004: five parallel passes, each
  staging its folders outside the repository, then one catalogue pass that merged their
  records into [INDEX.md](INDEX.md), this file and [bibliography.bib](bibliography.bib),
  checked that no entry duplicated one already here (the overlaps are cross-linked: for
  example `shivers-2019-remora`, `henriksen-2017-futhark`, `lattner-2020-mlir`, and the
  Slepak, Xi, Trojahner, Accelerate, Lift, ELEVATE and Triton entries already in the
  bibliography), and verified that every new folder records the bytes and SHA-256 of its
  files. Outcomes: 42 papers stored (6 arXiv TeX, 1 author TeX, 25 PDF, 2 PostScript, 7
  HTML, 1 repository text extraction), 6 link-only, 3 unresolved rows resolved
  (`henriksen-thesis`, `sac-language`, `dex-papers`), 19 new snapshots and the `code/idris2/`
  and `code/mlir/` addenda; `code-dex` and `code-futhark` moved from
  [Planned sources not collected](#planned-sources-not-collected) into the library.

## Open-access acquisition

The record of the open-access pass (formerly `sources/oa-locations.md`), for the targets the
access record listed as DOI-only (§3b, no ready OA fetch URL) and unresolved (§3c), plus
the defunctionalization rows unresolved in the manifest's cross-cutting table. Per target:
whether an authorized open-access copy was found, the best direct URL, host, version,
licence, and the API or site that surfaced it. For a downloaded copy these are in its paper
README; the rest are under [Papers not stored](#papers-not-stored).

- **Pass run:** 2026-09-26.
- **Discovery APIs:** Unpaywall (`/v2/<doi>`), OpenAlex (`/works/doi:<doi>`,
  `/works?search=`, `locations`), Crossref (title resolution only, for DOIs OpenAlex could
  not find), arXiv `e-print` (TeX source) and the arXiv Atom API, and publisher, author and
  lab pages.
- **Downloaded to** `docs/research/sources/oa-papers/<shortname>/`, each with a README; now
  merged into `papers/`.
- **Not attempted:** Sci-Hub, Library Genesis, or any paywall-bypassing or pirate mirror
  (see [Licences](#licences)).
- **Cap:** 20 MB per file; nothing downloaded exceeded it.

Result summary:
- **Targets processed:** 80 rows — 51 DOI-only rows (§3b), 27 unresolved rows (§3c), and 2
  defunctionalization rows unresolved in the manifest's cross-cutting table (`cejtin-2000`,
  `huang-yallop-2023`).
- **OA copies found and downloaded: 32.** Stored as TeX source: 1, `pal-2023-ruler` (arXiv
  `e-print`, unpacked LaTeX). Stored as PDF: 30. Stored as PostScript: 1,
  `wadler-linear-types` (`linear.ps`; the author hosts only PS). 15 of the 32 duplicated
  the papers pass (see [Where the old files went](#where-the-old-files-went)).
- **OA located but not fetchable from this host** (blocked, 403, or unreachable): 8
  (`lorenzen-2024`, `teiiscak-2020`, `christiansen-2016`, `taha-2000`, `wadler-1990`,
  `gill-1993`, `lorenzen-2022`, `lafont-1997`); also `massalin-1987`, `lamping-1990`,
  `turchin-1986` and `certicoq`, all publisher gold or bronze at `dl.acm.org` (403).
- **No OA copy found** (closed; needs a subscription or the author): the rest of
  [Papers not stored](#papers-not-stored).
- **Unresolved rows resolved to a concrete identifier** (even where the paper stayed
  inaccessible):

| Previously unresolved row | Resolved identifier | Now |
| --- | --- | --- |
| fractional uniqueness | `10.1145/3649848` (Functional Ownership through Fractional Uniqueness) | stored, `papers/marshall-2024-fractional-uniqueness/` |
| Secrets of the GHC Inliner | `10.1017/S0956796802004331` (the candidate `…4270` was wrong) | link-only |
| MLIR (CGO 2021) | `10.1109/CGO51591.2021.9370308` | link-only |
| `cejtin-2000-defunctionalization` | `10.1007/3-540-46425-5_4` | link-only |
| `huang-yallop-2023-defunctionalization` | `10.1145/3591241` | stored, `papers/huang-2023-defunctionalization/` |
| `maranget-2008-pattern-matching` | `10.1145/1411304.1411311` | stored, `papers/maranget-2008-pattern-matching/` |
| `wadler-linear-types` | no DOI (IFIP 1990); author-hosted PostScript | stored, `papers/wadler-1990-linear-types/` |
| `hovgaard-2018-defunctionalisation` | `10.1007/978-3-030-18506-0_7` | stored, `papers/hovgaard-2018-defunctionalisation/` |
| `lafont-1997-interaction-combinators` | `10.1006/inco.1997.2643` | link-only |
| `certicoq` | `10.1145/3473591`; `10.1145/3703595.3705879` (CertiCoq-Wasm) | link-only |

**2026-10-09.** The array-languages passes found open copies on author, lab and project
sites for most ACM and Springer papers whose publisher copy is closed (the §3e table names
each host), used the Wayback Machine for one dead author page (`grelck-2006-sac`), and took
the McDonell copies from the Git LFS host behind `tmcdonell.github.io`, whose pointer oid
matches the stored file's SHA-256. Two copies carry personal-use terms
(`trojahner-2009-qube`, `cockx-2016-unifiers-as-equivalences`): they are stored for study and
must not be redistributed. What could not be fetched is under
[Papers not stored](#papers-not-stored).

**HAL.** `leroy-2009-compcert` also has an author HAL deposit
(`https://inria.hal.science/inria-00415861`, version 1). HAL serves an **Anubis**
bot-protection challenge to scripted clients; the open-access pass intentionally did not
solve or evade it and used the author's own site copy instead. Any future automated HAL
fetch would require solving the challenge through a real browser session. (The papers pass
had fetched `inria-00415861v1/document` with HTTP 200 the same day; both copies are
stored.)

## Papers not stored

Every paper target with an identifier or a concrete title that has no copy in the library:
where an authorized copy exists, what blocked it, and what it would take. `blocked` means
publisher gold or bronze open access that a host blocks for scripted fetches: the copy is
authorized, so a browser download or another host would obtain it. `no` means closed, with
no authorized OA copy found: it needs an institutional subscription, interlibrary loan or
the author. A paper obtained later goes in `papers/<author>-<year>-<slug>/` (for most
rows, the shortname used here, as the manifest planned) and moves to the stored table of
[INDEX.md](INDEX.md).

| Target | DOI | OA found | Best direct URL | Host | Version | Licence | Surfaced by | Result | What it would take |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `lorenzen-2024-oxidizing-ocaml` | 10.1145/3674642 | blocked | https://www.research.ed.ac.uk/files/475247237/LorenzenEtalPACMPL2024OxidizingOCamlWith.pdf | repository (Univ. of Edinburgh) | submitted | CC-BY | Unpaywall / OpenAlex | **not downloaded** (HTTP 403) | browser download of the Edinburgh PDF, or author email |
| `lorenzen-2022-frame-limited-reuse` | 10.1145/3547634 | blocked | https://dl.acm.org/doi/pdf/10.1145/3547634 | publisher (ACM gold) | published | CC-BY | Unpaywall | **not downloaded** (dl.acm.org 403) | browser download via ACM CC-BY page |
| `bolingbroke-2010-supercompilation-by-eval` | 10.1145/1863523.1863540 | no | — | — | — | ACM © | Unpaywall (closed); only CiteSeerX stubs | **inaccessible** | ACM subscription / interlibrary loan / author email (Bolingbroke, Peyton Jones) |
| `brady-2004-inductive-families` | 10.1007/978-3-540-24849-1_8 | no | — | — | — | Springer © | Unpaywall (closed) | **inaccessible** | Springer institutional subscription / author email (Brady) |
| `lee-2001-size-change` | 10.1145/360204.360210 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** | ACM subscription / author email (Ben-Amram) |
| `wurthinger-2017-practical-partial-eval` | 10.1145/3062341.3062381 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** | ACM subscription / author email (Würthinger) |
| `wurthinger-2013-one-vm` | 10.1145/2509578.2509581 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** | ACM subscription / author email |
| `teiiscak-2020-erasure-calculus` | 10.1145/3408973 | blocked | https://dl.acm.org/doi/pdf/10.1145/3408973; St Andrews accepted copy unreachable | publisher (ACM gold) / repository | published / accepted | CC-BY | Unpaywall / OpenAlex | **not downloaded** (ACM 403; St Andrews host down) | browser download via ACM CC-BY page, or retry St Andrews |
| `taha-2000-metaml` | 10.1016/S0304-3975(00)00053-0 | blocked | https://www.sciencedirect.com/science/article/pii/S0304397500000530/pdf | publisher (Elsevier, bronze) | published | Elsevier © | Unpaywall | **not downloaded** (ScienceDirect 403) | browser/ScienceDirect access |
| `christiansen-2016-elaborator-reflection` | 10.1145/2951913.2951932 | blocked | https://research-repository.st-andrews.ac.uk/bitstream/10023/9522/1/elab_reflection_paper.pdf | repository (St Andrews) | submitted | ACM © | Unpaywall / OpenAlex | **not downloaded** (St Andrews host unreachable; ACM ft_gateway 403) | retry St Andrews repository / author email |
| `wadler-1990-deforestation` | 10.1016/0304-3975(90)90147-A | blocked | https://www.sciencedirect.com/science/article/pii/030439759090147A/pdf | publisher (Elsevier, bronze) | published | Elsevier © | Unpaywall | **not downloaded** (ScienceDirect 403) | browser/ScienceDirect access |
| `gill-1993-short-cut` | 10.1145/165180.165214 | blocked | https://dl.acm.org/doi/pdf/10.1145/165180.165214 | publisher (ACM gold) | published | not stated | Unpaywall | **not downloaded** (dl.acm.org 403) | browser download via ACM page |
| `coutts-2007-stream-fusion` | 10.1145/1291151.1291199 | no | — | — | — | ACM © | Unpaywall (closed); MSR copy 403 | **inaccessible** | ACM subscription / author email (Coutts) |
| `massalin-1987-superoptimizer` | 10.1145/36206.36194 | blocked | https://dl.acm.org/doi/pdf/10.1145/36206.36194 | publisher (ACM gold) | published | not stated | Unpaywall | **not downloaded** (dl.acm.org 403) | browser download via ACM page |
| `bansal-2006-peephole-superoptimizer` | 10.1145/1168918.1168906 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** | ACM subscription / author email (Aiken) |
| `joshi-2002-denali` | 10.1145/512529.512566 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** | ACM subscription / interlibrary loan |
| `pnueli-1998-translation-validation` | 10.1007/BFb0054170 | no | — | — | — | Springer © | Unpaywall (closed) | **inaccessible** | Springer subscription / author email / Weizmann report |
| `lafont-1990-interaction-nets` | 10.1145/96709.96718 | no | — | — | — | ACM © | Unpaywall (closed) | **inaccessible** | ACM subscription / author email (Lafont) |
| `lamping-1990-optimal-reduction` | 10.1145/96709.96711 | blocked | https://dl.acm.org/doi/pdf/10.1145/96709.96711 | publisher (ACM gold) | published | not stated | Unpaywall | **not downloaded** (dl.acm.org 403) | browser download via ACM page |
| `reynolds-1972-definitional-interpreters` | 10.1145/800194.805852 | no | Syracuse `surface.syr.edu/lcsmith_other/13` has no direct PDF | — | — | ACM © | Unpaywall / OpenAlex (closed) | **inaccessible** | ACM subscription / Syracuse repository direct request |
| `turchin-1986-supercompiler` | 10.1145/5956.5957 | blocked | https://dl.acm.org/doi/pdf/10.1145/5956.5957 | publisher (ACM bronze) | published | not stated | Unpaywall | **not downloaded** (dl.acm.org 403) | browser download via ACM page |
| `taha-2004-gentle-intro-multistage` | 10.1007/978-3-540-25935-0_3 | no | — | — | — | Springer © | Unpaywall (closed) | **inaccessible** | Springer subscription / author email (Taha) |
| `rompf-2010-lms` | 10.1145/1868294.1868314 | no | — | — | — | ACM © | Unpaywall / OpenAlex (closed) | **inaccessible** | ACM subscription / author email (Rompf) |
| `blackburn-2008-immix` | 10.1145/1375581.1375586 | no | ANU repository 503; no author copy found | — | — | ACM © | Unpaywall / OpenAlex (closed) | **inaccessible** | ACM subscription / retry ANU Open Research repository / author email (Blackburn) |
| `secrets-ghc-inliner` | 10.1017/S0956796802004331 (resolved; candidate `…4270` was wrong) | no | — | — | — | CUP © | Crossref title | **inaccessible** | CUP subscription / interlibrary loan / MSR author copy request |
| `mlir-cgo-2021` | 10.1109/CGO51591.2021.9370308 (resolved) | no | — | — | — | IEEE © | OpenAlex title | **inaccessible** | IEEE Xplore subscription / author email |
| `cejtin-2000-defunctionalization` | 10.1007/3-540-46425-5_4 (resolved) | no | — | — | — | Springer © | OpenAlex title | **inaccessible** | Springer subscription / interlibrary loan |
| `lafont-1997-interaction-combinators` | 10.1006/inco.1997.2643 (resolved) | blocked | https://www.sciencedirect.com/science/article/pii/S0890540197926432/pdf | publisher (Elsevier, bronze) | published | Elsevier © | OpenAlex title → Unpaywall | **not downloaded** (ScienceDirect 403) | browser/ScienceDirect access |
| `certicoq` | 10.1145/3473591, 10.1145/3703595.3705879 (resolved) | blocked | https://dl.acm.org/doi/pdf/10.1145/3473591; https://dl.acm.org/doi/pdf/10.1145/3703595.3705879 | publisher (ACM gold) | published | CC-BY | Crossref title → Unpaywall | **not downloaded** (dl.acm.org 403) | browser download via ACM CC-BY page |
| `brady-2013-thesis` | n/a | no | St Andrews repository unreachable | — | — | — | access record | **inaccessible** | author email; retry St Andrews repository when reachable; Wayback of author page |
| `christiansen-thesis` | n/a | no | no OA URL located | — | — | — | access record | **inaccessible** | author email; retry St Andrews repository when reachable; Wayback of author page |
| `teiiscak-2020-erasure-thesis` | n/a | no | St Andrews repository unreachable | — | — | — | access record | **inaccessible** | author email; retry St Andrews repository when reachable; Wayback of author page |
| `henriksen-thesis` | n/a | no | no OA URL located | — | — | — | access record | **inaccessible** | author email; retry St Andrews repository when reachable; Wayback of author page |
| `abel-foetus` | n/a (tech report) | no | author `/foetus/` path 404 | — | — | — | access record | **inaccessible** | author email (Abel) |
| `futamura-projections` | none | no | no DOI/OA copy located | — | — | — | access record | **inaccessible** | library scan / interlibrary loan |
| `wadler-1987-pattern-matching` | none | no | no DOI/OA copy located | — | — | — | access record | **inaccessible** | library scan / author email (Wadler) |
| `hui-2020-apl-since-1978` | 10.1145/3386319 | blocked | https://dl.acm.org/doi/pdf/10.1145/3386319 | publisher (ACM, PACMPL) | published | CC-BY 4.0 (Crossref) / CC-BY-SA (OpenAlex) | OpenAlex, Semantic Scholar, Crossref (2026-10-09) | **not downloaded** (HTTP 403) | browser download of the ACM PDF (gold OA) |
| `bernecky-1988-function-rank` | 10.1145/55626.55632 | no | — | — | — | ACM © | OpenAlex (closed) | **inaccessible** | ACM subscription or the author |
| `hsu-2019-data-parallel-compiler` (PDF) | hdl:2022/24749 | yes | https://scholarworks.iu.edu/iuswrrest/api/core/bitstreams/dcbd5240-8454-4533-bc0c-ac3ee7628b8e/content | repository (IUScholarWorks) | published | "may be protected by copyright" | DSpace REST | **not stored**: 30,678,406 bytes, over the 20 MB cap (SHA-256 `91017caa3a4f551b6b8c6f85603e558bd2a034213890fb47e406a705c8c7e107`); the text extraction is stored | a decision to raise the cap for it, or keep it link-only |
| `diatchki-2015-smt` (published PDF) | 10.1145/2804302.2804307 | no | — (the author TeX is stored instead; the author's PDF at `yav.github.io` was fetched, not stored) | — | — | ACM © | Unpaywall (closed); web search | **PDF not stored; TeX source stored** | ACM subscription, to confirm the camera-ready text |
| `cockx-2021-taming-rew` | 10.1145/3434341 | yes (HAL; PACMPL gold) | https://hal.science/hal-02901011v2/document | HAL | accepted / published | CC-BY expected for PACMPL (verify) | Agda manual (`rewriting.lagda.rst`), author page | **not stored**: HAL served an Anubis challenge; `dl.acm.org` 403 | a browser session for HAL, or the ACM PDF |
| `cockx-2016-without-k` | 10.1017/S0956796816000174 | yes | Cambridge Core PDF (§1b) | Cambridge Core | published | CUP © | web search | fetched, **not stored**: revised as chapters 2 and 4 of `cockx-2017-dependent-pattern-matching-thesis` | nothing; store it if the journal text is wanted |
| `cockx-2018-proof-relevant-unification` | 10.1017/S095679681800014X | yes | https://jesper.cx/files/proof-relevant-unification.pdf | author site | author version | CUP © | author page | fetched, **not stored**: revised as chapter 3 of the thesis | nothing; store it if wanted |
| `gregoire-2005-ring` | 10.1007/11541868_7 | HAL (Anubis) | — | HAL | — | Springer © | Frex related work | **not attempted** beyond identification | a browser session for HAL |

The rest have no canonical target to fetch and are in [INDEX.md](INDEX.md)'s "Unresolved"
tables: the rows the plan gave no author or title for (warm and shortcut fusion,
destination-passing style, SaC, MLGO/CompilerGym, autotuning surveys, e-graph extraction
(ILP/MaxSAT)) — accept the gap, or pick references and say so; the books and project pages
to be kept as pointers (Garbage Collection Handbook, a paid book; Boehm GC and precise
tracing GC; *Partial Evaluation and Automatic Program Generation*; the GMP manual and
*Modern Computer Arithmetic*); and the docs, code and sweep rows the open-access pass left
out of scope (`code-koka`, `idris-vect-material`, `sweep-2024-2026`).

## Planned sources not collected

The manifest's code, documentation and pointer rows that were planned and not collected.
"Would go in" gives the place in this layout (the manifest named the same places under
`sources/`); pins for the repositories are in [Pins](#pins).

| Shortname | What | Threads | Harvest method (planned) | Would go in | Licence | Outcome |
| --- | --- | --- | --- | --- | --- | --- |
| `code-eqsat-dialects` | DialEgg and the MLIR `eqsat` dialect source | B, F | pinned LLVM (planned at `llvmorg-23.1.2`; the pin is now main `7208ba24`); DialEgg repo | `code/mlir-eqsat/` | Apache-2.0 WITH LLVM-exception / DialEgg verify | not collected |
| `code-egg-repos` | egg / egglog repositories | B | pinned GitHub `2f31b28e…` (egg), `90635860…` (egglog) | `code/egg/`, `code/egglog/` | MIT | not collected |
| `book-pe-jones-gomard-sestoft` | *Partial Evaluation and Automatic Program Generation* (book) | C | author-hosted free PDF → pointer | `docs/pe-book/` (pointer) | author-hosted free | not collected |
| `book-gc-handbook` | Garbage Collection Handbook | D | no OA; pointer only | `docs/gc-handbook/` (pointer) | book © | not collected |
| `boehm-gc` | Boehm GC (project/tech report) | D | project page → pointer | `docs/boehm-gc/` (pointer) | verify | not collected |
| `abel-foetus` | foetus — termination checker for simple functional programs | E | author host; no DOI | `docs/foetus/` (pointer) | TBD | unresolved: author `/foetus/` path 404 |
| `docs-mojo` | Mojo docs | F | `docs.modular.com/mojo/` | `docs/mojo/` | Apache-2.0 WITH LLVM-exception | in part: five pages on inline MLIR, the `pop` dialect and parameters (2026-10-09); the rest not collected |
| `docs-iree` | IREE docs | F | `iree.dev` | `docs/iree/` (pointer) | Apache-2.0 verify | not collected |
| `code-polygeist` | Polygeist | F | `polygeist.pages.dev` / repo → pointer | `code/polygeist/` (pointer) | Apache-2.0 WITH LLVM-exception verify | not collected |
| `code-dex` | `google-research/dex-lang` source | G | pinned GitHub `25e2e389…` | `code/dex/` | BSD-3-Clause (was recorded as Apache-2.0) | collected 2026-10-09: 13 files |
| `code-futhark` | Futhark source | G | pinned GitHub `304c56ff…` | `code/futhark/` | ISC (was recorded as BSD-3-Clause) | collected 2026-10-09: 20 files, and 5 docs in `docs/futhark/` |
| `idris-vect-material` | Idris `Vect`/index-typed array material; tinygrad symbolic shapes | E, G, A | Idris2 pinned docs/source; tinygrad pinned source | `docs/idris2/`, `code/idris2/`, `code/tinygrad/` | BSD-3-Clause / MIT verify | not collected as such; the tinygrad symbolic-shape modules are in `code/tinygrad/`, and `libs/base/Data/Nat.idr` with the `rewrite` elaborator in the `code/idris2/` addendum (2026-10-09) |
| `mlgo-compilergym` | MLGO / CompilerGym | H | project pages + papers; probe | `docs/mlgo-compilergym/` (pointer) | TBD | unresolved |
| `code-hvm` | HVM2 source + docs | J | pinned GitHub `7365a56c…` | `code/hvm/` | verify | not vendored |
| `code-bend` | Bend source + docs | J | pinned GitHub `574b6d39…` | `code/bend/` | verify | not vendored |
| `inpla-inets` | Inpla / inets | J | repo/author host → pointer | `docs/inpla-inets/` (pointer) | TBD | unresolved |
| `code-lean4-lcnf-specinfo` | Lean 4 `LCNF` and `SpecInfo` | cross-cutting | lean4 repo pinned at fetch time → pointer/excerpts | `code/lean4/` | Apache-2.0 | not collected; `code/lean4/` now exists at `7cd10322` with the rewrite tactics (2026-10-09), and these files would join it at that pin |
| `pointers-ocaml-flambda` | OCaml Flambda | cross-cutting | repo/docs → pointer | `docs/ocaml-flambda/` (pointer) | verify | not collected |
| `pointers-swift-sil` | Swift SIL | cross-cutting | docs → pointer | `docs/swift-sil/` (pointer) | Apache-2.0 verify | not collected |
| `pointers-rust-mir` | Rust MIR | cross-cutting | docs → pointer | `docs/rust-mir/` (pointer) | MIT/Apache-2.0 verify | not collected |
| `pointers-dotnet-ryujit` | .NET RyuJIT | cross-cutting | docs → pointer | `docs/dotnet-ryujit/` (pointer) | MIT verify | not collected |
| `grin` | GRIN | cross-cutting | papers/repo → pointer | `docs/grin/` (pointer) | TBD | unresolved |
| `code-koka` | Koka | D, cross-cutting | repo/docs → pointer | `code/koka/` (pointer) | verify | not collected |
| `pointers-gmp-manual` | GMP manual | cross-cutting | `gmplib.org` → pointer | `docs/gmp/` (pointer) | GFDL verify | not collected |
| `pointers-modern-computer-arithmetic` | *Modern Computer Arithmetic* (free book) | cross-cutting | author-hosted PDF → pointer | `docs/mca/` (pointer) | free book verify | not collected |
| `code-idris-integer-string` | Idris `Integer`/`String` | cross-cutting, E | Idris2 pinned source | `code/idris2/` | BSD-3-Clause verify | not collected |

The sources pass also left the pointer files for large non-documentation, non-code sources
(memory and GC, prior-art compilers, defunctionalisation, and so on) to the phases owning
those threads. For GHC, the manifest planned pointers plus small `.hs` excerpts
(`code/ghc/`); only the pointer was written (`docs/ghc/SNAPSHOT.md`).

## Bibliography

[bibliography.bib](bibliography.bib) aggregates the `.bib` files of the paper folders and
entries added to cover the catalogued papers, de-duplicated by citation key
(case-insensitive), DOI and title.
- **Sources pass:** 680 entries harvested from 13 per-paper `.bib` files (read-only) → 596
  unique; one malformed entry (missing closing brace) removed; 46 entries appended by the
  bib-verify pass for catalogued papers absent from the harvest (metadata from the papers
  index, the access record, and Crossref for the eight rows the open-access pass resolved)
  → 642 entries. Rows with unknown metadata were deliberately not entered; the file's last
  comment block lists them.
- **Library merge (2026-09-27):** 4 entries for library papers that had none
  (`kovacs-2022-staged`, `lopes-2015-alive`, `lopes-2021-alive2`,
  `koehler-2024-guided-eqsat`; the bib-verify pass's title matching had taken a different
  paper for each), and the 7 per-paper entries the harvest's parser skipped (six in
  `shivers-2019-remora/refs.bib`, one in `ullrich-2019-counting-immutable-beans/refcount.bib`)
  → 653 entries, no two sharing a key, DOI or normalized title. Two given names were
  corrected against the paper sources (`bhat-2022-lambda-ultimate-ssa`, `pal-2023-ruler`).
- **Array-languages passes (2026-10-09):** 44 entries appended in a final section, keyed by
  the library shortnames (papers, link-only rows, and eight snapshots cited as sources) →
  697 entries, no two sharing a key or DOI. Twelve papers already had an entry under another
  key and were not entered twice (the list is in that section's header); five of those
  entries were completed in place: `DMLBoundsChecking` (doi), `trojahner2009dependently` (the
  mis-encoded apostrophe of "don't", doi), `Slepak:PhD` (the note "In preparation" replaced
  by month and url), `APL` (url), `RingSolver` (doi).
- **Sources:** the 13 per-paper files are `bhat-2022-lambda-ultimate-ssa/references.bib`,
  `brady-2021-idris2-qtt/idris-qtt.bib`, `koehler-2021-sketch-eqsat/reference.bib`,
  `lattner-2020-mlir/references.bib`, `shivers-2019-remora/refs.bib`,
  `ullrich-2019-counting-immutable-beans/refcount.bib`, `wang-2020-spores/vldb2020.bib`,
  `willsey-2021-egg/references.bib`, `wu-2026-slotted-egraphs/ref.bib`,
  `yang-2021-tensat/main.bib`, `zhang-2022-relational-ematching/main.bib`,
  `zhang-2023-egglog/references.bib` and `zheng-2020-ansor/ansor.bib`, under `papers/`.
  They stay in their folders as part of the TeX sources. If the corpus grows, re-harvest
  rather than editing by hand.

## Corrections

Places where the plan's identifiers, the access record, or an earlier pass did not match
what the hosts served or what the sources say. Trust these, not the earlier rows.

**From the access pass** (identifier resolution, §3):
- `wang-2020-spores`: the plan's `2003.02423` is an unrelated physics paper; `2002.07951`
  is SPORES.
- `yang-2021-tensat`: the plan's `2011.02043` is an unrelated mapping paper; `2101.01332`
  is Tensat.
- `kovacs-2022-staged`: the plan's `2204.05653` is Kudasov's "Free Monads…";
  `2209.09729` is the paper.
- `koehler-2024-guided-eqsat`: the plan's candidate `2306.07214` is an X-ray astronomy
  paper.
- `reinking-2021-perceus`: the plan's `2004.02812` is a math paper.
- `pal-2023-ruler`: the published title differs from the plan's "Ruler"; the tool is Ruler.
- `bhat-2024-verifying-peephole`: OpenAlex mislinks this DOI to a Vasilache MLIR-2 paper;
  the title was verified from search and LIPIcs.
- `chataing-2024-unboxed-data-constructors`: the plan said "Alexis King, ICFP 2024"; the
  authors and venue are as in [INDEX.md](INDEX.md).
- `ikarashi-2022-exo`: the plan said ASPLOS 2021; it is PLDI 2022.
- IDs the plan left "to confirm": sketch-guided equality saturation is
  `koehler-2021-sketch-eqsat`; the Transform Dialect (CGO 2025) is
  `lucke-2024-transform-dialect`; Remora is `shivers-2019-remora`; slotted e-graphs and
  binders are `wu-2026-slotted-egraphs`, a future-dated ID to verify at fetch time.

**From the papers pass** (the former `papers/INDEX.md`, "Corrections and discrepancies
found while fetching"):
1. `taha-2000-metaml` and `wadler-1990-deforestation`: ScienceDirect is 403, not 200. The
   access record labelled both "ScienceDirect PDF (verified 200)"; live probes on
   2026-09-26 returned HTTP 403 (`text/html`), so both are link-only. OpenAlex also reports
   them as OA PDFs on ScienceDirect, so the OA flag itself is unreliable.
2. `bhat-2024-verifying-peephole`: OpenAlex maps DOI `10.4230/LIPIcs.ITP.2024.9` to
   `https://arxiv.org/pdf/2202.03293`, but that arXiv record is "Composable and Modular
   Code Generation in MLIR". The correct OA source is the LIPIcs DROPS PDF
   (`lipics-vol309-itp2024/LIPIcs.ITP.2024.9`), whose title was verified; it was stored
   from LIPIcs, not arXiv.
3. `pal-2023-ruler`: the access record resolved only the ACM DOI (`10.1145/3622834`, ACM
   403). OpenAlex's location list exposed arXiv `2609.14527` ("Equality saturation theory
   exploration à la carte"), verified through the arXiv API, so the TeX was fetched instead
   of a link.
4. `chen-2018-tvm`: listed in §3b as a DOI with an arXiv OA fetch (`1802.04799`); stored as
   TeX. A USENIX OSDI PDF (`https://www.usenix.net/system/files/osdi18-chen.pdf`) is a
   second OA copy.
5. `ragankelley-2013-halide`: the `citation_pdf_url` DSpace exposes
   (`/bitstreams/<uuid>/download`) returns HTTP 405; the file is only retrievable through
   the DSpace REST content endpoint (`/server/api/core/bitstreams/<uuid>/content`). Item
   metadata confirmed the Halide title.
6. `brady-2004-inductive-families`, `taha-2004-gentle-intro-multistage`,
   `pnueli-1998-translation-validation`: the access record listed them as "Springer
   landing"; none exposes an OA PDF, so they are link-only.
7. The St Andrews repository stayed unreachable: HTTP 000 in the access record, 503 during
   the papers pass. `christiansen-2016-elaborator-reflection` (St Andrews PDF in OpenAlex)
   and the two St Andrews theses stayed unresolved or link-only.
8. `wu-2026-slotted-egraphs`: the access record flagged arXiv `2609.03998` as future-dated,
   to verify at fetch time; it returned HTTP 200 and the raw LaTeX unpacked normally.
   Likewise `2609.14527` (the Ruler parallel) resolved.
9. `koehler-2024-guided-eqsat`: the access record's OA fetch (arXiv `2111.13040`) is the
   *sketch* paper, stored as `koehler-2021-sketch-eqsat`. The Guided Equality Saturation
   paper (DOI `10.1145/3632900`) was not obtained and is recorded link-only, to avoid
   duplicating the sketch paper.
10. Extra green-OA copies located through OpenAlex, beyond the access record: CompCert
    (HAL), TACO, Exo and Halide (DSpace@MIT), Futhark (author site), Halide-learning
    (eScholarship), STOKE and Alive (author sites), and Ruler (arXiv), where the access
    record had only "author host / ACM 403" or "ACM 403". Conversely, some green-OA
    locations OpenAlex reports were not usable: Edinburgh (403), Utrecht (no direct PDF),
    ETH (500), Chalmers (no PDF), ANU (503), eScholarship PDFs (need a browser User-Agent).

**From the sources pass** (the former `sources/README.md`):
- `third_party/Idris2` was not checked out, so the Idris 2 documentation and code
  snapshots were fetched from the pinned raw GitHub URLs
  (`https://raw.githubusercontent.com/idris-lang/Idris2/1c630e67.../...`) rather than read
  from the local submodule. Reading `third_party/Idris2/src/...` locally needed
  `git submodule update --init` first; that does not change this corpus. (It is checked out
  now, at the same pin.)
- Erasure is not in a `Compiler/Erase.idr`; there is no such file. It lives in
  `code/idris2/src/Core/LinearCheck.idr` (multiplicity and erasure inference with `Erased`
  nodes) plus the `eraseArgs` / `safeErase` fields of `GlobalDef` in
  `code/idris2/src/Core/Context/Context.idr`.
- Idris 2 case optimization is `src/Compiler/CaseOpts.idr`, not `CaseOpt.idr`.
- `TTImp` is `src/TTImp/**`, not `src/Core/TTImp/**`.
- MLton RSSA lives under `mlton/backend/` (`ssa2-to-rssa.fun`, `rssa.fun`,
  `packed-representation.fun`), not a `mlton/rssa/` directory.
- `RewriterBase` has no separate header at this pin: it is declared in
  `code/mlir/include/mlir/IR/PatternMatch.h`, which is vendored.
- tinygrad's BEAM search is `tinygrad/codegen/opt/search.py`, located from the pinned
  `tinygrad/codegen/{opt,late,decomp}` trees, not guessed.
- GHC has no `inliner` or `unarisation` commentary pages (HTTP 404 at fetch time). The
  nearest captured material is `docs/ghc/commentary-compiler-core-to-core-pipeline.md`,
  `...-opt-ordering.md`, `...-code-gen.md` and `...-backends.md`.
- Several MLIR dialects named in the plan (`arith`, `cf`, `index`, `ptr`, `scf`, `ub`,
  `pdl`) have no standalone `.md` in `mlir/docs/Dialects/` at `llvmorg-23.1.2`; their docs
  are generated from ODS/TableGen and covered by the full `docs/mlir/` snapshot. LLVM's
  DataLayout has no separate file: it is in `LangRef`.
- ScienceDirect returned HTTP 403, not 200 (see papers-pass item 1); both papers are
  link-only.
- `ssabook.gforge.inria.fr` is dead; the PDF was retrieved through the Wayback Machine.

**From the library merge** (2026-09-27), checked against the TeX sources or Crossref:
- `bhat-2022-lambda-ultimate-ssa` is by Siddharth Bhat (its README said "Sameer", the
  bibliography "Utkarsh").
- `lucke-2024-transform-dialect` has five authors (Lücke, Zinenko, Moses, Steuwer, Cohen);
  three were recorded.
- `pal-2023-ruler` lists Amy Zhu and Oliver Flatt (recorded as "Yongwei Zhu, Zachery
  Flatt", "Amy Zhu, Zachary Flatt" and "Eric Zhu").
- The open-access pass's notes misnamed authors of `marshall-2022-linearity-uniqueness`
  and `marshall-2024-fractional-uniqueness` ("Will Marshall, Jan Vollmer"),
  `bhat-2024-verifying-peephole` ("Tobias Keizer") and `huang-2023-defunctionalization`
  ("Yizhou Huang").
- `yang-2021-tensat` is MLSys 2021: its source uses the accepted `mlsys2021` style (it was
  recorded as "PLDI 2021 Tensat").
- `panchekha-2015-herbie` is PLDI 2015, as the open-access pass recorded: its DOI is in the
  PLDI 2015 proceedings (`10.1145/2737924`, like Alive's). The access record and the papers
  index said POPL 2015.
- `huang-yallop-2023-defunctionalization` was an unresolved row of the manifest's
  cross-cutting table; the open-access pass's note cited it as access-record §3c.

**From the array-languages passes** (2026-10-09):
- `code-dex` was recorded as Apache-2.0 (verify): dex-lang's `LICENSE` is BSD-3-Clause.
  `code-futhark` was recorded as BSD-3-Clause (verify): Futhark's `LICENSE` is ISC.
- `trojahner2009dependently` in the bibliography carried a replacement character for the
  apostrophe in "don't"; fixed.
- `Slepak:PhD` in the bibliography (from `shivers-2019-remora/refs.bib`) said "In
  preparation"; the dissertation was completed in July 2020.
- One pass reported `DMLBoundsChecking` as malformed (duplicate `year` and `publisher`
  fields); the entry in this file is well formed and only lacked its DOI, now added.
- `hui-2020-apl-since-1978`: Crossref records CC-BY 4.0, OpenAlex and Semantic Scholar
  CC-BY-SA; the licence is recorded with both.
- `gibbons-2017-naperian`: Oxford lists pages 568–583, DBLP 556–583; the bibliography uses
  556–583 (verify against Springer).
- Xi's BU pages (`www.cs.bu.edu/~hwxi/...`) and Grelck's UvA staff pages are 404; the copies
  came from `www.cs.cmu.edu/~fp/`, `hwxi.github.io`, UvA-DARE and the Wayback Machine.
- `tmcdonell.github.io/papers/*.pdf` serves Git LFS pointer files (131 bytes), not PDFs;
  the PDFs are on `media.githubusercontent.com`.
- `vasilache-2022-structured-codegen`'s e-print ships a second, older copy of its sources in
  a subdirectory; it is kept as shipped, and the top-level files are the ones `ms.tex`
  inputs.

## Known holes

- **Empty `third_party/Idris2` at collection time.** The Idris 2 material came from pinned
  raw URLs (`1c630e67c386629a0fbbc6b78a59176fde7f0a76`). The submodule is checked out now,
  at the same pin, and can be read in place.
- **GHC `unarisation` gap** (`docs-ghc-unarisation`). No `commentary/compiler/unarisation`
  page exists (HTTP 404); the nearest captured material is
  `docs/ghc/commentary-compiler-code-gen.md`, `...-backends.md` and `...-data-types.md`.
- **Dead `ssabook.gforge.inria.fr`.** The SSA book PDF was fetched through the Wayback
  Machine (snapshot `20210621194509`); see `docs/ssa-book/SNAPSHOT.md`.
- **Dead `mlton.org`.** MLton material came from the pinned GitHub mirror.
- **Hosts that block or fail scripted fetches:** `dl.acm.org` (403), `sciencedirect.com`
  (403), `research.ed.ac.uk` (403), `research-repository.st-andrews.ac.uk` (503 or
  unreachable), `research-collection.ethz.ch` (500), ANU Open Research (503), and HAL
  (Anubis bot challenge, not solved or evaded). The affected papers are in
  [Papers not stored](#papers-not-stored).
- **Un-vendored source trees:** egg, egglog, HVM, Bend and GHC sources were planned or
  pointer-only; only their pins and URL patterns are recorded ([Pins](#pins),
  `docs/ghc/SNAPSHOT.md`). Fetch on demand when exact code is needed. dex-lang and Futhark
  are vendored as excerpts since 2026-10-09 (`code/dex/`, `code/futhark/`).
- **No `mlir/include/mlir/IR/RewriterBase.h`** at the pin: `RewriterBase` lives in
  `PatternMatch.h` (vendored). Likewise several dialect docs exist only as ODS-generated
  content covered by the full `docs/mlir/` snapshot; for the array dialects the ODS itself is
  now vendored (the `code/mlir/` addendum).
- **Addenda not merged.** `code/mlir/SNAPSHOT.addendum.md` and
  `code/idris2/SNAPSHOT.dependent-equality.md` describe files added on 2026-10-09; their
  text is to be merged into the two `SNAPSHOT.md` files (counts 94 → 132 and 30 → 38).
- **Hosts behind challenges (2026-10-09):** `code.jsoftware.com` (NuVoc) and `aplwiki.com`
  answer scripted fetches with a Cloudflare challenge, and HAL with Anubis; none was solved
  or evaded, so NuVoc, the APL Wiki, `cockx-2021-taming-rew` and `gregoire-2005-ring` are
  missing.
- **Over the cap:** the PDF of `hsu-2019-data-parallel-compiler` (30.7 MB); only the
  repository's text extraction is stored, so its figures and the layout of its APL code are
  lost.
- **Partial texts:** `iverson-1962-programming-language` holds only what Jsoftware
  transcribed (the preface, Chapter 1 and part of Chapter 3).
- **Personal-use copies:** `trojahner-2009-qube` and `cockx-2016-unifiers-as-equivalences`
  must not be redistributed.
- **Not yet indexed:** nineteen paper folders and six documentation snapshots added on
  2026-10-07 (commit `cb65104d`; listed in [INDEX.md](INDEX.md#summary) and under
  [Layout](#layout)) have no rows in [INDEX.md](INDEX.md) or in this file's tables.

## Open questions at handoff

The sources pass handed over (2026-09-26) with these questions, which the sources cannot
settle: each needs an experiment or a user decision. They are kept as recorded; the project
answers them in `docs/plan.md` and `docs/architecture/`.
- **Custom MLIR dialect and passes in C++ or not?** `docs/research/next-research-prompt.md`
  (removed in `27513bf`; git keeps it) framed this as the central open question; the corpus
  documents MLIR's facilities but cannot decide whether this project should add C++. It
  needed a research recommendation and user sign-off.
- **Does a linear/QTT binder imply unique heap ownership?** The sources (`LinearCheck.idr`,
  Perceus, FP²) show what the type system does; whether this backend can exploit it for
  in-place update needs a representation experiment.
- **Are indexed vectors contiguous?** `brady-2004` and `brady-2021` explain the erasure of
  indices; contiguous storage is an implementation choice to test, not to assume.
- **Erased ≠ constant.** Which erased values must still exist at runtime, and at what cost,
  is a per-constructor experiment.
- **Which cost model drives extraction and search?** Hand-written (tinygrad's heuristics)
  or learned (`mendis-2019-ithemal`)? The sources describe both; choosing needs
  measurement.
- **Do any of these passes pay off on Idris-generated IR?** Fusion, equality saturation,
  supercompilation and Transform-dialect schedules are all documented; none is measured on
  this project's IR. Claims must be marked *demonstrated* or *claimed* (the Thread J rule).
- **The 2024–2026 venue sweep** (`sweep-2024-2026`) is a live literature sweep that cannot
  be pre-enumerated; it must be run, recording demonstrated vs claimed.
- **Destination-passing style, SaC, warm and shortcut fusion, MLGO/CompilerGym,
  autotuning, and e-graph extraction (ILP/MaxSAT) surveys:** the plan selected no
  canonical reference; confirm the intent before citing.


## Additions of 2026-10-09: flattened data and type checking

Access records, licences, snapshots and papers not stored for the entries added on 2026-10-09 (the array-language entries are merged above). The Swift snapshots carry their own SNAPSHOT files (upstream, pinned revision, licence: Apache-2.0 with Runtime Library Exception).

#### Flattened data: packed, columnar and nested layouts — columnar: 2. Access record lines

**Reachability (§1), probed 2026-10-09:**

| Host | Status | What it serves | Notes |
| --- | --- | --- | --- |
| `static.googleusercontent.com` (`/media/research.google.com/en//pubs/archive/<n>.pdf`) | 200 | Google Research publication PDFs | `research.google.com/pubs/archive/<n>.pdf` redirects here. |
| `www.vldb.org` (`/pvldb/vldb2010/papers/R29.pdf`) | 200, `text/html` | a page shell, not the PDF | Not pursued; the Google copy was used. |
| `usr.lmf.cnrs.fr` (`/~jcf/publis/`) | 200 | J.-C. Filliâtre's publications | `www.lri.fr/~filliatr/...` now redirects to `usr.lmf.cnrs.fr/~jcf/` (the home page, not the file). |
| `blog.twitter.com` | 403 | redirects to `blog.x.com`, which refuses scripted fetches | Not evaded. |
| `archive.org` (`/wayback/available`) | 429 | Wayback availability API | Rate-limited; not retried. |
| `api.crossref.org`, `api.openalex.org` | 200 | DOI metadata, OA status | Used for both papers. |
| `api.github.com` (`/repos/<o>/<r>/git/trees/<sha>?recursive=1`) | 200 | tree listings | Unauthenticated limit 60 requests per hour. |
| `raw.githubusercontent.com` | 200 | files at a pinned commit | All snapshots. |

**Identifier resolution (§3):**

| Shortname | Identifier | Resolution | How |
| --- | --- | --- | --- |
| `melnik-2010-dremel` | DOI 10.14778/1920841.1920886 | resolved (PVLDB 3(1–2):330–339, 2010-09) | Crossref; OpenAlex: closed, no OA location |
| `filliatre-2006-hash-consing` | DOI 10.1145/1159876.1159880 | resolved (ML '06, pp. 12–19, 2006-09-16) | Crossref; OpenAlex: closed (one CiteSeerX metadata stub, not used) |

**Non-paper source URLs (§3d):**

| Source | Canonical base URL | Pin |
| --- | --- | --- |
| Arrow format docs | https://raw.githubusercontent.com/apache/arrow/446167169a0dc547e00e1bc29f417a40c0ca267a/ | tag `apache-arrow-26.0.0` |
| Arrow site (blog) | https://raw.githubusercontent.com/apache/arrow-site/bf8285bef4296db932fc9a2c81cebef929ee39b4/ | `main` at `bf8285be…` |
| Parquet format | https://raw.githubusercontent.com/apache/parquet-format/04d56f291ff963e98bc37ab8100e2fc133ff583c/ | tag `apache-parquet-format-2.14.0` |
| Parquet site | https://raw.githubusercontent.com/apache/parquet-site/14a991210815076568d0f334c36cf1db71d13c70/ | `main` at `14a99121…` |
| Zig | https://raw.githubusercontent.com/ziglang/zig/e4cbd752c8c05f131051f8c873cff7823177d7d3/ | tag `0.15.2` |
| StructArrays.jl | https://raw.githubusercontent.com/JuliaArrays/StructArrays.jl/4a1e271029b3c562bcff5056f1a861a24a76eb3e/ | tag `v0.7.3` |
| vector | https://raw.githubusercontent.com/haskell/vector/d9d0d46623fdecce7652f59caa4a28849292a0e7/ | tag `vector-0.13.2.0` |
| ocaml-hashcons | https://raw.githubusercontent.com/backtracking/ocaml-hashcons/9d6a7855e70ac59f8e434efdc301aa9c9bc81991/ | tag `1.4.0` |

**Pins rows:**

| Component | Pin | Resolved SHA | Source of truth command | In the library |
| --- | --- | --- | --- | --- |
| `apache/arrow` | `apache-arrow-26.0.0` | `446167169a0dc547e00e1bc29f417a40c0ca267a` | `git ls-remote https://github.com/apache/arrow.git 'refs/tags/apache-arrow-26.0.0^{}'` | `docs/arrow/` |
| `apache/arrow-site` | `main` | `bf8285bef4296db932fc9a2c81cebef929ee39b4` | `git ls-remote https://github.com/apache/arrow-site.git HEAD` | `docs/arrow-site/` |
| `apache/parquet-format` | `apache-parquet-format-2.14.0` | `04d56f291ff963e98bc37ab8100e2fc133ff583c` | `git ls-remote https://github.com/apache/parquet-format.git 'refs/tags/apache-parquet-format-2.14.0^{}'` | `docs/parquet-format/` |
| `apache/parquet-site` | `main` | `14a991210815076568d0f334c36cf1db71d13c70` | `git ls-remote https://github.com/apache/parquet-site.git HEAD` | `docs/parquet-site/` |
| `ziglang/zig` | `0.15.2` | `e4cbd752c8c05f131051f8c873cff7823177d7d3` | `git ls-remote https://github.com/ziglang/zig.git 'refs/tags/0.15.2^{}'` | `code/zig/` |
| `JuliaArrays/StructArrays.jl` | `v0.7.3` | `4a1e271029b3c562bcff5056f1a861a24a76eb3e` | `git ls-remote https://github.com/JuliaArrays/StructArrays.jl.git 'refs/tags/v0.7.3^{}'` | `code/structarrays/` |
| `haskell/vector` | `vector-0.13.2.0` | `d9d0d46623fdecce7652f59caa4a28849292a0e7` | `git ls-remote https://github.com/haskell/vector.git refs/tags/vector-0.13.2.0` | `code/vector/` |
| `backtracking/ocaml-hashcons` | `1.4.0` | `9d6a7855e70ac59f8e434efdc301aa9c9bc81991` | `git ls-remote https://github.com/backtracking/ocaml-hashcons.git 'refs/tags/1.4.0^{}'` | `code/ocaml-hashcons/` |

**Snapshots table rows:**

| Snapshot | Upstream | Revision | Files | Threads | Manifest rows |
| --- | --- | --- | --- | --- | --- |
| [`code/ocaml-hashcons/`](code/ocaml-hashcons/SNAPSHOT.md) | `backtracking/ocaml-hashcons` | `9d6a7855e70ac59f8e434efdc301aa9c9bc81991` (`1.4.0`) | 6 | columnar | — |
| [`code/structarrays/`](code/structarrays/SNAPSHOT.md) | `JuliaArrays/StructArrays.jl` | `4a1e271029b3c562bcff5056f1a861a24a76eb3e` (`v0.7.3`) | 15 | columnar | — |
| [`code/vector/`](code/vector/SNAPSHOT.md) | `haskell/vector` | `d9d0d46623fdecce7652f59caa4a28849292a0e7` (`vector-0.13.2.0`) | 8 | columnar | — |
| [`code/zig/`](code/zig/SNAPSHOT.md) | `ziglang/zig` | `e4cbd752c8c05f131051f8c873cff7823177d7d3` (`0.15.2`) | 5 | columnar | — |
| [`docs/arrow/`](docs/arrow/SNAPSHOT.md) | `apache/arrow` | `446167169a0dc547e00e1bc29f417a40c0ca267a` (`apache-arrow-26.0.0`) | 26 | columnar | — |
| [`docs/arrow-site/`](docs/arrow-site/SNAPSHOT.md) | `apache/arrow-site` | `bf8285bef4296db932fc9a2c81cebef929ee39b4` | 4 | columnar | — |
| [`docs/parquet-format/`](docs/parquet-format/SNAPSHOT.md) | `apache/parquet-format` | `04d56f291ff963e98bc37ab8100e2fc133ff583c` (`apache-parquet-format-2.14.0`) | 9 | columnar | — |
| [`docs/parquet-site/`](docs/parquet-site/SNAPSHOT.md) | `apache/parquet-site` | `14a991210815076568d0f334c36cf1db71d13c70` | 10 | columnar | — |

**Licences table rows:** `docs/arrow/`, `docs/arrow-site/`, `docs/parquet-format/`,
`docs/parquet-site/` Apache-2.0; `code/zig/` MIT (Expat); `code/structarrays/` MIT (Expat);
`code/vector/` BSD-3-Clause; `code/ocaml-hashcons/` LGPL-2.1 with the OCaml linking exception
(`COPYING` says version 2, `LICENSE` and headers 2.1; verify; study only, never copied into this
repository's code). Papers: `melnik-2010-dremel` © VLDB Endowment with a personal/classroom
permission notice, no open licence (verify); `filliatre-2006-hash-consing` ACM ©, author copy,
no open licence (verify).

**Fetch commands (§4), as run; read-only, nothing executed from the downloads:**

```bash
# pins
git ls-remote https://github.com/<owner>/<repo>.git HEAD 'refs/tags/<tag>' 'refs/tags/<tag>^{}'
# file lists at a pin
curl -s "https://api.github.com/repos/<owner>/<repo>/git/trees/<sha>?recursive=1"
# each snapshot file, one new directory per snapshot
curl -sL --fail -o "<path>" "https://raw.githubusercontent.com/<owner>/<repo>/<sha>/<path>"   # spaces as %20 for parquet-site

# papers, one new directory each
curl -sL --fail -o paper.pdf https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/36632.pdf
curl -sL --fail -o paper.pdf https://usr.lmf.cnrs.fr/~jcf/publis/hash-consing2.pdf

# metadata
curl -s "https://api.crossref.org/works/10.14778/1920841.1920886"
curl -s "https://api.crossref.org/works/10.1145/1159876.1159880"
curl -s "https://api.openalex.org/works/doi:10.14778/1920841.1920886"
curl -s "https://api.openalex.org/works/doi:10.1145/1159876.1159880"
```

**Papers not stored rows:**

| Target | DOI | OA found | Best direct URL | Host | Version | Licence | Surfaced by | Result | What it would take |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `ledem-2013-dremel-made-simple` (blog post, not a paper) | none | no | https://blog.twitter.com/engineering/en_us/a/2013/dremel-made-simple-with-parquet | Twitter engineering blog (now `blog.x.com`) | published post | © Twitter/X, none stated | the Parquet site's nested-encoding page (upstream text) | **not downloaded** (HTTP 403; Wayback availability API 429) | a browser fetch or a Wayback snapshot; `docs/arrow-site/` covers the same ground |

**Planned sources not collected:** none of this cluster's targets. Not attempted, and possibly
worth a later pass: Abadi, Boncz, Harizopoulos, "Column-Oriented Database Systems" (PVLDB 2(2),
2009, Dremel's reference [1]); the Arrow C data interface (`CDataInterface.rst`, at the same
pin); Zig's `src/Air.zig` and `lib/std/zig/AstGen.zig`.


#### Flattened data: packed, columnar and nested layouts — flattening: README.md lines

**Snapshots table rows.**

| Snapshot | Upstream | Revision | Files | Threads | Manifest rows |
| --- | --- | --- | --- | --- | --- |
| [`code/nesl/`](code/nesl/SNAPSHOT.md) | CMU SCAL, NESL distribution on `www.cs.cmu.edu/afs/cs.cmu.edu/project/scandal/public/code/nesl/nesl/` | release 3.1.0 (1995-12-20); no VCS, files pinned by SHA-256 | 22 | flattening | — |
| [`docs/nesl/`](docs/nesl/SNAPSHOT.md) | same, `doc/` | release 3.1.0 | 2 | flattening | — |
| [`code/dph/`](code/dph/SNAPSHOT.md) | `ghc/packages-dph` | `master` at `64eca669f13f4d216af9024474a3fc73ce101793` (last commit, 2016-07-05) | 20 | flattening | — |
| [`code/ghc-vectoriser/`](code/ghc-vectoriser/SNAPSHOT.md) | `ghc/ghc`, `compiler/vectorise/` | `13a86606e51400bc2a81a0e04cfbb94ada5d2620` (parent of the removal `faee23bb`, 2018-06-02) | 11 | flattening | — |
| [`docs/ghc-dph/`](docs/ghc-dph/SNAPSHOT.md) | GHC GitLab wiki, `data-parallel` pages | none: live wiki | 15 | flattening | — |

**Licences table rows.** `code/nesl/`, `docs/nesl/`: CMU SCAL permissive licence (verify for the
docs). `code/dph/`: BSD-3-Clause style, "The DPH Team" (verify). `code/ghc-vectoriser/`: The
Glasgow Haskell Compiler License (BSD-3-Clause style). `docs/ghc-dph/`: GHC wiki, none stated
(verify). Papers: CC-BY-NC-ND `peytonjones-2008-harnessing-multicores`; CC-BY-NC-SA 4.0
`hashemi-2026-full-flattening`; publisher ©, author or project copy, no licence stated (verify):
ACM `blelloch-1996-programming-parallel-algorithms` (personal-use notice on the copy),
`chakravarty-2000-more-types`, `chakravarty-2007-dph-status`,
`lippmeier-2012-work-efficient-vectorisation`, `keller-2012-vectorisation-avoidance` (preprint),
`bergstrom-2013-data-only-flattening` (preprint), `larsen-2017-segmented-reductions`,
`elsman-2019-flattening-by-expansion`; Springer `keller-1998-flattening-trees`,
`leshchinskiy-2006-higher-order-flattening` (preprints); Academic Press
`blelloch-1994-portable-nesl` (the TR copy states none); MIT Press `blelloch-1990-vector-models`;
CMU technical report, none stated `blelloch-1995-nesl`.

**Pins rows.**

| Component | Pin | Resolved SHA | Source of truth command | In the library |
| --- | --- | --- | --- | --- |
| `ghc/packages-dph` | `master` | `64eca669f13f4d216af9024474a3fc73ce101793` | `curl -s https://api.github.com/repos/ghc/packages-dph/commits?per_page=1` | `code/dph/` |
| `ghc/ghc` (vectoriser) | parent of `faee23bb69ca813296da484bc177f4480bcaee9f` | `13a86606e51400bc2a81a0e04cfbb94ada5d2620` | `curl -s https://api.github.com/repos/ghc/ghc/commits/faee23bb69ca813296da484bc177f4480bcaee9f` (field `parents`) | `code/ghc-vectoriser/` |
| NESL 3.1 | release 3.1.0, no VCS | — (files pinned by SHA-256 in `code/nesl/SNAPSHOT.md`) | `curl -s https://www.cs.cmu.edu/afs/cs.cmu.edu/project/scandal/public/code/nesl/nesl/neslsrc/releasenum` | `code/nesl/`, `docs/nesl/` |

**Papers not stored rows.**

| Target | DOI | OA found | Best direct URL | Host | Version | Licence | Surfaced by | Result | What it would take |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `blelloch-1990-collection-oriented` | 10.1016/0743-7315(90)90087-6 | no | — | ScienceDirect | published | Elsevier © | Crossref; web search | not stored | institutional access or the author |
| `leshchinskiy-2005-thesis` | — (URN urn:nbn:de:kobv:83-opus-12865) | yes | https://depositonce.tu-berlin.de/items/3a5f106d-4c15-4e5e-8610-7b7fb81b372f/full | DepositOnce (TU Berlin) | accepted thesis | verify | web search | not fetched (scope) | a fetch through the repository's bitstream link |
| `lippmeier-2012-work-efficient-tr` | — | unknown | — | `www.cse.unsw.edu.au` (403) | TR | unknown | cited in the ICFP paper | not stored | Wayback capture or the authors |
| `keller-1998-flattening-trees-tr` | — | unknown | — | TU Berlin | TR 98-6 | unknown | cited in the Euro-Par paper | unresolved | locate the TU Berlin report |


#### Flattened data: packed, columnar and nested layouts — flattening: Access record lines

Probes on 2026-10-09 with `curl -s -o /dev/null -w "%{http_code} %{content_type} %{size_download}" -L --max-time 30 <url>`.

| Item | URL | Host | Status | Fetch command |
| --- | --- | --- | --- | --- |
| `blelloch-1990-vector-models` | https://www.cs.cmu.edu/~guyb/papers/Ble90.pdf | www.cs.cmu.edu | 200 | `curl -sL --fail -o Ble90.pdf <url>` |
| `blelloch-1995-nesl` | https://www.cs.cmu.edu/~guyb/papers/Nesl3.1.pdf | www.cs.cmu.edu | 200 | `curl -sL --fail -o Nesl3.1.pdf <url>` |
| `blelloch-1995-nesl` (scan, not stored) | http://reports-archive.adm.cs.cmu.edu/anon/1995/CMU-CS-95-170.pdf | reports-archive.adm.cs.cmu.edu | 200 (2,604,071 bytes, no text layer) | — |
| `blelloch-1994-portable-nesl` (article) | https://www.cs.cmu.edu/~guyb/papers/BHSZC94.pdf | www.cs.cmu.edu | 200 | `curl -sL --fail -o BHSZC94.pdf <url>` |
| `blelloch-1994-portable-nesl` (TR) | http://reports-archive.adm.cs.cmu.edu/anon/1993/CMU-CS-93-112.ps | reports-archive.adm.cs.cmu.edu | 200 (`.pdf`: 404) | `curl -sL --fail -o CMU-CS-93-112.ps <url>` |
| `blelloch-1996-programming-parallel-algorithms` | https://www.cs.cmu.edu/~scandal/cacm.html, `.../cacm/{cacm2,node1..node15}.html`, `.../cacm/img*.gif` | www.cs.cmu.edu | 200 (`cacm/images/matrix.gif`: 404) | see the folder README |
| `keller-1998-flattening-trees` | http://web.archive.org/web/20060105013451id_/http://www.cse.unsw.edu.au/~chak/papers/tflat.ps.gz | web.archive.org (live UNSW: 403) | 200 | `curl -sL --fail -o tflat.ps.gz '<url>'` |
| `chakravarty-2000-more-types` | http://web.archive.org/web/2012id_/http://www.cse.unsw.edu.au/~chak/papers/pure-funs.ps.gz | web.archive.org (live UNSW: 403) | 200 | `curl -sL --fail -o pure-funs.ps.gz '<url>'` |
| `leshchinskiy-2006-higher-order-flattening` | http://web.archive.org/web/2012id_/http://www.cse.unsw.edu.au/~chak/papers/ho-flat.ps.gz | web.archive.org (live UNSW: 403) | 200 | `curl -sL --fail -o ho-flat.ps.gz '<url>'` |
| `keller-2012-vectorisation-avoidance` | http://web.archive.org/web/2013id_/http://www.cse.unsw.edu.au/~chak/papers/vect-avoid.pdf | web.archive.org (live UNSW: 403) | 200 | `curl -sL --fail -o vect-avoid.pdf '<url>'` |
| `chakravarty-2007-dph-status` | https://www.microsoft.com/en-us/research/wp-content/uploads/2007/01/ndp.pdf | www.microsoft.com | 200 | `curl -sL --fail -o ndp.pdf <url>` |
| `peytonjones-2008-harnessing-multicores` | https://drops.dagstuhl.de/storage/00lipics/lipics-vol002-fsttcs2008/LIPIcs.FSTTCS.2008.1769/LIPIcs.FSTTCS.2008.1769.pdf | drops.dagstuhl.de | 200 | `curl -sL --fail -o LIPIcs.FSTTCS.2008.1769.pdf '<url>'` |
| `peytonjones-2008-harnessing-multicores` (second copy, not stored) | https://www.microsoft.com/en-us/research/wp-content/uploads/2016/07/fsttcs2008.pdf | www.microsoft.com | 200 | — |
| `lippmeier-2012-work-efficient-vectorisation` | https://www.microsoft.com/en-us/research/wp-content/uploads/2016/07/icfp60-lippmeier.pdf | www.microsoft.com | 200 | `curl -sL --fail -o icfp60-lippmeier.pdf <url>` |
| `bergstrom-2013-data-only-flattening` | http://manticore.cs.uchicago.edu/papers/ppopp13-flat.pdf | manticore.cs.uchicago.edu (`papers.html`: 404) | 200 | `curl -sL --fail -o ppopp13-flat.pdf <url>` |
| `larsen-2017-segmented-reductions` | https://futhark-lang.org/publications/fhpc17.pdf | futhark-lang.org | 200 | `curl -sL --fail -o fhpc17.pdf <url>` |
| `elsman-2019-flattening-by-expansion` | https://futhark-lang.org/publications/array19.pdf | futhark-lang.org | 200 | `curl -sL --fail -o array19.pdf <url>` |
| `hashemi-2026-full-flattening` | https://futhark-lang.org/student-projects/amir-msc-thesis.pdf | futhark-lang.org | 200 | `curl -sL --fail -o amir-msc-thesis.pdf <url>` |
| `code/nesl/`, `docs/nesl/` | https://www.cs.cmu.edu/afs/cs.cmu.edu/project/scandal/public/code/nesl/nesl/<path> | www.cs.cmu.edu (AFS gateway, directory listings enabled) | 200 | see `code/nesl/SNAPSHOT.md` |
| `code/dph/` | https://raw.githubusercontent.com/ghc/packages-dph/64eca669f13f4d216af9024474a3fc73ce101793/<path> | raw.githubusercontent.com | 200 | see `code/dph/SNAPSHOT.md` |
| `code/ghc-vectoriser/` | https://raw.githubusercontent.com/ghc/ghc/13a86606e51400bc2a81a0e04cfbb94ada5d2620/<path> | raw.githubusercontent.com | 200 | see `code/ghc-vectoriser/SNAPSHOT.md` |
| `docs/ghc-dph/` | https://gitlab.haskell.org/ghc/ghc/-/wikis/<slug>.md | gitlab.haskell.org | 200 | see `docs/ghc-dph/SNAPSHOT.md` |

Hosts seen: `www.cse.unsw.edu.au/~chak/papers/*` → 403 for every paper page and file tried
(`KC98.html`, `CLPKM07.html`, `tflat.ps.gz`); the Wayback Machine holds the author pages
`KC98.html` (capture 20060105013451), `CK00.html`, `LCK06.html` (2012) and `KCLLP12.html`
(2013-09-24) with their files. `www.cs.cmu.edu/~guyb/papers/{Ble96,BS90,BCHSZ94,BG96}.pdf` → 404
(guessed names); `www.cs.cmu.edu/~scandal/cacm.pdf`, `cacm/cacm.ps` → 404;
`reports-archive.adm.cs.cmu.edu/anon/1992/CMU-CS-92-103.pdf` and `.../1993/CMU-CS-93-129.pdf` →
404 (the author page serves `Nesl2.0.pdf` and `Nesl2.6.pdf`). `api.github.com/search/repositories`
found no NESL mirror. `api.openalex.org` refused with "Rate limit exceeded" (the shared daily
budget was spent) on 2026-10-09; Crossref (`api.crossref.org/works`) resolved every DOI above.
`www.microsoft.com/en-us/research/wp-json/wp/v2/msr-research-item/<id>` gave the PDF URLs for
items 154379 and 260430. Third-party course copies (cs.uwaterloo.ca, classes.cs.uchicago.edu)
were found and not used. No paywall was bypassed; `dl.acm.org` was not fetched.


#### Flattened data: packed, columnar and nested layouts — packed-trees: README.md lines

**Snapshots table rows.**

| Snapshot | Upstream | Revision | Files | Threads | Manifest rows |
| --- | --- | --- | --- | --- | --- |
| [`code/gibbon/`](code/gibbon/SNAPSHOT.md) | `gibbon-compiler/gibbon` (formerly `iu-parfunc/gibbon`) | `main` at `41e650f14f2a815bcc78ec466a05bae6a33a7a11` | 28 | flat, D | — |
| [`code/ghc/`](code/ghc/SNAPSHOT.md) | `ghc/ghc` | tag `ghc-9.14.1-release`, `902339d332fb4ce2b3c87dcac1ee6495d41ad886` | 7 | flat, D | — |

**Licences table rows.** `code/gibbon/`: none stated (verify; no licence file at the root,
`gibbon.cabal` licence fields commented out, "Copyright 2016-2022 Ryan Newton and contributors").
`code/ghc/`: The Glasgow Haskell Compiler License, BSD-3-Clause style (`ghc-compact`: BSD3).
Papers: CC-BY 3.0 `vollmer-2017-packed-tree-transforms`; CC-BY 4.0
`koparkar-2021-efficient-tree-traversals`, `singhal-2024-marmoset`,
`allais-2023-serialised-data`; CC-BY-ND 4.0 `koparkar-2024-mostly-serialized-gc`; publisher ©,
author or project copy, no licence stated (verify): ACM `vollmer-2019-local`,
`yang-2015-compact-normal-forms` (the copy says "Not for redistribution").

**Pins rows.** `gibbon-compiler/gibbon` `41e650f1…` → in the library: `code/gibbon/` (re-verify:
`git ls-remote https://github.com/gibbon-compiler/gibbon HEAD`). `ghc/ghc` tag
`ghc-9.14.1-release` `902339d3…` → in the library: `code/ghc/` (same release series as
`docs/ghc/`'s users guide).


#### Flattened data: packed, columnar and nested layouts — packed-trees: Access record lines

Probes on 2026-10-09 with `curl -s -o /dev/null -w "%{http_code} %{content_type} %{size_download}" -L --max-time 30 -A 'Mozilla/5.0' <url>`.

| Item | URL | Host | Status | Fetch command |
| --- | --- | --- | --- | --- |
| `vollmer-2017-packed-tree-transforms` | https://drops.dagstuhl.de/storage/00lipics/lipics-vol074-ecoop2017/LIPIcs.ECOOP.2017.26/LIPIcs.ECOOP.2017.26.pdf | drops.dagstuhl.de | 200 `application/pdf` | `curl -sL --fail -o LIPIcs.ECOOP.2017.26.pdf <url>` |
| `vollmer-2019-local` (PLDI) | https://par.nsf.gov/servlets/purl/10108087 | par.nsf.gov | 200 `application/pdf` | `curl -sL --fail -o paper.pdf <url>` |
| `vollmer-2019-local` (TR741) | https://scholarworks.iu.edu/iuswrrest/api/core/bitstreams/1b8e3e45-06b1-41eb-b8aa-e21cc0c11ea9/content | scholarworks.iu.edu (DSpace REST) | 200 `application/pdf` | `curl -sL --fail -o TR741.pdf <url>` |
| `koparkar-2021-efficient-tree-traversals` | https://arxiv.org/e-print/2107.00522 | arxiv.org | 200 `application/gzip` | `curl -sL --fail -o 2107.00522.src https://arxiv.org/e-print/2107.00522 && tar xzf 2107.00522.src` |
| `koparkar-2024-mostly-serialized-gc` | https://par.nsf.gov/servlets/purl/10577816 | par.nsf.gov | 200 `application/pdf` | `curl -sL --fail -o paper.pdf <url>` |
| `yang-2015-compact-normal-forms` | http://ezyang.com/papers/ezyang15-cnf.pdf | ezyang.com (author site) | 200 `application/pdf` | `curl -sL --fail -o ezyang15-cnf.pdf <url>` |
| `singhal-2024-marmoset` | https://arxiv.org/e-print/2405.17590 | arxiv.org | 200 `application/gzip` | `curl -sL --fail -o 2405.17590.src https://arxiv.org/e-print/2405.17590 && tar xzf 2405.17590.src` |
| `allais-2023-serialised-data` | https://arxiv.org/e-print/2310.13441 | arxiv.org | 200 `application/gzip` | `curl -sL --fail -o 2310.13441.src https://arxiv.org/e-print/2310.13441 && tar xzf 2310.13441.src` |
| `code/gibbon/` | https://raw.githubusercontent.com/gibbon-compiler/gibbon/41e650f14f2a815bcc78ec466a05bae6a33a7a11/<path> | raw.githubusercontent.com | 200 | see `code/gibbon/SNAPSHOT.md` |
| `code/ghc/` | https://raw.githubusercontent.com/ghc/ghc/902339d332fb4ce2b3c87dcac1ee6495d41ad886/<path> | raw.githubusercontent.com | 200 | see `code/ghc/SNAPSHOT.md` |

Hosts seen: `api.openalex.org` → 429-style refusal ("Rate limit exceeded", the shared free daily
budget exhausted), so identifiers were resolved through Crossref (`api.crossref.org/works?query.bibliographic=`)
and the arXiv API (`export.arxiv.org/api/query?id_list=2107.00522,2405.17590,2310.13441`), and
licences from the arXiv abstract pages and the Dagstuhl records.
`https://www.cs.indiana.edu/pub/techreports/TR741.pdf` → 200 but HTML (redirect to the Luddy
school's landing page); the TR was taken from IU ScholarWorks instead.
`https://drops.dagstuhl.de/opus/volltexte/2017/7273/pdf/LIPIcs-ECOOP-2017-26.pdf` → 200, same bytes
as the stored copy. `https://drops.dagstuhl.de/storage/00lipics/lipics-vol313-ecoop2024/LIPIcs.ECOOP.2024.38/LIPIcs.ECOOP.2024.38.pdf`
→ 200 (2,405,695 bytes; downloaded to check the published Marmoset text, not stored because the
TeX source exists). `api.github.com/repos/iu-parfunc/gibbon` → 301 to repository 58642617
(`gibbon-compiler/gibbon`). No paywall was bypassed; `dl.acm.org` was not fetched.


#### Fast dependent type checking and elaboration — elaborators: README.md: Snapshots table rows

| Snapshot | Upstream | Revision | Files | Threads | Manifest rows |
| --- | --- | --- | --- | --- | --- |
| [`code/smalltt/`](code/smalltt/SNAPSHOT.md) | `AndrasKovacs/smalltt` | `ea99b0f478e50dcb81ea19e40bfb4262339b22aa` | 23 | elaborators | `code-smalltt` |
| [`code/elaboration-zoo/`](code/elaboration-zoo/SNAPSHOT.md) | `AndrasKovacs/elaboration-zoo` | `9626d6c7a40efa753a757f435df3710efc805d2f` | 11 | elaborators | `code-elaboration-zoo` |
| [`code/lean4lean/`](code/lean4lean/SNAPSHOT.md) | `digama0/lean4lean` | `8223d223ed98661882e95d9d6a7126df7097cd76` | 9 | elaborators | `code-lean4lean` |
| [`code/nanoda_lib/`](code/nanoda_lib/SNAPSHOT.md) | `ammkrn/nanoda_lib` | `3a2407216ee84a75f9e1aead6803d0578be06ae7` | 9 | elaborators | `code-nanoda` |
| [`code/lean4/`](code/lean4/SNAPSHOT.md) (addendum) | `leanprover/lean4` | `7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f` | +18 | elaborators | `code-lean-kernel` |
| [`docs/lean-reference-manual/`](docs/lean-reference-manual/SNAPSHOT.md) | `leanprover/reference-manual` | `349244b4dd2f284728c1dacb621cc74a32f9929b` | 6 | elaborators | `docs-lean-releases` |
| [`docs/agda/`](docs/agda/SNAPSHOT.md) (addendum) | `agda/agda` | `83f3fcce37fc5bd11cd7da10bccbe0f59d860037` | +3 | elaborators | `docs-agda-performance` |
| [`docs/pop-in-fstar/`](docs/pop-in-fstar/SNAPSHOT.md) (addendum) | `FStarLang/PoP-in-FStar` | `958d86f2eb158f349785e447228dbf016818c6be` | +3 | elaborators | `docs-fstar-book` |

Licences table additions: `code/smalltt/` MIT; `code/elaboration-zoo/` BSD-3-Clause style
(verify); `code/lean4lean/`, `code/nanoda_lib/`, `docs/lean-reference-manual/` Apache-2.0;
`code/lean4/`, `docs/agda/`, `docs/pop-in-fstar/` unchanged. Papers: `demoura-2021-lean4`
CC-BY 4.0; `wenzel-2013-read-eval-print` CC BY-NC-ND; `selsam-2020-tabled-typeclass`,
`carneiro-2024-lean4lean`, `barras-2015-async-coq`, `martinez-2019-meta-fstar`,
`gross-2024-scalable-proof-engine` arXiv non-exclusive; `boespflug-2011-full-throttle`
Springer ©, `swamy-2016-fstar-mumon` ACM ©, `wenzel-2009-parallel-isabelle` none stated:
author or project copies (verify).


#### Fast dependent type checking and elaboration — elaborators: README.md: Pins

| Pin | Value | Resolved |
| --- | --- | --- |
| `AndrasKovacs/smalltt` | `ea99b0f478e50dcb81ea19e40bfb4262339b22aa` | `git ls-remote https://github.com/AndrasKovacs/smalltt HEAD`, 2026-10-09 |
| `AndrasKovacs/elaboration-zoo` | `9626d6c7a40efa753a757f435df3710efc805d2f` | `git ls-remote https://github.com/AndrasKovacs/elaboration-zoo HEAD`, 2026-10-09 |
| `digama0/lean4lean` | `8223d223ed98661882e95d9d6a7126df7097cd76` | `git ls-remote https://github.com/digama0/lean4lean HEAD`, 2026-10-09 (`leanprover/lean4lean`: "Repository not found") |
| `ammkrn/nanoda_lib` | `3a2407216ee84a75f9e1aead6803d0578be06ae7` | `git ls-remote https://github.com/ammkrn/nanoda_lib HEAD`, 2026-10-09 |
| `leanprover/lean4` | `7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f` | `git ls-remote https://github.com/leanprover/lean4 HEAD`, 2026-10-09 (unchanged from the other clusters) |
| `leanprover/reference-manual` | `349244b4dd2f284728c1dacb621cc74a32f9929b` | `git ls-remote https://github.com/leanprover/reference-manual HEAD`, 2026-10-09 |
| `agda/agda` | `83f3fcce37fc5bd11cd7da10bccbe0f59d860037` | `git ls-remote https://github.com/agda/agda HEAD`, 2026-10-09 (unchanged) |
| `FStarLang/PoP-in-FStar` | `958d86f2eb158f349785e447228dbf016818c6be` | `git ls-remote https://github.com/FStarLang/PoP-in-FStar HEAD`, 2026-10-09 |
| `FStarLang/FStar` | `334c989ed27b617e694e1d7db35c242735ecceac` | `git ls-remote`, 2026-10-09; resolved, nothing taken |
| `rocq-prover/rocq` | `29f5238ebcc99136c8e695babcb658ade8d96fa4` | `git ls-remote`, 2026-10-09; unchanged, nothing taken by this cluster |


#### Fast dependent type checking and elaboration — elaborators: README.md: Access record lines

Reachability (2026-10-09), `curl -sL --max-time 120 -A "Mozilla/5.0" -o <file> -w "%{http_code} %{content_type} %{size_download}" <url>`:

| URL | Host | Result |
| --- | --- | --- |
| `https://arxiv.org/e-print/2001.04301`, `2403.14064`, `1803.06547`, `1506.05605`, `1307.1944`, `2305.02521` | arXiv (→ `/src/<id>`) | 200 `application/gzip`: 691,966; 35,895; 145,897; 803,730; 112,581; 2,933,370 B |
| `https://arxiv.org/abs/<id>` (the six above) | arXiv | 200; titles, versions, journal references and comments read there |
| `https://link.springer.com/content/pdf/10.1007/978-3-030-79876-5_37.pdf` | Springer | 200 `text/html`, 3,038 B: JavaScript "Client Challenge"; not solved or evaded, discarded |
| `https://publikationen.bibliothek.kit.edu/1000142109/141380002` | KIT repository | 200 `application/pdf`, 306,659 B |
| `https://xavierleroy.org/publi/strong-reduction.pdf` | Leroy's site | 200 `application/pdf`, 124,874 B (not staged: identical to the kernels cluster's copy) |
| `https://www.cs.mcgill.ca/~mboes/` | Boespflug's page | 200 (links `papers/cpp11.pdf`) |
| `https://www.cs.mcgill.ca/~mboes/papers/cpp11.pdf` | same | 200 `application/pdf`, 148,013 B |
| `https://hal.science/hal-00650940/document` | HAL | 200 `text/html`, 12,508 B: Anubis challenge ("Making sure you're not a bot!"); not solved or evaded, discarded |
| `https://www21.in.tum.de/~wenzelm/papers/parallel-isabelle.pdf` | Wenzel's TUM page | 200 `application/pdf`, 183,722 B |
| `https://www.fstar-lang.org/papers/mumon/paper.pdf` | F* site (→ `fstar-lang.org`) | 200 `application/pdf`, 396,340 B |
| `https://api.github.com/repos/<repo>/git/trees/<sha>?recursive=1` | GitHub API | 200 for lean4, lean4lean, nanoda_lib, smalltt, elaboration-zoo, PoP-in-FStar, agda, reference-manual |
| `https://raw.githubusercontent.com/<repo>/<sha>/<path>` | GitHub raw | 200 for every file listed in the snapshots; the 49 Lean release-note files all 200 |
| `https://api.crossref.org/works?query.bibliographic=...` | Crossref | 200, then 429 on rapid repeats (retried after 8 s pauses); resolved the DOIs below |
| `https://api.unpaywall.org/v2/<doi>` | Unpaywall | 200; OA locations for the Lean 4, Grégoire–Leroy, Boespflug, Barras, Swamy and Wenzel 2013 DOIs |

Identifier resolution (2026-10-09):

| Shortname | Identifier | Resolved by | Status |
| --- | --- | --- | --- |
| `demoura-2021-lean4` | 10.1007/978-3-030-79876-5_37 | Crossref (title, authors, pp. 625–635, CC-BY 4.0) | resolved |
| `selsam-2020-tabled-typeclass` | arXiv 2001.04301 | arXiv abstract page | resolved (no peer-reviewed version located) |
| `carneiro-2024-lean4lean` | arXiv 2403.14064 | arXiv abstract page (v3, "submitted to CPP 2026") | resolved |
| `boespflug-2011-full-throttle` | 10.1007/978-3-642-25379-9_26 | Crossref | resolved |
| `wenzel-2009-parallel-isabelle` | none | Crossref title search returned other Wenzel papers | unresolved (author copy stored) |
| `wenzel-2013-read-eval-print` | 10.4204/EPTCS.118.4; arXiv 1307.1944 | Crossref; Unpaywall | resolved |
| `barras-2015-async-coq` | 10.1007/978-3-319-22102-1_4; arXiv 1506.05605 | Crossref; Unpaywall | resolved-corrected (pages 51–66; the plan gave only "ITP 2015") |
| `swamy-2016-fstar-mumon` | 10.1145/2837614.2837655 | Crossref | resolved |
| `martinez-2019-meta-fstar` | arXiv 1803.06547; 10.1007/978-3-030-17184-1_2 | arXiv abstract page | resolved |
| `gross-2024-scalable-proof-engine` | 10.1007/s10817-024-09705-6; arXiv 2305.02521 | arXiv journal reference | resolved (surfaced by search, not in the plan) |
| `gregoire-2002-strong-reduction` | 10.1145/581478.581501 | Crossref | resolved (kernels cluster stores it) |

Fetch commands (read-only; nothing built or run; destinations relative to `sources/`):

```bash
# arXiv e-prints (README §4.2); .bbl removed where no .bib exists, generated .arxiv-aux removed
for p in 2001.04301:selsam-2020-tabled-typeclass 2403.14064:carneiro-2024-lean4lean \
         1803.06547:martinez-2019-meta-fstar 1506.05605:barras-2015-async-coq \
         1307.1944:wenzel-2013-read-eval-print 2305.02521:gross-2024-scalable-proof-engine; do
  id=${p%%:*}; d=papers/${p#*:}; mkdir -p /tmp/arxiv-$id "$d"
  curl -L --fail -o /tmp/arxiv-$id/src https://arxiv.org/e-print/$id && tar -xzf /tmp/arxiv-$id/src -C "$d"
done
rm papers/{selsam-2020-tabled-typeclass/typeclass,carneiro-2024-lean4lean/main,martinez-2019-meta-fstar/paper,barras-2015-async-coq/full,wenzel-2013-read-eval-print/root}.bbl
rm papers/gross-2024-scalable-proof-engine/rewriting.arxiv-aux
# PDFs
fetch() { mkdir "papers/$1" && curl -sL --fail --max-time 120 -A "Mozilla/5.0" -o "papers/$1/$2" "$3"; }
fetch demoura-2021-lean4 paper-kit.pdf https://publikationen.bibliothek.kit.edu/1000142109/141380002
fetch boespflug-2011-full-throttle cpp11.pdf https://www.cs.mcgill.ca/~mboes/papers/cpp11.pdf
fetch wenzel-2009-parallel-isabelle parallel-isabelle.pdf https://www21.in.tum.de/~wenzelm/papers/parallel-isabelle.pdf
fetch swamy-2016-fstar-mumon paper.pdf https://www.fstar-lang.org/papers/mumon/paper.pdf
# GitHub raw at pinned commits
raw() { repo=$1 sha=$2 dest=$3; shift 3; for p in "$@"; do mkdir -p "$dest/$(dirname "$p")"; curl -sL --fail -o "$dest/$p" "https://raw.githubusercontent.com/$repo/$sha/$p"; done; }
raw AndrasKovacs/smalltt ea99b0f478e50dcb81ea19e40bfb4262339b22aa code/smalltt README.md LICENSE.txt CITATION.cff bench/README.md src/Evaluation.hs src/Unification.hs src/Elaboration.hs src/CoreTypes.hs src/MetaCxt.hs src/Common.hs src/SymTable.hs src/LvlSet.hs src/TopCxt.hs src/Cxt.hs src/Cxt/Extension.hs src/Cxt/Types.hs src/InCxt.hs bench/conv_eval.stt bench/conv_eval.lean bench/conv_eval.idr bench/conv_eval.v bench/asymptotics.stt bench/stlc_small.stt
raw AndrasKovacs/elaboration-zoo 9626d6c7a40efa753a757f435df3710efc805d2f code/elaboration-zoo README.md LICENSE GluedEval.hs 03-holes/pattern-unification.txt 05-pruning/README.md 05-pruning/Unification.hs 05-pruning/Evaluation.hs 05-pruning/Value.hs 05-pruning/Metacontext.hs 05-pruning/Syntax.hs 05-pruning/Elaboration.hs
raw digama0/lean4lean 8223d223ed98661882e95d9d6a7126df7097cd76 code/lean4lean README.md LICENSE bugs-found.md Main.lean Lean4Lean/TypeChecker.lean Lean4Lean/EquivManager.lean Lean4Lean/Instantiate.lean Lean4Lean/PtrEq.lean Lean4Lean/Expr.lean
raw ammkrn/nanoda_lib 3a2407216ee84a75f9e1aead6803d0578be06ae7 code/nanoda_lib README.md LICENSE Cargo.toml src/tc.rs src/expr.rs src/util.rs src/union_find.rs src/unique_hasher.rs src/main.rs
raw leanprover/lean4 7cd10322fcb4c2f4fd3827c9082422a49ac2dd1f code/lean4 src/kernel/type_checker.cpp src/kernel/type_checker.h src/kernel/instantiate.cpp src/kernel/instantiate.h src/kernel/expr.h src/kernel/expr.cpp src/kernel/expr_eq_fn.cpp src/kernel/abstract.cpp src/kernel/replace_fn.cpp src/kernel/environment.cpp src/library/instantiate_mvars.cpp src/runtime/sharecommon.h src/runtime/sharecommon.cpp src/Lean/Meta/SynthInstance.lean src/Lean/Meta/ExprDefEq.lean src/Lean/Meta/WHNF.lean src/Lean/Language/Lean.lean src/Lean/Elab/Frontend.lean
raw leanprover/reference-manual 349244b4dd2f284728c1dacb621cc74a32f9929b docs/lean-reference-manual LICENSE Manual/Releases/v4_8_0.lean Manual/Releases/v4_17_0.lean Manual/Releases/v4_18_0.lean Manual/Releases/v4_19_0.lean Manual/Releases/v4_23_0.lean
raw agda/agda 83f3fcce37fc5bd11cd7da10bccbe0f59d860037 docs/agda doc/user-manual/tools/performance.rst doc/user-manual/language/lossy-unification.lagda.rst doc/user-manual/language/opaque-definitions.lagda.rst
raw FStarLang/PoP-in-FStar 958d86f2eb158f349785e447228dbf016818c6be docs/pop-in-fstar book/intro.rst book/part3/part3_typeclasses.rst book/part5/part5_meta.rst
```


#### Fast dependent type checking and elaboration — elaborators: README.md: Papers not stored

| Target | DOI | OA found | Best direct URL | Host | Version | Licence | Surfaced by | Result | What it would take |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Lean 4 CADE 2021, publisher PDF | 10.1007/978-3-030-79876-5_37 | yes (gold) | `https://link.springer.com/content/pdf/10.1007/978-3-030-79876-5_37.pdf` | Springer | published | CC-BY 4.0 | Unpaywall | **not downloaded** (Client Challenge); the KIT copy of the same text is stored | a browser download, if a second copy is wanted |
| `gross-2022-itp-rewriting` (the ITP 2022 conference version) | arXiv 2205.00862 | yes | `https://arxiv.org/e-print/2205.00862` | arXiv | — | arXiv | arXiv comment on 2305.02521 | **not fetched**: "substantial text overlap" with the stored journal version | nothing; fetch if the conference text is wanted |
| Tassi, "Asynchronous processing of formal documents in Coq" | 10.4204/eptcs.167.2 | yes | — | EPTCS | published | CC-BY (EPTCS, verify) | Crossref | **not fetched**: a two-page abstract of `barras-2015-async-coq` | nothing |
| Kovács, `normalization-bench` | none (repository) | — | `https://github.com/AndrasKovacs/normalization-bench` | GitHub | — | verify | `code/smalltt/README.md` line 599 | **not fetched** (out of this cluster's plan) | a snapshot at a pinned revision |
| Agda typechecking benchmarks (`agda-bench`) | none | — | `https://github.com/UlfNorell/agda-bench` | GitHub | — | verify | `docs/agda/doc/user-manual/tools/performance.rst` line 45 | **not fetched**: a tool, no published results located | a run, which this pass does not do |


#### Fast dependent type checking and elaboration — kernels-trust: 2. Access-record lines

**Reachability (§1), observed 2026-10-09.**

| Host | Status | What it serves | Notes |
| --- | --- | --- | --- |
| `www.brics.dk` (`/RS/97/18/`) | 200 | BRICS Report Series (PDF, PS, DVI) | Pollack's report. |
| `www.cs.ru.nl/~freek/pubs/` | 200 | Wiedijk's papers with `.tex` sources | Author host. |
| `www.cse.chalmers.se/~abela/` | 200 | Abel's papers and errata | Author host. |
| `cs.mcgill.ca/~bpientka/papers/` | 200 | Pientka's papers | Author host (second copy of the TLCA paper, not stored). |
| `adam.gundry.co.uk` | 200 (http) | Gundry's papers, code tarball, thesis errata | Author host. |
| `jfr.unibo.it` | 200 | Journal of Formalized Reasoning (OJS) | `/article/download/<id>/<galley>` serves the PDF. |
| `xavierleroy.org` | 200 | Leroy's papers | Author host. |
| `digama0.github.io/mm0/` | 200 | MM0 project site, thesis PDF | Project host. |
| `us.metamath.org` | 200 | Metamath site | `other.html` stored. |
| `inria.hal.science` (`/<id>/document`) | 200 HTML | HAL bot challenge instead of the PDF | Not evaded; as recorded for the open-access pass. |
| `www.ams.org` (`/notices/...pdf`) | 403 | Notices of the AMS | Scripted fetch refused. |
| `api.openalex.org` | 429 | OpenAlex API | Daily budget of the shared IP exhausted ("Insufficient budget"); Crossref used instead. |
| `api.crossref.org` | 200 (intermittent empty body) | Crossref works search | Retry after a pause succeeded. |

**Identifier resolution (§3a, arXiv).**

| Shortname | Canonical link | Fetch recommended | Licence recorded | Status |
| --- | --- | --- | --- | --- |
| `carneiro-2020-metamath-zero` | https://arxiv.org/abs/1910.10703 (DOI 10.1007/978-3-030-53518-6_5) | https://arxiv.org/e-print/1910.10703 | arXiv non-exclusive | resolved (arXiv v3 title is "Metamath Zero: The Cartesian Theorem Prover"; the CICM title is the plan's) |
| `assaf-2016-dedukti` | https://arxiv.org/abs/2311.07185 | https://arxiv.org/e-print/2311.07185 | arXiv non-exclusive | resolved (2016 manuscript, posted 2023-11-13) |
| `farber-2022-kontroli` | https://arxiv.org/abs/2102.08766 (DOI 10.1145/3497775.3503683) | https://arxiv.org/e-print/2102.08766 | arXiv non-exclusive | resolved |

**Identifier resolution (§3b, DOI, Crossref).**

| Shortname | Canonical DOI | Fetch recommended | Licence recorded | Status |
| --- | --- | --- | --- | --- |
| `pollack-1998-believe-machine-checked-proof` | https://doi.org/10.1093/oso/9780198501275.003.0013 | https://www.brics.dk/RS/97/18/BRICS-RS-97-18.pdf (report, DOI 10.7146/brics.v4i18.18945) | BRICS ©, research use with notice | resolved |
| `barendregt-2005-challenge-computer-mathematics` | https://doi.org/10.1098/rsta.2005.1650 | https://www.cs.ru.nl/~freek/pubs/rspaper.tex | © Royal Society; author source (verify) | resolved |
| `wiedijk-2012-pollack-inconsistency` | https://doi.org/10.1016/j.entcs.2012.06.008 | https://www.cs.ru.nl/~freek/pubs/rap.tex | ENTCS; author source (verify) | resolved |
| `gonthier-2010-small-scale-reflection` | https://doi.org/10.6092/issn.1972-5787/1979 | https://jfr.unibo.it/article/download/1979/1358 | CC-BY 3.0 | resolved |
| `gregoire-2002-strong-reduction` | https://doi.org/10.1145/581478.581501 | https://xavierleroy.org/publi/strong-reduction.pdf | ACM © (author copy) | resolved |
| `abel-2011-dynamic-pattern-unification` | https://doi.org/10.1007/978-3-642-21691-6_5 | https://www.cse.chalmers.se/~abela/unif-sigma.pdf (+ `unif-sigma-long.pdf`, `errata-tlca11.txt`) | Springer © (author copy) | resolved |
| `boutin-1997-reflection` | https://doi.org/10.1007/BFb0014565 | none found | Springer © | resolved (DOI from web search and the LNCS 1281 index; not Crossref-verified in this pass) |

**Identifier resolution (§3c, no DOI).**

| Shortname | Canonical link | Fetch recommended | Licence recorded | Status |
| --- | --- | --- | --- | --- |
| `carneiro-2022-metamath-zero-thesis` | https://digama0.github.io/mm0/thesis.pdf | same (also `site/thesis.pdf` in `digama0/mm0`) | none stated (verify) | resolved (no institutional record located) |
| `gundry-2012-dynamic-pattern-unification` | http://adam.gundry.co.uk/pub/pattern-unify/ | `pattern-unification-2012-07-10.pdf` and `.tar.gz` there | none stated (verify) | resolved (unpublished draft) |
| `gonthier-2008-ssreflect-manual` | https://inria.hal.science/inria-00258384 | HAL `/document` (bot challenge) | HAL (verify) | resolved, not fetched |
| `gonthier-2008-four-colour` | https://www.ams.org/notices/200811/tx081101382p.pdf | same (403) | AMS | resolved, not fetched |

**Non-paper source URLs (§3d).**

| Source | Canonical base URL | Pin |
| --- | --- | --- |
| MM0 repo | https://raw.githubusercontent.com/digama0/mm0/0d414c0bfdaaeb7fea571895127abc1fa5a3d956/ | `master` at `0d414c0b…` |
| Dedukti repo | https://raw.githubusercontent.com/Deducteam/Dedukti/f3c0eba869ddd46f2e75c123a59f2b612076dba0/ | default branch at `f3c0eba8…` |
| Lambdapi repo (listed, not vendored) | https://github.com/Deducteam/lambdapi | `220752a2…` |
| Kontroli repo | https://raw.githubusercontent.com/01mf02/kontroli-rs/c980688be66a7357725c1dcc41ca2c21ff282bc2/ | the paper's revision `c980688b…` (HEAD `22bfbdfc…` not taken) |
| Metamath book | https://raw.githubusercontent.com/metamath/metamath-book/a54c715930739fd11589595c310823ec5eb57eee/ | `a54c7159…` |
| metamath-knife | https://raw.githubusercontent.com/metamath/metamath-knife/76fc9f7f39f46f4c43499a0c2bd1402eb8b1cf9a/ | `76fc9f7f…` |
| Metamath verifier list | https://us.metamath.org/other.html | live |
| Gundry–McBride code | http://adam.gundry.co.uk/pub/pattern-unify/pattern-unification-2012-07-10.tar.gz | dated tarball |

**Pins.**

| Component | Pin | Resolved SHA | Source of truth command | In the library |
| --- | --- | --- | --- | --- |
| `digama0/mm0` | `master` | `0d414c0bfdaaeb7fea571895127abc1fa5a3d956` | `git ls-remote https://github.com/digama0/mm0 HEAD` | `code/mm0/` |
| `Deducteam/Dedukti` | default branch | `f3c0eba869ddd46f2e75c123a59f2b612076dba0` | `git ls-remote https://github.com/Deducteam/Dedukti HEAD` | `code/dedukti/` |
| `Deducteam/lambdapi` | default branch | `220752a204365c5d1591bcdf76079e1749268c0f` | `git ls-remote https://github.com/Deducteam/lambdapi HEAD` | not vendored |
| `01mf02/kontroli-rs` | commit named in the paper | `c980688be66a7357725c1dcc41ca2c21ff282bc2` | `curl https://api.github.com/repos/01mf02/kontroli-rs/commits/c980688` | `code/kontroli/` |
| `metamath/metamath-book` | default branch | `a54c715930739fd11589595c310823ec5eb57eee` | `git ls-remote https://github.com/metamath/metamath-book HEAD` | `docs/metamath/book/` |
| `metamath/metamath-knife` | default branch | `76fc9f7f39f46f4c43499a0c2bd1402eb8b1cf9a` | `git ls-remote https://github.com/metamath/metamath-knife HEAD` | `docs/metamath/knife/` |

**Papers not stored.**

| Target | DOI | OA found | Best direct URL | Host | Version | Licence | Surfaced by | Result | What it would take |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `boutin-1997-reflection` | 10.1007/BFb0014565 | no | — | — | — | Springer © | web search | **not stored** (no open copy found) | Springer subscription, or author/Inria copy; rerun Unpaywall/OpenAlex when the API budget resets |
| `gonthier-2008-ssreflect-manual` | — | yes (HAL) | https://inria.hal.science/inria-00258384/document | repository (HAL) | RR-6455 | HAL (verify) | web search | **not downloaded** (HAL bot challenge) | browser download from HAL |
| `gonthier-2008-four-colour` | — | yes (free to read) | https://www.ams.org/notices/200811/tx081101382p.pdf | publisher (AMS) | published | AMS | known URL | **not downloaded** (HTTP 403) | browser download |

