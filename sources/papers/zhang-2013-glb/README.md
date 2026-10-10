# GLB: Lifeline-based Global Load Balancing Library in X10

- **Authors:** Wei Zhang, Olivier Tardieu, David Grove, Benjamin Herta, Tomio Kamada, Vijay
  Saraswat, Mikio Takeuchi
- **Venue / year:** arXiv `1312.5691` (v1, 2013-12-19); published at PPAA 2014 (first
  Workshop on Parallel Programming for Analytics Applications), pp. 31–40,
  DOI 10.1145/2567634.2567639
- **Canonical link:** https://arxiv.org/abs/1312.5691
- **License:** arXiv non-exclusive licence (`nonexclusive-distrib/1.0`, the arXiv record);
  ACM © for the published version
- **Thread(s):** sharded-compilation (Sharded and incremental compilation)
- **Storage form:** raw LaTeX source (arXiv e-print `1312.5691`), as shipped except the
  orphan `.bbl`
- **Status:** stored

## Provenance

Fetched 2026-10-10 from `https://arxiv.org/e-print/1312.5691` (redirected to
`https://arxiv.org/src/1312.5691`; HTTP 200 `application/gzip`, gzip-compressed tar,
2,513,689 bytes, SHA-256 `3261b0f8a91c07a6c5553ec5f36c28e369557104727508563ba5e63a53cdfe41`).
Title, authors and licence from the arXiv API and abstract page; the arXiv record has no
journal reference, and the PPAA 2014 DOI was matched by title and authors with Crossref.

Unpacked with `tar xzf`. No `.aux`, `.log`, `.out`, `.blg`, `.synctex*`, `.fls` or
`.fdb_latexmk` files were present. `glbx10.bbl` (7,460 bytes) was removed: `glbx10.tex`
cites `\bibliography{x10}`, and `x10.bib` is not in the bundle (the convention for an orphan
`.bbl`; it is in the e-print archive whose SHA-256 is above). Kept as shipped: the compiled
`glb_arxiv.pdf` (979,431 bytes), the earlier drafts `bc_orig.tex`, `uts_orig.tex`,
`fib_old.tex`, the co-authors' notes `suggestion.txt`, the R scripts and transcripts under
`ppaa2014_figures/R/`, and the build scripts `Makefile`, `colourlatex.sh` and
`ppaa2014_figures/pdf2eps` (never run). `glbx10.tex` is the main file. 9.4 MB in all; the
largest file is `ppaa2014_figures/bgq_workload.eps` (1,961,288 bytes).

## Related

`blumofe-1999-work-stealing`; `sources/notes/sharded-compilation/deterministic-fixpoints.md`
§2 (work stealing without a shared heap).

## File manifest

Every stored file except this one: 54 files, 9,759,627 bytes in all. Computed 2026-10-10;
check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
0a7736a918d744f52d9cdf1ada98473fbac4904d4faa88490a993cc021723d63       1134  BGQ-architecture.tex
baf5e1c08c7882a42657fab4d721e7b541c14b82740d206f8fbd8d1b64192074        915  K-architecture.tex
b5ee6e0bf44d2e952824dac7e770026fe3ca7a5cb67a5596c2ef586024d70923       1244  Makefile
e710c1138d0a0a46016b83a5df72e7184883c8ac0edd61b12eb9d12418611c1a       1145  P7IH-architecture.tex
07ff3d82989592dd10a3835c607278c9da790329183f31b1b2f370d4dc44720f       1186  abstract.tex
6c3f69982c7b954aebeab499d6208301da37a5f69d1fc75d66f2833b2cf2dab1       4258  bc.tex
0a0382ddfe5221fd8732c0f6f14a34331aa65dfa6dad2ab14599cbb1e070ed79       4256  bc_orig.tex
ff0241f585cf7ae43fbbd1b9804158eba838ce9b14cc23df2f9fbbff5f91a778       4599  bcg.tex
388d1927c02657d25bc97e8757ff5a2b78447744c74e1523be4d99e85e60e2a8       1097  colourlatex.sh
39231e7a803b198867a31039856743e55f7e070845d9ac2519115401f5b0d107      12259  design.tex
a6df3554bd3c4ed9f40712974584f9693fac6a2b27bf5f43a51cc9ea344de285        128  eval.tex
4a82fe535a9537c68ca72d666664362eb6b11e0fa9eaec91b751659631d6007f        236  fib.tex
58fa03c6c72af6db3085e4ed3b05f0e03d2777414f1c5c07ad05404ab9dcb9eb       2007  fib_old.tex
9e16aee3fb4d121408ae7f12847cc12679af056cef5879a29b10f26f97a62499        486  future.tex
2240083d4f55f5ab4dd52831e3bc0c7fdb93a8f72f70ac1022829ed9afa2c562       8142  glb.tex
4904c8c71f01dd9dd5198177b764715917e40ef1dc521acba0e864029a014742     979431  glb_arxiv.pdf
71889399ecb7d815c1183e5865288200c94a30a6bd4ad109783ce311089a4289       3708  glbx10.tex
a649dae5dd72190b6c1ead79e99b5917d50e0dc927e1552432681350b1a116b7       4017  intro.tex
2b701bbb75ef4d6b8e456cda8fd3bee254abc7260831794c725b8292fcf54e8b        611  meth.tex
3d7b329a5b71faa025256d2d91321e24ad1e499ba630017830c96e891d9fa7a7         65  ppaa2014_figures/R/K.Rout
26a125b45bb1d8919c7798ba6a3e2fa80571f828fb24eb302dcc7056b12c0570         67  ppaa2014_figures/R/bcg.Rout
c081484803b63f4cde1e0681556ceadea2fc7ef3f7d967ba64d8f263918d49b7        821  ppaa2014_figures/R/bgq.R
128b863df93f6d0e92dfea599be057ca4917d18acc15e42b4094ae7e6dbcfbe8        822  ppaa2014_figures/R/bgq.R_
b4d4d1923741bcf5bcf6cfa14820e84d7ceddf0ee760b9455bdebb215519b476       1725  ppaa2014_figures/R/bgq.Rout
79678c8688aea91bfd397195237a6525b6747b3ec0b9bd0fa79d2c36719bfeca        728  ppaa2014_figures/R/k.R
e1f886cd3dc5d9fc5469eb606f29a3dff145e34ce00afb8d4ba8c84b82f0a9bd        729  ppaa2014_figures/R/k.R_
39f5261e14f840d755dd367b087856e667b38ec44a728549e699804d33d72c4f        932  ppaa2014_figures/R/p7ih.R
53224c8688608f2f223692f89d5c088e7cc8e2342c7a8bc677ded465d4afbd29        933  ppaa2014_figures/R/p7ih.R_
bdbcadc75aed0c38e317b4558c3af447edae30bd27ac6cfb439249115b154004       1836  ppaa2014_figures/R/p7ih.Rout
8198ddefd9f4fec7123a3c114313ecb61bf7514c40fe0ee5cf461771ea4f6f45     838749  ppaa2014_figures/bc_bgq.eps
ed04ac3e45a8197133db03152caf81180867f23d44404454d6ef2cd80e8cae6d      38643  ppaa2014_figures/bc_bgq.pdf
8c01b9b7ba570fe52215bb2505c792d7b5431a2bb4a0973cce14d117a732a80c     755163  ppaa2014_figures/bc_k.eps
89a6d074a6ecfb1985ba350f8cdb178e36c266ad55f227ac3da0db27c9bc47f4      39153  ppaa2014_figures/bc_k.pdf
67949fee11e07aab6d56f52ec53f58298a4305d2ecffb5f2d958528184b572cc     740567  ppaa2014_figures/bc_p7ih.eps
ff3aafbb29ea1d57f7dc34e5bd13cace9ca84662f3a961eb9ebadea00dbeb84e    1961288  ppaa2014_figures/bgq_workload.eps
7ae17568cedb1bbcd0443c8d3f02c8e7475cb6e8ddbd3b5c3df1ce4a87d69d95     175380  ppaa2014_figures/bgq_workload.pdf
b92d0425facea75da6a162a21a9f7801da808c35646e588dc4e5d602c331f27d       1310  ppaa2014_figures/fib.java
8926599d5ab86e1c6b5806b1a235df036af5adf736a0c827566ab1101bfa6493    1098262  ppaa2014_figures/glb_overview.eps
cc499fa994b5bd1b016459af755c367968d226f5c95030ca4b2d88ac8b629a27    1493354  ppaa2014_figures/k_workload.eps
96431e774b5633c120bd15b41a68eb9608e726e5755f0b6ab759acdc671a7981     139414  ppaa2014_figures/k_workload.pdf
fc41be56200d3dce8b9d7c090294019fd65cfa597cdae9c4027e20205150d155      47583  ppaa2014_figures/p7ih_workload.eps
4b17c8ea4604d9037057a763cc7674bd305e62a98939915e8601c7f61545c099       8126  ppaa2014_figures/p7ih_workload.pdf
5f75d0984c877c5273cb4eb7b5b30a5754d63b62afa1212e59b37ae06ad739ea        269  ppaa2014_figures/pdf2eps
635a1725ab28870921e1cbf6db777c1734bb6f116d0866cf0bafb2931d7cd8a5     357283  ppaa2014_figures/uts_bgq.eps
8f02c38f9017b683bd25c7731afb91946768355731351a65a836e1ad1d02ae06      32685  ppaa2014_figures/uts_bgq.pdf
e0cd19979fce4471926ce8aabb010c0c72ce5d58c949763b537c668a37695cad     499202  ppaa2014_figures/uts_k.eps
0affb1101037517468f0ec978875b863971528e9177876ba261192372ee73800      30717  ppaa2014_figures/uts_k.pdf
04b8368d8f70a60a0d327384f030dc00521a15defeac6c22b3c9c005bc18bde4     396761  ppaa2014_figures/uts_p7ih.eps
4a97284b11173f0bd0f6e01ef96637cce713f81d08bb9a11e6b03b247bb1a7d2      32641  ppaa2014_figures/uts_p7ih.pdf
5193119c7f67038199f096aef8c28df55eacaeeaccfbdd0202df23bc78a37e6c       4347  related.tex
cf9220196e90f02228b4024891bc8dfd115410d53766225e93135fac5f8d2ecf       8058  result.tex
57d09742c84fec56089d40e49f6d39d902f4f676871ab5dd925e540d4ade2f36       1549  suggestion.txt
b932d28189c5461cad48299bd0be5dbd667a91d5b6d8e76ec20140e6b08d9002       9977  uts.tex
1a9d23a8a6299589a3a8591d927b05b6aa76e2212eba6d20ee5ab8ff26b8d8fa       9629  uts_orig.tex
```
