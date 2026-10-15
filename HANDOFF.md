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
  rebuild, as one cutover, right after `make self`;
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
