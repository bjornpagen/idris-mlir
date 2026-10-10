# Frex: Dependently Typed Algebraic Simplification

- **Authors:** Guillaume Allais, Edwin Brady, Nathan Corbyn, Ohad Kammar, Jeremy Yallop
- **Venue / year:** Proc. ACM Program. Lang. 9 (ICFP), Article 237, 36 pages, August 2025
- **Canonical link:** https://doi.org/10.1145/3747506 (arXiv:
  https://arxiv.org/abs/2306.15375)
- **License:** arXiv non-exclusive license; the source states that the authors applied a CC BY
  licence to any Author Accepted Manuscript (`frex.tex`, the "Note" before the bibliography)
- **Thread(s):** dependent-equality (Array languages and typed array programming); also E
- **Storage form:** raw LaTeX source (arXiv e-print `2306.15375`, v2), 85 files, 1.4 MB:
  top-level `frex.tex` (8,069 bytes, SHA-256
  `72739ae429c392d88a515c4f4de34469301e0d42b432c0febc2274390521a7aa`), section files
  (`new-intro.tex`, `overview.tex`, `core.tex`, `reflection.tex`, `evaluation.tex`,
  `idris2.tex`, ...), `frex.bib` (75,224 bytes, SHA-256
  `89cb376300a233539a20aa435a9aec7c85657a9512a456c1fb5c430c73d5fcd0`) and `frex.bbl` (kept:
  `.bib` present), timing data in `csv/`, MetaPost figures, and the bundle's own
  `create_diagram.sh` and `fancyvrb.sty.patch` (stored as shipped, never run)
- **Status:** stored

## Provenance

Fetched 2026-10-09 from `https://arxiv.org/e-print/2306.15375` (served from
`https://arxiv.org/src/2306.15375`, gzip-compressed tar, 485,178 bytes, SHA-256
`2379d95df5ceb132a05621efa937e8e2c3147eb9732130e333681d717be77716`). Unpacked with `tar xzf`;
no generated files were present. The arXiv abstract page gives the journal reference; the DOI
was resolved with the Crossref API.

## File manifest

Every stored file except this one: 85 files, 1,257,742 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
e1fb962c2a22a372946edaf2dbd2ff7011637e7d9b5ab66669760f7b88046b33       4007  00README.json
ecbc9bfbf595d820dcc271d1bada20448c6eb5a6cf4d57de8dc4ed2608d5f23f      90333  ACM-Reference-Format.bst
6ed058b4e589ed9f8eee4925aff109158901dd0f92e68cfaf8f3c21769fd7676        346  Cross.idr
7baae37352fbd780241d9e63347a63d5a867a84e0612c80530a73f59d679ea44        683  abstract.tex
da283243f63178da207da639cc94652407a0fe218d3cd12b852d21de9d01c8da       2773  acmart.bib
c8fbf6a083bd6a25b6b7ef0c026411f8d0ad7f253fa3b7b0b4817a9d81840618     121725  acmart.cls
555a33a0485d23250b7fb340dd8781b8afc91a9c71faa2a744705dd1d5d2a6e8      20721  acmauthoryear.bbx
cb22394f982fcaf8ed7f0df34234696f45fc130afcf9ee3cd1260805ad2170d1       6245  acmauthoryear.cbx
a5bab6fed4585780632607ef2790ee8797864244a4b80bc0c4e3bfcb76b0c2bc       1093  acmdatamodel.dbx
bbf30642de2ea8b16f2d7056f9114af7e1d29efb2293848e61197ccd9e897943      19840  acmnumeric.bbx
22db9dd1bcb095d8af106e6a834f0ce1f182c73eee656589043c0153f226d911         90  acmnumeric.cbx
dd59eb18d45fee533e2e7302b82875e67541abc437b6792a628b74628a161d29      25944  agda.sty
861ab2a3f4dc60dc1c63dbbec476e36be6adff8a5efe2864659fd1732a4e396f       1391  agda.tex
c8a7769daed8843ce0bad0eb942e84728413d596c3660975f17359536f643ebc       4324  appendix.tex
c8a7769daed8843ce0bad0eb942e84728413d596c3660975f17359536f643ebc       4324  automated-appendix.tex
d98ce5fd3e9b13eafe00925ec85758772f74b1e901fbc879d00280b144d51dfd      54647  automation.png
7a3a6d6c9a8cb32a00c6c60d335aac8d95cce198e5d5e679eeacf6ec87c7d56e      28983  background-listings.tex
eb6b7eb87dc0b562878589ce8ebb14f6373c3d67b033e593259e58cfce748a29       2107  background.tex
2fd52ca3671e9462788b1268e45648dc53104273786c8519c2add56de2d6d1a2       2989  ccsxml.tex
407474d543b70e44d7613a1e475b26b1f5ee36182c5c3be7884d50d298b322ab      13307  certificates-listings.tex
5b492fe2136063c7ff634db664baadabc18cc089c65192e362330737232f44ef        221  code-listings.tex
69672064537a55af8cfc76952442a5db2b3ca78d38fc15f6de0494e73b4455b4      14573  conclusion.tex
2f3a1d24f3091e5cd17cc4beba369656667ba48c420fd37cc4fc29c3c27714b1      37437  core-listings.tex
896cb17e4b243913d701b7350ac9435186d0b8354e98a1157f14c3d978ce93b3      15208  core.tex
af254b2f48727650370b2fd783a52b26073e0c4a662e08dc9ac816d4aa70d5d7        350  create_diagram.sh
15ab7a52236615b7066a81b323209c6fa1ee01ae25e31e6ed26c02230c0150d3        431  csv/10vars_commutative.csv
e874b2c8d26e1993247136bb9f31116d50f8f091501a4f64978851b7b87fc858        426  csv/10vars_noncommutative.csv
5e1c8a046c413cdc3758f5197c56ca17d6948cb9721f1df1bc3bd27f97117acb        328  csv/15vars_commutative.csv
d410fd9c0537c9546df9077211c4da25b367f5d40fbf7bc02d43d3abaeeae83d        331  csv/15vars_noncommutative.csv
119babfc9ba690806d3c594adaac0fffbd3b7865ad776c4e3d29e2a026b56ecf        598  csv/1vars_commutative.csv
6e59e933aeadc3e34681ddabac539f390c610e16839783e0776eea7126bd1de0        598  csv/1vars_noncommutative.csv
bda1e5cd983361bb84085574e384200696c30ad0a9cb74b9c613b5cabade5366        533  csv/5vars_commutative.csv
79a2d10a2ebfc0775ab60b8bf2bff9c490e042ea90301b8bb5789e50ffc75a0e        526  csv/5vars_noncommutative.csv
40291d7fb91adc6050b483590bcee313fb1ab37865b1c8ac6a0dbcca1268d78a        102  csv/Monoid_commutative_1.csv
6b8412a1e9d3783c0115d0768d6b04899ff07b9512d0ba034e78d7b0b27ceaa8        722  csv/Monoid_commutative_2.csv
a21a9d0dfd6473a44308291363dc497bbd8aee2b20f4d926b5ec8fc647a5978b      67909  csv/Monoid_commutative_3.csv
62c4b7062da0252f83871578bb512862fbd8366f3a91caf335505f296d58e671        108  csv/Monoid_noncommutative_1.csv
2cb6872eb2a58da61d530d3f035adb0824c16c16da5c071cc8643386e7d4ccc2        719  csv/Monoid_noncommutative_2.csv
bbc6de7e1144186212716edae8cf9069efff056037e12e6de2e5d5727d967b0d      36703  csv/Monoid_noncommutative_3.csv
488f18ff86391eb787d6952208714e0d27cb6531ab4d0583bf0b56bd7f369c36        213  csv/commutative.csv
459cea22bc7450f8c26956fcead9c447b805c20a59bb0e2ecd4b2e25f3a8c924        215  csv/noncommutative.csv
584f3b8072be576b4dc60d219de3d81d41af56102bfcb872e8249f8ae0e17dd5       9350  def.tex
d0d65a5259b11c9c268dd2b71d162ecbab53a1b9aa9d89a8f7be3b0fce0140d4       4586  deps.tex
0f29825df79ec3988dde6f82ae616cf5cf406af2b626bdf063a6a50af9bf6d98       1817  diagram-01.mps
2e175f31d24d8e207bacdd4595751ca8a00060df00a950cb9c86390839c9a805       2744  diagram-02.mps
1513914e37cc69c1cf76f8b9fc1e37b60d0aac123319f47f47ccafda736c442f       2375  diagram-03.mps
c35efc65ff2d6d9ff740fcf3fcdad12b947c347f50862bfcea73ea489be55a37       3329  diagram-04.mps
5b35a27b4c8c232aa5cd8d262fa2f7e3cabeef13ec8f5c898bc1923912672a2f       2990  diagram-05.mps
d2d52ec0338aaddaf5e41084fe657b9821313be34a42c2092827c7af203a6dd8       3165  diagram-06.mps
5a186500ede54f65034823d9245d69244ad94a3b00ac87a824d87ec9afdc10cc       2612  diagram-07.mps
3100861e014c87b3e5f6f9297f911f478718e8cb59be85f9a28377ae60b79247       2236  diagram-08.mps
d444fdd940c61e1f46b521aa879f043459103485f1db9bff2cc5f894a48ac84b       3810  diagram-09.mps
0d46c9aad8cc004a78155b4c93b7ec83d54da47ed2ca202aa09c07bb9d117c6c       3178  diagram-10.mps
ea7023c6b39883c01e6fcff1afa4c3b9ef8b870028254467488009eed9bcd959       2058  diagram-11.mps
f1ca3f23e612e80df1e8c918cfc9f777c4ca8b503b30439dff4bcaeb71492cb8       2467  diagram-12.mps
b2285be2cd71f2066d9ff94010e6602601f66846e11ab1f77319af7b97d2fb49       2262  diagram-13.mps
7d0a558215e8b5ad273d53f6183f3f66b579ef4b15caad48d324fda664d77534       3735  diagram-14.mps
a2a3092c61c71d42269ec8b6f5aefe8116d48e9918df719e91492a99ba77d9f7       1022  evaluation-listings.tex
6d20c4437281449b301f3abd742b34b46cbc39494d75964a34d7444482551206       7931  evaluation.tex
2233291bd8086e7b0eeeba06edda9e2c576b96275de99de3b366eacf047813e8       2584  experiment-unused.tex
6a42951530be6ea0c3adcccc1bd732c7c533005bc557f27d29db68b9c53f5a06      43048  fancyvrb.sty
6f527f688f4f65e4b2f47b80693ef9324e5a1ebb6607410e698b839d20cf8de3        558  fancyvrb.sty.patch
55c2f7a6947eb0e142b662e5154aa56074b6094043f5e5ea691001ae38cf5104      41514  frex.bbl
89cb376300a233539a20aa435a9aec7c85657a9512a456c1fb5c430c73d5fcd0      75224  frex.bib
72739ae429c392d88a515c4f4de34469301e0d42b432c0febc2274390521a7aa       8069  frex.tex
2f9e032c97eaa2a7ab0113775c65645c6f4fcd57cbd370bcf7df6a3809562e7b      55578  frexlib-listings.tex
b325a6519c1a8394274c854747029d2874b1e0f1980b1cc1bcd7aa9f0909eada       8779  frexlib.tex
6c351e622066251929ea4a5230345f4d4dad6ac9ccd96ab6affddffb2d105401       4541  generic.tex
56a3265424cf3d11f005277b8e7d49d8da8ae04a470f32f287660fe51d5a9b7f       5498  idris2.tex
585c09efc17469189f28ddaec49d5b59fac023f4283852e733433bfeb6700be0       4879  intro-printer.tex
10968302b702e36b09e0c22ecb4a447f926a0e629ee57e1222099dfec2ccf36a      43730  introduction-listings.tex
1d3b148a56e02f010329471dafc2be3a278f5d5a51c8b3e0b074ffcbd6ffb2ea      14129  involutive.tex
dc7b63fc37b2eb47460725b83e3b72367feeed71dcd7da5b5f30b15be1e0a4ee       2871  katla-preamble.tex
968b94ddc52c1882b96a241bc1298de27bf0ac6c02f558c8a761ad2281f88954        584  lessons.tex
a390f50b4882fed32c02372365b8f15449e727deb0505292ef316cc463900077      10444  new-intro.tex
6209c022515fde4d1f439f0f51be1a7cceae121c1e7083c60009b878e6b3bd4f       2569  oksemantics.sty
f8b4e3634b04eefe44eb61436735150245aef05949565db97a225a7101804c92      18946  overview.tex
1ee31102e3595da76b3a5715a5f72c0499eaa632c9a2c1aba7ff992dedcc5f82       9322  printing.tex
30eb030b79cab3c24599f4ac051534c9bf40397cd73996758886902a474469ef        705  provability.tex
ac5dd45029fd103cd2354c6f794b02750b1237561a41688a636946215d7c81a5       2776  reflection-listings.tex
7519fb310e447274e61222e0dc4ed69c5f5e5821eb59423f81ea49b06a3cd733       6683  reflection.tex
9fc6542b95e98d0e78b2a18c736f52daae7ed36f0536e4eb5d5029b7c1fa8a3f      47406  solve-type.png
efd84e069c555d69805fd921d1735512c841585640357df8032c8d802a5d8564     123003  solve-types.png
6e01cba3f2093c45fc065fd7675e4ac74f1fd74a73996270feb7153438721b8d      75315  solve-vect-type.png
18a52bb70cfd9f7dad1b4b9b76411766ce46d4063f4659f9920df99823edfc6e       3197  table-of-frex.tex
```
