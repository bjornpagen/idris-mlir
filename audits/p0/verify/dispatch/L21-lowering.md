# Lane L21 (lowering): the lowering to LLVM, and the target

**Exclusive write:** `foreign/idr/lib/Conversion/Lower/` (new, for new code), `foreign/idr/lib/Conversion/{Counting,Cells,Entry,Facts,Fields,FuncToFunc,Lower,Mangle,MemoCells,PassThroughMemory,ReturnRegisters,Runtime,RuntimeCalls,RuntimeCells,StaticBytes,StaticData,StaticNames}.cpp`,
`foreign/idr/include/idr/Conversion/{Facts,Fields,FuncToFunc,IdrPattern,Mangle,Passes,PassThroughMemory,Patterns,ReturnRegisters,Runtime,StaticData}.h`,
`foreign/idr/lib/Target/{Extract,Optimize,Partition,Schedules,Target}.cpp`,
`foreign/idr/include/idr/Target/Target.h`.

**Read deeply:** P0 §5.5 (the runtime entries) and §5.1 (what reaches
LLVM); in §2 D19, D61, D80, D88 to D90, D93, D100, D102; in §3 C72, C73,
C149. The verification reports `L11-runtime.md` (lowering parts),
`L02-effects-rows.md` (LLVM attributes), `L07-counting.md` (lowered
count operations), `L13-ops-canon.md` (conversion);
`design/lifetimes/lowering.md` §4.9; `design/egraph-full/machine-prototype.md`
(the dropped `noalias`). The audits: 12; 18; wave1 §5.11. Code:
`lib/Conversion/`, `lib/Target/`, `include/idr/Target/`.

**Also yours** (rulings and decisions no brief named before): C42, C62; and C8: every suspected bug of P0 §8 whose code lies in your paths.

**Also yours (absorbed work placed by L16 §2.9):** line tables: the locations the frontend keeps reach the emitted debug info (0003's "no line tables", `L16-frontend.md` §2.9).

**Contract:** blocks only at the lowering (D19); a lifetime's kind lowers
by one context-free, cached `TypeConverter` rule per kind, `view` and
`home` to no value (D93); the grade lowers to its word or pointer; what
the compiler knows of effects reaches LLVM (`willreturn`,
`mustprogress`, argument memory from D61, `noalias` on quantity-1
buffers through C149's patch); no test of a fact a type states (no NULL
or odd-bit test on a typed word, no uniqueness branch, D10); a crash
names its cause as data (D80); the target decided only by the module's
triple and data layout from the target's entry.

**End state:** as the reports' lowering units draft it, amended by D93,
D100, D102, C149.

**Recipe:** write the conversion; remove every per-target case outside
the target's entry.

**Delete:** the uniqueness branches in C++, the `Fields` side table, the
per-site crash strings, the NULL and odd-bit tests on typed words,
`LowerDrop`'s token branch, the host's `sizeof` of a runtime header.

**QTT:** a quantity-1 buffer's `noalias` and an exclusive parameter's
argument-memory write reach LLVM.

**NOT TO DO:** the runtime (L11); arrays' conversion (L12); scalar
conversion (L13); tail calls' lowering (L10).

**Acceptance:** INT finds every program linking and running on the four
targets with the attributes present in the emitted IR.

**Stop and return:** when the lowering is written and your handoff is
sent.

## Common obligations (every lane)

**What this swarm is.** The P0 cutover itself: the implementation of
`proposals/0000-mlir-native.md`, written whole by twenty-one owned lanes
at once and an integration lane, in place, on `main`.
It is one change (D56: "we will only build when this entire cutover is
fully done"): no lane builds, typechecks or runs its part; the
integration lane (INT) builds, runs and qualifies the whole on the four
targets and routes every failure back to the lane that owns it. It is a
hard cutover (D6, AGENTS.md): the new form replaces the old in the same
change, with no shim, alias, re-export, dual path, fallback, flag or
"remove later", and the dead code, tests and comments it leaves are
deleted.

**Read first, in full, before any edit:**
1. `.claude/skills/representation-first/SKILL.md` (the lens every change
   is judged by), and `.claude/skills/testing-by-search/SKILL.md` before
   touching a test.
2. `AGENTS.md` (the rules; the owner's dated rulings are quoted there).
3. `proposals/0000-mlir-native.md`, the whole document: §2 holds the
   owner's rulings D1 to D109, which bind you; §3 the coordinator's
   decisions C1 to C157, which bind you unless you show the coordinator a
   contradiction; §5 the target by area, the canonical contract every
   lane writes against; §6 what goes; §7 the order.
4. Your verification report, `audits/p0/verify/LNN-*.md` (named in your
   lane): its §2 (boundaries, provenance, seams) and §5 (work units) are
   the drafted recipe for your area, written before the rulings after
   it; where a later ruling or decision differs, the later one governs.
5. The design documents your lane names, then the code you own and the
   code that consumes it.
6. Every contract under `audits/p0/verify/parts/contracts/`: shared
   declarations the lanes fixed while working (the specification's Core
   vocabulary and the pass list among them), binding as P0 §5 is.

**The engagement contract.**
- Checkout `/Users/bjorn/Documents/idris-mlir`, branch `main` (the owner, 2026-10-21: "we should do everything on main").
  Record `git rev-parse --short HEAD` when you start and when you finish.
- Write only inside your **exclusive write** paths (`ownership.json`); a
  new file goes only inside a directory you own. Every other path is
  another writer's: the other lanes, INT, and the coordinator
  (`proposals/`, `AGENTS.md`, `audits/`, `.claude/`). Never edit
  `third_party/` or `sources/`.
- No build, no typecheck, no test run, no generator run, no `make` target
  of any kind, and never `make bootstrap`, `tools/bootstrap.sh`,
  `make build`, `make test*`, `make self` or `make compile` (D56; this
  machine does not build LLVM). Reading, `grep`, `find`, `wc`, `git log`,
  `git show` and `git diff` are fine. No git write: the coordinator
  commits.
- Four first-class targets (AGENTS.md): nothing per-target outside the
  target's entry.

**Shared contracts.** P0 §5 fixes every shared declaration by name and
shape: the specification's ops, types and attributes, the grade
(`!idr.graded<uses, hold, T>`, D88 to D90), the lifetime
(`!idr.lifetime<view | room | cursor | home k>` and its openers, D93),
families (`!idr.data<#Family[...]>`, D48), the effect tree and its one
query API (D9, D27 to D29), the solver layer's shared types (C114), the
tail fact on `idr.call` (D30, C139), the runtime's one ending table
(D37, D64, D81) and the pipeline as one generated list (C28). Write
against those names and shapes as P0 states them, whoever owns the file
that declares them; never declare your own copy, and never wait for the
owner's file to land. Where you need a declaration P0 does not fix,
report the exact seam to the coordinator and continue with everything
else.

**Hub files.** Every `CMakeLists.txt` outside a directory you own, the root `Makefile` and
`CMakeLists.txt`, and the generated outputs (`include/idr/IR/Generated/`,
`generated.manifest`) are INT's. Do not edit them: list in your handoff
each file you added, moved or deleted, per directory, and INT wires
them.

**How the code is written.**
- C++: concept-constrained templates, monomorphized; dispatch over ops
  only through MLIR (an interface, a trait, a rooted pattern), never an
  `isa<A, B>` ladder or a concept that lists ops; a choice is a type or
  an enum case, never a `bool`; invariants asserted freely, always on
  (D114, D115, C226), C++26 contracts once clang has them; no
  pointer-keyed map holding per-node state; nothing static built per
  function.
- Idris, D112: no run-time check of our own invariant (`internal`,
  `assert_total`, `assert_smaller`, `believe_me`): the state is made
  unrepresentable or its proof carried; code is never kept worse to
  spare the compiler (D113).
- Idris: in the subset both hosts compile, type-driven (indices, views,
  erased proofs, evidence over `Bool`, C154: evidence at quantity 0 in
  bodies the stock host runs). On the stock host, avoid until fixed:
  constructors named `Nil`, `::` or `#` matched inside pattern lambdas,
  nested linear `LPair`s (`audits/p0/design/idris-linear-check.md`), and
  an effectful `let` whose value the body ignores
  (`audits/p0/design/idris-identity-bug.md`).
- Comments explain why the code is the way it is; they cite no document
  or rule number. Names are churned until correct (D90's vocabulary).

**Verification you may do.** Read-only checks only: every symbol you
delete has no remaining reference inside your paths (`grep`), and each
reference outside them is listed in your handoff as a seam for its
owner. INT runs the checks AGENTS.md names (`make check`, `make build`,
`make test`, `make test-idr`, `make test-unit`, `make test-mlir-tools`)
on the whole.

**Handoff.** When your obligations are done, reply in under 400 words:
the paths you changed, per obligation; per obligation, the state made
unrepresentable, the check moved to a boundary or the branch deleted,
or why the case is essential (AGENTS.md); the files added, moved or
deleted per directory, for INT; every unresolved seam, with its owner;
HEAD at start and at finish.

**The owner's word over the coordinator's.** The owner, 2026-10-21: "my
human word always takes precedence over automated decisions." The
rulings bind you; a coordinator decision that the evidence shows wrong
is reported to the coordinator, never changed by you. Escalate
conflicting evidence with the contract change you propose, and keep
working on every obligation it does not block.

## The six binding rules (verbatim)

1. Do exactly the assigned obligations and the necessary consumer adaptations within the exclusive write set. Every changed hunk, new file, dependency or abstraction must map to a named obligation. If the contract cannot be completed within those writes, report the exact missing seam; do not silently widen scope.
2. Add no unsolicited features, frameworks, generic helpers, configuration knobs, retries, telemetry, documentation, dependencies, formatting sweeps or neighboring cleanup. Elegance means completing the selected representation and deleting its named predecessor, not opening another project.
3. Do not be afraid to duplicate reading, investigation, reasoning or small, packet-local, non-authoritative glue. Do not wait for a sibling just to avoid that duplication, and do not introduce a shared helper that creates a false dependency. Reuse repairs that have already landed; duplicated investigation does not mean rebuilding working mechanisms.
4. Authoritative schemas, vocabularies, identities and business facts still have exactly one owner. Never duplicate them, create competing implementations or write concurrently to another owner's file. Duplicate effort is allowed; duplicate authority and overlapping writes are not.
5. Finish the bounded deliverable, report changed paths against obligations, the checks actually run and any unresolved seams, then return control. Do not roam into another packet, manufacture work to keep up the headcount, or build a reporting or coordination platform.
6. User steering goes through the coordinator, into the affected packet only. The coordinator corrects an architectural contradiction in the canonical contract and re-dispatches the affected lane. No lane stops for it.
