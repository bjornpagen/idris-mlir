# The cutover swarm: 0004's pipeline and 0003's stage 1, one wave

**What this is.** The executable packet for one hard cutover that lands
0004's design (`README.md` here) and 0003's stage 1 (`../0003-typed-apl/README.md`)
together, by the owner's decision of 2026-10-14. It is the last wave: every
lane starts at dispatch, all at once; there is no foundation step, no
prerequisite wave and no ready queue. Every declaration two lanes share is
fixed in `contracts.md` by name and shape, so a consumer writes against the
contract while the owner writes the file. After the lanes come only the
coordinator's integration and qualification.

**Engagement contract** (observed 2026-10-14, at `main`, clean tree):
- Checkout: `/Users/bjorn/Documents/idris-mlir`, branch `main`, one tree, no
  worktrees or branches (the owner's standing rule).
- Compatibility: none owed to any mechanism the packet replaces; no user
  data exists.
- Targets: x86_64 Linux and arm64 macOS (AGENTS.md); this machine is arm64
  macOS with no stage-2 LLVM.
- Verification timing: lanes run only `check-units.py` and private-build-dir
  Idris typechecks; the coordinator runs `make typecheck` and `make check` at
  each integration point; `make build` and the suites run later on the
  owner's machine, which is where qualification happens.
- Commits: lanes never commit; the coordinator commits and pushes to `main`
  at each green integration point (`make typecheck` and `make check` clean).
- Deletions: everything 0004 §6 and 0003 §15 list, and every retired
  mechanism below.
- Release prerequisites: none; this is not a release.

**Concurrency.** Nineteen lanes, all ready at dispatch. The owner asked for
at least twelve running at once. The workflow tool on this 8-CPU machine
runs six at a time; lanes are therefore dispatched as direct background
agents, all in one message, and the coordinator records how many the
environment actually ran at once. A lane the environment queues is queued
for capacity, never for a dependency: nothing in any part waits on another.

## Lanes and the ready frontier

Every lane consumes only `contracts.md` and the live tree; none consumes a
sibling's output file. Write sets are disjoint (`ownership.json`;
`validate.sh` proves it).

| Lane | Outcome | Writes (summary) | Produces (contracts.md) | Consumes |
| --- | --- | --- | --- | --- |
| U01 | IR core: identified data types, inherent facts, the root, refusals as data | `include/idr/IR`, `lib/IR` but arrays and flow files; `idris-mlir-tblgen.cpp`; `Rule.idr`, generated `Dialect/`, `Syntax/` | C01 types, C02 inherent facts, C03 root and verifier, C04 rule enum | C05, C11 |
| U02 | Total defunctionalization | flow interface files; `Analysis/Labels*`; `Defunctionalize/` but `ByName.cpp`; `Isolate/` deleted | C05 flow interface, C06 label solve and sums | C01, C02, C03, C07 |
| U03 | The ready-set optimizer and inliner | `Transforms/Simplify` deleted, `Transforms/Optimize` new, `Inline/`, `Identity/`, `Analysis/Inline`, `References`, `Holds`, `Canonicalize.h`, `Support/Scc` | C07 ready set, C08 inline decisions | C01, C06, C09, C10 |
| U04 | Specialization as content-keyed nodes | `Transforms/Specialize`, `Analysis/Specialize`, `BindingTimes`, `Identities*` | C09 specialization nodes | C01, C07, C10 |
| U05 | Effects and constants as SCC summaries | `Transforms/Effects`, `Analysis/Effects`, `Analysis/Constants` (new), `Defunctionalize/ByName.cpp` | C10 summaries | C01, C06, C07 |
| U06 | The pipeline, the driver, the options that go | `lib/Driver` but `Artifacts.cpp`, `include/idr/Driver` but `Artifacts.h`, `Pipeline.cpp`, `Passes.td`, `Support/Profile`, `Actions`, the three tools, `tools/compile.sh` | C12 pass registry and pipeline order | every pass's create function (C05 to C11, C13 to C15, C23) |
| U07 | Code generation in size-balanced units | `lib/Target`, `include/idr/Target`, `Driver/Artifacts` | C13 partition and parallel codegen | C01, C12 |
| U08 | Memory: counting, stack, in-place as a type fact | `Ownership/`, `Stack/`, `Demand/`, `Analysis/Ownership`, `Escapes*` | C14 memory facts | C01, C02, C15 |
| U09 | Tail, narrowing; in-bounds and vectorize deleted | `Tail/`, `Narrow/`, `InBounds/`, `Vectorize/`, `Analysis/Ranges`, `Analysis/Tail` | names from content for `.acc`, `.trmc` | C01, C02, C12 |
| U10 | Lowering, memrefs from bufferization | `lib/Conversion`, `include/idr/Conversion` | C16 lowering contract | C01, C02, C11, C15, C17 |
| U11 | Array ops MLIR-first | `IdrArrayOps.td`, `OpsArrays.cpp`, `Transforms/StructureLoops` (new) | C11 array ops and `idr.tie_shape` | C01, C05 |
| U12 | One-Shot bufferization on `idr.func` | `Transforms/Bufferize` (new) | C15 bufferization pass and models | C01, C11, C18 |
| U13 | The array library and its users | `libs/`, the fork's `Table.idr`, five bench programs | C19 library surface | C20 |
| U14 | Frontend translation | `compiler/src/IdrisMLIR/Frontend`, `Registry`, `Facts`, `Graph`, `Term`, `Types`, `Ids`, `Loc`, the ipkg | C20 recognition and request chains, C21 names | C01, C04, C11, C19 |
| U15 | Emission | `Emit.idr`, `Emit/`, `MLIR.idr`, `MLIR/`, syntax samples | C22 emitted module | C01, C04, C11, C21 |
| U16 | Upstream patches and the Modular port | `upstream/`, `PINS.md`, `tests/upstream`, `Transforms/Deduplicate`, `LICENSES/THIRD-PARTY.md` | C18 patched upstream APIs, C23 deduplication | C01 |
| U17 | The dialect suite and property checks | `tests/idr`, `Transforms/Expect` | C24 expect properties | every contract |
| U18 | Programs, rejections, toolchain, spec | the rest of `tests/`, `bench/run.sh`, `report.sh`, `README.md` | none | C04, C12, C13, C19, C20 |
| U19 | The runtime | `runtime/` | C17 runtime hooks | C16 |

Nineteen lanes, none waiting: the frontier is the whole table.

**0004's design lanes and these.** 0004 §10 plans the work as L0 to L9;
this packet executes it as U01 to U19, a finer cut by file ownership so
nineteen workers start at once. L0 (the baseline record) is the owner's
machine's, after integration. L1 is U14 and U15; L2 is U02; L3 is U03,
U04 and U05; L4 is U06; L5 is U01; L6 is U16; L7 is U07; L8 is U17 and
U18; L9 is U08, U09 and U10. 0003's stage 1 is U11, U12, U13 and the array
halves of U10, U14, U15, U17, U18 and U19. Where 0004 §6 or §10 names an
owner by L-lane, the U-lane above owns it.

## Retired mechanisms

Named in a part only under `## Delete`. `validate.sh` checks the list.

- `scc-pipeline`, `max-rounds`, the Simplify rounds (`buildSimplifyRound`,
  `CompositeFixedPointPass` around them), `RoundFacts`, `LoopBreakers`,
  `break_last`
- `OperationFingerPrint` as change detection; the RDV resume loop; the inline
  cycle guard
- `idr.inlined` seed marks; `idr.stack` and `idr.program` as discardable
  attributes; the self-referencing `CloneAttr`
- `--without`, `--dump-dir`, `--demand-in-place`, `--break-shape`, the
  `reuse` and `sink` options
- `unsupported (compile-time budget)`, `instanceBudget`,
  `checkComponent`'s blanket refusal
- `LabelSet::top`, `isFollowed`, `unifySuspensions`, `labelsFor`,
  `idr-isolate`
- `Linear.Array`, `IArray`, `idr-in-bounds`, `idr-vectorize`,
  `ArrayLoops`, `ArrayLoopReads`, `ArrayView`, `prim__index`,
  `prim__arraySize`
- `Prof.idr`, the `$world` binder name, the hole sentinel

## Integration and qualification (the coordinator's)

1. While lanes run: answer escalations in `contracts.md` (one owner per
   decision), re-dispatch only the affected lane, never pause the others.
2. As lanes return: audit each diff against its part (permitted outcome,
   NOT TO DO, deletions), reject overreach through its writer, add new
   sources to the build lists the coordinator owns.
3. Integration points: `make typecheck` and `make check` clean, then commit
   and push to `main`. Repairs go to the owning lane.
4. Qualification is the owner's machine: `make build`, `make test`, `make
   test-idr`, `make test-mlir-tools`, `tests/determinism` at 1, 2 and 8
   threads, the stage-0 measurement by binary (0004 §10), and every
   `NEEDS-ACCEPTANCE` file. The handoff lists exactly what to run and read.
