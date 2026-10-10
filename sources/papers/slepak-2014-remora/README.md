# An Array-Oriented Language with Static Rank Polymorphism

- **Authors:** Justin Slepak, Olin Shivers, Panagiotis Manolios
- **Venue / year:** ESOP 2014, LNCS 8410, pp. 27–46 (DOI 10.1007/978-3-642-54833-8_3)
- **Canonical link:** https://doi.org/10.1007/978-3-642-54833-8_3
- **License:** Springer © (published version, author-hosted); Unpaywall reports bronze OA at
  Springer; no licence stated on either copy (verify before redistributing)
- **Thread(s):** typed-rank (Array languages and typed array programming); also G
- **Storage form:** 2 PDFs, no TeX source exists (not on arXiv):
  - `paper.pdf`: the published LNCS version, 20 pages (346,573 bytes, SHA-256
    `1c7f32013cadbe1e670ad639000eebbc822b2a052ff03fe3b8eea38c0ba58a7a`)
  - `paper-full.pdf`: the authors' full version with appendices A (basis library types),
    B (typed example code), C (soundness proof sketch), D (implementation pointer), 26 pages
    (469,898 bytes, SHA-256
    `efb62aa1f55f0e1aa11bc5188660ac989fb8f6daf077268247563c59b160fe8f`)
- **Status:** stored

## Provenance

Fetched 2026-10-09 from Panagiotis Manolios's Northeastern page
(`https://www.khoury.northeastern.edu/~pete/research/esop-2014.html`), HTTP 200
`application/pdf`:

- `paper.pdf` from `https://khoury.northeastern.edu/~pete/pub/esop-2014.pdf`
- `paper-full.pdf` from `https://khoury.northeastern.edu/~pete/pub/esop14-full.pdf`

The two copies differ: the full version adds the appendices. Unpaywall
(`/v2/10.1007/978-3-642-54833-8_3`) lists a bronze publisher copy at
`https://link.springer.com/content/pdf/10.1007%2F978-3-642-54833-8_3.pdf`, not fetched (the
author copy is the published version).

## Related

- `shivers-2019-remora` (already in the library): the 2019 tutorial draft for the same
  language.
- `slepak-2019-semantics`, `slepak-2020-dissertation`: the revised formal semantics and the
  dissertation that supersede this paper's type system (dimension/shape sorts, `++` on
  shapes, boxes as dependent sums).
- Code: `code/remora/semantics/` is the PLT Redex model this paper describes (appendix D).
