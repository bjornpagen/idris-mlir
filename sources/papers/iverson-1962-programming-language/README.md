# A Programming Language (partial: preface, Chapter 1, part of Chapter 3)

- **Authors:** Kenneth E. Iverson
- **Venue / year:** book, John Wiley & Sons, New York, 1962 (LCCN 62-15180)
- **Canonical link:** no DOI; Jsoftware's transcription at https://www.jsoftware.com/papers/APL.htm
- **License:** © 1962 John Wiley & Sons / K. E. Iverson; the transcription is served openly by Jsoftware, no licence stated (verify)
- **Thread(s):** Array languages and typed array programming (cluster apl-lineage)
- **Storage form:** HTML transcription: `APL.htm` (frameset), `APLTOC.htm` (contents of the whole book, all seven chapters), `APL1.htm` (the transcribed text: preface, Chapter 1 "The Language" §1.1–1.23, and Chapter 3 "Representation of Variables" §3.1–3.4), `adoc.css`, and `APLimg/` (171 small `.bmp` glyph and figure images the text uses for notation that has no Unicode form; 389,128 bytes in all). Chapters 2 and 4–7 are not transcribed on the host and are not stored.
- **Status:** stored (partial)

## Provenance

Fetched 2026-10-09 with `curl -sL -O` from `https://www.jsoftware.com/papers/APL.htm`,
`.../APLTOC.htm`, `.../APL1.htm`, `.../adoc.css`, and each image referenced by `APL1.htm` from
`https://www.jsoftware.com/papers/APLimg/<name>.bmp` (171 files, all HTTP 200). The library's
`bibliography.bib` already has this book as key `APL` (harvested from a paper's `.bib`); no new
entry is needed.

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `APL.htm` | 287 | `58a6060bdd19768da1b0f76b0c9697822d5a44278d9120a8c91a79c63829fd33` |
| `APLTOC.htm` | 25,097 | `532fcd520e1da0dd24c97491e51c63f9490ad2d978dd97f1ae63c461786da7c0` |
| `APL1.htm` | 524,619 | `6047c05525b94eb655e510c8537e322cd6d35a20f0da1eb74540a4fd246c7f67` |
| `adoc.css` | 501 | `5d7124486db1414db72e0012d37e4d948f69d697defe2af6aac4b976a62d1bdd` |
| `APLimg/*.bmp` | 389,128 (171 files) | per file: `shasum -a 256 APLimg/*` |

Anchors in `APL1.htm`: §1.8 Reduction at line 1495, §1.11 generalized matrix product at 2266,
§1.20 Levels of structure at 3966, §1.23 Ordered trees at 4526 (degree vector at 4912, full
left list at 6957).

## File manifest

Every stored file except this one: 175 files, 939,632 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
58a6060bdd19768da1b0f76b0c9697822d5a44278d9120a8c91a79c63829fd33        287  APL.htm
6047c05525b94eb655e510c8537e322cd6d35a20f0da1eb74540a4fd246c7f67     524619  APL1.htm
532fcd520e1da0dd24c97491e51c63f9490ad2d978dd97f1ae63c461786da7c0      25097  APLTOC.htm
7081f178ee223106cef5ae68f7827f55a7920795cf05e555fdf704d9755c42f3        118  APLimg/0tree.bmp
eb1a61832bc51a9ecc57c0d19f0dbe0a702b645fabc785b8ddce5ed16a9fbfd3        434  APLimg/1x12a.bmp
dfaf9357cddf58caf2d6758906b527160f9f5578902dcb7d3dd813d56723b3a0        362  APLimg/1x12b.bmp
028a07176f39c21112cb689dabb7c00f834a7eb9d0784434647d7c2e3ec57538        386  APLimg/1x12c.bmp
3b32cce94945d3f3ab14da1096f2d568541fc52b92f81e738c7b7a95995aad74        238  APLimg/1x13a.bmp
1f2b817d207acb3651b95d55826b3a06147dda28c94cd79c84b8dc845a0b19e9        246  APLimg/1x13b.bmp
0d6c7eed23f5162f2a83b0dacdf351ec997edc20df78e15e3b1ee0366ba5b208        254  APLimg/1x13c.bmp
f07ce0dd6dc2444b9e22a7f11a96f3cfbaf1c6c456be8913c2d0758a84ecd678        182  APLimg/APLbranch.bmp
bbce572bdc9d1a937ece0dffb58f90235cecd2710b7a675ff36f2fdd1a597d82         94  APLimg/alphaboscore.bmp
0c537666de80d348e1a11f5705cda3b8b0858b070805d0fb27d6484c5f70505b        114  APLimg/andeq.bmp
68b23a0c514c49d5a0c4b928e4a3bd961b031d92986c455f86e221f6f2c5c2a7        142  APLimg/bnearr.bmp
51a78a0662b822ce127e340ca5551528480a8c64510f5e655dc132cca499e171        142  APLimg/bnwarr.bmp
6c95b90601340691d62fba50daad6865063fa8282a9113d77a65e8e098330969        254  APLimg/bracket1x11.bmp
9df44e0bb5bc36737d8437ba4c09c5b1cc99da01b50dce441ac72036a091d815        586  APLimg/bracket1x12.bmp
e2046374c18b9a9f90586b88924026a5f8b5e4a11a6efcd0e84a8a4d3af3fff3        574  APLimg/bracket1x13.bmp
065b8e0a68e67ca7681ded5e5aa96568841fb8f89332ec5c28e72dfdb6872963        314  APLimg/bracket1x17.bmp
8906864cb0721cdc7a0f87c11abe7121d83fe79e6fdb51aa4d82dc21c11e8fd7        230  APLimg/bracketsx12.bmp
db8652ab40c1122aaac5e5a6b6a65e74008d7dd2d3caa7828792c78a396b1ce3       1146  APLimg/bracketsx7a.bmp
dc5ad4f7be5c776344092c48e6372636fda06b9621c0cc2069a5abd5ffa3bfdf        570  APLimg/bracketsx7b.bmp
dc2dd666e00c9c62b62885fb69b01c4cd73d941400c902f24550b288d9e787be        750  APLimg/bracketsx8.bmp
ebc62ea0afaaabfd3127fbc043ee9284e4d08ada5bbb614fdc99ed16d89b448e        130  APLimg/brarr.bmp
befaaafa90066e131fe2ffd534973b1370bec8a1a99dd575056bd4771410bf79        118  APLimg/btilde.bmp
9999b535d53abd2bf7aa49f9a69969e3d768112e3d65c488c7261a9cc290c5dd        142  APLimg/buarr.bmp
2d3621a4a813fbd7fbd7e51458e1ef94e9e2e6f90fb81e991343710d52dc2874        134  APLimg/circle1circle2.bmp
b85e0339cb469f839e996985c82f8f773aec9378912af36eb2f6f6d58bc61f12         98  APLimg/circledot.bmp
b5c814ead63b96a5a5639d070c8cc4ff46d6b77fcabbca185f9039d33f83bb25        102  APLimg/circleplus.bmp
75b28f6b4c2e800197da638628e5edb3718237c8a7ba9d6c1a593842058d3154        102  APLimg/circletimes.bmp
557d7b6ea227972692f325520ee186ff0cd54415ea3a558cafb86099748b1c3f        114  APLimg/darr.bmp
aa7175c670dbed53d072e743e1f86eb0a16cb8d448d877cdf74a005853a2c761        166  APLimg/ddy.bmp
8efdf2412d4c2171daf19fdf8ff8043842a241658e1ae465678a293998bc7548         86  APLimg/decode2.bmp
72576d9f9fec372699e24f20f32b6d5cb14b8db4fcd2699bfce67931a71d5e22        122  APLimg/demorgan.bmp
63964bb2111971afcbd74ea200154d4b72bc697f228702f74ea04c18643caf2c        118  APLimg/ecapboscore.bmp
14ea436937dfc75105fcd0695772cb4e2a153f2933718e221df8d0afb56ca892         98  APLimg/epsboscore.bmp
83068ece0e056e35e1e64b95864057e88283b2964e8198d834cbd1308353e8bc        118  APLimg/ex1x10a.bmp
de796fe7407695ebe884293e3d1416abef5db892fd1f736f9d22bc5c833d523b        222  APLimg/ex1x10c.bmp
9fb28fc2b895adf8d44045b41b111f38db64014e3b8ca7cc5934bba9dcd1bde8        122  APLimg/ex1x10d.bmp
ebb2d6c9a5ffb7d30ad9ef54512a2b35717ea63585d24e0fa83ee0576f949fe7        206  APLimg/ex1x10f.bmp
bc9e31d576860fabf1479de86462ffd13c4f3bd3c22cdb207836c81002a04d94        286  APLimg/ex1x45a.bmp
3f2339ff92e08aa89488d9a62f42c3a9d506a7ba860a4a820b6c003a5af7c1b0        366  APLimg/ex1x45b.bmp
de5cee72404949b00bb34d2149752161c8a10ae8e69ce19db6f4edd65ce0d16c        410  APLimg/ex1x45c.bmp
2464808709a2a29a2fda6746bbfd2956dd0e03b8995c795f591cc7935d8376da        334  APLimg/exp1x10.bmp
76a1e05e916370cab16c438c4b5c6b36ea5a6654eb40cce078fdb354920e0beb        118  APLimg/fboscore.bmp
c373edc10a1d3da46348598d59c2a16259375a54b07e58b6ff15b883bfc53fd3        266  APLimg/fcopyinit0.bmp
ed6754d4bd7ce4a242d5511543585e6937720ca5d3821b4d975e23404a99a091        266  APLimg/fcopyinit1.bmp
0eaf3312cd3e1d6fcac1f67b6f5d7c13f9b84742d83d56f6da3679738be2928a      34022  APLimg/fig1x16.bmp
9f58634ec98efe28cd863c8e1ca4c7a966cad07cb1bc4a18ee5f17b0e96736cc       5578  APLimg/fig1x17.bmp
f8987860ebaf6085f72b38528478d26c949eedef002b05494b1f26dd2b1b475a       6134  APLimg/fig1x22a.bmp
864b1b64f9c4f0e59071b4e87e4883e4167224d9147456ee2f1cb63a0d614935       6134  APLimg/fig1x22b.bmp
d19d72694ddbe3ee317e358c9f09020be3c6b1b53a26c1147beefbcd29a4fc58       1238  APLimg/fig1x22v.bmp
a3f0aec4b9dc261326b4e5f0defcd171555532845f42aca0c6c7baa6fcb172f6       1202  APLimg/fig1x24a.bmp
6ed56b8df5c400b087608b1a7f007fc3b713451d402b4aec3c4d9344880c00d6       1202  APLimg/fig1x24b.bmp
4c005fbfefbb0210fb669234975bdaf9ef3b6f28f65f74f65cc9576238ec7032       1202  APLimg/fig1x24c.bmp
78b4a55a4035ec18565c4b4f9441801d6639db268678908f678c9e656a01d240       1202  APLimg/fig1x24d.bmp
775951890ab0625c68a6e18c8bd27df33331560290cfa30c9c03b18a24d17774       1202  APLimg/fig1x24e.bmp
d35955fae1be2e3f9a931118cf1897164613fb5bbc66ab348e7cdba26fd5ceee       1202  APLimg/fig1x24f.bmp
03dfacdcd64413a8551cfdbfbf475209a485f20297c566be68d3bc1e05cc8cf8       1202  APLimg/fig1x24g.bmp
857944385d8baca7e980a6d6b403a000937e48fe223ec14b4592dbc38cc12c9c       1202  APLimg/fig1x24h.bmp
f8dafb7c7d324edc0a465bd71523f5cda0771cd065d41118f3068ef45d7847c7       1202  APLimg/fig1x24i.bmp
7ada9e7656b17712015023b3e61d262b4e5a8830d8d4664f5a8377812dd07143       3902  APLimg/fig1x25.bmp
9db6edcd80a48e02bc7cecfb7a04ea80b3392f4cde1798a1332c7e5f073ea7aa      14342  APLimg/fig3x1.bmp
9c26b98d5fd1aab1c4a9bb0b7174ad85f77be387eb0c8ec01ea3609d69420a89       8270  APLimg/fig3x10.bmp
ea85555b8e4803213c8cc1b6f10267467ea9f6a860eebc3a850ca479a3f440e8       2522  APLimg/fig3x2.bmp
421c494b334562926dfa830f59dd8144c0ef7daef140c5256406aae39d709ca9       2402  APLimg/fig3x8.bmp
b158a668871c78da5efa495a6208bf92431ea477aece602c0f30ba23bf4ea081        642  APLimg/filebranch.bmp
c80301648e6f4c0b135bf1dfa4c35dcd33929c37c0933c0ad7d21ffbc1cf6c97        278  APLimg/gmp.bmp
4d35b1c22ec4447599edf72692d307f1573cdb06329f87526798feb75e5792fa        110  APLimg/gtarr.bmp
f099a051826013f49cee8c72a8c9ed48cb5c21b127995e4e665810c3c8dd05d9         74  APLimg/hline1x23x8.bmp
d24679d5929e6f16522c536fd28de69b0546699d4194be9d9724f2b6c955f251        110  APLimg/jotand.bmp
4e2e19d78346a76415ba91de0f4aa0b753aae84a9c0dbe4326f57183b0952b22        114  APLimg/jotbase.bmp
d1b5982ed674bb8946d3165352a7ebd6683e82ac77513c816e51854166a976f6        110  APLimg/jotcircle.bmp
3325dc514821d5e8868f12568d00c4f5b9c3d5fd572f8f299b5fd1a5ebbe28d0        118  APLimg/jotindex.bmp
359f252a7976a96557a0fe4654d273bc836141f1e60a13c5ce768482b682acb3        110  APLimg/jotiota.bmp
0cef48cd60e7b0f921223a58255dc8192606dd3b50f1db4dc35a844d3d6c5971        114  APLimg/jotmax.bmp
3667b4a48cd7c9ef971196f0b762419eeda8ae979a3c28a0d87386e3230ce277        114  APLimg/jottimes.bmp
55f8cd3d0bab36e9537a007f501234759c8da1381f03af8702b4c703f5c91428        118  APLimg/ktilde.bmp
a28ee09ff696312697a43ccac5a7525a6d9487421931ea86c097c2863f1e7544        198  APLimg/link.bmp
9fa2e752e8b4f100849773a8880579ac88d5f18dee99acf93423c49ea83c2b46        110  APLimg/ltarr.bmp
4759b7084fe8e884985a44501a68ecad593bcd7ce3715ab779cf3cea36de79a8        106  APLimg/luarr.bmp
4d1c0c60e60ed82fa9e45e311fa131bae727a5827257dd905042cfbc2f42effd       1202  APLimg/matrixl1x15.bmp
fe4b5b89a6fd76ed90cd0266eaa4e88847d43466533e9057b8f1c8c8ea942ccf        514  APLimg/matrixl1x5.bmp
ea6a7653957713d980ea373e7453b439a4505b1b249e7a52427ebabb8f2b8308        514  APLimg/matrixl1x9c.bmp
5b08454ae6d93c7bf02bc6de13dbe7d9ff6b6442365b9da887d149a1dfcc7325        266  APLimg/matrixl2.bmp
7afe2ccc49260946a8d45a7450cef5dfafe2df9a76ac72136c906731ecae981c        386  APLimg/matrixl3.bmp
d943899f435801c01745879d499335d5005a8e57b6f00df4aa0eb1bd636f5711        530  APLimg/matrixl4.bmp
0f6f726bdfe2f588b34e55fa1e9ab5f80f45958cc7cad4d06be87c1a72169bc4        642  APLimg/matrixl5.bmp
098d0010d8a8f524c0161873f66f6a4fa5c0ca683b20bd13d119e77e29dba9bb        746  APLimg/matrixl6.bmp
37454dd3da1f3717de8446d62ab9f5098a3cdf1ad7cd70ee9ce29d19fc514b68        850  APLimg/matrixl7.bmp
f547d2473c4cd679fa5110e017c5aa1a3fe83c343ef7651c6ad8bda05a7e0a0c       1202  APLimg/matrixr1x15.bmp
07b7030752a3ef39fdc670cee679fb89e196e6917902c8237cf1713d057a8add        514  APLimg/matrixr1x5.bmp
11748d8e3a6895f3d6b2c0c7cc8bafce4b12128e3d5c6a969acb473cad31fdb2        514  APLimg/matrixr1x9c.bmp
a1b8350ce90e0fbc704a0fd4cf3045051f574269686a793e0f549dd0eb1d32c1        266  APLimg/matrixr2.bmp
85a3777736dd74286cd0bdad54732a24ce6df07c2f3d3ed3e342cff0b71dcd6a        386  APLimg/matrixr3.bmp
ef419df03d7b5d21065043a7877a9cc8250a6f8c3cf0c278fe5a06c7cbc3e766        530  APLimg/matrixr4.bmp
2fc1236c9d7d5d7cb24bf8787d514c7cb39fb1f67e829d6af46f2954f6762f1c        642  APLimg/matrixr5.bmp
3034cac5d5ff13d7b72d925d5027df7ad7973309cea504b131bb7d390919ad4a        746  APLimg/matrixr6.bmp
4308981375d96ec42bce46e216b58caa230e5390728c8be9f27cf16ad59ab711        850  APLimg/matrixr7.bmp
27ec3fccaab132b3f39a362efb12c8dea7b9360a552e6413c3c1efd14eb5f196        750  APLimg/matrixr8.bmp
423c7025344da21cefca5bc957b544b13af76b47e973e402814a5c7923beb51c        110  APLimg/minusslash.bmp
777842211325a34b854677ae1c31b117ef5912c970989f5c10edc4042134505d        110  APLimg/neand.bmp
6c97ac50e7a0df6dde6d5b8881a91c6d71e8c2ab32a28ac8f4c4d1fd52da0bd2        110  APLimg/noteps.bmp
8bef4bb992b1aed8401431e349e602ff2e390771f383addfa33159e4fd202290        114  APLimg/notgt.bmp
165f88cb9e2c67a07fbf825ef5040018448f56729ac04d07838d12a0826d8052        122  APLimg/notrel.bmp
d04070531c93e617a48d36dd2a4ff39af453184023545d2cd0990363bede3507        114  APLimg/notsube.bmp
77eea0dd488706d13df7cac78b89eb4a95b5a1e2fc8f949046c66c6dcb0cb2ec        114  APLimg/notsup.bmp
78180d8d61f75c5fd68d9e476d782f7048254186041a1b1901dba6d3c7e2bc12        114  APLimg/notsupe.bmp
07b67b8ba1071acdb60d80b5f2260ceb7c159a5a0890d79767bc2d8d439fd49f         94  APLimg/omegaboscore.bmp
0e3ad288a839cdb00502ea25cdba118c06067500208912478176f36d8f360b01        110  APLimg/orand.bmp
ac26eb319875b8eb1817fa83d6c464c3570affbd743bef1ba8ae94ce66e90267        114  APLimg/orne.bmp
9271820ff8c1b670d6331ec5aa1d8c4f0b9209c1d2aeb3e10d2a42c338c17568        114  APLimg/plusslash.bmp
f53ff62870b8d42e784e231fc0105f46df6f9ccfb580d4bdc3306e0c8f2a6464        114  APLimg/plustimes.bmp
75baf083f9547de0d042aededac64688ec34427a09bc2c6a6861e14d6b1fdf59       1442  APLimg/prog1x1.bmp
fe686516bd24956474bc0b8557f6d2f52c9ddf7f871484bda09d320c2f957545       8462  APLimg/prog1x10a.bmp
20bcfa8efd5ad99650cdde76fe2053f253113589321099e8ecf9ca2442e842bf       1966  APLimg/prog1x10b.bmp
adc83d1e6a82d1d695397336dc84e41aad2d638b588502aa5b0c161cfbdc014f       3102  APLimg/prog1x12a.bmp
833a5b620a85fe9dc2001c99b8ebbf1c3b80da76e3c46c02c18ad3a9ccf926c6       3710  APLimg/prog1x12b.bmp
97fc55d1a56e721ee24d3b2990d792571faca1ef01d9ffae0b76fdde25d40cee       5102  APLimg/prog1x12c.bmp
635a5364080deccd54e5773298ef7ca76bb218f8a92fdf5da0eea89ef38351e1       2318  APLimg/prog1x12d.bmp
9e30d8e79e2bff74e17d827148b6fbab356dd649defbc98fa6d0a388114b9ba0       1622  APLimg/prog1x12e.bmp
a1e91a4ca4b61c5332e98864540593f7f21ed7eb1e15101b00863dd1ddb2beee       1934  APLimg/prog1x13a.bmp
bed78eca19353a96e3683694aa8a367addbd71dddafb50d52cc34133ed719e22       1166  APLimg/prog1x13b.bmp
7e7b08002fb78936db1912d47a738946f2a1ec03d5fc39bd80c33e975bbcc587        962  APLimg/prog1x13c.bmp
0b42bad5cb0f957eaf09b69270384962bd2e0cb43ac7835fad0decc047710ae9      11934  APLimg/prog1x14.bmp
5b717ec519130b0efe5443b8d1a1b285f0b2f8206d96255d17d7a18d99bed746       9950  APLimg/prog1x15.bmp
b20bb44da25fdd4c6bbea6c2451b785681fcc522200e59a64c045ca1a7b7d7d6       8714  APLimg/prog1x18.bmp
d688c2323152d997314690ba10e14b2038a0c9e0943776d6594eda08369e605c       1842  APLimg/prog1x2.bmp
fb7f87a6ca5ad74683ae0f2afe8d02b7bdd6d66f3cb6fe116b2b078fd256a8ea      15486  APLimg/prog1x20.bmp
70ad4fd76379b50dea2944c540b78e3813ee0d9e68b868a254eb6f77185b952f      21982  APLimg/prog1x21.bmp
22b8effac5c8a9be1d7ad4f030aec56fbaf93f467b97419f81c17ca14c908071      10310  APLimg/prog1x23.bmp
d289c32bf938e0d041d26425bf5ce78cb8dd58bc9595bbfb739ac1b8523dcdc6      13886  APLimg/prog1x3.bmp
5d740ef25e15f14df0ea948260afd8b53f0a1637bcc26f4b627da04b1a64d9ec       5078  APLimg/prog1x4.bmp
ca9c3609c2c550d1024f1e8f2bf41a893f04a24ec78e7584d7944be104cd2257      11042  APLimg/prog1x5.bmp
fcbe25224394a00994904eb3f73a5c41e257a0356e2fd441b73283b179a38d61       7486  APLimg/prog1x6.bmp
1df773c13e53493234491bd3d4aa08a8b72220266092e2ca226c20625e9f5da4       8414  APLimg/prog1x7.bmp
39da7232f729587f63f90a2dcb80f6a51b18c2d60bf1bbc0a49f3c76f9daea13       4254  APLimg/prog1x9.bmp
0410e51905e4faa0993253612cc171510e452cf50948d2ae6b09c28b80eeb27d       6506  APLimg/prog3x11.bmp
a75c037584e3a70f14a95c709e7acdfe10a7266274452e01ab30f468bfbbb5f2      16502  APLimg/prog3x12.bmp
6fcabc470c9658e27e9f65a67f5fc2420602ef42a8d69335b7ab711661078f66       8322  APLimg/prog3x14.bmp
428752303f25748d45e5e0ac64662449fbbb42ac1beb86c9d8cc4432efd4890d       7510  APLimg/prog3x3.bmp
9245f88c318358468a84321982c5bd691517d144f614f047b38dd6a18414397a       6578  APLimg/prog3x4.bmp
41f28764f69ec15a1d9f8575dfaf1b759e32636f38dad3ec4948bc6e5c26e849      21566  APLimg/prog3x5.bmp
61668ffcf5a006a3c649ee693e519530e8a2bc813d6fba737429a0ee6495de88       8574  APLimg/prog3x6.bmp
3376a7e229678ae36d3baa22850800b5343fe3e0ecda487cf7abdf9815e12e53       4358  APLimg/prog3x7.bmp
45665ac292f1902325bb2b6a36e0c1e029cae830e024e37e4dc22e490ef21297       7838  APLimg/prog3x9.bmp
dad457ad04368cc94d9c8bec5b1f3735c3f8270039d7280d662d827c92a07a6c        106  APLimg/quadne.bmp
e9c02fa7b4c73015dc95efe8b67127d2db16521acc3f189e1ea7bb6f97c878e9        106  APLimg/quadnw.bmp
05818e2c5ff2251d2de9b75ac213ddc82853fd58325ed3db8a35a64af5bd5eb8        106  APLimg/quadse.bmp
e08beca8d18e38c028a12a941e091baf1431613b2cb701992ebc215c8b87c8ca        106  APLimg/quadsw.bmp
4e8b856c7999e2cb9edc3fa246042cac1d4e9eeb07d57c7235f31bfa69ea246d        302  APLimg/sigma1x11.bmp
5f8d7c53dc5d7dde14274aa06185e0b476afc2f0b7fd08f89705e24794db6271        250  APLimg/sigma1x23.bmp
0d04463146b6928508d5b718f4fe660ab78de83fe326ee5f04cabd4334aba49c        298  APLimg/sigmamm.bmp
e6294b4f5ced3a412d5194490e2b1deca90cf2a01a7a9c25b4c83e326d75e1ac        238  APLimg/sx7a.bmp
57faf12de3e1aede0f58e8d102a6e650c125f0d32155400fb772029f4e4884cb        246  APLimg/sx7b.bmp
4b8d547afd657597868d38d3a307bfef5d1c9aca6ed04b1be8cce3a36033e50f        254  APLimg/sx7c.bmp
43c9d1f5f6f1c1d53141b01f0ddb171a2dd1f4d7bee1386925314fb576d93d76        374  APLimg/sx8a.bmp
012497f46540384b3c4a6f7051854326ede608ee8a2b81062d3a30c12caf34ab        362  APLimg/sx8b.bmp
59ffd82121c582715c8d63d34caa8a94c14453e74b7e63976e934a0cfa0640ff        314  APLimg/sx8c.bmp
383423f8566fb7217721322092db97ce4c807d000f481cf1e1fbb5722c2ffdab        246  APLimg/tie1x3a.bmp
a3f735d91c119d8d36b12224f2adc02ff7c0f5b47e693cf680472ae4460b96d4        154  APLimg/tie1x3b.bmp
a9ff37a1c7d3965ac0c5f23af69cb10d8b95dc8270cec9395539742b20e0fdf4        114  APLimg/timesslash.bmp
49e52b6147ca61203c2e7c5abdcab38987ac28cfba06c709bb3063bcee5bff3c      11608  APLimg/title.jpg
18b52a9d4b8b98c22b2e965bb8f79f191961b5ddd54b8cb37ac0314e568c6879        114  APLimg/uarr.bmp
71a26d34f41d828d8b7abb941424f999c616566b5aeefec9389c681b59686dd8        106  APLimg/uboscore.bmp
66793a008b5f20dd2a28a315c33481a36826c50ffd958fec55096648f539c43a        114  APLimg/ucapboscore.bmp
b13be937856c26a98e8897ad8b060e259f5d3562aca5107fd81c59a616eaa0d3        238  APLimg/ukk.bmp
5a015c34760171ee3ef7a42be864f43a6bc252b66204b75ffb912afe131bb931         98  APLimg/uoscore.bmp
a1d6f1ad424ef8043d896de9e2506bcada4a3bd80025f2d16cc7dafc269831a3        106  APLimg/vboscore.bmp
94ecb5c6633ba71addaf85f3703eeee07d9215699cd1dae7de09706c4c4bacde        106  APLimg/xarr.bmp
9835fd81037b758a3831ed5d65fa855b9bd3d952dece57e6410017370c000080         98  APLimg/xoscore.bmp
69fcd63d14d034903be4339f5c6f2dd130999343eabbb5eb452aac05c255b7c3        114  APLimg/xrarr.bmp
050f95fe6af98ad87815c22df115ced704181321238d1dfeec1caf7a70f92669        126  APLimg/xuarr.bmp
5c7a54339fafa25c401b390347b060fa9734c92a346f779b19730edc21e309b2        134  APLimg/yrarr.bmp
5d7124486db1414db72e0012d37e4d948f69d697defe2af6aac4b976a62d1bdd        501  adoc.css
```
