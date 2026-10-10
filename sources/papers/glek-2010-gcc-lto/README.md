# Optimizing real-world applications with GCC Link Time Optimization

- **Authors:** Taras Glek, Jan Hubička
- **Venue / year:** Proceedings of the 2010 GCC Developers' Summit (arXiv journal reference);
  arXiv `1010.2196`, v1 2010-10-11, v2 "published version", 21 pages
- **Canonical link:** https://arxiv.org/abs/1010.2196 (no DOI)
- **License:** arXiv non-exclusive licence (`nonexclusive-distrib/1.0`, the arXiv record)
- **Thread(s):** sharded-compilation (Sharded and incremental compilation)
- **Storage form:** raw LaTeX source (arXiv e-print `1010.2196`, latest version), as shipped
- **Status:** stored

## Provenance

Fetched 2026-10-10 from `https://arxiv.org/e-print/1010.2196` (redirected to
`https://arxiv.org/src/1010.2196`; HTTP 200 `application/gzip`, gzip-compressed tar, 58,891
bytes, SHA-256 `ba93925aec75d9a2ba3f0850ed2f7ba51baa1fe384c54d568898d0d8c49d2891`). Title,
authors, journal reference and licence from the arXiv API and abstract page. Unpacked with
`tar xzf`; no generated files (`.aux`, `.log`, `.out`, `.blg`, `.synctex*`, `.fls`,
`.fdb_latexmk`) were present. The bibliography is inline (`thebibliography` in
`hubicka-arxiv.tex`); there is no `.bib` or `.bbl`. `hubicka-arxiv.tex` is the main file
(`ols.cls`, the GCC Summit proceedings class).

## Related

`docs/gcc-lto/` (`gcc/lto/lto-partition.cc` and the `-flto` option documentation at a pinned
GCC revision, added the same day); `johnson-2017-thinlto`;
`sources/notes/sharded-compilation/whole-program-at-scale.md` §2.

## File manifest

Every stored file except this one: 5 files, 168,556 bytes in all. Computed 2026-10-10;
check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
b5aac5d968ac7d980778c466215b91373d2a5a9645bdaf20a12c108f36d69149      48529  figure.eps
0792d40d3cd8e7b0f01cf7c92f82b13fccd393bc3a32df7c57a3c402dfcf8cc5        671  hubicka-abstract.tex
e345ffb09460bd550ad10833d2089a2c7b794d83c43211d0382f018a06b70eb0      88836  hubicka-arxiv.tex
9f92a8e3a834063730908551e26ec90837fb3e7703b596830d67f8744cbe8fcb      10934  ols.cls
c1693e5918423052cc65155e8d40932d95bb1edf06413c9a54e4ebcbb9b72cb9      19586  zrl.sty
```
