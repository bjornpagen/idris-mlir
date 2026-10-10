# The Semantics of Rank Polymorphism

- **Authors:** Justin Slepak, Olin Shivers, Panagiotis Manolios
- **Venue / year:** arXiv 2019 (preprint of a journal submission, JFP class file); v1 only,
  2019-07-01
- **Canonical link:** https://arxiv.org/abs/1907.00509
- **License:** arXiv non-exclusive license
- **Thread(s):** typed-rank (Array languages and typed array programming); also G
- **Storage form:** raw LaTeX source (arXiv e-print `1907.00509`), 24 files, 648 KB on disk.
  Main file `paper.tex`; sections `intro.tex`, `formalism.tex` (syntax, index theory, static
  and dynamic semantics, lemmas), `soundness.tex`, `type_erasure.tex`, `related_work.tex`,
  `conclusion.tex`; all figures are macros in `figs.tex` (`\FigTypingRules`,
  `\FigDynamicSemantics`, `\FigErasedSemantics`, ...); `decls.tex` holds notation macros. The
  bundle ships its class and style files (`jfp1.cls`, `llncs.cls`, `mathpartir.sty`, ...) and
  a `Makefile` (stored as shipped, never run).
- **Status:** stored

## Provenance

Fetched 2026-10-09 from `https://arxiv.org/e-print/1907.00509` (gzip-compressed tar, 140,678
bytes, SHA-256 `6f4c306d6af80a25986ac2ed50cf105d15e0fae14426020c2d775b078a095dd3`).
Unpacked with `tar xzf`. No generated files (`.aux`, `.log`, ...) were present; `paper.bbl`
was removed because no `.bib` is present (library convention), so the bibliography must be
regenerated from the arXiv abstract page's references if the PDF is rebuilt.

SHA-256 of the main sources: `paper.tex`
`5f1790e864b371babf9ac73d384a87b82240009e43fab62ec81e13ffb0efbe84` (3,546 bytes);
`formalism.tex` `d75794157b80c43df93fadb898411345cb94a788a8560287d20d447df6fc4459`
(174,310 bytes); `figs.tex`
`8ec3c1a9eddfdc86832b578bc1334051592e057387972a232ea8facb48247de1` (37,848 bytes);
`type_erasure.tex` `97a731222bba1f0c7c843a3180670cec1e1bee4a5816e2ac57bed76662085f1f`
(69,517 bytes).

## Related

- `bibliography.bib` already has `Slepak+:semantics-rank-poly-preprint` for this paper
  (harvested from `shivers-2019-remora/refs.bib`); it is not a duplicate of
  `shivers-2019-remora` (arXiv 1912.13451, the tutorial).
- `slepak-2020-dissertation` chapters 4 and 10 are revised versions of this text.

## File manifest

Every stored file except this one: 24 files, 623,635 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
38e37b23543428637fcd4a169f39315f7700f4a891a7cd0a6b6cd417aefcd4ce       1214  Makefile
03414b731ff17c203eadca26f5b51abd2e6bf6daeccdd6a5df0cd5332857c9f2       8180  amsfonts.sty
b27c70ec1fa09d4bfa191e4a9cb56fd38d76d4b1a17b97e140c9db2f2a233fed      12214  bm.sty
6c1bc3cc6cc7c3b9989e119c6abc62e4f5afe8809abba45989f088a8e182a53d      12280  code.sty
27ae3f2a0fb2449f9254e851f81427583d09d3c221dfe9796842d1e94887975f       2634  conclusion.tex
663a3d066edf29dc3159c5791ddd63352bc2f0495ee62b76c026a113b6f7df5e        243  ct.sty
28d2f5c5d9b54962afb55b4c2df3291cf288f65e83e69af7f8c5e73b66ac280c      12089  decls.tex
8c9e4f7b581069b55d1d2c4de435dc6781fc2029a0447df7cb29d2dadf3fe59b      42406  etoolbox.sty
8ec3c1a9eddfdc86832b578bc1334051592e057387972a232ea8facb48247de1      37848  figs.tex
d75794157b80c43df93fadb898411345cb94a788a8560287d20d447df6fc4459     174310  formalism.tex
46b782a01105e484177d1560397e87106ced2c0471f04f7798942e72a8e1ed8d       8008  intro.tex
f5c5c092db5bfd7c3dcf655cf652b26e3921da15ce7be6f69b852dee37bd6739      31958  jfp.bst
c9fd2d22ca987fe85ab7ecac8b98d4fc24acad62af690e997df4b1e89d34a836      56104  jfp1.cls
b16d78261444a08ee6610e693c64bf9fc98c563d0ce46a1f02d7499abb30cc1a      10387  listproc.sty
3a775dacf7b0fe34a16a5ab8a4bee2c1dcd43bbc7f5677f5b69478dc52199a32      42910  llncs.cls
8bb02d626a1e13936f05664ece685839d02ec5c39ed4b5c94bf4839b3530447d      15308  mathpartir.sty
bd1120dec27e649eba2cf3eaa7d4a4938075b70384134668955ae97d599eb8a0       1546  mathptmx.sty
e89fd18a559a7c0e96a7d20b155e6dacb6464bee6bf412794c3c554317cc73d0       1452  olingrammar.sty
5f1790e864b371babf9ac73d384a87b82240009e43fab62ec81e13ffb0efbe84       3546  paper.tex
88b0608a1f67c6cfd0d5b589d0d376a3af66d41712a0d329a41984d171037c4b       9172  plstx.sty
1622485ce493c5438ececf3d0533f5a0d776fd08536427bef1479fc8112d1a71      12575  related_work.tex
f11e4372eb596958b3fcdcbe5dc46e282718f4bd17992af90d6fc86b7c6f10cd      52145  soundness.tex
dbac9f6578d81cbdcd02ecf6a495f7228673036a7564f3f348f4a574647a0fce       5589  trfrac.sty
97a731222bba1f0c7c843a3180670cec1e1bee4a5816e2ac57bed76662085f1f      69517  type_erasure.tex
```
