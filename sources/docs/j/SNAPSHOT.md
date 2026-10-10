# Snapshot: the J Dictionary (rank, verbs, adverbs and conjunctions)

- **Upstream:** Jsoftware's web edition of *J Dictionary* (Roger K. W. Hui and Kenneth E. Iverson), `https://www.jsoftware.com/help/dictionary/`.
- **Revision:** none (live host). The title page states "Copyright © 1991-2011 Jsoftware Inc. All Rights Reserved. Last updated: 2001-5-3"; the pages are as served on 2026-10-09.
- **Fetched:** 2026-10-09, with `curl -s --fail -O https://www.jsoftware.com/help/dictionary/<page>.htm`, and `https://www.jsoftware.com/help/jdoc.css`.
- **Paths:** relative to `https://www.jsoftware.com/` (so `help/dictionary/d600n.htm`).
- **Files:** 52: 51 dictionary pages and `help/jdoc.css`.
- **Licence:** © Jsoftware Inc., all rights reserved (verify before redistributing).
- **Threads:** Array languages and typed array programming (cluster apl-lineage).

**What is here and why.** The parts of the dictionary that define J's array model and the
operators that compose over it:
- the contents, vocabulary and title pages: `contents.htm`, `vocabul.htm`, `title.htm`;
- the grammar: `dict.htm`, `dict1.htm`, `dict2.htm`, `dicta.htm` (nouns: atoms, items, k-cells,
  frames), `dictb.htm` (verbs: ranks, result assembly with fill, prefix agreement, the zero
  frame), `dictc.htm` (adverbs and conjunctions), `dicte.htm` (parsing and execution),
  `dictf.htm` (trains: hook and fork), `dict3.htm`, `partsofspeech.htm`, `special.htm`
  (special code: the phrases the interpreter recognises), `ref.htm`, `ack.htm`;
- the introduction chapters on the same topics: `intro.htm`, `intro03.htm` (verbs and adverbs),
  `intro05.htm` (forks), `intro08.htm` (atop), `intro19.htm` (tacit equivalents),
  `intro20.htm` (rank), `intro26.htm` (obverse and under), `intro27.htm` (identity functions
  and neutrals);
- the definitions of the rank conjunction and its relatives: `d600n.htm` (`m"n`), `d600v.htm`
  (`u"n`), `d600xv.htm` (`u"v`, assign rank), `d620.htm` (`@` atop), `d622.htm` (`@:` at),
  `d630v.htm` (`&` compose), `d631.htm` (`&.` under/dual), `d631c.htm` (`&.:`), `d202n.htm`
  (`^:` power and obverses), `d220v.htm` (`~` reflex/passive), `dlcapdot.htm`, `dlcapco.htm`
  (`L.`, `L:` level), `dscapco.htm` (`S:` spread);
- the structural verbs the rank model is stated in terms of: `d010.htm` (`<` box), `d020.htm`
  (`>` open), `d210.htm` (`$` shape/reshape), `d320.htm` (`,` ravel/append), `d322.htm`
  (`,:` itemize/laminate), `d330.htm` (`;` raze/link), `d400.htm` (`#` tally/copy),
  `d420.htm` (`/` insert and table), `d421.htm` (`/.` oblique and key), `d430.htm` (`\`
  prefix/infix), `d431.htm` (`\.` suffix/outfix), `d520.htm` (`{` from), `d521.htm` (`{.`
  take), `d530n.htm` (`}` amend).

**Not taken, and how to get more.** The rest of the vocabulary (`d000.htm` … `dxco.htm`) and the
sample topics (`samp*.htm`): fetch with the URL pattern above, names from `vocabul.htm`. NuVoc,
the newer wiki reference (`https://code.jsoftware.com/wiki/NuVoc`), answers scripted fetches with
a Cloudflare challenge (HTTP 403, "Just a moment...") and was not fetched; the challenge was
not solved or evaded. The J engine source (`github.com/jsoftware/jsource`) was not snapshotted.
Two pages reference `../caution.js`; scripts are not vendored.

## File manifest

Every stored file except this one: 52 files, 236,314 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
a3f37bc282ea743b12164d93dbb34d8ca57cab78cbe555c75afe81d622d23472       1484  help/dictionary/ack.htm
6cceb150457f3e99e628d5e1a37706bd959587dbedd865110a9d8335794b73d9       8330  help/dictionary/contents.htm
468844942737605a761260e3a980551aa6e86f7c68af7932272e58d15bdc835e       3556  help/dictionary/d010.htm
a7a43cde8a967feb09850cc0ec5d182f4eef59e09f7290c0f6024c6e95c695aa       3389  help/dictionary/d020.htm
e8b09ccc04b82ecaea86b9488e92277b7bb0d142e5744a3b8fb858b4cf52d478      11221  help/dictionary/d202n.htm
4bbbe46cc399ec4107e9ee97082a7b0f40b0d2de68c39a09176707369e879d1f       3642  help/dictionary/d210.htm
edc7ce34fb107bb772662de36c956c3b11a3c5a4fc36c804584050ff8263e742       3105  help/dictionary/d220v.htm
b42c6477c9dc679c7011a263a0579b1120017be47be195c889257a57bec54d72       3335  help/dictionary/d320.htm
14028e74c7f1814e46e196202eb337da0362bac792b8ea473a49d7185f2c229a       3617  help/dictionary/d322.htm
6ac055c6678b2e73a546809a6be563a2b2047387ce372a00cfc71c7daca0db9f       2869  help/dictionary/d330.htm
a3f95f2966829008e8401476b0dcf536aad2e2d0ee2acc0d3fa84ed6b175e80d       3216  help/dictionary/d400.htm
32131d1067ca6c2e1938b1df19622a7e70984d5203b71f0a13f4631e7084aea0       4549  help/dictionary/d420.htm
bbf4642b0b3ea1bdbec08e98df025a0ff3a4c197b32cd7c13181a0f845b47ed2       3961  help/dictionary/d421.htm
fbe3784de727c202f227d64d30d8a9f2a594c39b7285a5f214bb6f0a7e187b3d       3423  help/dictionary/d430.htm
7606a8c791ce32a63fb75cb9c020293e924e075a1bfadac135e50342081aec6c       3236  help/dictionary/d431.htm
79bc23a7d5a6915ec5b4e2669e44b3ca4d3dd974a56afb6b8ad30cb41bee0fbe       3869  help/dictionary/d520.htm
7ddae4ba722a76e5dc4c8c9b1640d5258639b9a9b79d9861b5171683ab988516       4075  help/dictionary/d521.htm
1c4aeec91a0af5f14db42ae0e5f9cfe9d950a140fb29838282236eddcffb8843       4214  help/dictionary/d530n.htm
4717973d22a3080f35df96946b08fcad2c8a1415e996c760c172a5f7f225d2e6       2789  help/dictionary/d600n.htm
2bb02818ef63557a2fe2b3ca9ecf4d0220ad93fc5a2d55220a9a3f88c480b876       4028  help/dictionary/d600v.htm
403467eaf5966ae72f59f61e38dc3c821f0cefff84ce77f0d731a6915c8d4a3f       2194  help/dictionary/d600xv.htm
9c36a2b63c015136cfef02d755948c1769fb8a7e8b178344a094832e4fe6e1ae       2987  help/dictionary/d620.htm
f16ec3fb873cc8470ab21fb595b1936ad491225ee4142ed94f32885d8831850a       2127  help/dictionary/d622.htm
a1c2288a0e17e2c82d5c96169f7079f85683a9e78da41ef621bfb94928538662       2888  help/dictionary/d630v.htm
68c0cc8921413f306c6a94a352fdeed404faab0fc15d7298eda6d801c27e5ee7       3865  help/dictionary/d631.htm
b8949fc46f6eff1a0bb18b67cbe025b6c11390476a571d71b879bf856eac78d8       2451  help/dictionary/d631c.htm
01ec25c6ffbcf98fe769cec552e9a4bd7b7d0aeffb29363089a2c9eadc3fe881       2661  help/dictionary/dict.htm
3b831ba7810e0abc0289ac24d449bec5e38e6ffc72c2919bff9944c390a8494d       3326  help/dictionary/dict1.htm
5fb84e0d05b0623cb75f4359503a8de9f252f6b8bd3e75d73fc619db266aa2c8       3616  help/dictionary/dict2.htm
36c88fac6b41888802133569aa13758abbbc9abfd0f83101c15a792aea9ef373       3802  help/dictionary/dict3.htm
a3ed99c3b388cbc1ab8512967ec4c623948bf1f5f9c260b6fb06378da85a9471       5590  help/dictionary/dicta.htm
2258b9f9d34dd51a4a4b1e01ef9b660600e658cda600795bc0e8cf13f9e8fa4a       4951  help/dictionary/dictb.htm
c4c3b31a09c2a963f733f5eac024cab27df6f5bb2cbe18c5e4d6329728673f3f       2203  help/dictionary/dictc.htm
6528a20d7575349615fe3ded4090eb1a72e3799c96b4726c3e7dcc6fac9cb05d       8551  help/dictionary/dicte.htm
cadc56a69e40d8ee380c8141108deb4e2cb535a0e11e54cd00ed2e389dd0a3c8       3284  help/dictionary/dictf.htm
0daae2457b1da678ec7c9a99a09902ca47a4ae04e39db264e999c9c113dd512d       3576  help/dictionary/dlcapco.htm
678a4ff6aa606abddb6199631fa2271fb2844276fdc4b7f122ce0e43989a1c41       2285  help/dictionary/dlcapdot.htm
1ce62abc5936ba4ff4f1f576b74b6f29a5fd6a430f9db5808361435019c9c1ee       3702  help/dictionary/dscapco.htm
6763298765c2a4cc2fcbcb1f67685cbaf83e532d77254001c35390a045786e3a       4177  help/dictionary/intro.htm
51aed481cd1d9f2eb46ac512fa7e94d330731257d3dfd1d6d66bc9eaed18cfba       4364  help/dictionary/intro03.htm
ed08f9b7fb3abae66b8c987ccff73fc055cfbf41cbe9af46d680bf8bb9b832a9       4945  help/dictionary/intro05.htm
812cbb1c743b9b289121182fa91b9fa5684305aa31df9aa76156e34a5006808f       3609  help/dictionary/intro08.htm
c1da8a41a6733685facfb6dfa18b33b3597704cface92aa1fb96bfd9557c7556       2562  help/dictionary/intro19.htm
6f52a4289b9abbd7c926390725123826ae7af99ec907e469678e844b89f2015f       5128  help/dictionary/intro20.htm
85fa8ce2cba7494d7a4f37b25d6d812a06de7c6cc68242a70196ccac778a1fb6       4070  help/dictionary/intro26.htm
4078273af7267bb86bfefa559f7ce2f435258bf7b8a9059ab0d0c607aa62635e       8392  help/dictionary/intro27.htm
3a02eb1a12f8a27c0aab375727defcb24b6b3fa1e63cf26e0048f8e20ba0364c      11768  help/dictionary/partsofspeech.htm
e0176d13fd408d2a712e3c5851d56d8ae97d1fa8d3a8c27450cccde89a40956c       3542  help/dictionary/ref.htm
7c16a462b235cd075ef0b72049fe8fdb304b807e75311ade989343e66d683686      23278  help/dictionary/special.htm
fba8a2d1e9869f91c29852fc65aa628152cbd2c0ff296761330e40f03c1fa099       1536  help/dictionary/title.htm
e25c8c88270b3b30c97d23d47233c4cdd568ba9c097d51d0830b4cbac83a1cca      12253  help/dictionary/vocabul.htm
b2e7be84f4e05fedc7385f16eb233f043abec5d7c56407be21729de7242871ab        723  help/jdoc.css
```
