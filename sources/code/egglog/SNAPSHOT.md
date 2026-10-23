# Snapshot: egglog, Datalog and equality saturation in one engine

- **Upstream:** `egraphs-good/egglog` on GitHub.
- **Revision:** `main` at `90635860397ce710f8c0a4eeb04154a8ebc3ac05` ("Merge pull request #1008
  from saulshanabrook/codex/pr414-rule-name-roundtrip", 2026-09-04), the pin `sources/README.md`
  recorded on 2026-09-26. It is 62 commits ahead of and 0 behind the latest release tag `v3.0.0`
  (`8879605cafad303db25787406163a7e5bc845f5d`, 2026-08-19), and the workspace `Cargo.toml` says
  `version = "3.0.0"`; `main` was at `43cc88e5abed0567afa75180e27e0805b62e89ff` on 2026-10-23.
- **Fetched:** 2026-10-23, from
  `https://raw.githubusercontent.com/egraphs-good/egglog/90635860397ce710f8c0a4eeb04154a8ebc3ac05/<path>`;
  every file under `src/`, and the `Cargo.toml` and every file under `src/` of the workspace
  members `core-relations`, `egglog-bridge`, `union-find`, `numeric-id` and `egglog-ast`, at that
  commit, with the root `Cargo.toml`, `README.md` and `LICENSE`.
- **Paths:** relative to the repository root (so `core-relations/src/free_join/mod.rs`).
- **Files:** 116 (plus this file).
- **Licence:** MIT (`LICENSE`, "MIT License, Copyright (c) 2025 egraphs-good"; `license = "MIT"`
  in the workspace `Cargo.toml`, which the members inherit).
- **Topic:** Analyses, solvers and dense side tables (P0 audit 5.7, item 16); equality saturation
  (Rewriting), with `zhang-2023-egglog`.
- Nothing was built or run; the files were read only.

**What is here, and why.**

| Path | Why |
| --- | --- |
| `core-relations/src/` | the relational engine under egglog: tables (`table/`, with `rebuild.rs`), hash indexes (`hash_index/`), free join query planning and execution (`free_join/`), actions, and the union-find it rebuilds against (`uf/`) |
| `egglog-bridge/src/` | egglog's semantics on `core-relations`: "seminaive evaluation, default values, and merge functions" (its `lib.rs`), rules (`rule.rs`) |
| `union-find/src/` | the single-threaded and the concurrent union-find |
| `numeric-id/src/` | typed dense numeric ids and the vectors indexed by them |
| `egglog-ast/src/` | the generic surface syntax |
| `src/` | the egglog language: parsing and desugaring (`ast/`), type checking (`typechecking.rs`), the scheduler (`scheduler.rs`), extraction (`extract.rs`), sorts and primitives (`sort/`, including the nested proc-macro crate `sort/add_primitive/`), proofs (`proofs/`), serialization and the term DAG |
| `Cargo.toml`, `README.md`, `LICENSE` | workspace manifest, description, licence |

Not taken: `tests/` (the `.egg` programs), `benches/`, `concurrency/`, `egglog-reports/`,
`web-demo/`, `wasm-example/`, `www/`, `profile-viz/`, `infra/`, `scripts/`,
`global-var-formatter/`, `.claude/`, `Cargo.lock`, `CHANGELOG.md`, `CLAUDE.md`, `Makefile`,
`build.rs`, `release-instructions.md`.

**How to fetch more.**

```bash
rev=90635860397ce710f8c0a4eeb04154a8ebc3ac05
p=concurrency/src/lib.rs
mkdir -p "code/egglog/$(dirname $p)"
curl -sL --fail -o "code/egglog/$p" "https://raw.githubusercontent.com/egraphs-good/egglog/$rev/$p"
```

## File manifest

Every stored file except this one: 116 files, 2,071,633 bytes in all. Computed 2026-10-23 over
the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
dba97703c6d82a2f82591e1ef22de21e1ca3ab60ab08b4db3af9d4cd057b88e1       4457  Cargo.toml
9a13b3840c0601e436f2b34f7730ff39a2b2e5635f3ce0df334fbf4638b23173       1069  LICENSE
897bf8fdf0f94edcfcf115f7b348b7ef8ac4cc1100b4dbfac847d2f58d95cbcb       9958  README.md
48288544bef60b3c4eb6626bb369a0cd3818dc572e389e217469b88d7771239a       1355  core-relations/Cargo.toml
dc4070f4c591ad683e7d948973cd35930d3e7fbf3e128385835b3b3e26467b36      17164  core-relations/src/action/mask.rs
5edbb81d47bfb3676fc7ae81da6811570060e80b58dc80b304c58c2a0146aea8      38436  core-relations/src/action/mod.rs
7134671e33a8db672dc20e1e8ad443dfd26af29f7978668cc5a42435db42b095       3694  core-relations/src/action/tests.rs
7878de9ee971ff013b0f89631b25d32a05d5f7ae71f886a68b10a837649ad070       8615  core-relations/src/base_values/mod.rs
f9d32ba64015ff82a703bfe9d4e789cd326a5021d3dd55e29fd625e7427ab236       8853  core-relations/src/base_values/tests.rs
323cf06e6f05e61a447b70b153e3d0f6b37d5e8b4d6da75b0e2c34a74b6f8976       3211  core-relations/src/base_values/unboxed.rs
95b570227a8c42e2d20d8f08d9c2bdfa554cb4800ff9318177c5dd49835eaa44       6936  core-relations/src/common.rs
591585b695bda73e9940b44225a608c79474100b917a87c9d4cfc0ce9b7fd83c      31392  core-relations/src/containers/mod.rs
7d94b021b584f19ee8fe71bfc119f900fbe12dedd729fd58ff68c6dd8c8746f8       7192  core-relations/src/containers/tests.rs
23859ad5ed19109ba9d9cb10511874d5ab7790afcfcf20a919d9a25592273f04       2219  core-relations/src/dependency_graph.rs
5cdba4c3d66673df7f685b15765ed6b3c5e6e499552b608444bb525279919af5     121723  core-relations/src/free_join/execute.rs
10028ee34a6fbba0f673940986e0dfe0f907380110528d415b42e463602a4d98       3663  core-relations/src/free_join/frame_update.rs
2db7b112bcb1afc1e4367bb8e8c598f303d2d3200bb4292a7edb335ca646faaf      38736  core-relations/src/free_join/mod.rs
d30a57f1d03859b0c09383ab27c8e0fcdcdf98deb806ef8bc666fdab5e1c6bf7      62501  core-relations/src/free_join/plan.rs
1c16f9a913eba2a2f2dcc6560bea06d5f98f95e887e568cf8f898ac2d8a7cff4       5147  core-relations/src/hash_index/bench_support.rs
ba83db779ff4f76cf25dc05dd3124cb449b49f63e08f7ca223d4ed02d2057cbe      40248  core-relations/src/hash_index/mod.rs
ffc9d6a73b42eb7ebb790bea3b50063013a89f5728cce10f5d3c8c3b5c6435db       9031  core-relations/src/hash_index/tests.rs
87174d00f3d0883ebc701b79b5f4f524074b84c32023086ae0a18d49a5a10215       1611  core-relations/src/lib.rs
3132344672a17ede5515522046b68adb6f3dc1db4228faced5ab51081d9ed9c1      18376  core-relations/src/offsets/mod.rs
00165c49503d7b9870b93a139864f1fd2955e221de8e70bf2e03c0634b5ed1c0       4924  core-relations/src/offsets/tests.rs
1ccc72f4269fe6f48e4bcd695672322f9d3051bf8a043a977b71ce52b6f42a05       4519  core-relations/src/parallel.rs
35ade2ded643bc116cb702d3d053aafe1c5eea5a200e73f05a204463ed42f547       4156  core-relations/src/parallel_heuristics.rs
8f26635af8753f15312abaeaeca2a16dff5ee4066da82896f240c0a73c855ed4      12417  core-relations/src/pool/mod.rs
7f95047d6c28ab59d412243957216d698caddb66a22b292e2728727beb20aad9       2631  core-relations/src/pool/tests.rs
6c2e567de681521d6305845851b4376542e694411a4568cfab689d5ba77c40be      35063  core-relations/src/query.rs
1e6bb7b37a1f56ccc7306df9787145ccfe07ff86f8935fb254c25fa65d69f7ff      22004  core-relations/src/row_buffer/mod.rs
d1975e47d5e09260792b8cc169cc2ce56a5198eeb34eda1886e5da734fe6b253       2402  core-relations/src/row_buffer/tests.rs
758c00facf806e93d97658a6ceebb552a96044fb968fa0ef6efafaeb38aa5baf      59088  core-relations/src/table/mod.rs
ff040857475d460a59d0d1ea9935c2556a685e1e68e709a3bb9720feee93b603       9605  core-relations/src/table/rebuild.rs
bbcd9a9b244c78a726fdbdd107d96ba7e1d23b4f90ed01aca9fee7a13ff25b54       1360  core-relations/src/table/sharded_hash_table.rs
203759abe5f8522b4311db5ea5bc811b30d36cbc91ec01c588bc8c658511ea52       4818  core-relations/src/table/tests.rs
7ea3e3719e0b6fc9500d91cb723c32cfc906de74c1aea10bac679d0b5ed002f9       2038  core-relations/src/table_shortcuts.rs
62c5ce2bb8adb5a3ad8a75aa004585e437facf1adf2cce13722919658b9c205c      31114  core-relations/src/table_spec.rs
2b1b433cf7fb6ad337ab9c26cd9d53a69ba232916e42501a60159e0deffaa05a      43352  core-relations/src/tests.rs
823a8e2bfe00f9009017240f456f759595f0b4c3d93b32b04572512ace841955      17881  core-relations/src/uf/mod.rs
3c45ef2534d401863b893f806c747926bfac8a75b4144ee0f44d6e57ca1e3081       1381  core-relations/src/uf/tests.rs
27be0fce33a389b8cb8241d792de29be3229b2da560d3d79acf27c4675ec3cf4        431  egglog-ast/Cargo.toml
a8d8190c2c4629f2b7f448b9a494943aafd16cf14f42bd0d133e87b3d3e325f4       5039  egglog-ast/src/generic_ast.rs
ed9e7c543e778ddda759bf989ecb839abbffd3fb43823e77eec154fd8151690c      29212  egglog-ast/src/generic_ast_helpers.rs
b0b17a1c00f9cafa10d9d245a805798cefd927274f9880478dd7a4f0ac5baa18         78  egglog-ast/src/lib.rs
bcfdbf367f85d34b2577b34147e7652645b5e8f541439e71572451ecc33796ea       3343  egglog-ast/src/span.rs
796c7db7a7f71d2ee3c9642c2e549da7d858c31c9d5ff7ba80b338835b8c9a41        528  egglog-ast/src/util.rs
384315609015664032340028ae768177ebd3d3944fb66d2253dd49d03ebaa4a2       1005  egglog-bridge/Cargo.toml
c270ebd0cc99d6d293cdf4d72d819c60eb9f356375dd26680db57a2fce4f3bcb      74864  egglog-bridge/src/lib.rs
6feac30f14c9da3113c6e2a2149ff427f7b3c29e5b11a08b071e43945bb69b9a       8614  egglog-bridge/src/macros.rs
b5b4e622e7ecf2acfdfc3a300c83e17a5e4839aea24ca1ab3d88f00504c8e916      31379  egglog-bridge/src/rule.rs
b896b04cbc1076748a0e38f345b695fa122fd57d9aeac672e699173a59701101      55474  egglog-bridge/src/tests.rs
0217279c4aaf669ff86af1fa4bca227b5aeb9b3f304a8ecaa0c7ef0a1d0f8a5d        286  numeric-id/Cargo.toml
6bf7eb1f9ba08b6a980e1fe8df9b1cfc4da0569a0e9ba969c871b448149a93cd      14462  numeric-id/src/lib.rs
0dd06a32f7f389a7edb0fd92233d6650badc178f1b9de7cd2550ce5d9dcb0c6a       1845  numeric-id/src/tests.rs
c6159243640215f1ffdad4705f9d4a4f297bfdba20981d7f0613a7dcc845aa94       9389  src/api/mod.rs
9a739273ade3c8be154e9653304040b7704e0bd1c3c544a3cabbae128dc8cf52       5260  src/ast/check_shadowing.rs
4e8b075ca28e93fa2e91f516e3923f24877e1681f1fafb6c0503e69c13c12fb2      15871  src/ast/desugar.rs
101ea85e4cf36829d268581df2e68d87e0bf83dbc7016d3ecab3ce97d90db1da       3076  src/ast/expr.rs
935f2a25a8fb8a9510a30ff1ccb737d2f1a17adc2bcabe77b0872657e7304e68      81894  src/ast/mod.rs
44f5748ca05585f61e13466fcdcf3ea5fcd90ee6f865a7a5e13c27fb5d4efb67      54221  src/ast/parse.rs
9446dd64359d06ac58a881292c54a09dff792a5c13094dbd488730830a5eeec8       5196  src/ast/proof_global_remover.rs
f51ce537691d2986a5f1a668b71c0676af7ddb79c085881f7504678d64a20228       7567  src/ast/remove_globals.rs
72b7fa4cc6fce0c80785027d7e0274c80a4f8150106bac2a94bc0d81e73adf16      15709  src/cli.rs
bb8189755293baf98fc45305059f4732ebf45c04050e9dd9579559b5e09fd9b8       1837  src/command_macro.rs
697114c982a2443ea830c44e015dd02cce7935d82bf65c5135e37b33d9c4162a      42029  src/constraint.rs
c08a340678202785303a1850f75717f05af156940a331319e1deaa92dde3b230      46184  src/core.rs
c824ac717c9cb939e3eeb33acd64655e960180a0465cc739f77b16d2f5f09679      37796  src/exec_state.rs
601ac0be86d59b9c1281104a97120eb04af96e9a209806b24d7a5ed7522438aa      40714  src/extract.rs
e85e9ae28b3596f83e4fa803d785b69de652c90699d4d922cad1744a0d898fb1       2289  src/lib.md
7c2ecd9baae45ebe12da7bc573df7a695ca5296885e8dc1ef06f4938dd7d679e     141386  src/lib.rs
970bd0471e50cd0874b2f5317fd6a341d1e108c2102ddbf1d513458e13df2b28        172  src/main.rs
ebbaacc2d586f2689fc3cfae02362deb2bf3b5b228e5e7149ce066c420e7a8e5      35586  src/prelude.rs
019ed54910525b944f5ffeb1e777af518e54a5f117f9f3422bd87d856e2f8a99        333  src/proofs/mod.rs
0963ccec2572eba54ace5e90076f7d984f017949cb91a41cbe32d791172957c9      52662  src/proofs/proof_checker.rs
f5e8ee599c5091c23b9e605a3460a3de5beec1f4a345d0e46ab6559313b9d9de      14499  src/proofs/proof_container_rebuild.rs
a5203ea6e7dac858e9638263bc79a9d49edbc422bcd7c8b31550614b2c9381b4      15678  src/proofs/proof_encoding.md
72e3e810ec00b13842c21062f676a24749dce9472ad898516b162871b99e5942      80447  src/proofs/proof_encoding.rs
8b2e46c765bfb2ff2e55e11d2f53a60bb6eef10ea90ad7dd7e301e4bcc1075ad      28437  src/proofs/proof_encoding_helpers.rs
90dd66326b216bb0169c77a12468ee07e50fbcf646c9cec4f298b01fa9b8ad18       5481  src/proofs/proof_extraction.rs
842566aec831a75a19e2345edc20b7e54a095695337c252c85994ff1bb1b5941       9147  src/proofs/proof_extractor.rs
e7a852565a46b27a47c70018fa0c36a900c59dcbc0786352ac68ea55b483402c      36530  src/proofs/proof_format.rs
611f6cb456e19c0b146f46c613b6ac5c62ded341aba25cc1d745ab337eda4db8       8326  src/proofs/proof_normal_form.rs
7751fc826e0aca4e583e8266f893bc0ab296e17461df7b9c22ef5c586408ec43      15743  src/proofs/proof_simplification.rs
ac1ca7098e53776bd481891be6cdf07ae47e4ca7d158b03df6241d3a29a92e5d      11748  src/proofs/proof_tests.rs
48cca4c0b004d8fda4dbdfa0690e8dd500b616645d558f87e7ed4b1de54fa8bd       3505  src/proofs/snapshots/egglog__proofs__proof_tests__tests__doc_example_add_function1.snap
ed28732467e6ca3d60791ccf6ea6470e137f192a39702700981a2fa669a9c5c4       2165  src/proofs/snapshots/egglog__proofs__proof_tests__tests__doc_example_add_function2.snap
1e99ae9d6aaf19a5bd75a85513f11a9b7304d7c92743674f0f7371759f2a7b7d      41004  src/scheduler.rs
c00e59cfd4ade77310239e1382b8790dd3ae7b2af3626840a5948d6d06efa1d4      16369  src/serialize.rs
b586e30689b6b47a537812eb133845917dfb14bc4dd7f707912d2668c7ffe0de       1102  src/sort/add_primitive/Cargo.lock
cbf573968a52ffafced630473667b185d857934dbb8e2b7532bec3522de2ea32        617  src/sort/add_primitive/Cargo.toml
aad93e66e590fc2da312c9801d1e67f776397258ccd15bd4bc552b8c583ddbcd      19412  src/sort/add_primitive/src/lib.rs
3693ee942e75a401f08445ee127b649d34ac08dc5a866814e7ca09507ea749bc       2659  src/sort/bigint.rs
3eebdeebf89d3a951dbad0f526f33e463ed9548e740eff8d2072b60aa4e1c296       5331  src/sort/bigrat.rs
e6713dddb60e9846504de68abc4951ccdaa13b86a24ee8675a38e14152d79ca1       1475  src/sort/bool.rs
1a400116814c14f22078edf0bf0cde0fdc7fdcb2f8e540df84a8ca29e3117575       2803  src/sort/f64.rs
5ee5e18fdc9fe8e25b50aaf3afcd5df4ef2f35535ca8956f74742bd58a848b68      23863  src/sort/fn.rs
8857ed9088b8274455554a70c829c33d04b33c2683c1821e631132958d9fcb94       3489  src/sort/i64.rs
894f9c1f04176ac242c03c190840e2484d8e064e0f559e4d85368abb45c5ac9a      13179  src/sort/map.rs
0be74319643bf11b0e6f807f074c97e07a099bcc60363ade01095c129abac5c4       6061  src/sort/mod.rs
d63686c17c7e960e1b7b68f8b4e77eccd6f336e89583fde6e288cc577966b334      34592  src/sort/multiset.rs
d1e03482ffaadbf761aa7b671fb2f0dbfffe7448b131d5b4ff8f6306ab1c0482       6100  src/sort/pair.rs
2144e0b28444e41388ef0756e5d63c64ffaa871bcca501f80f8e892c91aec550      10947  src/sort/set.rs
59c45c98a274e4e3afabb5856273a0485cb04ba71415051e7db09af0b3011f41       1375  src/sort/string.rs
8a00561ba112a636beb2b1fcfcf3e4b641c767a5a4641aa7821ae1c0a0c6eedc        348  src/sort/unit.rs
c3873adfeae1c735d72569846c61f44c67c5ab3e6d8f794e3f0080ce17225bc0      14524  src/sort/vec.rs
1258701952d86a91e0e87e51b70cf79c048dab74664f96fc77cd76bb6b402561      25789  src/termdag.rs
8c9d80f2b7978d7975b0763074b9f6c84299b50656a7d0b71f1a964a9e9d0550      48220  src/typechecking.rs
ae3fa968874ee7266127b6841b2df53577d4935f68c469836e60cff774e5ea86       5246  src/util.rs
7e74488b243ab4fe59e7d7c4f83924dd99798d67fd769c05a44cd52c78873312        545  union-find/Cargo.toml
8d5f1aa5f799b523d7672dea486d0b46e983720bd4712089e58ffb69fee698c0       3157  union-find/src/concurrent/atomic_int.rs
c98e3e115d96d1a364d695ad688fa225ebf2f62b21b2f5aee51167fb917b870b       3260  union-find/src/concurrent/buffer.rs
42f9861936b40c1a8ad37b63843008efd4addba648bd61b385accd69123576d1       3294  union-find/src/concurrent/mod.rs
c894a0181f4103da53514067fdaf37a2b4caea1e36f7e56b1dfdb53dbe26207b       5156  union-find/src/concurrent/tests.rs
f378e266e202f7f44a90e93f3410b077c1b5f2b1788770efbc5e1c76cb8b0d5c       5535  union-find/src/concurrent/uf.rs
51c01571424b35d97b67ae8270235a18d86abaed22bfec00ab7c8287d64675ac       3254  union-find/src/lib.rs
c901fd2216215cf564ff7a98fa202af38a0d374809ad49df1c983f46653f4860       1150  union-find/src/tests.rs
```
