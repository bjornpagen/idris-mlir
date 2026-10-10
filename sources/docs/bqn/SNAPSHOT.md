# Snapshot: BQN documentation (array model, leading axis, rank, depth, compilation)

- **Upstream:** `mlochbaum/BQN` on GitHub (Marshall Lochbaum).
- **Revision:** `master` at `5abbab967fefc68ae9b3c2620d5d38473a90cb66` (`git ls-remote https://github.com/mlochbaum/BQN.git HEAD`, 2026-10-09).
- **Fetched:** 2026-10-09, from `https://raw.githubusercontent.com/mlochbaum/BQN/5abbab967fefc68ae9b3c2620d5d38473a90cb66/<path>`.
- **Paths:** relative to the repository root (so `doc/leading.md`).
- **Files:** 55.
- **Licence:** ISC (`LICENSE`, © 2020 Marshall Lochbaum), stored with the snapshot.
- **Threads:** Array languages and typed array programming (cluster apl-lineage).

**What is here and why.**
- `LICENSE`, `README.md`.
- `doc/`, the language documentation that states the array model and why the primitives
  compose: `README.md`, `array.md` (what an array is; cells), `arrayrepr.md`, `based.md` (the
  based array model versus APL2's nested and SHARP/J's boxed models), `depth.md`,
  `leading.md` (the leading axis convention and leading axis agreement), `rank.md` (Cells and
  Rank; frames and cells; `F⎉k x ←→ >F¨<⎉k x`), `shape.md`, `reshape.md`, `fill.md` (fill
  elements), `map.md` (Each, Table), `fold.md` (Fold and Insert), `scan.md`, `under.md`
  (structural and computational Under), `undo.md`, `enclose.md` (units), `couple.md` (Merge
  and array theory), `join.md`, `prefixes.md`, `windows.md`, `transpose.md`, `group.md`,
  `primitive.md`, `ops.md`, `compose.md`, `train.md`, `tacit.md`, `types.md`, `glossary.md`,
  `select.md`, `take.md`, `identity.md`, `replicate.md`, `indices.md`, `pair.md`,
  `fromJ.md`, `fromDyalog.md`, `shift.md`, `range.md`, `search.md`, `hook.md`, `valences.md`.
- `commentary/`: `problems.md` (the author's list of BQN's design problems: empty arrays losing
  type information, rank/depth negative zero, no joint reduce), `primitive.md`, `why.md`,
  `history.md`.
- `implementation/`: `codfns.md` (Co-dfns versus BQN's self-hosted array-style compiler, with
  performance comparison and the "axis system" wish), `compile/README.md`,
  `compile/intro.md` (array language compilation in context; typed array languages including
  MLIR), `compile/fusion.md` (loop fusion and blocking in array languages),
  `compile/dynamic.md`, `primitive/types.md` (element types), `primitive/transpose.md`.

The `.md` files embed `<!--GEN … -->` blocks of BQN code that generate figures on the website;
they are data and were not run.

**Not taken, and how to get more.** The specification (`spec/`), the self-hosted compiler
(`src/c.bqn`), the remaining `doc/` and `implementation/primitive/` pages, and the tutorials:
fetch from the raw URL pattern above at the same revision; list paths with
`https://api.github.com/repos/mlochbaum/BQN/git/trees/5abbab967fefc68ae9b3c2620d5d38473a90cb66?recursive=1`.
`src/c.bqn` is the natural next item if the array-style compiler is studied further.

## File manifest

Every stored file except this one: 55 files, 527,927 bytes in all. Computed
2026-10-09 over the stored copies; check with `shasum -a 256 <path>` from this folder.

```
SHA-256                                                           bytes  path
4525bdc55efb7b932c2d94da049aa2dd97ac80bbea9233f5bbb1d77e935d2f8c        772  LICENSE
cffc38c1172f510a7ce62e35ece36705fc09c6389c3d5a433d320eb4a3bd9e32       9019  README.md
0f19ac0e93ab5e49caf73b9c3d12786f7c1fc573ffc14f90fba6607c601bb233      16675  commentary/history.md
faa969d34c5bf0550d8105b5ebb707be5c42dbb15dec40a3458e8839325f1349      10402  commentary/primitive.md
0199946a79b0d5dade9f2ee190a5593d6317ebfbfaeee157c08bf11992156063      37500  commentary/problems.md
93c87f9afd9784f8501de4530f821680a865b7a20ec126b4e5fff2b567d74944      18283  commentary/why.md
dcf6c95768921234077720a68dbc3e2180b07ef58df9c24fd4fcba778e25aef9       3243  doc/README.md
975a90fca1f74f9f548ab159b78082d6a64f3bde1b041a98ca45d34c30125a77      13456  doc/array.md
a333519d0a11ed1d607f9d5e1671d1578f6dcebbb228d8d4cff786b9a93858bc      12507  doc/arrayrepr.md
964c4df386d11f57fe0fbcd20c725afe446674277134e9e9d4cabb67cc78570f       7427  doc/based.md
3d9cbd388f0e16d7ae1d6c50f736194ad2037915ec85a80fc066013d6638e338       3842  doc/compose.md
73fc7a9dfa6b24b1377e0a79570a67fd5f84a3cd24346e16f8bf2f0296f6f400       5539  doc/couple.md
ffca2328d11b9a6ecefb63867f9c42f2d13bd408afa55f9a3b4bf0500e09dd2b       7326  doc/depth.md
e4f2bc6ea4d74fcf79445a534da519b0691a2e15041ead0ecdd33bd63b1ae81b       8989  doc/enclose.md
bc036b9e5942460b67f1df744d2bf7d151af466ffd05a600d88e6c3f786813ac       7039  doc/fill.md
a1ea7d22ef9d27d4f368fe2f45773971818958615db7e4c4f03f4d09177b0f2f      11610  doc/fold.md
e35d80bd51060fe9082e4f78c2254e3bd850be4656b3e0e7dfd0d82f6884548a      11685  doc/fromDyalog.md
910253d3397047aa58cc73940176cd69c58e61438bac0fa504bef4f149cce699      10094  doc/fromJ.md
3fbd08d9784ed9efc1f427502151ff6c7b5656b091a5cb2509ff72994cd4d05b      10184  doc/glossary.md
fbc5abf0897816004356f71fa397aa3be0e36098ae3424dcced46531af79453d      11322  doc/group.md
b2b70f483ec4238c0f3a57c58a61508016f96f2fefe227dff3793cb4af388a43       6848  doc/hook.md
6023744ab52391d6d9302aa86c23c2881a0ee2aa5c50a6d25c034df57e1cca4a       4033  doc/identity.md
50ac465b2e0692f3e134dd4b04eaccfebefeb35f3382a871f17de8d3f5a6244b       9203  doc/indices.md
af89abca257906f7766afee96977f43620bb9eead9395cb5988eb38c5b65744e       6016  doc/join.md
06ae458d5cc1e75cae56d54567579a9c8a05bb75f18364faa634efa959b5cd23      11229  doc/leading.md
c209789107f4cfe750aaa317b1f3a7e0ce3b6fa0f5590c73116fab77f38a2360       8627  doc/map.md
af97a5762ccb8455c942d13ae2ff5ad7a4105c2fb238f1ca80114919f935b544       3908  doc/ops.md
33bd2178a581e02e17c81ae6e713f7e7ea3636071871e701f8928657a5a60176       2566  doc/pair.md
e94a4626ddecb7bd40a74149975661a68f2d00d22f3494bf02c8658b97d45a03       6972  doc/prefixes.md
ca03ab5bc5da6b15df29ccab9cfe3c8892b0e4f50bd25be4e40955b9c6c00cf4       8935  doc/primitive.md
7dc515c9e2d7245370f470001263a9cedebbd2651c82e72b0eaa608177f682a1       4249  doc/range.md
637a873fbf7c1349d8dd5260d7d49f286b898adc2bb9612b4f1e4d912c8bcfe1      15755  doc/rank.md
fa9e5a004027c17f142c27042b2581aa0c2f8bf67f26432ffa12624d952c1428      10761  doc/replicate.md
def0cca5fca4f6023ad2cd11f77f861be766072b3ab21dc31e57cfe8e213b0f0       8340  doc/reshape.md
9c81a4cb21f08754803a2f1c0de3b38d7a6063eabc17117e071f1a40a7ac6556       8095  doc/scan.md
598b0f9b09cac9ab329ff0b947a7a83376eec04cfc366fce04eb13d39352983a      11453  doc/search.md
b9eb1469322bc4253862fade8959bca899ca3d7a890dec4bce14dc7a91ec0168       6450  doc/select.md
977c6d40310eb08d9e641ebf630832bbe1faf6a4181a25d3eb26f6b48a938535       3509  doc/shape.md
198c26e2fd573045cef4c6a682f1927cfed2895a6ef7ebde064244e492ad60b0       7624  doc/shift.md
4d93c7329beadf488cefcef7030c81f5af554a7b48c4afbe1cbe92c384eeb5f8      12840  doc/tacit.md
24bd9497d85b18266354614d34a92cb63f295f84dae82399ccb519734ca1cc3d       6559  doc/take.md
ee63c678c8b28ecda67b5a460cff264c23f7e0ee7d5c366ee9193513490bda0c      11055  doc/train.md
91f336b6241f86c33e2aa6514156ae51af685dfcf80aaf79dcec8cabfa089461       8193  doc/transpose.md
8e203ad02f6fbc46003b458f208532d4cabd905964ef565dc7e903907d696eb5      10002  doc/types.md
8f8cc2ad08d3124715709317452c28d2052165646fe0d11e21ea3b40d3f5213e       9517  doc/under.md
60f3965eeccb9cb409d0dfbaeda839e79960fbdf8093048a7a9ff244fbab0bd0       5427  doc/undo.md
6071b1708692cd986fd23bfd94faac1baeca26a6442f1dc6867ace5bc2d8282b       1149  doc/valences.md
d2c4df6846aae31e6aad9a74a847a7b8f72c2ec7bbb0a0b8480b05b702bcfd4b       6782  doc/windows.md
15604321ff75f573440050c3e7a344e80087778de4c901a45e861271ac4b2a42      22258  implementation/codfns.md
6bb0b9fa6338794538f88e84af53106102e3434b55a1d69394cd101a1d99cfa0       1589  implementation/compile/README.md
e27edad92dc234b8059bba67c578832cf6bb59386d72982bfda5e180aed5669e      12894  implementation/compile/dynamic.md
57e1540621b36020b2feafe1f1501cfaae03fe51a3fe36a3d727b9e71feb6851      10518  implementation/compile/fusion.md
d08f2c75a408fc8c94673966715144e7578f9a0a2c914fde4f98eaf15f65fc7a      16421  implementation/compile/intro.md
b31e3ddaa5dfc80f7aeef1028cc1e2e6bd552c80c64fb7f46e39d4a0b2a08121      19755  implementation/primitive/transpose.md
4a4f43dd48f2894e1016533df8f4c41bb1fc421b4d46aef6835f8e6f54985c73      11481  implementation/primitive/types.md
```
