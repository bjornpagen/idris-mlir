# Pointer: GHC (Glasgow Haskell Compiler)

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
  and record the SHA in `ACCESS.md`.

**Exact URL patterns.**
- Commentary page: `https://gitlab.haskell.org/ghc/ghc/-/wikis/<slug>.md`
  (append `.md` for raw Markdown; without it the page is JS-rendered HTML).
- Users guide page: `https://downloads.haskell.org/ghc/latest/docs/users_guide/<page>.html`
- Source file (read-only reference only):
  `https://gitlab.haskell.org/ghc/ghc/-/raw/master/<path>`

**Why it is not vendored.**
- The GHC source tree is large (thousands of Haskell modules plus the RTS); vendoring it
  would dwarf the rest of the corpus and is outside the "selected pinned excerpts" scope.
- The documentation *is* vendored: see `sources/docs/ghc/` (commentary pages and selected
  users-guide pages). What lives here is only the reproducibility pointer for the parts
  deliberately not copied.

**Slugs actually captured under `sources/docs/ghc/`** (snapshot 2026-09-26):
`commentary/compiler`, `commentary/pipeline`, `commentary/compiler/core-syn-type`,
`commentary/compiler/stg-syn-type`, `commentary/compiler/cmm-type`, `commentary/rts`,
`commentary/compiler/demand`, `commentary/compiler/core-to-core-pipeline`,
`commentary/compiler/opt-ordering`, `commentary/compiler/code-gen`,
`commentary/compiler/backends`, `commentary/compiler/generated-code`,
`commentary/compiler/data-types`.

**Known gaps (verified 2026-09-26).** There is no dedicated commentary wiki page at
`commentary/compiler/inliner` or `commentary/compiler/unarisation` (both HTTP 404). The
closest captured material is `core-to-core-pipeline` / `opt-ordering` (simplifier and
inliner context) and `code-gen` / `backends` (the Cmm-to-native path where unarisation
lives). Record this against any row that assumed those pages exist.
