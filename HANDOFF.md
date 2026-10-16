<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Checkpoint (2026-10-15, 0014-sound integrated on the typecheck machine)

Proposal 0014 (sound passes, typed identities, good tests or none;
proposals/0014-sound/README.md, the packet and its record) ran as one wave
of eighteen lanes, plus a delegated lane Z for `lib/Conversion`, on top of
0004. Every dispatch carried the owner's representation-first guideline
first and verbatim. Mid-wave the owner added hard cutover (no backwards
compatibility) and upstream MLIR first (our C++ at its minimum). It is
integrated: `make typecheck` passes every part (configure, tblgen, cxx
with 0 errors, the regenerated dialects, libs, the fork with `Idris.Host`,
the frontend) and `make check` is 35 of 35. Nothing of the compiler is
built or run. What ran here, needing no LLVM:
- **Runtime property programs** (host clang): bigs 14/14, text 8/8,
  doubles 13/13, utf8 7/7, strings 8/8, the counting model, and `rc`
  101/101. Each lane's mutants are caught by the properties named.
- **googletest:** `idr-box-ranges` 7/7 and `idr-box-tagged` 15/15.
- **On Chez:** Gen and its users; Sem's 72 programs and TwoLevels'
  modules are byte-identical to HEAD. The frontend changes give identical
  exit status on all 312 test programs (T), and Q's runs give
  byte-identical Core and modules on 15 programs and three refusals.

What the tree is now (the packet's §4 and §8):
- **Per-pass contracts:** `idris-mlir-opt --idr-contracts`, on every
  dialect fixture through `tests/lib/lit.sh` with `--verify-roundtrip`.
- **Pass roles and actions:** pass roles are TableGen records
  (`IdrPassRoles.txt`), and every optional transform is an MLIR action,
  skippable one at a time.
- **One rule each:** one effects rule (`idr::bodyEffect`, read by the
  analysis and the verifier), one slot rule (`atPermission`, five sites),
  one program per module.
- **One verdict:** `Accepted < Refused < Internal`, a refusal failing its
  step, and `--report=<file>`.
- **Typed identities in the frontend:** `Address`, `ConId` by index,
  `Con.tag` derived. The trust in Idris's compiler lives in the fork
  (`Idris.Host`), and `Finite.translateFrom` is `covering` (outcome B).
  The translation of applications is total.
- **Dead and duplicated code deleted:** the `scalar_end` chain, the byte
  ops, the lowering's UTF-8 length and exclusivity copies, the frontend's
  second UTF-8 encoder, and the compiler's copy of the small range.
- **About 300 brittle checks deleted outright,** among them the 176,000-line
  doubles snapshot. Three tests are kept as their own contract (R2).
- **Tests added:** idr-expect gains `folded`, and every property has a test
  that fails it. Also new: the runtime property programs (`prop.h`), the
  googletest boxes (`make test-unit`), `tests/Gen.idr` and
  `tests/Prims.idr`, the `rules-covered` and `dialect-text` specs, and
  determinism at 1, 3, 5, 13 threads plus a second process.
- **The owner's rulings:** R1-R5 (packet §8), and the totality rule
  narrowed (2026-10-15): a definition Idris does not prove ends is refused
  only where a normaliser would run it.

Owed on the owner's machine, before anything else:
1. `make build` (it reconfigures for the new CMake: IdrContracts,
   `foreign/idr/unittests`, `IdrPassRoles.txt`), then `make test`,
   `make test-idr`, `make test-unit` and `make test-mlir-tools` on both
   targets, accepting the 285 files `tests/ACCEPTANCE.md` lists. No pin
   moved, so no `make bootstrap` is needed beyond the last entry's.
2. Watch for:
   - `--idr-contracts` on every dialect fixture prints and parses the
     module once per checked run, so the slowest fixtures may near their
     timeouts.
   - `tests/idr/actions/inner-steps` may fail falsely if specialization
     folds `@inc(7)`.
   - Fuzz shrinking can be long.
3. Then self-hosting (proposals/self-host.md, at the head of the queue):
   its stage S1, the refusal sweep, runs on the typecheck machine.

# Checkpoint (2026-10-15, 0004-total integrated on the typecheck machine)

Proposal 0004 (total by construction, every known item, and upstream's
TODOs; proposals/0004-total/README.md, the wave's record) ran as one
wave of thirteen lanes on top of the pipeline cutover and the
representation wave (whose proposals' last texts are at 484d6403), and
is integrated, typecheck only. The C++ tree typechecks with regenerated
headers (353 steps, 0 errors); the host libraries and the fork build and
install; the frontend typechecks against the fork (64 of 64 modules);
`make typecheck` passes every part and `make check` is 33 of 33 (the
licence sweep applied). Nothing is
built or run, and nothing has run on a build machine since c7aa7b62: the
owner's build below is the first of the cutover's, the representation
wave's and 0004's.

What the tree is now (the record's §3 and §4):
- No fuel. Every C++ worklist is an `idr::OnceWorklist` or
  `idr::MonotoneWorklist` (`idr/Support/Worklist.h`); TailPosition has no
  4096-step budget (an insert-once set over blocks and known values);
  every size policy is a named constant in `tools/policies.txt`, and
  `tests/spec/no-fuel` holds the rest of the tree to none. An
  optimization may stop at a budget; `idr-canonicalize` counts
  `not-converged`, and fixtures set `test-convergence`.
- The frontend is `%default total` everywhere but the translation of
  applications (`Terms.idr`'s `covering` definitions and the definitions
  of Programs, Cases, Program and Driver that reach them, each named in
  `tools/policies.txt`); instance finiteness is
  proved (`compiler/src/IdrisMLIR/Proof/`, `Frontend/Finite.idr`); the
  fork is total on the frontend's paths, with four of Idris's bugs fixed
  as fork code (`upstream/fork-*`). Two trust points remain, each in
  `tools/policies.txt`: `Frontend/Host.idr` (the evaluator, the
  elaborator, `checkTerminating`) and the dictionary passes in
  `Finite.translateFrom` (one `assert_total` over a set that only grows).
- A linear value is used at most once on every path; an unused one is
  released, so a pure use may be dropped or sunk.
- Specialization lifts the scalars of a key that matches an earlier one's
  shape into parameters of one copy; only structural growth is refused.
- Patch 24 analyzes cycles of calls to a fixpoint and carries what was
  26; 27, 48 and 49 are submissions, not carried. `idr.element.update`
  rebuilds an element of a value array's buffer in place (a vector's
  pop).
- The runtime: one-pass UTF-8 (simdutf 9.3.0), simdutf's kernel chosen
  by the target's startup check, GMP's allocator set once, small big-int
  paths always-inline. simdutf v9.3.0 and fast_float v8.3.2 are their
  latest releases; modular is a reference submodule
  (`third_party/modular`, `update = none`).
- The caller decides the CPU count (`IDRIS_MLIR_NCPU`, default every
  core); the `NCPU=6` convention and the bootstrap's memory-per-job rule
  are gone. The pin policy (AGENTS.md): llvm-project, modular and Idris 2
  track main; every other dependency its latest release.

Owed on the owner's machine, before anything else:
1. `make bootstrap` (patch 24 changed again, and the simdutf and
   fast_float pins moved), then `make build`, which reconfigures and so
   writes the runtime's `<build>/runtime/c-flags`: nine toolchain tests
   read it to find the generated `idris_rt_ops.h`.
2. `make test`, `make test-idr` and `make test-mlir-tools` on both
   targets, accepting the 189 files `tests/ACCEPTANCE.md` lists, each
   with what to confirm.
3. Then the toolchain bump (proposals/0004-total/toolchain-bump.md):
   Idris 2 to main 89ba32eb alone; then CMake 4.4.4 and LLVM main
   7a83be39 together (rebase 06, refresh 07, retire 01, check the folded
   24 again). Chez stays on v10.4.1 until 10.5.0 is tagged.
4. Then the queue: 0002's G1 (determinism at 1, 2 and 8 threads, the
   bench, x86_64 Linux) and `make self`.

Open (the record's §5):
- Decided by the owner: the request relation keeps refusing a chain that
  grows once and stops, and the total translation of applications
  refuses an implementation that refers to a definition Idris does not
  prove total; the compiler's subset is deliberate, and programs and
  libraries are written for it. Still the owner's: the ryu pin (no release since v2.0); filing the submissions ready to go
  (01 test-only, 02, 16, 22, 23, 25; 48 and 49 need a human author).
- the dictionary passes' proof (a finite universe of learnable fields,
  then a pigeonhole measure), which waits on typed identities in place of
  strings that stand for things (`Request`'s names, `ConId`'s name,
  Recursion's and Emit's string-keyed tables, the C++'s label- and
  name-keyed lookups).
- the primitives cleaned up: dead, duplicated or badly shaped ones,
  across the registry, the ODS and the runtime at once (`scalar_end` is
  dead; the UTF-8 width has a copy in `libs/mlir-linear`).
- the translation of applications made total (`Terms.idr`'s `covering`
  definitions and their callers, named in tools/policies.txt).
- Deferred designs: data-type bodies that hold buffers (deletes
  `DataRemap`'s buffers remap); dependent rewrites with 0003's stage 2;
  a vectorizer gather from a memref; the canonicalizer cases a fold
  weakens.
- A pass to trim the C++ once the suites are green (it grew about 3,500
  lines net).

# Checkpoint (2026-10-15, 0005 integrated on the typecheck machine)

Proposal 0005 (one representation for every fact, and no fuel) ran as one
wave of eighteen lanes (proposals/0005-representation/: the design,
ownership.json, obligations.md) on top of the cutover, and is integrated:
`make typecheck` passes every part (configure, tblgen, cxx, dialects,
libs, fork, frontend) and `make check` is 32/32. Nothing is built or run;
the owner's machine owes what the entry below lists, now against this tree.

What changed, by decision (0005 §4):
- A constructor is its tag, with a role (`ListNil`, `ListCons`, `Label`,
  `Running`, `Forced`); a label holds its function. A force is a call to a
  per-memo-sum dispatch (`<sum>.force`), so `mlir::CallGraph` is the one call
  graph; the hand-built graphs and the force edges are gone.
- The program is `idr.program @p root(@f) stage(higher|first|owned|lowered)`;
  an `idr.func`'s visibility is derived (public exactly for the root). The
  stage rules are its verifier's; stage inference is deleted. In-place
  containment is checked from stage first on (fit boxes in
  defunctionalization; the frontend holds every type in place).
- No fuel and no count refusal: the frontend's reduction is structural
  (head path plus Idris's totality); specialization stops by the
  request-chain rule and keys only parameters passed unchanged along a
  recursion (no unrolling of counters or static tables); the layout limits
  are representations (a two-level tag, a count word, a boxed element);
  the 1024-step owner caps, the int-range and lowering iteration limits,
  and every to-a-fixpoint loop are gone. Every Rule case has a category;
  Cycle and Uniqueness are OutsideLanguage (AGENTS.md says so now).
- One flow interface for closures, suspensions and counted references,
  declared in ODS; one value-facts type interface; the runtime ABI, the
  guards, the rule list, the constructor roles and the big-to-word table
  generated from ODS (a runtime/ODS mismatch is a compile error); one
  summary per function, published at the wave barrier; no effects on a
  call (an inner-pipeline step erases and merges pure calls from the
  callee's summary); boxing decided once, in C++.
- Arrays are ops end to end (`idr.tabulate`, `tabulate_io`, `fold_last`,
  `scan_last`, `transpose`, `array.update`), lowered one to one; record
  arrays become columns by upstream's one-to-N conversion (`idr-columns`,
  right after the optimizer); mlir-array's generating set is bodiless
  `%extern`s; bufferization uses upstream's function models (patch 24
  extended: interface models, non-writable call results, symbol-table
  scope); memrefs inside a function lower through upstream's patterns.
- The bytecode writer uses the attribute-dictionary encoding (the pinned
  reader's unregistered-properties path is broken: upstream/25, kept as a
  submission); every inherent value an op holds is an attribute-backed
  property, and the generator refuses any other.
- The 35 bugs found by reading the cutover (0005 §7) are fixed in their
  lanes, among them the two that stopped every program (bytecode; the flow
  walk at every match), the owned verifier's rejection of buffers, the
  type graph's reference across a reallocation, the parallel lowering's
  data race, a use-after-free of a view in a loop, and flag-dependent
  content names.

Owed on the owner's machine, before anything else:
1. `make bootstrap` (patch 24 changed again), `make build`.
2. `make test`, `make test-idr`, `make test-mlir-tools`, with the 134
   `NEEDS-ACCEPTANCE` files (`git grep -l NEEDS-ACCEPTANCE -- tests`).
   Known mismatches to settle while accepting: R18's tests that read a
   callee's effects at a call (facts-as-marked, queries, alloc,
   call-effects) predate the no-effects-on-calls ruling; Sink and
   case-of-case no longer move calls (a call reports every effect), which
   may cost the raise its dispatch in a few fixtures; idr-rc makes one
   copy per function (every followed parameter exclusive).
3. Determinism at 1, 2 and 8 threads; the bench; `make self` (tools/self.sh
   now compares the `.mlirbc` and records peak memory on both targets).
4. Fork bug to fix next, in the fork (ours): `checkCaseDelayed`
   (`compiler/idris/src/TTImp/Elab/Case.idr:394-404`) retries a scrutinee at
   linear only on a bare LinearMisuse, so an ambiguous name on the right of
   a linear pattern `let` fails.

# Checkpoint (2026-10-14, late, the cutover wave integrated on the typecheck machine)

Proposal 0004 (the pipeline cutover) and 0003's stage 1 (the MLIR-first
array rebuild) landed as one swarm wave of 19 lanes on disjoint files
(proposals/0004-compile-time/: ownership.json, swarm.md, the 24
contracts, each lane's part). It is the last wave: everything after
it is ordinary work on main. Integrated at c7aa7b62 and the commits
after it, on the typecheck machine, which builds no LLVM.

What the tree is now:
- Defunctionalization is total by analysis: every op holds the flow
  interface as an external model (lib/IR/Flow.cpp); a 0CFA label solve
  with no unknown element; every key a sum named from its content.
- `idr-optimize` is the ready set: call-graph components run bottom-up
  in deterministic waves (`failableParallelForEach`, nodes inserted
  between waves), with MLton's inline rule on final sizes and a caller
  cap that stops and never rejects. Specialization nodes are
  content-keyed and stop at a per-owner limit. The frontend's instance
  budget is gone for 0011's request-chain rule. AGENTS.md makes
  acceptance a property of the program, and spec/totality holds that
  no refusal by count, round or budget remains.
- Data types are identified types (`!idr.data<"T", kind [...] ...>`,
  body set once; `idr.data`/`idr.ctor` deleted; `#idr.con` carries its
  type). Stack, effects and the in-place promise are inherent facts.
  Refusals are one `Rule` enum in ODS, generated into Syntax/Idr.idr
  (Rule.idr deleted). Names come from content (XXH3-128 in C++ and Idris).
- Arrays are tensors: `idr.tie_shape`, `#idr.world` memory, literal
  extents static, `idr-structure-loops` into linalg/scf, One-Shot
  bufferization on idr.func through patch 24. An array's lowered value
  is one pointer, its cell; a constant is one global with the header in
  front. libs/mlir-array replaces Linear.Array; the fork's context table
  is an IOArray. Deleted: the InBounds stack, idr-vectorize (now the
  transform schedule, `transform.idr.vectorize_lanes`), Simplify and its
  rounds, Isolate, Prof, the break shape, `break_last`.
- Code generation partitions the program into size-balanced bins for
  parallel LLVM (lib/Target/Partition.cpp, `writeObjects`). The frontend
  hands over MLIR bytecode (`.mlirbc`).
- Patches 02, 16 and 22 retired as submissions; 24 added; Modular's
  EliminateDuplicateFunctions ported (Apache-2.0 WITH LLVM-exception).

Verified here: `make typecheck` configure, tblgen, cxx (every C++ unit
of the dialect and tools), dialects, libs and fork; `make check` 32/32.
The frontend typechecks too (`idris-mlir.ipkg`, 60 modules, and
`syntax-samples`), so `make typecheck` passes every part. The Idris
XXH3-128 reproduces all 13 of LLVM's published vectors and C21's text
vector. Known gaps, each an internal error by C20's shapes, never a
miscompile: a suspension of an array of records (`!idr.lazy` holds one
value, the record array N columns), and a tabulated cell whose own
dimensions are dynamic (the frontend refuses that as `unsupported
(type)` first, so it should not be reached).

Not run, because this machine builds no LLVM, and owed on the owner's
machine before anything else (AGENTS.md's checks):
1. `make bootstrap` (patch set changed: 24 in, 02/16/22 out), then
   `make build`.
2. `make test`, `make test-idr`, `make test-mlir-tools`. 106 expected
   files carry a `NEEDS-ACCEPTANCE:` first line (`git grep -l
   NEEDS-ACCEPTANCE -- tests`): 96 in tests/idr (27 defunc, 10 raise, 8
   specialize, 7 bufferize, ...), the dialect-syntax and handoff tests,
   the registry three, runtime-api, data/shapes, and the two cycle
   rejects, whose location moves because a type has no location. Each
   line says what to confirm; accept by replacing the file with the
   output, the line removed, when the output says it.
3. Determinism at 1, 2 and 8 threads over dumps, objects and the
   executable; the three two-bin partition tests of C13.
4. The bench against the 2026-10-13 record within 0003 D35's 2%:
   spectral-norm-linear's vectors (now the transform schedule), the IO
   loop (tests/idr/raise/io-loop ending in scf.while), the five ports
   to mlir-array.
5. The optimizer's wall on stage 0 against 0004 §10's margin (under
   600 s), and the bytecode read time against the 11.7 s text parse.
6. x86_64 Linux: the same, NotRun as before.

Owner questions still open, each with its default taken: GMP's licence
(0001 §5); a port's changes note (0001 §9); G1's Linux leg (0002 §5);
0006 §12's host question; 0007 §13's restated D3 and D5.

# Checkpoint (2026-10-14 night, the pipeline cutover designed and the queue reconciled)

Proposal 0004 is rewritten as the pipeline cutover (3de67510) and
awaits the owner's approval; no code changes until then. It answers
first whether inlining can be pure optimization: yes, by making
defunctionalization total by analysis alone, as MLton's closure
conversion is (closed world as a verified invariant, one flow
interface, a forced-state anchor keyed by the lazy value's type, no
unknown element in the label set; 0004 §2). Then one bottom-up ready
set over call-graph SCCs replaces the Simplify rounds (each function
cleaned once, after its callees are final, under MLton's inline
formula applied once and a per-caller cap of 10,000 ops), and code
generation is split into size-balanced bins of SCCs, 2^15 LLVM
instructions each, for parallel LLVM (0004 §4, §5). §6 is the
deletion table; §10 the lanes, each owning its files outright (D44),
run on the owner's machine with builds and suites at each
integration. The opt-in scc-pipeline of 552d682a is deleted by the
cutover. Every question in 0004 is decided. The owner approved the
cutover and ruled that a count never decides acceptance, so it also
takes 0011 D4, the request-chain rule that replaces the frontend's
instance budget (D40); AGENTS.md holds that as a project rule. The
swarm packet is written next, then the cutover runs as one wave.

Every proposal on the path, 0001 to 0011, was reconciled with 0004 the
same day (db27189e, and the passes committed with this entry): each made
consistent with the cutover, its open questions decided with their
reasons, its claims cited; proposals/README.md's entries and priority
paragraph now match them. A cross-proposal check then fixed what the
files said differently. 0004 now states four rules 0006 had decided
but the cutover runs (the clone budget per requesting node, `calls(f)`
frozen, the XXH3-128 name hash, the homes of RoundFacts' facts), names
the pass registry after the cutover (`idr-optimize` is the ready set),
gives every build list, header and generated module a lane, writes
call-site effects when a caller becomes ready, deletes `break_last`
with LoopBreakers, and names the header's 2^16 tags as the one
representation limit left. D23 now keeps upstream patches 02, 16 and
22 carried until the pin moves, as AGENTS.md binds; the seam the
earlier entry left for the owner is closed, and AGENTS.md is unchanged.
Instance symbols carry their identity hash by a rule of the key alone
(0008 §4.10); every measurement threshold is 0004 §10's margin, never a
run-to-run spread; the precise rejection messages are 0002's change
after the cutover, not the cutover's. 0012 and 0013 stay parked, each
with its reason in its status line. 0011 puts 0004's question too, with
the same default.

Besides it, the questions only the owner can settle, each with its
default taken in its proposal: GMP's licence, with counsel (0001 §5);
whether a port's changes note names only what changed (0001 §9;
default yes, path and revision in PINS.md alone); where G1's x86_64
Linux leg runs (0002 §5); what a registry primitive means on the Chez
host that runs stage 0, for the compiler's Idris half on shards
(default processes) and for 0007's A3 folds (default: from A3, stage 0
is the native frontend of the last commit before A3) (0006 §12); and
the restated forms of the owner's D3 and D5 for static normalization
(0007 §13).

The tree: `make check` 27/27 at ccaba89c and on the working tree this
entry is committed with (typecheck machine, 2026-10-14); spec/time-trace
leaves sources/ out of its mention search, since the research notes
there are kept verbatim. The gate on arm64 macOS was last green at
552d682a (NCPU=6: build clean, check 27/27, test-idr 286/286, test
415/415), on the rounds, as at 7a27fd34 before the opt-in; the cutover
must reproduce the rounds' 415/415. x86_64 Linux is NotRun. Stage 1 of
`make self` has never finished. Next: 0001's L5 and L6 on the typecheck
machine, before the packet fixes its disjoint writes, since they touch
`foreign/idr/tools/idris-mlir-tblgen.cpp` and `tests/spec/licenses`,
which 0004's L5 and L8 own; the owner's approval of 0004; then the
cutover's swarm packet, written from 0004 §10 under
.claude/skills/compile-swarm-proposal (28a76e26); G1's run before the
cutover is taken beside lane L0, on the commit L0 records its baseline
on, and commits the bench and compile-time records it compares against
(0002 §3, D19); before it, bench/run.sh stops comparing the Chez
column's output (0002 D20).

The research is stored verbatim in sources/notes/compile-pipeline/
(MLton, code generation partitioning, Mojo, upstream MLIR and LLVM,
the casework audit), with 27 more MLton files in sources/code/mlton
(43 in all, at aa2fd1ad) and a Mojo snapshot at 9211931 in
sources/code/modular (the full clone is at ~/Documents/modular, read
only).

# Checkpoint (2026-10-14 evening, licensing built; F3 opt-in pinned as a problem)

The owner approved the rewritten proposals and the bankruptcy
ended. Licensing (0001) is built and pushed (3a275cf0): SPDX on
every file, LICENSES/, NOTICE, tests/spec/licenses gating it;
only the GMP question (owner, with counsel) and the deferred
foreign/idr rename remain there. F3's first serial form is built
opt-in as idr-simplify's scc-pipeline (552d682a; rounds stay the
default), byte-identical to the rounds on do-block in 3 deltas,
with that identity now maintained coverage in
tests/idr/pipeline/do-block.mlir. Gate on arm64 macOS at
552d682a (NCPU=6): build clean, check 27/27, test-idr 286/286,
test 415/415 (x86_64 Linux still NotRun). The file-size split
(Scc.cpp driver, Simplify/Trace.cpp; Simplify.cpp 463 -> 383
lines, pure movement) is committed with this entry. The corpus
verdict run (scc-pipeline over /tmp/f0/post-contify.mlir,
throttled, command in proposal 0004 §2.2) was killed by the
owner at 18:10 after ~66 wall-minutes and 90+ CPU-minutes with
no output and no verdict -- and the opt-in two-path state
itself is now pinned in 0004 §2.3 as a problem for
re-evaluation: a behavior-selecting option with the rounds as
fallback is configuration slop this compiler does not carry.
Nothing builds on the option, and nobody reruns the corpus to
"decide the flip", until the owner decides one path or a
revert. Everything is on main in the one checkout: the last
stale remote branches (fully merged, zero unique commits) were
deleted 2026-10-14; no branches, no worktrees, by the owner's
standing rule.

# Checkpoint (2026-10-14, F0 and the bankruptcy)

The proposals were cut over to current-state documents (dcb087d2:
the cutover packet deleted and the queue closed up; then licensing
took 0001 and every other proposal moved up one, maps in those
commits). Every worktree lane of the
perf round and the older self-host work is merged into main
(b4713f66); gate on arm64 macOS at 7a27fd34: check 26/26, test-idr
286/286, test 415/415 (x86_64 Linux still NotRun). One CPU budget
(tools/host.sh: IDRIS_MLIR_NCPU, else every CPU) now threads the
Makefile, bootstrap, the runner and the driver's --num-threads.

F0 is recorded (bench/profiles/2026-10-14-f0-stage0.md): Simplify
round 1 is 447 s with one InlineCleanup instance at 211 s; sixteen
rounds do not reach a fixpoint; the largest post-inlining SCC is 24
functions. Two InlineCleanup refactors (strict worklist confinement;
deferring simplifyRegions to a once-after-inlining pass) were built,
measured slower or wrong, and reverted the same day -- proposal 0004
§2.1 records both. Licensing (0001: SPDX provenance everywhere, the
Mojo/MLIR porting protocol, the third-party inventory with GMP
named) is first in the queue. No code changes land until the owner
approves the rewritten proposals (0004 §4 is the design awaiting
that approval).

# Checkpoint (2026-10-13, profiling/speedup pass)

Gate on arm64 macOS (x86_64 Linux NotRun): make check 26/26,
make test-idr 282/282, make test-mlir-tools 17/17, make test 415/415,
determinism 7/7, fuzz seed-1 and seed-2 pass. Fixed since the
cutover's first suites: defunctionalize unifies the result slot of one
lazy cell's suspension labels (the labels-lost cluster); isolate
outlines an evaluated delay of a closure or suspension;
idr-in-bounds decides integer emptiness by branching on the simplex's
fractional coordinates under a budget (qsort's pass: unfinished at
180s, now 0.5s, same guards erased), in Transforms/InBounds/Empty.cpp;
synthetic world binders are named $world, so no quantity key collides
with a user's w; inline's preparation and inliner cycle together, so
a do-block unfolds within a round instead of one statement per round
(the fuzz fixpoint failures); the frontend names a block referred to
only from a definition's type (referencesOf walks types last). CSE's
statistics were an upstream bug (assignment, not accumulation):
upstream/23 carries the patch and the toolchain is rebuilt with it.

Compile times: tests/compile-times.sh recorded 490 compilations
(/tmp/compile-times-2026-10-13.md); IdrSimplify dominates. A
time-trace profile of every-interfaces-export is in bench/profiles/
(15.2s total: IdrSimplify 9.8s, IdrInline 6.4s across 5 rounds,
Canonicalizer 4.8s across 7062 runs). The full bench is recorded in
bench/runs/2026-10-13-9a1b7b1-darwin-arm64/, the only record kept:
against clang, 6 faster, 13 within 15%, 8 slower; against Chez,
faster on all 27 (1.2x-154x); bench compiles take 0.8-5.4s.

The last three failures are fixed. linarray-fannkuch: idr-rc dup'd an
array's memref field in rev because the consumer that keeps its root
alive (lin.enter for the recursive call) sat before the writes through
the field; sinkConsumers now counts uses of fields read from a consumed
value as reads and runs before ownFields, so the entry sinks past the
writes and no count changes (Transforms/Ownership/Reshape.cpp).
every-types-export: its 2 live cells are the top-level cyclic stream
`powers` (cons cell and suspension), which reference counting does not
collect; the fixture carries a live-cells mark of 2, as stream-share
and memo-shared-stream do. implementation-runtime-scope and stage 1's
Prelude.Show.show refusal were one frontend bug in three parts:
dependence of a dictionary is now also judged on its expanded form
(a case block of `Show (Term vars)` takes the erased `vars` at
runtime, so the dictionary closes over it: Instances.classify with
Closed.expandClosed); the holed walk now walks any constructor of an
implementation, not only a constraint pair, so an expanded
dictionary's method closures are found values (Terms.holed gives);
and Idris's normaliser quotes the bound hole marker as the innermost
variable, capturing it, so marker-holding terms are normalised with
markers renamed to function references and back
(Closed.normaliseKeeping, in whnf and expandClosed) — that capture
was the packed projection applied to the matched term. A dictionary
built of a shaped runtime argument (`MkSize n` at shape `S _`) is
accordingly accepted with the value passed (programs/interfaces/
implementation-shape-value, moved out of reject/); in a constructor's
dictionary field it is still refused, now naming the implementation
as written. ApplyOp::canonicalize no longer reads a signature for a
constant closure without captures; a cached symbol table there is
raced on and stale (tried, crashed in the inliner's workers, reverted
with the reason in OpsClosures.cpp).

Self-hosting: stage 1's frontend now translates the whole frontend
(58k functions, 308 MB module; frontend ~140s of the run) and the
pipeline is the long pole: one stage-1 attempt ran 51 minutes in
IdrSimplify/IdrInline (single busy thread in the inliner's callable
canonicalization; samples in the session) without finishing, and was
stopped to land the fixes above. Stage 2 = stage 3 is still unproven;
the stage-0 profile is stage 1's own -mlir-timing when it lands.
Nothing below this section has been re-checked yet.

# Handoff (2026-10-12)

Two independent agents, each started locally in Claude Code in a clone of
bjornpagen/idris-mlir at `main`. Paste the prompt under each heading as
the agent's first message. They touch disjoint things: the first works
in a separate clone of llvm-project and only updates `upstream/` status
here; the second owns this repository's toolchain and code.

State, updated 2026-10-12.

**The cutover.** Proposal 0002 is committed, and it builds:
`foreign/idr` is an in-tree MLIR dialect in upstream's layout (headers
and .cpp, no C++ module), functions are `idr.func` with their facts as
inherent attributes, analyses run under the analysis manager, the round
is upstream's composite pass, the runtime is headers and .cpp, the
frontend emits no erased value, and compile-time evaluation (`idr-eval`,
its JIT and its child) is gone. Its first real build (4d5e7e8f, arm64
macOS) passed, and a Prelude program compiled by it runs with no live
cells at exit. The suites ran once, before the fixes that followed:
`make test` 84 of 415, `make test-idr` 251 of 272, `make
test-mlir-tools` 15 of 16. The failure clusters those runs showed are
fixed in the commits after it (isolate's linear closures, the
quantities check's keys, rc's reuse of atoms, the newtype's field
quantity, block naming, the parsers' inherent facts), and the gate has
not run again since. `make typecheck`, which compiles every unit with
the dev warnings as errors without stage 2, and `make check` pass. Its
qualification is the 0002 README's "Qualification".

**Toolchain.** Built on arm64 macOS, pin llvm main 7208ba24, one recipe
(`tools/bootstrap.sh`, into `.toolchain/llvm`). Before the cutover, on
2026-10-10, `make build` passed, `make check` was 26/26, `test-idr`
269/269 and `test-mlir-tools` 17/17, and two `make test` programs,
`programs/prelude/every-interfaces-export` and `every-types-export`,
compiled and then hit their time limits. A stage-2 rebuild takes about 3
minutes with ccache. x86_64 Linux is still unbuilt at this pin (0001's
gate G1).

**Self-hosting.**
- **Stage 0 compiles itself (2026-10-10).** The frontend, built by the
  stock Idris and running on Chez, compiles its own sources
  (`IdrisMLIR/Frontend/Driver.idr` with `-p idris-compiler -p
  mlir-linear`) with no rejection and no error: a 405 MB MLIR module of
  58,305 functions and 7,664 data types, and its 74 MB Core, in 137 s at
  9.1 GB peak (arm64 macOS; phases: checks 0.4 s, reachable 4.2 s,
  translate 81 s, print 40 s, write 0.9 s). The fork installs in about
  75 s. The 702-program corpus's outputs are byte-identical before and
  after each change but one, by design (a type parameter named only in
  erased fields keys no data instance: `Equal`'s).
- **How to run it:** `make fork frontend prefix libs host-libs PINS=true
  CHECKOUT_PREFIX=<p> HOST_PREFIX=<h>`, then the frontend's package mode
  installs `compiler/idris` into `<p>` (`idris-mlir-front --prefix <p>
  --install idris-compiler.ipkg` from a copy of it), then
  `idris-mlir-front --prefix <p> -p idris-compiler -p mlir-linear
  --timing <t> --core <c> -o <m> IdrisMLIR/Frontend/Driver.idr` from a
  copy of `compiler/src`. Cap the Chez process's memory when running it by
  hand: a translator bug shows as unbounded growth, not as an error.
- **`make self` (1ce907d3)** builds stages 1 to 3 and checks that stage 2
  matches stage 3: the same executable, module and Core. The new tests'
  end-to-end runs and FileCheck with the native frontend are after that,
  and the same on x86_64 Linux has not been run.
- **Then:** the test runner off Chez (orchestration in sh, generators
  compiled by idris-mlir, an `--exports` query instead of the stock
  REPL); `tests/toolchain/static-linking` covering `idris-mlir-front`;
  AGENTS.md's Chez exception narrowed to stage 0 and bench; every
  rejection message made precise (named in the user's request of
  2026-10-10: what was found, where, why, and what form compiles);
  emission's memory (9.1 GB for a 405 MB text module: the print-write
  patch in the scratch audit, and R7's bytecode rule, now measurable).
- The rewrites self-hosting forced, and the compiler features that would
  replace the regressions among them, are proposal 0011.

**Proposals** (`proposals/README.md`), in their numbered order, which
is the order the work is done:
- 0001: self-hosting (its stage S, §6.1), behind its gate G1 (its §12):
  what remained of the Linux bootstrap and of the representation cutover;
- 0002: the cutover that executes 0001's stages C and H, committed;
  qualifying it is 0001 §6.1's first steps;
- 0003's stage 1: the purge of today's array stack and its MLIR-first
  rebuild, in the same swarm wave as 0004's cutover;
- 0005 and 0006: sharding (0005's P1, P2 and P4; 0006's S0, S1, S2 and
  S8);
- then the array work: 0003's typed array language, with 0007's array
  interpreter (static normalization on the type checker's evaluator),
  0008's tables and 0009's flattened data as its consumers, and 0010's
  type checker on 0007's machine;
- 0011: the compiler features self-hosting asked for, once `make self`
  is green;
- parked: 0012 (the relational core), 0013 (Rust), 0006's S3 to S6 and
  S9 to S10, and 0005's P3.

The research behind 0010, 0003 and 0009 is in `sources/`, with reading
notes in `sources/notes/`. Contiguous runs (one run cell for strings,
arrays and buffers) has no proposal yet. The LLVM submissions are in
`upstream/`; their status table says which is next.

## Agent 1: upstreaming

```
Read upstream/README.md in this repository, all of it, and do what it
says. You are the sending agent it describes. Start with the first row
of its status table marked "send next". Its rules are absolute: I (Bjorn)
approve every post one command at a time, everything ends with
"Assisted-by: Claude Code", you push only to my fork, one submission at
a time, trunk only, the diff applying to current llvm main and
clang-format clean, check-mlir left to LLVM's pre-merge CI. Before
anything else, confirm `gh auth status` and git's user.name/user.email,
and tell me what you found. Do not touch this repository's toolchain or
code; the only files you change here are upstream/README.md's status
table, upstream/NN-*/README.md's "Upstreaming plan" and PINS.md entries,
as its "After a pull request lands" and step 9 say, committed and pushed
to main.
```

## Agent 2: done

Its two phases landed: the trunk cutover (20fcfadb, 1677b8cb) and the
representation cutover (93f5d9c9, 327c2e30, 0451b1b8). What it left open
is now the repository's own: the bootstrap and the suites on both
targets at the pin, and the rest of the representation cutover's
qualification, both in 0001's gate G1
(`proposals/0001-get-back-on-track.md` §12).
