# Composable and Modular Code Generation in MLIR: A Structured and Retargetable Approach to Tensor Compiler Construction

- **Authors:** Nicolas Vasilache, Oleksandr Zinenko, Aart J. C. Bik, Mahesh Ravishankar, Thomas Raoux, Alexander Belyaev, Matthias Springer, Tobias Gysi, Diego Caballero, Stephan Herhut, Stella Laurenzo, Albert Cohen
- **Venue / year:** arXiv preprint 2022 (`2202.03293`, submitted 2022-02-07); no journal reference on the arXiv record
- **Canonical link:** https://arxiv.org/abs/2202.03293
- **License:** CC BY 4.0 (the licence the arXiv record links, `http://creativecommons.org/licenses/by/4.0/`)
- **Thread(s):** F, G (topic: Array languages and typed array programming / lowering target)
- **Storage form:** raw LaTeX source (arXiv e-print `2202.03293`), as shipped
- **Status:** stored

## Provenance

Fetched 2026-10-09 from `https://arxiv.org/e-print/2202.03293` (HTTP 200, gzip-compressed
tar, 2,337,538 bytes, SHA-256
`df6776c36465356c18d16ac7d46bf9c5f5ce84d4ce4b50a0a99b5db782b71b0e`). Identifier resolved
from the abstract page's `citation_*` metadata (the arXiv Atom API answered "Rate
exceeded" at the time). Unpacked with `tar xzf`; no generated files (`.aux`, `.log`,
`.out`, `.blg`, `.synctex*`, `.fls`, `.fdb_latexmk`) were present. `ms.bbl` is kept because
`bibliography.bib` is present.

The bundle is kept as shipped, including its duplicate subdirectory
`Composable and Modular Code Generation in MLIR/`, an earlier copy of the same sources:
every `.tex` file in it is byte-identical to the top-level one except `0-abstract.tex`,
and its `ms.bbl` differs from the top-level `ms.bbl`. The top-level files are the ones
`ms.tex` inputs.

100 files, 3.5 MB in total; largest single file 142,939 bytes
(`figures/MLIRtoLLVMandIntrinsics.png`). No file is over the 20 MB cap.

Main sources (top level), SHA-256:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `ms.tex` | 5,793 | `aa5e20a25d73c4e9285562dc648c80c079aa39a341d0d1115ba219117834ed95` |
| `0-abstract.tex` | 917 | `baace6a839bf83f6f26c37dd402feb16e2da7aebb30ad8736ee17d11692669a1` |
| `1-intro.tex` | 8,359 | `d5e5af8fd686ca6a85fa6f45b2954f84b87dc76969568f5b29449a4638820a91` |
| `2-codegen-flow-overview.tex` | 17,841 | `879b92ed3203ac66b06f3faae1eba2041e5ff19c86d60ae27b6b462725dd7d00` |
| `3-transformations.tex` | 38,966 | `5497763e9e175355903eabf336ae943e725f65a0594fbc48bfd61108269b07d3` |
| `4-experiments.tex` | 42,638 | `9ab1288fc6d60bac421cc7ed8eb3f296cd8289957933c126e17b00080966f59d` |
| `5-related-work.tex` | 14,005 | `90ae6c6f65011a5ac1bb434e19df6d2d5527ac0f8536a8cdc749d85bfa32654f` |
| `6-conclusion.tex` | 2,400 | `a84562f755b80465dfb0d0248843cb7fa20b6d11d71e493943164449af756f93` |
| `a1-annotated-examples.tex` | 8,059 | `1e4d0645a6eb6bc7181835fcd9a13dc7108c30cf284db38673d1837850e2f749` |
| `bibliography.bib` | 45,183 | `596f8d7b0df958b82d06435b59f5770d57a798b7a11231f047e5c6f2970040d9` |
| `ms.bbl` | 45,520 | `b438b04e1b64eb21192d71d603f03113a5b18a63d587543976d0725e72ced235` |

## Related entries

- `lattner-2020-mlir` (the MLIR paper this one builds on) and `lucke-2024-transform-dialect`
  (the Transform dialect this paper's Section 3.5 anticipates) are already in the library.
- `docs/mlir/docs/Rationale/RationaleLinalgDialect.md`, `docs/mlir/docs/Dialects/Linalg/`,
  `docs/mlir/docs/Bufferization.md` and the ODS excerpts under `code/mlir/include/mlir/Dialect/`
  describe the same abstractions at the LLVM pin.

## File manifest

Every stored file except this one: 100 files, 3,378,714 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
baace6a839bf83f6f26c37dd402feb16e2da7aebb30ad8736ee17d11692669a1        917  0-abstract.tex
d5e5af8fd686ca6a85fa6f45b2954f84b87dc76969568f5b29449a4638820a91       8359  1-intro.tex
879b92ed3203ac66b06f3faae1eba2041e5ff19c86d60ae27b6b462725dd7d00      17841  2-codegen-flow-overview.tex
5497763e9e175355903eabf336ae943e725f65a0594fbc48bfd61108269b07d3      38966  3-transformations.tex
9ab1288fc6d60bac421cc7ed8eb3f296cd8289957933c126e17b00080966f59d      42638  4-experiments.tex
90ae6c6f65011a5ac1bb434e19df6d2d5527ac0f8536a8cdc749d85bfa32654f      14005  5-related-work.tex
a84562f755b80465dfb0d0248843cb7fa20b6d11d71e493943164449af756f93       2400  6-conclusion.tex
3e968ce4f0cd8f790a48967bf64018cf3ce1e2363218944fa4c3d0462a93e8a9      89986  ACM-Reference-Format.bst
2058a01bc4965204fd6c01a6ec6dd0d4de86597b7b71bc82fb58fea1d5dbf49e        711  Composable and Modular Code Generation in MLIR/0-abstract.tex
d5e5af8fd686ca6a85fa6f45b2954f84b87dc76969568f5b29449a4638820a91       8359  Composable and Modular Code Generation in MLIR/1-intro.tex
879b92ed3203ac66b06f3faae1eba2041e5ff19c86d60ae27b6b462725dd7d00      17841  Composable and Modular Code Generation in MLIR/2-codegen-flow-overview.tex
5497763e9e175355903eabf336ae943e725f65a0594fbc48bfd61108269b07d3      38966  Composable and Modular Code Generation in MLIR/3-transformations.tex
9ab1288fc6d60bac421cc7ed8eb3f296cd8289957933c126e17b00080966f59d      42638  Composable and Modular Code Generation in MLIR/4-experiments.tex
90ae6c6f65011a5ac1bb434e19df6d2d5527ac0f8536a8cdc749d85bfa32654f      14005  Composable and Modular Code Generation in MLIR/5-related-work.tex
a84562f755b80465dfb0d0248843cb7fa20b6d11d71e493943164449af756f93       2400  Composable and Modular Code Generation in MLIR/6-conclusion.tex
3e968ce4f0cd8f790a48967bf64018cf3ce1e2363218944fa4c3d0462a93e8a9      89986  Composable and Modular Code Generation in MLIR/ACM-Reference-Format.bst
1e4d0645a6eb6bc7181835fcd9a13dc7108c30cf284db38673d1837850e2f749       8059  Composable and Modular Code Generation in MLIR/a1-annotated-examples.tex
000dc35c9af8ef89a20ffd62932f81b92dd23570219278818a6e8225a46976fa     103404  Composable and Modular Code Generation in MLIR/acmart.cls
596f8d7b0df958b82d06435b59f5770d57a798b7a11231f047e5c6f2970040d9      45183  Composable and Modular Code Generation in MLIR/bibliography.bib
29ffc3af7bb88b39d51b0861952194dcd64186e5b99ad11b3bd805297ae6236c     129458  Composable and Modular Code Generation in MLIR/figures/BirdsEyesViewCodegenFlow.png
38b87ab0c85c082b870e9d60747ebe169ed2ba872f367a8e9cb40e4e9ce59cae      74226  Composable and Modular Code Generation in MLIR/figures/MLIRtoLLVM.png
0e851c1fb9d381987e2f2a99ff5e79ed08fd3c8779fb7029b92f391a510b4057     142939  Composable and Modular Code Generation in MLIR/figures/MLIRtoLLVMandIntrinsics.png
a2e38db1a6485ca08355acb7e516d0bb298da05ef8e3b2adcb72ed750ba57e07      41132  Composable and Modular Code Generation in MLIR/figures/bufferization.pdf
0df05a08285e3d572635f1e9b620eabdeb2d439d9487f4742e5c632fd9604372      30133  Composable and Modular Code Generation in MLIR/figures/bufferization_conflict.png
7032ffe25dd81eafa65370363f9b0f2e45b737ae6021bce1bc3a8b576c18cc81      19991  Composable and Modular Code Generation in MLIR/figures/bufferization_notation.png
702f0691ee31d80b70b2d718475f11be000ffbf3c88765d13ebe79a362c4c0bd      48825  Composable and Modular Code Generation in MLIR/figures/bufferization_notation_conflict.pdf
0f346320daec6b70b5436b63aefdbe8f0e51211e9b427af48b97d8ef5e770ffd      43147  Composable and Modular Code Generation in MLIR/figures/bufferization_phase2.png
5eaf65e517e2933eb2a2ab44a67ad06f95e400397e1ff4f330e3f817527b5b9c      43685  Composable and Modular Code Generation in MLIR/figures/lower_vectors.pdf
9a0a231ef2f5a71aa7c42a09ccae893ea05241a0ef1b4be46527d5fe154bc1ae      18004  Composable and Modular Code Generation in MLIR/figures/memref.pdf
4235f2229101299a384b7adeb019848e64aef481f15132ed897e68856bf09bb3      11934  Composable and Modular Code Generation in MLIR/figures/mlir_example.pdf
f1e6b23c042b717744ca265bdc047876d06c3d1b67f5efb860c35320221980e9      11942  Composable and Modular Code Generation in MLIR/figures/mlir_example_large.pdf
6c6af579fa90cccfb2c3456e3e8ac785230368f66a80e8f19e94d719d34a65d5      12124  Composable and Modular Code Generation in MLIR/figures/opdsl_example.pdf
7157ff551838679c70a05f6cfb36b89903b4a4721d55f30f1a66a13ec3abcc2c      12123  Composable and Modular Code Generation in MLIR/figures/opdsl_example_large.pdf
43725654ab97b38b7e5322d5af34cb143e93f7716ca0fec6ca95a37af15b8f6d      38895  Composable and Modular Code Generation in MLIR/figures/padding.pdf
fae72ede0cd4c47eb99d32f99f0290f01d28524ddd900cfd7e728c681237985d      30918  Composable and Modular Code Generation in MLIR/figures/sparse_layouts.pdf
6cd0eb571843b76ed45f7bcb6b9900ee5dcc849eebdd0a6f71a3846f5819de41      36904  Composable and Modular Code Generation in MLIR/figures/sparse_lowering.pdf
ead1ac2ebd9ab7a886e2cea7089c0da688563ee559ade9b335313486beffd5eb      38172  Composable and Modular Code Generation in MLIR/figures/tiling.pdf
f004b620f7cd0b3597ed6c0c88a0798ee58fef50996a4f9d039e7c25b77320b1      13405  Composable and Modular Code Generation in MLIR/figures/tiling_experts.pdf
8027d1dae7965a2fd87c0b6fc07b3ee761284c2bd153de8e73be4c0a63378add      13406  Composable and Modular Code Generation in MLIR/figures/tiling_experts_large.pdf
d2d6de63985f4d97c3d0310f13d715eb80f66bd04befdf7ebfd00fbe1f48f28f      31622  Composable and Modular Code Generation in MLIR/figures/vector_deeper.pdf
ef1da4a09d0e9fcb3e16c703914590142dcc7b19f573c09ac218a1fda62839db      43651  Composable and Modular Code Generation in MLIR/figures/vectorization.pdf
9131df8848694fd2a47c73006619ef9c94502e85b21cd79b5705bc87857fb576      44882  Composable and Modular Code Generation in MLIR/ms.bbl
aa5e20a25d73c4e9285562dc648c80c079aa39a341d0d1115ba219117834ed95       5793  Composable and Modular Code Generation in MLIR/ms.tex
2399a53c7256b5e2c0934262ce7f031b2c2179a3fff302887f1a1083ded2d00f      21318  Composable and Modular Code Generation in MLIR/plots/bandwidth/bandwidth-bound-l1.pdf
56a874427e95c96dc782fec7b174923a28110b6f69bde14396d8f3dac9d9eafc      21561  Composable and Modular Code Generation in MLIR/plots/bandwidth/bandwidth-bound-l2.pdf
13e5e72e88b871eb012c2530dc65995229de1ab36f7561627ca03526ce239f18      21248  Composable and Modular Code Generation in MLIR/plots/bandwidth/bandwidth-bound-l3.pdf
2c1224533e37b6aafdeb8f0ab0bd1e3b04da5dd2d9e7415a6191111a3af4d967      17252  Composable and Modular Code Generation in MLIR/plots/conv/conv_1d.pdf
b6cb9957ea28fe1d2050c526cfc63e7fafefb7df362196a79b3a872e2521d159      17420  Composable and Modular Code Generation in MLIR/plots/conv/conv_2d.pdf
46a949438464d494438b473fdd1ae5deeecebaf0dffb9ea650936ec3b9534759      42074  Composable and Modular Code Generation in MLIR/plots/copy2d_small/copy_2d_static_small_2_gbyte_per_s_per_iter.pdf
161b5c966e667d3a01d29dc86967f108170098ebc6ee7de203edca65fcf09af7      20373  Composable and Modular Code Generation in MLIR/plots/depthwise_conv/depthwise_conv_1d.pdf
db400960e39dcb4dd915d9f50167e9f2d9d46a2bf312bf36c60b031031e1c678      16317  Composable and Modular Code Generation in MLIR/plots/depthwise_conv/depthwise_conv_2d.pdf
c125eb4f4fbf9f0490eaa6066f9cf89dbe377f0e3f09a9fa1f4a6326fd360116      20049  Composable and Modular Code Generation in MLIR/plots/matmul/matmul.pdf
3020494cd963ce7ba9b02c04d27c901237e977614260e0b3d2d4d5bbcd671ca8      26568  Composable and Modular Code Generation in MLIR/plots/reduction/col-reduction-2d.pdf
2b601bac98d970c81fdc21da5302f9b112c8d9ca9cff94d71d69ebf4c4e3d5da      26688  Composable and Modular Code Generation in MLIR/plots/reduction/row-reduction-2d.pdf
91a5143ef6e700112d040ec8ea206b2321337821318d093bdb0e21d255057b5f      25390  Composable and Modular Code Generation in MLIR/plots/transpose/single-tiling8x8.pdf
43caaae7b5d9965c3809a6f5ddbb50a220e9d4b058c5d2884e341a84cb7ba718      29409  Composable and Modular Code Generation in MLIR/plots/transpose/transpose_2d_static_l1_repro_gbyte_per_s_per_iter.pdf
37ae666d9f73c7eac7b5afb85a3d2a0f0ed1f4faf4b11c58aa18bec6634d7e3b      35691  Composable and Modular Code Generation in MLIR/plots/transpose/transpose_2d_static_l2_repro_gbyte_per_s_per_iter.pdf
4a4987b19b8be8eb2c60e73298b630a752a4d677426cdda0820f4c3cb37f7b8f      38714  Composable and Modular Code Generation in MLIR/plots/transpose/transpose_2d_static_l3_repro_gbyte_per_s_per_iter.pdf
1e4d0645a6eb6bc7181835fcd9a13dc7108c30cf284db38673d1837850e2f749       8059  a1-annotated-examples.tex
000dc35c9af8ef89a20ffd62932f81b92dd23570219278818a6e8225a46976fa     103404  acmart.cls
596f8d7b0df958b82d06435b59f5770d57a798b7a11231f047e5c6f2970040d9      45183  bibliography.bib
29ffc3af7bb88b39d51b0861952194dcd64186e5b99ad11b3bd805297ae6236c     129458  figures/BirdsEyesViewCodegenFlow.png
38b87ab0c85c082b870e9d60747ebe169ed2ba872f367a8e9cb40e4e9ce59cae      74226  figures/MLIRtoLLVM.png
0e851c1fb9d381987e2f2a99ff5e79ed08fd3c8779fb7029b92f391a510b4057     142939  figures/MLIRtoLLVMandIntrinsics.png
a2e38db1a6485ca08355acb7e516d0bb298da05ef8e3b2adcb72ed750ba57e07      41132  figures/bufferization.pdf
0df05a08285e3d572635f1e9b620eabdeb2d439d9487f4742e5c632fd9604372      30133  figures/bufferization_conflict.png
7032ffe25dd81eafa65370363f9b0f2e45b737ae6021bce1bc3a8b576c18cc81      19991  figures/bufferization_notation.png
702f0691ee31d80b70b2d718475f11be000ffbf3c88765d13ebe79a362c4c0bd      48825  figures/bufferization_notation_conflict.pdf
0f346320daec6b70b5436b63aefdbe8f0e51211e9b427af48b97d8ef5e770ffd      43147  figures/bufferization_phase2.png
5eaf65e517e2933eb2a2ab44a67ad06f95e400397e1ff4f330e3f817527b5b9c      43685  figures/lower_vectors.pdf
9a0a231ef2f5a71aa7c42a09ccae893ea05241a0ef1b4be46527d5fe154bc1ae      18004  figures/memref.pdf
4235f2229101299a384b7adeb019848e64aef481f15132ed897e68856bf09bb3      11934  figures/mlir_example.pdf
f1e6b23c042b717744ca265bdc047876d06c3d1b67f5efb860c35320221980e9      11942  figures/mlir_example_large.pdf
6c6af579fa90cccfb2c3456e3e8ac785230368f66a80e8f19e94d719d34a65d5      12124  figures/opdsl_example.pdf
7157ff551838679c70a05f6cfb36b89903b4a4721d55f30f1a66a13ec3abcc2c      12123  figures/opdsl_example_large.pdf
43725654ab97b38b7e5322d5af34cb143e93f7716ca0fec6ca95a37af15b8f6d      38895  figures/padding.pdf
fae72ede0cd4c47eb99d32f99f0290f01d28524ddd900cfd7e728c681237985d      30918  figures/sparse_layouts.pdf
6cd0eb571843b76ed45f7bcb6b9900ee5dcc849eebdd0a6f71a3846f5819de41      36904  figures/sparse_lowering.pdf
ead1ac2ebd9ab7a886e2cea7089c0da688563ee559ade9b335313486beffd5eb      38172  figures/tiling.pdf
f004b620f7cd0b3597ed6c0c88a0798ee58fef50996a4f9d039e7c25b77320b1      13405  figures/tiling_experts.pdf
8027d1dae7965a2fd87c0b6fc07b3ee761284c2bd153de8e73be4c0a63378add      13406  figures/tiling_experts_large.pdf
d2d6de63985f4d97c3d0310f13d715eb80f66bd04befdf7ebfd00fbe1f48f28f      31622  figures/vector_deeper.pdf
ef1da4a09d0e9fcb3e16c703914590142dcc7b19f573c09ac218a1fda62839db      43651  figures/vectorization.pdf
b438b04e1b64eb21192d71d603f03113a5b18a63d587543976d0725e72ced235      45520  ms.bbl
aa5e20a25d73c4e9285562dc648c80c079aa39a341d0d1115ba219117834ed95       5793  ms.tex
2399a53c7256b5e2c0934262ce7f031b2c2179a3fff302887f1a1083ded2d00f      21318  plots/bandwidth/bandwidth-bound-l1.pdf
56a874427e95c96dc782fec7b174923a28110b6f69bde14396d8f3dac9d9eafc      21561  plots/bandwidth/bandwidth-bound-l2.pdf
13e5e72e88b871eb012c2530dc65995229de1ab36f7561627ca03526ce239f18      21248  plots/bandwidth/bandwidth-bound-l3.pdf
2c1224533e37b6aafdeb8f0ab0bd1e3b04da5dd2d9e7415a6191111a3af4d967      17252  plots/conv/conv_1d.pdf
b6cb9957ea28fe1d2050c526cfc63e7fafefb7df362196a79b3a872e2521d159      17420  plots/conv/conv_2d.pdf
46a949438464d494438b473fdd1ae5deeecebaf0dffb9ea650936ec3b9534759      42074  plots/copy2d_small/copy_2d_static_small_2_gbyte_per_s_per_iter.pdf
161b5c966e667d3a01d29dc86967f108170098ebc6ee7de203edca65fcf09af7      20373  plots/depthwise_conv/depthwise_conv_1d.pdf
db400960e39dcb4dd915d9f50167e9f2d9d46a2bf312bf36c60b031031e1c678      16317  plots/depthwise_conv/depthwise_conv_2d.pdf
c125eb4f4fbf9f0490eaa6066f9cf89dbe377f0e3f09a9fa1f4a6326fd360116      20049  plots/matmul/matmul.pdf
3020494cd963ce7ba9b02c04d27c901237e977614260e0b3d2d4d5bbcd671ca8      26568  plots/reduction/col-reduction-2d.pdf
2b601bac98d970c81fdc21da5302f9b112c8d9ca9cff94d71d69ebf4c4e3d5da      26688  plots/reduction/row-reduction-2d.pdf
91a5143ef6e700112d040ec8ea206b2321337821318d093bdb0e21d255057b5f      25390  plots/transpose/single-tiling8x8.pdf
43caaae7b5d9965c3809a6f5ddbb50a220e9d4b058c5d2884e341a84cb7ba718      29409  plots/transpose/transpose_2d_static_l1_repro_gbyte_per_s_per_iter.pdf
37ae666d9f73c7eac7b5afb85a3d2a0f0ed1f4faf4b11c58aa18bec6634d7e3b      35691  plots/transpose/transpose_2d_static_l2_repro_gbyte_per_s_per_iter.pdf
4a4987b19b8be8eb2c60e73298b630a752a4d677426cdda0820f4c3cb37f7b8f      38714  plots/transpose/transpose_2d_static_l3_repro_gbyte_per_s_per_iter.pdf
```
