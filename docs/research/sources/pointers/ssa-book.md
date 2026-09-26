# Pointer: SSA-based Compiler Design (cross-link)

**What it is.** Rastello & Bouchez Tichadou (eds.), *SSA-based Compiler Design* (Springer,
2022). Free full-book PDF. Relevant to the SSA/PDL/e-graph and MLIR threads.

**Stored copy (not a pointer-only item).** The PDF is vendored once at
`sources/docs/ssa-book/ssa-based-compiler-design.pdf` (5,257,556 bytes, 5.0 MB — under the
20 MB cap, so no pointer-only handling was required).

- SHA-256: `d563a8376b28cc5450a592b9d96a5f886ecd7b477e6a76ba608927e789585a52`
- Retrieved via the Wayback Machine (the original host is dead — see below):
  `https://web.archive.org/web/2023id_/https://ssabook.gforge.inria.fr/latest/book.pdf`
  which redirects to snapshot `20210621194509` of `http://ssabook.gforge.inria.fr/latest/book.pdf`.

**Why this file exists.** `MANIFEST.md` Thread F lists the book as
`sources/pointers/ssa-book.md` while the `sources/docs/` table lists it as
`sources/docs/ssa-book/`. Per the "store once, cross-link" rule this pointer records the
single stored location; do not fetch the book a second time.

**Host status (verified 2026-09-26).** `ssabook.gforge.inria.fr` does not resolve
(HTTP 000); use the Wayback URL above.
