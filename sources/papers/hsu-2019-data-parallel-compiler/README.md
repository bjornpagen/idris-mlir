# A Data Parallel Compiler Hosted on the GPU

- **Authors:** Aaron Wen-yao Hsu (advisor Andrew Lumsdaine)
- **Venue / year:** Ph.D. dissertation, Indiana University, School of Informatics, Computing, and Engineering, November 2019
- **Canonical link:** https://hdl.handle.net/2022/24749 (IUScholarWorks item `3ab772c9-92c9-4f59-bd95-40aff99e8c7a`)
- **License:** repository statement "This work may be protected by copyright unless otherwise stated"; no open licence (verify before redistributing)
- **Thread(s):** Array languages and typed array programming (cluster apl-lineage)
- **Storage form:** the repository's own full-text extraction, `hsu-dissertation.pdf.txt` (DSpace `TEXT` bundle). **The PDF is not stored**: it is 30,678,406 bytes, over the library's 20 MB per-file cap.
- **Status:** stored (repository text extraction only; PDF over the cap, link-only)

## Provenance

The item page `https://scholarworks.iu.edu/dspace/handle/2022/24749` lists the bitstreams;
the DSpace REST API (`https://scholarworks.iu.edu/iuswrrest/api/core/items/3ab772c9-92c9-4f59-bd95-40aff99e8c7a/bundles?embed=bitstreams`)
gives:

| Bundle | Name | Bytes | Id |
| --- | --- | --- | --- |
| ORIGINAL | `Hsu Dissertation.pdf` | 30,678,406 (MD5 `5cf1368ad74d9a78a1ebbb451fe24f01`; SHA-256 `91017caa3a4f551b6b8c6f85603e558bd2a034213890fb47e406a705c8c7e107`) | `dcbd5240-8454-4533-bc0c-ac3ee7628b8e` |
| TEXT | `Hsu Dissertation.pdf.txt` | 173,191 | `8f9f9835-485c-483c-9c87-6ccb45fcfa74` |

Both were fetched on 2026-10-09 from
`https://scholarworks.iu.edu/iuswrrest/api/core/bitstreams/<id>/content`. The PDF (284 pages,
Microsoft Word 2019-11-05) was read in place for this pass and not kept in the library; fetch it
again with the command above (id `dcbd5240-…`). Only the text bundle is stored:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `hsu-dissertation.pdf.txt` | 173,191 | `1997787fbd7ab732ea76d2e69b78324d17509c27e2e35ddbc3daaf18c1630669` |

**Limits of the stored text.** The PDF's body text is set in fonts without a Unicode map, so
both the repository's extraction and `pdftotext` recover mostly the APL code and tables, not
the prose. The stored file does contain the code: the 17-line compiler of Appendix B is at
lines 2228–2245 (`tt←{…}`, one header line plus 17 lines, each tagged with its pass: PV, LF, WX, LG, CI, LX, SL, FR, XN, AV), and the inline derivations (for example depth-to-parent at line 883 and the
nearest-lexical-contour walk at lines 965–984). Claims about the prose cite the PDF's printed page numbers; the PDF page
index is the printed page plus 11 (printed page 1 is PDF page 12).

A Leanpub "pre-print edition" exists (https://leanpub.com/arcfide_dissertation, paid) and is
not a library source. Co-dfns itself is snapshotted at
[`code/co-dfns/`](../../code/co-dfns/SNAPSHOT.md).
