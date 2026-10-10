# Higher-Order, Data-Parallel Structured Deduction

- **Authors:** Thomas Gilray, Arash Sahebolamri, Sidharth Kumar, Kristopher Micinski
- **Venue / year:** arXiv `2211.11573` (v1, 2022-11-21); no journal reference on the arXiv
  record (the source is set in `acmart` `acmsmall`, file name `toplas.tex`)
- **Canonical link:** https://arxiv.org/abs/2211.11573
- **License:** arXiv non-exclusive licence (`nonexclusive-distrib/1.0`, the arXiv record)
- **Thread(s):** sharded-compilation (Sharded and incremental compilation)
- **Storage form:** raw LaTeX source (arXiv e-print `2211.11573`), as shipped except one
  generated file
- **Status:** stored

## Provenance

Fetched 2026-10-10 from `https://arxiv.org/e-print/2211.11573` (redirected to
`https://arxiv.org/src/2211.11573`; HTTP 200 `application/gzip`, gzip-compressed tar,
578,050 bytes, SHA-256 `c9ceec3b8dbc45c0f79b9e4439a2012fe33fbbb5a975cb2f6e585058cd1bcc1b`).
Title, authors and licence from the arXiv API and abstract page. Unpacked with `tar xzf`;
the generated `toplas.out` (hyperref outline) was removed; no other generated files were
present. `toplas.bbl` is kept because `local.bib` is present. `toplas.tex` is the main file;
`aam-table-old.tex` and the unused `IEEEtran.cls`/`.bst` are kept as shipped, and the
`Makefile` was not run.

## Related

`jordan-2016-souffle`, `jordan-2019-concurrent-btree`, `sun-2025-gpu-datalog` (the same
group's GPU Datalog), `mcsherry-2013-differential-dataflow`;
`sources/notes/sharded-compilation/deterministic-fixpoints.md` §4.

## File manifest

Every stored file except this one: 34 files, 1,120,116 bytes in all. Computed 2026-10-10;
check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
b445bc94cfde36bb836a4c6f5ce7149f1488d76dfe8acd39a8771f084ba8f348      59215  IEEEtran.bst
da751920a317ed318b7b5cd7fa585a6cc7d28502d457856382e9be24b10a3bd7     281957  IEEEtran.cls
d44f18739d8f2e8dd81aa2933dbc71b2bc3e9523243e2fd191e23d539ae791ef        412  Makefile
29605e7ce50b36c23ffdf58308589de50cae5bf3998a37cbe3ceefed2ddbd6ac       3752  aam-table-old.tex
3b42e5a67cfa527fcd913a580abc995e712f93479ece5c1c3922059a4d3e2db9       3936  aam-table.tex
3342f591d01cd57563acd5769c51f9db3ea5c7dea628b9766562f487f25f4839      93366  fig/dvh.pdf
cd97ed71383c416423f3658be6ea47a3fc638c57e8ad6632af7a420cd76f0a14     224321  fig/dvh.png
0f3fccbf519fe67c8895fd3713e18e999b169e71830812147168337c3c2c514a     121347  fig/ra.pdf
299eca0c07da1ec22b9d3f9244724fb53fa1644275fc6686775feafd01a747fb       1588  grammar.tex
59f06a0172a88658bc82a1957cd1c9cc11418f41bb5cb3e744089a68a62a85ca     180404  local.bib
f1931cb541d1ed849289ee135237176be467fe627a0d4ebc9a9accaf68b4e095       1343  sec-apps-aam-ceskc.tex
43d198df2e72db731e984e6d50cf285fed416ebca26e11d7594dfd031e2db9e2       2579  sec-apps-aam-kcfa.tex
34dcb1f6adf9e184be49707632fbdfd20715d2b18e3127e3f526d296b6bedca4       8318  sec-apps-aam.tex
7d2f0fd83f8dc54d41c82fe9b90fd0631bb10d080d137abab70a376fe3babc7a       1391  sec-apps-am-ce.tex
59968162bdbb0215e517e90720b1ba8f2e22ebb58ab7847d156049a8638b844f       2567  sec-apps-am-cek.tex
356b88334fd63047b936c378bc5383fa827e870e1a227e916ccc1db9d370c2f3       4162  sec-apps-am.tex
bab5c5857c8b8abd18604b5d8aafd3acaaed78c4e343a790bac80f54d438cce3         57  sec-apps-eqsat.tex
c3e6a728b04ec4c69afdaa1503718f4d1dee16fc61669b2e26e9db84baadd83e      20418  sec-apps-ts.tex
058f4e27ebb3db3e4ffad74839c272f827a4a5e8a8c48ae264a14d921efef549       7399  sec-apps.tex
ecb04f9709c89dff7c6f63d2746c6604f36ffbd271c6d6344dfbcd10a5917818       1171  sec-conclusion.tex
7216a859ac278823280dda822067a22196c42ef5fb9c6a93769c0d74fa58f931       7622  sec-eval-aam.tex
aa88053b63f0084426a7f269d79af1cb837821e7ae3963ea435bc1206d10a81b       4802  sec-eval-tc.tex
eabc33c69b5a39287f833ee5149d09d0d316f5f903e048cce4f5a7e48e1a8948       3620  sec-eval-theta.tex
5eb51f403a88b8ecbd92fa81affffdb9ffaf079194879106840aade792736941       1564  sec-eval.tex
80b461184855f1680bf57bd1a002a690ff87897ac9f75f636deaccd94491c29f         50  sec-future.tex
09683b98736524ebfb856463e3d89539f1b98bb35554445795e61334eaea7f1a      14229  sec-impl.tex
74a6f0ce7ae9174182b0c458fa1567a4802368d978e2aefc52eeda7ffa41fb12       5840  sec-intro.tex
23ff72a2533d0215b040440b7c839f4147b435a71a60c70a05d681ed56305128         48  sec-outro.tex
6f432c3fec7dc330d894d2119ceda6ba7817549ffad181b36b5288cb44f7cb3c       5385  sec-over.tex
376c96ddddd781bdd67c6eaf5f8f62d39f1eee44dcfe25f3a59a5d672e698fa2       7390  sec-related.tex
e4514fac54aac493eee7d73b58e0b8368f99f215a941233ca7c102017e25f4b2       6113  sec-semantics-extended.tex
c74bc0f8a74bef12b0e5caa403fd60b38b7d6cf0cc15732773b0d76559fafb13      10760  sec-semantics.tex
39c53c10aec860ae35ce90fea086981d4a6bf81e48057dea6c82e619ec4df6ae      22817  toplas.bbl
0a5d30eb23f5aa5b70dde65af656cc66b14269e6ac1482ab0e58e812cd14021c      10173  toplas.tex
```
