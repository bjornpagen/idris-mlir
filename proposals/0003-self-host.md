<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Self-hosting: `make self` finishes

**Status:** proposed 2026-10-15, at the head of the queue (the coordinator
numbers it). It takes 0005's former §2 (self-hosting's steps 4 to 6) and
its decisions D10, D11 and D16 (their text at b843d8b5). Goal: the
frontend (`compiler/src`) and the fork (`compiler/idris`), compiled by
idris-mlir itself, stages 1 to 3, stage 2 the same as stage 3, on both
targets. None of 0013's features is needed: stage 0 emitted the whole of
the frontend and the fork with no frontend refusal (F0, 44495199,
`bench/profiles/2026-10-14-f0-stage0.md`; *measured*). Claims are marked
*read* (the path), *measured* (the record), *recalled*, *conjecture*,
*decision*.

## 1. What it changes

- `tools/self.sh` (D6): each stage runs its frontend alone, then the
  pipeline on the module it wrote, each half under its own `peak_memory`;
  each stage builds from a fresh copy of the sources at one path; stages
  2 and 3 compare the TTCs of `compiler/src` too.
- The fork and the frontend, wherever idris-mlir refuses them (§3), in
  their own code, representation first. No rule of the compiler changes.
- Nothing else: the pipeline, the runtime and the rules are what the
  waves before built.

## 2. Where it stands

What `make self` does (*read*, `Makefile:210-257`, `tools/self.sh`):
`prefix` installs the pinned Idris's packages into the checkout prefix
with the Chez frontend, `libs` installs `libs/`, `self-fork` installs the
fork as `idris-compiler`; then `self.sh` copies `compiler/src` once
(`:31-32`) and for N = 1..3 runs stage N-1's `idris-mlir` (stage 1: `make
build`'s, whose frontend runs on Chez) on `IdrisMLIR/Frontend/Driver.idr`
with `-p idris-compiler -mlir-timing --num-threads=$ncpu`, under
`peak_memory` (`:44`), copies the same C++ driver into each stage (`:54`),
and compares stage 2 with stage 3 by `cmp` on `idris-mlir-front`, its
`.mlirbc` and its `.core` (`:63-68`). Only the frontend is self-compiled.

Where it stopped: stage 1 never finished. A 4 h 23 min attempt and a
restarted one stopped inside the Simplify rounds (*measured* then, logs
not kept; the compile-time proposal at dcb087d2, "What stands"); a 51-min
attempt sat in IdrInline (HANDOFF.md, 2026-10-13). F0 then measured the
rounds on the stage-0 module (58,236 functions, 294 MB of text, about
140 s of frontend): round 1 447 s, sixteen rounds and no fixpoint, over
2,000 s extrapolated, 5.27 GB to 7.65 GB peak, and defunctionalize still
refusing `Idris.Parser.directive.lam4` after round 16 (*measured*). Stage 0
on Chez: 58,305 functions in 137 s at 9.1 GB (2026-10-10, HANDOFF.md).

Since: the pipeline cutover (c7aa7b62, 5d5f3312) deleted the rounds and
made defunctionalization total, right after emission; the representation
wave (bfdcac70) made the frontend's reduction structural; 0002 (d06ed15c)
made the frontend total and added the guard of §3.2(a); 0001 is
integrating. Nothing has been built or run since c7aa7b62 (*read*,
proposals/README.md), so every item of §3.2 and §3.3 is unmeasured.

## 3. Blockers

### 3.1 Known by reading

| Site | What | Rule |
| --- | --- | --- |
| `compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:33` | `%prefix_record_projections off` in a user module, added by d06ed15c | `user pragma`: `Frontend/Profile.idr:161-162`; only `discharged` (`:125-126`) passes |
| `compiler/idris/README.md:467-472`; `Idris/Desugar.idr:1189, 1236, 1379`; `TTImp/TTImp.idr:482-490`; `Idris/Syntax.idr:900-920` | `SyntaxInfo` holds terms (`startExpr`, `usingImpl`, an interface's parents and defaults), a term's local block holds `IPragma`, and the desugarer's interface, implementation and `%hide` fixity actions capture `Ref Syn SyntaxInfo`: an IORef whose element type reaches it | `cycle`: `foreign/idr/lib/IR/Verify/Knots.cpp`, a type-graph knot through an array, checked at every verification once defunctionalization makes captures types (`lib/IR/TypeGraph.cpp:18-20`, `Verify/Program.cpp:305`). *Conjecture*, strong: F0 never got past defunctionalize, so this never ran on the fork |
| `compiler/idris/idris-compiler.ipkg` | `Idris.Host` (0001's lane I, `src/Idris/Host.idr`) is not in its module list | the fork does not install it; the frontend's imports fail |
| `compiler/idris-mlir.ipkg:46` | still lists `IdrisMLIR.Frontend.Host`, deleted | the frontend does not build |
| `tools/policies.txt:33-34, 38-46, 48-54` | name the `assert_total` of `Frontend/Host.idr` and of Finite, and the `covering` definitions of Terms, Cases and `translateInstance`, all gone; Finite's `covering translateFrom` is not named | `tests/spec/no-fuel` requires each listed line in its file |

The last three are 0001's integration (*read*, live tree). With them,
0001's R4 holds in the live tree: no `assert_total`, `believe_me`, hole or
`%MkWorld` in `compiler/src` or `libs/` (*read*, a search), the trust in
Idris's compiler is the fork's (`Idris/Host.idr`), and the frontend's
`covering` chain is `Finite.translateFrom` (`Finite.idr:296`),
`Programs.translateIOProgram` (`:150`), `Program.program` (`:140`) and
`Driver`'s `perform`, `frontend` and `main` (`:284, 310, 333`). Every import
of the frontend and the fork resolves to the prelude, base or the fork
(*read*); neither reaches a thread, process, signal, finalizer or
deprecated buffer name, and the fork declares no `%foreign` or `%extern`
and spells no escape hatch (*read*).

### 3.2 Not yet run on the fork or on code written since F0

- (a) **An implementation whose method Idris does not prove ends.** The
  owner narrowed the 47f97059 ruling on 2026-10-15 (*decision*): a
  definition Idris does not prove ends is refused only where a normaliser
  would run it (`host.normalise`, `host.normaliseAll`, through
  `Closed.normalisedBy`), never by lambda-only simplification, which runs
  nothing (`Closed.lambdasApplied`, now what `Terms.settle` uses). The
  owner's reason: the project is a good optimizing compiler producing good
  code, and a total compiler compiles a partial program without running it.
  The fork's 92 `%default covering` modules (about 343 implementations,
  *read*) meet the refusal only where the head path must run one of their
  definitions to learn a static value (`Closed.idr`'s `normaliseAll` and
  `normalise` sites); S1 counts them.
- (b) **The request-chain rule**, which refuses a chain that grows once and
  stops (`Frontend/Finite.idr:123-130`, `Polymorphism`; 47f97059), and its
  data-instance form: never run on the fork (0013, feature 2).
- (c) **The erased match** (`Translate/Cases.idr:585-590`, `Match`) on
  `Proof/`, Finite and 0001's typed identities. Their erased matches read
  so far have one constructor (`Finite.idr:247`, `Access`;
  `Proof/Requests.idr:351-352`), which `Cases.idr:579-583` admits, and the
  runtime decision uses `So`, not base's primitive `DecEq`, whose
  `believe_me` (`base/Decidable/Equality.idr:140-143`) is refused even from
  base (`Profile.idr:319`) (*read*); the rest is unmeasured.
- (d) **The fork's elaborator on `compiler/src`.** `make typecheck` checks
  the frontend with the stock Idris only (`Makefile:369-372`); stage 1
  elaborates it with the fork's, a different Idris (one known bug open,
  `TTImp/Elab/Case.idr:394-404`, HANDOFF.md). Not run since 2026-10-10.

### 3.3 Pipeline and scale

What kept stage 1 from finishing, the rounds, is deleted. In their place,
never run: the label solve, the bottom-up ready set with MLton's inline
rule once and the caller cap (`kCallerCap = 10000`, `tools/policies.txt`),
and code generation in bins of 2^15 LLVM instructions, at self scale. LLVM's
share is measured only at test scale (3.8%, F0). Unknown too: the
bytecode handoff's size, the frontend's memory without the text printer,
and the native frontend's speed. Two facts of the tools stand in the way
of measuring it: the driver removes the `.mlirbc` when any later step fails
(`foreign/idr/include/idr/Driver/Artifacts.h:105-111`), and `peak-kib`
is one figure, the larger of the frontend child and the pipeline
(`tools/host.sh:129-158`, wait4's `ru_maxrss`).

### 3.4 Two hosts

On `make self`'s path, none beyond §3.2(d) (*read*). `libs/` is not on it:
neither the frontend nor the fork imports a module of it (*read*), its
`%extern` primitives run under idris-mlir alone (AGENTS.md), and `make
test`'s programs are what compile it there. Off the path: the test
machinery cannot compile under idris-mlir, which AGENTS.md requires.
`tests/Runner.idr:42, 53, 57` call `system` (`process`, outside the
language), and `tests/Main.idr` imports `Test.Golden` and `Language.JSON`,
packages outside the table (`Registry/Libraries.idr:102`, refused at
`Profile.idr:289-290`).

## 4. The plan

- **S0, integration** (typecheck machine; 0001's coordinator). The three
  integration rows of §3.1; Closed.idr's pragma deleted, renaming what it
  kept apart (lane I's file). Verified: `make typecheck`, `make check`.
- **S1, the census** (typecheck machine, no LLVM; this proposal). `make
  typecheck` (the dialect modules), `make fork frontend`, the checkout
  prefix, `libs` and the fork installed by the Chez frontend, then
  `idris-mlir-front --prefix P -p idris-compiler --timing T --core C -o M
  IdrisMLIR/Frontend/Driver.idr` on a copy of `compiler/src`, under
  `peak_memory`. It reports every independent refusal and every error of
  the fork's elaborator in one run (`Profile.idr:240-251`), and when none,
  writes the module. Recorded under `bench/profiles/`: the refusals, and
  once S2 has made it exit 0, the handoff's functions, operations and
  bytes, the phases, and the frontend's peak memory (0005's old step 4).
- **S2, the fixes** (typecheck machine; this proposal: the fork is ours,
  the frontend's files after 0001 releases them). Each S1 refusal, by D2;
  the `SyntaxInfo` knot, by D3. Verified: S1 again, exit 0; `make
  typecheck`; `make check`; the fork and the frontend still build on the
  stock Idris; no closure in `ImpDecl` captures a cell (review).
- **S3, the pipeline** (owner's machine, arm64 macOS, after 0002's build
  and acceptance). `idris-mlir M -o front -mlir-timing` from S1's module
  (a `.mlirbc` input is read, never removed: `lib/Driver/Artifacts.cpp:
  64-66`), with `tools/profile.sh`. A refusal (`cycle`, `uniqueness`) or
  internal error is fixed where its rule's design is. Recorded: the label
  solve against 10 s and the optimizer against 600 s (the pipeline
  cutover's §10 at 484d6403), the pipeline's peak memory apart. D4 says
  when a figure holds back S4.
- **S4, `make self` on arm64 macOS** (owner's machine). `tools/self.sh` as
  D5 and D6 amend it. Verified: stage 2 = stage 3; each stage's time and
  peak memory, and D5's record, in HANDOFF.md.
- **S5, `make self` on x86_64 Linux** (the Linux machine, after 0005's
  Linux build and suite). The same, there. `make self` holds then (D8).

After it, not in it: G1 (0005, re-cut to follow `make self`), the test
machinery under both hosts (D7), the toolchain bump (0004), and
0013's features, which may start then.

## 5. Alternatives rejected

- A compiler case for the fork: exempting a trusted library from the
  static-argument rule, the knot rule or the pragma rule. Each is a branch
  by origin, and the subset is deliberate (47f97059); the fork is ours.
- An `assert_total` at each refused site: a trust is stated once
  (AGENTS.md); a site's assertion is a second copy of it.
- Comparing stage 1's module with stage 2's: stage 1's frontend runs on
  Chez, so the comparison makes Chez's meaning a gate (no oracle).
- Measuring S3 on F0's module: it is text in the dialect before the
  cutover, which the pipeline no longer reads.
- Running all of `make self` before S1: an owner's machine cycle to learn
  what the typecheck machine can, since every frontend refusal is decided
  before any MLIR exists (the pipeline cutover's §2.5).
- Breaking the knot with a weak reference or a collector: the heap is
  acyclic by the memory model, which counting rests on.

## 6. Decisions

- D1. S1 runs on the typecheck machine before the owner's build. Reason:
  the frontend runs on Chez and needs no LLVM, which that machine may run
  (the owner, 2026-10-15); only the pipeline's half needs the owner's.
- D2. A refusal is fixed in the code it names, never in the compiler's
  rules. In the fork: a definition is made total where its recursion is
  the fork's own; where it is Idris's theory's (a call of the evaluator or
  the elaborator, or a recursion on what the evaluator returns, as
  `Reify`'s), it rests on the one stated trust, `Idris.Host`'s, extended
  there (its evaluator fields split into a module below `Core.Reflect` if
  an import cycle forces it), never on a new assertion at the site. Which
  of the two each refusal is, S1's list says (*conjecture* until then).
  Reason: R4, and one thing, one representation.
- D3. The pragma actions stop holding the cell: the desugarer's actions
  become first-order data that `IPragma` holds and the processor
  interprets with every cell in hand, as the action is already given
  `Ref DLY` (`TTImp/TTImp.idr:486-489`). Reason: a closure that captures a
  cell is the state the data makes unrepresentable; `TTImp`, below
  `Idris.Syntax`, cannot name `SyntaxInfo` to take it as an argument
  (`compiler/idris/README.md:470-471`). Verified first by review, then by
  S3's verifier.
- D4 (was 0005's D10). The diet and the memory are a record, not a gate,
  unless a stage does not fit the owner's machine or does not finish;
  then the stage the record names is fixed first, where its design is
  (the frontend's memory: 0010; the optimizer and labels: S3, by the
  cutover's §10 rule; LLVM: 0007's split before O3). The frontend's and
  the pipeline's peaks are recorded apart (S1, S3).
- D5 (was 0005's D16). `make self` compares at the default thread count.
  Thread independence is `tests/determinism` on every suite run and one
  record of stage 3 compiling itself at the counts `tests/lib/
  determinism.sh:14` names (1, 3, 5, 13 and a second process), read from
  there. Reason: the counts are one fact, in one place.
- D6. Each stage copies `compiler/src` afresh into `build/self/src` before
  it runs, and stages 2 and 3 compare the TTCs that copy's build holds.
  Reason: `self.sh:31-32` copies once, so stages 2 and 3 load the TTCs
  stage 1 wrote and the native elaborator never runs on the frontend
  (*read*; the fork's up-to-date check reusing them is *recalled* from
  upstream). One path, since locations carry it. Each stage runs stage
  N-1's `idris-mlir-front` alone, then its `idris-mlir` on the `.mlirbc`:
  the driver removes the module when a later step fails (§3.3), and the
  two peaks are D4's. The artifacts compared keep their names.
- D7 (was 0005's D11, restated). The test machinery also builds and runs
  under idris-mlir, and the stock host keeps running it: its process
  creation moves into sh glue and its imports to base. After `make self`;
  the owner is 0001's X3 and N lanes' successors.
- D8. `make self` holds when stage 2 = stage 3 on both targets, recorded
  in HANDOFF.md. This proposal is deleted then.

## 7. Open, for the owner

Nothing. The guard's scope (§3.2(a)) was decided by the owner on
2026-10-15, and S1 runs on the typecheck machine under the owner's
standing permission to build anything but the LLVM project.
