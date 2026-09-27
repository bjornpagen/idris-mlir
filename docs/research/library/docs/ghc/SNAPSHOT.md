# Snapshot: GHC documentation (Glasgow Haskell Compiler)

- **Upstream:** the GHC commentary wiki (`gitlab.haskell.org/ghc/ghc/-/wikis`) and the GHC
  users guide (`downloads.haskell.org`).
- **Revision:** none; live, unpinned hosts, snapshot 2026-09-26. The users guide `latest`
  resolved to the 9.14.1 series.
- **Files:** 22: 13 commentary pages as raw Markdown (`commentary-*.md`, flat,
  human-readable names) and 9 users-guide pages (`users_guide/*.html`).
- **Licence:** BSD-3-Clause (verify).
- **Threads:** D, E, cross-cutting.

This file was `sources/pointers/ghc.md`, the reproducibility pointer for the GHC parts that
are not vendored; it now sits with the documentation it describes.

**What it is.** GHC's compiler implementation (HsSyn, Core, STG, Cmm, the runtime
system), its commentary wiki, and users guide.

**Pin / version.**
- Documentation is fetched from live, unpinned hosts:
  - GHC commentary wiki (raw Markdown): `https://gitlab.haskell.org/ghc/ghc/-/wikis/<slug>.md`
  - GHC users guide: `https://downloads.haskell.org/ghc/latest/docs/users_guide/<page>.html`
    (`latest` at snapshot time resolved to the 9.14.1 series).
- The **source tree is not vendored** and no source commit is pinned here. If a pin is
  needed later, resolve it with:
  `git ls-remote https://gitlab.haskell.org/ghc/ghc.git refs/heads/master`
  and record the SHA in the pin table of the library [README](../../README.md#pins).

**Exact URL patterns.**
- Commentary page: `https://gitlab.haskell.org/ghc/ghc/-/wikis/<slug>.md`
  (append `.md` for raw Markdown; without it the page is JS-rendered HTML).
- Users guide page: `https://downloads.haskell.org/ghc/latest/docs/users_guide/<page>.html`
- Source file (read-only reference only):
  `https://gitlab.haskell.org/ghc/ghc/-/raw/master/<path>`

**Why it is not vendored.**
- The GHC source tree is large (thousands of Haskell modules plus the RTS); vendoring it
  would dwarf the rest of the corpus and is outside the "selected pinned excerpts" scope.
- The documentation *is* vendored: this folder (commentary pages and selected
  users-guide pages). What this section records is only the reproducibility pointer for the
  parts deliberately not copied. No `code/ghc/` excerpts were taken.

**Slugs actually captured in this folder** (snapshot 2026-09-26):
`commentary/compiler`, `commentary/pipeline`, `commentary/compiler/core-syn-type`,
`commentary/compiler/stg-syn-type`, `commentary/compiler/cmm-type`, `commentary/rts`,
`commentary/compiler/demand`, `commentary/compiler/core-to-core-pipeline`,
`commentary/compiler/opt-ordering`, `commentary/compiler/code-gen`,
`commentary/compiler/backends`, `commentary/compiler/generated-code`,
`commentary/compiler/data-types`.

**Users-guide pages captured:** `codegens.html`, `debugging.html`, `index.html`,
`packages.html`, `phases.html`, `profiling.html`, `runtime_control.html`,
`separate_compilation.html`, `using-optimisation.html`.

**What the manifest asked for, and what covers it.**
- GHC STG/Cmm/RTS (cross-cutting, D): `commentary-compiler-stg-syn-type.md`,
  `commentary-compiler-cmm-type.md`, `commentary-rts.md`, plus `core-syn-type`,
  `data-types` and `core-to-core-pipeline`.
- GHC `specialise`/`SpecConstr` and dictionary specialisation (cross-cutting): there is no
  dedicated commentary page; `users_guide/using-optimisation.html`, `opt-ordering.md` and
  `core-to-core-pipeline.md` document `-fspecialise`/`SpecConstr` and the inliner.
- GHC unarisation (E): unresolved, see below.

**Known gaps (verified 2026-09-26).** There is no dedicated commentary wiki page at
`commentary/compiler/inliner` or `commentary/compiler/unarisation` (both HTTP 404). The
closest captured material is `core-to-core-pipeline` / `opt-ordering` (simplifier and
inliner context) and `code-gen` / `backends` (the Cmm-to-native path where unarisation
lives); `data-types` also bears on representation. Record this against any row that
assumed those pages exist.
