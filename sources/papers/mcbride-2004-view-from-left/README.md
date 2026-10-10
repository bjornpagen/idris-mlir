# The view from the left

- **Authors:** Conor McBride, James McKinna
- **Venue / year:** Journal of Functional Programming 14(1), 69–111, 2004
- **Canonical link:** https://doi.org/10.1017/S0956796803004829
- **License:** CUP ©; author-hosted preprint ("Under consideration for publication in J.
  Functional Programming"), no licence stated (verify before redistributing)
- **Thread(s):** dependent-equality (Array languages and typed array programming); also E
- **Storage form:** PostScript (`view.ps`, 47 pages, 487,048 bytes, SHA-256
  `2d57f4299d58f05ccf86600aaad667c1cad4a93317bacc2f0f0de02df6bf8162`), decompressed from the
  author's `view.ps.gz` (179,765 bytes, SHA-256
  `e29e62ac05067fbdd5204d675f81ef9da9648c16259671b6718e91b0ab305924`). No TeX source exists.
- **Status:** stored (preprint; not verified against the published text)

## Provenance

Fetched 2026-10-09 from `http://strictlypositive.org/view.ps.gz` (HTTP 200
`application/gzip`), linked from `http://strictlypositive.org/publications.html`; unpacked
with `gunzip -c`. The page also links `view-Dec6.ps.gz` (an earlier draft, not stored). Agda's
documentation cites a PDF at `http://strictlypositive.org/vfl.pdf` (not fetched).

## Why it is here

It is the origin of the `with` rule (section 5, figure 12) that Idris 2 and Agda implement,
and of views as derived eliminators (section 6), including the `Compare` view whose
patterns `x (x + s y)` are arithmetic.
