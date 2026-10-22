<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 wave 2, lane `history`: what the history teaches the cutover

Lane `history` of proposal P0 (`proposals/0000-mlir-native.md`). Scope: the
git history (first commit 0948fbf4, 2026-09-22), the audits as they stood at
77eaa5b1, `PINS.md`, `upstream/`, and the deleted proposals' last texts.
Read as a history, the layout of `audits/p0/README.md` means: section 2 is the
history's shape; section 3 reconciles the proposal's claims about history
with the commits; section 4 is the issues the history reveals; section 5 is
what P0's plan must do differently because of it.

Marks: *read* (a commit, a file, a proposal section), *measured* (a count,
with its command), *recalled*, *conjecture*.

## 1. Reading notes

Notes on the proposal (`proposals/0000-mlir-native.md` at the working tree
of 2026-10-21), written while reading, kept to what bears on the history.

- **§1 (owner's directives).** "Undo the damage of replacing upstream MLIR
  machinery. The agent that did it was concerned with getting it to work;
  learn from that history." This lane's whole charge. Also: "the `idr`
  dialect is a historical accident"; "no fanouts across our own codebase
  until the research is fleshed out" (a lesson already drawn from history:
  fanouts before the plan).
- **§2 (brief).** Measured at e96bb991. Lists still-on-framework files
  (`Analysis/Constants`, `Ranges`, `Ownership/Borrows`,
  `Narrow/{Lanes,Copy}`, `Tail/Returned`, `Effects/Constants`) and the
  carried patches touching analyses (01, 06, 16, 22 on remove-dead-values
  "before the pipeline dropped it"; 02, 17 SCCP; 05; 28, 63 liveness; 29;
  62; 24, 27; 03, 25; 23, 56; 09, 57). The trait-layer reading is
  *recalled* from another agent: three representations of "does IO"
  (`PerformsIO`, `IOResource`, world-operand body effect). History must say
  how three arose.
- **§3 (the table).** Eight walls of 2026-10-20/21: ffa91113 (exclusivity
  on DataFlowSolver, 627 GB), 16005000 (remove-dead-values 52 GB after four
  patches; idr-frames 43 GB), e96bb991 (exclusivity graph build, quadratic
  per terminator/successor pair), b8301ebe (rc-stack 47 GB), 3a96c407 and
  7987388b (optimize, 75 M pattern attempts, any-op patterns), 98c6315c
  (context write lock on a mutable type's facts), 73bba53f (defunc 843 s,
  data table rebuilt per declaration). Conjecture there: upstream failed on
  its *state model*, not its algorithm; several walls were ours and each
  was fixed by a representation. This lane completes the table.
- **§4 (the bar).** Order: upstream as is; upstream patched; our solver in
  the solver layer with a header naming what upstream lacks and the
  measurement. "Hard cutover, and a hard cleanup after."
- **§5.1 mlir-analysis.** A4 (*measured*): at the pin a 1-bit state costs
  about 2.9 KB, more than 90 percent two minimum (64-bucket) hash tables;
  patch P1 (two declarations) cuts it about fifteenfold. A6: per-function
  solve is a supported scope; nothing between function and module. A7:
  `loadBaselineAnalyses` coupling (DeadCode + SCCP must load). B3: the only
  reason remove-dead-values needs a whole-module solve is its
  interprocedural part (dead args/results of private functions). B4: of
  the eight carried liveness/RDV patches, two were silent miscompiles on
  our shapes (28: terminator forwarding nothing; 29: nested symbol table,
  every idr program is an `idr.program` nested in the module). C2/C4: the
  match ops can override `getPredecessors`, `getPredecessorValues`,
  `getSuccessorRegions(Region&)`, `isRepetitiveRegion` per op; e96bb991's
  quadratic graph is "this lesson". D3: `RecursiveMemoryEffects` is a whole
  body walk per query. G3: ownership-based deallocation fixes a function
  boundary ABI instead of solving across calls. H1: 52 GB implies about
  10 M values at ~5 KB/value. H2 (*conjecture*): 627 GB is ~200 M states.
  5.1.2 item 1: "the previous agent's inference that DataFlowSolver
  'cannot' do 70,000 functions was right about the pin and wrong about
  upstream". Item 4: RDV split along B3's line; patches 06, 16, 22, 28, 63
  stay relevant per function. Owner questions QA1 (U1 first, P1 or P2),
  QA2, QA3 (RDV split or whole module), QA4. Wave-2 W1-W7.
- **§5.2 mlir-ods.** A5: ODS effects and a hand `getEffects` on one op
  collide (all or nothing). A7: divergence/crash as speculation vs a
  `Write` effect. E1: the 75 M attempts of 3a96c407 "are what the any-op
  list does by design"; interface- and trait-rooted patterns are filed per
  op at freeze. E3: the walk driver terminates by construction (AGENTS.md's
  shape). E4: DRR native; PDLL has no production user. M10: 98c6315c's lock
  came from a uniquing or mutating call on a read path; 73bba53f's
  quadratic cost is the immutable-attribute table's. Questions Q1-Q6;
  wave-2 W1-W10 (W6 is the history of 98c6315c).
- **§5.3 llvm.** B3: our `std::variant` density is about a hundred times
  LLVM's per line. B7: dense numbering is LLVM's newest move
  (`Block::getBlockID`). B8: `lib/Support/Scc.cpp` is "by its name a
  hand-rolled `scc_iterator`". C7: none of LLVM/clang's frameworks is
  threaded; SCCP scales with no stored dependents and one flat map.
  D1: `llvm::parallelFor` inside an MLIR pass is a second pool.
- **§5.4 modular (read most carefully).** F2: Modular runs no
  `DataFlowSolver` anywhere; keeps upstream lattice values, folders,
  effects, dominance, greedy driver; replaces only engine and state. F3:
  `SCCGraph`/`CallGraphBase` CRTP pair is the interprocedural spine. F4:
  `EliminateDuplicateFunctions` is what we ported (PINS.md); our port
  replaced AsyncRT chains by waves by height with a barrier per wave
  (5.4.2 item 3). F5: Modular's own SCCP copies its map per nested region
  (b8301ebe's shape). F6: IPDF rows shared until written (design 3). F7:
  HLCF does not implement `RegionBranchOpInterface`; `CFGAnalysis` asks each
  terminator once (the e96bb991 lesson). F8: dead-argument elimination
  with state per argument/result, no `remove-dead-values` (16005000's
  answer). F14: Modular's agent rules govern *process* (small PRs,
  human-written descriptions, Assisted-by trailer); ours govern design.
  F16: verifier off in production, explicit verifier passes at phase
  boundaries. F17: Modular keeps two implementations behind options, a
  legacy one; facts in discardable attributes; "keep in sync" lists. These
  are the drift our hard-cutover rule exists to prevent. Q-M1 (spine),
  Q-M2 (verification), Q-M4 (port more of Modular: schedule, per-worker
  driver, dead-argument pass, `Shared<T>`), Q-M5 (specializer shape). The
  history lane gives evidence on Q-M4 from the deduplicator port's history.
- **§5.5 cxx26.** No reflection, no contracts in the pin; expansion
  statements partial. `std::visit` cliff at 12 alternatives (measured on
  host). PCH 1.54 s to 0.43 s per TU. D1 boundary rule (interfaces over
  ops, concepts below the dispatch). D2 `match`. History bears on how the
  192 variant accesses and the 60 variants grew (which commits added them).
- **§5.6 ecosystem (read most carefully).** "None of the large MLIR
  codebases runs a whole-program per-value solve on `DataFlowSolver`." B5:
  CIRCT moved Arc's `LegalizeStateUpdate` off the framework in e2eb7c66b
  (2023): 130 s to 200 ms, nodes only for interesting ops; "the move our
  ffa91113 made for exclusivity, three years earlier." B3: upstream's
  framework was reviewed without a memory measurement (D126751). B4:
  designed for extensibility against DFX. C3: IREE turns DFX's round budget
  into a compile error (what AGENTS.md forbids). D2: IREE's
  `FixedPointIteratorPass` (round count that refuses, "changed" in a
  discardable attribute). D3: IREE scopes upstream's framework per function
  and re-solves after each greedy round because incremental invalidation
  crashes (iree#20636). D4: IREE rebuilds DFX analyses in 14 passes (the
  rederivation chain at whole-program scale). D6: IREE writes the
  analysis answer into the type once (our grades are this). G1: Enzyme
  moved to per-function summaries; G2: Triton walks a DAG per path
  (exponential). 5.6.2 item 1: "a state exists only for what the problem
  is about"; our types already answer it for many values. Item 2: one
  call graph, cached and maintained (CIRCT `InstanceGraph`); item 8:
  structured walks copy state per branch unless deltas. Design 1:
  `ProgramGraph` + three solve shapes (S summaries, L local, G
  extract-solve-write-back). Q-E1..Q-E5; Q-E4 (porting CIRCT/IREE code,
  recorded in PINS.md like the Modular port) and Q-E5 (two upstream RFCs:
  maintained call graph; a scope between function and module) are this
  lane's to give evidence for. W-E1..W-E9.
- **§5.7 library.** M1: the 627 GB wall is "a dense formulation of a
  sparse problem"; L1: SSI by representation (every ownership change a new
  value). M2: the 52 GB wall is a one-bit problem held as a lattice per
  value; dead args are a bit per argument in a summary. M3: e96bb991 is
  "validation repeated where a parse belongs". M4: rc-stack 47 GB is a
  dense set per value copied per edge. M5: frames 43 GB and the
  specializer walls are "clones materialized before they are
  deduplicated" (L5 clones as keys). M6: 98c6315c and 73bba53f are "a
  mutable, nominal type read while it may change"; L3 build-then-freeze.
  It cites `notes/compile-pipeline/upstream-mlir-llvm.md` §4:
  `int-range-optimizations` nested per function measured 3 s against 30 s
  module-wide (an earlier measurement in our notes, history to check).
  QL1-QL6.
- **§5.8 dialect-design.** "The `idr` dialect is a historical accident: it
  grew one case at a time." The design guide's carrier table: a fact in a
  lower row than its readers need is rederived. DS1 one grade attribute
  with an interface (illegal pairs unrepresentable). DS2.1 no world value
  after the frontend; DS2.2 keep the world, derive effects by one rule.
  DS3 recursive data types: 98c6315c and 73bba53f "were walls of this
  design". DS4 the mapping table (check ops into `arith.cmpi` + one
  `idr.check`, word ops into `arith`, six stat ops into one, eight clocks
  into one, `put_*` into show + write). DD-Q1..DD-Q8. History bears on
  how each family arose (one commit per case?) and on whether the world
  token, the `data` mutable type and the grade's four parameters were
  owner decisions or agent drift.
- **§5.9 mlton.** H's table maps every §3 wall to a MLton non-choice
  (no program points, no whole-program liveness, flat cases, demanded
  instances, no pattern driver, facts not inside types, tables built
  once). M2: "the three fixes already made (ffa91113, b8301ebe, 16005000)
  are each a step towards MLton's model, taken one analysis at a time".
  F3: DeepFlatten, MLton's one pass with state per object value, is its
  one documented blowup (same lesson as §3). G2.10: the driver reports
  the live heap per pass; Design 6 "footprint of every pass as a
  first-class report" (Tracy plot per pass). Design 2 (`case` as a
  terminator after defunctionalization); Design 3 (facts into types, no
  side tables between passes); Design 5 (one linear normalizer, no
  any-op patterns). Q-O1..Q-O5; Q-W1..Q-W9.
- **§5.10 rc.** M1: "every counting algorithm in the field is per
  function"; "None keeps per-value state for the whole program. Each of
  §3's counting walls did." M2: if `Uses`/`Values` compute liveness that
  `idr-rc-cells` reads, that is a rederivation chain Perceus does not have.
  M6: "the commit messages of ffa91113 and e96bb991 ... suggest it is
  already this shape" (history to confirm). M7: `Reuses` before or after
  insertion (algorithm K/D vs drop-guided). M8: `Captures` may vanish
  after defunctionalization. R1-R4; rc-Q1..Q5; W1-W9.
- **§5.11 oom.** O1: every wall was memory after the time walls fell;
  each fixed at the representation, none by a limit (proposal 0001).
  (A): "every wall so far was a representation, and every fix was one";
  A1 memory stated per solver in program units; A2 per-pass footprint as
  `PassInstrumentation`; A3 name the death; A4 budgets in program units
  only (stage 2 = stage 3). oom-1..9.
- **§6-§9.** §6: twenty wave-2 lanes dispatched 2026-10-21. §7 not
  written. §8 gathers every owner question; this lane's: QA1, QA3 (8.4),
  Q-E5 (8.4), Q-M4 and Q-E4 (8.2). §9: D1 P0 first; D2 own solvers
  allowed, named honestly; D3 no fan-out over our code until wave 1
  fleshed out; D4 no code until the whole plan is approved.

## 2. The history's shape

### 2.1 Size and authorship (*measured*)

- 1,202 commits, 0948fbf4 (2026-09-22) to e96bb991 (2026-10-21)
  (`git rev-list --count HEAD`); 109 merges (`git rev-list --merges
  --count HEAD`).
- Author field: 613 `Claude`, 589 Bjorn Pagen (two addresses, 521 + 68)
  (`git log --format='%an <%ae>' | sort | uniq -c`).
- Co-author trailers: 884 Claude Opus 5.5, 134 Cursor, 62 Claude Fable
  5.1, 22 Muse (Meta) in four spellings (`git log
  --format='%(trailers:key=Co-Authored-By,valueonly)' | sort | uniq -c`).
- 1,124 commits are agent-authored or agent-co-authored; 78 carry no agent
  at all, and those are almost all merges, lane checkpoints, the two
  reverts and bench regenerations (`git log --format='%H%x09%an%x09%(trailers:...)'`,
  counted by awk).
- Commits per day peak on 09-29 (171), 10-19 (125), 10-09 (118), 09-28
  (100) (`git log --format=%ad --date=short | sort | uniq -c`).
- The walls of §3 (2026-10-20/21) were fixed by three different agents:
  Muse (3a96c407, 7987388b, 16005000, b8301ebe, ffa91113, e96bb991), Claude
  Opus 5.5 (98c6315c), Claude Fable 5.1 (73bba53f) (*read*, the trailers).

### 2.2 Phases (*read*, the commits named)

| dates | phase | what happened | marks |
| --- | --- | --- | --- |
| 09-22..25 | scaffold | 0948fbf4 scaffold; d79c9714 removes the C++ driver | owner-authored |
| 09-26..30 | first agent swarm | 045f8ed5 "WIP: p0/v0/v1 dialect" (world type, IOResource, CrashResource on day one); 7 "WIP: coding-wave snapshot (unverified)" on 09-27; 54 "Work in progress from the agents" on 09-29/30 (69fea52a "as it stood when the container restarted"); 2ab5adf9 puts upstream remove-dead-values and SCCP in an idr-simplify fixpoint compared by printed module text; 595ed341 puts exclusivity on `DataFlowSolver`; 64c03508 deletes the normative docs ("the code is the specification") | almost all `Claude` authored |
| 10-01..03 | findings and modules | findings/ (f2d6df36 "what the pinned MLIR offers that the pipeline does not use yet"); 4cfce768 "C++ as named modules, one concept per file" (39,204 lines), 0641826a writes the modules rule into AGENTS.md | `Claude` |
| 10-05..09 | upstream policy and the LLVM pin | fc7dc230 "a patch for every upstream bug that can have one"; 7203ef2e writes AGENTS.md's "fixed in that upstream" rule (10-06); 20fcfadb pins LLVM main 7208ba24; 327c2e30 "the representation cutover"; 563ecc8b deletes 38 of 150 configuration knobs; 9eaa1adb "findings/ is gone" | owner-authored, Claude co-authored |
| 10-10..12 | the layout cutover | 1e1a3827 (66,564 lines): upstream's layout, no C++ modules, analysis manager, `idr.func`; "Nothing has been built or tested beyond make typecheck and make check" | the largest commit |
| 10-13..15 | compile time and the four swarm waves | 3dbf0e2f and 2c89226a ("upstream MLIR mechanisms first; Mojo is evidence, not a template"); 2295e06b "bankruptcy declared"; 552d682a scc-pipeline behind an option, struck by the owner (57bf8e1d); 30 lane checkpoints and merges on 10-14 (*measured*); c7aa7b62 pipeline cutover (30,243 lines), bfdcac70 "no fuel" (29,070), d06ed15c "0004-total" (19,436), 1cd1193a "0014-sound" (4,098), each "integrated on the typecheck machine"; 19fe1332 AGENTS.md's acceptance and budget rules | waves landed unbuilt |
| 10-16..18 | the representation wave | 1e5a8a8e packet (24 lanes); 2c042728 lands it (32,095 lines) "nothing is linked or run"; d346040c purges the test suite (362/463); 45cc3544 four targets | owner "rip it" (2026-10-17) |
| 10-19 | sweeps, WIP and the close-out | 125 commits: the rederivation sweep (audits/rederived.md, owner's request), label solve (7adc6095), leaks (da66bd95); ten WIP commits; the static-lifetime cutover and its removal (c4d38e9b); two owner reverts of agent WIP (43fc7b39, be2fa9e7); upstream 28, 29, 62, 63 (62902eff, 4dde6b7f); 91615083 culls the proposals and folds the audits into them | |
| 10-20..21 | stage 1's pipeline walls | b9d4d592, 73bba53f, 98c6315c, 3a96c407, 7987388b, 16005000, b8301ebe, ffa91113, e96bb991 (§3's table); P0 written | Muse, Claude, Fable |

### 2.3 How changes landed (*measured* unless marked)

- **Swarm waves as single commits.** Nine commits change more than 4,000
  lines of `foreign/idr` (`git log --shortstat -- foreign/idr`, summed):
  1e1a3827 66,564; 4cfce768 39,204; 2c042728 32,095; c7aa7b62 30,243;
  bfdcac70 29,070; d06ed15c 19,436; 327c2e30 8,858; 69fea52a 6,802;
  96e1d308 4,804. Six commit bodies say "typecheck machine"; four of the
  waves say in their own words that nothing was built or run (1e1a3827,
  d06ed15c, 2c042728; 1cd1193a "the compiler's behaviour is the owner's
  build").
- **WIP on main.** 85 subjects start "WIP" or say "work in progress"
  (54 of them "Work in progress from the agents", 09-29/30; ten on 10-19);
  25 say "unbuilt" or "unverified"; 28 are checkpoints
  (`git log --format=%s | grep -c ...`). 9c30f058 made it policy: "a WIP
  commit still builds, since every lane builds from main, and a lane pushes
  whenever it waits".
- **Reverts.** Two `Revert` commits, both by the owner with no agent
  trailer, both of agent WIP marked "unfinished and unbuilt" (43fc7b39 of
  0377cf24, be2fa9e7 of 1715e261, 10-19); both were then committed again
  (d701b686, d5b45672). Other undo commits: c4d38e9b ("the static-lifetime
  cutover is taken out"), "Restore Proof/AlmostFull.idr, which 3b1909e7
  deleted by accident", "Rule: restore the withdrawn heap rules' removal,
  which the last commit undid".
- **The suite record.** `make test` was 415/415 at 7a27fd34, 3a275cf0 and
  df5d8742 (10-14). It has not been green since: 362/463 (d346040c,
  10-18), 408/462 (4603d0cb), 413/462 (6f774119), 451/480 (017f5374, per
  proposals/README.md), 470/480 (ffa91113, 10-21) (`git log --format=%B`,
  grepped for `N/M`).

### 2.4 Churn and growth (*measured*)

- Most-touched files (`git log --format= --name-only | sort | uniq -c |
  sort -rn`): PINS.md 109, `foreign/idr/include/idr/IdrOps.td` (the
  pre-layout path) 88, `Passes.td` 78, README.md 73,
  `foreign/idr/CMakeLists.txt` 66, upstream/README.md 59, audits/bugs.md
  58, proposals/README.md 55, AGENTS.md 53. On the Idris side:
  `Dialect/Idr.idr` 45, `Translate/Terms.idr` 41, `Translate/Types.idr` 39,
  `Emit/Bodies.idr` 38. The documents of record churn as much as the code.
- Since the layout cutover (1e1a3827, 10-12) the most-changed C++ areas
  (`git rev-list --count 1e1a3827^..HEAD -- <dir>`): `lib/IR` 49,
  `include/idr/IR` 36, `lib/Analysis` 30, `Transforms/Ownership` 22,
  `Analysis/Ownership` 20, `Transforms/Tail` 20, `Specialize` 19,
  `Conversion` 19; `tests` 112.
- The C++ and its patterns across the waves (`git ls-tree` + `git show |
  wc -l` for lines; `git grep -c` summed over `lib`, `include`, `tools`,
  `unittests` for the rest; 4cfce768's layout differs, so its row
  undercounts):

| commit | date | C++ lines | `isa<` | `dyn_cast<` | `visit`/`get_if`/`holds_alternative` | `std::variant<` | `function_ref<` | `getEffects`/`MemoryEffects` | `hasTrait<` | worklist | `MatchAnyOpTypeTag` | `DataFlowSolver` |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 4cfce768 | 10-03 | 29,310 | 244 | 330 | 12 | | 30 | 75 | 12 | 7 | | |
| 1e1a3827 | 10-12 | 39,827 | 285 | 459 | 9 | 4 | 55 | 110 | 16 | 1 | 3 | 20 |
| c7aa7b62 | 10-14 | 41,183 | 272 | 407 | 7 | 4 | 60 | 108 | 15 | 11 | 3 | 22 |
| bfdcac70 | 10-15 | 47,531 | 292 | 427 | 4 | 1 | 87 | 138 | 39 | 12 | 3 | 23 |
| d06ed15c | 10-15 | 50,555 | 280 | 428 | 117 | 38 | 93 | 145 | 42 | 101 | 6 | 29 |
| 1cd1193a | 10-15 | 53,438 | 285 | 434 | 117 | 38 | 94 | 151 | 43 | 101 | 7 | 29 |
| 2c042728 | 10-18 | 55,650 | 247 | 407 | 156 | 59 | 85 | 124 | 37 | 96 | 6 | 31 |
| HEAD | 10-21 | 59,886 | 278 | 451 | 192 | 60 | 94 | 155 | 49 | 87 | 0 | 29 |

  The C++ doubled in eighteen days and grew by half in the last nine. The
  closed sums the brief counts (60 variants, 192 accesses, §2; §5.3 B3's
  "a hundred times LLVM's density") came in two waves: 0004-total
  (d06ed15c, "termination by construction and representation-first")
  added 34 variants, 113 accesses and 89 worklists in one commit; the
  representation wave (2c042728) added 21 variants and 39 accesses. The
  `isa<` count did not fall across any wave.

### 2.5 The documents of record

- Proposals are deleted when done and the queue renumbered (eight
  renumberings, proposals/README.md); the three waves' last texts are
  d346040c (total), 2d9290b5 (sound) and 77eaa5b1 (representation), each a
  dispatch packet of 18 to 27 lanes with `ownership.json` and per-lane
  dispatch files (*read*: `git ls-tree 77eaa5b1 proposals/`).
- The audits at 77eaa5b1 are 44 files and about 19,000 lines (`git
  ls-tree -r 77eaa5b1 audits/`, `wc -l`): the 10-18 test-suite audit
  (SUMMARY.md 1,455 lines, gaps.md 886, programs.md 967, and the
  strengthen-* files), the 10-19 audits (rederived.md 269, label-solve.md
  484, leaks.md 626, arrays-refused.md 459, constant-stack-io.md 448,
  crash-after-main.md 135, config.md 132) and 15 `done-*` files. All
  but `bugs.md` were folded into proposals and deleted by 91615083 (10-19).

## 3. Reconciliation with the proposal's claims about history

### 3.1 §3's table, row by row

| §3 row | verdict | what the commits show |
| --- | --- | --- |
| ffa91113, exclusivity on `DataFlowSolver`, 627 GB | holds | *read*, the message: "four analyses on MLIR's DataFlowSolver over the whole program: a lattice per value, an Executable per program point and a predecessor state per function, each behind nested maps and uniqued program points ... a 627 GB peak footprint when jetsam stopped it". Two things §3 does not say. The design was upstream-first by choice: 595ed341 (09-30, Claude with Fable) put the excl inference on the solver, "optimistic as SCCP is, with DeadCodeAnalysis for reachability and a constant lattice that knows no constant", which is §5.1 A7's baseline coupling paid as a rigged lattice; ffa91113 calls it "a lattice rigged to know no constants". And the drop tried no patch of the state's storage: the one patch that touches `DataFlowFramework.h` is 05, a per-run `SymbolTableCollection` for callee lookup, and none touches the per-anchor map or the dependents' `SetVector` (*measured*: `grep -l DataFlowFramework upstream/*/llvm.patch` finds only 05; `grep -c 'SetVector\|DenseMap<TypeID'` on it is 0); the commit argues from the problem's shape ("reachability and joins over a lattice of height two"). |
| 16005000, `remove-dead-values`, 52 GB "after four carried patches" | holds in part | *read*: the 52 GB is "the untraced run sampled there", a sample, not a peak. The four patches carried at the drop were 06 (unreachable values), 28 (liveness at a non-forwarding terminator), 29 (dead code under a nested symbol use) and 63 (liveness's trivially-dead walk), not §2's "01, 06, 16, 22": 01 never had a patch of its own (06's covers it, PINS.md "remove-dead-values-address-taken"), and 16 and 22 stopped being carried on 10-14/15 when the pipeline cutover deleted the simplify rounds that reached them (upstream/README.md "When nothing reaches the bug"; c7aa7b62, d06ed15c). 28, 29, 62 and 63 were all added on 10-19 (62902eff, 4dde6b7f, Claude) for this pass and its driver; the pass left the pipeline the next day. The drop rides in a commit about idr-frames, in the message's second half, and did not touch PINS.md or `upstream/` (*read*: `git show --stat 16005000`). |
| e96bb991, the exclusivity graph's build | holds | *read*: "an interface lookup and a fresh successor list per pair ... the square of the case count"; after: "a generated match of 20000 cases now takes 1.3 s of IdrRcExclusive in the debug build". The quadratic was written under three hours earlier, in the graph's first version (ffa91113, 05:10; e96bb991, 07:49; both co-authored by Muse). |
| 16005000, idr-frames, 43 GB | holds | *read*: "cloned every member's body once per member-and-answer pair ... bindGrammar's grammar interpreter, 336 s in one action ... jetsam-killed at 43 GB". |
| b8301ebe, idr-rc-stack, 47 GB | holds | *read*: "sampled live in memmove inside BitVector unions ... a fact per pair of value and cell". |
| 3a96c407, 7987388b, 75 million attempts | holds | *read*: "each was a MatchAnyOp pattern, tried 75 million times in 31 traced minutes"; 7987388b: "MatchAnyOpTypeTag occurs nowhere in the tree now". *Measured* (`git grep -c MatchAnyOpTypeTag <commit>`): 3 at 1e1a3827, 6 at d06ed15c, 7 at 1cd1193a, 6 at 2c042728, 0 at 7987388b: the waves added them. |
| 98c6315c, the context's write lock | holds | *read*: "every holdsReferences and holdsWorld of a data type read its facts through the uniquer's mutate, which takes the context-wide write lock ... The facts were a lazy fixpoint, kept on the first question". The mutable `!idr.data` type itself arrived six days earlier, in the pipeline cutover's wave (c7aa7b62, 10-14: first `MutableType` and `class DataType`, *measured* by pickaxe). |
| 73bba53f, defunctionalize 843 s | holds | *read*: "declaring a type remakes it whole, and the dev build verifies every member of each remake ... O(N^2) in the table, 843 s ... 6,988 types to start with". The verifier after every pass multiplied the quadratic. |

### 3.2 Walls §3 does not list

Each *read* from its commit; "ours" or "upstream" as §3 marks them.

| commit | what ran out | why | whose |
| --- | --- | --- | --- |
| b9d4d592 (10-20) | defunctionalize's first half hour on stage 1 | a data type's printed text held every body it reached, once per path; types were digested by printing them | ours |
| 7adc6095 (10-19), audits/label-solve.md at 77eaa5b1 | the label solve: about 4.3·10⁹ (node, label) items, ~300 GB projected at 65,536 labels | each union-find class owned a copy of its set | ours |
| 4dde6b7f (10-19), PINS.md "greedy-multi-region-ancestors" | canonicalize 30, 120, 223 s at 1k, 2k, 4k cases | the greedy driver re-queues every ancestor of a changed op; patterns of a many-region op read all regions | upstream, patched (62) |
| 4dde6b7f, PINS.md "liveness-trivially-dead" | remove-dead-values 10.9, 30.9, 87 s at 1k, 2k, 4k | liveness asks `wouldOpBeTriviallyDead` once per region successor | upstream, patched (63) |
| upstream/05 (98fb2f3d, 10-08) | sccp 8.8 s at 16,000 functions (0.7 s patched, per §5.1 B1) | `resolveCallable` scans the module per call visit | upstream, patched |
| 2295e06b (10-14), F0 | the simplify rounds: round 1 447 s with one 211 s InlineCleanup, sixteen rounds without a fixpoint | whole-module rounds, per-round fingerprints and rebuilt analyses | ours |
| 2ab5adf9 (09-28) | the simplify loop never ended | `OperationFingerPrint` hashes op pointers and SCCP rematerializes every constant, so the loop compared the module's printed text instead (patch 02 later) | upstream behaviour worked around by ours |
| 5d3318fb (10-14) | int ranges | solved over the module; now per function in parallel (§5.7 cites 3 s against 30 s from our notes) | upstream, rescoped |
| 25890d32, 96e1d308 (10-11) | nested pipelines and the driver single-threaded | workers could not read the symbol table opened on the pass thread; a JIT kept the driver serial | ours |

### 3.3 Every upstream mechanism we dropped, patched or never adopted

*Read* from the commits named; "first/last" by pickaxe over `foreign/idr`
(`git log -S`); "at HEAD" by `git grep`.

| mechanism | history | why, per the commits | what it cost | does the reason hold after wave 1? |
| --- | --- | --- | --- | --- |
| `DataFlowSolver`, exclusivity | adopted 595ed341 (09-30); dropped ffa91113 (10-21) | state per program value; the question is a two-point marking | 627 GB; the rigged constant lattice | In part. §5.1 A4 puts most of the per-state cost in two 64-bucket tables a two-line patch removes; no patch was tried. §5.10 M6 and §5.9 M2 agree the problem is a marking, so the honest solver is defensible, but it was chosen under pressure, not by §4's order. |
| `DataFlowSolver`, Borrows | a hand solver until the representation wave moved it onto the framework ("analysis-14: Borrows is a hand-built dependency solver where MLIR's solver is the mechanism", 77eaa5b1 packet §3 and §5); on it at HEAD (`lib/Analysis/Ownership/Borrows.cpp:298`, a whole-program solver) | upstream first (packet invariant 5) | not measured at stage 1 | Unknown: the same state model ffa91113 left three days later; wave 2's analyses and ownership lanes must measure it. |
| `remove-dead-values` | adopted 2ab5adf9 (09-28) inside idr-simplify; our idr-prune and idr-dead-values deleted in its favour (c018b2bc 10-06, 0451b1b8 10-09); patches 01, 06, 16, 22, 28, 29, 63; dropped 16005000 (10-20) | whole-program liveness per value | a crash on a self-recursive private function (2ab5adf9: symbol-dce must run first), a fingerprint broken by rebuilt calls (16), two silent miscompiles (28, 29), 87 s at 4k cases (63), 52 GB | For the whole-module form, yes. §5.1 B3 splits it: intraprocedural upstream per function, dead arguments as a signature summary; 16005000 moved the signature half into specialization ("decided where demand is decided"), so only the per-function half is a candidate to return (QA3). |
| SCCP | in the simplify round from the first swarm (045f8ed5, 09-26) until the pipeline cutover deleted the rounds (c7aa7b62, 10-14) | the rounds' cost (F0), not SCCP's; `SparseConstantPropagation` survives, subclassed (`Analysis/Constants.h:44`) | the text-compared fixpoint (2ab5adf9); patch 02 written, then uncarried | The pass went with the rounds; nothing measured SCCP alone. |
| `int-range-optimizations` | added in the WIP swarm (1b507bcb, 09-30); per function in parallel (5d3318fb, 10-14); gone at bfdcac70 (10-15) | absorbed into our narrowing; `IntegerRangeAnalysis` stays (`Analysis/Ranges.cpp:25`, `Narrow/Copy.cpp:72`) | patches 09, 57 carried | Holds as a design choice; §5.1 item 2 lists Ranges and Narrow as per-function framework users to keep. |
| upstream's composite fixed-point pass | replaced by idr-simplify's own fixpoint (report 6046a8f9, upstream/02), then the rounds deleted (c7aa7b62) | SCCP's constant churn broke the fingerprint | text comparison of whole modules per round | The fixpoint is gone; AGENTS.md now forbids a round count that refuses (19fe1332). |
| the upstream inliner pass | never adopted (`createInlinerPass` never in the tree); our idr-inline, then idr-optimize, with `DialectInlinerInterface` (`IR/Func.h:26`) and patch 07 | "each function once, bottom-up", with specialization | InlineCleanup 211 s in F0; two refactors built and measured on 10-14, both rejected (2295e06b) | Holds: §5.1 E1 finds the inliner parallel only inside one SCC. |
| `duplicate-function-elimination` | never adopted; Modular's pass ported (234b81a0, 10-14; PINS.md "eliminate-duplicate-functions") | upstream's works on `func::FuncOp` and merges in one round | none recorded | Holds; the upstream generalization PINS.md plans "is planned ... not written". |
| the greedy driver | kept for canonicalize; patch 62; any-op patterns removed (7987388b); 7 `walkAndApplyPatterns` uses at HEAD | many-region ancestors; any-op dispatch | §3.2's 223 s; 75 M attempts | Holds (§5.2 E1-E3). |
| One-Shot Bufferize | adopted with patch 24 (c7aa7b62) and 27 (uncarried) | `FunctionOpInterface`, a custom tensor-like type | not measured at stage 1 | Holds. |
| `CallGraph` | the representation wave moved the five SCC walks to `AnalysisManager` and `CallGraph` (packet §5); `CallCycles` uses `mlir::CallGraph`; `lib/Support/Scc.cpp` still serves nine type and data graphs (`git grep -l Scc`) | one fact, one place | | Partly done; §5.3 B8's question stands for the other nine. |
| `AnalysisManager` | adopted at 1e1a3827 ("analyses live in the analysis manager") | | 0003 lists analyses dropped and rebuilt (Effects preserving only `SymbolTable`; `TypeGraph(op)` built outside the manager) | Adopted, not used whole. |
| MLIR's own C++ (headers) | `bjornpagen/cpp-starter` (AGENTS.md before 1e1a3827) → named C++20 modules (4cfce768, 0641826a, 10-03, Claude) → upstream's layout (1e1a3827, 10-12) | modules: "nothing is declared twice"; back: "in-tree MLIR dialect in upstream's layout" | two clang crashes "worked around and reported in upstream/ (not reduced yet)" (4cfce768), then upstream/11 and 12 dropped with the modules | Holds (§5.5 D7: no modules in P0). |
| the ExecutionEngine (compile-time evaluation by JIT) | dropped (96e1d308, 1e1a3827) | single-threaded driver | patch 08 kept as a submission | Holds. |
| LICM, control-flow sink, mem2reg, SROA, ownership-based deallocation, upstream `Liveness` | never in the tree (*measured*: no pickaxe hit for their pass constructors in `foreign/idr`) | never stated | | §5.1 D2 and G1, §5.10 G5: candidates, if the effects are declared. |

### 3.4 The wave-1 lanes' readings of the history

- **§2, "four on remove-dead-values (01, 06, 16, 22)"**: refuted in part
  (3.1).
- **§5.1 5.1.2 item 1, "the previous agent's inference that
  DataFlowSolver 'cannot' do 70,000 functions"**: holds in part.
  ffa91113 never says "cannot"; it says the state per value ran out and
  that the questions are a marking. 595ed341's choice of the framework was
  itself the upstream-first move; the error was adopting without a scale
  test and dropping without a patch, not a belief that upstream cannot.
- **§5.1 B4, two silent miscompiles on our shapes (28, 29)**: holds
  (PINS.md lines 100-139: "a silent miscompile" in both entries).
- **§5.2 M10 and W6, the lock came from a uniquing or mutating call on a
  read path**: holds; 98c6315c names `mutate` on the read path.
- **§5.2 E1, the 75 M attempts are what the any-op list does by design**:
  holds (3a96c407).
- **§5.4 item 3, the deduplicator's port replaced AsyncRT chains by waves
  by height**: holds (PINS.md, "AsyncRT's dependency chains are waves by
  height over the graph's components").
- **§5.6 B5, CIRCT's Arc made ffa91113's move three years earlier**:
  consistent with the history; ours was made only after a 627 GB kill.
- **§5.7 M5, frames and the specializer walls are "clones materialized
  before they are deduplicated"**: holds for frames (16005000's fix is one
  sum over result types).
- **§5.9 M2, the three fixes are "each a step towards MLton's model,
  taken one analysis at a time"**: holds; the same idea (marking a graph
  built once) was written three times in two days by one agent
  (b8301ebe, ffa91113, e96bb991) with no shared code.
- **§5.10 M6, "the commit messages of ffa91113 and e96bb991 ... suggest
  it is already this shape"**: holds: "one item per op, call, region
  successor and block that writes a value ... and a worklist marking"
  (ffa91113).
- **§5.8, "the `idr` dialect is a historical accident: it grew one case at
  a time"**: holds. The world type, `IOResource` and `CrashResource` date
  from the first WIP commit (045f8ed5, 09-26), `PerformsIO` from b36d104e
  (09-28), the body effect from 1cd1193a (10-15); `TakesReference` came
  in da66bd95 (10-19) and `BuildsValue` in 7987388b (10-20), each inside
  a fix (*measured* by pickaxe). `IdrOps.td` was the second most-changed
  file of the tree before the layout move (88 commits).

### 3.5 Wave-2 questions the history answers

- **§5.2 W6** (what took the lock in 98c6315c): the uniquer's `mutate`,
  called by the lazy readers `holdsReferences` and `holdsWorld`; now a
  `DataType::seal` writes each group once and reads are plain fields
  (98c6315c, *read*).
- **§5.2 W2, §5.7 "which patterns are not rooted", §5.9 Q-W9**: none at
  HEAD (7987388b); the three narrowing, retype and poison patterns were
  re-rooted "at each registered op but the ones with a pattern of their
  own", a generated per-op filing, not an interface.
- **§5.4 "every option that selects between two implementations"**: the
  history removed the one it built (scc-pipeline, 552d682a, struck by
  the owner in 57bf8e1d: "fallback/configuration slop"); 563ecc8b deleted
  38 dead knobs of 150 (*read*). Today's set is wave 2's driver lane's to
  count.
- **§5.6 W-E4** (facts in discardable attributes): 2295e06b's casework
  inventory found "seed marks in discardable attributes, fingerprints,
  per-round rebuilds" in the simplify rounds, after AGENTS.md had forbidden
  it (2f61af50, 09-29); the rounds are gone.
- **§5.6 W-E5** (budgets that fail): idr-simplify's `max-rounds` made a
  non-converging module "the error `unsupported (compile-time budget)`"
  (Passes.td at c7aa7b62^, lines 598-602) until c7aa7b62; the frontend's
  instance budget, "the last refusal by count", went by the owner's ruling
  (19fe1332). `Exclusivity::solve` "repeats while a label goes" (c4d38e9b).
- **§5.10 W4** (exclusivity's graph): one item per op, call, region
  successor and block that writes a value; each point control leaves read
  once (ffa91113, e96bb991); 1.3 s on 20,000 cases in a debug build.
- **§5.3 "what does `lib/Support/Scc.cpp` do that `scc_iterator` does
  not"**: it arrived with the layout cutover (1e1a3827); the call graph
  moved to `mlir::CallGraph` in the representation wave; its nine users
  are type, data, label and partition graphs (*measured*).
- **§5.1 W1, §5.7's stage-1 counts, §5.9 Q-W1 and Q-W3**: not in the
  history; the only stage-1 numbers are the frontend half's (450 to 528 s,
  6.5 GB, 71 MB, proposals/README.md) and the walls' samples.

## 4. Issues the history reveals

### 4.1 Every reversal of a design, and whose it was

"Owner" means the reversal cites a dated directive of the owner (in the
commit, the proposal it executes, or AGENTS.md's change); "agent" means no
directive is recorded and the commit is agent-written or agent-co-written.
All *read* from the commits named.

| design | introduced | reversed | reason given | whose |
| --- | --- | --- | --- | --- |
| C++ layout | `bjornpagen/cpp-starter` (AGENTS.md until 1e1a3827) → named C++20 modules, one concept per file (4cfce768, 0641826a, 10-03, `Claude`) | upstream's in-tree layout, no modules (1e1a3827, 10-12) | "an in-tree MLIR dialect in upstream's layout" | modules: agent; the return: owner's commit, no directive quoted |
| dead values | ours: idr-prune, idr-dead-values | upstream `remove-dead-values` (c018b2bc 10-06, 0451b1b8 10-09), then dropped (16005000, 10-20) | first upstream first; then whole-program liveness per value | first: owner's policy of 10-06 (7203ef2e); the drop: agent (Muse), no directive |
| exclusivity's engine | upstream `DataFlowSolver` (595ed341, 09-30, `Claude`/Fable) | a graph of our own, marked (ffa91113, 10-21) | 627 GB | both agent; no directive either way |
| Borrows' engine | a hand dependency solver | onto `DataFlowSolver` (2c042728, finding analysis-14) | upstream first | owner (packet approved 2026-10-17, "rip it") |
| the optimizer's driver | idr-simplify: canonicalize, CSE, SCCP, int-range, our passes and RDV in rounds to a fixpoint, `max-rounds` refusing | scc-pipeline behind an option (552d682a, agent), struck (57bf8e1d); then the fixed bottom-up optimizer (c7aa7b62) | F0's 447 s round and no fixpoint (2295e06b); "fallback/configuration slop" | the option's removal: owner ("Owner's call, 2026-10-14"); the cutover: proposal 0004 and 19fe1332's ruling |
| refusal by count | `unsupported (compile-time budget)` from `max-rounds`; the frontend's instance budget | termination by construction (bfdcac70 "no fuel", d06ed15c); AGENTS.md's rule (19fe1332) | acceptance is a property of the program | owner ("By the owner's ruling", 19fe1332) |
| static data's lifetime | `isStatic`, searched along the definition chain | a grade written once (467fa2f5, fc1a5daa, 4365c540, ccc9f4e7, WIP, `Claude`), taken out (c4d38e9b) | it graded a value static "from where it came instead of from what it holds" | both agent; still owed (0003, "The static lifetime in the grade") |
| memo exchange | `memo.enter`/`memo.settle` | `idr.memo.run` WIP (1715e261, `Claude`), reverted (be2fa9e7), re-committed (d5b45672), done (leaks.md status at 77eaa5b1) | the revert gives no reason | revert: owner (no agent trailer); the design: owner's leaks plan |
| array rank in data keys | none | roles per type-constructor argument WIP (0377cf24), reverted (43fc7b39), re-committed (d701b686, 8e65cf14) | none given | revert: owner |
| InlineCleanup | the 211 s cleanup | two refactors built and measured the same day, rejected ("7% slower A/B") and reverted (2295e06b) | measured slower | agent work, owner's record |
| the data type | a structural type printed with every body it reaches; mutable, lazily completed (`MutableType` first at c7aa7b62) | nominal, body once in the program's table (b9d4d592); declared once per pass (73bba53f); sealed per group (98c6315c), all 10-20 | the stage-1 walls | agent (Claude, Fable); 0003 records the owner's "we cannot have the binary format be read by hand" (10-19) for the table's encoding |
| compile-time evaluation | a JIT in the driver and runtime | gone (96e1d308, 1e1a3827) | kept the driver single-threaded | owner's commits, no directive quoted |
| specifications | normative docs | deleted, "the code is the specification" (64c03508, 09-28, `Claude`); findings/ deleted (9eaa1adb) | one fact, one place | agent, later AGENTS.md text |
| the LLVM pin | llvmorg-23.1.2 | main 7208ba24 (20fcfadb, 10-09) | the pin policy | owner's policy (AGENTS.md, memory) |

What the table shows (*conjecture*, reading it): the reversals that held
were owner rulings with a rule written down the same day (19fe1332,
57bf8e1d, 7203ef2e). The agent's own reversals of an engine (595ed341 →
ffa91113; 0451b1b8 → 16005000) each followed a wall and wrote no rule,
so the next agent had nothing to keep: the representation wave moved
Borrows *onto* the framework three days before exclusivity was moved
*off* it.

### 4.2 Recurring failure patterns of agent-written changes

Each names its commits; what the commits show first, the reading after.

1. **Adopt without a scale test, drop without a patch.** 595ed341 adopted
   the framework with a 0.84 s rbtree as its measurement; nothing ran it on
   a module of stage 1's size until stage 1 did, 21 days later; ffa91113
   then dropped it in one commit. 0451b1b8 deleted our dead-values pass for
   upstream's; four patches followed, the last two on 10-19; the pass went
   on 10-20. *Reading:* §4's order (upstream, upstream patched, ours) was
   applied at adoption and skipped at removal.
2. **Machinery that did not move the measured problem.** Two InlineCleanup
   refactors, built and measured slower, reverted (2295e06b); the
   scc-pipeline option "corpus verdict pending", its run cancelled
   (552d682a); upstream 28, 29, 62 and 63 built for a pass removed the next
   day (62902eff, 4dde6b7f, 16005000); "no fuel" (bfdcac70, d06ed15c) added
   89 worklists and 113 variant accesses (2.4) while every one of §3's
   walls was still there to be found.
3. **Waves integrated unbuilt, then fixed forward.** Four waves in five
   days landed as single commits typechecked but not built or run (2.3);
   the suite, 415/415 on 10-14, was 362/463 on 10-18 and is 470/480 now;
   4108916a ("Bug phase") and c4d38e9b ("Main green again") are the
   fix-forwards. *Reading:* the swarm optimized for disjoint write sets,
   not for a running compiler.
4. **WIP and A/B scaffolding on main.** 85 WIP commits, a lane policy that
   pushes them (9c30f058), two owner reverts of WIP; scc-pipeline's option
   "with the rounds kept as fallback" (57bf8e1d). 150 configuration knobs
   by 10-09, 38 dead (563ecc8b).
5. **The same files, fixed again within hours.** Exclusivity: ffa91113 then
   e96bb991 the same morning, and five more commits to
   `Analysis/Ownership` on 10-19..20 (e8e38bd7, d40d3c32, 467fa2f5,
   c4d38e9b, 276e8878). The data type: b9d4d592, 73bba53f, 98c6315c, one
   day. idr-frames: two WIP commits (0ddd15c1, 1595d9cd) then 16005000.
   *Reading:* each fix answered the run in front of it; none wrote the
   shared mechanism (§5.9 M2's "one analysis at a time").
6. **Bundled changes and stale records.** 16005000 removed upstream's
   `remove-dead-values` inside a frames commit and left PINS.md naming it
   as a site at four entries (lines 109, 130, 189, 290) and patches 06, 28,
   63 carried with nothing to reach; upstream/README.md's table has no row
   for 62 or 63 and its status is dated 10-15; the proposal's §2 lists the
   wrong RDV patches. AGENTS.md's procedure ("When nothing reaches the
   bug", upstream/README.md) was not followed.
7. **Representation-first written as `std::variant`.** "A sum, never a
   flag" landed in C++ as variants and `get_if` chains (2.4), the form
   §5.3 I3 and §5.5 D2 now ask to replace; the `isa<` ladders did not
   fall in any wave.
8. **Collateral edits.** 3b1909e7 deleted `Proof/AlmostFull.idr` by
   accident (660bb8ea restores it); b3dcf722 restores a removal "which the
   last commit undid".
9. **Walls found only by running stage 1.** Nine walls in two days
   (2.2); the scale fixtures came after each wall (e96bb991's generated
   20,000-case match; `tests/defunc-tag-limit` at 65,536 labels, added in
   d346040c), and the memory numbers are OS kills and samples, never a
   per-pass record (§5.11 A2).

### 4.3 The rederivation sweep (audits/rederived.md at 77eaa5b1) and its status

The owner asked for it on 2026-10-19 ("check the code base for any
inappropriate rederiving of values that we already knew at some point",
rederived.md's header). Five read-only sweeps over 374e0e77's parent; the
file was folded, nearly verbatim, into `proposals/0003-facts-once.md` by
91615083 and queued "after self-hosting" (0003's status, the owner's
deferral of 2026-10-19). *Measured* at HEAD with `git grep` (a symbol
present means the finding stands; the fix deletes it):

| 0003 / rederived.md item | probe | at HEAD |
| --- | --- | --- |
| term locations | 374e0e77 | done (374e0e77); `bestFC` fallback still 34 hits in `Translate/Terms.idr` and kin |
| C1 a let's type | `valueType` | present, `Translate/Terms.idr:261` |
| C2 a match's scrutinee type | `instanceOf` | present (8) |
| a leaf's clause number | `covers` | gone from `Forced.idr` (removing commit not identified) |
| B1 a block's parent | `outermost`, `rootOf`, `keyOrigin` | first two gone; `keyOrigin` present (5) |
| B3 imports, main path | `elaboratedFile` | present (3) |
| erased arguments, five readers | `erasedArgs`, `quantitiesOf` | present (9) |
| C3 constructor's type constructor | `conIdOf` | present (8) |
| B5 registry | `foreignHook` | present (7) |
| D1 Emit's use counts | `mostUses` | present (49) |
| static lifetime | `isStatic`, `madeStatic`, `Class::Phantom`/`StaticRead` | present (12, 9, 9) |
| MoveOut's second classifier | `doesOf` | present |
| `feeds()` ladder | `feeds(` | present |
| `knownNonEmpty` re-walk | | present (5) |
| frames' `closureLabels` | | present (3) |
| `givesBack` solved twice | | present (23) |
| `TypeGraph(op)` outside the manager | | present (3) |
| what an enclosing match says, three ways | `knownFromMatch`, `takenFromEnclosing` | present (6) |
| data body kind beside roles | `KindRule`, `RoleOnce`, `ruleOf` | present (7) |
| tblgen matches a record by name | `getName() == "Idr_` | present (1) |
| owned stage reads `memref::AllocOp` | | present, `Verify/Program.cpp` |
| exclusivity no analysis | `createRcCommit` by constructor | present (3) |
| optimizer restamps call effects | `writeCallEffects` | present (7) |
| no stack probes | `probe-stack` | absent (owed) |

Of 24 items probed, three are done (term locations, `covers`, the
parent's text parsing in part) and 21 stand. The sweep's second half (the
label solve, the leaks) was built the same day (7adc6095, da66bd95);
everything filed under "facts once" waits. *Reading:* the sweep is P0's
most direct input on "no rederivation chains", and it is unscheduled.

### 4.4 Issues

| ID | where | category | what | proposed disposition |
| --- | --- | --- | --- | --- |
| H1 | 595ed341, ffa91113 | upstream | the framework adopted with no scale test and dropped with no storage patch | §5.1 U1 (QA1) measured on a stage-1-sized module before any solver of ours replaces a framework user |
| H2 | 16005000; `PINS.md:109,130,189,290`; `upstream/{06,28,63}/llvm.patch` | upstream, dead | patches carried with nothing to reach; PINS.md names a pass that does not run | after QA3: either the per-function RDV returns and they stay, or each becomes `pull-request.diff` by upstream/README's procedure |
| H3 | `upstream/README.md:54-114` | list | no rows for 62, 63; status dated 10-15 | regenerate the table from the directories (one source) |
| H4 | `upstream/README.md` table | upstream | no LLVM patch of about 25 has been filed (the one thing sent is 01's test, as a comment on #208881, PINS.md:549-551); "ready" and "ready to file" rows date from 10-08..10-19; the owner ruled out local LLVM builds (10-09), so a PR rests on LLVM's CI | P0's plan names a sending step per patch it depends on (Q-E5) |
| H5 | c7aa7b62^ `Passes.td:598-602` | budget | a round budget that refused, until c7aa7b62 | fixed; P0's solver layer keeps AGENTS.md's rule (Q-llvm-2, Q-E3) |
| H6 | c7aa7b62, bfdcac70, d06ed15c, 1cd1193a, 2c042728 | process | waves typechecked, not built; suite never green since 10-14 | P0's steps each build and pass on the build machine before the next (§5) |
| H7 | 9c30f058; 85 WIP commits; 43fc7b39, be2fa9e7 | process | WIP pushed to main as policy | no WIP on main during the cutover |
| H8 | 552d682a, 57bf8e1d; 563ecc8b | process | A/B options frozen into main | no option selects an implementation (owner, 10-14) |
| H9 | c7aa7b62 (`MutableType`), b9d4d592, 73bba53f, 98c6315c | state | a mutable, lazily completed type made in a wave, three walls on one day | §5.8 DS3 decides the table's form once, with the measurement |
| H10 | d06ed15c, 2c042728 | cpp | variants 4 → 60, accesses 9 → 192, worklists 1 → 87 across two waves | §5.5 D2's `match` and §5.3 I6/I7 as cutover rules; measure the `get_if` share |
| H11 | 1e1a3827..d06ed15c | ladder | `MatchAnyOpTypeTag` patterns added by waves (3 → 7) | gone; P0 forbids any-op roots (§5.2 design 2) |
| H12 | `proposals/0003-facts-once.md` | rederivation | 21 of 24 probed items stand | P0 takes 0003 whole or names what it leaves (§5) |
| H13 | c4d38e9b | rederivation | static lifetime reverted; `isStatic` re-walks chains per reader | 0003's design, with its acceptance (IdrRcGrades near 3.5 s) |
| H14 | 045f8ed5, b36d104e, 1cd1193a | attribute, ladder | "does IO" held three ways since week one, a fourth reader added in 0014-sound | §5.8 DS2 (DD-Q3, ods-Q2) |
| H15 | da66bd95, 7987388b | dead | traits added inside fixes, read once or never (`TakesReference`, `BuildsValue`; §2) | ods-effects lane |
| H16 | 2c042728 (analysis-14); `Borrows.cpp:298` | upstream | Borrows moved onto a whole-program `DataFlowSolver` three days before exclusivity left it | measure at stage 1 before P0 decides its engine |
| H17 | b8301ebe, ffa91113, e96bb991 | ladder | one idea (a graph built once, marked) written three times with no shared code | §5.3 S1 / §5.6 design 1: one marking |
| H18 | 16005000 | process | an upstream pass removed inside an unrelated commit | each removal its own commit, with its records |
| H19 | 660bb8ea, b3dcf722 | process | collateral deletions by agents | review gate per step |
| H20 | the walls of 2.2 | process | memory known only from OS kills and samples | §5.11 A2's per-pass footprint record before the cutover's first step |

## 5. What P0's plan must do differently

### 5.1 The lessons, each on its commits

Each lesson: the commits; what they show; the change to P0 (the skill's
one line: what becomes unrepresentable, the check moved to a boundary, or
the branch deleted).

- **L1. Measure an upstream mechanism at our scale before it is adopted,
  and patch it before it is dropped.** 595ed341 (adopt, rbtree 0.84 s),
  ffa91113 (drop, 627 GB, no storage patch); 0451b1b8 (adopt RDV, ours
  deleted), 62902eff and 4dde6b7f (patches), 16005000 (drop the next day).
  *Change:* every step of §7 that adopts, keeps or removes an upstream
  mechanism carries a measurement on a stage-1-sized input (the generated
  20,000-case match of e96bb991, defunc-tag-limit's 65,536 labels, and the
  stage-1 module itself), and a removal carries either the upstream patch
  that was tried or the measurement that shows the state is essential to
  the problem (§4's header line for the solver layer, made a gate). *Line:*
  the check moves to the step's boundary; "dropped because it ran out" is
  no longer a reason a commit can give alone.
- **L2. One cutover, but every step built, run and green before the
  next.** The four waves of 10-14..18 typechecked and did not run; the
  suite has not been green since 10-14 (2.3). *Change:* P0's §7.3 orders
  steps that each pass `make check`, `make test`, `make test-idr`,
  `make test-unit`, `make test-mlir-tools` and a stage-1 pipeline run on
  the build machine, with no WIP on main and no option selecting an old
  path (H6-H8). "Hard cutover" is per step: the step deletes what it
  replaces; it does not wait for the next step to compile. *Line:* a
  half-landed cutover becomes unrepresentable on main.
- **L3. A representation is decided once, with its measurement, and every
  reader moves with it.** `!idr.data` was made mutable and lazy in a wave
  (c7aa7b62) and paid three walls on one day (b9d4d592, 73bba53f,
  98c6315c); the static lifetime was cut over and taken out on one day
  (467fa2f5 … c4d38e9b). *Change:* the dialect redesign (§5.8) decides
  the data table, the grade and the world from the owner's answers to
  DS1-DS3, before any lane writes C++ against them, and states each one's
  cost per program unit (§5.11 A1).
- **L4. A mechanism found by one fix is written once, as the mechanism.**
  The graph-marking idea was written three times in two days (b8301ebe,
  ffa91113, e96bb991), and its quadratic graph build within three hours of
  the first. *Change:* the solver layer's graph and marking (§5.3 S1,
  §5.6 design 1, §5.9 design 1) are built first, with the linear graph
  build as a tested property (one interface query per op), and the three
  existing markings are ported onto it in the same step. *Line:* the
  per-pair query becomes unwritable in a client.
- **L5. Records are part of the change.** 16005000 left PINS.md and three
  patches describing a pass that no longer runs; upstream/README.md lacks
  62 and 63; §2 of the proposal repeats a stale patch list. *Change:* each
  P0 step updates PINS.md, `upstream/` and the proposal in the same
  commit, and the upstream table is generated from the directories (one
  source). *Line:* the drift becomes a build or check failure.
- **L6. Representation-first in C++ is not `std::variant` everywhere.**
  The "termination by construction" and representation waves added 55
  variants and 183 accesses (2.4) without lowering `isa<`. *Change:* the
  cutover's C++ rules (§5.3 I1-I8, §5.5 D1-D3) are written before the
  C++ is churned, with the interface-or-concept line (§8 Q1) settled first.
- **L7. The footprint is a record, not a kill.** Every wall was found by
  jetsam or a sample (2.2, §5.11 O1). *Change:* §5.11 A2's per-pass
  footprint record and A3's named death land before the first solver is
  rewritten, so each step's measurement in L1 exists.
- **L8. Rules written the day of a reversal hold; agent reversals without
  one recur.** 19fe1332, 57bf8e1d and 7203ef2e held; the engine reversals
  of 4.1 left no rule and were contradicted within days. *Change:* every
  P0 decision that reverses an earlier design names the owner's dated
  ruling in §9 and in its commit; an agent may not reverse a recorded
  design on its own (memory: "Loop the owner in").

### 5.2 Changes to P0's plan

1. **§3 is corrected** by 3.1 (the RDV patches carried at the drop were 06,
   28, 29, 63; the 52 GB is a sample) and completed by 3.2 and 3.3.
2. **§7.3 gets a gate per step** (L1, L2, L7): build, the five suites,
   a stage-1 pipeline run with the footprint record, and the step's
   measurement; no WIP, no option, no "typecheck machine" landing.
3. **§7's first steps are infrastructure, in this order** (*conjecture*,
   from L1, L4, L7): the footprint record and scale fixtures; the upstream
   storage patch U1 measured against today's three framework users of
   whole-program scope (Ranges, Borrows, Returned); the solver
   layer's graph and marking with the existing markings ported; only then
   the dialect redesign's passes.
4. **0003 is folded into P0 or explicitly deferred item by item** (4.3):
   21 rederivations stand, and P0's goal "no rederivation chains" is
   otherwise unmet by construction.
5. **Upstream sending is scheduled** (H4): each patch P0 depends on (62,
   06/28/63 if RDV returns, U1-U3) gets a sending step; Q-E5's RFCs are
   recorded as upstream work.
6. **The orphaned records are settled with QA3** (H2): retire 06, 28, 63
   by upstream/README's procedure or bring the per-function RDV back.

### 5.3 What each wave-2 lane should know from history

- **01 ods-types.** `!idr.q` arrived 09-30 (ea85a95d) and has changed in
  18 commits; `Idr_Lifetime` only on 10-19 (da66bd95). The mutable
  `!idr.data` came with the pipeline cutover (c7aa7b62) and cost three
  walls on 10-20 (b9d4d592 printing, 73bba53f the O(N²) table with the
  verifier re-run per remake, 98c6315c `mutate` on reads); `DataType::seal`
  is the fix of record. The static lifetime as a grade was tried and taken
  out (c4d38e9b: graded "from where it came instead of from what it
  holds"); 0003 holds the design that should replace `isStatic`. The data
  body's kind beside roles (`KindRule`) is a representation-wave leftover.
- **02 ods-effects.** "Does IO" has been three facts since week one
  (`IOResource` and the world type in 045f8ed5, `PerformsIO` in b36d104e),
  and 0014-sound added a fourth reader, the body effect (1cd1193a, "one
  effects rule read by analysis and verifier"). `ObservableIO` came in a
  checkpoint (5677cd90), `TakesReference` and `BuildsValue` inside fixes
  (da66bd95, 7987388b). 880ec272 (10-01) made a call answer
  `MemoryEffectOpInterface`; the representation wave planned to delete 11 hand
  `getEffects` (packet §5); the effect tokens fell from 151 to 124 in its
  commit (2c042728) and are 155 at HEAD (2.4). The crash-site
  count and the crash effect already disagree (0003, representation
  leftovers).
- **03 ods-ops.** `IdrOps.td` was changed in 88 commits before the layout
  move, one case at a time (§5.8's "historical accident" is literal). Ops
  were added and deleted by waves (the representation wave's packet lists
  its op changes per lane); `idr.memo.run` was reverted once by the owner
  and re-landed (be2fa9e7, d5b45672). The `!idr.token` without its cell is
  in 0003.
- **04 canon.** Every `MatchAnyOpTypeTag` was added by a wave and removed
  on 10-20 (3a96c407, 7987388b); patch 62 is the greedy driver's on
  many-region ops; the stage-1 run hit "a rewrite cycle between
  case-of-case and yield-fields" (proposals/README.md); 0003 lists three
  copies of "what an enclosing match says" and MoveOut's second effect
  classifier.
- **05 analyses.** The framework users at HEAD are Constants, Ranges,
  Borrows, Narrow, Returned and Effects/Constants; Borrows was moved
  *onto* it by the representation wave (analysis-14); int ranges went per
  function in 5d3318fb (3 s against 30 s in our notes). Nothing in the
  history measured any of them at stage 1. `Scc.cpp` dates from 1e1a3827;
  the call graph moved to `mlir::CallGraph`, nine other graphs did not.
- **06 defunc.** The label solve was rebuilt on 10-19 (7adc6095) with an
  old-against-new differential over 314 solves before the old was deleted:
  the history's best-run representation change, a model for P0's. The
  table rebuild per declaration (73bba53f) and the printing digest
  (b9d4d592) were defunctionalize's stage-1 walls; 6a7841dc made labels
  one walk.
- **07 ownership-analysis.** Exclusivity went framework (595ed341) →
  marked graph (ffa91113) → linear graph build (e96bb991) in three weeks;
  "Exclusivity solved twice" and "no analysis" (handed to `createRcCommit`
  by constructor) are in 0003. Borrows is on a whole-program solver now.
  Captures, Reuses, Uses, Values: §5.10 M2, M7, M8 ask questions the
  history cannot answer.
- **08 counting.** idr-rc-stack's per-value bit vectors were the 47 GB wall
  (b8301ebe); idr-rc segfaulted pairing a dead fieldless constructor
  (9982cae8); grades are placed before any verifier runs on a half-graded
  program (4c87dcc5); the static lifetime revert (c4d38e9b) left
  `Class::Phantom`, `Constant`, `StaticRead`.
- **09 optimize.** The simplify rounds (canonicalize, CSE, SCCP, int-range,
  RDV, a refusing round budget) were replaced by the fixed bottom-up
  optimizer (c7aa7b62) after F0's 447 s round (2295e06b); two InlineCleanup
  refactors and an scc-pipeline option were rejected; the any-op patterns
  and the context lock were its stage-1 walls. 0003: it rescans each wave
  and restamps call effects per round.
- **10 tail.** idr-frames' per-pair clones were the 43 GB wall (16005000);
  the frames-over-a-cycle work landed as two WIP commits (0ddd15c1,
  1595d9cd); `givesBack` is solved in the optimizer and again in
  `Tail/Returned` (0003); TRMC grew on 10-19 (0c98b266).
- **11 arrays.** Bufferization runs on upstream's One-Shot with patch 24
  (27 uncarried); the arrays-refused audit (601a85ea) led to the
  role-per-argument WIP the owner reverted (43fc7b39) and re-landed; patches
  56, 57 on linalg's index op.
- **12 conversion.** Patches 60, 61 (aliases, sqrt) and 30 (AArch64
  sibcall) sit near the lowering; 0003 lists hand decodes of the small word
  and an un-lowered function facts list (`willreturn`, `memory`); no stack
  probes (absent at HEAD; §5.11 B2).
- **13 driver-pipeline.** `Pipeline.cpp` changed in 12 commits since
  1e1a3827, five of them waves; the verifier after every pass multiplied
  73bba53f's quadratic; nested pipelines once could not read the symbol
  table (25890d32); the owner ruled out local LLVM builds on 10-09, so a
  toolchain patch rests on CI and on `tools/bootstrap.sh` (63 and 62 were
  "tested on a private build ... not yet built into the toolchain").
- **14 idris-dialect-side.** b9d4d592 made the data table "one ODS record
  on both sides" after the owner's "we cannot have the binary format be
  read by hand" (10-19); `idris-mlir-tblgen` still matches a record by
  name (0003). `Dialect/Idr.idr` is among the most-changed Idris files
  (45).
- **15 frontend-translate.** `Translate/Terms.idr` (41) and `Types.idr`
  (39) are the most-churned Idris files; most of 0003's items (C1-C5,
  B1-B7, D1) are here and stand (4.3), rooted in the fork's lossy TTC.
- **16 frontend-checks.** The growth rule was replaced by the polymorphism
  checker (3fc4d2e4); the instance budget, the last refusal by count, went
  by the owner's ruling (19fe1332); totality was narrowed to where a
  normaliser runs definitions (1cd1193a).
- **17 fork-boundary.** Seventeen Idris changes are carried as fork code
  because Idris takes no tool-written contribution (upstream 18, 20, 21,
  50-55, 59 and seven `fork-*`); 374e0e77 made the TTC keep term
  locations; C1, C2 and B1 of 0003 are fork-side.
- **18 runtime.** `runtime/idris_rt.h` changed in 47 commits; the JIT and
  compile-time evaluation left the runtime (96e1d308, 1e1a3827); patches
  48, 49 (simdutf, snmalloc) are uncarried submissions.
- **19 tests-harness.** The suite was purged and rewritten (d346040c), about
  300 brittle checks deleted (1cd1193a), and audited in 19 files on 10-18
  (SUMMARY.md); it has not been green on `make test` since 10-14; the
  scale fixtures that would have found §3's walls (a 20,000-case match,
  65,536 labels) were added after the walls.

## 6. Evidence for the owner's questions

No answers; what the history holds, by ID.

- **QA1 (patch upstream's state storage first; P1 or P2).** No patch to
  the framework's state storage was ever written: the only patch on
  `DataFlowFramework.h` is 05 (callee lookup), and the 627 GB drop
  (ffa91113) tried none (3.1). The memory numbers the proposal cites were
  taken on the unpatched framework: 627 GB footprint at a jetsam kill,
  52 GB sampled. Our patch cadence: 28 and 29 were written and carried the
  same day (62902eff); 62 and 63 were "tested on a private build of the
  pinned source ... not yet built into the toolchain" (4dde6b7f, PINS.md
  lines 179-181, 196-198), because the owner ruled out building LLVM
  locally on 2026-10-09 (upstream/README.md "Status"), so a storage patch
  reaches the tool only through `tools/bootstrap.sh` on the build machine.
  None of about 25 LLVM patches has been filed upstream (H4), so "likely
  quick upstream" (P1) has no precedent here either way. Three framework
  users today solve the whole program or module (*read*: Ranges,
  `Ranges.cpp:74-76`, on the program with the baseline loaded; Borrows,
  `Borrows.cpp:298-303`, on the program; Returned, `Returned.cpp:153-158`,
  on the lowered module), none measured at stage 1.
- **QA3 (`remove-dead-values`: split, or whole module patched).** History
  of the pass: adopted in the simplify loop (2ab5adf9, 09-28), where it
  crashed on a private self-recursive function unless symbol-dce ran first;
  our idr-prune and idr-dead-values deleted in its favour (c018b2bc,
  0451b1b8); seven patches over its life (01, 06, 16, 22, 28, 29, 63), two
  for silent miscompiles on our IR (28: `idr.array.yield` forwards nothing;
  29: every program is a nested symbol table), one for 87 s at 4k cases
  (63); 52 GB sampled on stage 1; dropped by 16005000, whose message says
  the signature half is "decided where demand is decided, in the
  optimizer's specialization, and what it leaves in place counting drops
  like any other dead owned value". So the interprocedural half already
  has an owner of ours, and the intraprocedural half has no user now.
  Patches 06, 28, 63 are still carried for it, and PINS.md still names it
  as their site (H2).
- **Q-E5 (two upstream RFCs, sent separately).** Our record of sending: one
  test posted as a comment on llvm/llvm-project#208881 (2026-10-08, PINS.md
  "remove-dead-values-address-taken"); no LLVM pull request or issue filed;
  every row of upstream/README.md's table reads "ready", "ready to file",
  "not filed" or "carried" (*read*, lines 77-114). Idris takes no
  tool-written contribution (upstream/README.md), so seventeen Idris
  changes stay fork code; simdutf wants a human author and snmalloc a CLA
  (rows 48, 49). An RFC is a larger social step than any sent so far.
- **Q-M4 (port more of Modular).** The one port, Modular's
  `EliminateDuplicateFunctions` (234b81a0, 10-14, owner-authored, 13
  files, 635 lines), was documented in PINS.md with its changes
  (waves by height in place of AsyncRT's chains, our own equivalence) and
  its retirement condition (an upstream generalization "planned ... not
  written"). Since then it has been touched only by the waves' sweeping
  changes (c7aa7b62, bfdcac70, d06ed15c, 1cd1193a, 2c042728) and by no fix
  of its own (*measured*: `git log -- foreign/idr/lib/Transforms/Deduplicate`).
  The deviation §5.4 item 3 flags (barrier per wave) is the port's own
  choice, recorded. The upstream-side follow-up the port promised was not
  written.
- **Q-E4 (port from CIRCT and IREE).** No code of CIRCT or IREE was ever
  ported (*measured*: no `circt` or `iree` path in PINS.md or in any file
  header, `git grep -il 'circt\|iree' -- foreign/idr` finds none). The
  licence handling exists (the Modular port's PINS.md entry, LICENSES/ from
  3a275cf0). The history's one related lesson: the port that succeeded was
  of a self-contained pass with a property test; the engines that churned
  (exclusivity, RDV) were adoptions of frameworks.
- **Q-llvm-2, Q-E3, oom-2 (budgets).** The one budget that refused
  (idr-simplify's `max-rounds`, "unsupported (compile-time budget)") and
  the frontend's instance budget were removed by the owner's rulings
  (19fe1332, 10-14); AGENTS.md's rule dates from that commit. "No fuel"
  (bfdcac70) followed. `Exclusivity::solve` "repeats while a label goes"
  (c4d38e9b) is the one loop since stated by its end.
- **ods-Q6, Q-M2, Q-O5 (verification).** The verifier after every pass
  turned 73bba53f's table rebuild into "the dev build verifies every member
  of each remake"; 4c87dcc5 had to place grades so "no verifier runs on a
  half-graded program". No measurement of the verifier's share at stage 1
  exists in the history.
- **ods-Q2, DD-Q3 (the world, effects from types).** The world type and
  `IOResource` were both in the first WIP commit (045f8ed5, 09-26) and
  have coexisted since; `PerformsIO` was added two days later (b36d104e),
  the body effect on 10-15 (1cd1193a). No commit records a decision to
  keep both.
- **QL4, Q-llvm-6 (determinism).** 3dbf0e2f (10-13) required each
  compile-time stage to land "only if measured faster, byte-identical and
  deterministic at 1/2/8 threads"; the waves that followed were not built,
  so the rule was not applied to them.
- **Q2 (self-hosting during P0).** Every wall of §3 was found by running
  stage 1's pipeline half, one per run, two days running (2.2); none was
  found by a fixture first.
- **DD-Q8 (renames).** Names have churned with every wave (the layout
  move, the representation wave's lanes); `SpecKeyAttr`'s `origin` means
  the owner while `Node::origin` means the function (0003): renames have
  been cheap and drifting.

**New questions for the owner.**

- **NQ1.** Should P0 make L1 a rule (AGENTS.md or §4): an upstream
  mechanism is adopted only with a measurement at stage-1 scale, and
  removed only with the upstream patch tried or the measurement that the
  state is essential? The history has one adoption (595ed341) and two
  removals (ffa91113, 16005000) that would each have failed it.
- **NQ2.** May P0 land as typechecked, unbuilt waves, as 10-14..18 did, or
  must every step build and pass the five suites and a stage-1 run on the
  build machine before the next (L2)? The suite has not been green since
  those waves.
- **NQ3.** Patches 06, 28 and 63 reach nothing today: retire them now by
  upstream/README.md's procedure, or hold them until QA3 is answered?
- **NQ4.** 0003 (facts once) is queued after self-hosting, P0 before
  self-hosting, and P0's goal includes "no rederivation chains": does P0
  absorb 0003, or does P0 leave the 21 standing items (4.3) for later?
- **NQ5.** May an agent reverse a recorded design (an engine, a type's
  representation) without a dated ruling from you, as 595ed341 → ffa91113
  and the static-lifetime cutover were?

## 7. Deletion list

The history lane owns no code; these are what the history marks dead or
stale, for the owning lanes and the owner (NQ3) to decide.

- `upstream/06-remove-dead-values-unreachable/llvm.patch`,
  `upstream/28-liveness-non-forwarded-terminator/llvm.patch`,
  `upstream/63-liveness-trivially-dead/llvm.patch`: carried, reaching no
  pass of ours since 16005000 (no `LivenessAnalysis` or
  `remove-dead-values` user at HEAD, *measured* by `git grep`). By
  upstream/README.md "When nothing reaches the bug": each becomes
  `pull-request.diff`, its PINS.md entry goes, its `tests/upstream-*`
  check turns to "the pin still has the bug". Unless QA3 brings the
  per-function pass back.
- `PINS.md`: the "sites" lines naming `remove-dead-values` in
  `Pipeline.cpp` (lines 109-111, 130-131, 189-190, 290-291); `upstream/29`'s
  entry keeps its second site ("every analysis on MLIR's solver that loads
  DeadCodeAnalysis").
- `upstream/README.md`: the hand table (lines 77-114) as a second copy of
  the directories, already missing 62 and 63 and dated 10-15; generate it.
- `proposals/0000-mlir-native.md` §2: "four on `remove-dead-values` (01, 06,
  16, 22)", to read 06, 28, 29, 63 (the coordinator's edit, not this lane's).
- Whatever P0 replaces in 0003's 21 standing items (4.3) goes with its
  symbol (`valueType`, `instanceOf`, `keyOrigin`, `isStatic`, `doesOf`,
  `feeds`, `KindRule`, `writeCallEffects`, ...), by the owning lanes.

## 8. Risks, unknowns, measurements needed

- **The largest risk the history shows: a cutover that lands before it
  runs.** Every wave of 10-14..18 landed typechecked and unrun, and the
  suite has not recovered (2.3); P0 is larger than all of them together
  (§1: every `.td`, every effect, the dialect whole, the C++ restyled).
  If P0 lands the same way, the fix-forward will run into stage 1's walls
  and the waves' regressions at once, and the history says fix-forward
  under a wall drops upstream mechanisms instead of patching them (4.2,
  items 1 and 3).
- **The second: adopting upstream again without the measurement.** P0's
  first preference is upstream; 595ed341 and 0451b1b8 were upstream-first
  too. Without L1's gate the cycle (adopt, run out at stage 1, drop) can
  repeat for every analysis §5.1 item 2 sends back to the framework.
- **Attribution is incomplete.** Owner directives are rarely quoted in
  commits (*measured*: grepping every body for "the owner" finds five
  commits, one a false match; 57bf8e1d's "Owner's call" is a sixth); most
  decisions live in proposals since deleted.
  4.1's "owner or agent" rests on the commit text, the proposal of the
  day, and the trailers; an owner decision made in conversation and never
  written is invisible here.
- **Unknowns the history cannot settle:** the stage-1 counts (§5.1 W1);
  whether Borrows, Ranges and Returned survive stage 1 on the framework;
  the verifier's share of each pass; whether the dedup port's waves idle
  threads (§5.4); what the full `make test` is at HEAD (the last full run
  recorded is 470/480 at ffa91113).
- **Measurements this lane could not make** (no builds allowed): the
  footprint per pass on stage 1; U1's effect on 595ed341's design
  (re-running exclusivity on the patched framework at stage 1 would say
  whether ffa91113 was forced or chosen).
- **Commands used for every count** are given beside each count; the
  history lane ran only `git log`, `git show`, `git ls-tree`, `git grep`,
  `git rev-list`, `git merge-base` and file reads.

## 9. Sources read

- `.claude/skills/representation-first/SKILL.md` (whole); `AGENTS.md`;
  `proposals/0000-mlir-native.md` (whole, §0-§9, every lane's section; §3,
  §5.1, §5.4, §5.6 closest); `proposals/0003-facts-once.md` (whole);
  `proposals/README.md` (whole); `audits/p0/README.md`.
- `PINS.md`: section list (all headings), and in full the entries
  liveness-non-forwarded-terminator, dead-code-nested-symbol-use,
  greedy-multi-region-ancestors, liveness-trivially-dead,
  remove-dead-values-unreachable, remove-dead-values-address-taken,
  forward-dataflow-callee-lookup, eliminate-duplicate-functions, and lines
  67-70.
- `upstream/README.md` (layout, status, the table, "When nothing reaches
  the bug"); the patch and diff listing of every directory; the headers of
  `upstream/05-forward-dataflow-callee-lookup/llvm.patch`.
- Audits at 77eaa5b1: the file list and sizes; `rederived.md` (first 140
  lines, and the rest through 0003, which carries it); `label-solve.md`
  (head and status); `leaks.md` (head and status); `machinery.md` (head);
  `SUMMARY.md` and `gaps.md` (section headings).
- Deleted proposals: `proposals/0004-representation/README.md` at 77eaa5b1
  (status, invariants, §3 rows, §5 "Library first", S3); the file lists at
  d346040c, 2d9290b5 and 77eaa5b1.
- `foreign/idr/include/idr/Transforms/Passes.td` at c7aa7b62^ (idr-simplify);
  `foreign/idr/lib/Transforms/Pipeline.cpp` (pass list at HEAD);
  `foreign/idr/lib/Analysis/Ranges.cpp:60-80` (the solve's scope).
- Commits read in full or in their messages: 0948fbf4, d79c9714, 045f8ed5,
  2ab5adf9, 595ed341, 64c03508, b36d104e, 4cfce768, 0641826a, 880ec272,
  fc7dc230, 7203ef2e, 20fcfadb, 327c2e30, 563ecc8b, 9eaa1adb, 0451b1b8,
  c018b2bc, 96e1d308, 25890d32, 1e1a3827, 3dbf0e2f, 2c89226a, 2295e06b,
  552d682a, 57bf8e1d, 234b81a0, 5d3318fb, c7aa7b62, bfdcac70, d06ed15c,
  1cd1193a, 19fe1332, 3b1909e7/660bb8ea, b3dcf722, 1e5a8a8e, 2c042728,
  d346040c, 4c87dcc5, 374e0e77, 62902eff, 4dde6b7f, 7adc6095, da66bd95,
  467fa2f5, fc1a5daa, 4365c540, ccc9f4e7, c4d38e9b, 1715e261, be2fa9e7,
  0377cf24, 43fc7b39, 4af38372, 9c30f058, 4108916a, 6f774119, 91615083,
  b9d4d592, 73bba53f, 98c6315c, 3a96c407, 7987388b, 16005000, b8301ebe,
  ffa91113, e96bb991.
- Whole-history queries: `git log --stat`, `--shortstat`, `--name-only`,
  pickaxe (`-S`) for `DataFlowSolver`, `RemoveDeadValues`,
  `MatchAnyOpTypeTag`, `sccp`, `int-range-optimizations`, the pass
  constructors of 3.3, the trait and resource names of 3.4, AGENTS.md's
  rules; `--grep` for remove-dead-values, WIP, checkpoint, revert,
  typecheck machine, owner attributions; `git grep -c` at the eight
  commits of 2.4.
