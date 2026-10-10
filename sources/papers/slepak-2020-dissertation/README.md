# A Typed Programming Language: The Semantics of Rank Polymorphism (PhD dissertation)

- **Authors:** Justin Slepak (advisor Olin Shivers; committee Panagiotis Manolios, Amal Ahmed,
  Alex Aiken)
- **Venue / year:** PhD dissertation, Khoury College of Computer Sciences, Northeastern
  University, 2020 (title page dated 2020-07-03)
- **Canonical link:** https://www.khoury.northeastern.edu/~jrslepak/Dissertation.pdf (author
  page; no repository handle located)
- **License:** © 2020 Justin Slepak (title-page notice), author-hosted, no licence stated
  (verify before redistributing)
- **Thread(s):** typed-rank (Array languages and typed array programming); also G
- **Storage form:** PDF (`Dissertation.pdf`, 292 pages, 2,504,318 bytes, SHA-256
  `9cf12812a839ed6da9a5b3e8b05536146fd9b6685520345f300bccbd2f85d1c1`); no TeX source located
- **Status:** stored

## Provenance

Fetched 2026-10-09 from `https://www.khoury.northeastern.edu/~jrslepak/Dissertation.pdf`
(HTTP 200 `application/pdf`), located by web search. The PDF's first pages include the
graduate office's "PhD Thesis Approval" form as shipped.

## Contents (by chapter, as cited from the notes)

Part I (formal semantics): ch. 2 background, ch. 3 programming with rank polymorphism, ch. 4
semantics of typed Remora (syntax, static and dynamic semantics, soundness). Part II (type
inference): ch. 5 background (local/bidirectional inference, dependent type inference, theory
of sequences), ch. 6 bidirectional elaboration with an equation archive, ch. 7 the
first-order theory of array shapes (Makanin's algorithm modulo a theory of dimensions, the
mixed-prefix fragment), ch. 8 evaluation (elaboration soundness, worked examples). Part III
(translation): ch. 9 compilation targets, ch. 10 type erasure, ch. 11 explicit iteration
(`map`/`rep` IR, flat arrays and index-function views), ch. 12 conclusion.

## Related

- `bibliography.bib` has `Slepak:PhD` (with the note "In preparation"; update it to the
  finished 2020 dissertation and this URL).
- Code: `code/revised-remora/` (the Redex model of ch. 4 and 6) and `code/makanin-algo/`
  (the ch. 7 solver), both named in the dissertation's margin notes.
