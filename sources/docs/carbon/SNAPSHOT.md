# Snapshot: Carbon's toolchain design documents

- **Upstream:** `carbon-language/carbon-lang` on GitHub, directory `toolchain/docs/`.
- **Revision:** tag `v0.0.0-0.nightly.2026.10.23` (lightweight), commit
  `434c564a9437faeb7666a01445b85dcbba71918f` ("Fix crash when diagnosing an invalid qualified name
  access (#8012)", 2026-10-22). Carbon publishes no releases; its only tags are nightly builds, and
  this is the latest on 2026-10-23 (`trunk` was at `789f582eb1465ec19aa25224668a03ca0294c381`).
- **Fetched:** 2026-10-23, from
  `https://raw.githubusercontent.com/carbon-language/carbon-lang/434c564a9437faeb7666a01445b85dcbba71918f/<path>`;
  every file under `toolchain/docs/` at that commit, and the root `LICENSE`.
- **Paths:** relative to the repository root (so `toolchain/docs/check/README.md`).
- **Files:** 19 (plus this file).
- **Licence:** Apache-2.0 WITH LLVM-exception (`LICENSE`: "The Carbon language is under the
  Apache License v2.0 with LLVM Exceptions").
- **Topic:** Analyses, solvers and dense side tables (P0 audit 5.7, item 14).
- Nothing was built or run; the files were read only.

**What is here, and why.** A compiler written in C++ on flat, index-based IRs:
`toolchain/docs/README.md` states the architecture (source, lex, parse, check, lower, each step
producing one output structure) and the design patterns, among them "vectorized storage: data is
stored in vectors and flyweights are passed around"; `lex.md`, `parse.md` (the postorder parse
tree in one vector), `check/README.md` (SemIR, its instructions, the node stack and the core loop),
`lower.md` (SemIR to LLVM IR), `idioms.md` (the C++ idioms the toolchain uses) and the rest of the
directory as shipped: `adding_features.md`, `coalesce_generic_lowering.md`, `debugging.md`,
`diagnostics.md`, `diagnostics_rendering.md`, `driver.md`, `design/`, `check/associated_constant.md`,
`check/pattern_matching.md`, `check/cpp/thunks.md`, `lex/mismatched_brackets.md`. The documents
link to sources under `toolchain/` that are not taken.

**How to fetch more.**

```bash
rev=434c564a9437faeb7666a01445b85dcbba71918f
p=toolchain/sem_ir/inst.h
mkdir -p "docs/carbon/$(dirname $p)"
curl -sL --fail -o "docs/carbon/$p" "https://raw.githubusercontent.com/carbon-language/carbon-lang/$rev/$p"
```

## File manifest

Every stored file except this one: 19 files, 285,345 bytes in all. Computed 2026-10-23 over the
stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
46fb19e0671a92ced8396c93a79bce6e97ea5f3578ab0e06fbc86b5a2109ab5d      13160  LICENSE
0f8b90287ad4fb5fb1bd0edfa608f8c946f5efaf7f3d6fef8b1fc183a165934d       4325  toolchain/docs/README.md
43f822ba08757a7a87eefcae5678e8d9c93a84040b11c536999f9c8c82fb5bc0      28161  toolchain/docs/adding_features.md
a495876228a6b9fc75efcd18610fefece83b8ec87a3495088e1869e27d51bf14      30166  toolchain/docs/check/README.md
ba10ec0900fae0635e63ab56d2441ce8e45b841ea89abda7087bdcaf74ebdeeb       7793  toolchain/docs/check/associated_constant.md
3b56da3eec7890f4a7775c8d8aeb34868f3faa423b8a9451db9ecace21d80422      10785  toolchain/docs/check/cpp/thunks.md
c0851169a380436585ab2065377348f3f4a0b0b6916a3ca97d53122393516777      20180  toolchain/docs/check/pattern_matching.md
ec0b3982da05b305ccfcac556eebb4f9cecb046e9112ac7c54f41c9f652e8a18      11844  toolchain/docs/coalesce_generic_lowering.md
e8a7723f83a1f213d4316eea85a756cc3742624ccfb8a8f3d3c093323282421b       9391  toolchain/docs/debugging.md
63b1da921c273dc7596607ccb06adb43e0e0ec2fafc9f2c4a45f7606e5e9a233        267  toolchain/docs/design/README.md
d3ffeefbc2fd330af708ef2fad61bfcb618c2954422d0d38679b6b8d17cdae26       8402  toolchain/docs/design/clang_api.md
fed21bf328c1ef36da2fcce0760854742c545cffaa3bd7a0fb6751ac99517a1a      24517  toolchain/docs/diagnostics.md
f3de2ada3b3daa407b7dd86b3921b880cc5835a29bf42acced29f162f779d206      44616  toolchain/docs/diagnostics_rendering.md
51da1796a72360d7c789f5dfb5245223d0b7516fbe9eea7d5d332d5eeefd5294        571  toolchain/docs/driver.md
b6798d9565fe74121b729a78cde9db0bf56366f1f41880d58c3b5c6fb47b1465      15527  toolchain/docs/idioms.md
b2d5eaac30e968153013ffb3a9ddc05963f56e8c635e7a84fda3df547fec0fdb       1198  toolchain/docs/lex.md
be49ea9c9f2ead557153d81bc6d60b5f73eac58a41328f6543d9987b283b204f      15136  toolchain/docs/lex/mismatched_brackets.md
2b444e0bd2b1df0d441a353ddb77769ac4fd72859f33bf5b9551653181e332a6       8004  toolchain/docs/lower.md
a10f401053675bbc1d0f2b53621bdeb6afe13143855a8d2b07b79d8d9b7c1480      31302  toolchain/docs/parse.md
```
