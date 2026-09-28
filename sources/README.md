# Research library

The vendored research library of idris-mlir: papers, code and documentation snapshots,
and one bibliography. The material was collected on 2026-09-26 for a first-principles
optimization study and organized in this layout on 2026-09-27 (`docs/plan.md`,
section 9). This file is the record of provenance and licences: where every item came
from, at which revision, under which licence, how to fetch it again, and what is still
missing. [INDEX.md](INDEX.md) lists the papers by topic.

The study's report, `docs/research/first-principles-optimization.md`, was deferred by the
sources pass and never written; this library is the material it was to reason from.

- [Layout](#layout)
- [Where the old files went](#where-the-old-files-went)
- [How to use the library](#how-to-use-the-library)
- [Conventions](#conventions)
- [Licences](#licences)
- [Snapshots](#snapshots)
- [Pins](#pins)
- [Access record](#access-record): [reachability](#reachability),
  [identifier resolution](#identifier-resolution),
  [non-paper source URLs](#non-paper-source-urls), [fetch commands](#fetch-commands)
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
├── bibliography.bib   one BibTeX file for the library (653 entries)
├── papers/<author>-<year>-<slug>/
│                      README.md (provenance) plus the TeX source, or the PDF when no
│                      TeX source exists (51 papers)
├── code/<project>/    selected source excerpts at a pinned revision, each with SNAPSHOT.md
│   ├── idris2/        Core, Compiler and TTImp sources at the submodule pin
│   ├── mlir/          headers and TableGen interfaces at llvmorg-23.1.2
│   ├── mlton/         closure-convert, SSA and RSSA pass sources
│   └── tinygrad/      the Thread A modules and the BEAM search module
└── docs/<project>/    documentation snapshots, each with SNAPSHOT.md
    ├── ghc/           GHC commentary wiki (raw .md) and selected users-guide pages
    ├── idris2/        Idris 2 docs at the submodule pin
    ├── llvm/          selected LLVM docs at llvmorg-23.1.2
    ├── mlir/          MLIR docs at llvmorg-23.1.2
    ├── mlton/         selected MLton guide pages
    ├── ssa-book/      SSA-based Compiler Design (free PDF)
    └── tinygrad/      tinygrad docs and README
```

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
  under `docs/ghc/` and `docs/ssa-book/`.
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

All fetched on 2026-09-26. File counts exclude `SNAPSHOT.md`.

| Snapshot | Upstream | Revision | Files | Threads | Manifest rows |
| --- | --- | --- | --- | --- | --- |
| [`code/idris2/`](code/idris2/SNAPSHOT.md) | `idris-lang/Idris2` | `1c630e67c386629a0fbbc6b78a59176fde7f0a76` (submodule pin) | 30 | E, D, I, cross-cutting | `code-idris2`, `code-idris-transform` |
| [`code/mlir/`](code/mlir/SNAPSHOT.md) | `llvm/llvm-project`, `mlir/` | tag `llvmorg-23.1.2` = `2d56740342c3bd86a7525fb4c147252757589e30` | 94 | F, B, I | `code-mlir` |
| [`code/mlton/`](code/mlton/SNAPSHOT.md) | `MLton/mlton` | `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37` | 16 | D, G | `code-mlton` |
| [`code/tinygrad/`](code/tinygrad/SNAPSHOT.md) | `tinygrad/tinygrad` | `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a` | 19 | A, G, H | `code-tinygrad` |
| [`docs/ghc/`](docs/ghc/SNAPSHOT.md) | GHC commentary wiki; GHC users guide | none: live hosts (users guide `latest` = the 9.14.1 series) | 22 | D, E, cross-cutting | `docs-ghc`, `docs-ghc-stg-cmm-rts`, `docs-ghc-specialise-specConstr`, `pointers-ghc` |
| [`docs/idris2/`](docs/idris2/SNAPSHOT.md) | `idris-lang/Idris2` | `1c630e67c386629a0fbbc6b78a59176fde7f0a76` (submodule pin) | 71 | E, D | `docs-idris2` |
| [`docs/llvm/`](docs/llvm/SNAPSHOT.md) | `llvm/llvm-project`, `llvm/` | tag `llvmorg-23.1.2` | 11 | F, B, I | `docs-mlir-llvm` |
| [`docs/mlir/`](docs/mlir/SNAPSHOT.md) | `llvm/llvm-project`, `mlir/` | tag `llvmorg-23.1.2` | 100 | F, B, I | `docs-mlir-llvm` |
| [`docs/mlton/`](docs/mlton/SNAPSHOT.md) | `MLton/mlton` | `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37` | 16 | D, G | `docs-mlton` |
| [`docs/ssa-book/`](docs/ssa-book/SNAPSHOT.md) | `ssabook.gforge.inria.fr` (dead) | Wayback snapshot `20210621194509` | 1 | F, B | `docs-ssa-book`, `book-ssa-compiler-design` |
| [`docs/tinygrad/`](docs/tinygrad/SNAPSHOT.md) | `tinygrad/tinygrad`; `docs.tinygrad.org` | `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a`; the live site index | 29 | A, G | `docs-tinygrad` |

The Idris 2 snapshots were fetched from the pinned raw GitHub URLs because
`third_party/Idris2` was not checked out at the time; it is now, at the same pin.

## Pins

Resolved on 2026-09-26. Raw bases: `https://raw.githubusercontent.com/<repo>/<pin>/<path>`.

| Component | Pin | Resolved SHA | Source of truth command | In the library |
| --- | --- | --- | --- | --- |
| `third_party/Idris2` (git submodule) | pinned commit `1c630e67` | `1c630e67c386629a0fbbc6b78a59176fde7f0a76` | `git submodule status third_party/Idris2` | `code/idris2/`, `docs/idris2/` |
| this repo `origin/main` HEAD, at access time | `main` | `e37040ac93c9ad244097868e16db482a02fd23ef` | `git ls-remote https://github.com/bjornpagen/idris-mlir.git refs/heads/main` | — |
| local working HEAD, at access time (matched `origin/main`) | `main` | `e37040ac93c9ad244097868e16db482a02fd23ef` | `git rev-parse HEAD` | — |
| `tinygrad/tinygrad` | `master` | `b1a9b35bdd89ed2ed3fa69e0786210fbd268b33a` | `git ls-remote https://github.com/tinygrad/tinygrad.git refs/heads/master` | `code/tinygrad/`, `docs/tinygrad/` |
| `MLton/mlton` | `master` | `aa2fd1ad9b91375903a4253cfcf1ea5ef2754f37` | `git ls-remote https://github.com/MLton/mlton.git refs/heads/master` | `code/mlton/`, `docs/mlton/` |
| `llvm/llvm-project` | tag `llvmorg-23.1.2` | `2d56740342c3bd86a7525fb4c147252757589e30`; `mlir` subtree `ca7b652dc7f3c9b48dc57f408c70f5229dc39363` | `git ls-remote https://github.com/llvm/llvm-project.git refs/tags/llvmorg-23.1.2` | `code/mlir/`, `docs/mlir/`, `docs/llvm/` |
| `egraphs-good/egg` | `main` | `2f31b28e3f9d78e02273b6c6d4201b5b0720b343` | `git ls-remote https://github.com/egraphs-good/egg refs/heads/main` | not vendored |
| `egraphs-good/egglog` | `main` | `90635860397ce710f8c0a4eeb04154a8ebc3ac05` | `git ls-remote https://github.com/egraphs-good/egglog refs/heads/main` | not vendored |
| `HigherOrderCO/HVM` | `master` | `7365a56cca56a5853c979755891cb86aa343c42d` | `git ls-remote https://github.com/HigherOrderCO/HVM refs/heads/master` | not vendored |
| `HigherOrderCO/Bend` | `main` | `574b6d39a235b539eb19a5c532993a0abb3d11ad` | `git ls-remote https://github.com/HigherOrderCO/Bend refs/heads/main` | not vendored |
| `google-research/dex-lang` | `main` | `25e2e389b90403ae2f8d67fb6d52f47d23c439ee` | `git ls-remote https://github.com/google-research/dex-lang refs/heads/main` | not vendored |
| `diku-dk/futhark` | `master` | `304c56ff73c48f1842ed3971fe19805a3a85c766` | `git ls-remote https://github.com/diku-dk/futhark refs/heads/master` | not vendored |
| GHC | not vendored (live docs) | — | pointer only: `docs/ghc/SNAPSHOT.md` | `docs/ghc/` |
| SSA book | Wayback snapshot `20210621194509` | — | `docs/ssa-book/SNAPSHOT.md` | `docs/ssa-book/` |

The LLVM pin is a **tag**, not a branch; the resolved SHA is the commit the annotated tag
dereferences to for the archive tree. Raw fetches should use the tag name `llvmorg-23.1.2`
(stable) or this SHA. The pinned-repository SHAs should be re-verified before vendoring
(commands in [Fetch commands](#fetch-commands), §4.9).

## Access record

The reproducible access record of the sources pass (plan step `access`, formerly
`sources/ACCESS.md`): what is reachable, how each host was probed, the resolved identifier
of every paper candidate, and the exact fetch commands for the collection steps. All probes
and API lookups were run on **2026-09-26**. Section numbers §1–§4 are that record's; the
paper READMEs cite them.

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
| LLVM/MLIR raw tree | https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-23.1.2/ | tag `llvmorg-23.1.2` (= `2d567403…`) |
| LLVM/MLIR GitHub tree API | https://api.github.com/repos/llvm/llvm-project/git/trees/llvmorg-23.1.2?recursive=1 | tag |
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

#### 4.4 LLVM / MLIR raw fetch at the pinned tag

```bash
tag=llvmorg-23.1.2
base="https://raw.githubusercontent.com/llvm/llvm-project/${tag}"

# Single file
curl -L --fail -o /tmp/PatternMatch.h "${base}/mlir/include/mlir/IR/PatternMatch.h"

# Full tree listing (to enumerate mlir/docs/**), then fetch each path
curl -s "https://api.github.com/repos/llvm/llvm-project/git/trees/${tag}?recursive=1" \
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
| `code-eqsat-dialects` | DialEgg and the MLIR `eqsat` dialect source | B, F | pinned LLVM @ `llvmorg-23.1.2`; DialEgg repo | `code/mlir-eqsat/` | Apache-2.0 WITH LLVM-exception / DialEgg verify | not collected |
| `code-egg-repos` | egg / egglog repositories | B | pinned GitHub `2f31b28e…` (egg), `90635860…` (egglog) | `code/egg/`, `code/egglog/` | MIT | not collected |
| `book-pe-jones-gomard-sestoft` | *Partial Evaluation and Automatic Program Generation* (book) | C | author-hosted free PDF → pointer | `docs/pe-book/` (pointer) | author-hosted free | not collected |
| `book-gc-handbook` | Garbage Collection Handbook | D | no OA; pointer only | `docs/gc-handbook/` (pointer) | book © | not collected |
| `boehm-gc` | Boehm GC (project/tech report) | D | project page → pointer | `docs/boehm-gc/` (pointer) | verify | not collected |
| `abel-foetus` | foetus — termination checker for simple functional programs | E | author host; no DOI | `docs/foetus/` (pointer) | TBD | unresolved: author `/foetus/` path 404 |
| `docs-mojo` | Mojo docs | F | `docs.modular.com/mojo/` | `docs/mojo/` | verify | not collected |
| `docs-iree` | IREE docs | F | `iree.dev` | `docs/iree/` (pointer) | Apache-2.0 verify | not collected |
| `code-polygeist` | Polygeist | F | `polygeist.pages.dev` / repo → pointer | `code/polygeist/` (pointer) | Apache-2.0 WITH LLVM-exception verify | not collected |
| `code-dex` | `google-research/dex-lang` source | G | pinned GitHub `25e2e389…` | `code/dex/` | Apache-2.0 verify | not collected |
| `code-futhark` | Futhark source | G | pinned GitHub `304c56ff…` | `code/futhark/` | BSD-3-Clause verify | not collected |
| `idris-vect-material` | Idris `Vect`/index-typed array material; tinygrad symbolic shapes | E, G, A | Idris2 pinned docs/source; tinygrad pinned source | `docs/idris2/`, `code/idris2/`, `code/tinygrad/` | BSD-3-Clause / MIT verify | not collected as such; the tinygrad symbolic-shape modules are in `code/tinygrad/` |
| `mlgo-compilergym` | MLGO / CompilerGym | H | project pages + papers; probe | `docs/mlgo-compilergym/` (pointer) | TBD | unresolved |
| `code-hvm` | HVM2 source + docs | J | pinned GitHub `7365a56c…` | `code/hvm/` | verify | not vendored |
| `code-bend` | Bend source + docs | J | pinned GitHub `574b6d39…` | `code/bend/` | verify | not vendored |
| `inpla-inets` | Inpla / inets | J | repo/author host → pointer | `docs/inpla-inets/` (pointer) | TBD | unresolved |
| `code-lean4-lcnf-specinfo` | Lean 4 `LCNF` and `SpecInfo` | cross-cutting | lean4 repo pinned at fetch time → pointer/excerpts | `code/lean4/` | Apache-2.0 verify | not collected |
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
- **Un-vendored source trees:** egg, egglog, HVM, Bend, dex-lang, Futhark and GHC sources
  were planned or pointer-only; only their pins and URL patterns are recorded
  ([Pins](#pins), `docs/ghc/SNAPSHOT.md`). Fetch on demand when exact code is needed.
- **No `mlir/include/mlir/IR/RewriterBase.h`** at the pin: `RewriterBase` lives in
  `PatternMatch.h` (vendored). Likewise several dialect docs exist only as ODS-generated
  content covered by the full `docs/mlir/` snapshot.

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
